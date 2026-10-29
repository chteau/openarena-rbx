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
-- Luau port of code/cgame/cg_ents.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- cg_ents.c -- present snapshot entities, happens every single frame

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

local function newMatrix()
	return { [0] = Q.vec3(0, 0, 0), [1] = Q.vec3(0, 0, 0), [2] = Q.vec3(0, 0, 0) }
end

--[[
======================
CG_PositionEntityOnTag

Modifies the entities position and axis by the given
tag location
======================
]]
function G.CG_PositionEntityOnTag(entity, parent, parentModel, tagName)
	local lerped = T.orientation_t()

	-- lerp the tag
	trap.R_LerpTag(lerped, parentModel, parent.oldframe, parent.frame, 1.0 - parent.backlerp, tagName)

	-- FIXME: allow origin offsets along tag?
	Q.VectorCopy(parent.origin, entity.origin)
	for i = 0, 2 do
		Q.VectorMA(entity.origin, lerped.origin[i], parent.axis[i], entity.origin)
	end

	Q.MatrixMultiply(lerped.axis, parent.axis, entity.axis)
	entity.backlerp = parent.backlerp
end

--[[
======================
CG_PositionRotatedEntityOnTag

Modifies the entities position and axis by the given
tag location
======================
]]
function G.CG_PositionRotatedEntityOnTag(entity, parent, parentModel, tagName)
	local lerped = T.orientation_t()
	local tempAxis = newMatrix()

	trap.R_LerpTag(lerped, parentModel, parent.oldframe, parent.frame, 1.0 - parent.backlerp, tagName)

	-- FIXME: allow origin offsets along tag?
	Q.VectorCopy(parent.origin, entity.origin)
	for i = 0, 2 do
		Q.VectorMA(entity.origin, lerped.origin[i], parent.axis[i], entity.origin)
	end

	Q.MatrixMultiply(entity.axis, lerped.axis, tempAxis)
	Q.MatrixMultiply(tempAxis, parent.axis, entity.axis)
end

--[[
======================
CG_SetEntitySoundPosition

Also called by event processing code
======================
]]
function G.CG_SetEntitySoundPosition(cent)
	if cent.currentState.solid == C.SOLID_BMODEL then
		local origin = Q.vec3(0, 0, 0)
		local v = G.cgs.inlineModelMidpoints[cent.currentState.modelindex]
		Q.VectorAdd(cent.lerpOrigin, v, origin)
		trap.S_UpdateEntityPosition(cent.currentState.number, origin)
	else
		trap.S_UpdateEntityPosition(cent.currentState.number, cent.lerpOrigin)
	end
end

--[[
==================
CG_EntityEffects

Add continuous entity effects, like local entity emission and lighting
==================
]]
local function CG_EntityEffects(cent)
	-- update sound origins
	G.CG_SetEntitySoundPosition(cent)

	-- add loop sound
	if cent.currentState.loopSound ~= 0 then
		if cent.currentState.eType ~= C.ET_SPEAKER then
			trap.S_AddLoopingSound(cent.currentState.number, cent.lerpOrigin, Q.vec3_origin,
				G.cgs.gameSounds[cent.currentState.loopSound])
		else
			trap.S_AddRealLoopingSound(cent.currentState.number, cent.lerpOrigin, Q.vec3_origin,
				G.cgs.gameSounds[cent.currentState.loopSound])
		end
	end

	-- constant light glow
	if cent.currentState.constantLight ~= 0 then
		local cl = cent.currentState.constantLight
		local r = bit32.band(cl, 0xFF) / 255.0
		local g = bit32.band(bit32.rshift(cl, 8), 0xFF) / 255.0
		local b = bit32.band(bit32.rshift(cl, 16), 0xFF) / 255.0
		local i = bit32.band(bit32.rshift(cl, 24), 0xFF) * 4.0
		trap.R_AddLightToScene(cent.lerpOrigin, i, r, g, b)
	end
end

local function CG_General(cent)
	local s1 = cent.currentState

	-- if set to invisible, skip
	if s1.modelindex == 0 then
		return
	end

	local ent = T.refEntity_t()

	ent.frame = s1.frame
	ent.oldframe = ent.frame
	ent.backlerp = 0

	Q.VectorCopy(cent.lerpOrigin, ent.origin)
	Q.VectorCopy(cent.lerpOrigin, ent.oldorigin)

	ent.hModel = G.cgs.gameModels[s1.modelindex]

	-- player model
	if s1.number == G.cg.snap.ps.clientNum then
		ent.renderfx = bit32.bor(ent.renderfx, C.RF_THIRD_PERSON) -- only draw from mirrors
	end

	-- convert angles to axis
	Q.AnglesToAxis(cent.lerpAngles, ent.axis)

	-- add to refresh list
	trap.R_AddRefEntityToScene(ent)
