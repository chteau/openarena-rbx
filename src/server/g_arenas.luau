--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_arenas.c).

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
-- Luau port of OpenArena 0.8.8's g_arenas.c (gamecode 9e0f0c0). Single player tournament info and the victory podium.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SP_PODIUM_MODEL = "models/mapobjects/podium/podium4.md3" -- g_local.h

local podium1 = nil
local podium2 = nil
local podium3 = nil

function G.UpdateTournamentInfo()
	local level = G.level
	local player = nil
	local i = 0
	local accuracy, perfect
	local msg

	-- find the real player
	i = 0
	while i < level.maxclients do
		player = G.g_entities[i]
		if not player.inuse then
			i += 1
			continue
		end
		if bit32.band(player.r.svFlags, C.SVF_BOT) == 0 then
			break
		end
		i += 1
	end
	-- this should never happen!
	if player == nil or i == level.maxclients then
		return
	end
	local playerClientNum = i

	G.CalculateRanks()

	if level.clients[playerClientNum].sess.sessionTeam == C.TEAM_SPECTATOR then
		msg = QS.Com_sprintf(C.MAX_STRING_CHARS, "postgame %i %i 0 0 0 0 0 0", level.numNonSpectatorClients, playerClientNum)
	else
		if player.client.accuracy_shots ~= 0 then
			accuracy = Q.idiv(player.client.accuracy_hits * 100, player.client.accuracy_shots)
		else
			accuracy = 0
		end
		perfect = if level.clients[playerClientNum].ps.persistant[C.PERS_RANK] == 0 and player.client.ps.persistant[C.PERS_KILLED] == 0 then 1 else 0
		msg = QS.Com_sprintf(C.MAX_STRING_CHARS, "postgame %i %i %i %i %i %i %i %i", level.numNonSpectatorClients, playerClientNum, accuracy,
			player.client.ps.persistant[C.PERS_IMPRESSIVE_COUNT], player.client.ps.persistant[C.PERS_EXCELLENT_COUNT],
			player.client.ps.persistant[C.PERS_GAUNTLET_FRAG_COUNT], player.client.ps.persistant[C.PERS_SCORE],
			perfect)
	end

	local msglen = #msg
	i = 0
	while i < level.numNonSpectatorClients do
		local n = level.sortedClients[i]
		local buf = QS.Com_sprintf(32, " %i %i %i", n, level.clients[n].ps.persistant[C.PERS_RANK], level.clients[n].ps.persistant[C.PERS_SCORE])
		msglen += #buf
		if msglen >= C.MAX_STRING_CHARS then
			break
		end
		msg = msg .. buf
		i += 1
	end
	G.trap_SendConsoleCommand(C.EXEC_APPEND, msg)
end

local function SpawnModelOnVictoryPad(pad, offset, ent, place)
	local vec = Q.vec3()
	local f, r, u = Q.vec3(), Q.vec3(), Q.vec3()

	local body = G.G_Spawn()
	if body == nil then
		G.G_Printf("^1ERROR: out of gentities\n")
		return nil
	end

	body.classname = ent.client.pers.netname
	body.client = ent.client
	S.copy_entityState_t(body.s, ent.s)
	body.s.eType = C.ET_PLAYER -- could be ET_INVISIBLE
	body.s.eFlags = 0 -- clear EF_TALK, etc
	body.s.powerups = 0 -- clear powerups
	body.s.loopSound = 0 -- clear lava burning
	body.s.number = body.index
	body.timestamp = G.level.time
	body.physicsObject = true
	body.physicsBounce = 0 -- don't bounce
	body.s.event = 0
	body.s.pos.trType = C.TR_STATIONARY
	body.s.groundEntityNum = C.ENTITYNUM_WORLD
	body.s.legsAnim = C.LEGS_IDLE
	body.s.torsoAnim = C.TORSO_STAND
	if body.s.weapon == C.WP_NONE then
		body.s.weapon = C.WP_MACHINEGUN
	end
	if body.s.weapon == C.WP_GAUNTLET then
		body.s.torsoAnim = C.TORSO_STAND2
	end
	body.s.event = 0
	body.r.svFlags = ent.r.svFlags
	Q.VectorCopy(ent.r.mins, body.r.mins)
	Q.VectorCopy(ent.r.maxs, body.r.maxs)
	Q.VectorCopy(ent.r.absmin, body.r.absmin)
	Q.VectorCopy(ent.r.absmax, body.r.absmax)
	body.clipmask = bit32.bor(C.CONTENTS_SOLID, C.CONTENTS_PLAYERCLIP)
	body.r.contents = C.CONTENTS_BODY
	body.r.ownerNum = ent.r.ownerNum
	body.takedamage = false

	Q.VectorSubtract(G.level.intermission_origin, pad.r.currentOrigin, vec)
	Q.vectoangles(vec, body.s.apos.trBase)
	body.s.apos.trBase[C.PITCH] = 0
	body.s.apos.trBase[C.ROLL] = 0

	Q.AngleVectors(body.s.apos.trBase, f, r, u)
	Q.VectorMA(pad.r.currentOrigin, offset[0], f, vec)
	Q.VectorMA(vec, offset[1], r, vec)
	Q.VectorMA(vec, offset[2], u, vec)

	G.G_SetOrigin(body, vec)

	G.trap_LinkEntity(body)

	body.count = place

	return body
end

