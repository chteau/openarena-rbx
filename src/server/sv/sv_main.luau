--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (ioquake3 code/server/sv_main.c, sv_init.c, sv_client.c, sv_snapshot.c, sv_ccmds.c).

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
===========================================================================
]]
--!native
-- The server engine (ioquake3 code/server/sv_main.c, sv_init.c,
-- sv_client.c, sv_snapshot.c and sv_ccmds.c): map spawning and
-- map_restart, the fixed-step frame loop at sv_fps, client connection
-- states, reliable server commands, usercmd intake and the per-client
-- delta-compressed snapshots built from the PVS.
--
-- What is not here (no UDP, no master servers, no pk3s): challenges,
-- netchan fragments, downloads, pure checks, rcon, heartbeats, VoIP.
-- A transport (sv/transport_*.luau) moves the message buffers; it calls
--   SV.SV_DirectConnect(userinfo, handle) -> clientNum or nil, reason
--   SV.SV_PacketEvent(clientNum, buffer)
--   SV.SV_Disconnect(clientNum)        (the player left)
-- and SV.send(clientNum, buffer) delivers server messages. The format is
-- in docs/formats/net.md.

local SV = require("./server")
local W = require("./sv_world")
local Cvar = require("./cvar")
local Cmd = require("./cmd")
local Fs = require("./fs")
local G = require("../g_local")
require("./sv_game")
local FriendBots = require("./friendbots")
local MSG = require("../../shared/net/msg")
local Collision = require("../../shared/Collision")
local QS = require("../../shared/q_shared")
local S = require("../../shared/structs")
local Q = require("../../shared/q_math")
local C = require("../g_defs")

local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot

local sv, svs = SV.sv, SV.svs
local PACKET_MASK = SV.PACKET_MASK
local MAX_RELIABLE_COMMANDS = SV.MAX_RELIABLE_COMMANDS

-- transport hook: (clientNum, buffer) -> ()
SV.send = function(clientNum: number, data: buffer) end
-- map loader hook: (mapname) -> lumps for Collision.LoadMap (maps/<name>.bsp)
SV.loadMap = nil :: ((string) -> any)?
-- the bots (bot/Bots.luau), set by Game.luau
SV.Bots = nil :: any

local cv: { [string]: any } = {}

local function s32(v: number): number
	v = band(v, 0xFFFFFFFF)
	return if v >= 0x80000000 then v - 0x100000000 else v
end

local function maxclients(): number
	return cv.sv_maxclients.integer
end

local function Com_Printf(fmt: string, ...)
	SV.Com_Printf(QS.va(fmt, ...))
end

--
-- configstrings and userinfo (sv_init.c)
--

local function SV_SendConfigstring(client, index: number)
	local maxChunkSize = C.MAX_STRING_CHARS - 24
	local s = sv.configstrings[index]
	local len = #s
	if len >= maxChunkSize then
		local sent = 0
		local remaining = len
		while remaining > 0 do
			local cmd
			if sent == 0 then
				cmd = "bcs0"
			elseif remaining < maxChunkSize then
				cmd = "bcs2"
			else
				cmd = "bcs1"
			end
			local buf = string.sub(s, sent + 1, sent + maxChunkSize - 1)
			SV.SV_SendServerCommand(client, QS.va('%s %i "%s"\n', cmd, index, buf))
			sent += (maxChunkSize - 1)
			remaining -= (maxChunkSize - 1)
		end
	else
		SV.SV_SendServerCommand(client, QS.va('cs %i "%s"\n', index, s))
	end
end

-- resend the configstrings that changed while the client was CS_PRIMED
function SV.SV_UpdateConfigstrings(client)
	for index = 0, C.MAX_CONFIGSTRINGS - 1 do
		if not client.csUpdated[index] then
			continue
		end
		-- do not always send server info to all clients
		if
			index == C.CS_SERVERINFO
			and client.gentity
			and band(client.gentity.r.svFlags, C.SVF_NOSERVERINFO) ~= 0
		then
			continue
		end
		SV_SendConfigstring(client, index)
		client.csUpdated[index] = false
	end
end

function SV.SV_SetConfigstring(index: number, val: string?)
	if index < 0 or index >= C.MAX_CONFIGSTRINGS then
		error(SV.GameError(string.format("SV_SetConfigstring: bad index %i", index)), 0)
	end
	if not val then
		val = ""
	end
	-- don't bother broadcasting an update if no change
	if val == sv.configstrings[index] then
		return
	end
	sv.configstrings[index] = val

	-- send it to all the clients if we aren't spawning a new server
	if sv.state == SV.SS_GAME or sv.restarting then
		-- send the data to all relevant clients
		for i = 0, maxclients() - 1 do
			local client = svs.clients[i]
			if client.state < SV.CS_ACTIVE then
				if client.state == SV.CS_PRIMED then
					client.csUpdated[index] = true
				end
				continue
			end
			-- do not always send server info to all clients
			if
				index == C.CS_SERVERINFO
				and client.gentity
				and band(client.gentity.r.svFlags, C.SVF_NOSERVERINFO) ~= 0
			then
				continue
			end
			SV_SendConfigstring(client, index)
		end
	end
end

function SV.SV_GetConfigstring(index: number): string
	if index < 0 or index >= C.MAX_CONFIGSTRINGS then
		error(SV.GameError(string.format("SV_GetConfigstring: bad index %i", index)), 0)
	end
	return sv.configstrings[index] or ""
end

function SV.SV_SetUserinfo(index: number, val: string?)
	if index < 0 or index >= maxclients() then
		error(SV.GameError(string.format("SV_SetUserinfo: bad index %i", index)), 0)
	end
	val = val or ""
	local cl = svs.clients[index]
	cl.userinfo = string.sub(val :: string, 1, C.MAX_INFO_STRING - 1)
	cl.name = string.sub(QS.Info_ValueForKey(val :: string, "name"), 1, C.MAX_NAME_LENGTH - 1)
end

function SV.SV_GetUserinfo(index: number): string
	if index < 0 or index >= maxclients() then
		error(SV.GameError(string.format("SV_GetUserinfo: bad index %i", index)), 0)
	end
	return svs.clients[index].userinfo
end

--
-- reliable server commands (sv_main.c)
--

-- The given command will be transmitted to the client, and is guaranteed
-- to not have future snapshot_t executed before it is executed
function SV.SV_AddServerCommand(client, cmd: string)
	-- do not send commands until the gamestate has been sent
	if client.state < SV.CS_PRIMED then
		return
	end
	client.reliableSequence += 1
	-- if we would be losing an old command that hasn't been acknowledged,
	-- we must drop the connection; we check == instead of >= so a broadcast
	-- print added by SV_DropClient() doesn't cause a recursive drop client
	if client.reliableSequence - client.reliableAcknowledge == MAX_RELIABLE_COMMANDS + 1 then
		if client.gamestateMessageNum == -1 then
			return
		end
		Com_Printf("===== pending server commands =====\n")
		for i = client.reliableAcknowledge + 1, client.reliableSequence do
			Com_Printf("cmd %5d: %s\n", i, client.reliableCommands[band(i, MAX_RELIABLE_COMMANDS - 1)])
		end
		SV.SV_DropClient(client, "Server command overflow")
		return
	end
	local index = band(client.reliableSequence, MAX_RELIABLE_COMMANDS - 1)
	client.reliableCommands[index] = string.sub(cmd, 1, C.MAX_STRING_CHARS - 1)
end

-- Sends a reliable command string to be interpreted by the client game
-- module: "cp", "print", "chat", etc. A nil client will broadcast to all
-- clients
function SV.SV_SendServerCommand(cl, message: string)
	-- Fix to http://aluigi.altervista.org/adv/q3msgboom-adv.txt
	if #message > 1022 then
		return
	end
	if cl ~= nil then
		SV.SV_AddServerCommand(cl, message)
		return
	end
	-- hack to echo broadcast prints to console
	if string.sub(message, 1, 5) == "print" then
		Com_Printf("broadcast: %s\n", (string.gsub(message, "\n", "\\n")))
	end
	-- send the data to all relevant clients
	for j = 0, maxclients() - 1 do
		SV.SV_AddServerCommand(svs.clients[j], message)
	end
end

--
-- clients (sv_client.c)
--

local function SV_SendMessageToClient(msg, client)
	-- record information about the message
	local frame = client.frames[band(client.outgoingSequence, PACKET_MASK)]
	frame.messageSize = msg.cursize
	frame.messageSent = svs.time
	frame.messageAcked = -1

	-- the transport header: the message sequence (netchan's outgoing
	-- sequence), then the message itself
	local out = MSG.Init(msg.cursize + 4)
	MSG.WriteLong(out, client.outgoingSequence)
	for i = 0, msg.cursize - 1 do
		MSG.WriteByte(out, buffer.readu8(msg.data, i))
	end
	client.outgoingSequence += 1
	if not client.isBot then
		SV.send(client.index, MSG.ToBuffer(out))
	end
end

-- (re)send all server commands the client hasn't acknowledged yet
local function SV_UpdateServerCommandsToClient(client, msg)
	-- write any unacknowledged serverCommands
	for i = client.reliableAcknowledge + 1, client.reliableSequence do
		MSG.WriteByte(msg, MSG.svc_serverCommand)
		MSG.WriteLong(msg, i)
		MSG.WriteString(msg, client.reliableCommands[band(i, MAX_RELIABLE_COMMANDS - 1)])
	end
	client.reliableSent = client.reliableSequence