end

--[[
==================
CG_Speaker

Speaker entities can automatically play sounds
==================
]]
local function CG_Speaker(cent)
	if cent.currentState.clientNum == 0 then -- FIXME: use something other than clientNum...
		return -- not auto triggering
	end

	if G.cg.time < cent.miscTime then
		return
	end

	trap.S_StartSound(nil, cent.currentState.number, C.CHAN_ITEM, G.cgs.gameSounds[cent.currentState.eventParm])

	cent.miscTime = G.cg.time + cent.currentState.frame * 100 + cent.currentState.clientNum * 100 * Q.crandom()
end

local function CG_Item(cent)
	local cg = G.cg
	local cgs = G.cgs
	local es = cent.currentState
	if es.modelindex >= BG.bg_numItems then
		G.CG_Error(Q.va("Bad item index %i on entity", es.modelindex))
	end

	-- if set to invisible, skip
	if es.modelindex == 0 or bit32.band(es.eFlags, C.EF_NODRAW) ~= 0 then
		return
	end

	local item = BG.bg_itemlist[es.modelindex]
	local ent
	if G.cg_simpleItems.integer ~= 0 and item.giType ~= C.IT_TEAM then
		ent = T.refEntity_t()
		ent.reType = C.RT_SPRITE
		Q.VectorCopy(cent.lerpOrigin, ent.origin)
		ent.radius = 14
		ent.customShader = G.cg_items[es.modelindex].icon
		ent.shaderRGBA[0] = 255
		ent.shaderRGBA[1] = 255
		ent.shaderRGBA[2] = 255
		ent.shaderRGBA[3] = 255
		trap.R_AddRefEntityToScene(ent)
		return
	end

	-- items bob up and down continuously
	local scale = 0.005 + cent.currentState.number * 0.00001
	cent.lerpOrigin[2] = cent.lerpOrigin[2] + 4 + math.cos((cg.time + 1000) * scale) * 4

	ent = T.refEntity_t()

	-- autorotate at one of two speeds
	if item.giType == C.IT_HEALTH then
		Q.VectorCopy(cg.autoAnglesFast, cent.lerpAngles)
		Q.AxisCopy(cg.autoAxisFast, ent.axis)
	else
		Q.VectorCopy(cg.autoAngles, cent.lerpAngles)
		Q.AxisCopy(cg.autoAxis, ent.axis)
	end

	local wi = nil
	-- the weapons have their origin where they attatch to player
	-- models, so we need to offset them or they will rotate
	-- eccentricly
	if item.giType == C.IT_WEAPON then
		wi = G.cg_weapons[item.giTag]
		cent.lerpOrigin[0] = cent.lerpOrigin[0] -
			(wi.weaponMidpoint[0] * ent.axis[0][0] +
			wi.weaponMidpoint[1] * ent.axis[1][0] +
			wi.weaponMidpoint[2] * ent.axis[2][0])
		cent.lerpOrigin[1] = cent.lerpOrigin[1] -
			(wi.weaponMidpoint[0] * ent.axis[0][1] +
			wi.weaponMidpoint[1] * ent.axis[1][1] +
			wi.weaponMidpoint[2] * ent.axis[2][1])
		cent.lerpOrigin[2] = cent.lerpOrigin[2] -
			(wi.weaponMidpoint[0] * ent.axis[0][2] +
			wi.weaponMidpoint[1] * ent.axis[1][2] +
			wi.weaponMidpoint[2] * ent.axis[2][2])

		cent.lerpOrigin[2] = cent.lerpOrigin[2] + 8 -- an extra height boost
	end

	ent.hModel = G.cg_items[es.modelindex].models[0]

	Q.VectorCopy(cent.lerpOrigin, ent.origin)
	Q.VectorCopy(cent.lerpOrigin, ent.oldorigin)

	ent.nonNormalizedAxes = false

	-- if just respawned, slowly scale up
	local msec = cg.time - cent.miscTime
	local frac
	if msec >= 0 and msec < C.ITEM_SCALEUP_TIME then
		frac = msec / C.ITEM_SCALEUP_TIME
		Q.VectorScale(ent.axis[0], frac, ent.axis[0])
		Q.VectorScale(ent.axis[1], frac, ent.axis[1])
		Q.VectorScale(ent.axis[2], frac, ent.axis[2])
		ent.nonNormalizedAxes = true
	else
		frac = 1.0
	end

	-- items without glow textures need to keep a minimum light value
	-- so they are always visible
	if item.giType == C.IT_WEAPON or item.giType == C.IT_ARMOR then
		ent.renderfx = bit32.bor(ent.renderfx, C.RF_MINLIGHT)
	end

	-- increase the size of the weapons when they are presented as items
	if item.giType == C.IT_WEAPON then
		Q.VectorScale(ent.axis[0], 1.5, ent.axis[0])
		Q.VectorScale(ent.axis[1], 1.5, ent.axis[1])
		Q.VectorScale(ent.axis[2], 1.5, ent.axis[2])
		ent.nonNormalizedAxes = true
		trap.S_AddLoopingSound(cent.currentState.number, cent.lerpOrigin, Q.vec3_origin, cgs.media.weaponHoverSound)
	end

	if item.giType == C.IT_HOLDABLE and item.giTag == C.HI_KAMIKAZE then
		Q.VectorScale(ent.axis[0], 2, ent.axis[0])
		Q.VectorScale(ent.axis[1], 2, ent.axis[1])
		Q.VectorScale(ent.axis[2], 2, ent.axis[2])
		ent.nonNormalizedAxes = true
	end

	-- add to refresh list
	trap.R_AddRefEntityToScene(ent)

	if item.giType == C.IT_WEAPON and wi.barrelModel ~= 0 then
		local barrel = T.refEntity_t()

		barrel.hModel = wi.barrelModel

		Q.VectorCopy(ent.lightingOrigin, barrel.lightingOrigin)
		barrel.shadowPlane = ent.shadowPlane
		barrel.renderfx = ent.renderfx

		G.CG_PositionRotatedEntityOnTag(barrel, ent, wi.weaponModel, "tag_barrel")

		Q.AxisCopy(ent.axis, barrel.axis)
		barrel.nonNormalizedAxes = ent.nonNormalizedAxes

		trap.R_AddRefEntityToScene(barrel)
	end

	-- accompanying rings / spheres for powerups
	if G.cg_simpleItems.integer == 0 then
		local spinAngles = Q.vec3(0, 0, 0)

		if item.giType == C.IT_HEALTH or item.giType == C.IT_POWERUP then
			ent.hModel = G.cg_items[es.modelindex].models[1]
			if ent.hModel ~= 0 then
				if item.giType == C.IT_POWERUP then
					ent.origin[2] = ent.origin[2] + 12
					spinAngles[1] = bit32.band(cg.time, 1023) * 360 / -1024.0
				end
				Q.AnglesToAxis(spinAngles, ent.axis)

				-- scale up if respawning
				if frac ~= 1.0 then
					Q.VectorScale(ent.axis[0], frac, ent.axis[0])
					Q.VectorScale(ent.axis[1], frac, ent.axis[1])
					Q.VectorScale(ent.axis[2], frac, ent.axis[2])
					ent.nonNormalizedAxes = true
				end
				trap.R_AddRefEntityToScene(ent)
			end
		end
	end
