--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_dmq3.c, part 7 of 7).

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
-- Luau port of OpenArena 0.8.8's ai_dmq3.c (gamecode 9e0f0c0), part 7 of 7. Event checks, alternate routes, deathmatch AI frame and setup.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmq3")

local MAX_ALTROUTEGOALS = 32

function G.BotCheckForGrenades(bs, state)
	if state.eType ~= C.ET_MISSILE or state.weapon ~= C.WP_GRENADE_LAUNCHER then
		return
	end
	G.trap_BotAddAvoidSpot(bs.ms, state.pos.trBase, 160, C.AVOID_ALWAYS)
end

function G.BotCheckForProxMines(bs, state)
	if state.eType ~= C.ET_MISSILE or state.weapon ~= C.WP_PROX_LAUNCHER then
		return
	end
	if state.generic1 == G.BotTeam(bs) then
		return
	end
	if not (bs.inventory[C.INVENTORY_PLASMAGUN] > 0 and bs.inventory[C.INVENTORY_CELLS] > 0)
		and not (bs.inventory[C.INVENTORY_ROCKETLAUNCHER] > 0 and bs.inventory[C.INVENTORY_ROCKETS] > 0)
		and not (bs.inventory[C.INVENTORY_BFG10K] > 0 and bs.inventory[C.INVENTORY_BFGAMMO] > 0) then
		return
	end
	G.trap_BotAddAvoidSpot(bs.ms, state.pos.trBase, 160, C.AVOID_ALWAYS)
	if bs.numproxmines >= C.MAX_PROXMINES then
		return
	end
	bs.proxmines[bs.numproxmines] = state.number
	bs.numproxmines += 1
end

function G.BotCheckForKamikazeBody(bs, state)
	if bit32.band(state.eFlags, C.EF_KAMIKAZE) == 0 then
		return
	end
	if bit32.band(state.eFlags, C.EF_DEAD) == 0 then
		return
	end
	bs.kamikazebody = state.number
end

