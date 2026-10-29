--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_team.c, part 1 of 3).

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
-- Luau port of ai_team.c, part 1 of 3. Team order helpers and CTF order generation.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_team")

-- match.h
local EC = "\x19"

-- voice chat names (ui/menudef.h)
local VOICECHAT_GETFLAG = "getflag"
local VOICECHAT_DEFEND = "defend"
local VOICECHAT_FOLLOWME = "followme"
local VOICECHAT_FOLLOWFLAGCARRIER = "followflagcarrier"
local VOICECHAT_RETURNFLAG = "returnflag"

-- ctf task preferences for a client
SF.ctftaskpreferences = {}
for i = 0, C.MAX_CLIENTS - 1 do
	SF.ctftaskpreferences[i] = { name = "", preference = 0 }
end

-- static int maxclients in BotNumTeamMates
SF.BotNumTeamMates_maxclients = 0
-- static int maxclients in BotSortTeamMatesByRelativeTravelTime2ddA
SF.BotSortTeamMatesByRelativeTravelTime2ddA_maxclients = 0

function G.BotValidTeamLeader(bs)
	if #bs.teamleader == 0 then return false end
	if G.ClientFromName(bs.teamleader) == -1 then return false end
	return true
end

function G.BotNumTeamMates(bs)
	if SF.BotNumTeamMates_maxclients == 0 then
		SF.BotNumTeamMates_maxclients = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end

	local numplayers = 0
	for i = 0, G.level.maxclients - 1 do
		local buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
		--if no config string or no name
		if #buf == 0 or #QS.Info_ValueForKey(buf, "n") == 0 then continue end
		--skip spectators
		if QS.atoi(QS.Info_ValueForKey(buf, "t")) == C.TEAM_SPECTATOR then continue end
		--
		if G.BotSameTeam(bs, i) ~= 0 then
			numplayers += 1
		end
	end
	return numplayers
end

function G.BotClientTravelTimeToGoal(client, goal)
	local ps = S.playerState_t()
	local areanum

	if G.BotAI_GetClientState(client, ps) ~= 0 then
		areanum = G.BotPointAreaNum(ps.origin)
	else
		areanum = 0
	end
	if areanum == 0 then return 1 end
	return G.trap_AAS_AreaTravelTimeToGoalArea(areanum, ps.origin, goal.areanum, C.TFL_DEFAULT)
end

function G.BotSortTeamMatesByBaseTravelTime(bs, teammates, maxteammates)
	local traveltimes = {}
	local goal = nil

	if G.gametype == C.GT_CTF or G.gametype == C.GT_1FCTF or G.gametype == C.GT_CTF_ELIMINATION then
		if G.BotTeam(bs) == C.TEAM_RED then
			goal = G.ctf_redflag
		else
			goal = G.ctf_blueflag
		end
	else
		if G.BotTeam(bs) == C.TEAM_RED then
			goal = G.redobelisk
		else
			goal = G.blueobelisk
		end
	end
	local numteammates = 0
	for i = 0, G.level.maxclients - 1 do
		local buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
		--if no config string or no name
		if #buf == 0 or #QS.Info_ValueForKey(buf, "n") == 0 then continue end
		--skip spectators
		if QS.atoi(QS.Info_ValueForKey(buf, "t")) == C.TEAM_SPECTATOR then continue end
		--
		if G.BotSameTeam(bs, i) ~= 0 then
			--
			local traveltime = G.BotClientTravelTimeToGoal(i, goal)
			--
			local j = 0
			while j < numteammates do
				if traveltime < traveltimes[j] then
					for k = numteammates, j + 1, -1 do
						traveltimes[k] = traveltimes[k - 1]
						teammates[k] = teammates[k - 1]
					end
					break
				end
				j += 1
			end
			traveltimes[j] = traveltime
			teammates[j] = i
			numteammates += 1
			if numteammates >= maxteammates then break end
		end
	end
	return numteammates
