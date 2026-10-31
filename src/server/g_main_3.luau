--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_main.c, part 3 of 3).

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
-- Luau port of OpenArena 0.8.8's g_main.c (gamecode 9e0f0c0) (part 3). Exit rules, per-frame checks, G_RunFrame.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_main")

-- static int lastMod in CheckCvars
local lastMod = -1

function G.LogExit(string_)
	local level = G.level
	local numSorted
	G.G_LogPrintf("Exit: %s\n", string_)

	level.intermissionQueued = level.time

	-- this will keep the clients from playing any voice sounds
	-- that will get cut off when the queued intermission starts
	G.trap_SetConfigstring(C.CS_INTERMISSION, "1")

	-- don't send more than 32 scores (FIXME?)
	numSorted = level.numConnectedClients
	if numSorted > 32 then
		numSorted = 32
	end

	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		G.G_LogPrintf("red:%i  blue:%i\n", level.teamScores[C.TEAM_RED], level.teamScores[C.TEAM_BLUE])
	end

	for i = 0, numSorted - 1 do
		local cl = level.clients[level.sortedClients[i]]

		if cl.sess.sessionTeam == C.TEAM_SPECTATOR then
			continue
		end
		if cl.pers.connected == C.CON_CONNECTING then
			continue
		end

		local ping = if cl.ps.ping < 999 then cl.ps.ping else 999

		G.G_LogPrintf("score: %i  ping: %i  client: %i %s\n", cl.ps.persistant[C.PERS_SCORE], ping, level.sortedClients[i], cl.pers.netname)
	end
end

local INTERMISSION_IDLE_EXIT = 30000

--[[
=================
CheckIntermissionExit

The level will stay at the intermission for a minimum of 5 seconds
If all players wish to continue, the level will then exit.
If one or more players have not acknowledged the continue, the game will
wait 10 seconds before going on.
=================
]]
function G.CheckIntermissionExit()
	local level = G.level
	local g_entities = G.g_entities

	if G.g_gametype.integer == C.GT_SINGLE_PLAYER then
		return
	end

	-- see which players are ready
	local ready = 0
	local notReady = 0
	local readyMask = 0
	local playerCount = 0
	for i = 0, G.g_maxclients.integer - 1 do
		local cl = level.clients[i]
		if cl.pers.connected ~= C.CON_CONNECTED then
			continue
		end
		if bit32.band(g_entities[cl.ps.clientNum].r.svFlags, C.SVF_BOT) ~= 0 then
			continue
		end

		playerCount += 1
		if cl.readyToExit then
			ready += 1
			if i < 16 then
				readyMask = bit32.bor(readyMask, bit32.lshift(1, i))
			end
		else
			notReady += 1
		end
	end

	-- copy the readyMask to each player's stats so
	-- it can be displayed on the scoreboard
	for i = 0, G.g_maxclients.integer - 1 do
		local cl = level.clients[i]
		if cl.pers.connected ~= C.CON_CONNECTED then
			continue
		end
		cl.ps.stats[C.STAT_CLIENTS_READY] = readyMask
	end

	-- never exit in less than five seconds
	if level.time < level.intermissiontime + 5000 then
		return
	end

	-- only test ready status when there are real players present
	if playerCount > 0 then
		-- if nobody wants to go, clear timer
		if ready == 0 then
			level.readyToExit = false
			-- port: a Roblox player idling or sitting in a menu never
			-- presses fire, and would hold the whole server at the
			-- scoreboard; nobody ready still moves on in the end
			if level.time >= level.intermissiontime + INTERMISSION_IDLE_EXIT then
				G.ExitLevel()
			end
			return
		end

		-- if everyone wants to go, go now
		if notReady == 0 then
			G.ExitLevel()
			return
		end
	end

	-- the first person to ready starts the ten second timeout
	if not level.readyToExit then
		level.readyToExit = true
		level.exitTime = level.time
	end

	-- if we have waited ten seconds since at least one player
	-- wanted to exit, go ahead
	if level.time < level.exitTime + 10000 then
		return
	end

	G.ExitLevel()
end

function G.ScoreIsTied(): boolean
	local level = G.level

	if level.numPlayingClients < 2 then
		return false
	end

	--Sago: In Elimination and Oneway Flag Capture teams must win by two points.
	if G.g_gametype.integer == C.GT_ELIMINATION or
		(G.g_gametype.integer == C.GT_CTF_ELIMINATION and G.g_elimination_ctf_oneway.integer ~= 0) then
		return level.teamScores[C.TEAM_RED] == level.teamScores[C.TEAM_BLUE] or
			level.teamScores[C.TEAM_RED] == level.teamScores[C.TEAM_BLUE] + 1 or
			level.teamScores[C.TEAM_RED] == level.teamScores[C.TEAM_BLUE] - 1
	end

	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		return level.teamScores[C.TEAM_RED] == level.teamScores[C.TEAM_BLUE]
	end

	local a = level.clients[level.sortedClients[0]].ps.persistant[C.PERS_SCORE]
	local b = level.clients[level.sortedClients[1]].ps.persistant[C.PERS_SCORE]

	return a == b
end

