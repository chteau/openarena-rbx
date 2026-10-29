--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_team.c, part 3 of 3).

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
-- Luau port of g_team.c part 3: team spawn points, team overlay info, obelisks.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_team")

-- challenge id from challenges.h (not provided by g_defs); value not checked
-- against challenges.h, which was unreadable when this file was ported
local AWARD_CAPTURE = 402

function G.SelectRandomEntity(classname)
	return G.SelectRandomEntityFilter(classname, nil)
end

local MAX_TEAM_SPAWN_POINTS = 32

-- shared body of the four SelectRandom*SpawnPoint loops
local function PickSpot(classname)
	local spots = {}
	local count = 0
	local spot = nil

	while true do
		spot = G.G_Find(spot, "classname", classname)
		if spot == nil then
			break
		end
		if G.SpotWouldTelefrag(spot) then
			continue
		end
		spots[count] = spot
		count += 1
		if count == MAX_TEAM_SPAWN_POINTS then
			break
		end
	end

	if count == 0 then
		return G.G_Find(nil, "classname", classname)
	end

	local selection = Q.imod(Q.rand(), count)
	return spots[selection]
end

function G.SelectRandomTeamSpawnPoint(teamstate, team)
	local classname

	if G.g_gametype.integer == C.GT_ELIMINATION then
		if Q.imod(G.level.roundNumber + G.level.eliminationSides, 2) == 1 then
			if team == C.TEAM_RED then
				team = C.TEAM_BLUE
			elseif team == C.TEAM_BLUE then
				team = C.TEAM_RED
			end
		end
	end

	if teamstate == C.TEAM_BEGIN then
		if team == C.TEAM_RED then
			classname = "team_CTF_redplayer"
		elseif team == C.TEAM_BLUE then
			classname = "team_CTF_blueplayer"
		else
			return nil
		end
	else
		if team == C.TEAM_RED then
			classname = "team_CTF_redspawn"
		elseif team == C.TEAM_BLUE then
			classname = "team_CTF_bluespawn"
		else
			return nil
		end
	end
	return PickSpot(classname)
end

function G.SelectRandomDDSpawnPoint()
	return PickSpot("info_player_dd")
end

function G.SelectRandomTeamDDSpawnPoint(team)
	local classname
	if team == C.TEAM_RED then
		classname = "info_player_dd_red"
	else
		classname = "info_player_dd_blue"
	end
	return PickSpot(classname)
end

function G.SelectRandomTeamDomSpawnPoint(team)
	local classname
	if team == C.TEAM_RED then
		classname = "info_player_dom_red"
	else
		classname = "info_player_dom_blue"
	end
	return PickSpot(classname)
end

function G.SelectCTFSpawnPoint(team, teamstate, origin, angles)
	local spot = G.SelectRandomTeamSpawnPoint(teamstate, team)

	if spot == nil then
		return G.SelectSpawnPoint(Q.vec3_origin, origin, angles, 0)
	end

	Q.VectorCopy(spot.s.origin, origin)
	origin[2] += 9
	Q.VectorCopy(spot.s.angles, angles)

	return spot
end

function G.SelectDoubleDominationSpawnPoint(team, origin, angles)
	local spot = G.SelectRandomTeamDDSpawnPoint(team)

	if spot == nil then
		spot = G.SelectRandomDDSpawnPoint()
	end

	if spot == nil then
		return G.SelectSpawnPoint(Q.vec3_origin, origin, angles, 0)
	end

	Q.VectorCopy(spot.s.origin, origin)
	origin[2] += 9
	Q.VectorCopy(spot.s.angles, angles)

	return spot
end

function G.SelectDominationSpawnPoint(team, origin, angles)
	local spot = G.SelectRandomTeamDomSpawnPoint(team)

	if spot == nil then
		return G.SelectSpawnPoint(Q.vec3_origin, origin, angles, 0)
	end

	Q.VectorCopy(spot.s.origin, origin)
	origin[2] += 9
	Q.VectorCopy(spot.s.angles, angles)

	return spot
end

