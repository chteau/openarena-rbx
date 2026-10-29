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
-- Luau port of code/cgame/cg_weapons.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- This part covers C lines 2643-3654 of the 0.8.8 source.

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)

-- Q_crandom( &seed ): the seed is advanced and returned alongside the value
local function Q_crandom(seed)
	seed = (69069 * (seed % 4294967296) + 1) % 4294967296
	local r = bit32.band(seed, 0xffff) / 65536
	return 2.0 * (r - 0.5), seed
end

function G.CG_FireWeapon(cent)
	if
		(G.cgs.gametype == C.GT_ELIMINATION or G.cgs.gametype == C.GT_CTF_ELIMINATION)
		and G.cgs.roundStartTime >= G.cg.time
	then
		return -- if we havn't started in ELIMINATION then do not fire
	end

	local ent = cent.currentState
	if ent.weapon == C.WP_NONE then
		return
	end
	if ent.weapon >= C.WP_NUM_WEAPONS then
		G.CG_Error("CG_FireWeapon: ent->weapon >= WP_NUM_WEAPONS")
		return
	end
	local weap = G.cg_weapons[ent.weapon]

	-- mark the entity as muzzle flashing, so when it is added it will
	-- append the flash to the weapon model
	cent.muzzleFlashTime = G.cg.time

	-- lightning gun only does this this on initial press
	if ent.weapon == C.WP_LIGHTNING then
		if cent.pe.lightningFiring then
			return
		end
	end

	-- play quad sound if needed
	if bit32.band(cent.currentState.powerups, bit32.lshift(1, C.PW_QUAD)) ~= 0 then
		trap.S_StartSound(nil, cent.currentState.number, C.CHAN_ITEM, G.cgs.media.quadSound)
	end

	-- play a sound
	local c = 0
	while c < 4 do
		if weap.flashSound[c] == 0 then
			break
		end
		c += 1
	end
	if c > 0 then
		c = Q.rand() % c
		if weap.flashSound[c] ~= 0 then
			trap.S_StartSound(nil, ent.number, C.CHAN_WEAPON, weap.flashSound[c])
		end
	end

	-- do brass ejection
	if weap.ejectBrassFunc ~= nil and G.cg_brassTime.integer > 0 then
		weap.ejectBrassFunc(cent)
	end

	G.CG_PredictWeaponEffects(cent)
end

local function leiFireball(origin, dir, lightColor)
	local sprOrg, sprVel = Q.vec3(), Q.vec3()
	-- some more fireball, fireball, fireball, fire fire!
	Q.VectorMA(origin, 24, dir, sprOrg)
	Q.VectorScale(dir, 64, sprVel)
	lightColor[0] = 0.7 -- subtler explosion colors
	lightColor[1] = 0.6
	lightColor[2] = 0.4
	Q.VectorMA(origin, 4, dir, sprOrg)
	Q.VectorScale(dir, 2, sprVel)
	Q.VectorMA(origin, 4, dir, sprOrg)
	Q.VectorScale(dir, 42, sprVel)
	G.CG_ParticleExplosion("explode1", sprOrg, sprVel, 700, 10, 108)
	Q.VectorMA(origin, 4, dir, sprOrg)
	Q.VectorScale(dir, 82, sprVel)
	G.CG_ParticleExplosion("explode1", sprOrg, sprVel, 400, 11, 158)
	Q.VectorMA(origin, -5, dir, sprOrg)
	Q.VectorScale(dir, 182, sprVel)
	G.CG_ParticleExplosion("explode1", sprOrg, sprVel, 600, 47, 88)
	Q.VectorMA(origin, -5, dir, sprOrg)
	Q.VectorScale(dir, 64, sprVel)
	G.CG_ParticleExplosion("explode1", sprOrg, sprVel, 110, 72, 28)
end

