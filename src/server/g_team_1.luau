--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_team.c).

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
-- Luau port of g_team.c, part 1 of 3 (game/g_team.c, part 1 of 3): team game state, flag status, frag bonuses, domination spawn.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_team")

-- challenge id from challenges.h (not provided by g_defs)
local CH_AWARD_DEFENCE = 34

local S_COLOR_RED = "^1"
local S_COLOR_BLUE = "^4"
local S_COLOR_YELLOW = "^3"
local S_COLOR_WHITE = "^7"

local function newTeamgame()
	return {
		last_flag_capture = 0,
		last_capture_team = 0,
		redStatus = 0,
		blueStatus = 0,
		flagStatus = 0,
		redTakenTime = 0,
		blueTakenTime = 0,
		redObeliskAttackedTime = 0,
		blueObeliskAttackedTime = 0,
	}
end

G.teamgame = newTeamgame()

G.neutralObelisk = nil

-- Some pointers for Double Domination so we don't need GFind
G.ddA = nil
G.ddB = nil
-- Pointers for Standard Domination
G.dom_points = {}

G.dominationPointsSpawned = false

SF.ctfFlagStatusRemap = { [0] = "0", "1", "*", "*", "2" }
SF.oneFlagStatusRemap = { [0] = "0", "1", "2", "3", "4" }

local function clearAwardFlags(client)
	client.ps.eFlags = bit32.band(client.ps.eFlags, bit32.bnot(bit32.bor(C.EF_AWARD_IMPRESSIVE, C.EF_AWARD_EXCELLENT, C.EF_AWARD_GAUNTLET, C.EF_AWARD_ASSIST, C.EF_AWARD_DEFEND, C.EF_AWARD_CAP)))
	client.ps.eFlags = bit32.bor(client.ps.eFlags, C.EF_AWARD_DEFEND)
end

function G.Team_InitGame()
	G.teamgame = newTeamgame()
	local gt = G.g_gametype.integer

	if gt == C.GT_CTF or gt == C.GT_CTF_ELIMINATION or gt == C.GT_DOUBLE_D then
		G.teamgame.redStatus = -1 -- Invalid to force update
		G.Team_SetFlagStatus(C.TEAM_RED, C.FLAG_ATBASE)
		G.teamgame.blueStatus = -1 -- Invalid to force update
		G.Team_SetFlagStatus(C.TEAM_BLUE, C.FLAG_ATBASE)
		G.ddA = nil
		G.ddB = nil
	elseif gt == C.GT_DOMINATION then
		G.dominationPointsSpawned = false
	elseif gt == C.GT_1FCTF or gt == C.GT_POSSESSION then
		G.teamgame.flagStatus = -1 -- Invalid to force update
		G.Team_SetFlagStatus(C.TEAM_FREE, C.FLAG_ATBASE)
	end
end

function G.OtherTeam(team)
	if team == C.TEAM_RED then
		return C.TEAM_BLUE
	elseif team == C.TEAM_BLUE then
		return C.TEAM_RED
	end
	return team
end

function G.TeamName(team)
	if team == C.TEAM_RED then
		return "RED"
	elseif team == C.TEAM_BLUE then
		return "BLUE"
	elseif team == C.TEAM_SPECTATOR then
		return "SPECTATOR"
	end
	return "FREE"
end

function G.OtherTeamName(team)
	if team == C.TEAM_RED then
		return "BLUE"
	elseif team == C.TEAM_BLUE then
		return "RED"
	elseif team == C.TEAM_SPECTATOR then
		return "SPECTATOR"
	end
	return "FREE"
end

function G.TeamColorString(team)
	if team == C.TEAM_RED then
		return S_COLOR_RED
	elseif team == C.TEAM_BLUE then
		return S_COLOR_BLUE
	elseif team == C.TEAM_SPECTATOR then
		return S_COLOR_YELLOW
	end
	return S_COLOR_WHITE
end

-- NULL (nil) for everyone
function G.PrintMsg(ent, fmt, ...)
	local msg = QS.va(fmt, ...)
	if #msg >= 1024 then
		G.G_Error("PrintMsg overrun")
	end

	-- double quotes are bad
	msg = string.gsub(msg, '"', "'")

	G.trap_SendServerCommand(if ent == nil then -1 else ent.index, QS.va('print "%s"', msg))
