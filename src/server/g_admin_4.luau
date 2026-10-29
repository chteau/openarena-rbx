--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_admin.c, part 4 of 4).

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
-- Luau port of OpenArena 0.8.8's g_admin.c (gamecode 9e0f0c0) (part 4). Admin commands help..warn, print/buffer helpers, cleanup.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_admin")

local ADMF_UNACCOUNTABLE = string.byte("2")

-- g_admin.h macros
local function AP(x)
	G.trap_SendServerCommand(-1, x)
end
local function CPx(x, y)
	G.trap_SendServerCommand(x, y)
end
local function ADMP(ent, x)
	G.G_admin_print(ent, x)
end
local function ADMBP(ent, x)
	G.G_admin_buffer_print(ent, x)
end
local function ADMBP_begin()
	G.G_admin_buffer_begin()
end
local function ADMBP_end(ent)
	G.G_admin_buffer_end(ent)
end

local function netnameOf(ent)
	if ent then
		return ent.client.pers.netname
	end
	return "console"
end

local function consoleNameOf(ent)
	if ent then
		return ent.client.pers.netname
	end
	return "^3SERVER CONSOLE"
end

local function becauseOf(reason)
	if reason ~= "" then
		return " because:\n", reason
	end
	return "", ""
end

function G.G_admin_help(ent, skiparg)
	local i

	if G.G_SayArgc() < 2 + skiparg then
		local j = 0
		local count = 0

		ADMBP_begin()
		for k = 0, SF.adminNumCmds - 1 do
			i = k
			if G.G_admin_permission(ent, string.sub(G.g_admin_cmds[i].flag, 1, 1)) then
				ADMBP(ent, QS.va("^3!%-12s", G.g_admin_cmds[i].keyword))
				j += 1
				count += 1
			end
			-- show 6 commands per line
			if j == 6 then
				ADMBP(ent, "\n")
				j = 0
			end
		end
		i = 0
		while i < C.MAX_ADMIN_COMMANDS and G.g_admin_commands[i] ~= nil do
			if not SF.admin_command_permission(ent, G.g_admin_commands[i].command) then
				i += 1
				continue
			end
			ADMBP(ent, QS.va("^3!%-12s", G.g_admin_commands[i].command))
			j += 1
			count += 1
			-- show 6 commands per line
			if j == 6 then
				ADMBP(ent, "\n")
				j = 0
			end
			i += 1
		end
		if count ~= 0 then
			ADMBP(ent, "\n")
		end
		ADMBP(ent, QS.va("^3!help: ^7%i available commands\n", count))
		ADMBP(ent, "run !help [^3command^7] for help with a specific command.\n")
		ADMBP_end(ent)

		return true
	else
		--!help param
		local param = G.G_SayArgv(1 + skiparg, C.MAX_ADMIN_CMD_LEN)
		local cmd
		if string.sub(param, 1, 1) == "!" then
			cmd = string.sub(param, 2)
		else
			cmd = param
		end
		ADMBP_begin()
		for k = 0, SF.adminNumCmds - 1 do
			i = k
			if QS.Q_stricmp(cmd, G.g_admin_cmds[i].keyword) == 0 then
				if not G.G_admin_permission(ent, string.sub(G.g_admin_cmds[i].flag, 1, 1)) then
					ADMBP(ent, QS.va("^3!help: ^7you do not have permission to use '%s'\n",
						G.g_admin_cmds[i].keyword))
					ADMBP_end(ent)
					return false
				end
				ADMBP(ent, QS.va("^3!help: ^7help for '!%s':\n",
					G.g_admin_cmds[i].keyword))
				ADMBP(ent, QS.va(" ^3Function: ^7%s\n", G.g_admin_cmds[i]["function"]))
				ADMBP(ent, QS.va(" ^3Syntax: ^7!%s %s\n", G.g_admin_cmds[i].keyword,
					G.g_admin_cmds[i].syntax))
				ADMBP(ent, QS.va(" ^3Flag: ^7'%c'\n", string.byte(G.g_admin_cmds[i].flag, 1) or 0))
				ADMBP_end(ent)
				return true
			end
		end
		i = 0
		while i < C.MAX_ADMIN_COMMANDS and G.g_admin_commands[i] ~= nil do
			if QS.Q_stricmp(cmd, G.g_admin_commands[i].command) == 0 then
				if not SF.admin_command_permission(ent, G.g_admin_commands[i].command) then
					ADMBP(ent, QS.va("^3!help: ^7you do not have permission to use '%s'\n",
						G.g_admin_commands[i].command))
					ADMBP_end(ent)
					return false
				end
				ADMBP(ent, QS.va("^3!help: ^7help for '%s':\n",
					G.g_admin_commands[i].command))
				ADMBP(ent, QS.va(" ^3Description: ^7%s\n", G.g_admin_commands[i].desc))
				ADMBP(ent, QS.va(" ^3Syntax: ^7!%s\n", G.g_admin_commands[i].command))
				ADMBP_end(ent)
				return true
			end
			i += 1
		end
		ADMBP(ent, QS.va("^3!help: ^7no help found for '%s'\n", cmd))
		ADMBP_end(ent)
		return false
	end
