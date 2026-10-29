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
-- Luau port of code/q3_ui/ui_players.c (OpenArena gamecode).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)
local BG = require(script.Parent.Parent.Parent.client.adapters.BG)

local UI_TIMER_GESTURE = 2300
local UI_TIMER_JUMP = 1000
local UI_TIMER_LAND = 130
local UI_TIMER_WEAPON_SWITCH = 300
local UI_TIMER_ATTACK = 500
local UI_TIMER_MUZZLE_FLASH = 20
local UI_TIMER_WEAPON_DELAY = 250

local JUMP_HEIGHT = 56

local SWINGSPEED = 0.3

local SPIN_SPEED = 0.9
local COAST_TIME = 1000

local dp_realtime = 0
local jumpHeight = 0

local NOT_TOGGLE = bit32.bnot(C.ANIM_TOGGLEBIT)

local function MAKERGB(v, r, g, b)
	v[0] = r
	v[1] = g
	v[2] = b
end

local function stripExtension(path)
	local base = string.match(path, "^(.*)%.[^%./]*$")
	return base or path
end

local UI_ForceLegsAnim, UI_SetLegsAnim, UI_ForceTorsoAnim, UI_SetTorsoAnim

local function UI_PlayerInfo_SetWeapon(pi, weaponNum)
	local item
	local path

	pi.currentWeapon = weaponNum
	while true do
		pi.realWeapon = weaponNum
		pi.weaponModel = 0
		pi.barrelModel = 0
		pi.flashModel = 0

		if weaponNum == C.WP_NONE then
			return
		end

		local idx = 1
		item = BG.bg_itemlist[idx]
		while item ~= nil and item.classname ~= nil and item.classname ~= "" do
			if item.giType == C.IT_WEAPON and item.giTag == weaponNum then
				break
			end
			idx += 1
			item = BG.bg_itemlist[idx]
		end

		if item ~= nil and item.classname ~= nil and item.classname ~= "" then
			pi.weaponModel = trap.R_RegisterModel(item.world_model[0])
		end

		if pi.weaponModel == 0 then
			if weaponNum == C.WP_MACHINEGUN then
				weaponNum = C.WP_NONE
			else
				weaponNum = C.WP_MACHINEGUN
			end
		else
			break
		end
	end

	if weaponNum == C.WP_MACHINEGUN or weaponNum == C.WP_GAUNTLET or weaponNum == C.WP_BFG then
		path = stripExtension(item.world_model[0]) .. "_barrel.md3"
		pi.barrelModel = trap.R_RegisterModel(path)
	end

	path = stripExtension(item.world_model[0]) .. "_flash.md3"
	pi.flashModel = trap.R_RegisterModel(path)

	local col = pi.flashDlightColor
	if weaponNum == C.WP_GAUNTLET then
		MAKERGB(col, 0.6, 0.6, 1)
	elseif weaponNum == C.WP_MACHINEGUN then
		MAKERGB(col, 1, 1, 0)
	elseif weaponNum == C.WP_SHOTGUN then
		MAKERGB(col, 1, 1, 0)
	elseif weaponNum == C.WP_GRENADE_LAUNCHER then
		MAKERGB(col, 1, 0.7, 0.5)
	elseif weaponNum == C.WP_ROCKET_LAUNCHER then
		MAKERGB(col, 1, 0.75, 0)
	elseif weaponNum == C.WP_LIGHTNING then
		MAKERGB(col, 0.6, 0.6, 1)
	elseif weaponNum == C.WP_RAILGUN then
		MAKERGB(col, 1, 0.5, 0)
	elseif weaponNum == C.WP_PLASMAGUN then
		MAKERGB(col, 0.6, 0.6, 1)
	elseif weaponNum == C.WP_BFG then
		MAKERGB(col, 1, 0.7, 1)
	elseif weaponNum == C.WP_GRAPPLING_HOOK then
		MAKERGB(col, 0.6, 0.6, 1)
	else
		MAKERGB(col, 1, 1, 1)
	end
end

function UI_ForceLegsAnim(pi, anim)
	pi.legsAnim = bit32.bor(bit32.bxor(bit32.band(pi.legsAnim, C.ANIM_TOGGLEBIT), C.ANIM_TOGGLEBIT), anim)

	if anim == C.LEGS_JUMP then
		pi.legsAnimationTimer = UI_TIMER_JUMP
	end
end

function UI_SetLegsAnim(pi, anim)
	if pi.pendingLegsAnim ~= 0 then
		anim = pi.pendingLegsAnim
		pi.pendingLegsAnim = 0
	end
	UI_ForceLegsAnim(pi, anim)
end