end

--[[
================
KK-OAX From Tremulous
G_TeamFromString
Return the team referenced by a string
================
]]
function G.G_TeamFromString(str)
	local ch = string.lower(string.sub(str, 1, 1))
	if ch == "0" or ch == "s" then
		return C.TEAM_NONE
	elseif ch == "1" or ch == "f" then
		return C.TEAM_FREE
	elseif ch == "2" or ch == "r" then
		return C.TEAM_RED
	elseif ch == "3" or ch == "b" then
		return C.TEAM_BLUE
	end
	return C.TEAM_NUM_TEAMS
end

--[[
==============
AddTeamScore

 used for gametype > GT_TEAM
 for gametype GT_TEAM the level.teamScores is updated in AddScore in g_combat.c
==============
]]
function G.AddTeamScore(origin, team, score)
	local level = G.level

	if G.g_gametype.integer ~= C.GT_DOMINATION then
		local te = G.G_TempEntity(origin, C.EV_GLOBAL_TEAM_SOUND)
		te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_BROADCAST)

		if team == C.TEAM_RED then
			if level.teamScores[C.TEAM_RED] + score == level.teamScores[C.TEAM_BLUE] then
				-- teams are tied sound
				te.s.eventParm = C.GTS_TEAMS_ARE_TIED
			elseif level.teamScores[C.TEAM_RED] <= level.teamScores[C.TEAM_BLUE] and
				level.teamScores[C.TEAM_RED] + score > level.teamScores[C.TEAM_BLUE] then
				-- red took the lead sound
				te.s.eventParm = C.GTS_REDTEAM_TOOK_LEAD
			else
				-- red scored sound
				te.s.eventParm = C.GTS_REDTEAM_SCORED
			end
		else
			if level.teamScores[C.TEAM_BLUE] + score == level.teamScores[C.TEAM_RED] then
				-- teams are tied sound
				te.s.eventParm = C.GTS_TEAMS_ARE_TIED
			elseif level.teamScores[C.TEAM_BLUE] <= level.teamScores[C.TEAM_RED] and
				level.teamScores[C.TEAM_BLUE] + score > level.teamScores[C.TEAM_RED] then
				-- blue took the lead sound
				te.s.eventParm = C.GTS_BLUETEAM_TOOK_LEAD
			else
				-- blue scored sound
				te.s.eventParm = C.GTS_BLUETEAM_SCORED
			end
		end
	end
	level.teamScores[team] += score
end

--[[
==============
OnSameTeam
==============
]]
function G.OnSameTeam(ent1, ent2)
	if ent1.client == nil or ent2.client == nil then
		return false
	end

	if G.g_gametype.integer < C.GT_TEAM or G.g_ffa_gt == 1 then
		return false
	end

	if ent1.client.sess.sessionTeam == ent2.client.sess.sessionTeam then
		return true
	end

	return false
end

function G.Team_SetFlagStatus(team, status)
	local teamgame = G.teamgame
	local modified = false

	if team == C.TEAM_RED then -- CTF
		if teamgame.redStatus ~= status then
			teamgame.redStatus = status
			modified = true
		end
	elseif team == C.TEAM_BLUE then -- CTF
		if teamgame.blueStatus ~= status then
			teamgame.blueStatus = status
			modified = true
		end
	elseif team == C.TEAM_FREE then -- One Flag CTF
		if teamgame.flagStatus ~= status then
			teamgame.flagStatus = status
			modified = true
		end
	end

	if modified then
		local st
		local gt = G.g_gametype.integer

		if gt == C.GT_CTF or gt == C.GT_CTF_ELIMINATION then
			st = SF.ctfFlagStatusRemap[teamgame.redStatus] .. SF.ctfFlagStatusRemap[teamgame.blueStatus]
		elseif gt == C.GT_DOUBLE_D then
			st = SF.oneFlagStatusRemap[teamgame.redStatus] .. SF.oneFlagStatusRemap[teamgame.blueStatus]
		else -- GT_1FCTF
			st = SF.oneFlagStatusRemap[teamgame.flagStatus]
		end

		G.trap_SetConfigstring(C.CS_FLAGSTATUS, st)
	end
