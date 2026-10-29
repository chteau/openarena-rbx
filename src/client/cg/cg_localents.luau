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
-- Luau port of code/cgame/cg_localents.c (OpenArena 0.8.8, gamecode 9e0f0c0).

-- cg_localents.c -- every frame, generate renderer commands for locally
-- processed entities, like smoke puffs, gibs, shells, etc.

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

local MAX_LOCAL_ENTITIES = 512
local NUMBER_SIZE = 8

G.cg_localEntities = {}
G.cg_activeLocalEntities = T.localEntity_t() -- double linked list
G.cg_freeLocalEntities = nil -- single linked list

local function u8(x: number): number
	return bit32.band(Q.int(x), 255)
end

--[[
===================
CG_InitLocalEntities

This is called at startup and for tournement restarts
===================
]]
function G.CG_InitLocalEntities()
	G.cg_localEntities = {}
	for i = 0, MAX_LOCAL_ENTITIES - 1 do
		G.cg_localEntities[i] = T.localEntity_t()
	end
	local active = G.cg_activeLocalEntities
	active.next = active
	active.prev = active
	G.cg_freeLocalEntities = G.cg_localEntities[0]
	for i = 0, MAX_LOCAL_ENTITIES - 2 do
		G.cg_localEntities[i].next = G.cg_localEntities[i + 1]
	end
end

function G.CG_FreeLocalEntity(le)
	if le.prev == nil then
		G.CG_Error("CG_FreeLocalEntity: not active")
	end

	-- remove from the doubly linked active list
	le.prev.next = le.next
	le.next.prev = le.prev

	-- the free list is only singly linked
	le.next = G.cg_freeLocalEntities
	G.cg_freeLocalEntities = le
end

--[[
===================
CG_AllocLocalEntity

Will always succeed, even if it requires freeing an old active entity
===================
]]
function G.CG_AllocLocalEntity()
	if G.cg_freeLocalEntities == nil then
		-- no free entities, so free the one at the end of the chain
		-- remove the oldest active entity
		G.CG_FreeLocalEntity(G.cg_activeLocalEntities.prev)
	end

	local le = G.cg_freeLocalEntities
	G.cg_freeLocalEntities = le.next

	T.reset(le, T.localEntity_t)
	le.next = nil
	le.prev = nil

	-- link into the active list
	local active = G.cg_activeLocalEntities
	le.next = active.next
	le.prev = active
	active.next.prev = le
	active.next = le
	return le
end

--[[
CG_BloodTrail

Leave expanding blood puffs behind gibs
]]
function G.CG_BloodTrail(le)
	local cg = G.cg
	local newOrigin = Q.vec3(0, 0, 0)

	local step = 150
	local t = step * Q.idiv(cg.time - cg.frametime + step, step)
	local t2 = step * Q.idiv(cg.time, step)

	while t <= t2 do
		BG.BG_EvaluateTrajectory(le.pos, t, newOrigin)

		local blood = G.CG_SmokePuff(newOrigin, Q.vec3_origin,
			20, -- radius
			1, 1, 1, 1, -- color
			2000, -- trailTime
			t, -- startTime
			0, -- fadeInTime
			0, -- flags
			G.cgs.media.bloodTrailShader)
		-- use the optimized version
		blood.leType = C.LE_FALL_SCALE_FADE
		-- drop a total of 40 units over its lifetime
		blood.pos.trDelta[2] = 40
		t += step
	end
end

-- LEILEI
function G.CG_SmallBloodTrail(le)
	local cg = G.cg
	local newOrigin = Q.vec3(0, 0, 0)

	local step = 61
	local t = step * Q.idiv(cg.time - cg.frametime + step, step)
	local t2 = step * Q.idiv(cg.time, step)

	while t <= t2 do
		BG.BG_EvaluateTrajectory(le.pos, t, newOrigin)

		local blood = G.CG_SmokePuff(newOrigin, Q.vec3_origin,
			3, -- radius
			1, 1, 1, 1, -- color
			770, -- trailTime
			t, -- startTime
			0, -- fadeInTime
			0, -- flags
			G.cgs.media.lbldShader1)
		-- use the optimized version
		blood.leType = C.LE_FALL_SCALE_FADE
		-- drop a total of 40 units over its lifetime
		blood.pos.trDelta[2] = 120
		t += step
	end
