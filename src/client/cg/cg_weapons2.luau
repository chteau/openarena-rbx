--[[
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
along with Foobar; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
]]
-- Luau port of code/cgame/cg_weapons.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- This part covers C lines 1049-1667 of the 0.8.8 source.

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)

local SPIN_SPEED = 0.9
local COAST_TIME = 1000

local function isSet(v: any): boolean
	return v == true or (type(v) == "number" and v ~= 0)
end

local function anyDlight(weapon): boolean
	local c = weapon.flashDlightColor
	return c[0] ~= 0 or c[1] ~= 0 or c[2] ~= 0
end

local function isBeamWeapon(weaponNum: number): boolean
	return weaponNum == C.WP_LIGHTNING or weaponNum == C.WP_GAUNTLET or weaponNum == C.WP_GRAPPLING_HOOK
end

function G.CG_MapTorsoToWeaponFrame(ci, frame: number): number
	local anims = ci.animations

	-- change weapon
	if frame >= anims[C.TORSO_DROP].firstFrame and frame < anims[C.TORSO_DROP].firstFrame + 9 then
		return frame - anims[C.TORSO_DROP].firstFrame + 6
	end

	-- stand attack
	if frame >= anims[C.TORSO_ATTACK].firstFrame and frame < anims[C.TORSO_ATTACK].firstFrame + 6 then
		return 1 + frame - anims[C.TORSO_ATTACK].firstFrame
	end

	-- stand attack 2
	if frame >= anims[C.TORSO_ATTACK2].firstFrame and frame < anims[C.TORSO_ATTACK2].firstFrame + 6 then
		return 1 + frame - anims[C.TORSO_ATTACK2].firstFrame
	end

	return 0
end

function G.CG_CalculateWeaponPosition(origin, angles)
	local cg = G.cg
	local scale: number
	local delta: number
	local fracsin: number

	Q.VectorCopy(cg.refdef.vieworg, origin)
	Q.VectorCopy(cg.refdefViewAngles, angles)

	-- on odd legs, invert some angles
	if bit32.band(cg.bobcycle, 1) ~= 0 then
		scale = -cg.xyspeed
	else
		scale = cg.xyspeed
	end

	-- gun angles from bobbing
	angles[C.ROLL] += scale * cg.bobfracsin * 0.005
	angles[C.YAW] += scale * cg.bobfracsin * 0.01
	angles[C.PITCH] += cg.xyspeed * cg.bobfracsin * 0.005

	-- drop the weapon when landing
	delta = cg.time - cg.landTime
	if delta < C.LAND_DEFLECT_TIME then
		origin[2] += cg.landChange * 0.25 * delta / C.LAND_DEFLECT_TIME
	elseif delta < C.LAND_DEFLECT_TIME + C.LAND_RETURN_TIME then
		origin[2] += cg.landChange * 0.25 * (C.LAND_DEFLECT_TIME + C.LAND_RETURN_TIME - delta) / C.LAND_RETURN_TIME
	end

	-- idle drift
	scale = cg.xyspeed + 40
	fracsin = math.sin(cg.time * 0.001)
	angles[C.ROLL] += scale * fracsin * 0.01
	angles[C.YAW] += scale * fracsin * 0.01
	angles[C.PITCH] += scale * fracsin * 0.01
end