end

function G.Team_CheckDroppedItem(dropped)
	if dropped.item.giTag == C.PW_REDFLAG then
		G.Team_SetFlagStatus(C.TEAM_RED, C.FLAG_DROPPED)
	elseif dropped.item.giTag == C.PW_BLUEFLAG then
		G.Team_SetFlagStatus(C.TEAM_BLUE, C.FLAG_DROPPED)
	elseif dropped.item.giTag == C.PW_NEUTRALFLAG then
		G.Team_SetFlagStatus(C.TEAM_FREE, C.FLAG_DROPPED)
	end
end

--[[
================
Team_ForceGesture
================
]]
function G.Team_ForceGesture(team)
	for i = 0, C.MAX_CLIENTS - 1 do
		local ent = G.g_entities[i]
		if ent.inuse and ent.client ~= nil and ent.client.sess.sessionTeam == team then
			ent.flags = bit32.bor(ent.flags, C.FL_FORCE_GESTURE)
		end
	end
end

--[[
================
Team_DD_bonusAtPoints
Adds bonus point to a player if he is close to the point and on the team that scores
================
]]
function G.Team_DD_bonusAtPoints(team)
	local v1 = Q.vec3()
	local v2 = Q.vec3()
	local ddA = G.ddA
	local ddB = G.ddB

	for i = 0, C.MAX_CLIENTS - 1 do
		local player = G.g_entities[i]
		if player.inuse and player.client ~= nil then
			if player.client.sess.sessionTeam ~= team then
				return -- player was not on scoring team
			end

			-- See if the player is close to any of the points:
			Q.VectorSubtract(player.r.currentOrigin, ddA.r.currentOrigin, v1)
			Q.VectorSubtract(player.r.currentOrigin, ddB.r.currentOrigin, v2)
			if not (((Q.VectorLength(v1) < C.CTF_TARGET_PROTECT_RADIUS and
				G.trap_InPVS(ddA.r.currentOrigin, player.r.currentOrigin)) or
				(Q.VectorLength(v2) < C.CTF_TARGET_PROTECT_RADIUS and
				G.trap_InPVS(ddB.r.currentOrigin, player.r.currentOrigin)))) then
				return -- Wasn't close to any of the points
			end

			G.AddScore(player, player.r.currentOrigin, C.DD_AT_POINT_AT_CAPTURE)
		end
	end
end