end

function G.CG_FragmentBounceMark(le, trace)
	if le.leMarkType == C.LEMT_BLOOD then
		local radius = 16 + bit32.band(Q.rand(), 31)
		G.CG_ImpactMark(G.cgs.media.bloodMarkShader, trace.endpos, trace.plane.normal, Q.random() * 360,
			1, 1, 1, 1, true, radius, false)
	elseif le.leMarkType == C.LEMT_BURN then
		local radius = 8 + bit32.band(Q.rand(), 15)
		G.CG_ImpactMark(G.cgs.media.burnMarkShader, trace.endpos, trace.plane.normal, Q.random() * 360,
			1, 1, 1, 1, true, radius, false)
	end

	-- don't allow a fragment to make multiple marks, or they
	-- pile up while settling
	le.leMarkType = C.LEMT_NONE
end

local function bounceSound(trace, s1, s2, s3)
	-- half the casings will make sounds
	if bit32.band(Q.rand(), 1) ~= 0 then
		local r = bit32.band(Q.rand(), 3)
		local s
		if r == 0 then
			s = s1
		elseif r == 1 then
			s = s2
		else
			s = s3
		end
		trap.S_StartSound(trace.endpos, C.ENTITYNUM_WORLD, C.CHAN_AUTO, s)
	end
end

function G.CG_FragmentBounceSound(le, trace)
	local media = G.cgs.media
	if le.leBounceSoundType == C.LEBS_BLOOD then
		bounceSound(trace, media.gibBounce1Sound, media.gibBounce2Sound, media.gibBounce3Sound)
	elseif le.leBounceSoundType == C.LEBS_BRASS then
		if G.cg_leiBrassNoise.integer ~= 0 then
			bounceSound(trace, media.lbul1Sound, media.lbul2Sound, media.lbul3Sound)
		end
	elseif le.leBounceSoundType == C.LEBS_SHELL then
		if G.cg_leiBrassNoise.integer ~= 0 then
			bounceSound(trace, media.lshl1Sound, media.lshl2Sound, media.lshl3Sound)
		end
	end

	-- don't allow a fragment to make multiple bounce sounds,
	-- or it gets too noisy as they settle
	le.leBounceSoundType = C.LEBS_NONE
end

-- LEILEI
function G.CG_GoreMark(le, trace)
	if le.leMarkType == C.LEMT_BURN then
		local radius = 6 + bit32.band(Q.rand(), 16)
		G.CG_ImpactMark(G.cgs.media.lbldShader2, trace.endpos, trace.plane.normal, Q.random() * 360,
			1, 1, 1, 1, true, radius, false)
	end

	le.leMarkType = C.LEMT_NONE
end

-- LEILEI
function G.CG_SplatSound(le, trace)
	local media = G.cgs.media
	if le.leBounceSoundType == C.LEBS_BLOOD then
		-- half the splats will make splat sounds
		if G.cg_leiGoreNoise.integer ~= 0 then
			bounceSound(trace, media.lspl1Sound, media.lspl2Sound, media.lspl3Sound)
		end
	end

	-- don't allow a fragment to make multiple bounce sounds,
	-- or it gets too noisy as they settle
	le.leBounceSoundType = C.LEBS_NONE
end

