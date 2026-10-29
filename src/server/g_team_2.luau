--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_team.c, part 2 of 3).

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
-- Luau port of OpenArena 0.8.8's g_team.c (gamecode 9e0f0c0), part 2: domination, double domination and flag touch logic.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_team")

local INT_MAX = 2147483647
local S_COLOR_WHITE = "^7"
-- challenges.h award numbers are absent from g_defs; same values as the logged award ids
local AWARD_CAPTURE = 4
local AWARD_ASSIST = 5

function G.getDomPointNumber(point)
	local i = 1
	while i < C.MAX_DOMINATION_POINTS and i < G.level.domination_points_count do
		if G.dom_points[i] == nil then
			return 0 -- Not found, just return first, so we don't crash
		end
		if G.dom_points[i] == point then
			return i
		end
		i += 1
	end
	return 0
end

function G.Team_Dom_TakePoint(point, team, clientnumber)
	local it
	local origin = Q.vec3()
	local i = G.getDomPointNumber(point)
	if i < 0 then
		i = 0
	end
	if i >= C.MAX_DOMINATION_POINTS then
		i = C.MAX_DOMINATION_POINTS - 1
	end

	it = nil
	Q.VectorCopy(point.r.currentOrigin, origin)

	if team == C.TEAM_RED then
		it = BG.BG_FindItem("Red domination point")
		G.PrintMsg(nil, "Red took '%s'\n", G.level.domination_points_names[i])
	elseif team == C.TEAM_BLUE then
		it = BG.BG_FindItem("Blue domination point")
		G.PrintMsg(nil, "Blue took '%s'\n", G.level.domination_points_names[i])
	end
	if it == nil then
		G.PrintMsg(nil, "No item\n")
		return
	end

	G.G_FreeEntity(point)

	point = G.G_Spawn()

	Q.VectorCopy(origin, point.s.origin)
	point.classname = it.classname
	G.dom_points[i] = point
	G.G_SpawnItem(point, it)
	G.FinishSpawningItem(point)
	G.level.pointStatusDom[i] = team
	G.G_LogPrintf("DOM: %i %i %i %i: %s takes point %s!\n",
		clientnumber, i, 0, team,
		G.TeamName(team), G.level.domination_points_names[i])
	G.SendDominationPointsStatusMessageToAllClients()
end

--Functions for Double Domination

function G.Team_DD_RemovePointAgfx()
	if G.ddA ~= nil then
		G.G_FreeEntity(G.ddA)
		G.ddA = nil
	end
end

function G.Team_DD_RemovePointBgfx()
	if G.ddB ~= nil then
		G.G_FreeEntity(G.ddB)
		G.ddB = nil
	end
end

function G.Team_DD_makeA2team(target, team)
	local it
	G.Team_DD_RemovePointAgfx()
	it = nil
	if team == C.TEAM_NONE then
		return
	end
	if team == C.TEAM_RED then
		it = BG.BG_FindItem("Point A (Red)")
	end
	if team == C.TEAM_BLUE then
		it = BG.BG_FindItem("Point A (Blue)")
	end
	if team == C.TEAM_FREE then
		it = BG.BG_FindItem("Point A (White)")
	end
	if it == nil then
		G.PrintMsg(nil, "No item\n")
		return
	end
	G.ddA = G.G_Spawn()

	Q.VectorCopy(target.r.currentOrigin, G.ddA.s.origin)
	G.ddA.classname = it.classname
	G.G_SpawnItem(G.ddA, it)
	G.FinishSpawningItem(G.ddA)
end

