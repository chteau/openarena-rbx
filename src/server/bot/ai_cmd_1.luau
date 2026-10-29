--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_cmd.c, part 1 of 3).

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
-- Luau port of OpenArena 0.8.8's ai_cmd.c (gamecode 9e0f0c0), part 1 of 3. Bot team command helpers and the first command handlers.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_cmd")

G.notleader = {}
for i = 0, C.MAX_CLIENTS - 1 do
	G.notleader[i] = 0
end

--[[
==================
BotGetItemTeamGoal

FIXME: add stuff like "upper rocket launcher"
"the rl near the railgun", "lower grenade launcher" etc.
==================
]]
function G.BotGetItemTeamGoal(goalname, goal)
	if #goalname == 0 then return 0 end
	local i = -1
	repeat
		i = G.trap_BotGetLevelItemGoal(i, goalname, goal)
		if i > 0 then
			--do NOT defend dropped items
			if bit32.band(goal.flags, C.GFL_DROPPED) ~= 0 then
				continue
			end
			return 1
		end
	until not (i > 0)
	return 0
end

--[[
==================
BotGetMessageTeamGoal
==================
]]
function G.BotGetMessageTeamGoal(bs, goalname, goal)
	if G.BotGetItemTeamGoal(goalname, goal) ~= 0 then return 1 end

	local cp = G.BotFindWayPoint(bs.checkpoints, goalname)
	if cp then
		S.copy_bot_goal_t(goal, cp.goal)
		return 1
	end
	return 0
end

--[[
==================
BotGetTime
==================
]]
function G.BotGetTime(match)
	local timematch = S.bot_match_t()
	local t = 0

	--if the matched string has a time
	if bit32.band(match.subtype, C.ST_TIME) ~= 0 then
		--get the time string
		local timestring = G.trap_BotMatchVariable(match, C.TIME, C.MAX_MESSAGE_SIZE)
		--match it to find out if the time is in seconds or minutes
		if G.trap_BotFindMatch(timestring, timematch, C.MTCONTEXT_TIME) ~= 0 then
			if timematch.type == C.MSG_FOREVER then
				t = 99999999.0
			elseif timematch.type == C.MSG_FORAWHILE then
				t = 10 * 60 -- 10 minutes
			elseif timematch.type == C.MSG_FORALONGTIME then
				t = 30 * 60 -- 30 minutes
			else
				timestring = G.trap_BotMatchVariable(timematch, C.TIME, C.MAX_MESSAGE_SIZE)
				if timematch.type == C.MSG_MINUTES then
					t = QS.atof(timestring) * 60
				elseif timematch.type == C.MSG_SECONDS then
					t = QS.atof(timestring)
				else
					t = 0
				end
			end
			--if there's a valid time
			if t > 0 then return G.floattime + t end
		end
	end
	return 0
end

--[[
==================
FindClientByName
==================
]]
local maxclients_FindClientByName = 0
function G.FindClientByName(name)
	if maxclients_FindClientByName == 0 then
		maxclients_FindClientByName = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	for i = 0, math.min(maxclients_FindClientByName, C.MAX_CLIENTS) - 1 do
		local buf = G.ClientName(i, C.MAX_INFO_STRING)
		if QS.Q_stricmp(buf, name) == 0 then return i end
	end
	for i = 0, math.min(maxclients_FindClientByName, C.MAX_CLIENTS) - 1 do
		local buf = G.ClientName(i, C.MAX_INFO_STRING)
		if G.stristr(buf, name) then return i end
	end
	return -1
end

--[[
==================
FindEnemyByName
==================
]]
local maxclients_FindEnemyByName = 0
function G.FindEnemyByName(bs, name)
	if maxclients_FindEnemyByName == 0 then
		maxclients_FindEnemyByName = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	for i = 0, math.min(maxclients_FindEnemyByName, C.MAX_CLIENTS) - 1 do
		if G.BotSameTeam(bs, i) ~= 0 then continue end
		local buf = G.ClientName(i, C.MAX_INFO_STRING)
		if QS.Q_stricmp(buf, name) == 0 then return i end
	end
	for i = 0, math.min(maxclients_FindEnemyByName, C.MAX_CLIENTS) - 1 do
		if G.BotSameTeam(bs, i) ~= 0 then continue end
		local buf = G.ClientName(i, C.MAX_INFO_STRING)
		if G.stristr(buf, name) then return i end
	end
	return -1
