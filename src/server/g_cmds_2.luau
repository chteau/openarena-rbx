--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_cmds.c, part 2 of 3).

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
-- Luau port of OpenArena 0.8.8's g_cmds.c (gamecode 9e0f0c0) (part 2): team changes, following, chat and voice commands.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_cmds")

local Q_COLOR_ESCAPE = string.byte("^")
local COLOR_GREEN = string.byte("2")
local COLOR_CYAN = string.byte("5")
local COLOR_MAGENTA = string.byte("6")
local COLOR_WHITE = string.byte("7")

local ADMF_FORCETEAMCHANGE = string.byte("4")

local VOICECHAT_KILLINSULT = "kill_insult"
local VOICECHAT_KILLGAUNTLET = "kill_gauntlet"
local VOICECHAT_TAUNT = "taunt"
local VOICECHAT_DEATHINSULT = "death_insult"
local VOICECHAT_PRAISE = "praise"

function G.SetTeam(ent, s)
	local team, oldTeam
	local client
	local clientNum
	local specState
	local specClient
	local teamLeader
	local userinfo
	local force

	force = G.G_admin_permission(ent, ADMF_FORCETEAMCHANGE)

	client = ent.client

	clientNum = client.index
	userinfo = G.trap_GetUserinfo(clientNum)
	specClient = 0
	specState = C.SPECTATOR_NOT
	if QS.Q_strequal(s, "scoreboard") or QS.Q_strequal(s, "score") then
		team = C.TEAM_SPECTATOR
		specState = C.SPECTATOR_SCOREBOARD
	elseif QS.Q_strequal(s, "follow1") then
		team = C.TEAM_SPECTATOR
		specState = C.SPECTATOR_FOLLOW
		specClient = -1
	elseif QS.Q_strequal(s, "follow2") then
		team = C.TEAM_SPECTATOR
		specState = C.SPECTATOR_FOLLOW
		specClient = -2
	elseif QS.Q_strequal(s, "spectator") or QS.Q_strequal(s, "s") then
		team = C.TEAM_SPECTATOR
		specState = C.SPECTATOR_FREE
	elseif G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		specState = C.SPECTATOR_NOT
		if QS.Q_strequal(s, "red") or QS.Q_strequal(s, "r") then
			team = C.TEAM_RED
		elseif QS.Q_strequal(s, "blue") or QS.Q_strequal(s, "b") then
			team = C.TEAM_BLUE
		else
			team = G.PickTeam(clientNum)
		end
		if not force then
			if G.g_teamForceBalance.integer ~= 0 then
				local counts = {}

				counts[C.TEAM_BLUE] = G.TeamCount(ent.client.ps.clientNum, C.TEAM_BLUE)
				counts[C.TEAM_RED] = G.TeamCount(ent.client.ps.clientNum, C.TEAM_RED)

				-- We allow a spread of two
				if team == C.TEAM_RED and counts[C.TEAM_RED] - counts[C.TEAM_BLUE] > 1 then
					G.trap_SendServerCommand(ent.client.ps.clientNum,
						"cp \"Red team has too many players.\n\"")
					return
				end
				if team == C.TEAM_BLUE and counts[C.TEAM_BLUE] - counts[C.TEAM_RED] > 1 then
					G.trap_SendServerCommand(ent.client.ps.clientNum,
						"cp \"Blue team has too many players.\n\"")
					return
				end
			end
		end
	else
		team = C.TEAM_FREE
	end
	if not force then
		if G.g_gametype.integer == C.GT_TOURNAMENT
			and G.level.numNonSpectatorClients >= 2 then
			team = C.TEAM_SPECTATOR
		elseif G.g_maxGameClients.integer > 0 and
			G.level.numNonSpectatorClients >= G.g_maxGameClients.integer then
			team = C.TEAM_SPECTATOR
		end
	end

	oldTeam = client.sess.sessionTeam
	if team == oldTeam and team ~= C.TEAM_SPECTATOR then
		return
	end
	if not force then
		if team == C.TEAM_RED and G.level.RedTeamLocked then
			G.trap_SendServerCommand(ent.client.ps.clientNum,
				"cp \"The Red Team has been locked by the Admin! \n\"")
			return
		end
		if team == C.TEAM_BLUE and G.level.BlueTeamLocked then
			G.trap_SendServerCommand(ent.client.ps.clientNum,
				"cp \"The Blue Team has been locked by the Admin! \n\"")
			return
		end
		if team == C.TEAM_FREE and G.level.FFALocked then
			G.trap_SendServerCommand(ent.client.ps.clientNum,
				"cp \"This Deathmatch has been locked by the Admin! \n\"")
			return
		end
	end

	-- if the player was dead leave the body
	if client.ps.stats[C.STAT_HEALTH] <= 0 then
		G.CopyToBodyQue(ent)
	end

	-- he starts at 'base'
	client.pers.teamState.state = C.TEAM_BEGIN
	if oldTeam ~= C.TEAM_SPECTATOR then
		local teamscore = -99
		if G.g_gametype.integer == C.GT_TEAM and ent.client.ps.stats[C.STAT_HEALTH] ~= 0 then
			teamscore = G.level.teamScores[ent.client.sess.sessionTeam]
		end
		ent.flags = bit32.band(ent.flags, bit32.bnot(C.FL_GODMODE))
		ent.client.ps.stats[C.STAT_HEALTH] = 0
		ent.health = 0
		G.player_die(ent, ent, ent, 100000, C.MOD_SUICIDE)
		if teamscore ~= -99 then
			G.level.teamScores[ent.client.sess.sessionTeam] = teamscore
		end

		G.PlayerStore_store(QS.Info_ValueForKey(userinfo, "cl_guid"), client.ps)
	end
	-- they go to the end of the line for tournements
	if team == C.TEAM_SPECTATOR and oldTeam ~= team then
		G.AddTournamentQueue(client)
	end
	client.sess.sessionTeam = team
	client.sess.spectatorState = specState
	client.sess.spectatorClient = specClient

	client.sess.teamLeader = false
	if team == C.TEAM_RED or team == C.TEAM_BLUE then
		teamLeader = G.TeamLeader(team)
		if teamLeader == -1 or (bit32.band(G.g_entities[clientNum].r.svFlags, C.SVF_BOT) == 0 and bit32.band(G.g_entities[teamLeader].r.svFlags, C.SVF_BOT) ~= 0) then
			G.SetLeader(team, clientNum)
		end
	end
	if oldTeam == C.TEAM_RED or oldTeam == C.TEAM_BLUE then
		G.CheckTeamLeader(oldTeam)
	end

	G.BroadcastTeamChange(client, oldTeam)

	G.ClientUserinfoChanged(clientNum)

	G.ClientBegin(clientNum)
