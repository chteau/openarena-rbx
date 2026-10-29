--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/cgame/cg_weapons.c (OpenArena gamecode).
-- This part covers C lines 1-1148 (through CG_RegisterItemVisuals).

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

local function vec3x3()
	return { [0] = Q.vec3(0, 0, 0), [1] = Q.vec3(0, 0, 0), [2] = Q.vec3(0, 0, 0) }
end

local function MAKERGB(v, r, g, b)
	v[0] = r
	v[1] = g
	v[2] = b
end

local function xform(o, v, out)
	out[0] = o[0] * v[0][0] + o[1] * v[1][0] + o[2] * v[2][0]
	out[1] = o[0] * v[0][1] + o[1] * v[1][1] + o[2] * v[2][1]
	out[2] = o[0] * v[0][2] + o[1] * v[1][2] + o[2] * v[2][2]
end

function G.CG_MachineGunEjectBrass(cent)
	local velocity = Q.vec3(0, 0, 0)
	local xvelocity = Q.vec3(0, 0, 0)
	local offset = Q.vec3(0, 0, 0)
	local xoffset = Q.vec3(0, 0, 0)
	local waterScale = 1.0
	local v = vec3x3()

	if G.cg_brassTime.integer <= 0 then
		return
	end

	local le = G.CG_AllocLocalEntity()
	local re = le.refEntity

	velocity[0] = 0
	velocity[1] = -50 + 40 * Q.crandom()
	velocity[2] = 100 + 50 * Q.crandom()

	le.leType = C.LE_FRAGMENT
	le.startTime = G.cg.time
	le.endTime = Q.int(le.startTime + G.cg_brassTime.integer + Q.idiv(G.cg_brassTime.integer, 4) * Q.random())

	le.pos.trType = C.TR_GRAVITY
	le.pos.trTime = G.cg.time - bit32.band(Q.rand(), 15)

	Q.AnglesToAxis(cent.lerpAngles, v)

	offset[0] = 8
	offset[1] = -4
	offset[2] = 24

	xform(offset, v, xoffset)
	Q.VectorAdd(cent.lerpOrigin, xoffset, re.origin)

	Q.VectorCopy(re.origin, le.pos.trBase)

	if bit32.band(G.CG_PointContents(re.origin, -1), C.CONTENTS_WATER) ~= 0 then
		waterScale = 0.10
	end

	xform(velocity, v, xvelocity)
	Q.VectorScale(xvelocity, waterScale, le.pos.trDelta)

	Q.AxisCopy(Q.axisDefault, re.axis)
	re.hModel = G.cgs.media.machinegunBrassModel

	if G.cg_leiBrassNoise.integer ~= 0 then
		le.bounceFactor = 0.6 * waterScale
	else
		le.bounceFactor = 0.4 * waterScale
	end

	le.angles.trType = C.TR_LINEAR
	le.angles.trTime = G.cg.time
	le.angles.trBase[0] = bit32.band(Q.rand(), 31)
	le.angles.trBase[1] = bit32.band(Q.rand(), 31)
	le.angles.trBase[2] = bit32.band(Q.rand(), 31)
	le.angles.trDelta[0] = 2
	le.angles.trDelta[1] = 1
	le.angles.trDelta[2] = 0

	le.leFlags = C.LEF_TUMBLE
	le.leBounceSoundType = C.LEBS_BRASS
	le.leMarkType = C.LEMT_NONE
end

function G.CG_ShotgunEjectBrass(cent)
	local velocity = Q.vec3(0, 0, 0)
	local xvelocity = Q.vec3(0, 0, 0)
	local offset = Q.vec3(0, 0, 0)
	local xoffset = Q.vec3(0, 0, 0)
	local v = vec3x3()

	if G.cg_brassTime.integer <= 0 then
		return
	end

	for i = 0, 1 do
		local waterScale = 1.0

		local le = G.CG_AllocLocalEntity()
		local re = le.refEntity

		velocity[0] = 60 + 60 * Q.crandom()
		if i == 0 then
			velocity[1] = 40 + 10 * Q.crandom()
		else
			velocity[1] = -40 + 10 * Q.crandom()
		end
		velocity[2] = 100 + 50 * Q.crandom()

		le.leType = C.LE_FRAGMENT
		le.startTime = G.cg.time
		le.endTime = Q.int(le.startTime + G.cg_brassTime.integer * 3 + G.cg_brassTime.integer * Q.random())

		le.pos.trType = C.TR_GRAVITY
		le.pos.trTime = G.cg.time

		Q.AnglesToAxis(cent.lerpAngles, v)

		offset[0] = 8
		offset[1] = 0
		offset[2] = 24

		xform(offset, v, xoffset)
		Q.VectorAdd(cent.lerpOrigin, xoffset, re.origin)
		Q.VectorCopy(re.origin, le.pos.trBase)
		if bit32.band(G.CG_PointContents(re.origin, -1), C.CONTENTS_WATER) ~= 0 then
			waterScale = 0.10
		end

		xform(velocity, v, xvelocity)
		Q.VectorScale(xvelocity, waterScale, le.pos.trDelta)

		Q.AxisCopy(Q.axisDefault, re.axis)
		re.hModel = G.cgs.media.shotgunBrassModel
		if G.cg_leiBrassNoise.integer ~= 0 then
			le.bounceFactor = 0.5
		else
			le.bounceFactor = 0.3
		end

		le.angles.trType = C.TR_LINEAR
		le.angles.trTime = G.cg.time
		le.angles.trBase[0] = bit32.band(Q.rand(), 31)
		le.angles.trBase[1] = bit32.band(Q.rand(), 31)
		le.angles.trBase[2] = bit32.band(Q.rand(), 31)
		le.angles.trDelta[0] = 1
		le.angles.trDelta[1] = 0.5
		le.angles.trDelta[2] = 0

		le.leFlags = C.LEF_TUMBLE
		le.leBounceSoundType = C.LEBS_SHELL -- LEILEI shell noises
		le.leMarkType = C.LEMT_NONE
	end