function UI_ForceTorsoAnim(pi, anim)
	pi.torsoAnim = bit32.bor(bit32.bxor(bit32.band(pi.torsoAnim, C.ANIM_TOGGLEBIT), C.ANIM_TOGGLEBIT), anim)

	if anim == C.TORSO_GESTURE then
		pi.torsoAnimationTimer = UI_TIMER_GESTURE
	end

	if anim == C.TORSO_ATTACK or anim == C.TORSO_ATTACK2 then
		pi.torsoAnimationTimer = UI_TIMER_ATTACK
	end
end

function UI_SetTorsoAnim(pi, anim)
	if pi.pendingTorsoAnim ~= 0 then
		anim = pi.pendingTorsoAnim
		pi.pendingTorsoAnim = 0
	end

	UI_ForceTorsoAnim(pi, anim)
end

local function UI_TorsoSequencing(pi)
	local currentAnim = bit32.band(pi.torsoAnim, NOT_TOGGLE)

	if pi.weapon ~= pi.currentWeapon then
		if currentAnim ~= C.TORSO_DROP then
			pi.torsoAnimationTimer = UI_TIMER_WEAPON_SWITCH
			UI_ForceTorsoAnim(pi, C.TORSO_DROP)
		end
	end

	if pi.torsoAnimationTimer > 0 then
		return
	end

	if currentAnim == C.TORSO_GESTURE then
		UI_SetTorsoAnim(pi, C.TORSO_STAND)
		return
	end

	if currentAnim == C.TORSO_ATTACK or currentAnim == C.TORSO_ATTACK2 then
		UI_SetTorsoAnim(pi, C.TORSO_STAND)
		return
	end

	if currentAnim == C.TORSO_DROP then
		UI_PlayerInfo_SetWeapon(pi, pi.weapon)
		pi.torsoAnimationTimer = UI_TIMER_WEAPON_SWITCH
		UI_ForceTorsoAnim(pi, C.TORSO_RAISE)
		return
	end

	if currentAnim == C.TORSO_RAISE then
		UI_SetTorsoAnim(pi, C.TORSO_STAND)
		return
	end
end

local function UI_LegsSequencing(pi)
	local currentAnim = bit32.band(pi.legsAnim, NOT_TOGGLE)

	if pi.legsAnimationTimer > 0 then
		if currentAnim == C.LEGS_JUMP then
			jumpHeight = JUMP_HEIGHT * math.sin(math.pi * (UI_TIMER_JUMP - pi.legsAnimationTimer) / UI_TIMER_JUMP)
		end
		return
	end

	if currentAnim == C.LEGS_JUMP then
		UI_ForceLegsAnim(pi, C.LEGS_LAND)
		pi.legsAnimationTimer = UI_TIMER_LAND
		jumpHeight = 0
		return
	end

	if currentAnim == C.LEGS_LAND then
		UI_SetLegsAnim(pi, C.LEGS_IDLE)
		return
	end
end

local function UI_PositionEntityOnTag(entity, parent, parentModel, tagName)
	local lerped = T.orientation_t()

	trap.R_LerpTag(lerped, parentModel, parent.oldframe, parent.frame, 1.0 - parent.backlerp, tagName)

	Q.VectorCopy(parent.origin, entity.origin)
	for i = 0, 2 do
		Q.VectorMA(entity.origin, lerped.origin[i], parent.axis[i], entity.origin)
	end

	Q.MatrixMultiply(lerped.axis, parent.axis, entity.axis)
	entity.backlerp = parent.backlerp
end

local function UI_PositionRotatedEntityOnTag(entity, parent, parentModel, tagName)
	local lerped = T.orientation_t()
	local tempAxis = { [0] = Q.vec3(0, 0, 0), [1] = Q.vec3(0, 0, 0), [2] = Q.vec3(0, 0, 0) }

	trap.R_LerpTag(lerped, parentModel, parent.oldframe, parent.frame, 1.0 - parent.backlerp, tagName)

	Q.VectorCopy(parent.origin, entity.origin)
	for i = 0, 2 do
		Q.VectorMA(entity.origin, lerped.origin[i], parent.axis[i], entity.origin)
	end

	Q.MatrixMultiply(entity.axis, lerped.axis, tempAxis)
	Q.MatrixMultiply(tempAxis, parent.axis, entity.axis)
end

local function UI_SetLerpFrameAnimation(ci, lf, newAnimation)
	lf.animationNumber = newAnimation
	newAnimation = bit32.band(newAnimation, NOT_TOGGLE)

	if newAnimation < 0 or newAnimation >= C.MAX_ANIMATIONS then
		trap.Error(Q.va("Bad animation number: %i", newAnimation))
	end

	local anim = ci.animations[newAnimation]

	lf.animation = anim
	lf.animationTime = lf.frameTime + anim.initialLerp
