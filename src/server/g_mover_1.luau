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
-- Luau port of OpenArena 0.8.8's g_mover.c (gamecode 9e0f0c0), part 1 of 2. Pushmove, general movers, binary mover and door blocking.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_mover")

--[[
===============================================================================

PUSHMOVE

===============================================================================
]]

-- pushed_t pushed[MAX_GENTITIES], *pushed_p; pushed_p is an index into pushed
local pushed = {}
for i = 0, C.MAX_GENTITIES - 1 do
	pushed[i] = { ent = nil, origin = Q.vec3(), angles = Q.vec3(), deltayaw = 0 }
end
local pushed_p = 0

--[[
============
G_TestEntityPosition

============
]]
function G.G_TestEntityPosition(ent)
	local tr = S.trace_t()
	local mask

	if ent.clipmask ~= 0 then
		mask = ent.clipmask
	else
		mask = C.MASK_SOLID
	end
	if ent.client ~= nil then
		G.trap_Trace(tr, ent.client.ps.origin, ent.r.mins, ent.r.maxs, ent.client.ps.origin, ent.s.number, mask)
	else
		G.trap_Trace(tr, ent.s.pos.trBase, ent.r.mins, ent.r.maxs, ent.s.pos.trBase, ent.s.number, mask)
	end

	if tr.startsolid then
		return G.g_entities[tr.entityNum]
	end

	return nil
end

--[[
================
G_CreateRotationMatrix
================
]]
function G.G_CreateRotationMatrix(angles, matrix)
	Q.AngleVectors(angles, matrix[0], matrix[1], matrix[2])
	Q.VectorInverse(matrix[1])
end

--[[
================
G_TransposeMatrix
================
]]
function G.G_TransposeMatrix(matrix, transpose)
	for i = 0, 2 do
		for j = 0, 2 do
			transpose[i][j] = matrix[j][i]
		end
	end
end

--[[
================
G_RotatePoint
================
]]
function G.G_RotatePoint(point, matrix)
	local tvec = Q.vec3()

	Q.VectorCopy(point, tvec)
	point[0] = Q.DotProduct(matrix[0], tvec)
	point[1] = Q.DotProduct(matrix[1], tvec)
	point[2] = Q.DotProduct(matrix[2], tvec)
end

--[[
==================
G_TryPushingEntity

Returns qfalse if the move is blocked
==================
]]
function G.G_TryPushingEntity(check, pusher, move, amove)
	local matrix = { [0] = Q.vec3(), Q.vec3(), Q.vec3() }
	local transpose = { [0] = Q.vec3(), Q.vec3(), Q.vec3() }
	local org = Q.vec3()
	local org2 = Q.vec3()
	local move2 = Q.vec3()
	local block

	-- EF_MOVER_STOP will just stop when contacting another entity
	-- instead of pushing it, but entities can still ride on top of it
	if bit32.band(pusher.s.eFlags, C.EF_MOVER_STOP) ~= 0 and check.s.groundEntityNum ~= pusher.s.number then
		return false
	end

	-- save off the old position
	if pushed_p > C.MAX_GENTITIES then
		G.G_Error("pushed_p > &pushed[MAX_GENTITIES]")
	end
	local pp = pushed[pushed_p]
	pp.ent = check
	Q.VectorCopy(check.s.pos.trBase, pp.origin)
	Q.VectorCopy(check.s.apos.trBase, pp.angles)
	if check.client ~= nil then
		pp.deltayaw = check.client.ps.delta_angles[C.YAW]
		Q.VectorCopy(check.client.ps.origin, pp.origin)
	end
	pushed_p += 1

	-- try moving the contacted entity
	-- figure movement due to the pusher's amove
	G.G_CreateRotationMatrix(amove, transpose)
	G.G_TransposeMatrix(transpose, matrix)
	if check.client ~= nil then
		Q.VectorSubtract(check.client.ps.origin, pusher.r.currentOrigin, org)
	else
		Q.VectorSubtract(check.s.pos.trBase, pusher.r.currentOrigin, org)
	end
	Q.VectorCopy(org, org2)
	G.G_RotatePoint(org2, matrix)
	Q.VectorSubtract(org2, org, move2)
	-- add movement
	Q.VectorAdd(check.s.pos.trBase, move, check.s.pos.trBase)
	Q.VectorAdd(check.s.pos.trBase, move2, check.s.pos.trBase)
	if check.client ~= nil then
		Q.VectorAdd(check.client.ps.origin, move, check.client.ps.origin)
		Q.VectorAdd(check.client.ps.origin, move2, check.client.ps.origin)
		-- make sure the client's view rotates when on a rotating mover
		check.client.ps.delta_angles[C.YAW] += Q.ANGLE2SHORT(amove[C.YAW])
	end

	-- may have pushed them off an edge
	if check.s.groundEntityNum ~= pusher.s.number then
		check.s.groundEntityNum = -1
	end

	block = G.G_TestEntityPosition(check)
	if block == nil then
		-- pushed ok
		if check.client ~= nil then
			Q.VectorCopy(check.client.ps.origin, check.r.currentOrigin)
		else
			Q.VectorCopy(check.s.pos.trBase, check.r.currentOrigin)
		end
		G.trap_LinkEntity(check)
		return true
	end

	-- if it is ok to leave in the old position, do it
	-- this is only relevent for riding entities, not pushed
	-- Sliding trapdoors can cause this.
	local prev = pushed[pushed_p - 1]
	Q.VectorCopy(prev.origin, check.s.pos.trBase)
	if check.client ~= nil then
		Q.VectorCopy(prev.origin, check.client.ps.origin)
	end
	Q.VectorCopy(prev.angles, check.s.apos.trBase)
	block = G.G_TestEntityPosition(check)
	if block == nil then
		check.s.groundEntityNum = -1
		pushed_p -= 1
		return true
	end

	-- blocked
	return false