end

function G.CG_NailgunEjectBrass(cent)
	local origin = Q.vec3(0, 0, 0)
	local v = vec3x3()
	local offset = Q.vec3(0, 0, 0)
	local xoffset = Q.vec3(0, 0, 0)
	local up = Q.vec3(0, 0, 0)

	Q.AnglesToAxis(cent.lerpAngles, v)

	offset[0] = 0
	offset[1] = -12
	offset[2] = 24

	xform(offset, v, xoffset)
	Q.VectorAdd(cent.lerpOrigin, xoffset, origin)

	Q.VectorSet(up, 0, 0, 64)

	local smoke = G.CG_SmokePuff(origin, up, 32, 1, 1, 1, 0.33, 700, G.cg.time, 0, 0, G.cgs.media.smokePuffShader)
	-- use the optimized local entity add
	smoke.leType = C.LE_SCALE_FADE
end

function G.CG_RailTrail(ci, start, finish)
	local RADIUS = 4
	local ROTATION = 1
	local SPACING = 5

	local axis = {}
	for i = 0, 35 do
		axis[i] = Q.vec3(0, 0, 0)
	end
	local move = Q.vec3(0, 0, 0)
	local move2 = Q.vec3(0, 0, 0)
	local vec = Q.vec3(0, 0, 0)
	local temp = Q.vec3(0, 0, 0)

	start[2] -= 4

	local le = G.CG_AllocLocalEntity()
	local re = le.refEntity

	le.leType = C.LE_FADE_RGB
	le.startTime = G.cg.time
	le.endTime = Q.int(G.cg.time + G.cg_railTrailTime.value)
	le.lifeRate = 1.0 / (le.endTime - le.startTime)

	re.shaderTime = G.cg.time / 1000.0
	re.reType = C.RT_RAIL_CORE
	re.customShader = G.cgs.media.railCoreShader

	Q.VectorCopy(start, re.origin)
	Q.VectorCopy(finish, re.oldorigin)

	re.shaderRGBA[0] = Q.int(ci.color1[0] * 255)
	re.shaderRGBA[1] = Q.int(ci.color1[1] * 255)
	re.shaderRGBA[2] = Q.int(ci.color1[2] * 255)
	re.shaderRGBA[3] = 255

	le.color[0] = ci.color1[0] * 0.75
	le.color[1] = ci.color1[1] * 0.75
	le.color[2] = ci.color1[2] * 0.75
	le.color[3] = 1.0

	Q.AxisClear(re.axis)

	if G.cg_oldRail.integer ~= 0 then
		-- nudge down a bit so it isn't exactly in center
		re.origin[2] -= 8
		re.oldorigin[2] -= 8

		-- leilei - reimplementing the rail discs that were removed in 1.30
		if G.cg_oldRail.integer > 1 then
			le = G.CG_AllocLocalEntity()
			re = le.refEntity

			Q.VectorCopy(start, re.origin)
			Q.VectorCopy(finish, re.oldorigin)
			le.leType = C.LE_FADE_RGB
			le.startTime = G.cg.time
			le.endTime = Q.int(G.cg.time + G.cg_railTrailTime.value)
			le.lifeRate = 1.0 / (le.endTime - le.startTime)

			re.shaderTime = G.cg.time / 1000.0
			re.reType = C.RT_RAIL_RINGS
			re.customShader = G.cgs.media.railRingsShader
			re.shaderRGBA[0] = Q.int(ci.color1[0] * 255)
			re.shaderRGBA[1] = Q.int(ci.color1[1] * 255)
			re.shaderRGBA[2] = Q.int(ci.color1[2] * 255)
			re.shaderRGBA[3] = 255

			le.color[0] = ci.color1[0] * 0.75
			le.color[1] = ci.color1[1] * 0.75
			le.color[2] = ci.color1[2] * 0.75
			le.color[3] = 1.0

			re.origin[2] -= 8
			re.oldorigin[2] -= 8

			if G.cg_oldRail.integer > 2 then -- use the secondary color instead
				re.shaderRGBA[0] = Q.int(ci.color2[0] * 255)
				re.shaderRGBA[1] = Q.int(ci.color2[1] * 255)
				re.shaderRGBA[2] = Q.int(ci.color2[2] * 255)
				re.shaderRGBA[3] = 255

				le.color[0] = ci.color2[0] * 0.75
				le.color[1] = ci.color2[1] * 0.75
				le.color[2] = ci.color2[2] * 0.75
				le.color[3] = 1.0
			end
		end
		return
	end

	Q.VectorCopy(start, move)
	Q.VectorSubtract(finish, start, vec)
	local len = Q.VectorNormalize(vec)
	Q.PerpendicularVector(temp, vec)
	for i = 0, 35 do
		Q.RotatePointAroundVector(axis[i], vec, temp, i * 10) --banshee 2.4 was 10
	end

	Q.VectorMA(move, 20, vec, move)
	Q.VectorScale(vec, SPACING, vec)

	local skip = -1

	local j = 18
	local i = 0
	while i < len do
		if i ~= skip then
			skip = i + SPACING
			le = G.CG_AllocLocalEntity()
			re = le.refEntity
			le.leFlags = C.LEF_PUFF_DONT_SCALE
			le.leType = C.LE_MOVE_SCALE_FADE
			le.startTime = G.cg.time
			le.endTime = G.cg.time + bit32.rshift(i, 1) + 600
			le.lifeRate = 1.0 / (le.endTime - le.startTime)

			re.shaderTime = G.cg.time / 1000.0
			re.reType = C.RT_SPRITE
			re.radius = 1.1
			re.customShader = G.cgs.media.railRingsShader

			re.shaderRGBA[0] = Q.int(ci.color2[0] * 255)
			re.shaderRGBA[1] = Q.int(ci.color2[1] * 255)
			re.shaderRGBA[2] = Q.int(ci.color2[2] * 255)
			re.shaderRGBA[3] = 255

			le.color[0] = ci.color2[0] * 0.75
			le.color[1] = ci.color2[1] * 0.75
			le.color[2] = ci.color2[2] * 0.75
			le.color[3] = 1.0

			le.pos.trType = C.TR_LINEAR
			le.pos.trTime = G.cg.time

			Q.VectorCopy(move, move2)
			Q.VectorMA(move2, RADIUS, axis[j], move2)
			Q.VectorCopy(move2, le.pos.trBase)

			le.pos.trDelta[0] = axis[j][0] * 6
			le.pos.trDelta[1] = axis[j][1] * 6
			le.pos.trDelta[2] = axis[j][2] * 6
		end

		Q.VectorAdd(move, vec, move)

		j = (j + ROTATION) % 36
		i += SPACING
	end
