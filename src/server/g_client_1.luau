--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_client.c, part 1 of 2).

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
-- Luau port of g_client.c, part 1 of 2. Client functions that don't happen every frame.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_client")

SF.playerMins = { [0] = -15, -15, -24 }
SF.playerMaxs = { [0] = 15, 15, 32 }

--[[QUAKED info_player_deathmatch (1 0 1) (-16 -16 -24) (16 16 32) initial
potential spawning position for deathmatch games.
The first time a player enters the game, they will be at an 'initial' spot.
Targets will be fired when someone spawns in on them.
"nobots" will prevent bots from using this spot.
"nohumans" will prevent non-bots from using this spot.
]]
function G.SP_info_player_deathmatch(ent)
	local _, i = G.G_SpawnInt("nobots", "0")
	if i ~= 0 then
		ent.flags = bit32.bor(ent.flags, C.FL_NO_BOTS)
	end
	_, i = G.G_SpawnInt("nohumans", "0")
	if i ~= 0 then
		ent.flags = bit32.bor(ent.flags, C.FL_NO_HUMANS)
	end
end

--[[QUAKED info_player_start (1 0 0) (-16 -16 -24) (16 16 32)
equivelant to info_player_deathmatch
]]
function G.SP_info_player_start(ent)
	ent.classname = "info_player_deathmatch"
	G.SP_info_player_deathmatch(ent)
end

--One for Standard Domination, not really a player spawn point
function G.SP_domination_point(ent)
end

--[[QUAKED info_player_intermission (1 0 1) (-16 -16 -24) (16 16 32)
The intermission will be viewed from this point.  Target an info_notnull for the view direction.
]]
function G.SP_info_player_intermission(ent)
end

--[[
=======================================================================

 SelectSpawnPoint

=======================================================================
]]

