--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_dmq3.c).

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
-- Luau port of OpenArena 0.8.8's ai_dmq3.c (gamecode 9e0f0c0), part 1 of 7. File-top declarations, team/flag helpers and CTF seek goals.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmq3")

-- from ui/menudef.h
local VOICECHAT_NO = "no"
local VOICECHAT_IHAVEFLAG = "ihaveflag"
local VOICECHAT_ONFOLLOW = "onfollow"

-- from aasfile.h
SF.AREACONTENTS_MOVER = 1024
SF.AREACONTENTS_MODELNUMSHIFT = 24
SF.AREACONTENTS_MAXMODELNUM = 0xFF
SF.AREACONTENTS_MODELNUM = bit32.lshift(SF.AREACONTENTS_MAXMODELNUM, SF.AREACONTENTS_MODELNUMSHIFT)

SF.IDEAL_ATTACKDIST = 140

SF.MAX_WAYPOINTS = 128

SF.MAX_EPAIRKEY = 128

G.botai_waypoints = {}
for i = 0, SF.MAX_WAYPOINTS - 1 do
	G.botai_waypoints[i] = S.bot_waypoint_t()
end
G.botai_freewaypoints = nil

--NOTE: not using a cvars which can be updated because the game should be reloaded anyway
G.gametype = 0 --game type
G.maxclients = 0 --maximum number of clients

G.bot_grapple = S.vmCvar_t()
G.bot_rocketjump = S.vmCvar_t()
G.bot_fastchat = S.vmCvar_t()
G.bot_nochat = S.vmCvar_t()
G.bot_friendChat = S.vmCvar_t()
G.bot_testrchat = S.vmCvar_t()
G.bot_challenge = S.vmCvar_t()
G.bot_predictobstacles = S.vmCvar_t()
G.g_spSkill = S.vmCvar_t()

G.lastteleport_origin = Q.vec3() --last teleport event origin
G.lastteleport_time = 0 --last teleport event time
G.max_bspmodelindex = 0 --maximum BSP model index

--CTF flag goals
G.ctf_redflag = S.bot_goal_t()
G.ctf_blueflag = S.bot_goal_t()
--Domination goals:
G.dom_points_bot = {}
for i = 0, C.MAX_DOMINATION_POINTS - 1 do
	G.dom_points_bot[i] = S.bot_goal_t()
end
G.ctf_neutralflag = S.bot_goal_t()
G.redobelisk = S.bot_goal_t()
G.blueobelisk = S.bot_goal_t()
G.neutralobelisk = S.bot_goal_t()

SF.MAX_ALTROUTEGOALS = 32

G.altroutegoals_setup = 0
G.red_altroutegoals = {}
G.blue_altroutegoals = {}
for i = 0, SF.MAX_ALTROUTEGOALS - 1 do
	G.red_altroutegoals[i] = S.aas_altroutegoal_t()
	G.blue_altroutegoals[i] = S.aas_altroutegoal_t()
end
G.red_numaltroutegoals = 0
G.blue_numaltroutegoals = 0

local gametypeNames = { [0] = "ffa", "tournament", "single", "team", "ctf", "oneflag", "obelisk", "harvester", "elimination",
	"ctf", "lms", "dd", "dom" }

--[[
==================
untrap_BotGetLevelItemGoal
 *same as trap_BotGetLevelItemGoal, but respects the gametype flag!
==================
]]
function G.untrap_BotGetLevelItemGoal(start, classname, goal)
	start = G.trap_BotGetLevelItemGoal(start, classname, goal)
	while start > -1 do
		local ok, allowedGametypes = G.trap_AAS_ValueForBSPEpairKey(start, "gametype", SF.MAX_EPAIRKEY)
		if ok == 0 or not ok then
			return start --No gametype flag
		end
		if G.gametype >= C.GT_FFA and G.gametype < C.GT_MAX_GAME_TYPE then
			local gametypeName = gametypeNames[G.gametype]
			if QS.strstr(allowedGametypes, gametypeName) ~= nil then
				--In gametype strig
				return start
			end
		else
			return start
		end
		start = G.trap_BotGetLevelItemGoal(start, classname, goal)
	end
	return -1
end

