--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_dmq3.c).

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
-- Luau port of ai_dmq3.c, part 2 of 7. Team goal selection (CTF, 1FCTF, obelisk, harvester, DD) and client name helpers.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmq3")

-- not defined in the shared defs: menudef.h voice chat names and the possession gametype
local VOICECHAT_IHAVEFLAG = "ihaveflag"
local VOICECHAT_ONFOLLOW = "onfollow"
local GT_POSSESSION = 13

-- static int maxclients of ClientOnSameTeamFromName
local clientOnSameTeamMaxclients = 0

function G.BotCTFRetreatGoals(bs)
	--when carrying a flag in ctf the bot should rush to the base
	if G.BotCTFCarryingFlag(bs) ~= 0 then
		--if not already rushing to the base
		if bs.ltgtype ~= C.LTG_RUSHBASE then
			G.BotRefuseOrder(bs)
			bs.ltgtype = C.LTG_RUSHBASE
			bs.teamgoal_time = G.floattime + C.CTF_RUSHBASE_TIME
			bs.rushbaseaway_time = 0
			bs.decisionmaker = bs.client
			bs.ordered = false
			G.BotSetTeamStatus(bs)
		end
	end
end

function G.BotDDSeekGoals(bs)
	if bs.ltgtype == C.LTG_POINTA then
		S.copy_bot_goal_t(bs.teamgoal, G.ctf_redflag)
	end
	if bs.ltgtype == C.LTG_POINTB then
		S.copy_bot_goal_t(bs.teamgoal, G.ctf_blueflag)
	end

	if bs.ltgtype == C.LTG_POINTA or bs.ltgtype == C.LTG_POINTB then
		return
	end

	if Q.imod(Q.rand(), 2) == 0 then
		bs.ltgtype = C.LTG_POINTA
	else
		bs.ltgtype = C.LTG_POINTB
	end

	if bs.ltgtype == C.LTG_POINTA then
		S.copy_bot_goal_t(bs.teamgoal, G.ctf_redflag)
		if G.BotTeam(bs) == C.TEAM_BLUE then
			G.BotSetUserInfo(bs, "teamtask", QS.va("%d", C.TEAMTASK_OFFENSE))
		else
			G.BotSetUserInfo(bs, "teamtask", QS.va("%d", C.TEAMTASK_DEFENSE))
		end
	elseif bs.ltgtype == C.LTG_POINTB then
		S.copy_bot_goal_t(bs.teamgoal, G.ctf_blueflag)
		if G.BotTeam(bs) == C.TEAM_RED then
			G.BotSetUserInfo(bs, "teamtask", QS.va("%d", C.TEAMTASK_OFFENSE))
		else
			G.BotSetUserInfo(bs, "teamtask", QS.va("%d", C.TEAMTASK_DEFENSE))
		end
	end
end