--[[
=================
CG_MissileHitWall

Caused by an EV_MISSILE_MISS event, or directly by local bullet tracing
=================
]]
function G.CG_MissileHitWall(weapon, clientNum, origin, dir, soundType)
	local media = G.cgs.media
	local mark = 0
	local radius = 32
	local sfx = 0
	local mod = 0
	local shader = 0
	local light = 0
	local lightColor = Q.vec3(1, 1, 0)

	-- set defaults
	local isSprite = false
	local duration = 600

	if weapon == C.WP_LIGHTNING then
		-- no explosion at LG impact, it is added with the beam
		local r = bit32.band(Q.rand(), 3)
		if r < 2 then
			sfx = media.sfx_lghit2
		elseif r == 2 then
			sfx = media.sfx_lghit1
		else
			sfx = media.sfx_lghit3
		end
		mark = media.holeMarkShader
		radius = 12
	elseif weapon == C.WP_PROX_LAUNCHER then
		mod = media.dishFlashModel
		shader = media.grenadeExplosionShader
		sfx = media.sfx_proxexp
		mark = media.burnMarkShader
		radius = 64
		light = 300
		isSprite = true
		if G.cg_leiEnhancement.integer ~= 0 then
			leiFireball(origin, dir, lightColor)
			mod = 0 -- turns off the sprite (unfortunately, disables dlight)
		end
	elseif weapon == C.WP_GRENADE_LAUNCHER then
		mod = media.dishFlashModel
		shader = media.grenadeExplosionShader
		sfx = media.sfx_rockexp
		mark = media.burnMarkShader
		radius = 64
		light = 300
		isSprite = true
		if G.cg_leiEnhancement.integer ~= 0 then
			leiFireball(origin, dir, lightColor)
			mod = 0
		end
	elseif weapon == C.WP_ROCKET_LAUNCHER then
		mod = media.dishFlashModel
		shader = media.rocketExplosionShader
		sfx = media.sfx_rockexp
		mark = media.burnMarkShader
		radius = 64
		light = 300
		isSprite = true
		duration = 1000
		lightColor[0] = 1
		lightColor[1] = 0.75
		lightColor[2] = 0.0
		if G.cg_oldRocket.integer == 0 then
			-- explosion sprite animation
			local sprOrg, sprVel = Q.vec3(), Q.vec3()
			Q.VectorMA(origin, 24, dir, sprOrg)
			Q.VectorScale(dir, 64, sprVel)

			G.CG_ParticleExplosion("explode1", sprOrg, sprVel, 1400, 20, 30)
		end
		if G.cg_leiEnhancement.integer ~= 0 then
			leiFireball(origin, dir, lightColor)
			mod = 0
		end
	elseif weapon == C.WP_RAILGUN then
		mod = media.ringFlashModel
		shader = media.railExplosionShader
		sfx = media.sfx_plasmaexp
		mark = media.energyMarkShader
		radius = 24
	elseif weapon == C.WP_PLASMAGUN then
		mod = media.ringFlashModel
		shader = media.plasmaExplosionShader
		sfx = media.sfx_plasmaexp
		mark = media.energyMarkShader
		radius = 16
	elseif weapon == C.WP_BFG then
		mod = media.dishFlashModel
		shader = media.bfgExplosionShader
		sfx = media.sfx_rockexp
		mark = media.burnMarkShader
		radius = 32
		isSprite = true
	elseif weapon == C.WP_SHOTGUN then
		mod = media.bulletFlashModel
		shader = media.bulletExplosionShader
		mark = media.bulletMarkShader
		sfx = 0
		radius = 4
	elseif weapon == C.WP_CHAINGUN then
		mod = media.bulletFlashModel
		if soundType == C.IMPACTSOUND_FLESH then
			sfx = media.sfx_chghitflesh
		elseif soundType == C.IMPACTSOUND_METAL then
			sfx = media.sfx_chghitmetal
		else
			sfx = media.sfx_chghit
		end

		mark = media.bulletMarkShader
		local r = bit32.band(Q.rand(), 3)
		if r < 2 then
			sfx = media.sfx_ric1
		elseif r == 2 then
			sfx = media.sfx_ric2
		else
			sfx = media.sfx_ric3
		end

		radius = 8
	elseif weapon == C.WP_MACHINEGUN then
		mod = media.bulletFlashModel
		shader = media.bulletExplosionShader
		mark = media.bulletMarkShader

		local r = bit32.band(Q.rand(), 3)
		if r == 0 then
			sfx = media.sfx_ric1
		elseif r == 1 then
			sfx = media.sfx_ric2
		else
			sfx = media.sfx_ric3
		end

		radius = 8
	else
		-- default and WP_NAILGUN
		if soundType == C.IMPACTSOUND_FLESH then
			sfx = media.sfx_nghitflesh
		elseif soundType == C.IMPACTSOUND_METAL then
			sfx = media.sfx_nghitmetal
		else
			sfx = media.sfx_nghit
		end
		mark = media.holeMarkShader
		radius = 12
	end

	if sfx ~= 0 then
		trap.S_StartSound(origin, C.ENTITYNUM_WORLD, C.CHAN_AUTO, sfx)
	end

	--
	-- create the explosion
	--
	if mod ~= 0 then
		local le = G.CG_MakeExplosion(origin, dir, mod, shader, duration, isSprite)
		le.light = light
		le.lightColor[0] = lightColor[0]
		le.lightColor[1] = lightColor[1]
		le.lightColor[2] = lightColor[2]
		if weapon == C.WP_RAILGUN then
			-- colorize with client color
			local c1 = G.cgs.clientinfo[clientNum].color1
			le.color[0] = c1[0]
			le.color[1] = c1[1]
			le.color[2] = c1[2]
			le.refEntity.shaderRGBA[0] = le.color[0] * 0xff
			le.refEntity.shaderRGBA[1] = le.color[1] * 0xff
			le.refEntity.shaderRGBA[2] = le.color[2] * 0xff
			le.refEntity.shaderRGBA[3] = 0xff
		end
	end

	--
	-- impact mark
	--
	local alphaFade = (mark == media.energyMarkShader) -- plasma fades alpha, all others fade color
	if weapon == C.WP_RAILGUN then
		-- colorize with client color
		local color = G.cgs.clientinfo[clientNum].color1
		G.CG_ImpactMark(mark, origin, dir, Q.random() * 360, color[0], color[1], color[2], 1, alphaFade, radius, false)
	else
		G.CG_ImpactMark(mark, origin, dir, Q.random() * 360, 1, 1, 1, 1, alphaFade, radius, false)
	end