--[[
=================
CheckExitRules

There will be a delay between the time the exit is qualified for
and the time everyone is moved to the intermission spot, so you
can see the last frag.
=================
]]
function G.CheckExitRules()
	local level = G.level
	-- if at the intermission, wait for all non-bots to
	-- signal ready, then go to next level
	if level.intermissiontime ~= 0 then
		G.CheckIntermissionExit()
		return
	else
		--sago: Find the reason for this to be neccesary.
		for i = 0, G.g_maxclients.integer - 1 do
			local cl = level.clients[i]
			if cl.pers.connected ~= C.CON_CONNECTED then
				continue
			end
			cl.ps.stats[C.STAT_CLIENTS_READY] = 0
		end
	end

	if level.intermissionQueued ~= 0 then
		if level.time - level.intermissionQueued >= C.INTERMISSION_DELAY_TIME then
			level.intermissionQueued = 0
			G.BeginIntermission()
		end
		return
	end

	-- check for sudden death
	if G.ScoreIsTied() then
		-- always wait for sudden death
		return
	end

	if G.g_timelimit.integer > 0 and level.warmupTime == 0 then
		if Q.idiv(level.time - level.startTime, 60000) >= G.g_timelimit.integer then
			G.trap_SendServerCommand(-1, "print \"Timelimit hit.\n\"")
			G.LogExit("Timelimit hit.")
			return
		end
	end

	if level.numPlayingClients < 2 then
		return
	end

	if (G.g_gametype.integer < C.GT_CTF or G.g_ffa_gt > 0) and G.g_fraglimit.integer ~= 0 then
		if level.teamScores[C.TEAM_RED] >= G.g_fraglimit.integer then
			G.trap_SendServerCommand(-1, "print \"Red hit the fraglimit.\n\"")
			G.LogExit("Fraglimit hit.")
			return
		end

		if level.teamScores[C.TEAM_BLUE] >= G.g_fraglimit.integer then
			G.trap_SendServerCommand(-1, "print \"Blue hit the fraglimit.\n\"")
			G.LogExit("Fraglimit hit.")
			return
		end

		for i = 0, G.g_maxclients.integer - 1 do
			local cl = level.clients[i]
			if cl.pers.connected ~= C.CON_CONNECTED then
				continue
			end
			if cl.sess.sessionTeam ~= C.TEAM_FREE then
				continue
			end

			if cl.ps.persistant[C.PERS_SCORE] >= G.g_fraglimit.integer then
				G.LogExit("Fraglimit hit.")
				G.trap_SendServerCommand(-1, QS.va("print \"%s" .. "^7" .. " hit the fraglimit.\n\"", cl.pers.netname))
				return
			end
		end
	end

	if (G.g_gametype.integer >= C.GT_CTF and G.g_ffa_gt < 1) and G.g_capturelimit.integer ~= 0 then
		if level.teamScores[C.TEAM_RED] >= G.g_capturelimit.integer then
			G.trap_SendServerCommand(-1, "print \"Red hit the capturelimit.\n\"")
			G.LogExit("Capturelimit hit.")
			return
		end

		if level.teamScores[C.TEAM_BLUE] >= G.g_capturelimit.integer then
			G.trap_SendServerCommand(-1, "print \"Blue hit the capturelimit.\n\"")
			G.LogExit("Capturelimit hit.")
			return
		end
	end
end

--LMS - Last man Stading functions:
function G.StartLMSRound()
	local level = G.level
	local countsLiving = G.TeamLivingCount(-1, C.TEAM_FREE)
	if countsLiving < 2 then
		G.trap_SendServerCommand(-1, "print \"Not enough players to start the round\n\"")
		level.roundNumberStarted = level.roundNumber - 1
		level.roundStartTime = level.time + 1000 * G.g_elimination_warmup.integer
		return
	end

	--If we are enough to start a round:
	level.roundNumberStarted = level.roundNumber --Set numbers

	G.G_LogPrintf("LMS: %i %i %i: Round %i has started!\n", level.roundNumber, -1, 0, level.roundNumber)

	G.SendEliminationMessageToAllClients()
	G.EnableWeapons()
end

--the elimination start function
function G.StartEliminationRound()
	local level = G.level
	local countsLiving = {}
	countsLiving[C.TEAM_BLUE] = G.TeamLivingCount(-1, C.TEAM_BLUE)
	countsLiving[C.TEAM_RED] = G.TeamLivingCount(-1, C.TEAM_RED)
	if countsLiving[C.TEAM_BLUE] == 0 or countsLiving[C.TEAM_RED] == 0 then
		G.trap_SendServerCommand(-1, "print \"Not enough players to start the round\n\"")
		level.roundNumberStarted = level.roundNumber - 1
		level.roundRespawned = false
		--Remember that one of the teams is empty!
		level.roundRedPlayers = countsLiving[C.TEAM_RED]
		level.roundBluePlayers = countsLiving[C.TEAM_BLUE]
		level.roundStartTime = level.time + 1000 * G.g_elimination_warmup.integer
		return
	end

	--If we are enough to start a round:
	level.roundNumberStarted = level.roundNumber --Set numbers
	level.roundRedPlayers = countsLiving[C.TEAM_RED]
	level.roundBluePlayers = countsLiving[C.TEAM_BLUE]
	if G.g_gametype.integer == C.GT_CTF_ELIMINATION then
		G.Team_ReturnFlag(C.TEAM_RED)
		G.Team_ReturnFlag(C.TEAM_BLUE)
	end
	if G.g_gametype.integer == C.GT_ELIMINATION then
		G.G_LogPrintf("ELIMINATION: %i %i %i: Round %i has started!\n", level.roundNumber, -1, 0, level.roundNumber)
	elseif G.g_gametype.integer == C.GT_CTF_ELIMINATION then
		G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: Round %i has started!\n", level.roundNumber, -1, -1, 4, level.roundNumber)
	end
	G.SendEliminationMessageToAllClients()
	if G.g_elimination_ctf_oneway.integer ~= 0 then
		G.SendAttackingTeamMessageToAllClients() --Ensure that evaryone know who should attack.
	end
	G.EnableWeapons()