end

-- Sends the first message from the server to a connected client. This
-- will be sent on the initial connection and upon each new map load. It
-- will be resent if the client acknowledges a later message but has the
-- wrong gamestate.
function SV.SV_SendClientGameState(client)
	client.state = SV.CS_PRIMED
	-- the gamestate carries every configstring
	table.clear(client.csUpdated)

	-- when we receive the first packet from the client, we will notice
	-- that it is from a different serverid and that the gamestate message
	-- was not just sent, forcing a retransmit
	client.gamestateMessageNum = client.outgoingSequence

	-- the gamestate goes over the reliable remote, which has no 16 KB
	-- datagram limit; a Huffman-less gamestate of a big map can pass it
	local msg = MSG.Init(MSG.MAX_MSGLEN * 4)

	-- NOTE, MRE: all server->client messages now acknowledge
	-- let the client know which reliable clientCommands we have received
	MSG.WriteLong(msg, client.lastClientCommand)

	-- send any server commands waiting to be sent first. we have to do
	-- this cause we send the client->reliableSequence with a gamestate
	-- and it sets the clc.serverCommandSequence at the client side
	SV_UpdateServerCommandsToClient(client, msg)

	-- send the gamestate
	MSG.WriteByte(msg, MSG.svc_gamestate)
	MSG.WriteLong(msg, client.reliableSequence)

	-- write the configstrings
	for start = 0, C.MAX_CONFIGSTRINGS - 1 do
		local s = sv.configstrings[start]
		if s ~= "" then
			MSG.WriteByte(msg, MSG.svc_configstring)
			MSG.WriteShort(msg, start)
			MSG.WriteBigString(msg, s)
		end
	end

	-- write the baselines
	for start = 0, C.MAX_GENTITIES - 1 do
		local base = sv.svEntities[start].baseline
		if base.number == 0 then
			continue
		end
		MSG.WriteByte(msg, MSG.svc_baseline)
		MSG.WriteDeltaEntity(msg, MSG.nullEntityState, base, true)
	end

	MSG.WriteByte(msg, MSG.svc_EOF)

	MSG.WriteLong(msg, client.index)

	-- write the checksum feed
	MSG.WriteLong(msg, sv.checksumFeed)

	if msg.overflowed then
		Com_Printf("WARNING: gamestate overflowed for %s\n", client.name)
	end

	-- deliver this to the client
	SV_SendMessageToClient(msg, client)
end

function SV.SV_ClientEnterWorld(client, cmd)
	client.state = SV.CS_ACTIVE

	-- resend all configstrings using the cs commands since these are no
	-- longer sent when the client is CS_PRIMED
	SV.SV_UpdateConfigstrings(client)

	-- set up the entity for the client
	local clientNum = client.index
	local ent = W.SV_GentityNum(clientNum)
	ent.s.number = clientNum
	client.gentity = ent

	client.deltaMessage = -1
	client.lastSnapshotTime = 0 -- generate a snapshot immediately

	if cmd then
		S.copy_usercmd_t(client.lastUsercmd, cmd)
	else
		S.copy_usercmd_t(client.lastUsercmd, S.usercmd_t())
	end

	-- call the game begin function
	G.vmMain(C.GAME_CLIENT_BEGIN, clientNum)
end

-- Called when the player is totally leaving the server, either willingly
-- or unwillingly. This is NOT called if the entire server is quiting or
-- crashing -- SV_FinalMessage() will handle that
function SV.SV_DropClient(drop, reason: string)
	if drop.state == SV.CS_ZOMBIE then
		return -- already dropped
	end
	local isBot = drop.isBot

	-- Reset the reliable sequence to the currently acknowledged command
	-- so SV_AddServerCommand() can't recurse into SV_DropClient(), and the
	-- client receives both the print and disconnect commands
	drop.reliableSequence = drop.reliableAcknowledge

	-- Setting the gamestate message number to -1 ensures that
	-- SV_AddServerCommand() will not call SV_DropClient() again
	drop.gamestateMessageNum = -1

	-- tell everyone why they got dropped
	SV.SV_SendServerCommand(nil, QS.va('print "%s^7 %s\n"', drop.name, reason))

	-- call the prog function for removing a client; this will remove the
	-- body, among other things
	G.vmMain(C.GAME_CLIENT_DISCONNECT, drop.index)

	-- add the disconnect command
	SV.SV_SendServerCommand(drop, QS.va('disconnect "%s"', reason))

	if isBot then
		G.trap_BotFreeClient(drop.index)
		FriendBots.Release(drop.index)
		-- bots shouldn't go zombie, as there's no real net connection.
		drop.state = SV.CS_FREE
	else
		drop.state = SV.CS_ZOMBIE -- become free in a few seconds
		-- zombies keep getting (empty) snapshots that carry the disconnect
		-- command until SV_CheckTimeouts frees them
		if SV.onDrop then
			SV.onDrop(drop.index, reason)
		end
	end

	-- nuke user info
	SV.SV_SetUserinfo(drop.index, "")
end

-- Pull specific info from a newly changed userinfo string into a more C
-- friendly form.
function SV.SV_UserinfoChanged(cl)
	-- name for C code
	cl.name = string.sub(QS.Info_ValueForKey(cl.userinfo, "name"), 1, C.MAX_NAME_LENGTH - 1)

	-- rate command (no LAN detection over Roblox)
	local val = QS.Info_ValueForKey(cl.userinfo, "rate")
	if #val > 0 then
		local i = QS.atoi(val)
		cl.rate = i
		if cl.rate < 1000 then
			cl.rate = 1000
		elseif cl.rate > 90000 then
			cl.rate = 90000
		end
	else
		cl.rate = 3000
	end
	val = QS.Info_ValueForKey(cl.userinfo, "handicap")
	if #val > 0 then
		local i = QS.atoi(val)
		if i <= 0 or i > 100 or #val > 4 then
			cl.userinfo = QS.Info_SetValueForKey(cl.userinfo, "handicap", "100")
		end
	end

	-- snaps command
	val = QS.Info_ValueForKey(cl.userinfo, "snaps")
	local i
	if #val > 0 then
		i = QS.atoi(val)
		if i < 1 then
			i = 1
		elseif i > cv.sv_fps.integer then
			i = cv.sv_fps.integer
		end
		i = Q.idiv(1000, i)
	else
		i = 50
	end
	if i ~= cl.snapshotMsec then
		-- Reset last sent snapshot so we avoid desync between server frame
		-- time and snapshot send time
		cl.lastSnapshotTime = 0
		cl.snapshotMsec = i
	end

	-- the GUID is the server's, not the client's: the transport derives it
	-- from the platform account (SV.GuidFor) and every userinfo carries it
	if cl.guid then
		cl.userinfo = QS.Info_SetValueForKey(cl.userinfo, "cl_guid", cl.guid)
	end

	-- maintain the IP information; the banning code relies on this being
	-- consistently present. The transport gives each player a stable
	-- pseudo address (see docs/formats/net.md).
	local ip = cl.address or "localhost"
	val = QS.Info_ValueForKey(cl.userinfo, "ip")
	local len
	if #val > 0 then
		len = #ip - #val + #cl.userinfo
	else
		len = #ip + 4 + #cl.userinfo
	end
	if len >= C.MAX_INFO_STRING then
		SV.SV_DropClient(cl, "userinfo string length exceeded")
	else
		cl.userinfo = QS.Info_SetValueForKey(cl.userinfo, "ip", ip)
	end
end

local function SV_UpdateUserinfo_f(cl)
	cl.userinfo = string.sub(Cmd.Cmd_Argv(1), 1, C.MAX_INFO_STRING - 1)
	SV.SV_UserinfoChanged(cl)
	-- call prog code to allow overrides
	G.vmMain(C.GAME_CLIENT_USERINFO_CHANGED, cl.index)
end

local function SV_Disconnect_f(cl)
	SV.SV_DropClient(cl, "disconnected")
end

local ucmds: { [string]: (any) -> () } = {
	userinfo = SV_UpdateUserinfo_f,
	disconnect = SV_Disconnect_f,
	-- "cp", "vdr" and the download commands have nothing to do here
	cp = function(cl) end,
	vdr = function(cl) end,
	download = function(cl) end,
	nextdl = function(cl) end,
	stopdl = function(cl) end,
	donedl = function(cl) end,
}

-- Cmd_Args_Sanitize: newlines and carriage returns become spaces, ';' too
local function Cmd_Args_Sanitize()
	-- the game reads argv through trap_Argv, which our tokenizer already
	-- split; ioq3 rewrites \n \r ; inside each argument
	for i = 1, Cmd.Cmd_Argc() - 1 do
		local a = Cmd.Cmd_Argv(i)
		if string.find(a, "[\n\r;]") then
			Cmd.SetArgv(i, (string.gsub(a, "[\n\r;]", " ")))
		end
	end
end

-- Also called by bot code
function SV.SV_ExecuteClientCommand(cl, s: string, clientOK: boolean)
	local bProcessed = false
	Cmd.Cmd_TokenizeString(s)

	-- see if it is a server level command
	local u = ucmds[Cmd.Cmd_Argv(0)]
	if u then
		u(cl)
		bProcessed = true
	end

	if clientOK then
		-- pass unknown strings to the game
		if
			not u
			and sv.state == SV.SS_GAME
			and (cl.state == SV.CS_ACTIVE or cl.state == SV.CS_PRIMED)
		then
			Cmd_Args_Sanitize()
			G.vmMain(C.GAME_CLIENT_COMMAND, cl.index)
		end
	elseif not bProcessed then
		-- client text ignored (flood protection)
	end