function G.BotCheckEvents(bs, state)
	local event
	local buf
	local entinfo = S.aas_entityinfo_t()

	if bs.entityeventTime[state.number] == G.g_entities[state.number].eventTime then
		return
	end
	bs.entityeventTime[state.number] = G.g_entities[state.number].eventTime
	if state.eType > C.ET_EVENTS then
		event = bit32.band(state.eType - C.ET_EVENTS, bit32.bnot(C.EV_EVENT_BITS))
	else
		event = bit32.band(state.event, bit32.bnot(C.EV_EVENT_BITS))
	end
	if event == C.EV_OBITUARY then
		local target = state.otherEntityNum
		local attacker = state.otherEntityNum2
		local mod = state.eventParm
		if target == bs.client then
			bs.botdeathtype = mod
			bs.lastkilledby = attacker
			if target == attacker or target == C.ENTITYNUM_NONE or target == C.ENTITYNUM_WORLD then
				bs.botsuicide = true
			else
				bs.botsuicide = false
			end
			bs.num_deaths += 1
		elseif attacker == bs.client then
			bs.enemydeathtype = mod
			bs.lastkilledplayer = target
			bs.killedenemy_time = G.floattime
			bs.num_kills += 1
		elseif attacker == bs.enemy and target == attacker then
			bs.enemysuicide = true
		end
		if G.gametype == C.GT_1FCTF then
			G.BotEntityInfo(target, entinfo)
			if bit32.band(entinfo.powerups, bit32.lshift(1, C.PW_NEUTRALFLAG)) ~= 0 then
				if G.BotSameTeam(bs, target) == 0 then
					bs.neutralflagstatus = 3
					bs.flagstatuschanged = true
				end
			end
		end
	elseif event == C.EV_GLOBAL_SOUND then
		if state.eventParm < 0 or state.eventParm > C.MAX_SOUNDS then
			G.BotAI_Print(C.PRT_ERROR, "EV_GLOBAL_SOUND: eventParm (%d) out of range\n", state.eventParm)
			return
		end
		buf = G.trap_GetConfigstring(C.CS_SOUNDS + state.eventParm)
		if buf == "sound/items/kamikazerespawn.wav" then
			G.BotDontAvoid(bs, "Kamikaze")
		elseif buf == "sound/items/poweruprespawn.wav" then
			G.BotGoForPowerups(bs)
		end
	elseif event == C.EV_GLOBAL_TEAM_SOUND then
		if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
			local p = state.eventParm
			if p == C.GTS_RED_CAPTURE then
				bs.blueflagstatus = 0
				bs.redflagstatus = 0
				bs.flagstatuschanged = true
			elseif p == C.GTS_BLUE_CAPTURE then
				bs.blueflagstatus = 0
				bs.redflagstatus = 0
				bs.flagstatuschanged = true
			elseif p == C.GTS_RED_RETURN then
				bs.blueflagstatus = 0
				bs.flagstatuschanged = true
			elseif p == C.GTS_BLUE_RETURN then
				bs.redflagstatus = 0
				bs.flagstatuschanged = true
			elseif p == C.GTS_RED_TAKEN then
				bs.blueflagstatus = 1
				bs.flagstatuschanged = true
			elseif p == C.GTS_BLUE_TAKEN then
				bs.redflagstatus = 1
				bs.flagstatuschanged = true
			end
		elseif G.gametype == C.GT_1FCTF then
			local p = state.eventParm
			if p == C.GTS_RED_CAPTURE then
				bs.neutralflagstatus = 0
				bs.flagstatuschanged = true
			elseif p == C.GTS_BLUE_CAPTURE then
				bs.neutralflagstatus = 0
				bs.flagstatuschanged = true
			elseif p == C.GTS_RED_RETURN then
				bs.neutralflagstatus = 0
				bs.flagstatuschanged = true
			elseif p == C.GTS_BLUE_RETURN then
				bs.neutralflagstatus = 0
				bs.flagstatuschanged = true
			elseif p == C.GTS_RED_TAKEN then
				bs.neutralflagstatus = if G.BotTeam(bs) == C.TEAM_RED then 2 else 1
				bs.flagstatuschanged = true
			elseif p == C.GTS_BLUE_TAKEN then
				bs.neutralflagstatus = if G.BotTeam(bs) == C.TEAM_BLUE then 2 else 1
				bs.flagstatuschanged = true
			end
		end
	elseif event == C.EV_PLAYER_TELEPORT_IN then
		Q.VectorCopy(state.origin, G.lastteleport_origin)
		G.lastteleport_time = G.floattime
	elseif event == C.EV_GENERAL_SOUND then
		if state.number == bs.client then
			if state.eventParm < 0 or state.eventParm > C.MAX_SOUNDS then
				G.BotAI_Print(C.PRT_ERROR, "EV_GENERAL_SOUND: eventParm (%d) out of range\n", state.eventParm)
				return
			end
			buf = G.trap_GetConfigstring(C.CS_SOUNDS + state.eventParm)
			if buf == "*falling1.wav" then
				if bs.inventory[C.INVENTORY_TELEPORTER] > 0 then
					G.trap_EA_Use(bs.client)
				end
			end
		end
	end
end

function G.BotCheckSnapshot(bs)
	local ent
	local state = S.entityState_t()

	G.trap_BotAddAvoidSpot(bs.ms, Q.vec3_origin, 0, C.AVOID_CLEAR)
	bs.kamikazebody = 0
	bs.numproxmines = 0
	ent = 0
	while true do
		ent = G.BotAI_GetSnapshotEntity(bs.client, ent, state)
		if ent == -1 then
			break
		end
		G.BotCheckEvents(bs, state)
		G.BotCheckForGrenades(bs, state)
		G.BotCheckForProxMines(bs, state)
		G.BotCheckForKamikazeBody(bs, state)
	end
	G.BotAI_GetEntityState(bs.client, state)
	state.event = bs.cur_ps.externalEvent
	state.eventParm = bs.cur_ps.externalEventParm
	G.BotCheckEvents(bs, state)
end