end

function G.CG_MissileHitPlayer(weapon, origin, dir, entityNum)
	if G.cg_leiEnhancement.integer ~= 0 then
		G.CG_SmokePuff(origin, dir, 22, 1, 1, 1, 1.0, 900, G.cg.time, 0, 0, G.cgs.media.lbldShader1)
		G.CG_SpurtBlood(origin, dir, 1)
	else
		G.CG_Bleed(origin, entityNum)
	end

	-- some weapons will make an explosion with the blood, while
	-- others will just make the blood
	if
		weapon == C.WP_GRENADE_LAUNCHER
		or weapon == C.WP_ROCKET_LAUNCHER
		or weapon == C.WP_NAILGUN
		or weapon == C.WP_CHAINGUN
		or weapon == C.WP_PROX_LAUNCHER
	then
		G.CG_MissileHitWall(weapon, 0, origin, dir, C.IMPACTSOUND_FLESH)
	end
end

--[[
============================================================================

SHOTGUN TRACING

============================================================================
]]

local function waterSplash(trace)
	local kapow = Q.vec3()
	local media = G.cgs.media
	Q.VectorCopy(trace.plane.normal, kapow)

	kapow[0] = kapow[0] * (Q.crandom() * 22)
	kapow[1] = kapow[1] * (Q.crandom() * 22)
	kapow[2] = kapow[2] * (Q.crandom() * 65 + 37)
	G.CG_SmokePuff(trace.endpos, kapow, 14, 1, 1, 1, 1.0, 400, G.cg.time, 0, 0, media.lsplShader)
	G.CG_SmokePuff(trace.endpos, kapow, 6, 1, 1, 1, 1.0, 200, G.cg.time, 0, 0, media.lsplShader)
	G.CG_SmokePuff(trace.endpos, kapow, 10, 1, 1, 1, 1.0, 300, G.cg.time, 0, 0, media.lsplShader)
end

