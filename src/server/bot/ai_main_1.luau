--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_main.c, part 1 of 3).

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
-- Luau port of OpenArena 0.8.8's ai_main.c (gamecode 9e0f0c0), part 1 of 3. Bot AI entry: globals, print/trace/state helpers, status reports.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_main")

local S_COLOR_RED = "^1"
local S_COLOR_YELLOW = "^3"
local S_COLOR_BLUE = "^4"

SF.MAX_PATH = 144

--bot states
G.botstates = {}
--number of bots
G.numbots = 0
--floating point time
G.floattime = 0
--time to do a regular update
G.regularupdate_time = 0
--
G.bot_interbreed = 0
G.bot_interbreedmatchcount = 0
--
G.bot_thinktime = S.vmCvar_t()
G.bot_memorydump = S.vmCvar_t()
G.bot_saveroutingcache = S.vmCvar_t()
G.bot_pause = S.vmCvar_t()
G.bot_report = S.vmCvar_t()
G.bot_testsolid = S.vmCvar_t()
G.bot_testclusters = S.vmCvar_t()
G.bot_developer = S.vmCvar_t()
G.bot_interbreedchar = S.vmCvar_t()
G.bot_interbreedbots = S.vmCvar_t()
G.bot_interbreedcycle = S.vmCvar_t()
G.bot_interbreedwrite = S.vmCvar_t()

--[[
==================
BotAI_Print
==================
]]
function G.BotAI_Print(type_, fmt, ...)
	local str = QS.va(fmt, ...)

	if type_ == C.PRT_MESSAGE then
		G.G_Printf("%s", str)
	elseif type_ == C.PRT_WARNING then
		G.G_Printf(S_COLOR_YELLOW .. "Warning: %s", str)
	elseif type_ == C.PRT_ERROR then
		G.G_Printf(S_COLOR_RED .. "Error: %s", str)
	elseif type_ == C.PRT_FATAL then
		G.G_Printf(S_COLOR_RED .. "Fatal: %s", str)
	elseif type_ == C.PRT_EXIT then
		G.G_Error(S_COLOR_RED .. "Exit: %s", str)
	else
		G.G_Printf("unknown print type\n")
	end
end

--[[
==================
BotAI_Trace
==================
]]
function G.BotAI_Trace(bsptrace, start, mins, maxs, end_, passent, contentmask)
	local trace = S.trace_t()

	G.trap_Trace(trace, start, mins, maxs, end_, passent, contentmask)
	--copy the trace information
	bsptrace.allsolid = trace.allsolid
	bsptrace.startsolid = trace.startsolid
	bsptrace.fraction = trace.fraction
	Q.VectorCopy(trace.endpos, bsptrace.endpos)
	bsptrace.plane.dist = trace.plane.dist
	Q.VectorCopy(trace.plane.normal, bsptrace.plane.normal)
	bsptrace.plane.signbits = trace.plane.signbits
	bsptrace.plane.type = trace.plane.type
	bsptrace.surface.value = trace.surfaceFlags
	bsptrace.ent = trace.entityNum
	bsptrace.exp_dist = 0
	bsptrace.sidenum = 0
	bsptrace.contents = 0
end

--[[
==================
BotAI_GetClientState
==================
]]
function G.BotAI_GetClientState(clientNum, state)
	local ent = G.g_entities[clientNum]
	if not ent.inuse then
		return 0
	end
	if ent.client == nil then
		return 0
	end

	S.copy_playerState_t(state, ent.client.ps)
	return 1
end

--[[
==================
BotAI_GetEntityState
==================
]]
function G.BotAI_GetEntityState(entityNum, state)
	local ent = G.g_entities[entityNum]
	S.copy_entityState_t(state, S.entityState_t())
	if not ent.inuse then return 0 end
	if not ent.r.linked then return 0 end
	if not (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_LMS or G.g_instantgib.integer ~= 0 or G.g_rockets.integer ~= 0 or G.g_elimination_allgametypes.integer ~= 0 or G.g_gametype.integer == C.GT_CTF_ELIMINATION)
		and bit32.band(ent.r.svFlags, C.SVF_NOCLIENT) ~= 0 then
		return 0
	end
	S.copy_entityState_t(state, ent.s)
	return 1