function G.BotCheckAir(bs)
	if bs.inventory[C.INVENTORY_ENVIRONMENTSUIT] <= 0 then
		if bit32.band(G.trap_AAS_PointContents(bs.eye), bit32.bor(C.CONTENTS_WATER, C.CONTENTS_SLIME, C.CONTENTS_LAVA)) ~= 0 then
			return
		end
	end
	bs.lastair_time = G.floattime
end

function G.BotAlternateRoute(bs, goal)
	if bs.altroutegoal.areanum ~= 0 then
		if bs.reachedaltroutegoal_time ~= 0 then
			return goal
		end
		local t = G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin, bs.altroutegoal.areanum, bs.tfl)
		if t ~= 0 and t < 20 then
			bs.reachedaltroutegoal_time = G.floattime
		end
		S.copy_bot_goal_t(goal, bs.altroutegoal)
		return bs.altroutegoal
	end
	return goal
end

function G.BotGetAlternateRouteGoal(bs, base)
	local altroutegoals
	local numaltroutegoals

	if base == C.TEAM_RED then
		altroutegoals = G.red_altroutegoals
		numaltroutegoals = G.red_numaltroutegoals
	else
		altroutegoals = G.blue_altroutegoals
		numaltroutegoals = G.blue_numaltroutegoals
	end
	if numaltroutegoals == 0 then
		return 0
	end
	local rnd = Q.trunc(Q.random() * numaltroutegoals)
	if rnd >= numaltroutegoals then
		rnd = numaltroutegoals - 1
	end
	local goal = bs.altroutegoal
	goal.areanum = altroutegoals[rnd].areanum
	Q.VectorCopy(altroutegoals[rnd].origin, goal.origin)
	Q.VectorSet(goal.mins, -8, -8, -8)
	Q.VectorSet(goal.maxs, 8, 8, 8)
	goal.entitynum = 0
	goal.iteminfo = 0
	goal.number = 0
	goal.flags = 0
	bs.reachedaltroutegoal_time = 0
	return 1
end

function G.BotSetupAlternativeRouteGoals()
	local flags = bit32.bor(C.ALTROUTEGOAL_CLUSTERPORTALS, C.ALTROUTEGOAL_VIEWPORTALS)

	if G.altroutegoals_setup ~= 0 and G.altroutegoals_setup ~= false then
		return
	end
	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
		if G.trap_BotGetLevelItemGoal(-1, "Neutral Flag", G.ctf_neutralflag) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "No alt routes without Neutral Flag\n")
		end
		if G.ctf_neutralflag.areanum ~= 0 then
			G.red_numaltroutegoals = G.trap_AAS_AlternativeRouteGoals(
				G.ctf_neutralflag.origin, G.ctf_neutralflag.areanum,
				G.ctf_redflag.origin, G.ctf_redflag.areanum, C.TFL_DEFAULT,
				G.red_altroutegoals, MAX_ALTROUTEGOALS, flags)
			G.blue_numaltroutegoals = G.trap_AAS_AlternativeRouteGoals(
				G.ctf_neutralflag.origin, G.ctf_neutralflag.areanum,
				G.ctf_blueflag.origin, G.ctf_blueflag.areanum, C.TFL_DEFAULT,
				G.blue_altroutegoals, MAX_ALTROUTEGOALS, flags)
		end
	elseif G.gametype == C.GT_1FCTF then
		if G.trap_BotGetLevelItemGoal(-1, "Neutral Obelisk", G.neutralobelisk) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "One Flag CTF without Neutral Obelisk\n")
		end
		G.red_numaltroutegoals = G.trap_AAS_AlternativeRouteGoals(
			G.ctf_neutralflag.origin, G.ctf_neutralflag.areanum,
			G.ctf_redflag.origin, G.ctf_redflag.areanum, C.TFL_DEFAULT,
			G.red_altroutegoals, MAX_ALTROUTEGOALS, flags)
		G.blue_numaltroutegoals = G.trap_AAS_AlternativeRouteGoals(
			G.ctf_neutralflag.origin, G.ctf_neutralflag.areanum,
			G.ctf_blueflag.origin, G.ctf_blueflag.areanum, C.TFL_DEFAULT,
			G.blue_altroutegoals, MAX_ALTROUTEGOALS, flags)
	elseif G.gametype == C.GT_OBELISK then
		if G.trap_BotGetLevelItemGoal(-1, "Neutral Obelisk", G.neutralobelisk) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "Obelisk without neutral obelisk\n")
		end
		G.red_numaltroutegoals = G.trap_AAS_AlternativeRouteGoals(
			G.neutralobelisk.origin, G.neutralobelisk.areanum,
			G.redobelisk.origin, G.redobelisk.areanum, C.TFL_DEFAULT,
			G.red_altroutegoals, MAX_ALTROUTEGOALS, flags)
		G.blue_numaltroutegoals = G.trap_AAS_AlternativeRouteGoals(
			G.neutralobelisk.origin, G.neutralobelisk.areanum,
			G.blueobelisk.origin, G.blueobelisk.areanum, C.TFL_DEFAULT,
			G.blue_altroutegoals, MAX_ALTROUTEGOALS, flags)
	elseif G.gametype == C.GT_HARVESTER then
		if G.untrap_BotGetLevelItemGoal(-1, "Neutral Obelisk", G.neutralobelisk) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "Harvester without neutral obelisk\n")
		end
		G.red_numaltroutegoals = G.trap_AAS_AlternativeRouteGoals(
			G.neutralobelisk.origin, G.neutralobelisk.areanum,
			G.redobelisk.origin, G.redobelisk.areanum, C.TFL_DEFAULT,
			G.red_altroutegoals, MAX_ALTROUTEGOALS, flags)
		G.blue_numaltroutegoals = G.trap_AAS_AlternativeRouteGoals(
			G.neutralobelisk.origin, G.neutralobelisk.areanum,
			G.blueobelisk.origin, G.blueobelisk.areanum, C.TFL_DEFAULT,
			G.blue_altroutegoals, MAX_ALTROUTEGOALS, flags)
	end
	G.altroutegoals_setup = 1