end

local WATERLAVASLIME = bit32.bor(C.CONTENTS_WATER, C.CONTENTS_SLIME, C.CONTENTS_LAVA)

-- CG_OldRocketTrail (for the crappy old rocket trail.)
function G.CG_OldRocketTrail(ent, wi)
	local origin = Q.vec3(0, 0, 0)
	local lastPos = Q.vec3(0, 0, 0)
	local up = Q.vec3(0, 0, 0)

	if G.cg_noProjectileTrail.integer ~= 0 then
		return
	end

	local step = 50

	local es = ent.currentState
	local startTime = ent.trailTime
	local t = step * Q.idiv(startTime + step, step)

	BG.BG_EvaluateTrajectory(es.pos, G.cg.time, origin)
	local contents = G.CG_PointContents(origin, -1)

	-- if object (e.g. grenade) is stationary, don't toss up smoke
	if es.pos.trType == C.TR_STATIONARY then
		ent.trailTime = G.cg.time
		return
	end

	BG.BG_EvaluateTrajectory(es.pos, ent.trailTime, lastPos)
	local lastContents = G.CG_PointContents(lastPos, -1)

	ent.trailTime = G.cg.time

	if bit32.band(contents, WATERLAVASLIME) ~= 0 then
		if bit32.band(contents, lastContents, C.CONTENTS_WATER) ~= 0 then
			G.CG_BubbleTrail(lastPos, origin, 8)
		end
		return
	end

	while t <= ent.trailTime do
		BG.BG_EvaluateTrajectory(es.pos, t, lastPos)

		local smoke = G.CG_SmokePuff(
			lastPos,
			up,
			wi.trailRadius,
			1,
			1,
			1,
			0.33,
			wi.wiTrailTime,
			t,
			0,
			0,
			G.cgs.media.smokePuffShader
		)
		-- use the optimized local entity add
		smoke.leType = C.LE_SCALE_FADE
		t += step
	end
end