end

--============================================================================

local function CG_Missile(cent)
	local cg = G.cg
	local s1 = cent.currentState
	if s1.weapon >= C.WP_NUM_WEAPONS then
		s1.weapon = 0
	end
	local weapon = G.cg_weapons[s1.weapon]

	-- calculate the axis
	Q.VectorCopy(s1.angles, cent.lerpAngles)

	-- add trails
	if weapon.missileTrailFunc ~= nil then
		weapon.missileTrailFunc(cent, weapon)
	end

	-- add dynamic light
	if weapon.missileDlight ~= 0 then
		trap.R_AddLightToScene(cent.lerpOrigin, weapon.missileDlight,
			weapon.missileDlightColor[0], weapon.missileDlightColor[1], weapon.missileDlightColor[2])
	end

	-- add missile sound
	if weapon.missileSound ~= 0 then
		local velocity = Q.vec3(0, 0, 0)

		BG.BG_EvaluateTrajectoryDelta(cent.currentState.pos, cg.time, velocity)

		trap.S_AddLoopingSound(cent.currentState.number, cent.lerpOrigin, velocity, weapon.missileSound)
	end

	-- create the render entity
	local ent = T.refEntity_t()
	Q.VectorCopy(cent.lerpOrigin, ent.origin)
	Q.VectorCopy(cent.lerpOrigin, ent.oldorigin)

	if cent.currentState.weapon == C.WP_PLASMAGUN then
		ent.reType = C.RT_SPRITE
		ent.radius = 16
		ent.rotation = 0
		ent.customShader = G.cgs.media.plasmaBallShader
		trap.R_AddRefEntityToScene(ent)
		return
	end

	-- flicker between two skins
	ent.skinNum = bit32.band(cg.clientFrame, 1)
	ent.hModel = weapon.missileModel
	ent.renderfx = bit32.bor(weapon.missileRenderfx, C.RF_NOSHADOW)

	if cent.currentState.weapon == C.WP_PROX_LAUNCHER then
		if s1.generic1 == C.TEAM_BLUE then
			ent.hModel = G.cgs.media.blueProxMine
		end
	end

	-- convert direction of travel into axis
	if Q.VectorNormalize2(s1.pos.trDelta, ent.axis[0]) == 0 then
		ent.axis[0][2] = 1
	end

	-- spin as it moves
	if s1.pos.trType ~= C.TR_STATIONARY then
		Q.RotateAroundDirection(ent.axis, Q.idiv(cg.time, 4))
	else
		if s1.weapon == C.WP_PROX_LAUNCHER then
			Q.AnglesToAxis(cent.lerpAngles, ent.axis)
		else
			Q.RotateAroundDirection(ent.axis, s1.time)
		end
	end

	-- add to refresh list, possibly with quad glow
	G.CG_AddRefEntityWithPowerups(ent, s1, C.TEAM_FREE, true)