function G.CG_ReflectVelocity(le, trace)
	local cg = G.cg
	local velocity = Q.vec3(0, 0, 0)

	-- reflect the velocity on the trace plane
	local hitTime = Q.int(cg.time - cg.frametime + cg.frametime * trace.fraction)
	BG.BG_EvaluateTrajectoryDelta(le.pos, hitTime, velocity)
	local dot = Q.DotProduct(velocity, trace.plane.normal)
	Q.VectorMA(velocity, -2 * dot, trace.plane.normal, le.pos.trDelta)

	Q.VectorScale(le.pos.trDelta, le.bounceFactor, le.pos.trDelta)

	Q.VectorCopy(trace.endpos, le.pos.trBase)
	le.pos.trTime = cg.time

	-- check for stop, making sure that even on low FPS systems it doesn't bobble
	if trace.allsolid
		or (trace.plane.normal[2] > 0
			and (le.pos.trDelta[2] < 40 or le.pos.trDelta[2] < -cg.frametime * le.pos.trDelta[2]))
	then
		le.pos.trType = C.TR_STATIONARY
	end
end

function G.CG_AddFragment(le)
	local cg = G.cg
	local newOrigin = Q.vec3(0, 0, 0)
	local trace = T.trace_t()

	if le.pos.trType == C.TR_STATIONARY then
		-- sink into the ground if near the removal time
		local t = le.endTime - cg.time
		if t < C.SINK_TIME then
			-- we must use an explicit lighting origin, otherwise the
			-- lighting would be lost as soon as the origin went
			-- into the ground
			Q.VectorCopy(le.refEntity.origin, le.refEntity.lightingOrigin)
			le.refEntity.renderfx = bit32.bor(le.refEntity.renderfx, C.RF_LIGHTING_ORIGIN)
			local oldZ = le.refEntity.origin[2]
			le.refEntity.origin[2] -= 16 * (1.0 - t / C.SINK_TIME)
			trap.R_AddRefEntityToScene(le.refEntity)
			le.refEntity.origin[2] = oldZ
		else
			trap.R_AddRefEntityToScene(le.refEntity)
		end

		return
	end

	-- calculate new position
	BG.BG_EvaluateTrajectory(le.pos, cg.time, newOrigin)

	-- trace a line from previous position to new position
	G.CG_Trace(trace, le.refEntity.origin, nil, nil, newOrigin, -1, C.CONTENTS_SOLID)
	if trace.fraction == 1.0 then
		-- still in free fall
		Q.VectorCopy(newOrigin, le.refEntity.origin)

		if bit32.band(le.leFlags, C.LEF_TUMBLE) ~= 0 then
			local angles = Q.vec3(0, 0, 0)

			BG.BG_EvaluateTrajectory(le.angles, cg.time, angles)
			Q.AnglesToAxis(angles, le.refEntity.axis)
		end

		trap.R_AddRefEntityToScene(le.refEntity)

		-- add a blood trail
		if le.leBounceSoundType == C.LEBS_BLOOD then
			G.CG_BloodTrail(le)
		end

		return
	end

	-- if it is in a nodrop zone, remove it
	-- this keeps gibs from waiting at the bottom of pits of death
	-- and floating levels
	if bit32.band(G.CG_PointContents(trace.endpos, 0), C.CONTENTS_NODROP) ~= 0 then
		G.CG_FreeLocalEntity(le)
		return
	end

	-- leave a mark
	G.CG_FragmentBounceMark(le, trace)

	-- do a bouncy sound
	G.CG_FragmentBounceSound(le, trace)

	-- reflect the velocity on the trace plane
	G.CG_ReflectVelocity(le, trace)

	trap.R_AddRefEntityToScene(le.refEntity)
end

-- LEILEI
function G.CG_JustSplat(le, trace)
	local cg = G.cg
	local velocity = Q.vec3(0, 0, 0)

	-- reflect the velocity on the trace plane
	local hitTime = Q.int(cg.time - cg.frametime + cg.frametime * trace.fraction)
	BG.BG_EvaluateTrajectoryDelta(le.pos, hitTime, velocity)
	local dot = Q.DotProduct(velocity, trace.plane.normal)
	Q.VectorMA(velocity, -2 * dot, trace.plane.normal, le.pos.trDelta)

	Q.VectorScale(le.pos.trDelta, le.bounceFactor, le.pos.trDelta)

	Q.VectorCopy(trace.endpos, le.pos.trBase)
	le.pos.trTime = cg.time

	-- check for stop, making sure that even on low FPS systems it doesn't bobble
	if trace.allsolid
		or (trace.plane.normal[2] > 0
			and (le.pos.trDelta[2] < 40 or le.pos.trDelta[2] < -cg.frametime * le.pos.trDelta[2]))
	then
		le.pos.trType = C.TR_STATIONARY
	end
