--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/bg_pmove.c).

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
-- Luau port of OpenArena 0.8.8's bg_pmove.c (gamecode 9e0f0c0): takes a playerState and a usercmd and returns a
-- modified playerState. Shared by the server (authoritative) and the client
-- (prediction), so both must call it with identical inputs.
--
-- Float semantics follow the C build exactly (see q_math.luau): each float
-- operation rounds with f(); a float combined with a double literal (0.001,
-- 1.5, 0.0001, 3.0) is computed in double and rounded once where C stores it.

local B = require("./bg_local")
require("./bg_slidemove")
local BGM = require("./bg_misc")
local S = require("../structs")
local Q = require("../q_math")
local C = require("../consts")

local f = Q.f
local band, bor, bxor, bnot, lshift = bit32.band, bit32.bor, bit32.bxor, bit32.bnot, bit32.lshift
local sqrt, abs = math.sqrt, math.abs
local DotProduct, VectorCopy, VectorMA, VectorAdd, VectorSubtract, VectorClear, VectorScale, VectorNormalize, VectorLength, VectorSet =
	Q.DotProduct, Q.VectorCopy, Q.VectorMA, Q.VectorAdd, Q.VectorSubtract, Q.VectorClear, Q.VectorScale, Q.VectorNormalize, Q.VectorLength, Q.VectorSet
local vec3 = Q.vec3
local trunc = Q.trunc
local bg_itemlist = BGM.bg_itemlist

local OVERCLIP = C.OVERCLIP
local MIN_WALK_NORMAL = C.MIN_WALK_NORMAL
local ENTITYNUM_NONE, ENTITYNUM_WORLD = C.ENTITYNUM_NONE, C.ENTITYNUM_WORLD
local ANIM_TOGGLEBIT = C.ANIM_TOGGLEBIT
local PMF_JUMP_HELD, PMF_BACKWARDS_JUMP, PMF_BACKWARDS_RUN, PMF_DUCKED = C.PMF_JUMP_HELD, C.PMF_BACKWARDS_JUMP, C.PMF_BACKWARDS_RUN, C.PMF_DUCKED
local PMF_TIME_LAND, PMF_TIME_KNOCKBACK, PMF_TIME_WATERJUMP, PMF_ALL_TIMES = C.PMF_TIME_LAND, C.PMF_TIME_KNOCKBACK, C.PMF_TIME_WATERJUMP, C.PMF_ALL_TIMES
local PMF_RESPAWNED, PMF_USE_ITEM_HELD, PMF_GRAPPLE_PULL, PMF_INVULEXPAND = C.PMF_RESPAWNED, C.PMF_USE_ITEM_HELD, C.PMF_GRAPPLE_PULL, C.PMF_INVULEXPAND
local PMF_ELIMWARMUP = C.PMF_ELIMWARMUP
local SURF_SLICK = C.SURF_SLICK

local function PM_AddEvent(newEvent: number)
	BGM.BG_AddPredictableEventToPlayerstate(newEvent, 0, B.pm.ps)
end
B.PM_AddEvent = PM_AddEvent

local function PM_AddTouchEnt(entityNum: number)
	local pm = B.pm
	if entityNum == ENTITYNUM_WORLD then
		return
	end
	if pm.numtouch == C.MAXTOUCH then
		return
	end

	-- see if it is already added
	for i = 0, pm.numtouch - 1 do
		if pm.touchents[i] == entityNum then
			return
		end
	end

	-- add it
	pm.touchents[pm.numtouch] = entityNum
	pm.numtouch += 1
end
B.PM_AddTouchEnt = PM_AddTouchEnt

local function PM_StartTorsoAnim(anim: number)
	local ps = B.pm.ps
	if ps.pm_type >= C.PM_DEAD then
		return
	end
	ps.torsoAnim = bor(bxor(band(ps.torsoAnim, ANIM_TOGGLEBIT), ANIM_TOGGLEBIT), anim)
end
local function PM_StartLegsAnim(anim: number)
	local ps = B.pm.ps
	if ps.pm_type >= C.PM_DEAD then
		return
	end
	if ps.legsTimer > 0 then
		return -- a high priority animation is running
	end
	ps.legsAnim = bor(bxor(band(ps.legsAnim, ANIM_TOGGLEBIT), ANIM_TOGGLEBIT), anim)
end

local function PM_ContinueLegsAnim(anim: number)
	local ps = B.pm.ps
	if band(ps.legsAnim, bnot(ANIM_TOGGLEBIT)) == anim then
		return
	end
	if ps.legsTimer > 0 then
		return -- a high priority animation is running
	end
	PM_StartLegsAnim(anim)
end

local function PM_ContinueTorsoAnim(anim: number)
	local ps = B.pm.ps
	if band(ps.torsoAnim, bnot(ANIM_TOGGLEBIT)) == anim then
		return
	end
	if ps.torsoTimer > 0 then
		return -- a high priority animation is running
	end
	PM_StartTorsoAnim(anim)
end

local function PM_ForceLegsAnim(anim: number)
	B.pm.ps.legsTimer = 0
	PM_StartLegsAnim(anim)
end

-- Slide off of the impacting surface
local function PM_ClipVelocity(inv, normal, out, overbounce: number)
	local backoff = DotProduct(inv, normal)

	if backoff < 0 then
		backoff = f(backoff * overbounce)
	else
		backoff = f(backoff / overbounce)
	end

	for i = 0, 2 do
		local change = f(normal[i] * backoff)
		out[i] = f(inv[i] - change)
	end
end
B.PM_ClipVelocity = PM_ClipVelocity

-- Handles both ground friction and water friction
local fvec = vec3()
local function PM_Friction()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps
	local vel = ps.velocity

	VectorCopy(vel, fvec)
	if pml.walking then
		fvec[2] = 0 -- ignore slope movement
	end

	local speed = VectorLength(fvec)
	if speed < 1 then
		vel[0] = 0
		vel[1] = 0 -- allow sinking underwater
		-- FIXME: still have z friction underwater?
		return
	end

	local drop = 0

	-- apply ground friction
	if pm.waterlevel <= 1 then
		if pml.walking and band(pml.groundTrace.surfaceFlags, SURF_SLICK) == 0 then
			-- if getting knocked back, no friction
			if band(ps.pm_flags, PMF_TIME_KNOCKBACK) == 0 then
				local control = if speed < B.pm_stopspeed then B.pm_stopspeed else speed
				drop = f(drop + f(f(control * B.pm_friction) * pml.frametime))
			end
		end
	end

	-- apply water friction even if just wading
	if pm.waterlevel ~= 0 then
		drop = f(drop + f(f(f(speed * B.pm_waterfriction) * pm.waterlevel) * pml.frametime))
	end

	-- apply flying friction
	if ps.powerups[C.PW_FLIGHT] ~= 0 then
		drop = f(drop + f(f(speed * B.pm_flightfriction) * pml.frametime))
	end

	if ps.pm_type == C.PM_SPECTATOR then
		drop = f(drop + f(f(speed * B.pm_spectatorfriction) * pml.frametime))
	end

	-- scale the velocity
	local newspeed = f(speed - drop)
	if newspeed < 0 then
		newspeed = 0
	end
	newspeed = f(newspeed / speed)

	vel[0] = f(vel[0] * newspeed)
	vel[1] = f(vel[1] * newspeed)
	vel[2] = f(vel[2] * newspeed)