function G.TeamplayInfoMessage(ent)
	local clients = {}
	local team

	if not ent.client.pers.teamInfo then
		return
	end

	if ent.client.sess.sessionTeam == C.TEAM_SPECTATOR then
		if ent.client.sess.spectatorState ~= C.SPECTATOR_FOLLOW or ent.client.sess.spectatorClient < 0 then
			return
		end
		team = G.g_entities[ent.client.sess.spectatorClient].client.sess.sessionTeam
	else
		team = ent.client.sess.sessionTeam
	end

	if team ~= C.TEAM_RED and team ~= C.TEAM_BLUE then
		return
	end

	local cnt = 0
	local i = 0
	while i < G.g_maxclients.integer and i < C.MAX_CLIENTS and cnt < C.TEAM_MAXOVERLAY do
		local player = G.g_entities[G.level.sortedClients[i]]
		if player.inuse and player.client.sess.sessionTeam == team then
			clients[cnt] = G.level.sortedClients[i]
			cnt += 1
		end
		i += 1
	end

	-- qsort with SortClients (ascending clientNum)
	for a = 1, cnt - 1 do
		local v = clients[a]
		local b = a - 1
		while b >= 0 and clients[b] - v > 0 do
			clients[b + 1] = clients[b]
			b -= 1
		end
		clients[b + 1] = v
	end

	local str = ""
	local stringlength = 0

	i = 0
	cnt = 0
	while i < G.g_maxclients.integer and i < C.MAX_GENTITIES and cnt < C.TEAM_MAXOVERLAY do
		local player = G.g_entities[i]
		if player.inuse and player.client.sess.sessionTeam == team then
			local h = player.client.ps.stats[C.STAT_HEALTH]
			local a = player.client.ps.stats[C.STAT_ARMOR]
			local w = player.client.ps.weapon
			if player.client.isEliminated then
				h = 0
				a = 0
				w = 0
			end
			if h < 0 then h = 0 end
			if a < 0 then a = 0 end

			local entry = QS.Com_sprintf(1024, " %i %i %i %i %i %i",
				i, player.client.pers.teamState.location, h, a,
				w, player.s.powerups)
			local j = #entry
			if stringlength + j > 8192 then
				break
			end
			str = str .. entry
			stringlength += j
			cnt += 1
		end
		i += 1
	end

	G.trap_SendServerCommand(ent.index, QS.va("tinfo %i %s", cnt, str))
end

function G.CheckTeamStatus()
	if G.level.time - G.level.lastTeamLocationTime > C.TEAM_LOCATION_UPDATE_TIME then
		G.level.lastTeamLocationTime = G.level.time

		for i = 0, G.g_maxclients.integer - 1 do
			local ent = G.g_entities[i]

			if ent.client.pers.connected ~= C.CON_CONNECTED then
				continue
			end

			if ent.inuse and (ent.client.sess.sessionTeam == C.TEAM_RED or ent.client.sess.sessionTeam == C.TEAM_BLUE) then
				local loc = G.Team_GetLocation(ent)
				if loc ~= nil then
					ent.client.pers.teamState.location = loc.health
				else
					ent.client.pers.teamState.location = 0
				end
			end
		end

		for i = 0, G.g_maxclients.integer - 1 do
			local ent = G.g_entities[i]

			if ent.client.pers.connected ~= C.CON_CONNECTED then
				continue
			end

			if ent.inuse then
				G.TeamplayInfoMessage(ent)
			end
		end
	end
end

function G.SP_team_CTF_redplayer(ent)
end

function G.SP_team_CTF_blueplayer(ent)
end

function G.SP_team_CTF_redspawn(ent)
end

function G.SP_team_CTF_bluespawn(ent)
end

function SF.ObeliskHealthChange(team, health)
	local currentPercentage
	local percentage = Q.idiv(health * 100, G.g_obeliskHealth.integer)
	if percentage < 0 then
		percentage = 0
	end
	currentPercentage = G.level.healthRedObelisk
	if team ~= C.TEAM_RED then
		currentPercentage = G.level.healthBlueObelisk
	end
	if percentage ~= currentPercentage then
		if team == C.TEAM_RED then
			G.level.healthRedObelisk = percentage
		else
			G.level.healthBlueObelisk = percentage
		end
		G.level.MustSendObeliskHealth = true
		G.ObeliskHealthMessage()
	end
end