end

function G.CG_AddGore(le)
	local cg = G.cg
	local newOrigin = Q.vec3(0, 0, 0)
	local trace = T.trace_t()

	if le.pos.trType == C.TR_STATIONARY then
		G.CG_FreeLocalEntity(le) -- kill it
		return
	end

	-- calculate new position
	BG.BG_EvaluateTrajectory(le.pos, cg.time, newOrigin)

	-- trace a line from previous position to new position
	G.CG_Trace(trace, le.refEntity.origin, nil, nil, newOrigin, -1, C.CONTENTS_SOLID)
	if trace.fraction == 1.0 then
		-- still in free fall
		Q.VectorCopy(newOrigin, le.refEntity.origin)

		if bit32.band(le.leFlags, C.LEF_TUMBLE) ~= 0 then
			local angles = Q.vec3(0, 0, 0)

			BG.BG_EvaluateTrajectory(le.angles, cg.time, angles)
			Q.AnglesToAxis(angles, le.refEntity.axis)
		end

		trap.R_AddRefEntityToScene(le.refEntity)

		G.CG_SmallBloodTrail(le)

		return
	end

	-- if it is in a nodrop zone, remove it
	-- this keeps gibs from waiting at the bottom of pits of death
	-- and floating levels
	if bit32.band(trap.CM_PointContents(trace.endpos, 0), C.CONTENTS_NODROP) ~= 0 then
		G.CG_FreeLocalEntity(le)
		return
	end

	-- leave a mark
	G.CG_GoreMark(le, trace)

	-- do a juicy sound
	G.CG_SplatSound(le, trace)

	G.CG_JustSplat(le, trace)

	trap.R_AddRefEntityToScene(le.refEntity)
end

--[[
TRIVIAL LOCAL ENTITIES

These only do simple scaling or modulation before passing to the renderer
]]

function G.CG_AddFadeRGB(le)
	local cg = G.cg
	local re = le.refEntity

	local c = (le.endTime - cg.time) * le.lifeRate
	c *= 0xff

	re.shaderRGBA[0] = u8(le.color[0] * c)
	re.shaderRGBA[1] = u8(le.color[1] * c)
	re.shaderRGBA[2] = u8(le.color[2] * c)
	re.shaderRGBA[3] = u8(le.color[3] * c)

	trap.R_AddRefEntityToScene(re)
end

local function CG_AddMoveScaleFade(le)
	local cg = G.cg
	local re = le.refEntity
	local c

	if le.fadeInTime > le.startTime and cg.time < le.fadeInTime then
		-- fade / grow time
		c = 1.0 - (le.fadeInTime - cg.time) / (le.fadeInTime - le.startTime)
	else
		-- fade / grow time
		c = (le.endTime - cg.time) * le.lifeRate
	end

	re.shaderRGBA[3] = u8(0xff * c * le.color[3])

	if bit32.band(le.leFlags, C.LEF_PUFF_DONT_SCALE) == 0 then
		re.radius = le.radius * (1.0 - c) + 8
	end

	BG.BG_EvaluateTrajectory(le.pos, cg.time, re.origin)

	-- if the view would be "inside" the sprite, kill the sprite
	-- so it doesn't add too much overdraw
	local delta = Q.vec3(0, 0, 0)
	Q.VectorSubtract(re.origin, cg.refdef.vieworg, delta)
	local len = Q.VectorLength(delta)
	if len < le.radius then
		G.CG_FreeLocalEntity(le)
		return
	end

	trap.R_AddRefEntityToScene(re)
