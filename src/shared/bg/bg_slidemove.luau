--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/bg_slidemove.c).

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
-- Luau port of OpenArena 0.8.8's bg_slidemove.c (gamecode 9e0f0c0). Float semantics follow the C build exactly:
-- every float operation is rounded with f(); comparisons against double
-- literals (0.99, 0.1, 0.7) stay in double, as C promotes them.

local B = require("./bg_local")
local S = require("../structs")
local Q = require("../q_math")
local C = require("../consts")

local f = Q.f
local DotProduct, VectorCopy, VectorMA, VectorAdd, VectorClear, VectorScale, VectorNormalize, VectorNormalize2, CrossProduct, VectorSet =
	Q.DotProduct, Q.VectorCopy, Q.VectorMA, Q.VectorAdd, Q.VectorClear, Q.VectorScale, Q.VectorNormalize, Q.VectorNormalize2, Q.CrossProduct, Q.VectorSet
local vec3 = Q.vec3
local OVERCLIP = C.OVERCLIP
local STEPSIZE = C.STEPSIZE

local MAX_CLIP_PLANES = 5

-- scratch storage (the C locals); PM_SlideMove never re-enters itself
local dir, primal_velocity, clipVelocity, endp, endVelocity, endClipVelocity = vec3(), vec3(), vec3(), vec3(), vec3(), vec3()
local planes = { [0] = vec3(), vec3(), vec3(), vec3(), vec3() }
local trace = S.trace_t()

-- Returns true if the velocity was clipped in some way
local function PM_SlideMove(gravity: boolean): boolean
	local pm, pml = B.pm, B.pml
	local ps = pm.ps
	local PM_ClipVelocity = B.PM_ClipVelocity
	local numbumps = 4
	local numplanes
	local d, into
	local i, j, k

	VectorCopy(ps.velocity, primal_velocity)

	if gravity then
		VectorCopy(ps.velocity, endVelocity)
		endVelocity[2] = f(endVelocity[2] - f(ps.gravity * pml.frametime))
		ps.velocity[2] = f(f(ps.velocity[2] + endVelocity[2]) * 0.5)
		primal_velocity[2] = endVelocity[2]
		if pml.groundPlane then
			-- slide along the ground plane
			PM_ClipVelocity(ps.velocity, pml.groundTrace.plane.normal, ps.velocity, OVERCLIP)
		end
	end

	local time_left = pml.frametime

	-- never turn against the ground plane
	if pml.groundPlane then
		numplanes = 1
		VectorCopy(pml.groundTrace.plane.normal, planes[0])
	else
		numplanes = 0
	end

	-- never turn against original velocity
	VectorNormalize2(ps.velocity, planes[numplanes])
	numplanes += 1

	local bumpcount = 0
	while bumpcount < numbumps do
		-- calculate position we are trying to move to
		VectorMA(ps.origin, time_left, ps.velocity, endp)

		-- see if we can make it there
		pm.trace(trace, ps.origin, pm.mins, pm.maxs, endp, ps.clientNum, pm.tracemask)

		if trace.allsolid then
			-- entity is completely trapped in another solid
			ps.velocity[2] = 0 -- don't build up falling damage, but allow sideways acceleration
			return true
		end

		if trace.fraction > 0 then
			-- actually covered some distance
			VectorCopy(trace.endpos, ps.origin)
		end

		if trace.fraction == 1 then
			break -- moved the entire distance
		end

		-- save entity for contact
		B.PM_AddTouchEnt(trace.entityNum)

		time_left = f(time_left - f(time_left * trace.fraction))

		if numplanes >= MAX_CLIP_PLANES then
			-- this shouldn't really happen
			VectorClear(ps.velocity)
			return true
		end

		--
		-- if this is the same plane we hit before, nudge velocity
		-- out along it, which fixes some epsilon issues with
		-- non-axial planes
		--
		i = 0
		while i < numplanes do
			if DotProduct(trace.plane.normal, planes[i]) > 0.99 then
				VectorAdd(trace.plane.normal, ps.velocity, ps.velocity)
				break
			end
			i += 1
		end
		if i < numplanes then
			bumpcount += 1
			continue
		end
		VectorCopy(trace.plane.normal, planes[numplanes])
		numplanes += 1

		--
		-- modify velocity so it parallels all of the clip planes
		--

		-- find a plane that it enters
		i = 0
		while i < numplanes do
			into = DotProduct(ps.velocity, planes[i])
			if into >= 0.1 then
				i += 1
				continue -- move doesn't interact with the plane
			end

			-- see how hard we are hitting things
			if -into > pml.impactSpeed then
				pml.impactSpeed = -into
			end

			-- slide along the plane
			PM_ClipVelocity(ps.velocity, planes[i], clipVelocity, OVERCLIP)

			-- slide along the plane
			PM_ClipVelocity(endVelocity, planes[i], endClipVelocity, OVERCLIP)

			-- see if there is a second plane that the new move enters
			j = 0
			while j < numplanes do
				if j == i then
					j += 1
					continue
				end
				if DotProduct(clipVelocity, planes[j]) >= 0.1 then
					j += 1
					continue -- move doesn't interact with the plane
				end

				-- try clipping the move to the plane
				PM_ClipVelocity(clipVelocity, planes[j], clipVelocity, OVERCLIP)

				PM_ClipVelocity(endClipVelocity, planes[j], endClipVelocity, OVERCLIP)

				-- see if it goes back into the first clip plane
				if DotProduct(clipVelocity, planes[i]) >= 0 then
					j += 1
					continue
				end

				-- slide the original velocity along the crease
				CrossProduct(planes[i], planes[j], dir)
				VectorNormalize(dir)
				d = DotProduct(dir, ps.velocity)
				VectorScale(dir, d, clipVelocity)

				CrossProduct(planes[i], planes[j], dir)
				VectorNormalize(dir)
				d = DotProduct(dir, endVelocity)
				VectorScale(dir, d, endClipVelocity)

				-- see if there is a third plane the the new move enters
				k = 0
				while k < numplanes do
					if k == i or k == j then
						k += 1
						continue
					end
					if DotProduct(clipVelocity, planes[k]) >= 0.1 then
						k += 1
						continue -- move doesn't interact with the plane
					end

					-- stop dead at a tripple plane interaction
					VectorClear(ps.velocity)
					return true
				end
				j += 1
			end

			-- if we have fixed all interactions, try another move
			VectorCopy(clipVelocity, ps.velocity)
			VectorCopy(endClipVelocity, endVelocity)
			break
		end
		bumpcount += 1
	end

	if gravity then
		VectorCopy(endVelocity, ps.velocity)
	end

	-- don't change velocity if in a timer (FIXME: is this correct?)
	if ps.pm_time ~= 0 then
		VectorCopy(primal_velocity, ps.velocity)
	end

	return bumpcount ~= 0