--[[
==================
BotSetUserInfo
==================
]]
function G.BotSetUserInfo(bs, key, value)
	local userinfo = G.trap_GetUserinfo(bs.client)
	userinfo = QS.Info_SetValueForKey(userinfo, key, value)
	G.trap_SetUserinfo(bs.client, userinfo)
	G.ClientUserinfoChanged(bs.client)
end

--[[
==================
BotCTFCarryingFlag
==================
]]
function G.BotCTFCarryingFlag(bs)
	if G.gametype ~= C.GT_CTF and G.gametype ~= C.GT_CTF_ELIMINATION then return C.CTF_FLAG_NONE end

	if bs.inventory[C.INVENTORY_REDFLAG] > 0 then return C.CTF_FLAG_RED
	elseif bs.inventory[C.INVENTORY_BLUEFLAG] > 0 then return C.CTF_FLAG_BLUE end
	return C.CTF_FLAG_NONE
end

--[[
==================
BotTeam
==================
]]
function G.BotTeam(bs)
	if bs.client < 0 or bs.client >= C.MAX_CLIENTS then
		return 0
	end

	if G.level.clients[bs.client].sess.sessionTeam == C.TEAM_RED then
		return C.TEAM_RED
	elseif G.level.clients[bs.client].sess.sessionTeam == C.TEAM_BLUE then
		return C.TEAM_BLUE
	end

	return C.TEAM_FREE
end

--[[
==================
BotOppositeTeam
==================
]]
function G.BotOppositeTeam(bs)
	local team = G.BotTeam(bs)
	if team == C.TEAM_RED then return C.TEAM_BLUE
	elseif team == C.TEAM_BLUE then return C.TEAM_RED
	else return C.TEAM_FREE end
end

--[[
==================
BotEnemyFlag
==================
]]
function G.BotEnemyFlag(bs)
	if G.BotTeam(bs) == C.TEAM_RED then
		return G.ctf_blueflag
	else
		return G.ctf_redflag
	end
end

--[[
==================
BotTeamFlag
==================
]]
function G.BotTeamFlag(bs)
	if G.BotTeam(bs) == C.TEAM_RED then
		return G.ctf_redflag
	else
		return G.ctf_blueflag
	end
end

--[[
==================
EntityIsDead
==================
]]
function G.EntityIsDead(entinfo)
	local ps = S.playerState_t()

	if entinfo.number >= 0 and entinfo.number < C.MAX_CLIENTS then
		--retrieve the current client state
		G.BotAI_GetClientState(entinfo.number, ps)

		if ps.pm_type ~= C.PM_NORMAL then return true end
	end
	return false
end

--[[
==================
EntityCarriesFlag
==================
]]
function G.EntityCarriesFlag(entinfo)
	if bit32.band(entinfo.powerups, bit32.lshift(1, C.PW_REDFLAG)) ~= 0 then
		return true
	end
	if bit32.band(entinfo.powerups, bit32.lshift(1, C.PW_BLUEFLAG)) ~= 0 then
		return true
	end
	if bit32.band(entinfo.powerups, bit32.lshift(1, C.PW_NEUTRALFLAG)) ~= 0 then
		return true
	end
	return false
end

--[[
==================
EntityIsInvisible
==================
]]
function G.EntityIsInvisible(entinfo)
	-- the flag is always visible
	if G.EntityCarriesFlag(entinfo) then
		return false
	end
	if bit32.band(entinfo.powerups, bit32.lshift(1, C.PW_INVIS)) ~= 0 then
		return true
	end
	return false
end

--[[
==================
EntityIsShooting
==================
]]
function G.EntityIsShooting(entinfo)
	if bit32.band(entinfo.flags, C.EF_FIRING) ~= 0 then
		return true
	end
	return false
end

--[[
==================
EntityIsChatting
==================
]]
function G.EntityIsChatting(entinfo)
	if bit32.band(entinfo.flags, C.EF_TALK) ~= 0 then
		return true
	end
	return false
end

--[[
==================
EntityHasQuad
==================
]]
function G.EntityHasQuad(entinfo)
	if bit32.band(entinfo.powerups, bit32.lshift(1, C.PW_QUAD)) ~= 0 then
		return true
	end
	return false
end

--[[
==================
EntityHasKamikze
==================
]]
function G.EntityHasKamikaze(entinfo)
	if bit32.band(entinfo.flags, C.EF_KAMIKAZE) ~= 0 then
		return true
	end
	return false
