--[[
===========================================================================
Copyright (C) 2006 Neil Toronto.

This file is part of the Unlagged source code.

Unlagged source code is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at your
option) any later version.

Unlagged source code is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License
along with Unlagged source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/cgame/cg_unlagged.c (OpenArena gamecode).

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)

-- Must be in sync with g_weapon.c
local MACHINEGUN_SPREAD = 200
local CHAINGUN_SPREAD = 600

-- seeded generators of q_shared.c; seed is a one-field table {v = int}
local function Q_rand(seed)
	seed.v = (69069 * seed.v + 1) % 4294967296
	return seed.v
end

local function Q_random(seed)
	return bit32.band(Q_rand(seed), 0xffff) / 0x10000
end

local function Q_crandom(seed)
	return 2.0 * (Q_random(seed) - 0.5)
end

local function hitscanBullet(cent, muzzlePoint, forward, right, up, spread)
	local seed = { v = G.cg.oldTime % 256 }
	local ps = G.cg.predictedPlayerState
	local endPoint = Q.vec3(0, 0, 0)
	local tr = T.trace_t()

	-- do everything exactly like the server does
	local r = Q_random(seed) * math.pi * 2.0
	local u = math.sin(r) * Q_crandom(seed) * spread * 16
	r = math.cos(r) * Q_crandom(seed) * spread * 16

	Q.VectorMA(muzzlePoint, 8192 * 16, forward, endPoint)
	Q.VectorMA(endPoint, r, right, endPoint)
	Q.VectorMA(endPoint, u, up, endPoint)

	G.CG_Trace(tr, muzzlePoint, nil, nil, endPoint, ps.clientNum, C.MASK_SHOT)

	if bit32.band(tr.surfaceFlags, C.SURF_NOIMPACT) ~= 0 then
		return
	end

	-- snap the endpos to integers, but nudged towards the line
	Q.SnapVectorTowards(tr.endpos, muzzlePoint)

	local flesh = false
	local fleshEntityNum = 0
	if tr.entityNum < C.MAX_CLIENTS then
		flesh = true
		fleshEntityNum = tr.entityNum
	end

	G.CG_Bullet(tr.endpos, ps.clientNum, tr.plane.normal, flesh, fleshEntityNum)
end