--[[
Origin will be the exact tag point, which is slightly
different than the muzzle point used for determining hits.
The cent should be the non-predicted cent if it is from the player,
so the endpoint will reflect the simulated strike (lagging the predicted
angle)
]]
function G.CG_LightningBolt(cent, origin)
	local cg = G.cg
	local cgs = G.cgs
	local trace = T.trace_t()
	local beam = T.refEntity_t()
	local forward = Q.vec3(0, 0, 0)
	local muzzlePoint = Q.vec3(0, 0, 0)
	local endPoint = Q.vec3(0, 0, 0)

	if cent.currentState.weapon ~= C.WP_LIGHTNING then
		return
	end

	local isUs = cent.currentState.number == cg.predictedPlayerState.clientNum

	if isUs and isSet(cgs.delagHitscan) and bit32.band(G.cg_delag.integer, 9) ~= 0 then
		-- always shoot straight forward from our current position
		Q.AngleVectors(cg.predictedPlayerState.viewangles, forward, nil, nil)
		Q.VectorCopy(cg.predictedPlayerState.origin, muzzlePoint)
	elseif isUs and G.cg_trueLightning.value ~= 0 then
		-- CPMA "true" lightning
		local angle = Q.vec3(0, 0, 0)

		for i = 0, 2 do
			local a = cent.lerpAngles[i] - cg.refdefViewAngles[i]
			if a > 180 then
				a -= 360
			end
			if a < -180 then
				a += 360
			end

			angle[i] = cg.refdefViewAngles[i] + a * (1.0 - G.cg_trueLightning.value)
			if angle[i] < 0 then
				angle[i] += 360
			end
			if angle[i] > 360 then
				angle[i] -= 360
			end
		end

		Q.AngleVectors(angle, forward, nil, nil)
		-- *this* is the correct origin for true lightning
		Q.VectorCopy(cg.predictedPlayerState.origin, muzzlePoint)
	else
		-- !CPMA
		Q.AngleVectors(cent.lerpAngles, forward, nil, nil)
		Q.VectorCopy(cent.lerpOrigin, muzzlePoint)
	end

	-- FIXME: crouch
	muzzlePoint[2] += C.DEFAULT_VIEWHEIGHT

	Q.VectorMA(muzzlePoint, 14, forward, muzzlePoint)

	-- project forward by the lightning range
	Q.VectorMA(muzzlePoint, C.LIGHTNING_RANGE, forward, endPoint)

	-- see if it hit a wall
	G.CG_Trace(trace, muzzlePoint, Q.vec3_origin, Q.vec3_origin, endPoint, cent.currentState.number, C.MASK_SHOT)

	-- this is the endpoint
	Q.VectorCopy(trace.endpos, beam.oldorigin)

	-- use the provided origin, even though it may be slightly
	-- different than the muzzle origin
	Q.VectorCopy(origin, beam.origin)

	beam.reType = C.RT_LIGHTNING
	beam.customShader = cgs.media.lightningShader
	trap.R_AddRefEntityToScene(beam)

	-- add the impact flare if it hit something
	if trace.fraction < 1.0 then
		local angles = Q.vec3(0, 0, 0)
		local dir = Q.vec3(0, 0, 0)

		Q.VectorSubtract(beam.oldorigin, beam.origin, dir)
		Q.VectorNormalize(dir)

		beam = T.refEntity_t()
		beam.hModel = cgs.media.lightningExplosionModel

		Q.VectorMA(trace.endpos, -16, dir, beam.origin)

		-- make a random orientation
		angles[0] = Q.rand() % 360
		angles[1] = Q.rand() % 360
		angles[2] = Q.rand() % 360
		Q.AnglesToAxis(angles, beam.axis)
		trap.R_AddRefEntityToScene(beam)
	end
end

--[[
Origin will be the exact tag point, which is slightly
different than the muzzle point used for determining hits.
]]
function G.CG_SpawnRailTrail(cent, origin)
	if cent.currentState.weapon ~= C.WP_RAILGUN then
		return
	end
	if not cent.pe.railgunFlash then
		return
	end
	cent.pe.railgunFlash = true
	local ci = G.cgs.clientinfo[cent.currentState.clientNum]
	G.CG_RailTrail(ci, origin, cent.pe.railgunImpact)
end

function G.CG_MachinegunSpinAngle(cent): number
	local cg = G.cg
	local delta: number
	local angle: number
	local speed: number

	delta = cg.time - cent.pe.barrelTime
	if cent.pe.barrelSpinning then
		angle = cent.pe.barrelAngle + delta * SPIN_SPEED
	else
		if delta > COAST_TIME then
			delta = COAST_TIME
		end

		speed = 0.5 * (SPIN_SPEED + (COAST_TIME - delta) / COAST_TIME)
		angle = cent.pe.barrelAngle + delta * speed
	end

	local firing = bit32.band(cent.currentState.eFlags, C.EF_FIRING) ~= 0
	if cent.pe.barrelSpinning == not firing then
		cent.pe.barrelTime = cg.time
		cent.pe.barrelAngle = Q.AngleMod(angle)
		cent.pe.barrelSpinning = firing
		if cent.currentState.weapon == C.WP_CHAINGUN and not cent.pe.barrelSpinning then
			trap.S_StartSound(
				nil,
				cent.currentState.number,
				C.CHAN_WEAPON,
				trap.S_RegisterSound("sound/weapons/vulcan/wvulwind.wav", false)
			)
		end
	end

	return angle
end

function G.CG_AddWeaponWithPowerups(gun, powerups: number)
	local cgs = G.cgs
	-- add powerup effects
	if bit32.band(powerups, bit32.lshift(1, C.PW_INVIS)) ~= 0 then
		if bit32.band(cgs.dmflags, C.DF_INVIS) == 0 then
			gun.customShader = cgs.media.invisShader
			trap.R_AddRefEntityToScene(gun)
		end
	else
		trap.R_AddRefEntityToScene(gun)

		if bit32.band(powerups, bit32.lshift(1, C.PW_BATTLESUIT)) ~= 0 then
			gun.customShader = cgs.media.battleWeaponShader
			trap.R_AddRefEntityToScene(gun)
		end
		if bit32.band(powerups, bit32.lshift(1, C.PW_QUAD)) ~= 0 then
			gun.customShader = cgs.media.quadWeaponShader
			trap.R_AddRefEntityToScene(gun)
		end
	end
