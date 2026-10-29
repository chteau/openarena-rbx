--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_client.c).

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
-- Luau port of g_client.c, part 2 of 2 (ClientUserinfoChanged .. ClientDisconnect).

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_client")

local function isxdigitAt(s, i)
	local ch = string.sub(s, i + 1, i + 1)
	return ch ~= "" and string.match(ch, "^%x$") ~= nil
end

--[[
===========
ClientUserinfoChanged

Called from ClientConnect when the player first connects and
directly by the server system when the player updates a userinfo variable.

The game can override any of the settings and call trap_SetUserinfo
if desired.
============
]]
function G.ClientUserinfoChanged(clientNum)
	local ent
	local teamTask, teamLeader, team, health
	local s
	local model
	local headModel
	local oldname
	local err = ""
	local revertName = false

	local client
	local c1 = ""
	local c2 = ""
	local redTeam
	local blueTeam
	local userinfo

	ent = G.g_entities[clientNum]
	client = ent.client

	userinfo = G.trap_GetUserinfo(clientNum)

	-- check for malformed or illegal info strings
	if not QS.Info_Validate(userinfo) then
		userinfo = "\\name\\badinfo"
	end

	-- check the item prediction
	s = QS.Info_ValueForKey(userinfo, "cg_predictItems")
	if QS.atoi(s) == 0 then
		client.pers.predictItemPickup = false
	else
		client.pers.predictItemPickup = true
	end

	--unlagged - client options
	-- see if the player has opted out
	s = QS.Info_ValueForKey(userinfo, "cg_delag")
	if QS.atoi(s) == 0 then
		client.pers.delag = 0
	else
		client.pers.delag = QS.atoi(s)
	end

	-- see if the player is nudging his shots
	s = QS.Info_ValueForKey(userinfo, "cg_cmdTimeNudge")
	client.pers.cmdTimeNudge = QS.atoi(s)
	--unlagged - client options

	-- set name
	oldname = QS.Q_strncpyz(client.pers.netname, C.MAX_STRING_CHARS)
	s = QS.Info_ValueForKey(userinfo, "name")
	client.pers.netname = SF.ClientCleanName(s, C.MAX_NETNAME, clientNum)

	--KK-OAPub Added From Tremulous-Control Name Changes
	if oldname ~= client.pers.netname then
		if
			client.pers.nameChangeTime ~= 0
			and (G.level.time - client.pers.nameChangeTime) <= (G.g_minNameChangePeriod.value * 1000)
		then
			G.trap_SendServerCommand(
				ent.index,
				QS.va(
					"print \"Name change spam protection (g_minNameChangePeriod = %d)\n\"",
					G.g_minNameChangePeriod.integer
				)
			)
			revertName = true
		elseif G.g_maxNameChanges.integer > 0 and client.pers.nameChanges >= G.g_maxNameChanges.integer then
			G.trap_SendServerCommand(
				ent.index,
				QS.va(
					"print \"Maximum name changes reached (g_maxNameChanges = %d)\n\"",
					G.g_maxNameChanges.integer
				)
			)
			revertName = true
		elseif client.pers.muted then
			G.trap_SendServerCommand(ent.index, "print \"You cannot change your name while you are muted\n\"")
			revertName = true
		else
			local ok
			ok, err = G.G_admin_name_check(ent, client.pers.netname, C.MAX_STRING_CHARS)
			if not ok then
				G.trap_SendServerCommand(ent.index, QS.va("print \"%s\n\"", err))
				revertName = true
			end
		end

		--Never revert a bots name... just to bad if it hapens... but the bot will always be expendeble :-)
		if bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 then
			revertName = false
		end

		if revertName then
			client.pers.netname = QS.Q_strncpyz(if oldname ~= "" then oldname else "UnnamedPlayer", C.MAX_NETNAME)
			userinfo = QS.Info_SetValueForKey(userinfo, "name", oldname)
			G.trap_SetUserinfo(clientNum, userinfo)
		else
			if client.pers.connected == C.CON_CONNECTED then
				client.pers.nameChangeTime = G.level.time
				client.pers.nameChanges += 1
			end
		end
	end
	if
		(
			client.sess.sessionTeam == C.TEAM_SPECTATOR
			or (
				client.isEliminated
				and (
					G.g_gametype.integer == C.GT_ELIMINATION
					or G.g_gametype.integer == C.GT_CTF_ELIMINATION
					or G.g_gametype.integer == C.GT_LMS
				)
			)
		)
		and client.sess.spectatorState == C.SPECTATOR_SCOREBOARD
	then
		client.pers.netname = QS.Q_strncpyz("scoreboard", C.MAX_NETNAME)
	end

	if client.pers.connected == C.CON_CONNECTED then
		if oldname ~= client.pers.netname then
			G.trap_SendServerCommand(
				-1,
				QS.va("print \"%s^7 renamed to %s\n\"", oldname, client.pers.netname)
			)
		end
	end

	-- set max health
	if client.ps.powerups[C.PW_GUARD] ~= 0 then
		client.pers.maxHealth = 200
	else
		health = QS.atoi(QS.Info_ValueForKey(userinfo, "handicap"))
		client.pers.maxHealth = health
		if client.pers.maxHealth < 1 or client.pers.maxHealth > 100 then
			client.pers.maxHealth = 100
		end
	end
	client.ps.stats[C.STAT_MAX_HEALTH] = client.pers.maxHealth

	-- set model
	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt == 0 then
		model = QS.Q_strncpyz(QS.Info_ValueForKey(userinfo, "team_model"), C.MAX_QPATH)
		headModel = QS.Q_strncpyz(QS.Info_ValueForKey(userinfo, "team_headmodel"), C.MAX_QPATH)
	else
		model = QS.Q_strncpyz(QS.Info_ValueForKey(userinfo, "model"), C.MAX_QPATH)
		headModel = QS.Q_strncpyz(QS.Info_ValueForKey(userinfo, "headmodel"), C.MAX_QPATH)
	end

	-- bots set their team a few frames later
	if
		G.g_gametype.integer >= C.GT_TEAM
		and G.g_ffa_gt == 0
		and bit32.band(G.g_entities[clientNum].r.svFlags, C.SVF_BOT) ~= 0
	then
		s = QS.Info_ValueForKey(userinfo, "team")
		if QS.Q_strequal(s, "red") or QS.Q_strequal(s, "r") then
			team = C.TEAM_RED
		elseif QS.Q_strequal(s, "blue") or QS.Q_strequal(s, "b") then
			team = C.TEAM_BLUE
		else
			-- pick the team with the least number of players
			team = G.PickTeam(clientNum)
		end
		client.sess.sessionTeam = team
	else
		team = client.sess.sessionTeam
	end

	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		client.pers.teamInfo = true
	else
		s = QS.Info_ValueForKey(userinfo, "teamoverlay")
		if s == "" or QS.atoi(s) ~= 0 then
			client.pers.teamInfo = true
		else
			client.pers.teamInfo = false
		end
	end

	-- team task (0 = none, 1 = offence, 2 = defence)
	teamTask = QS.atoi(QS.Info_ValueForKey(userinfo, "teamtask"))
	-- team Leader (1 = leader, 0 is normal player)
	teamLeader = if client.sess.teamLeader then 1 else 0

	-- colors
	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt == 0 and G.g_instantgib.integer ~= 0 then
		if client.sess.sessionTeam == C.TEAM_RED then
			c1 = "4"
			c2 = "4"
		elseif client.sess.sessionTeam == C.TEAM_BLUE then
			c1 = "1"
			c2 = "1"
		end
	else
		c1 = QS.Q_strncpyz(QS.Info_ValueForKey(userinfo, "color1"), C.MAX_INFO_STRING)
		c2 = QS.Q_strncpyz(QS.Info_ValueForKey(userinfo, "color2"), C.MAX_INFO_STRING)
	end

	redTeam = QS.Q_strncpyz(QS.Info_ValueForKey(userinfo, "g_redteam"), C.MAX_INFO_STRING)
	blueTeam = QS.Q_strncpyz(QS.Info_ValueForKey(userinfo, "g_blueteam"), C.MAX_INFO_STRING)

	-- send over a subset of the userinfo keys so other clients can
	-- print scoreboards, display models, and play custom sounds
	if bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 then
		s = QS.va(
			"n\\%s\\t\\%i\\model\\%s\\hmodel\\%s\\c1\\%s\\c2\\%s\\hc\\%i\\w\\%i\\l\\%i\\skill\\%s\\tt\\%d\\tl\\%d",
			client.pers.netname,
			client.sess.sessionTeam,
			model,
			headModel,
			c1,
			c2,
			client.pers.maxHealth,
			client.sess.wins,
			client.sess.losses,
			QS.Info_ValueForKey(userinfo, "skill"),
			teamTask,
			teamLeader
		)
	else
		s = QS.va(
			"n\\%s\\t\\%i\\model\\%s\\hmodel\\%s\\g_redteam\\%s\\g_blueteam\\%s\\c1\\%s\\c2\\%s\\hc\\%i\\w\\%i\\l\\%i\\tt\\%d\\tl\\%d",
			client.pers.netname,
			client.sess.sessionTeam,
			model,
			headModel,
			redTeam,
			blueTeam,
			c1,
			c2,
			client.pers.maxHealth,
			client.sess.wins,
			client.sess.losses,
			teamTask,
			teamLeader
		)
	end

	G.trap_SetConfigstring(C.CS_PLAYERS + clientNum, s)

	-- this is not the userinfo, more like the configstring actually
	G.G_LogPrintf("ClientUserinfoChanged: %i %s\\id\\%s\n", clientNum, s, QS.Info_ValueForKey(userinfo, "cl_guid"))