end

local function SV_ClientCommand(cl, msg): boolean
	local clientOk = true
	local seq = MSG.ReadLong(msg)
	local s = MSG.ReadString(msg)

	-- see if we have already executed it
	if cl.lastClientCommand >= seq then
		return true
	end

	-- drop the connection if we have somehow lost commands
	if seq > cl.lastClientCommand + 1 then
		Com_Printf("Client %s lost %i clientCommands\n", cl.name, seq - cl.lastClientCommand + 1)
		SV.SV_DropClient(cl, "Lost reliable commands")
		return false
	end

	-- malicious users may try using too many string commands to lag
	-- other players. If we decide that we want to stall the command, we
	-- will stop processing the rest of the packet, including the usercmd.
	-- This causes flooders to lag themselves but not other people. We
	-- don't do this when the client hasn't been active yet since it's
	-- normal to spam a lot of commands when downloading
	if cl.state >= SV.CS_ACTIVE and cv.sv_floodProtect.integer ~= 0 and svs.time < cl.nextReliableTime then
		-- ignore any other text messages from this client but let them keep playing
		clientOk = false
	end

	-- don't allow another command for one second
	cl.nextReliableTime = svs.time + 1000

	SV.SV_ExecuteClientCommand(cl, s, clientOk)

	cl.lastClientCommand = seq
	cl.lastClientCommandString = s

	return true -- continue procesing
end

-- Also called by bot code
function SV.SV_ClientThink(cl, cmd)
	S.copy_usercmd_t(cl.lastUsercmd, cmd)
	if cl.state ~= SV.CS_ACTIVE then
		return -- may have been kicked during the last usercmd
	end
	G.vmMain(C.GAME_CLIENT_THINK, cl.index)
end

local userCmds = {}
for i = 0, MSG.MAX_PACKET_USERCMDS - 1 do
	userCmds[i] = S.usercmd_t()
end
local nullcmd = S.usercmd_t()

-- The message usually contains all the movement commands that were in
-- the last three packets, so that the information in dropped packets can
-- be recovered. On very fast clients, there may be multiple usercmd
-- packed into each of the backup packets.
local function SV_UserMove(cl, msg, delta: boolean)
	if delta then
		cl.deltaMessage = cl.messageAcknowledge
	else
		cl.deltaMessage = -1
	end

	local cmdCount = MSG.ReadByte(msg)
	if cmdCount < 1 then
		Com_Printf("cmdCount < 1\n")
		return
	end
	if cmdCount > MSG.MAX_PACKET_USERCMDS then
		Com_Printf("cmdCount > MAX_PACKET_USERCMDS\n")
		return
	end

	-- use the checksum feed in the key
	local key = sv.checksumFeed
	-- also use the message acknowledge
	key = bxor(key, cl.messageAcknowledge)
	-- also use the last acknowledged server command in the key
	key = bxor(
		key,
		MSG.HashKey(cl.reliableCommands[band(cl.reliableAcknowledge, MAX_RELIABLE_COMMANDS - 1)] or "", 32)
	)

	local oldcmd = nullcmd
	for i = 0, cmdCount - 1 do
		local cmd = userCmds[i]
		MSG.ReadDeltaUsercmdKey(msg, key, oldcmd, cmd)
		oldcmd = cmd
	end

	-- save time for ping calculation
	cl.frames[band(cl.messageAcknowledge, PACKET_MASK)].messageAcked = svs.time

	-- if this is the first usercmd we have received this gamestate, put
	-- the client into the world
	if cl.state == SV.CS_PRIMED then
		SV.SV_ClientEnterWorld(cl, userCmds[0])
		-- the moves can be processed normaly
	end

	if cl.state ~= SV.CS_ACTIVE then
		cl.deltaMessage = -1
		return
	end

	-- usually, the first couple commands will be duplicates of ones we
	-- have previously received, but the servertimes in the commands will
	-- cause them to be immediately discarded
	for i = 0, cmdCount - 1 do
		-- if this is a cmd from before a map_restart ignore it
		if userCmds[i].serverTime > userCmds[cmdCount - 1].serverTime then
			continue
		end
		-- don't execute if this is an old cmd which is already executed;
		-- these old cmds are included when cl_packetdup > 0
		if userCmds[i].serverTime <= cl.lastUsercmd.serverTime then
			continue
		end
		SV.SV_ClientThink(cl, userCmds[i])
	end
end

-- Parses a client message: serverId, acknowledges, client commands and
-- the moves (layout in docs/formats/net.md)
function SV.SV_ExecuteClientMessage(cl, msg)
	local serverId = MSG.ReadLong(msg)
	cl.messageAcknowledge = MSG.ReadLong(msg)

	if cl.messageAcknowledge < 0 then
		-- usually only hackers create messages like this; it is more
		-- annoying for them to let them hanging
		return
	end

	cl.reliableAcknowledge = MSG.ReadLong(msg)

	-- NOTE: when the client message is fux0red the acknowledgement numbers
	-- can be out of range, this could cause the server to send thousands
	-- of server commands which the server thinks are not yet acknowledged
	-- in SV_UpdateServerCommandsToClient
	if
		cl.reliableSequence - cl.reliableAcknowledge >= MAX_RELIABLE_COMMANDS
		or cl.reliableSequence - cl.reliableAcknowledge < 0
	then
		cl.reliableAcknowledge = cl.reliableSequence
		return
	end

	-- if this is a usercmd from a previous gamestate, ignore it or
	-- retransmit the current gamestate
	if serverId ~= sv.serverId then
		if serverId >= sv.restartedServerId and serverId < sv.serverId then
			-- they just haven't caught the map_restart yet
			return
		end
		-- if we can tell that the client has dropped the last gamestate we
		-- sent them, resend it
		if cl.state ~= SV.CS_ACTIVE and cl.messageAcknowledge > cl.gamestateMessageNum then
			SV.SV_SendClientGameState(cl)
		end
		return
	end

	-- this client has acknowledged the new gamestate so it's safe to start
	-- sending it the real time again
	if cl.oldServerTime ~= 0 and serverId == sv.serverId then
		cl.oldServerTime = 0
	end

	-- read optional clientCommand strings
	local c
	repeat
		c = MSG.ReadByte(msg)
		if c == MSG.clc_EOF then
			break
		end
		if c ~= MSG.clc_clientCommand then
			break
		end
		if not SV_ClientCommand(cl, msg) then
			return -- we couldn't execute it because of the flood protection
		end
		if cl.state == SV.CS_ZOMBIE then
			return -- disconnect command
		end
	until false

	-- read the usercmd_t
	if c == MSG.clc_move then
		SV_UserMove(cl, msg, true)
	elseif c == MSG.clc_moveNoDelta then
		SV_UserMove(cl, msg, false)
	elseif c ~= MSG.clc_EOF then
		Com_Printf("WARNING: bad command byte for client %i\n", cl.index)
	end
end

-- A message from a connected client arrived (the transport calls this
-- for both the unreliable and the reliable channel). The leading long is
-- the client's packet sequence (netchan): late or duplicated packets are
-- dropped like Netchan_Process does.
function SV.SV_PacketEvent(clientNum: number, data: buffer)
	local cl = svs.clients[clientNum]
	if not cl or cl.state == SV.CS_FREE or cl.isBot then
		return
	end
	local msg = MSG.FromBuffer(data)
	local sequence = MSG.ReadLong(msg)
	if MSG.Overrun(msg) then
		return
	end
	if sequence <= cl.incomingSequence then
		return -- out of order or duplicated
	end
	cl.incomingSequence = sequence
	cl.lastPacketTime = svs.time -- don't timeout
	-- zombie clients still need to do the Netchan_Process to make sure
	-- they don't need to retransmit the final reliable message, but they
	-- don't do any other processing
	if cl.state ~= SV.CS_ZOMBIE then
		local ok, err = pcall(SV.SV_ExecuteClientMessage, cl, msg)
		if not ok then
			if type(err) == "table" and err.isGameError then
				error(err, 0)
			end
			Com_Printf("bad message from client %i: %s\n", clientNum, tostring(err))
		end
	end
end

-- cl_guid for an account id: 32 hex digits, as g_client.c and g_admin.c
-- expect (the C client derives its own from a key file)
function SV.GuidFor(accountId: number | string): string
	local s = tostring(accountId)
	local h1, h2 = 0x811C9DC5, 0x01000193
	for i = 1, #s do
		local c = string.byte(s, i)
		h1 = bit32.bxor(h1, c)
		h1 = bit32.band(h1 * 0x01000193, 0xFFFFFFFF)
		h2 = bit32.band(bit32.bxor(h2 * 31, c * 0x9E3779B1), 0xFFFFFFFF)
	end
	local n = tonumber(s)
	return string.format("%08X%08X%016X", h1, h2, if n then n else 0)
end