end

--[[
==================
EntityCarriesCubes
==================
]]
function G.EntityCarriesCubes(entinfo)
	local state = S.entityState_t()

	if G.gametype ~= C.GT_HARVESTER then
		return false
	end
	--FIXME: get this info from the aas_entityinfo_t ?
	G.BotAI_GetEntityState(entinfo.number, state)
	if state.generic1 > 0 then
		return true
	end
	return false
end

--[[
==================
Bot1FCTFCarryingFlag
==================
]]
function G.Bot1FCTFCarryingFlag(bs)
	if G.gametype ~= C.GT_1FCTF then return 0 end

	if bs.inventory[C.INVENTORY_NEUTRALFLAG] > 0 then return 1 end
	return 0
end

--[[
==================
BotHarvesterCarryingCubes
==================
]]
function G.BotHarvesterCarryingCubes(bs)
	if G.gametype ~= C.GT_HARVESTER then return 0 end

	if bs.inventory[C.INVENTORY_REDCUBE] > 0 then return 1 end
	if bs.inventory[C.INVENTORY_BLUECUBE] > 0 then return 1 end
	return 0
end

--[[
==================
BotRememberLastOrderedTask
==================
]]
function G.BotRememberLastOrderedTask(bs)
	if bs.ordered == 0 then
		return
	end
	bs.lastgoal_decisionmaker = bs.decisionmaker
	bs.lastgoal_ltgtype = bs.ltgtype
	S.copy_bot_goal_t(bs.lastgoal_teamgoal, bs.teamgoal)
	bs.lastgoal_teammate = bs.teammate
end

--[[
==================
BotSetTeamStatus
==================
]]
function G.BotSetTeamStatus(bs)
	local teamtask = C.TEAMTASK_PATROL
	local entinfo = S.aas_entityinfo_t()
	local gt = G.gametype
	local ltg = bs.ltgtype

	if ltg == C.LTG_TEAMHELP then
		-- nothing
	elseif ltg == C.LTG_TEAMACCOMPANY then
		G.BotEntityInfo(bs.teammate, entinfo)
		if ((gt == C.GT_CTF or gt == C.GT_CTF_ELIMINATION or gt == C.GT_1FCTF) and G.EntityCarriesFlag(entinfo))
			or (gt == C.GT_HARVESTER and G.EntityCarriesCubes(entinfo)) then
			teamtask = C.TEAMTASK_ESCORT
		else
			teamtask = C.TEAMTASK_FOLLOW
		end
	elseif ltg == C.LTG_DEFENDKEYAREA then
		teamtask = C.TEAMTASK_DEFENSE
	elseif ltg == C.LTG_GETFLAG then
		teamtask = C.TEAMTASK_OFFENSE
	elseif ltg == C.LTG_RUSHBASE then
		teamtask = C.TEAMTASK_DEFENSE
	elseif ltg == C.LTG_RETURNFLAG then
		teamtask = C.TEAMTASK_RETRIEVE
	elseif ltg == C.LTG_CAMP or ltg == C.LTG_CAMPORDER then
		teamtask = C.TEAMTASK_CAMP
	elseif ltg == C.LTG_PATROL then
		teamtask = C.TEAMTASK_PATROL
	elseif ltg == C.LTG_GETITEM then
		teamtask = C.TEAMTASK_PATROL
	elseif ltg == C.LTG_KILL then
		teamtask = C.TEAMTASK_PATROL
	elseif ltg == C.LTG_HARVEST then
		teamtask = C.TEAMTASK_OFFENSE
	elseif ltg == C.LTG_ATTACKENEMYBASE then
		teamtask = C.TEAMTASK_OFFENSE
	else
		-- 0.8.8's LTG_POINTA/LTG_POINTB cases lack a break and fall through to default
		teamtask = C.TEAMTASK_PATROL
	end
	G.BotSetUserInfo(bs, "teamtask", QS.va("%d", teamtask))
end