--[[
================
Team_FragBonuses

Calculate the bonuses for flag defense, flag carrier defense, etc.
Note that bonuses are not cumulative.  You get one, they are in importance
order.
================
]]
function G.Team_FragBonuses(targ, inflictor, attacker)
	local level = G.level
	local flag_pw, enemy_flag_pw
	local carrier = nil
	local c
	local v1 = Q.vec3()
	local v2 = Q.vec3()

	-- no bonus for fragging yourself or team mates
	if targ.client == nil or attacker.client == nil or targ == attacker or G.OnSameTeam(targ, attacker) then
		return
	end

	local team = targ.client.sess.sessionTeam
	local otherteam = G.OtherTeam(targ.client.sess.sessionTeam)
	if otherteam < 0 then
		return -- whoever died isn't on a team
	end

	-- same team, if the flag at base, check to he has the enemy flag
	if team == C.TEAM_RED then
		flag_pw = C.PW_REDFLAG
		enemy_flag_pw = C.PW_BLUEFLAG
	else
		flag_pw = C.PW_BLUEFLAG
		enemy_flag_pw = C.PW_REDFLAG
	end

	if G.g_gametype.integer == C.GT_1FCTF or G.g_gametype.integer == C.GT_POSSESSION then
		enemy_flag_pw = C.PW_NEUTRALFLAG
	end

	-- did the attacker frag the flag carrier?
	local tokens = 0
	if G.g_gametype.integer == C.GT_HARVESTER then
		tokens = targ.client.ps.generic1
	end
	if targ.client.ps.powerups[enemy_flag_pw] ~= 0 then
		attacker.client.pers.teamState.lastfraggedcarrier = level.time
		if G.g_gametype.integer ~= C.GT_POSSESSION then
			G.AddScore(attacker, targ.r.currentOrigin, C.CTF_FRAG_CARRIER_BONUS)
		end
		attacker.client.pers.teamState.fragcarrier += 1
		if G.g_gametype.integer ~= C.GT_POSSESSION then
			G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " fragged %s's flag carrier!\n",
				attacker.client.pers.netname, G.TeamName(team))
		else
			G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " fragged the flag carrier!\n",
				attacker.client.pers.netname)
			G.G_LogPrintf("POS: %i %i: %s^7 fragged the carrier\n", attacker.s.number, 2, attacker.client.pers.netname)
		end
		if G.g_gametype.integer == C.GT_CTF then
			G.G_LogPrintf("CTF: %i %i %i: %s fragged %s's flag carrier!\n", attacker.client.ps.clientNum, team, 3, attacker.client.pers.netname, G.TeamName(team))
		elseif G.g_gametype.integer == C.GT_CTF_ELIMINATION then
			G.G_LogPrintf("CTF_ELIMINATION: %i %i %i %i: %s fragged %s's flag carrier!\n", level.roundNumber, attacker.client.ps.clientNum, team, 3, attacker.client.pers.netname, G.TeamName(team))
		elseif G.g_gametype.integer == C.GT_1FCTF then
			G.G_LogPrintf("1fCTF: %i %i %i: %s fragged %s's flag carrier!\n", attacker.client.ps.clientNum, team, 3, attacker.client.pers.netname, G.TeamName(team))
		end

		-- the target had the flag, clear the hurt carrier
		-- field on the other team
		for i = 0, G.g_maxclients.integer - 1 do
			local ent = G.g_entities[i]
			if ent.inuse and ent.client.sess.sessionTeam == otherteam then
				ent.client.pers.teamState.lasthurtcarrier = 0
			end
		end
		return
	end

	-- did the attacker frag a head carrier? other->client->ps.generic1
	if tokens ~= 0 then
		attacker.client.pers.teamState.lastfraggedcarrier = level.time
		G.AddScore(attacker, targ.r.currentOrigin, C.CTF_FRAG_CARRIER_BONUS * tokens * tokens)
		attacker.client.pers.teamState.fragcarrier += 1
		G.PrintMsg(nil, "%s" .. S_COLOR_WHITE .. " fragged %s's skull carrier!\n",
			attacker.client.pers.netname, G.TeamName(team))

		G.G_LogPrintf("HARVESTER: %i %i %i %i %i: %s fragged %s (%s) who had %i skulls.\n",
			attacker.client.ps.clientNum, team, 1, targ.client.ps.clientNum, tokens,
			attacker.client.pers.netname, targ.client.pers.netname, G.TeamName(team), tokens)

		-- the target had the flag, clear the hurt carrier
		-- field on the other team
		for i = 0, G.g_maxclients.integer - 1 do
			local ent = G.g_entities[i]
			if ent.inuse and ent.client.sess.sessionTeam == otherteam then
				ent.client.pers.teamState.lasthurtcarrier = 0
			end
		end
		return
	end

	if targ.client.pers.teamState.lasthurtcarrier ~= 0 and
		level.time - targ.client.pers.teamState.lasthurtcarrier < C.CTF_CARRIER_DANGER_PROTECT_TIMEOUT and
		attacker.client.ps.powerups[flag_pw] == 0 then
		-- attacker is on the same team as the flag carrier and
		-- fragged a guy who hurt our flag carrier
		G.AddScore(attacker, targ.r.currentOrigin, C.CTF_CARRIER_DANGER_PROTECT_BONUS)

		attacker.client.pers.teamState.carrierdefense += 1
		targ.client.pers.teamState.lasthurtcarrier = 0

		attacker.client.ps.persistant[C.PERS_DEFEND_COUNT] += 1
		G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", attacker.client.ps.clientNum, 3, attacker.client.pers.netname, "DEFENCE")
		if not level.hadBots then
			G.ChallengeMessage(attacker, CH_AWARD_DEFENCE)
		end
		team = attacker.client.sess.sessionTeam
		-- add the sprite over the player's head
		clearAwardFlags(attacker.client)
		attacker.client.rewardTime = level.time + C.REWARD_SPRITE_TIME

		return
	end
	-- We place the Double Domination bonus test here! This appears to be the best place to place them.
	if G.g_gametype.integer == C.GT_DOUBLE_D then
		local ddA = G.ddA
		local ddB = G.ddB
		if attacker.client.sess.sessionTeam == level.pointStatusA then -- Attack must defend point A
			-- See how close attacker and target was to Point A:
			Q.VectorSubtract(targ.r.currentOrigin, ddA.r.currentOrigin, v1)
			Q.VectorSubtract(attacker.r.currentOrigin, ddA.r.currentOrigin, v2)

			if ((Q.VectorLength(v1) < C.CTF_TARGET_PROTECT_RADIUS and
				G.trap_InPVS(ddA.r.currentOrigin, targ.r.currentOrigin)) or
				(Q.VectorLength(v2) < C.CTF_TARGET_PROTECT_RADIUS and
				G.trap_InPVS(ddA.r.currentOrigin, attacker.r.currentOrigin))) and
				attacker.client.sess.sessionTeam ~= targ.client.sess.sessionTeam then

				-- We defended point A
				-- Was we dominating and maybe close to score?
				if attacker.client.sess.sessionTeam == level.pointStatusB and level.time - level.timeTaken > (G.g_ddCaptureTime.integer - C.DD_CLOSE) * 1000 then
					G.AddScore(attacker, targ.r.currentOrigin, C.DD_POINT_DEFENCE_CLOSE_BONUS)
				else
					G.AddScore(attacker, targ.r.currentOrigin, C.DD_POINT_DEFENCE_BONUS)
				end
				attacker.client.pers.teamState.basedefense += 1

				attacker.client.ps.persistant[C.PERS_DEFEND_COUNT] += 1
				G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", attacker.client.ps.clientNum, 3, attacker.client.pers.netname, "DEFENCE")
				if not level.hadBots then
					G.ChallengeMessage(attacker, CH_AWARD_DEFENCE)
				end
				-- add the sprite over the player's head
				clearAwardFlags(attacker.client)
				attacker.client.rewardTime = level.time + C.REWARD_SPRITE_TIME

				return -- Return so we don't recieve credits for point B also
			end -- We denfended point A
		end -- Defend point A

		if attacker.client.sess.sessionTeam == level.pointStatusB then -- Attack must defend point B
			-- See how close attacker and target was to Point B:
			Q.VectorSubtract(targ.r.currentOrigin, ddB.r.currentOrigin, v1)
			Q.VectorSubtract(attacker.r.currentOrigin, ddB.r.currentOrigin, v2)

			if ((Q.VectorLength(v1) < C.CTF_TARGET_PROTECT_RADIUS and
				G.trap_InPVS(ddB.r.currentOrigin, targ.r.currentOrigin)) or
				(Q.VectorLength(v2) < C.CTF_TARGET_PROTECT_RADIUS and
				G.trap_InPVS(ddB.r.currentOrigin, attacker.r.currentOrigin))) and
				attacker.client.sess.sessionTeam ~= targ.client.sess.sessionTeam then

				-- We defended point B
				-- Was we dominating and maybe close to score?
				if attacker.client.sess.sessionTeam == level.pointStatusA and level.time - level.timeTaken > (G.g_ddCaptureTime.integer - C.DD_CLOSE) * 1000 then
					G.AddScore(attacker, targ.r.currentOrigin, C.DD_POINT_DEFENCE_CLOSE_BONUS)
				else
					G.AddScore(attacker, targ.r.currentOrigin, C.DD_POINT_DEFENCE_BONUS)
				end
				attacker.client.pers.teamState.basedefense += 1

				attacker.client.ps.persistant[C.PERS_DEFEND_COUNT] += 1
				if not level.hadBots then
					G.ChallengeMessage(attacker, CH_AWARD_DEFENCE)
				end
				G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", attacker.client.ps.clientNum, 3, attacker.client.pers.netname, "DEFENCE")
				-- add the sprite over the player's head
				clearAwardFlags(attacker.client)
				attacker.client.rewardTime = level.time + C.REWARD_SPRITE_TIME

				return
			end -- We denfended point B
		end -- Defend point B
		return -- In double Domination we shall not go on, or we would test for team bases that we don't use
	end

	-- flag and flag carrier area defense bonuses

	-- we have to find the flag and carrier entities

	if G.g_gametype.integer == C.GT_OBELISK then
		-- find the team obelisk
		if attacker.client.sess.sessionTeam == C.TEAM_RED then
			c = "team_redobelisk"
		elseif attacker.client.sess.sessionTeam == C.TEAM_BLUE then
			c = "team_blueobelisk"
		else
			return
		end
	elseif G.g_gametype.integer == C.GT_HARVESTER then
		-- find the center obelisk
		c = "team_neutralobelisk"
	else
		-- find the flag
		if attacker.client.sess.sessionTeam == C.TEAM_RED then
			c = "team_CTF_redflag"
		elseif attacker.client.sess.sessionTeam == C.TEAM_BLUE then
			c = "team_CTF_blueflag"
		else
			return
		end
		-- find attacker's team's flag carrier
		for i = 0, G.g_maxclients.integer - 1 do
			carrier = G.g_entities[i]
			if carrier.inuse and carrier.client.ps.powerups[flag_pw] ~= 0 then
				break
			end
			carrier = nil
		end
	end
	local flag = nil
	while true do
		flag = G.G_Find(flag, "classname", c)
		if flag == nil then
			break
		end
		if bit32.band(flag.flags, C.FL_DROPPED_ITEM) == 0 then
			break
		end
	end

	if flag == nil then
		return -- can't find attacker's flag
	end

	-- ok we have the attackers flag and a pointer to the carrier

	-- check to see if we are defending the base's flag
	Q.VectorSubtract(targ.r.currentOrigin, flag.r.currentOrigin, v1)
	Q.VectorSubtract(attacker.r.currentOrigin, flag.r.currentOrigin, v2)

	if ((Q.VectorLength(v1) < C.CTF_TARGET_PROTECT_RADIUS and
		G.trap_InPVS(flag.r.currentOrigin, targ.r.currentOrigin)) or
		(Q.VectorLength(v2) < C.CTF_TARGET_PROTECT_RADIUS and
		G.trap_InPVS(flag.r.currentOrigin, attacker.r.currentOrigin))) and
		attacker.client.sess.sessionTeam ~= targ.client.sess.sessionTeam and G.g_gametype.integer ~= C.GT_ELIMINATION and
		(G.g_gametype.integer ~= C.GT_CTF_ELIMINATION or G.g_elimination_ctf_oneway.integer == 0 or
			((level.eliminationSides + level.roundNumber) % 2 == 0 and attacker.client.sess.sessionTeam == C.TEAM_BLUE) or
			((level.eliminationSides + level.roundNumber) % 2 == 1 and attacker.client.sess.sessionTeam == C.TEAM_RED)) then

		-- we defended the base flag
		G.AddScore(attacker, targ.r.currentOrigin, C.CTF_FLAG_DEFENSE_BONUS)
		attacker.client.pers.teamState.basedefense += 1

		attacker.client.ps.persistant[C.PERS_DEFEND_COUNT] += 1
		if not level.hadBots then
			G.ChallengeMessage(attacker, CH_AWARD_DEFENCE)
		end
		G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", attacker.client.ps.clientNum, 3, attacker.client.pers.netname, "DEFENCE")
		-- add the sprite over the player's head
		clearAwardFlags(attacker.client)
		attacker.client.rewardTime = level.time + C.REWARD_SPRITE_TIME

		return
	end

	if carrier ~= nil and carrier ~= attacker then
		Q.VectorSubtract(targ.r.currentOrigin, carrier.r.currentOrigin, v1)
		Q.VectorSubtract(attacker.r.currentOrigin, carrier.r.currentOrigin, v2)

		if ((Q.VectorLength(v1) < C.CTF_ATTACKER_PROTECT_RADIUS and
			G.trap_InPVS(carrier.r.currentOrigin, targ.r.currentOrigin)) or
			(Q.VectorLength(v2) < C.CTF_ATTACKER_PROTECT_RADIUS and
			G.trap_InPVS(carrier.r.currentOrigin, attacker.r.currentOrigin))) and
			attacker.client.sess.sessionTeam ~= targ.client.sess.sessionTeam then
			G.AddScore(attacker, targ.r.currentOrigin, C.CTF_CARRIER_PROTECT_BONUS)
			attacker.client.pers.teamState.carrierdefense += 1

			attacker.client.ps.persistant[C.PERS_DEFEND_COUNT] += 1
			if not level.hadBots then
				G.ChallengeMessage(attacker, CH_AWARD_DEFENCE)
			end
			G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", attacker.client.ps.clientNum, 3, attacker.client.pers.netname, "DEFENCE")
			-- add the sprite over the player's head
			clearAwardFlags(attacker.client)
			attacker.client.rewardTime = level.time + C.REWARD_SPRITE_TIME

			return
		end
	end
