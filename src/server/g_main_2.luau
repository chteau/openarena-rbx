--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_main.c, part 2 of 3).

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
-- Luau port of g_main.c (part 2). Shutdown, player counting / ranking, intermission, logging.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_main")

-- challenges.h award ids (not exported by g_defs)
local GAMETYPES_FFA_WINS = 200
local GAMETYPES_TOURNEY_WINS = 201
local GAMETYPES_LMS_WINS = 202
local GAMETYPES_CTF_WINS = 203
local GAMETYPES_1FCTF_WINS = 204
local GAMETYPES_OVERLOAD_WINS = 205
local GAMETYPES_HARVESTER_WINS = 206
local GAMETYPES_ELIMINATION_WINS = 207
local GAMETYPES_CTF_ELIMINATION_WINS = 208
local GAMETYPES_DD_WINS = 209
local GAMETYPES_DOM_WINS = 210
local GAMETYPES_POS_WINS = 211

--[[
=================
G_ShutdownGame
=================
]]
function G.G_ShutdownGame(restart)
	G.G_Printf("==== ShutdownGame ====\n")

	if G.level.logFile ~= 0 then
		G.G_LogPrintf("ShutdownGame:\n")
		G.G_LogPrintf("------------------------------------------------------------\n")
		G.trap_FS_FCloseFile(G.level.logFile)
		G.level.logFile = 0
	end

	-- write all the client session data so we can get it back
	G.G_WriteSessionData()

	--KK-OAX Admin Cleanup
	G.G_admin_cleanup()
	G.G_admin_namelog_cleanup()

	if G.trap_Cvar_VariableIntegerValue("bot_enable") ~= 0 then
		G.BotAIShutdown(restart)
	end
end

--===================================================================

function G.Com_Error(level, error, ...)
	local text = QS.va(error, ...)
	G.G_Error("%s", text)
end

function G.Com_Printf(msg, ...)
	local text = QS.va(msg, ...)
	G.G_Printf("%s", text)
end

--[[
========================================================================

PLAYER COUNTING / SCORE SORTING

========================================================================
]]

--[[
=============
AddTournamentPlayer

If there are less than two tournament players, put a
spectator in the game and restart
=============
]]
function G.AddTournamentPlayer()
	local level = G.level

	if level.numPlayingClients >= 2 then
		return
	end

	-- never change during intermission
	if level.intermissiontime ~= 0 then
		return
	end

	local nextInLine = nil

	for i = 0, level.maxclients - 1 do
		local client = level.clients[i]
		if client.pers.connected ~= C.CON_CONNECTED then
			continue
		end
		if client.sess.sessionTeam ~= C.TEAM_SPECTATOR then
			continue
		end
		-- never select the dedicated follow or scoreboard clients
		if client.sess.spectatorState == C.SPECTATOR_SCOREBOARD
			or client.sess.spectatorClient < 0 then
			continue
		end

		if nextInLine == nil or client.sess.spectatorNum > nextInLine.sess.spectatorNum then
			nextInLine = client
		end
	end

	if nextInLine == nil then
		return
	end

	level.warmupTime = -1

	-- set them to free-for-all team
	G.SetTeam(G.g_entities[nextInLine.index], "f")
end

--[[
=======================
AddTournamentQueue

Add client to end of tournament queue
=======================
]]
function G.AddTournamentQueue(client)
	local level = G.level
	for index = 0, level.maxclients - 1 do
		local curclient = level.clients[index]
		if curclient.pers.connected ~= C.CON_DISCONNECTED then
			if curclient == client then
				curclient.sess.spectatorNum = 0
			elseif curclient.sess.sessionTeam == C.TEAM_SPECTATOR then
				curclient.sess.spectatorNum += 1
			end
		end
	end
end

--[[
=======================
RemoveTournamentLoser

Make the loser a spectator at the back of the line
=======================
]]
function G.RemoveTournamentLoser()
	local level = G.level

	if level.numPlayingClients ~= 2 then
		return
	end

	local clientNum = level.sortedClients[1]

	if level.clients[clientNum].pers.connected ~= C.CON_CONNECTED then
		return
	end

	-- make them a spectator
	G.SetTeam(G.g_entities[clientNum], "s")
end

