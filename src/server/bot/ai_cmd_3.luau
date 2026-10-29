--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_cmd.c, part 3 of 3).

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
-- Luau port of ai_cmd.c, part 3 of 3. Team leader, status questions and the message dispatcher.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_cmd")

local MAX_MESSAGE_SIZE = 150
local GT_POSSESSION = 13

function G.BotMatch_StartTeamLeaderShip(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	if bit32.band(match.subtype, C.ST_I) ~= 0 then
		local teammate = G.trap_BotMatchVariable(match, C.NETNAME, MAX_MESSAGE_SIZE)
		bs.teamleader = QS.Q_strncpyz(teammate, C.MAX_NETNAME)
	else
		local teammate = G.trap_BotMatchVariable(match, C.TEAMMATE, MAX_MESSAGE_SIZE)
		local client = G.FindClientByName(teammate)
		if client >= 0 then bs.teamleader = G.ClientName(client, C.MAX_NETNAME) end
	end
end

function G.BotMatch_StopTeamLeaderShip(bs, match)
	local client
	local teammate = G.trap_BotMatchVariable(match, C.TEAMMATE, MAX_MESSAGE_SIZE)
	if G.TeamPlayIsOn() == 0 then return end
	if bit32.band(match.subtype, C.ST_I) ~= 0 then
		local netname = G.trap_BotMatchVariable(match, C.NETNAME, MAX_MESSAGE_SIZE)
		client = G.FindClientByName(netname)
	else
		client = G.FindClientByName(teammate)
	end
	if client >= 0 then
		if QS.Q_strequal(bs.teamleader, G.ClientName(client, MAX_MESSAGE_SIZE)) then
			bs.teamleader = ""
			G.notleader[client] = 1
		end
	end
end

function G.BotMatch_WhoIsTeamLeader(bs, match)
	if G.TeamPlayIsOn() == 0 then return end

	local netname = G.ClientName(bs.client, MAX_MESSAGE_SIZE)
	if QS.Q_strequal(netname, bs.teamleader) then
		G.trap_EA_SayTeam(bs.client, "I'm the team leader\n")
	end
end

function G.BotMatch_WhatAreYouDoing(bs, match)
	if G.BotAddressedToBot(bs, match) == 0 then return end
	local t = bs.ltgtype
	if t == C.LTG_TEAMHELP then
		local netname = G.EasyClientName(bs.teammate, MAX_MESSAGE_SIZE)
		G.BotAI_BotInitialChat(bs, "helping", netname, nil)
	elseif t == C.LTG_TEAMACCOMPANY then
		local netname = G.EasyClientName(bs.teammate, MAX_MESSAGE_SIZE)
		G.BotAI_BotInitialChat(bs, "accompanying", netname, nil)
	elseif t == C.LTG_DEFENDKEYAREA then
		local goalname = G.trap_BotGoalName(bs.teamgoal.number, MAX_MESSAGE_SIZE)
		G.BotAI_BotInitialChat(bs, "defending", goalname, nil)
	elseif t == C.LTG_GETITEM then
		local goalname = G.trap_BotGoalName(bs.teamgoal.number, MAX_MESSAGE_SIZE)
		G.BotAI_BotInitialChat(bs, "gettingitem", goalname, nil)
	elseif t == C.LTG_KILL then
		local netname = G.ClientName(bs.teamgoal.entitynum, MAX_MESSAGE_SIZE)
		G.BotAI_BotInitialChat(bs, "killing", netname, nil)
	elseif t == C.LTG_CAMP or t == C.LTG_CAMPORDER then
		G.BotAI_BotInitialChat(bs, "camping", nil)
	elseif t == C.LTG_PATROL then
		G.BotAI_BotInitialChat(bs, "patrolling", nil)
	elseif t == C.LTG_GETFLAG then
		G.BotAI_BotInitialChat(bs, "capturingflag", nil)
	elseif t == C.LTG_RUSHBASE then
		G.BotAI_BotInitialChat(bs, "rushingbase", nil)
	elseif t == C.LTG_RETURNFLAG then
		G.BotAI_BotInitialChat(bs, "returningflag", nil)
	elseif t == C.LTG_ATTACKENEMYBASE then
		G.BotAI_BotInitialChat(bs, "attackingenemybase", nil)
	elseif t == C.LTG_HARVEST then
		G.BotAI_BotInitialChat(bs, "harvesting", nil)
	elseif t == C.LTG_POINTA then
		G.BotAI_BotInitialChat(bs, "dd_pointa", nil)
	elseif t == C.LTG_POINTB then
		G.BotAI_BotInitialChat(bs, "dd_pointb", nil)
	else
		G.BotAI_BotInitialChat(bs, "roaming", nil)
	end
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, MAX_MESSAGE_SIZE)
	local client = G.ClientFromName(netname)
	G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