function SF.ObeliskRegen(self)
	self.nextthink = G.level.time + G.g_obeliskRegenPeriod.integer * 1000
	SF.ObeliskHealthChange(self.spawnflags, self.health)
	if self.health >= G.g_obeliskHealth.integer then
		return
	end

	G.G_AddEvent(self, C.EV_POWERUP_REGEN, 0)
	self.health += G.g_obeliskRegenAmount.integer
	if self.health > G.g_obeliskHealth.integer then
		self.health = G.g_obeliskHealth.integer
	end

	self.activator.s.modelindex2 = Q.idiv(self.health * 0xff, G.g_obeliskHealth.integer)
	self.activator.s.frame = 0
end

function SF.ObeliskRespawn(self)
	self.takedamage = true
	self.health = G.g_obeliskHealth.integer

	self.think = SF.ObeliskRegen
	self.nextthink = G.level.time + G.g_obeliskRegenPeriod.integer * 1000

	self.activator.s.frame = 0
end

function SF.ObeliskDie(self, inflictor, attacker, damage, mod)
	local otherTeam = G.OtherTeam(self.spawnflags)
	G.AddTeamScore(self.s.pos.trBase, otherTeam, 1)
	G.Team_ForceGesture(otherTeam)

	G.CalculateRanks()

	self.takedamage = false
	self.think = SF.ObeliskRespawn
	self.nextthink = G.level.time + G.g_obeliskRespawnDelay.integer * 1000

	self.activator.s.modelindex2 = 0xff
	self.activator.s.frame = 2

	G.G_AddEvent(self.activator, C.EV_OBELISKEXPLODE, 0)

	G.AddScore(attacker, self.r.currentOrigin, C.CTF_CAPTURE_BONUS)

	-- add the sprite over the player's head
	local awards = bit32.bor(C.EF_AWARD_IMPRESSIVE, C.EF_AWARD_EXCELLENT, C.EF_AWARD_GAUNTLET, C.EF_AWARD_ASSIST, C.EF_AWARD_DEFEND, C.EF_AWARD_CAP)
	attacker.client.ps.eFlags = bit32.band(attacker.client.ps.eFlags, bit32.bnot(awards))
	attacker.client.ps.eFlags = bit32.bor(attacker.client.ps.eFlags, C.EF_AWARD_CAP)
	attacker.client.rewardTime = G.level.time + C.REWARD_SPRITE_TIME
	attacker.client.ps.persistant[C.PERS_CAPTURES] += 1
	G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", attacker.client.ps.clientNum, 4, attacker.client.pers.netname, "CAPTURE")
	G.G_LogPrintf("OBELISK: %i %i %i %i: %s destroyed the enemy obelisk.\n",
		attacker.client.ps.clientNum, attacker.client.sess.sessionTeam, 3, 0,
		attacker.client.pers.netname)
	if G.TeamCount(-1, C.TEAM_RED) ~= 0 and G.TeamCount(-1, C.TEAM_BLUE) ~= 0 and not G.level.hadBots then
		G.ChallengeMessage(attacker, AWARD_CAPTURE)
	end
	SF.ObeliskHealthChange(self.spawnflags, self.health)
	G.teamgame.redObeliskAttackedTime = 0
	G.teamgame.blueObeliskAttackedTime = 0
end