end

--[[
==================
G_CheckProxMinePosition
==================
]]
function G.G_CheckProxMinePosition(check)
	local start = Q.vec3()
	local end_ = Q.vec3()
	local tr = S.trace_t()

	Q.VectorMA(check.s.pos.trBase, 0.125, check.movedir, start)
	Q.VectorMA(check.s.pos.trBase, 2, check.movedir, end_)
	G.trap_Trace(tr, start, nil, nil, end_, check.s.number, C.MASK_SOLID)

	if tr.startsolid or tr.fraction < 1 then
		return false
	end

	return true
end

--[[
==================
G_TryPushingProxMine
==================
]]
function G.G_TryPushingProxMine(check, pusher, move, amove)
	local forward = Q.vec3()
	local right = Q.vec3()
	local up = Q.vec3()
	local org = Q.vec3()
	local org2 = Q.vec3()
	local move2 = Q.vec3()

	-- we need this for pushing things later
	Q.VectorSubtract(Q.vec3_origin, amove, org)
	Q.AngleVectors(org, forward, right, up)

	-- try moving the contacted entity
	Q.VectorAdd(check.s.pos.trBase, move, check.s.pos.trBase)

	-- figure movement due to the pusher's amove
	Q.VectorSubtract(check.s.pos.trBase, pusher.r.currentOrigin, org)
	org2[0] = Q.DotProduct(org, forward)
	org2[1] = -Q.DotProduct(org, right)
	org2[2] = Q.DotProduct(org, up)
	Q.VectorSubtract(org2, org, move2)
	Q.VectorAdd(check.s.pos.trBase, move2, check.s.pos.trBase)

	local ret = G.G_CheckProxMinePosition(check)
	if ret then
		Q.VectorCopy(check.s.pos.trBase, check.r.currentOrigin)
		G.trap_LinkEntity(check)
	end
	return ret
end