end

local function UI_RunLerpFrame(ci, lf, newAnimation)
	if newAnimation ~= lf.animationNumber or lf.animation == nil then
		UI_SetLerpFrameAnimation(ci, lf, newAnimation)
	end

	if dp_realtime >= lf.frameTime then
		lf.oldFrame = lf.frame
		lf.oldFrameTime = lf.frameTime

		local anim = lf.animation
		if anim.frameLerp == 0 then
			return
		end
		if dp_realtime < lf.animationTime then
			lf.frameTime = lf.animationTime
		else
			lf.frameTime = lf.oldFrameTime + anim.frameLerp
		end
		local f = Q.idiv(lf.frameTime - lf.animationTime, anim.frameLerp)
		local numFrames = anim.numFrames
		if anim.flipflop then
			numFrames *= 2
		end
		if f >= numFrames then
			f -= numFrames
			if anim.loopFrames ~= 0 then
				f = math.fmod(f, anim.loopFrames)
				f += anim.numFrames - anim.loopFrames
			else
				f = numFrames - 1
				lf.frameTime = dp_realtime
			end
		end
		if anim.reversed then
			lf.frame = anim.firstFrame + anim.numFrames - 1 - f
		elseif anim.flipflop and f >= anim.numFrames then
			lf.frame = anim.firstFrame + anim.numFrames - 1 - math.fmod(f, anim.numFrames)
		else
			lf.frame = anim.firstFrame + f
		end
		if dp_realtime > lf.frameTime then
			lf.frameTime = dp_realtime
		end
	end

	if lf.frameTime > dp_realtime + 200 then
		lf.frameTime = dp_realtime
	end

	if lf.oldFrameTime > dp_realtime then
		lf.oldFrameTime = dp_realtime
	end
	if lf.frameTime == lf.oldFrameTime then
		lf.backlerp = 0
	else
		lf.backlerp = 1.0 - (dp_realtime - lf.oldFrameTime) / (lf.frameTime - lf.oldFrameTime)
	end
end

local function UI_PlayerAnimation(pi)
	pi.legsAnimationTimer -= U.uis.frametime
	if pi.legsAnimationTimer < 0 then
		pi.legsAnimationTimer = 0
	end

	UI_LegsSequencing(pi)

	if pi.legs.yawing and bit32.band(pi.legsAnim, NOT_TOGGLE) == C.LEGS_IDLE then
		UI_RunLerpFrame(pi, pi.legs, C.LEGS_TURN)
	else
		UI_RunLerpFrame(pi, pi.legs, pi.legsAnim)
	end
	local legsOld = pi.legs.oldFrame
	local legs = pi.legs.frame
	local legsBackLerp = pi.legs.backlerp

	pi.torsoAnimationTimer -= U.uis.frametime
	if pi.torsoAnimationTimer < 0 then
		pi.torsoAnimationTimer = 0
	end

	UI_TorsoSequencing(pi)

	UI_RunLerpFrame(pi, pi.torso, pi.torsoAnim)
	return legsOld, legs, legsBackLerp, pi.torso.oldFrame, pi.torso.frame, pi.torso.backlerp
end

local function UI_SwingAngles(destination, swingTolerance, clampTolerance, speed, angle, swinging)
	if not swinging then
		local swing = Q.AngleSubtract(angle, destination)
		if swing > swingTolerance or swing < -swingTolerance then
			swinging = true
		end
	end

	if not swinging then
		return angle, swinging
	end

	local swing = Q.AngleSubtract(destination, angle)
	local scale = math.abs(swing)
	if scale < swingTolerance * 0.5 then
		scale = 0.5
	elseif scale < swingTolerance then
		scale = 1.0
	else
		scale = 2.0
	end

	local move
	if swing >= 0 then
		move = U.uis.frametime * scale * speed
		if move >= swing then
			move = swing
			swinging = false
		end
		angle = Q.AngleMod(angle + move)
	else
		move = U.uis.frametime * scale * -speed
		if move <= swing then
			move = swing
			swinging = false
		end
		angle = Q.AngleMod(angle + move)
	end

	swing = Q.AngleSubtract(destination, angle)
	if swing > clampTolerance then
		angle = Q.AngleMod(destination - (clampTolerance - 1))
	elseif swing < -clampTolerance then
		angle = Q.AngleMod(destination + (clampTolerance - 1))
	end
	return angle, swinging
end

