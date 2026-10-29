--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_mover.c).

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
-- Luau port of OpenArena 0.8.8's g_mover.c (gamecode 9e0f0c0), part 2 of 2: door triggers, doors, plats, buttons, trains, static/rotating/bobbing/pendulum movers.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_mover")

local TRAIN_START_ON = 1
local TRAIN_TOGGLE = 2
local TRAIN_BLOCK_STOPS = 4

function SF.Touch_DoorTriggerSpectator(ent, other, trace)
	local axis = ent.count
	-- the constants below relate to constants in Think_SpawnNewDoorTrigger()
	local doorMin = ent.r.absmin[axis] + 100
	local doorMax = ent.r.absmax[axis] - 100
	local origin = Q.vec3()

	Q.VectorCopy(other.client.ps.origin, origin)

	if origin[axis] < doorMin or origin[axis] > doorMax then
		return
	end

	if math.abs(origin[axis] - doorMax) < math.abs(origin[axis] - doorMin) then
		origin[axis] = doorMin - 10
	else
		origin[axis] = doorMax + 10
	end

	G.TeleportPlayer(other, origin, G.tv(10000000.0, 0, 0))
end

function G.Touch_DoorTrigger(ent, other, trace)
	if other.client ~= nil and (other.client.sess.sessionTeam == C.TEAM_SPECTATOR or other.client.ps.pm_type == C.PM_SPECTATOR) then
		-- if the door is not open and not opening
		if ent.parent.moverState ~= C.MOVER_1TO2 and ent.parent.moverState ~= C.MOVER_POS2 then
			SF.Touch_DoorTriggerSpectator(ent, other, trace)
		end
	elseif ent.parent.moverState ~= C.MOVER_1TO2 then
		G.Use_BinaryMover(ent.parent, ent, other)
	end
end

function G.Think_SpawnNewDoorTrigger(ent)
	local other
	local mins = Q.vec3()
	local maxs = Q.vec3()
	local best

	-- set all of the slaves as shootable
	other = ent
	while other ~= nil do
		other.takedamage = true
		other = other.teamchain
	end

	-- find the bounds of everything on the team
	Q.VectorCopy(ent.r.absmin, mins)
	Q.VectorCopy(ent.r.absmax, maxs)

	other = ent.teamchain
	while other ~= nil do
		Q.AddPointToBounds(other.r.absmin, mins, maxs)
		Q.AddPointToBounds(other.r.absmax, mins, maxs)
		other = other.teamchain
	end

	-- find the thinnest axis, which will be the one we expand
	best = 0
	for i = 1, 2 do
		if maxs[i] - mins[i] < maxs[best] - mins[best] then
			best = i
		end
	end
	maxs[best] += 120
	mins[best] -= 120

	-- create a trigger with this size
	other = G.G_Spawn()
	other.classname = "door_trigger"
	Q.VectorCopy(mins, other.r.mins)
	Q.VectorCopy(maxs, other.r.maxs)
	other.parent = ent
	other.r.contents = C.CONTENTS_TRIGGER
	other.touch = G.Touch_DoorTrigger
	-- remember the thinnest axis
	other.count = best
	G.trap_LinkEntity(other)

	G.MatchTeam(ent, ent.moverState, G.level.time)
end

function G.Think_MatchTeam(ent)
	G.MatchTeam(ent, ent.moverState, G.level.time)
end