end

function G.StopFollowing(ent)
	if G.g_gametype.integer < C.GT_ELIMINATION or G.g_gametype.integer > C.GT_LMS then
		ent.client.ps.persistant[C.PERS_TEAM] = C.TEAM_SPECTATOR
		ent.client.sess.sessionTeam = C.TEAM_SPECTATOR
	else
		ent.client.ps.stats[C.STAT_HEALTH] = 0
		ent.health = 0
	end
	ent.client.sess.spectatorState = C.SPECTATOR_FREE
	ent.client.ps.pm_flags = bit32.band(ent.client.ps.pm_flags, bit32.bnot(C.PMF_FOLLOW))
	ent.r.svFlags = bit32.band(ent.r.svFlags, bit32.bnot(C.SVF_BOT))
	ent.client.ps.clientNum = ent.index
end

function G.Cmd_Team_f(ent)
	local oldTeam
	local s
	local force

	if G.trap_Argc() ~= 2 then
		oldTeam = ent.client.sess.sessionTeam
		if oldTeam == C.TEAM_BLUE then
			G.trap_SendServerCommand(ent.index, "print \"Blue team\n\"")
		elseif oldTeam == C.TEAM_RED then
			G.trap_SendServerCommand(ent.index, "print \"Red team\n\"")
		elseif oldTeam == C.TEAM_FREE then
			G.trap_SendServerCommand(ent.index, "print \"Deathmatch-Playing\n\"")
		elseif oldTeam == C.TEAM_SPECTATOR then
			G.trap_SendServerCommand(ent.index, "print \"Spectator team\n\"")
		end
		return
	end

	force = G.G_admin_permission(ent, ADMF_FORCETEAMCHANGE)

	if not force then
		if ent.client.switchTeamTime > G.level.time then
			G.trap_SendServerCommand(ent.index, "print \"May not switch teams more than once per 5 seconds.\n\"")
			return
		end
	end

	-- if they are playing a tournement game, count as a loss
	if G.g_gametype.integer == C.GT_TOURNAMENT
		and ent.client.sess.sessionTeam == C.TEAM_FREE then
		ent.client.sess.losses = ent.client.sess.losses + 1
	end

	s = string.sub(G.trap_Argv(1), 1, C.MAX_TOKEN_CHARS - 1)

	G.SetTeam(ent, s)

	ent.client.switchTeamTime = G.level.time + 5000
