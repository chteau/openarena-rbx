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
-- Luau port of code/cgame/cg_effects.c (OpenArena gamecode).
-- cg_effects.c -- these functions generate localentities, usually as a result
-- of event processing

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local trap = require(script.Parent.Parent.sys.Trap)

local GIB_VELOCITY = 250
local GIB_JUMP = 250
local EXP_VELOCITY = 100
local EXP_JUMP = 150

local smokeSeed = 0x92
local slowSeed = 0x92
local lastPos = Q.vec3(0, 0, 0)

local function nextRandom(seed)
	seed = (69069 * seed + 1) % 4294967296
	return seed, (bit32.band(seed, 0xffff)) / 65536
end

function G.CG_BubbleTrail(start, finish, spacing)
	local move = Q.vec3(0, 0, 0)
	local vec = Q.vec3(0, 0, 0)

	if G.cg_noProjectileTrail.integer ~= 0 then
		return
	end

	Q.VectorCopy(start, move)
	Q.VectorSubtract(finish, start, vec)
	local len = Q.VectorNormalize(vec)

	-- advance a random amount first
	local i = Q.rand() % Q.int(spacing)
	Q.VectorMA(move, i, vec, move)

	Q.VectorScale(vec, spacing, vec)

	while i < len do
		local le = G.CG_AllocLocalEntity()
		le.leFlags = C.LEF_PUFF_DONT_SCALE
		le.leType = C.LE_MOVE_SCALE_FADE
		le.startTime = G.cg.time
		le.endTime = G.cg.time + 1000 + Q.random() * 250
		le.lifeRate = 1.0 / (le.endTime - le.startTime)

		local re = le.refEntity
		re.shaderTime = G.cg.time / 1000.0

		re.reType = C.RT_SPRITE
		re.rotation = 0
		re.radius = 3
		re.customShader = G.cgs.media.waterBubbleShader
		re.shaderRGBA[0] = 0xff
		re.shaderRGBA[1] = 0xff
		re.shaderRGBA[2] = 0xff
		re.shaderRGBA[3] = 0xff

		le.color[3] = 1.0

		le.pos.trType = C.TR_LINEAR
		le.pos.trTime = G.cg.time
		Q.VectorCopy(move, le.pos.trBase)
		le.pos.trDelta[0] = Q.crandom() * 5
		le.pos.trDelta[1] = Q.crandom() * 5
		le.pos.trDelta[2] = Q.crandom() * 5 + 6

		Q.VectorAdd(move, vec, move)
		i += spacing
	end
end

function G.CG_SmokePuff(p, vel, radius, r, g, b, a, duration, startTime, fadeInTime, leFlags, hShader)
	local le = G.CG_AllocLocalEntity()
	le.leFlags = leFlags
	le.radius = radius

	local re = le.refEntity
	local rnd
	smokeSeed, rnd = nextRandom(smokeSeed)
	re.rotation = rnd * 360
	re.radius = radius
	re.shaderTime = startTime / 1000.0

	le.leType = C.LE_MOVE_SCALE_FADE
	le.startTime = startTime
	le.fadeInTime = fadeInTime
	le.endTime = startTime + duration
	if fadeInTime > startTime then
		le.lifeRate = 1.0 / (le.endTime - le.fadeInTime)
	else
		le.lifeRate = 1.0 / (le.endTime - le.startTime)
	end
	le.color[0] = r
	le.color[1] = g
	le.color[2] = b
	le.color[3] = a

	le.pos.trType = C.TR_LINEAR_STOP
	le.pos.trTime = startTime
	Q.VectorCopy(vel, le.pos.trDelta)
	Q.VectorCopy(p, le.pos.trBase)

	Q.VectorCopy(p, re.origin)
	re.customShader = hShader

	-- rage pro can't alpha fade, so use a different shader
	if G.cgs.glconfig.hardwareType == C.GLHW_RAGEPRO then
		re.customShader = G.cgs.media.smokePuffRageProShader
		re.shaderRGBA[0] = 0xff
		re.shaderRGBA[1] = 0xff
		re.shaderRGBA[2] = 0xff
		re.shaderRGBA[3] = 0xff
	else
		re.shaderRGBA[0] = Q.int(le.color[0] * 0xff)
		re.shaderRGBA[1] = Q.int(le.color[1] * 0xff)
		re.shaderRGBA[2] = Q.int(le.color[2] * 0xff)
		re.shaderRGBA[3] = 0xff
	end

	re.reType = C.RT_SPRITE
	re.radius = le.radius

	return le