--[[
==================
BotSetLastOrderedTask
==================
]]
function G.BotSetLastOrderedTask(bs)

	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
		-- don't go back to returning the flag if it's at the base
		if bs.lastgoal_ltgtype == C.LTG_RETURNFLAG then
			if G.BotTeam(bs) == C.TEAM_RED then
				if bs.redflagstatus == 0 then
					bs.lastgoal_ltgtype = 0
				end
			else
				if bs.blueflagstatus == 0 then
					bs.lastgoal_ltgtype = 0
				end
			end
		end
	end

	if bs.lastgoal_ltgtype ~= 0 then
		bs.decisionmaker = bs.lastgoal_decisionmaker
		bs.ordered = 1
		bs.ltgtype = bs.lastgoal_ltgtype
		S.copy_bot_goal_t(bs.teamgoal, bs.lastgoal_teamgoal)
		bs.teammate = bs.lastgoal_teammate
		bs.teamgoal_time = G.floattime + 300
		G.BotSetTeamStatus(bs)
		--
		if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
			if bs.ltgtype == C.LTG_GETFLAG then
				local tb = G.BotTeamFlag(bs)
				local eb = G.BotEnemyFlag(bs)
				local tt = G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin, tb.areanum, C.TFL_DEFAULT)
				local et = G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin, eb.areanum, C.TFL_DEFAULT)
				-- if the travel time towards the enemy base is larger than towards our base
				if et > tt then
					--get an alternative route goal towards the enemy base
					G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
				end
			end
		end
		return 1
	end
	return 0
end

--[[
==================
BotRefuseOrder
==================
]]
function G.BotRefuseOrder(bs)
	if bs.ordered == 0 then
		return
	end
	-- if the bot was ordered to do something
	if bs.order_time ~= 0 and bs.order_time > G.floattime - 10 then
		G.trap_EA_Action(bs.client, C.ACTION_NEGATIVE)
		G.BotVoiceChat(bs, bs.decisionmaker, VOICECHAT_NO)
		bs.order_time = 0
	end
end