end

function G.Cmd_Follow_f(ent)
	local i
	local arg

	if G.trap_Argc() ~= 2 then
		if ent.client.sess.spectatorState == C.SPECTATOR_FOLLOW then
			G.StopFollowing(ent)
		end
		return
	end

	arg = string.sub(G.trap_Argv(1), 1, C.MAX_TOKEN_CHARS - 1)
	i = G.ClientNumberFromString(ent, arg)
	if i == -1 then
		return
	end

	-- can't follow self
	if G.level.clients[i] == ent.client then
		return
	end

	-- can't follow another spectator (or an eliminated player)
	if G.level.clients[i].sess.sessionTeam == C.TEAM_SPECTATOR or G.level.clients[i].isEliminated then
		return
	end

	if (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION) and G.g_elimination_lockspectator.integer ~= 0
		and ((ent.client.sess.sessionTeam == C.TEAM_RED and G.level.clients[i].sess.sessionTeam == C.TEAM_BLUE) or
			(ent.client.sess.sessionTeam == C.TEAM_BLUE and G.level.clients[i].sess.sessionTeam == C.TEAM_RED)) then
		return
	end

	-- if they are playing a tournement game, count as a loss
	if G.g_gametype.integer == C.GT_TOURNAMENT
		and ent.client.sess.sessionTeam == C.TEAM_FREE then
		ent.client.sess.losses = ent.client.sess.losses + 1
	end

	-- first set them to spectator
	if ent.client.sess.spectatorState == C.SPECTATOR_NOT then
		G.SetTeam(ent, "spectator")
	end

	ent.client.sess.spectatorState = C.SPECTATOR_FOLLOW
	ent.client.sess.spectatorClient = i
end

function G.Cmd_FollowCycle_f(ent)
	local clientnum
	local original
	local count
	local args
	local dir

	if ent.client.sess.sessionTeam == C.TEAM_NONE then
		dir = 1
	end

	args = string.sub(G.trap_Argv(0), 1, 10)
	if QS.Q_strequal(args, "followprev") then
		dir = -1
	elseif QS.Q_strequal(args, "follownext") then
		dir = 1
	else
		dir = 1
	end

	-- if they are playing a tournement game, count as a loss
	if G.g_gametype.integer == C.GT_TOURNAMENT
		and ent.client.sess.sessionTeam == C.TEAM_FREE then
		ent.client.sess.losses = ent.client.sess.losses + 1
	end
	-- first set them to spectator
	if ent.client.sess.spectatorState == C.SPECTATOR_NOT then
		G.SetTeam(ent, "spectator")
	end

	if dir ~= 1 and dir ~= -1 then
		G.G_Error("Cmd_FollowCycle_f: bad dir %i", dir)
	end

	clientnum = ent.client.sess.spectatorClient
	original = clientnum
	count = 0
	while true do
		clientnum = clientnum + dir
		count = count + 1
		if clientnum >= G.level.maxclients then
			clientnum = 0
		end
		if clientnum < 0 then
			clientnum = G.level.maxclients - 1
		end

		if count > G.level.maxclients then
			return
		end

		local skip = false
		-- can only follow connected clients
		if G.level.clients[clientnum].pers.connected ~= C.CON_CONNECTED then
			skip = true
		elseif G.level.clients[clientnum].sess.sessionTeam == C.TEAM_SPECTATOR or G.level.clients[clientnum].isEliminated then
			-- can't follow another spectator
			skip = true
		elseif (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION) and G.g_elimination_lockspectator.integer ~= 0
			and ((ent.client.sess.sessionTeam == C.TEAM_RED and G.level.clients[clientnum].sess.sessionTeam == C.TEAM_BLUE) or
				(ent.client.sess.sessionTeam == C.TEAM_BLUE and G.level.clients[clientnum].sess.sessionTeam == C.TEAM_RED)) then
			-- Stop players from spectating players on the enemy team in elimination modes.
			skip = true
		end

		if not skip then
			-- this is good, we can use it
			ent.client.sess.spectatorClient = clientnum
			ent.client.sess.spectatorState = C.SPECTATOR_FOLLOW
			return
		end
		if clientnum == original then
			break
		end
	end

	-- leave it where it was