function G.Team_DD_makeB2team(target, team)
	local it

	G.Team_DD_RemovePointBgfx()
	it = nil
	if team == C.TEAM_NONE then
		return
	end
	if team == C.TEAM_RED then
		it = BG.BG_FindItem("Point B (Red)")
	end
	if team == C.TEAM_BLUE then
		it = BG.BG_FindItem("Point B (Blue)")
	end
	if team == C.TEAM_FREE then
		it = BG.BG_FindItem("Point B (White)")
	end
	if it == nil then
		G.PrintMsg(nil, "No item\n")
		return
	end
	G.ddB = G.G_Spawn()

	Q.VectorCopy(target.r.currentOrigin, G.ddB.s.origin)
	G.ddB.classname = it.classname
	G.G_SpawnItem(G.ddB, it)
	G.FinishSpawningItem(G.ddB)
end

function G.Team_ResetFlags()
	if G.g_gametype.integer == C.GT_CTF or G.g_gametype.integer == C.GT_CTF_ELIMINATION then
		G.Team_ResetFlag(C.TEAM_RED)
		G.Team_ResetFlag(C.TEAM_BLUE)
	elseif G.g_gametype.integer == C.GT_1FCTF then
		G.Team_ResetFlag(C.TEAM_FREE)
	end
end

function G.Team_ReturnFlagSound(ent, team)
	if ent == nil then
		G.G_Printf("Warning:  NULL passed to Team_ReturnFlagSound\n")
		return
	end

	--See if we are during CTF_ELIMINATION warmup
	if (G.level.time <= G.level.roundStartTime and G.level.time > G.level.roundStartTime - 1000 * G.g_elimination_activewarmup.integer) and G.g_gametype.integer == C.GT_CTF_ELIMINATION then
		return
	end

	local te = G.G_TempEntity(ent.s.pos.trBase, C.EV_GLOBAL_TEAM_SOUND)
	if team == C.TEAM_BLUE then
		te.s.eventParm = C.GTS_RED_RETURN
	else
		te.s.eventParm = C.GTS_BLUE_RETURN
	end
	te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_BROADCAST)
end

function G.Team_TakeFlagSound(ent, team)
	if ent == nil then
		G.G_Printf("Warning:  NULL passed to Team_TakeFlagSound\n")
		return
	end

	-- only play sound when the flag was at the base
	-- or not picked up the last 10 seconds
	local teamgame = G.teamgame
	if team == C.TEAM_RED then
		if teamgame.blueStatus ~= C.FLAG_ATBASE then
			if teamgame.blueTakenTime > G.level.time - 10000 and G.g_gametype.integer ~= C.GT_CTF_ELIMINATION then
				return
			end
		end
		teamgame.blueTakenTime = G.level.time
	elseif team == C.TEAM_BLUE then -- CTF
		if teamgame.redStatus ~= C.FLAG_ATBASE then
			if teamgame.redTakenTime > G.level.time - 10000 and G.g_gametype.integer ~= C.GT_CTF_ELIMINATION then
				return
			end
		end
		teamgame.redTakenTime = G.level.time
	end

	local te = G.G_TempEntity(ent.s.pos.trBase, C.EV_GLOBAL_TEAM_SOUND)
	if team == C.TEAM_BLUE then
		te.s.eventParm = C.GTS_RED_TAKEN
	else
		te.s.eventParm = C.GTS_BLUE_TAKEN
	end
	te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_BROADCAST)
end

function G.Team_CaptureFlagSound(ent, team)
	if ent == nil then
		G.G_Printf("Warning:  NULL passed to Team_CaptureFlagSound\n")
		return
	end

	local te = G.G_TempEntity(ent.s.pos.trBase, C.EV_GLOBAL_TEAM_SOUND)
	if team == C.TEAM_BLUE then
		te.s.eventParm = C.GTS_BLUE_CAPTURE
	else
		te.s.eventParm = C.GTS_RED_CAPTURE
	end
	te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_BROADCAST)
end

