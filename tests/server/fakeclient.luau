-- A minimal client network layer for the server tests: it parses server
-- messages the way ioq3's cl_parse.c does (gamestate, server commands,
-- delta-compressed snapshots against the frame the server names) and
-- writes client packets like CL_WritePacket (acknowledges, reliable
-- commands, keyed usercmd deltas). It doubles as the reference decoder for
-- docs/formats/net.md.
local MSG = require("../../src/shared/net/msg")
local S = require("../../src/shared/structs")
local K = require("../../src/shared/consts")

local band = bit32.band

local PACKET_BACKUP = 32
local PACKET_MASK = PACKET_BACKUP - 1
local MAX_RELIABLE_COMMANDS = 64
local MAX_PARSE_ENTITIES = 2048

local FC = {}
FC.__index = FC

function FC.new(name: string)
	local self = setmetatable({}, FC)
	self.name = name
	self.clientNum = -1
	self.serverId = 0
	self.checksumFeed = 0
	self.serverMessageSequence = 0
	self.serverCommandSequence = 0
	self.serverCommands = {} -- [seq & mask] = text
	self.executed = 0 -- last server command handed to the "cgame"
	self.commands = {} -- every server command executed, in order
	self.reliableSequence = 0
	self.reliableAcknowledge = 0
	self.reliableCommands = {}
	self.outgoingSequence = 1
	self.configstrings = {}
	self.baselines = {}
	self.snapshots = {} -- [messageNum & mask]
	self.parseEntities = {} -- ring of entityState_t
	self.parseEntitiesNum = 0
	self.snap = nil -- latest valid snapshot
	self.cmds = {} -- usercmds to send (latest last)
	self.serverTime = 0
	self.gamestates = 0
	self.disconnected = nil
	return self
end

function FC:addReliableCommand(text: string)
	self.reliableSequence += 1
	self.reliableCommands[band(self.reliableSequence, MAX_RELIABLE_COMMANDS - 1)] = text
end

--
-- parsing (cl_parse.c)
--

function FC:parseCommandString(msg)
	local seq = MSG.ReadLong(msg)
	local s = MSG.ReadString(msg)
	-- see if we have already executed stored it off
	if self.serverCommandSequence >= seq then
		return
	end
	self.serverCommandSequence = seq
	self.serverCommands[band(seq, MAX_RELIABLE_COMMANDS - 1)] = s
end

function FC:parseGamestate(msg)
	self.gamestates += 1
	self.configstrings = {}
	self.baselines = {}
	-- a gamestate always marks a server command sequence
	self.serverCommandSequence = MSG.ReadLong(msg)
	while true do
		local cmd = MSG.ReadByte(msg)
		if cmd == MSG.svc_EOF then
			break
		end
		if cmd == MSG.svc_configstring then
			local i = MSG.ReadShort(msg)
			self.configstrings[i] = MSG.ReadBigString(msg)
		elseif cmd == MSG.svc_baseline then
			local newnum = MSG.ReadBits(msg, K.GENTITYNUM_BITS)
			local es = S.entityState_t()
			MSG.ReadDeltaEntity(msg, MSG.nullEntityState, es, newnum)
			self.baselines[newnum] = es
		else
			error("CL_ParseGamestate: bad command byte " .. cmd)
		end
	end
	self.clientNum = MSG.ReadLong(msg)
	self.checksumFeed = MSG.ReadLong(msg)
	self.serverId = tonumber(string.match(self.configstrings[K.CS_SYSTEMINFO] or "", "\\sv_serverid\\(%-?%d+)")) or 0
	self.snapshots = {}
	self.snap = nil
end

local function baselineOf(self, n)
	return self.baselines[n] or MSG.nullEntityState
end

function FC:deltaEntity(msg, frame, newnum, old, unchanged)
	local idx = band(self.parseEntitiesNum, MAX_PARSE_ENTITIES - 1)
	local state = self.parseEntities[idx]
	if not state then
		state = S.entityState_t()
		self.parseEntities[idx] = state
	end
	if unchanged then
		S.copy_entityState_t(state, old)
	else
		MSG.ReadDeltaEntity(msg, old, state, newnum)
	end
	if state.number == K.MAX_GENTITIES - 1 then
		return -- entity was delta removed
	end
	self.parseEntitiesNum += 1
	frame.numEntities += 1
end