end

function G.G_admin_admintest(ent, skiparg)
	local i = 0
	local l = 0
	local found = false
	local lname = false

	if not ent then
		ADMP(ent, "^3!admintest: ^7you are on the console.\n")
		return true
	end
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil do
		if QS.Q_stricmp(G.g_admin_admins[i].guid, ent.client.pers.guid) == 0 then
			found = true
			break
		end
		i += 1
	end

	if found then
		l = G.g_admin_admins[i].level
		i = 0
		while i < C.MAX_ADMIN_LEVELS and G.g_admin_levels[i] ~= nil do
			if G.g_admin_levels[i].level ~= l then
				i += 1
				continue
			end
			if G.g_admin_levels[i].name ~= "" then
				lname = true
				break
			end
			i += 1
		end
	end
	AP(QS.va("print \"^3!admintest: ^7%s^7 is a level %d admin %s%s^7%s\n\"",
		ent.client.pers.netname,
		l,
		if lname then "(" else "",
		if lname then G.g_admin_levels[i].name else "",
		if lname then ")" else ""))
	return true
end

function G.G_admin_allready(ent, skiparg)
	local cl

	if G.level.intermissiontime == 0 then
		ADMP(ent, "^3!allready: ^7this command is only valid during intermission\n")
		return false
	end

	for i = 0, G.g_maxclients.integer - 1 do
		cl = G.level.clients[i]
		if cl.pers.connected ~= C.CON_CONNECTED then
			continue
		end

		if cl.sess.sessionTeam == C.TEAM_NONE then
			continue
		end

		cl.readyToExit = true
	end
	AP(QS.va("print \"^3!allready:^7 %s^7 says everyone is READY now\n\"",
		netnameOf(ent)))
	return true
end

function G.G_admin_cancelvote(ent, skiparg)
	local level = G.level
	if level.voteTime == 0 and level.teamVoteTime[0] == 0 and level.teamVoteTime[1] == 0 then
		ADMP(ent, "^3!cancelvote: ^7no vote in progress\n")
		return false
	end
	level.voteNo = level.numConnectedClients
	level.voteYes = 0
	G.CheckVote()
	level.teamVoteNo[0] = level.numConnectedClients
	level.teamVoteYes[0] = 0
	G.CheckTeamVote(C.TEAM_RED)
	level.teamVoteNo[1] = level.numConnectedClients
	level.teamVoteYes[1] = 0
	G.CheckTeamVote(C.TEAM_BLUE)
	AP(QS.va("print \"^3!cancelvote: ^7%s^7 decided that everyone voted No\n\"",
		netnameOf(ent)))
	return true
end

function G.G_admin_passvote(ent, skiparg)
	local level = G.level
	if level.voteTime == 0 and level.teamVoteTime[0] == 0 and level.teamVoteTime[1] == 0 then
		ADMP(ent, "^3!passvote: ^7no vote in progress\n")
		return false
	end
	level.voteYes = level.numConnectedClients
	level.voteNo = 0
	G.CheckVote()
	level.teamVoteYes[0] = level.numConnectedClients
	level.teamVoteNo[0] = 0
	G.CheckTeamVote(C.TEAM_RED)
	level.teamVoteYes[1] = level.numConnectedClients
	level.teamVoteNo[1] = 0
	G.CheckTeamVote(C.TEAM_BLUE)
	AP(QS.va("print \"^3!passvote: ^7%s^7 decided that everyone voted Yes\n\"",
		netnameOf(ent)))
	return true