end

--[[
===============
CG_Grapple

This is called when the grapple is sitting up against the wall
===============
]]
local function CG_Grapple(cent)
	local s1 = cent.currentState
	if s1.weapon >= C.WP_NUM_WEAPONS then
		s1.weapon = 0
	end
	local weapon = G.cg_weapons[s1.weapon]

	-- calculate the axis
	Q.VectorCopy(s1.angles, cent.lerpAngles)

	-- FIXME add grapple pull sound here..?
	-- add missile sound
	if weapon.missileSound ~= 0 then
		trap.S_AddLoopingSound(cent.currentState.number, cent.lerpOrigin, Q.vec3_origin, weapon.missileSound)
	end

	-- Will draw cable if needed
	G.CG_GrappleTrail(cent, weapon)

	-- create the render entity
	local ent = T.refEntity_t()
	Q.VectorCopy(cent.lerpOrigin, ent.origin)
	Q.VectorCopy(cent.lerpOrigin, ent.oldorigin)

	-- flicker between two skins
	ent.skinNum = bit32.band(G.cg.clientFrame, 1)
	ent.hModel = weapon.missileModel
	ent.renderfx = bit32.bor(weapon.missileRenderfx, C.RF_NOSHADOW)

	-- convert direction of travel into axis
	if Q.VectorNormalize2(s1.pos.trDelta, ent.axis[0]) == 0 then
		ent.axis[0][2] = 1
	end

	trap.R_AddRefEntityToScene(ent)
end

local function CG_Mover(cent)
	local s1 = cent.currentState

	-- create the render entity
	local ent = T.refEntity_t()
	Q.VectorCopy(cent.lerpOrigin, ent.origin)
	Q.VectorCopy(cent.lerpOrigin, ent.oldorigin)
	Q.AnglesToAxis(cent.lerpAngles, ent.axis)

	ent.renderfx = C.RF_NOSHADOW

	-- flicker between two skins (FIXME?)
	ent.skinNum = bit32.band(bit32.arshift(G.cg.time, 6), 1)

	-- get the model, either as a bmodel or a modelindex
	if s1.solid == C.SOLID_BMODEL then
		ent.hModel = G.cgs.inlineDrawModel[s1.modelindex]
	else
		ent.hModel = G.cgs.gameModels[s1.modelindex]
	end

	-- add to refresh list
	trap.R_AddRefEntityToScene(ent)

	-- add the secondary model
	if s1.modelindex2 ~= 0 then
		ent.skinNum = 0
		ent.hModel = G.cgs.gameModels[s1.modelindex2]
		trap.R_AddRefEntityToScene(ent)
	end
end

