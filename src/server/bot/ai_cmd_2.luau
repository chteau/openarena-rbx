--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/ai_cmd.c, part 2 of 3).

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
-- Luau port of ai_cmd.c, part 2 of 3. Team command handlers (TakeB .. Suicide).

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local GT_POSSESSION = 13
local VOICECHAT_YES = "yes"
local VOICECHAT_TAUNT = "taunt"

function G.BotMatch_TakeB(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--
	local client = G.ClientFromName(netname)
	--the team mate who ordered
	bs.decisionmaker = client
	bs.ordered = true
	bs.order_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--set the ltg type
	bs.ltgtype = C.LTG_POINTB
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

function G.BotMatch_GetItem(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--get the match variable
	local itemname = G.trap_BotMatchVariable(match, C.ITEM, C.MAX_MESSAGE_SIZE)
	--
	if G.BotGetMessageTeamGoal(bs, itemname, bs.teamgoal) == 0 then
		return
	end
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	local client = G.ClientOnSameTeamFromName(bs, netname)
	--
	bs.decisionmaker = client
	bs.ordered = true
	bs.order_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--set the ltg type
	bs.ltgtype = C.LTG_GETITEM
	--set the team goal time
	bs.teamgoal_time = G.floattime + C.TEAM_GETITEM_TIME
	--
	G.BotSetTeamStatus(bs)
end

function G.BotMatch_Camp(bs, match)
	local entinfo = S.aas_entityinfo_t()

	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--asked for someone else
	local client = G.FindClientByName(netname)
	--if there's no valid client with this name
	if client < 0 then
		G.BotAI_BotInitialChat(bs, "whois", netname, nil)
		G.trap_BotEnterChat(bs.cs, bs.client, C.CHAT_TEAM)
		return
	end
	--get the match variable
	local itemname = G.trap_BotMatchVariable(match, C.KEYAREA, C.MAX_MESSAGE_SIZE)
	--in CTF it could be the base
	if bit32.band(match.subtype, C.ST_THERE) ~= 0 then
		--camp at the spot the bot is currently standing
		bs.teamgoal.entitynum = bs.entitynum
		bs.teamgoal.areanum = bs.areanum
		Q.VectorCopy(bs.origin, bs.teamgoal.origin)
		Q.VectorSet(bs.teamgoal.mins, -8, -8, -8)
		Q.VectorSet(bs.teamgoal.maxs, 8, 8, 8)
	elseif bit32.band(match.subtype, C.ST_HERE) ~= 0 then
		--if this is the bot self
		if client == bs.client then return end
		--
		bs.teamgoal.entitynum = -1
		G.BotEntityInfo(client, entinfo)
		--if info is valid (in PVS)
		if entinfo.valid ~= 0 then
			local areanum = G.BotPointAreaNum(entinfo.origin)
			if areanum ~= 0 then
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
			G.BotAI_BotInitialChat(bs, "whereareyou", netname, nil)
			client = G.ClientFromName(netname)
			G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
			return
		end
	elseif G.BotGetMessageTeamGoal(bs, itemname, bs.teamgoal) == 0 then
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
	bs.teamgoal_time = G.BotGetTime(match)
	--set the team goal time
	if bs.teamgoal_time == 0 then bs.teamgoal_time = G.floattime + C.TEAM_CAMP_TIME end
	--not arrived yet
	bs.arrive_time = 0
	--
	G.BotSetTeamStatus(bs)
	-- remember last ordered task
	G.BotRememberLastOrderedTask(bs)
end

function G.BotMatch_Patrol(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--get the patrol waypoints
	if G.BotGetPatrolWaypoints(bs, match) == 0 then return end
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--
	local client = G.FindClientByName(netname)
	--
	bs.decisionmaker = client
	bs.ordered = true
	bs.order_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--set the ltg type
	bs.ltgtype = C.LTG_PATROL
	--get the team goal time
	bs.teamgoal_time = G.BotGetTime(match)
	--set the team goal time if not set already
	if bs.teamgoal_time == 0 then bs.teamgoal_time = G.floattime + C.TEAM_PATROL_TIME end
	--
	G.BotSetTeamStatus(bs)
	-- remember last ordered task
	G.BotRememberLastOrderedTask(bs)
end

function G.BotMatch_GetFlag(bs, match)
	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
		if G.ctf_redflag.areanum == 0 or G.ctf_blueflag.areanum == 0 then
			return
		end
	elseif G.gametype == C.GT_1FCTF then
		if G.ctf_neutralflag.areanum == 0 or G.ctf_redflag.areanum == 0 or G.ctf_blueflag.areanum == 0 then
			return
		end
	elseif G.gametype == GT_POSSESSION then
		if G.ctf_neutralflag.areanum == 0 then
			return
		end
	else
		return
	end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--
	local client = G.FindClientByName(netname)
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
	if G.gametype == C.GT_CTF or G.gametype == C.GT_1FCTF or G.gametype == C.GT_CTF_ELIMINATION then
		--get an alternative route goal towards the enemy base
		G.BotGetAlternateRouteGoal(bs, G.BotOppositeTeam(bs))
	end
	--
	G.BotSetTeamStatus(bs)
	-- remember last ordered task
	G.BotRememberLastOrderedTask(bs)
end

function G.BotMatch_AttackEnemyBase(bs, match)
	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
		G.BotMatch_GetFlag(bs, match)
	elseif G.gametype == C.GT_1FCTF or G.gametype == C.GT_OBELISK or G.gametype == C.GT_HARVESTER then
		if G.redobelisk.areanum == 0 or G.blueobelisk.areanum == 0 then
			return
		end
	else
		return
	end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--
	local client = G.FindClientByName(netname)
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

function G.BotMatch_Harvest(bs, match)
	if G.gametype == C.GT_HARVESTER then
		if G.neutralobelisk.areanum == 0 or G.redobelisk.areanum == 0 or G.blueobelisk.areanum == 0 then
			return
		end
	else
		return
	end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--
	local client = G.FindClientByName(netname)
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
end

function G.BotMatch_RushBase(bs, match)
	if G.gametype == C.GT_CTF or G.gametype == C.GT_CTF_ELIMINATION then
		if G.ctf_redflag.areanum == 0 or G.ctf_blueflag.areanum == 0 then
			return
		end
	elseif G.gametype == C.GT_1FCTF or G.gametype == C.GT_HARVESTER then
		if G.redobelisk.areanum == 0 or G.blueobelisk.areanum == 0 then
			return
		end
	else
		return
	end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--
	local client = G.FindClientByName(netname)
	--
	bs.decisionmaker = client
	bs.ordered = true
	bs.order_time = G.floattime
	--set the time to send a message to the team mates
	bs.teammessage_time = G.floattime + 2 * Q.random()
	--set the ltg type
	bs.ltgtype = C.LTG_RUSHBASE
	--set the team goal time
	bs.teamgoal_time = G.floattime + C.CTF_RUSHBASE_TIME
	bs.rushbaseaway_time = 0
	--
	G.BotSetTeamStatus(bs)
end

function G.BotMatch_TaskPreference(bs, match)
	local netname = G.ClientName(bs.client, C.MAX_NETNAME)
	if not QS.Q_strequal(netname, bs.teamleader) then
		return
	end

	local teammatename = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	local teammate = G.ClientFromName(teammatename)
	if teammate < 0 then return end

	local preference = G.BotGetTeamMateTaskPreference(bs, teammate)
	local subtype = match.subtype
	if subtype == C.ST_DEFENDER then
		preference = bit32.band(preference, bit32.bnot(C.TEAMTP_ATTACKER))
		preference = bit32.bor(preference, C.TEAMTP_DEFENDER)
	elseif subtype == C.ST_ATTACKER then
		preference = bit32.band(preference, bit32.bnot(C.TEAMTP_DEFENDER))
		preference = bit32.bor(preference, C.TEAMTP_ATTACKER)
	elseif subtype == C.ST_ROAMER then
		preference = bit32.band(preference, bit32.bnot(bit32.bor(C.TEAMTP_ATTACKER, C.TEAMTP_DEFENDER)))
	end
	G.BotSetTeamMateTaskPreference(bs, teammate, preference)
	--
	teammatename = G.EasyClientName(teammate, C.MAX_MESSAGE_SIZE)
	G.BotAI_BotInitialChat(bs, "keepinmind", teammatename, nil)
	G.trap_BotEnterChat(bs.cs, teammate, C.CHAT_TELL)
	G.BotVoiceChatOnly(bs, teammate, VOICECHAT_YES)
	G.trap_EA_Action(bs.client, C.ACTION_AFFIRMATIVE)
end

function G.BotMatch_ReturnFlag(bs, match)
	--if not in CTF mode
	if G.gametype ~= C.GT_CTF and G.gametype ~= C.GT_CTF_ELIMINATION and G.gametype ~= C.GT_1FCTF then
		return
	end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then
		return
	end
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	--
	local client = G.FindClientByName(netname)
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
	--
	G.BotSetTeamStatus(bs)
end

function G.BotMatch_JoinSubteam(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--get the sub team name
	local teammate = G.trap_BotMatchVariable(match, C.TEAMNAME, C.MAX_MESSAGE_SIZE)
	--set the sub team name
	bs.subteam = QS.Q_strncpyz(teammate, 32)
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	G.BotAI_BotInitialChat(bs, "joinedteam", teammate, nil)
	local client = G.ClientFromName(netname)
	G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
end

function G.BotMatch_LeaveSubteam(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--
	if #bs.subteam ~= 0 then
		G.BotAI_BotInitialChat(bs, "leftteam", bs.subteam, nil)
		local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
		local client = G.ClientFromName(netname)
		G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
	end --end if
	bs.subteam = ""
end

function G.BotMatch_WhichTeam(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end

	--
	if #bs.subteam ~= 0 then
		G.BotAI_BotInitialChat(bs, "inteam", bs.subteam, nil)
	else
		G.BotAI_BotInitialChat(bs, "noteam", nil)
	end
	G.trap_BotEnterChat(bs.cs, bs.client, C.CHAT_TEAM)
end

function G.BotMatch_CheckPoint(bs, match)
	local position = Q.vec3()

	if G.TeamPlayIsOn() == 0 then return end
	--
	local buf = G.trap_BotMatchVariable(match, C.POSITION, C.MAX_MESSAGE_SIZE)
	Q.VectorClear(position)
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	local client = G.ClientFromName(netname)
	-- sscanf(buf, "%f %f %f", ...): stops at the first token that is not a number
	local n = 0
	for tok in string.gmatch(buf, "%S+") do
		local v = tonumber(tok)
		if v == nil or n >= 3 then break end
		position[n] = v
		n += 1
	end
	position[2] += 0.5
	local areanum = G.BotPointAreaNum(position)
	if areanum == 0 then
		if G.BotAddressedToBot(bs, match) ~= 0 then
			G.BotAI_BotInitialChat(bs, "checkpoint_invalid", nil)
			G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
		end
		return
	end
	--
	buf = G.trap_BotMatchVariable(match, C.NAME, C.MAX_MESSAGE_SIZE)
	--check if there already exists a checkpoint with this name
	local cp = G.BotFindWayPoint(bs.checkpoints, buf)
	if cp ~= nil then
		if cp.next ~= nil then cp.next.prev = cp.prev end
		if cp.prev ~= nil then cp.prev.next = cp.next
		else bs.checkpoints = cp.next end
		cp.inuse = 0
	end
	--create a new check point
	cp = G.BotCreateWayPoint(buf, position, areanum)
	--add the check point to the bot's known chech points
	cp.next = bs.checkpoints
	if bs.checkpoints ~= nil then bs.checkpoints.prev = cp end
	bs.checkpoints = cp
	--
	if G.BotAddressedToBot(bs, match) ~= 0 then
		buf = QS.Com_sprintf(C.MAX_MESSAGE_SIZE, "%1.0f %1.0f %1.0f", cp.goal.origin[0],
													cp.goal.origin[1],
													cp.goal.origin[2])

		G.BotAI_BotInitialChat(bs, "checkpoint_confirm", cp.name, buf, nil)
		G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
	end
end

function G.BotMatch_FormationSpace(bs, match)
	local space

	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--
	local buf = G.trap_BotMatchVariable(match, C.NUMBER, C.MAX_MESSAGE_SIZE)
	--if it's the distance in feet
	if bit32.band(match.subtype, C.ST_FEET) ~= 0 then space = 0.3048 * 32 * QS.atof(buf)
	--else it's in meters
	else space = 32 * QS.atof(buf) end
	--check if the formation intervening space is valid
	if space < 48 or space > 500 then space = 100 end
	bs.formation_dist = space
end

function G.BotMatch_Dismiss(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	local client = G.ClientFromName(netname)
	--
	bs.decisionmaker = client
	--
	bs.ltgtype = 0
	bs.lead_time = 0
	bs.lastgoal_ltgtype = 0
	--
	G.BotAI_BotInitialChat(bs, "dismissed", nil)
	G.trap_BotEnterChat(bs.cs, client, C.CHAT_TELL)
end

function G.BotMatch_Suicide(bs, match)
	if G.TeamPlayIsOn() == 0 then return end
	--if not addressed to this bot
	if G.BotAddressedToBot(bs, match) == 0 then return end
	--
	G.trap_EA_Command(bs.client, "kill")
	--
	local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_MESSAGE_SIZE)
	local client = G.ClientFromName(netname)
	--
	G.BotVoiceChat(bs, client, VOICECHAT_TAUNT)
	G.trap_EA_Action(bs.client, C.ACTION_AFFIRMATIVE)
end

return nil