function G.Team_ReturnFlag(team)
	G.Team_ReturnFlagSound(G.Team_ResetFlag(team), team)
	if team == C.TEAM_FREE then
		G.PrintMsg(nil, "The flag has returned!\n")
		if G.g_gametype.integer == C.GT_1FCTF then
			G.G_LogPrintf("1FCTF: %i %i %i: The flag was returned!\n", -1, -1, 2)
		end
	else
		G.PrintMsg(nil, "The %s flag has returned!\n", G.TeamName(team))
		if G.g_gametype.integer == C.GT_CTF_ELIMINATION then
			G.G_LogPrintf("CTF: %i %i %i: The %s flag was returned!\n", -1, team, 2, G.TeamName(team))
		else
			-- 0.8.8 tests GT_CTF_ELIMINATION twice, so this branch never runs
			if G.g_gametype.integer == C.GT_CTF_ELIMINATION then
				G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: The %s flag was returned!\n", G.level.roundNumber, -1, team, 2, G.TeamName(team))
			end
		end
	end
end

function G.Team_FreeEntity(ent)
	if ent.item.giTag == C.PW_REDFLAG then
		G.Team_ReturnFlag(C.TEAM_RED)
	elseif ent.item.giTag == C.PW_BLUEFLAG then
		G.Team_ReturnFlag(C.TEAM_BLUE)
	elseif ent.item.giTag == C.PW_NEUTRALFLAG then
		G.Team_ReturnFlag(C.TEAM_FREE)
	end
end

--[[
==============
Team_DroppedFlagThink

Automatically set in Launch_Item if the item is one of the flags

Flags are unique in that if they are dropped, the base flag must be respawned when they time out
==============
]]
function G.Team_DroppedFlagThink(ent)
	local team = C.TEAM_FREE

	if ent.item.giTag == C.PW_REDFLAG then
		team = C.TEAM_RED
	elseif ent.item.giTag == C.PW_BLUEFLAG then
		team = C.TEAM_BLUE
	elseif ent.item.giTag == C.PW_NEUTRALFLAG then
		team = C.TEAM_FREE
	end

	G.Team_ReturnFlagSound(G.Team_ResetFlag(team), team)
	-- Reset Flag will delete this entity
end

--Update DD points
function G.updateDDpoints()
	G.Team_SetFlagStatus(C.TEAM_RED, G.level.pointStatusA)
	G.Team_SetFlagStatus(C.TEAM_BLUE, G.level.pointStatusB)
end

function G.Team_SpawnDoubleDominationPoints()
	G.level.pointStatusA = C.TEAM_FREE
	G.level.pointStatusB = C.TEAM_FREE
	G.updateDDpoints()
	local ent = nil
	ent = G.G_Find(ent, "classname", "team_CTF_redflag")
	if ent ~= nil then
		G.Team_DD_makeA2team(ent, C.TEAM_FREE)
	end
	ent = nil
	ent = G.G_Find(ent, "classname", "team_CTF_blueflag")
	if ent ~= nil then
		G.Team_DD_makeB2team(ent, C.TEAM_FREE)
	end
	return 1
end

function G.Team_RemoveDoubleDominationPoints()
	G.level.pointStatusA = C.TEAM_NONE
	G.level.pointStatusB = C.TEAM_NONE
	G.updateDDpoints()
	G.Team_DD_makeA2team(nil, C.TEAM_NONE)
	G.Team_DD_makeB2team(nil, C.TEAM_NONE)
	return 1
end