--[[
=======================
RemoveTournamentWinner
=======================
]]
function G.RemoveTournamentWinner()
	local level = G.level

	if level.numPlayingClients ~= 2 then
		return
	end

	local clientNum = level.sortedClients[0]

	if level.clients[clientNum].pers.connected ~= C.CON_CONNECTED then
		return
	end

	-- make them a spectator
	G.SetTeam(G.g_entities[clientNum], "s")
end

--[[
=======================
AdjustTournamentScores
=======================
]]
function G.AdjustTournamentScores()
	local level = G.level

	local clientNum = level.sortedClients[0]
	if level.clients[clientNum].pers.connected == C.CON_CONNECTED then
		level.clients[clientNum].sess.wins += 1
		G.ClientUserinfoChanged(clientNum)
	end

	clientNum = level.sortedClients[1]
	if level.clients[clientNum].pers.connected == C.CON_CONNECTED then
		level.clients[clientNum].sess.losses += 1
		G.ClientUserinfoChanged(clientNum)
	end
end

--[[
=============
SortRanks

=============
]]
function G.SortRanks(a, b)
	local level = G.level
	local ca = level.clients[a]
	local cb = level.clients[b]

	-- sort special clients last
	if ca.sess.spectatorState == C.SPECTATOR_SCOREBOARD or ca.sess.spectatorClient < 0 then
		return 1
	end
	if cb.sess.spectatorState == C.SPECTATOR_SCOREBOARD or cb.sess.spectatorClient < 0 then
		return -1
	end

	-- then connecting clients
	if ca.pers.connected == C.CON_CONNECTING then
		return 1
	end
	if cb.pers.connected == C.CON_CONNECTING then
		return -1
	end

	-- then spectators
	if ca.sess.sessionTeam == C.TEAM_SPECTATOR and cb.sess.sessionTeam == C.TEAM_SPECTATOR then
		if ca.sess.spectatorNum > cb.sess.spectatorNum then
			return -1
		end
		if ca.sess.spectatorNum < cb.sess.spectatorNum then
			return 1
		end
		return 0
	end
	if ca.sess.sessionTeam == C.TEAM_SPECTATOR then
		return 1
	end
	if cb.sess.sessionTeam == C.TEAM_SPECTATOR then
		return -1
	end

	--In elimination and CTF elimination, sort dead players last
	if (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION)
		and level.roundNumber == level.roundNumberStarted and (ca.isEliminated ~= cb.isEliminated) then
		if ca.isEliminated then
			return 1
		end
		if cb.isEliminated then
			return -1
		end
	end

	-- then sort by score
	if ca.ps.persistant[C.PERS_SCORE] > cb.ps.persistant[C.PERS_SCORE] then
		return -1
	end
	if ca.ps.persistant[C.PERS_SCORE] < cb.ps.persistant[C.PERS_SCORE] then
		return 1
	end
	return 0
end