end

--[[
================
Team_CheckHurtCarrier

Check to see if attacker hurt the flag carrier.  Needed when handing out bonuses for assistance to flag
carrier defense.
================
]]
function G.Team_CheckHurtCarrier(targ, attacker)
	local flag_pw

	if targ.client == nil or attacker.client == nil then
		return
	end

	if targ.client.sess.sessionTeam == C.TEAM_RED then
		flag_pw = C.PW_BLUEFLAG
	else
		flag_pw = C.PW_REDFLAG
	end

	if G.g_gametype.integer == C.GT_1FCTF then
		flag_pw = C.PW_NEUTRALFLAG
	end

	-- flags
	if targ.client.ps.powerups[flag_pw] ~= 0 and
		targ.client.sess.sessionTeam ~= attacker.client.sess.sessionTeam then
		attacker.client.pers.teamState.lasthurtcarrier = G.level.time
	end

	-- skulls
	if targ.client.ps.generic1 ~= 0 and
		targ.client.sess.sessionTeam ~= attacker.client.sess.sessionTeam then
		attacker.client.pers.teamState.lasthurtcarrier = G.level.time
	end
end

function G.Team_ResetFlag(team)
	local c
	local rent = nil

	if team == C.TEAM_RED then
		c = "team_CTF_redflag"
	elseif team == C.TEAM_BLUE then
		c = "team_CTF_blueflag"
	elseif team == C.TEAM_FREE then
		c = "team_CTF_neutralflag"
	else
		return nil
	end

	local ent = nil
	while true do
		ent = G.G_Find(ent, "classname", c)
		if ent == nil then
			break
		end
		if bit32.band(ent.flags, C.FL_DROPPED_ITEM) ~= 0 then
			G.G_FreeEntity(ent)
		else
			rent = ent
			G.RespawnItem(ent)
		end
	end

	G.Team_SetFlagStatus(team, C.FLAG_ATBASE)

	return rent