end

--[[
==================
BotAI_GetSnapshotEntity
==================
]]
function G.BotAI_GetSnapshotEntity(clientNum, sequence, state)
	local entNum = G.trap_BotGetSnapshotEntity(clientNum, sequence)
	if entNum == -1 then
		S.copy_entityState_t(state, S.entityState_t())
		return -1
	end

	G.BotAI_GetEntityState(entNum, state)

	return sequence + 1
end

--[[
==================
BotAI_BotInitialChat
==================
]]
function G.BotAI_BotInitialChat(bs, type_, ...)
	local vars = {}
	local n = select("#", ...)

	for i = 0, C.MAX_MATCHVARIABLES - 1 do
		if i >= n then
			break
		end
		local p = select(i + 1, ...)
		if p == nil then
			break
		end
		vars[i] = p
	end

	local mcontext = G.BotSynonymContext(bs)

	G.trap_BotInitialChat(bs.cs, type_, mcontext, vars[0], vars[1], vars[2], vars[3], vars[4], vars[5], vars[6], vars[7])
end

--[[
==================
BotTestAAS
==================
]]
function G.BotTestAAS(origin)
	local info = S.aas_areainfo_t()

	G.trap_Cvar_Update(G.bot_testsolid)
	G.trap_Cvar_Update(G.bot_testclusters)
	if G.bot_testsolid.integer ~= 0 then
		if not G.trap_AAS_Initialized() then return end
		local areanum = G.BotPointAreaNum(origin)
		if areanum ~= 0 then G.BotAI_Print(C.PRT_MESSAGE, "\rempty area")
		else G.BotAI_Print(C.PRT_MESSAGE, "\r^1SOLID area") end
	elseif G.bot_testclusters.integer ~= 0 then
		if not G.trap_AAS_Initialized() then return end
		local areanum = G.BotPointAreaNum(origin)
		if areanum == 0 then
			G.BotAI_Print(C.PRT_MESSAGE, "\r^1Solid!                              ")
		else
			G.trap_AAS_AreaInfo(areanum, info)
			G.BotAI_Print(C.PRT_MESSAGE, "\rarea %d, cluster %d       ", areanum, info.cluster)
		end
	end
end