end

function G.BotDeathmatchAI(bs, thinktime)
	local gender
	local name
	local userinfo

	if bs.setupcount > 0 then
		bs.setupcount -= 1
		if bs.setupcount > 0 then
			return
		end
		gender = G.trap_Characteristic_String(bs.character, C.CHARACTERISTIC_GENDER, 144)
		userinfo = G.trap_GetUserinfo(bs.client)
		userinfo = QS.Info_SetValueForKey(userinfo, "sex", gender)
		G.trap_SetUserinfo(bs.client, userinfo)
		if bs.map_restart == 0 and G.g_gametype.integer ~= C.GT_TOURNAMENT then
			G.trap_EA_Command(bs.client, string.format("team %s", bs.settings.team))
		end
		local g0 = string.sub(gender, 1, 1)
		if g0 == "m" then
			G.trap_BotSetChatGender(bs.cs, C.CHAT_GENDERMALE)
		elseif g0 == "f" then
			G.trap_BotSetChatGender(bs.cs, C.CHAT_GENDERFEMALE)
		else
			G.trap_BotSetChatGender(bs.cs, C.CHAT_GENDERLESS)
		end
		name = G.ClientName(bs.client, 144)
		G.trap_BotSetChatName(bs.cs, name, bs.client)
		bs.lastframe_health = bs.inventory[C.INVENTORY_HEALTH]
		bs.lasthitcount = bs.cur_ps.persistant[C.PERS_HITS]
		bs.setupcount = 0
		G.BotSetupAlternativeRouteGoals()
	end
	bs.flags = bit32.band(bs.flags, bit32.bnot(C.BFL_IDEALVIEWSET))
	if not G.BotIntermission(bs) then
		G.BotSetTeleportTime(bs)
		G.BotUpdateInventory(bs)
		G.BotCheckSnapshot(bs)
		G.BotCheckAir(bs)
	end
	G.BotCheckConsoleMessages(bs)
	if not G.BotIntermission(bs) and not G.BotIsObserver(bs) then
		G.BotTeamAI(bs)
	end
	if bs.ainode == nil then
		G.AIEnter_Seek_LTG(bs, "BotDeathmatchAI: no ai node")
	end
	if bs.entergamechat == 0 and bs.entergame_time > G.floattime - 8 then
		if G.BotChat_EnterGame(bs) ~= 0 then
			bs.stand_time = G.floattime + G.BotChatTime(bs)
			G.AIEnter_Stand(bs, "BotDeathmatchAI: chat enter game")
		end
		bs.entergamechat = 1
	end
	G.BotResetNodeSwitches()
	for _ = 0, C.MAX_NODESWITCHES - 1 do
		if bs.ainode(bs) ~= 0 then
			break
		end
	end
	if bs.inuse == 0 then
		return
	end
	bs.lastframe_health = bs.inventory[C.INVENTORY_HEALTH]
	bs.lasthitcount = bs.cur_ps.persistant[C.PERS_HITS]