--[[
===============
CG_Beam

Also called as an event
===============
]]
function G.CG_Beam(cent)
	local s1 = cent.currentState

	-- create the render entity
	local ent = T.refEntity_t()
	Q.VectorCopy(s1.pos.trBase, ent.origin)
	Q.VectorCopy(s1.origin2, ent.oldorigin)
	Q.AxisClear(ent.axis)
	ent.reType = C.RT_BEAM

	ent.renderfx = C.RF_NOSHADOW

	-- add to refresh list
	trap.R_AddRefEntityToScene(ent)
end

local function CG_Portal(cent)
	local s1 = cent.currentState

	-- create the render entity
	local ent = T.refEntity_t()
	Q.VectorCopy(cent.lerpOrigin, ent.origin)
	Q.VectorCopy(s1.origin2, ent.oldorigin)
	Q.ByteToDir(s1.eventParm, ent.axis[0])
	Q.PerpendicularVector(ent.axis[1], ent.axis[0])

	-- negating this tends to get the directions like they want
	-- we really should have a camera roll value
	Q.VectorSubtract(Q.vec3_origin, ent.axis[1], ent.axis[1])

	Q.CrossProduct(ent.axis[0], ent.axis[1], ent.axis[2])
	ent.reType = C.RT_PORTALSURFACE
	ent.oldframe = s1.powerups
	ent.frame = s1.frame -- rotation speed
	ent.skinNum = Q.int(s1.clientNum / 256.0 * 360) -- roll offset

	-- add to refresh list
	trap.R_AddRefEntityToScene(ent)
end

--[[
=========================
CG_AdjustPositionForMover

Also called by client movement prediction code
=========================
]]
function G.CG_AdjustPositionForMover(i_n, moverNum, fromTime, toTime, out, angles_in, angles_out)
	local oldOrigin = Q.vec3(0, 0, 0)
	local origin = Q.vec3(0, 0, 0)
	local deltaOrigin = Q.vec3(0, 0, 0)
	local oldAngles = Q.vec3(0, 0, 0)
	local angles = Q.vec3(0, 0, 0)
	local deltaAngles = Q.vec3(0, 0, 0)

	if moverNum <= 0 or moverNum >= C.ENTITYNUM_MAX_NORMAL then
		Q.VectorCopy(i_n, out)
		Q.VectorCopy(angles_in, angles_out)
		return
	end

	local cent = G.cg_entities[moverNum]
	if cent.currentState.eType ~= C.ET_MOVER then
		Q.VectorCopy(i_n, out)
		Q.VectorCopy(angles_in, angles_out)
		return
	end

	BG.BG_EvaluateTrajectory(cent.currentState.pos, fromTime, oldOrigin)
	BG.BG_EvaluateTrajectory(cent.currentState.apos, fromTime, oldAngles)

	BG.BG_EvaluateTrajectory(cent.currentState.pos, toTime, origin)
	BG.BG_EvaluateTrajectory(cent.currentState.apos, toTime, angles)

	Q.VectorSubtract(origin, oldOrigin, deltaOrigin)
	Q.VectorSubtract(angles, oldAngles, deltaAngles)

	Q.VectorAdd(i_n, deltaOrigin, out)
	Q.VectorAdd(angles_in, deltaAngles, angles_out)

	-- FIXME: origin change when on a rotating object
end

local function CG_InterpolateEntityPosition(cent)
	local cg = G.cg
	local current = Q.vec3(0, 0, 0)
	local nxt = Q.vec3(0, 0, 0)

	-- it would be an internal error to find an entity that interpolates without
	-- a snapshot ahead of the current one
	if cg.nextSnap == nil then
		G.CG_Error("CG_InterpoateEntityPosition: cg.nextSnap == NULL")
	end

	local f = cg.frameInterpolation

	-- this will linearize a sine or parabolic curve, but it is important
	-- to not extrapolate player positions if more recent data is available
	BG.BG_EvaluateTrajectory(cent.currentState.pos, cg.snap.serverTime, current)
	BG.BG_EvaluateTrajectory(cent.nextState.pos, cg.nextSnap.serverTime, nxt)

	cent.lerpOrigin[0] = current[0] + f * (nxt[0] - current[0])
	cent.lerpOrigin[1] = current[1] + f * (nxt[1] - current[1])
	cent.lerpOrigin[2] = current[2] + f * (nxt[2] - current[2])

	BG.BG_EvaluateTrajectory(cent.currentState.apos, cg.snap.serverTime, current)
	BG.BG_EvaluateTrajectory(cent.nextState.apos, cg.nextSnap.serverTime, nxt)

	cent.lerpAngles[0] = Q.LerpAngle(current[0], nxt[0], f)
	cent.lerpAngles[1] = Q.LerpAngle(current[1], nxt[1], f)
	cent.lerpAngles[2] = Q.LerpAngle(current[2], nxt[2], f)