-- A new client connects (SV_DirectConnect without the challenge and
-- netchan parts). `handle` is the transport's player object; `address`
-- the stable pseudo address that stands in for the IP; `guid` the
-- account's cl_guid (SV.GuidFor). Returns the client number, or nil and
-- the reason it was refused.
function SV.SV_DirectConnect(userinfo: string, handle: any, address: string?, guid: string?): (number?, string?)
	if sv.state ~= SV.SS_GAME then
		return nil, "Server is not running."
	end

	-- quick reject: a reconnect from the same address reuses its slot
	local newcl = nil
	for i = 0, maxclients() - 1 do
		local cl = svs.clients[i]
		if cl.state ~= SV.CS_FREE and not cl.isBot and address and cl.address == address then
			if cl.state >= SV.CS_CONNECTED then
				SV.SV_DropClient(cl, "reconnect")
			end
			cl.state = SV.CS_FREE
			newcl = cl
			break
		end
	end

	userinfo = QS.Info_SetValueForKey(userinfo, "ip", address or "localhost")
	if guid then
		userinfo = QS.Info_SetValueForKey(userinfo, "cl_guid", guid)
	end

	-- check for privateClient password
	local password = QS.Info_ValueForKey(userinfo, "password")
	local startIndex
	if password ~= "" and password == Cvar.VariableString("sv_privatePassword") then
		startIndex = 0
	else
		-- skip past the reserved slots
		startIndex = cv.sv_privateClients.integer
	end

	if not newcl then
		for i = startIndex, maxclients() - 1 do
			local cl = svs.clients[i]
			if cl.state == SV.CS_FREE then
				newcl = cl
				break
			end
		end
	end

	if not newcl then
		return nil, "Server is full."
	end

	-- build a new connection, accept the new client
	local clientNum = newcl.index
	local fresh = SV.newClient(clientNum)
	for k, v in fresh do
		newcl[k] = v
	end
	local ent = W.SV_GentityNum(clientNum)
	newcl.gentity = ent
	newcl.player = handle
	newcl.address = address or "localhost"
	newcl.guid = guid

	-- save the userinfo
	newcl.userinfo = string.sub(userinfo, 1, C.MAX_INFO_STRING - 1)

	-- get the game a chance to reject this connection or modify the userinfo
	local denied = G.vmMain(C.GAME_CLIENT_CONNECT, clientNum, true, false)
	if type(denied) == "string" then
		newcl.state = SV.CS_FREE
		return nil, denied
	end

	SV.SV_UserinfoChanged(newcl)

	newcl.state = SV.CS_CONNECTED
	newcl.lastSnapshotTime = 0
	newcl.lastPacketTime = svs.time
	newcl.lastConnectTime = svs.time

	-- when we receive the first packet from the client, we will notice
	-- that it is from a different serverid and that the gamestate message
	-- was not just sent, forcing a retransmit
	newcl.gamestateMessageNum = -1

	return clientNum, nil
end

-- the transport saw the player leave
function SV.SV_Disconnect(clientNum: number)
	local cl = svs.clients[clientNum]
	if not cl or cl.state == SV.CS_FREE or cl.isBot then
		return
	end
	SV.SV_DropClient(cl, "disconnected")
	cl.state = SV.CS_FREE
end

--
-- snapshots (sv_snapshot.c)
--

local function SV_EmitPacketEntities(from, to, msg)
	-- generate the delta update
	local from_num_entities = if from then from.num_entities else 0

	local newent, oldent = nil, nil
	local newindex, oldindex = 0, 0
	while newindex < to.num_entities or oldindex < from_num_entities do
		local newnum, oldnum
		if newindex >= to.num_entities then
			newnum = 9999
		else
			newent = to.entities[newindex]
			newnum = newent.number
		end

		if oldindex >= from_num_entities then
			oldnum = 9999
		else
			oldent = from.entities[oldindex]
			oldnum = oldent.number
		end

		if newnum == oldnum then
			-- delta update from old position; because the force parm is
			-- false, this will not result in any bytes being emitted if the
			-- entity has not changed at all
			MSG.WriteDeltaEntity(msg, oldent, newent, false)
			oldindex += 1
			newindex += 1
			continue
		end

		if newnum < oldnum then
			-- this is a new entity, send it from the baseline
			MSG.WriteDeltaEntity(msg, sv.svEntities[newnum].baseline, newent, true)
			newindex += 1
			continue
		end

		if newnum > oldnum then
			-- the old entity isn't present in the new message
			MSG.WriteDeltaEntity(msg, oldent, nil, true)
			oldindex += 1
			continue
		end
	end

	MSG.WriteBits(msg, C.MAX_GENTITIES - 1, C.GENTITYNUM_BITS) -- end of packetentities
end

local function SV_WriteSnapshotToClient(client, msg)
	-- this is the snapshot we are creating
	local frame = client.frames[band(client.outgoingSequence, PACKET_MASK)]
	local oldframe, lastframe

	-- try to use a previous frame as the source for delta compressing the snapshot
	if client.deltaMessage <= 0 or client.state ~= SV.CS_ACTIVE then
		-- client is asking for a retransmit
		oldframe = nil
		lastframe = 0
	elseif client.outgoingSequence - client.deltaMessage >= (SV.PACKET_BACKUP - 3) then
		-- client hasn't gotten a good message through in a long time
		oldframe = nil
		lastframe = 0
	else
		-- we have a valid snapshot to delta from (each frame keeps its own
		-- entity copies, so it cannot roll off a shared buffer)
		oldframe = client.frames[band(client.deltaMessage, PACKET_MASK)]
		lastframe = client.outgoingSequence - client.deltaMessage
	end

	MSG.WriteByte(msg, MSG.svc_snapshot)

	-- send over the current server time so the client can drift its view
	-- of time to try to match
	if client.oldServerTime ~= 0 then
		-- The server has not yet got an acknowledgement of the new
		-- gamestate from this client, so continue to send it a time as if
		-- the server has not restarted.
		MSG.WriteLong(msg, sv.time + client.oldServerTime)
	else
		MSG.WriteLong(msg, sv.time)
	end

	-- what we are delta'ing from
	MSG.WriteByte(msg, lastframe)

	local snapFlags = svs.snapFlagServerBit
	if client.rateDelayed then
		snapFlags = bor(snapFlags, C.SNAPFLAG_RATE_DELAYED)
	end
	if client.state ~= SV.CS_ACTIVE then
		snapFlags = bor(snapFlags, C.SNAPFLAG_NOT_ACTIVE)
	end

	MSG.WriteByte(msg, snapFlags)

	-- send over the areabits
	MSG.WriteByte(msg, frame.areabytes)
	MSG.WriteData(msg, frame.areabits, frame.areabytes)

	-- delta encode the playerstate
	if oldframe then
		MSG.WriteDeltaPlayerstate(msg, oldframe.ps, frame.ps)
	else
		MSG.WriteDeltaPlayerstate(msg, nil, frame.ps)
	end

	-- delta encode the entities
	SV_EmitPacketEntities(oldframe, frame, msg)
end

local MAX_SNAPSHOT_ENTITIES = SV.MAX_SNAPSHOT_ENTITIES

local function SV_AddEntToSnapshot(svEnt, gEnt, eNums)
	-- if we have already added this entity to this snapshot, don't add again
	if svEnt.snapshotCounter == sv.snapshotCounter then
		return
	end
	svEnt.snapshotCounter = sv.snapshotCounter

	-- if we are full, silently discard entities
	if eNums.n == MAX_SNAPSHOT_ENTITIES then
		return
	end

	eNums.list[eNums.n] = gEnt.s.number
	eNums.n += 1
end

local pvsBit = W.pvsBit

local function SV_AddEntitiesVisibleFromPoint(origin, frame, eNums, portal: boolean)
	-- during an error shutdown message we may need to transmit the
	-- shutdown message after the server has shutdown, so specfically
	-- check for it
	if sv.state == SV.SS_DEAD then
		return
	end

	local leafnum = Collision.PointLeafnum(origin)
	local clientarea = Collision.LeafArea(leafnum)
	local clientcluster = Collision.LeafCluster(leafnum)

	-- calculate the visible areas
	frame.areabytes = Collision.WriteAreaBits(frame.areabits, clientarea)

	local clientpvs, pvsOff = Collision.ClusterPVS(clientcluster)

	for e = 0, sv.num_entities - 1 do
		local ent = W.SV_GentityNum(e)

		-- never send entities that aren't linked in
		if not ent.r.linked then
			continue
		end

		if ent.s.number ~= e then
			ent.s.number = e
		end

		local svFlags = ent.r.svFlags

		-- entities can be flagged to explicitly not be sent to the client
		if band(svFlags, C.SVF_NOCLIENT) ~= 0 then
			continue
		end

		-- entities can be flagged to be sent to only one client
		if band(svFlags, C.SVF_SINGLECLIENT) ~= 0 then
			if ent.r.singleClient ~= frame.ps.clientNum then
				continue
			end
		end
		-- entities can be flagged to be sent to everyone but one client
		if band(svFlags, C.SVF_NOTSINGLECLIENT) ~= 0 then
			if ent.r.singleClient == frame.ps.clientNum then
				continue
			end
		end
		-- entities can be flagged to be sent to a given mask of clients
		if band(svFlags, C.SVF_CLIENTMASK) ~= 0 then
			if frame.ps.clientNum >= 32 then
				error(SV.GameError("SVF_CLIENTMASK: clientNum >= 32"), 0)
			end
			if band(bnot(ent.r.singleClient), bit32.lshift(1, frame.ps.clientNum)) ~= 0 then
				continue
			end
		end

		local svEnt = W.SV_SvEntityForGentity(ent)

		-- don't double add an entity through portals
		if svEnt.snapshotCounter == sv.snapshotCounter then
			continue
		end

		-- broadcast entities are always sent
		if band(svFlags, C.SVF_BROADCAST) ~= 0 then
			SV_AddEntToSnapshot(svEnt, ent, eNums)
			continue
		end

		-- ignore if not touching a PV leaf; check area
		if not Collision.AreasConnected(clientarea, svEnt.areanum) then
			-- doors can legally straddle two areas, so we may need to
			-- check another one
			if not Collision.AreasConnected(clientarea, svEnt.areanum2) then
				continue -- blocked by a door
			end
		end

		-- check individual leafs
		if svEnt.numClusters == 0 then
			continue
		end
		local l = 0
		local i = 0
		while i < svEnt.numClusters do
			l = svEnt.clusternums[i]
			if pvsBit(clientpvs, pvsOff, l) then
				break
			end
			i += 1
		end

		-- if we haven't found it to be visible, check overflow clusters
		-- that coudln't be stored
		if i == svEnt.numClusters then
			if svEnt.lastCluster ~= 0 then
				while l <= svEnt.lastCluster do
					if pvsBit(clientpvs, pvsOff, l) then
						break
					end
					l += 1
				end
				if l == svEnt.lastCluster then
					continue -- not visible
				end
			else
				continue
			end
		end

		-- add it
		SV_AddEntToSnapshot(svEnt, ent, eNums)

		-- if it's a portal entity, add everything visible from its camera position
		if band(svFlags, C.SVF_PORTAL) ~= 0 then
			if ent.s.generic1 ~= 0 then
				local o, org = ent.s.origin, origin
				local dx = Q.f(o[0] - org[0])
				local dy = Q.f(o[1] - org[1])
				local dz = Q.f(o[2] - org[2])
				local lsq = Q.f(Q.f(Q.f(dx * dx) + Q.f(dy * dy)) + Q.f(dz * dz))
				local g = Q.f(ent.s.generic1)
				if lsq > Q.f(g * g) then
					continue
				end
			end
			SV_AddEntitiesVisibleFromPoint(ent.s.origin2, frame, eNums, true)
		end
	end