function G.CG_LeiSmokeTrail(ent, wi)
	local origin = Q.vec3(0, 0, 0)
	local lastPos = Q.vec3(0, 0, 0)
	local up = Q.vec3(0, 0, 0)

	if G.cg_noProjectileTrail.integer ~= 0 then
		return
	end

	up[0] = 5 - 10 * Q.crandom()
	up[1] = 5 - 10 * Q.crandom()
	up[2] = 8 - 5 * Q.crandom()

	local step = 18

	local es = ent.currentState
	local startTime = ent.trailTime
	local t = step * Q.idiv(startTime + step, step)

	BG.BG_EvaluateTrajectory(es.pos, G.cg.time, origin)
	local contents = G.CG_PointContents(origin, -1)

	-- if object (e.g. grenade) is stationary, don't toss up smoke
	if es.pos.trType == C.TR_STATIONARY then
		ent.trailTime = G.cg.time
		return
	end

	BG.BG_EvaluateTrajectory(es.pos, ent.trailTime, lastPos)
	local lastContents = G.CG_PointContents(lastPos, -1)

	ent.trailTime = G.cg.time

	if bit32.band(contents, WATERLAVASLIME) ~= 0 then
		if bit32.band(contents, lastContents, C.CONTENTS_WATER) ~= 0 then
			G.CG_BubbleTrail(lastPos, origin, 8)
		end
		return
	end

	while t <= ent.trailTime do
		if G.cg_leiEnhancement.integer ~= 0 then
			trap.R_LFX_ParticleEffect(1, origin, up) -- that was easy.
		end
		t += step
	end
end

function G.CG_LeiPlasmaTrail(ent, wi)
	local origin = Q.vec3(0, 0, 0)
	local lastPos = Q.vec3(0, 0, 0)
	local up = Q.vec3(0, 0, 0)

	if G.cg_noProjectileTrail.integer ~= 0 then
		return
	end

	local step = 16

	local es = ent.currentState
	local startTime = ent.trailTime
	local t = step * Q.idiv(startTime + step, step)

	BG.BG_EvaluateTrajectory(es.pos, G.cg.time, origin)
	local contents = G.CG_PointContents(origin, -1)

	-- if object (e.g. grenade) is stationary, don't toss up smoke
	if es.pos.trType == C.TR_STATIONARY then
		ent.trailTime = G.cg.time
		return
	end

	BG.BG_EvaluateTrajectory(es.pos, ent.trailTime, lastPos)

	ent.trailTime = G.cg.time

	if bit32.band(contents, WATERLAVASLIME) ~= 0 then
		return
	end

	while t <= ent.trailTime do
		BG.BG_EvaluateTrajectory(es.pos, t, lastPos)

		local smoke = G.CG_SmokePuff(lastPos, up, 27, 1, 1, 1, 0.9, wi.wiTrailTime, t, 0, 0, G.cgs.media.lsmkShader1)
		-- use the optimized local entity add
		smoke.leType = C.LE_SCALE_FADE
		t += step
	end
end

function G.CG_NailTrail(ent, wi)
	local origin = Q.vec3(0, 0, 0)
	local lastPos = Q.vec3(0, 0, 0)
	local up = Q.vec3(0, 0, 0)

	if G.cg_noProjectileTrail.integer ~= 0 then
		return
	end

	local step = 50

	local es = ent.currentState
	local startTime = ent.trailTime
	local t = step * Q.idiv(startTime + step, step)

	BG.BG_EvaluateTrajectory(es.pos, G.cg.time, origin)
	local contents = G.CG_PointContents(origin, -1)

	-- if object (e.g. grenade) is stationary, don't toss up smoke
	if es.pos.trType == C.TR_STATIONARY then
		ent.trailTime = G.cg.time
		return
	end

	BG.BG_EvaluateTrajectory(es.pos, ent.trailTime, lastPos)
	local lastContents = G.CG_PointContents(lastPos, -1)

	ent.trailTime = G.cg.time

	if bit32.band(contents, WATERLAVASLIME) ~= 0 then
		if bit32.band(contents, lastContents, C.CONTENTS_WATER) ~= 0 then
			G.CG_BubbleTrail(lastPos, origin, 8)
		end
		return
	end

	while t <= ent.trailTime do
		BG.BG_EvaluateTrajectory(es.pos, t, lastPos)

		local smoke = G.CG_SmokePuff(
			lastPos,
			up,
			wi.trailRadius,
			1,
			1,
			1,
			0.33,
			wi.wiTrailTime,
			t,
			0,
			0,
			G.cgs.media.nailPuffShader
		)
		-- use the optimized local entity add
		smoke.leType = C.LE_SCALE_FADE
		t += step
	end
end