end

function G.BotSetEntityNumForGoalWithModel(goal, eType, modelname)
	local dir = Q.vec3()
	local modelindex = G.G_ModelIndex(modelname)
	for i = 0, G.level.num_entities - 1 do
		local ent = G.g_entities[i]
		if not ent.inuse then
			continue
		end
		if eType ~= 0 and ent.s.eType ~= eType then
			continue
		end
		if ent.s.modelindex ~= modelindex then
			continue
		end
		Q.VectorSubtract(goal.origin, ent.s.origin, dir)
		if Q.DotProduct(dir, dir) < 100 then
			goal.entitynum = i
			return
		end
	end
end

function G.BotSetEntityNumForGoal(goal, classname)
	local dir = Q.vec3()
	for i = 0, G.level.num_entities - 1 do
		local ent = G.g_entities[i]
		if not ent.inuse then
			continue
		end
		if QS.Q_stricmp(ent.classname, classname) ~= 0 then
			continue
		end
		Q.VectorSubtract(goal.origin, ent.s.origin, dir)
		if Q.DotProduct(dir, dir) < 100 then
			goal.entitynum = i
			return
		end
	end
end

function G.BotGoalForBSPEntity(classname, goal)
	local origin = Q.vec3()
	local start = Q.vec3()
	local end_ = Q.vec3()
	local areas = {}

	S.copy_bot_goal_t(goal, S.bot_goal_t())
	local ent = G.trap_AAS_NextBSPEntity(0)
	while ent ~= 0 do
		local ok, value = G.trap_AAS_ValueForBSPEpairKey(ent, "classname", C.MAX_INFO_STRING)
		if ok ~= 0 and ok then
			if value == classname then
				local vok = G.trap_AAS_VectorForBSPEpairKey(ent, "origin", origin)
				if vok == 0 or not vok then
					return 0
				end
				Q.VectorCopy(origin, goal.origin)
				Q.VectorCopy(origin, start)
				start[2] -= 32
				Q.VectorCopy(origin, end_)
				end_[2] += 32
				local numareas = G.trap_AAS_TraceAreas(start, end_, areas, nil, 10)
				if numareas == 0 then
					return 0
				end
				goal.areanum = areas[0]
				return 1
			end
		end
		ent = G.trap_AAS_NextBSPEntity(ent)
	end
	return 0
end