end

-- Handles user intended acceleration
local wishVelocity, pushDir = vec3(), vec3()
local function PM_Accelerate(wishdir, wishspeed: number, accel: number)
	local pm, pml = B.pm, B.pml
	local ps = pm.ps
	if band(pm.pmove_flags, C.DF_NO_BUNNY) == 0 then
		-- q2 style
		local currentspeed = DotProduct(ps.velocity, wishdir)
		local addspeed = f(wishspeed - currentspeed)
		if addspeed <= 0 then
			return
		end
		local accelspeed = f(f(accel * pml.frametime) * wishspeed)
		if accelspeed > addspeed then
			accelspeed = addspeed
		end

		for i = 0, 2 do
			ps.velocity[i] = f(ps.velocity[i] + f(accelspeed * wishdir[i]))
		end
	else
		-- proper way (avoids strafe jump maxspeed bug), but feels bad
		VectorScale(wishdir, wishspeed, wishVelocity)
		VectorSubtract(wishVelocity, ps.velocity, pushDir)
		local pushLen = VectorNormalize(pushDir)

		local canPush = f(f(accel * pml.frametime) * wishspeed)
		if canPush > pushLen then
			canPush = pushLen
		end

		VectorMA(ps.velocity, canPush, pushDir, ps.velocity)
	end
end

-- Returns the scale factor to apply to cmd movements
-- This allows the clients to use axial -127 to 127 values for all directions
-- without getting a sqrt(2) distortion in speed.
local function PM_CmdScale(cmd): number
	local max = abs(cmd.forwardmove)
	if abs(cmd.rightmove) > max then
		max = abs(cmd.rightmove)
	end
	if abs(cmd.upmove) > max then
		max = abs(cmd.upmove)
	end
	if max == 0 then
		return 0
	end

	local total = f(sqrt(cmd.forwardmove * cmd.forwardmove + cmd.rightmove * cmd.rightmove + cmd.upmove * cmd.upmove))
	local scale = f(f(B.pm.ps.speed * max) / (127.0 * total))

	return scale
end

-- Determine the rotation of the legs reletive to the facing dir
local function PM_SetMovementDir()
	local pm = B.pm
	local ps, cmd = pm.ps, pm.cmd
	if cmd.forwardmove ~= 0 or cmd.rightmove ~= 0 then
		if cmd.rightmove == 0 and cmd.forwardmove > 0 then
			ps.movementDir = 0
		elseif cmd.rightmove < 0 and cmd.forwardmove > 0 then
			ps.movementDir = 1
		elseif cmd.rightmove < 0 and cmd.forwardmove == 0 then
			ps.movementDir = 2
		elseif cmd.rightmove < 0 and cmd.forwardmove < 0 then
			ps.movementDir = 3
		elseif cmd.rightmove == 0 and cmd.forwardmove < 0 then
			ps.movementDir = 4
		elseif cmd.rightmove > 0 and cmd.forwardmove < 0 then
			ps.movementDir = 5
		elseif cmd.rightmove > 0 and cmd.forwardmove == 0 then
			ps.movementDir = 6
		elseif cmd.rightmove > 0 and cmd.forwardmove > 0 then
			ps.movementDir = 7
		end
	else
		-- if they aren't actively going directly sideways,
		-- change the animation to the diagonal so they
		-- don't stop too crooked
		if ps.movementDir == 2 then
			ps.movementDir = 1
		elseif ps.movementDir == 6 then
			ps.movementDir = 7
		end
	end
end

local function PM_CheckJump(): boolean
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	if band(ps.pm_flags, PMF_RESPAWNED) ~= 0 then
		return false -- don't allow jump until all buttons are up
	end

	if pm.cmd.upmove < 10 then
		-- not holding jump
		return false
	end

	-- must wait for jump to be released
	if band(ps.pm_flags, PMF_JUMP_HELD) ~= 0 then
		-- clear upmove so cmdscale doesn't lower running speed
		pm.cmd.upmove = 0
		return false
	end

	pml.groundPlane = false -- jumping away
	pml.walking = false
	ps.pm_flags = bor(ps.pm_flags, PMF_JUMP_HELD)

	ps.groundEntityNum = ENTITYNUM_NONE
	ps.velocity[2] = C.JUMP_VELOCITY
	PM_AddEvent(C.EV_JUMP)

	if pm.cmd.forwardmove >= 0 then
		PM_ForceLegsAnim(C.LEGS_JUMP)
		ps.pm_flags = band(ps.pm_flags, bnot(PMF_BACKWARDS_JUMP))
	else
		PM_ForceLegsAnim(C.LEGS_JUMPB)
		ps.pm_flags = bor(ps.pm_flags, PMF_BACKWARDS_JUMP)
	end

	return true
end

local spot, flatforward = vec3(), vec3()
local function PM_CheckWaterJump(): boolean
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	if ps.pm_time ~= 0 then
		return false
	end

	-- check for water jump
	if pm.waterlevel ~= 2 then
		return false
	end

	flatforward[0] = pml.forward[0]
	flatforward[1] = pml.forward[1]
	flatforward[2] = 0
	VectorNormalize(flatforward)

	VectorMA(ps.origin, 30, flatforward, spot)
	spot[2] = f(spot[2] + 4)
	local cont = pm.pointcontents(spot, ps.clientNum)
	if band(cont, C.CONTENTS_SOLID) == 0 then
		return false
	end

	spot[2] = f(spot[2] + 16)
	cont = pm.pointcontents(spot, ps.clientNum)
	if band(cont, bor(C.CONTENTS_SOLID, C.CONTENTS_PLAYERCLIP, C.CONTENTS_BODY)) ~= 0 then
		return false
	end

	-- jump out of water
	VectorScale(pml.forward, 200, ps.velocity)
	ps.velocity[2] = 350

	ps.pm_flags = bor(ps.pm_flags, PMF_TIME_WATERJUMP)
	ps.pm_time = 2000

	return true
end

--============================================================================

-- Flying out of the water
local function PM_WaterJumpMove()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps
	-- waterjump has no control, but falls

	B.PM_StepSlideMove(true)

	ps.velocity[2] = f(ps.velocity[2] - f(ps.gravity * pml.frametime))
	if ps.velocity[2] < 0 then
		-- cancel as soon as we are falling down again
		ps.pm_flags = band(ps.pm_flags, bnot(PMF_ALL_TIMES))
		ps.pm_time = 0
	end
end

local wishvel, wishdir = vec3(), vec3()