end

-- LEILEI same as above, but slows down.......
function G.CG_SlowPuff(p, vel, radius, r, g, b, a, duration, startTime, fadeInTime, leFlags, hShader)
	local le = G.CG_AllocLocalEntity()
	le.leFlags = leFlags
	le.radius = radius

	local re = le.refEntity
	local rnd
	slowSeed, rnd = nextRandom(slowSeed)
	re.rotation = rnd * 360
	re.radius = radius
	re.shaderTime = startTime / 1000.0

	le.leType = C.LE_MOVE_SCALE_FADE
	le.startTime = startTime
	le.fadeInTime = fadeInTime
	le.endTime = startTime + duration
	if fadeInTime > startTime then
		le.lifeRate = 1.0 / (le.endTime - le.fadeInTime)
	else
		le.lifeRate = 1.0 / (le.endTime - le.startTime)
	end
	le.color[0] = r
	le.color[1] = g
	le.color[2] = b
	le.color[3] = a

	le.pos.trType = C.TR_LINEAR
	le.pos.trTime = startTime
	Q.VectorCopy(vel, le.pos.trDelta)
	Q.VectorCopy(p, le.pos.trBase)

	Q.VectorCopy(p, re.origin)
	re.customShader = hShader

	-- rage pro can't alpha fade, so use a different shader
	if G.cgs.glconfig.hardwareType == C.GLHW_RAGEPRO then
		re.customShader = G.cgs.media.smokePuffRageProShader
		re.shaderRGBA[0] = 0xff
		re.shaderRGBA[1] = 0xff
		re.shaderRGBA[2] = 0xff
		re.shaderRGBA[3] = 0xff
	else
		re.shaderRGBA[0] = Q.int(le.color[0] * 0xff)
		re.shaderRGBA[1] = Q.int(le.color[1] * 0xff)
		re.shaderRGBA[2] = Q.int(le.color[2] * 0xff)
		re.shaderRGBA[3] = 0xff
	end

	re.reType = C.RT_SPRITE
	re.radius = le.radius

	return le
end

-- Player teleporting in or out
function G.CG_SpawnEffect(org)
	local le = G.CG_AllocLocalEntity()
	le.leFlags = 0
	le.leType = C.LE_FADE_RGB
	le.startTime = G.cg.time
	le.endTime = G.cg.time + 500
	le.lifeRate = 1.0 / (le.endTime - le.startTime)

	le.color[0] = 1.0
	le.color[1] = 1.0
	le.color[2] = 1.0
	le.color[3] = 1.0

	local re = le.refEntity

	re.reType = C.RT_MODEL
	re.shaderTime = G.cg.time / 1000.0

	re.customShader = G.cgs.media.teleportEffectShader
	re.hModel = G.cgs.media.teleportEffectModel
	Q.AxisClear(re.axis)

	Q.VectorCopy(org, re.origin)
	re.origin[2] -= 24
end

function G.CG_LightningBoltBeam(start, finish)
	local le = G.CG_AllocLocalEntity()
	le.leFlags = 0
	le.leType = C.LE_SHOWREFENTITY
	le.startTime = G.cg.time
	le.endTime = G.cg.time + 50

	local beam = le.refEntity

	Q.VectorCopy(start, beam.origin)
	-- this is the end point
	Q.VectorCopy(finish, beam.oldorigin)

	beam.reType = C.RT_LIGHTNING
	beam.customShader = G.cgs.media.lightningShader
end

function G.CG_KamikazeEffect(org)
	local le = G.CG_AllocLocalEntity()
	le.leFlags = 0
	le.leType = C.LE_KAMIKAZE
	le.startTime = G.cg.time
	le.endTime = G.cg.time + 3000 --2250
	le.lifeRate = 1.0 / (le.endTime - le.startTime)

	le.color[0] = 1.0
	le.color[1] = 1.0
	le.color[2] = 1.0
	le.color[3] = 1.0

	le.angles.trBase[0] = 0
	le.angles.trBase[1] = 0
	le.angles.trBase[2] = 0

	local re = le.refEntity

	re.reType = C.RT_MODEL
	re.shaderTime = G.cg.time / 1000.0

	re.hModel = G.cgs.media.kamikazeEffectModel

	Q.VectorCopy(org, re.origin)