function FC:parsePacketEntities(msg, oldframe, newframe)
	newframe.parseEntitiesNum = self.parseEntitiesNum
	newframe.numEntities = 0

	local oldindex = 0
	local oldstate = nil
	local oldnum
	if not oldframe then
		oldnum = 99999
	else
		if oldindex >= oldframe.numEntities then
			oldnum = 99999
		else
			oldstate = self.parseEntities[band(oldframe.parseEntitiesNum + oldindex, MAX_PARSE_ENTITIES - 1)]
			oldnum = oldstate.number
		end
	end

	local function nextOld()
		oldindex += 1
		if oldindex >= oldframe.numEntities then
			oldnum = 99999
		else
			oldstate = self.parseEntities[band(oldframe.parseEntitiesNum + oldindex, MAX_PARSE_ENTITIES - 1)]
			oldnum = oldstate.number
		end
	end

	while true do
		-- read the entity index number
		local newnum = MSG.ReadBits(msg, K.GENTITYNUM_BITS)
		if newnum == K.MAX_GENTITIES - 1 then
			break
		end
		if MSG.Overrun(msg) then
			error("CL_ParsePacketEntities: end of message")
		end
		while oldnum < newnum do
			-- one or more entities from the old packet are unchanged
			self:deltaEntity(msg, newframe, oldnum, oldstate, true)
			nextOld()
		end
		if oldnum == newnum then
			-- delta from previous state
			self:deltaEntity(msg, newframe, newnum, oldstate, false)
			nextOld()
		elseif oldnum > newnum then
			-- delta from baseline
			self:deltaEntity(msg, newframe, newnum, baselineOf(self, newnum), false)
		end
	end

	-- any remaining entities in the old frame are copied over
	while oldnum ~= 99999 do
		self:deltaEntity(msg, newframe, oldnum, oldstate, true)
		nextOld()
	end
end

function FC:parseSnapshot(msg)
	local newSnap = {
		serverCommandNum = self.serverCommandSequence,
		serverTime = MSG.ReadLong(msg),
		messageNum = self.serverMessageSequence,
		deltaNum = 0,
		snapFlags = 0,
		valid = false,
		ps = S.playerState_t(),
		areamask = buffer.create(K.MAX_MAP_AREA_BYTES),
		numEntities = 0,
		parseEntitiesNum = 0,
	}
	local deltaNum = MSG.ReadByte(msg)
	if deltaNum == 0 then
		newSnap.deltaNum = -1
	else
		newSnap.deltaNum = newSnap.messageNum - deltaNum
	end
	newSnap.snapFlags = MSG.ReadByte(msg)

	-- If the frame is delta compressed from data that we no longer have
	-- available, we must suck up the rest of the frame, but not use it,
	-- then ask for a non-compressed message
	local old = nil
	if newSnap.deltaNum <= 0 then
		newSnap.valid = true -- uncompressed frame
	else
		old = self.snapshots[band(newSnap.deltaNum, PACKET_MASK)]
		if not old or not old.valid then
			-- should never happen
			old = nil
		elseif old.messageNum ~= newSnap.deltaNum then
			-- The frame that the server did the delta from is too old, so
			-- we can't reconstruct it properly.
			old = nil
		elseif self.parseEntitiesNum - old.parseEntitiesNum > MAX_PARSE_ENTITIES - 128 then
			old = nil
		else
			newSnap.valid = true -- valid delta parse
		end
	end

	-- read areamask
	local len = MSG.ReadByte(msg)
	MSG.ReadData(msg, newSnap.areamask, len)

	-- read playerinfo
	if old then
		MSG.ReadDeltaPlayerstate(msg, old.ps, newSnap.ps)
	else
		MSG.ReadDeltaPlayerstate(msg, nil, newSnap.ps)
	end

	-- read packet entities
	self:parsePacketEntities(msg, old, newSnap)

	-- if not valid, dump the entire thing now that it has been properly read
	if not newSnap.valid then
		return
	end

	self.snapshots[band(newSnap.messageNum, PACKET_MASK)] = newSnap
	self.snap = newSnap
	self.serverTime = newSnap.serverTime
end

-- the entities of a snapshot, as a number -> entityState_t map
function FC:snapEntities(snap)
	local t = {}
	snap = snap or self.snap
	if not snap then
		return t
	end
	for i = 0, snap.numEntities - 1 do
		local es = self.parseEntities[band(snap.parseEntitiesNum + i, MAX_PARSE_ENTITIES - 1)]
		t[es.number] = es
	end
	return t