--[[
============
CalculateRanks

Recalculates the score ranks of all players
This will be called on every client connect, begin, disconnect, death,
and team change.
============
]]
function G.CalculateRanks()
	local level = G.level

	level.follow1 = -1
	level.follow2 = -1
	level.numConnectedClients = 0
	level.numNonSpectatorClients = 0
	level.numPlayingClients = 0
	local humanplayers = 0 -- don't count bots
	for i = 0, C.TEAM_NUM_TEAMS - 1 do
		level.numteamVotingClients[i] = 0
	end
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected ~= C.CON_DISCONNECTED then
			level.sortedClients[level.numConnectedClients] = i
			level.numConnectedClients += 1

			--We just set humanplayers to 0 during intermission
			if level.intermissiontime == 0 and level.clients[i].pers.connected == C.CON_CONNECTED
				and bit32.band(G.g_entities[i].r.svFlags, C.SVF_BOT) == 0 then
				humanplayers += 1
			end

			if level.clients[i].sess.sessionTeam ~= C.TEAM_SPECTATOR then
				level.numNonSpectatorClients += 1
				-- decide if this should be auto-followed
				if level.clients[i].pers.connected == C.CON_CONNECTED then
					level.numPlayingClients += 1
					if bit32.band(G.g_entities[i].r.svFlags, C.SVF_BOT) == 0 then
						if level.clients[i].sess.sessionTeam == C.TEAM_RED then
							level.numteamVotingClients[0] += 1
						elseif level.clients[i].sess.sessionTeam == C.TEAM_BLUE then
							level.numteamVotingClients[1] += 1
						end
					end
					if level.follow1 == -1 then
						level.follow1 = i
					elseif level.follow2 == -1 then
						level.follow2 = i
					end
				end
			end
		end
	end

	-- qsort( level.sortedClients, level.numConnectedClients, sizeof(int), SortRanks )
	local sorted = level.sortedClients
	for i = 1, level.numConnectedClients - 1 do
		local j = i
		while j > 0 and G.SortRanks(sorted[j - 1], sorted[j]) > 0 do
			sorted[j - 1], sorted[j] = sorted[j], sorted[j - 1]
			j -= 1
		end
	end

	-- set the rank value for all clients that are connected and not spectators
	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		-- in team games, rank is just the order of the teams, 0=red, 1=blue, 2=tied
		for i = 0, level.numConnectedClients - 1 do
			local cl = level.clients[level.sortedClients[i]]
			if level.teamScores[C.TEAM_RED] == level.teamScores[C.TEAM_BLUE] then
				cl.ps.persistant[C.PERS_RANK] = 2
			elseif level.teamScores[C.TEAM_RED] > level.teamScores[C.TEAM_BLUE] then
				cl.ps.persistant[C.PERS_RANK] = 0
			else
				cl.ps.persistant[C.PERS_RANK] = 1
			end
		end
	else
		local rank = -1
		local score = 0
		for i = 0, level.numPlayingClients - 1 do
			local cl = level.clients[level.sortedClients[i]]
			local newScore = cl.ps.persistant[C.PERS_SCORE]
			if i == 0 or newScore ~= score then
				rank = i
				-- assume we aren't tied until the next client is checked
				level.clients[level.sortedClients[i]].ps.persistant[C.PERS_RANK] = rank
			else
				-- we are tied with the previous client
				level.clients[level.sortedClients[i - 1]].ps.persistant[C.PERS_RANK] = bit32.bor(rank, C.RANK_TIED_FLAG)
				level.clients[level.sortedClients[i]].ps.persistant[C.PERS_RANK] = bit32.bor(rank, C.RANK_TIED_FLAG)
			end
			score = newScore
			if G.g_gametype.integer == C.GT_SINGLE_PLAYER and level.numPlayingClients == 1 then
				level.clients[level.sortedClients[i]].ps.persistant[C.PERS_RANK] = bit32.bor(rank, C.RANK_TIED_FLAG)
			end
		end
	end

	-- set the CS_SCORES1/2 configstrings, which will be visible to everyone
	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		G.trap_SetConfigstring(C.CS_SCORES1, QS.va("%i", level.teamScores[C.TEAM_RED]))
		G.trap_SetConfigstring(C.CS_SCORES2, QS.va("%i", level.teamScores[C.TEAM_BLUE]))
	else
		if level.numConnectedClients == 0 then
			G.trap_SetConfigstring(C.CS_SCORES1, QS.va("%i", C.SCORE_NOT_PRESENT))
			G.trap_SetConfigstring(C.CS_SCORES2, QS.va("%i", C.SCORE_NOT_PRESENT))
		elseif level.numConnectedClients == 1 then
			G.trap_SetConfigstring(C.CS_SCORES1, QS.va("%i", level.clients[level.sortedClients[0]].ps.persistant[C.PERS_SCORE]))
			G.trap_SetConfigstring(C.CS_SCORES2, QS.va("%i", C.SCORE_NOT_PRESENT))
		else
			G.trap_SetConfigstring(C.CS_SCORES1, QS.va("%i", level.clients[level.sortedClients[0]].ps.persistant[C.PERS_SCORE]))
			G.trap_SetConfigstring(C.CS_SCORES2, QS.va("%i", level.clients[level.sortedClients[1]].ps.persistant[C.PERS_SCORE]))
		end
	end

	-- see if it is time to end the level
	G.CheckExitRules()

	-- if we are at the intermission, send the new info to everyone
	if level.intermissiontime ~= 0 then
		G.SendScoreboardMessageToAllClients()
	end

	if G.g_humanplayers.integer ~= humanplayers then --Presume all spectators are humans!
		G.trap_Cvar_Set("g_humanplayers", QS.va("%i", humanplayers))
	end
	if humanplayers > level.max_humanplayers then
		G.G_LogPrintf("Info: There has been at least %i humans now\n", humanplayers)
		level.max_humanplayers = humanplayers
	end