--team is the either TEAM_RED(A) or TEAM_BLUE(B)
function G.Team_TouchDoubleDominationPoint(ent, other, team)
	local level = G.level
	local cl = other.client
	local otherDominating, isClose
	local clientTeam = cl.sess.sessionTeam
	local otherTeam
	local score

	if clientTeam == C.TEAM_RED then
		otherTeam = C.TEAM_BLUE
	else
		otherTeam = C.TEAM_RED
	end

	otherDominating = false
	isClose = false

	if level.pointStatusA == otherTeam and level.pointStatusB == otherTeam then
		otherDominating = true
		if level.time - level.timeTaken > (10 - C.DD_CLOSE) * 1000 then
			isClose = true
		end
	end

	if team == C.TEAM_RED then --We have touched point A
		if C.TEAM_NONE == level.pointStatusA then
			return 0 --Haven't spawned yet
		end
		if clientTeam == level.pointStatusA then
			return 0 --If we already have the flag
		end
		level.pointStatusA = clientTeam
		G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " (%s) took control of A!\n", cl.pers.netname, G.TeamName(clientTeam))
		G.Team_DD_makeA2team(ent, clientTeam)
		G.G_LogPrintf("DD: %i %i %i: %s took point A for %s!\n", cl.ps.clientNum, clientTeam, 0, cl.pers.netname, G.TeamName(clientTeam))
		--Give personal score
		score = C.DD_POINT_CAPTURE --Base score for capture
		if otherDominating then
			score += C.DD_POINT_CAPTURE_BREAK
			if isClose then
				score += C.DD_POINT_CAPTURE_CLOSE
			end
		end
		G.AddScore(other, ent.r.currentOrigin, score)
		--Do we also have point B?
		if clientTeam == level.pointStatusB then
			--We are dominating!
			level.timeTaken = level.time --At this time
			G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " is dominating!\n", G.TeamName(clientTeam))
			G.SendDDtimetakenMessageToAllClients()
		end
	end

	if team == C.TEAM_BLUE then --We have touched point B
		if C.TEAM_NONE == level.pointStatusB then
			return 0 --Haven't spawned yet
		end
		if clientTeam == level.pointStatusB then
			return 0 --If we already have the flag
		end
		level.pointStatusB = clientTeam
		G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " (%s) took control of B!\n", cl.pers.netname, G.TeamName(clientTeam))
		G.Team_DD_makeB2team(ent, clientTeam)
		G.G_LogPrintf("DD: %i %i %i: %s took point B for %s!\n", cl.ps.clientNum, clientTeam, 1, cl.pers.netname, G.TeamName(clientTeam))
		score = C.DD_POINT_CAPTURE
		if otherDominating then
			score += C.DD_POINT_CAPTURE_BREAK
			if isClose then
				score += C.DD_POINT_CAPTURE_CLOSE
			end
		end
		G.AddScore(other, ent.r.currentOrigin, score)
		--Do we also have point A?
		if clientTeam == level.pointStatusA then
			level.timeTaken = level.time
			G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " is dominating!\n", G.TeamName(clientTeam))
			G.SendDDtimetakenMessageToAllClients()
		end
	end

	G.updateDDpoints()

	return 0
end

local AWARD_CLEAR = bit32.bnot(bit32.bor(C.EF_AWARD_IMPRESSIVE, C.EF_AWARD_EXCELLENT, C.EF_AWARD_GAUNTLET, C.EF_AWARD_ASSIST, C.EF_AWARD_DEFEND, C.EF_AWARD_CAP))