end
local entityNumbers = { n = 0, list = {} }
local org = { [0] = 0, 0, 0 }

-- Decides which entities are going to be visible to the client, and
-- copies off the playerstate and areabits.
function SV.SV_BuildClientSnapshot(client)
	-- bump the counter used to prevent double adding
	sv.snapshotCounter += 1

	-- this is the frame we are creating
	local frame = client.frames[band(client.outgoingSequence, PACKET_MASK)]

	-- clear everything in this snapshot
	entityNumbers.n = 0
	buffer.fill(frame.areabits, 0, 0)

	frame.num_entities = 0

	local clent = client.gentity
	if not clent or client.state == SV.CS_ZOMBIE then
		return
	end

	-- grab the current playerState_t
	local ps = sv.gameClients[client.index].ps
	S.copy_playerState_t(frame.ps, ps)

	-- never send client's own entity, because it can be regenerated from
	-- the playerstate
	local clientNum = frame.ps.clientNum
	if clientNum < 0 or clientNum >= C.MAX_GENTITIES then
		error(SV.GameError("SV_SvEntityForGentity: bad gEnt"), 0)
	end
	local svEnt = sv.svEntities[clientNum]
	svEnt.snapshotCounter = sv.snapshotCounter

	-- find the client's viewpoint
	org[0], org[1], org[2] = ps.origin[0], ps.origin[1], ps.origin[2]
	org[2] = Q.f(org[2] + ps.viewheight)

	-- add all the entities directly visible to the eye, which may include
	-- portal entities that merge other viewpoints
	SV_AddEntitiesVisibleFromPoint(org, frame, entityNumbers, false)

	-- if there were portals visible, there may be out of order entities in
	-- the list which will need to be resorted for the delta compression to
	-- work correctly. This also catches the error condition of an entity
	-- being included twice.
	local sorted = table.create(entityNumbers.n)
	for i = 0, entityNumbers.n - 1 do
		sorted[i + 1] = entityNumbers.list[i]
	end
	table.sort(sorted)
	for i = 2, #sorted do
		if sorted[i] == sorted[i - 1] then
			error(SV.GameError("SV_QsortEntityStates: duplicated entity"), 0)
		end
	end

	-- now that all viewpoint's areabits have been OR'd together, invert
	-- all of them to make it a mask vector, which is what the renderer wants
	for i = 0, C.MAX_MAP_AREA_BYTES - 1 do
		buffer.writeu8(frame.areabits, i, bxor(buffer.readu8(frame.areabits, i), 255))
	end

	-- copy the entity states out
	frame.num_entities = 0
	for i = 1, #sorted do
		local ent = W.SV_GentityNum(sorted[i])
		local state = frame.entities[frame.num_entities]
		if not state then
			state = S.entityState_t()
			frame.entities[frame.num_entities] = state
		end
		S.copy_entityState_t(state, ent.s)
		svs.nextSnapshotEntities += 1
		frame.num_entities += 1
	end
end

function SV.SV_SendClientSnapshot(client)
	-- build the snapshot
	SV.SV_BuildClientSnapshot(client)

	-- bots need to have their snapshots build, but the query them
	-- directly without needing to send
	if client.gentity and band(client.gentity.r.svFlags, C.SVF_BOT) ~= 0 then
		return
	end

	local msg = MSG.Init()

	-- NOTE, MRE: all server->client messages now acknowledge
	-- let the client know which reliable clientCommands we have received
	MSG.WriteLong(msg, client.lastClientCommand)

	-- (re)send any reliable server commands
	SV_UpdateServerCommandsToClient(client, msg)

	-- send over all the relevant entityState_t and the playerState_t
	SV_WriteSnapshotToClient(client, msg)

	MSG.WriteByte(msg, MSG.svc_EOF)

	-- check for overflow
	if msg.overflowed then
		Com_Printf("WARNING: msg overflowed for %s\n", client.name)
		msg = MSG.Init()
	end

	SV_SendMessageToClient(msg, client)
end

function SV.SV_SendClientMessages()
	for i = 0, maxclients() - 1 do
		local c = svs.clients[i]

		if c.state == SV.CS_FREE then
			continue -- not connected
		end

		if svs.time - c.lastSnapshotTime < c.snapshotMsec then
			continue -- It's not time yet
		end

		-- no rate limiting: Roblox does its own pacing, and an unreliable
		-- event is dropped rather than queued (docs/formats/net.md)
		SV.SV_SendClientSnapshot(c)
		c.lastSnapshotTime = svs.time
		c.rateDelayed = false
	end
end

--
-- frame (sv_main.c)
--

-- Updates the cl->ping variables
local function SV_CalcPings()
	for i = 0, maxclients() - 1 do
		local cl = svs.clients[i]
		if cl.state ~= SV.CS_ACTIVE then
			cl.ping = 999
			continue
		end
		if not cl.gentity then
			cl.ping = 999
			continue
		end
		if band(cl.gentity.r.svFlags, C.SVF_BOT) ~= 0 then
			cl.ping = 0
			continue
		end

		local total, count = 0, 0
		for j = 0, SV.PACKET_BACKUP - 1 do
			if cl.frames[j].messageAcked <= 0 then
				continue
			end
			local delta = cl.frames[j].messageAcked - cl.frames[j].messageSent
			count += 1
			total += delta
		end
		if count == 0 then
			cl.ping = 999
		else
			cl.ping = Q.idiv(total, count)
			if cl.ping > 999 then
				cl.ping = 999
			end
		end

		-- let the game dll know about the ping
		sv.gameClients[i].ps.ping = cl.ping
	end
end

-- If a packet has not been received from a client for timeout->integer
-- seconds, drop the connection. Server time is used instead of realtime
-- to avoid dropping the local client while debugging.
local function SV_CheckTimeouts()
	local droppoint = svs.time - 1000 * cv.sv_timeout.integer
	local zombiepoint = svs.time - 1000 * cv.sv_zombietime.integer

	for i = 0, maxclients() - 1 do
		local cl = svs.clients[i]
		-- message times may be wrong across a changelevel
		if cl.lastPacketTime > svs.time then
			cl.lastPacketTime = svs.time
		end

		if cl.state == SV.CS_ZOMBIE and cl.lastPacketTime < zombiepoint then
			cl.state = SV.CS_FREE -- can now be reused
			continue
		end
		if cl.state >= SV.CS_CONNECTED and not cl.isBot and cl.lastPacketTime < droppoint then
			-- wait several frames so a debugger session doesn't cause a timeout
			cl.timeoutCount += 1
			if cl.timeoutCount > 5 then
				SV.SV_DropClient(cl, "timed out")
				cl.state = SV.CS_FREE -- don't bother with zombie state
			end
		else
			cl.timeoutCount = 0
		end
	end
end

-- the host's frame clock (com_frameTime): serverIds come from it. A
-- client's first packets carry serverId 0, so it must never be 0; ioq3's
-- starts at the engine's uptime, ours at a random point.
SV.com_frameTime = math.random(1, 0x3FFFFFF)