end

--[[
========================================================================

MAP CHANGING

========================================================================
]]

--[[
========================
SendScoreboardMessageToAllClients

Do this at BeginIntermission time and whenever ranks are recalculated
due to enters/exits/forced team changes
========================
]]
function G.SendScoreboardMessageToAllClients()
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_CONNECTED then
			G.DeathmatchScoreboardMessage(G.g_entities[i])
			G.EliminationMessage(G.g_entities[i])
		end
	end
end

function SF.WriteAccForAllClients()
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_CONNECTED then
			G.LogAcc(i)
		end
	end
end

function SF.SendVictoryChallenge()
	local level = G.level
	local award = 0
	local gt = G.g_gametype.integer

	if level.max_humanplayers < 2 or level.hadBots then
		return
	end

	if gt == C.GT_FFA then
		award = GAMETYPES_FFA_WINS
	elseif gt == C.GT_TOURNAMENT then
		award = GAMETYPES_TOURNEY_WINS
	elseif gt == C.GT_LMS then
		award = GAMETYPES_LMS_WINS
	elseif gt == C.GT_CTF then
		award = GAMETYPES_CTF_WINS
	elseif gt == C.GT_1FCTF then
		award = GAMETYPES_1FCTF_WINS
	elseif gt == C.GT_OBELISK then
		award = GAMETYPES_OVERLOAD_WINS
	elseif gt == C.GT_HARVESTER then
		award = GAMETYPES_HARVESTER_WINS
	elseif gt == C.GT_ELIMINATION then
		award = GAMETYPES_ELIMINATION_WINS
	elseif gt == C.GT_CTF_ELIMINATION then
		award = GAMETYPES_CTF_ELIMINATION_WINS
	elseif gt == C.GT_DOUBLE_D then
		award = GAMETYPES_DD_WINS
	elseif gt == C.GT_DOMINATION then
		award = GAMETYPES_DOM_WINS
	elseif gt == C.GT_POSSESSION then
		award = GAMETYPES_POS_WINS
	else
		return
	end
	if gt ~= C.GT_FFA and gt ~= C.GT_TOURNAMENT and gt ~= C.GT_LMS and gt ~= C.GT_POSSESSION then
		--Team games
		for i = 0, level.maxclients - 1 do
			local cl = level.clients[i]

			if cl.sess.sessionTeam == C.TEAM_SPECTATOR then
				continue
			end
			if cl.pers.connected ~= C.CON_CONNECTED then
				continue
			end

			if cl.sess.sessionTeam == C.TEAM_RED and level.teamScores[C.TEAM_RED] > level.teamScores[C.TEAM_BLUE] then
				G.ChallengeMessage(G.g_entities[cl.ps.clientNum], award)
			end

			if cl.sess.sessionTeam == C.TEAM_BLUE and level.teamScores[C.TEAM_RED] < level.teamScores[C.TEAM_BLUE] then
				G.ChallengeMessage(G.g_entities[cl.ps.clientNum], award)
			end
		end
	else
		--FFA games
		G.ChallengeMessage(G.g_entities[level.sortedClients[0]], award)
	end
end

--[[
========================
SendElimiantionMessageToAllClients

Used to send information important to Elimination
========================
]]
function G.SendEliminationMessageToAllClients()
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_CONNECTED then
			G.EliminationMessage(G.g_entities[i])
		end
	end
end

--[[
========================
SendDDtimetakenMessageToAllClients

Do this if a team just started dominating.
========================
]]
function G.SendDDtimetakenMessageToAllClients()
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_CONNECTED then
			G.DoubleDominationScoreTimeMessage(G.g_entities[i])
		end
	end
end

--[[
========================
SendDominationPointsStatusMessageToAllClients

Used for Standard domination
========================
]]
function G.SendDominationPointsStatusMessageToAllClients()
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_CONNECTED then
			G.DominationPointStatusMessage(G.g_entities[i])
		end
	end
end