function G.Bot1FCTFSeekGoals(bs)
	local entinfo = S.aas_entityinfo_t()
	local rnd, l1, l2
	local c

	--when carrying a flag in ctf the bot should rush to the base
	if G.Bot1FCTFCarryingFlag(bs) ~= 0 then
		--if not already rushing to the base
		if bs.ltgtype ~= C.LTG_RUSHBASE then
			G.BotRefuseOrder(bs)
			bs.ltgtype = C.LTG_RUSHBASE
			bs.teamgoal_time = G.floattime + C.CTF_RUSHBASE_TIME
			bs.rushbaseaway_time = 0
			bs.decisionmaker = bs.client
			bs.ordered = false
			--get an alternative route goal towards the enemy base
			G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
			--
			G.BotSetTeamStatus(bs)
			G.BotVoiceChat(bs, -1, VOICECHAT_IHAVEFLAG)
		end
		return
	end
	-- if the bot decided to follow someone
	if bs.ltgtype == C.LTG_TEAMACCOMPANY and not bs.ordered then
		-- if the team mate being accompanied no longer carries the flag
		G.BotEntityInfo(bs.teammate, entinfo)
		if not G.EntityCarriesFlag(entinfo) then
			bs.ltgtype = 0
		end
	end
	--our team has the flag
	if bs.neutralflagstatus == 1 then
		if bs.owndecision_time < G.floattime then
			-- if not already following someone
			if bs.ltgtype ~= C.LTG_TEAMACCOMPANY then
				--if there is a visible team mate flag carrier
				c = G.BotTeamFlagCarrierVisible(bs)
				if c >= 0 then
					G.BotRefuseOrder(bs)
					--follow the flag carrier
					bs.decisionmaker = bs.client
					bs.ordered = false
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
					bs.owndecision_time = Q.trunc(G.floattime + 5)
					return
				end
			end
			--if already a CTF or team goal
			if bs.ltgtype == C.LTG_TEAMHELP or
					bs.ltgtype == C.LTG_TEAMACCOMPANY or
					bs.ltgtype == C.LTG_DEFENDKEYAREA or
					bs.ltgtype == C.LTG_GETFLAG or
					bs.ltgtype == C.LTG_RUSHBASE or
					bs.ltgtype == C.LTG_CAMPORDER or
					bs.ltgtype == C.LTG_PATROL or
					bs.ltgtype == C.LTG_ATTACKENEMYBASE or
					bs.ltgtype == C.LTG_GETITEM or
					bs.ltgtype == C.LTG_MAKELOVE_UNDER or
					bs.ltgtype == C.LTG_MAKELOVE_ONTOP then
				return
			end
			--if not already attacking the enemy base
			if bs.ltgtype ~= C.LTG_ATTACKENEMYBASE then
				G.BotRefuseOrder(bs)
				bs.decisionmaker = bs.client
				bs.ordered = false
				--
				if G.BotTeam(bs) == C.TEAM_RED then
					S.copy_bot_goal_t(bs.teamgoal, G.ctf_blueflag)
				else
					S.copy_bot_goal_t(bs.teamgoal, G.ctf_redflag)
				end
				--set the ltg type
				bs.ltgtype = C.LTG_ATTACKENEMYBASE
				--set the time the bot will stop getting the flag
				bs.teamgoal_time = G.floattime + C.TEAM_ATTACKENEMYBASE_TIME
				G.BotSetTeamStatus(bs)
				bs.owndecision_time = Q.trunc(G.floattime + 5)
			end
		end
		return
	--enemy team has the flag
	elseif bs.neutralflagstatus == 2 then
		if bs.owndecision_time < G.floattime then
			c = G.BotEnemyFlagCarrierVisible(bs)
			if c >= 0 then
				--FIXME: attack enemy flag carrier
			end
			--if already a CTF or team goal
			if bs.ltgtype == C.LTG_TEAMHELP or
					bs.ltgtype == C.LTG_TEAMACCOMPANY or
					bs.ltgtype == C.LTG_CAMPORDER or
					bs.ltgtype == C.LTG_PATROL or
					bs.ltgtype == C.LTG_GETITEM then
				return
			end
			-- if not already defending the base
			if bs.ltgtype ~= C.LTG_DEFENDKEYAREA then
				G.BotRefuseOrder(bs)
				bs.decisionmaker = bs.client
				bs.ordered = false
				--
				if G.BotTeam(bs) == C.TEAM_RED then
					S.copy_bot_goal_t(bs.teamgoal, G.ctf_redflag)
				else
					S.copy_bot_goal_t(bs.teamgoal, G.ctf_blueflag)
				end
				--set the ltg type
				bs.ltgtype = C.LTG_DEFENDKEYAREA
				--set the time the bot stops defending the base
				bs.teamgoal_time = G.floattime + C.TEAM_DEFENDKEYAREA_TIME
				bs.defendaway_time = 0
				G.BotSetTeamStatus(bs)
				bs.owndecision_time = Q.trunc(G.floattime + 5)
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
	if not bs.ordered and bs.lastgoal_ltgtype ~= 0 then
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
			bs.ltgtype == C.LTG_ATTACKENEMYBASE or
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
	if rnd < l1 and G.ctf_neutralflag.areanum ~= 0 then
		bs.decisionmaker = bs.client
		bs.ordered = false
		bs.ltgtype = C.LTG_GETFLAG
		--set the time the bot will stop getting the flag
		bs.teamgoal_time = G.floattime + C.CTF_GETFLAG_TIME
		G.BotSetTeamStatus(bs)
	elseif rnd < l2 and G.ctf_redflag.areanum ~= 0 and G.ctf_blueflag.areanum ~= 0 then
		bs.decisionmaker = bs.client
		bs.ordered = false
		--
		if G.BotTeam(bs) == C.TEAM_RED then
			S.copy_bot_goal_t(bs.teamgoal, G.ctf_redflag)
		else
			S.copy_bot_goal_t(bs.teamgoal, G.ctf_blueflag)
		end
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
	bs.owndecision_time = Q.trunc(G.floattime + 5)