end

function G.BotMatch_WhatIsMyCommand(bs, match)
	local netname = G.ClientName(bs.client, C.MAX_NETNAME)
	if not QS.Q_strequal(netname, bs.teamleader) then
		return
	end
	bs.forceorders = 1
end

function G.BotNearestVisibleItem(bs, itemname, goal)
	local tmpgoal = S.bot_goal_t()
	local dir = Q.vec3()
	local trace = S.bsp_trace_t()

	local bestdist = 999999
	local i = -1
	while true do
		i = G.trap_BotGetLevelItemGoal(i, itemname, tmpgoal)
		local name = G.trap_BotGoalName(tmpgoal.number, 64)
		if QS.Q_strequal(itemname, name) then
			Q.VectorSubtract(tmpgoal.origin, bs.origin, dir)
			local dist = Q.VectorLength(dir)
			if dist < bestdist then
				G.BotAI_Trace(trace, bs.eye, nil, nil, tmpgoal.origin, bs.client, bit32.bor(C.CONTENTS_SOLID, C.CONTENTS_PLAYERCLIP))
				if trace.fraction >= 1.0 then
					bestdist = dist
					S.copy_bot_goal_t(goal, tmpgoal)
				end
			end
		end
		if not (i > 0) then break end
	end
	return bestdist
end

function G.BotMatch_WhereAreYou(bs, match)
	local goal = S.bot_goal_t()
	local nearbyitems = {
		"Shotgun",
		"Grenade Launcher",
		"Rocket Launcher",
		"Plasmagun",
		"Railgun",
		"Lightning Gun",
		"BFG10K",
		"Quad Damage",
		"Regeneration",
		"Battle Suit",
		"Speed",
		"Invisibility",
		"Flight",
		"Armor",
		"Heavy Armor",
		"Red Flag",
		"Blue Flag",
		"Nailgun",
		"Prox Launcher",
		"Chaingun",
		"Scout",
		"Guard",
		"Doubler",
		"Ammo Regen",
		"Neutral Flag",
		"Red Obelisk",
		"Blue Obelisk",
		"Neutral Obelisk",
	}
	if G.TeamPlayIsOn() == 0 then
		return
	end

	if G.BotAddressedToBot(bs, match) == 0 then
		return
	end

	local bestitem = -1
	local bestdist = 999999
	for i = 1, #nearbyitems do
		local dist = G.BotNearestVisibleItem(bs, nearbyitems[i], goal)
		if dist < bestdist then
			bestdist = dist
			bestitem = i
		end
	end
	if bestitem ~= -1 then
		local gametype = G.gametype
		if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION or gametype == C.GT_1FCTF then
			local redtt = G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin, G.ctf_redflag.areanum, C.TFL_DEFAULT)
			local bluett = G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin, G.ctf_blueflag.areanum, C.TFL_DEFAULT)
			if redtt < (redtt + bluett) * 0.4 then
				G.BotAI_BotInitialChat(bs, "teamlocation", nearbyitems[bestitem], "red", nil)
			elseif bluett < (redtt + bluett) * 0.4 then
				G.BotAI_BotInitialChat(bs, "teamlocation", nearbyitems[bestitem], "blue", nil)
			else
				G.BotAI_BotInitialChat(bs, "location", nearbyitems[bestitem], nil)
			end
		elseif gametype == C.GT_OBELISK or gametype == C.GT_HARVESTER then
			local redtt = G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin, G.redobelisk.areanum, C.TFL_DEFAULT)
			local bluett = G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin, G.blueobelisk.areanum, C.TFL_DEFAULT)
			if redtt < (redtt + bluett) * 0.4 then
				G.BotAI_BotInitialChat(bs, "teamlocation", nearbyitems[bestitem], "red", nil)
			elseif bluett < (redtt + bluett) * 0.4 then
				G.BotAI_BotInitialChat(bs, "teamlocation", nearbyitems[bestitem], "blue", nil)
			else
				G.BotAI_BotInitialChat(bs, "location", nearbyitems[bestitem], nil)
			end
		else
			G.BotAI_BotInitialChat(bs, "location", nearbyitems[bestitem], nil)
		end
		local netname = G.trap_BotMatchVariable(match, C.NETNAME, MAX_MESSAGE_SIZE)
		local client = G.ClientFromName(netname)
		G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
	end
end