end

--[[
==================
NumPlayersOnSameTeam
==================
]]
local maxclients_NumPlayersOnSameTeam = 0
function G.NumPlayersOnSameTeam(bs)
	if maxclients_NumPlayersOnSameTeam == 0 then
		maxclients_NumPlayersOnSameTeam = G.trap_Cvar_VariableIntegerValue("sv_maxclients")
	end
	local num = 0
	for i = 0, math.min(maxclients_NumPlayersOnSameTeam, C.MAX_CLIENTS) - 1 do
		local buf = G.trap_GetConfigstring(C.CS_PLAYERS + i)
		if #buf ~= 0 then
			if G.BotSameTeam(bs, i + 1) ~= 0 then num += 1 end
		end
	end
	return num
end

--[[
==================
TeamPlayIsOn
==================
]]
function G.BotGetPatrolWaypoints(bs, match)
	local patrolflags = 0
	local newpatrolpoints = nil
	local keyareamatch = S.bot_match_t()
	local goal = S.bot_goal_t()

	local keyarea = G.trap_BotMatchVariable(match, C.KEYAREA, C.MAX_MESSAGE_SIZE)
	--
	while true do
		if G.trap_BotFindMatch(keyarea, keyareamatch, C.MTCONTEXT_PATROLKEYAREA) == 0 then
			G.trap_EA_SayTeam(bs.client, "what do you say?")
			G.BotFreeWaypoints(newpatrolpoints)
			bs.patrolpoints = nil
			return 0
		end
		keyarea = G.trap_BotMatchVariable(keyareamatch, C.KEYAREA, C.MAX_MESSAGE_SIZE)
		if G.BotGetMessageTeamGoal(bs, keyarea, goal) == 0 then
			G.BotFreeWaypoints(newpatrolpoints)
			bs.patrolpoints = nil
			return 0
		end
		--create a new waypoint
		local newwp = G.BotCreateWayPoint(keyarea, goal.origin, goal.areanum)
		if not newwp then
			break
		end
		--add the waypoint to the patrol points
		newwp.next = nil
		local wp = newpatrolpoints
		while wp and wp.next do
			wp = wp.next
		end
		if not wp then
			newpatrolpoints = newwp
			newwp.prev = nil
		else
			wp.next = newwp
			newwp.prev = wp
		end
		--
		if bit32.band(keyareamatch.subtype, C.ST_BACK) ~= 0 then
			patrolflags = C.PATROL_LOOP
			break
		elseif bit32.band(keyareamatch.subtype, C.ST_REVERSE) ~= 0 then
			patrolflags = C.PATROL_REVERSE
			break
		elseif bit32.band(keyareamatch.subtype, C.ST_MORE) ~= 0 then
			keyarea = G.trap_BotMatchVariable(keyareamatch, C.MORE, C.MAX_MESSAGE_SIZE)
		else
			break
		end
	end
	--
	if not newpatrolpoints or not newpatrolpoints.next then
		G.trap_EA_SayTeam(bs.client, "I need more key points to patrol\n")
		G.BotFreeWaypoints(newpatrolpoints)
		newpatrolpoints = nil
		return 0
	end
	--
	G.BotFreeWaypoints(bs.patrolpoints)
	bs.patrolpoints = newpatrolpoints
	--
	bs.curpatrolpoint = bs.patrolpoints
	bs.patrolflags = patrolflags
	--
	return 1
end