--[[
=======================
CG_PredictWeaponEffects

Draws predicted effects for the railgun, shotgun, and machinegun.  The
lightning gun is done in CG_LightningBolt, since it was just a matter
of setting the right origin and angles.
=======================
]]
function G.CG_PredictWeaponEffects(cent)
	local cg = G.cg
	local cgs = G.cgs
	local muzzlePoint = Q.vec3(0, 0, 0)
	local forward = Q.vec3(0, 0, 0)
	local right = Q.vec3(0, 0, 0)
	local up = Q.vec3(0, 0, 0)
	local ent = cent.currentState
	local delag = G.cg_delag.integer

	-- if the client isn't us, forget it
	if cent.currentState.number ~= cg.predictedPlayerState.clientNum then
		return
	end

	-- if it's not switched on server-side, forget it
	if cgs.delagHitscan == 0 then
		return
	end

	-- get the muzzle point
	Q.VectorCopy(cg.predictedPlayerState.origin, muzzlePoint)
	muzzlePoint[2] += cg.predictedPlayerState.viewheight

	-- get forward, right, and up
	Q.AngleVectors(cg.predictedPlayerState.viewangles, forward, right, up)
	Q.VectorMA(muzzlePoint, 14, forward, muzzlePoint)

	if ent.weapon == C.WP_RAILGUN then
		if bit32.band(delag, 1) ~= 0 or bit32.band(delag, 16) ~= 0 then
			local trace = T.trace_t()
			local endPoint = Q.vec3(0, 0, 0)

			-- trace forward
			Q.VectorMA(muzzlePoint, 8192, forward, endPoint)

			-- find the rail's end point
			G.CG_Trace(trace, muzzlePoint, Q.vec3_origin, Q.vec3_origin, endPoint, cg.predictedPlayerState.clientNum, C.CONTENTS_SOLID)

			-- do the magic-number adjustment
			Q.VectorMA(muzzlePoint, 4, right, muzzlePoint)
			Q.VectorMA(muzzlePoint, -1, up, muzzlePoint)

			if not cg.renderingThirdPerson then
				if G.cg_drawGun.integer == 2 then
					Q.VectorMA(muzzlePoint, 8, cg.refdef.viewaxis[1], muzzlePoint)
				elseif G.cg_drawGun.integer == 3 then
					Q.VectorMA(muzzlePoint, 4, cg.refdef.viewaxis[1], muzzlePoint)
				end
			end

			-- draw a rail trail
			G.CG_RailTrail(cgs.clientinfo[cent.currentState.number], muzzlePoint, trace.endpos)

			-- explosion at end if not SURF_NOIMPACT
			if bit32.band(trace.surfaceFlags, C.SURF_NOIMPACT) == 0 then
				-- predict an explosion
				G.CG_MissileHitWall(ent.weapon, cg.predictedPlayerState.clientNum, trace.endpos, trace.plane.normal, C.IMPACTSOUND_DEFAULT)
			end
		end
	elseif ent.weapon == C.WP_SHOTGUN then
		if bit32.band(delag, 1) ~= 0 or bit32.band(delag, 4) ~= 0 then
			local endPoint = Q.vec3(0, 0, 0)
			local v = Q.vec3(0, 0, 0)

			-- do everything like the server does
			trap.SnapVector(muzzlePoint)

			Q.VectorScale(forward, 4096, endPoint)
			trap.SnapVector(endPoint)

			Q.VectorSubtract(endPoint, muzzlePoint, v)
			Q.VectorNormalize(v)
			Q.VectorScale(v, 32, v)
			Q.VectorAdd(muzzlePoint, v, v)

			if cgs.glconfig.hardwareType ~= C.GLHW_RAGEPRO then
				-- ragepro can't alpha fade, so don't even bother with smoke
				local smokeUp = Q.vec3(0, 0, 0)

				local contents = trap.CM_PointContents(muzzlePoint, 0)
				if bit32.band(contents, C.CONTENTS_WATER) == 0 then
					Q.VectorSet(smokeUp, 0, 0, 8)
					G.CG_SmokePuff(v, smokeUp, 32, 1, 1, 1, 0.33, 900, cg.time, 0, C.LEF_PUFF_DONT_SCALE, cgs.media.shotgunSmokePuffShader)
				end
			end

			-- do the shotgun pellets
			G.CG_ShotgunPattern(muzzlePoint, endPoint, cg.oldTime % 256, cg.predictedPlayerState.clientNum)
		end
	elseif ent.weapon == C.WP_MACHINEGUN then
		if bit32.band(delag, 1) ~= 0 or bit32.band(delag, 2) ~= 0 then
			hitscanBullet(cent, muzzlePoint, forward, right, up, MACHINEGUN_SPREAD)
		end
	elseif ent.weapon == C.WP_CHAINGUN then
		if bit32.band(delag, 1) ~= 0 or bit32.band(delag, 2) ~= 0 then
			hitscanBullet(cent, muzzlePoint, forward, right, up, CHAINGUN_SPREAD)
		end
	end
end

--[[
================
CG_Cvar_ClampInt

Clamps a cvar between two integer values, returns qtrue if it had to.
================
]]
function G.CG_Cvar_ClampInt(name, vmCvar, min, max)
	if vmCvar.integer > max then
		G.CG_Printf(Q.va("Allowed values are %d to %d.\n", min, max))

		vmCvar.string = Q.va("%d", max)
		vmCvar.value = max
		vmCvar.integer = max

		trap.Cvar_Set(name, vmCvar.string)
		return true
	end

	if vmCvar.integer < min then
		G.CG_Printf(Q.va("Allowed values are %d to %d.\n", min, max))

		vmCvar.string = Q.va("%d", min)
		vmCvar.value = min
		vmCvar.integer = min

		trap.Cvar_Set(name, vmCvar.string)
		return true
	end

	return false
end

return G