function G.CG_ShotgunPellet(start, finish, skipNum)
	local tr = T.trace_t()
	local kapow = Q.vec3()

	G.CG_Trace(tr, start, nil, nil, finish, skipNum, C.MASK_SHOT)

	local sourceContentType = G.CG_PointContents(start, 0)
	local destContentType = G.CG_PointContents(tr.endpos, 0)

	-- FIXME: should probably move this cruft into CG_BubbleTrail
	if sourceContentType == destContentType then
		if bit32.band(sourceContentType, C.CONTENTS_WATER) ~= 0 then
			G.CG_BubbleTrail(start, tr.endpos, 32)
		end
	elseif bit32.band(sourceContentType, C.CONTENTS_WATER) ~= 0 then
		local trace = T.trace_t()

		trap.CM_BoxTrace(trace, finish, start, nil, nil, 0, C.CONTENTS_WATER)
		G.CG_BubbleTrail(start, trace.endpos, 32)

		if G.cg_leiEnhancement.integer ~= 0 then
			waterSplash(trace)
		end
	elseif bit32.band(destContentType, C.CONTENTS_WATER) ~= 0 then
		local trace = T.trace_t()

		trap.CM_BoxTrace(trace, start, finish, nil, nil, 0, C.CONTENTS_WATER)
		G.CG_BubbleTrail(tr.endpos, trace.endpos, 32)

		if G.cg_leiEnhancement.integer ~= 0 then
			waterSplash(trace)
		end
	end

	if bit32.band(tr.surfaceFlags, C.SURF_NOIMPACT) ~= 0 then
		return
	end

	if G.cg_entities[tr.entityNum].currentState.eType == C.ET_PLAYER then
		G.CG_MissileHitPlayer(C.WP_SHOTGUN, tr.endpos, tr.plane.normal, tr.entityNum)
	else
		if bit32.band(tr.surfaceFlags, C.SURF_NOIMPACT) ~= 0 then
			-- SURF_NOIMPACT will not make a flame puff or a mark
			return
		end
		if bit32.band(tr.surfaceFlags, C.SURF_METALSTEPS) ~= 0 then
			G.CG_MissileHitWall(C.WP_SHOTGUN, 0, tr.endpos, tr.plane.normal, C.IMPACTSOUND_METAL)
			if G.cg_leiEnhancement.integer ~= 0 then
				Q.VectorCopy(tr.plane.normal, kapow)

				kapow[0] = kapow[0] * (Q.crandom() * 65 + 37)
				kapow[1] = kapow[1] * (Q.crandom() * 65 + 37)
				kapow[2] = kapow[2] * (Q.crandom() * 65 + 37)
				G.CG_LeiSparks(tr.endpos, tr.plane.normal, 800, 0, 0, 7)
				G.CG_LeiSparks(tr.endpos, tr.plane.normal, 800, 0, 0, 3)
				G.CG_LeiSparks(tr.endpos, tr.plane.normal, 800, 0, 0, 1)
			end
		else
			G.CG_MissileHitWall(C.WP_SHOTGUN, 0, tr.endpos, tr.plane.normal, C.IMPACTSOUND_DEFAULT)

			if G.cg_leiEnhancement.integer ~= 0 then
				Q.VectorCopy(tr.plane.normal, kapow)

				kapow[0] = kapow[0] * (Q.crandom() * 65 + 37)
				kapow[1] = kapow[1] * (Q.crandom() * 65 + 37)
				kapow[2] = kapow[2] * (Q.crandom() * 65 + 37)
				G.CG_LeiSparks(tr.endpos, tr.plane.normal, 800, 0, 0, 7)
				G.CG_LeiSparks(tr.endpos, tr.plane.normal, 800, 0, 0, 2)

				G.CG_SmokePuff(tr.endpos, kapow, 21, 1, 1, 1, 0.9, 1200, G.cg.time, 0, 0, G.cgs.media.lsmkShader2)
			end
		end
	end
end

--[[
================
CG_ShotgunPattern

Perform the same traces the server did to locate the
hit splashes
================
]]
function G.CG_ShotgunPattern(origin, origin2, seed, otherEntNum)
	local finish = Q.vec3()
	local forward, right, up = Q.vec3(), Q.vec3(), Q.vec3()

	-- derive the right and up vectors from the forward vector, because
	-- the client won't have any other information
	Q.VectorNormalize2(origin2, forward)
	Q.PerpendicularVector(right, forward)
	Q.CrossProduct(forward, right, up)

	-- generate the "random" spread pattern
	for _ = 0, C.DEFAULT_SHOTGUN_COUNT - 1 do
		local rv, uv
		rv, seed = Q_crandom(seed)
		uv, seed = Q_crandom(seed)
		local r = rv * C.DEFAULT_SHOTGUN_SPREAD * 16
		local u = uv * C.DEFAULT_SHOTGUN_SPREAD * 16
		Q.VectorMA(origin, 8192 * 16, forward, finish)
		Q.VectorMA(finish, r, right, finish)
		Q.VectorMA(finish, u, up, finish)

		G.CG_ShotgunPellet(origin, finish, otherEntNum)
	end
end