function G.BotSetupDeathmatchAI()
	local ent
	local modelnum
	local model

	G.gametype = G.trap_Cvar_VariableIntegerValue("g_gametype")
	G.maxclients = G.trap_Cvar_VariableIntegerValue("sv_maxclients")

	G.trap_Cvar_Register(G.bot_rocketjump, "bot_rocketjump", "1", 0)
	G.trap_Cvar_Register(G.bot_grapple, "bot_grapple", "0", 0)
	G.trap_Cvar_Register(G.bot_fastchat, "bot_fastchat", "0", 0)
	G.trap_Cvar_Register(G.bot_nochat, "bot_nochat", "0", 0)
	G.trap_Cvar_Register(G.bot_testrchat, "bot_testrchat", "0", 0)
	G.trap_Cvar_Register(G.bot_challenge, "bot_challenge", "0", 0)
	G.trap_Cvar_Register(G.bot_predictobstacles, "bot_predictobstacles", "1", 0)
	G.trap_Cvar_Register(G.g_spSkill, "g_spSkill", "2", 0)
	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
		if G.untrap_BotGetLevelItemGoal(-1, "Red Flag", G.ctf_redflag) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "CTF without Red Flag\n")
		end
		if G.untrap_BotGetLevelItemGoal(-1, "Blue Flag", G.ctf_blueflag) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "CTF without Blue Flag\n")
		end
	elseif G.gametype == C.GT_DOUBLE_D then
		if G.untrap_BotGetLevelItemGoal(-1, "Red Flag", G.ctf_redflag) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "DD without Point A\n")
		end
		if G.untrap_BotGetLevelItemGoal(-1, "Blue Flag", G.ctf_blueflag) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "DD without Point B\n")
		end
	elseif G.gametype == C.GT_DOMINATION then
		ent = G.untrap_BotGetLevelItemGoal(-1, "Domination point", G.dom_points_bot[0])
		if ent < 0 then
			G.BotAI_Print(C.PRT_WARNING, "Domination without a single domination point\n")
		else
			G.BotSetEntityNumForGoal(G.dom_points_bot[0], QS.va("domination_point%i", 0))
		end
		for i = 1, G.level.domination_points_count - 1 do
			ent = G.untrap_BotGetLevelItemGoal(ent, "Domination point", G.dom_points_bot[i])
			if ent < 0 then
				G.BotAI_Print(C.PRT_WARNING, "Domination point %i not found!\n", i)
			else
				G.BotSetEntityNumForGoal(G.dom_points_bot[0], QS.va("domination_point%i", i))
			end
		end
	elseif G.gametype == C.GT_1FCTF then
		if G.untrap_BotGetLevelItemGoal(-1, "Neutral Flag", G.ctf_neutralflag) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "One Flag CTF without Neutral Flag\n")
		end
		if G.untrap_BotGetLevelItemGoal(-1, "Red Flag", G.ctf_redflag) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "CTF without Red Flag\n")
		end
		if G.untrap_BotGetLevelItemGoal(-1, "Blue Flag", G.ctf_blueflag) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "CTF without Blue Flag\n")
		end
	elseif G.gametype == C.GT_OBELISK then
		if G.untrap_BotGetLevelItemGoal(-1, "Red Obelisk", G.redobelisk) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "Obelisk without red obelisk\n")
		end
		G.BotSetEntityNumForGoal(G.redobelisk, "team_redobelisk")
		if G.untrap_BotGetLevelItemGoal(-1, "Blue Obelisk", G.blueobelisk) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "Obelisk without blue obelisk\n")
		end
		G.BotSetEntityNumForGoal(G.blueobelisk, "team_blueobelisk")
	elseif G.gametype == C.GT_HARVESTER then
		if G.untrap_BotGetLevelItemGoal(-1, "Red Obelisk", G.redobelisk) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "Harvester without red obelisk\n")
		end
		G.BotSetEntityNumForGoal(G.redobelisk, "team_redobelisk")
		if G.untrap_BotGetLevelItemGoal(-1, "Blue Obelisk", G.blueobelisk) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "Harvester without blue obelisk\n")
		end
		G.BotSetEntityNumForGoal(G.blueobelisk, "team_blueobelisk")
		if G.untrap_BotGetLevelItemGoal(-1, "Neutral Obelisk", G.neutralobelisk) < 0 then
			G.BotAI_Print(C.PRT_WARNING, "Harvester without neutral obelisk\n")
		end
		G.BotSetEntityNumForGoal(G.neutralobelisk, "team_neutralobelisk")
	end

	G.max_bspmodelindex = 0
	ent = G.trap_AAS_NextBSPEntity(0)
	while ent ~= 0 do
		local ok
		ok, model = G.trap_AAS_ValueForBSPEpairKey(ent, "model", 128)
		if ok ~= 0 and ok then
			if string.sub(model, 1, 1) == "*" then
				modelnum = QS.atoi(string.sub(model, 2))
				if modelnum > G.max_bspmodelindex then
					G.max_bspmodelindex = modelnum
				end
			end
		end
		ent = G.trap_AAS_NextBSPEntity(ent)
	end
	G.BotInitWaypoints()
end

function G.BotShutdownDeathmatchAI()
	G.altroutegoals_setup = 0
end

return nil