end

-- For Double Domination
function G.BotSortTeamMatesByRelativeTravelTime2ddA(bs, teammates, maxteammates)
	local traveltimes = {}
	local goalA = G.ctf_redflag
	local goalB = G.ctf_blueflag

	if SF.BotSortTeamMatesByRelativeTravelTime2ddA_maxclients == 0 then
		SF.BotSortTeamMatesByRelativeTravelTime2ddA_maxclients = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	local maxclients = SF.BotSortTeamMatesByRelativeTravelTime2ddA_maxclients

	local numteammates = 0

	local i = 0
	while i < maxclients and i < C.MAX_CLIENTS do
		local buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
		--if no config string or no name
		if #buf == 0 or #QS.Info_ValueForKey(buf, "n") == 0 then i += 1; continue end
		--skip spectators
		if QS.atoi(QS.Info_ValueForKey(buf, "t")) == C.TEAM_SPECTATOR then i += 1; continue end
		if G.BotSameTeam(bs, i) ~= 0 then
			local traveltime = G.BotClientTravelTimeToGoal(i, goalA) + 0.0
			local traveltime2b = G.BotClientTravelTimeToGoal(i, goalB) + 0.0
			traveltime = traveltime / traveltime2b

			local j = 0
			while j < numteammates do
				if traveltime < traveltimes[j] then
					for k = numteammates, j + 1, -1 do
						traveltimes[k] = traveltimes[k - 1]
						teammates[k] = teammates[k - 1]
					end
					break
				end
				j += 1
			end
			traveltimes[j] = traveltime
			teammates[j] = i
			numteammates += 1
			if numteammates >= maxteammates then break end
		end
		i += 1
	end

	return numteammates
end

function G.BotSetTeamMateTaskPreference(bs, teammate, preference)
	SF.ctftaskpreferences[teammate].preference = preference
	local teammatename = G.ClientName(teammate, C.MAX_NETNAME)
	SF.ctftaskpreferences[teammate].name = teammatename
end

function G.BotGetTeamMateTaskPreference(bs, teammate)
	if SF.ctftaskpreferences[teammate].preference == 0 then
		return 0
	end
	local teammatename = G.ClientName(teammate, C.MAX_NETNAME)
	if not QS.Q_strequal(teammatename, SF.ctftaskpreferences[teammate].name) then
		return 0
	end
	return SF.ctftaskpreferences[teammate].preference
end

function G.BotSortTeamMatesByTaskPreference(bs, teammates, numteammates)
	local defenders, attackers, roamers = {}, {}, {}
	local numdefenders, numattackers, numroamers = 0, 0, 0

	for i = 0, numteammates - 1 do
		local preference = G.BotGetTeamMateTaskPreference(bs, teammates[i])
		if bit32.band(preference, C.TEAMTP_DEFENDER) ~= 0 then
			defenders[numdefenders] = teammates[i]
			numdefenders += 1
		elseif bit32.band(preference, C.TEAMTP_ATTACKER) ~= 0 then
			attackers[numattackers] = teammates[i]
			numattackers += 1
		else
			roamers[numroamers] = teammates[i]
			numroamers += 1
		end
	end
	numteammates = 0
	--defenders at the front of the list
	for i = 0, numdefenders - 1 do
		teammates[numteammates + i] = defenders[i]
	end
	numteammates += numdefenders
	--roamers in the middle
	for i = 0, numroamers - 1 do
		teammates[numteammates + i] = roamers[i]
	end
	numteammates += numroamers
	--attacker in the back of the list
	for i = 0, numattackers - 1 do
		teammates[numteammates + i] = attackers[i]
	end
	numteammates += numattackers

	return numteammates
end

