--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (server/sv_bot.c and the BOTLIB_* cases of server/sv_game.c).

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
-- Luau port of sv_bot.c: the engine side of the bots. It builds botlib's
-- import from the engine (traces, contents, PVS, entity string, files),
-- holds botlib_export, runs the per-frame BOTAI_START_FRAME call, and
-- answers the bot syscalls that live in the engine (console messages,
-- snapshot entities, user commands). Everything it needs from the server
-- engine comes through the BotGame adapter (BotGame.luau, documented in
-- docs/bots-notes.md); SV_BotAllocateClient/SV_BotFreeClient are the
-- engine's own (the game branch's sv_game.luau has them).

local BC = require("./botlib/consts")
local SB = require("./botlib/structs")
local B = require("./botlib/botlib")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")

local SVB = {}

-- the BotGame adapter (see BotGame.luau)
local E: any = nil
-- int bot_enable
SVB.bot_enable = 0
SVB.botlib_export = nil :: any

type debugpoly = { inuse: boolean, color: number, numPoints: number, points: { any } }
local debugpolygons: { [number]: debugpoly }? = nil
local bot_maxdebugpolys = 0

function SVB.Bind(adapter)
	E = adapter
end

--==================
-- BotDrawDebugPolygons
--==================
local bot_debug, bot_groundonly, bot_reachability, bot_highlightarea
function SVB.BotDrawDebugPolygons(drawPoly: (number, number, { any }) -> (), value: number)
	if debugpolygons == nil then
		return
	end
	--bot debugging
	if not bot_debug then
		bot_debug = E.Cvar_Get("bot_debug", "0", 0)
	end
	if SVB.bot_enable ~= 0 and bot_debug.integer ~= 0 then
		--show reachabilities
		if not bot_reachability then
			bot_reachability = E.Cvar_Get("bot_reachability", "0", 0)
		end
		--show ground faces only
		if not bot_groundonly then
			bot_groundonly = E.Cvar_Get("bot_groundonly", "1", 0)
		end
		--get the hightlight area
		if not bot_highlightarea then
			bot_highlightarea = E.Cvar_Get("bot_highlightarea", "0", 0)
		end
		local parm0 = 0
		local cl0 = E.GetClient(0)
		if bit32.band(cl0.lastUsercmd.buttons, BC.BUTTON_ATTACK) ~= 0 then
			parm0 = bit32.bor(parm0, 1)
		end
		if bot_reachability.integer ~= 0 then
			parm0 = bit32.bor(parm0, 2)
		end
		if bot_groundonly.integer ~= 0 then
			parm0 = bit32.bor(parm0, 4)
		end
		SVB.botlib_export.BotLibVarSet("bot_highlightarea", bot_highlightarea.string)
		SVB.botlib_export.Test(parm0, nil, cl0.gentity.r.currentOrigin, cl0.gentity.r.currentAngles)
	end
	--draw all debug polys
	for i = 0, bot_maxdebugpolys - 1 do
		local poly = debugpolygons[i]
		if poly.inuse then
			drawPoly(poly.color, poly.numPoints, poly.points)
		end
	end
end

--==================
-- BotImport_Print
--==================
local function BotImport_Print(type: number, fmt: string, ...)
	local str = QS.Com_sprintf(2048, fmt, ...)
	if type == BC.PRT_MESSAGE then
		E.Com_Printf(str)
	elseif type == BC.PRT_WARNING then
		E.Com_Printf("^3Warning: " .. str)
	elseif type == BC.PRT_ERROR then
		E.Com_Printf("^1Error: " .. str)
	elseif type == BC.PRT_FATAL then
		E.Com_Printf("^1Fatal: " .. str)
	elseif type == BC.PRT_EXIT then
		E.Com_Error(BC.ERR_DROP, "^1Exit: " .. str)
	else
		E.Com_Printf("unknown print type\n")
	end
end

-- copy the trace information (BotImport_Trace / BotImport_EntityTrace)
local function copytrace(bsptrace, trace)
	bsptrace.allsolid = trace.allsolid
	bsptrace.startsolid = trace.startsolid
	bsptrace.fraction = trace.fraction
	Q.VectorCopy(trace.endpos, bsptrace.endpos)
	bsptrace.plane.dist = trace.plane.dist
	Q.VectorCopy(trace.plane.normal, bsptrace.plane.normal)
	bsptrace.plane.signbits = trace.plane.signbits
	bsptrace.plane.type = trace.plane.type
	bsptrace.surface.value = 0
	bsptrace.surface.flags = trace.surfaceFlags
	bsptrace.ent = trace.entityNum
	bsptrace.exp_dist = 0
	bsptrace.sidenum = 0
	bsptrace.contents = 0
