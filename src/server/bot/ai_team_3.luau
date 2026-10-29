--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_team.c, part 3 of 3).

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
-- Luau port of ai_team.c, part 3 of 3. 1FCTF, obelisk and harvester orders, human team leader search and BotTeamAI.

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
local VOICECHAT_STARTLEADER = "startleader"

-- the C code repeats this four-statement sequence for every order
local function GiveOrder(bs, mate, cmd, voice)
	local name = G.ClientName(mate, C.MAX_NETNAME)
	G.BotAI_BotInitialChat(bs, cmd, name)
	G.BotSayTeamOrder(bs, mate)
	G.BotSayVoiceTeamOrder(bs, mate, voice)
end

-- shared shape of the "default" (more than 3 team mates) branches
local function GiveOrdersByShare(bs, teammates, numteammates, defenders, attackers, cmd2, voice2)
	for i = 0, defenders - 1 do
		GiveOrder(bs, teammates[i], "cmd_defendbase", VOICECHAT_DEFEND)
	end
	for i = 0, attackers - 1 do
		GiveOrder(bs, teammates[numteammates - i - 1], cmd2, voice2)
	end
end

local function SortedTeamMates(bs)
	local teammates = {}
	local numteammates = G.BotSortTeamMatesByBaseTravelTime(bs, teammates, C.MAX_CLIENTS * 4)
	G.BotSortTeamMatesByTaskPreference(bs, teammates, numteammates)
	return teammates, numteammates
end

function G.Bot1FCTFOrders_EnemyHasFlag(bs)
	if G.bot_nochat.integer > 2 then return end

	local teammates, numteammates = SortedTeamMates(bs)
	if bit32.band(bs.ctfstrategy, C.CTFS_AGRESSIVE) == 0 then
		if numteammates == 1 then
		elseif numteammates == 2 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_defendbase", VOICECHAT_DEFEND)
		elseif numteammates == 3 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[2], "cmd_defendbase", VOICECHAT_DEFEND)
		else
			local defenders = Q.trunc(numteammates * 0.8 + 0.5)
			if defenders > 8 then defenders = 8 end
			local attackers = Q.trunc(numteammates * 0.1 + 0.5)
			if attackers > 1 then attackers = 1 end
			GiveOrdersByShare(bs, teammates, numteammates, defenders, attackers, "cmd_returnflag", VOICECHAT_GETFLAG)
		end
	else
		if numteammates == 1 then
		elseif numteammates == 2 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_defendbase", VOICECHAT_DEFEND)
		elseif numteammates == 3 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[2], "cmd_returnflag", VOICECHAT_GETFLAG)
		else
			local defenders = Q.trunc(numteammates * 0.7 + 0.5)
			if defenders > 7 then defenders = 7 end
			local attackers = Q.trunc(numteammates * 0.2 + 0.5)
			if attackers > 2 then attackers = 2 end
			GiveOrdersByShare(bs, teammates, numteammates, defenders, attackers, "cmd_returnflag", VOICECHAT_GETFLAG)
		end
	end
end

function G.Bot1FCTFOrders_EnemyDroppedFlag(bs)
	if G.bot_nochat.integer > 2 then return end

	local teammates, numteammates = SortedTeamMates(bs)
	if bit32.band(bs.ctfstrategy, C.CTFS_AGRESSIVE) == 0 then
		if numteammates == 1 then
		elseif numteammates == 2 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_getflag", VOICECHAT_GETFLAG)
		elseif numteammates == 3 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[2], "cmd_getflag", VOICECHAT_GETFLAG)
		else
			local defenders = Q.trunc(numteammates * 0.5 + 0.5)
			if defenders > 5 then defenders = 5 end
			local attackers = Q.trunc(numteammates * 0.4 + 0.5)
			if attackers > 4 then attackers = 4 end
			GiveOrdersByShare(bs, teammates, numteammates, defenders, attackers, "cmd_getflag", VOICECHAT_GETFLAG)
		end
	else
		if numteammates == 1 then
		elseif numteammates == 2 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_getflag", VOICECHAT_GETFLAG)
		elseif numteammates == 3 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_getflag", VOICECHAT_GETFLAG)
			GiveOrder(bs, teammates[2], "cmd_getflag", VOICECHAT_GETFLAG)
		else
			local defenders = Q.trunc(numteammates * 0.3 + 0.5)
			if defenders > 3 then defenders = 3 end
			local attackers = Q.trunc(numteammates * 0.6 + 0.5)
			if attackers > 6 then attackers = 6 end
			GiveOrdersByShare(bs, teammates, numteammates, defenders, attackers, "cmd_getflag", VOICECHAT_GETFLAG)
		end
	end
end

function G.Bot1FCTFOrders(bs)
	local status = bs.neutralflagstatus
	if status == 0 then
		G.Bot1FCTFOrders_FlagAtCenter(bs)
	elseif status == 1 then
		G.Bot1FCTFOrders_TeamHasFlag(bs)
	elseif status == 2 then
		G.Bot1FCTFOrders_EnemyHasFlag(bs)
	elseif status == 3 then
		G.Bot1FCTFOrders_EnemyDroppedFlag(bs)
	end