function G.BotMatch_LeadTheWay(bs, match)
	local entinfo = S.aas_entityinfo_t()
	local netname = ""
	local teammate = ""
	local client, other

	if G.TeamPlayIsOn() == 0 then return end
	if G.BotAddressedToBot(bs, match) == 0 then return end
	if bit32.band(match.subtype, C.ST_SOMEONE) ~= 0 then
		teammate = G.trap_BotMatchVariable(match, C.TEAMMATE, MAX_MESSAGE_SIZE)
		client = G.FindClientByName(teammate)
		if client == bs.client then
			other = false
		elseif G.BotSameTeam(bs, client) == 0 then
			return
		else
			other = true
		end
	else
		netname = G.trap_BotMatchVariable(match, C.NETNAME, MAX_MESSAGE_SIZE)
		client = G.ClientFromName(netname)
		other = false
	end
	if client < 0 then
		G.BotAI_BotInitialChat(bs, "whois", netname, nil)
		G.trap_BotEnterChat(bs.cs, bs.client, C.CHAT_TEAM)
		return
	end
	bs.lead_teamgoal.entitynum = -1
	G.BotEntityInfo(client, entinfo)
	if entinfo.valid ~= 0 then
		local areanum = G.BotPointAreaNum(entinfo.origin)
		if areanum ~= 0 then
			bs.lead_teamgoal.entitynum = client
			bs.lead_teamgoal.areanum = areanum
			Q.VectorCopy(entinfo.origin, bs.lead_teamgoal.origin)
			Q.VectorSet(bs.lead_teamgoal.mins, -8, -8, -8)
			Q.VectorSet(bs.lead_teamgoal.maxs, 8, 8, 8)
		end
	end

	if bs.teamgoal.entitynum < 0 then
		if other then
			G.BotAI_BotInitialChat(bs, "whereis", teammate, nil)
		else
			G.BotAI_BotInitialChat(bs, "whereareyou", netname, nil)
		end
		G.trap_BotEnterChat(bs.cs, bs.client, C.CHAT_TEAM)
		return
	end
	bs.lead_teammate = client
	bs.lead_time = G.floattime + C.TEAM_LEAD_TIME
	bs.leadvisible_time = 0
	bs.leadmessage_time = -(G.floattime + 2 * Q.random())
end

function G.BotMatch_Kill(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	if G.BotAddressedToBot(bs, match) == 0 then return end

	local enemy = G.trap_BotMatchVariable(match, C.ENEMY, MAX_MESSAGE_SIZE)
	local client = G.FindEnemyByName(bs, enemy)
	if client < 0 then
		G.BotAI_BotInitialChat(bs, "whois", enemy, nil)
		local netname = G.trap_BotMatchVariable(match, C.NETNAME, MAX_MESSAGE_SIZE)
		client = G.ClientFromName(netname)
		G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
		return
	end
	bs.teamgoal.entitynum = client
	bs.teammessage_time = G.floattime + 2 * Q.random()
	bs.ltgtype = C.LTG_KILL
	bs.teamgoal_time = G.floattime + C.TEAM_KILL_SOMEONE
	G.BotSetTeamStatus(bs)
end

function G.BotMatch_CTF(bs, match)
	local gametype = G.gametype
	if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION then
		local flag = G.trap_BotMatchVariable(match, C.FLAG, 128)
		if bit32.band(match.subtype, C.ST_GOTFLAG) ~= 0 then
			if QS.Q_strequal(flag, "red") then
				bs.redflagstatus = 1
				if G.BotTeam(bs) == C.TEAM_BLUE then
					local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_NETNAME)
					bs.flagcarrier = G.ClientFromName(netname)
				end
			else
				bs.blueflagstatus = 1
				if G.BotTeam(bs) == C.TEAM_RED then
					local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_NETNAME)
					bs.flagcarrier = G.ClientFromName(netname)
				end
			end
			bs.flagstatuschanged = 1
			bs.lastflagcapture_time = G.floattime
		elseif bit32.band(match.subtype, C.ST_CAPTUREDFLAG) ~= 0 then
			bs.redflagstatus = 0
			bs.blueflagstatus = 0
			bs.flagcarrier = 0
			bs.flagstatuschanged = 1
		elseif bit32.band(match.subtype, C.ST_RETURNEDFLAG) ~= 0 then
			if QS.Q_strequal(flag, "red") then
				bs.redflagstatus = 0
			else
				bs.blueflagstatus = 0
			end
			bs.flagstatuschanged = 1
		end
	elseif gametype == C.GT_1FCTF or gametype == GT_POSSESSION then
		if bit32.band(match.subtype, C.ST_1FCTFGOTFLAG) ~= 0 then
			local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_NETNAME)
			bs.flagcarrier = G.ClientFromName(netname)
		end
	end
end

function G.BotMatch_EnterGame(bs, match)
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_NETNAME)
	local client = G.FindClientByName(netname)
	if client >= 0 then
		G.notleader[client] = 0
	end
end

