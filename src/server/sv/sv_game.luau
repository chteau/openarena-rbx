--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (ioquake3 code/server/sv_game.c).

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
-- The game module's system calls (ioquake3 code/server/sv_game.c): every
-- G.trap_* the ported g_*.luau files call, implemented on the engine
-- modules (sv_world, cvar, cmd, fs, Collision) and the client table in
-- server.luau. sv_main.luau provides the client-facing pieces
-- (SV.SV_SendServerCommand, SV.SV_DropClient, SV.SV_SetConfigstring ...).
--
-- The C boundary passes buffers; here out-parameters become return values
-- as listed in docs/game-notes.md ("Trap API").

local G = require("../g_local")
local SV = require("./server")
local W = require("./sv_world")
local Cvar = require("./cvar")
local Cmd = require("./cmd")
local Fs = require("./fs")
local Collision = require("../../shared/Collision")
local QS = require("../../shared/q_shared")
local Q = require("../../shared/q_math")
local S = require("../../shared/structs")
local C = require("../g_defs")

local sv, svs = SV.sv, SV.svs

-- host clock in milliseconds (Sys_Milliseconds); the host may replace it
SV.Sys_Milliseconds = function(): number
	return math.floor(os.clock() * 1000)
end

-- console output sink; the host may replace it. The default prints whole
-- lines (print() always ends one)
local pending = ""
SV.Com_Printf = function(text: string)
	pending ..= text
	while true do
		local nl = string.find(pending, "\n", 1, true)
		if not nl then
			break
		end
		print(string.sub(pending, 1, nl - 1))
		pending = string.sub(pending, nl + 1)
	end
end

local function sv_maxclients(): number
	return Cvar.VariableIntegerValue("sv_maxclients")
end

--
-- printing and errors
--

function G.trap_Printf(text: string)
	SV.Com_Printf(text)
end

-- ERR_DROP: the game raises, the host catches it and kills the server
function G.trap_Error(text: string)
	error(SV.GameError(text), 0)
end

-- a recognisable error object so the host can tell a game drop from a bug
local GameErrorMT = {
	__tostring = function(e)
		return "Game error: " .. e.text
	end,
}
function SV.GameError(text: string)
	return setmetatable({ text = text, isGameError = true }, GameErrorMT)
end

function G.trap_Milliseconds(): number
	return SV.Sys_Milliseconds()
end

-- Com_RealTime: fills qtime (struct tm fields) and returns the epoch time
function G.trap_RealTime(qtime): number
	local t = os.time()
	if qtime then
		local d = os.date("*t", t) :: any
		qtime.tm_sec = d.sec
		qtime.tm_min = d.min
		qtime.tm_hour = d.hour
		qtime.tm_mday = d.day
		qtime.tm_mon = d.month - 1
		qtime.tm_year = d.year - 1900
		qtime.tm_wday = d.wday - 1
		qtime.tm_yday = d.yday - 1
		qtime.tm_isdst = if d.isdst then 1 else 0
	end
	return t
end

--
-- console
--

function G.trap_Argc(): number
	return Cmd.Cmd_Argc()
end

function G.trap_Argv(n: number): string
	return Cmd.Cmd_Argv(n)
end

function G.trap_SendConsoleCommand(exec_when: number, text: string)
	Cmd.Cbuf_ExecuteText(exec_when, text)
end

--
-- cvars
--

function G.trap_Cvar_Register(vmCvar, name: string, value: string, flags: number)
	Cvar.Register(vmCvar, name, value, flags)
end

function G.trap_Cvar_Update(vmCvar)
	Cvar.Update(vmCvar)
end

-- the game's own sets are trusted (CVAR_ROM etc. still apply via Set2 force)
function G.trap_Cvar_Set(name: string, value: string)
	Cvar.Set2(name, value, true)
end

function G.trap_Cvar_VariableIntegerValue(name: string): number
	return Cvar.VariableIntegerValue(name)
end

function G.trap_Cvar_VariableValue(name: string): number
	return Cvar.VariableValue(name)
end

function G.trap_Cvar_VariableStringBuffer(name: string): string
	return Cvar.VariableString(name)
end

--
-- game data and clients
--

function G.trap_LocateGameData(gEnts, numGEntities: number, clients)
	sv.gentities = gEnts
	sv.num_entities = numGEntities
	sv.gameClients = clients
end

function G.trap_DropClient(clientNum: number, reason: string)
	if clientNum < 0 or clientNum >= sv_maxclients() then
		return
	end
	SV.SV_DropClient(svs.clients[clientNum], reason)
end

function G.trap_SendServerCommand(clientNum: number, text: string)
	if clientNum == -1 then
		SV.SV_SendServerCommand(nil, text)
	else
		if clientNum < 0 or clientNum >= sv_maxclients() then
			return
		end
		SV.SV_SendServerCommand(svs.clients[clientNum], text)
	end
end

function G.trap_SetConfigstring(num: number, s: string)
	SV.SV_SetConfigstring(num, s)
end

function G.trap_GetConfigstring(num: number): string
	return SV.SV_GetConfigstring(num)