local function UI_MovedirAdjustment(pi)
	local relativeAngles = Q.vec3(0, 0, 0)
	local moveVector = Q.vec3(0, 0, 0)

	Q.VectorSubtract(pi.viewAngles, pi.moveAngles, relativeAngles)
	Q.AngleVectors(relativeAngles, moveVector, nil, nil)
	if math.abs(moveVector[0]) < 0.01 then
		moveVector[0] = 0.0
	end
	if math.abs(moveVector[1]) < 0.01 then
		moveVector[1] = 0.0
	end

	if moveVector[1] == 0 and moveVector[0] > 0 then
		return 0
	end
	if moveVector[1] < 0 and moveVector[0] > 0 then
		return 22
	end
	if moveVector[1] < 0 and moveVector[0] == 0 then
		return 45
	end
	if moveVector[1] < 0 and moveVector[0] < 0 then
		return -22
	end
	if moveVector[1] == 0 and moveVector[0] < 0 then
		return 0
	end
	if moveVector[1] > 0 and moveVector[0] < 0 then
		return 22
	end
	if moveVector[1] > 0 and moveVector[0] == 0 then
		return -45
	end

	return -22
end

local function UI_PlayerAngles(pi, legs, torso, head)
	local legsAngles = Q.vec3(0, 0, 0)
	local torsoAngles = Q.vec3(0, 0, 0)
	local headAngles = Q.vec3(0, 0, 0)
	local dest

	Q.VectorCopy(pi.viewAngles, headAngles)
	headAngles[C.YAW] = Q.AngleMod(headAngles[C.YAW])

	if bit32.band(pi.legsAnim, NOT_TOGGLE) ~= C.LEGS_IDLE
		or bit32.band(pi.torsoAnim, NOT_TOGGLE) ~= C.TORSO_STAND then
		pi.torso.yawing = true
		pi.torso.pitching = true
		pi.legs.yawing = true
	end

	local adjust = UI_MovedirAdjustment(pi)
	legsAngles[C.YAW] = headAngles[C.YAW] + adjust
	torsoAngles[C.YAW] = headAngles[C.YAW] + 0.25 * adjust

	pi.torso.yawAngle, pi.torso.yawing =
		UI_SwingAngles(torsoAngles[C.YAW], 25, 90, SWINGSPEED, pi.torso.yawAngle, pi.torso.yawing)
	pi.legs.yawAngle, pi.legs.yawing =
		UI_SwingAngles(legsAngles[C.YAW], 40, 90, SWINGSPEED, pi.legs.yawAngle, pi.legs.yawing)

	torsoAngles[C.YAW] = pi.torso.yawAngle
	legsAngles[C.YAW] = pi.legs.yawAngle

	if headAngles[C.PITCH] > 180 then
		dest = (-360 + headAngles[C.PITCH]) * 0.75
	else
		dest = headAngles[C.PITCH] * 0.75
	end
	pi.torso.pitchAngle, pi.torso.pitching =
		UI_SwingAngles(dest, 15, 30, 0.1, pi.torso.pitchAngle, pi.torso.pitching)
	torsoAngles[C.PITCH] = pi.torso.pitchAngle
	if pi.fixedtorso then
		torsoAngles[C.PITCH] = 0.0
	end
	if pi.fixedlegs then
		legsAngles[C.YAW] = torsoAngles[C.YAW]
		legsAngles[C.PITCH] = 0.0
		legsAngles[C.ROLL] = 0.0
	end

	Q.AnglesSubtract(headAngles, torsoAngles, headAngles)
	Q.AnglesSubtract(torsoAngles, legsAngles, torsoAngles)
	Q.AnglesToAxis(legsAngles, legs)
	Q.AnglesToAxis(torsoAngles, torso)
	Q.AnglesToAxis(headAngles, head)
end

local function UI_PlayerFloatSprite(pi, origin, shader)
	local ent = T.refEntity_t()
	Q.VectorCopy(origin, ent.origin)
	ent.origin[2] += 48
	ent.reType = C.RT_SPRITE
	ent.customShader = shader
	ent.radius = 10
	ent.renderfx = 0
	trap.R_AddRefEntityToScene(ent)
end

function U.UI_MachinegunSpinAngle(pi)
	local angle
	local delta = dp_realtime - pi.barrelTime
	if pi.barrelSpinning then
		angle = pi.barrelAngle + delta * SPIN_SPEED
	else
		if delta > COAST_TIME then
			delta = COAST_TIME
		end

		local speed = 0.5 * (SPIN_SPEED + (COAST_TIME - delta) / COAST_TIME)
		angle = pi.barrelAngle + delta * speed
	end

	local torsoAnim = bit32.band(pi.torsoAnim, NOT_TOGGLE)
	if torsoAnim == C.TORSO_ATTACK2 then
		torsoAnim = C.TORSO_ATTACK
	end
	local attacking = torsoAnim == C.TORSO_ATTACK
	if (pi.barrelSpinning == true) == (not attacking) then
		pi.barrelTime = dp_realtime
		pi.barrelAngle = Q.AngleMod(angle)
		pi.barrelSpinning = attacking
	end

	return angle