end

local function CG_CalcEntityLerpPositions(cent)
	local cg = G.cg
	--unlagged - projectile nudge
	-- this will be set to how far forward projectiles will be extrapolated
	local timeshift = 0

	if cent.interpolate and cent.currentState.pos.trType == C.TR_INTERPOLATE then
		CG_InterpolateEntityPosition(cent)
		return
	end

	-- first see if we can interpolate between two snaps for
	-- linear extrapolated clients
	if cent.interpolate and cent.currentState.pos.trType == C.TR_LINEAR_STOP
		and cent.currentState.number < C.MAX_CLIENTS then
		CG_InterpolateEntityPosition(cent)
		return
	end

	--unlagged - timenudge extrapolation
	-- interpolating failed (probably no nextSnap), so extrapolate
	-- this can also happen if the teleport bit is flipped, but that
	-- won't be noticeable
	if cent.currentState.number < C.MAX_CLIENTS
		and cent.currentState.clientNum ~= cg.predictedPlayerState.clientNum then
		cent.currentState.pos.trType = C.TR_LINEAR_STOP
		cent.currentState.pos.trTime = cg.snap.serverTime
		cent.currentState.pos.trDuration = Q.idiv(1000, G.sv_fps.integer)
	end

	--unlagged - projectile nudge
	-- if it's a missile but not a grappling hook
	if cent.currentState.eType == C.ET_MISSILE and cent.currentState.weapon ~= C.WP_GRAPPLING_HOOK then
		-- if it's one of ours
		if cent.currentState.otherEntityNum == cg.clientNum then
			-- extrapolate one server frame's worth - this will correct for tiny
			-- visual inconsistencies introduced by backward-reconciling all players
			-- one server frame before running projectiles
			timeshift = Q.idiv(1000, G.sv_fps.integer)
		-- if it's not, and it's not a grenade launcher
		elseif cent.currentState.weapon ~= C.WP_GRENADE_LAUNCHER then
			-- extrapolate based on cg_projectileNudge
			timeshift = G.cg_projectileNudge.integer + Q.idiv(1000, G.sv_fps.integer)
		end
	end

	-- just use the current frame and evaluate as best we can
	BG.BG_EvaluateTrajectory(cent.currentState.pos, cg.time + timeshift, cent.lerpOrigin)
	BG.BG_EvaluateTrajectory(cent.currentState.apos, cg.time + timeshift, cent.lerpAngles)

	-- if there's a time shift
	if timeshift ~= 0 then
		local tr = T.trace_t()
		local lastOrigin = Q.vec3(0, 0, 0)

		BG.BG_EvaluateTrajectory(cent.currentState.pos, cg.time, lastOrigin)

		G.CG_Trace(tr, lastOrigin, Q.vec3_origin, Q.vec3_origin, cent.lerpOrigin, cent.currentState.number, C.MASK_SHOT)

		-- don't let the projectile go through the floor
		if tr.fraction < 1.0 then
			cent.lerpOrigin[0] = lastOrigin[0] + tr.fraction * (cent.lerpOrigin[0] - lastOrigin[0])
			cent.lerpOrigin[1] = lastOrigin[1] + tr.fraction * (cent.lerpOrigin[1] - lastOrigin[1])
			cent.lerpOrigin[2] = lastOrigin[2] + tr.fraction * (cent.lerpOrigin[2] - lastOrigin[2])
		end
	end

	-- adjust for riding a mover if it wasn't rolled into the predicted
	-- player state
	if cent ~= cg.predictedPlayerEntity then
		G.CG_AdjustPositionForMover(cent.lerpOrigin, cent.currentState.groundEntityNum,
			cg.snap.serverTime, cg.time, cent.lerpOrigin, cent.lerpAngles, cent.lerpAngles)
	end
end