end

function G.CG_ObeliskExplode(org, entityNum)
	local origin = Q.vec3(0, 0, 0)

	-- create an explosion
	Q.VectorCopy(org, origin)
	origin[2] += 64
	local le = G.CG_MakeExplosion(origin, Q.vec3_origin,
		G.cgs.media.dishFlashModel,
		G.cgs.media.rocketExplosionShader,
		600, true)
	le.light = 300
	le.lightColor[0] = 1
	le.lightColor[1] = 0.75
	le.lightColor[2] = 0.0
end

function G.CG_ObeliskPain(org)
	local sfx

	-- hit sound
	local r = bit32.band(Q.rand(), 3)
	if r < 2 then
		sfx = G.cgs.media.obeliskHitSound1
	elseif r == 2 then
		sfx = G.cgs.media.obeliskHitSound2
	else
		sfx = G.cgs.media.obeliskHitSound3
	end
	trap.S_StartSound(org, C.ENTITYNUM_NONE, C.CHAN_BODY, sfx)
end

function G.CG_InvulnerabilityImpact(org, angles)
	local sfx

	local le = G.CG_AllocLocalEntity()
	le.leFlags = 0
	le.leType = C.LE_INVULIMPACT
	le.startTime = G.cg.time
	le.endTime = G.cg.time + 1000
	le.lifeRate = 1.0 / (le.endTime - le.startTime)

	le.color[0] = 1.0
	le.color[1] = 1.0
	le.color[2] = 1.0
	le.color[3] = 1.0

	local re = le.refEntity

	re.reType = C.RT_MODEL
	re.shaderTime = G.cg.time / 1000.0

	re.hModel = G.cgs.media.invulnerabilityImpactModel

	Q.VectorCopy(org, re.origin)
	Q.AnglesToAxis(angles, re.axis)

	local r = bit32.band(Q.rand(), 3)
	if r < 2 then
		sfx = G.cgs.media.invulnerabilityImpactSound1
	elseif r == 2 then
		sfx = G.cgs.media.invulnerabilityImpactSound2
	else
		sfx = G.cgs.media.invulnerabilityImpactSound3
	end
	trap.S_StartSound(org, C.ENTITYNUM_NONE, C.CHAN_BODY, sfx)
end

function G.CG_InvulnerabilityJuiced(org)
	local angles = Q.vec3(0, 0, 0)

	local le = G.CG_AllocLocalEntity()
	le.leFlags = 0
	le.leType = C.LE_INVULJUICED
	le.startTime = G.cg.time
	le.endTime = G.cg.time + 10000
	le.lifeRate = 1.0 / (le.endTime - le.startTime)

	le.color[0] = 1.0
	le.color[1] = 1.0
	le.color[2] = 1.0
	le.color[3] = 1.0

	local re = le.refEntity

	re.reType = C.RT_MODEL
	re.shaderTime = G.cg.time / 1000.0

	re.hModel = G.cgs.media.invulnerabilityJuicedModel

	Q.VectorCopy(org, re.origin)
	Q.AnglesToAxis(angles, re.axis)

	trap.S_StartSound(org, C.ENTITYNUM_NONE, C.CHAN_BODY, G.cgs.media.invulnerabilityJuicedSound)
end

function G.CG_ScorePlum(client, org, score)
	local angles = Q.vec3(0, 0, 0)

	-- only visualize for the client that scored
	if client ~= G.cg.predictedPlayerState.clientNum or G.cg_scorePlum.integer == 0 then
		return
	end

	local le = G.CG_AllocLocalEntity()
	le.leFlags = 0
	le.leType = C.LE_SCOREPLUM
	le.startTime = G.cg.time
	le.endTime = G.cg.time + 4000
	le.lifeRate = 1.0 / (le.endTime - le.startTime)

	le.color[0] = 1.0
	le.color[1] = 1.0
	le.color[2] = 1.0
	le.color[3] = 1.0
	le.radius = score

	Q.VectorCopy(org, le.pos.trBase)
	if org[2] >= lastPos[2] - 20 and org[2] <= lastPos[2] + 20 then
		le.pos.trBase[2] -= 20
	end

	Q.VectorCopy(org, lastPos)

	local re = le.refEntity

	re.reType = C.RT_SPRITE
	re.radius = 16

	Q.AnglesToAxis(angles, re.axis)