end

function U.UI_DrawPlayer(x, y, w, h, pi, time)
	local refdef = T.refdef_t()
	local legs = T.refEntity_t()
	local torso = T.refEntity_t()
	local head = T.refEntity_t()
	local gun = T.refEntity_t()
	local barrel = T.refEntity_t()
	local flash = T.refEntity_t()
	local origin = Q.vec3(0, 0, 0)
	local mins = Q.vec3(-16, -16, -24)
	local maxs = Q.vec3(16, 16, 32)

	if pi.legsModel == 0 or pi.torsoModel == 0 or pi.headModel == 0 or pi.animations[0].numFrames == 0 then
		return
	end

	dp_realtime = time

	if pi.pendingWeapon ~= C.WP_NUM_WEAPONS and dp_realtime > pi.weaponTimer then
		pi.weapon = pi.pendingWeapon
		pi.lastWeapon = pi.pendingWeapon
		pi.pendingWeapon = C.WP_NUM_WEAPONS
		pi.weaponTimer = 0
		if pi.currentWeapon ~= pi.weapon then
			trap.S_StartLocalSound(U.weaponChangeSound, C.CHAN_LOCAL)
		end
	end

	x, y, w, h = U.UI_AdjustFrom640(x, y, w, h)

	y -= jumpHeight

	refdef.rdflags = C.RDF_NOWORLDMODEL

	Q.AxisClear(refdef.viewaxis)

	refdef.x = x
	refdef.y = y
	refdef.width = w
	refdef.height = h

	refdef.fov_x = Q.int(refdef.width / U.uis.xscale / 640.0 * 90.0)
	local xx = refdef.width / U.uis.xscale / math.tan(refdef.fov_x / 360 * math.pi)
	refdef.fov_y = math.atan2(refdef.height / U.uis.yscale, xx)
	refdef.fov_y *= (360 / math.pi)

	local len = 0.7 * (maxs[2] - mins[2])
	origin[0] = len / math.tan(refdef.fov_x * (math.pi / 180) * 0.5)
	origin[1] = 0.5 * (mins[1] + maxs[1])
	origin[2] = -0.5 * (mins[2] + maxs[2])

	refdef.time = dp_realtime

	trap.R_ClearScene()

	UI_PlayerAngles(pi, legs.axis, torso.axis, head.axis)

	legs.oldframe, legs.frame, legs.backlerp, torso.oldframe, torso.frame, torso.backlerp = UI_PlayerAnimation(pi)

	local renderfx = bit32.bor(C.RF_LIGHTING_ORIGIN, C.RF_NOSHADOW)

	legs.hModel = pi.legsModel
	legs.customSkin = pi.legsSkin

	Q.VectorCopy(origin, legs.origin)

	Q.VectorCopy(origin, legs.lightingOrigin)
	legs.renderfx = renderfx
	Q.VectorCopy(legs.origin, legs.oldorigin)

	trap.R_AddRefEntityToScene(legs)

	if legs.hModel == 0 then
		return
	end

	torso.hModel = pi.torsoModel
	if torso.hModel == 0 then
		return
	end

	torso.customSkin = pi.torsoSkin

	Q.VectorCopy(origin, torso.lightingOrigin)

	UI_PositionRotatedEntityOnTag(torso, legs, pi.legsModel, "tag_torso")

	torso.renderfx = renderfx

	trap.R_AddRefEntityToScene(torso)

	head.hModel = pi.headModel
	if head.hModel == 0 then
		return
	end
	head.customSkin = pi.headSkin

	Q.VectorCopy(origin, head.lightingOrigin)

	UI_PositionRotatedEntityOnTag(head, torso, pi.torsoModel, "tag_head")

	head.renderfx = renderfx

	trap.R_AddRefEntityToScene(head)

	if pi.currentWeapon ~= C.WP_NONE then
		gun.hModel = pi.weaponModel
		Q.VectorCopy(origin, gun.lightingOrigin)
		UI_PositionEntityOnTag(gun, torso, pi.torsoModel, "tag_weapon")
		gun.renderfx = renderfx
		trap.R_AddRefEntityToScene(gun)
	end

	if pi.realWeapon == C.WP_MACHINEGUN or pi.realWeapon == C.WP_GAUNTLET or pi.realWeapon == C.WP_BFG then
		local angles = Q.vec3(0, 0, 0)

		Q.VectorCopy(origin, barrel.lightingOrigin)
		barrel.renderfx = renderfx

		barrel.hModel = pi.barrelModel
		angles[C.YAW] = 0
		angles[C.PITCH] = 0
		angles[C.ROLL] = U.UI_MachinegunSpinAngle(pi)
		Q.AnglesToAxis(angles, barrel.axis)

		UI_PositionRotatedEntityOnTag(barrel, gun, pi.weaponModel, "tag_barrel")

		trap.R_AddRefEntityToScene(barrel)
	end

	if dp_realtime <= pi.muzzleFlashTime then
		if pi.flashModel ~= 0 then
			flash.hModel = pi.flashModel
			Q.VectorCopy(origin, flash.lightingOrigin)
			UI_PositionEntityOnTag(flash, gun, pi.weaponModel, "tag_flash")
			flash.renderfx = renderfx
			trap.R_AddRefEntityToScene(flash)
		end

		if pi.flashDlightColor[0] ~= 0 or pi.flashDlightColor[1] ~= 0 or pi.flashDlightColor[2] ~= 0 then
			trap.R_AddLightToScene(flash.origin, 200 + bit32.band(Q.rand(), 31), pi.flashDlightColor[0],
				pi.flashDlightColor[1], pi.flashDlightColor[2])
		end
	end

	if pi.chat then
		UI_PlayerFloatSprite(pi, origin, trap.R_RegisterShaderNoMip("sprites/balloon3"))
	end

	origin[0] -= 100
	origin[1] += 100
	origin[2] += 100
	trap.R_AddLightToScene(origin, 500, 1.0, 1.0, 1.0)

	origin[0] -= 100
	origin[1] -= 100
	origin[2] -= 100
	trap.R_AddLightToScene(origin, 500, 1.0, 0.0, 0.0)

	trap.R_RenderScene(refdef)
