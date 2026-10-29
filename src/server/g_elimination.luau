--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_elimination.c).

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
-- Luau port of g_elimination.c. Elimination, CTF Elimination and LMS round logic.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local ELIMINATION_ACTIVE_TARGETNAME = "elimination_active"

local function CloseEliminationDoors()
	local next = nil
	next = G.G_Find(next, "classname", "func_door")
	while next ~= nil do
		if next.targetname == ELIMINATION_ACTIVE_TARGETNAME then
			if next.moverState ~= C.MOVER_2TO1 and next.moverState ~= C.MOVER_POS1 then
				G.MatchTeam(next, C.MOVER_2TO1, G.level.time)
			end
		end
		next = G.G_Find(next, "classname", "func_door")
	end
end

local function CloseEliminationDoorsInstantly()
	local next = nil
	next = G.G_Find(next, "classname", "func_door")
	while next ~= nil do
		if next.targetname == ELIMINATION_ACTIVE_TARGETNAME then
			if next.moverState ~= C.MOVER_POS1 then
				G.MatchTeam(next, C.MOVER_POS1, G.level.time)
			end
		end
		next = G.G_Find(next, "classname", "func_door")
	end
end

local function OpenEliminationDoors()
	local next = nil
	next = G.G_Find(next, "classname", "func_door")
	while next ~= nil do
		if next.targetname == ELIMINATION_ACTIVE_TARGETNAME then
			if next.moverState ~= C.MOVER_1TO2 and next.moverState ~= C.MOVER_POS2 then
				G.MatchTeam(next, C.MOVER_1TO2, G.level.time)
			end
		end
		next = G.G_Find(next, "classname", "func_door")
	end
end

--[[
========================
SendAttackingTeamMessageToAllClients

Used for CTF Elimination oneway
========================
]]
function G.SendAttackingTeamMessageToAllClients()
	for i = 0, G.level.maxclients - 1 do
		if G.level.clients[i].pers.connected == C.CON_CONNECTED then
			G.AttackingTeamMessage(G.g_entities[i])
		end
	end
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
	OpenEliminationDoors()
end

--things to do at end of round:
function G.EndEliminationRound()
	local level = G.level
	G.DisableWeapons()
	CloseEliminationDoors()
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
	CloseEliminationDoors()
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
	--OpenEliminationDoors();
	level.roundNumberStarted = level.roundNumber - 1
	level.roundStartTime = level.time + 1000 * G.g_elimination_warmup.integer
	G.SendEliminationMessageToAllClients()
	level.roundRespawned = false
	if G.g_elimination_ctf_oneway.integer ~= 0 then
		G.SendAttackingTeamMessageToAllClients()
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

--[[
=============
CheckElimination
=============
]]
function G.CheckElimination()
	local level = G.level
	local counts = {}
	local countsLiving = {}
	local countsHealth = {}
	local countLivingHumans
	local countHumans

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

	if G.g_gametype.integer ~= C.GT_ELIMINATION and G.g_gametype.integer ~= C.GT_CTF_ELIMINATION then
		return
	end

	counts[C.TEAM_BLUE] = G.TeamCount(-1, C.TEAM_BLUE)
	counts[C.TEAM_RED] = G.TeamCount(-1, C.TEAM_RED)

	countsLiving[C.TEAM_BLUE] = G.TeamLivingCount(-1, C.TEAM_BLUE)
	countsLiving[C.TEAM_RED] = G.TeamLivingCount(-1, C.TEAM_RED)

	countsHealth[C.TEAM_BLUE] = G.TeamHealthCount(-1, C.TEAM_BLUE)
	countsHealth[C.TEAM_RED] = G.TeamHealthCount(-1, C.TEAM_RED)

	countHumans = G.TeamHumanParticipantsCount(-1)
	countLivingHumans = G.TeamLivingHumanCount(-1)

	if countLivingHumans == 0 and countHumans > 0 then
		level.humansEliminated = true
	else
		level.humansEliminated = false
	end

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
		CloseEliminationDoorsInstantly()
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
			OpenEliminationDoors()
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

--[[
CheckLMS
]]
function G.CheckLMS()
	local level = G.level
	local mode
	local countsLiving = {}
	local countHumans
	local countLivingHumans
	mode = G.g_lms_mode.integer
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

	if G.g_gametype.integer ~= C.GT_LMS then
		return
	end

	countsLiving[C.TEAM_FREE] = G.TeamLivingCount(-1, C.TEAM_FREE)

	countHumans = G.TeamHumanParticipantsCount(-1)
	countLivingHumans = G.TeamLivingHumanCount(-1)

	if countLivingHumans == 0 and countHumans > 0 then
		level.humansEliminated = true
	else
		level.humansEliminated = false
	end

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
		--DisableWeapons();
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

return nil