end

-- one server message (CL_PacketEvent + CL_ParseServerMessage)
function FC:receive(data: buffer)
	local msg = MSG.FromBuffer(data)
	local sequence = MSG.ReadLong(msg)
	if sequence <= self.serverMessageSequence then
		return -- out of order
	end
	self.serverMessageSequence = sequence

	-- get the reliable sequence acknowledge number
	self.reliableAcknowledge = MSG.ReadLong(msg)
	if self.reliableAcknowledge < self.reliableSequence - MAX_RELIABLE_COMMANDS then
		self.reliableAcknowledge = self.reliableSequence
	end

	while true do
		if MSG.Overrun(msg) then
			error("CL_ParseServerMessage: read past end of server message")
		end
		local cmd = MSG.ReadByte(msg)
		if cmd == MSG.svc_EOF or cmd == -1 then
			break
		end
		if cmd == MSG.svc_nop then
			-- nothing
		elseif cmd == MSG.svc_serverCommand then
			self:parseCommandString(msg)
		elseif cmd == MSG.svc_gamestate then
			self:parseGamestate(msg)
		elseif cmd == MSG.svc_snapshot then
			self:parseSnapshot(msg)
		else
			error("CL_ParseServerMessage: Illegible server message " .. cmd)
		end
	end

	-- hand new server commands to the "cgame" (CG_ExecuteNewServerCommands)
	while self.executed < self.serverCommandSequence do
		self.executed += 1
		local text = self.serverCommands[band(self.executed, MAX_RELIABLE_COMMANDS - 1)]
		table.insert(self.commands, text)
		local cs, rest = string.match(text, '^cs (%d+) "(.*)"')
		if cs then
			self.configstrings[tonumber(cs)] = rest
			if tonumber(cs) == K.CS_SYSTEMINFO then
				-- CL_SystemInfoChanged
				self.serverId = tonumber(string.match(rest, "\\sv_serverid\\(%-?%d+)")) or self.serverId
			end
		end
		if string.match(text, "^disconnect") then
			self.disconnected = text
		end
		if string.match(text, "^map_restart") then
			self.snap = nil
		end
	end
end

--
-- writing (CL_WritePacket)
--

function FC:writePacket(cmds: { any }): buffer
	local msg = MSG.Init()
	MSG.WriteLong(msg, self.outgoingSequence)
	self.outgoingSequence += 1

	MSG.WriteLong(msg, self.serverId)
	-- write the last message we received, which can be used for delta
	-- compression, and is also used to tell if we dropped a gamestate
	MSG.WriteLong(msg, self.serverMessageSequence)
	-- write the last reliable message we received
	MSG.WriteLong(msg, self.serverCommandSequence)

	-- write any unacknowledged clientCommands
	for i = self.reliableAcknowledge + 1, self.reliableSequence do
		MSG.WriteByte(msg, MSG.clc_clientCommand)
		MSG.WriteLong(msg, i)
		MSG.WriteString(msg, self.reliableCommands[band(i, MAX_RELIABLE_COMMANDS - 1)])
	end

	if #cmds > 0 then
		-- begin a client move command; delta only from a valid snapshot
		if not self.snap or not self.snap.valid or self.serverMessageSequence ~= self.snap.messageNum then
			MSG.WriteByte(msg, MSG.clc_moveNoDelta)
		else
			MSG.WriteByte(msg, MSG.clc_move)
		end
		MSG.WriteByte(msg, #cmds)

		-- use the checksum feed in the key
		local key = self.checksumFeed
		-- also use the message acknowledge
		key = bit32.bxor(key, self.serverMessageSequence)
		-- also use the last acknowledged server command in the key
		key = bit32.bxor(
			key,
			MSG.HashKey(self.serverCommands[band(self.serverCommandSequence, MAX_RELIABLE_COMMANDS - 1)] or "", 32)
		)

		local oldcmd = S.usercmd_t()
		for _, cmd in cmds do
			MSG.WriteDeltaUsercmdKey(msg, key, oldcmd, cmd)
			oldcmd = cmd
		end
	end
	MSG.WriteByte(msg, MSG.clc_EOF)
	return MSG.ToBuffer(msg)
end

return FC