function G.SpotWouldTelefrag(spot)
	local mins = Q.vec3()
	local maxs = Q.vec3()
	local touch = {}

	Q.VectorAdd(spot.s.origin, SF.playerMins, mins)
	Q.VectorAdd(spot.s.origin, SF.playerMaxs, maxs)
	local num = G.trap_EntitiesInBox(mins, maxs, touch, C.MAX_GENTITIES)

	for i = 0, num - 1 do
		local hit = G.g_entities[touch[i]]
		--if ( hit->client && hit->client->ps.stats[STAT_HEALTH] > 0 ) {
		if hit.client ~= nil then
			return true
		end
	end

	return false
end

--[[
================
SelectNearestDeathmatchSpawnPoint

Find the spot that we DON'T want to use
================
]]
function G.SelectNearestDeathmatchSpawnPoint(from)
	local delta = Q.vec3()
	local nearestDist = 999999
	local nearestSpot = nil
	local spot = nil

	while true do
		spot = G.G_Find(spot, "classname", "info_player_deathmatch")
		if spot == nil then
			break
		end

		Q.VectorSubtract(spot.s.origin, from, delta)
		local dist = Q.VectorLength(delta)
		if dist < nearestDist then
			nearestDist = dist
			nearestSpot = spot
		end
	end

	return nearestSpot
end

--[[
 Pick a random info_player_deathmatch spawnpoint
 Will prefer a spot that wont telefrag if such a point exist.
 filter_flags Will NEVER pick a spawnpoint mathcing these flags.
 Returns a spot or nil if no spots exists.
]]
function SF.SelectRandomDeathmatchSpawnPoint(filter_flags)
	local spots = {}
	local count = 0
	local spot = nil
	local last_valid_spot = nil --Last valid spot although it might telefrag

	while true do
		spot = G.G_Find(spot, "classname", "info_player_deathmatch")
		if spot == nil then
			break
		end
		if bit32.band(spot.flags, filter_flags) ~= 0 then
			continue
		end
		last_valid_spot = spot
		if G.SpotWouldTelefrag(spot) then
			continue
		end
		spots[count] = spot
		count += 1
	end

	if count == 0 then -- no spots that won't telefrag
		return last_valid_spot
	end

	local selection = Q.imod(Q.rand(), count)
	return spots[selection]
end

--[[
===========
SelectSpawnPoint

Chooses a player start, deathmatch start, etc
============
]]
function G.SelectSpawnPoint(avoidPoint, origin, angles, filter_flags)
	local nearestSpot = G.SelectNearestDeathmatchSpawnPoint(avoidPoint)

	local spot = SF.SelectRandomDeathmatchSpawnPoint(filter_flags)
	if spot == nearestSpot then
		-- roll again if it would be real close to point of death
		spot = SF.SelectRandomDeathmatchSpawnPoint(filter_flags)
		if spot == nearestSpot then
			-- last try
			spot = SF.SelectRandomDeathmatchSpawnPoint(filter_flags)
		end
	end

	-- find a single player start spot
	if spot == nil then
		if G.g_cheats.integer ~= 0 then
			--If in developer mode: Crash to ensure that the developer discovers the problem.
			G.G_Error("Couldn't find a spawn point.\nAny map must contain at least one \"info_player_deathmatch\" with no spawn restrictions")
		end
		spot = G.g_entities[0]
	end

	Q.VectorCopy(spot.s.origin, origin)
	origin[2] += 9
	Q.VectorCopy(spot.s.angles, angles)

	return spot
end

--[[
===========
SelectInitialSpawnPoint

Try to find a spawn point marked 'initial', otherwise
use normal spawn selection.
============
]]
function SF.SelectInitialSpawnPoint(origin, angles, filter_flags)
	local spot = nil
	while true do
		spot = G.G_Find(spot, "classname", "info_player_deathmatch")
		if spot == nil then
			break
		end
		if bit32.band(spot.flags, filter_flags) == 0 then
			if bit32.band(spot.spawnflags, 1) ~= 0 then
				break
			end
		end
	end

	if spot == nil or G.SpotWouldTelefrag(spot) then
		return G.SelectSpawnPoint(Q.vec3_origin, origin, angles, filter_flags)
	end

	Q.VectorCopy(spot.s.origin, origin)
	origin[2] += 9
	Q.VectorCopy(spot.s.angles, angles)

	return spot
end

--[[
===========
SelectSpectatorSpawnPoint

============
]]
function SF.SelectSpectatorSpawnPoint(origin, angles)
	G.FindIntermissionPoint()

	Q.VectorCopy(G.level.intermission_origin, origin)
	Q.VectorCopy(G.level.intermission_angle, angles)

	return nil --spot;
end

--[[
=======================================================================

BODYQUE

=======================================================================
]]

function G.InitBodyQue()
	G.level.bodyQueIndex = 0
	for i = 0, C.BODY_QUEUE_SIZE - 1 do
		local ent = G.G_Spawn()
		ent.classname = "bodyque"
		ent.neverFree = true
		G.level.bodyQue[i] = ent
	end
end

--[[
=============
BodySink

After sitting around for five seconds, fall into the ground and dissapear
=============
]]
function G.BodySink(ent)
	if G.level.time - ent.timestamp > 6500 then
		-- the body ques are never actually freed, they are just unlinked
		G.trap_UnlinkEntity(ent)
		ent.physicsObject = false
		return
	end
	ent.nextthink = G.level.time + 100
	ent.s.pos.trBase[2] -= 1
end

--[[
=============
CopyToBodyQue

A player is respawning, so make an entity that looks
just like the existing corpse to leave behind.
=============
]]
function G.CopyToBodyQue(ent)
	local level = G.level

	G.trap_UnlinkEntity(ent)

	-- if client is in a nodrop area, don't leave the body
	local contents = G.trap_PointContents(ent.s.origin, -1)
	if bit32.band(contents, C.CONTENTS_NODROP) ~= 0 and bit32.band(ent.s.eFlags, C.EF_KAMIKAZE) == 0 then --the check for kamikaze is a workaround for ctf4ish
		return
	end

	-- grab a body que and cycle to the next one
	local body = level.bodyQue[level.bodyQueIndex]
	level.bodyQueIndex = Q.imod(level.bodyQueIndex + 1, C.BODY_QUEUE_SIZE)

	--Check if the next body has the kamikaze, in that case skip it.
	local i = 0
	while bit32.band(level.bodyQue[level.bodyQueIndex].s.eFlags, C.EF_KAMIKAZE) ~= 0 and i < 10 do
		level.bodyQueIndex = Q.imod(level.bodyQueIndex + 1, C.BODY_QUEUE_SIZE)
		i += 1
	end

	S.copy_entityState_t(body.s, ent.s)
	body.s.eFlags = C.EF_DEAD -- clear EF_TALK, etc
	if bit32.band(ent.s.eFlags, C.EF_KAMIKAZE) ~= 0 then
		ent.s.eFlags = bit32.band(ent.s.eFlags, bit32.bnot(C.EF_KAMIKAZE))
		body.s.eFlags = bit32.bor(body.s.eFlags, C.EF_KAMIKAZE)

		-- check if there is a kamikaze timer around for this owner
		for j = 0, level.num_entities - 1 do
			local e = G.g_entities[j]
			if not e.inuse then
				continue
			end
			if e.activator ~= ent then
				continue
			end
			if e.classname ~= "kamikaze timer" then
				continue
			end
			e.activator = body
			break
		end
	end
	body.s.powerups = 0 -- clear powerups
	body.s.loopSound = 0 -- clear lava burning
	body.s.number = body.index
	body.timestamp = level.time
	body.physicsObject = true
	body.physicsBounce = 0 -- don't bounce
	if body.s.groundEntityNum == C.ENTITYNUM_NONE then
		body.s.pos.trType = C.TR_GRAVITY
		body.s.pos.trTime = level.time
		Q.VectorCopy(ent.client.ps.velocity, body.s.pos.trDelta)
	else
		body.s.pos.trType = C.TR_STATIONARY
	end
	body.s.event = 0

	-- change the animation to the last-frame only, so the sequence
	-- doesn't repeat anew for the body
	local anim = bit32.band(body.s.legsAnim, bit32.bnot(C.ANIM_TOGGLEBIT))
	if anim == C.BOTH_DEATH1 or anim == C.BOTH_DEAD1 then
		body.s.legsAnim = C.BOTH_DEAD1
		body.s.torsoAnim = C.BOTH_DEAD1
	elseif anim == C.BOTH_DEATH2 or anim == C.BOTH_DEAD2 then
		body.s.legsAnim = C.BOTH_DEAD2
		body.s.torsoAnim = C.BOTH_DEAD2
	else
		body.s.legsAnim = C.BOTH_DEAD3
		body.s.torsoAnim = C.BOTH_DEAD3
	end

	body.r.svFlags = ent.r.svFlags
	Q.VectorCopy(ent.r.mins, body.r.mins)
	Q.VectorCopy(ent.r.maxs, body.r.maxs)
	Q.VectorCopy(ent.r.absmin, body.r.absmin)
	Q.VectorCopy(ent.r.absmax, body.r.absmax)

	body.clipmask = bit32.bor(C.CONTENTS_SOLID, C.CONTENTS_PLAYERCLIP)
	body.r.contents = C.CONTENTS_CORPSE
	body.r.ownerNum = ent.s.number

	body.nextthink = level.time + 5000
	body.think = G.BodySink

	body.die = G.body_die

	-- don't take more damage if already gibbed
	if ent.health <= C.GIB_HEALTH then
		body.takedamage = false
	else
		body.takedamage = true
	end

	Q.VectorCopy(body.s.pos.trBase, body.r.currentOrigin)
	G.trap_LinkEntity(body)
end

--======================================================================

function G.SetClientViewAngle(ent, angle)
	-- set the delta angle
	for i = 0, 2 do
		local cmdAngle = Q.ANGLE2SHORT(angle[i])
		ent.client.ps.delta_angles[i] = cmdAngle - ent.client.pers.cmd.angles[i]
	end
	Q.VectorCopy(angle, ent.s.angles)
	Q.VectorCopy(ent.s.angles, ent.client.ps.viewangles)
end

--[[
================
respawn
================
]]
function G.ClientRespawn(ent)
	local gt = G.g_gametype.integer

	if (gt ~= C.GT_ELIMINATION and gt ~= C.GT_CTF_ELIMINATION and gt ~= C.GT_LMS) and not ent.client.isEliminated then
		ent.client.isEliminated = true --must not be true in warmup
	else
		--Must always be false in other gametypes
		ent.client.isEliminated = false
	end
	G.CopyToBodyQue(ent) --Unlinks ent

	if G.g_gametype.integer == C.GT_LMS then
		if ent.client.pers.livesLeft > 0 then
			ent.client.isEliminated = false
		else --We have used all our lives
			if ent.client.isEliminated ~= true then
				ent.client.isEliminated = true
				if (G.g_lms_mode.integer == 2 or G.g_lms_mode.integer == 3) and G.level.roundNumber == G.level.roundNumberStarted then
					G.LMSpoint()
				end
				--Sago: This is really bad
				--TODO: Try not to make people spectators here
				ent.client.sess.spectatorState = C.SPECTATOR_FOLLOW
				ent.client.ps.pm_type = C.PM_SPECTATOR
				--We have to force spawn imidiantly to prevent lag.
				G.ClientSpawn(ent)
			end
			return
		end
	end

	if (gt == C.GT_ELIMINATION or gt == C.GT_CTF_ELIMINATION or gt == C.GT_LMS)
		and ent.client.ps.pm_type == C.PM_SPECTATOR and ent.client.ps.stats[C.STAT_HEALTH] > 0 then
		return
	end
	G.ClientSpawn(ent)

	-- add a teleportation effect
	if gt ~= C.GT_ELIMINATION and gt ~= C.GT_CTF_ELIMINATION and gt ~= C.GT_LMS then
		local tent = G.G_TempEntity(ent.client.ps.origin, C.EV_PLAYER_TELEPORT_IN)
		tent.s.clientNum = ent.s.clientNum
	end
end

--[[
================
respawnRound
================
]]
function G.respawnRound(ent)
	if ent.client.hook ~= nil then
		G.Weapon_HookFree(ent.client.hook)
	end

	G.trap_UnlinkEntity(ent)

	G.ClientSpawn(ent)

	-- add a teleportation effect
	local gt = G.g_gametype.integer
	if gt ~= C.GT_ELIMINATION and gt ~= C.GT_CTF_ELIMINATION and gt ~= C.GT_LMS then
		local tent = G.G_TempEntity(ent.client.ps.origin, C.EV_PLAYER_TELEPORT_IN)
		tent.s.clientNum = ent.s.clientNum
	end
end

--[[
================
TeamCvarSet

Sets the red and blue team client number cvars.
================
]]
function G.TeamCvarSet()
	local level = G.level
	local redChanged = false
	local blueChanged = false
	local first = true
	local temp = nil

	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end
		if level.clients[i].sess.sessionTeam == C.TEAM_RED then
			if first then
				temp = QS.va("%i", i)
				first = false
			else
				temp = QS.va("%s,%i", temp, i)
			end
		end
	end

	if not QS.Q_strequal(G.g_redTeamClientNumbers.string, temp or "") then
		redChanged = true
	end
	G.trap_Cvar_Set("g_redTeamClientNumbers", temp or "") --Set it right
	first = true

	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end
		if level.clients[i].sess.sessionTeam == C.TEAM_BLUE then
			if first then
				temp = QS.va("%i", i)
				first = false
			else
				temp = QS.va("%s,%i", temp, i)
			end
		end
	end
	if not QS.Q_strequal(G.g_blueTeamClientNumbers.string, temp or "") then
		blueChanged = true
	end
	G.trap_Cvar_Set("g_blueTeamClientNumbers", temp or "")

	--Note: We need to force update of the cvar or SendYourTeamMessage will send the old cvar value!
	if redChanged then
		G.trap_Cvar_Update(G.g_redTeamClientNumbers) --Force update of CVAR
		G.SendYourTeamMessageToTeam(C.TEAM_RED)
	end
	if blueChanged then
		G.trap_Cvar_Update(G.g_blueTeamClientNumbers)
		G.SendYourTeamMessageToTeam(C.TEAM_BLUE) --Force update of CVAR
	end
end

--[[
================
TeamCount

Returns number of players on a team
================
]]
function G.TeamCount(ignoreClientNum, team)
	local level = G.level
	local count = 0

	for i = 0, level.maxclients - 1 do
		if i == ignoreClientNum then
			continue
		end
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end

		if level.clients[i].pers.connected == C.CON_CONNECTING then
			continue
		end

		if level.clients[i].sess.sessionTeam == team then
			count += 1
		end
	end

	return count
end

--[[
================
TeamLivingCount

Returns number of living players on a team
================
]]
function G.TeamLivingCount(ignoreClientNum, team)
	local level = G.level
	local count = 0
	local isLMS = (G.g_gametype.integer == C.GT_LMS)

	for i = 0, level.maxclients - 1 do
		if i == ignoreClientNum then
			continue
		end
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end

		if level.clients[i].pers.connected == C.CON_CONNECTING then
			continue
		end
		--crash if g_gametype.integer is used here, why?
		if level.clients[i].sess.sessionTeam == team and (level.clients[i].ps.stats[C.STAT_HEALTH] > 0 or isLMS) and not level.clients[i].isEliminated then
			count += 1
		end
	end

	return count
end

function G.TeamLivingHumanCount(ignoreClientNum)
	local level = G.level
	local count = 0
	local isLMS = (G.g_gametype.integer == C.GT_LMS)

	for i = 0, level.maxclients - 1 do
		if i == ignoreClientNum then
			continue
		end
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end

		if level.clients[i].pers.connected == C.CON_CONNECTING then
			continue
		end
		if bit32.band(G.g_entities[i].r.svFlags, C.SVF_BOT) ~= 0 then
			continue
		end
		if level.clients[i].sess.sessionTeam == C.TEAM_SPECTATOR then
			continue
		end
		--crash if g_gametype.integer is used here, why?
		if (level.clients[i].ps.stats[C.STAT_HEALTH] > 0 or isLMS) and not level.clients[i].isEliminated then
			count += 1
		end
	end
	return count
end

function G.TeamHumanParticipantsCount(ignoreClientNum)
	local level = G.level
	local count = 0

	for i = 0, level.maxclients - 1 do
		if i == ignoreClientNum then
			continue
		end
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end

		if level.clients[i].pers.connected == C.CON_CONNECTING then
			continue
		end
		if bit32.band(G.g_entities[i].r.svFlags, C.SVF_BOT) ~= 0 then
			continue
		end
		if level.clients[i].sess.sessionTeam == C.TEAM_SPECTATOR then
			continue
		end
		count += 1
	end

	return count
end

--[[
================
TeamHealthCount

Count total number of healthpoints on teh teams used for draws in Elimination
================
]]
function G.TeamHealthCount(ignoreClientNum, team)
	local level = G.level
	local count = 0

	for i = 0, level.maxclients - 1 do
		if i == ignoreClientNum then
			continue
		end
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end

		if level.clients[i].pers.connected == C.CON_CONNECTING then
			continue
		end

		--only count clients with positive health
		if level.clients[i].sess.sessionTeam == team and (level.clients[i].ps.stats[C.STAT_HEALTH] > 0) and not level.clients[i].isEliminated then
			count += level.clients[i].ps.stats[C.STAT_HEALTH]
		end
	end

	return count
end

--[[
================
RespawnAll

Forces all clients to respawn.
================
]]
function G.RespawnAll()
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end

		if level.clients[i].pers.connected == C.CON_CONNECTING then
			continue
		end

		if level.clients[i].sess.sessionTeam == C.TEAM_SPECTATOR then
			continue
		end
		local client = G.g_entities[i]
		client.client.ps.pm_type = C.PM_NORMAL
		client.client.pers.livesLeft = G.g_lms_lives.integer
		G.respawnRound(client)
	end
end

--[[
================
RespawnDead

Forces all *DEAD* clients to respawn.
================
]]
function G.RespawnDead()
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end
		if level.clients[i].pers.connected == C.CON_CONNECTING then
			continue
		end
		local client = G.g_entities[i]
		client.client.pers.livesLeft = G.g_lms_lives.integer - 1
		if level.clients[i].isEliminated == false then
			continue
		end
		if level.clients[i].sess.sessionTeam == C.TEAM_SPECTATOR then
			continue
		end

		client.client.pers.livesLeft = G.g_lms_lives.integer

		G.respawnRound(client)
	end
end

--[[
================
DisableWeapons

disables all weapons
================
]]
function G.DisableWeapons()
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end
		if level.clients[i].pers.connected == C.CON_CONNECTING then
			continue
		end

		if level.clients[i].sess.sessionTeam == C.TEAM_SPECTATOR then
			continue
		end
		local client = G.g_entities[i]
		client.client.ps.pm_flags = bit32.bor(client.client.ps.pm_flags, C.PMF_ELIMWARMUP)
	end
	G.ProximityMine_RemoveAll() --Remove all the prox mines
end

--[[
================
EnableWeapons

enables all weapons
================
]]
function G.EnableWeapons()
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end

		if level.clients[i].sess.sessionTeam == C.TEAM_SPECTATOR then
			continue
		end

		local client = G.g_entities[i]
		client.client.ps.pm_flags = bit32.band(client.client.ps.pm_flags, bit32.bnot(C.PMF_ELIMWARMUP))
	end
end

--[[
================
LMSpoint

Gives a point to the lucky survivor
================
]]
function G.LMSpoint()
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end

		if level.clients[i].sess.sessionTeam == C.TEAM_SPECTATOR then
			continue
		end

		if level.clients[i].isEliminated then
			continue
		end

		local client = G.g_entities[i]

		client.client.ps.persistant[C.PERS_SCORE] += 1
		G.G_LogPrintf("PlayerScore: %i %i: %s now has %d points\n",
			i, client.client.ps.persistant[C.PERS_SCORE], client.client.pers.netname, client.client.ps.persistant[C.PERS_SCORE])
	end

	G.CalculateRanks()
end

--[[
================
TeamLeader

Returns the client number of the team leader
================
]]
function G.TeamLeader(team)
	local level = G.level
	for i = 0, level.maxclients - 1 do
		if level.clients[i].pers.connected == C.CON_DISCONNECTED then
			continue
		end
		if level.clients[i].sess.sessionTeam == team then
			if level.clients[i].sess.teamLeader then
				return i
			end
		end
	end

	return -1
end

--[[
================
PickTeam

================
]]
function G.PickTeam(ignoreClientNum)
	local level = G.level
	local counts = {}

	counts[C.TEAM_BLUE] = G.TeamCount(ignoreClientNum, C.TEAM_BLUE)
	counts[C.TEAM_RED] = G.TeamCount(ignoreClientNum, C.TEAM_RED)

	--KK-OAX Both Teams locked...forget about it, print an error message, keep as spec
	if level.RedTeamLocked and level.BlueTeamLocked then
		G.G_Printf("Both teams have been locked by the Admin! \n")
		return C.TEAM_NONE
	end
	if (counts[C.TEAM_BLUE] > counts[C.TEAM_RED]) and not level.RedTeamLocked then
		return C.TEAM_RED
	end
	if (counts[C.TEAM_RED] > counts[C.TEAM_BLUE]) and not level.BlueTeamLocked then
		return C.TEAM_BLUE
	end
	-- equal team count, so join the team with the lowest score
	if (level.teamScores[C.TEAM_BLUE] > level.teamScores[C.TEAM_RED]) and not level.RedTeamLocked then
		return C.TEAM_RED
	end
	if (level.teamScores[C.TEAM_RED] > level.teamScores[C.TEAM_BLUE]) and not level.BlueTeamLocked then
		return C.TEAM_BLUE
	end
	--KK-OAX Force Team Blue?
	return C.TEAM_BLUE
end

--[[
===========
ClientCleanName
============
]]
function SF.ClientCleanName(inStr, outSize, clientNum)
	local out = ""
	local outpos = 0
	local colorlessLen = 0
	local spaces = 0
	local notblack = 0
	local black = false
	local ip = 1
	local space = string.byte(" ")
	local escape = string.byte("^")

	-- discard leading spaces
	while string.byte(inStr, ip) == space do
		ip += 1
	end

	while ip <= #inStr and outpos < outSize - 1 do
		local ch = string.byte(inStr, ip)
		out = string.sub(out, 1, outpos) .. string.char(ch)

		local skip = false
		if ch == space then
			-- don't allow too many consecutive spaces
			if spaces > 2 then
				skip = true
			else
				spaces += 1
			end
		elseif outpos > 0 and string.byte(out, outpos) == escape then
			if QS.Q_IsColorString(out, outpos) then
				colorlessLen -= 1

				if QS.ColorIndex(ch) == 0 then
					-- Disallow color black in names to prevent players
					-- from getting advantage playing in front of black backgrounds
					black = true
				else
					black = false
				end
			else
				spaces = 0
				colorlessLen += 1
			end
		else
			spaces = 0
			colorlessLen += 1
			if not black and (QS.Q_isalpha(ch) or (ch >= string.byte("0") and ch <= string.byte("9"))) then
				notblack += 1
			end
		end

		if not skip then
			outpos += 1
		end
		ip += 1
	end

	out = string.sub(out, 1, outpos)

	--There was none not-black alphanum chars. Remove all colors
	if notblack < 1 then
		out = QS.Q_CleanStr(out)
	end

	-- don't allow empty names
	if out == "" or colorlessLen == 0 then
		out = QS.Q_strncpyz(QS.va("Nameless%i", clientNum), outSize)
	end

	return out
end

return nil