end

function G.G_admin_spec999(ent, skiparg)
	local vic

	for i = 0, G.level.maxclients - 1 do
		vic = G.g_entities[i]
		if not vic.client then
			continue
		end
		if vic.client.pers.connected ~= C.CON_CONNECTED then
			continue
		end
		if vic.client.sess.sessionTeam == C.TEAM_NONE then
			continue
		end
		if vic.client.ps.ping == 999 then
			G.SetTeam(vic, "spectator")
			AP(QS.va("print \"^3!spec999: ^7%s^7 moved ^7%s^7 to spectators\n\"",
				netnameOf(ent),
				vic.client.pers.netname))
		end
	end
	return true
end

function G.G_admin_rename(ent, skiparg)
	local pids = {}
	local found
	local name
	local newname
	local oldname
	local err
	local userinfo
	local s
	local victim

	if G.G_SayArgc() < 3 + skiparg then
		ADMP(ent, "^3!rename: ^7usage: !rename [name] [newname]\n")
		return false
	end
	name = G.G_SayArgv(1 + skiparg, C.MAX_NAME_LENGTH)
	s = G.G_SayConcatArgs(2 + skiparg)
	newname = QS.Q_strncpyz(s, C.MAX_NAME_LENGTH)
	found = G.G_ClientNumbersFromString(name, pids, C.MAX_CLIENTS)
	if found ~= 1 then
		err = G.G_MatchOnePlayer(pids, found, C.MAX_STRING_CHARS)
		ADMP(ent, QS.va("^3!rename: ^7%s\n", err))
		return false
	end
	victim = G.g_entities[pids[0]]
	if not SF.admin_higher(ent, victim) then
		ADMP(ent, "^3!rename: ^7sorry, but your intended victim has a higher admin"
			.. " level than you\n")
		return false
	end
	local ok
	ok, err = G.G_admin_name_check(victim, newname, C.MAX_STRING_CHARS)
	if not ok then
		ADMP(ent, QS.va("^3!rename: ^7%s\n", err))
		return false
	end

	--KK-OAX Since NameChanges are not going to be implemented just yet...let's ignore this.
	G.level.clients[pids[0]].pers.nameChanges -= 1
	G.level.clients[pids[0]].pers.nameChangeTime = 0

	userinfo = G.trap_GetUserinfo(pids[0])
	s = QS.Info_ValueForKey(userinfo, "name")
	oldname = QS.Q_strncpyz(s, C.MAX_NAME_LENGTH)
	userinfo = QS.Info_SetValueForKey(userinfo, "name", newname)
	G.trap_SetUserinfo(pids[0], userinfo)
	G.ClientUserinfoChanged(pids[0])
	AP(QS.va("print \"^3!rename: ^7%s^7 has been renamed to %s^7 by %s\n\"",
		oldname,
		newname,
		netnameOf(ent)))
	return true
end

--KK-Will Fix this For OAPub
function G.G_admin_restart(ent, skiparg)
	local layout = ""

	if G.G_SayArgc() > 1 + skiparg then
		local map = G.trap_Cvar_VariableStringBuffer("mapname")
		layout = G.G_SayArgv(skiparg + 1, C.MAX_CVAR_VALUE_STRING)
	end

	G.trap_SendConsoleCommand(C.EXEC_APPEND, "map_restart")
	AP(QS.va("print \"^3!restart: ^7map restarted by %s \n\"",
		netnameOf(ent)))
	return true
end

function G.G_admin_nextmap(ent, skiparg)
	AP(QS.va("print \"^3!nextmap: ^7%s^7 decided to load the next map\n\"",
		netnameOf(ent)))
	G.LogExit(QS.va("nextmap was run by %s", netnameOf(ent)))
	return true
end