end

--[[
===========
ClientConnect

Called when a player begins connecting to the server.
Called again for every map change or tournement restart.

The session information will be valid after exit.

Return NULL if the client should be allowed, otherwise return
a string with the reason for denial.

Otherwise, the client will be sent the current gamestate
and will eventually get to ClientBegin.

firstTime will be qtrue the very first time a client connects
to the server machine, but qfalse on map changes and tournement
restarts.
============
]]
function G.ClientConnect(clientNum, firstTime, isBot)
	local value
	local client
	local userinfo
	local ent
	local reason = ""
	local i

	--KK-OAX I moved these up so userinfo could be assigned/used.
	ent = G.g_entities[clientNum]
	client = G.level.clients[clientNum]
	ent.client = client
	S.copy_gclient_t(client, S.gclient_t())

	userinfo = G.trap_GetUserinfo(clientNum)

	value = QS.Info_ValueForKey(userinfo, "cl_guid")
	client.pers.guid = QS.Q_strncpyz(value, 33)

	-- IP filtering //KK-OAX Has this been obsoleted?
	-- check to see if they are on the banned IP list
	value = QS.Info_ValueForKey(userinfo, "ip")
	client.pers.ip = QS.Q_strncpyz(value, 40)

	if G.G_FilterPacket(value) and QS.Q_strequal(value, "localhost") then
		G.G_Printf("Player with IP: %s is banned\n", value)
		return "You are banned from this server."
	end

	local banned
	banned, reason = G.G_admin_ban_check(userinfo, C.MAX_STRING_CHARS)
	if banned then
		return QS.va("%s", reason)
	end

	--KK-OAX
	-- we don't check GUID or password for bots and local client
	-- NOTE: local client <-> "ip" "localhost"
	--   this means this client is not running in our current process
	if not isBot and value ~= "localhost" then
		-- check for a password
		value = QS.Info_ValueForKey(userinfo, "password")
		if
			G.g_password.string ~= ""
			and not QS.Q_strequal(G.g_password.string, "none")
			and G.g_password.string ~= value
		then
			return "Invalid password"
		end
		i = 0
		while i < 33 - 1 and isxdigitAt(client.pers.guid, i) do
			i += 1
		end
		if i < 33 - 1 then
			return "Invalid GUID"
		end

		for j = 0, G.level.maxclients - 1 do
			if G.level.clients[j].pers.connected ~= C.CON_DISCONNECTED then
				if QS.Q_strequal(client.pers.guid, G.level.clients[j].pers.guid) then
					if not G.G_ClientIsLagging(G.level.clients[j]) then
						G.trap_SendServerCommand(j, "cp \"Your GUID is not secure\"")
						return "Duplicate GUID"
					end
					G.trap_DropClient(j, "Ghost")
				end
			end
		end
	end

	--Check for local client
	if client.pers.ip == "localhost" then
		client.pers.localClient = true
	end
	client.pers.adminLevel = G.G_admin_level(ent)

	client.pers.connected = C.CON_CONNECTING

	-- check for local client
	value = QS.Info_ValueForKey(userinfo, "ip")
	if value == "localhost" then
		client.pers.localClient = true
	end

	if isBot then
		ent.r.svFlags = bit32.bor(ent.r.svFlags, C.SVF_BOT)
		ent.inuse = true
		if not G.G_BotConnect(clientNum, not firstTime) then
			return "BotConnectfailed"
		end
	end
	-- read or initialize the session data
	if firstTime or G.level.newSession then
		G.G_InitSessionData(client, userinfo)
	end
	G.G_ReadSessionData(client)

	--KK-OAX Swapped these in order...seemed to help the connection process.
	-- get and distribute relevent paramters
	G.ClientUserinfoChanged(clientNum)
	G.G_LogPrintf("ClientConnect: %i\n", clientNum)

	-- don't do the "xxx connected" messages if they were caried over from previous level
	if firstTime then
		G.trap_SendServerCommand(-1, QS.va("print \"%s^7 connected\n\"", client.pers.netname))
	end

	if G.g_gametype.integer >= C.GT_TEAM and client.sess.sessionTeam ~= C.TEAM_SPECTATOR then
		G.BroadcastTeamChange(client, -1)
	end

	-- count current clients and rank for scoreboard
	G.CalculateRanks()

	--Sago: Changed the message
	--unlagged - backward reconciliation #5
	-- announce it
	if G.g_delagHitscan.integer ~= 0 then
		G.trap_SendServerCommand(clientNum, "print \"Full lag compensation is ON!\n\"")
	else
		G.trap_SendServerCommand(clientNum, "print \"Full lag compensation is OFF!\n\"")
	end

	--unlagged - backward reconciliation #5
	G.G_admin_namelog_update(client, false)
	return nil