function G.BotMatch_NewLeader(bs, match)
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_NETNAME)
	local client = G.FindClientByName(netname)
	if G.BotSameTeam(bs, client) == 0 then
		return
	end
	bs.teamleader = QS.Q_strncpyz(netname, C.MAX_NETNAME)
end

function G.BotMatchMessage(bs, message)
	local match = S.bot_match_t()

	match.type = 0
	if G.trap_BotFindMatch(message, match, bit32.bor(C.MTCONTEXT_MISC, C.MTCONTEXT_INITIALTEAMCHAT, C.MTCONTEXT_CTF, C.MTCONTEXT_DD)) == 0 then
		return 0
	end
	local t = match.type
	if t == C.MSG_HELP or t == C.MSG_ACCOMPANY then
		G.BotMatch_HelpAccompany(bs, match)
	elseif t == C.MSG_DEFENDKEYAREA then
		G.BotMatch_DefendKeyArea(bs, match)
	elseif t == C.MSG_CAMP then
		G.BotMatch_Camp(bs, match)
	elseif t == C.MSG_PATROL then
		G.BotMatch_Patrol(bs, match)
	elseif t == C.MSG_GETFLAG then
		G.BotMatch_GetFlag(bs, match)
	elseif t == C.MSG_ATTACKENEMYBASE then
		G.BotMatch_AttackEnemyBase(bs, match)
	elseif t == C.MSG_HARVEST then
		G.BotMatch_Harvest(bs, match)
	elseif t == C.MSG_RUSHBASE then
		G.BotMatch_RushBase(bs, match)
	elseif t == C.MSG_RETURNFLAG then
		G.BotMatch_ReturnFlag(bs, match)
	elseif t == C.MSG_TASKPREFERENCE then
		G.BotMatch_TaskPreference(bs, match)
	elseif t == C.MSG_CTF then
		G.BotMatch_CTF(bs, match)
	elseif t == C.MSG_GETITEM then
		G.BotMatch_GetItem(bs, match)
	elseif t == C.MSG_JOINSUBTEAM then
		G.BotMatch_JoinSubteam(bs, match)
	elseif t == C.MSG_LEAVESUBTEAM then
		G.BotMatch_LeaveSubteam(bs, match)
	elseif t == C.MSG_WHICHTEAM then
		G.BotMatch_WhichTeam(bs, match)
	elseif t == C.MSG_CHECKPOINT then
		G.BotMatch_CheckPoint(bs, match)
	elseif t == C.MSG_CREATENEWFORMATION then
		G.trap_EA_SayTeam(bs.client, "the part of my brain to create formations has been damaged")
	elseif t == C.MSG_FORMATIONPOSITION then
		G.trap_EA_SayTeam(bs.client, "the part of my brain to create formations has been damaged")
	elseif t == C.MSG_FORMATIONSPACE then
		G.BotMatch_FormationSpace(bs, match)
	elseif t == C.MSG_DOFORMATION then
		-- nothing to do
	elseif t == C.MSG_DISMISS then
		G.BotMatch_Dismiss(bs, match)
	elseif t == C.MSG_STARTTEAMLEADERSHIP then
		G.BotMatch_StartTeamLeaderShip(bs, match)
	elseif t == C.MSG_STOPTEAMLEADERSHIP then
		G.BotMatch_StopTeamLeaderShip(bs, match)
	elseif t == C.MSG_WHOISTEAMLAEDER then
		G.BotMatch_WhoIsTeamLeader(bs, match)
	elseif t == C.MSG_WHATAREYOUDOING then
		G.BotMatch_WhatAreYouDoing(bs, match)
	elseif t == C.MSG_WHATISMYCOMMAND then
		G.BotMatch_WhatIsMyCommand(bs, match)
	elseif t == C.MSG_WHEREAREYOU then
		G.BotMatch_WhereAreYou(bs, match)
	elseif t == C.MSG_LEADTHEWAY then
		G.BotMatch_LeadTheWay(bs, match)
	elseif t == C.MSG_KILL then
		G.BotMatch_Kill(bs, match)
	elseif t == C.MSG_ENTERGAME then
		G.BotMatch_EnterGame(bs, match)
	elseif t == C.MSG_NEWLEADER then
		G.BotMatch_NewLeader(bs, match)
	elseif t == C.MSG_WAIT then
		-- nothing to do
	elseif t == C.MSG_SUICIDE then
		G.BotMatch_Suicide(bs, match)
	elseif t == C.MSG_TAKEA then
		G.BotMatch_TakeA(bs, match)
	elseif t == C.MSG_TAKEB then
		G.BotMatch_TakeB(bs, match)
	else
		G.BotAI_Print(C.PRT_MESSAGE, "unknown match type\n")
	end
	return 1
end

return nil