function SF.ObeliskTouch(self, other, trace)
	if other.client == nil then
		return
	end

	if G.OtherTeam(other.client.sess.sessionTeam) ~= self.spawnflags then
		return
	end

	local tokens = other.client.ps.generic1
	if tokens <= 0 then
		return
	end

	G.PrintMsg(nil, "%s^7 brought in %i %s.\n",
		other.client.pers.netname, tokens, if tokens == 1 then "skull" else "skulls")

	G.G_LogPrintf("HARVESTER: %i %i %i %i %i: %s brought in %i skull%s for %s\n",
		other.client.ps.clientNum, other.client.sess.sessionTeam, 0, -1, tokens,
		other.client.pers.netname, tokens, if tokens > 1 then "s" else "", G.TeamName(other.client.sess.sessionTeam))

	G.AddTeamScore(self.s.pos.trBase, other.client.sess.sessionTeam, tokens)
	G.Team_ForceGesture(other.client.sess.sessionTeam)

	G.AddScore(other, self.r.currentOrigin, C.CTF_CAPTURE_BONUS * tokens)

	-- add the sprite over the player's head
	local awards = bit32.bor(C.EF_AWARD_IMPRESSIVE, C.EF_AWARD_EXCELLENT, C.EF_AWARD_GAUNTLET, C.EF_AWARD_ASSIST, C.EF_AWARD_DEFEND, C.EF_AWARD_CAP)
	other.client.ps.eFlags = bit32.band(other.client.ps.eFlags, bit32.bnot(awards))
	other.client.ps.eFlags = bit32.bor(other.client.ps.eFlags, C.EF_AWARD_CAP)
	other.client.rewardTime = G.level.time + C.REWARD_SPRITE_TIME
	other.client.ps.persistant[C.PERS_CAPTURES] += tokens
	for i = 0, tokens - 1 do
		G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", other.client.ps.clientNum, 4, other.client.pers.netname, "CAPTURE")
		if G.TeamCount(-1, C.TEAM_RED) ~= 0 and G.TeamCount(-1, C.TEAM_BLUE) ~= 0 and not G.level.hadBots then
			G.ChallengeMessage(other, AWARD_CAPTURE)
		end
	end

	other.client.ps.generic1 = 0
	G.CalculateRanks()

	G.Team_CaptureFlagSound(self, self.spawnflags)
end

function SF.ObeliskPain(self, attacker, damage)
	local actualDamage = Q.idiv(damage, 10)
	if actualDamage <= 0 then
		actualDamage = 1
	end
	self.activator.s.modelindex2 = Q.idiv(self.health * 0xff, G.g_obeliskHealth.integer)
	if self.activator.s.frame == 0 then
		G.G_AddEvent(self, C.EV_OBELISKPAIN, 0)
	end
	self.activator.s.frame = 1
	G.AddScore(attacker, self.r.currentOrigin, actualDamage)
	G.G_LogPrintf("OBELISK: %i %i %i %i: %s dealt %i damage to the enemy obelisk.\n",
		attacker.client.ps.clientNum, attacker.client.sess.sessionTeam, 1, actualDamage,
		attacker.client.pers.netname, actualDamage)
end

function SF.SpawnObelisk(origin, team, spawnflags)
	local tr = S.trace_t()
	local dest = Q.vec3()

	local ent = G.G_Spawn()

	Q.VectorCopy(origin, ent.s.origin)
	Q.VectorCopy(origin, ent.s.pos.trBase)
	Q.VectorCopy(origin, ent.r.currentOrigin)

	Q.VectorSet(ent.r.mins, -15, -15, 0)
	Q.VectorSet(ent.r.maxs, 15, 15, 87)

	ent.s.eType = C.ET_GENERAL
	ent.flags = C.FL_NO_KNOCKBACK

	if G.g_gametype.integer == C.GT_OBELISK then
		ent.r.contents = C.CONTENTS_SOLID
		ent.takedamage = true
		ent.health = G.g_obeliskHealth.integer
		ent.die = SF.ObeliskDie
		ent.pain = SF.ObeliskPain
		ent.think = SF.ObeliskRegen
		ent.nextthink = G.level.time + G.g_obeliskRegenPeriod.integer * 1000
	end
	if G.g_gametype.integer == C.GT_HARVESTER then
		ent.r.contents = C.CONTENTS_TRIGGER
		ent.touch = SF.ObeliskTouch
	end

	if bit32.band(spawnflags, 1) ~= 0 then
		-- suspended
		G.G_SetOrigin(ent, ent.s.origin)
	else
		-- mappers like to put them exactly on the floor, but being coplanar
		-- will sometimes show up as starting in solid, so lif it up one pixel
		ent.s.origin[2] += 1

		-- drop to floor
		Q.VectorSet(dest, ent.s.origin[0], ent.s.origin[1], ent.s.origin[2] - 4096)
		G.trap_Trace(tr, ent.s.origin, ent.r.mins, ent.r.maxs, dest, ent.s.number, C.MASK_SOLID)
		if tr.startsolid then
			ent.s.origin[2] -= 1
			G.G_Printf("SpawnObelisk: %s startsolid at %s\n", ent.classname, G.vtos(ent.s.origin))

			ent.s.groundEntityNum = C.ENTITYNUM_NONE
			G.G_SetOrigin(ent, ent.s.origin)
		else
			-- allow to ride movers
			ent.s.groundEntityNum = tr.entityNum
			G.G_SetOrigin(ent, tr.endpos)
		end
	end

	ent.spawnflags = team

	G.trap_LinkEntity(ent)

	return ent