end

function G.motd(ent)
	local motd
	local motdFile
	local motdLen
	local fileLen

	motd = "cp \""
	fileLen, motdFile = G.trap_FS_FOpenFile(G.g_motdfile.string, C.FS_READ)
	if motdFile ~= 0 then
		motdLen = #motd
		if (motdLen + fileLen) > (1024 - 2) then
			fileLen = 1024 - 2 - motdLen
		end
		motd = motd .. G.trap_FS_Read(fileLen, motdFile)
		motd = motd .. "\""
		G.trap_FS_FCloseFile(motdFile)

		--Remove carrier return. 0x0D
		motd = string.gsub(motd, "\r", "")
	end
	G.trap_SendServerCommand(ent.index, motd)
end

--[[
===========
ClientBegin

called when a client has finished connecting, and is ready
to be placed into the level.  This will happen every level load,
and on transition between teams, but doesn't happen on respawns
============
]]
function G.ClientBegin(clientNum)
	local ent
	local client
	local tent
	local flags
	local countRed, countBlue, countFree
	local userinfo

	userinfo = G.trap_GetUserinfo(clientNum)

	ent = G.g_entities[clientNum]

	client = G.level.clients[clientNum]

	if ent.r.linked then
		G.trap_UnlinkEntity(ent)
	end
	G.G_InitGentity(ent)
	ent.touch = nil
	ent.pain = nil
	ent.client = client

	client.pers.connected = C.CON_CONNECTED
	client.pers.enterTime = G.level.time
	client.pers.teamState.state = C.TEAM_BEGIN

	--Elimination:
	client.pers.roundReached = 0 --We will spawn in next round
	if G.g_gametype.integer == C.GT_LMS then
		client.isEliminated = true --So player does not give a point in gamemode 2 and 3
	end

	--player is a bot:
	if bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 then
		if not G.level.hadBots then
			G.G_LogPrintf("Info: There has been at least 1 bot now\n")
			G.level.hadBots = true
		end
	end

	--Count smallest team
	countFree = G.TeamCount(-1, C.TEAM_FREE)
	countRed = G.TeamCount(-1, C.TEAM_RED)
	countBlue = G.TeamCount(-1, C.TEAM_BLUE)
	if G.g_gametype.integer < C.GT_TEAM or G.g_ffa_gt ~= 0 then
		if countFree > G.level.teamSize then
			G.level.teamSize = countFree
		end
	elseif countRed > countBlue then
		if countBlue > G.level.teamSize then
			G.level.teamSize = countBlue
		end
	else
		if countRed > G.level.teamSize then
			G.level.teamSize = countRed
		end
	end

	-- save eflags around this, because changing teams will
	-- cause this to happen with a valid entity, and we
	-- want to make sure the teleport bit is set right
	-- so the viewpoint doesn't interpolate through the
	-- world to the new position
	flags = client.ps.eFlags
	S.copy_playerState_t(client.ps, S.playerState_t())
	if client.sess.sessionTeam ~= C.TEAM_SPECTATOR then
		G.PlayerStore_restore(QS.Info_ValueForKey(userinfo, "cl_guid"), client.ps)
	end
	client.ps.eFlags = flags

	-- locate ent at a spawn point
	G.ClientSpawn(ent)

	if
		client.sess.sessionTeam ~= C.TEAM_SPECTATOR
		and (
			not client.isEliminated
			or (
				(G.g_gametype.integer ~= C.GT_ELIMINATION or G.level.intermissiontime ~= 0)
				and (G.g_gametype.integer ~= C.GT_CTF_ELIMINATION or G.level.intermissiontime ~= 0)
				and (G.g_gametype.integer ~= C.GT_LMS or G.level.intermissiontime ~= 0)
			)
		)
	then
		-- send event
		tent = G.G_TempEntity(ent.client.ps.origin, C.EV_PLAYER_TELEPORT_IN)
		tent.s.clientNum = ent.s.clientNum

		if G.g_gametype.integer ~= C.GT_TOURNAMENT then
			G.trap_SendServerCommand(-1, QS.va("print \"%s^7 entered the game\n\"", client.pers.netname))
		end
	end

	G.motd(ent)

	G.G_LogPrintf("ClientBegin: %i\n", clientNum)

	--Send domination point names:
	if G.g_gametype.integer == C.GT_DOMINATION then
		G.DominationPointNamesMessage(ent)
		G.DominationPointStatusMessage(ent)
	end

	G.TeamCvarSet()

	-- count current clients and rank for scoreboard
	G.CalculateRanks()

	--Send the list of custom vote options:
	if #G.custom_vote_info ~= 0 then
		G.SendCustomVoteCommands(clientNum)
	end