--[[
==================
BotReportStatus
==================
]]
function G.BotReportStatus(bs)
	local goalname
	local netname = G.ClientName(bs.client, C.MAX_MESSAGE_SIZE)
	local leader
	local flagstatus
	if QS.Q_stricmp(netname, bs.teamleader) == 0 then
		leader = "L"
	else
		leader = " "
	end

	flagstatus = "  "
	local gametype = G.gametype
	if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION then
		if G.BotCTFCarryingFlag(bs) ~= 0 then
			if G.BotTeam(bs) == C.TEAM_RED then flagstatus = S_COLOR_RED .. "F "
			else flagstatus = S_COLOR_BLUE .. "F " end
		end
	elseif gametype == C.GT_1FCTF then
		if G.Bot1FCTFCarryingFlag(bs) ~= 0 then
			if G.BotTeam(bs) == C.TEAM_RED then flagstatus = S_COLOR_RED .. "F "
			else flagstatus = S_COLOR_BLUE .. "F " end
		end
	elseif gametype == C.GT_HARVESTER then
		if G.BotHarvesterCarryingCubes(bs) ~= 0 then
			if G.BotTeam(bs) == C.TEAM_RED then flagstatus = QS.Com_sprintf(32, S_COLOR_RED .. "%2d", bs.inventory[C.INVENTORY_REDCUBE])
			else flagstatus = QS.Com_sprintf(32, S_COLOR_BLUE .. "%2d", bs.inventory[C.INVENTORY_BLUECUBE]) end
		end
	end

	local ltgtype = bs.ltgtype
	if ltgtype == C.LTG_TEAMHELP then
		goalname = G.EasyClientName(bs.teammate, C.MAX_MESSAGE_SIZE)
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: helping %s\n", netname, leader, flagstatus, goalname)
	elseif ltgtype == C.LTG_TEAMACCOMPANY then
		goalname = G.EasyClientName(bs.teammate, C.MAX_MESSAGE_SIZE)
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: accompanying %s\n", netname, leader, flagstatus, goalname)
	elseif ltgtype == C.LTG_DEFENDKEYAREA then
		goalname = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: defending %s\n", netname, leader, flagstatus, goalname)
	elseif ltgtype == C.LTG_GETITEM then
		goalname = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: getting item %s\n", netname, leader, flagstatus, goalname)
	elseif ltgtype == C.LTG_KILL then
		goalname = G.ClientName(bs.teamgoal.entitynum, C.MAX_MESSAGE_SIZE)
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: killing %s\n", netname, leader, flagstatus, goalname)
	elseif ltgtype == C.LTG_CAMP or ltgtype == C.LTG_CAMPORDER then
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: camping\n", netname, leader, flagstatus)
	elseif ltgtype == C.LTG_PATROL then
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: patrolling\n", netname, leader, flagstatus)
	elseif ltgtype == C.LTG_GETFLAG then
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: capturing flag\n", netname, leader, flagstatus)
	elseif ltgtype == C.LTG_RUSHBASE then
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: rushing base\n", netname, leader, flagstatus)
	elseif ltgtype == C.LTG_RETURNFLAG then
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: returning flag\n", netname, leader, flagstatus)
	elseif ltgtype == C.LTG_ATTACKENEMYBASE then
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: attacking the enemy base\n", netname, leader, flagstatus)
	elseif ltgtype == C.LTG_HARVEST then
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: harvesting\n", netname, leader, flagstatus)
	elseif ltgtype == C.LTG_POINTA then
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: going for point A\n", netname, leader, flagstatus)
	elseif ltgtype == C.LTG_POINTB then
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: going for point B\n", netname, leader, flagstatus)
	else
		G.BotAI_Print(C.PRT_MESSAGE, "%-20s%s%s: roaming\n", netname, leader, flagstatus)
	end
end