local function PM_WaterMove()
	local pm, pml = B.pm, B.pml
	local ps, cmd = pm.ps, pm.cmd

	if PM_CheckWaterJump() then
		PM_WaterJumpMove()
		return
	end
	PM_Friction()

	local scale = PM_CmdScale(cmd)
	--
	-- user intentions
	--
	if scale == 0 then
		wishvel[0] = 0
		wishvel[1] = 0
		wishvel[2] = -60 -- sink towards bottom
	else
		for i = 0, 2 do
			wishvel[i] = f(f(f(scale * pml.forward[i]) * cmd.forwardmove) + f(f(scale * pml.right[i]) * cmd.rightmove))
		end

		wishvel[2] = f(wishvel[2] + f(scale * cmd.upmove))
	end

	VectorCopy(wishvel, wishdir)
	local wishspeed = VectorNormalize(wishdir)

	if wishspeed > f(ps.speed * B.pm_swimScale) then
		wishspeed = f(ps.speed * B.pm_swimScale)
	end

	PM_Accelerate(wishdir, wishspeed, B.pm_wateraccelerate)

	-- make sure we can go up slopes easily under water
	if pml.groundPlane and DotProduct(ps.velocity, pml.groundTrace.plane.normal) < 0 then
		local vel = VectorLength(ps.velocity)
		-- slide along the ground plane
		PM_ClipVelocity(ps.velocity, pml.groundTrace.plane.normal, ps.velocity, OVERCLIP)

		VectorNormalize(ps.velocity)
		VectorScale(ps.velocity, vel, ps.velocity)
	end

	B.PM_SlideMove(false)
end

-- Only with the invulnerability powerup
local function PM_InvulnerabilityMove()
	local pm = B.pm
	pm.cmd.forwardmove = 0
	pm.cmd.rightmove = 0
	pm.cmd.upmove = 0
	VectorClear(pm.ps.velocity)
end

-- Only with the flight powerup
local function PM_FlyMove()
	local pm, pml = B.pm, B.pml
	local cmd = pm.cmd

	-- normal slowdown
	PM_Friction()

	local scale = PM_CmdScale(cmd)
	--
	-- user intentions
	--
	if scale == 0 then
		wishvel[0] = 0
		wishvel[1] = 0
		wishvel[2] = 0
	else
		for i = 0, 2 do
			wishvel[i] = f(f(f(scale * pml.forward[i]) * cmd.forwardmove) + f(f(scale * pml.right[i]) * cmd.rightmove))
		end

		wishvel[2] = f(wishvel[2] + f(scale * cmd.upmove))
	end

	VectorCopy(wishvel, wishdir)
	local wishspeed = VectorNormalize(wishdir)

	PM_Accelerate(wishdir, wishspeed, B.pm_flyaccelerate)

	B.PM_StepSlideMove(false)
end

local function PM_AirMove()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	PM_Friction()

	local fmove = pm.cmd.forwardmove
	local smove = pm.cmd.rightmove

	-- (C copies pm->cmd first; PM_CmdScale does not modify it)
	local scale = PM_CmdScale(pm.cmd)

	-- set the movementDir so clients can rotate the legs for strafing
	PM_SetMovementDir()

	-- project moves down to flat plane
	pml.forward[2] = 0
	pml.right[2] = 0
	VectorNormalize(pml.forward)
	VectorNormalize(pml.right)

	for i = 0, 1 do
		wishvel[i] = f(f(pml.forward[i] * fmove) + f(pml.right[i] * smove))
	end
	wishvel[2] = 0

	VectorCopy(wishvel, wishdir)
	local wishspeed = VectorNormalize(wishdir)
	wishspeed = f(wishspeed * scale)

	-- not on ground, so little effect on velocity
	PM_Accelerate(wishdir, wishspeed, B.pm_airaccelerate)

	-- we may have a ground plane that is very steep, even
	-- though we don't have a groundentity
	-- slide along the steep plane
	if pml.groundPlane then
		PM_ClipVelocity(ps.velocity, pml.groundTrace.plane.normal, ps.velocity, OVERCLIP)
	end

	B.PM_StepSlideMove(true)
end

local gvel, gv = vec3(), vec3()
local function PM_GrappleMove()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	VectorScale(pml.forward, -16, gv)
	VectorAdd(ps.grapplePoint, gv, gv)
	VectorSubtract(gv, ps.origin, gvel)
	local vlen = VectorLength(gvel)
	VectorNormalize(gvel)

	if vlen <= 100 then
		VectorScale(gvel, f(10 * vlen), gvel)
	else
		VectorScale(gvel, 800, gvel)
	end

	VectorCopy(gvel, ps.velocity)

	pml.groundPlane = false
end

local function PM_WalkMove()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	if pm.waterlevel > 2 and DotProduct(pml.forward, pml.groundTrace.plane.normal) > 0 then
		-- begin swimming
		PM_WaterMove()
		return
	end

	if PM_CheckJump() then
		-- jumped away
		if pm.waterlevel > 1 then
			PM_WaterMove()
		else
			PM_AirMove()
		end
		return
	end

	PM_Friction()

	local fmove = pm.cmd.forwardmove
	local smove = pm.cmd.rightmove

	local scale = PM_CmdScale(pm.cmd)

	-- set the movementDir so clients can rotate the legs for strafing
	PM_SetMovementDir()

	-- project moves down to flat plane
	pml.forward[2] = 0
	pml.right[2] = 0

	-- project the forward and right directions onto the ground plane
	PM_ClipVelocity(pml.forward, pml.groundTrace.plane.normal, pml.forward, OVERCLIP)
	PM_ClipVelocity(pml.right, pml.groundTrace.plane.normal, pml.right, OVERCLIP)
	--
	VectorNormalize(pml.forward)
	VectorNormalize(pml.right)

	for i = 0, 2 do
		wishvel[i] = f(f(pml.forward[i] * fmove) + f(pml.right[i] * smove))
	end

	VectorCopy(wishvel, wishdir)
	local wishspeed = VectorNormalize(wishdir)
	wishspeed = f(wishspeed * scale)

	-- clamp the speed lower if ducking
	if band(ps.pm_flags, PMF_DUCKED) ~= 0 then
		if wishspeed > f(ps.speed * B.pm_duckScale) then
			wishspeed = f(ps.speed * B.pm_duckScale)
		end
	end

	-- clamp the speed lower if wading or walking on the bottom
	if pm.waterlevel ~= 0 then
		local waterScale = f(pm.waterlevel / 3.0)
		waterScale = f(1.0 - (1.0 - B.pm_swimScale) * waterScale)
		if wishspeed > f(ps.speed * waterScale) then
			wishspeed = f(ps.speed * waterScale)
		end
	end

	-- when a player gets hit, they temporarily lose
	-- full control, which allows them to be moved a bit
	local accelerate
	local slick = band(pml.groundTrace.surfaceFlags, SURF_SLICK) ~= 0 or band(ps.pm_flags, PMF_TIME_KNOCKBACK) ~= 0
	if slick then
		accelerate = B.pm_airaccelerate
	else
		accelerate = B.pm_accelerate
	end

	PM_Accelerate(wishdir, wishspeed, accelerate)

	if slick then
		ps.velocity[2] = f(ps.velocity[2] - f(ps.gravity * pml.frametime))
	end

	local vel = VectorLength(ps.velocity)

	-- slide along the ground plane
	PM_ClipVelocity(ps.velocity, pml.groundTrace.plane.normal, ps.velocity, OVERCLIP)

	-- don't decrease velocity when going up or down a slope
	VectorNormalize(ps.velocity)
	VectorScale(ps.velocity, vel, ps.velocity)

	-- don't do anything if standing still
	if ps.velocity[0] == 0 and ps.velocity[1] == 0 then
		return
	end

	B.PM_StepSlideMove(false)