function G.SP_func_door(ent)
	local abs_movedir = Q.vec3()
	local distance
	local size = Q.vec3()
	local lip

	ent.sound1to2 = G.G_SoundIndex("sound/movers/doors/dr1_strt.wav")
	ent.sound2to1 = ent.sound1to2
	ent.soundPos1 = G.G_SoundIndex("sound/movers/doors/dr1_end.wav")
	ent.soundPos2 = ent.soundPos1

	ent.blocked = G.Blocked_Door

	-- default speed of 400
	if ent.speed == 0 then
		ent.speed = 400
	end

	-- default wait of 2 seconds
	if ent.wait == 0 then
		ent.wait = 2
	end
	ent.wait *= 1000

	-- default lip of 8 units
	local _
	_, lip = G.G_SpawnFloat("lip", "8")

	-- default damage of 2 points
	_, ent.damage = G.G_SpawnInt("dmg", "2")

	-- first position at start
	Q.VectorCopy(ent.s.origin, ent.pos1)

	-- calculate second position
	G.trap_SetBrushModel(ent, ent.model)
	G.G_SetMovedir(ent.s.angles, ent.movedir)
	abs_movedir[0] = math.abs(ent.movedir[0])
	abs_movedir[1] = math.abs(ent.movedir[1])
	abs_movedir[2] = math.abs(ent.movedir[2])
	Q.VectorSubtract(ent.r.maxs, ent.r.mins, size)
	distance = Q.DotProduct(abs_movedir, size) - lip
	Q.VectorMA(ent.pos1, distance, ent.movedir, ent.pos2)

	-- if "start_open", reverse position 1 and 2
	if bit32.band(ent.spawnflags, 1) ~= 0 then
		local temp = Q.vec3()

		Q.VectorCopy(ent.pos2, temp)
		Q.VectorCopy(ent.s.origin, ent.pos2)
		Q.VectorCopy(temp, ent.pos1)
	end

	G.InitMover(ent)

	ent.nextthink = G.level.time + C.FRAMETIME

	if bit32.band(ent.flags, C.FL_TEAMSLAVE) == 0 then
		local health

		_, health = G.G_SpawnInt("health", "0")
		if health ~= 0 then
			ent.takedamage = true
		end
		if ent.targetname ~= nil or health ~= 0 then
			-- non touch/shoot doors
			ent.think = G.Think_MatchTeam
		else
			ent.think = G.Think_SpawnNewDoorTrigger
		end
	end
end

function G.Touch_Plat(ent, other, trace)
	if other.client == nil or other.client.ps.stats[C.STAT_HEALTH] <= 0 then
		return
	end

	-- delay return-to-pos1 by one second
	if ent.moverState == C.MOVER_POS2 then
		ent.nextthink = G.level.time + 1000
	end
end

function G.Touch_PlatCenterTrigger(ent, other, trace)
	if other.client == nil then
		return
	end

	if ent.parent.moverState == C.MOVER_POS1 then
		G.Use_BinaryMover(ent.parent, ent, other)
	end
end

function G.SpawnPlatTrigger(ent)
	local trigger
	local tmin = Q.vec3()
	local tmax = Q.vec3()

	-- the middle trigger will be a thin trigger just
	-- above the starting position
	trigger = G.G_Spawn()
	trigger.classname = "plat_trigger"
	trigger.touch = G.Touch_PlatCenterTrigger
	trigger.r.contents = C.CONTENTS_TRIGGER
	trigger.parent = ent

	tmin[0] = ent.pos1[0] + ent.r.mins[0] + 33
	tmin[1] = ent.pos1[1] + ent.r.mins[1] + 33
	tmin[2] = ent.pos1[2] + ent.r.mins[2]

	tmax[0] = ent.pos1[0] + ent.r.maxs[0] - 33
	tmax[1] = ent.pos1[1] + ent.r.maxs[1] - 33
	tmax[2] = ent.pos1[2] + ent.r.maxs[2] + 8

	if tmax[0] <= tmin[0] then
		tmin[0] = ent.pos1[0] + (ent.r.mins[0] + ent.r.maxs[0]) * 0.5
		tmax[0] = tmin[0] + 1
	end
	if tmax[1] <= tmin[1] then
		tmin[1] = ent.pos1[1] + (ent.r.mins[1] + ent.r.maxs[1]) * 0.5
		tmax[1] = tmin[1] + 1
	end

	Q.VectorCopy(tmin, trigger.r.mins)
	Q.VectorCopy(tmax, trigger.r.maxs)

	G.trap_LinkEntity(trigger)