--[[
==================
BotAddressedToBot
==================
]]
function G.BotAddressedToBot(bs, match)
	local addresseematch = S.bot_match_t()

	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	local client = G.ClientOnSameTeamFromName(bs, netname)
	if client < 0 then return 0 end
	--if the message is addressed to someone
	if bit32.band(match.subtype, C.ST_ADDRESSED) ~= 0 then
		local addressedto = G.trap_BotMatchVariable(match, C.ADDRESSEE, C.MAX_MESSAGE_SIZE)
		--the name of this bot
		local botname = G.ClientName(bs.client, 128)
		--
		while G.trap_BotFindMatch(addressedto, addresseematch, C.MTCONTEXT_ADDRESSEE) ~= 0 do
			if addresseematch.type == C.MSG_EVERYONE then
				return 1
			elseif addresseematch.type == C.MSG_MULTIPLENAMES then
				local name = G.trap_BotMatchVariable(addresseematch, C.TEAMMATE, C.MAX_MESSAGE_SIZE)
				if #name ~= 0 then
					if G.stristr(botname, name) then return 1 end
					if G.stristr(bs.subteam, name) then return 1 end
				end
				addressedto = G.trap_BotMatchVariable(addresseematch, C.MORE, C.MAX_MESSAGE_SIZE)
			else
				local name = G.trap_BotMatchVariable(addresseematch, C.TEAMMATE, C.MAX_MESSAGE_SIZE)
				if #name ~= 0 then
					if G.stristr(botname, name) then return 1 end
					if G.stristr(bs.subteam, name) then return 1 end
				end
				break
			end
		end
		return 0
	else
		local tellmatch = S.bot_match_t()

		tellmatch.type = 0
		--if this message wasn't directed solely to this bot
		if G.trap_BotFindMatch(match.string, tellmatch, C.MTCONTEXT_REPLYCHAT) == 0
			or tellmatch.type ~= C.MSG_CHATTELL then
			--make sure not everyone reacts to this message
			if Q.random() > Q.f(1.0 / (G.NumPlayersOnSameTeam(bs) - 1)) then return 0 end
		end
	end
	return 1
end

--[[
==================
BotGPSToPosition
==================
]]
function G.BotGPSToPosition(buf, position)
	local j = 0
	local function at(k)
		return string.byte(buf, k + 1) or 0
	end

	for i = 0, 2 do
		local num = 0
		local sign
		while at(j) == 32 do j += 1 end
		if at(j) == 45 then
			j += 1
			sign = -1
		else
			sign = 1
		end
		while at(j) ~= 0 do
			if at(j) >= 48 and at(j) <= 57 then
				num = num * 10 + at(j) - 48
				j += 1
			else
				j += 1
				break
			end
		end
		G.BotAI_Print(C.PRT_MESSAGE, "%d\n", sign * num)
		position[i] = sign * num
	end
	return 1
end

