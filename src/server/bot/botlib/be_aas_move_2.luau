--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_move.c, part 2 of 2).

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
-- Luau port of be_aas_move.c lines 408-1091 (botlib/be_aas_move.c, part 2 of 2): bbox clipping, client movement prediction, jump velocity.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

function B.AAS_ClipToBBox(trace, start, end_, presencetype, mins, maxs)
	local bboxmins = { [0] = 0, 0, 0 }
	local bboxmaxs = { [0] = 0, 0, 0 }
	local absmins = { [0] = 0, 0, 0 }
	local absmaxs = { [0] = 0, 0, 0 }
	local dir = { [0] = 0, 0, 0 }
	local mid = { [0] = 0, 0, 0 }
	local front, back, planedist
	local side

	B.AAS_PresenceTypeBoundingBox(presencetype, bboxmins, bboxmaxs)
	Q.VectorSubtract(mins, bboxmaxs, absmins)
	Q.VectorSubtract(maxs, bboxmins, absmaxs)
	--
	Q.VectorCopy(end_, trace.endpos)
	trace.fraction = 1
	for i = 0, 2 do
		if start[i] < absmins[i] and end_[i] < absmins[i] then
			return 0
		end
		if start[i] > absmaxs[i] and end_[i] > absmaxs[i] then
			return 0
		end
	end
	--check bounding box collision
	Q.VectorSubtract(end_, start, dir)
	local frac = 1
	local i = 0
	while i < 3 do
		--get plane to test collision with for the current axis direction
		if dir[i] > 0 then
			planedist = absmins[i]
		else
			planedist = absmaxs[i]
		end
		--calculate collision fraction
		front = Q.f(start[i] - planedist)
		back = Q.f(end_[i] - planedist)
		frac = Q.f(front / Q.f(front - back))
		--check if between bounding planes of next axis
		side = i + 1
		if side > 2 then
			side = 0
		end
		mid[side] = Q.f(start[side] + Q.f(dir[side] * frac))
		if mid[side] > absmins[side] and mid[side] < absmaxs[side] then
			--check if between bounding planes of next axis
			side = side + 1
			if side > 2 then
				side = 0
			end
			mid[side] = Q.f(start[side] + Q.f(dir[side] * frac))
			if mid[side] > absmins[side] and mid[side] < absmaxs[side] then
				mid[i] = planedist
				break
			end
		end
		i = i + 1
	end
	--if there was a collision
	if i ~= 3 then
		trace.startsolid = false
		trace.fraction = frac
		trace.ent = 0
		trace.planenum = 0
		trace.area = 0
		trace.lastarea = 0
		--trace endpos
		for j = 0, 2 do
			trace.endpos[j] = Q.f(start[j] + Q.f(dir[j] * frac))
		end
		return 1
	end
	return 0
end

