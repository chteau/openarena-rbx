--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_vcmd.c).

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
-- Luau port of ai_vcmd.c. Bot reactions to team voice chat commands.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

-- voice chat names from ui/menudef.h
local VC = {
	GETFLAG = "getflag",
	OFFENSE = "offense",
	DEFEND = "defend",
	DEFENDFLAG = "defendflag",
	PATROL = "patrol",
	ONPATROL = "onpatrol",
	CAMP = "camp",
	FOLLOWME = "followme",
	FOLLOWFLAGCARRIER = "followflagcarrier",
	RETURNFLAG = "returnflag",
	STARTLEADER = "startleader",
	STOPLEADER = "stopleader",
	WHOISLEADER = "whoisleader",
	WANTONDEFENSE = "wantondefense",
	WANTONOFFENSE = "wantonoffense",
	YES = "yes",
}

function G.BotVoiceChat_GetFlag(bs, client, mode)
	--
	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
		if G.ctf_redflag.areanum == 0 or G.ctf_blueflag.areanum == 0 then
			return
		end
	elseif G.gametype == C.GT_1FCTF then
		if G.ctf_neutralflag.areanum == 0 or G.ctf_redflag.areanum == 0 or G.ctf_blueflag.areanum == 0 then
			return
		end
	else
		return
	end
	--
	bs.decisionmaker = client
	bs.ordered = true
	bs.order_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--set the ltg type
	bs.ltgtype = C.LTG_GETFLAG
	--set the team goal time
	bs.teamgoal_time = G.floattime + C.CTF_GETFLAG_TIME
	-- get an alternate route in ctf
	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
		--get an alternative route goal towards the enemy base
		G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
	end
	--
	G.BotSetTeamStatus(bs)
	-- remember last ordered task
	G.BotRememberLastOrderedTask(bs)
end

function G.BotVoiceChat_Offense(bs, client, mode)
	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION or G.gametype == C.GT_1FCTF then
		G.BotVoiceChat_GetFlag(bs, client, mode)
		return
	end
	if G.gametype == C.GT_HARVESTER then
		--
		bs.decisionmaker = client
		bs.ordered = true
		bs.order_time = G.floattime
		--set the time to send a message to the team mates
		bs.teammessage_time = G.floattime + 2 * Q.random()
		--set the ltg type
		bs.ltgtype = C.LTG_HARVEST
		--set the team goal time
		bs.teamgoal_time = G.floattime + C.TEAM_HARVEST_TIME
		bs.harvestaway_time = 0
		--
		G.BotSetTeamStatus(bs)
		-- remember last ordered task
		G.BotRememberLastOrderedTask(bs)
	else
		--
		bs.decisionmaker = client
		bs.ordered = true
		bs.order_time = G.floattime
		--set the time to send a message to the team mates
		bs.teammessage_time = G.floattime + 2 * Q.random()
		--set the ltg type
		bs.ltgtype = C.LTG_ATTACKENEMYBASE
		--set the team goal time
		bs.teamgoal_time = G.floattime + C.TEAM_ATTACKENEMYBASE_TIME
		bs.attackaway_time = 0
		--
		G.BotSetTeamStatus(bs)
		-- remember last ordered task
		G.BotRememberLastOrderedTask(bs)
	end
end

function G.BotVoiceChat_Defend(bs, client, mode)
	if G.gametype == C.GT_OBELISK or G.gametype == C.GT_HARVESTER then
		--
		local team = G.BotTeam(bs)
		if team == C.TEAM_RED then
			S.copy_bot_goal_t(bs.teamgoal, G.redobelisk)
		elseif team == C.TEAM_BLUE then
			S.copy_bot_goal_t(bs.teamgoal, G.blueobelisk)
		else
			return
		end
	elseif G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION or G.gametype == C.GT_1FCTF then
		--
		local team = G.BotTeam(bs)
		if team == C.TEAM_RED then
			S.copy_bot_goal_t(bs.teamgoal, G.ctf_redflag)
		elseif team == C.TEAM_BLUE then
			S.copy_bot_goal_t(bs.teamgoal, G.ctf_blueflag)
		else
			return
		end
	else
		return
	end
	--
	bs.decisionmaker = client
	bs.ordered = true
	bs.order_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--set the ltg type
	bs.ltgtype = C.LTG_DEFENDKEYAREA
	--get the team goal time
	bs.teamgoal_time = G.floattime + C.TEAM_DEFENDKEYAREA_TIME
	--away from defending
	bs.defendaway_time = 0
	--
	G.BotSetTeamStatus(bs)
	-- remember last ordered task
	G.BotRememberLastOrderedTask(bs)
end

function G.BotVoiceChat_DefendFlag(bs, client, mode)
	G.BotVoiceChat_Defend(bs, client, mode)
end

function G.BotVoiceChat_Patrol(bs, client, mode)
	--
	bs.decisionmaker = client
	--
	bs.ltgtype = 0
	bs.lead_time = 0
	bs.lastgoal_ltgtype = 0
	--
	G.BotAI_BotInitialChat(bs, "dismissed", nil)
	G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
	G.BotVoiceChatOnly(bs, -1, VC.ONPATROL)
	--
	G.BotSetTeamStatus(bs)