end

function G.Bot1FCTFRetreatGoals(bs)
	--when carrying a flag in ctf the bot should rush to the enemy base
	if G.Bot1FCTFCarryingFlag(bs) ~= 0 then
		--if not already rushing to the base
		if bs.ltgtype ~= C.LTG_RUSHBASE then
			G.BotRefuseOrder(bs)
			bs.ltgtype = C.LTG_RUSHBASE
			bs.teamgoal_time = G.floattime + C.CTF_RUSHBASE_TIME
			bs.rushbaseaway_time = 0
			bs.decisionmaker = bs.client
			bs.ordered = false
			--get an alternative route goal towards the enemy base
			G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
			G.BotSetTeamStatus(bs)
		end
	end
end

function G.BotObeliskSeekGoals(bs)
	local rnd, l1, l2

	-- don't just do something wait for the bot team leader to give orders
	if G.BotTeamLeader(bs) ~= 0 then
		return
	end
	-- if the bot is ordered to do something
	if bs.lastgoal_ltgtype ~= 0 then
		bs.teamgoal_time += 60
	end
	--if already a team goal
	if bs.ltgtype == C.LTG_TEAMHELP or
			bs.ltgtype == C.LTG_TEAMACCOMPANY or
			bs.ltgtype == C.LTG_DEFENDKEYAREA or
			bs.ltgtype == C.LTG_GETFLAG or
			bs.ltgtype == C.LTG_RUSHBASE or
			bs.ltgtype == C.LTG_RETURNFLAG or
			bs.ltgtype == C.LTG_CAMPORDER or
			bs.ltgtype == C.LTG_PATROL or
			bs.ltgtype == C.LTG_ATTACKENEMYBASE or
			bs.ltgtype == C.LTG_GETITEM or
			bs.ltgtype == C.LTG_MAKELOVE_UNDER or
			bs.ltgtype == C.LTG_MAKELOVE_ONTOP then
		return
	end
	--
	if G.BotSetLastOrderedTask(bs) ~= 0 then
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
	if rnd < l1 and G.redobelisk.areanum ~= 0 and G.blueobelisk.areanum ~= 0 then
		bs.decisionmaker = bs.client
		bs.ordered = false
		--
		if G.BotTeam(bs) == C.TEAM_RED then
			S.copy_bot_goal_t(bs.teamgoal, G.blueobelisk)
		else
			S.copy_bot_goal_t(bs.teamgoal, G.redobelisk)
		end
		--set the ltg type
		bs.ltgtype = C.LTG_ATTACKENEMYBASE
		--set the time the bot will stop attacking the enemy base
		bs.teamgoal_time = G.floattime + C.TEAM_ATTACKENEMYBASE_TIME
		--get an alternate route goal towards the enemy base
		G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
		G.BotSetTeamStatus(bs)
	elseif rnd < l2 and G.redobelisk.areanum ~= 0 and G.blueobelisk.areanum ~= 0 then
		bs.decisionmaker = bs.client
		bs.ordered = false
		--
		if G.BotTeam(bs) == C.TEAM_RED then
			S.copy_bot_goal_t(bs.teamgoal, G.redobelisk)
		else
			S.copy_bot_goal_t(bs.teamgoal, G.blueobelisk)
		end
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
end

function G.BotGoHarvest(bs)
	--
	if G.BotTeam(bs) == C.TEAM_RED then
		S.copy_bot_goal_t(bs.teamgoal, G.blueobelisk)
	else
		S.copy_bot_goal_t(bs.teamgoal, G.redobelisk)
	end
	--set the ltg type
	bs.ltgtype = C.LTG_HARVEST
	--set the time the bot will stop harvesting
	bs.teamgoal_time = G.floattime + C.TEAM_HARVEST_TIME
	bs.harvestaway_time = 0
	G.BotSetTeamStatus(bs)