end

--things to do at end of round:
function G.EndEliminationRound()
	local level = G.level
	G.DisableWeapons()
	level.roundNumber += 1
	level.roundStartTime = level.time + 1000 * G.g_elimination_warmup.integer
	G.SendEliminationMessageToAllClients()
	G.CalculateRanks()
	level.roundRespawned = false
	if G.g_elimination_ctf_oneway.integer ~= 0 then
		G.SendAttackingTeamMessageToAllClients()
	end
end

--Things to do if we don't want to move the roundNumber
function G.RestartEliminationRound()
	local level = G.level
	G.DisableWeapons()
	level.roundNumberStarted = level.roundNumber - 1
	level.roundStartTime = level.time + 1000 * G.g_elimination_warmup.integer
	if level.intermissiontime == 0 then
		G.SendEliminationMessageToAllClients()
	end
	level.roundRespawned = false
	if G.g_elimination_ctf_oneway.integer ~= 0 then
		G.SendAttackingTeamMessageToAllClients()
	end
end

--Things to do during match warmup
function G.WarmupEliminationRound()
	local level = G.level
	G.EnableWeapons()
	level.roundNumberStarted = level.roundNumber - 1
	level.roundStartTime = level.time + 1000 * G.g_elimination_warmup.integer
	G.SendEliminationMessageToAllClients()
	level.roundRespawned = false
	if G.g_elimination_ctf_oneway.integer ~= 0 then
		G.SendAttackingTeamMessageToAllClients()
	end
end

--[[
========================================================================

FUNCTIONS CALLED EVERY FRAME

========================================================================
]]

function G.CheckDoubleDomination()
	local level = G.level
	if level.numPlayingClients < 1 then
		return
	end

	if level.warmupTime ~= 0 then
		if ((level.pointStatusA == C.TEAM_BLUE and level.pointStatusB == C.TEAM_BLUE) or
			(level.pointStatusA == C.TEAM_RED and level.pointStatusB == C.TEAM_RED)) and
			level.timeTaken + 10 * 1000 <= level.time then
			G.Team_RemoveDoubleDominationPoints()
			level.roundStartTime = level.time + 10 * 1000
			G.SendScoreboardMessageToAllClients()
		end
		return
	end

	if G.g_gametype.integer ~= C.GT_DOUBLE_D then
		return
	end

	--Don't score if we are in intermission. Both points might have been taken when we went into intermission
	if level.intermissiontime ~= 0 then
		return
	end

	if level.pointStatusA == C.TEAM_RED and level.pointStatusB == C.TEAM_RED and
		level.timeTaken + 10 * 1000 <= level.time then
		--Red scores
		G.trap_SendServerCommand(-1, "print \"Red team scores!\n\"")
		G.AddTeamScore(level.intermission_origin, C.TEAM_RED, 1)
		G.G_LogPrintf("DD: %i %i %i: %s scores!\n", -1, C.TEAM_RED, 2, G.TeamName(C.TEAM_RED))
		G.Team_ForceGesture(C.TEAM_RED)
		G.Team_DD_bonusAtPoints(C.TEAM_RED)
		G.Team_RemoveDoubleDominationPoints()
		--We start again in 10 seconds:
		level.roundStartTime = level.time + 10 * 1000
		G.SendScoreboardMessageToAllClients()
		G.CalculateRanks()
	end

	if level.pointStatusA == C.TEAM_BLUE and level.pointStatusB == C.TEAM_BLUE and
		level.timeTaken + 10 * 1000 <= level.time then
		--Blue scores
		G.trap_SendServerCommand(-1, "print \"Blue team scores!\n\"")
		G.AddTeamScore(level.intermission_origin, C.TEAM_BLUE, 1)
		G.G_LogPrintf("DD: %i %i %i: %s scores!\n", -1, C.TEAM_BLUE, 2, G.TeamName(C.TEAM_BLUE))
		G.Team_ForceGesture(C.TEAM_BLUE)
		G.Team_DD_bonusAtPoints(C.TEAM_BLUE)
		G.Team_RemoveDoubleDominationPoints()
		--We start again in 10 seconds:
		level.roundStartTime = level.time + 10 * 1000
		G.SendScoreboardMessageToAllClients()
		G.CalculateRanks()
	end

	if (level.pointStatusA == C.TEAM_NONE or level.pointStatusB == C.TEAM_NONE) and level.time > level.roundStartTime then
		G.trap_SendServerCommand(-1, "print \"A new round has started\n\"")
		G.Team_SpawnDoubleDominationPoints()
		G.SendScoreboardMessageToAllClients()
	end
end