end

function SF.G_SayTo(ent, other, mode, color, name, message)
	if other == nil then
		return
	end
	if not other.inuse then
		return
	end
	if other.client == nil then
		return
	end
	if other.client.pers.connected ~= C.CON_CONNECTED then
		return
	end
	if mode == C.SAY_TEAM and not G.OnSameTeam(ent, other) then
		return
	end

	if bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 and G.trap_Cvar_VariableValue("bot_nochat") > 1 then return end

	-- no chatting to players in tournements
	if G.g_gametype.integer == C.GT_TOURNAMENT
		and other.client.sess.sessionTeam == C.TEAM_FREE
		and ent.client.sess.sessionTeam ~= C.TEAM_FREE then
		return
	end

	G.trap_SendServerCommand(other.index, QS.va("%s \"%s%c%c%s\"",
		if mode == C.SAY_TEAM then "tchat" else "chat",
		name, Q_COLOR_ESCAPE, color, message))
end

local EC = "\x19"

function G.G_Say(ent, target, mode, chatText)
	local other
	local color
	local name
	local text
	local location

	if bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 and G.trap_Cvar_VariableValue("bot_nochat") > 1 then return end

	if (G.g_gametype.integer < C.GT_TEAM or G.g_ffa_gt == 1) and mode == C.SAY_TEAM then
		mode = C.SAY_ALL
	end

	if mode == C.SAY_TEAM then
		G.G_LogPrintf("sayteam: %s: %s\n", ent.client.pers.netname, chatText)
		local ok, loc = G.Team_GetLocationMsg(ent, 64)
		location = loc
		if ok then
			name = QS.Com_sprintf(64, EC .. "(%s%c%c" .. EC .. ") (%s)" .. EC .. ": ",
				ent.client.pers.netname, Q_COLOR_ESCAPE, COLOR_WHITE, location)
		else
			name = QS.Com_sprintf(64, EC .. "(%s%c%c" .. EC .. ")" .. EC .. ": ",
				ent.client.pers.netname, Q_COLOR_ESCAPE, COLOR_WHITE)
		end
		color = COLOR_CYAN
	elseif mode == C.SAY_TELL then
		local ok = false
		if target ~= nil and G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 and
			target.client.sess.sessionTeam == ent.client.sess.sessionTeam then
			ok, location = G.Team_GetLocationMsg(ent, 64)
		end
		if ok then
			name = QS.Com_sprintf(64, EC .. "[%s%c%c" .. EC .. "] (%s)" .. EC .. ": ", ent.client.pers.netname, Q_COLOR_ESCAPE, COLOR_WHITE, location)
		else
			name = QS.Com_sprintf(64, EC .. "[%s%c%c" .. EC .. "]" .. EC .. ": ", ent.client.pers.netname, Q_COLOR_ESCAPE, COLOR_WHITE)
		end
		color = COLOR_MAGENTA
	else
		G.G_LogPrintf("say: %s: %s\n", ent.client.pers.netname, chatText)
		name = QS.Com_sprintf(64, "%s%c%c" .. EC .. ": ", ent.client.pers.netname, Q_COLOR_ESCAPE, COLOR_WHITE)
		color = COLOR_GREEN
	end
	-- Add the chat text
	text = QS.Q_strncpyz(chatText, C.MAX_SAY_TEXT)

	if target ~= nil then
		SF.G_SayTo(ent, target, mode, color, name, text)
		return
	end

	-- echo the text to the console
	if G.g_dedicated.integer ~= 0 then
		G.G_Printf("%s%s\n", name, text)
	end

	-- send it to all the apropriate clients
	for j = 0, G.level.maxclients - 1 do
		other = G.g_entities[j]
		SF.G_SayTo(ent, other, mode, color, name, text)
	end
	if G.g_adminParseSay.integer ~= 0 then
		G.G_admin_cmd_check(ent, true)
	end