function G.CG_ShotgunFire(es)
	local v = Q.vec3()

	Q.VectorSubtract(es.origin2, es.pos.trBase, v)
	Q.VectorNormalize(v)
	Q.VectorScale(v, 32, v)
	Q.VectorAdd(es.pos.trBase, v, v)
	if G.cgs.glconfig.hardwareType ~= C.GLHW_RAGEPRO then
		-- ragepro can't alpha fade, so don't even bother with smoke
		local up = Q.vec3()
		local forward = Q.vec3()

		local contents = G.CG_PointContents(es.pos.trBase, 0)
		if bit32.band(contents, C.CONTENTS_WATER) == 0 then
			Q.VectorSet(up, 0, 0, 8)
			if G.cg_leiEnhancement.integer ~= 0 then
				-- Shotgun puffy
				for _ = 1, 6 do
					G.CG_LeiSparks(v, forward, 1500, 0, 0, 7)
				end
			else
				G.CG_SmokePuff(v, up, 32, 1, 1, 1, 0.33, 900, G.cg.time, 0, C.LEF_PUFF_DONT_SCALE, G.cgs.media.shotgunSmokePuffShader)
			end
		end
	end
	G.CG_ShotgunPattern(es.pos.trBase, es.origin2, es.eventParm, es.otherEntityNum)
end

--[[
============================================================================

BULLETS

============================================================================
]]

function G.CG_Tracer(source, dest)
	local forward, right = Q.vec3(), Q.vec3()
	local verts = {}
	for i = 0, 3 do
		verts[i] = T.polyVert_t()
	end
	local line = Q.vec3()
	local start, finish = Q.vec3(), Q.vec3()
	local midpoint = Q.vec3()
	local viewaxis = G.cg.refdef.viewaxis

	-- tracer
	Q.VectorSubtract(dest, source, forward)
	local len = Q.VectorNormalize(forward)

	-- start at least a little ways from the muzzle
	if len < 100 then
		return
	end
	local begin = 50 + Q.random() * (len - 60)
	local last = begin + G.cg_tracerLength.value
	if last > len then
		last = len
	end
	Q.VectorMA(source, begin, forward, start)
	Q.VectorMA(source, last, forward, finish)

	line[0] = Q.DotProduct(forward, viewaxis[1])
	line[1] = Q.DotProduct(forward, viewaxis[2])

	Q.VectorScale(viewaxis[1], line[1], right)
	Q.VectorMA(right, -line[0], viewaxis[2], right)
	Q.VectorNormalize(right)

	local w = G.cg_tracerWidth.value

	local function setVert(v, s, t)
		v.st[0] = s
		v.st[1] = t
		v.modulate[0] = 255
		v.modulate[1] = 255
		v.modulate[2] = 255
		v.modulate[3] = 255
	end

	Q.VectorMA(finish, w, right, verts[0].xyz)
	setVert(verts[0], 0, 1)

	Q.VectorMA(finish, -w, right, verts[1].xyz)
	setVert(verts[1], 1, 0)

	Q.VectorMA(start, -w, right, verts[2].xyz)
	setVert(verts[2], 1, 1)

	Q.VectorMA(start, w, right, verts[3].xyz)
	setVert(verts[3], 0, 0)

	trap.R_AddPolyToScene(G.cgs.media.tracerShader, 4, verts)

	midpoint[0] = (start[0] + finish[0]) * 0.5
	midpoint[1] = (start[1] + finish[1]) * 0.5
	midpoint[2] = (start[2] + finish[2]) * 0.5

	-- add the tracer sound
	trap.S_StartSound(midpoint, C.ENTITYNUM_WORLD, C.CHAN_AUTO, G.cgs.media.tracerSound)
end

function G.CG_CalcMuzzlePoint(entityNum, muzzle)
	local forward = Q.vec3()
	local snapPs = G.cg.snap.ps

	if entityNum == snapPs.clientNum then
		Q.VectorCopy(snapPs.origin, muzzle)
		muzzle[2] += snapPs.viewheight
		Q.AngleVectors(snapPs.viewangles, forward, nil, nil)
		Q.VectorMA(muzzle, 14, forward, muzzle)
		return true
	end

	local cent = G.cg_entities[entityNum]
	if not cent.currentValid then
		return false
	end

	Q.VectorCopy(cent.currentState.pos.trBase, muzzle)

	Q.AngleVectors(cent.currentState.apos.trBase, forward, nil, nil)
	local anim = bit32.band(cent.currentState.legsAnim, bit32.bnot(C.ANIM_TOGGLEBIT))
	if anim == C.LEGS_WALKCR or anim == C.LEGS_IDLECR then
		muzzle[2] += C.CROUCH_VIEWHEIGHT
	else
		muzzle[2] += C.DEFAULT_VIEWHEIGHT
	end

	Q.VectorMA(muzzle, 14, forward, muzzle)

	return true