function G.CheckLMS()
	local level = G.level
	local mode = G.g_lms_mode.integer
	if level.numPlayingClients < 1 then
		return
	end

	--We don't want to do anything in intermission
	if level.intermissiontime ~= 0 then
		if level.roundRespawned then
			G.RestartEliminationRound()
		end
		level.roundStartTime = level.time --so that a player might join at any time to fix the bots+no humans+autojoin bug
		return
	end

	if G.g_gametype.integer == C.GT_LMS then
		local countsLiving = {}
		countsLiving[C.TEAM_FREE] = G.TeamLivingCount(-1, C.TEAM_FREE)
		if countsLiving[C.TEAM_FREE] == 1 and level.roundNumber == level.roundNumberStarted then
			if mode <= 1 then
				G.LMSpoint()
			end
			G.trap_SendServerCommand(-1, "print \"We have a winner!\n\"")
			G.EndEliminationRound()
			G.Team_ForceGesture(C.TEAM_FREE)
		end

		if countsLiving[C.TEAM_FREE] == 0 and level.roundNumber == level.roundNumberStarted then
			G.trap_SendServerCommand(-1, "print \"All death... how sad\n\"")
			G.EndEliminationRound()
		end

		if G.g_elimination_roundtime.integer ~= 0 and level.roundNumber == level.roundNumberStarted and (G.g_lms_mode.integer == 1 or G.g_lms_mode.integer == 3) and level.time >= level.roundStartTime + 1000 * G.g_elimination_roundtime.integer then
			G.trap_SendServerCommand(-1, "print \"Time up - Overtime disabled\n\"")
			if mode <= 1 then
				G.LMSpoint()
			end
			G.EndEliminationRound()
		end

		--This might be better placed another place:
		if G.g_elimination_activewarmup.integer < 2 then
			G.g_elimination_activewarmup.integer = 2 --We need at least 2 seconds to spawn all players
		end
		if G.g_elimination_activewarmup.integer >= G.g_elimination_warmup.integer then --This must not be true
			G.g_elimination_warmup.integer = G.g_elimination_activewarmup.integer + 1 --Increase warmup
		end

		--Force respawn
		if level.roundNumber ~= level.roundNumberStarted and level.time > level.roundStartTime - 1000 * G.g_elimination_activewarmup.integer and not level.roundRespawned then
			level.roundRespawned = true
			G.RespawnAll()
			G.DisableWeapons()
			G.SendEliminationMessageToAllClients()
		end

		if level.time <= level.roundStartTime and level.time > level.roundStartTime - 1000 * G.g_elimination_activewarmup.integer then
			G.RespawnDead()
		end

		if level.roundNumber == level.roundNumberStarted then
			G.EnableWeapons()
		end

		if level.roundNumber > level.roundNumberStarted and level.time >= level.roundStartTime then
			G.StartLMSRound()
		end

		if level.time + 1000 * G.g_elimination_warmup.integer - 500 > level.roundStartTime and level.numPlayingClients < 2 then
			G.RespawnDead() --Allow player to run around anyway
			G.WarmupEliminationRound() --Start over
			return
		end

		if level.warmupTime ~= 0 then
			if level.time + 1000 * G.g_elimination_warmup.integer - 500 > level.roundStartTime then
				G.RespawnDead()
				G.WarmupEliminationRound()
			end
		end
	end
end