end

--[[
CG_AddScaleFade

For rocket smokes that hang in place, fade out, and are
removed if the view passes through them.
There are often many of these, so it needs to be simple.
]]
local function CG_AddScaleFade(le)
	local cg = G.cg
	local re = le.refEntity

	-- fade / grow time
	local c = (le.endTime - cg.time) * le.lifeRate

	re.shaderRGBA[3] = u8(0xff * c * le.color[3])
	re.radius = le.radius * (1.0 - c) + 8

	-- if the view would be "inside" the sprite, kill the sprite
	-- so it doesn't add too much overdraw
	local delta = Q.vec3(0, 0, 0)
	Q.VectorSubtract(re.origin, cg.refdef.vieworg, delta)
	local len = Q.VectorLength(delta)
	-- LEILEI
	if G.cg_leiEnhancement.integer == 0 then
		if len < le.radius then
			G.CG_FreeLocalEntity(le)
			return
		end
	end
	trap.R_AddRefEntityToScene(re)
end

--[[
CG_AddFallScaleFade

This is just an optimized CG_AddMoveScaleFade
For blood mists that drift down, fade out, and are
removed if the view passes through them.
There are often 100+ of these, so it needs to be simple.
]]
local function CG_AddFallScaleFade(le)
	local cg = G.cg
	local re = le.refEntity

	-- fade time
	local c = (le.endTime - cg.time) * le.lifeRate

	re.shaderRGBA[3] = u8(0xff * c * le.color[3])

	re.origin[2] = le.pos.trBase[2] - (1.0 - c) * le.pos.trDelta[2]

	re.radius = le.radius * (1.0 - c) + 16

	-- if the view would be "inside" the sprite, kill the sprite
	-- so it doesn't add too much overdraw
	local delta = Q.vec3(0, 0, 0)
	Q.VectorSubtract(re.origin, cg.refdef.vieworg, delta)
	local len = Q.VectorLength(delta)

	-- LEILEI
	if G.cg_leiEnhancement.integer == 0 then
		if len < le.radius then
			G.CG_FreeLocalEntity(le)
			return
		end
	end
	trap.R_AddRefEntityToScene(re)
end

local function CG_AddExplosion(ex)
	local cg = G.cg
	local ent = ex.refEntity

	-- add the entity
	trap.R_AddRefEntityToScene(ent)

	-- add the dlight
	if ex.light ~= 0 then
		local light = (cg.time - ex.startTime) / (ex.endTime - ex.startTime)
		if light < 0.5 then
			light = 1.0
		else
			light = 1.0 - (light - 0.5) * 2
		end
		light = ex.light * light
		trap.R_AddLightToScene(ent.origin, light, ex.lightColor[0], ex.lightColor[1], ex.lightColor[2])
	end
end

local function CG_AddSpriteExplosion(le)
	local cg = G.cg
	local re = T.copy(le.refEntity)

	local c = (le.endTime - cg.time) / (le.endTime - le.startTime)
	if c > 1 then
		c = 1.0 -- can happen during connection problems
	end

	re.shaderRGBA[0] = 0xff
	re.shaderRGBA[1] = 0xff
	re.shaderRGBA[2] = 0xff
	re.shaderRGBA[3] = u8(0xff * c * 0.33)

	re.reType = C.RT_SPRITE
	re.radius = 42 * (1.0 - c) + 30

	trap.R_AddRefEntityToScene(re)

	-- add the dlight
	if le.light ~= 0 then
		local light = (cg.time - le.startTime) / (le.endTime - le.startTime)
		if light < 0.5 then
			light = 1.0
		else
			light = 1.0 - (light - 0.5) * 2
		end
		light = le.light * light
		trap.R_AddLightToScene(re.origin, light, le.lightColor[0], le.lightColor[1], le.lightColor[2])
	end
end