end

--[[
===========
ClientSpawn

Called every time a client is placed fresh in the world:
after the first ClientBegin, and after each respawn
Initializes all non-persistant parts of playerState
============
]]
function G.ClientSpawn(ent)
	local index
	local spawn_origin = Q.vec3()
	local spawn_angles = Q.vec3()
	local client
	local saved = S.clientPersistant_t()
	local savedSess = S.clientSession_t()
	local persistant = {}
	local spawnPoint
	local flags
	local savedPing
	local accuracy_hits, accuracy_shots, vote
	local accuracy = {}
	local eventSequence
	local userinfo

	index = ent.index
	client = ent.client

	--In Elimination the player should not spawn if he have already spawned in the round (but not for spectators)
	if
		(
			(
				G.g_gametype.integer == C.GT_ELIMINATION
				or G.g_gametype.integer == C.GT_CTF_ELIMINATION
				or (G.g_gametype.integer == C.GT_LMS and client.isEliminated)
			)
			and (G.level.intermissiontime == 0 or G.level.warmupTime ~= 0)
		)
		and client.sess.sessionTeam ~= C.TEAM_SPECTATOR
	then
		-- Sago: I beleive the TeamCount is to make sure people can join even if the game can't start
		if
			G.level.roundNumber == G.level.roundNumberStarted
			or (
				(G.level.time < G.level.roundStartTime - G.g_elimination_activewarmup.integer * 1000)
				and G.TeamCount(-1, C.TEAM_BLUE) ~= 0
				and G.TeamCount(-1, C.TEAM_RED) ~= 0
			)
		then
			client.sess.spectatorState = C.SPECTATOR_FREE
			client.isEliminated = true
			if G.g_gametype.integer == C.GT_LMS then
				G.G_LogPrintf(
					"LMS: %i %i %i: Player \"%s^7\" eliminated!\n",
					G.level.roundNumber,
					index,
					1,
					client.pers.netname
				)
			end
			client.ps.pm_type = C.PM_SPECTATOR
			G.CalculateRanks()
			return
		else
			client.pers.roundReached = G.level.roundNumber + 1
			client.sess.spectatorState = C.SPECTATOR_NOT
			client.ps.pm_type = C.PM_NORMAL
			client.isEliminated = false
			G.CalculateRanks()
		end
	else
		--Force false.
		if client.isEliminated then
			client.isEliminated = false
			G.CalculateRanks()
		end
	end

	if
		G.g_gametype.integer == C.GT_LMS
		and client.sess.sessionTeam ~= C.TEAM_SPECTATOR
		and (G.level.intermissiontime == 0 or G.level.warmupTime ~= 0)
	then
		if G.level.roundNumber == G.level.roundNumberStarted and 1 > client.pers.livesLeft then
			client.sess.spectatorState = C.SPECTATOR_FREE
			if ent.client.isEliminated ~= true then
				client.isEliminated = true
				if
					(G.g_lms_mode.integer == 2 or G.g_lms_mode.integer == 3)
					and G.level.roundNumber == G.level.roundNumberStarted
				then
					G.LMSpoint()
				end
				G.G_LogPrintf(
					"LMS: %i %i %i: Player \"%s^7\" eliminated!\n",
					G.level.roundNumber,
					index,
					1,
					client.pers.netname
				)
			end
			client.ps.pm_type = C.PM_SPECTATOR
			return
		end

		client.sess.spectatorState = C.SPECTATOR_NOT
		client.ps.pm_type = C.PM_NORMAL
		client.isEliminated = false
		if client.pers.livesLeft > 0 then
			client.pers.livesLeft -= 1
		end
	end

	-- find a spawn point
	-- do it before setting health back up, so farthest
	-- ranging doesn't count this client
	if
		client.sess.sessionTeam == C.TEAM_SPECTATOR
		or (
			(client.ps.pm_type == C.PM_SPECTATOR or client.isEliminated)
			and (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION)
		)
	then
		spawnPoint = SF.SelectSpectatorSpawnPoint(spawn_origin, spawn_angles)
	elseif G.g_gametype.integer == C.GT_DOUBLE_D then
		--Double Domination uses special spawn points:
		spawnPoint = G.SelectDoubleDominationSpawnPoint(client.sess.sessionTeam, spawn_origin, spawn_angles)
	elseif G.g_gametype.integer == C.GT_DOMINATION then
		--Domination uses special spawn points:
		spawnPoint = G.SelectDominationSpawnPoint(client.sess.sessionTeam, spawn_origin, spawn_angles)
	elseif G.g_gametype.integer >= C.GT_CTF and G.g_ffa_gt == 0 then
		-- all base oriented team games use the CTF spawn points
		spawnPoint = G.SelectCTFSpawnPoint(
			client.sess.sessionTeam,
			client.pers.teamState.state,
			spawn_origin,
			spawn_angles
		)
	else
		local filters
		if bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 then
			filters = C.FL_NO_BOTS
		else
			filters = C.FL_NO_HUMANS
		end
		-- the first spawn should be at a good looking spot
		if not client.pers.initialSpawn and client.pers.localClient then
			client.pers.initialSpawn = true
			spawnPoint = SF.SelectInitialSpawnPoint(spawn_origin, spawn_angles, filters)
		else
			-- don't spawn near existing origin if possible
			spawnPoint = G.SelectSpawnPoint(client.ps.origin, spawn_origin, spawn_angles, filters)
		end
	end
	client.pers.teamState.state = C.TEAM_ACTIVE

	-- always clear the kamikaze flag
	ent.s.eFlags = bit32.band(ent.s.eFlags, bit32.bnot(C.EF_KAMIKAZE))

	-- toggle the teleport bit so the client knows to not lerp
	-- and never clear the voted flag
	flags = bit32.band(ent.client.ps.eFlags, bit32.bor(C.EF_TELEPORT_BIT, C.EF_VOTED, C.EF_TEAMVOTED))
	flags = bit32.bxor(flags, C.EF_TELEPORT_BIT)

	--unlagged - backward reconciliation #3
	-- we don't want players being backward-reconciled to the place they died
	G.G_ResetHistory(ent)
	-- and this is as good a time as any to clear the saved state
	ent.client.saved.leveltime = 0
	--unlagged - backward reconciliation #3

	-- clear everything but the persistant data

	S.copy_clientPersistant_t(saved, client.pers)
	S.copy_clientSession_t(savedSess, client.sess)
	savedPing = client.ps.ping
	vote = client.vote
	accuracy_hits = client.accuracy_hits
	accuracy_shots = client.accuracy_shots
	for w = 0, C.WP_NUM_WEAPONS - 1 do
		accuracy[w] = { [0] = client.accuracy[w][0], client.accuracy[w][1] }
	end

	for p = 0, C.MAX_PERSISTANT - 1 do
		persistant[p] = client.ps.persistant[p]
	end
	eventSequence = client.ps.eventSequence

	S.copy_gclient_t(client, S.gclient_t())

	S.copy_clientPersistant_t(client.pers, saved)
	S.copy_clientSession_t(client.sess, savedSess)
	client.ps.ping = savedPing
	client.vote = vote
	client.accuracy_hits = accuracy_hits
	client.accuracy_shots = accuracy_shots
	for w = 0, C.WP_NUM_WEAPONS - 1 do
		client.accuracy[w][0] = accuracy[w][0]
		client.accuracy[w][1] = accuracy[w][1]
	end

	client.lastkilled_client = -1

	for p = 0, C.MAX_PERSISTANT - 1 do
		client.ps.persistant[p] = persistant[p]
	end
	client.ps.eventSequence = eventSequence
	-- increment the spawncount so the client will detect the respawn
	client.ps.persistant[C.PERS_SPAWN_COUNT] += 1
	client.ps.persistant[C.PERS_TEAM] = client.sess.sessionTeam

	client.airOutTime = G.level.time + 12000

	userinfo = G.trap_GetUserinfo(index)
	-- set max health
	client.pers.maxHealth = QS.atoi(QS.Info_ValueForKey(userinfo, "handicap"))
	if client.pers.maxHealth < 1 or client.pers.maxHealth > 100 then
		client.pers.maxHealth = 100
	end
	-- clear entity values
	client.ps.stats[C.STAT_MAX_HEALTH] = client.pers.maxHealth
	client.ps.eFlags = flags

	ent.s.groundEntityNum = C.ENTITYNUM_NONE
	ent.client = G.level.clients[index]
	ent.takedamage = true
	ent.inuse = true
	ent.classname = "player"
	ent.r.contents = C.CONTENTS_BODY
	ent.clipmask = C.MASK_PLAYERSOLID
	ent.die = function(self, inflictor, attacker, damage, mod)
		G.player_die(self, inflictor, attacker, damage, mod)
	end
	ent.waterlevel = 0
	ent.watertype = 0
	ent.flags = 0

	--Sago: No one has hit the client yet!
	client.lastSentFlying = -1

	Q.VectorCopy(SF.playerMins, ent.r.mins)
	Q.VectorCopy(SF.playerMaxs, ent.r.maxs)

	client.ps.clientNum = index

	if
		G.g_gametype.integer ~= C.GT_ELIMINATION
		and G.g_gametype.integer ~= C.GT_CTF_ELIMINATION
		and G.g_gametype.integer ~= C.GT_LMS
		and G.g_elimination_allgametypes.integer == 0
	then
		client.ps.stats[C.STAT_WEAPONS] = bit32.lshift(1, C.WP_MACHINEGUN)
		if G.g_gametype.integer == C.GT_TEAM then
			client.ps.ammo[C.WP_MACHINEGUN] = 50
		else
			client.ps.ammo[C.WP_MACHINEGUN] = 100
		end

		client.ps.stats[C.STAT_WEAPONS] = bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_GAUNTLET))
		client.ps.ammo[C.WP_GAUNTLET] = -1
		client.ps.ammo[C.WP_GRAPPLING_HOOK] = -1

		-- health will count down towards max_health
		client.ps.stats[C.STAT_HEALTH] = client.ps.stats[C.STAT_MAX_HEALTH] + 25
		ent.health = client.ps.stats[C.STAT_HEALTH]
	else
		client.ps.stats[C.STAT_WEAPONS] = bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_GAUNTLET))
		client.ps.ammo[C.WP_GAUNTLET] = -1
		client.ps.ammo[C.WP_GRAPPLING_HOOK] = -1
		if G.g_elimination_machinegun.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] =
				bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_MACHINEGUN))
			client.ps.ammo[C.WP_MACHINEGUN] = G.g_elimination_machinegun.integer
		end
		if G.g_elimination_shotgun.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] = bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_SHOTGUN))
			client.ps.ammo[C.WP_SHOTGUN] = G.g_elimination_shotgun.integer
		end
		if G.g_elimination_grenade.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] =
				bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_GRENADE_LAUNCHER))
			client.ps.ammo[C.WP_GRENADE_LAUNCHER] = G.g_elimination_grenade.integer
		end
		if G.g_elimination_rocket.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] =
				bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_ROCKET_LAUNCHER))
			client.ps.ammo[C.WP_ROCKET_LAUNCHER] = G.g_elimination_rocket.integer
		end
		if G.g_elimination_lightning.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] =
				bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_LIGHTNING))
			client.ps.ammo[C.WP_LIGHTNING] = G.g_elimination_lightning.integer
		end
		if G.g_elimination_railgun.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] = bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_RAILGUN))
			client.ps.ammo[C.WP_RAILGUN] = G.g_elimination_railgun.integer
		end
		if G.g_elimination_plasmagun.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] =
				bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_PLASMAGUN))
			client.ps.ammo[C.WP_PLASMAGUN] = G.g_elimination_plasmagun.integer
		end
		if G.g_elimination_bfg.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] = bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_BFG))
			client.ps.ammo[C.WP_BFG] = G.g_elimination_bfg.integer
		end
		if G.g_elimination_nail.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] = bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_NAILGUN))
			client.ps.ammo[C.WP_NAILGUN] = G.g_elimination_nail.integer
		end
		if G.g_elimination_mine.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] =
				bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_PROX_LAUNCHER))
			client.ps.ammo[C.WP_PROX_LAUNCHER] = G.g_elimination_mine.integer
		end
		if G.g_elimination_chain.integer > 0 then
			client.ps.stats[C.STAT_WEAPONS] =
				bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_CHAINGUN))
			client.ps.ammo[C.WP_CHAINGUN] = G.g_elimination_chain.integer
		end

		client.ps.stats[C.STAT_ARMOR] = G.g_elimination_startArmor.integer
		ent.health = client.ps.stats[C.STAT_ARMOR]
		client.ps.stats[C.STAT_HEALTH] = G.g_elimination_startHealth.integer
		ent.health = client.ps.stats[C.STAT_HEALTH]
	end

	if G.g_instantgib.integer ~= 0 then
		client.ps.stats[C.STAT_WEAPONS] = bit32.lshift(1, C.WP_RAILGUN)
		client.ps.ammo[C.WP_RAILGUN] = 999 --Don't display any ammo
		if G.g_instantgib.integer > 1 then
			client.ps.stats[C.STAT_WEAPONS] = bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_GAUNTLET))
			client.ps.ammo[C.WP_GAUNTLET] = -1
		end
	end

	if G.g_rockets.integer ~= 0 then
		client.ps.stats[C.STAT_WEAPONS] = bit32.lshift(1, C.WP_ROCKET_LAUNCHER)
		client.ps.ammo[C.WP_ROCKET_LAUNCHER] = 999
	end

	if G.g_grapple.integer ~= 0 then
		client.ps.stats[C.STAT_WEAPONS] =
			bit32.bor(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, C.WP_GRAPPLING_HOOK))
	end

	G.G_SetOrigin(ent, spawn_origin)
	Q.VectorCopy(spawn_origin, client.ps.origin)

	-- the respawned flag will be cleared after the attack and jump keys come up
	client.ps.pm_flags = bit32.bor(client.ps.pm_flags, C.PMF_RESPAWNED)
	if
		G.g_gametype.integer == C.GT_ELIMINATION
		or G.g_gametype.integer == C.GT_CTF_ELIMINATION
		or G.g_gametype.integer == C.GT_LMS
	then
		client.ps.pm_flags = bit32.bor(client.ps.pm_flags, C.PMF_ELIMWARMUP)
	end

	G.trap_GetUsercmd(client.index, ent.client.pers.cmd)
	G.SetClientViewAngle(ent, spawn_angles)

	if
		ent.client.sess.sessionTeam == C.TEAM_SPECTATOR
		or (
			(client.ps.pm_type == C.PM_SPECTATOR or client.isEliminated)
			and (
				G.g_gametype.integer == C.GT_ELIMINATION
				or G.g_gametype.integer == C.GT_CTF_ELIMINATION
				or G.g_gametype.integer == C.GT_LMS
			)
		)
	then
		-- spectators and eliminated players are not placed in the world
	else
		G.G_KillBox(ent)
		G.trap_LinkEntity(ent)

		-- force the base weapon up
		client.ps.weapon = C.WP_MACHINEGUN
		client.ps.weaponstate = C.WEAPON_READY
	end

	-- don't allow full run speed for a bit
	client.ps.pm_flags = bit32.bor(client.ps.pm_flags, C.PMF_TIME_KNOCKBACK)
	client.ps.pm_time = 100

	client.respawnTime = G.level.time
	client.inactivityTime = G.level.time + G.g_inactivity.integer * 1000
	client.latched_buttons = 0

	-- set default animations
	client.ps.torsoAnim = C.TORSO_STAND
	client.ps.legsAnim = C.LEGS_IDLE

	if G.level.intermissiontime ~= 0 then
		G.MoveClientToIntermission(ent)
	else
		-- fire the targets of the spawn point
		G.G_UseTargets(spawnPoint, ent)

		-- select the highest weapon number available, after any
		-- spawn given items have fired
		client.ps.weapon = 1
		for i = C.WP_NUM_WEAPONS - 1, 1, -1 do
			if
				bit32.band(client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, i)) ~= 0
				and i ~= C.WP_GRAPPLING_HOOK
			then
				client.ps.weapon = i
				break
			end
		end
	end

	-- run a client frame to drop exactly to the floor,
	-- initialize animations and other things
	client.ps.commandTime = G.level.time - 100
	ent.client.pers.cmd.serverTime = G.level.time
	G.ClientThink(ent.index)

	-- positively link the client, even if the command times are weird
	if
		ent.client.sess.sessionTeam ~= C.TEAM_SPECTATOR
		or (
			(not client.isEliminated or client.ps.pm_type ~= C.PM_SPECTATOR)
			and (
				G.g_gametype.integer == C.GT_ELIMINATION
				or G.g_gametype.integer == C.GT_CTF_ELIMINATION
				or G.g_gametype.integer == C.GT_LMS
			)
		)
	then
		BG.BG_PlayerStateToEntityState(client.ps, ent.s, true)
		Q.VectorCopy(ent.client.ps.origin, ent.r.currentOrigin)
		G.trap_LinkEntity(ent)
	end

	-- run the presend to set anything else
	G.ClientEndFrame(ent)

	-- clear entity state values
	BG.BG_PlayerStateToEntityState(client.ps, ent.s, true)

	if G.g_spawnprotect.integer ~= 0 then
		client.spawnprotected = true
	end

	G.RespawnTimeMessage(ent, 0)