function G.CG_OldPlasmaTrail(cent, wi)
	local velocity = Q.vec3(0, 0, 0)
	local xvelocity = Q.vec3(0, 0, 0)
	local origin = Q.vec3(0, 0, 0)
	local offset = Q.vec3(0, 0, 0)
	local xoffset = Q.vec3(0, 0, 0)
	local v = vec3x3()
	local waterScale = 1.0

	if G.cg_noProjectileTrail.integer ~= 0 or G.cg_oldPlasma.integer ~= 0 then
		return
	end
	local es = cent.currentState

	BG.BG_EvaluateTrajectory(es.pos, G.cg.time, origin)

	local le = G.CG_AllocLocalEntity()
	local re = le.refEntity

	velocity[0] = 60 - 120 * Q.crandom()
	velocity[1] = 40 - 80 * Q.crandom()
	velocity[2] = 100 - 200 * Q.crandom()

	le.leType = C.LE_MOVE_SCALE_FADE
	le.leFlags = C.LEF_TUMBLE
	le.leBounceSoundType = C.LEBS_NONE
	le.leMarkType = C.LEMT_NONE

	le.startTime = G.cg.time
	le.endTime = le.startTime + 600

	le.pos.trType = C.TR_GRAVITY
	le.pos.trTime = G.cg.time

	Q.AnglesToAxis(cent.lerpAngles, v)

	offset[0] = 2
	offset[1] = 2
	offset[2] = 2

	xform(offset, v, xoffset)

	Q.VectorAdd(origin, xoffset, re.origin)
	Q.VectorCopy(re.origin, le.pos.trBase)

	if bit32.band(G.CG_PointContents(re.origin, -1), C.CONTENTS_WATER) ~= 0 then
		waterScale = 0.10
	end

	xform(velocity, v, xvelocity)
	Q.VectorScale(xvelocity, waterScale, le.pos.trDelta)

	Q.AxisCopy(Q.axisDefault, re.axis)
	re.shaderTime = G.cg.time / 1000.0
	re.reType = C.RT_SPRITE
	re.radius = 0.25
	re.customShader = G.cgs.media.railRingsShader
	le.bounceFactor = 0.3

	re.shaderRGBA[0] = Q.int(wi.flashDlightColor[0] * 63)
	re.shaderRGBA[1] = Q.int(wi.flashDlightColor[1] * 63)
	re.shaderRGBA[2] = Q.int(wi.flashDlightColor[2] * 63)
	re.shaderRGBA[3] = 63

	le.color[0] = wi.flashDlightColor[0] * 0.2
	le.color[1] = wi.flashDlightColor[1] * 0.2
	le.color[2] = wi.flashDlightColor[2] * 0.2
	le.color[3] = 0.25

	le.angles.trType = C.TR_LINEAR
	le.angles.trTime = G.cg.time
	le.angles.trBase[0] = bit32.band(Q.rand(), 31)
	le.angles.trBase[1] = bit32.band(Q.rand(), 31)
	le.angles.trBase[2] = bit32.band(Q.rand(), 31)
	le.angles.trDelta[0] = 1
	le.angles.trDelta[1] = 0.5
	le.angles.trDelta[2] = 0
end

function G.CG_GrappleTrail(ent, wi)
	local origin = Q.vec3(0, 0, 0)
	local forward = Q.vec3(0, 0, 0)
	local up = Q.vec3(0, 0, 0)

	local es = ent.currentState

	BG.BG_EvaluateTrajectory(es.pos, G.cg.time, origin)
	ent.trailTime = G.cg.time

	local beam = T.refEntity_t()
	--FIXME adjust for muzzle position
	Q.VectorCopy(G.cg_entities[ent.currentState.otherEntityNum].lerpOrigin, beam.origin)
	beam.origin[2] += 26
	Q.AngleVectors(G.cg_entities[ent.currentState.otherEntityNum].lerpAngles, forward, nil, up)
	Q.VectorMA(beam.origin, -6, up, beam.origin)
	Q.VectorCopy(origin, beam.oldorigin)

	if Q.Distance(beam.origin, beam.oldorigin) < 64 then
		return -- Don't draw if close
	end

	beam.reType = C.RT_RAIL_CORE
	beam.customShader = G.cgs.media.grappleShader

	Q.AxisClear(beam.axis)
	beam.shaderRGBA[0] = 0xff
	beam.shaderRGBA[1] = 0xff
	beam.shaderRGBA[2] = 0xff
	beam.shaderRGBA[3] = 0xff
	trap.R_AddRefEntityToScene(beam)
end

-- LEILEI enhancment
function G.CG_RocketTrail(ent, wi)
	if G.cg_leiEnhancement.integer ~= 0 then
		G.CG_LeiSmokeTrail(ent, wi)
	else
		G.CG_OldRocketTrail(ent, wi)
	end
end

function G.CG_PlasmaTrail(ent, wi)
	if G.cg_leiEnhancement.integer ~= 0 then
		G.CG_LeiPlasmaTrail(ent, wi)
	else
		G.CG_OldPlasmaTrail(ent, wi)
	end
end

function G.CG_GrenadeTrail(ent, wi)
	G.CG_RocketTrail(ent, wi)
end

