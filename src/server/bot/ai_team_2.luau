--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_team.c).

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
-- Luau port of ai_team.c, part 2 of 3. (double domination / CTF / 1FCTF team orders)

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_team")

-- voice chat names from ui/menudef.h
local VOICECHAT_GETFLAG = "getflag"
local VOICECHAT_OFFENSE = "offense"
local VOICECHAT_DEFEND = "defend"
local VOICECHAT_FOLLOWME = "followme"
local VOICECHAT_FOLLOWFLAGCARRIER = "followflagcarrier"

-- sizeof(teammates) in the QVM: MAX_CLIENTS ints
local TEAMMATES_SIZE = C.MAX_CLIENTS * 4

local function SayOrder(bs, cmd, client, voice)
	local name = G.ClientName(client, C.MAX_NETNAME)
	G.BotAI_BotInitialChat(bs, cmd, name, nil)
	G.BotSayTeamOrder(bs, client)
	G.BotSayVoiceTeamOrder(bs, client, voice)
end

function G.BotDDorders_Standard(bs)
	local teammates = {}

	if G.bot_nochat.integer > 2 then return end

	--sort team mates by travel time to base
	local numteammates = G.BotSortTeamMatesByRelativeTravelTime2ddA(bs, teammates, TEAMMATES_SIZE)

	if numteammates == 1 then
		-- nothing
	else
		for i = 0, Q.idiv(numteammates, 2) - 1 do --Half take point A
			local name = G.ClientName(teammates[i], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_takea", name, nil)
			G.BotSayTeamOrder(bs, teammates[i])
		end
		for i = Q.idiv(numteammates, 2) + 1, numteammates - 1 do --Rest takes point B
			local name = G.ClientName(teammates[i], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_takeb", name, nil)
			G.BotSayTeamOrder(bs, teammates[i])
		end
	end
end

function G.BotCTFOrders_BothFlagsAtBase(bs)
	local teammates = {}

	if G.bot_nochat.integer > 2 then return end

	--sort team mates by travel time to base
	local numteammates = G.BotSortTeamMatesByBaseTravelTime(bs, teammates, TEAMMATES_SIZE)
	--sort team mates by CTF preference
	G.BotSortTeamMatesByTaskPreference(bs, teammates, numteammates)

	local weAreAttacking = false

	if G.g_elimination_ctf_oneway.integer > 0 then
		--See if we are attacking:
		if Q.imod(G.level.eliminationSides + G.level.roundNumber, 2) == 0 and G.BotTeam(bs) == C.TEAM_RED then
			weAreAttacking = true
		end

		if weAreAttacking then
			for i = 0, numteammates - 1 do
				SayOrder(bs, "cmd_getflag", teammates[i], VOICECHAT_GETFLAG)
			end
		else
			for i = 0, numteammates - 1 do
				SayOrder(bs, "cmd_defendbase", teammates[i], VOICECHAT_DEFEND)
			end
		end
		return --Sago: Or the leader will make a counter order.
	end

	--passive strategy
	if bit32.band(bs.ctfstrategy, C.CTFS_AGRESSIVE) == 0 then
		--different orders based on the number of team mates
		if numteammates == 1 then
			-- nothing
		elseif numteammates == 2 then
			--the one closest to the base will defend the base
			SayOrder(bs, "cmd_defendbase", teammates[0], VOICECHAT_DEFEND)
			--the other will get the flag
			SayOrder(bs, "cmd_getflag", teammates[1], VOICECHAT_GETFLAG)
		elseif numteammates == 3 then
			--the one closest to the base will defend the base
			SayOrder(bs, "cmd_defendbase", teammates[0], VOICECHAT_DEFEND)
			--the second one closest to the base will defend the base
			SayOrder(bs, "cmd_defendbase", teammates[1], VOICECHAT_DEFEND)
			--the other will get the flag
			SayOrder(bs, "cmd_getflag", teammates[2], VOICECHAT_GETFLAG)
		else
			local defenders = Q.trunc(numteammates * 0.5 + 0.5)
			if defenders > 5 then defenders = 5 end
			local attackers = Q.trunc(numteammates * 0.4 + 0.5)
			if attackers > 4 then attackers = 4 end
			for i = 0, defenders - 1 do
				SayOrder(bs, "cmd_defendbase", teammates[i], VOICECHAT_DEFEND)
			end
			for i = 0, attackers - 1 do
				SayOrder(bs, "cmd_getflag", teammates[numteammates - i - 1], VOICECHAT_GETFLAG)
			end
		end
	else
		--different orders based on the number of team mates
		if numteammates == 1 then
			-- nothing
		elseif numteammates == 2 then
			--the one closest to the base will defend the base
			SayOrder(bs, "cmd_defendbase", teammates[0], VOICECHAT_DEFEND)
			--the other will get the flag
			SayOrder(bs, "cmd_getflag", teammates[1], VOICECHAT_GETFLAG)
		elseif numteammates == 3 then
			--the one closest to the base will defend the base
			SayOrder(bs, "cmd_defendbase", teammates[0], VOICECHAT_DEFEND)
			--the others should go for the enemy flag
			SayOrder(bs, "cmd_getflag", teammates[1], VOICECHAT_GETFLAG)
			SayOrder(bs, "cmd_getflag", teammates[2], VOICECHAT_GETFLAG)
		else
			local defenders = Q.trunc(numteammates * 0.4 + 0.5)
			if defenders > 4 then defenders = 4 end
			local attackers = Q.trunc(numteammates * 0.5 + 0.5)
			if attackers > 5 then attackers = 5 end
			for i = 0, defenders - 1 do
				SayOrder(bs, "cmd_defendbase", teammates[i], VOICECHAT_DEFEND)
			end
			for i = 0, attackers - 1 do
				SayOrder(bs, "cmd_getflag", teammates[numteammates - i - 1], VOICECHAT_GETFLAG)
			end
		end
	end
end

function G.BotCTFOrders(bs)
	local flagstatus
	if G.BotTeam(bs) == C.TEAM_RED then
		flagstatus = bs.redflagstatus * 2 + bs.blueflagstatus
	else
		flagstatus = bs.blueflagstatus * 2 + bs.redflagstatus
	end
	if flagstatus == 0 then G.BotCTFOrders_BothFlagsAtBase(bs)
	elseif flagstatus == 1 then G.BotCTFOrders_EnemyFlagNotAtBase(bs)
	elseif flagstatus == 2 then G.BotCTFOrders_FlagNotAtBase(bs)
	elseif flagstatus == 3 then G.BotCTFOrders_BothFlagsNotAtBase(bs)
	end
end

function G.BotDDorders(bs)
	G.BotDDorders_Standard(bs)
end

function G.BotCreateGroup(bs, teammates, groupsize)
	if G.bot_nochat.integer > 2 then return end

	-- the others in the group will follow the teammates[0]
	local leadername = G.ClientName(teammates[0], C.MAX_NETNAME)
	for i = 1, groupsize - 1 do
		local name = G.ClientName(teammates[i], C.MAX_NETNAME)
		if teammates[0] == bs.client then
			G.BotAI_BotInitialChat(bs, "cmd_accompanyme", name, nil)
		else
			G.BotAI_BotInitialChat(bs, "cmd_accompany", name, leadername, nil)
		end
		G.BotSayTeamOrderAlways(bs, teammates[i])
	end
end

-- &teammates[offset]
local function SubArray(arr, offset, count)
	local sub = {}
	for k = 0, count - 1 do
		sub[k] = arr[offset + k]
	end
	return sub
end

function G.BotTeamOrders(bs)
	local teammates = {}
	local numteammates = 0
	for i = 0, G.level.maxclients - 1 do
		local buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
		--if no config string or no name
		if #buf == 0 or #QS.Info_ValueForKey(buf, "n") == 0 then continue end
		--skip spectators
		if QS.atoi(QS.Info_ValueForKey(buf, "t")) == C.TEAM_SPECTATOR then continue end
		--
		if G.BotSameTeam(bs, i) ~= 0 then
			teammates[numteammates] = i
			numteammates += 1
		end
	end
	--
	if numteammates == 1 then
		-- nothing
	elseif numteammates == 2 then
		--nothing special
	elseif numteammates == 3 then
		--have one follow another and one free roaming
		G.BotCreateGroup(bs, teammates, 2)
	elseif numteammates == 4 then
		G.BotCreateGroup(bs, teammates, 2) --a group of 2
		G.BotCreateGroup(bs, SubArray(teammates, 2, 2), 2) --a group of 2
	elseif numteammates == 5 then
		G.BotCreateGroup(bs, teammates, 2) --a group of 2
		G.BotCreateGroup(bs, SubArray(teammates, 2, 3), 3) --a group of 3
	else
		if numteammates <= 10 then
			for i = 0, Q.idiv(numteammates, 2) - 1 do
				G.BotCreateGroup(bs, SubArray(teammates, i * 2, 2), 2) --groups of 2
			end
		end
	end
end

function G.Bot1FCTFOrders_FlagAtCenter(bs)
	local teammates = {}

	if G.bot_nochat.integer > 2 then return end

	--sort team mates by travel time to base
	local numteammates = G.BotSortTeamMatesByBaseTravelTime(bs, teammates, TEAMMATES_SIZE)
	--sort team mates by CTF preference
	G.BotSortTeamMatesByTaskPreference(bs, teammates, numteammates)
	--passive strategy
	if bit32.band(bs.ctfstrategy, C.CTFS_AGRESSIVE) == 0 then
		if numteammates == 1 then
			-- nothing
		elseif numteammates == 2 then
			--the one closest to the base will defend the base
			SayOrder(bs, "cmd_defendbase", teammates[0], VOICECHAT_DEFEND)
			--the other will get the flag
			SayOrder(bs, "cmd_getflag", teammates[1], VOICECHAT_GETFLAG)
		elseif numteammates == 3 then
			--the one closest to the base will defend the base
			SayOrder(bs, "cmd_defendbase", teammates[0], VOICECHAT_DEFEND)
			--the second one closest to the base will defend the base
			local name = G.ClientName(teammates[1], C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_defendbase", name, nil)
			G.BotSayTeamOrder(bs, teammates[1])
			G.BotSayVoiceTeamOrder(bs, teammates[0], VOICECHAT_DEFEND)
			--the other will get the flag
			SayOrder(bs, "cmd_getflag", teammates[2], VOICECHAT_GETFLAG)
		else
			--50% defend the base
			local defenders = Q.trunc(numteammates * 0.5 + 0.5)
			if defenders > 5 then defenders = 5 end
			--40% get the flag
			local attackers = Q.trunc(numteammates * 0.4 + 0.5)
			if attackers > 4 then attackers = 4 end
			for i = 0, defenders - 1 do
				SayOrder(bs, "cmd_defendbase", teammates[i], VOICECHAT_DEFEND)
			end
			for i = 0, attackers - 1 do
				SayOrder(bs, "cmd_getflag", teammates[numteammates - i - 1], VOICECHAT_GETFLAG)
			end
		end
	else --agressive
		if numteammates == 1 then
			-- nothing
		elseif numteammates == 2 then
			--the one closest to the base will defend the base
			SayOrder(bs, "cmd_defendbase", teammates[0], VOICECHAT_DEFEND)
			--the other will get the flag
			SayOrder(bs, "cmd_getflag", teammates[1], VOICECHAT_GETFLAG)
		elseif numteammates == 3 then
			--the one closest to the base will defend the base
			SayOrder(bs, "cmd_defendbase", teammates[0], VOICECHAT_DEFEND)
			--the others should go for the enemy flag
			SayOrder(bs, "cmd_getflag", teammates[1], VOICECHAT_GETFLAG)
			SayOrder(bs, "cmd_getflag", teammates[2], VOICECHAT_GETFLAG)
		else
			--30% defend the base
			local defenders = Q.trunc(numteammates * 0.3 + 0.5)
			if defenders > 3 then defenders = 3 end
			--60% get the flag
			local attackers = Q.trunc(numteammates * 0.6 + 0.5)
			if attackers > 6 then attackers = 6 end
			for i = 0, defenders - 1 do
				SayOrder(bs, "cmd_defendbase", teammates[i], VOICECHAT_DEFEND)
			end
			for i = 0, attackers - 1 do
				SayOrder(bs, "cmd_getflag", teammates[numteammates - i - 1], VOICECHAT_GETFLAG)
			end
		end
	end
end

function G.Bot1FCTFOrders_TeamHasFlag(bs)
	local teammates = {}
	local other

	if G.bot_nochat.integer > 2 then return end

	--sort team mates by travel time to base
	local numteammates = G.BotSortTeamMatesByBaseTravelTime(bs, teammates, TEAMMATES_SIZE)
	--sort team mates by CTF preference
	G.BotSortTeamMatesByTaskPreference(bs, teammates, numteammates)
	--passive strategy
	if bit32.band(bs.ctfstrategy, C.CTFS_AGRESSIVE) == 0 then
		if numteammates == 1 then
			-- nothing
		elseif numteammates == 2 then
			--tell the one not carrying the flag to attack the enemy base
			if teammates[0] == bs.flagcarrier then other = teammates[1] else other = teammates[0] end
			local name = G.ClientName(other, C.MAX_NETNAME)
			G.BotAI_BotInitialChat(bs, "cmd_attackenemybase", name, nil)
			G.BotSayTeamOrder(bs, other)
			G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_OFFENSE)
		elseif numteammates == 3 then
			--tell the one closest to the base not carrying the flag to defend the base
			if teammates[0] ~= bs.flagcarrier then other = teammates[0] else other = teammates[1] end
			SayOrder(bs, "cmd_defendbase", other, VOICECHAT_DEFEND)
			--tell the one furthest from the base not carrying the flag to accompany the flag carrier
			if teammates[2] ~= bs.flagcarrier then other = teammates[2] else other = teammates[1] end
			local name = G.ClientName(other, C.MAX_NETNAME)
			if bs.flagcarrier ~= -1 then
				local carriername = G.ClientName(bs.flagcarrier, C.MAX_NETNAME)
				if bs.flagcarrier == bs.client then
					G.BotAI_BotInitialChat(bs, "cmd_accompanyme", name, nil)
					G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_FOLLOWME)
				else
					G.BotAI_BotInitialChat(bs, "cmd_accompany", name, carriername, nil)
					G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_FOLLOWFLAGCARRIER)
				end
			else
				G.BotAI_BotInitialChat(bs, "cmd_getflag", name, nil)
				G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_GETFLAG)
			end
			G.BotSayTeamOrder(bs, other)
		else
			--30% will defend the base
			local defenders = Q.trunc(numteammates * 0.3 + 0.5)
			if defenders > 3 then defenders = 3 end
			--70% accompanies the flag carrier
			local attackers = Q.trunc(numteammates * 0.7 + 0.5)
			if attackers > 7 then attackers = 7 end
			for i = 0, defenders - 1 do
				if teammates[i] == bs.flagcarrier then
					continue
				end
				SayOrder(bs, "cmd_defendbase", teammates[i], VOICECHAT_DEFEND)
			end
			if bs.flagcarrier ~= -1 then
				local carriername = G.ClientName(bs.flagcarrier, C.MAX_NETNAME)
				for i = 0, attackers - 1 do
					if teammates[numteammates - i - 1] == bs.flagcarrier then
						continue
					end
					local name = G.ClientName(teammates[numteammates - i - 1], C.MAX_NETNAME)
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
					if teammates[numteammates - i - 1] == bs.flagcarrier then
						continue
					end
					SayOrder(bs, "cmd_getflag", teammates[numteammates - i - 1], VOICECHAT_GETFLAG)
				end
			end
		end
	else --agressive
		if numteammates == 1 then
			-- nothing
		elseif numteammates == 2 then
			--tell the one not carrying the flag to defend the base
			if teammates[0] == bs.flagcarrier then other = teammates[1] else other = teammates[0] end
			SayOrder(bs, "cmd_defendbase", other, VOICECHAT_DEFEND)
		elseif numteammates == 3 then
			--tell the one closest to the base not carrying the flag to defend the base
			if teammates[0] ~= bs.flagcarrier then other = teammates[0] else other = teammates[1] end
			SayOrder(bs, "cmd_defendbase", other, VOICECHAT_DEFEND)
			--tell the one furthest from the base not carrying the flag to accompany the flag carrier
			if teammates[2] ~= bs.flagcarrier then other = teammates[2] else other = teammates[1] end
			local name = G.ClientName(other, C.MAX_NETNAME)
			local carriername = G.ClientName(bs.flagcarrier, C.MAX_NETNAME)
			if bs.flagcarrier == bs.client then
				G.BotAI_BotInitialChat(bs, "cmd_accompanyme", name, nil)
				G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_FOLLOWME)
			else
				G.BotAI_BotInitialChat(bs, "cmd_accompany", name, carriername, nil)
				G.BotSayVoiceTeamOrder(bs, other, VOICECHAT_FOLLOWFLAGCARRIER)
			end
			G.BotSayTeamOrder(bs, other)
		else
			--20% will defend the base
			local defenders = Q.trunc(numteammates * 0.2 + 0.5)
			if defenders > 2 then defenders = 2 end
			--80% accompanies the flag carrier
			local attackers = Q.trunc(numteammates * 0.8 + 0.5)
			if attackers > 8 then attackers = 8 end
			for i = 0, defenders - 1 do
				if teammates[i] == bs.flagcarrier then
					continue
				end
				SayOrder(bs, "cmd_defendbase", teammates[i], VOICECHAT_DEFEND)
			end
			local carriername = G.ClientName(bs.flagcarrier, C.MAX_NETNAME)
			for i = 0, attackers - 1 do
				if teammates[numteammates - i - 1] == bs.flagcarrier then
					continue
				end
				local name = G.ClientName(teammates[numteammates - i - 1], C.MAX_NETNAME)
				if bs.flagcarrier == bs.client then
					G.BotAI_BotInitialChat(bs, "cmd_accompanyme", name, nil)
					G.BotSayVoiceTeamOrder(bs, teammates[numteammates - i - 1], VOICECHAT_FOLLOWME)
				else
					G.BotAI_BotInitialChat(bs, "cmd_accompany", name, carriername, nil)
					G.BotSayVoiceTeamOrder(bs, teammates[numteammates - i - 1], VOICECHAT_FOLLOWFLAGCARRIER)
				end
				G.BotSayTeamOrder(bs, teammates[numteammates - i - 1])
			end
		end
	end
end

return nil