--[[
============
G_MoverPush

Objects need to be moved back on a failed push,
otherwise riders would continue to slide.
Returns (ok, obstacle): if ok is false, obstacle is the blocking entity
============
]]
function G.G_MoverPush(pusher, move, amove)
	local mins = Q.vec3()
	local maxs = Q.vec3()
	local entityList = {}
	local totalMins = Q.vec3()
	local totalMaxs = Q.vec3()

	local obstacle = nil

	-- mins/maxs are the bounds at the destination
	-- totalMins / totalMaxs are the bounds for the entire move
	if
		pusher.r.currentAngles[0] ~= 0
		or pusher.r.currentAngles[1] ~= 0
		or pusher.r.currentAngles[2] ~= 0
		or amove[0] ~= 0
		or amove[1] ~= 0
		or amove[2] ~= 0
	then
		local radius = Q.RadiusFromBounds(pusher.r.mins, pusher.r.maxs)
		for i = 0, 2 do
			mins[i] = pusher.r.currentOrigin[i] + move[i] - radius
			maxs[i] = pusher.r.currentOrigin[i] + move[i] + radius
			totalMins[i] = mins[i] - move[i]
			totalMaxs[i] = maxs[i] - move[i]
		end
	else
		for i = 0, 2 do
			mins[i] = pusher.r.absmin[i] + move[i]
			maxs[i] = pusher.r.absmax[i] + move[i]
		end

		Q.VectorCopy(pusher.r.absmin, totalMins)
		Q.VectorCopy(pusher.r.absmax, totalMaxs)
		for i = 0, 2 do
			if move[i] > 0 then
				totalMaxs[i] += move[i]
			else
				totalMins[i] += move[i]
			end
		end
	end

	-- unlink the pusher so we don't get it in the entityList
	G.trap_UnlinkEntity(pusher)

	local listedEntities = G.trap_EntitiesInBox(totalMins, totalMaxs, entityList, C.MAX_GENTITIES)

	-- move the pusher to it's final position
	Q.VectorAdd(pusher.r.currentOrigin, move, pusher.r.currentOrigin)
	Q.VectorAdd(pusher.r.currentAngles, amove, pusher.r.currentAngles)
	G.trap_LinkEntity(pusher)

	-- see if any solid entities are inside the final position
	for e = 0, listedEntities - 1 do
		local check = G.g_entities[entityList[e]]
		local skip = false

		if check.s.eType == C.ET_MISSILE then
			-- if it is a prox mine
			if check.classname == "prox mine" then
				-- if this prox mine is attached to this mover try to move it with the pusher
				if check.enemy == pusher then
					if not G.G_TryPushingProxMine(check, pusher, move, amove) then
						--explode
						check.s.loopSound = 0
						G.G_AddEvent(check, C.EV_PROXIMITY_MINE_TRIGGER, 0)
						G.G_ExplodeMissile(check)
						if check.activator ~= nil then
							G.G_FreeEntity(check.activator)
							check.activator = nil
						end
					end
				else
					--check if the prox mine is crushed by the mover
					if not G.G_CheckProxMinePosition(check) then
						--explode
						check.s.loopSound = 0
						G.G_AddEvent(check, C.EV_PROXIMITY_MINE_TRIGGER, 0)
						G.G_ExplodeMissile(check)
						if check.activator ~= nil then
							G.G_FreeEntity(check.activator)
							check.activator = nil
						end
					end
				end
				skip = true
			end
		end
		-- only push items and players
		if not skip and check.s.eType ~= C.ET_ITEM and check.s.eType ~= C.ET_PLAYER and not check.physicsObject then
			skip = true
		end

		-- if the entity is standing on the pusher, it will definitely be moved
		if not skip and check.s.groundEntityNum ~= pusher.s.number then
			-- see if the ent needs to be tested
			if
				check.r.absmin[0] >= maxs[0]
				or check.r.absmin[1] >= maxs[1]
				or check.r.absmin[2] >= maxs[2]
				or check.r.absmax[0] <= mins[0]
				or check.r.absmax[1] <= mins[1]
				or check.r.absmax[2] <= mins[2]
			then
				skip = true
			elseif G.G_TestEntityPosition(check) == nil then
				-- see if the ent's bbox is inside the pusher's final position
				-- this does allow a fast moving object to pass through a thin entity...
				skip = true
			end
		end

		-- the entity needs to be pushed
		if not skip and G.G_TryPushingEntity(check, pusher, move, amove) then
			skip = true
		end

		if not skip then
			-- the move was blocked an entity

			-- bobbing entities are instant-kill and never get blocked
			if pusher.s.pos.trType == C.TR_SINE or pusher.s.apos.trType == C.TR_SINE then
				G.G_Damage(check, pusher, pusher, nil, nil, 99999, 0, C.MOD_CRUSH)
			else
				-- save off the obstacle so we can call the block function (crush, etc)
				obstacle = check

				-- move back any entities we already moved
				-- go backwards, so if the same entity was pushed
				-- twice, it goes back to the original position
				for p = pushed_p - 1, 0, -1 do
					local pe = pushed[p]
					Q.VectorCopy(pe.origin, pe.ent.s.pos.trBase)
					Q.VectorCopy(pe.angles, pe.ent.s.apos.trBase)
					if pe.ent.client ~= nil then
						pe.ent.client.ps.delta_angles[C.YAW] = pe.deltayaw
						Q.VectorCopy(pe.origin, pe.ent.client.ps.origin)
					end
					G.trap_LinkEntity(pe.ent)
				end
				return false, obstacle
			end
		end
	end

	return true, obstacle