end

function SF.Cmd_Say_f(ent)
	local p
	local arg
	local mode = C.SAY_ALL

	arg = G.trap_Argv(0)
	if QS.Q_strequal(arg, "say_team") then
		mode = C.SAY_TEAM
	end

	if G.trap_Argc() < 2 then
		return
	end

	p = G.ConcatArgs(1)
	G.G_Say(ent, nil, mode, p)
end

function SF.Cmd_Tell_f(ent)
	local targetNum
	local target
	local p
	local arg

	if G.trap_Argc() < 2 then
		return
	end

	arg = G.trap_Argv(1)
	targetNum = QS.atoi(arg)
	if targetNum < 0 or targetNum >= G.level.maxclients then
		return
	end

	target = G.g_entities[targetNum]
	if target == nil or not target.inuse or target.client == nil then
		return
	end

	p = G.ConcatArgs(2)

	G.G_LogPrintf("tell: %s to %s: %s\n", ent.client.pers.netname, target.client.pers.netname, p)
	G.G_Say(ent, target, C.SAY_TELL, p)
	-- don't tell to the player self if it was already directed to this player
	-- also don't send the chat back to a bot
	if ent ~= target and bit32.band(ent.r.svFlags, C.SVF_BOT) == 0 then
		G.G_Say(ent, ent, C.SAY_TELL, p)
	end
end

function SF.G_VoiceTo(ent, other, mode, id, voiceonly)
	local color
	local cmd

	if other == nil then
		return
	end
	if not other.inuse then
		return
	end
	if other.client == nil then
		return
	end
	if mode == C.SAY_TEAM and not G.OnSameTeam(ent, other) then
		return
	end
	-- no chatting to players in tournements
	if G.g_gametype.integer == C.GT_TOURNAMENT then
		return
	end

	if mode == C.SAY_TEAM then
		color = COLOR_CYAN
		cmd = "vtchat"
	elseif mode == C.SAY_TELL then
		color = COLOR_MAGENTA
		cmd = "vtell"
	else
		color = COLOR_GREEN
		cmd = "vchat"
	end

	G.trap_SendServerCommand(other.index, QS.va("%s %d %d %d %s", cmd, voiceonly, ent.s.number, color, id))
end

function G.G_Voice(ent, target, mode, id, voiceonly)
	local other

	if (G.g_gametype.integer < C.GT_TEAM or G.g_ffa_gt == 1) and mode == C.SAY_TEAM then
		mode = C.SAY_ALL
	end

	if target ~= nil then
		SF.G_VoiceTo(ent, target, mode, id, voiceonly)
		return
	end

	-- echo the text to the console
	if G.g_dedicated.integer ~= 0 then
		G.G_Printf("voice: %s %s\n", ent.client.pers.netname, id)
	end

	-- send it to all the apropriate clients
	for j = 0, G.level.maxclients - 1 do
		other = G.g_entities[j]
		SF.G_VoiceTo(ent, other, mode, id, voiceonly)
	end
end

function SF.Cmd_Voice_f(ent)
	local p
	local arg
	local mode = C.SAY_ALL
	local voiceonly = false

	arg = G.trap_Argv(0)
	if QS.Q_strequal(arg, "vsay_team") or
		QS.Q_strequal(arg, "vosay_team") then
		mode = C.SAY_TEAM
	end

	if QS.Q_strequal(arg, "vosay") or
		QS.Q_strequal(arg, "vosay_team") then
		voiceonly = true
	end

	if G.trap_Argc() < 2 then
		return
	end

	p = G.ConcatArgs(1)

	G.G_Voice(ent, nil, mode, p, voiceonly)
end