local function CG_TeamBase(cent)
	local cg = G.cg
	local cgs = G.cgs
	local model
	local c

	if cgs.gametype == C.GT_CTF or cgs.gametype == C.GT_1FCTF then
		-- show the flag base
		model = T.refEntity_t()
		model.reType = C.RT_MODEL
		Q.VectorCopy(cent.lerpOrigin, model.lightingOrigin)
		Q.VectorCopy(cent.lerpOrigin, model.origin)
		Q.AnglesToAxis(cent.currentState.angles, model.axis)
		if cent.currentState.modelindex == C.TEAM_RED then
			model.hModel = cgs.media.redFlagBaseModel
		elseif cent.currentState.modelindex == C.TEAM_BLUE then
			model.hModel = cgs.media.blueFlagBaseModel
		else
			model.hModel = cgs.media.neutralFlagBaseModel
		end
		trap.R_AddRefEntityToScene(model)
	elseif cgs.gametype == C.GT_OBELISK then
		-- show the obelisk
		model = T.refEntity_t()
		model.reType = C.RT_MODEL
		Q.VectorCopy(cent.lerpOrigin, model.lightingOrigin)
		Q.VectorCopy(cent.lerpOrigin, model.origin)
		Q.AnglesToAxis(cent.currentState.angles, model.axis)

		model.hModel = cgs.media.overloadBaseModel
		trap.R_AddRefEntityToScene(model)
		-- if hit
		if cent.currentState.frame == 1 then
			-- show hit model
			-- modelindex2 is the health value of the obelisk
			c = cent.currentState.modelindex2
			model.shaderRGBA[0] = 0xff
			model.shaderRGBA[1] = c
			model.shaderRGBA[2] = c
			model.shaderRGBA[3] = 0xff
			model.hModel = cgs.media.overloadEnergyModel
			trap.R_AddRefEntityToScene(model)
		end
		-- if respawning
		if cent.currentState.frame == 2 then
			if cent.miscTime == 0 then
				cent.miscTime = cg.time
			end
			local t = cg.time - cent.miscTime
			local h = (G.cg_obeliskRespawnDelay.integer - 5) * 1000
			if t > h then
				c = (t - h) / h
				if c > 1 then
					c = 1
				end
			else
				c = 0
			end
			-- show the lights
			Q.AnglesToAxis(cent.currentState.angles, model.axis)
			model.shaderRGBA[0] = Q.int(c * 0xff)
			model.shaderRGBA[1] = Q.int(c * 0xff)
			model.shaderRGBA[2] = Q.int(c * 0xff)
			model.shaderRGBA[3] = Q.int(c * 0xff)

			model.hModel = cgs.media.overloadLightsModel
			trap.R_AddRefEntityToScene(model)
			-- show the target
			if t > h then
				if cent.muzzleFlashTime == 0 then
					trap.S_StartSound(cent.lerpOrigin, C.ENTITYNUM_NONE, C.CHAN_BODY, cgs.media.obeliskRespawnSound)
					cent.muzzleFlashTime = 1
				end
				local angles = Q.vec3(0, 0, 0)
				Q.VectorCopy(cent.currentState.angles, angles)
				angles[C.YAW] = angles[C.YAW] + 16 * math.acos(1 - c) * 180 / math.pi
				Q.AnglesToAxis(angles, model.axis)

				Q.VectorScale(model.axis[0], c, model.axis[0])
				Q.VectorScale(model.axis[1], c, model.axis[1])
				Q.VectorScale(model.axis[2], c, model.axis[2])

				model.shaderRGBA[0] = 0xff
				model.shaderRGBA[1] = 0xff
				model.shaderRGBA[2] = 0xff
				model.shaderRGBA[3] = 0xff

				model.origin[2] = model.origin[2] + 56
				model.hModel = cgs.media.overloadTargetModel
				trap.R_AddRefEntityToScene(model)
			end
			--FIXME: show animated smoke
		else
			cent.miscTime = 0
			cent.muzzleFlashTime = 0
			-- modelindex2 is the health value of the obelisk
			c = cent.currentState.modelindex2
			model.shaderRGBA[0] = 0xff
			model.shaderRGBA[1] = c
			model.shaderRGBA[2] = c
			model.shaderRGBA[3] = 0xff
			-- show the lights
			model.hModel = cgs.media.overloadLightsModel
			trap.R_AddRefEntityToScene(model)
			-- show the target
			model.origin[2] = model.origin[2] + 56
			model.hModel = cgs.media.overloadTargetModel
			trap.R_AddRefEntityToScene(model)
		end
	elseif cgs.gametype == C.GT_HARVESTER then
		-- show harvester model
		model = T.refEntity_t()
		model.reType = C.RT_MODEL
		Q.VectorCopy(cent.lerpOrigin, model.lightingOrigin)
		Q.VectorCopy(cent.lerpOrigin, model.origin)
		Q.AnglesToAxis(cent.currentState.angles, model.axis)

		if cent.currentState.modelindex == C.TEAM_RED then
			model.hModel = cgs.media.harvesterModel
			model.customSkin = cgs.media.harvesterRedSkin
		elseif cent.currentState.modelindex == C.TEAM_BLUE then
			model.hModel = cgs.media.harvesterModel
			model.customSkin = cgs.media.harvesterBlueSkin
		else
			model.hModel = cgs.media.harvesterNeutralModel
			model.customSkin = 0
		end
		trap.R_AddRefEntityToScene(model)
	end