end

local function PM_DeadMove()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	if not pml.walking then
		return
	end

	-- extra friction

	local forward = VectorLength(ps.velocity)
	forward = f(forward - 20)
	if forward <= 0 then
		VectorClear(ps.velocity)
	else
		VectorNormalize(ps.velocity)
		VectorScale(ps.velocity, forward, ps.velocity)
	end
end

local function PM_NoclipMove()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	ps.viewheight = C.DEFAULT_VIEWHEIGHT

	-- friction

	local speed = VectorLength(ps.velocity)
	if speed < 1 then
		VectorCopy(Q.vec3_origin, ps.velocity)
	else
		local drop = 0

		local friction = f(B.pm_friction * 1.5) -- extra friction
		local control = if speed < B.pm_stopspeed then B.pm_stopspeed else speed
		drop = f(drop + f(f(control * friction) * pml.frametime))

		-- scale the velocity
		local newspeed = f(speed - drop)
		if newspeed < 0 then
			newspeed = 0
		end
		newspeed = f(newspeed / speed)

		VectorScale(ps.velocity, newspeed, ps.velocity)
	end

	-- accelerate
	local scale = PM_CmdScale(pm.cmd)

	local fmove = pm.cmd.forwardmove
	local smove = pm.cmd.rightmove

	for i = 0, 2 do
		wishvel[i] = f(f(pml.forward[i] * fmove) + f(pml.right[i] * smove))
	end
	wishvel[2] = f(wishvel[2] + pm.cmd.upmove)

	VectorCopy(wishvel, wishdir)
	local wishspeed = VectorNormalize(wishdir)
	wishspeed = f(wishspeed * scale)

	PM_Accelerate(wishdir, wishspeed, B.pm_accelerate)

	-- move
	VectorMA(ps.origin, pml.frametime, ps.velocity, ps.origin)
end

--============================================================================

-- Returns an event number apropriate for the groundsurface
local function PM_FootstepForSurface(): number
	local sf = B.pml.groundTrace.surfaceFlags
	if band(sf, C.SURF_NOSTEPS) ~= 0 then
		return 0
	end
	if band(sf, C.SURF_METALSTEPS) ~= 0 then
		return C.EV_FOOTSTEP_METAL
	end
	return C.EV_FOOTSTEP
end

-- Check for hard landings that generate sound events
local function PM_CrashLand()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	-- decide which landing animation to use
	if band(ps.pm_flags, PMF_BACKWARDS_JUMP) ~= 0 then
		PM_ForceLegsAnim(C.LEGS_LANDB)
	else
		PM_ForceLegsAnim(C.LEGS_LAND)
	end

	ps.legsTimer = C.TIMER_LAND

	-- calculate the exact velocity on landing
	local dist = f(ps.origin[2] - pml.previous_origin[2])
	local vel = pml.previous_velocity[2]
	local acc = -ps.gravity

	local a = f(acc / 2)
	local b = vel
	local c = -dist

	local den = f(f(b * b) - f(f(4 * a) * c))
	if den < 0 then
		return
	end
	local t = f((-b - sqrt(den)) / f(2 * a))

	local delta = f(vel + f(t * acc))
	delta = f(f(delta * delta) * 0.0001)

	-- ducking while falling doubles damage
	if band(ps.pm_flags, PMF_DUCKED) ~= 0 then
		delta = f(delta * 2)
	end

	-- never take falling damage if completely underwater
	if pm.waterlevel == 3 then
		return
	end

	-- reduce falling damage if there is standing water
	if pm.waterlevel == 2 then
		delta = f(delta * 0.25)
	end
	if pm.waterlevel == 1 then
		delta = f(delta * 0.5)
	end

	if delta < 1 then
		return
	end

	-- create a local entity event to play the sound

	-- SURF_NODAMAGE is used for bounce pads where you don't ever
	-- want to take damage or play a crunch sound
	if band(pml.groundTrace.surfaceFlags, C.SURF_NODAMAGE) == 0 then
		if delta > 60 then
			PM_AddEvent(C.EV_FALL_FAR)
		elseif delta > 40 then
			-- this is a pain grunt, so don't play it if dead
			if ps.stats[C.STAT_HEALTH] > 0 then
				PM_AddEvent(C.EV_FALL_MEDIUM)
			end
		elseif delta > 7 then
			PM_AddEvent(C.EV_FALL_SHORT)
		else
			PM_AddEvent(PM_FootstepForSurface())
		end
	end

	-- start footstep cycle over
	ps.bobCycle = 0
end

local point = vec3()
local function PM_CorrectAllSolid(trace): boolean
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	-- jitter around
	for i = -1, 1 do
		for j = -1, 1 do
			for k = -1, 1 do
				VectorCopy(ps.origin, point)
				point[0] = f(point[0] + i)
				point[1] = f(point[1] + j)
				point[2] = f(point[2] + k)
				pm.trace(trace, point, pm.mins, pm.maxs, point, ps.clientNum, pm.tracemask)
				if not trace.allsolid then
					point[0] = ps.origin[0]
					point[1] = ps.origin[1]
					point[2] = f(ps.origin[2] - 0.25)

					pm.trace(trace, ps.origin, pm.mins, pm.maxs, point, ps.clientNum, pm.tracemask)
					S.copy_trace_t(pml.groundTrace, trace)
					return true
				end
			end
		end
	end

	ps.groundEntityNum = ENTITYNUM_NONE
	pml.groundPlane = false
	pml.walking = false

	return false
end

-- The ground trace didn't hit a surface, so we are in freefall
local mtrace = S.trace_t()
local function PM_GroundTraceMissed()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	if ps.groundEntityNum ~= ENTITYNUM_NONE then
		-- we just transitioned into freefall

		-- if they aren't in a jumping animation and the ground is a ways away, force into it
		-- if we didn't do the trace, the player would be backflipping down staircases
		VectorCopy(ps.origin, point)
		point[2] = f(point[2] - 64)

		pm.trace(mtrace, ps.origin, pm.mins, pm.maxs, point, ps.clientNum, pm.tracemask)
		if mtrace.fraction == 1.0 then
			if pm.cmd.forwardmove >= 0 then
				PM_ForceLegsAnim(C.LEGS_JUMP)
				ps.pm_flags = band(ps.pm_flags, bnot(PMF_BACKWARDS_JUMP))
			else
				PM_ForceLegsAnim(C.LEGS_JUMPB)
				ps.pm_flags = bor(ps.pm_flags, PMF_BACKWARDS_JUMP)
			end
		end
	end

	ps.groundEntityNum = ENTITYNUM_NONE
	pml.groundPlane = false
	pml.walking = false
end