end

function G.BotObeliskRetreatGoals(bs)
	--nothing special
end

function G.BotHarvesterSeekGoals(bs)
	local entinfo = S.aas_entityinfo_t()
	local rnd, l1, l2
	local c

	--when carrying cubes in harvester the bot should rush to the base
	if G.BotHarvesterCarryingCubes(bs) ~= 0 then
		--if not already rushing to the base
		if bs.ltgtype ~= C.LTG_RUSHBASE then
			G.BotRefuseOrder(bs)
			bs.ltgtype = C.LTG_RUSHBASE
			bs.teamgoal_time = G.floattime + C.CTF_RUSHBASE_TIME
			bs.rushbaseaway_time = 0
			bs.decisionmaker = bs.client
			bs.ordered = false
			--get an alternative route goal towards the enemy base
			G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
			--
			G.BotSetTeamStatus(bs)
		end
		return
	end
	-- don't just do something wait for the bot team leader to give orders
	if G.BotTeamLeader(bs) ~= 0 then
		return
	end
	-- if the bot decided to follow someone
	if bs.ltgtype == C.LTG_TEAMACCOMPANY and not bs.ordered then
		-- if the team mate being accompanied no longer carries the flag
		G.BotEntityInfo(bs.teammate, entinfo)
		if not G.EntityCarriesCubes(entinfo) then
			bs.ltgtype = 0
		end
	end
	-- if the bot is ordered to do something
	if bs.lastgoal_ltgtype ~= 0 then
		bs.teamgoal_time += 60
	end
	--if not yet doing something
	if bs.ltgtype == C.LTG_TEAMHELP or
			bs.ltgtype == C.LTG_TEAMACCOMPANY or
			bs.ltgtype == C.LTG_DEFENDKEYAREA or
			bs.ltgtype == C.LTG_GETFLAG or
			bs.ltgtype == C.LTG_CAMPORDER or
			bs.ltgtype == C.LTG_PATROL or
			bs.ltgtype == C.LTG_ATTACKENEMYBASE or
			bs.ltgtype == C.LTG_HARVEST or
			bs.ltgtype == C.LTG_GETITEM or
			bs.ltgtype == C.LTG_MAKELOVE_UNDER or
			bs.ltgtype == C.LTG_MAKELOVE_ONTOP then
		return
	end
	--
	if G.BotSetLastOrderedTask(bs) ~= 0 then
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
	c = G.BotEnemyCubeCarrierVisible(bs)
	if c >= 0 then
		--FIXME: attack enemy cube carrier
	end
	if bs.ltgtype ~= C.LTG_TEAMACCOMPANY then
		--if there is a visible team mate carrying cubes
		c = G.BotTeamCubeCarrierVisible(bs)
		if c >= 0 then
			--follow the team mate carrying cubes
			bs.decisionmaker = bs.client
			bs.ordered = false
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
			return
		end
	end
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
	--
	rnd = Q.random()
	if rnd < l1 and G.redobelisk.areanum ~= 0 and G.blueobelisk.areanum ~= 0 then
		bs.decisionmaker = bs.client
		bs.ordered = false
		G.BotGoHarvest(bs)
	elseif rnd < l2 and G.redobelisk.areanum ~= 0 and G.blueobelisk.areanum ~= 0 then
		bs.decisionmaker = bs.client
		bs.ordered = false
		--
		if G.BotTeam(bs) == C.TEAM_RED then
			S.copy_bot_goal_t(bs.teamgoal, G.redobelisk)
		else
			S.copy_bot_goal_t(bs.teamgoal, G.blueobelisk)
		end
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
end

function G.BotHarvesterRetreatGoals(bs)
	--when carrying cubes in harvester the bot should rush to the base
	if G.BotHarvesterCarryingCubes(bs) ~= 0 then
		--if not already rushing to the base
		if bs.ltgtype ~= C.LTG_RUSHBASE then
			G.BotRefuseOrder(bs)
			bs.ltgtype = C.LTG_RUSHBASE
			bs.teamgoal_time = G.floattime + C.CTF_RUSHBASE_TIME
			bs.rushbaseaway_time = 0
			bs.decisionmaker = bs.client
			bs.ordered = false
			G.BotSetTeamStatus(bs)
		end
		return
	end