end

function G.CG_MakeExplosion(origin, dir, hModel, shader, msec, isSprite)
	local tmpVec = Q.vec3(0, 0, 0)
	local newOrigin = Q.vec3(0, 0, 0)

	if msec <= 0 then
		G.CG_Error(Q.va("CG_MakeExplosion: msec = %i", msec))
	end

	-- skew the time a bit so they aren't all in sync
	local offset = bit32.band(Q.rand(), 63)

	local ex = G.CG_AllocLocalEntity()
	if isSprite then
		ex.leType = C.LE_SPRITE_EXPLOSION

		-- randomly rotate sprite orientation
		ex.refEntity.rotation = Q.rand() % 360
		Q.VectorScale(dir, 16, tmpVec)
		Q.VectorAdd(tmpVec, origin, newOrigin)
	else
		ex.leType = C.LE_EXPLOSION
		Q.VectorCopy(origin, newOrigin)

		-- set axis with random rotate
		if dir == nil then
			Q.AxisClear(ex.refEntity.axis)
		else
			local ang = Q.rand() % 360
			Q.VectorCopy(dir, ex.refEntity.axis[0])
			Q.RotateAroundDirection(ex.refEntity.axis, ang)
		end
	end

	ex.startTime = G.cg.time - offset
	ex.endTime = ex.startTime + msec

	-- bias the time so all shader effects start correctly
	ex.refEntity.shaderTime = ex.startTime / 1000.0

	ex.refEntity.hModel = hModel
	ex.refEntity.customShader = shader

	-- set origin
	Q.VectorCopy(newOrigin, ex.refEntity.origin)
	Q.VectorCopy(newOrigin, ex.refEntity.oldorigin)

	ex.color[0] = 1.0
	ex.color[1] = 1.0
	ex.color[2] = 1.0

	return ex
end

-- This is the spurt of blood when a character gets hit
function G.CG_Bleed(origin, entityNum)
	if G.cg_blood.integer == 0 then
		return
	end

	local ex = G.CG_AllocLocalEntity()
	ex.leType = C.LE_EXPLOSION

	ex.startTime = G.cg.time
	ex.endTime = ex.startTime + 500

	Q.VectorCopy(origin, ex.refEntity.origin)
	ex.refEntity.reType = C.RT_SPRITE
	ex.refEntity.rotation = Q.rand() % 360
	ex.refEntity.radius = 24

	ex.refEntity.shaderTime = ex.startTime / 1000.0 -- leilei-  fix the blood animation
	ex.refEntity.customShader = G.cgs.media.bloodExplosionShader

	-- don't show player's own blood in view
	if entityNum == G.cg.snap.ps.clientNum then
		ex.refEntity.renderfx = bit32.bor(ex.refEntity.renderfx, C.RF_THIRD_PERSON)
	end
end

function G.CG_SpurtBlood(origin, velocity, hard)
	velocity[0] = velocity[0] * hard * Q.crandom() * 460
	velocity[1] = velocity[1] * hard * Q.crandom() * 460
	velocity[2] = velocity[2] * hard * Q.crandom() * 566 + 65
	local blood = G.CG_SmokePuff(origin, velocity,
		21, -- radius
		1, 1, 1, 1, -- color
		2450, -- trailTime
		G.cg.time, -- startTime
		0, -- fadeInTime
		0, -- flags
		G.cgs.media.lbldShader1)
	-- use the optimized version
	blood.leType = C.LE_FALL_SCALE_FADE
	blood.leType = C.LE_GORE
	blood.pos.trType = C.TR_GRAVITY
	Q.VectorCopy(velocity, blood.pos.trDelta)
	blood.pos.trDelta[2] = 55
	if Q.crandom() < 0.5 then
		blood.leMarkType = C.LEMT_BURN
		blood.leBounceSoundType = C.LEBS_BLOOD
	end