local gtrace = S.trace_t()
local gpoint = vec3()
local function PM_GroundTrace()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps
	local trace = gtrace

	gpoint[0] = ps.origin[0]
	gpoint[1] = ps.origin[1]
	gpoint[2] = f(ps.origin[2] - 0.25)

	pm.trace(trace, ps.origin, pm.mins, pm.maxs, gpoint, ps.clientNum, pm.tracemask)
	S.copy_trace_t(pml.groundTrace, trace)

	-- do something corrective if the trace starts in a solid...
	if trace.allsolid then
		if not PM_CorrectAllSolid(trace) then
			return
		end
	end

	-- if the trace didn't hit anything, we are in free fall
	if trace.fraction == 1.0 then
		PM_GroundTraceMissed()
		pml.groundPlane = false
		pml.walking = false
		return
	end

	-- check if getting thrown off the ground
	if ps.velocity[2] > 0 and DotProduct(ps.velocity, trace.plane.normal) > 10 then
		-- go into jump animation
		if pm.cmd.forwardmove >= 0 then
			PM_ForceLegsAnim(C.LEGS_JUMP)
			ps.pm_flags = band(ps.pm_flags, bnot(PMF_BACKWARDS_JUMP))
		else
			PM_ForceLegsAnim(C.LEGS_JUMPB)
			ps.pm_flags = bor(ps.pm_flags, PMF_BACKWARDS_JUMP)
		end

		ps.groundEntityNum = ENTITYNUM_NONE
		pml.groundPlane = false
		pml.walking = false
		return
	end

	-- slopes that are too steep will not be considered onground
	if trace.plane.normal[2] < MIN_WALK_NORMAL then
		-- FIXME: if they can't slide down the slope, let them
		-- walk (sharp crevices)
		ps.groundEntityNum = ENTITYNUM_NONE
		pml.groundPlane = true
		pml.walking = false
		return
	end

	pml.groundPlane = true
	pml.walking = true

	-- hitting solid ground will end a waterjump
	if band(ps.pm_flags, PMF_TIME_WATERJUMP) ~= 0 then
		ps.pm_flags = band(ps.pm_flags, bnot(bor(PMF_TIME_WATERJUMP, PMF_TIME_LAND)))
		ps.pm_time = 0
	end

	if ps.groundEntityNum == ENTITYNUM_NONE then
		-- just hit the ground
		PM_CrashLand()

		-- don't do landing time if we were just going down a slope
		if pml.previous_velocity[2] < -200 then
			-- don't allow another jump for a little while
			ps.pm_flags = bor(ps.pm_flags, PMF_TIME_LAND)
			ps.pm_time = 250
		end
	end

	ps.groundEntityNum = trace.entityNum

	PM_AddTouchEnt(trace.entityNum)
end

-- FIXME: avoid this twice?  certainly if not moving
local wpoint = vec3()
local function PM_SetWaterLevel()
	local pm = B.pm
	local ps = pm.ps
	local MASK_WATER = C.MASK_WATER

	--
	-- get waterlevel, accounting for ducking
	--
	pm.waterlevel = 0
	pm.watertype = 0

	wpoint[0] = ps.origin[0]
	wpoint[1] = ps.origin[1]
	wpoint[2] = f(f(ps.origin[2] + C.MINS_Z) + 1)
	local cont = pm.pointcontents(wpoint, ps.clientNum)

	if band(cont, MASK_WATER) ~= 0 then
		local sample2 = ps.viewheight - C.MINS_Z
		local sample1 = Q.idiv(sample2, 2)

		pm.watertype = cont
		pm.waterlevel = 1
		wpoint[2] = f(f(ps.origin[2] + C.MINS_Z) + sample1)
		cont = pm.pointcontents(wpoint, ps.clientNum)
		if band(cont, MASK_WATER) ~= 0 then
			pm.waterlevel = 2
			wpoint[2] = f(f(ps.origin[2] + C.MINS_Z) + sample2)
			cont = pm.pointcontents(wpoint, ps.clientNum)
			if band(cont, MASK_WATER) ~= 0 then
				pm.waterlevel = 3
			end
		end
	end
end

-- Sets mins, maxs, and pm->ps->viewheight
local dtrace = S.trace_t()
local function PM_CheckDuck()
	local pm = B.pm
	local ps = pm.ps

	if ps.powerups[C.PW_INVULNERABILITY] ~= 0 then
		if band(ps.pm_flags, PMF_INVULEXPAND) ~= 0 then
			-- invulnerability sphere has a 42 units radius
			VectorSet(pm.mins, -42, -42, -42)
			VectorSet(pm.maxs, 42, 42, 42)
		else
			VectorSet(pm.mins, -15, -15, C.MINS_Z)
			VectorSet(pm.maxs, 15, 15, 16)
		end
		ps.pm_flags = bor(ps.pm_flags, PMF_DUCKED)
		ps.viewheight = C.CROUCH_VIEWHEIGHT
		return
	end
	ps.pm_flags = band(ps.pm_flags, bnot(PMF_INVULEXPAND))

	pm.mins[0] = -15
	pm.mins[1] = -15

	pm.maxs[0] = 15
	pm.maxs[1] = 15

	pm.mins[2] = C.MINS_Z

	if ps.pm_type == C.PM_DEAD then
		pm.maxs[2] = -8
		ps.viewheight = C.DEAD_VIEWHEIGHT
		return
	end

	if pm.cmd.upmove < 0 then
		-- duck
		ps.pm_flags = bor(ps.pm_flags, PMF_DUCKED)
	else
		-- stand up if possible
		if band(ps.pm_flags, PMF_DUCKED) ~= 0 then
			-- try to stand up
			pm.maxs[2] = 32
			pm.trace(dtrace, ps.origin, pm.mins, pm.maxs, ps.origin, ps.clientNum, pm.tracemask)
			if not dtrace.allsolid then
				ps.pm_flags = band(ps.pm_flags, bnot(PMF_DUCKED))
			end
		end
	end

	if band(ps.pm_flags, PMF_DUCKED) ~= 0 then
		pm.maxs[2] = 16
		ps.viewheight = C.CROUCH_VIEWHEIGHT
	else
		pm.maxs[2] = 32
		ps.viewheight = C.DEFAULT_VIEWHEIGHT
	end
end

--===================================================================

local BOB_04, BOB_03 = f(0.4), f(0.3)