--[[
==================
BotTeamplayReport
==================
]]
function G.BotTeamplayReport()
	G.BotAI_Print(C.PRT_MESSAGE, S_COLOR_RED .. "RED\n")
	for i = 0, math.min(G.maxclients, C.MAX_CLIENTS) - 1 do
		--
		local b = G.botstates[i]
		if b ~= nil and b.inuse ~= 0 then
			local buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
			--if no config string or no name
			if not (#buf == 0 or #QS.Info_ValueForKey(buf, "n") == 0) then
				--skip spectators
				if QS.atoi(QS.Info_ValueForKey(buf, "t")) == C.TEAM_RED then
					G.BotReportStatus(b)
				end
			end
		end
	end
	G.BotAI_Print(C.PRT_MESSAGE, S_COLOR_BLUE .. "BLUE\n")
	for i = 0, math.min(G.maxclients, C.MAX_CLIENTS) - 1 do
		--
		local b = G.botstates[i]
		if b ~= nil and b.inuse ~= 0 then
			local buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
			--if no config string or no name
			if not (#buf == 0 or #QS.Info_ValueForKey(buf, "n") == 0) then
				--skip spectators
				if QS.atoi(QS.Info_ValueForKey(buf, "t")) == C.TEAM_BLUE then
					G.BotReportStatus(b)
				end
			end
		end
	end
end

--[[
==================
BotSetInfoConfigString
==================
]]
function G.BotSetInfoConfigString(bs)
	local goalname
	local action
	local goal = S.bot_goal_t()
	local leader
	local carrying
	--
	local netname = G.ClientName(bs.client, C.MAX_MESSAGE_SIZE)
	if QS.Q_stricmp(netname, bs.teamleader) == 0 then
		leader = "L"
	else
		leader = " "
	end

	carrying = "  "
	local gametype = G.gametype
	if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION then
		if G.BotCTFCarryingFlag(bs) ~= 0 then
			carrying = "F "
		end
	elseif gametype == C.GT_1FCTF then
		if G.Bot1FCTFCarryingFlag(bs) ~= 0 then
			carrying = "F "
		end
	elseif gametype == C.GT_HARVESTER then
		if G.BotHarvesterCarryingCubes(bs) ~= 0 then
			if G.BotTeam(bs) == C.TEAM_RED then carrying = QS.Com_sprintf(32, "%2d", bs.inventory[C.INVENTORY_REDCUBE])
			else carrying = QS.Com_sprintf(32, "%2d", bs.inventory[C.INVENTORY_BLUECUBE]) end
		end
	end

	local ltgtype = bs.ltgtype
	if ltgtype == C.LTG_TEAMHELP then
		goalname = G.EasyClientName(bs.teammate, C.MAX_MESSAGE_SIZE)
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "helping %s", goalname)
	elseif ltgtype == C.LTG_TEAMACCOMPANY then
		goalname = G.EasyClientName(bs.teammate, C.MAX_MESSAGE_SIZE)
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "accompanying %s", goalname)
	elseif ltgtype == C.LTG_DEFENDKEYAREA then
		goalname = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "defending %s", goalname)
	elseif ltgtype == C.LTG_GETITEM then
		goalname = G.trap_BotGoalName(bs.teamgoal.number, C.MAX_MESSAGE_SIZE)
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "getting item %s", goalname)
	elseif ltgtype == C.LTG_KILL then
		goalname = G.ClientName(bs.teamgoal.entitynum, C.MAX_MESSAGE_SIZE)
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "killing %s", goalname)
	elseif ltgtype == C.LTG_CAMP or ltgtype == C.LTG_CAMPORDER then
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "camping")
	elseif ltgtype == C.LTG_PATROL then
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "patrolling")
	elseif ltgtype == C.LTG_GETFLAG then
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "capturing flag")
	elseif ltgtype == C.LTG_RUSHBASE then
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "rushing base")
	elseif ltgtype == C.LTG_RETURNFLAG then
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "returning flag")
	elseif ltgtype == C.LTG_ATTACKENEMYBASE then
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "attacking the enemy base")
	elseif ltgtype == C.LTG_HARVEST then
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "harvesting")
	elseif ltgtype == C.LTG_POINTA then
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "going for point A")
	elseif ltgtype == C.LTG_POINTB then
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "going for point B")
	else
		G.trap_BotGetTopGoal(bs.gs, goal)
		goalname = G.trap_BotGoalName(goal.number, C.MAX_MESSAGE_SIZE)
		action = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "roaming %s", goalname)
	end
	local cs = QS.va("l\\%s\\c\\%s\\a\\%s",
		leader,
		carrying,
		action)
	G.trap_SetConfigstring(C.CS_BOTINFO + bs.client, cs)
end

--[[
==============
BotUpdateInfoConfigStrings
==============
]]
function G.BotUpdateInfoConfigStrings()
	for i = 0, math.min(G.maxclients, C.MAX_CLIENTS) - 1 do
		--
		local b = G.botstates[i]
		if b ~= nil and b.inuse ~= 0 then
			local buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
			--if no config string or no name
			if not (#buf == 0 or #QS.Info_ValueForKey(buf, "n") == 0) then
				G.BotSetInfoConfigString(b)
			end
		end
	end
end

return nil
