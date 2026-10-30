--!strict
-- The client's side of the Roblox transport (ioq3's cl_parse.c and
-- CL_WritePacket, over the two remotes in ReplicatedStorage.OANet that
-- src/server/sv/transport_roblox.luau creates). It parses server messages
-- (gamestate, reliable commands, delta snapshots) into Net and writes the
-- client's packets (acknowledges, reliable commands, keyed usercmd deltas).
-- docs/formats/net.md is the wire format; tests/server/fakeclient.luau is
-- the reference decoder this follows.
--
-- This file is GPL-2.0 like the rest of the port; it has no C original.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(script.Parent.Net)
local shared = script.Parent.Parent.Parent.shared
local MSG = require(shared.net.msg) :: any
local S = require(shared.structs) :: any
local K = require(shared.consts) :: any

local band = bit32.band

local PACKET_BACKUP = 32
local PACKET_MASK = PACKET_BACKUP - 1
local MAX_RELIABLE_COMMANDS = 64
local MAX_PARSE_ENTITIES = 2048
local UNRELIABLE_MAX = 800
-- usercmds resent with each packet (cl_packetdup): a lost packet loses no
-- input, and the server skips the ones it already ran
local CMD_BACKUP = 3

local Transport = {}
-- called with no arguments when a new gamestate arrives (a map change):
-- the boot code restarts cgame
Transport.onGamestate = nil :: (() -> ())?

local st: any

local function reset()
	-- the packet numbers we send keep counting across a reconnect: the
	-- connect message names the first one, so the server can tell the old
	-- connection's late packets from the new one's
	local outgoing = if st then st.outgoingSequence else 1
	st = {
		serverId = 0,
		checksumFeed = 0,
		serverMessageSequence = 0,
		serverCommandSequence = 0,
		serverCommands = {},
		reliableSequence = 0,
		reliableAcknowledge = 0,
		reliableCommands = {},
		outgoingSequence = outgoing,
		baselines = {},
		snapshots = {},
		parseEntities = {},
		parseEntitiesNum = 0,
		snap = nil,
		cmds = {},
	}
end
reset()

local function serverIdOf(info: string?): number?
	return tonumber(string.match(info or "", "\\sv_serverid\\(%-?%d+)"))
end

local function parseCommandString(msg)
	local seq = MSG.ReadLong(msg)
	local s = MSG.ReadString(msg)
	if st.serverCommandSequence >= seq then
		return
	end
	st.serverCommandSequence = seq
	st.serverCommands[band(seq, MAX_RELIABLE_COMMANDS - 1)] = s
	-- CL_SystemInfoChanged: the serverId stamps every usercmd packet
	local idx, rest = string.match(s, '^cs (%d+) "(.*)"')
	if idx and tonumber(idx) == K.CS_SYSTEMINFO then
		st.serverId = serverIdOf(rest) or st.serverId
	end
	Net.ReceiveServerCommand(seq, s)
end

local function parseGamestate(msg)
	local cs: { [number]: string } = {}
	st.baselines = {}
	st.serverCommandSequence = MSG.ReadLong(msg)
	while true do
		local cmd = MSG.ReadByte(msg)
		if cmd == MSG.svc_EOF then
			break
		end
		if cmd == MSG.svc_configstring then
			local i = MSG.ReadShort(msg)
			cs[i] = MSG.ReadBigString(msg)
		elseif cmd == MSG.svc_baseline then
			local newnum = MSG.ReadBits(msg, K.GENTITYNUM_BITS)
			local es = S.entityState_t()
			MSG.ReadDeltaEntity(msg, MSG.nullEntityState, es, newnum)
			st.baselines[newnum] = es
		else
			error("CL_ParseGamestate: bad command byte " .. cmd)
		end
	end
	local clientNum = MSG.ReadLong(msg)
	st.checksumFeed = MSG.ReadLong(msg)
	st.serverId = serverIdOf(cs[K.CS_SYSTEMINFO]) or 0
	st.snapshots = {}
	st.snap = nil
	Net.ReceiveGamestate(cs, st.serverCommandSequence, clientNum)
	if Transport.onGamestate then
		Transport.onGamestate()
	end
end