function G.Team_TouchOurFlag(ent, other, team)
	local level = G.level
	local player
	local cl = other.client
	local enemy_flag

	if G.g_gametype.integer == C.GT_1FCTF then
		enemy_flag = C.PW_NEUTRALFLAG
	else
		if cl.sess.sessionTeam == C.TEAM_RED then
			enemy_flag = C.PW_BLUEFLAG
		else
			enemy_flag = C.PW_REDFLAG
		end

		if bit32.band(ent.flags, C.FL_DROPPED_ITEM) ~= 0 then
			-- hey, its not home.  return it by teleporting it back
			G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " returned the %s flag!\n",
				cl.pers.netname, G.TeamName(team))
			G.AddScore(other, ent.r.currentOrigin, C.CTF_RECOVERY_BONUS)
			if G.g_gametype.integer == C.GT_CTF then
				G.G_LogPrintf("CTF: %i %i %i: %s returned the %s flag!\n", cl.ps.clientNum, team, 2, cl.pers.netname, G.TeamName(team))
			elseif G.g_gametype.integer == C.GT_CTF_ELIMINATION then
				G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s returned the %s flag!\n", level.roundNumber, cl.ps.clientNum, team, 2, cl.pers.netname, G.TeamName(team))
			end
			other.client.pers.teamState.flagrecovery += 1
			other.client.pers.teamState.lastreturnedflag = level.time
			--ResetFlag will remove this entity!  We must return zero
			G.Team_ReturnFlagSound(G.Team_ResetFlag(team), team)
			return 0
		end
	end

	-- the flag is at home base.  if the player has the enemy
	-- flag, he's just won!
	if cl.ps.powerups[enemy_flag] == 0 then
		return 0 -- We don't have the flag
	end
	if G.g_gametype.integer == C.GT_1FCTF then
		G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " captured the flag!\n", cl.pers.netname)
		G.G_LogPrintf("1FCTF: %i %i %i: %s captured the flag!\n", cl.ps.clientNum, -1, 1, cl.pers.netname)
	else
		G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " captured the %s flag!\n", cl.pers.netname, G.TeamName(G.OtherTeam(team)))
		if G.g_gametype.integer == C.GT_CTF then
			G.G_LogPrintf("CTF: %i %i %i: %s captured the %s flag!\n", cl.ps.clientNum, G.OtherTeam(team), 1, cl.pers.netname, G.TeamName(G.OtherTeam(team)))
		end
		if G.g_gametype.integer == C.GT_CTF_ELIMINATION then
			G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s captured the %s flag!\n", level.roundNumber, cl.ps.clientNum, G.OtherTeam(team), 1, cl.pers.netname, G.TeamName(G.OtherTeam(team)))
		end
	end

	cl.ps.powerups[enemy_flag] = 0

	G.teamgame.last_flag_capture = level.time
	G.teamgame.last_capture_team = team

	-- Increase the team's score
	G.AddTeamScore(ent.s.pos.trBase, other.client.sess.sessionTeam, 1)
	G.Team_ForceGesture(other.client.sess.sessionTeam)
	--If CTF Elimination, stop the round:
	if G.g_gametype.integer == C.GT_CTF_ELIMINATION then
		G.EndEliminationRound()
	end

	other.client.pers.teamState.captures += 1
	-- add the sprite over the player's head
	other.client.ps.eFlags = bit32.band(other.client.ps.eFlags, AWARD_CLEAR)
	other.client.ps.eFlags = bit32.bor(other.client.ps.eFlags, C.EF_AWARD_CAP)
	other.client.rewardTime = level.time + C.REWARD_SPRITE_TIME
	other.client.ps.persistant[C.PERS_CAPTURES] += 1
	G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", other.client.ps.clientNum, 4, other.client.pers.netname, "CAPTURE")
	if G.TeamCount(-1, C.TEAM_RED) ~= 0 and G.TeamCount(-1, C.TEAM_BLUE) ~= 0 and not level.hadBots then
		G.ChallengeMessage(other, AWARD_CAPTURE)
	end
	-- other gets another 10 frag bonus
	G.AddScore(other, ent.r.currentOrigin, C.CTF_CAPTURE_BONUS)

	G.Team_CaptureFlagSound(ent, team)

	-- Ok, let's do the player loop, hand out the bonuses
	for i = 0, G.g_maxclients.integer - 1 do
		player = G.g_entities[i]
		if not player.inuse or player == other then
			continue
		end

		if player.client.sess.sessionTeam ~= cl.sess.sessionTeam then
			player.client.pers.teamState.lasthurtcarrier = -5
		else
			if player ~= other then
				G.AddScore(player, ent.r.currentOrigin, C.CTF_TEAM_BONUS)
			end
			-- award extra points for capture assists
			if player.client.pers.teamState.lastreturnedflag +
				C.CTF_RETURN_FLAG_ASSIST_TIMEOUT > level.time then
				G.AddScore(player, ent.r.currentOrigin, C.CTF_RETURN_FLAG_ASSIST_BONUS)
				other.client.pers.teamState.assists += 1

				player.client.ps.persistant[C.PERS_ASSIST_COUNT] += 1
				if not level.hadBots then
					G.ChallengeMessage(player, AWARD_ASSIST)
				end
				G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", player.client.ps.clientNum, 5, player.client.pers.netname, "ASSIST")
				-- add the sprite over the player's head
				player.client.ps.eFlags = bit32.band(player.client.ps.eFlags, AWARD_CLEAR)
				player.client.ps.eFlags = bit32.bor(player.client.ps.eFlags, C.EF_AWARD_ASSIST)
				player.client.rewardTime = level.time + C.REWARD_SPRITE_TIME
			end
			if player.client.pers.teamState.lastfraggedcarrier +
				C.CTF_FRAG_CARRIER_ASSIST_TIMEOUT > level.time then
				G.AddScore(player, ent.r.currentOrigin, C.CTF_FRAG_CARRIER_ASSIST_BONUS)
				other.client.pers.teamState.assists += 1
				player.client.ps.persistant[C.PERS_ASSIST_COUNT] += 1
				if not level.hadBots then
					G.ChallengeMessage(player, AWARD_ASSIST)
				end
				G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", player.client.ps.clientNum, 5, player.client.pers.netname, "ASSIST")
				-- add the sprite over the player's head
				player.client.ps.eFlags = bit32.band(player.client.ps.eFlags, AWARD_CLEAR)
				player.client.ps.eFlags = bit32.bor(player.client.ps.eFlags, C.EF_AWARD_ASSIST)
				player.client.rewardTime = level.time + C.REWARD_SPRITE_TIME
			end
		end
	end
	G.Team_ResetFlags()

	G.CalculateRanks()

	return 0 -- Do not respawn this automatically