function G.CheckElimination()
	local level = G.level
	if level.numPlayingClients < 1 then
		if (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION) and
			(level.time + 1000 * G.g_elimination_warmup.integer - 500 > level.roundStartTime) then
			G.RestartEliminationRound() --For spectators
		end
		return
	end

	--We don't want to do anything in itnermission
	if level.intermissiontime ~= 0 then
		if level.roundRespawned then
			G.RestartEliminationRound()
		end
		level.roundStartTime = level.time + 1000 * G.g_elimination_warmup.integer
		return
	end

	if G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION then
		local counts = {}
		local countsLiving = {}
		local countsHealth = {}
		counts[C.TEAM_BLUE] = G.TeamCount(-1, C.TEAM_BLUE)
		counts[C.TEAM_RED] = G.TeamCount(-1, C.TEAM_RED)

		countsLiving[C.TEAM_BLUE] = G.TeamLivingCount(-1, C.TEAM_BLUE)
		countsLiving[C.TEAM_RED] = G.TeamLivingCount(-1, C.TEAM_RED)

		countsHealth[C.TEAM_BLUE] = G.TeamHealthCount(-1, C.TEAM_BLUE)
		countsHealth[C.TEAM_RED] = G.TeamHealthCount(-1, C.TEAM_RED)

		if level.roundBluePlayers ~= 0 and level.roundRedPlayers ~= 0 then --Cannot score if one of the team never got any living players
			if countsLiving[C.TEAM_BLUE] == 0 and level.roundNumber == level.roundNumberStarted then
				--Blue team has been eliminated!
				G.trap_SendServerCommand(-1, "print \"Blue Team eliminated!\n\"")
				G.AddTeamScore(level.intermission_origin, C.TEAM_RED, 1)
				if G.g_gametype.integer == C.GT_ELIMINATION then
					G.G_LogPrintf("ELIMINATION: %i %i %i: %s wins round %i by eleminating the enemy team!\n", level.roundNumber, C.TEAM_RED, 1, G.TeamName(C.TEAM_RED), level.roundNumber)
				else
					G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s wins round %i by eleminating the enemy team!\n", level.roundNumber, -1, C.TEAM_RED, 6, G.TeamName(C.TEAM_RED), level.roundNumber)
				end
				G.EndEliminationRound()
				G.Team_ForceGesture(C.TEAM_RED)
			elseif countsLiving[C.TEAM_RED] == 0 and level.roundNumber == level.roundNumberStarted then
				--Red team eliminated!
				G.trap_SendServerCommand(-1, "print \"Red Team eliminated!\n\"")
				G.AddTeamScore(level.intermission_origin, C.TEAM_BLUE, 1)
				if G.g_gametype.integer == C.GT_ELIMINATION then
					G.G_LogPrintf("ELIMINATION: %i %i %i: %s wins round %i by eleminating the enemy team!\n", level.roundNumber, C.TEAM_BLUE, 1, G.TeamName(C.TEAM_BLUE), level.roundNumber)
				else
					G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s wins round %i by eleminating the enemy team!\n", level.roundNumber, -1, C.TEAM_BLUE, 6, G.TeamName(C.TEAM_BLUE), level.roundNumber)
				end
				G.EndEliminationRound()
				G.Team_ForceGesture(C.TEAM_BLUE)
			end
		end

		--Time up
		if level.roundNumber == level.roundNumberStarted and G.g_elimination_roundtime.integer ~= 0 and level.time >= level.roundStartTime + 1000 * G.g_elimination_roundtime.integer then
			G.trap_SendServerCommand(-1, "print \"No teams eliminated.\n\"")

			if level.roundBluePlayers ~= 0 and level.roundRedPlayers ~= 0 then --We don't want to divide by zero. (should not be possible)
				if G.g_gametype.integer == C.GT_CTF_ELIMINATION and G.g_elimination_ctf_oneway.integer ~= 0 then
					--One way CTF, make defensice team the winner.
					if Q.imod(level.eliminationSides + level.roundNumber, 2) == 0 then --Red was attacking
						G.trap_SendServerCommand(-1, "print \"Blue team defended the base\n\"")
						G.AddTeamScore(level.intermission_origin, C.TEAM_BLUE, 1)
						G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s wins round %i by defending the flag!\n", level.roundNumber, -1, C.TEAM_BLUE, 5, G.TeamName(C.TEAM_BLUE), level.roundNumber)
					else
						G.trap_SendServerCommand(-1, "print \"Red team defended the base\n\"")
						G.AddTeamScore(level.intermission_origin, C.TEAM_RED, 1)
						G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s wins round %i by defending the flag!\n", level.roundNumber, -1, C.TEAM_RED, 5, G.TeamName(C.TEAM_RED), level.roundNumber)
					end
				elseif countsLiving[C.TEAM_RED] / level.roundRedPlayers > countsLiving[C.TEAM_BLUE] / level.roundBluePlayers then
					--Red team has higher procentage survivors
					G.trap_SendServerCommand(-1, "print \"Red team has most survivers!\n\"")
					G.AddTeamScore(level.intermission_origin, C.TEAM_RED, 1)
					if G.g_gametype.integer == C.GT_ELIMINATION then
						G.G_LogPrintf("ELIMINATION: %i %i %i: %s wins round %i due to more survivors!\n", level.roundNumber, C.TEAM_RED, 2, G.TeamName(C.TEAM_RED), level.roundNumber)
					else
						G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s wins round %i due to more survivors!\n", level.roundNumber, -1, C.TEAM_RED, 7, G.TeamName(C.TEAM_RED), level.roundNumber)
					end
				elseif countsLiving[C.TEAM_RED] / level.roundRedPlayers < countsLiving[C.TEAM_BLUE] / level.roundBluePlayers then
					--Blue team has higher procentage survivors
					G.trap_SendServerCommand(-1, "print \"Blue team has most survivers!\n\"")
					G.AddTeamScore(level.intermission_origin, C.TEAM_BLUE, 1)
					if G.g_gametype.integer == C.GT_ELIMINATION then
						G.G_LogPrintf("ELIMINATION: %i %i %i: %s wins round %i due to more survivors!\n", level.roundNumber, C.TEAM_BLUE, 2, G.TeamName(C.TEAM_BLUE), level.roundNumber)
					else
						G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s wins round %i due to more survivors!\n", level.roundNumber, -1, C.TEAM_BLUE, 7, G.TeamName(C.TEAM_BLUE), level.roundNumber)
					end
				elseif countsHealth[C.TEAM_RED] > countsHealth[C.TEAM_BLUE] then
					--Red team has more health
					G.trap_SendServerCommand(-1, "print \"Red team has more health left!\n\"")
					G.AddTeamScore(level.intermission_origin, C.TEAM_RED, 1)
					if G.g_gametype.integer == C.GT_ELIMINATION then
						G.G_LogPrintf("ELIMINATION: %i %i %i: %s wins round %i due to more health left!\n", level.roundNumber, C.TEAM_RED, 3, G.TeamName(C.TEAM_RED), level.roundNumber)
					else
						G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s wins round %i due to more health left!\n", level.roundNumber, -1, C.TEAM_RED, 8, G.TeamName(C.TEAM_RED), level.roundNumber)
					end
				elseif countsHealth[C.TEAM_RED] < countsHealth[C.TEAM_BLUE] then
					--Blue team has more health
					G.trap_SendServerCommand(-1, "print \"Blue team has more health left!\n\"")
					G.AddTeamScore(level.intermission_origin, C.TEAM_BLUE, 1)
					if G.g_gametype.integer == C.GT_ELIMINATION then
						G.G_LogPrintf("ELIMINATION: %i %i %i: %s wins round %i due to more health left!\n", level.roundNumber, C.TEAM_BLUE, 3, G.TeamName(C.TEAM_BLUE), level.roundNumber)
					else
						G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s wins round %i due to more health left!\n", level.roundNumber, -1, C.TEAM_BLUE, 8, G.TeamName(C.TEAM_BLUE), level.roundNumber)
					end
				end
			end
			--Draw
			if G.g_gametype.integer == C.GT_ELIMINATION then
				G.G_LogPrintf("ELIMINATION: %i %i %i: Round %i ended in a draw!\n", level.roundNumber, -1, 4, level.roundNumber)
			else
				G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: Round %i ended in a draw!\n", level.roundNumber, -1, -1, 9, level.roundNumber)
			end
			G.EndEliminationRound()
		end

		--This might be better placed another place:
		if G.g_elimination_activewarmup.integer < 1 then
			G.g_elimination_activewarmup.integer = 1 --We need at least 1 second to spawn all players
		end
		if G.g_elimination_activewarmup.integer >= G.g_elimination_warmup.integer then --This must not be true
			G.g_elimination_warmup.integer = G.g_elimination_activewarmup.integer + 1 --Increase warmup
		end

		--Force respawn
		if level.roundNumber ~= level.roundNumberStarted and level.time > level.roundStartTime - 1000 * G.g_elimination_activewarmup.integer and not level.roundRespawned then
			level.roundRespawned = true
			G.RespawnAll()
			G.SendEliminationMessageToAllClients()
		end

		if level.time <= level.roundStartTime and level.time > level.roundStartTime - 1000 * G.g_elimination_activewarmup.integer then
			G.RespawnDead()
		end

		if level.roundNumber > level.roundNumberStarted and level.time >= level.roundStartTime then
			G.StartEliminationRound()
		end

		if level.time + 1000 * G.g_elimination_warmup.integer - 500 > level.roundStartTime then
			if counts[C.TEAM_BLUE] < 1 or counts[C.TEAM_RED] < 1 then
				G.RespawnDead() --Allow players to run around anyway
				G.WarmupEliminationRound() --Start over
				return
			end
		end

		if level.warmupTime ~= 0 then
			if level.time + 1000 * G.g_elimination_warmup.integer - 500 > level.roundStartTime then
				G.RespawnDead()
				G.WarmupEliminationRound()
			end
		end
	end