end

function G.BotVoiceChat_Camp(bs, client, mode)
	local entinfo = S.aas_entityinfo_t()

	--
	bs.teamgoal.entitynum = -1
	G.BotEntityInfo(client, entinfo)
	--if info is valid (in PVS)
	if entinfo.valid and entinfo.valid ~= 0 then
		local areanum = G.BotPointAreaNum(entinfo.origin)
		if areanum ~= 0 then -- && trap_AAS_AreaReachability(areanum)) {
			--NOTE: just assume the bot knows where the person is
			bs.teamgoal.entitynum = client
			bs.teamgoal.areanum = areanum
			Q.VectorCopy(entinfo.origin, bs.teamgoal.origin)
			Q.VectorSet(bs.teamgoal.mins, -8, -8, -8)
			Q.VectorSet(bs.teamgoal.maxs, 8, 8, 8)
		end
	end
	--if the other is not visible
	if bs.teamgoal.entitynum < 0 then
		G.BotAI_BotInitialChat(bs, "whereareyou", G.EasyClientName(client, C.MAX_NETNAME), nil)
		G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
		return
	end
	--
	bs.decisionmaker = client
	bs.ordered = true
	bs.order_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--set the ltg type
	bs.ltgtype = C.LTG_CAMPORDER
	--get the team goal time
	bs.teamgoal_time = G.floattime + C.TEAM_CAMP_TIME
	--the teammate that requested the camping
	bs.teammate = client
	--not arrived yet
	bs.arrive_time = 0
	--
	G.BotSetTeamStatus(bs)
	-- remember last ordered task
	G.BotRememberLastOrderedTask(bs)
end

function G.BotVoiceChat_FollowMe(bs, client, mode)
	local entinfo = S.aas_entityinfo_t()

	bs.teamgoal.entitynum = -1
	G.BotEntityInfo(client, entinfo)
	--if info is valid (in PVS)
	if entinfo.valid and entinfo.valid ~= 0 then
		local areanum = G.BotPointAreaNum(entinfo.origin)
		if areanum ~= 0 then -- && trap_AAS_AreaReachability(areanum)) {
			bs.teamgoal.entitynum = client
			bs.teamgoal.areanum = areanum
			Q.VectorCopy(entinfo.origin, bs.teamgoal.origin)
			Q.VectorSet(bs.teamgoal.mins, -8, -8, -8)
			Q.VectorSet(bs.teamgoal.maxs, 8, 8, 8)
		end
	end
	--if the other is not visible
	if bs.teamgoal.entitynum < 0 then
		G.BotAI_BotInitialChat(bs, "whereareyou", G.EasyClientName(client, C.MAX_NETNAME), nil)
		G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
		return
	end
	--
	bs.decisionmaker = client
	bs.ordered = true
	bs.order_time = G.floattime
	--the team mate
	bs.teammate = client
	--last time the team mate was assumed visible
	bs.teammatevisible_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--get the team goal time
	bs.teamgoal_time = G.floattime + C.TEAM_ACCOMPANY_TIME
	--set the ltg type
	bs.ltgtype = C.LTG_TEAMACCOMPANY
	bs.formation_dist = 3.5 * 32 --3.5 meter
	bs.arrive_time = 0
	--
	G.BotSetTeamStatus(bs)
	-- remember last ordered task
	G.BotRememberLastOrderedTask(bs)
end

function G.BotVoiceChat_FollowFlagCarrier(bs, client, mode)
	local carrier = G.BotTeamFlagCarrier(bs)
	if carrier >= 0 then
		G.BotVoiceChat_FollowMe(bs, carrier, mode)
	end
end

function G.BotVoiceChat_ReturnFlag(bs, client, mode)
	--if not in CTF mode
	if G.gametype ~= C.GT_CTF and G.gametype ~= C.GT_CTF_ELIMINATION and G.gametype ~= C.GT_1FCTF then
		return
	end
	--
	bs.decisionmaker = client
	bs.ordered = true
	bs.order_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--set the ltg type
	bs.ltgtype = C.LTG_RETURNFLAG
	--set the team goal time
	bs.teamgoal_time = G.floattime + C.CTF_RETURNFLAG_TIME
	bs.rushbaseaway_time = 0
	G.BotSetTeamStatus(bs)
end

function G.BotVoiceChat_StartLeader(bs, client, mode)
	bs.teamleader = G.ClientName(client, C.MAX_NETNAME)
end

function G.BotVoiceChat_StopLeader(bs, client, mode)
	if QS.Q_strequal(bs.teamleader, G.ClientName(client, C.MAX_MESSAGE_SIZE)) then
		bs.teamleader = ""
		G.notleader[client] = true
	end
end

function G.BotVoiceChat_WhoIsLeader(bs, client, mode)
	if G.TeamPlayIsOn() == 0 then
		return
	end

	local netname = G.ClientName(bs.client, C.MAX_MESSAGE_SIZE)
	--if this bot IS the team leader
	if QS.Q_strequal(netname, bs.teamleader) then
		G.BotAI_BotInitialChat(bs, "iamteamleader", nil)
		G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
		G.BotVoiceChatOnly(bs, -1, VC.STARTLEADER)
	end
end

function G.BotVoiceChat_WantOnDefense(bs, client, mode)
	local preference = G.BotGetTeamMateTaskPreference(bs, client)
	preference = bit32.band(preference, bit32.bnot(C.TEAMTP_ATTACKER))
	preference = bit32.bor(preference, C.TEAMTP_DEFENDER)
	G.BotSetTeamMateTaskPreference(bs, client, preference)
	--
	local netname = G.EasyClientName(client, C.MAX_NETNAME)
	G.BotAI_BotInitialChat(bs, "keepinmind", netname, nil)
	G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
	G.BotVoiceChatOnly(bs, client, VC.YES)
	G.trap_EA_Action(bs.client, C.ACTION_AFFIRMATIVE)
end

function G.BotVoiceChat_WantOnOffense(bs, client, mode)
	local preference = G.BotGetTeamMateTaskPreference(bs, client)
	preference = bit32.band(preference, bit32.bnot(C.TEAMTP_DEFENDER))
	preference = bit32.bor(preference, C.TEAMTP_ATTACKER)
	G.BotSetTeamMateTaskPreference(bs, client, preference)
	--
	local netname = G.EasyClientName(client, C.MAX_NETNAME)
	G.BotAI_BotInitialChat(bs, "keepinmind", netname, nil)
	G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
	G.BotVoiceChatOnly(bs, client, VC.YES)
	G.trap_EA_Action(bs.client, C.ACTION_AFFIRMATIVE)
end

function G.BotVoiceChat_Dummy(bs, client, mode)
end

local voiceCommands = {
	{ VC.GETFLAG, function(bs, c, m) G.BotVoiceChat_GetFlag(bs, c, m) end },
	{ VC.OFFENSE, function(bs, c, m) G.BotVoiceChat_Offense(bs, c, m) end },
	{ VC.DEFEND, function(bs, c, m) G.BotVoiceChat_Defend(bs, c, m) end },
	{ VC.DEFENDFLAG, function(bs, c, m) G.BotVoiceChat_DefendFlag(bs, c, m) end },
	{ VC.PATROL, function(bs, c, m) G.BotVoiceChat_Patrol(bs, c, m) end },
	{ VC.CAMP, function(bs, c, m) G.BotVoiceChat_Camp(bs, c, m) end },
	{ VC.FOLLOWME, function(bs, c, m) G.BotVoiceChat_FollowMe(bs, c, m) end },
	{ VC.FOLLOWFLAGCARRIER, function(bs, c, m) G.BotVoiceChat_FollowFlagCarrier(bs, c, m) end },
	{ VC.RETURNFLAG, function(bs, c, m) G.BotVoiceChat_ReturnFlag(bs, c, m) end },
	{ VC.STARTLEADER, function(bs, c, m) G.BotVoiceChat_StartLeader(bs, c, m) end },
	{ VC.STOPLEADER, function(bs, c, m) G.BotVoiceChat_StopLeader(bs, c, m) end },
	{ VC.WHOISLEADER, function(bs, c, m) G.BotVoiceChat_WhoIsLeader(bs, c, m) end },
	{ VC.WANTONDEFENSE, function(bs, c, m) G.BotVoiceChat_WantOnDefense(bs, c, m) end },
	{ VC.WANTONOFFENSE, function(bs, c, m) G.BotVoiceChat_WantOnOffense(bs, c, m) end },
}

-- advances pos (1-based) over non-blank characters, then over blanks
local function SkipTokenAndBlanks(buf, pos)
	local len = #buf
	while pos <= len and string.byte(buf, pos) > 32 do
		pos += 1
	end
	while pos <= len and string.byte(buf, pos) <= 32 do
		pos += 1
	end
	return pos
end

function G.BotVoiceChatCommand(bs, mode, voiceChat)
	if G.TeamPlayIsOn() == 0 then
		return false
	end

	if mode == C.SAY_ALL then
		return false -- don't do anything with voice chats to everyone
	end

	local buf = QS.Q_strncpyz(voiceChat, C.MAX_MESSAGE_SIZE)
	local cmd = 1
	cmd = SkipTokenAndBlanks(buf, cmd)
	local ptr = cmd
	cmd = SkipTokenAndBlanks(buf, cmd)
	local clientNum = QS.atoi(string.match(string.sub(buf, ptr, cmd - 1), "^%S*") or "")
	cmd = SkipTokenAndBlanks(buf, cmd)
	local cmdStr = string.sub(buf, cmd)

	if G.BotSameTeam(bs, clientNum) == 0 then
		return false
	end

	for i = 1, #voiceCommands do
		if QS.Q_strequal(cmdStr, voiceCommands[i][1]) then
			voiceCommands[i][2](bs, clientNum, mode)
			return true
		end
	end
	return false
end

return nil