end

function G.SP_func_plat(ent)
	local lip, height
	local _

	ent.sound1to2 = G.G_SoundIndex("sound/movers/plats/pt1_strt.wav")
	ent.sound2to1 = ent.sound1to2
	ent.soundPos1 = G.G_SoundIndex("sound/movers/plats/pt1_end.wav")
	ent.soundPos2 = ent.soundPos1

	Q.VectorClear(ent.s.angles)

	_, ent.speed = G.G_SpawnFloat("speed", "200")
	_, ent.damage = G.G_SpawnInt("dmg", "2")
	_, ent.wait = G.G_SpawnFloat("wait", "1")
	_, lip = G.G_SpawnFloat("lip", "8")

	ent.wait = 1000

	-- create second position
	G.trap_SetBrushModel(ent, ent.model)

	local found
	found, height = G.G_SpawnFloat("height", "0")
	if not found then
		height = (ent.r.maxs[2] - ent.r.mins[2]) - lip
	end

	-- pos1 is the rest (bottom) position, pos2 is the top
	Q.VectorCopy(ent.s.origin, ent.pos2)
	Q.VectorCopy(ent.pos2, ent.pos1)
	ent.pos1[2] -= height

	G.InitMover(ent)

	-- touch function keeps the plat from returning while
	-- a live player is standing on it
	ent.touch = G.Touch_Plat

	ent.blocked = G.Blocked_Door

	ent.parent = ent -- so it can be treated as a door

	-- spawn the trigger if one hasn't been custom made
	if ent.targetname == nil then
		G.SpawnPlatTrigger(ent)
	end
end

function G.Touch_Button(ent, other, trace)
	if other.client == nil then
		return
	end

	if ent.moverState == C.MOVER_POS1 then
		G.Use_BinaryMover(ent, other, other)
	end
end

function G.SP_func_button(ent)
	local abs_movedir = Q.vec3()
	local distance
	local size = Q.vec3()
	local lip
	local _

	ent.sound1to2 = G.G_SoundIndex("sound/movers/switches/butn2.wav")

	if ent.speed == 0 then
		ent.speed = 40
	end

	if ent.wait == 0 then
		ent.wait = 1
	end
	ent.wait *= 1000

	-- first position
	Q.VectorCopy(ent.s.origin, ent.pos1)

	-- calculate second position
	G.trap_SetBrushModel(ent, ent.model)

	_, lip = G.G_SpawnFloat("lip", "4")

	G.G_SetMovedir(ent.s.angles, ent.movedir)
	abs_movedir[0] = math.abs(ent.movedir[0])
	abs_movedir[1] = math.abs(ent.movedir[1])
	abs_movedir[2] = math.abs(ent.movedir[2])
	Q.VectorSubtract(ent.r.maxs, ent.r.mins, size)
	distance = abs_movedir[0] * size[0] + abs_movedir[1] * size[1] + abs_movedir[2] * size[2] - lip
	Q.VectorMA(ent.pos1, distance, ent.movedir, ent.pos2)

	if ent.health ~= 0 then
		-- shootable button
		ent.takedamage = true
	else
		-- touchable button
		ent.touch = G.Touch_Button
	end

	G.InitMover(ent)
end

function G.Think_BeginMoving(ent)
	ent.s.pos.trTime = G.level.time
	ent.s.pos.trType = C.TR_LINEAR_STOP
end