end

function G.CheckDomination()
	local level = G.level
	local scoreFactor = 1

	if level.numPlayingClients < 1 or G.g_gametype.integer ~= C.GT_DOMINATION then
		return
	end

	--Do nothing if warmup
	if level.warmupTime ~= 0 then
		return
	end

	--Don't score if we are in intermission. Just plain stupid
	if level.intermissiontime ~= 0 then
		return
	end

	--Sago: I use if instead of while, since if the server stops for more than 2 seconds people should not be allowed to score anyway
	if level.domination_points_count > 3 then
		scoreFactor = 2 --score more slowly if there are many points
	end
	if level.time >= level.dom_scoreGiven * C.DOM_SECSPERPOINT * scoreFactor then
		for i = 0, level.domination_points_count - 1 do
			if level.pointStatusDom[i] == C.TEAM_RED then
				G.AddTeamScore(level.intermission_origin, C.TEAM_RED, 1)
			end
			if level.pointStatusDom[i] == C.TEAM_BLUE then
				G.AddTeamScore(level.intermission_origin, C.TEAM_BLUE, 1)
			end
			G.G_LogPrintf("DOM: %i %i %i %i: %s holds point %s for 1 point!\n",
				-1, i, 1, level.pointStatusDom[i],
				G.TeamName(level.pointStatusDom[i]), level.domination_points_names[i])
		end
		level.dom_scoreGiven += 1
		while level.time > level.dom_scoreGiven * C.DOM_SECSPERPOINT * scoreFactor do
			level.dom_scoreGiven += 1
		end
		G.CalculateRanks()
	end
end

--[[
=============
CheckTournament

Once a frame, check for changes in tournement player state
=============
]]
function G.CheckTournament()
	local level = G.level
	-- check because we run 3 game frames before calling Connect and/or ClientBegin
	-- for clients on a map_restart
	if level.numPlayingClients == 0 then
		return
	end

	if G.g_gametype.integer == C.GT_TOURNAMENT then
		-- pull in a spectator if needed
		if level.numPlayingClients < 2 then
			G.AddTournamentPlayer()
		end

		-- if we don't have two players, go back to "waiting for players"
		if level.numPlayingClients ~= 2 then
			if level.warmupTime ~= -1 then
				level.warmupTime = -1
				G.trap_SetConfigstring(C.CS_WARMUP, QS.va("%i", level.warmupTime))
				G.G_LogPrintf("Warmup:\n")
			end
			return
		end

		if level.warmupTime == 0 then
			return
		end

		-- if the warmup is changed at the console, restart it
		if G.g_warmup.modificationCount ~= level.warmupModificationCount then
			level.warmupModificationCount = G.g_warmup.modificationCount
			level.warmupTime = -1
		end

		-- if all players have arrived, start the countdown
		if level.warmupTime < 0 then
			if level.numPlayingClients == 2 then
				-- fudge by -1 to account for extra delays
				if G.g_warmup.integer > 1 then
					level.warmupTime = level.time + (G.g_warmup.integer - 1) * 1000
				else
					level.warmupTime = 0
				end

				G.trap_SetConfigstring(C.CS_WARMUP, QS.va("%i", level.warmupTime))
			end
			return
		end

		-- if the warmup time has counted down, restart
		if level.time > level.warmupTime then
			level.warmupTime += 10000
			G.trap_Cvar_Set("g_restarted", "1")
			G.trap_SendConsoleCommand(C.EXEC_APPEND, "map_restart 0\n")
			level.restarted = true
			return
		end
	elseif G.g_gametype.integer ~= C.GT_SINGLE_PLAYER and level.warmupTime ~= 0 then
		local counts = {}
		local notEnough = false

		if G.g_gametype.integer > C.GT_TEAM and G.g_ffa_gt == 0 then
			counts[C.TEAM_BLUE] = G.TeamCount(-1, C.TEAM_BLUE)
			counts[C.TEAM_RED] = G.TeamCount(-1, C.TEAM_RED)

			if counts[C.TEAM_RED] < 1 or counts[C.TEAM_BLUE] < 1 then
				notEnough = true
			end
		elseif level.numPlayingClients < 2 then
			notEnough = true
		end

		if notEnough then
			if level.warmupTime ~= -1 then
				level.warmupTime = -1
				G.trap_SetConfigstring(C.CS_WARMUP, QS.va("%i", level.warmupTime))
				G.G_LogPrintf("Warmup:\n")
			end
			return -- still waiting for team members
		end

		if level.warmupTime == 0 then
			return
		end

		-- if the warmup is changed at the console, restart it
		if G.g_warmup.modificationCount ~= level.warmupModificationCount then
			level.warmupModificationCount = G.g_warmup.modificationCount
			level.warmupTime = -1
		end

		-- if all players have arrived, start the countdown
		if level.warmupTime < 0 then
			-- fudge by -1 to account for extra delays
			level.warmupTime = level.time + (G.g_warmup.integer - 1) * 1000
			G.trap_SetConfigstring(C.CS_WARMUP, QS.va("%i", level.warmupTime))
			return
		end

		-- if the warmup time has counted down, restart
		if level.time > level.warmupTime then
			level.warmupTime += 10000
			G.trap_Cvar_Set("g_restarted", "1")
			G.trap_SendConsoleCommand(C.EXEC_APPEND, "map_restart 0\n")
			level.restarted = true
			return
		end
	end