function G.CG_AddKamikaze(le)
	local cg = G.cg
	local re = le.refEntity
	local c

	local t = cg.time - le.startTime
	local test = Q.vec3(0, 0, 0)
	local axis = { [0] = Q.vec3(0, 0, 0), Q.vec3(0, 0, 0), Q.vec3(0, 0, 0) }
	Q.AnglesToAxis(test, axis)

	if t > C.KAMI_SHOCKWAVE_STARTTIME and t < C.KAMI_SHOCKWAVE_ENDTIME then
		if bit32.band(le.leFlags, C.LEF_SOUND1) == 0 then
			trap.S_StartLocalSound(G.cgs.media.kamikazeExplodeSound, C.CHAN_AUTO)
			le.leFlags = bit32.bor(le.leFlags, C.LEF_SOUND1)
		end
		-- 1st kamikaze shockwave
		local shockwave = T.refEntity_t()
		shockwave.hModel = G.cgs.media.kamikazeShockWave
		shockwave.reType = C.RT_MODEL
		shockwave.shaderTime = re.shaderTime
		Q.VectorCopy(re.origin, shockwave.origin)

		c = (t - C.KAMI_SHOCKWAVE_STARTTIME) / (C.KAMI_SHOCKWAVE_ENDTIME - C.KAMI_SHOCKWAVE_STARTTIME)
		for i = 0, 2 do
			Q.VectorScale(axis[i], c * C.KAMI_SHOCKWAVE_MAXRADIUS / C.KAMI_SHOCKWAVEMODEL_RADIUS, shockwave.axis[i])
		end
		shockwave.nonNormalizedAxes = true

		if t > C.KAMI_SHOCKWAVEFADE_STARTTIME then
			c = (t - C.KAMI_SHOCKWAVEFADE_STARTTIME) / (C.KAMI_SHOCKWAVE_ENDTIME - C.KAMI_SHOCKWAVEFADE_STARTTIME)
		else
			c = 0
		end
		c *= 0xff
		shockwave.shaderRGBA[0] = u8(0xff - c)
		shockwave.shaderRGBA[1] = u8(0xff - c)
		shockwave.shaderRGBA[2] = u8(0xff - c)
		shockwave.shaderRGBA[3] = u8(0xff - c)

		trap.R_AddRefEntityToScene(shockwave)
	end

	if t > C.KAMI_EXPLODE_STARTTIME and t < C.KAMI_IMPLODE_ENDTIME then
		-- explosion and implosion
		c = (le.endTime - cg.time) * le.lifeRate
		c *= 0xff
		re.shaderRGBA[0] = u8(le.color[0] * c)
		re.shaderRGBA[1] = u8(le.color[1] * c)
		re.shaderRGBA[2] = u8(le.color[2] * c)
		re.shaderRGBA[3] = u8(le.color[3] * c)

		if t < C.KAMI_IMPLODE_STARTTIME then
			c = (t - C.KAMI_EXPLODE_STARTTIME) / (C.KAMI_IMPLODE_STARTTIME - C.KAMI_EXPLODE_STARTTIME)
		else
			if bit32.band(le.leFlags, C.LEF_SOUND2) == 0 then
				trap.S_StartLocalSound(G.cgs.media.kamikazeImplodeSound, C.CHAN_AUTO)
				le.leFlags = bit32.bor(le.leFlags, C.LEF_SOUND2)
			end
			c = (C.KAMI_IMPLODE_ENDTIME - t) / (C.KAMI_IMPLODE_ENDTIME - C.KAMI_IMPLODE_STARTTIME)
		end
		for i = 0, 2 do
			Q.VectorScale(axis[i], c * C.KAMI_BOOMSPHERE_MAXRADIUS / C.KAMI_BOOMSPHEREMODEL_RADIUS, re.axis[i])
		end
		re.nonNormalizedAxes = true

		trap.R_AddRefEntityToScene(re)
		-- add the dlight
		trap.R_AddLightToScene(re.origin, c * 1000.0, 1.0, 1.0, c)
	end

	if t > C.KAMI_SHOCKWAVE2_STARTTIME and t < C.KAMI_SHOCKWAVE2_ENDTIME then
		-- 2nd kamikaze shockwave
		if le.angles.trBase[0] == 0 and le.angles.trBase[1] == 0 and le.angles.trBase[2] == 0 then
			le.angles.trBase[0] = Q.random() * 360
			le.angles.trBase[1] = Q.random() * 360
			le.angles.trBase[2] = Q.random() * 360
		else
			c = 0
		end
		local shockwave = T.refEntity_t()
		shockwave.hModel = G.cgs.media.kamikazeShockWave
		shockwave.reType = C.RT_MODEL
		shockwave.shaderTime = re.shaderTime
		Q.VectorCopy(re.origin, shockwave.origin)

		test[0] = le.angles.trBase[0]
		test[1] = le.angles.trBase[1]
		test[2] = le.angles.trBase[2]
		Q.AnglesToAxis(test, axis)

		c = (t - C.KAMI_SHOCKWAVE2_STARTTIME) / (C.KAMI_SHOCKWAVE2_ENDTIME - C.KAMI_SHOCKWAVE2_STARTTIME)
		for i = 0, 2 do
			Q.VectorScale(axis[i], c * C.KAMI_SHOCKWAVE2_MAXRADIUS / C.KAMI_SHOCKWAVEMODEL_RADIUS, shockwave.axis[i])
		end
		shockwave.nonNormalizedAxes = true

		if t > C.KAMI_SHOCKWAVE2FADE_STARTTIME then
			c = (t - C.KAMI_SHOCKWAVE2FADE_STARTTIME) / (C.KAMI_SHOCKWAVE2_ENDTIME - C.KAMI_SHOCKWAVE2FADE_STARTTIME)
		else
			c = 0
		end
		c *= 0xff
		shockwave.shaderRGBA[0] = u8(0xff - c)
		shockwave.shaderRGBA[1] = u8(0xff - c)
		shockwave.shaderRGBA[2] = u8(0xff - c)
		shockwave.shaderRGBA[3] = u8(0xff - c)

		trap.R_AddRefEntityToScene(shockwave)
	end