--[[
=================
CG_RegisterWeapon

The server says this item is used on this level
=================
]]
function G.CG_RegisterWeapon(weaponNum)
	local weaponInfo = G.cg_weapons[weaponNum]
	local mins = Q.vec3(0, 0, 0)
	local maxs = Q.vec3(0, 0, 0)

	if weaponNum == 0 then
		return
	end

	if weaponInfo.registered then
		return
	end

	T.reset(weaponInfo, T.weaponInfo_t)
	weaponInfo.registered = true

	local itemIndex = 1
	local item = BG.bg_itemlist[itemIndex]
	while item ~= nil and item.classname ~= nil and item.classname ~= "" do
		if item.giType == C.IT_WEAPON and item.giTag == weaponNum then
			weaponInfo.item = item
			break
		end
		itemIndex += 1
		item = BG.bg_itemlist[itemIndex]
	end
	if item == nil or item.classname == nil or item.classname == "" then
		G.CG_Error(Q.va("Couldn't find weapon %i", weaponNum))
	end
	G.CG_RegisterItemVisuals(itemIndex)

	-- load cmodel before model so filecache works
	weaponInfo.weaponModel = trap.R_RegisterModel(item.world_model[0])

	-- calc midpoint for rotation
	trap.R_ModelBounds(weaponInfo.weaponModel, mins, maxs)
	for i = 0, 2 do
		weaponInfo.weaponMidpoint[i] = mins[i] + 0.5 * (maxs[i] - mins[i])
	end

	weaponInfo.weaponIcon = trap.R_RegisterShader(item.icon)
	weaponInfo.ammoIcon = trap.R_RegisterShader(item.icon)

	local ammo = BG.bg_itemlist[1]
	local ammoIndex = 1
	while ammo ~= nil and ammo.classname ~= nil and ammo.classname ~= "" do
		if ammo.giType == C.IT_AMMO and ammo.giTag == weaponNum then
			break
		end
		ammoIndex += 1
		ammo = BG.bg_itemlist[ammoIndex]
	end
	if ammo ~= nil and ammo.classname ~= nil and ammo.classname ~= "" and ammo.world_model[0] ~= nil and ammo.world_model[0] ~= "" then
		weaponInfo.ammoModel = trap.R_RegisterModel(ammo.world_model[0])
	end

	local base = Q.COM_StripExtension(item.world_model[0])
	weaponInfo.flashModel = trap.R_RegisterModel(base .. "_flash.md3")

	if weaponInfo.flashModel == 0 then
		weaponInfo.flashModel = trap.R_RegisterModel("models/weapons2/shotgun/shotgun_flash.md3") -- default flash
	end

	-- leilei - additional flash styles
	weaponInfo.flashModel_type1 = trap.R_RegisterModel(base .. "_flash1.md3")
	weaponInfo.flashModel_type2 = trap.R_RegisterModel(base .. "_flash2.md3")
	weaponInfo.flashModel_type2a = trap.R_RegisterModel(base .. "_flash2a.md3")
	weaponInfo.flashModel_type3 = trap.R_RegisterModel(base .. "_flash3.md3")
	weaponInfo.flashModel_type4 = trap.R_RegisterModel(base .. "_flash4.md3")
	weaponInfo.flashModel_type5 = trap.R_RegisterModel(base .. "_flash5.md3")
	weaponInfo.flashModel_type5a = trap.R_RegisterModel(base .. "_flash5a.md3")

	-- leilei - revert to default flash model if we really don't have a real one.
	if weaponInfo.flashModel_type1 == 0 then
		weaponInfo.flashModel_type1 = trap.R_RegisterModel("models/muzzle/flash1.md3")
	end
	if weaponInfo.flashModel_type2 == 0 then
		weaponInfo.flashModel_type2 = trap.R_RegisterModel("models/muzzle/flash2.md3")
	end
	if weaponInfo.flashModel_type2a == 0 then
		weaponInfo.flashModel_type2a = trap.R_RegisterModel("models/muzzle/flash2a.md3")
	end
	if weaponInfo.flashModel_type3 == 0 then
		weaponInfo.flashModel_type3 = trap.R_RegisterModel("models/muzzle/flash3.md3")
	end
	if weaponInfo.flashModel_type4 == 0 then
		weaponInfo.flashModel_type4 = trap.R_RegisterModel("models/muzzle/flash4.md3")
	end
	if weaponInfo.flashModel_type5 == 0 then
		weaponInfo.flashModel_type5 = trap.R_RegisterModel("models/muzzle/flash5.md3")
	end
	if weaponInfo.flashModel_type5a == 0 then
		weaponInfo.flashModel_type5a = trap.R_RegisterModel("models/muzzle/flash5a.md3")
	end

	weaponInfo.barrelModel = trap.R_RegisterModel(base .. "_barrel.md3")

	weaponInfo.handsModel = trap.R_RegisterModel(base .. "_hand.md3")

	if weaponInfo.handsModel == 0 then
		weaponInfo.handsModel = trap.R_RegisterModel("models/weapons2/shotgun/shotgun_hand.md3")
	end

	weaponInfo.loopFireSound = false

	local media = G.cgs.media

	if weaponNum == C.WP_GAUNTLET then
		MAKERGB(weaponInfo.flashDlightColor, 0.6, 0.6, 1.0)
		weaponInfo.firingSound = trap.S_RegisterSound("sound/weapons/melee/fstrun.wav", false)
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/melee/fstatck.wav", false)
		weaponInfo.lfx = 0 --  no effect
	elseif weaponNum == C.WP_LIGHTNING then
		MAKERGB(weaponInfo.flashDlightColor, 0.6, 0.6, 1.0)
		weaponInfo.readySound = trap.S_RegisterSound("sound/weapons/melee/fsthum.wav", false)
		weaponInfo.firingSound = trap.S_RegisterSound("sound/weapons/lightning/lg_hum.wav", false)

		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/lightning/lg_fire.wav", false)
		media.lightningShader = trap.R_RegisterShader("lightningBoltNew")
		media.lightningExplosionModel = trap.R_RegisterModel("models/weaphits/crackle.md3")
		media.sfx_lghit1 = trap.S_RegisterSound("sound/weapons/lightning/lg_hit.wav", false)
		media.sfx_lghit2 = trap.S_RegisterSound("sound/weapons/lightning/lg_hit2.wav", false)
		media.sfx_lghit3 = trap.S_RegisterSound("sound/weapons/lightning/lg_hit3.wav", false)
		weaponInfo.lfx = 0 --  no effect
	elseif weaponNum == C.WP_GRAPPLING_HOOK then
		MAKERGB(weaponInfo.flashDlightColor, 0.6, 0.6, 1.0)
		weaponInfo.missileModel = trap.R_RegisterModel("models/ammo/hook/hook.md3")
		weaponInfo.missileTrailFunc = G.CG_GrappleTrail
		weaponInfo.missileDlight = 0
		weaponInfo.wiTrailTime = 2000
		weaponInfo.trailRadius = 64
		MAKERGB(weaponInfo.missileDlightColor, 1, 0.75, 0)
		media.grappleShader = trap.R_RegisterShader("grappleRope")
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/grapple/grapfire.wav", false)
		weaponInfo.missileSound = trap.S_RegisterSound("sound/weapons/grapple/grappull.wav", false)
		weaponInfo.lfx = 0 --  no effect
	elseif weaponNum == C.WP_CHAINGUN then
		weaponInfo.firingSound = trap.S_RegisterSound("sound/weapons/vulcan/wvulfire.wav", false)
		weaponInfo.loopFireSound = true
		MAKERGB(weaponInfo.flashDlightColor, 1, 1, 0)
		-- leilei -testing a looping firing sound instead of lots of flash sounds for performance reasons
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/vulcan/vulcanf1b.wav", false)
		weaponInfo.flashSound[1] = trap.S_RegisterSound("sound/weapons/vulcan/vulcanf2b.wav", false)
		weaponInfo.flashSound[2] = trap.S_RegisterSound("sound/weapons/vulcan/vulcanf3b.wav", false)
		weaponInfo.flashSound[3] = trap.S_RegisterSound("sound/weapons/vulcan/vulcanf4b.wav", false)
		weaponInfo.ejectBrassFunc = G.CG_MachineGunEjectBrass
		media.bulletExplosionShader = trap.R_RegisterShader("bulletExplosion")
		weaponInfo.lfx = 71
	elseif weaponNum == C.WP_MACHINEGUN then
		MAKERGB(weaponInfo.flashDlightColor, 1, 1, 0)
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/machinegun/machgf1b.wav", false)
		weaponInfo.flashSound[1] = trap.S_RegisterSound("sound/weapons/machinegun/machgf2b.wav", false)
		weaponInfo.flashSound[2] = trap.S_RegisterSound("sound/weapons/machinegun/machgf3b.wav", false)
		weaponInfo.flashSound[3] = trap.S_RegisterSound("sound/weapons/machinegun/machgf4b.wav", false)
		weaponInfo.ejectBrassFunc = G.CG_MachineGunEjectBrass
		media.bulletExplosionShader = trap.R_RegisterShader("bulletExplosion")
		weaponInfo.lfx = 62
	elseif weaponNum == C.WP_SHOTGUN then
		MAKERGB(weaponInfo.flashDlightColor, 1, 1, 0)
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/shotgun/sshotf1b.wav", false)
		weaponInfo.ejectBrassFunc = G.CG_ShotgunEjectBrass
		weaponInfo.lfx = 63
	elseif weaponNum == C.WP_ROCKET_LAUNCHER then
		weaponInfo.missileModel = trap.R_RegisterModel("models/ammo/rocket/rocket.md3")
		weaponInfo.missileSound = trap.S_RegisterSound("sound/weapons/rocket/rockfly.wav", false)
		weaponInfo.missileTrailFunc = G.CG_RocketTrail
		weaponInfo.missileDlight = 200
		weaponInfo.wiTrailTime = 2000
		weaponInfo.trailRadius = 64

		MAKERGB(weaponInfo.missileDlightColor, 1, 0.75, 0)
		MAKERGB(weaponInfo.flashDlightColor, 1, 0.75, 0)

		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/rocket/rocklf1a.wav", false)
		media.rocketExplosionShader = trap.R_RegisterShader("rocketExplosion")
		weaponInfo.lfx = 65
	elseif weaponNum == C.WP_PROX_LAUNCHER then
		weaponInfo.missileModel = trap.R_RegisterModel("models/weaphits/proxmine.md3")
		weaponInfo.missileTrailFunc = G.CG_GrenadeTrail
		weaponInfo.wiTrailTime = 700
		weaponInfo.trailRadius = 32
		MAKERGB(weaponInfo.flashDlightColor, 1, 0.70, 0)
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/proxmine/wstbfire.wav", false)
		media.grenadeExplosionShader = trap.R_RegisterShader("grenadeExplosion")
		weaponInfo.lfx = 70
	elseif weaponNum == C.WP_GRENADE_LAUNCHER then
		weaponInfo.missileModel = trap.R_RegisterModel("models/ammo/grenade1.md3")
		weaponInfo.missileTrailFunc = G.CG_GrenadeTrail
		weaponInfo.wiTrailTime = 700
		weaponInfo.trailRadius = 32
		MAKERGB(weaponInfo.flashDlightColor, 1, 0.70, 0)
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/grenade/grenlf1a.wav", false)
		media.grenadeExplosionShader = trap.R_RegisterShader("grenadeExplosion")
		weaponInfo.lfx = 64
	elseif weaponNum == C.WP_NAILGUN then
		weaponInfo.ejectBrassFunc = G.CG_NailgunEjectBrass
		weaponInfo.missileTrailFunc = G.CG_NailTrail
		weaponInfo.trailRadius = 16
		weaponInfo.wiTrailTime = 250
		weaponInfo.missileModel = trap.R_RegisterModel("models/weaphits/nail.md3")
		MAKERGB(weaponInfo.flashDlightColor, 1, 0.75, 0)
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/nailgun/wnalfire.wav", false)
		weaponInfo.lfx = 69
	elseif weaponNum == C.WP_PLASMAGUN then
		weaponInfo.missileTrailFunc = G.CG_PlasmaTrail
		weaponInfo.missileSound = trap.S_RegisterSound("sound/weapons/plasma/lasfly.wav", false)
		MAKERGB(weaponInfo.flashDlightColor, 0.6, 0.6, 1.0)
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/plasma/hyprbf1a.wav", false)
		media.plasmaExplosionShader = trap.R_RegisterShader("plasmaExplosion")
		media.railRingsShader = trap.R_RegisterShader("railDisc")
		weaponInfo.lfx = 66
	elseif weaponNum == C.WP_RAILGUN then
		weaponInfo.readySound = trap.S_RegisterSound("sound/weapons/railgun/rg_hum.wav", false)
		MAKERGB(weaponInfo.flashDlightColor, 1, 0.5, 0)
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/railgun/railgf1a.wav", false)
		media.railExplosionShader = trap.R_RegisterShader("railExplosion")
		media.railRingsShader = trap.R_RegisterShader("railDisc")
		media.railCoreShader = trap.R_RegisterShader("railCore")
		weaponInfo.lfx = 67
	elseif weaponNum == C.WP_BFG then
		weaponInfo.readySound = trap.S_RegisterSound("sound/weapons/bfg/bfg_hum.wav", false)
		MAKERGB(weaponInfo.flashDlightColor, 1, 0.7, 1)
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/bfg/bfg_fire.wav", false)
		media.bfgExplosionShader = trap.R_RegisterShader("bfgExplosion")
		weaponInfo.missileModel = trap.R_RegisterModel("models/weaphits/bfg.md3")
		weaponInfo.missileSound = trap.S_RegisterSound("sound/weapons/rocket/rockfly.wav", false)
		weaponInfo.lfx = 68
	else
		MAKERGB(weaponInfo.flashDlightColor, 1, 1, 1)
		weaponInfo.flashSound[0] = trap.S_RegisterSound("sound/weapons/rocket/rocklf1a.wav", false)
	end
