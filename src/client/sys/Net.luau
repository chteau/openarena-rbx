-- The client's connection state (cl_cgame.c / cl_parse.c semantics): the
-- gamestate's configstrings, a ring of received snapshots, the reliable
-- server-command ring, and the cgame clock (CL_SetCGameTime). The wire
-- format belongs to feat/game (docs/formats/net.md); whatever carries it
-- calls Net.ReceiveGamestate / ReceiveSnapshot / ReceiveServerCommand and
-- sets Net.transport for the outgoing side.
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local Cmd = require(script.Parent.Cmd)

local Net = {}

local PACKET_BACKUP = C.PACKET_BACKUP or 32
local PACKET_MASK = PACKET_BACKUP - 1
local MAX_RELIABLE_COMMANDS = C.MAX_RELIABLE_COMMANDS or 64

-- connstate_t values
Net.state = C.CA_DISCONNECTED or 0
Net.clientNum = 0
Net.serverName = "roblox"
Net.messageString = ""

local configstrings: { [number]: string } = {}
local snapshots: { [number]: any } = {}
local latest: any = nil
local serverCommands: { [number]: string } = {}
local serverCommandSequence = 0
local bigConfigString = ""

Net.newSnapshots = false
Net.serverTime = 0
Net.oldServerTime = 0
Net.serverTimeDelta = 0
Net.extrapolatedSnapshot = false

-- Outgoing side, set by the transport: { command = (seq, text) -> (), usercmds = (cmds) -> () }
Net.transport = nil :: any
local reliableSequence = 0

-- Called when a configstring changes (the client restarts cgame on a new map, ...).
Net.onConfigstring = nil :: ((index: number, value: string) -> ())?

-- incoming -------------------------------------------------------------------

-- A full gamestate: a 0-based configstrings array, the server command
-- sequence it was sent at, and the client's slot.
function Net.ReceiveGamestate(cs: { [number]: string }, commandSequence: number, clientNum: number)
	table.clear(configstrings)
	for i, s in cs do
		configstrings[i] = s
	end
	serverCommandSequence = commandSequence
	Net.clientNum = clientNum
	table.clear(snapshots)
	latest = nil
	Net.state = C.CA_PRIMED
end

function Net.ReceiveServerCommand(sequence: number, text: string)
	if sequence <= serverCommandSequence then
		return
	end
	serverCommandSequence = sequence
	serverCommands[bit32.band(sequence, MAX_RELIABLE_COMMANDS - 1)] = text
end

-- `snap` is a snapshot_t-shaped table; `messageNum` numbers it.
function Net.ReceiveSnapshot(messageNum: number, snap)
	snap.messageNum = messageNum
	snap.valid = true
	snap.serverCommandNum = serverCommandSequence
	snapshots[bit32.band(messageNum, PACKET_MASK)] = snap
	if latest == nil or messageNum > latest.messageNum then
		latest = snap
		Net.newSnapshots = true
	end
end

-- syscalls -------------------------------------------------------------------

function Net.ConfigString(index: number): string
	return configstrings[index] or ""
end

function Net.GetGameState(gs)
	gs.configstrings = {}
	for i, s in configstrings do
		gs.configstrings[i] = s
	end
	gs.dataCount = 0
end

function Net.GetClientState(cs)
	cs.connState = Net.state
	cs.connectPacketCount = 0
	cs.clientNum = Net.clientNum
	cs.servername = Net.serverName
	cs.updateInfoString = ""
	cs.messageString = Net.messageString
end

function Net.GetCurrentSnapshotNumber(): (number, number)
	if latest == nil then
		return 0, 0
	end
	return latest.messageNum, latest.serverTime
end

function Net.GetSnapshot(n: number, out): boolean
	if latest == nil or n > latest.messageNum then
		error("CL_GetSnapshot: snapshotNumber > cl.snapshot.messageNum")
	end
	if latest.messageNum - n >= PACKET_BACKUP then
		return false
	end
	local s = snapshots[bit32.band(n, PACKET_MASK)]
	if s == nil or not s.valid or s.messageNum ~= n then
		return false
	end
	out.snapFlags = s.snapFlags or 0
	out.serverCommandSequence = s.serverCommandNum
	out.ping = s.ping or 0
	out.serverTime = s.serverTime
	out.areamask = s.areamask or out.areamask
	T.assign(out.ps, s.ps)
	out.numEntities = s.numEntities
	for i = 0, s.numEntities - 1 do
		T.assign(out.entities[i], s.entities[i])
	end
	return true