end

local function UI_RegisterClientSkin(pi, modelName, skinName)
	pi.legsSkin = trap.R_RegisterSkin(Q.va("models/players/%s/lower_%s.skin", modelName, skinName))
	pi.torsoSkin = trap.R_RegisterSkin(Q.va("models/players/%s/upper_%s.skin", modelName, skinName))
	pi.headSkin = trap.R_RegisterSkin(Q.va("models/players/%s/head_%s.skin", modelName, skinName))

	if pi.legsSkin == 0 or pi.torsoSkin == 0 or pi.headSkin == 0 then
		return false
	end

	return true
end

-- COM_Parse over a string; pos is a 1-based index. Returns token, newPos.
local function parseToken(text, pos)
	local n = #text
	while true do
		while pos <= n and string.byte(text, pos) <= 32 do
			pos += 1
		end
		if pos > n then
			return "", pos
		end
		local c = string.sub(text, pos, pos)
		local c2 = string.sub(text, pos, pos + 1)
		if c2 == "//" then
			while pos <= n and string.sub(text, pos, pos) ~= "\n" do
				pos += 1
			end
		elseif c2 == "/*" then
			local e = string.find(text, "*/", pos + 2, true)
			if e == nil then
				return "", n + 1
			end
			pos = e + 2
		elseif c == '"' then
			local e = string.find(text, '"', pos + 1, true)
			if e == nil then
				return string.sub(text, pos + 1), n + 1
			end
			return string.sub(text, pos + 1, e - 1), e + 1
		else
			local start = pos
			while pos <= n and string.byte(text, pos) > 32 do
				pos += 1
			end
			return string.sub(text, start, pos - 1), pos
		end
	end
end