-- Player movement occurs as a result of packet events, which happen
-- before SV_Frame is called
function SV.SV_Frame(msec: number)
	SV.com_frameTime += msec

	-- run queued console commands first (map changes land here)
	Cmd.Cbuf_Execute()

	if cv.sv_killserver.integer ~= 0 then
		SV.SV_Shutdown("Server was killed")
		Cvar.Set("sv_killserver", "0")
		return
	end

	if sv.state ~= SV.SS_GAME then
		return
	end

	-- if it isn't time for the next frame, do nothing
	if cv.sv_fps.integer < 1 then
		Cvar.Set("sv_fps", "10")
	end

	local frameMsec = Q.idiv(1000, cv.sv_fps.integer)
	if frameMsec < 1 then
		frameMsec = 1
	end

	sv.timeResidual += msec

	-- if time is about to hit the 32nd bit, kick all clients and clear
	-- sv.time, rather than checking for negative time wraparound everywhere.
	if svs.time > 0x70000000 then
		SV.SV_Shutdown("Restarting server due to time wrapping")
		Cmd.Cbuf_AddText(QS.va("map %s\n", Cvar.VariableString("mapname")))
		return
	end

	if sv.restartTime ~= 0 and sv.time >= sv.restartTime then
		sv.restartTime = 0
		Cmd.Cbuf_AddText("map_restart 0\n")
		return
	end

	-- update infostrings if anything has been changed
	if band(Cvar.cvar_modifiedFlags, C.CVAR_SERVERINFO) ~= 0 then
		SV.SV_SetConfigstring(C.CS_SERVERINFO, Cvar.InfoString(C.CVAR_SERVERINFO))
		Cvar.cvar_modifiedFlags = band(Cvar.cvar_modifiedFlags, bnot(C.CVAR_SERVERINFO))
	end
	if band(Cvar.cvar_modifiedFlags, C.CVAR_SYSTEMINFO) ~= 0 then
		SV.SV_SetConfigstring(C.CS_SYSTEMINFO, Cvar.InfoString(C.CVAR_SYSTEMINFO))
		Cvar.cvar_modifiedFlags = band(Cvar.cvar_modifiedFlags, bnot(C.CVAR_SYSTEMINFO))
	end

	-- update ping based on the all received frames
	SV_CalcPings()

	-- the bots think once per host frame (dedicated server)
	SV.Bots.Frame(sv.time)

	-- run the game simulation in chunks
	while sv.timeResidual >= frameMsec do
		sv.timeResidual -= frameMsec
		svs.time += frameMsec
		sv.time += frameMsec

		-- let everything in the world think and move
		G.vmMain(C.GAME_RUN_FRAME, sv.time)
		if sv.state ~= SV.SS_GAME then
			return -- the frame changed the map
		end
	end

	-- check timeouts
	SV_CheckTimeouts()

	-- send messages back to the clients
	SV.SV_SendClientMessages()
end

--
-- init (sv_init.c)
--

-- Entity baselines are used to compress non-delta messages to the
-- clients -- only the fields that differ from the baseline will be
-- transmitted
local function SV_CreateBaseline()
	for entnum = 1, sv.num_entities - 1 do
		local svent = W.SV_GentityNum(entnum)
		if not svent.r.linked then
			continue
		end
		svent.s.number = entnum

		-- take current state as baseline
		S.copy_entityState_t(sv.svEntities[entnum].baseline, svent.s)
	end
end

-- wipe the per-level state (C: Com_Memset(&sv, 0, sizeof(sv)))
local function SV_ClearServer()
	sv.state = SV.SS_DEAD
	sv.restartedServerId = 0
	sv.serverId = 0
	sv.time = 0
	sv.nextFrameTime = 0
	sv.checksumFeed = 0
	sv.gentities = nil
	sv.gameClients = nil
	sv.configstrings = {}
	for i = 0, C.MAX_GENTITIES - 1 do
		local e = SV.newSvEntity()
		e.index = i
		sv.svEntities[i] = e
	end
	sv.snapshotCounter = 0
	sv.timeResidual = 0
	sv.restartTime = 0
	sv.restarting = false
	sv.num_entities = 0
	sv.entityParsePoint = nil
end

local function SV_ShutdownGameProgs()
	if sv.gameRunning then
		G.vmMain(C.GAME_SHUTDOWN, false)
		sv.gameRunning = false
	end
end