end

function G.Team_TouchEnemyFlag(ent, other, team)
	local cl = other.client

	if G.g_gametype.integer == C.GT_1FCTF then
		G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " got the flag!\n", other.client.pers.netname)
		G.G_LogPrintf("1FCTF: %i %i %i: %s got the flag!\n", cl.ps.clientNum, team, 0, cl.pers.netname)

		cl.ps.powerups[C.PW_NEUTRALFLAG] = INT_MAX -- flags never expire

		if team == C.TEAM_RED then
			G.Team_SetFlagStatus(C.TEAM_FREE, C.FLAG_TAKEN_RED)
		else
			G.Team_SetFlagStatus(C.TEAM_FREE, C.FLAG_TAKEN_BLUE)
		end
	else
		G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " got the %s flag!\n",
			other.client.pers.netname, G.TeamName(team))

		if G.g_gametype.integer == C.GT_CTF then
			G.G_LogPrintf("CTF: %i %i %i: %s got the %s flag!\n", cl.ps.clientNum, team, 0, cl.pers.netname, G.TeamName(team))
		elseif G.g_gametype.integer == C.GT_CTF_ELIMINATION then
			G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s got the %s flag!\n", G.level.roundNumber, cl.ps.clientNum, team, 0, cl.pers.netname, G.TeamName(team))
		end

		if team == C.TEAM_RED then
			cl.ps.powerups[C.PW_REDFLAG] = INT_MAX -- flags never expire
		else
			cl.ps.powerups[C.PW_BLUEFLAG] = INT_MAX -- flags never expire
		end

		G.Team_SetFlagStatus(team, C.FLAG_TAKEN)
	end

	G.AddScore(other, ent.r.currentOrigin, C.CTF_FLAG_BONUS)
	cl.pers.teamState.flagsince = G.level.time
	G.Team_TakeFlagSound(ent, team)

	return -1 -- Do not respawn this automatically, but do delete it if it was FL_DROPPED
end