end

--[[
Used for both the view weapon (ps is valid) and the world modelother character models (ps is NULL)
The main player will have this called for BOTH cases, so effects like light and
sound should only be done on the world model case.
]]
function G.CG_AddPlayerWeapon(parent, ps, cent, team)
	local cg = G.cg
	local cgs = G.cgs
	local gun = T.refEntity_t()
	local angles = Q.vec3(0, 0, 0)
	local lerped = T.orientation_t()

	local weaponNum = cent.currentState.weapon

	G.CG_RegisterWeapon(weaponNum)
	local weapon = G.cg_weapons[weaponNum]

	-- add the weapon
	Q.VectorCopy(parent.lightingOrigin, gun.lightingOrigin)
	gun.shadowPlane = parent.shadowPlane
	gun.renderfx = parent.renderfx

	-- set custom shading for railgun refire rate
	if ps ~= nil or cent.currentState.clientNum == cg.predictedPlayerState.clientNum then
		if cg.predictedPlayerState.weapon == C.WP_RAILGUN and cg.predictedPlayerState.weaponstate == C.WEAPON_FIRING then
			local f = cg.predictedPlayerState.weaponTime / 1500
			gun.shaderRGBA[1] = 0
			gun.shaderRGBA[2] = 255 * (1.0 - f)
			gun.shaderRGBA[0] = gun.shaderRGBA[2]
		else
			gun.shaderRGBA[0] = 255
			gun.shaderRGBA[1] = 255
			gun.shaderRGBA[2] = 255
			gun.shaderRGBA[3] = 255
		end
	end

	gun.hModel = weapon.weaponModel
	if gun.hModel == 0 then
		return
	end

	if ps == nil then
		-- add weapon ready sound
		cent.pe.lightningFiring = false
		if bit32.band(cent.currentState.eFlags, C.EF_FIRING) ~= 0 and weapon.firingSound ~= 0 then
			-- lightning gun and guantlet make a different sound when fire is held down
			trap.S_AddLoopingSound(cent.currentState.number, cent.lerpOrigin, Q.vec3_origin, weapon.firingSound)
			cent.pe.lightningFiring = true
		elseif weapon.readySound ~= 0 then
			trap.S_AddLoopingSound(cent.currentState.number, cent.lerpOrigin, Q.vec3_origin, weapon.readySound)
		end
	end

	trap.R_LerpTag(lerped, parent.hModel, parent.oldframe, parent.frame, 1.0 - parent.backlerp, "tag_weapon")
	Q.VectorCopy(parent.origin, gun.origin)

	Q.VectorMA(gun.origin, lerped.origin[0], parent.axis[0], gun.origin)

	-- Make weapon appear left-handed for 2 and centered for 3
	if ps ~= nil and G.cg_drawGun.integer == 2 then
		Q.VectorMA(gun.origin, -lerped.origin[1], parent.axis[1], gun.origin)
	elseif ps == nil or G.cg_drawGun.integer ~= 3 then
		Q.VectorMA(gun.origin, lerped.origin[1], parent.axis[1], gun.origin)
	end

	Q.VectorMA(gun.origin, lerped.origin[2], parent.axis[2], gun.origin)

	Q.MatrixMultiply(lerped.axis, parent.axis, gun.axis)
	gun.backlerp = parent.backlerp

	G.CG_AddWeaponWithPowerups(gun, cent.currentState.powerups)

	-- add the spinning barrel
	if weapon.barrelModel ~= 0 then
		local barrel = T.refEntity_t()
		Q.VectorCopy(parent.lightingOrigin, barrel.lightingOrigin)
		barrel.shadowPlane = parent.shadowPlane
		barrel.renderfx = parent.renderfx

		barrel.hModel = weapon.barrelModel
		angles[C.YAW] = 0
		angles[C.PITCH] = 0
		angles[C.ROLL] = G.CG_MachinegunSpinAngle(cent)
		Q.AnglesToAxis(angles, barrel.axis)

		G.CG_PositionRotatedEntityOnTag(barrel, gun, weapon.weaponModel, "tag_barrel")

		G.CG_AddWeaponWithPowerups(barrel, cent.currentState.powerups)
	end

	-- make sure we aren't looking at cg.predictedPlayerEntity for LG
	local nonPredictedCent = G.cg_entities[cent.currentState.clientNum]

	-- add the flash
	if isBeamWeapon(weaponNum) and bit32.band(nonPredictedCent.currentState.eFlags, C.EF_FIRING) ~= 0 then
		-- continuous flash
	else
		-- impulse flash
		if cg.time - cent.muzzleFlashTime > C.MUZZLE_FLASH_TIME and not cent.pe.railgunFlash then
			return
		end
	end

	local flash = T.refEntity_t()
	Q.VectorCopy(parent.lightingOrigin, flash.lightingOrigin)
	flash.shadowPlane = parent.shadowPlane
	flash.renderfx = parent.renderfx

	flash.hModel = weapon.flashModel
	if flash.hModel == 0 then
		return
	end
	angles[C.YAW] = 0
	angles[C.PITCH] = 0
	angles[C.ROLL] = Q.crandom() * 10
	Q.AnglesToAxis(angles, flash.axis)

	-- colorize the railgun blast
	if weaponNum == C.WP_RAILGUN then
		local ci = cgs.clientinfo[cent.currentState.clientNum]
		flash.shaderRGBA[0] = 255 * ci.color1[0]
		flash.shaderRGBA[1] = 255 * ci.color1[1]
		flash.shaderRGBA[2] = 255 * ci.color1[2]
	end

	G.CG_PositionRotatedEntityOnTag(flash, gun, weapon.weaponModel, "tag_flash")
	trap.R_AddRefEntityToScene(flash)

	if ps ~= nil or cg.renderingThirdPerson or cent.currentState.number ~= cg.predictedPlayerState.clientNum then
		-- add lightning bolt
		G.CG_LightningBolt(nonPredictedCent, flash.origin)

		-- add rail trail
		G.CG_SpawnRailTrail(cent, flash.origin)

		if anyDlight(weapon) then
			trap.R_AddLightToScene(
				flash.origin,
				300 + bit32.band(Q.rand(), 31),
				weapon.flashDlightColor[0],
				weapon.flashDlightColor[1],
				weapon.flashDlightColor[2]
			)
		end
	end