function SF.Cmd_VoiceTell_f(ent)
	local targetNum
	local target
	local id
	local arg
	local voiceonly = false

	if G.trap_Argc() < 2 then
		return
	end

	arg = G.trap_Argv(0)
	if QS.Q_strequal(arg, "votell") then
		voiceonly = true
	end

	arg = G.trap_Argv(1)
	targetNum = QS.atoi(arg)
	if targetNum < 0 or targetNum >= G.level.maxclients then
		return
	end

	target = G.g_entities[targetNum]
	if target == nil or not target.inuse or target.client == nil then
		return
	end

	id = G.ConcatArgs(2)

	G.G_LogPrintf("vtell: %s to %s: %s\n", ent.client.pers.netname, target.client.pers.netname, id)
	G.G_Voice(ent, target, C.SAY_TELL, id, voiceonly)
	-- don't tell to the player self if it was already directed to this player
	-- also don't send the chat back to a bot
	if ent ~= target and bit32.band(ent.r.svFlags, C.SVF_BOT) == 0 then
		G.G_Voice(ent, ent, C.SAY_TELL, id, voiceonly)
	end
end

function SF.Cmd_VoiceTaunt_f(ent)
	local who

	if ent.client == nil then
		return
	end

	-- insult someone who just killed you
	if ent.enemy ~= nil and ent.enemy.client ~= nil and ent.enemy.client.lastkilled_client == ent.s.number then
		-- i am a dead corpse
		if bit32.band(ent.enemy.r.svFlags, C.SVF_BOT) == 0 then
			G.G_Voice(ent, ent.enemy, C.SAY_TELL, VOICECHAT_DEATHINSULT, false)
		end
		if bit32.band(ent.r.svFlags, C.SVF_BOT) == 0 then
			G.G_Voice(ent, ent, C.SAY_TELL, VOICECHAT_DEATHINSULT, false)
		end
		ent.enemy = nil
		return
	end
	-- insult someone you just killed
	if ent.client.lastkilled_client >= 0 and ent.client.lastkilled_client ~= ent.s.number then
		who = G.g_entities[ent.client.lastkilled_client]
		if who.client ~= nil then
			-- who is the person I just killed
			if who.client.lasthurt_mod == C.MOD_GAUNTLET then
				if bit32.band(who.r.svFlags, C.SVF_BOT) == 0 then
					G.G_Voice(ent, who, C.SAY_TELL, VOICECHAT_KILLGAUNTLET, false) -- and I killed them with a gauntlet
				end
				if bit32.band(ent.r.svFlags, C.SVF_BOT) == 0 then
					G.G_Voice(ent, ent, C.SAY_TELL, VOICECHAT_KILLGAUNTLET, false)
				end
			else
				if bit32.band(who.r.svFlags, C.SVF_BOT) == 0 then
					G.G_Voice(ent, who, C.SAY_TELL, VOICECHAT_KILLINSULT, false) -- and I killed them with something else
				end
				if bit32.band(ent.r.svFlags, C.SVF_BOT) == 0 then
					G.G_Voice(ent, ent, C.SAY_TELL, VOICECHAT_KILLINSULT, false)
				end
			end
			ent.client.lastkilled_client = -1
			return
		end
	end

	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		-- praise a team mate who just got a reward
		for i = 0, C.MAX_CLIENTS - 1 do
			who = G.g_entities[i]
			if who.client ~= nil and who ~= ent and who.client.sess.sessionTeam == ent.client.sess.sessionTeam then
				if who.client.rewardTime > G.level.time then
					if bit32.band(who.r.svFlags, C.SVF_BOT) == 0 then
						G.G_Voice(ent, who, C.SAY_TELL, VOICECHAT_PRAISE, false)
					end
					if bit32.band(ent.r.svFlags, C.SVF_BOT) == 0 then
						G.G_Voice(ent, ent, C.SAY_TELL, VOICECHAT_PRAISE, false)
					end
					return
				end
			end
		end
	end

	-- just say something
	G.G_Voice(ent, nil, C.SAY_ALL, VOICECHAT_TAUNT, false)
end

SF.gc_orders = {
	[0] = "hold your position",
	"hold this position",
	"come here",
	"cover me",
	"guard location",
	"search and destroy",
	"report",
}

function G.Cmd_GameCommand_f(ent)
	local player
	local order
	local str

	str = G.trap_Argv(1)
	player = QS.atoi(str)
	str = G.trap_Argv(2)
	order = QS.atoi(str)

	if player < 0 or player >= C.MAX_CLIENTS then
		return
	end
	if order < 0 or order > 7 then
		return
	end
	G.G_Say(ent, G.g_entities[player], C.SAY_TELL, SF.gc_orders[order])
	G.G_Say(ent, ent, C.SAY_TELL, SF.gc_orders[order])
end

return nil