end

local function CG_AddCEntity(cent)
	local eType = cent.currentState.eType

	-- event-only entities will have been dealt with already
	if eType >= C.ET_EVENTS then
		return
	end

	-- calculate the current origin
	CG_CalcEntityLerpPositions(cent)

	-- add automatic effects
	CG_EntityEffects(cent)

	if eType == C.ET_INVISIBLE or eType == C.ET_PUSH_TRIGGER or eType == C.ET_TELEPORT_TRIGGER then
		return
	elseif eType == C.ET_GENERAL then
		CG_General(cent)
	elseif eType == C.ET_PLAYER then
		G.CG_Player(cent)
	elseif eType == C.ET_ITEM then
		CG_Item(cent)
	elseif eType == C.ET_MISSILE then
		CG_Missile(cent)
	elseif eType == C.ET_MOVER then
		CG_Mover(cent)
	elseif eType == C.ET_BEAM then
		G.CG_Beam(cent)
	elseif eType == C.ET_PORTAL then
		CG_Portal(cent)
	elseif eType == C.ET_SPEAKER then
		CG_Speaker(cent)
	elseif eType == C.ET_GRAPPLE then
		CG_Grapple(cent)
	elseif eType == C.ET_TEAM then
		CG_TeamBase(cent)
	else
		G.CG_Error(Q.va("Bad entity type: %i\n", eType))
	end
end

function G.CG_AddPacketEntities()
	local cg = G.cg

	-- set cg.frameInterpolation
	if cg.nextSnap ~= nil then
		local delta = cg.nextSnap.serverTime - cg.snap.serverTime
		if delta == 0 then
			cg.frameInterpolation = 0
		else
			cg.frameInterpolation = (cg.time - cg.snap.serverTime) / delta
		end
	else
		cg.frameInterpolation = 0 -- actually, it should never be used, because
		-- no entities should be marked as interpolating
	end

	-- the auto-rotating items will all have the same axis
	cg.autoAngles[0] = 0
	cg.autoAngles[1] = bit32.band(cg.time, 2047) * 360 / 2048.0
	cg.autoAngles[2] = 0

	cg.autoAnglesFast[0] = 0
	cg.autoAnglesFast[1] = bit32.band(cg.time, 1023) * 360 / 1024.0
	cg.autoAnglesFast[2] = 0

	Q.AnglesToAxis(cg.autoAngles, cg.autoAxis)
	Q.AnglesToAxis(cg.autoAnglesFast, cg.autoAxisFast)

	-- generate and add the entity from the playerstate
	local ps = cg.predictedPlayerState
	BG.BG_PlayerStateToEntityState(ps, cg.predictedPlayerEntity.currentState, false)
	CG_AddCEntity(cg.predictedPlayerEntity)

	-- lerp the non-predicted value for lightning gun origins
	CG_CalcEntityLerpPositions(G.cg_entities[cg.snap.ps.clientNum])

	--unlagged - early transitioning
	if cg.nextSnap ~= nil then
		-- pre-add some of the entities sent over by the server
		-- we have data for them and they don't need to interpolate
		for num = 0, cg.nextSnap.numEntities - 1 do
			local cent = G.cg_entities[cg.nextSnap.entities[num].number]
			if cent.nextState.eType == C.ET_MISSILE or cent.nextState.eType == C.ET_GENERAL then
				-- transition it immediately and add it
				G.CG_TransitionEntity(cent)
				cent.interpolate = true
				CG_AddCEntity(cent)
			end
		end
	end

	-- add each entity sent over by the server
	for num = 0, cg.snap.numEntities - 1 do
		local cent = G.cg_entities[cg.snap.entities[num].number]
		if cg.nextSnap == nil
			or (cent.nextState.eType ~= C.ET_MISSILE and cent.nextState.eType ~= C.ET_GENERAL) then
			CG_AddCEntity(cent)
		end
	end
end

return G