end

--[[
=================
G_MoverTeam
=================
]]
function G.G_MoverTeam(ent)
	local move = Q.vec3()
	local amove = Q.vec3()
	local part, obstacle
	local origin = Q.vec3()
	local angles = Q.vec3()

	obstacle = nil

	-- make sure all team slaves can move before commiting
	-- any moves or calling any think functions
	-- if the move is blocked, all moved objects will be backed out
	pushed_p = 0
	part = ent
	while part ~= nil do
		-- get current position
		BG.BG_EvaluateTrajectory(part.s.pos, G.level.time, origin)
		BG.BG_EvaluateTrajectory(part.s.apos, G.level.time, angles)
		Q.VectorSubtract(origin, part.r.currentOrigin, move)
		Q.VectorSubtract(angles, part.r.currentAngles, amove)
		local ok
		ok, obstacle = G.G_MoverPush(part, move, amove)
		if not ok then
			break -- move was blocked
		end
		part = part.teamchain
	end

	if part ~= nil then
		-- go back to the previous position
		part = ent
		while part ~= nil do
			part.s.pos.trTime += G.level.time - G.level.previousTime
			part.s.apos.trTime += G.level.time - G.level.previousTime
			BG.BG_EvaluateTrajectory(part.s.pos, G.level.time, part.r.currentOrigin)
			BG.BG_EvaluateTrajectory(part.s.apos, G.level.time, part.r.currentAngles)
			G.trap_LinkEntity(part)
			part = part.teamchain
		end

		-- if the pusher has a "blocked" function, call it
		if ent.blocked ~= nil then
			ent.blocked(ent, obstacle)
		end
		return
	end

	-- the move succeeded
	part = ent
	while part ~= nil do
		-- call the reached function if time is at or past end point
		if part.s.pos.trType == C.TR_LINEAR_STOP then
			if G.level.time >= part.s.pos.trTime + part.s.pos.trDuration then
				if part.reached ~= nil then
					part.reached(part)
				end
			end
		end
		part = part.teamchain
	end
end

--[[
================
G_RunMover

================
]]
function G.G_RunMover(ent)
	-- if not a team captain, don't do anything, because
	-- the captain will handle everything
	if bit32.band(ent.flags, C.FL_TEAMSLAVE) ~= 0 then
		return
	end

	-- if stationary at one of the positions, don't move anything
	if ent.s.pos.trType ~= C.TR_STATIONARY or ent.s.apos.trType ~= C.TR_STATIONARY then
		G.G_MoverTeam(ent)
	end

	-- check think function
	G.G_RunThink(ent)
end

--[[
============================================================================

GENERAL MOVERS

Doors, plats, and buttons are all binary (two position) movers
Pos1 is "at rest", pos2 is "activated"
============================================================================
]]

--[[
===============
SetMoverState
===============
]]
function G.SetMoverState(ent, moverState, time)
	local delta = Q.vec3()
	local f

	ent.moverState = moverState

	ent.s.pos.trTime = time
	if moverState == C.MOVER_POS1 then
		Q.VectorCopy(ent.pos1, ent.s.pos.trBase)
		ent.s.pos.trType = C.TR_STATIONARY
	elseif moverState == C.MOVER_POS2 then
		Q.VectorCopy(ent.pos2, ent.s.pos.trBase)
		ent.s.pos.trType = C.TR_STATIONARY
	elseif moverState == C.MOVER_1TO2 then
		Q.VectorCopy(ent.pos1, ent.s.pos.trBase)
		Q.VectorSubtract(ent.pos2, ent.pos1, delta)
		f = 1000.0 / ent.s.pos.trDuration
		Q.VectorScale(delta, f, ent.s.pos.trDelta)
		ent.s.pos.trType = C.TR_LINEAR_STOP
	elseif moverState == C.MOVER_2TO1 then
		Q.VectorCopy(ent.pos2, ent.s.pos.trBase)
		Q.VectorSubtract(ent.pos1, ent.pos2, delta)
		f = 1000.0 / ent.s.pos.trDuration
		Q.VectorScale(delta, f, ent.s.pos.trDelta)
		ent.s.pos.trType = C.TR_LINEAR_STOP
	end
	BG.BG_EvaluateTrajectory(ent.s.pos, G.level.time, ent.r.currentOrigin)
	G.trap_LinkEntity(ent)