end

function G.CG_AddInvulnerabilityImpact(le)
	trap.R_AddRefEntityToScene(le.refEntity)
end

function G.CG_AddInvulnerabilityJuiced(le)
	local t = G.cg.time - le.startTime
	if t > 3000 then
		le.refEntity.axis[0][0] = 1.0 + 0.3 * (t - 3000) / 2000
		le.refEntity.axis[1][1] = 1.0 + 0.3 * (t - 3000) / 2000
		le.refEntity.axis[2][2] = 0.7 + 0.3 * (2000 - (t - 3000)) / 2000
	end
	if t > 5000 then
		le.endTime = 0
		G.CG_GibPlayer(le.refEntity.origin)
	else
		trap.R_AddRefEntityToScene(le.refEntity)
	end
end

function G.CG_AddRefEntity(le)
	if le.endTime < G.cg.time then
		G.CG_FreeLocalEntity(le)
		return
	end
	trap.R_AddRefEntityToScene(le.refEntity)
end

function G.CG_AddScorePlum(le)
	local cg = G.cg
	local re = le.refEntity
	local origin = Q.vec3(0, 0, 0)
	local delta = Q.vec3(0, 0, 0)
	local dir = Q.vec3(0, 0, 0)
	local vec = Q.vec3(0, 0, 0)
	local up = Q.vec3(0, 0, 1)
	local digits = {}

	local c = (le.endTime - cg.time) * le.lifeRate

	local score = Q.int(le.radius)
	if score < 0 then
		re.shaderRGBA[0] = 0xff
		re.shaderRGBA[1] = 0x11
		re.shaderRGBA[2] = 0x11
	else
		re.shaderRGBA[0] = 0xff
		re.shaderRGBA[1] = 0xff
		re.shaderRGBA[2] = 0xff
		if score >= 50 then
			re.shaderRGBA[1] = 0
		elseif score >= 20 then
			re.shaderRGBA[0] = 0
			re.shaderRGBA[1] = 0
		elseif score >= 10 then
			re.shaderRGBA[2] = 0
		elseif score >= 2 then
			re.shaderRGBA[0] = 0
			re.shaderRGBA[2] = 0
		end
	end
	if c < 0.25 then
		re.shaderRGBA[3] = u8(0xff * 4 * c)
	else
		re.shaderRGBA[3] = 0xff
	end

	re.radius = NUMBER_SIZE / 2

	Q.VectorCopy(le.pos.trBase, origin)
	origin[2] += 110 - c * 100

	Q.VectorSubtract(cg.refdef.vieworg, origin, dir)
	Q.CrossProduct(dir, up, vec)
	Q.VectorNormalize(vec)

	Q.VectorMA(origin, -10 + 20 * math.sin(c * 2 * math.pi), vec, origin)

	-- if the view would be "inside" the sprite, kill the sprite
	-- so it doesn't add too much overdraw
	Q.VectorSubtract(origin, cg.refdef.vieworg, delta)
	local len = Q.VectorLength(delta)
	if len < 20 then
		G.CG_FreeLocalEntity(le)
		return
	end

	local negative = false
	if score < 0 then
		negative = true
		score = -score
	end

	local numdigits = 0
	while not (numdigits ~= 0 and score == 0) do
		digits[numdigits] = score % 10
		score = Q.idiv(score, 10)
		numdigits += 1
	end

	if negative then
		digits[numdigits] = 10
		numdigits += 1
	end

	for i = 0, numdigits - 1 do
		Q.VectorMA(origin, (numdigits / 2 - i) * NUMBER_SIZE, vec, re.origin)
		re.customShader = G.cgs.media.numberShaders[digits[numdigits - 1 - i]]
		trap.R_AddRefEntityToScene(re)
	end