function G.G_admin_namelog(ent, skiparg)
	local search = ""
	local s2 = ""
	local n2 = ""
	local guid_stub
	local found = false
	local printed = 0

	if G.G_SayArgc() > 1 + skiparg then
		search = G.G_SayArgv(1 + skiparg, C.MAX_NAME_LENGTH)
		s2 = G.G_SanitiseString(search, C.MAX_NAME_LENGTH)
	end
	ADMBP_begin()
	local i = 0
	while i < C.MAX_ADMIN_NAMELOGS and G.g_admin_namelog[i] ~= nil do
		local nl = G.g_admin_namelog[i]
		local skip = false
		if search ~= "" then
			found = false
			local j = 0
			while j < C.MAX_ADMIN_NAMELOG_NAMES and nl.name[j] ~= "" do
				n2 = G.G_SanitiseString(nl.name[j], C.MAX_NAME_LENGTH)
				if QS.strstr(n2, s2) then
					found = true
					break
				end
				j += 1
			end
			if not found then
				skip = true
			end
		end
		if not skip then
			printed += 1
			guid_stub = string.sub(nl.guid, 25, 32)
			if nl.slot > -1 then
				ADMBP(ent, "^3")
			end
			ADMBP(ent, QS.va("%-2s (*%s) %15s^7",
				if nl.slot > -1 then QS.va("%d", nl.slot) else "-",
				guid_stub, nl.ip))
			local j = 0
			while j < C.MAX_ADMIN_NAMELOG_NAMES and nl.name[j] ~= "" do
				ADMBP(ent, QS.va(" '%s^7'", nl.name[j]))
				j += 1
			end
			ADMBP(ent, "\n")
		end
		i += 1
	end
	ADMBP(ent, QS.va("^3!namelog:^7 %d recent clients found\n", printed))
	ADMBP_end(ent)
	return true
end

function G.G_admin_lock(ent, skiparg)
	local teamName
	local team

	if G.G_SayArgc() < 2 + skiparg then
		ADMP(ent, "^3!lock: ^7usage: !lock [r|b|f]\n")
		return false
	end
	teamName = string.sub(G.G_SayArgv(1 + skiparg, 2), 1, 1)
	team = G.G_TeamFromString(teamName)

	if team == C.TEAM_RED then
		if G.level.RedTeamLocked then
			ADMP(ent, "^3!lock: ^7the Red team is already locked\n")
			return false
		end
		G.level.RedTeamLocked = true
	elseif team == C.TEAM_BLUE then
		if G.level.BlueTeamLocked then
			ADMP(ent, "^3!lock: ^7the Blue team is already locked\n")
			return false
		end
		G.level.BlueTeamLocked = true
	elseif team == C.TEAM_FREE then
		if G.level.FFALocked then
			ADMP(ent, "^3!lock: ^7DeathMatch is already Locked!!!\n")
			return false
		end
		G.level.FFALocked = true
	else
		ADMP(ent, QS.va("^3!lock: ^7invalid team\"%c\"\n", string.byte(teamName, 1) or 0))
		return false
	end

	AP(QS.va("print \"^3!lock: ^7the %s team has been locked by %s\n\"",
		BG.BG_TeamName(team),
		netnameOf(ent)))
	return true
end

function G.G_admin_unlock(ent, skiparg)
	local teamName
	local team

	if G.G_SayArgc() < 2 + skiparg then
		ADMP(ent, "^3!unlock: ^7usage: !unlock [r|b|f]\n")
		return false
	end
	teamName = string.sub(G.G_SayArgv(1 + skiparg, 2), 1, 1)
	team = G.G_TeamFromString(teamName)

	if team == C.TEAM_RED then
		if not G.level.RedTeamLocked then
			ADMP(ent, "^3!unlock: ^7the Red team is not currently locked\n")
			return false
		end
		G.level.RedTeamLocked = false
	elseif team == C.TEAM_BLUE then
		if not G.level.BlueTeamLocked then
			ADMP(ent, "^3!unlock: ^7the Blue team is not currently locked\n")
			return false
		end
		G.level.BlueTeamLocked = false
	elseif team == C.TEAM_FREE then
		if not G.level.FFALocked then
			ADMP(ent, "^!unlock: ^7Deathmatch is not currently Locked!!!\n")
			return false
		end
		G.level.FFALocked = false
	else
		ADMP(ent, QS.va("^3!unlock: ^7invalid team\"%c\"\n", string.byte(teamName, 1) or 0))
		return false
	end
	AP(QS.va("print \"^3!unlock: ^7the %s team has been unlocked by %s\n\"",
		BG.BG_TeamName(team),
		netnameOf(ent)))
	return true
end