local function PM_Footsteps()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps
	local bobmove

	--
	-- calculate speed and cycle to be used for
	-- all cyclic walking effects
	--
	pm.xyspeed = f(sqrt(f(f(ps.velocity[0] * ps.velocity[0]) + f(ps.velocity[1] * ps.velocity[1]))))

	if ps.groundEntityNum == ENTITYNUM_NONE then
		if ps.powerups[C.PW_INVULNERABILITY] ~= 0 then
			PM_ContinueLegsAnim(C.LEGS_IDLECR)
		end
		-- airborne leaves position in cycle intact, but doesn't advance
		if pm.waterlevel > 1 then
			PM_ContinueLegsAnim(C.LEGS_SWIM)
		end
		return
	end

	-- if not trying to move
	if pm.cmd.forwardmove == 0 and pm.cmd.rightmove == 0 then
		if pm.xyspeed < 5 then
			ps.bobCycle = 0 -- start at beginning of cycle again
			if band(ps.pm_flags, PMF_DUCKED) ~= 0 then
				PM_ContinueLegsAnim(C.LEGS_IDLECR)
			else
				PM_ContinueLegsAnim(C.LEGS_IDLE)
			end
		end
		return
	end

	local footstep = false

	if band(ps.pm_flags, PMF_DUCKED) ~= 0 then
		bobmove = 0.5 -- ducked characters bob much faster
		if band(ps.pm_flags, PMF_BACKWARDS_RUN) ~= 0 then
			PM_ContinueLegsAnim(C.LEGS_BACKCR)
		else
			PM_ContinueLegsAnim(C.LEGS_WALKCR)
		end
	else
		if band(pm.cmd.buttons, C.BUTTON_WALKING) == 0 then
			bobmove = BOB_04 -- faster speeds bob faster
			if band(ps.pm_flags, PMF_BACKWARDS_RUN) ~= 0 then
				PM_ContinueLegsAnim(C.LEGS_BACK)
			else
				PM_ContinueLegsAnim(C.LEGS_RUN)
			end
			footstep = true
		else
			bobmove = BOB_03 -- walking bobs slow
			if band(ps.pm_flags, PMF_BACKWARDS_RUN) ~= 0 then
				PM_ContinueLegsAnim(C.LEGS_BACKWALK)
			else
				PM_ContinueLegsAnim(C.LEGS_WALK)
			end
		end
	end

	-- check for footstep / splash sounds
	local old = ps.bobCycle
	ps.bobCycle = band(trunc(f(old + f(bobmove * pml.msec))), 255)

	-- if we just crossed a cycle boundary, play an apropriate footstep event
	if band(bxor(old + 64, ps.bobCycle + 64), 128) ~= 0 then
		if pm.waterlevel == 0 then
			-- on ground will only play sounds if running
			if footstep and not pm.noFootsteps then
				PM_AddEvent(PM_FootstepForSurface())
			end
		elseif pm.waterlevel == 1 then
			-- splashing
			PM_AddEvent(C.EV_FOOTSPLASH)
		elseif pm.waterlevel == 2 then
			-- wading / swimming at surface
			PM_AddEvent(C.EV_SWIM)
		end
		-- waterlevel 3: no sound when completely underwater
	end
end

-- Generate sound events for entering and leaving water
local function PM_WaterEvents() -- FIXME?
	local pm, pml = B.pm, B.pml
	--
	-- if just entered a water volume, play a sound
	--
	if pml.previous_waterlevel == 0 and pm.waterlevel ~= 0 then
		PM_AddEvent(C.EV_WATER_TOUCH)
	end

	--
	-- if just completely exited a water volume, play a sound
	--
	if pml.previous_waterlevel ~= 0 and pm.waterlevel == 0 then
		PM_AddEvent(C.EV_WATER_LEAVE)
	end

	--
	-- check for head just going under water
	--
	if pml.previous_waterlevel ~= 3 and pm.waterlevel == 3 then
		PM_AddEvent(C.EV_WATER_UNDER)
	end

	--
	-- check for head just coming out of water
	--
	if pml.previous_waterlevel == 3 and pm.waterlevel ~= 3 then
		PM_AddEvent(C.EV_WATER_CLEAR)
	end
end

local function PM_BeginWeaponChange(weapon: number)
	local pm = B.pm
	local ps = pm.ps
	if weapon <= C.WP_NONE or weapon >= C.WP_NUM_WEAPONS then
		return
	end

	if band(ps.stats[C.STAT_WEAPONS], lshift(1, weapon)) == 0 then
		return
	end

	if ps.weaponstate == C.WEAPON_DROPPING then
		return
	end

	if band(pm.pmove_flags, C.DF_INSTANT_WEAPON_CHANGE) ~= 0 then
		ps.weaponstate = C.WEAPON_DROPPING
	else
		PM_AddEvent(C.EV_CHANGE_WEAPON)
		ps.weaponstate = C.WEAPON_DROPPING
		ps.weaponTime += 200
		PM_StartTorsoAnim(C.TORSO_DROP)
	end
end

local function PM_FinishWeaponChange()
	local pm = B.pm
	local ps = pm.ps

	local weapon = pm.cmd.weapon
	if weapon < C.WP_NONE or weapon >= C.WP_NUM_WEAPONS then
		weapon = C.WP_NONE
	end

	if band(ps.stats[C.STAT_WEAPONS], lshift(1, weapon)) == 0 then
		weapon = C.WP_NONE
	end

	ps.weapon = weapon
	ps.weaponstate = C.WEAPON_RAISING
	if band(pm.pmove_flags, C.DF_INSTANT_WEAPON_CHANGE) == 0 then
		ps.weaponTime += 250
		PM_StartTorsoAnim(C.TORSO_RAISE)
	end
end

local function PM_TorsoAnimation()
	local ps = B.pm.ps
	if ps.weaponstate == C.WEAPON_READY then
		if ps.weapon == C.WP_GAUNTLET then
			PM_ContinueTorsoAnim(C.TORSO_STAND2)
		else
			PM_ContinueTorsoAnim(C.TORSO_STAND)
		end
		return
	end
end

local ADDTIME = {
	[C.WP_GAUNTLET] = 400,
	[C.WP_LIGHTNING] = 50,
	[C.WP_SHOTGUN] = 1000,
	[C.WP_MACHINEGUN] = 100,
	[C.WP_GRENADE_LAUNCHER] = 800,
	[C.WP_ROCKET_LAUNCHER] = 800,
	[C.WP_PLASMAGUN] = 100,
	[C.WP_RAILGUN] = 1500,
	[C.WP_BFG] = 200,
	[C.WP_GRAPPLING_HOOK] = 400,
	[C.WP_NAILGUN] = 1000,
	[C.WP_PROX_LAUNCHER] = 800,
	[C.WP_CHAINGUN] = 30,
}