end
B.PM_SlideMove = PM_SlideMove

local start_o, start_v, up, down = vec3(), vec3(), vec3(), vec3()
local strace = S.trace_t()

local function PM_StepSlideMove(gravity: boolean)
	local pm = B.pm
	local ps = pm.ps

	VectorCopy(ps.origin, start_o)
	VectorCopy(ps.velocity, start_v)

	if PM_SlideMove(gravity) == false then
		return -- we got exactly where we wanted to go first try
	end

	VectorCopy(start_o, down)
	down[2] = f(down[2] - STEPSIZE)
	pm.trace(strace, start_o, pm.mins, pm.maxs, down, ps.clientNum, pm.tracemask)
	VectorSet(up, 0, 0, 1)
	-- never step up when you still have up velocity
	if ps.velocity[2] > 0 and (strace.fraction == 1.0 or DotProduct(strace.plane.normal, up) < 0.7) then
		return
	end

	VectorCopy(start_o, up)
	up[2] = f(up[2] + STEPSIZE)

	-- test the player position if they were a stepheight higher
	pm.trace(strace, start_o, pm.mins, pm.maxs, up, ps.clientNum, pm.tracemask)
	if strace.allsolid then
		return -- can't step up
	end

	local stepSize = f(strace.endpos[2] - start_o[2])
	-- try slidemove from this position
	VectorCopy(strace.endpos, ps.origin)
	VectorCopy(start_v, ps.velocity)

	PM_SlideMove(gravity)

	-- push down the final amount
	VectorCopy(ps.origin, down)
	down[2] = f(down[2] - stepSize)
	pm.trace(strace, ps.origin, pm.mins, pm.maxs, down, ps.clientNum, pm.tracemask)
	if not strace.allsolid then
		VectorCopy(strace.endpos, ps.origin)
	end
	if strace.fraction < 1.0 then
		B.PM_ClipVelocity(ps.velocity, strace.plane.normal, ps.velocity, OVERCLIP)
	end

	-- use the step move
	local delta = f(ps.origin[2] - start_o[2])
	if delta > 2 then
		if delta < 7 then
			B.PM_AddEvent(C.EV_STEP_4)
		elseif delta < 11 then
			B.PM_AddEvent(C.EV_STEP_8)
		elseif delta < 15 then
			B.PM_AddEvent(C.EV_STEP_12)
		else
			B.PM_AddEvent(C.EV_STEP_16)
		end
	end
end
B.PM_StepSlideMove = PM_StepSlideMove

return B