--KK-OAX Begin Addition
function G.G_admin_disorient(ent, skiparg)
	local pids = {}
	local found
	local name
	local err
	local reason
	local vic

	if G.G_SayArgc() < 2 + skiparg then
		ADMP(ent, "^/disorient usage: ^7!disorient [name|slot#] [reason]")
		return false
	end
	name = G.G_SayArgv(1 + skiparg, C.MAX_NAME_LENGTH)
	reason = G.G_SayConcatArgs(2 + skiparg)

	found = G.G_ClientNumbersFromString(name, pids, C.MAX_CLIENTS)
	if found ~= 1 then
		err = G.G_MatchOnePlayer(pids, found, C.MAX_STRING_CHARS)
		ADMP(ent, QS.va("^/disorient: ^7%s", err))
		return false
	end
	vic = G.g_entities[pids[0]]
	if not SF.admin_higher(ent, vic) then
		ADMP(ent, "^/disorient: ^7sorry, but your intended victim has a higher admin level than you do")
		return false
	end

	if not (vic.client.sess.sessionTeam == C.TEAM_RED or
			vic.client.sess.sessionTeam == C.TEAM_BLUE or
			vic.client.sess.sessionTeam == C.TEAM_FREE) then
		ADMP(ent, "^/disorient: ^7player must be on a team")
		return false
	end
	if vic.client.pers.disoriented then
		ADMP(ent, QS.va("^/disorient: ^7%s^7 is already disoriented",
			vic.client.pers.netname))
		return false
	end
	vic.client.pers.disoriented = true
	AP(QS.va("chat \"^/disorient: ^7%s ^7is disoriented\" -1",
		vic.client.pers.netname))

	local because, rsn = becauseOf(reason)
	CPx(pids[0], QS.va("cp \"%s ^7disoriented you%s%s\"",
		consoleNameOf(ent),
		because,
		rsn))
	return true
end

function G.G_admin_orient(ent, skiparg)
	local pids = {}
	local found
	local name
	local err
	local vic

	if G.G_SayArgc() < 2 + skiparg then
		ADMP(ent, "^/orient usage: ^7!orient [name|slot#]")
		return false
	end
	name = G.G_SayArgv(1 + skiparg, C.MAX_NAME_LENGTH)
	--Fix
	found = G.G_ClientNumbersFromString(name, pids, C.MAX_CLIENTS)
	if found ~= 1 then
		err = G.G_MatchOnePlayer(pids, found, C.MAX_STRING_CHARS)
		ADMP(ent, QS.va("^/orient: ^7%s", err))
		return false
	end
	vic = G.g_entities[pids[0]]

	if not vic.client.pers.disoriented then
		ADMP(ent, QS.va("^/orient: ^7%s^7 is not currently disoriented",
			vic.client.pers.netname))
		return false
	end
	vic.client.pers.disoriented = false
	AP(QS.va("chat \"^/orient: ^7%s ^7is no longer disoriented\" -1",
		vic.client.pers.netname))

	CPx(pids[0], QS.va("cp \"%s ^7oriented you\"",
		consoleNameOf(ent)))
	return true
end