end

--==================
-- BotImport_Trace
--==================
local function BotImport_Trace(bsptrace, start, mins, maxs, end_, passent: number, contentmask: number)
	local trace = E.trace_t()
	E.SV_Trace(trace, start, mins, maxs, end_, passent, contentmask, false)
	copytrace(bsptrace, trace)
end

--==================
-- BotImport_EntityTrace
--==================
local function BotImport_EntityTrace(bsptrace, start, mins, maxs, end_, entnum: number, contentmask: number)
	local trace = E.trace_t()
	E.SV_ClipToEntity(trace, start, mins, maxs, end_, entnum, contentmask, false)
	copytrace(bsptrace, trace)
end

--==================
-- BotImport_PointContents
--==================
local function BotImport_PointContents(point): number
	return E.SV_PointContents(point, -1)
end

--==================
-- BotImport_inPVS
--==================
local function BotImport_inPVS(p1, p2): boolean
	return E.SV_inPVS(p1, p2)
end

--==================
-- BotImport_BSPEntityData
--==================
local function BotImport_BSPEntityData(): string
	return E.CM_EntityString()
end

--==================
-- BotImport_BSPModelMinsMaxsOrigin
--==================
local function BotImport_BSPModelMinsMaxsOrigin(modelnum: number, angles, outmins, outmaxs, origin)
	local mins, maxs = Q.vec3(), Q.vec3()
	local h = E.CM_InlineModel(modelnum)
	E.CM_ModelBounds(h, mins, maxs)
	--if the model is rotated
	if angles[0] ~= 0 or angles[1] ~= 0 or angles[2] ~= 0 then
		-- expand for rotation
		local max = Q.RadiusFromBounds(mins, maxs)
		for i = 0, 2 do
			mins[i] = -max
			maxs[i] = max
		end
	end
	if outmins then
		Q.VectorCopy(mins, outmins)
	end
	if outmaxs then
		Q.VectorCopy(maxs, outmaxs)
	end
	if origin then
		Q.VectorClear(origin)
	end
end

--==================
-- BotImport_DebugPolygonCreate
--==================
local function BotImport_DebugPolygonCreate(color: number, numPoints: number, points): number
	if debugpolygons == nil then
		return 0
	end
	local i = 1
	while i < bot_maxdebugpolys do
		if not debugpolygons[i].inuse then
			break
		end
		i += 1
	end
	if i >= bot_maxdebugpolys then
		return 0
	end
	local poly = debugpolygons[i]
	poly.inuse = true
	poly.color = color
	poly.numPoints = numPoints
	poly.points = {}
	for j = 0, numPoints - 1 do
		poly.points[j] = { [0] = points[j][0], points[j][1], points[j][2] }
	end
	return i
end

--==================
-- BotImport_DebugPolygonShow
--==================
local function BotImport_DebugPolygonShow(id: number, color: number, numPoints: number, points)
	if debugpolygons == nil then
		return
	end
	local poly = debugpolygons[id]
	poly.inuse = true
	poly.color = color
	poly.numPoints = numPoints
	poly.points = {}
	for j = 0, numPoints - 1 do
		poly.points[j] = { [0] = points[j][0], points[j][1], points[j][2] }
	end
end

--==================
-- BotImport_DebugPolygonDelete
--==================
local function BotImport_DebugPolygonDelete(id: number)
	if debugpolygons == nil then
		return
	end
	debugpolygons[id].inuse = false
end

--==================
-- BotImport_DebugLineCreate
--==================
local function BotImport_DebugLineCreate(): number
	return BotImport_DebugPolygonCreate(0, 0, {})
end

--==================
-- BotImport_DebugLineDelete
--==================
local function BotImport_DebugLineDelete(line: number)
	BotImport_DebugPolygonDelete(line)
end