function G.BotSayTeamOrderAlways(bs, toclient)
	if G.bot_nochat.integer > 2 then return end

	--if the bot is talking to itself
	if bs.client == toclient then
		--don't show the message just put it in the console message queue
		local buf = G.trap_BotGetChatMessage(bs.cs, C.MAX_MESSAGE_SIZE)
		local name = G.ClientName(bs.client, C.MAX_NETNAME)
		local teamchat = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, EC .. "(%s" .. EC .. ")" .. EC .. ": %s", name, buf)
		G.trap_BotQueueConsoleMessage(bs.cs, C.CMS_CHAT, teamchat)
	else
		G.trap_BotEnterChat(bs.cs, toclient, C.CHAT_TELL)
	end
end

function G.BotSayTeamOrder(bs, toclient)
	G.BotSayTeamOrderAlways(bs, toclient)
end

function G.BotVoiceChat(bs, toclient, voicechat)
end

function G.BotVoiceChatOnly(bs, toclient, voicechat)
end

function G.BotSayVoiceTeamOrder(bs, toclient, voicechat)
end

function G.BotCTFOrders_BothFlagsNotAtBase(bs)
	local teammates = {}
	local other
	local name, carriername

	local numteammates = G.BotSortTeamMatesByBaseTravelTime(bs, teammates, C.MAX_CLIENTS * 4)
	G.BotSortTeamMatesByTaskPreference(bs, teammates, numteammates)
	--different orders based on the number of team mates
	local nt = bs.numteammates
	if nt == 1 then
	elseif nt == 2 then
		--tell the one not carrying the flag to attack the enemy base
		if teammates[0] ~= bs.flagcarrier then other = teammates[0] else other = teammates[1] end
		name = G.ClientName(other, C.MAX_NETNAME)
		if G.bot_nochat.integer < 3 then G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil) end
		G.BotSayTeamOrder(bs, other)
		G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_GETFLAG)
	elseif nt == 3 then
		--tell the one closest to the base not carrying the flag to accompany the flag carrier
		if teammates[0] ~= bs.flagcarrier then other = teammates[0] else other = teammates[1] end
		name = G.ClientName(other, C.MAX_NETNAME)
		if bs.flagcarrier ~= -1 then
			carriername = G.ClientName(bs.flagcarrier, C.MAX_NETNAME)
			if bs.flagcarrier == bs.client then
				if G.bot_nochat.integer < 3 then G.BotAI_BotInitialChat(bs, "cmd_accompanyme", name, nil) end
				if G.bot_nochat.integer < 3 then G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_FOLLOWME) end
			else
				if G.bot_nochat.integer < 3 then G.BotAI_BotInitialChat(bs, "cmd_accompany", name, carriername, nil) end
				if G.bot_nochat.integer < 3 then G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_FOLLOWFLAGCARRIER) end
			end
		else
			--
			if G.bot_nochat.integer < 3 then G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil) end
			if G.bot_nochat.integer < 3 then G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_GETFLAG) end
		end
		if G.bot_nochat.integer < 3 then G.BotSayTeamOrder(bs, other) end
		--tell the one furthest from the the base not carrying the flag to get the enemy flag
		if teammates[2] ~= bs.flagcarrier then other = teammates[2] else other = teammates[1] end
		name = G.ClientName(other, C.MAX_NETNAME)
		if G.bot_nochat.integer < 3 then G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil) end
		if G.bot_nochat.integer < 3 then G.BotSayTeamOrder(bs, other) end
		if G.bot_nochat.integer < 3 then G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_RETURNFLAG) end
	else
		local defenders = Q.trunc(numteammates * 0.4 + 0.5)
		if defenders > 4 then defenders = 4 end
		local attackers = Q.trunc(numteammates * 0.5 + 0.5)
		if attackers > 5 then attackers = 5 end
		if bs.flagcarrier ~= -1 then
			carriername = G.ClientName(bs.flagcarrier, C.MAX_NETNAME)
			for i = 0, defenders - 1 do
				--
				if teammates[i] == bs.flagcarrier then
					continue
				end
				--
				name = G.ClientName(teammates[i], C.MAX_NETNAME)
				if bs.flagcarrier == bs.client then
					if G.bot_nochat.integer < 3 then G.BotAI_BotInitialChat(bs, "cmd_accompanyme", name, nil) end
					if G.bot_nochat.integer < 3 then G.BotSayVoiceTeamOrder(bs, teammates[i], VOICECHAT_FOLLOWME) end
				else
					if G.bot_nochat.integer < 3 then G.BotAI_BotInitialChat(bs, "cmd_accompany", name, carriername, nil) end
					if G.bot_nochat.integer < 3 then G.BotSayVoiceTeamOrder(bs, teammates[i], VOICECHAT_FOLLOWFLAGCARRIER) end
				end
				if G.bot_nochat.integer < 3 then G.BotSayTeamOrder(bs, teammates[i]) end
			end
		else
			for i = 0, defenders - 1 do
				--
				if teammates[i] == bs.flagcarrier then
					continue
				end
				--
				name = G.ClientName(teammates[i], C.MAX_NETNAME)
				if G.bot_nochat.integer < 3 then G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil) end
				if G.bot_nochat.integer < 3 then G.BotSayVoiceTeamOrder(bs, teammates[i], VOICECHAT_GETFLAG) end
				if G.bot_nochat.integer < 3 then G.BotSayTeamOrder(bs, teammates[i]) end
			end
		end
		for i = 0, attackers - 1 do
			--
			if teammates[numteammates - i - 1] == bs.flagcarrier then
				continue
			end
			--
			name = G.ClientName(teammates[numteammates - i - 1], C.MAX_NETNAME)
			if G.bot_nochat.integer < 3 then G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil) end
			if G.bot_nochat.integer < 3 then G.BotSayTeamOrder(bs, teammates[numteammates - i - 1]) end
			if G.bot_nochat.integer < 3 then G.BotSayVoiceTeamOrder(bs, teammates[numteammates - i - 1], VOICECHAT_RETURNFLAG) end
		end
	end