end

function G.BotObeliskOrders(bs)
	if G.bot_nochat.integer > 2 then return end

	local teammates, numteammates = SortedTeamMates(bs)
	if bit32.band(bs.ctfstrategy, C.CTFS_AGRESSIVE) == 0 then
		if numteammates == 1 then
		elseif numteammates == 2 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_attackenemybase", VOICECHAT_OFFENSE)
		elseif numteammates == 3 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[2], "cmd_attackenemybase", VOICECHAT_OFFENSE)
		else
			local defenders = Q.trunc(numteammates * 0.5 + 0.5)
			if defenders > 5 then defenders = 5 end
			local attackers = Q.trunc(numteammates * 0.4 + 0.5)
			if attackers > 4 then attackers = 4 end
			GiveOrdersByShare(bs, teammates, numteammates, defenders, attackers, "cmd_attackenemybase", VOICECHAT_OFFENSE)
		end
	else
		if numteammates == 1 then
		elseif numteammates == 2 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_attackenemybase", VOICECHAT_OFFENSE)
		elseif numteammates == 3 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_attackenemybase", VOICECHAT_OFFENSE)
			GiveOrder(bs, teammates[2], "cmd_attackenemybase", VOICECHAT_OFFENSE)
		else
			local defenders = Q.trunc(numteammates * 0.3 + 0.5)
			if defenders > 3 then defenders = 3 end
			local attackers = Q.trunc(numteammates * 0.7 + 0.5)
			if attackers > 7 then attackers = 7 end
			GiveOrdersByShare(bs, teammates, numteammates, defenders, attackers, "cmd_attackenemybase", VOICECHAT_OFFENSE)
		end
	end
end

function G.BotHarvesterOrders(bs)
	if G.bot_nochat.integer > 2 then return end

	local teammates, numteammates = SortedTeamMates(bs)
	if bit32.band(bs.ctfstrategy, C.CTFS_AGRESSIVE) == 0 then
		if numteammates == 1 then
		elseif numteammates == 2 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_harvest", VOICECHAT_OFFENSE)
		elseif numteammates == 3 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[2], "cmd_harvest", VOICECHAT_OFFENSE)
		else
			local defenders = Q.trunc(numteammates * 0.5 + 0.5)
			if defenders > 5 then defenders = 5 end
			local attackers = Q.trunc(numteammates * 0.4 + 0.5)
			if attackers > 4 then attackers = 4 end
			GiveOrdersByShare(bs, teammates, numteammates, defenders, attackers, "cmd_harvest", VOICECHAT_OFFENSE)
		end
	else
		if numteammates == 1 then
		elseif numteammates == 2 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_harvest", VOICECHAT_OFFENSE)
		elseif numteammates == 3 then
			GiveOrder(bs, teammates[0], "cmd_defendbase", VOICECHAT_DEFEND)
			GiveOrder(bs, teammates[1], "cmd_harvest", VOICECHAT_OFFENSE)
			GiveOrder(bs, teammates[2], "cmd_harvest", VOICECHAT_OFFENSE)
		else
			local defenders = Q.trunc(numteammates * 0.3 + 0.5)
			if defenders > 3 then defenders = 3 end
			local attackers = Q.trunc(numteammates * 0.7 + 0.5)
			if attackers > 7 then attackers = 7 end
			GiveOrdersByShare(bs, teammates, numteammates, defenders, attackers, "cmd_harvest", VOICECHAT_OFFENSE)
		end
	end
end

function G.FindHumanTeamLeader(bs)
	for i = 0, C.MAX_CLIENTS - 1 do
		if G.g_entities[i].inuse then
			if bit32.band(G.g_entities[i].r.svFlags, C.SVF_BOT) == 0 then
				if G.notleader[i] == 0 or G.notleader[i] == false or G.notleader[i] == nil then
					if G.BotSameTeam(bs, i) ~= 0 then
						bs.teamleader = G.ClientName(i, C.MAX_NETNAME)
						if G.BotSetLastOrderedTask(bs) == 0 then
							if G.bot_nochat.integer < 3 then G.BotVoiceChat_Defend(bs, i, C.SAY_TELL) end
						end
						return 1
					end
				end
			end
		end
	end
	return 0
end

G.lastRoundNumber = 0 -- used to give new orders every round