function G.Reached_Train(ent)
	local next
	local speed
	local move = Q.vec3()
	local length

	-- copy the apropriate values
	next = ent.nextTrain
	if next == nil or next.nextTrain == nil then
		return -- just stop
	end

	-- fire all other targets
	G.G_UseTargets(next, nil)

	-- set the new trajectory
	ent.nextTrain = next.nextTrain
	Q.VectorCopy(next.s.origin, ent.pos1)
	Q.VectorCopy(next.nextTrain.s.origin, ent.pos2)

	-- if the path_corner has a speed, use that
	if next.speed ~= 0 then
		speed = next.speed
	else
		-- otherwise use the train's speed
		speed = ent.speed
	end
	if speed < 1 then
		speed = 1
	end

	-- calculate duration
	Q.VectorSubtract(ent.pos2, ent.pos1, move)
	length = Q.VectorLength(move)

	ent.s.pos.trDuration = Q.trunc(length * 1000 / speed)

	-- Tequila comment: Be sure to send to clients after any fast move case
	ent.r.svFlags = bit32.band(ent.r.svFlags, bit32.bnot(C.SVF_NOCLIENT))

	-- Tequila comment: Fast move case
	if ent.s.pos.trDuration < 1 then
		-- Tequila comment: As trDuration is used later in a division, we need to avoid that case now
		-- With null trDuration,
		-- the calculated rocks bounding box becomes infinite and the engine think for a short time
		-- any entity is riding that mover but not the world entity... In rare case, I found it
		-- can also stuck every map entities after func_door are used.
		-- The desired effect with very very big speed is to have instant move, so any not null duration
		-- lower than a frame duration should be sufficient.
		-- Afaik, the negative case don't have to be supported.
		ent.s.pos.trDuration = 1

		-- Tequila comment: Don't send entity to clients so it becomes really invisible
		ent.r.svFlags = bit32.bor(ent.r.svFlags, C.SVF_NOCLIENT)
	end

	-- looping sound
	ent.s.loopSound = next.soundLoop

	-- start it going
	G.SetMoverState(ent, C.MOVER_1TO2, G.level.time)

	-- if there is a "wait" value on the target, don't start moving yet
	if next.wait ~= 0 then
		ent.nextthink = G.level.time + Q.trunc(next.wait * 1000)
		ent.think = G.Think_BeginMoving
		ent.s.pos.trType = C.TR_STATIONARY
	end
end

function G.Think_SetupTrainTargets(ent)
	local path, next, start

	ent.nextTrain = G.G_Find(nil, "targetname", ent.target)
	if ent.nextTrain == nil then
		G.G_Printf("func_train at %s with an unfound target\n", G.vtos(ent.r.absmin))
		return
	end

	start = nil
	path = ent.nextTrain
	while path ~= start do
		if start == nil then
			start = path
		end

		if path.target == nil then
			G.G_Printf("Train corner at %s without a target\n", G.vtos(path.s.origin))
			return
		end

		-- find a path_corner among the targets
		-- there may also be other targets that get fired when the corner
		-- is reached
		next = nil
		repeat
			next = G.G_Find(next, "targetname", path.target)
			if next == nil then
				G.G_Printf("Train corner at %s without a target path_corner\n", G.vtos(path.s.origin))
				return
			end
		until next.classname == "path_corner"

		path.nextTrain = next
		path = next
	end

	-- start the train moving from the first corner
	G.Reached_Train(ent)
end

function G.SP_path_corner(self)
	if self.targetname == nil then
		G.G_Printf("path_corner with no targetname at %s\n", G.vtos(self.s.origin))
		G.G_FreeEntity(self)
		return
	end
	-- path corners don't need to be linked in
end

function G.SP_func_train(self)
	Q.VectorClear(self.s.angles)

	if bit32.band(self.spawnflags, TRAIN_BLOCK_STOPS) ~= 0 then
		self.damage = 0
	else
		if self.damage == 0 then
			self.damage = 2
		end
	end

	if self.speed == 0 then
		self.speed = 100
	end

	if self.target == nil then
		G.G_Printf("func_train without a target at %s\n", G.vtos(self.r.absmin))
		G.G_FreeEntity(self)
		return
	end

	G.trap_SetBrushModel(self, self.model)
	G.InitMover(self)

	self.reached = G.Reached_Train

	-- start trains on the second frame, to make sure their targets have had
	-- a chance to spawn
	self.nextthink = G.level.time + C.FRAMETIME
	self.think = G.Think_SetupTrainTargets