end

function G.CG_LaunchGib(origin, velocity, hModel)
	local le = G.CG_AllocLocalEntity()
	local re = le.refEntity

	le.leType = C.LE_FRAGMENT
	le.startTime = G.cg.time
	le.endTime = le.startTime + 5000 + Q.random() * 3000

	Q.VectorCopy(origin, re.origin)
	Q.AxisCopy(Q.axisDefault, re.axis)
	re.hModel = hModel

	le.pos.trType = C.TR_GRAVITY
	Q.VectorCopy(origin, le.pos.trBase)
	Q.VectorCopy(velocity, le.pos.trDelta)
	le.pos.trTime = G.cg.time

	le.bounceFactor = 0.6

	le.leBounceSoundType = C.LEBS_BLOOD
	le.leMarkType = C.LEMT_BLOOD
end

-- Generated a bunch of gibs launching out from the bodies location
function G.CG_GibPlayer(playerOrigin)
	local origin = Q.vec3(0, 0, 0)
	local velocity = Q.vec3(0, 0, 0)

	if G.cg_blood.integer == 0 then
		return
	end

	Q.VectorCopy(playerOrigin, origin)
	velocity[0] = Q.crandom() * GIB_VELOCITY
	velocity[1] = Q.crandom() * GIB_VELOCITY
	velocity[2] = GIB_JUMP + Q.crandom() * GIB_VELOCITY
	if bit32.band(Q.rand(), 1) ~= 0 then
		G.CG_LaunchGib(origin, velocity, G.cgs.media.gibSkull)
	else
		G.CG_LaunchGib(origin, velocity, G.cgs.media.gibBrain)
	end

	-- allow gibs to be turned off for speed
	if G.cg_gibs.integer == 0 then
		return
	end

	local models = {
		G.cgs.media.gibAbdomen,
		G.cgs.media.gibArm,
		G.cgs.media.gibChest,
		G.cgs.media.gibFist,
		G.cgs.media.gibFoot,
		G.cgs.media.gibForearm,
		G.cgs.media.gibIntestine,
		G.cgs.media.gibLeg,
		G.cgs.media.gibLeg,
	}
	for _, model in models do
		Q.VectorCopy(playerOrigin, origin)
		velocity[0] = Q.crandom() * GIB_VELOCITY
		velocity[1] = Q.crandom() * GIB_VELOCITY
		velocity[2] = GIB_JUMP + Q.crandom() * GIB_VELOCITY
		G.CG_LaunchGib(origin, velocity, model)
	end
end

function G.CG_LaunchExplode(origin, velocity, hModel)
	local le = G.CG_AllocLocalEntity()
	local re = le.refEntity

	le.leType = C.LE_FRAGMENT
	le.startTime = G.cg.time
	le.endTime = le.startTime + 10000 + Q.random() * 6000

	Q.VectorCopy(origin, re.origin)
	Q.AxisCopy(Q.axisDefault, re.axis)
	re.hModel = hModel

	le.pos.trType = C.TR_GRAVITY
	Q.VectorCopy(origin, le.pos.trBase)
	Q.VectorCopy(velocity, le.pos.trDelta)
	le.pos.trTime = G.cg.time

	le.bounceFactor = 0.1

	le.leBounceSoundType = C.LEBS_BRASS
	le.leMarkType = C.LEMT_NONE
end

-- Generated a bunch of gibs launching out from the bodies location
function G.CG_BigExplosion(playerOrigin)
	local origin = Q.vec3(0, 0, 0)
	local velocity = Q.vec3(0, 0, 0)

	if G.cg_blood.integer == 0 then
		return
	end

	local scales = { 1, 1, 1.5, 2.0, 2.5 }
	for _, s in scales do
		Q.VectorCopy(playerOrigin, origin)
		velocity[0] = Q.crandom() * EXP_VELOCITY * s
		velocity[1] = Q.crandom() * EXP_VELOCITY * s
		velocity[2] = EXP_JUMP + Q.crandom() * EXP_VELOCITY
		G.CG_LaunchExplode(origin, velocity, G.cgs.media.smoke2)
	end
end

return G