end

--[[
======================
CG_Bullet

Renders bullet effects.
======================
]]
function G.CG_Bullet(finish, sourceEntityNum, normal, flesh, fleshEntityNum)
	local trace = T.trace_t()
	local start = Q.vec3()
	local kapew = Q.vec3()
	local kapow = Q.vec3()

	-- if the shooter is currently valid, calc a source point and possibly
	-- do trail effects
	if sourceEntityNum >= 0 and G.cg_tracerChance.value > 0 then
		if G.CG_CalcMuzzlePoint(sourceEntityNum, start) then
			local sourceContentType = G.CG_PointContents(start, 0)
			local destContentType = G.CG_PointContents(finish, 0)

			-- do a complete bubble trail if necessary
			if sourceContentType == destContentType and bit32.band(sourceContentType, C.CONTENTS_WATER) ~= 0 then
				G.CG_BubbleTrail(start, finish, 32)
			-- bubble trail from water into air
			elseif bit32.band(sourceContentType, C.CONTENTS_WATER) ~= 0 then
				trap.CM_BoxTrace(trace, finish, start, nil, nil, 0, C.CONTENTS_WATER)
				G.CG_BubbleTrail(start, trace.endpos, 32)

				if G.cg_leiEnhancement.integer ~= 0 then
					waterSplash(trace)
				end
			-- bubble trail from air into water
			elseif bit32.band(destContentType, C.CONTENTS_WATER) ~= 0 then
				trap.CM_BoxTrace(trace, start, finish, nil, nil, 0, C.CONTENTS_WATER)
				G.CG_BubbleTrail(trace.endpos, finish, 32)

				if G.cg_leiEnhancement.integer ~= 0 then
					waterSplash(trace)
				end
			end

			-- draw a tracer
			if Q.random() < G.cg_tracerChance.value then
				G.CG_Tracer(start, finish)
			end
		end
	end

	-- impact splash and mark
	if flesh then
		if G.cg_leiEnhancement.integer ~= 0 then
			-- Blood Hack
			Q.VectorCopy(normal, kapow)

			kapow[0] = kapow[0] * (Q.crandom() * 65 + 37)
			kapow[1] = kapow[1] * (Q.crandom() * 65 + 37)
			kapow[2] = kapow[2] * (Q.crandom() * 65 + 37)
			Q.VectorCopy(kapow, kapew)

			kapew[0] = kapew[0] * (Q.crandom() * 2 + 37)
			kapew[1] = kapew[1] * (Q.crandom() * 2 + 37)
			kapew[2] = kapew[2] * (Q.crandom() * 2 + 37)

			G.CG_SmokePuff(finish, kapow, 6, 1, 1, 1, 1.0, 600, G.cg.time, 0, 0, G.cgs.media.lbldShader1)
			G.CG_SpurtBlood(finish, kapew, 1)

			if G.cg_leiSuperGoreyAwesome.integer ~= 0 then
				G.CG_SpurtBlood(finish, kapow, -2)
			end
		else
			G.CG_Bleed(finish, fleshEntityNum)
		end
	else
		G.CG_MissileHitWall(C.WP_MACHINEGUN, 0, finish, normal, C.IMPACTSOUND_DEFAULT)

		if G.cg_leiEnhancement.integer ~= 0 then
			-- Smoke puff
			Q.VectorCopy(normal, kapow)

			kapow[0] = kapow[0] * (Q.crandom() * 65 + 37)
			kapow[1] = kapow[1] * (Q.crandom() * 65 + 37)
			kapow[2] = kapow[2] * (Q.crandom() * 65 + 37)
			Q.VectorCopy(kapow, kapew)

			kapew[0] = kapew[0] * (Q.crandom() * 65 + 37)
			kapew[1] = kapew[1] * (Q.crandom() * 65 + 37)
			kapew[2] = kapew[2] * (Q.crandom() * 65 + 37)

			G.CG_SmokePuff(finish, kapow, 14, 1, 1, 1, 1.0, 600, G.cg.time, 0, 0, G.cgs.media.lsmkShader1)
		end
	end
end

return G