local function CelebrateStop(player)
	local anim
	if player.s.weapon == C.WP_GAUNTLET then
		anim = C.TORSO_STAND2
	else
		anim = C.TORSO_STAND
	end
	player.s.torsoAnim = bit32.bor(bit32.bxor(bit32.band(player.s.torsoAnim, C.ANIM_TOGGLEBIT), C.ANIM_TOGGLEBIT), anim)
end

local TIMER_GESTURE = (34 * 66 + 50)
local function CelebrateStart(player)
	player.s.torsoAnim = bit32.bor(bit32.bxor(bit32.band(player.s.torsoAnim, C.ANIM_TOGGLEBIT), C.ANIM_TOGGLEBIT), C.TORSO_GESTURE)
	player.nextthink = G.level.time + TIMER_GESTURE
	player.think = CelebrateStop

	G.G_AddEvent(player, C.EV_TAUNT, 0)
end

local offsetFirst = Q.vec3(0, 0, 74)
local offsetSecond = Q.vec3(-10, 60, 54)
local offsetThird = Q.vec3(-19, -60, 45)

local function PodiumPlacementThink(podium)
	local level = G.level
	local vec = Q.vec3()
	local origin = Q.vec3()
	local f, r, u = Q.vec3(), Q.vec3(), Q.vec3()

	podium.nextthink = level.time + 100

	Q.AngleVectors(level.intermission_angle, vec, nil, nil)
	Q.VectorMA(level.intermission_origin, G.trap_Cvar_VariableIntegerValue("g_podiumDist"), vec, origin)
	origin[2] -= G.trap_Cvar_VariableIntegerValue("g_podiumDrop")
	G.G_SetOrigin(podium, origin)

	local function place(pod, offset)
		Q.VectorSubtract(level.intermission_origin, podium.r.currentOrigin, vec)
		Q.vectoangles(vec, pod.s.apos.trBase)
		pod.s.apos.trBase[C.PITCH] = 0
		pod.s.apos.trBase[C.ROLL] = 0

		Q.AngleVectors(pod.s.apos.trBase, f, r, u)
		Q.VectorMA(podium.r.currentOrigin, offset[0], f, vec)
		Q.VectorMA(vec, offset[1], r, vec)
		Q.VectorMA(vec, offset[2], u, vec)

		G.G_SetOrigin(pod, vec)
	end

	if podium1 ~= nil then
		place(podium1, offsetFirst)
	end
	if podium2 ~= nil then
		place(podium2, offsetSecond)
	end
	if podium3 ~= nil then
		place(podium3, offsetThird)
	end
end

local function SpawnPodium()
	local level = G.level
	local vec = Q.vec3()
	local origin = Q.vec3()

	local podium = G.G_Spawn()
	if podium == nil then
		return nil
	end

	podium.classname = "podium"
	podium.s.eType = C.ET_GENERAL
	podium.s.number = podium.index
	podium.clipmask = C.CONTENTS_SOLID
	podium.r.contents = C.CONTENTS_SOLID
	podium.s.modelindex = G.G_ModelIndex(SP_PODIUM_MODEL)

	Q.AngleVectors(level.intermission_angle, vec, nil, nil)
	Q.VectorMA(level.intermission_origin, G.trap_Cvar_VariableIntegerValue("g_podiumDist"), vec, origin)
	origin[2] -= G.trap_Cvar_VariableIntegerValue("g_podiumDrop")
	G.G_SetOrigin(podium, origin)

	Q.VectorSubtract(level.intermission_origin, podium.r.currentOrigin, vec)
	podium.s.apos.trBase[C.YAW] = Q.f(G.vectoyaw(vec))
	G.trap_LinkEntity(podium)

	podium.think = PodiumPlacementThink
	podium.nextthink = level.time + 100
	return podium
end

function G.SpawnModelsOnVictoryPads()
	local level = G.level

	podium1 = nil
	podium2 = nil
	podium3 = nil

	local podium = SpawnPodium()

	local player = SpawnModelOnVictoryPad(podium, offsetFirst, G.g_entities[level.sortedClients[0]],
		bit32.band(level.clients[level.sortedClients[0]].ps.persistant[C.PERS_RANK], bit32.bnot(C.RANK_TIED_FLAG)))
	if player ~= nil then
		player.nextthink = level.time + 2000
		player.think = CelebrateStart
		podium1 = player
	end

	player = SpawnModelOnVictoryPad(podium, offsetSecond, G.g_entities[level.sortedClients[1]],
		bit32.band(level.clients[level.sortedClients[1]].ps.persistant[C.PERS_RANK], bit32.bnot(C.RANK_TIED_FLAG)))
	if player ~= nil then
		podium2 = player
	end

	if level.numNonSpectatorClients > 2 then
		player = SpawnModelOnVictoryPad(podium, offsetThird, G.g_entities[level.sortedClients[2]],
			bit32.band(level.clients[level.sortedClients[2]].ps.persistant[C.PERS_RANK], bit32.bnot(C.RANK_TIED_FLAG)))
		if player ~= nil then
			podium3 = player
		end
	end
end

function G.Svcmd_AbortPodium_f()
	if G.g_gametype.integer ~= C.GT_SINGLE_PLAYER then
		return
	end

	if podium1 ~= nil then
		podium1.nextthink = G.level.time
		podium1.think = CelebrateStop
	end
end

return nil