local function deltaEntity(msg, frame, newnum, old, unchanged)
	local idx = band(st.parseEntitiesNum, MAX_PARSE_ENTITIES - 1)
	local state = st.parseEntities[idx]
	if not state then
		state = S.entityState_t()
		st.parseEntities[idx] = state
	end
	if unchanged then
		S.copy_entityState_t(state, old)
	else
		MSG.ReadDeltaEntity(msg, old, state, newnum)
	end
	if state.number == K.MAX_GENTITIES - 1 then
		return -- removed
	end
	st.parseEntitiesNum += 1
	frame.numEntities += 1
end

local function parsePacketEntities(msg, oldframe, newframe)
	newframe.parseEntitiesNum = st.parseEntitiesNum
	newframe.numEntities = 0
	local oldindex, oldstate, oldnum = 0, nil, 99999
	local function setOld()
		if oldframe == nil or oldindex >= oldframe.numEntities then
			oldnum = 99999
		else
			oldstate = st.parseEntities[band(oldframe.parseEntitiesNum + oldindex, MAX_PARSE_ENTITIES - 1)]
			oldnum = oldstate.number
		end
	end
	setOld()
	while true do
		local newnum = MSG.ReadBits(msg, K.GENTITYNUM_BITS)
		if newnum == K.MAX_GENTITIES - 1 then
			break
		end
		if MSG.Overrun(msg) then
			error("CL_ParsePacketEntities: end of message")
		end
		while oldnum < newnum do
			deltaEntity(msg, newframe, oldnum, oldstate, true)
			oldindex += 1
			setOld()
		end
		if oldnum == newnum then
			deltaEntity(msg, newframe, newnum, oldstate, false)
			oldindex += 1
			setOld()
		elseif oldnum > newnum then
			deltaEntity(msg, newframe, newnum, st.baselines[newnum] or MSG.nullEntityState, false)
		end
	end
	while oldnum ~= 99999 do
		deltaEntity(msg, newframe, oldnum, oldstate, true)
		oldindex += 1
		setOld()
	end
end

local function parseSnapshot(msg)
	local snap: any = {
		serverCommandNum = st.serverCommandSequence,
		serverTime = MSG.ReadLong(msg),
		messageNum = st.serverMessageSequence,
		deltaNum = 0,
		snapFlags = 0,
		valid = false,
		ps = S.playerState_t(),
		areamask = buffer.create(K.MAX_MAP_AREA_BYTES),
		numEntities = 0,
		parseEntitiesNum = 0,
	}
	local deltaNum = MSG.ReadByte(msg)
	snap.deltaNum = if deltaNum == 0 then -1 else snap.messageNum - deltaNum
	snap.snapFlags = MSG.ReadByte(msg)
	local old = nil
	if snap.deltaNum <= 0 then
		snap.valid = true
	else
		old = st.snapshots[band(snap.deltaNum, PACKET_MASK)]
		if old == nil or not old.valid or old.messageNum ~= snap.deltaNum
			or st.parseEntitiesNum - old.parseEntitiesNum > MAX_PARSE_ENTITIES - 128 then
			old = nil
		else
			snap.valid = true
		end
	end
	local len = MSG.ReadByte(msg)
	MSG.ReadData(msg, snap.areamask, len)
	MSG.ReadDeltaPlayerstate(msg, if old then old.ps else nil, snap.ps)
	parsePacketEntities(msg, old, snap)
	if not snap.valid then
		return
	end
	st.snapshots[band(snap.messageNum, PACKET_MASK)] = snap
	st.snap = snap

	-- the cgame's copy: the area mask and entities as 0-based arrays
	local areamask = {}
	for i = 0, K.MAX_MAP_AREA_BYTES - 1 do
		areamask[i] = buffer.readu8(snap.areamask, i)
	end
	local out: any = {
		serverTime = snap.serverTime,
		snapFlags = snap.snapFlags,
		ps = snap.ps,
		areamask = areamask,
		numEntities = snap.numEntities,
		entities = {},
	}
	for i = 0, snap.numEntities - 1 do
		local es = S.entityState_t()
		S.copy_entityState_t(es, st.parseEntities[band(snap.parseEntitiesNum + i, MAX_PARSE_ENTITIES - 1)])
		out.entities[i] = es
	end
	Net.ReceiveSnapshot(snap.messageNum, out)
end