--==================
-- BotImport_DebugLineShow
--==================
local function BotImport_DebugLineShow(line: number, start, end_, color: number)
	local points = { [0] = Q.vec3(), Q.vec3(), Q.vec3(), Q.vec3() }
	local dir, cross, up = Q.vec3(), Q.vec3(), { [0] = 0, 0, 1 }
	local dot

	Q.VectorCopy(start, points[0])
	Q.VectorCopy(start, points[1])
	--points[1][2] -= 2;
	Q.VectorCopy(end_, points[2])
	--points[2][2] -= 2;
	Q.VectorCopy(end_, points[3])

	Q.VectorSubtract(end_, start, dir)
	Q.VectorNormalize(dir)
	dot = Q.DotProduct(dir, up)
	if dot > 0.99 or dot < -0.99 then
		Q.VectorSet(cross, 1, 0, 0)
	else
		Q.CrossProduct(dir, up, cross)
	end

	Q.VectorNormalize(cross)

	Q.VectorMA(points[0], 2, cross, points[0])
	Q.VectorMA(points[1], -2, cross, points[1])
	Q.VectorMA(points[2], -2, cross, points[2])
	Q.VectorMA(points[3], 2, cross, points[3])

	BotImport_DebugPolygonShow(line, color, 4, points)
end

--==================
-- SV_BotClientCommand
--==================
local function BotClientCommand(client: number, command: string)
	E.SV_ExecuteClientCommand(client, command, true)
end

--==================
-- SV_BotFrame
--==================
function SVB.SV_BotFrame(time: number)
	if SVB.bot_enable == 0 then
		return
	end
	--NOTE: maybe the game is already shutdown
	if not E.GameRunning() then
		return
	end
	E.VM_Call_BotAIStartFrame(time)
end

--===============
-- SV_BotLibSetup
--===============
function SVB.SV_BotLibSetup(): number
	if SVB.bot_enable == 0 then
		return 0
	end

	if not SVB.botlib_export then
		E.Com_Printf("^1Error: SV_BotLibSetup without SV_BotInitBotLib\n")
		return -1
	end

	SVB.botlib_export.BotLibVarSet("basegame", E.Cvar_VariableString("com_basegame"))

	return SVB.botlib_export.BotLibSetup()
end

--===============
-- SV_ShutdownBotLib
--
-- Called when either the entire server is being killed, or
-- it is changing to a different game directory.
--===============
function SVB.SV_BotLibShutdown(): number
	if not SVB.botlib_export then
		return -1
	end

	return SVB.botlib_export.BotLibShutdown()
end

--==================
-- SV_BotInitCvars
--==================
function SVB.SV_BotInitCvars()
	E.Cvar_Get("bot_enable", "1", 0) --enable the bot
	E.Cvar_Get("bot_developer", "0", BC.CVAR_CHEAT) --bot developer mode
	E.Cvar_Get("bot_debug", "0", BC.CVAR_CHEAT) --enable bot debugging
	E.Cvar_Get("bot_maxdebugpolys", "2", 0) --maximum number of debug polys
	E.Cvar_Get("bot_groundonly", "1", 0) --only show ground faces of areas
	E.Cvar_Get("bot_reachability", "0", 0) --show all reachabilities to other areas
	E.Cvar_Get("bot_visualizejumppads", "0", BC.CVAR_CHEAT) --show jumppads
	E.Cvar_Get("bot_forceclustering", "0", 0) --force cluster calculations
	E.Cvar_Get("bot_forcereachability", "0", 0) --force reachability calculations
	E.Cvar_Get("bot_forcewrite", "0", 0) --force writing aas file
	E.Cvar_Get("bot_aasoptimize", "0", 0) --no aas file optimisation
	E.Cvar_Get("bot_saveroutingcache", "0", 0) --save routing cache
	E.Cvar_Get("bot_thinktime", "100", BC.CVAR_CHEAT) --msec the bots thinks
	E.Cvar_Get("bot_reloadcharacters", "0", 0) --reload the bot characters each time
	E.Cvar_Get("bot_testichat", "0", 0) --test ichats
	E.Cvar_Get("bot_testrchat", "0", 0) --test rchats
	E.Cvar_Get("bot_testsolid", "0", BC.CVAR_CHEAT) --test for solid areas
	E.Cvar_Get("bot_testclusters", "0", BC.CVAR_CHEAT) --test the AAS clusters
	E.Cvar_Get("bot_fastchat", "0", 0) --fast chatting bots
	E.Cvar_Get("bot_nochat", "0", 0) --disable chats
	E.Cvar_Get("bot_pause", "0", BC.CVAR_CHEAT) --pause the bots thinking
	E.Cvar_Get("bot_report", "0", BC.CVAR_CHEAT) --get a full report in ctf
	E.Cvar_Get("bot_grapple", "0", 0) --enable grapple
	E.Cvar_Get("bot_rocketjump", "1", 0) --enable rocket jumping
	E.Cvar_Get("bot_challenge", "0", 0) --challenging bot
	E.Cvar_Get("bot_minplayers", "0", 0) --minimum players in a team or the game
	E.Cvar_Get("bot_interbreedchar", "", BC.CVAR_CHEAT) --bot character used for interbreeding
	E.Cvar_Get("bot_interbreedbots", "10", BC.CVAR_CHEAT) --number of bots used for interbreeding
	E.Cvar_Get("bot_interbreedcycle", "20", BC.CVAR_CHEAT) --bot interbreeding cycle
	E.Cvar_Get("bot_interbreedwrite", "", BC.CVAR_CHEAT) --write interbreeded bots to this file