end

function G.PrintTeam(team, message)
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].sess.sessionTeam ~= team then
			continue
		end
		G.trap_SendServerCommand(i, message)
	end
end

function G.SetLeader(team, client)
	local level = G.level

	if level.clients[client].pers.connected == C.CON_DISCONNECTED then
		G.PrintTeam(team, QS.va("print \"%s is not connected\n\"", level.clients[client].pers.netname))
		return
	end
	if level.clients[client].sess.sessionTeam ~= team then
		G.PrintTeam(team, QS.va("print \"%s is not on the team anymore\n\"", level.clients[client].pers.netname))
		return
	end
	for i = 0, level.maxclients - 1 do
		if level.clients[i].sess.sessionTeam ~= team then
			continue
		end
		if level.clients[i].sess.teamLeader then
			level.clients[i].sess.teamLeader = false
			G.ClientUserinfoChanged(i)
		end
	end
	level.clients[client].sess.teamLeader = true
	G.ClientUserinfoChanged(client)
	G.PrintTeam(team, QS.va("print \"%s is the new team leader\n\"", level.clients[client].pers.netname))
end

function G.CheckTeamLeader(team)
	local level = G.level
	local g_entities = G.g_entities

	local i = 0
	while i < level.maxclients do
		if level.clients[i].sess.sessionTeam ~= team then
			i += 1
			continue
		end
		if level.clients[i].sess.teamLeader then
			break
		end
		i += 1
	end
	if i >= level.maxclients then
		i = 0
		while i < level.maxclients do
			if level.clients[i].sess.sessionTeam ~= team then
				i += 1
				continue
			end
			if bit32.band(g_entities[i].r.svFlags, C.SVF_BOT) == 0 then
				level.clients[i].sess.teamLeader = true
				break
			end
			i += 1
		end
		i = 0
		while i < level.maxclients do
			if level.clients[i].sess.sessionTeam ~= team then
				i += 1
				continue
			end
			level.clients[i].sess.teamLeader = true
			break
		end
	end
end

function G.CheckTeamVote(team)
	local level = G.level
	local cs_offset

	if team == C.TEAM_RED then
		cs_offset = 0
	elseif team == C.TEAM_BLUE then
		cs_offset = 1
	else
		return
	end

	if level.teamVoteTime[cs_offset] == 0 then
		return
	end
	if level.time - level.teamVoteTime[cs_offset] >= C.VOTE_TIME then
		G.trap_SendServerCommand(-1, "print \"Team vote failed.\n\"")
	else
		if level.teamVoteYes[cs_offset] > Q.idiv(level.numteamVotingClients[cs_offset], 2) then
			-- execute the command, then remove the vote
			G.trap_SendServerCommand(-1, "print \"Team vote passed.\n\"")
			--
			if QS.Q_strncmp("leader", level.teamVoteString[cs_offset], 6) == 0 then
				--set the team leader
				G.SetLeader(team, QS.atoi(string.sub(level.teamVoteString[cs_offset], 8)))
			else
				G.trap_SendConsoleCommand(C.EXEC_APPEND, QS.va("%s\n", level.teamVoteString[cs_offset]))
			end
		elseif level.teamVoteNo[cs_offset] >= Q.idiv(level.numteamVotingClients[cs_offset], 2) then
			-- same behavior as a timeout
			G.trap_SendServerCommand(-1, "print \"Team vote failed.\n\"")
		else
			-- still waiting for a majority
			return
		end
	end
	level.teamVoteTime[cs_offset] = 0
	G.trap_SetConfigstring(C.CS_TEAMVOTE_TIME + cs_offset, "")
end

function G.CheckCvars()
	if G.g_password.modificationCount ~= lastMod then
		lastMod = G.g_password.modificationCount
		if G.g_password.string ~= "" and QS.Q_stricmp(G.g_password.string, "none") ~= 0 then
			G.trap_Cvar_Set("g_needpass", "1")
		else
			G.trap_Cvar_Set("g_needpass", "0")
		end
	end
end

--[[
=============
G_RunThink

Runs thinking code for this frame if necessary
=============
]]
function G.G_RunThink(ent)
	local thinktime = ent.nextthink
	if thinktime <= 0 then
		return
	end
	if thinktime > G.level.time then
		return
	end

	ent.nextthink = 0
	if ent.think == nil then
		G.G_Error("NULL ent->think")
	end
	ent.think(ent)