end

function G.BotTeamGoals(bs, retreat)
	local gametype = G.gametype

	if retreat ~= 0 then
		if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION then
			G.BotCTFRetreatGoals(bs)
		elseif gametype == C.GT_1FCTF then
			G.Bot1FCTFRetreatGoals(bs)
		elseif gametype == C.GT_OBELISK then
			G.BotObeliskRetreatGoals(bs)
		elseif gametype == C.GT_HARVESTER then
			G.BotHarvesterRetreatGoals(bs)
		end
	else
		if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION then
			--decide what to do in CTF mode
			G.BotCTFSeekGoals(bs)
		elseif gametype == C.GT_1FCTF or gametype == GT_POSSESSION then
			G.Bot1FCTFSeekGoals(bs)
		elseif gametype == C.GT_OBELISK then
			G.BotObeliskSeekGoals(bs)
		elseif gametype == C.GT_HARVESTER then
			G.BotHarvesterSeekGoals(bs)
		end
	end

	if gametype == C.GT_DOUBLE_D then --Don't care about retreat
		G.BotDDSeekGoals(bs)
	end

	-- reset the order time which is used to see if
	-- we decided to refuse an order
	bs.order_time = 0
end

function G.BotPointAreaNum(origin)
	local areanum, numareas
	local areas = {}
	local end_ = Q.vec3()

	areanum = G.trap_AAS_PointAreaNum(origin)
	if areanum ~= 0 then
		return areanum
	end
	Q.VectorCopy(origin, end_)
	end_[2] += 10
	numareas = G.trap_AAS_TraceAreas(origin, end_, areas, nil, 10)
	if numareas > 0 then
		return areas[0]
	end
	return 0
end

function G.ClientName(client, size)
	local buf

	if client < 0 or client >= C.MAX_CLIENTS then
		G.BotAI_Print(C.PRT_ERROR, "ClientName: client out of range\n")
		return "[client out of range]"
	end
	buf = G.trap_GetConfigstring(C.CS_PLAYERS + client)
	local name = QS.Q_strncpyz(QS.Info_ValueForKey(buf, "n"), size)
	name = QS.Q_CleanStr(name)
	return name
end

function G.ClientSkin(client, size)
	local buf

	if client < 0 or client >= C.MAX_CLIENTS then
		G.BotAI_Print(C.PRT_ERROR, "ClientSkin: client out of range\n")
		return "[client out of range]"
	end
	buf = G.trap_GetConfigstring(C.CS_PLAYERS + client)
	return QS.Q_strncpyz(QS.Info_ValueForKey(buf, "model"), size)
end

function G.ClientFromName(name)
	local buf

	for i = 0, G.level.maxclients - 1 do
		buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
		buf = QS.Q_CleanStr(buf)
		if QS.Q_strequal(QS.Info_ValueForKey(buf, "n"), name) then
			return i
		end
	end
	return -1
end

function G.ClientOnSameTeamFromName(bs, name)
	local buf

	if clientOnSameTeamMaxclients == 0 then
		clientOnSameTeamMaxclients = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	local i = 0
	while i < clientOnSameTeamMaxclients and i < C.MAX_CLIENTS do
		if G.BotSameTeam(bs, i) ~= 0 then
			buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
			buf = QS.Q_CleanStr(buf)
			if QS.Q_strequal(QS.Info_ValueForKey(buf, "n"), name) then
				return i
			end
		end
		i += 1
	end
	return -1
end

function G.stristr(str, charset)
	local s = 0
	while (string.byte(str, s + 1) or 0) ~= 0 do
		local i = 0
		while (string.byte(charset, i + 1) or 0) ~= 0 and (string.byte(str, s + i + 1) or 0) ~= 0 do
			if string.upper(string.sub(charset, i + 1, i + 1)) ~= string.upper(string.sub(str, s + i + 1, s + i + 1)) then
				break
			end
			i += 1
		end
		if (string.byte(charset, i + 1) or 0) == 0 then
			return string.sub(str, s + 1)
		end
		s += 1
	end
	return nil
end

return nil