-- VectorMA(v, -DotProduct(v, n), n, v) is a macro in q_shared.h (#if 1): the
-- scale expression is re-evaluated for each component, after the previous
-- components of v have already been overwritten. Reproduced exactly.
local function VectorMAProject(v, n)
	for i = 0, 2 do
		v[i] = Q.f(v[i] + Q.f(n[i] * -Q.DotProduct(v, n)))
	end
end

local function ScaledVel(v, scale)
	return {
		[0] = Q.f(v[0] * scale),
		Q.f(v[1] * scale),
		Q.f(v[2] * scale),
	}
end

local function SetStop(move, endpos, endarea, trace, stopevent, presencetype, n, frametime, velocity)
	Q.VectorCopy(endpos, move.endpos)
	move.endarea = endarea
	move.velocity[0] = velocity[0]
	move.velocity[1] = velocity[1]
	move.velocity[2] = velocity[2]
	if trace ~= nil then
		SB.copy_aas_trace_t(move.trace, trace)
	end
	move.stopevent = stopevent
	move.presencetype = presencetype
	move.endcontents = 0
	move.time = Q.f(n * frametime)
	move.frames = n
end

function B.AAS_ClientMovementPrediction(
	move,
	entnum,
	origin,
	presencetype,
	onground,
	velocity,
	cmdmove,
	cmdframes,
	maxframes,
	frametime,
	stopevent,
	stopareanum,
	mins,
	maxs,
	visualize
)
	local aassettings = B.aassettings
	local aasworld = B.aasworld
	local gravity, delta, maxvel, wishspeed, accelerate, friction
	local swimming, crouch, event, areanum, pc, step
	local areas = {}
	local points = {}
	for k = 0, 19 do
		points[k] = { [0] = 0, 0, 0 }
	end
	local org = { [0] = 0, 0, 0 }
	local end_ = { [0] = 0, 0, 0 }
	local feet = { [0] = 0, 0, 0 }
	local start = { [0] = 0, 0, 0 }
	local stepend = { [0] = 0, 0, 0 }
	local lastorg = { [0] = 0, 0, 0 }
	local wishdir = { [0] = 0, 0, 0 }
	local frame_test_vel = { [0] = 0, 0, 0 }
	local old_frame_test_vel = { [0] = 0, 0, 0 }
	local left_test_vel = { [0] = 0, 0, 0 }
	local up = { [0] = 0, 0, 1 }
	local trace
	local steptrace
	local plane, plane2

	if frametime <= 0 then
		frametime = Q.f(0.1)
	end
	--
	local phys_friction = aassettings.phys_friction
	local phys_stopspeed = aassettings.phys_stopspeed
	local phys_gravity = aassettings.phys_gravity
	local phys_waterfriction = aassettings.phys_waterfriction
	local phys_watergravity = aassettings.phys_watergravity
	local phys_maxwalkvelocity = aassettings.phys_maxwalkvelocity
	local phys_maxcrouchvelocity = aassettings.phys_maxcrouchvelocity
	local phys_maxswimvelocity = aassettings.phys_maxswimvelocity
	local phys_walkaccelerate = aassettings.phys_walkaccelerate
	local phys_airaccelerate = aassettings.phys_airaccelerate
	local phys_swimaccelerate = aassettings.phys_swimaccelerate
	local phys_maxstep = aassettings.phys_maxstep
	local phys_maxsteepness = aassettings.phys_maxsteepness
	local phys_jumpvel = Q.f(aassettings.phys_jumpvel * frametime)
	local invframe = Q.f(1 / frametime)
	--
	SB.copy_aas_clientmove_t(move, SB.aas_clientmove_t())
	trace = SB.aas_trace_t()
	--start at the current origin
	Q.VectorCopy(origin, org)
	org[2] = Q.f(org[2] + 0.25)
	--velocity to test for the first frame
	Q.VectorScale(velocity, frametime, frame_test_vel)
	--
	local jump_frame = -1
	--predict a maximum of 'maxframes' ahead
	local n = 0
	while n < maxframes do
		swimming = B.AAS_Swimming(org)
		--get gravity depending on swimming or not
		if swimming ~= 0 then
			gravity = phys_watergravity
		else
			gravity = phys_gravity
		end
		--apply gravity at the START of the frame
		frame_test_vel[2] = Q.f(frame_test_vel[2] - (gravity * 0.1 * frametime))
		--if on the ground or swimming
		if onground ~= 0 or swimming ~= 0 then
			if swimming ~= 0 then
				friction = phys_waterfriction
			else
				friction = phys_friction
			end
			--apply friction
			Q.VectorScale(frame_test_vel, invframe, frame_test_vel)
			B.AAS_ApplyFriction(frame_test_vel, friction, phys_stopspeed, frametime)
			Q.VectorScale(frame_test_vel, frametime, frame_test_vel)
		end
		crouch = false
		--apply command movement
		if n < cmdframes then
			maxvel = phys_maxwalkvelocity
			accelerate = phys_airaccelerate
			Q.VectorCopy(cmdmove, wishdir)
			if onground ~= 0 then
				if cmdmove[2] < -300 then
					crouch = true
					maxvel = phys_maxcrouchvelocity
				end
				--if not swimming and upmove is positive then jump
				if swimming == 0 and cmdmove[2] > 1 then
					--jump velocity minus the gravity for one frame + 5 for safety
					frame_test_vel[2] = Q.f(phys_jumpvel - (gravity * 0.1 * frametime) + 5)
					jump_frame = n
					--jumping so air accelerate
					accelerate = phys_airaccelerate
				else
					accelerate = phys_walkaccelerate
				end
			end
			if swimming ~= 0 then
				maxvel = phys_maxswimvelocity
				accelerate = phys_swimaccelerate
			else
				wishdir[2] = 0
			end
			--
			wishspeed = Q.VectorNormalizeIoq3(wishdir)
			if wishspeed > maxvel then
				wishspeed = maxvel
			end
			Q.VectorScale(frame_test_vel, invframe, frame_test_vel)
			B.AAS_Accelerate(frame_test_vel, frametime, wishdir, wishspeed, accelerate)
			Q.VectorScale(frame_test_vel, frametime, frame_test_vel)
		end
		if crouch then
			presencetype = BC.PRESENCE_CROUCH
		elseif presencetype == BC.PRESENCE_CROUCH then
			if bit32.band(B.AAS_PointPresenceType(org), BC.PRESENCE_NORMAL) ~= 0 then
				presencetype = BC.PRESENCE_NORMAL
			end
		end
		--save the current origin
		Q.VectorCopy(org, lastorg)
		--move linear during one frame
		Q.VectorCopy(frame_test_vel, left_test_vel)
		local j = 0
		repeat
			Q.VectorAdd(org, left_test_vel, end_)
			--trace a bounding box
			trace = B.AAS_TraceClientBBox(org, end_, presencetype, entnum)
			--
			if visualize ~= 0 then
				if trace.startsolid then
					B.botimport.Print(BC.PRT_MESSAGE, "PredictMovement: start solid\n")
				end
				B.AAS_DebugLine(org, trace.endpos, BC.LINECOLOR_RED)
			end
			--
			if
				bit32.band(
					stopevent,
					bit32.bor(BC.SE_ENTERAREA, BC.SE_TOUCHJUMPPAD, BC.SE_TOUCHTELEPORTER, BC.SE_TOUCHCLUSTERPORTAL)
				) ~= 0
			then
				local numareas = B.AAS_TraceAreas(org, trace.endpos, areas, points, 20)
				for i = 0, numareas - 1 do
					if bit32.band(stopevent, BC.SE_ENTERAREA) ~= 0 then
						if areas[i] == stopareanum then
							SetStop(move, points[i], areas[i], trace, BC.SE_ENTERAREA, presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
							return 1
						end
					end
					--NOTE: if not the first frame
					if bit32.band(stopevent, BC.SE_TOUCHJUMPPAD) ~= 0 and n ~= 0 then
						if bit32.band(aasworld.areasettings[areas[i]].contents, BC.AREACONTENTS_JUMPPAD) ~= 0 then
							SetStop(move, points[i], areas[i], trace, BC.SE_TOUCHJUMPPAD, presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
							return 1
						end
					end
					if bit32.band(stopevent, BC.SE_TOUCHTELEPORTER) ~= 0 then
						if bit32.band(aasworld.areasettings[areas[i]].contents, BC.AREACONTENTS_TELEPORTER) ~= 0 then
							SetStop(move, points[i], areas[i], trace, BC.SE_TOUCHTELEPORTER, presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
							return 1
						end
					end
					if bit32.band(stopevent, BC.SE_TOUCHCLUSTERPORTAL) ~= 0 then
						if bit32.band(aasworld.areasettings[areas[i]].contents, BC.AREACONTENTS_CLUSTERPORTAL) ~= 0 then
							SetStop(move, points[i], areas[i], trace, BC.SE_TOUCHCLUSTERPORTAL, presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
							return 1
						end
					end
				end
			end
			--
			if bit32.band(stopevent, BC.SE_HITBOUNDINGBOX) ~= 0 then
				if B.AAS_ClipToBBox(trace, org, trace.endpos, presencetype, mins, maxs) ~= 0 then
					SetStop(move, trace.endpos, B.AAS_PointAreaNum(trace.endpos), trace, BC.SE_HITBOUNDINGBOX, presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
					return 1
				end
			end
			--move the entity to the trace end point
			Q.VectorCopy(trace.endpos, org)
			--if there was a collision
			if trace.fraction < 1.0 then
				--get the plane the bounding box collided with
				plane = B.AAS_PlaneFromNum(trace.planenum)
				--
				if bit32.band(stopevent, BC.SE_HITGROUNDAREA) ~= 0 then
					if Q.DotProduct(plane.normal, up) > phys_maxsteepness then
						Q.VectorCopy(org, start)
						start[2] = Q.f(start[2] + 0.5)
						if B.AAS_PointAreaNum(start) == stopareanum then
							SetStop(move, start, stopareanum, trace, BC.SE_HITGROUNDAREA, presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
							return 1
						end
					end
				end
				--assume there's no step
				step = false
				--if it is a vertical plane and the bot didn't jump recently
				if plane.normal[2] == 0 and (jump_frame < 0 or n - jump_frame > 2) then
					--check for a step
					Q.VectorMA(org, -0.25, plane.normal, start)
					Q.VectorCopy(start, stepend)
					start[2] = Q.f(start[2] + phys_maxstep)
					steptrace = B.AAS_TraceClientBBox(start, stepend, presencetype, entnum)
					--
					if not steptrace.startsolid then
						plane2 = B.AAS_PlaneFromNum(steptrace.planenum)
						if Q.DotProduct(plane2.normal, up) > phys_maxsteepness then
							Q.VectorSubtract(end_, steptrace.endpos, left_test_vel)
							left_test_vel[2] = 0
							frame_test_vel[2] = 0
							if visualize ~= 0 then
								if Q.f(steptrace.endpos[2] - org[2]) > 0.125 then
									Q.VectorCopy(org, start)
									start[2] = steptrace.endpos[2]
									B.AAS_DebugLine(org, start, BC.LINECOLOR_BLUE)
								end
							end
							org[2] = steptrace.endpos[2]
							step = true
						end
					end
				end
				--
				if not step then
					--velocity left to test for this frame is the projection
					--of the current test velocity into the hit plane
					VectorMAProject(left_test_vel, plane.normal)
					--store the old velocity for landing check
					Q.VectorCopy(frame_test_vel, old_frame_test_vel)
					--test velocity for the next frame is the projection
					--of the velocity of the current frame into the hit plane
					VectorMAProject(frame_test_vel, plane.normal)
					--check for a landing on an almost horizontal floor
					if Q.DotProduct(plane.normal, up) > phys_maxsteepness then
						onground = 1
					end
					if bit32.band(stopevent, BC.SE_HITGROUNDDAMAGE) ~= 0 then
						delta = 0
						if
							old_frame_test_vel[2] < 0
							and frame_test_vel[2] > old_frame_test_vel[2]
							and onground == 0
						then
							delta = old_frame_test_vel[2]
						elseif onground ~= 0 then
							delta = Q.f(frame_test_vel[2] - old_frame_test_vel[2])
						end
						if delta ~= 0 then
							delta = Q.f(delta * 10)
							delta = Q.f(Q.f(delta * delta) * 0.0001)
							if swimming ~= 0 then
								delta = 0
							end
							if delta > 40 then
								SetStop(move, org, B.AAS_PointAreaNum(org), trace, BC.SE_HITGROUNDDAMAGE, presencetype, n, frametime, frame_test_vel)
								return 1
							end
						end
					end
				end
			end
			--extra check to prevent endless loop
			j = j + 1
			if j > 20 then
				return 0
			end
			--while there is a plane hit
		until not (trace.fraction < 1.0)
		--if going down
		if frame_test_vel[2] <= 10 then
			--check for a liquid at the feet of the bot
			Q.VectorCopy(org, feet)
			feet[2] = Q.f(feet[2] - 22)
			pc = B.AAS_PointContents(feet)
			--get event from pc
			event = BC.SE_NONE
			if bit32.band(pc, BC.CONTENTS_LAVA) ~= 0 then
				event = bit32.bor(event, BC.SE_ENTERLAVA)
			end
			if bit32.band(pc, BC.CONTENTS_SLIME) ~= 0 then
				event = bit32.bor(event, BC.SE_ENTERSLIME)
			end
			if bit32.band(pc, BC.CONTENTS_WATER) ~= 0 then
				event = bit32.bor(event, BC.SE_ENTERWATER)
			end
			--
			areanum = B.AAS_PointAreaNum(org)
			if bit32.band(aasworld.areasettings[areanum].contents, BC.AREACONTENTS_LAVA) ~= 0 then
				event = bit32.bor(event, BC.SE_ENTERLAVA)
			end
			if bit32.band(aasworld.areasettings[areanum].contents, BC.AREACONTENTS_SLIME) ~= 0 then
				event = bit32.bor(event, BC.SE_ENTERSLIME)
			end
			if bit32.band(aasworld.areasettings[areanum].contents, BC.AREACONTENTS_WATER) ~= 0 then
				event = bit32.bor(event, BC.SE_ENTERWATER)
			end
			--if in lava or slime
			if bit32.band(event, stopevent) ~= 0 then
				SetStop(move, org, areanum, nil, bit32.band(event, stopevent), presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
				move.endcontents = pc
				return 1
			end
		end
		--
		onground = B.AAS_OnGround(org, presencetype, entnum)
		--if onground and on the ground for at least one whole frame
		if onground ~= 0 then
			if bit32.band(stopevent, BC.SE_HITGROUND) ~= 0 then
				SetStop(move, org, B.AAS_PointAreaNum(org), trace, BC.SE_HITGROUND, presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
				return 1
			end
		elseif bit32.band(stopevent, BC.SE_LEAVEGROUND) ~= 0 then
			SetStop(move, org, B.AAS_PointAreaNum(org), trace, BC.SE_LEAVEGROUND, presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
			return 1
		elseif bit32.band(stopevent, BC.SE_GAP) ~= 0 then
			Q.VectorCopy(org, start)
			Q.VectorCopy(start, end_)
			end_[2] = Q.f(end_[2] - Q.f(48 + aassettings.phys_maxbarrier))
			local gaptrace = B.AAS_TraceClientBBox(start, end_, BC.PRESENCE_CROUCH, -1)
			--if solid is found the bot cannot walk any further and will not fall into a gap
			if not gaptrace.startsolid then
				--if it is a gap (lower than one step height)
				if gaptrace.endpos[2] < Q.f(Q.f(org[2] - aassettings.phys_maxstep) - 1) then
					if bit32.band(B.AAS_PointContents(end_), BC.CONTENTS_WATER) == 0 then
						SetStop(move, lastorg, B.AAS_PointAreaNum(lastorg), trace, BC.SE_GAP, presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
						return 1
					end
				end
			end
		end
		n = n + 1
	end
	--
	SetStop(move, org, B.AAS_PointAreaNum(org), nil, BC.SE_NONE, presencetype, n, frametime, ScaledVel(frame_test_vel, invframe))
	--
	return 1
end

function B.AAS_PredictClientMovement(
	move,
	entnum,
	origin,
	presencetype,
	onground,
	velocity,
	cmdmove,
	cmdframes,
	maxframes,
	frametime,
	stopevent,
	stopareanum,
	visualize
)
	local mins = { [0] = 0, 0, 0 }
	local maxs = { [0] = 0, 0, 0 }
	return B.AAS_ClientMovementPrediction(
		move,
		entnum,
		origin,
		presencetype,
		onground,
		velocity,
		cmdmove,
		cmdframes,
		maxframes,
		frametime,
		stopevent,
		stopareanum,
		mins,
		maxs,
		visualize
	)
end

function B.AAS_ClientMovementHitBBox(
	move,
	entnum,
	origin,
	presencetype,
	onground,
	velocity,
	cmdmove,
	cmdframes,
	maxframes,
	frametime,
	mins,
	maxs,
	visualize
)
	return B.AAS_ClientMovementPrediction(
		move,
		entnum,
		origin,
		presencetype,
		onground,
		velocity,
		cmdmove,
		cmdframes,
		maxframes,
		frametime,
		BC.SE_HITBOUNDINGBOX,
		0,
		mins,
		maxs,
		visualize
	)
end

function B.AAS_TestMovementPrediction(entnum, origin, dir)
	local velocity = { [0] = 0, 0, 0 }
	local cmdmove = { [0] = 0, 0, 0 }
	local move = SB.aas_clientmove_t()

	Q.VectorClear(velocity)
	if B.AAS_Swimming(origin) == 0 then
		dir[2] = 0
	end
	Q.VectorNormalizeIoq3(dir)
	Q.VectorScale(dir, 400, cmdmove)
	cmdmove[2] = 224
	B.AAS_ClearShownDebugLines()
	B.AAS_PredictClientMovement(move, entnum, origin, BC.PRESENCE_NORMAL, 1, velocity, cmdmove, 13, 13, Q.f(0.1), BC.SE_HITGROUND, 0, 1)
	if bit32.band(move.stopevent, BC.SE_LEAVEGROUND) ~= 0 then
		B.botimport.Print(BC.PRT_MESSAGE, "leave ground\n")
	end
end

-- returns (qboolean as int, horizontal velocity)
function B.AAS_HorizontalVelocityForJump(zvel, start, end_)
	local aassettings = B.aassettings
	local dir = { [0] = 0, 0, 0 }

	local phys_gravity = aassettings.phys_gravity
	local phys_maxvelocity = aassettings.phys_maxvelocity

	--maximum height a player can jump with the given initial z velocity
	local zg = Q.f(zvel / phys_gravity)
	local maxjump = Q.f(0.5 * phys_gravity * zg * zg)
	--top of the parabolic jump
	local top = Q.f(start[2] + maxjump)
	--height the bot will fall from the top
	local height2fall = Q.f(top - end_[2])
	--if the goal is to high to jump to
	if height2fall < 0 then
		return 0, phys_maxvelocity
	end
	--time a player takes to fall the height
	local t = Q.f(math.sqrt(height2fall / (0.5 * phys_gravity)))
	--direction from start to end
	Q.VectorSubtract(end_, start, dir)
	--
	local tt = Q.f(t + zg)
	if tt == 0.0 then
		return 0, phys_maxvelocity
	end
	--calculate horizontal speed
	local velocity = Q.f(math.sqrt(Q.f(Q.f(dir[0] * dir[0]) + Q.f(dir[1] * dir[1]))) / tt)
	--the horizontal speed must be lower than the max speed
	if velocity > phys_maxvelocity then
		return 0, phys_maxvelocity
	end
	return 1, velocity
end

return nil