end

-- Functions for Domination

function G.Team_Dom_SpawnPoints()
	local level = G.level
	local flag = nil

	if G.dominationPointsSpawned then
		return
	end
	G.dominationPointsSpawned = true

	local it = BG.BG_FindItem("Neutral domination point")
	if it == nil then
		G.PrintMsg(nil, "No domination item\n")
		return
	else
		G.PrintMsg(nil, "Domination item found\n")
	end
	local i = 0
	local c = "domination_point"

	while true do
		flag = G.G_Find(flag, "classname", c)
		if flag == nil then
			break
		end
		if i >= C.MAX_DOMINATION_POINTS then
			break
		end
		if flag.message ~= nil then
			level.domination_points_names[i] = QS.Q_strncpyz(flag.message, C.MAX_DOMINATION_POINTS_NAMES - 1)
			G.PrintMsg(nil, "Domination point '%s' found\n", level.domination_points_names[i])
		else
			level.domination_points_names[i] = QS.Q_strncpyz(QS.va("Point %i", i), C.MAX_DOMINATION_POINTS_NAMES - 1)
			G.PrintMsg(nil, "Domination point '%s' found (autonamed)\n", level.domination_points_names[i])
		end
		G.dom_points[i] = G.G_Spawn()
		Q.VectorCopy(flag.r.currentOrigin, G.dom_points[i].s.origin)
		G.dom_points[i].classname = it.classname
		G.G_SpawnItem(G.dom_points[i], it)
		G.FinishSpawningItem(G.dom_points[i])

		i += 1
	end
	level.domination_points_count = i
end

return nil