end

local function configstringModified()
	local index = tonumber(Cmd.Argv(1)) or 0
	local s = Cmd.ArgsFrom(2)
	if configstrings[index] == s then
		return
	end
	configstrings[index] = s
	if Net.onConfigstring then
		Net.onConfigstring(index, s)
	end
end

-- CL_GetServerCommand: tokenizes command n into Cmd's argv; false when the
-- engine consumed it (big configstring pieces).
function Net.GetServerCommand(n: number): boolean
	if n <= serverCommandSequence - MAX_RELIABLE_COMMANDS then
		error("CL_GetServerCommand: a reliable command was cycled out")
	end
	if n > serverCommandSequence then
		error("CL_GetServerCommand: requested a command not received")
	end
	local s = serverCommands[bit32.band(n, MAX_RELIABLE_COMMANDS - 1)] or ""
	while true do
		Cmd.TokenizeString(s)
		local cmd = Cmd.Argv(0)
		if cmd == "disconnect" then
			Net.state = C.CA_DISCONNECTED
			error("Server disconnected")
		elseif cmd == "bcs0" then
			bigConfigString = ('cs %s "%s'):format(Cmd.Argv(1), Cmd.Argv(2))
			return false
		elseif cmd == "bcs1" then
			bigConfigString ..= Cmd.Argv(2)
			return false
		elseif cmd == "bcs2" then
			s = bigConfigString .. Cmd.Argv(2) .. '"'
			-- rescan the reassembled "cs" command
		elseif cmd == "cs" then
			configstringModified()
			Cmd.TokenizeString(s)
			return true
		else
			return true
		end
	end
end

-- CL_SetCGameTime / CL_AdjustTimeDelta. `realtime` is the client's ms clock.
function Net.SetCGameTime(realtime: number, timeNudge: number?)
	if Net.state ~= C.CA_ACTIVE then
		if Net.state ~= C.CA_PRIMED or not Net.newSnapshots or latest == nil then
			return
		end
		Net.newSnapshots = false
		if bit32.band(latest.snapFlags or 0, C.SNAPFLAG_NOT_ACTIVE) ~= 0 then
			return
		end
		Net.state = C.CA_ACTIVE
		Net.serverTimeDelta = latest.serverTime - realtime
		Net.oldServerTime = latest.serverTime
	end
	if latest == nil then
		return
	end
	local tn = math.clamp(timeNudge or 0, -30, 30)
	Net.serverTime = realtime + Net.serverTimeDelta - tn
	if Net.serverTime < Net.oldServerTime then
		Net.serverTime = Net.oldServerTime
	end
	Net.oldServerTime = Net.serverTime
	if realtime + Net.serverTimeDelta >= latest.serverTime - 5 then
		Net.extrapolatedSnapshot = true
	end
	if Net.newSnapshots then
		Net.newSnapshots = false
		local newDelta = latest.serverTime - realtime
		local dd = math.abs(newDelta - Net.serverTimeDelta)
		if dd > 500 then
			Net.serverTimeDelta = newDelta
			Net.oldServerTime = latest.serverTime
			Net.serverTime = latest.serverTime
		elseif dd > 100 then
			Net.serverTimeDelta = bit32.arshift(Net.serverTimeDelta + newDelta, 1)
		elseif Net.extrapolatedSnapshot then
			Net.extrapolatedSnapshot = false
			Net.serverTimeDelta -= 2
		else
			Net.serverTimeDelta += 1
		end
	end
end

-- outgoing -------------------------------------------------------------------

function Net.SendClientCommand(text: string)
	reliableSequence += 1
	if Net.transport then
		Net.transport.command(reliableSequence, text)
	end
end

function Net.SendUserCmds(cmds)
	if Net.transport then
		Net.transport.usercmds(cmds)
	end
end

return Net