end

function G.SP_func_static(ent)
	G.trap_SetBrushModel(ent, ent.model)
	G.InitMover(ent)
	Q.VectorCopy(ent.s.origin, ent.s.pos.trBase)
	Q.VectorCopy(ent.s.origin, ent.r.currentOrigin)
end

function G.SP_func_rotating(ent)
	if ent.speed == 0 then
		ent.speed = 100
	end

	-- set the axis of rotation
	ent.s.apos.trType = C.TR_LINEAR
	if bit32.band(ent.spawnflags, 4) ~= 0 then
		ent.s.apos.trDelta[2] = Q.f(ent.speed)
	elseif bit32.band(ent.spawnflags, 8) ~= 0 then
		ent.s.apos.trDelta[0] = Q.f(ent.speed)
	else
		ent.s.apos.trDelta[1] = Q.f(ent.speed)
	end

	if ent.damage == 0 then
		ent.damage = 2
	end

	G.trap_SetBrushModel(ent, ent.model)
	G.InitMover(ent)

	Q.VectorCopy(ent.s.origin, ent.s.pos.trBase)
	Q.VectorCopy(ent.s.pos.trBase, ent.r.currentOrigin)
	Q.VectorCopy(ent.s.apos.trBase, ent.r.currentAngles)

	G.trap_LinkEntity(ent)
end

function G.SP_func_bobbing(ent)
	local height
	local phase
	local _

	_, ent.speed = G.G_SpawnFloat("speed", "4")
	_, height = G.G_SpawnFloat("height", "32")
	_, ent.damage = G.G_SpawnInt("dmg", "2")
	_, phase = G.G_SpawnFloat("phase", "0")

	G.trap_SetBrushModel(ent, ent.model)
	G.InitMover(ent)

	Q.VectorCopy(ent.s.origin, ent.s.pos.trBase)
	Q.VectorCopy(ent.s.origin, ent.r.currentOrigin)

	ent.s.pos.trDuration = Q.trunc(ent.speed * 1000)
	ent.s.pos.trTime = Q.trunc(ent.s.pos.trDuration * phase)
	ent.s.pos.trType = C.TR_SINE

	-- set the axis of bobbing
	if bit32.band(ent.spawnflags, 1) ~= 0 then
		ent.s.pos.trDelta[0] = Q.f(height)
	elseif bit32.band(ent.spawnflags, 2) ~= 0 then
		ent.s.pos.trDelta[1] = Q.f(height)
	else
		ent.s.pos.trDelta[2] = Q.f(height)
	end
end

function G.SP_func_pendulum(ent)
	local freq
	local length
	local phase
	local speed
	local _

	_, speed = G.G_SpawnFloat("speed", "30")
	_, ent.damage = G.G_SpawnInt("dmg", "2")
	_, phase = G.G_SpawnFloat("phase", "0")

	G.trap_SetBrushModel(ent, ent.model)

	-- find pendulum length
	length = math.abs(ent.r.mins[2])
	if length < 8 then
		length = 8
	end

	freq = 1 / (Q.M_PI * 2) * math.sqrt(G.g_gravity.value * G.g_gravityModifier.value / (3 * length))

	ent.s.pos.trDuration = Q.trunc(1000 / freq)

	G.InitMover(ent)

	Q.VectorCopy(ent.s.origin, ent.s.pos.trBase)
	Q.VectorCopy(ent.s.origin, ent.r.currentOrigin)

	Q.VectorCopy(ent.s.angles, ent.s.apos.trBase)

	ent.s.apos.trDuration = Q.trunc(1000 / freq)
	ent.s.apos.trTime = Q.trunc(ent.s.apos.trDuration * phase)
	ent.s.apos.trType = C.TR_SINE
	ent.s.apos.trDelta[2] = Q.f(speed)
end

return nil