-- Generates weapon events and modifes the weapon counter
local function PM_Weapon()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps

	-- don't allow attack until all buttons are up
	if band(ps.pm_flags, PMF_RESPAWNED) ~= 0 then
		return
	end

	-- ignore if spectator
	if ps.persistant[C.PERS_TEAM] == C.TEAM_SPECTATOR or ps.pm_type == C.PM_SPECTATOR then
		return
	end

	-- check for dead player
	if ps.stats[C.STAT_HEALTH] <= 0 then
		ps.weapon = C.WP_NONE
		return
	end

	-- check for item using
	if band(pm.cmd.buttons, C.BUTTON_USE_HOLDABLE) ~= 0 then
		if band(ps.pm_flags, PMF_USE_ITEM_HELD) == 0 then
			local it = bg_itemlist[ps.stats[C.STAT_HOLDABLE_ITEM]]
			if it.giTag == C.HI_MEDKIT and ps.stats[C.STAT_HEALTH] >= (ps.stats[C.STAT_MAX_HEALTH] + 25) then
				-- don't use medkit if at max health
			else
				ps.pm_flags = bor(ps.pm_flags, PMF_USE_ITEM_HELD)
				PM_AddEvent(C.EV_USE_ITEM0 + it.giTag)
				ps.stats[C.STAT_HOLDABLE_ITEM] = 0
			end
			return
		end
	else
		ps.pm_flags = band(ps.pm_flags, bnot(PMF_USE_ITEM_HELD))
	end

	-- make weapon function
	if ps.weaponTime > 0 then
		ps.weaponTime -= pml.msec
	end

	-- check for weapon change
	-- can't change if weapon is firing, but can change
	-- again if lowering or raising
	if ps.weaponTime <= 0 or ps.weaponstate ~= C.WEAPON_FIRING then
		if ps.weapon ~= pm.cmd.weapon then
			PM_BeginWeaponChange(pm.cmd.weapon)
		end
	end

	if ps.weaponTime > 0 then
		return
	end

	-- change weapon if time
	if ps.weaponstate == C.WEAPON_DROPPING then
		PM_FinishWeaponChange()
		return
	end

	if ps.weaponstate == C.WEAPON_RAISING then
		ps.weaponstate = C.WEAPON_READY
		if ps.weapon == C.WP_GAUNTLET then
			PM_StartTorsoAnim(C.TORSO_STAND2)
		else
			PM_StartTorsoAnim(C.TORSO_STAND)
		end
		return
	end

	-- check for fire
	if band(pm.cmd.buttons, C.BUTTON_ATTACK) == 0 then
		ps.weaponTime = 0
		ps.weaponstate = C.WEAPON_READY
		return
	end

	-- start the animation even if out of ammo
	if ps.weapon == C.WP_GAUNTLET then
		-- the guantlet only "fires" when it actually hits something
		if not pm.gauntletHit then
			ps.weaponTime = 0
			ps.weaponstate = C.WEAPON_READY
			return
		end
		PM_StartTorsoAnim(C.TORSO_ATTACK2)
	else
		PM_StartTorsoAnim(C.TORSO_ATTACK)
	end

	ps.weaponstate = C.WEAPON_FIRING

	-- check for out of ammo
	if ps.ammo[ps.weapon] == 0 then
		PM_AddEvent(C.EV_NOAMMO)
		ps.weaponTime += 500
		return
	end

	-- take an ammo away if not infinite, 999 or up
	if not (ps.ammo[ps.weapon] == -1 or ps.ammo[ps.weapon] >= 999) then
		ps.ammo[ps.weapon] -= 1
	end

	-- fire weapon
	PM_AddEvent(C.EV_FIRE_WEAPON)

	local addTime = ADDTIME[ps.weapon] or 400 -- default: same as the gauntlet

	if bg_itemlist[ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_SCOUT then
		addTime = trunc(addTime / 1.5)
	elseif bg_itemlist[ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_AMMOREGEN then
		addTime = trunc(addTime / 1.3)
	elseif ps.powerups[C.PW_HASTE] ~= 0 then
		addTime = trunc(addTime / 1.3)
	end

	ps.weaponTime += addTime
end

local function PM_Animate()
	local pm = B.pm
	local ps = pm.ps
	local buttons = pm.cmd.buttons
	if band(buttons, C.BUTTON_GESTURE) ~= 0 then
		if ps.torsoTimer == 0 then
			PM_StartTorsoAnim(C.TORSO_GESTURE)
			ps.torsoTimer = C.TIMER_GESTURE
			PM_AddEvent(C.EV_TAUNT)
		end
	elseif band(buttons, C.BUTTON_GETFLAG) ~= 0 then
		if ps.torsoTimer == 0 then
			PM_StartTorsoAnim(C.TORSO_GETFLAG)
			ps.torsoTimer = 600 --TIMER_GESTURE;
		end
	elseif band(buttons, C.BUTTON_GUARDBASE) ~= 0 then
		if ps.torsoTimer == 0 then
			PM_StartTorsoAnim(C.TORSO_GUARDBASE)
			ps.torsoTimer = 600
		end
	elseif band(buttons, C.BUTTON_PATROL) ~= 0 then
		if ps.torsoTimer == 0 then
			PM_StartTorsoAnim(C.TORSO_PATROL)
			ps.torsoTimer = 600
		end
	elseif band(buttons, C.BUTTON_FOLLOWME) ~= 0 then
		if ps.torsoTimer == 0 then
			PM_StartTorsoAnim(C.TORSO_FOLLOWME)
			ps.torsoTimer = 600
		end
	elseif band(buttons, C.BUTTON_AFFIRMATIVE) ~= 0 then
		if ps.torsoTimer == 0 then
			PM_StartTorsoAnim(C.TORSO_AFFIRMATIVE)
			ps.torsoTimer = 600
		end
	elseif band(buttons, C.BUTTON_NEGATIVE) ~= 0 then
		if ps.torsoTimer == 0 then
			PM_StartTorsoAnim(C.TORSO_NEGATIVE)
			ps.torsoTimer = 600
		end
	end
end

local function PM_DropTimers()
	local pm, pml = B.pm, B.pml
	local ps = pm.ps
	-- drop misc timing counter
	if ps.pm_time ~= 0 then
		if pml.msec >= ps.pm_time then
			ps.pm_flags = band(ps.pm_flags, bnot(PMF_ALL_TIMES))
			ps.pm_time = 0
		else
			ps.pm_time -= pml.msec
		end
	end

	-- drop animation counter
	if ps.legsTimer > 0 then
		ps.legsTimer -= pml.msec
		if ps.legsTimer < 0 then
			ps.legsTimer = 0
		end
	end

	if ps.torsoTimer > 0 then
		ps.torsoTimer -= pml.msec
		if ps.torsoTimer < 0 then
			ps.torsoTimer = 0
		end
	end
end

-- This can be used as another entry point when only the viewangles
-- are being updated instead of a full move
local function PM_UpdateViewAngles(ps, cmd)
	if ps.pm_type == C.PM_INTERMISSION or ps.pm_type == C.PM_SPINTERMISSION then
		return -- no view changes at all
	end

	if ps.pm_type ~= C.PM_SPECTATOR and ps.stats[C.STAT_HEALTH] <= 0 then
		return -- no view changes at all
	end

	-- circularly clamp the angles with deltas
	for i = 0, 2 do
		local temp = Q.short(cmd.angles[i] + ps.delta_angles[i])
		if i == C.PITCH then
			-- don't let the player look up or down more than 90 degrees
			if temp > 16000 then
				ps.delta_angles[i] = 16000 - cmd.angles[i]
				temp = 16000
			elseif temp < -16000 then
				ps.delta_angles[i] = -16000 - cmd.angles[i]
				temp = -16000
			end
		end
		ps.viewangles[i] = Q.SHORT2ANGLE(temp)
	end
end
B.PM_UpdateViewAngles = PM_UpdateViewAngles

local function PmoveSingle(pmove)
	B.pm = pmove
	local pm, pml = pmove, B.pml
	local ps, cmd = pm.ps, pm.cmd

	-- this counter lets us debug movement problems with a journal
	-- by setting a conditional breakpoint fot the previous frame
	B.c_pmove += 1

	-- clear results
	pm.numtouch = 0
	pm.watertype = 0
	pm.waterlevel = 0

	if ps.stats[C.STAT_HEALTH] <= 0 then
		pm.tracemask = band(pm.tracemask, bnot(C.CONTENTS_BODY)) -- corpses can fly through bodies
	end

	-- make sure walking button is clear if they are running, to avoid
	-- proxy no-footsteps cheats
	if abs(cmd.forwardmove) > 64 or abs(cmd.rightmove) > 64 then
		cmd.buttons = band(cmd.buttons, bnot(C.BUTTON_WALKING))
	end

	-- set the talk balloon flag
	if band(cmd.buttons, C.BUTTON_TALK) ~= 0 then
		ps.eFlags = bor(ps.eFlags, C.EF_TALK)
	else
		ps.eFlags = band(ps.eFlags, bnot(C.EF_TALK))
	end

	-- set the firing flag for continuous beam weapons
	if band(ps.pm_flags, PMF_RESPAWNED) == 0 and ps.pm_type ~= C.PM_INTERMISSION and ps.pm_type ~= C.PM_NOCLIP
		and band(cmd.buttons, C.BUTTON_ATTACK) ~= 0 and ps.ammo[ps.weapon] ~= 0 then
		ps.eFlags = bor(ps.eFlags, C.EF_FIRING)
	else
		ps.eFlags = band(ps.eFlags, bnot(C.EF_FIRING))
	end

	-- clear the respawned flag if attack and use are cleared
	if ps.stats[C.STAT_HEALTH] > 0 and band(cmd.buttons, bor(C.BUTTON_ATTACK, C.BUTTON_USE_HOLDABLE)) == 0 then
		ps.pm_flags = band(ps.pm_flags, bnot(PMF_RESPAWNED))
	end

	-- if talk button is down, dissallow all other input
	-- this is to prevent any possible intercept proxy from
	-- adding fake talk balloons
	if band(cmd.buttons, C.BUTTON_TALK) ~= 0 then
		-- keep the talk button set tho for when the cmd.serverTime > 66 msec
		-- and the same cmd is used multiple times in Pmove
		cmd.buttons = C.BUTTON_TALK
		cmd.forwardmove = 0
		cmd.rightmove = 0
		cmd.upmove = 0
	end

	-- clear all pmove local vars
	B.clearPml()

	-- determine the time
	pml.msec = cmd.serverTime - ps.commandTime
	if pml.msec < 1 then
		pml.msec = 1
	elseif pml.msec > 200 then
		pml.msec = 200
	end
	ps.commandTime = cmd.serverTime

	-- save old org in case we get stuck
	VectorCopy(ps.origin, pml.previous_origin)

	-- save old velocity for crashlanding
	VectorCopy(ps.velocity, pml.previous_velocity)

	pml.frametime = f(pml.msec * 0.001)

	-- update the viewangles
	PM_UpdateViewAngles(ps, cmd)

	Q.AngleVectors(ps.viewangles, pml.forward, pml.right, pml.up)

	if cmd.upmove < 10 then
		-- not holding jump
		ps.pm_flags = band(ps.pm_flags, bnot(PMF_JUMP_HELD))
	end

	-- decide if backpedaling animations should be used
	if cmd.forwardmove < 0 then
		ps.pm_flags = bor(ps.pm_flags, PMF_BACKWARDS_RUN)
	elseif cmd.forwardmove > 0 or (cmd.forwardmove == 0 and cmd.rightmove ~= 0) then
		ps.pm_flags = band(ps.pm_flags, bnot(PMF_BACKWARDS_RUN))
	end

	if ps.pm_type >= C.PM_DEAD then
		cmd.forwardmove = 0
		cmd.rightmove = 0
		cmd.upmove = 0
	end

	if ps.pm_type == C.PM_SPECTATOR then
		PM_CheckDuck()
		PM_FlyMove()
		PM_DropTimers()
		return
	end

	if ps.pm_type == C.PM_NOCLIP then
		PM_NoclipMove()
		PM_DropTimers()
		return
	end

	if ps.pm_type == C.PM_FREEZE then
		return -- no movement at all
	end

	if ps.pm_type == C.PM_INTERMISSION or ps.pm_type == C.PM_SPINTERMISSION then
		return -- no movement at all
	end

	-- set watertype, and waterlevel
	PM_SetWaterLevel()
	pml.previous_waterlevel = pmove.waterlevel

	-- set mins, maxs, and viewheight
	PM_CheckDuck()

	-- set groundentity
	PM_GroundTrace()

	if ps.pm_type == C.PM_DEAD then
		PM_DeadMove()
	end

	PM_DropTimers()

	if ps.powerups[C.PW_INVULNERABILITY] ~= 0 then
		PM_InvulnerabilityMove()
	elseif ps.powerups[C.PW_FLIGHT] ~= 0 then
		-- flight powerup doesn't allow jump and has different friction
		PM_FlyMove()
	elseif band(ps.pm_flags, PMF_GRAPPLE_PULL) ~= 0 then
		PM_GrappleMove()
		-- We can wiggle a bit
		PM_AirMove()
	elseif band(ps.pm_flags, PMF_TIME_WATERJUMP) ~= 0 then
		PM_WaterJumpMove()
	elseif pm.waterlevel > 1 then
		-- swimming
		PM_WaterMove()
	elseif pml.walking then
		-- walking on ground
		PM_WalkMove()
	else
		-- airborne
		PM_AirMove()
	end

	PM_Animate()

	-- set groundentity, watertype, and waterlevel
	PM_GroundTrace()
	PM_SetWaterLevel()

	-- weapons
	if band(ps.pm_flags, PMF_ELIMWARMUP) == 0 then
		PM_Weapon()
	end

	-- torso animation
	PM_TorsoAnimation()

	-- footstep events / legs animations
	PM_Footsteps()

	-- entering / leaving water splashes
	PM_WaterEvents()

	-- snap some parts of playerstate to save network bandwidth
	--But only if pmove_float is not enabled
	if pm.pmove_float == 0 then
		Q.SnapVectorRint(ps.velocity) -- trap_SnapVector
	end
end
B.PmoveSingle = PmoveSingle

-- Can be called by either the server or the client
local function Pmove(pmove)
	local ps = pmove.ps
	local finalTime = pmove.cmd.serverTime

	if finalTime < ps.commandTime then
		return -- should not happen
	end

	if finalTime > ps.commandTime + 1000 then
		ps.commandTime = finalTime - 1000
	end

	ps.pmove_framecount = band(ps.pmove_framecount + 1, lshift(1, C.PS_PMOVEFRAMECOUNTBITS) - 1)

	-- chop the move up if it is too long, to prevent framerate
	-- dependent behavior
	while ps.commandTime ~= finalTime do
		local msec = finalTime - ps.commandTime

		if pmove.pmove_fixed ~= 0 then
			if msec > pmove.pmove_msec then
				msec = pmove.pmove_msec
			end
		else
			if msec > 66 then
				msec = 66
			end
		end
		pmove.cmd.serverTime = ps.commandTime + msec
		PmoveSingle(pmove)

		if band(ps.pm_flags, PMF_JUMP_HELD) ~= 0 then
			pmove.cmd.upmove = 20
		end
	end
end
B.Pmove = Pmove

return B