--[[
========================
SendYourTeamMessageToTeam

Tell all players on a given team who there allies are. Used for VoIP
========================
]]
function G.SendYourTeamMessageToTeam(team)
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_CONNECTED and level.clients[i].sess.sessionTeam == team then
			G.YourTeamMessage(G.g_entities[i])
		end
	end
end

--[[
========================
MoveClientToIntermission

When the intermission starts, this will be called for all players.
If a new client connects, this will be called after the spawn function.
========================
]]
function G.MoveClientToIntermission(ent)
	local level = G.level

	-- take out of follow mode if needed
	if ent.client.sess.spectatorState == C.SPECTATOR_FOLLOW then
		G.StopFollowing(ent)
	end

	G.FindIntermissionPoint()
	-- move to the spot
	Q.VectorCopy(level.intermission_origin, ent.s.origin)
	Q.VectorCopy(level.intermission_origin, ent.client.ps.origin)
	Q.VectorCopy(level.intermission_angle, ent.client.ps.viewangles)
	ent.client.ps.pm_type = C.PM_INTERMISSION

	-- clean up powerup info
	for i = 0, C.MAX_POWERUPS - 1 do
		ent.client.ps.powerups[i] = 0
	end

	ent.client.ps.eFlags = 0
	ent.s.eFlags = 0
	ent.s.eType = C.ET_GENERAL
	ent.s.modelindex = 0
	ent.s.loopSound = 0
	ent.s.event = 0
	ent.r.contents = 0
end

--[[
==================
FindIntermissionPoint

This is also used for spectator spawns
==================
]]
function G.FindIntermissionPoint()
	local level = G.level
	local dir = Q.vec3()

	-- find the intermission spot
	local ent = G.G_Find(nil, "classname", "info_player_intermission")
	if ent == nil then -- the map creator forgot to put in an intermission point...
		G.SelectSpawnPoint(Q.vec3_origin, level.intermission_origin, level.intermission_angle, 0)
	else
		Q.VectorCopy(ent.s.origin, level.intermission_origin)
		Q.VectorCopy(ent.s.angles, level.intermission_angle)
		-- if it has a target, look towards it
		if ent.target ~= nil then
			local target = G.G_PickTarget(ent.target)
			if target ~= nil then
				Q.VectorSubtract(target.s.origin, level.intermission_origin, dir)
				Q.vectoangles(dir, level.intermission_angle)
			end
		end
	end
end

--[[
==================
BeginIntermission
==================
]]
function G.BeginIntermission()
	local level = G.level

	if level.intermissiontime ~= 0 then
		return -- already active
	end

	-- if in tournement mode, change the wins / losses
	if G.g_gametype.integer == C.GT_TOURNAMENT then
		G.AdjustTournamentScores()
	end

	level.intermissiontime = level.time
	-- move all clients to the intermission point
	for i = 0, level.maxclients - 1 do
		local client = G.g_entities[i]
		if not client.inuse then
			continue
		end
		-- respawn if dead
		if client.health <= 0 then
			G.ClientRespawn(client)
		end
		G.MoveClientToIntermission(client)
	end
	-- if single player game
	if G.g_gametype.integer == C.GT_SINGLE_PLAYER then
		G.UpdateTournamentInfo()
		G.SpawnModelsOnVictoryPads()
	end
	-- send the current scoring to all clients
	G.SendScoreboardMessageToAllClients()
end