end

--[[
================
G_RunFrame

Advances the non-player objects in the world
================
]]
function G.G_RunFrame(levelTime)
	local level = G.level
	local g_entities = G.g_entities

	-- if we are waiting for the level to restart, do nothing
	if level.restarted then
		return
	end

	level.framenum += 1
	level.previousTime = level.time
	level.time = levelTime

	-- get any cvar changes
	G.G_UpdateCvars()

	if (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION) and bit32.band(G.g_elimflags.integer, C.EF_NO_FREESPEC) == 0 and G.g_elimination_lockspectator.integer > 1 then
		G.trap_Cvar_Set("elimflags", QS.va("%i", bit32.bor(G.g_elimflags.integer, C.EF_NO_FREESPEC)))
	elseif bit32.band(G.g_elimflags.integer, C.EF_NO_FREESPEC) ~= 0 and G.g_elimination_lockspectator.integer < 2 then
		G.trap_Cvar_Set("elimflags", QS.va("%i", bit32.band(G.g_elimflags.integer, bit32.bnot(C.EF_NO_FREESPEC))))
	end

	if G.g_elimination_ctf_oneway.integer ~= 0 and bit32.band(G.g_elimflags.integer, C.EF_ONEWAY) == 0 then
		G.trap_Cvar_Set("elimflags", QS.va("%i", bit32.bor(G.g_elimflags.integer, C.EF_ONEWAY)))
		--If the server admin has enabled it midgame imidiantly braodcast attacking team
		G.SendAttackingTeamMessageToAllClients()
	elseif G.g_elimination_ctf_oneway.integer == 0 and bit32.band(G.g_elimflags.integer, C.EF_ONEWAY) ~= 0 then
		G.trap_Cvar_Set("elimflags", QS.va("%i", bit32.band(G.g_elimflags.integer, bit32.bnot(C.EF_ONEWAY))))
	end

	--
	-- go through all allocated objects
	--
	for i = 0, level.num_entities - 1 do
		local ent = g_entities[i]
		if not ent.inuse then
			continue
		end

		-- clear events that are too old
		if level.time - ent.eventTime > C.EVENT_VALID_MSEC then
			if ent.s.event ~= 0 then
				ent.s.event = 0 -- &= EV_EVENT_BITS;
				if ent.client ~= nil then
					ent.client.ps.externalEvent = 0
				end
			end
			if ent.freeAfterEvent then
				-- tempEntities or dropped items completely go away after their event
				G.G_FreeEntity(ent)
				continue
			elseif ent.unlinkAfterEvent then
				-- items that will respawn will hide themselves after their pickup event
				ent.unlinkAfterEvent = false
				G.trap_UnlinkEntity(ent)
			end
		end

		-- temporary entities don't think
		if ent.freeAfterEvent then
			continue
		end

		if not ent.r.linked and ent.neverFree then
			continue
		end

		if ent.s.eType == C.ET_ITEM or ent.physicsObject then
			G.G_RunItem(ent)
			continue
		end

		if ent.s.eType == C.ET_MOVER then
			G.G_RunMover(ent)
			continue
		end

		if i < C.MAX_CLIENTS then
			G.G_RunClient(ent)
			continue
		end

		G.G_RunThink(ent)
	end

--unlagged - backward reconciliation #2
	-- NOW run the missiles, with all players backward-reconciled
	-- to the positions they were in exactly 50ms ago, at the end
	-- of the last server frame
	G.G_TimeShiftAllClients(level.previousTime, nil)

	for i = 0, level.num_entities - 1 do
		local ent = g_entities[i]
		if not ent.inuse then
			continue
		end

		-- temporary entities don't think
		if ent.freeAfterEvent then
			continue
		end

		if ent.s.eType == C.ET_MISSILE then
			G.G_RunMissile(ent)
		end
	end

	G.G_UnTimeShiftAllClients(nil)
--unlagged - backward reconciliation #2

	-- perform final fixups on the players
	for i = 0, level.maxclients - 1 do
		local ent = g_entities[i]
		if ent.inuse then
			G.ClientEndFrame(ent)
		end
	end

	-- see if it is time to do a tournement restart
	G.CheckTournament()

	--Check Elimination state
	G.CheckElimination()
	G.CheckLMS()

	--Check Double Domination
	G.CheckDoubleDomination()

	G.CheckDomination()

	--Sago: I just need to think why I placed this here... they should only spawn once
	if G.g_gametype.integer == C.GT_DOMINATION then
		G.Team_Dom_SpawnPoints()
	end

	-- see if it is time to end the level
	G.CheckExitRules()

	-- update to team status?
	G.CheckTeamStatus()

	-- cancel vote if timed out
	G.CheckVote()

	-- check team votes
	G.CheckTeamVote(C.TEAM_RED)
	G.CheckTeamVote(C.TEAM_BLUE)

	-- for tracking changes
	G.CheckCvars()

	if G.g_listEntity.integer ~= 0 then
		for i = 0, C.MAX_GENTITIES - 1 do
			G.G_Printf("%4i: %s\n", i, g_entities[i].classname)
		end
		G.trap_Cvar_Set("g_listEntity", "0")
	end

--unlagged - backward reconciliation #4
	-- record the time at the end of this frame - it should be about
	-- the time the next frame begins - when the server starts
	-- accepting commands from connected clients
	level.frameStartTime = G.trap_Milliseconds()
--unlagged - backward reconciliation #4
end

return nil