end

function G.trap_GetUserinfo(num: number): string
	return SV.SV_GetUserinfo(num)
end

function G.trap_SetUserinfo(num: number, s: string)
	SV.SV_SetUserinfo(num, s)
end

function G.trap_GetServerinfo(): string
	return Cvar.InfoString(C.CVAR_SERVERINFO)
end

function G.trap_GetUsercmd(clientNum: number, cmd)
	if clientNum < 0 or clientNum >= sv_maxclients() then
		error(string.format("SV_GetUsercmd: bad clientNum:%i", clientNum))
	end
	S.copy_usercmd_t(cmd, svs.clients[clientNum].lastUsercmd)
end

function G.trap_GetEntityToken(): string?
	local p = sv.entityParsePoint
	if not p then
		return nil
	end
	local s = QS.COM_Parse(p)
	if p.data == nil and s == "" then
		return nil
	end
	return s
end

--
-- world
--

function G.trap_SetBrushModel(ent, name: string)
	W.SV_SetBrushModel(ent, name)
end

function G.trap_Trace(results, start, mins, maxs, endp, passEntityNum: number, contentmask: number)
	W.SV_Trace(results, start, mins, maxs, endp, passEntityNum, contentmask, false)
end

function G.trap_TraceCapsule(results, start, mins, maxs, endp, passEntityNum: number, contentmask: number)
	W.SV_Trace(results, start, mins, maxs, endp, passEntityNum, contentmask, true)
end

function G.trap_PointContents(point, passEntityNum: number): number
	return W.SV_PointContents(point, passEntityNum)
end

function G.trap_InPVS(p1, p2): boolean
	return W.SV_inPVS(p1, p2)
end

function G.trap_InPVSIgnorePortals(p1, p2): boolean
	return W.SV_inPVSIgnorePortals(p1, p2)
end

function G.trap_AdjustAreaPortalState(ent, open: boolean)
	W.SV_AdjustAreaPortalState(ent, open)
end

function G.trap_AreasConnected(area1: number, area2: number): boolean
	return Collision.AreasConnected(area1, area2)
end

function G.trap_LinkEntity(ent)
	W.SV_LinkEntity(ent)
end

function G.trap_UnlinkEntity(ent)
	W.SV_UnlinkEntity(ent)
end

function G.trap_EntitiesInBox(mins, maxs, list, maxcount: number): number
	return W.SV_AreaEntities(mins, maxs, list, maxcount)
end

function G.trap_EntityContact(mins, maxs, ent): boolean
	return W.SV_EntityContact(mins, maxs, ent, false)
end

function G.trap_EntityContactCapsule(mins, maxs, ent): boolean
	return W.SV_EntityContact(mins, maxs, ent, true)
end

--
-- files
--

function G.trap_FS_FOpenFile(path: string, mode: number): (number, number)
	return Fs.FOpenFile(path, mode)
end

function G.trap_FS_Read(len: number, f: number): string
	return Fs.Read(len, f)
end

function G.trap_FS_Write(text: string, len: number, f: number)
	Fs.Write(text, len, f)
end

function G.trap_FS_FCloseFile(f: number)
	Fs.FCloseFile(f)
end

function G.trap_FS_GetFileList(path: string, extension: string): (number, { [number]: string })
	return Fs.GetFileList(path, extension)
end

function G.trap_FS_Seek(f: number, offset: number, origin: number): number
	return Fs.Seek(f, offset, origin)
end

--
-- misc
--

-- engine-side SnapVector: SSE round-to-nearest through an int (-0 -> +0)
function G.trap_SnapVector(v)
	Q.SnapVectorRint(v)
end

-- debug polygons are a renderer feature of listen servers; none here
function G.trap_DebugPolygonCreate(color: number, numPoints: number, points): number
	return 0
end

function G.trap_DebugPolygonDelete(id: number) end

--
-- bots: the server keeps the slots (the botlib traps are bot/g_botlib.luau)
--

-- SV_BotAllocateClient: finds a free slot, marks it active and a bot
function G.trap_BotAllocateClient(): number
	local maxc = sv_maxclients()
	local i = 0
	while i < maxc do
		if svs.clients[i].state == SV.CS_FREE then
			break
		end
		i += 1
	end
	if i == maxc then
		return -1
	end
	local cl = svs.clients[i]
	cl.gentity = W.SV_GentityNum(i)
	cl.gentity.s.number = i
	cl.state = SV.CS_ACTIVE
	cl.lastPacketTime = svs.time
	cl.isBot = true
	cl.rate = 16384
	return i
end

function G.trap_BotFreeClient(clientNum: number)
	if clientNum < 0 or clientNum >= sv_maxclients() then
		error(string.format("SV_BotFreeClient: bad clientNum: %i", clientNum))
	end
	local cl = svs.clients[clientNum]
	cl.state = SV.CS_FREE
	cl.name = ""
	if cl.gentity then
		cl.gentity.r.svFlags = bit32.band(cl.gentity.r.svFlags, bit32.bnot(C.SVF_BOT))
	end
end

return G