end

function G.BotCTFOrders_FlagNotAtBase(bs)
	local teammates = {}
	local name
	if G.bot_nochat.integer > 2 then return end
	local numteammates = G.BotSortTeamMatesByBaseTravelTime(bs, teammates, C.MAX_CLIENTS * 4)
	G.BotSortTeamMatesByTaskPreference(bs, teammates, numteammates)
	--In oneway ctf we must all move out of the base (only one strategi, maybe we can also send some to the enemy base  to meet the flag carier?)
	--We must be defending
	if G.g_elimination_ctf_oneway.integer > 0 then
		for i = 0, numteammates - 1 do
			--
			name = G.ClientName(teammates[i], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
			G.BotSayTeamOrder(bs, teammates[i])
			G.BotSayVoiceTeamOrder(bs, teammates[i], VOICECHAT_GETFLAG)
		end
		return
	end

	local nt = bs.numteammates
	--passive strategy
	if bit32.band(bs.ctfstrategy, C.CTFS_AGRESSIVE) == 0 then
		--different orders based on the number of team mates
		if nt == 1 then
		elseif nt == 2 then
			-- keep one near the base for when the flag is returned
			name = G.ClientName(teammates[0], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_defendbase", name, nil)
			G.BotSayTeamOrder(bs, teammates[0])
			G.BotSayVoiceTeamOrder(bs, teammates[0], VOICECHAT_DEFEND)
			--
			name = G.ClientName(teammates[1], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
			G.BotSayTeamOrder(bs, teammates[1])
			G.BotSayVoiceTeamOrder(bs, teammates[1], VOICECHAT_GETFLAG)
		elseif nt == 3 then
			--keep one near the base for when the flag is returned
			name = G.ClientName(teammates[0], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_defendbase", name, nil)
			G.BotSayTeamOrder(bs, teammates[0])
			G.BotSayVoiceTeamOrder(bs, teammates[0], VOICECHAT_DEFEND)
			--the other two get the flag
			name = G.ClientName(teammates[1], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
			G.BotSayTeamOrder(bs, teammates[1])
			G.BotSayVoiceTeamOrder(bs, teammates[1], VOICECHAT_GETFLAG)
			--
			name = G.ClientName(teammates[2], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
			G.BotSayTeamOrder(bs, teammates[2])
			G.BotSayVoiceTeamOrder(bs, teammates[2], VOICECHAT_GETFLAG)
		else
			--keep some people near the base for when the flag is returned
			local defenders = Q.trunc(numteammates * 0.3 + 0.5)
			if defenders > 3 then defenders = 3 end
			local attackers = Q.trunc(numteammates * 0.6 + 0.5)
			if attackers > 6 then attackers = 6 end
			for i = 0, defenders - 1 do
				--
				name = G.ClientName(teammates[i], C.MAX_NETNAME)
				G.BotAI_BotInitialChat(bs, "cmd_defendbase", name, nil)
				G.BotSayTeamOrder(bs, teammates[i])
				G.BotSayVoiceTeamOrder(bs, teammates[i], VOICECHAT_DEFEND)
			end
			for i = 0, attackers - 1 do
				--
				name = G.ClientName(teammates[numteammates - i - 1], C.MAX_NETNAME)
				G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
				G.BotSayTeamOrder(bs, teammates[numteammates - i - 1])
				G.BotSayVoiceTeamOrder(bs, teammates[0], VOICECHAT_GETFLAG)
			end
		end
	else
		--different orders based on the number of team mates
		if nt == 1 then
		elseif nt == 2 then
			--both will go for the enemy flag
			name = G.ClientName(teammates[0], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
			G.BotSayTeamOrder(bs, teammates[0])
			G.BotSayVoiceTeamOrder(bs, teammates[0], VOICECHAT_GETFLAG)
			--
			name = G.ClientName(teammates[1], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
			G.BotSayTeamOrder(bs, teammates[1])
			G.BotSayVoiceTeamOrder(bs, teammates[1], VOICECHAT_GETFLAG)
		elseif nt == 3 then
			--everyone go for the flag
			name = G.ClientName(teammates[0], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
			G.BotSayTeamOrder(bs, teammates[0])
			G.BotSayVoiceTeamOrder(bs, teammates[0], VOICECHAT_GETFLAG)
			--
			name = G.ClientName(teammates[1], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
			G.BotSayTeamOrder(bs, teammates[1])
			G.BotSayVoiceTeamOrder(bs, teammates[1], VOICECHAT_GETFLAG)
			--
			name = G.ClientName(teammates[2], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
			G.BotSayTeamOrder(bs, teammates[2])
			G.BotSayVoiceTeamOrder(bs, teammates[2], VOICECHAT_GETFLAG)
		else
			--keep some people near the base for when the flag is returned
			local defenders = Q.trunc(numteammates * 0.2 + 0.5)
			if defenders > 2 then defenders = 2 end
			local attackers = Q.trunc(numteammates * 0.7 + 0.5)
			if attackers > 7 then attackers = 7 end
			for i = 0, defenders - 1 do
				--
				name = G.ClientName(teammates[i], C.MAX_NETNAME)
				G.BotAI_BotInitialChat(bs, "cmd_defendbase", name, nil)
				G.BotSayTeamOrder(bs, teammates[i])
				G.BotSayVoiceTeamOrder(bs, teammates[i], VOICECHAT_DEFEND)
			end
			for i = 0, attackers - 1 do
				--
				name = G.ClientName(teammates[numteammates - i - 1], C.MAX_NETNAME)
				G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
				G.BotSayTeamOrder(bs, teammates[numteammates - i - 1])
				G.BotSayVoiceTeamOrder(bs, teammates[numteammates - i - 1], VOICECHAT_GETFLAG)
			end
		end
	end
end

function G.BotCTFOrders_EnemyFlagNotAtBase(bs)
	local teammates = {}
	local other
	local name, carriername

	if G.bot_nochat.integer > 2 then return end

	local numteammates = G.BotSortTeamMatesByBaseTravelTime(bs, teammates, C.MAX_CLIENTS * 4)
	G.BotSortTeamMatesByTaskPreference(bs, teammates, numteammates)
	--different orders based on the number of team mates
	if numteammates == 1 then
	elseif numteammates == 2 then
		--tell the one not carrying the flag to defend the base
		if teammates[0] == bs.flagcarrier then other = teammates[1] else other = teammates[0] end
		name = G.ClientName(other, C.MAX_NETNAME)
		G.BotAI_BotInitialChat(bs, "cmd_defendbase", name, nil)
		G.BotSayTeamOrder(bs, other)
		G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_DEFEND)
	elseif numteammates == 3 then
		--tell the one closest to the base not carrying the flag to defend the base
		if teammates[0] ~= bs.flagcarrier then other = teammates[0] else other = teammates[1] end
		name = G.ClientName(other, C.MAX_NETNAME)
		G.BotAI_BotInitialChat(bs, "cmd_defendbase", name, nil)
		G.BotSayTeamOrder(bs, other)
		G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_DEFEND)
		--tell the other also to defend the base
		if teammates[2] ~= bs.flagcarrier then other = teammates[2] else other = teammates[1] end
		name = G.ClientName(other, C.MAX_NETNAME)
		G.BotAI_BotInitialChat(bs, "cmd_defendbase", name, nil)
		G.BotSayTeamOrder(bs, other)
		G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_DEFEND)
	else
		--60% will defend the base
		local defenders = Q.trunc(numteammates * 0.6 + 0.5)
		if defenders > 6 then defenders = 6 end
		--30% accompanies the flag carrier
		local attackers = Q.trunc(numteammates * 0.3 + 0.5)
		if attackers > 3 then attackers = 3 end
		for i = 0, defenders - 1 do
			--
			if teammates[i] == bs.flagcarrier then
				continue
			end
			name = G.ClientName(teammates[i], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_defendbase", name, nil)
			G.BotSayTeamOrder(bs, teammates[i])
			G.BotSayVoiceTeamOrder(bs, teammates[i], VOICECHAT_DEFEND)
		end
		-- if we have a flag carrier
		if bs.flagcarrier ~= -1 then
			carriername = G.ClientName(bs.flagcarrier, C.MAX_NETNAME)
			for i = 0, attackers - 1 do
				--
				if teammates[numteammates - i - 1] == bs.flagcarrier then
					continue
				end
				--
				name = G.ClientName(teammates[numteammates - i - 1], C.MAX_NETNAME)
				if bs.flagcarrier == bs.client then
					G.BotAI_BotInitialChat(bs, "cmd_accompanyme", name, nil)
					G.BotSayVoiceTeamOrder(bs, teammates[numteammates - i - 1], VOICECHAT_FOLLOWME)
				else
					G.BotAI_BotInitialChat(bs, "cmd_accompany", name, carriername, nil)
					G.BotSayVoiceTeamOrder(bs, teammates[numteammates - i - 1], VOICECHAT_FOLLOWFLAGCARRIER)
				end
				G.BotSayTeamOrder(bs, teammates[numteammates - i - 1])
			end
		else
			for i = 0, attackers - 1 do
				--
				if teammates[numteammates - i - 1] == bs.flagcarrier then
					continue
				end
				--
				name = G.ClientName(teammates[numteammates - i - 1], C.MAX_NETNAME)
				G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
				G.BotSayVoiceTeamOrder(bs, teammates[numteammates - i - 1], VOICECHAT_GETFLAG)
				G.BotSayTeamOrder(bs, teammates[numteammates - i - 1])
			end
		end
	end
end

return nil