end

--[[
================
MatchTeam

All entities in a mover team will move from pos1 to pos2
in the same amount of time
================
]]
function G.MatchTeam(teamLeader, moverState, time)
	local slave = teamLeader
	while slave ~= nil do
		G.SetMoverState(slave, moverState, time)
		slave = slave.teamchain
	end
end

--[[
================
ReturnToPos1
================
]]
function G.ReturnToPos1(ent)
	G.MatchTeam(ent, C.MOVER_2TO1, G.level.time)

	-- looping sound
	ent.s.loopSound = ent.soundLoop

	-- starting sound
	if ent.sound2to1 ~= 0 then
		G.G_AddEvent(ent, C.EV_GENERAL_SOUND, ent.sound2to1)
	end
end

--[[
================
Reached_BinaryMover
================
]]
function G.Reached_BinaryMover(ent)
	-- stop the looping sound
	ent.s.loopSound = ent.soundLoop

	if ent.moverState == C.MOVER_1TO2 then
		-- reached pos2
		G.SetMoverState(ent, C.MOVER_POS2, G.level.time)

		-- play sound
		if ent.soundPos2 ~= 0 then
			G.G_AddEvent(ent, C.EV_GENERAL_SOUND, ent.soundPos2)
		end

		-- return to pos1 after a delay
		ent.think = G.ReturnToPos1
		ent.nextthink = Q.trunc(G.level.time + ent.wait)

		-- fire targets
		if ent.activator == nil then
			ent.activator = ent
		end
		G.G_UseTargets(ent, ent.activator)
	elseif ent.moverState == C.MOVER_2TO1 then
		-- reached pos1
		G.SetMoverState(ent, C.MOVER_POS1, G.level.time)

		-- play sound
		if ent.soundPos1 ~= 0 then
			G.G_AddEvent(ent, C.EV_GENERAL_SOUND, ent.soundPos1)
		end

		-- close areaportals
		if ent.teammaster == ent or ent.teammaster == nil then
			G.trap_AdjustAreaPortalState(ent, false)
		end
	else
		G.G_Error("Reached_BinaryMover: bad moverState")
	end
end

--[[
================
Use_BinaryMover
================
]]
function G.Use_BinaryMover(ent, other, activator)
	local total
	local partial

	-- only the master should be used
	if bit32.band(ent.flags, C.FL_TEAMSLAVE) ~= 0 then
		G.Use_BinaryMover(ent.teammaster, other, activator)
		return
	end

	ent.activator = activator

	if ent.moverState == C.MOVER_POS1 then
		-- start moving 50 msec later, becase if this was player
		-- triggered, level.time hasn't been advanced yet
		G.MatchTeam(ent, C.MOVER_1TO2, G.level.time + 50)

		-- starting sound
		if ent.sound1to2 ~= 0 then
			G.G_AddEvent(ent, C.EV_GENERAL_SOUND, ent.sound1to2)
		end

		-- looping sound
		ent.s.loopSound = ent.soundLoop

		-- open areaportal
		if ent.teammaster == ent or ent.teammaster == nil then
			G.trap_AdjustAreaPortalState(ent, true)
		end
		return
	end

	-- if all the way up, just delay before coming down
	if ent.moverState == C.MOVER_POS2 then
		ent.nextthink = Q.trunc(G.level.time + ent.wait)
		return
	end

	-- only partway down before reversing
	if ent.moverState == C.MOVER_2TO1 then
		total = ent.s.pos.trDuration
		partial = G.level.time - ent.s.pos.trTime
		if partial > total then
			partial = total
		end

		G.MatchTeam(ent, C.MOVER_1TO2, G.level.time - (total - partial))

		if ent.sound1to2 ~= 0 then
			G.G_AddEvent(ent, C.EV_GENERAL_SOUND, ent.sound1to2)
		end
		return
	end

	-- only partway up before reversing
	if ent.moverState == C.MOVER_1TO2 then
		total = ent.s.pos.trDuration
		partial = G.level.time - ent.s.pos.trTime
		if partial > total then
			partial = total
		end

		G.MatchTeam(ent, C.MOVER_2TO1, G.level.time - (total - partial))

		if ent.sound2to1 ~= 0 then
			G.G_AddEvent(ent, C.EV_GENERAL_SOUND, ent.sound2to1)
		end
		return
	end