end

--[[
Add the weapon, and flash for the player's view
]]
function G.CG_AddViewWeapon(ps)
	local cg = G.cg
	local fovOffset: number
	local angles = Q.vec3(0, 0, 0)

	if ps.persistant[C.PERS_TEAM] == C.TEAM_SPECTATOR then
		return
	end

	if ps.pm_type == C.PM_INTERMISSION then
		return
	end

	-- no gun if in third person view or a camera is active
	if cg.renderingThirdPerson then
		return
	end

	-- allow the gun to be completely removed
	if G.cg_drawGun.integer == 0 then
		local origin = Q.vec3(0, 0, 0)

		if bit32.band(cg.predictedPlayerState.eFlags, C.EF_FIRING) ~= 0 then
			-- special hack for lightning gun...
			Q.VectorCopy(cg.refdef.vieworg, origin)
			Q.VectorMA(origin, -8, cg.refdef.viewaxis[2], origin)
			G.CG_LightningBolt(G.cg_entities[ps.clientNum], origin)
		end
		return
	end

	-- don't draw if testing a gun model
	if cg.testGun then
		return
	end

	-- drop gun lower at higher fov
	if G.cg_fov.integer > 90 then
		fovOffset = -0.2 * (G.cg_fov.integer - 90)
	else
		fovOffset = 0
	end

	local cent = cg.predictedPlayerEntity
	G.CG_RegisterWeapon(ps.weapon)
	local weapon = G.cg_weapons[ps.weapon]

	local hand = T.refEntity_t()

	-- set up gun position
	G.CG_CalculateWeaponPosition(hand.origin, angles)

	Q.VectorMA(hand.origin, G.cg_gun_x.value, cg.refdef.viewaxis[0], hand.origin)
	Q.VectorMA(hand.origin, G.cg_gun_y.value, cg.refdef.viewaxis[1], hand.origin)
	Q.VectorMA(hand.origin, G.cg_gun_z.value + fovOffset, cg.refdef.viewaxis[2], hand.origin)

	Q.AnglesToAxis(angles, hand.axis)

	-- map torso animations to weapon animations
	if G.cg_gun_frame.integer ~= 0 then
		-- development tool
		hand.frame = G.cg_gun_frame.integer
		hand.oldframe = hand.frame
		hand.backlerp = 0
	else
		-- get clientinfo for animation map
		local ci = G.cgs.clientinfo[cent.currentState.clientNum]
		hand.frame = G.CG_MapTorsoToWeaponFrame(ci, cent.pe.torso.frame)
		hand.oldframe = G.CG_MapTorsoToWeaponFrame(ci, cent.pe.torso.oldFrame)
		hand.backlerp = cent.pe.torso.backlerp
	end

	hand.hModel = weapon.handsModel
	hand.renderfx = bit32.bor(C.RF_DEPTHHACK, C.RF_FIRST_PERSON, C.RF_MINLIGHT)

	-- add everything onto the hand
	G.CG_AddPlayerWeapon(hand, ps, cg.predictedPlayerEntity, ps.persistant[C.PERS_TEAM])
end

return G