local function SV_InitGameVM(restart: boolean)
	-- start the entity parsing at the beginning
	sv.entityParsePoint = QS.cursor(Collision.EntityString())

	-- clear all gentity pointers that might still be set from a previous
	-- level (https://bugzilla.icculus.org/show_bug.cgi?id=522)
	for i = 0, maxclients() - 1 do
		svs.clients[i].gentity = nil
	end

	-- use the current msec count for a random seed; init for this gamestate
	G.vmMain(C.GAME_INIT, sv.time, SV.Sys_Milliseconds(), restart)
	sv.gameRunning = true
end

-- the clients table follows sv_maxclients (SV_Startup / SV_ChangeMaxClients)
local function SV_SetupClients()
	local n = maxclients()
	if n < 1 then
		Cvar.Set("sv_maxclients", "1")
	elseif n > C.MAX_CLIENTS then
		Cvar.Set("sv_maxclients", tostring(C.MAX_CLIENTS))
	end
	n = maxclients()
	for i = 0, C.MAX_CLIENTS - 1 do
		if not svs.clients[i] then
			svs.clients[i] = SV.newClient(i)
		end
	end
	-- clients past the new maximum are dropped
	for i = n, C.MAX_CLIENTS - 1 do
		local cl = svs.clients[i]
		if cl.state >= SV.CS_CONNECTED then
			SV.SV_DropClient(cl, "server shrank")
		end
		svs.clients[i] = SV.newClient(i)
	end
	svs.initialized = true
end

-- Change the server to a new map, taking all connected clients along
-- with it. This is NOT called for map_restart
function SV.SV_SpawnServer(server: string, killBots: boolean)
	-- shut down the existing game if it is running
	SV_ShutdownGameProgs()

	Com_Printf("------ Server Initialization ------\n")
	Com_Printf("Server: %s\n", server)

	-- latched cvars (sv_maxclients, g_gametype ...) take their new value
	-- now; Cvar.Get re-registration applies latches
	for _, name in { "sv_maxclients", "g_gametype" } do
		local v = Cvar.FindVar(name)
		if v and v.latchedString then
			Cvar.Get(name, v.resetString, 0)
		end
	end
	SV_SetupClients()

	-- toggle the server bit so clients can detect that a server has changed
	svs.snapFlagServerBit = bxor(svs.snapFlagServerBit, C.SNAPFLAG_SERVERCOUNT)

	-- set nextmap to the same map, but it may be overriden by the game
	-- startup or another console command
	Cvar.Set("nextmap", "map_restart 0")

	-- make sure that sv.time and the client's oldServerTime stay sane
	for i = 0, maxclients() - 1 do
		if svs.clients[i].state >= SV.CS_CONNECTED then
			svs.clients[i].oldServerTime = sv.time
		end
	end

	-- wipe the entire per-level structure
	SV_ClearServer()
	for i = 0, C.MAX_CONFIGSTRINGS - 1 do
		sv.configstrings[i] = ""
	end

	-- the key that obfuscates usercmds (sv.checksumFeed)
	sv.checksumFeed = bxor(bit32.lshift(math.random(0, 0x7FFF), 16), math.random(0, 0x7FFF), SV.Sys_Milliseconds())
	sv.checksumFeed = s32(sv.checksumFeed)

	-- load the map data
	if not SV.loadMap then
		error("SV_SpawnServer: no map loader")
	end
	local lumps = SV.loadMap(server)
	if not lumps then
		error(SV.GameError(QS.va("Couldn't load maps/%s.bsp", server)), 0)
	end
	Collision.LoadMap(QS.va("maps/%s.bsp", server), lumps)
	-- botlib reads maps/<name>.aas when the game loads the map
	if lumps.aas then
		Fs.Mount(QS.va("maps/%s.aas", server), buffer.tostring(lumps.aas))
	end

	-- set serverinfo visible name
	Cvar.Set("mapname", server)
	Cvar.Set("sv_mapChecksum", tostring(lumps.checksum or 0))

	-- serverid should be different each time
	sv.serverId = SV.com_frameTime
	sv.restartedServerId = sv.serverId -- I suppose the init here is just to be safe
	Cvar.Set("sv_serverid", QS.va("%i", sv.serverId))

	-- clear physics interaction links
	W.SV_ClearWorld()

	-- media configstring setting should be done during the loading stage,
	-- so any media configstring commands are not sent to the clients
	sv.state = SV.SS_LOADING

	-- load and spawn all other entities (SV_InitGameProgs)
	SV.Bots.InitGameProgs()
	SV_InitGameVM(false)

	-- run a few frames to allow everything to settle
	for _ = 1, 3 do
		G.vmMain(C.GAME_RUN_FRAME, sv.time)
		SV.Bots.Frame(sv.time)
		sv.time += 100
		svs.time += 100
	end

	-- create a baseline for more efficient communications
	SV_CreateBaseline()

	for i = 0, maxclients() - 1 do
		local cl = svs.clients[i]
		-- send the new gamestate to all connected clients
		if cl.state >= SV.CS_CONNECTED then
			local isBot = cl.isBot
			if isBot and killBots then
				SV.SV_DropClient(cl, "")
				continue
			end

			-- connect the client again
			local denied = G.vmMain(C.GAME_CLIENT_CONNECT, i, false, isBot) -- firstTime = false
			if type(denied) == "string" then
				-- this generally shouldn't happen, because the client was
				-- connected before the level change
				SV.SV_DropClient(cl, denied)
			else
				if not isBot then
					-- when we get the next packet from a connected client,
					-- the new gamestate will be sent
					cl.state = SV.CS_CONNECTED
				else
					cl.state = SV.CS_ACTIVE
					local ent = W.SV_GentityNum(i)
					ent.s.number = i
					cl.gentity = ent

					cl.deltaMessage = -1
					cl.lastSnapshotTime = 0 -- generate a snapshot immediately

					G.vmMain(C.GAME_CLIENT_BEGIN, i)
				end
			end
		end
	end

	-- run another frame to allow things to look at all the players
	G.vmMain(C.GAME_RUN_FRAME, sv.time)
	SV.Bots.Frame(sv.time)
	sv.time += 100
	svs.time += 100

	Cvar.Set("sv_paks", "")
	Cvar.Set("sv_pakNames", "")

	-- save systeminfo and serverinfo strings
	SV.SV_SetConfigstring(C.CS_SYSTEMINFO, Cvar.InfoString(C.CVAR_SYSTEMINFO))
	Cvar.cvar_modifiedFlags = band(Cvar.cvar_modifiedFlags, bnot(C.CVAR_SYSTEMINFO))

	SV.SV_SetConfigstring(C.CS_SERVERINFO, Cvar.InfoString(C.CVAR_SERVERINFO))
	Cvar.cvar_modifiedFlags = band(Cvar.cvar_modifiedFlags, bnot(C.CVAR_SERVERINFO))

	-- any media configstring setting now should issue a warning and any
	-- configstring changes should be reliably transmitted to all clients
	sv.state = SV.SS_GAME

	Com_Printf("-----------------------------------\n")
end

-- Called when each game quits, before Sys_Quit or Sys_Error
function SV.SV_Shutdown(finalmsg: string)
	if sv.state == SV.SS_DEAD then
		return
	end
	Com_Printf("----- Server Shutdown (%s) -----\n", finalmsg)

	-- SV_FinalMessage: tell every client
	for i = 0, maxclients() - 1 do
		local cl = svs.clients[i]
		if cl.state >= SV.CS_CONNECTED and not cl.isBot then
			SV.SV_SendServerCommand(cl, QS.va('print "%s\n"\n', finalmsg))
			SV.SV_SendServerCommand(cl, QS.va('disconnect "%s"', finalmsg))
			local msg = MSG.Init()
			MSG.WriteLong(msg, cl.lastClientCommand)
			SV_UpdateServerCommandsToClient(cl, msg)
			MSG.WriteByte(msg, MSG.svc_EOF)
			SV_SendMessageToClient(msg, cl)
		end
	end

	SV_ShutdownGameProgs()

	-- free current level
	SV_ClearServer()
	sv.state = SV.SS_DEAD

	for i = 0, C.MAX_CLIENTS - 1 do
		svs.clients[i] = SV.newClient(i)
	end
	Com_Printf("---------------------------\n")
end

--
-- operator commands (sv_ccmds.c)
--

-- Returns the player with player id or name from Cmd_Argv(1)
local function SV_GetPlayerByHandle()
	if Cmd.Cmd_Argc() < 2 then
		Com_Printf("No player specified.\n")
		return nil
	end
	local s = Cmd.Cmd_Argv(1)

	-- Check whether this is a numeric player handle
	if string.match(s, "^%d+$") then
		local plid = tonumber(s) :: number
		if plid >= 0 and plid < maxclients() then
			local cl = svs.clients[plid]
			if cl.state ~= SV.CS_FREE then
				return cl
			end
		end
	end

	-- check for a name match
	for i = 0, maxclients() - 1 do
		local cl = svs.clients[i]
		if cl.state == SV.CS_FREE then
			continue
		end
		if QS.Q_stricmp(cl.name, s) == 0 then
			return cl
		end
		if QS.Q_stricmp(QS.Q_CleanStr(cl.name), s) == 0 then
			return cl
		end
		-- a friend-bot also answers to its OA bot name
		if cl.isBot and QS.Q_stricmp(QS.Info_ValueForKey(cl.userinfo, "oabot"), s) == 0 then
			return cl
		end
	end

	Com_Printf("Player %s is not on the server\n", s)
	return nil
end

-- Returns the player with idnum from Cmd_Argv(1)
local function SV_GetPlayerByNum()
	if Cmd.Cmd_Argc() < 2 then
		Com_Printf("No player specified.\n")
		return nil
	end
	local s = Cmd.Cmd_Argv(1)
	if not string.match(s, "^%d+$") then
		Com_Printf("Bad slot number: %s\n", s)
		return nil
	end
	local idnum = tonumber(s) :: number
	if idnum < 0 or idnum >= maxclients() then
		Com_Printf("Bad client slot: %i\n", idnum)
		return nil
	end
	local cl = svs.clients[idnum]
	if cl.state == SV.CS_FREE then
		Com_Printf("Client %i is not active\n", idnum)
		return nil
	end
	return cl
end

-- Restart the server on a different map
local function SV_Map_f()
	local map = Cmd.Cmd_Argv(1)
	if map == "" then
		return
	end

	-- make sure the level exists before trying to change, so that a typo
	-- at the server console won't end the game
	if SV.mapExists and not SV.mapExists(map) then
		Com_Printf("Can't find map maps/%s.bsp\n", map)
		return
	end

	-- force latched values to get set
	Cvar.Get("g_gametype", "0", bor(C.CVAR_SERVERINFO, C.CVAR_USERINFO, C.CVAR_LATCH))

	local cmd = string.lower(Cmd.Cmd_Argv(0))
	local cheat, killBots
	if string.sub(cmd, 1, 2) == "sp" then
		Cvar.SetValue("g_gametype", C.GT_SINGLE_PLAYER)
		Cvar.SetValue("g_doWarmup", 0)
		-- may not set sv_maxclients directly, always set latched
		Cvar.Set2("sv_maxclients", "8", false)
		cmd = string.sub(cmd, 3)
		cheat = cmd == "devmap"
		killBots = true
	else
		cheat = cmd == "devmap" or cmd == "spdevmap"
		killBots = false
		if Cvar.VariableIntegerValue("g_gametype") == C.GT_SINGLE_PLAYER then
			Cvar.SetValue("g_gametype", C.GT_FFA)
		end
	end

	-- save the map name here cause on a map restart we reload the
	-- q3config.cfg and thus nuke the arguments of the map command
	local mapname = map

	-- start up the map
	SV.SV_SpawnServer(mapname, killBots)

	-- set the cheat value; if the level is invalid, this will never be reached
	Cvar.Set("sv_cheats", if cheat then "1" else "0")
end

-- Completely restarts a level, but doesn't send a new gamestate to the
-- clients. This allows fair starts with variable load times.
local function SV_MapRestart_f()
	-- make sure we aren't restarting twice in the same frame
	if SV.com_frameTime == sv.serverId then
		return
	end

	-- make sure server is running
	if sv.state ~= SV.SS_GAME then
		Com_Printf("Server is not running.\n")
		return
	end

	if sv.restartTime ~= 0 then
		return
	end

	local delay
	if Cmd.Cmd_Argc() > 1 then
		delay = QS.atoi(Cmd.Cmd_Argv(1))
	else
		delay = 5
	end
	if delay ~= 0 and Cvar.VariableValue("g_doWarmup") == 0 then
		sv.restartTime = sv.time + delay * 1000
		SV.SV_SetConfigstring(C.CS_WARMUP, QS.va("%i", sv.restartTime))
		return
	end

	-- check for changes in variables that can't just be restarted; check
	-- for maxclients change
	local mc = Cvar.FindVar("sv_maxclients")
	local gt = Cvar.FindVar("g_gametype")
	if (mc and mc.latchedString) or (gt and gt.latchedString) then
		Com_Printf("variable change -- restarting.\n")
		-- restart the map the slow way
		local mapname = Cvar.VariableString("mapname")
		SV.SV_SpawnServer(mapname, false)
		return
	end

	-- toggle the server bit so clients can detect that a map_restart has happened
	svs.snapFlagServerBit = bxor(svs.snapFlagServerBit, C.SNAPFLAG_SERVERCOUNT)

	-- generate a new serverid
	-- TTimo - don't update restartedserverId there, otherwise we won't
	-- deal correctly with multiple map_restart
	sv.serverId = SV.com_frameTime
	Cvar.Set("sv_serverid", QS.va("%i", sv.serverId))

	-- if a map_restart occurs while a client is changing maps, we need to
	-- give them the correct time so that when they finish loading they
	-- don't violate the backwards time check in cl_cgame.c
	for i = 0, maxclients() - 1 do
		if svs.clients[i].state == SV.CS_PRIMED then
			svs.clients[i].oldServerTime = sv.restartTime
		end
	end

	-- reset all the vm data in place without changing memory allocation;
	-- note that we do NOT set sv.state = SS_LOADING, so configstrings
	-- that had been changed from their default values will generate
	-- broadcast updates
	sv.state = SV.SS_LOADING
	sv.restarting = true

	-- SV_RestartGameProgs
	if sv.gameRunning then
		G.vmMain(C.GAME_SHUTDOWN, true)
	end
	SV_InitGameVM(true)

	-- run a few frames to allow everything to settle
	for _ = 1, 3 do
		G.vmMain(C.GAME_RUN_FRAME, sv.time)
		sv.time += 100
		svs.time += 100
	end

	sv.state = SV.SS_GAME
	sv.restarting = false

	-- connect and begin all the clients
	for i = 0, maxclients() - 1 do
		local client = svs.clients[i]

		-- send the new gamestate to all connected clients
		if client.state < SV.CS_CONNECTED then
			continue
		end

		local isBot = client.isBot

		-- add the map_restart command
		SV.SV_AddServerCommand(client, "map_restart\n")

		-- connect the client again, without the firstTime flag
		local denied = G.vmMain(C.GAME_CLIENT_CONNECT, i, false, isBot)
		if type(denied) == "string" then
			-- this generally shouldn't happen, because the client was
			-- connected before the level change
			SV.SV_DropClient(client, denied)
			Com_Printf("SV_MapRestart_f(%d): dropped client %i - denied!\n", delay, i)
			continue
		end

		if client.state == SV.CS_ACTIVE then
			SV.SV_ClientEnterWorld(client, client.lastUsercmd)
		else
			-- If we don't reset client->lastUsercmd and are restarting
			-- during map load, the client will hang because we'll use the
			-- last Usercmd from the previous map, which is wrong obviously.
			SV.SV_ClientEnterWorld(client, nil)
		end
	end

	-- run another frame to allow things to look at all the players
	G.vmMain(C.GAME_RUN_FRAME, sv.time)
	sv.time += 100
	svs.time += 100
end

-- Kick a user off of the server
local function SV_Kick_f()
	if sv.state ~= SV.SS_GAME then
		Com_Printf("Server is not running.\n")
		return
	end
	if Cmd.Cmd_Argc() ~= 2 then
		Com_Printf("Usage: kick <player name>\nkick all = kick everyone\nkick allbots = kick all bots\n")
		return
	end
	local cl = SV_GetPlayerByHandle()
	if not cl then
		local a = Cmd.Cmd_Argv(1)
		if QS.Q_stricmp(a, "all") == 0 then
			for i = 0, maxclients() - 1 do
				local c = svs.clients[i]
				if c.state ~= SV.CS_FREE then
					SV.SV_DropClient(c, "was kicked")
					c.lastPacketTime = svs.time -- in case there is a funny zombie
				end
			end
		elseif QS.Q_stricmp(a, "allbots") == 0 then
			for i = 0, maxclients() - 1 do
				local c = svs.clients[i]
				if c.state ~= SV.CS_FREE and c.isBot then
					SV.SV_DropClient(c, "was kicked")
					c.lastPacketTime = svs.time -- in case there is a funny zombie
				end
			end
		end
		return
	end
	SV.SV_DropClient(cl, "was kicked")
	cl.lastPacketTime = svs.time -- in case there is a funny zombie
end

-- Kick a user off of the server by slot number
local function SV_KickNum_f()
	if sv.state ~= SV.SS_GAME then
		Com_Printf("Server is not running.\n")
		return
	end
	if Cmd.Cmd_Argc() ~= 2 then
		Com_Printf("Usage: %s <client number>\n", Cmd.Cmd_Argv(0))
		return
	end
	local cl = SV_GetPlayerByNum()
	if not cl then
		return
	end
	SV.SV_DropClient(cl, "was kicked")
	cl.lastPacketTime = svs.time -- in case there is a funny zombie
end

local function SV_Status_f()
	if sv.state ~= SV.SS_GAME then
		Com_Printf("Server is not running.\n")
		return
	end
	Com_Printf("map: %s\n", Cvar.VariableString("mapname"))
	Com_Printf("cl score ping name            address\n")
	Com_Printf("-- ----- ---- --------------- -------\n")
	for i = 0, maxclients() - 1 do
		local cl = svs.clients[i]
		if cl.state == SV.CS_FREE then
			continue
		end
		local ps = sv.gameClients[i].ps
		local ping
		if cl.state == SV.CS_CONNECTED then
			ping = "CNCT"
		elseif cl.state == SV.CS_ZOMBIE then
			ping = "ZMBI"
		else
			ping = QS.va("%4i", math.min(cl.ping, 9999))
		end
		Com_Printf(
			"%2i %5i %s %-15s %s\n",
			i,
			ps.persistant[C.PERS_SCORE],
			ping,
			cl.name,
			if cl.isBot then "bot" else cl.address or ""
		)
	end
end

local function SV_Serverinfo_f()
	Com_Printf("Server info settings:\n%s\n", Cvar.InfoString(C.CVAR_SERVERINFO))
end

local function SV_Systeminfo_f()
	Com_Printf("System info settings:\n%s\n", Cvar.InfoString(C.CVAR_SYSTEMINFO))
end

local function SV_DumpUser_f()
	if sv.state ~= SV.SS_GAME then
		Com_Printf("Server is not running.\n")
		return
	end
	if Cmd.Cmd_Argc() ~= 2 then
		Com_Printf("Usage: dumpuser <userid>\n")
		return
	end
	local cl = SV_GetPlayerByHandle()
	if not cl then
		return
	end
	Com_Printf("userinfo\n--------\n%s\n", cl.userinfo)
end

local function SV_KillServer_f()
	SV.SV_Shutdown("killserver")
end

-- the cvars the engine owns (SV_Init and the common ones the game reads)
function SV.SV_Init()
	Cmd.Init()
	Cmd.print = function(s)
		SV.Com_Printf(s)
	end
	Cvar.print = Cmd.print
	Cmd.readFile = Fs.ReadFile
	-- commands the engine does not know go to the game's ConsoleCommand
	Cmd.fallback = function(): boolean
		if sv.state ~= SV.SS_GAME and sv.state ~= SV.SS_LOADING then
			return false
		end
		local r = G.vmMain(C.GAME_CONSOLE_COMMAND)
		return r == true or (type(r) == "number" and r ~= 0)
	end

	local SI, LATCH, ROM, ARCH, TEMP, SYS =
		C.CVAR_SERVERINFO, C.CVAR_LATCH, C.CVAR_ROM, C.CVAR_ARCHIVE, C.CVAR_TEMP, C.CVAR_SYSTEMINFO
	Cvar.Get("dmflags", "0", SI)
	Cvar.Get("fraglimit", "20", SI)
	Cvar.Get("timelimit", "0", SI)
	cv.sv_gametype = Cvar.Get("g_gametype", "0", bor(SI, LATCH))
	Cvar.Get("sv_keywords", "", SI)
	cv.sv_mapname = Cvar.Get("mapname", "nomap", bor(SI, ROM))
	cv.sv_privateClients = Cvar.Get("sv_privateClients", "0", SI)
	cv.sv_hostname = Cvar.Get("sv_hostname", "noname", bor(SI, ARCH))
	cv.sv_maxclients = Cvar.Get("sv_maxclients", "8", bor(SI, LATCH))
	Cvar.Get("sv_minRate", "0", bor(ARCH, SI))
	Cvar.Get("sv_maxRate", "0", bor(ARCH, SI))
	Cvar.Get("sv_dlRate", "100", bor(ARCH, SI))
	Cvar.Get("sv_minPing", "0", bor(ARCH, SI))
	Cvar.Get("sv_maxPing", "0", bor(ARCH, SI))
	cv.sv_floodProtect = Cvar.Get("sv_floodProtect", "1", bor(ARCH, SI))

	-- systeminfo
	Cvar.Get("sv_cheats", "1", bor(SYS, ROM))
	cv.sv_serverid = Cvar.Get("sv_serverid", "0", bor(SYS, ROM))
	cv.sv_pure = Cvar.Get("sv_pure", "0", SYS)
	Cvar.Get("sv_paks", "", bor(SYS, ROM))
	Cvar.Get("sv_pakNames", "", bor(SYS, ROM))
	Cvar.Get("sv_referencedPaks", "", bor(SYS, ROM))
	Cvar.Get("sv_referencedPakNames", "", bor(SYS, ROM))

	-- server vars
	Cvar.Get("rconPassword", "", TEMP)
	Cvar.Get("sv_privatePassword", "", TEMP)
	cv.sv_fps = Cvar.Get("sv_fps", "20", TEMP)
	cv.sv_timeout = Cvar.Get("sv_timeout", "200", TEMP)
	cv.sv_zombietime = Cvar.Get("sv_zombietime", "2", TEMP)
	Cvar.Get("nextmap", "", TEMP)
	Cvar.Get("sv_allowDownload", "0", SI)
	cv.sv_killserver = Cvar.Get("sv_killserver", "0", 0)
	Cvar.Get("sv_mapChecksum", "", ROM)

	-- common cvars the game module reads (com_*, version strings)
	Cvar.Get("gamename", "baseoa", bor(SI, ROM))
	Cvar.Get("protocol", "71", bor(SI, ROM))
	Cvar.Get("version", "OpenArena-rbx", bor(ROM, SI))
	Cvar.Get("dedicated", "2", 0)
	Cvar.Get("sv_running", "1", ROM)
	Cvar.Get("timescale", "1", 0)

	Cmd.Cmd_AddCommand("map", SV_Map_f)
	Cmd.Cmd_AddCommand("devmap", SV_Map_f)
	Cmd.Cmd_AddCommand("spmap", SV_Map_f)
	Cmd.Cmd_AddCommand("spdevmap", SV_Map_f)
	Cmd.Cmd_AddCommand("map_restart", SV_MapRestart_f)
	Cmd.Cmd_AddCommand("kick", SV_Kick_f)
	Cmd.Cmd_AddCommand("clientkick", SV_KickNum_f)
	Cmd.Cmd_AddCommand("status", SV_Status_f)
	Cmd.Cmd_AddCommand("serverinfo", SV_Serverinfo_f)
	Cmd.Cmd_AddCommand("systeminfo", SV_Systeminfo_f)
	Cmd.Cmd_AddCommand("dumpuser", SV_DumpUser_f)
	Cmd.Cmd_AddCommand("killserver", SV_KillServer_f)
	Cmd.Cmd_AddCommand("sectorlist", function()
		W.SV_SectorList_f(Cmd.print)
	end)

	SV_SetupClients()

	-- load the botlib
	SV.Bots.Init()
end

return SV