end

--[[
================
InitMover

"pos1", "pos2", and "speed" should be set before calling,
so the movement delta can be calculated
================
]]
function G.InitMover(ent)
	local move = Q.vec3()
	local distance
	local light
	local color
	local lightSet, colorSet
	local found, sound

	-- if the "model2" key is set, use a seperate model
	-- for drawing, but clip against the brushes
	if ent.model2 ~= nil then
		ent.s.modelindex2 = G.G_ModelIndex(ent.model2)
	end

	-- if the "loopsound" key is set, use a constant looping sound when moving
	found, sound = G.G_SpawnString("noise", "100")
	if found then
		ent.s.loopSound = G.G_SoundIndex(sound)
	end

	-- if the "color" or "light" keys are set, setup constantLight
	lightSet, light = G.G_SpawnFloat("light", "100")
	colorSet, color = G.G_SpawnVector("color", "1 1 1")
	if lightSet or colorSet then
		local r = Q.trunc(color[0] * 255)
		if r > 255 then
			r = 255
		end
		local g = Q.trunc(color[1] * 255)
		if g > 255 then
			g = 255
		end
		local b = Q.trunc(color[2] * 255)
		if b > 255 then
			b = 255
		end
		local i = Q.trunc(light / 4)
		if i > 255 then
			i = 255
		end
		ent.s.constantLight = Q.int32(
			bit32.bor(r, bit32.lshift(g, 8), bit32.lshift(b, 16), bit32.lshift(i, 24))
		)
	end

	ent.use = G.Use_BinaryMover
	ent.reached = G.Reached_BinaryMover

	ent.moverState = C.MOVER_POS1
	ent.r.svFlags = C.SVF_USE_CURRENT_ORIGIN
	ent.s.eType = C.ET_MOVER
	Q.VectorCopy(ent.pos1, ent.r.currentOrigin)
	G.trap_LinkEntity(ent)

	ent.s.pos.trType = C.TR_STATIONARY
	Q.VectorCopy(ent.pos1, ent.s.pos.trBase)

	-- calculate time to reach second position from speed
	Q.VectorSubtract(ent.pos2, ent.pos1, move)
	distance = Q.VectorLength(move)
	if ent.speed == 0 then
		ent.speed = 100
	end
	Q.VectorScale(move, ent.speed, ent.s.pos.trDelta)
	ent.s.pos.trDuration = Q.trunc(distance * 1000 / ent.speed)
	if ent.s.pos.trDuration <= 0 then
		ent.s.pos.trDuration = 1
	end
end

--[[
===============================================================================

DOOR

A use can be triggered either by a touch function, by being shot, or by being
targeted by another entity.

===============================================================================
]]

--[[
================
Blocked_Door
================
]]
function G.Blocked_Door(ent, other)
	-- remove anything other than a client
	if other.client == nil then
		-- except CTF flags!!!!
		if other.s.eType == C.ET_ITEM and other.item.giType == C.IT_TEAM then
			G.Team_DroppedFlagThink(other)
			return
		end
		G.G_TempEntity(other.s.origin, C.EV_ITEM_POP)
		G.G_FreeEntity(other)
		return
	end

	if ent.damage ~= 0 then
		if G.g_awardpushing.integer ~= 0 then
			G.G_Damage(other, ent, ent.activator, nil, nil, ent.damage, 0, C.MOD_CRUSH)
		else
			G.G_Damage(other, ent, ent, nil, nil, ent.damage, 0, C.MOD_CRUSH)
		end
	end
	if bit32.band(ent.spawnflags, 4) ~= 0 then
		return -- crushers don't reverse
	end

	-- reverse direction
	G.Use_BinaryMover(ent, ent, other)
end

return nil