end

--==============================================================================

function G.CG_AddLocalEntities()
	local cg = G.cg
	local active = G.cg_activeLocalEntities

	-- walk the list backwards, so any new local entities generated
	-- (trails, marks, etc) will be present this frame
	local le = active.prev
	while le ~= active do
		-- grab next now, so if the local entity is freed we
		-- still have it
		local nextLe = le.prev

		if cg.time >= le.endTime then
			G.CG_FreeLocalEntity(le)
		else
			local leType = le.leType
			if leType == C.LE_MARK then
				-- nothing
			elseif leType == C.LE_SPRITE_EXPLOSION then
				CG_AddSpriteExplosion(le)
			elseif leType == C.LE_EXPLOSION then
				CG_AddExplosion(le)
			elseif leType == C.LE_FRAGMENT then -- gibs and brass
				G.CG_AddFragment(le)
			elseif leType == C.LE_MOVE_SCALE_FADE then -- water bubbles
				CG_AddMoveScaleFade(le)
			elseif leType == C.LE_FADE_RGB then -- teleporters, railtrails
				G.CG_AddFadeRGB(le)
			elseif leType == C.LE_FALL_SCALE_FADE then -- gib blood trails
				CG_AddFallScaleFade(le)
			elseif leType == C.LE_SCALE_FADE then -- rocket trails
				CG_AddScaleFade(le)
			elseif leType == C.LE_SCOREPLUM then
				G.CG_AddScorePlum(le)
			elseif leType == C.LE_KAMIKAZE then
				G.CG_AddKamikaze(le)
			elseif leType == C.LE_INVULIMPACT then
				G.CG_AddInvulnerabilityImpact(le)
			elseif leType == C.LE_INVULJUICED then
				G.CG_AddInvulnerabilityJuiced(le)
			elseif leType == C.LE_SHOWREFENTITY then
				G.CG_AddRefEntity(le)
			elseif leType == C.LE_GORE then -- blood
				G.CG_AddGore(le)
			else
				G.CG_Error(Q.va("Bad leType: %i", leType))
			end
		end
		le = nextLe
	end
end

return G