--[[
==================
BotMatch_HelpAccompany
==================
]]
function G.BotMatch_HelpAccompany(bs, match)
	local client, other, areanum
	local netname = ""
	local teammatematch = S.bot_match_t()
	local entinfo = S.aas_entityinfo_t()

	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--get the team mate name
	local teammate = G.trap_BotMatchVariable(match, C.TEAMMATE, C.MAX_MESSAGE_SIZE)
	--get the client to help
	if G.trap_BotFindMatch(teammate, teammatematch, C.MTCONTEXT_TEAMMATE) ~= 0
		--if someone asks for him or herself
		and teammatematch.type == C.MSG_ME then
		--get the netname
		netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
		client = G.ClientFromName(netname)
		other = false
	else
		--asked for someone else
		client = G.FindClientByName(teammate)
		--if this is the bot self
		if client == bs.client then
			other = false
		elseif G.BotSameTeam(bs, client) == 0 then
			--FIXME: say "I don't help the enemy"
			return
		else
			other = true
		end
	end
	--if the bot doesn't know who to help (FindClientByName returned -1)
	if client < 0 then
		if other then
			G.BotAI_BotInitialChat(bs, "whois", teammate, nil)
		else
			G.BotAI_BotInitialChat(bs, "whois", netname, nil)
		end
		client = G.ClientFromName(netname)
		G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
		return
	end
	--don't help or accompany yourself
	if client == bs.client then
		return
	end
	--
	bs.teamgoal.entitynum = -1
	G.BotEntityInfo(client, entinfo)
	--if info is valid (in PVS)
	if entinfo.valid ~= 0 then
		areanum = G.BotPointAreaNum(entinfo.origin)
		if areanum ~= 0 then -- && trap_AAS_AreaReachability(areanum)) {
			bs.teamgoal.entitynum = client
			bs.teamgoal.areanum = areanum
			Q.VectorCopy(entinfo.origin, bs.teamgoal.origin)
			Q.VectorSet(bs.teamgoal.mins, -8, -8, -8)
			Q.VectorSet(bs.teamgoal.maxs, 8, 8, 8)
		end
	end
	--if no teamgoal yet
	if bs.teamgoal.entitynum < 0 then
		--if near an item
		if bit32.band(match.subtype, C.ST_NEARITEM) ~= 0 then
			--get the match variable
			local itemname = G.trap_BotMatchVariable(match, C.ITEM, C.MAX_MESSAGE_SIZE)
			--
			if G.BotGetMessageTeamGoal(bs, itemname, bs.teamgoal) == 0 then
				return
			end
		end
	end
	--
	if bs.teamgoal.entitynum < 0 then
		if other then
			G.BotAI_BotInitialChat(bs, "whereis", teammate, nil)
		else
			G.BotAI_BotInitialChat(bs, "whereareyou", netname, nil)
		end
		client = G.ClientFromName(netname)
		G.trap_BotEnterChat(bs.cs, client, C.CHAT_TEAM)
		return
	end
	--the team mate
	bs.teammate = client
	--
	netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--
	client = G.ClientFromName(netname)
	--the team mate who ordered
	bs.decisionmaker = client
	bs.ordered = 1
	bs.order_time = G.floattime
	--last time the team mate was assumed visible
	bs.teammatevisible_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--get the team goal time
	bs.teamgoal_time = G.BotGetTime(match)
	--set the ltg type
	if match.type == C.MSG_HELP then
		bs.ltgtype = C.LTG_TEAMHELP
		if bs.teamgoal_time == 0 then bs.teamgoal_time = G.floattime + C.TEAM_HELP_TIME end
	else
		bs.ltgtype = C.LTG_TEAMACCOMPANY
		if bs.teamgoal_time == 0 then bs.teamgoal_time = G.floattime + C.TEAM_ACCOMPANY_TIME end
		bs.formation_dist = 3.5 * 32 --3.5 meter
		bs.arrive_time = 0
		--
		G.BotSetTeamStatus(bs)
		-- remember last ordered task
		G.BotRememberLastOrderedTask(bs)
	end
end

--[[
==================
BotMatch_DefendKeyArea
==================
]]
function G.BotMatch_DefendKeyArea(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--get the match variable
	local itemname = G.trap_BotMatchVariable(match, C.KEYAREA, C.MAX_MESSAGE_SIZE)
	--
	if G.BotGetMessageTeamGoal(bs, itemname, bs.teamgoal) == 0 then
		return
	end
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--
	local client = G.ClientFromName(netname)
	--the team mate who ordered
	bs.decisionmaker = client
	bs.ordered = 1
	bs.order_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--set the ltg type
	bs.ltgtype = C.LTG_DEFENDKEYAREA
	--get the team goal time
	bs.teamgoal_time = G.BotGetTime(match)
	--set the team goal time
	if bs.teamgoal_time == 0 then bs.teamgoal_time = G.floattime + C.TEAM_DEFENDKEYAREA_TIME end
	--away from defending
	bs.defendaway_time = 0
	--
	G.BotSetTeamStatus(bs)
	-- remember last ordered task
	G.BotRememberLastOrderedTask(bs)
end

--[[
==================
BotMatch_TakeA
For Double Domination
==================
]]
function G.BotMatch_TakeA(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--
	local client = G.ClientFromName(netname)
	--the team mate who ordered
	bs.decisionmaker = client
	bs.ordered = 1
	bs.order_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--set the ltg type
	bs.ltgtype = C.LTG_POINTA
	--get the team goal time
	bs.teamgoal_time = G.BotGetTime(match)
	--set the team goal time
	if bs.teamgoal_time == 0 then bs.teamgoal_time = G.floattime + C.DD_POINTA end
	--away from defending
	bs.defendaway_time = 0
	--
	G.BotSetTeamStatus(bs)
	-- remember last ordered task
	G.BotRememberLastOrderedTask(bs)
end

return nil