-- CL_PacketEvent + CL_ParseServerMessage
function Transport.Receive(data: buffer)
	local msg = MSG.FromBuffer(data)
	local sequence = MSG.ReadLong(msg)
	if sequence <= st.serverMessageSequence then
		return
	end
	st.serverMessageSequence = sequence
	st.reliableAcknowledge = MSG.ReadLong(msg)
	if st.reliableAcknowledge < st.reliableSequence - MAX_RELIABLE_COMMANDS then
		st.reliableAcknowledge = st.reliableSequence
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
			parseCommandString(msg)
		elseif cmd == MSG.svc_gamestate then
			parseGamestate(msg)
		elseif cmd == MSG.svc_snapshot then
			parseSnapshot(msg)
		else
			error("CL_ParseServerMessage: Illegible server message " .. cmd)
		end
	end
end

-- CL_WritePacket
local function writePacket(cmds: { any }): buffer
	local msg = MSG.Init()
	MSG.WriteLong(msg, st.outgoingSequence)
	st.outgoingSequence += 1
	MSG.WriteLong(msg, st.serverId)
	MSG.WriteLong(msg, st.serverMessageSequence)
	MSG.WriteLong(msg, st.serverCommandSequence)
	for i = st.reliableAcknowledge + 1, st.reliableSequence do
		MSG.WriteByte(msg, MSG.clc_clientCommand)
		MSG.WriteLong(msg, i)
		MSG.WriteString(msg, st.reliableCommands[band(i, MAX_RELIABLE_COMMANDS - 1)] or "")
	end
	if #cmds > 0 then
		if st.snap == nil or not st.snap.valid or st.serverMessageSequence ~= st.snap.messageNum then
			MSG.WriteByte(msg, MSG.clc_moveNoDelta)
		else
			MSG.WriteByte(msg, MSG.clc_move)
		end
		MSG.WriteByte(msg, #cmds)
		local key = bit32.bxor(st.checksumFeed, st.serverMessageSequence)
		key = bit32.bxor(key, MSG.HashKey(st.serverCommands[band(st.serverCommandSequence, MAX_RELIABLE_COMMANDS - 1)] or "", 32))
		local oldcmd = S.usercmd_t()
		for _, cmd in cmds do
			MSG.WriteDeltaUsercmdKey(msg, key, oldcmd, cmd)
			oldcmd = cmd
		end
	end
	MSG.WriteByte(msg, MSG.clc_EOF)
	return MSG.ToBuffer(msg)
end

function Transport.Start()
	local folder = ReplicatedStorage:WaitForChild("OANet")
	local reliable = folder:WaitForChild("Reliable") :: RemoteEvent
	local unreliable = folder:WaitForChild("Unreliable") :: UnreliableRemoteEvent
	local connected = false

	local function send(data: buffer)
		if buffer.len(data) <= UNRELIABLE_MAX then
			unreliable:FireServer(data)
		else
			reliable:FireServer("p", data)
		end
	end

	-- packets between a reconnect request and its answer belong to the old
	-- connection
	unreliable.OnClientEvent:Connect(function(data)
		if connected and typeof(data) == "buffer" then
			Transport.Receive(data)
		end
	end)
	reliable.OnClientEvent:Connect(function(kind, data, firstSequence)
		if kind == "p" and typeof(data) == "buffer" then
			if connected then
				Transport.Receive(data)
			end
		elseif kind == "connected" then
			connected = true
			-- the server's packets on this connection start here; anything
			-- older still in flight is the previous connection's
			if typeof(firstSequence) == "number" then
				st.serverMessageSequence = firstSequence - 1
			end
			-- a fresh connection: the server's first gamestate follows
			send(writePacket({}))
		elseif kind == "refused" then
			warn("OpenArena: connection refused: " .. tostring(data))
			Net.messageString = tostring(data)
		end
	end)

	Net.transport = {
		connect = function(userinfo: string)
			reset()
			connected = false
			reliable:FireServer("connect", userinfo, st.outgoingSequence)
		end,
		disconnect = function()
			connected = false
		end,
		command = function(seq: number, text: string)
			st.reliableSequence = seq
			st.reliableCommands[band(seq, MAX_RELIABLE_COMMANDS - 1)] = text
			if connected then
				send(writePacket({}))
			end
		end,
		usercmds = function(cmds: { any })
			if not connected then
				return
			end
			for _, c in cmds do
				table.insert(st.cmds, c)
			end
			while #st.cmds > CMD_BACKUP do
				table.remove(st.cmds, 1)
			end
			send(writePacket(st.cmds))
		end,
	}
end

return Transport