local function UI_ParseAnimationFile(filename, pi)
	local animations = pi.animations
	local skip = 0

	for k = 0, C.MAX_ANIMATIONS - 1 do
		animations[k] = T.animation_t()
	end
	pi.fixedlegs = false
	pi.fixedtorso = false

	local len, f = trap.FS_FOpenFile(filename, C.FS_READ)
	if len <= 0 then
		return false
	end
	if len >= 20000 - 1 then
		trap.Print(Q.va("File %s too long\n", filename))
		trap.FS_FCloseFile(f)
		return false
	end
	local text = trap.FS_Read(len, f)
	trap.FS_FCloseFile(f)

	local pos = 1
	local token

	while true do
		local prev = pos
		token, pos = parseToken(text, pos)
		if token == "" then
			break
		end
		if token == "footsteps" then
			token, pos = parseToken(text, pos)
			if token == "" then
				break
			end
		elseif token == "headoffset" then
			for _ = 0, 2 do
				token, pos = parseToken(text, pos)
				if token == "" then
					break
				end
			end
		elseif token == "sex" then
			token, pos = parseToken(text, pos)
			if token == "" then
				break
			end
		elseif Q.stricmp(token, "fixedlegs") == 0 then
			pi.fixedlegs = true
		elseif Q.stricmp(token, "fixedtorso") == 0 then
			pi.fixedtorso = true
		else
			local b = string.byte(token, 1)
			if b >= 48 and b <= 57 then
				pos = prev
				break
			end

			trap.Print(Q.va("unknown token '%s' in %s\n", token, filename))
		end
	end

	local i = 0
	while i < C.MAX_ANIMATIONS do
		token, pos = parseToken(text, pos)
		if token == "" then
			if i >= C.TORSO_GETFLAG and i <= C.TORSO_NEGATIVE then
				animations[i].firstFrame = animations[C.TORSO_GESTURE].firstFrame
				animations[i].frameLerp = animations[C.TORSO_GESTURE].frameLerp
				animations[i].initialLerp = animations[C.TORSO_GESTURE].initialLerp
				animations[i].loopFrames = animations[C.TORSO_GESTURE].loopFrames
				animations[i].numFrames = animations[C.TORSO_GESTURE].numFrames
				animations[i].reversed = false
				animations[i].flipflop = false
				i += 1
				continue
			end
			break
		end
		animations[i].firstFrame = Q.int(tonumber(token) or 0)
		if i == C.LEGS_WALKCR then
			skip = animations[C.LEGS_WALKCR].firstFrame - animations[C.TORSO_GESTURE].firstFrame
		end
		if i >= C.LEGS_WALKCR and i < C.TORSO_GETFLAG then
			animations[i].firstFrame -= skip
		end

		token, pos = parseToken(text, pos)
		if token == "" then
			break
		end
		animations[i].numFrames = Q.int(tonumber(token) or 0)

		animations[i].reversed = false
		animations[i].flipflop = false
		if animations[i].numFrames < 0 then
			animations[i].numFrames = -animations[i].numFrames
			animations[i].reversed = true
		end

		token, pos = parseToken(text, pos)
		if token == "" then
			break
		end
		animations[i].loopFrames = Q.int(tonumber(token) or 0)

		token, pos = parseToken(text, pos)
		if token == "" then
			break
		end
		local fps = tonumber(token) or 0
		if fps == 0 then
			fps = 1
		end
		animations[i].frameLerp = Q.int(1000 / fps)
		animations[i].initialLerp = Q.int(1000 / fps)
		i += 1
	end

	if i ~= C.MAX_ANIMATIONS - (C.TORSO_NEGATIVE - C.TORSO_GETFLAG + 1) then
		trap.Print(Q.va("Error parsing animation file: %s\n", filename))
		return false
	end

	return true
end

function U.UI_RegisterClientModelname(pi, modelSkinName)
	pi.torsoModel = 0
	pi.headModel = 0

	if modelSkinName == "" then
		return false
	end

	local modelName = string.sub(modelSkinName, 1, C.MAX_QPATH - 1)
	local skinName

	local slash = string.find(modelName, "/", 1, true)
	if slash == nil then
		skinName = "default"
	else
		skinName = string.sub(modelName, slash + 1)
		modelName = string.sub(modelName, 1, slash - 1)
	end

	local filename = Q.va("models/players/%s/lower.md3", modelName)
	pi.legsModel = trap.R_RegisterModel(filename)
	if pi.legsModel == 0 then
		trap.Print(Q.va("Failed to load model file %s\n", filename))
		return false
	end

	filename = Q.va("models/players/%s/upper.md3", modelName)
	pi.torsoModel = trap.R_RegisterModel(filename)
	if pi.torsoModel == 0 then
		trap.Print(Q.va("Failed to load model file %s\n", filename))
		return false
	end

	filename = Q.va("models/players/%s/head.md3", modelName)
	pi.headModel = trap.R_RegisterModel(filename)
	if pi.headModel == 0 then
		trap.Print(Q.va("Failed to load model file %s\n", filename))
		return false
	end

	if not UI_RegisterClientSkin(pi, modelName, skinName) then
		if not UI_RegisterClientSkin(pi, modelName, "default") then
			trap.Print(Q.va("Failed to load skin file: %s : %s\n", modelName, skinName))
			return false
		end
	end

	filename = Q.va("models/players/%s/animation.cfg", modelName)
	if not UI_ParseAnimationFile(filename, pi) then
		trap.Print(Q.va("Failed to load animation file %s\n", filename))
		return false
	end

	return true
end