end

--[[
=================
CG_RegisterItemVisuals

The server says this item is used on this level
=================
]]
function G.CG_RegisterItemVisuals(itemNum)
	if itemNum < 0 or itemNum >= BG.bg_numItems then
		G.CG_Error(Q.va("CG_RegisterItemVisuals: itemNum %d out of range [0-%d]", itemNum, BG.bg_numItems - 1))
	end

	local itemInfo = G.cg_items[itemNum]
	if itemInfo.registered then
		return
	end

	local item = BG.bg_itemlist[itemNum]

	T.reset(itemInfo, T.itemInfo_t)
	itemInfo.registered = true

	itemInfo.models[0] = trap.R_RegisterModel(item.world_model[0])

	itemInfo.icon = trap.R_RegisterShader(item.icon)

	if item.giType == C.IT_WEAPON then
		G.CG_RegisterWeapon(item.giTag)
	end

	-- powerups have an accompanying ring or sphere
	if
		item.giType == C.IT_POWERUP
		or item.giType == C.IT_HEALTH
		or item.giType == C.IT_ARMOR
		or item.giType == C.IT_HOLDABLE
	then
		local m = item.world_model[1]
		if m ~= nil and m ~= "" then
			itemInfo.models[1] = trap.R_RegisterModel(m)
		end
	end
end

return G