function G.G_admin_slap(ent, skiparg)
	local pids = {}
	local found
	local dmg
	local name
	local err
	local reason
	local damage
	local vic
	local soundIndex

	--KK-Too many Parameters Check removed.  It'll truncate the reason message.

	if G.G_SayArgc() < 2 + skiparg then
		ADMP(ent, "^/slap usage: ^7!slap [name|slot#] [reason] [damage]")
		return false
	end

	name = G.G_SayArgv(1 + skiparg, C.MAX_NAME_LENGTH)
	damage = string.sub(G.G_SayArgv(2 + skiparg, 4), 1, 3)

	dmg = QS.atoi(damage)
	if dmg == 0 then
		dmg = 25
		reason = G.G_SayConcatArgs(2 + skiparg)
	else
		reason = G.G_SayConcatArgs(3 + skiparg)
	end

	found = G.G_ClientNumbersFromString(name, pids, C.MAX_CLIENTS)
	if found ~= 1 then
		err = G.G_MatchOnePlayer(pids, found, C.MAX_STRING_CHARS)
		ADMP(ent, QS.va("^/slap: ^7%s", err))
		return false
	end

	vic = G.g_entities[pids[0]]
	if not SF.admin_higher(ent, vic) then
		ADMP(ent, "^/slap: ^7sorry, but your intended victim has a higher admin level than you do")
		return false
	end

	if not (vic.client.sess.sessionTeam == C.TEAM_RED or
			vic.client.sess.sessionTeam == C.TEAM_BLUE or
			vic.client.sess.sessionTeam == C.TEAM_FREE) then
		ADMP(ent, "^/slap: ^7player must be in the game!")
		return false
	end
	--Player Not Alive
	if vic.health < 1 then
		--Is Their Body Alive?
		if vic.s.eType ~= C.ET_INVISIBLE then
			--Make 'em a Bloody mess
			G.G_Damage(vic, nil, nil, nil, nil, 500, 0, C.MOD_UNKNOWN)
		end
		--Force Their Butt to Respawn
		G.ClientSpawn(vic)
	end
	-- Will the Slap Kill them? (Obviously false if we Respawned 'em)
	if not (vic.health > dmg) then
		vic.health = 1
	else --If it won't kill em...Do the full Damage
		vic.health -= dmg
	end

	--KK-OAX Play them the slap sound
	soundIndex = G.G_SoundIndex("sound/admin/slap.wav")
	G.G_Sound(vic, C.CHAN_VOICE, soundIndex)

	--Print it to everybody
	AP(QS.va("chat \"^/slap: ^7%s ^7was slapped\" -1", vic.client.pers.netname))
	--CenterPrint it to the Person Being Slapped
	local because, rsn = becauseOf(reason)
	CPx(pids[0], QS.va("cp \"%s ^7slapped you%s%s\"",
		consoleNameOf(ent),
		because,
		rsn))
	return true
end

--Called Each Time a Warning is Created
function G.G_admin_warn_check(ent)
	local ip
	local guid
	local t
	local numWarnings = 0

	t = G.trap_RealTime(nil)

	ip = ent.client.pers.ip

	--We Don't Want to Count Warnings for the LocalHost
	if ip == "" then
		return 0
	end

	guid = ent.client.pers.guid

	--Just to make sure...Don't want to crash...Will Figure something better out later
	if guid == "" then
		return 0
	end

	--For Each Warning, up to the max number of warnings
	local i = 0
	while i < C.MAX_ADMIN_WARNINGS and G.g_admin_warnings[i] ~= nil do
		-- Ignore Expired Warnings
		if (G.g_admin_warnings[i].expires - t) < 1 then
			i += 1
			continue
		end
		--If a warning matches their IP or GUID
		if QS.strstr(ip, G.g_admin_warnings[i].ip) or QS.strstr(guid, G.g_admin_warnings[i].guid) then
			numWarnings += 1
		end
		i += 1
	end
	--If we get here, return the number of warnings;
	return numWarnings
end

function G.G_admin_warn(ent, skiparg)
	local pids = {}
	local found
	local seconds
	local name
	local err
	local reason
	local minargc
	local duration
	local s2
	local vic
	local totalWarnings
	local soundIndex

	if G.G_admin_permission(ent, ADMF_UNACCOUNTABLE) then
		minargc = 1 + skiparg
	else
		minargc = 2 + skiparg
	end

	if G.G_SayArgc() < minargc then
		ADMP(ent, "^3!warn: ^7usage: !warn [name|slot|ip] [reason]\n")
		return false
	end

	name = G.G_SayArgv(1 + skiparg, C.MAX_NAME_LENGTH)
	s2 = G.G_SanitiseString(name, C.MAX_NAME_LENGTH)
	reason = G.G_SayConcatArgs(2 + skiparg)

	seconds = G.g_warningExpire.integer

	found = G.G_ClientNumbersFromString(name, pids, C.MAX_CLIENTS)
	if found ~= 1 then
		err = G.G_MatchOnePlayer(pids, found, C.MAX_STRING_CHARS)
		ADMP(ent, QS.va("^/warn: ^7%s", err))
		return false
	end

	vic = G.g_entities[pids[0]]
	if not SF.admin_higher(ent, vic) then
		ADMP(ent, "^/slap: ^7sorry, but your intended victim has a higher admin level than you do")
		return false
	end

	duration = G.G_admin_duration(if seconds ~= 0 then seconds else -1, 32)

	SF.admin_create_warning(ent,
		vic.client.pers.netname,
		vic.client.pers.guid,
		vic.client.pers.ip,
		seconds, reason)

	if G.g_admin.string == "" then
		ADMP(ent, "^3!warn: ^7WARNING g_admin not set, not saving warning to a file\n")
	else
		SF.admin_writeconfig()
	end

	--KK, Use The Check Warnings Deal Here
	totalWarnings = G.G_admin_warn_check(vic)

	-- Play the whistle
	soundIndex = G.G_SoundIndex("sound/admin/whistle.wav")
	G.G_GlobalSound(soundIndex)

	--First Check to make sure g_maxWarnings isn't a Null Value
	if G.g_maxWarnings.integer ~= 0 then
		--If they have gone over the max number of warnings...
		if totalWarnings >= G.g_maxWarnings.integer then
			--Give them The Boot till the Warning Expires
			SF.admin_create_ban(ent,
				vic.client.pers.netname,
				vic.client.pers.guid,
				vic.client.pers.ip,
				seconds,
				"Too Many Warnings")

			if G.g_admin.string ~= "" then
				SF.admin_writeconfig()
			end

			G.trap_SendServerCommand(pids[0],
				QS.va("disconnect \"You have been kicked.\n%s^7\nreason:\n%s\"",
					if ent then QS.va("admin:\n%s", ent.client.pers.netname) else "SERVER",
					"Too Many Warnings"))

			G.trap_DropClient(pids[0], QS.va("has been kicked%s^7. reason: %s",
				"Auto-Admin System",
				"Too Many Warnings"))
			return true
		else
			--Print it to everybody
			AP(QS.va("chat \"^/warn: ^7%s ^7was warned\" -1", vic.client.pers.netname))
			--CenterPrint it to the Person Being Slapped
			local because, rsn = becauseOf(reason)
			CPx(pids[0], QS.va("cp \"%s ^7warned you%s%s\"",
				consoleNameOf(ent),
				because,
				rsn))
			return true
		end
	else --KK-OAX g_maxWarnings is null or 0
		AP(QS.va("chat \"^/warn: ^7%s ^7was warned\" -1", vic.client.pers.netname))
		--CenterPrint it to the Person Being Slapped
		local because, rsn = becauseOf(reason)
		CPx(pids[0], QS.va("cp \"%s ^7warned you%s%s\"",
			consoleNameOf(ent),
			because,
			rsn))
		return true
	end
end

function G.G_admin_shuffle(ent, skipargs)
	G.trap_SendConsoleCommand(C.EXEC_APPEND, "shuffle")
	AP(QS.va("print \"^3!shuffle: ^7teams shuffled by %s \n\"",
		netnameOf(ent)))
	return true
end

--KK-OAX End Additions

--[[
================
 G_admin_print

 This function facilitates the ADMP define.  ADMP() is similar to CP except
 that it prints the message to the server console if ent is not defined.
================
]]
function G.G_admin_print(ent, m)
	if ent then
		G.trap_SendServerCommand(ent.index, QS.va("print \"%s\"", m))
	else
		if G.trap_Cvar_VariableIntegerValue("com_ansiColor") == 0 then
			local m2 = G.G_DecolorString(m, C.MAX_STRING_CHARS)
			G.trap_Printf(m2)
		else
			G.trap_Printf(m)
		end
	end
end

function G.G_admin_buffer_begin()
	SF.g_bfb = ""
end

function G.G_admin_buffer_end(ent)
	ADMP(ent, SF.g_bfb)
end

function G.G_admin_buffer_print(ent, m)
	-- 1022 - strlen("print 64 \"\"") - 1
	if #m + #SF.g_bfb >= 1009 then
		ADMP(ent, SF.g_bfb)
		SF.g_bfb = ""
	end
	SF.g_bfb = QS.Q_strcat(SF.g_bfb, 32000, m)
end

function G.G_admin_cleanup()
	local i = 0

	while i < C.MAX_ADMIN_LEVELS and G.g_admin_levels[i] ~= nil do
		G.g_admin_levels[i] = nil
		i += 1
	end
	i = 0
	while i < C.MAX_ADMIN_ADMINS and G.g_admin_admins[i] ~= nil do
		G.g_admin_admins[i] = nil
		i += 1
	end
	i = 0
	while i < C.MAX_ADMIN_BANS and G.g_admin_bans[i] ~= nil do
		G.g_admin_bans[i] = nil
		i += 1
	end
	i = 0
	while i < C.MAX_ADMIN_COMMANDS and G.g_admin_commands[i] ~= nil do
		G.g_admin_commands[i] = nil
		i += 1
	end
end

return nil