end

function G.SP_team_redobelisk(ent)
	if G.g_gametype.integer <= C.GT_TEAM or G.g_ffa_gt > 0 then
		G.G_FreeEntity(ent)
		return
	end
	ent.s.eType = C.ET_TEAM
	if G.g_gametype.integer == C.GT_OBELISK then
		local obelisk = SF.SpawnObelisk(ent.s.origin, C.TEAM_RED, ent.spawnflags)
		obelisk.activator = ent
		-- initial obelisk health value
		ent.s.modelindex2 = 0xff
		ent.s.frame = 0
	end
	if G.g_gametype.integer == C.GT_HARVESTER then
		local obelisk = SF.SpawnObelisk(ent.s.origin, C.TEAM_RED, ent.spawnflags)
		obelisk.activator = ent
	end
	ent.s.modelindex = C.TEAM_RED
	G.trap_LinkEntity(ent)
end

function G.SP_team_blueobelisk(ent)
	if G.g_gametype.integer <= C.GT_TEAM or G.g_ffa_gt > 0 then
		G.G_FreeEntity(ent)
		return
	end
	ent.s.eType = C.ET_TEAM
	if G.g_gametype.integer == C.GT_OBELISK then
		local obelisk = SF.SpawnObelisk(ent.s.origin, C.TEAM_BLUE, ent.spawnflags)
		obelisk.activator = ent
		-- initial obelisk health value
		ent.s.modelindex2 = 0xff
		ent.s.frame = 0
	end
	if G.g_gametype.integer == C.GT_HARVESTER then
		local obelisk = SF.SpawnObelisk(ent.s.origin, C.TEAM_BLUE, ent.spawnflags)
		obelisk.activator = ent
	end
	ent.s.modelindex = C.TEAM_BLUE
	G.trap_LinkEntity(ent)
end

function G.SP_team_neutralobelisk(ent)
	if G.g_gametype.integer ~= C.GT_1FCTF and G.g_gametype.integer ~= C.GT_HARVESTER and G.g_gametype.integer ~= C.GT_POSSESSION then
		G.G_FreeEntity(ent)
		return
	end
	ent.s.eType = C.ET_TEAM
	if G.g_gametype.integer == C.GT_HARVESTER then
		G.neutralObelisk = SF.SpawnObelisk(ent.s.origin, C.TEAM_FREE, ent.spawnflags)
		G.neutralObelisk.spawnflags = C.TEAM_FREE
	end
	ent.s.modelindex = C.TEAM_FREE
	G.trap_LinkEntity(ent)
end

function G.CheckObeliskAttack(obelisk, attacker)
	-- if this really is an obelisk
	if obelisk.die ~= SF.ObeliskDie then
		return false
	end

	-- if the attacker is a client
	if attacker.client == nil then
		return false
	end

	-- if the obelisk is on the same team as the attacker then don't hurt it
	if obelisk.spawnflags == attacker.client.sess.sessionTeam then
		return true
	end

	-- obelisk may be hurt

	-- if not played any sounds recently
	if (obelisk.spawnflags == C.TEAM_RED and
		G.teamgame.redObeliskAttackedTime < G.level.time - C.OVERLOAD_ATTACK_BASE_SOUND_TIME) or
		(obelisk.spawnflags == C.TEAM_BLUE and
		G.teamgame.blueObeliskAttackedTime < G.level.time - C.OVERLOAD_ATTACK_BASE_SOUND_TIME) then

		-- tell which obelisk is under attack
		local te = G.G_TempEntity(obelisk.s.pos.trBase, C.EV_GLOBAL_TEAM_SOUND)
		if obelisk.spawnflags == C.TEAM_RED then
			te.s.eventParm = C.GTS_REDOBELISK_ATTACKED
			G.teamgame.redObeliskAttackedTime = G.level.time
		else
			te.s.eventParm = C.GTS_BLUEOBELISK_ATTACKED
			G.teamgame.blueObeliskAttackedTime = G.level.time
		end
		te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_BROADCAST)
	end

	return false
end

return nil