--[[
==================
BotCTFSeekGoals
==================
]]
function G.BotCTFSeekGoals(bs)
	local rnd, l1, l2
	local flagstatus, c
	local dir = Q.vec3()
	local entinfo = S.aas_entityinfo_t()

	--when carrying a flag in ctf the bot should rush to the base
	if G.BotCTFCarryingFlag(bs) ~= 0 then
		--if not already rushing to the base
		if bs.ltgtype ~= C.LTG_RUSHBASE then
			G.BotRefuseOrder(bs)
			bs.ltgtype = C.LTG_RUSHBASE
			bs.teamgoal_time = G.floattime + C.CTF_RUSHBASE_TIME
			bs.rushbaseaway_time = 0
			bs.decisionmaker = bs.client
			bs.ordered = 0
			--
			local team = G.BotTeam(bs)
			if team == C.TEAM_RED then
				Q.VectorSubtract(bs.origin, G.ctf_blueflag.origin, dir)
			elseif team == C.TEAM_BLUE then
				Q.VectorSubtract(bs.origin, G.ctf_redflag.origin, dir)
			else
				Q.VectorSet(dir, 999, 999, 999)
			end
			-- if the bot picked up the flag very close to the enemy base
			if Q.VectorLength(dir) < 128 then
				-- get an alternative route goal through the enemy base
				G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
			else
				-- don't use any alt route goal, just get the hell out of the base
				bs.altroutegoal.areanum = 0
			end
			G.BotSetUserInfo(bs, "teamtask", QS.va("%d", C.TEAMTASK_OFFENSE))
			G.BotVoiceChat(bs, -1, VOICECHAT_IHAVEFLAG)
		elseif bs.rushbaseaway_time > G.floattime then
			if G.BotTeam(bs) == C.TEAM_RED then flagstatus = bs.redflagstatus
			else flagstatus = bs.blueflagstatus end
			--if the flag is back
			if flagstatus == 0 then
				bs.rushbaseaway_time = 0
			end
		end
		return
	end
	-- if the bot decided to follow someone
	if bs.ltgtype == C.LTG_TEAMACCOMPANY and bs.ordered == 0 then
		-- if the team mate being accompanied no longer carries the flag
		G.BotEntityInfo(bs.teammate, entinfo)
		if not G.EntityCarriesFlag(entinfo) then
			bs.ltgtype = 0
		end
	end
	--
	if G.BotTeam(bs) == C.TEAM_RED then flagstatus = bs.redflagstatus * 2 + bs.blueflagstatus
	else flagstatus = bs.blueflagstatus * 2 + bs.redflagstatus end
	--if our team has the enemy flag and our flag is at the base
	if flagstatus == 1 then
		--
		if bs.owndecision_time < G.floattime then
			--if Not defending the base already
			if not (bs.ltgtype == C.LTG_DEFENDKEYAREA and
				(bs.teamgoal.number == G.ctf_redflag.number or
				bs.teamgoal.number == G.ctf_blueflag.number)) then
				--if there is a visible team mate flag carrier
				c = G.BotTeamFlagCarrierVisible(bs)
				if c >= 0 and
					-- and not already following the team mate flag carrier
					(bs.ltgtype ~= C.LTG_TEAMACCOMPANY or bs.teammate ~= c) then
					--
					G.BotRefuseOrder(bs)
					--follow the flag carrier
					bs.decisionmaker = bs.client
					bs.ordered = 0
					--the team mate
					bs.teammate = c
					--last time the team mate was visible
					bs.teammatevisible_time = G.floattime
					--no message
					bs.teammessage_time = 0
					--no arrive message
					bs.arrive_time = 1
					--
					G.BotVoiceChat(bs, bs.teammate, VOICECHAT_ONFOLLOW)
					--get the team goal time
					bs.teamgoal_time = G.floattime + C.TEAM_ACCOMPANY_TIME
					bs.ltgtype = C.LTG_TEAMACCOMPANY
					bs.formation_dist = 3.5 * 32 --3.5 meter
					G.BotSetTeamStatus(bs)
					bs.owndecision_time = G.floattime + 5
				end
			end
		end
		return
	--if the enemy has our flag
	elseif flagstatus == 2 then
		--
		if bs.owndecision_time < G.floattime then
			--if enemy flag carrier is visible
			c = G.BotEnemyFlagCarrierVisible(bs)
			if c >= 0 then
				--FIXME: fight enemy flag carrier
			end
			--if not already doing something important
			if bs.ltgtype ~= C.LTG_GETFLAG and
				bs.ltgtype ~= C.LTG_RETURNFLAG and
				bs.ltgtype ~= C.LTG_TEAMHELP and
				bs.ltgtype ~= C.LTG_TEAMACCOMPANY and
				bs.ltgtype ~= C.LTG_CAMPORDER and
				bs.ltgtype ~= C.LTG_PATROL and
				bs.ltgtype ~= C.LTG_GETITEM then

				G.BotRefuseOrder(bs)
				bs.decisionmaker = bs.client
				bs.ordered = 0
				--
				if Q.random() < 0.5 then
					--go for the enemy flag
					bs.ltgtype = C.LTG_GETFLAG
				else
					bs.ltgtype = C.LTG_RETURNFLAG
				end
				--no team message
				bs.teammessage_time = 0
				--set the time the bot will stop getting the flag
				bs.teamgoal_time = G.floattime + C.CTF_GETFLAG_TIME
				--get an alternative route goal towards the enemy base
				G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
				--
				G.BotSetTeamStatus(bs)
				bs.owndecision_time = G.floattime + 5
			end
		end
		return
	--if both flags Not at their bases
	elseif flagstatus == 3 then
		--
		if bs.owndecision_time < G.floattime then
			-- if not trying to return the flag and not following the team flag carrier
			if bs.ltgtype ~= C.LTG_RETURNFLAG and bs.ltgtype ~= C.LTG_TEAMACCOMPANY then
				--
				c = G.BotTeamFlagCarrierVisible(bs)
				-- if there is a visible team mate flag carrier
				if c >= 0 then
					G.BotRefuseOrder(bs)
					--follow the flag carrier
					bs.decisionmaker = bs.client
					bs.ordered = 0
					--the team mate
					bs.teammate = c
					--last time the team mate was visible
					bs.teammatevisible_time = G.floattime
					--no message
					bs.teammessage_time = 0
					--no arrive message
					bs.arrive_time = 1
					--
					G.BotVoiceChat(bs, bs.teammate, VOICECHAT_ONFOLLOW)
					--get the team goal time
					bs.teamgoal_time = G.floattime + C.TEAM_ACCOMPANY_TIME
					bs.ltgtype = C.LTG_TEAMACCOMPANY
					bs.formation_dist = 3.5 * 32 --3.5 meter
					--
					G.BotSetTeamStatus(bs)
					bs.owndecision_time = G.floattime + 5
				else
					G.BotRefuseOrder(bs)
					bs.decisionmaker = bs.client
					bs.ordered = 0
					--get the enemy flag
					bs.teammessage_time = G.floattime + 2 * Q.random()
					--get the flag
					bs.ltgtype = C.LTG_RETURNFLAG
					--set the time the bot will stop getting the flag
					bs.teamgoal_time = G.floattime + C.CTF_RETURNFLAG_TIME
					--get an alternative route goal towards the enemy base
					G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
					--
					G.BotSetTeamStatus(bs)
					bs.owndecision_time = G.floattime + 5
				end
			end
		end
		return
	end
	-- don't just do something wait for the bot team leader to give orders
	if G.BotTeamLeader(bs) ~= 0 then
		return
	end
	-- if the bot is ordered to do something
	if bs.lastgoal_ltgtype ~= 0 then
		bs.teamgoal_time += 60
	end
	-- if the bot decided to do something on it's own and has a last ordered goal
	if bs.ordered == 0 and bs.lastgoal_ltgtype ~= 0 then
		bs.ltgtype = 0
	end
	--if already a CTF or team goal
	if bs.ltgtype == C.LTG_TEAMHELP or
		bs.ltgtype == C.LTG_TEAMACCOMPANY or
		bs.ltgtype == C.LTG_DEFENDKEYAREA or
		bs.ltgtype == C.LTG_GETFLAG or
		bs.ltgtype == C.LTG_RUSHBASE or
		bs.ltgtype == C.LTG_RETURNFLAG or
		bs.ltgtype == C.LTG_CAMPORDER or
		bs.ltgtype == C.LTG_PATROL or
		bs.ltgtype == C.LTG_GETITEM or
		bs.ltgtype == C.LTG_MAKELOVE_UNDER or
		bs.ltgtype == C.LTG_MAKELOVE_ONTOP then
		return
	end
	--
	if G.BotSetLastOrderedTask(bs) ~= 0 then
		return
	end
	--
	if bs.owndecision_time > G.floattime then
		return
	end
	--if the bot is roaming
	if bs.ctfroam_time > G.floattime then
		return
	end
	--if the bot has anough aggression to decide what to do
	if G.BotAggression(bs) < 50 then
		return
	end
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--
	if bit32.band(bs.teamtaskpreference, bit32.bor(C.TEAMTP_ATTACKER, C.TEAMTP_DEFENDER)) ~= 0 then
		if bit32.band(bs.teamtaskpreference, C.TEAMTP_ATTACKER) ~= 0 then
			l1 = Q.f(0.7)
		else
			l1 = Q.f(0.2)
		end
		l2 = Q.f(0.9)
	else
		l1 = Q.f(0.4)
		l2 = Q.f(0.7)
	end
	--get the flag or defend the base
	rnd = Q.random()
	if rnd < l1 and G.ctf_redflag.areanum ~= 0 and G.ctf_blueflag.areanum ~= 0 then
		bs.decisionmaker = bs.client
		bs.ordered = 0
		bs.ltgtype = C.LTG_GETFLAG
		--set the time the bot will stop getting the flag
		bs.teamgoal_time = G.floattime + C.CTF_GETFLAG_TIME
		--get an alternative route goal towards the enemy base
		G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
		G.BotSetTeamStatus(bs)
	elseif rnd < l2 and G.ctf_redflag.areanum ~= 0 and G.ctf_blueflag.areanum ~= 0 then
		bs.decisionmaker = bs.client
		bs.ordered = 0
		--
		if G.BotTeam(bs) == C.TEAM_RED then S.copy_bot_goal_t(bs.teamgoal, G.ctf_redflag)
		else S.copy_bot_goal_t(bs.teamgoal, G.ctf_blueflag) end
		--set the ltg type
		bs.ltgtype = C.LTG_DEFENDKEYAREA
		--set the time the bot stops defending the base
		bs.teamgoal_time = G.floattime + C.TEAM_DEFENDKEYAREA_TIME
		bs.defendaway_time = 0
		G.BotSetTeamStatus(bs)
	else
		bs.ltgtype = 0
		--set the time the bot will stop roaming
		bs.ctfroam_time = G.floattime + C.CTF_ROAM_TIME
		G.BotSetTeamStatus(bs)
	end
	bs.owndecision_time = G.floattime + 5
end

return nil