function G.Pickup_Team(ent, other)
	local team
	local cl = other.client

	if G.g_gametype.integer == C.GT_OBELISK then
		-- there are no team items that can be picked up in obelisk
		G.G_FreeEntity(ent)
		return 0
	end

	if G.g_gametype.integer == C.GT_HARVESTER then
		-- the only team items that can be picked up in harvester are the cubes
		if ent.spawnflags ~= cl.sess.sessionTeam then
			cl.ps.generic1 += 1 --Skull pickedup
			G.G_LogPrintf("HARVESTER: %i %i %i %i %i: %s picked up a skull.\n",
				cl.ps.clientNum, cl.sess.sessionTeam, 3, -1, 1,
				cl.pers.netname)
		else
			G.G_LogPrintf("HARVESTER: %i %i %i %i %i: %s destroyed a skull.\n,",
				cl.ps.clientNum, cl.sess.sessionTeam, 2, -1, 1,
				cl.pers.netname)
		end
		G.G_FreeEntity(ent) --Destory skull
		return 0
	end
	if G.g_gametype.integer == C.GT_DOMINATION then
		G.Team_Dom_TakePoint(ent, cl.sess.sessionTeam, cl.ps.clientNum)
		return 0
	end
	-- figure out what team this flag is
	if ent.classname == "team_CTF_redflag" then
		team = C.TEAM_RED
	elseif ent.classname == "team_CTF_blueflag" then
		team = C.TEAM_BLUE
	elseif ent.classname == "team_CTF_neutralflag" then
		team = C.TEAM_FREE
	else
		G.PrintMsg(other, "Don't know what team the flag is on.\n")
		return 0
	end
	if G.g_gametype.integer == C.GT_1FCTF then
		if team == C.TEAM_FREE then
			return G.Team_TouchEnemyFlag(ent, other, cl.sess.sessionTeam)
		end
		if team ~= cl.sess.sessionTeam then
			return G.Team_TouchOurFlag(ent, other, cl.sess.sessionTeam)
		end
		return 0
	end
	if G.g_gametype.integer == C.GT_DOUBLE_D then
		return G.Team_TouchDoubleDominationPoint(ent, other, team)
	end
	-- GT_CTF
	if team == cl.sess.sessionTeam then
		return G.Team_TouchOurFlag(ent, other, team)
	end
	return G.Team_TouchEnemyFlag(ent, other, team)
end

--[[
===========
Team_GetLocation

Report a location for the player. Uses placed nearby target_location entities
============
]]
function G.Team_GetLocation(ent)
	local best = nil
	local bestlen = 3 * 8192.0 * 8192.0
	local origin = Q.vec3()

	Q.VectorCopy(ent.r.currentOrigin, origin)

	local eloc = G.level.locationHead
	while eloc ~= nil do
		local co = eloc.r.currentOrigin
		local len = (origin[0] - co[0]) * (origin[0] - co[0])
			+ (origin[1] - co[1]) * (origin[1] - co[1])
			+ (origin[2] - co[2]) * (origin[2] - co[2])

		if len <= bestlen and G.trap_InPVS(origin, co) then
			bestlen = len
			best = eloc
		end
		eloc = eloc.nextTrain
	end

	return best
end

--[[
===========
Team_GetLocation

Report a location for the player. Uses placed nearby target_location entities
============
]]
function G.Team_GetLocationMsg(ent, loclen)
	local best = G.Team_GetLocation(ent)

	if best == nil then
		return false, ""
	end

	if best.count ~= 0 then
		if best.count < 0 then
			best.count = 0
		end
		if best.count > 7 then
			best.count = 7
		end
		return true, QS.Com_sprintf(loclen, "%c%c%s" .. S_COLOR_WHITE, string.byte(QS.Q_COLOR_ESCAPE), best.count + string.byte("0"), best.message)
	end
	return true, QS.Com_sprintf(loclen, "%s", best.message)
end

return nil