function U.UI_PlayerInfo_SetModel(pi, model)
	T.reset(pi, T.playerInfo_t)
	U.UI_RegisterClientModelname(pi, model)
	pi.weapon = C.WP_MACHINEGUN
	pi.currentWeapon = pi.weapon
	pi.lastWeapon = pi.weapon
	pi.pendingWeapon = C.WP_NUM_WEAPONS
	pi.weaponTimer = 0
	pi.chat = false
	pi.newModel = true
	UI_PlayerInfo_SetWeapon(pi, pi.weapon)
end

function U.UI_PlayerInfo_SetInfo(pi, legsAnim, torsoAnim, viewAngles, moveAngles, weaponNumber, chat)
	pi.chat = chat

	Q.VectorCopy(viewAngles, pi.viewAngles)

	Q.VectorCopy(moveAngles, pi.moveAngles)

	if pi.newModel then
		pi.newModel = false

		jumpHeight = 0
		pi.pendingLegsAnim = 0
		UI_ForceLegsAnim(pi, legsAnim)
		pi.legs.yawAngle = viewAngles[C.YAW]
		pi.legs.yawing = false

		pi.pendingTorsoAnim = 0
		UI_ForceTorsoAnim(pi, torsoAnim)
		pi.torso.yawAngle = viewAngles[C.YAW]
		pi.torso.yawing = false

		if weaponNumber ~= C.WP_NUM_WEAPONS then
			pi.weapon = weaponNumber
			pi.currentWeapon = weaponNumber
			pi.lastWeapon = weaponNumber
			pi.pendingWeapon = C.WP_NUM_WEAPONS
			pi.weaponTimer = 0
			UI_PlayerInfo_SetWeapon(pi, pi.weapon)
		end

		return
	end

	if weaponNumber == C.WP_NUM_WEAPONS then
		pi.pendingWeapon = C.WP_NUM_WEAPONS
		pi.weaponTimer = 0
	elseif weaponNumber ~= C.WP_NONE then
		pi.pendingWeapon = weaponNumber
		pi.weaponTimer = dp_realtime + UI_TIMER_WEAPON_DELAY
	end
	local weaponNum = pi.lastWeapon
	pi.weapon = weaponNum

	if torsoAnim == C.BOTH_DEATH1 or legsAnim == C.BOTH_DEATH1 then
		legsAnim = C.BOTH_DEATH1
		torsoAnim = legsAnim
		pi.currentWeapon = C.WP_NONE
		pi.weapon = C.WP_NONE
		UI_PlayerInfo_SetWeapon(pi, pi.weapon)

		jumpHeight = 0
		pi.pendingLegsAnim = 0
		UI_ForceLegsAnim(pi, legsAnim)

		pi.pendingTorsoAnim = 0
		UI_ForceTorsoAnim(pi, torsoAnim)

		return
	end

	local currentAnim = bit32.band(pi.legsAnim, NOT_TOGGLE)
	if legsAnim ~= C.LEGS_JUMP and (currentAnim == C.LEGS_JUMP or currentAnim == C.LEGS_LAND) then
		pi.pendingLegsAnim = legsAnim
	elseif legsAnim ~= currentAnim then
		jumpHeight = 0
		pi.pendingLegsAnim = 0
		UI_ForceLegsAnim(pi, legsAnim)
	end

	if torsoAnim == C.TORSO_STAND or torsoAnim == C.TORSO_STAND2 then
		if weaponNum == C.WP_NONE or weaponNum == C.WP_GAUNTLET then
			torsoAnim = C.TORSO_STAND2
		else
			torsoAnim = C.TORSO_STAND
		end
	end

	if torsoAnim == C.TORSO_ATTACK or torsoAnim == C.TORSO_ATTACK2 then
		if weaponNum == C.WP_NONE or weaponNum == C.WP_GAUNTLET then
			torsoAnim = C.TORSO_ATTACK2
		else
			torsoAnim = C.TORSO_ATTACK
		end
		pi.muzzleFlashTime = dp_realtime + UI_TIMER_MUZZLE_FLASH
	end

	currentAnim = bit32.band(pi.torsoAnim, NOT_TOGGLE)

	if weaponNum ~= pi.currentWeapon or currentAnim == C.TORSO_RAISE or currentAnim == C.TORSO_DROP then
		pi.pendingTorsoAnim = torsoAnim
	elseif (currentAnim == C.TORSO_GESTURE or currentAnim == C.TORSO_ATTACK) and torsoAnim ~= currentAnim then
		pi.pendingTorsoAnim = torsoAnim
	elseif torsoAnim ~= currentAnim then
		pi.pendingTorsoAnim = 0
		UI_ForceTorsoAnim(pi, torsoAnim)
	end
end

return U