--[[
=============
ExitLevel

When the intermission has been exited, the server is either killed
or moved to a new level based on the "nextmap" cvar

=============
]]
function G.ExitLevel()
	local level = G.level

	--bot interbreeding
	G.BotInterbreedEndMatch()

	-- if we are running a tournement map, kick the loser to spectator status,
	-- which will automatically grab the next spectator and restart
	if G.g_gametype.integer == C.GT_TOURNAMENT then
		if not level.restarted then
			G.RemoveTournamentLoser()
			G.trap_SendConsoleCommand(C.EXEC_APPEND, "map_restart 0\n")
			level.restarted = true
			level.changemap = nil
			level.intermissiontime = 0
		end
		return
	end

	local nextmap = G.trap_Cvar_VariableStringBuffer("nextmap")
	local d1 = G.trap_Cvar_VariableStringBuffer("d1")

	local serverinfo = G.trap_GetServerinfo()

	--Here the game finds the nextmap if g_autonextmap is set
	if G.g_autonextmap.integer ~= 0 then
		--Look in g_mappools.string for the file to look for maps in
		local filename = QS.Q_strncpyz(QS.Info_ValueForKey(G.g_mappools.string, QS.va("%i", G.g_gametype.integer)), C.MAX_FILEPATH)
		--If we found a filename:
		if filename ~= "" then
			--Read the file:
			local _, file = G.trap_FS_FOpenFile(filename, C.FS_READ)
			if file == 0 then
				_, file = G.trap_FS_FOpenFile(QS.va("%s.org", filename), C.FS_READ)
			end
			if file ~= 0 then
				local mapnames = {} -- Array of mapnames in the map pool
				local count = 0 --The random choice from mapnames and count of mapnames
				local buffer = G.trap_FS_Read(4 * 1024, file)
				local pointer = QS.cursor(buffer)
				while true do
					mapnames[count] = QS.Q_strncpyz(QS.COM_Parse(pointer), 20)
					if mapnames[count] == "" then
						break
					end
					G.G_Printf("Mapname in mappool: %s\n", mapnames[count])
					count += 1
				end
				G.trap_FS_FCloseFile(file)
				--It is possible that the maps in the file read are flawed, so we try up to ten times:
				for _ = 0, 9 do
					local choice = if count > 0 then Q.imod(Q.rand(), count) else 0
					local name = mapnames[choice] or ""
					if QS.Q_strequal(name, QS.Info_ValueForKey(serverinfo, "mapname")) then
						continue
					end
					--Now check that the map exists:
					local _, mapfile = G.trap_FS_FOpenFile(QS.va("maps/%s.bsp", name), C.FS_READ)
					if mapfile ~= 0 then
						G.G_Printf("Picked map number %i - %s\n", choice, name)
						nextmap = QS.Q_strncpyz(QS.va("map %s", name), C.MAX_STRING_CHARS)
						G.trap_Cvar_Set("nextmap", nextmap)
						G.trap_FS_FCloseFile(mapfile)
						break
					end
				end
			end
		end
	end

	if QS.Q_strequal(nextmap, "map_restart 0") and not QS.Q_strequal(d1, "") then
		G.trap_Cvar_Set("nextmap", "vstr d2")
		G.trap_SendConsoleCommand(C.EXEC_APPEND, "vstr d1\n")
	else
		G.trap_SendConsoleCommand(C.EXEC_APPEND, "vstr nextmap\n")
	end

	level.changemap = nil
	level.intermissiontime = 0

	-- reset all the scores so we don't enter the intermission again
	level.teamScores[C.TEAM_RED] = 0
	level.teamScores[C.TEAM_BLUE] = 0
	for i = 0, G.g_maxclients.integer - 1 do
		local cl = level.clients[i]
		if cl.pers.connected ~= C.CON_CONNECTED then
			continue
		end
		cl.ps.persistant[C.PERS_SCORE] = 0
	end

	-- we need to do this here before chaning to CON_CONNECTING
	G.G_WriteSessionData()

	-- change all client states to connecting, so the early players into the
	-- next level will know the others aren't done reconnecting
	for i = 0, G.g_maxclients.integer - 1 do
		if level.clients[i].pers.connected == C.CON_CONNECTED then
			level.clients[i].pers.connected = C.CON_CONNECTING
		end
	end
end

--[[
=================
G_LogPrintf

Print to the logfile with a time stamp if it is open
=================
]]
function G.G_LogPrintf(fmt, ...)
	local level = G.level

	local sec = Q.idiv(level.time, 1000)

	local min = Q.idiv(sec, 60)
	sec -= min * 60
	local tens = Q.idiv(sec, 10)
	sec -= tens * 10

	local text = QS.Com_sprintf(1024, "%3i:%i%i ", min, tens, sec)

	local msg = string.sub(QS.va(fmt, ...), 1, 1024 - 7 - 1)
	text = text .. msg

	if G.g_dedicated.integer ~= 0 then
		G.G_Printf("%s", msg)
	end

	if level.logFile == 0 then
		return
	end

	G.trap_FS_Write(text, #text, level.logFile)
end

return nil