function G.BotTeamAI(bs)
	if G.bot_nochat.integer > 2 then return end

	if G.gametype < C.GT_TEAM or G.g_ffa_gt == 1 then
		return
	end
	if G.BotValidTeamLeader(bs) == 0 then
		if G.FindHumanTeamLeader(bs) == 0 then
			if bs.askteamleader_time == 0 and bs.becometeamleader_time == 0 then
				if bs.entergame_time + 10 > G.floattime then
					bs.askteamleader_time = G.floattime + 5 + Q.random() * 10
				else
					bs.becometeamleader_time = G.floattime + 5 + Q.random() * 10
				end
			end
			if bs.askteamleader_time ~= 0 and bs.askteamleader_time < G.floattime then
				G.BotAI_BotInitialChat(bs, "whoisteamleader")
				G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
				bs.askteamleader_time = 0
				bs.becometeamleader_time = G.floattime + 8 + Q.random() * 10
			end
			if bs.becometeamleader_time ~= 0 and bs.becometeamleader_time < G.floattime then
				G.BotAI_BotInitialChat(bs, "iamteamleader")
				G.trap_BotEnterChat(bs.cs, 0, C.CHAT_TEAM)
				G.BotSayVoiceTeamOrder(bs, -1, VOICECHAT_STARTLEADER)
				local netname = G.ClientName(bs.client, C.MAX_NETNAME)
				bs.teamleader = QS.Q_strncpyz(netname, C.MAX_NETNAME)
				bs.becometeamleader_time = 0
			end
			return
		end
	end
	bs.askteamleader_time = 0
	bs.becometeamleader_time = 0

	local netname = G.ClientName(bs.client, C.MAX_NETNAME)
	if not QS.Q_strequal(netname, bs.teamleader) then
		return
	end
	local numteammates = G.BotNumTeamMates(bs)
	local gametype = G.gametype
	if gametype == C.GT_TEAM then
		if bs.numteammates ~= numteammates or bs.forceorders ~= 0 then
			bs.teamgiveorders_time = G.floattime
			bs.numteammates = numteammates
			bs.forceorders = 0
		end
		if bs.teamgiveorders_time ~= 0 and bs.teamgiveorders_time < G.floattime - 5 then
			G.BotTeamOrders(bs)
			bs.teamgiveorders_time = G.floattime + 120
		end
	elseif gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION then
		if bs.numteammates ~= numteammates or bs.flagstatuschanged ~= 0 or bs.forceorders ~= 0 or G.lastRoundNumber ~= G.level.roundNumber then
			bs.teamgiveorders_time = G.floattime
			bs.numteammates = numteammates
			bs.flagstatuschanged = 0
			bs.forceorders = 0
			G.lastRoundNumber = G.level.roundNumber
		end
		if bs.lastflagcapture_time < G.floattime - 240 then
			bs.lastflagcapture_time = G.floattime
			if Q.random() < 0.4 then
				bs.ctfstrategy = bit32.bxor(bs.ctfstrategy, C.CTFS_AGRESSIVE)
				bs.teamgiveorders_time = G.floattime
			end
		end
		if bs.teamgiveorders_time ~= 0 and bs.teamgiveorders_time < G.floattime - 3 then
			G.BotCTFOrders(bs)
			bs.teamgiveorders_time = 0
		end
	elseif gametype == C.GT_DOUBLE_D then
		if bs.numteammates ~= numteammates or bs.flagstatuschanged ~= 0 or bs.forceorders ~= 0 then
			bs.teamgiveorders_time = G.floattime
			bs.numteammates = numteammates
			bs.flagstatuschanged = 0
			bs.forceorders = 0
		end
		if bs.teamgiveorders_time ~= 0 and bs.teamgiveorders_time < G.floattime - 3 then
			G.BotDDorders(bs)
			bs.teamgiveorders_time = 0
		end
	elseif gametype == C.GT_1FCTF then
		if bs.numteammates ~= numteammates or bs.flagstatuschanged ~= 0 or bs.forceorders ~= 0 then
			bs.teamgiveorders_time = G.floattime
			bs.numteammates = numteammates
			bs.flagstatuschanged = 0
			bs.forceorders = 0
		end
		if bs.lastflagcapture_time < G.floattime - 240 then
			bs.lastflagcapture_time = G.floattime
			if Q.random() < 0.4 then
				bs.ctfstrategy = bit32.bxor(bs.ctfstrategy, C.CTFS_AGRESSIVE)
				bs.teamgiveorders_time = G.floattime
			end
		end
		if bs.teamgiveorders_time ~= 0 and bs.teamgiveorders_time < G.floattime - 2 then
			G.Bot1FCTFOrders(bs)
			bs.teamgiveorders_time = 0
		end
	elseif gametype == C.GT_OBELISK then
		if bs.numteammates ~= numteammates or bs.forceorders ~= 0 then
			bs.teamgiveorders_time = G.floattime
			bs.numteammates = numteammates
			bs.forceorders = 0
		end
		if bs.teamgiveorders_time ~= 0 and bs.teamgiveorders_time < G.floattime - 5 then
			G.BotObeliskOrders(bs)
			bs.teamgiveorders_time = G.floattime + 30
		end
	elseif gametype == C.GT_HARVESTER then
		if bs.numteammates ~= numteammates or bs.forceorders ~= 0 then
			bs.teamgiveorders_time = G.floattime
			bs.numteammates = numteammates
			bs.forceorders = 0
		end
		if bs.teamgiveorders_time ~= 0 and bs.teamgiveorders_time < G.floattime - 5 then
			G.BotHarvesterOrders(bs)
			bs.teamgiveorders_time = G.floattime + 30
		end
	end
end

return nil