end

--[[
===========
ClientDisconnect

Called when a player drops from the server.
Will not be called between levels.

This should NOT be called directly by any game logic,
call trap_DropClient(), which will call this and do
server system housekeeping.
============
]]
function G.ClientDisconnect(clientNum)
	local ent
	local i
	local userinfo

	-- cleanup if we are kicking a bot that
	-- hasn't spawned yet
	G.G_RemoveQueuedBotBegin(clientNum)

	ent = G.g_entities[clientNum]
	if ent.client == nil then
		return
	end

	G.ClientLeaving(clientNum)
	--KK-OAX Admin
	G.G_admin_namelog_update(ent.client, true)

	userinfo = G.trap_GetUserinfo(clientNum)

	-- stop any following clients
	for k = 0, G.level.maxclients - 1 do
		if
			(G.level.clients[k].sess.sessionTeam == C.TEAM_SPECTATOR or G.level.clients[k].ps.pm_type == C.PM_SPECTATOR)
			and G.level.clients[k].sess.spectatorState == C.SPECTATOR_FOLLOW
			and G.level.clients[k].sess.spectatorClient == clientNum
		then
			G.StopFollowing(G.g_entities[k])
		end
	end

	--Is the player alive?
	i = if ent.client.ps.stats[C.STAT_HEALTH] > 0 then 1 else 0
	--Commit suicide!
	if
		ent.client.pers.connected == C.CON_CONNECTED
		and ent.client.sess.sessionTeam ~= C.TEAM_SPECTATOR
		and i ~= 0
	then
		--Prevent a team from loosing point because of player leaving
		local teamscore = 0
		if G.g_gametype.integer == C.GT_TEAM then
			teamscore = G.level.teamScores[ent.client.sess.sessionTeam]
		end
		-- Kill him (makes sure he loses flags, etc)
		ent.flags = bit32.band(ent.flags, bit32.bnot(C.FL_GODMODE))
		ent.health = 0
		ent.client.ps.stats[C.STAT_HEALTH] = 0
		G.player_die(ent, ent, G.g_entities[C.ENTITYNUM_WORLD], 100000, C.MOD_SUICIDE)
		if G.g_gametype.integer == C.GT_TEAM then
			G.level.teamScores[ent.client.sess.sessionTeam] = teamscore
		end
	end

	if ent.client.pers.connected == C.CON_CONNECTED and ent.client.sess.sessionTeam ~= C.TEAM_SPECTATOR then
		G.PlayerStore_store(QS.Info_ValueForKey(userinfo, "cl_guid"), ent.client.ps)
	end

	G.G_LogPrintf("ClientDisconnect: %i\n", clientNum)

	-- if we are playing in tourney mode and losing, give a win to the other player
	if
		G.g_gametype.integer == C.GT_TOURNAMENT
		and G.level.intermissiontime == 0
		and G.level.warmupTime == 0
		and G.level.sortedClients[1] == clientNum
	then
		G.level.clients[G.level.sortedClients[0]].sess.wins += 1
		G.ClientUserinfoChanged(G.level.sortedClients[0])
	end

	if
		G.g_gametype.integer == C.GT_TOURNAMENT
		and ent.client.sess.sessionTeam == C.TEAM_FREE
		and G.level.intermissiontime ~= 0
	then
		G.trap_SendConsoleCommand(C.EXEC_APPEND, "map_restart 0\n")
		G.level.restarted = true
		G.level.changemap = nil
		G.level.intermissiontime = 0
	end

	G.trap_UnlinkEntity(ent)
	ent.s.modelindex = 0
	ent.inuse = false
	ent.classname = "disconnected"
	ent.client.pers.connected = C.CON_DISCONNECTED
	ent.client.ps.persistant[C.PERS_TEAM] = C.TEAM_FREE
	ent.client.sess.sessionTeam = C.TEAM_FREE

	G.trap_SetConfigstring(C.CS_PLAYERS + clientNum, "")

	G.CalculateRanks()
	G.CountVotes()

	if bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 then
		G.BotAIShutdownClient(clientNum, false)
	end
end

return nil