end

--==================
-- SV_BotInitBotLib
--==================
function SVB.SV_BotInitBotLib()
	bot_maxdebugpolys = E.Cvar_VariableIntegerValue("bot_maxdebugpolys")
	debugpolygons = {}
	for i = 0, bot_maxdebugpolys - 1 do
		(debugpolygons :: any)[i] = { inuse = false, color = 0, numPoints = 0, points = {} }
	end

	local botlib_import = {
		Print = BotImport_Print,
		Trace = BotImport_Trace,
		EntityTrace = BotImport_EntityTrace,
		PointContents = BotImport_PointContents,
		inPVS = BotImport_inPVS,
		BSPEntityData = BotImport_BSPEntityData,
		BSPModelMinsMaxsOrigin = BotImport_BSPModelMinsMaxsOrigin,
		BotClientCommand = BotClientCommand,
		--memory management: the Luau heap (Z_AvailableMemory has no equivalent)
		AvailableMemory = function(): number
			return 256 * 1024 * 1024
		end,
		-- file system access: whole files (botfiles/*, maps/*.aas)
		FS_ReadFile = function(path: string): buffer?
			return E.FS_ReadFile(path)
		end,
		Sys_MilliSeconds = function(): number
			return E.Sys_Milliseconds()
		end,
		--debug lines
		DebugLineCreate = BotImport_DebugLineCreate,
		DebugLineDelete = BotImport_DebugLineDelete,
		DebugLineShow = BotImport_DebugLineShow,
		--debug polygons
		DebugPolygonCreate = BotImport_DebugPolygonCreate,
		DebugPolygonDelete = BotImport_DebugPolygonDelete,
	}

	SVB.botlib_export = B.GetBotLibAPI(BC.BOTLIB_API_VERSION, botlib_import)
	assert(SVB.botlib_export) -- somehow we end up with a zero import.
end

--
--  * * * BOT AI CODE IS BELOW THIS POINT * * *
--

--==================
-- SV_BotGetConsoleMessage
--==================
function SVB.SV_BotGetConsoleMessage(client: number, size: number): (boolean, string?)
	local cl = E.GetClient(client)
	cl.lastPacketTime = E.svsTime()

	if cl.reliableAcknowledge == cl.reliableSequence then
		return false, nil
	end

	cl.reliableAcknowledge += 1
	local index = bit32.band(cl.reliableAcknowledge, E.MAX_RELIABLE_COMMANDS - 1)

	local cmd = cl.reliableCommands[index]
	if cmd == nil or cmd == "" then
		return false, nil
	end

	return true, QS.Q_strncpyz(cmd, size)
end

--==================
-- SV_BotGetSnapshotEntity
--==================
function SVB.SV_BotGetSnapshotEntity(client: number, sequence: number): number
	local cl = E.GetClient(client)
	local frame = cl.frames[bit32.band(cl.outgoingSequence, E.PACKET_MASK)]
	if sequence < 0 or sequence >= frame.num_entities then
		return -1
	end
	return E.SnapshotEntityNumber(frame, sequence)
end

--==================
-- BOTLIB_USER_COMMAND (sv_game.c)
--==================
function SVB.SV_BotUserCommand(clientNum: number, ucmd)
	if clientNum >= 0 and clientNum < E.Cvar_VariableIntegerValue("sv_maxclients") then
		E.SV_ClientThink(clientNum, ucmd)
	end
end

-- SV_InitGameProgs: bot_enable latches when the game module is created
function SVB.SV_InitGameProgs()
	local var = E.Cvar_Get("bot_enable", "1", BC.CVAR_LATCH)
	if var then
		SVB.bot_enable = var.integer
	else
		SVB.bot_enable = 0
	end
end

return SVB
