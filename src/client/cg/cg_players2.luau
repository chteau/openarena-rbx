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
along with Foobar; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/cgame/cg_players.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- This part covers C lines 1280-2624 of the 0.8.8 source.

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)
local BG = require(script.Parent.Parent.adapters.BG)

local band = bit32.band
local bor = bit32.bor

G.movementOffsets = { [0] = 0, 22, 45, -22, 0, 22, -45, -22 }
G.SHADOW_DISTANCE = 128

local ANIM_MASK = bit32.bnot(C.ANIM_TOGGLEBIT)

-- returns the new angle and swinging state
function G.CG_SwingAngles(destination, swingTolerance, clampTolerance, speed, angle, swinging)
	local swing, move, scale

	if not swinging then
		swing = Q.AngleSubtract(angle, destination)
		if swing > swingTolerance or swing < -swingTolerance then
			swinging = true
		end
	end

	if not swinging then
		return angle, swinging
	end

	swing = Q.AngleSubtract(destination, angle)
	scale = math.abs(swing)
	if scale < swingTolerance * 0.5 then
		scale = 0.5
	elseif scale < swingTolerance then
		scale = 1.0
	else
		scale = 2.0
	end

	if swing >= 0 then
		move = G.cg.frametime * scale * speed
		if move >= swing then
			move = swing
			swinging = false
		end
		angle = Q.AngleMod(angle + move)
	elseif swing < 0 then
		move = G.cg.frametime * scale * -speed
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

function G.CG_AddPainTwitch(cent, torsoAngles)
	local t = G.cg.time - cent.pe.painTime
	if t >= C.PAIN_TWITCH_TIME then
		return
	end

	local f = 1.0 - t / C.PAIN_TWITCH_TIME

	if cent.pe.painDirection ~= 0 then
		torsoAngles[C.ROLL] += 20 * f
	else
		torsoAngles[C.ROLL] -= 20 * f
	end
end

function G.CG_PlayerAngles(cent, legs, torso, head)
	local legsAngles = Q.vec3(0, 0, 0)
	local torsoAngles = Q.vec3(0, 0, 0)
	local headAngles = Q.vec3(0, 0, 0)
	local dest
	local velocity = Q.vec3(0, 0, 0)
	local speed
	local dir, clientNum
	local ci

	Q.VectorCopy(cent.lerpAngles, headAngles)
	headAngles[C.YAW] = Q.AngleMod(headAngles[C.YAW])

	-- allow yaw to drift a bit
	local legsAnim = band(cent.currentState.legsAnim, ANIM_MASK)
	local torsoAnim = band(cent.currentState.torsoAnim, ANIM_MASK)
	if legsAnim ~= C.LEGS_IDLE or (torsoAnim ~= C.TORSO_STAND and torsoAnim ~= C.TORSO_STAND2) then
		cent.pe.torso.yawing = true
		cent.pe.torso.pitching = true
		cent.pe.legs.yawing = true
	end

	-- adjust legs for movement dir
	if band(cent.currentState.eFlags, C.EF_DEAD) ~= 0 then
		dir = 0
	else
		dir = Q.int(cent.currentState.angles2[C.YAW])
		if dir < 0 or dir > 7 then
			G.CG_Error("Bad player movement angle")
		end
	end
	legsAngles[C.YAW] = headAngles[C.YAW] + G.movementOffsets[dir]
	torsoAngles[C.YAW] = headAngles[C.YAW] + 0.25 * G.movementOffsets[dir]

	local pe = cent.pe
	pe.torso.yawAngle, pe.torso.yawing = G.CG_SwingAngles(torsoAngles[C.YAW], 25, 90, G.cg_swingSpeed.value, pe.torso.yawAngle, pe.torso.yawing)
	pe.legs.yawAngle, pe.legs.yawing = G.CG_SwingAngles(legsAngles[C.YAW], 40, 90, G.cg_swingSpeed.value, pe.legs.yawAngle, pe.legs.yawing)

	torsoAngles[C.YAW] = pe.torso.yawAngle
	legsAngles[C.YAW] = pe.legs.yawAngle

	-- only show a fraction of the pitch angle in the torso
	if headAngles[C.PITCH] > 180 then
		dest = (-360 + headAngles[C.PITCH]) * 0.75
	else
		dest = headAngles[C.PITCH] * 0.75
	end
	pe.torso.pitchAngle, pe.torso.pitching = G.CG_SwingAngles(dest, 15, 30, 0.1, pe.torso.pitchAngle, pe.torso.pitching)
	torsoAngles[C.PITCH] = pe.torso.pitchAngle

	clientNum = cent.currentState.clientNum
	if clientNum >= 0 and clientNum < C.MAX_CLIENTS then
		ci = G.cgs.clientinfo[clientNum]
		if ci.fixedtorso then
			torsoAngles[C.PITCH] = 0.0
		end
	end

	-- lean towards the direction of travel
	Q.VectorCopy(cent.currentState.pos.trDelta, velocity)
	speed = Q.VectorNormalize(velocity)
	if speed ~= 0 then
		local axis = { [0] = Q.vec3(0, 0, 0), Q.vec3(0, 0, 0), Q.vec3(0, 0, 0) }
		local side

		speed *= 0.05

		Q.AnglesToAxis(legsAngles, axis)
		side = speed * Q.DotProduct(velocity, axis[1])
		legsAngles[C.ROLL] -= side

		side = speed * Q.DotProduct(velocity, axis[0])
		legsAngles[C.PITCH] += side
	end

	clientNum = cent.currentState.clientNum
	if clientNum >= 0 and clientNum < C.MAX_CLIENTS then
		ci = G.cgs.clientinfo[clientNum]
		if ci.fixedlegs then
			legsAngles[C.YAW] = torsoAngles[C.YAW]
			legsAngles[C.PITCH] = 0.0
			legsAngles[C.ROLL] = 0.0
		end
	end

	-- pain twitch
	G.CG_AddPainTwitch(cent, torsoAngles)

	-- pull the angles back out of the hierarchial chain
	Q.AnglesSubtract(headAngles, torsoAngles, headAngles)
	Q.AnglesSubtract(torsoAngles, legsAngles, torsoAngles)
	Q.AnglesToAxis(legsAngles, legs)
	Q.AnglesToAxis(torsoAngles, torso)
	Q.AnglesToAxis(headAngles, head)
end

function G.CG_HasteTrail(cent)
	local cg = G.cg
	if cent.trailTime > cg.time then
		return
	end
	local anim = band(cent.pe.legs.animationNumber, ANIM_MASK)
	if anim ~= C.LEGS_RUN and anim ~= C.LEGS_BACK then
		return
	end

	cent.trailTime += 100
	if cent.trailTime < cg.time then
		cent.trailTime = cg.time
	end

	local origin = Q.vec3(0, 0, 0)
	Q.VectorCopy(cent.lerpOrigin, origin)
	origin[2] -= 16

	local smoke = G.CG_SmokePuff(origin, Q.vec3_origin,
		8,
		1, 1, 1, 1,
		500,
		cg.time,
		0,
		0,
		G.cgs.media.hastePuffShader)

	-- use the optimized local entity add
	smoke.leType = C.LE_SCALE_FADE
end

function G.CG_BreathPuffs(cent, head)
	local cg = G.cg
	local ci = G.cgs.clientinfo[cent.currentState.number]

	if G.cg_enableBreath.integer == 0 then
		return
	end
	if cent.currentState.number == cg.snap.ps.clientNum and not cg.renderingThirdPerson then
		return
	end
	if band(cent.currentState.eFlags, C.EF_DEAD) ~= 0 then
		return
	end
	local contents = G.CG_PointContents(head.origin, 0)
	if band(contents, bor(C.CONTENTS_WATER, C.CONTENTS_SLIME, C.CONTENTS_LAVA)) ~= 0 then
		return
	end
	if ci.breathPuffTime > cg.time then
		return
	end

	local up = Q.vec3(0, 0, 8)
	local origin = Q.vec3(0, 0, 0)
	Q.VectorMA(head.origin, 8, head.axis[0], origin)
	Q.VectorMA(origin, -4, head.axis[2], origin)
	G.CG_SmokePuff(origin, up, 16, 1, 1, 1, 0.66, 1500, cg.time, cg.time + 400, C.LEF_PUFF_DONT_SCALE, G.cgs.media.shotgunSmokePuffShader)
	ci.breathPuffTime = cg.time + 2000
end

function G.CG_DustTrail(cent)
	local cg = G.cg
	if G.cg_enableDust.integer == 0 then
		return
	end

	if cent.dustTrailTime > cg.time then
		return
	end

	local anim = band(cent.pe.legs.animationNumber, ANIM_MASK)
	if anim ~= C.LEGS_LANDB and anim ~= C.LEGS_LAND then
		return
	end

	cent.dustTrailTime += 40
	if cent.dustTrailTime < cg.time then
		cent.dustTrailTime = cg.time
	end

	local end_ = Q.vec3(0, 0, 0)
	local vel = Q.vec3(0, 0, 0)
	local tr = T.trace_t()
	Q.VectorCopy(cent.currentState.pos.trBase, end_)
	end_[2] -= 64
	G.CG_Trace(tr, cent.currentState.pos.trBase, nil, nil, end_, cent.currentState.number, C.MASK_PLAYERSOLID)

	if band(tr.surfaceFlags, C.SURF_DUST) == 0 then
		return
	end

	Q.VectorCopy(cent.currentState.pos.trBase, end_)
	end_[2] -= 16

	Q.VectorSet(vel, 0, 0, -30)
	G.CG_SmokePuff(end_, vel,
		24,
		0.8, 0.8, 0.7, 0.33,
		500,
		cg.time,
		0,
		0,
		G.cgs.media.dustPuffShader)
end

function G.CG_TrailItem(cent, hModel)
	local ent = T.refEntity_t()
	local angles = Q.vec3(0, 0, 0)
	local axis = { [0] = Q.vec3(0, 0, 0), Q.vec3(0, 0, 0), Q.vec3(0, 0, 0) }

	Q.VectorCopy(cent.lerpAngles, angles)
	angles[C.PITCH] = 0
	angles[C.ROLL] = 0
	Q.AnglesToAxis(angles, axis)

	Q.VectorMA(cent.lerpOrigin, -16, axis[0], ent.origin)
	ent.origin[2] += 16
	angles[C.YAW] += 90
	Q.AnglesToAxis(angles, ent.axis)

	ent.hModel = hModel
	trap.R_AddRefEntityToScene(ent)
end

function G.CG_PlayerFlag(cent, hSkin, torso)
	local media = G.cgs.media
	local pole = T.refEntity_t()
	local flag = T.refEntity_t()
	local angles = Q.vec3(0, 0, 0)
	local dir = Q.vec3(0, 0, 0)
	local legsAnim, flagAnim
	local updateangles
	local angle, d

	-- show the flag pole model
	pole.hModel = media.flagPoleModel
	Q.VectorCopy(torso.lightingOrigin, pole.lightingOrigin)
	pole.shadowPlane = torso.shadowPlane
	pole.renderfx = torso.renderfx
	G.CG_PositionEntityOnTag(pole, torso, torso.hModel, "tag_flag")
	trap.R_AddRefEntityToScene(pole)

	-- show the flag model
	flag.hModel = media.flagFlapModel
	flag.customSkin = hSkin
	Q.VectorCopy(torso.lightingOrigin, flag.lightingOrigin)
	flag.shadowPlane = torso.shadowPlane
	flag.renderfx = torso.renderfx

	Q.VectorClear(angles)

	updateangles = false
	legsAnim = band(cent.currentState.legsAnim, ANIM_MASK)
	if legsAnim == C.LEGS_IDLE or legsAnim == C.LEGS_IDLECR then
		flagAnim = C.FLAG_STAND
	elseif legsAnim == C.LEGS_WALK or legsAnim == C.LEGS_WALKCR then
		flagAnim = C.FLAG_STAND
		updateangles = true
	else
		flagAnim = C.FLAG_RUN
		updateangles = true
	end

	if updateangles then
		Q.VectorCopy(cent.currentState.pos.trDelta, dir)
		-- add gravity
		dir[2] += 100
		Q.VectorNormalize(dir)
		d = Q.DotProduct(pole.axis[2], dir)
		-- if there is anough movement orthogonal to the flag pole
		if math.abs(d) < 0.9 then
			d = Q.DotProduct(pole.axis[0], dir)
			if d > 1.0 then
				d = 1.0
			elseif d < -1.0 then
				d = -1.0
			end
			angle = math.acos(d)

			d = Q.DotProduct(pole.axis[1], dir)
			if d < 0 then
				angles[C.YAW] = 360 - angle * 180 / math.pi
			else
				angles[C.YAW] = angle * 180 / math.pi
			end
			if angles[C.YAW] < 0 then
				angles[C.YAW] += 360
			end
			if angles[C.YAW] > 360 then
				angles[C.YAW] -= 360
			end

			-- change the yaw angle
			cent.pe.flag.yawAngle, cent.pe.flag.yawing = G.CG_SwingAngles(angles[C.YAW], 25, 90, 0.15, cent.pe.flag.yawAngle, cent.pe.flag.yawing)
		end
	end

	-- set the yaw angle
	angles[C.YAW] = cent.pe.flag.yawAngle
	-- lerp the flag animation frames
	local ci = G.cgs.clientinfo[cent.currentState.clientNum]
	G.CG_RunLerpFrame(ci, cent.pe.flag, flagAnim, 1)
	flag.oldframe = cent.pe.flag.oldFrame
	flag.frame = cent.pe.flag.frame
	flag.backlerp = cent.pe.flag.backlerp

	Q.AnglesToAxis(angles, flag.axis)
	G.CG_PositionRotatedEntityOnTag(flag, pole, pole.hModel, "tag_flag")

	trap.R_AddRefEntityToScene(flag)
end

function G.CG_PlayerTokens(cent, renderfx)
	local cg = G.cg
	local tokens, angle
	local dir = Q.vec3(0, 0, 0)
	local origin = Q.vec3(0, 0, 0)
	local trail = cg.skulltrails[cent.currentState.number]
	tokens = cent.currentState.generic1
	if tokens == 0 then
		trail.numpositions = 0
		return
	end

	if tokens > C.MAX_SKULLTRAIL then
		tokens = C.MAX_SKULLTRAIL
	end

	-- add skulls if there are more than last time
	for _ = 0, tokens - trail.numpositions - 1 do
		for j = trail.numpositions, 1, -1 do
			Q.VectorCopy(trail.positions[j - 1], trail.positions[j])
		end
		Q.VectorCopy(cent.lerpOrigin, trail.positions[0])
	end
	trail.numpositions = tokens

	-- move all the skulls along the trail
	Q.VectorCopy(cent.lerpOrigin, origin)
	for i = 0, trail.numpositions - 1 do
		Q.VectorSubtract(trail.positions[i], origin, dir)
		if Q.VectorNormalize(dir) > 30 then
			Q.VectorMA(origin, 30, dir, trail.positions[i])
		end
		Q.VectorCopy(trail.positions[i], origin)
	end

	local ent = T.refEntity_t()
	if G.cgs.clientinfo[cent.currentState.clientNum].team == C.TEAM_BLUE then
		ent.hModel = G.cgs.media.redCubeModel
	else
		ent.hModel = G.cgs.media.blueCubeModel
	end
	ent.renderfx = renderfx

	Q.VectorCopy(cent.lerpOrigin, origin)
	for i = 0, trail.numpositions - 1 do
		Q.VectorSubtract(origin, trail.positions[i], ent.axis[0])
		ent.axis[0][2] = 0
		Q.VectorNormalize(ent.axis[0])
		Q.VectorSet(ent.axis[2], 0, 0, 1)
		Q.CrossProduct(ent.axis[0], ent.axis[2], ent.axis[1])

		Q.VectorCopy(trail.positions[i], ent.origin)
		angle = band(Q.idiv(cg.time + 500 * C.MAX_SKULLTRAIL - 500 * i, 16), 255) * (math.pi * 2) / 255
		ent.origin[2] += math.sin(angle) * 10
		trap.R_AddRefEntityToScene(ent)
		Q.VectorCopy(trail.positions[i], origin)
	end
end

function G.CG_PlayerPowerups(cent, torso)
	local powerups = cent.currentState.powerups
	if powerups == 0 then
		return
	end
	local media = G.cgs.media

	if band(powerups, bit32.lshift(1, C.PW_QUAD)) ~= 0 then
		trap.R_AddLightToScene(cent.lerpOrigin, 200 + band(Q.rand(), 31), 0.2, 0.2, 1)
	end

	if band(powerups, bit32.lshift(1, C.PW_FLIGHT)) ~= 0 then
		trap.S_AddLoopingSound(cent.currentState.number, cent.lerpOrigin, Q.vec3_origin, media.flightSound)
	end

	local ci = G.cgs.clientinfo[cent.currentState.clientNum]
	if band(powerups, bit32.lshift(1, C.PW_REDFLAG)) ~= 0 then
		if ci.newAnims then
			G.CG_PlayerFlag(cent, media.redFlagFlapSkin, torso)
		else
			G.CG_TrailItem(cent, media.redFlagModel)
		end
		trap.R_AddLightToScene(cent.lerpOrigin, 200 + band(Q.rand(), 31), 1.0, 0.2, 0.2)
	end

	if band(powerups, bit32.lshift(1, C.PW_BLUEFLAG)) ~= 0 then
		if ci.newAnims then
			G.CG_PlayerFlag(cent, media.blueFlagFlapSkin, torso)
		else
			G.CG_TrailItem(cent, media.blueFlagModel)
		end
		trap.R_AddLightToScene(cent.lerpOrigin, 200 + band(Q.rand(), 31), 0.2, 0.2, 1.0)
	end

	if band(powerups, bit32.lshift(1, C.PW_NEUTRALFLAG)) ~= 0 then
		if ci.newAnims then
			G.CG_PlayerFlag(cent, media.neutralFlagFlapSkin, torso)
		else
			G.CG_TrailItem(cent, media.neutralFlagModel)
		end
		trap.R_AddLightToScene(cent.lerpOrigin, 200 + band(Q.rand(), 31), 1.0, 1.0, 1.0)
	end

	if band(powerups, bit32.lshift(1, C.PW_HASTE)) ~= 0 then
		G.CG_HasteTrail(cent)
	end
end

function G.CG_PlayerFloatSprite(cent, shader)
	local cg = G.cg
	local rf
	if cent.currentState.number == cg.snap.ps.clientNum and not cg.renderingThirdPerson then
		rf = C.RF_THIRD_PERSON
	else
		rf = 0
	end

	local ent = T.refEntity_t()
	Q.VectorCopy(cent.lerpOrigin, ent.origin)
	ent.origin[2] += 48
	ent.reType = C.RT_SPRITE
	ent.customShader = shader
	ent.radius = 10
	ent.renderfx = rf
	ent.shaderRGBA[0] = 255
	ent.shaderRGBA[1] = 255
	ent.shaderRGBA[2] = 255
	ent.shaderRGBA[3] = 255
	trap.R_AddRefEntityToScene(ent)
end

function G.CG_PlayerSprites(cent)
	local cg = G.cg
	local media = G.cgs.media
	local eFlags = cent.currentState.eFlags

	if band(eFlags, C.EF_CONNECTION) ~= 0 then
		G.CG_PlayerFloatSprite(cent, media.connectionShader)
		return
	end

	if band(eFlags, C.EF_TALK) ~= 0 then
		G.CG_PlayerFloatSprite(cent, media.balloonShader)
		return
	end

	if band(eFlags, C.EF_AWARD_IMPRESSIVE) ~= 0 then
		G.CG_PlayerFloatSprite(cent, media.medalImpressive)
		return
	end

	if band(eFlags, C.EF_AWARD_EXCELLENT) ~= 0 then
		G.CG_PlayerFloatSprite(cent, media.medalExcellent)
		return
	end

	if band(eFlags, C.EF_AWARD_GAUNTLET) ~= 0 then
		G.CG_PlayerFloatSprite(cent, media.medalGauntlet)
		return
	end

	if band(eFlags, C.EF_AWARD_DEFEND) ~= 0 then
		G.CG_PlayerFloatSprite(cent, media.medalDefend)
		return
	end

	if band(eFlags, C.EF_AWARD_ASSIST) ~= 0 then
		G.CG_PlayerFloatSprite(cent, media.medalAssist)
		return
	end

	if band(eFlags, C.EF_AWARD_CAP) ~= 0 then
		G.CG_PlayerFloatSprite(cent, media.medalCapture)
		return
	end

	local team = G.cgs.clientinfo[cent.currentState.clientNum].team
	if band(eFlags, C.EF_DEAD) == 0
		and cg.snap.ps.persistant[C.PERS_TEAM] == team
		and G.cgs.gametype >= C.GT_TEAM and G.cgs.ffa_gt ~= 1 then
		if G.cg_drawFriend.integer ~= 0 then
			G.CG_PlayerFloatSprite(cent, media.friendShader)
		end
		return
	end
end

-- Returns whether a shadow surface was found and the Z of that surface
function G.CG_PlayerShadow(cent)
	local mins = Q.vec3(-15, -15, 0)
	local maxs = Q.vec3(15, 15, 2)
	local end_ = Q.vec3(0, 0, 0)
	local trace = T.trace_t()
	local alpha
	local shadowPlane = 0

	if G.cg_shadows.integer == 0 then
		return false, shadowPlane
	end

	-- no shadows when invisible
	if band(cent.currentState.powerups, bit32.lshift(1, C.PW_INVIS)) ~= 0 then
		return false, shadowPlane
	end

	Q.VectorCopy(cent.lerpOrigin, end_)
	end_[2] -= G.SHADOW_DISTANCE

	trap.CM_BoxTrace(trace, cent.lerpOrigin, end_, mins, maxs, 0, C.MASK_PLAYERSOLID)

	-- no shadow if too high
	if trace.fraction == 1.0 or trace.startsolid or trace.allsolid then
		return false, shadowPlane
	end

	shadowPlane = trace.endpos[2] + 1

	if G.cg_shadows.integer ~= 1 then
		return true, shadowPlane
	end

	-- fade the shadow out with height
	alpha = 1.0 - trace.fraction

	G.CG_ImpactMark(G.cgs.media.shadowMarkShader, trace.endpos, trace.plane.normal,
		cent.pe.legs.yawAngle, alpha, alpha, alpha, 1, false, 24, true)

	return true, shadowPlane
end

function G.CG_PlayerSplash(cent)
	local start = Q.vec3(0, 0, 0)
	local end_ = Q.vec3(0, 0, 0)
	local trace = T.trace_t()
	local contents
	local liquid = bor(C.CONTENTS_WATER, C.CONTENTS_SLIME, C.CONTENTS_LAVA)

	if G.cg_shadows.integer == 0 then
		return
	end

	Q.VectorCopy(cent.lerpOrigin, end_)
	end_[2] -= 24

	contents = G.CG_PointContents(end_, 0)
	if band(contents, liquid) == 0 then
		return
	end

	Q.VectorCopy(cent.lerpOrigin, start)
	start[2] += 32

	contents = G.CG_PointContents(start, 0)
	if band(contents, bor(C.CONTENTS_SOLID, liquid)) ~= 0 then
		return
	end

	trap.CM_BoxTrace(trace, start, end_, nil, nil, 0, liquid)

	if trace.fraction == 1.0 then
		return
	end

	local corners = {
		[0] = { -32, -32, 0, 0 },
		{ -32, 32, 0, 1 },
		{ 32, 32, 1, 1 },
		{ 32, -32, 1, 0 },
	}
	local verts = {}
	for i = 0, 3 do
		local v = T.polyVert_t()
		Q.VectorCopy(trace.endpos, v.xyz)
		v.xyz[0] += corners[i][1]
		v.xyz[1] += corners[i][2]
		v.st[0] = corners[i][3]
		v.st[1] = corners[i][4]
		v.modulate[0] = 255
		v.modulate[1] = 255
		v.modulate[2] = 255
		v.modulate[3] = 255
		verts[i] = v
	end

	trap.R_AddPolyToScene(G.cgs.media.wakeMarkShader, 4, verts)
end

-- Adds a piece with modifications or duplications for powerups
-- Also called by CG_Missile for quad rockets, but nobody can tell...
function G.CG_AddRefEntityWithPowerups(ent, state, team, isMissile)
	local media = G.cgs.media
	local cgs = G.cgs

	if band(state.powerups, bit32.lshift(1, C.PW_INVIS)) ~= 0 then
		if band(cgs.dmflags, C.DF_INVIS) == 0 then
			ent.customShader = media.invisShader
			trap.R_AddRefEntityToScene(ent)
		end
	else
		trap.R_AddRefEntityToScene(ent)
		if not isMissile and band(cgs.dmflags, C.DF_PLAYER_OVERLAY) ~= 0 and band(state.eFlags, C.EF_DEAD) == 0 then
			if team == C.TEAM_RED then
				ent.customShader = media.redOverlay
			elseif team == C.TEAM_BLUE then
				ent.customShader = media.blueOverlay
			else
				ent.customShader = media.neutralOverlay
			end
			trap.R_AddRefEntityToScene(ent)
		end

		if band(state.powerups, bit32.lshift(1, C.PW_QUAD)) ~= 0 then
			if team == C.TEAM_RED then
				ent.customShader = media.redQuadShader
			else
				ent.customShader = media.quadShader
			end
			trap.R_AddRefEntityToScene(ent)
		end
		if band(state.powerups, bit32.lshift(1, C.PW_REGEN)) ~= 0 then
			if math.fmod(Q.idiv(G.cg.time, 100), 10) == 1 then
				ent.customShader = media.regenShader
				trap.R_AddRefEntityToScene(ent)
			end
		end
		if band(state.powerups, bit32.lshift(1, C.PW_BATTLESUIT)) ~= 0 then
			ent.customShader = media.battleSuitShader
			trap.R_AddRefEntityToScene(ent)
		end
	end
end

function G.CG_LightVerts(normal, numVerts, verts)
	local incoming, j
	local ambientLight = Q.vec3(0, 0, 0)
	local lightDir = Q.vec3(0, 0, 0)
	local directedLight = Q.vec3(0, 0, 0)

	trap.R_LightForPoint(verts[0].xyz, ambientLight, directedLight, lightDir)

	for i = 0, numVerts - 1 do
		local mod = verts[i].modulate
		incoming = Q.DotProduct(normal, lightDir)
		if incoming <= 0 then
			mod[0] = ambientLight[0]
			mod[1] = ambientLight[1]
			mod[2] = ambientLight[2]
			mod[3] = 255
		else
			for k = 0, 2 do
				j = Q.int(ambientLight[k] + incoming * directedLight[k])
				if j > 255 then
					j = 255
				end
				mod[k] = j
			end
			mod[3] = 255
		end
	end
	return 1
end

local function addSkull(skull, hModel)
	skull.hModel = hModel
	trap.R_AddRefEntityToScene(skull)
end

function G.CG_Player(cent)
	local cg = G.cg
	local cgs = G.cgs
	local media = cgs.media
	local ci
	local clientNum
	local renderfx
	local shadow, shadowPlane
	local t, c, angle
	local dir = Q.vec3(0, 0, 0)
	local angles = Q.vec3(0, 0, 0)

	-- the client number is stored in clientNum.  It can't be derived
	-- from the entity number, because a single client may have
	-- multiple corpses on the level using the same clientinfo
	clientNum = cent.currentState.clientNum
	if clientNum < 0 or clientNum >= C.MAX_CLIENTS then
		G.CG_Error("Bad clientNum on player entity")
	end
	ci = cgs.clientinfo[clientNum]

	-- it is possible to see corpses from disconnected players that may
	-- not have valid clientinfo
	if not ci.infoValid then
		return
	end

	-- get the player model information
	renderfx = 0
	if cent.currentState.number == cg.snap.ps.clientNum then
		if not cg.renderingThirdPerson then
			renderfx = C.RF_THIRD_PERSON -- only draw in mirrors
		else
			if G.cg_cameraMode.integer ~= 0 then
				return
			end
		end
	end

	-- not in OA: a player with a Roblox avatar is drawn as that (cg_avatars.luau)
	if G.CG_AvatarActive(clientNum) and G.CG_AvatarPlayer(cent, ci, renderfx) then
		return
	end

	local legs = T.refEntity_t()
	local torso = T.refEntity_t()
	local head = T.refEntity_t()

	-- get the rotation information
	G.CG_PlayerAngles(cent, legs.axis, torso.axis, head.axis)

	-- get the animation state (after rotation, to allow feet shuffle)
	legs.oldframe, legs.frame, legs.backlerp, torso.oldframe, torso.frame, torso.backlerp = G.CG_PlayerAnimation(cent)

	-- add the talk baloon or disconnect icon
	G.CG_PlayerSprites(cent)

	-- add the shadow
	shadow, shadowPlane = G.CG_PlayerShadow(cent)

	-- add a water splash if partially in and out of water
	G.CG_PlayerSplash(cent)

	if G.cg_shadows.integer == 3 and shadow then
		renderfx = bor(renderfx, C.RF_SHADOW_PLANE)
	end
	renderfx = bor(renderfx, C.RF_LIGHTING_ORIGIN) -- use the same origin for all
	if cgs.gametype == C.GT_HARVESTER then
		G.CG_PlayerTokens(cent, renderfx)
	end

	-- add the legs
	legs.hModel = ci.legsModel
	legs.customSkin = ci.legsSkin

	Q.VectorCopy(cent.lerpOrigin, legs.origin)
	Q.VectorCopy(cent.lerpOrigin, legs.lightingOrigin)
	legs.shadowPlane = shadowPlane
	legs.renderfx = renderfx
	Q.VectorCopy(legs.origin, legs.oldorigin) -- don't positionally lerp at all

	G.CG_AddRefEntityWithPowerups(legs, cent.currentState, ci.team, false)

	-- if the model failed, allow the default nullmodel to be displayed
	if legs.hModel == 0 then
		return
	end

	-- add the torso
	torso.hModel = ci.torsoModel
	if torso.hModel == 0 then
		return
	end

	torso.customSkin = ci.torsoSkin

	Q.VectorCopy(cent.lerpOrigin, torso.lightingOrigin)

	G.CG_PositionRotatedEntityOnTag(torso, legs, ci.legsModel, "tag_torso")

	torso.shadowPlane = shadowPlane
	torso.renderfx = renderfx

	G.CG_AddRefEntityWithPowerups(torso, cent.currentState, ci.team, false)

	if band(cent.currentState.eFlags, C.EF_KAMIKAZE) ~= 0 then
		local skull = T.refEntity_t()

		Q.VectorCopy(cent.lerpOrigin, skull.lightingOrigin)
		skull.shadowPlane = shadowPlane
		skull.renderfx = renderfx

		if band(cent.currentState.eFlags, C.EF_DEAD) ~= 0 then
			-- one skull bobbing above the dead body
			angle = band(Q.idiv(cg.time, 7), 255) * (math.pi * 2) / 255
			if angle > math.pi * 2 then
				angle -= math.pi * 2
			end
			dir[0] = math.sin(angle) * 20
			dir[1] = math.cos(angle) * 20
			angle = band(Q.idiv(cg.time, 4), 255) * (math.pi * 2) / 255
			dir[2] = 15 + math.sin(angle) * 8
			Q.VectorAdd(torso.origin, dir, skull.origin)

			dir[2] = 0
			Q.VectorCopy(dir, skull.axis[1])
			Q.VectorNormalize(skull.axis[1])
			Q.VectorSet(skull.axis[2], 0, 0, 1)
			Q.CrossProduct(skull.axis[1], skull.axis[2], skull.axis[0])

			addSkull(skull, media.kamikazeHeadModel)
			addSkull(skull, media.kamikazeHeadTrail)
		else
			-- three skulls spinning around the player
			angle = band(Q.idiv(cg.time, 4), 255) * (math.pi * 2) / 255
			dir[0] = math.cos(angle) * 20
			dir[1] = math.sin(angle) * 20
			dir[2] = math.cos(angle) * 20
			Q.VectorAdd(torso.origin, dir, skull.origin)

			angles[0] = math.sin(angle) * 30
			angles[1] = (angle * 180 / math.pi) + 90
			if angles[1] > 360 then
				angles[1] -= 360
			end
			angles[2] = 0
			Q.AnglesToAxis(angles, skull.axis)

			addSkull(skull, media.kamikazeHeadModel)
			-- flip the trail because this skull is spinning in the other direction
			Q.VectorInverse(skull.axis[1])
			addSkull(skull, media.kamikazeHeadTrail)

			angle = band(Q.idiv(cg.time, 4), 255) * (math.pi * 2) / 255 + math.pi
			if angle > math.pi * 2 then
				angle -= math.pi * 2
			end
			dir[0] = math.sin(angle) * 20
			dir[1] = math.cos(angle) * 20
			dir[2] = math.cos(angle) * 20
			Q.VectorAdd(torso.origin, dir, skull.origin)

			angles[0] = math.cos(angle - 0.5 * math.pi) * 30
			angles[1] = 360 - (angle * 180 / math.pi)
			if angles[1] > 360 then
				angles[1] -= 360
			end
			angles[2] = 0
			Q.AnglesToAxis(angles, skull.axis)

			addSkull(skull, media.kamikazeHeadModel)
			addSkull(skull, media.kamikazeHeadTrail)

			angle = band(Q.idiv(cg.time, 3), 255) * (math.pi * 2) / 255 + 0.5 * math.pi
			if angle > math.pi * 2 then
				angle -= math.pi * 2
			end
			dir[0] = math.sin(angle) * 20
			dir[1] = math.cos(angle) * 20
			dir[2] = 0
			Q.VectorAdd(torso.origin, dir, skull.origin)

			Q.VectorCopy(dir, skull.axis[1])
			Q.VectorNormalize(skull.axis[1])
			Q.VectorSet(skull.axis[2], 0, 0, 1)
			Q.CrossProduct(skull.axis[1], skull.axis[2], skull.axis[0])

			addSkull(skull, media.kamikazeHeadModel)
			addSkull(skull, media.kamikazeHeadTrail)
		end
	end

	local powerups = cent.currentState.powerups
	local function addTorsoPowerup(pw, model)
		if band(powerups, bit32.lshift(1, pw)) ~= 0 then
			local powerup = T.copy(torso)
			powerup.hModel = model
			powerup.frame = 0
			powerup.oldframe = 0
			powerup.customSkin = 0
			trap.R_AddRefEntityToScene(powerup)
		end
	end
	addTorsoPowerup(C.PW_GUARD, media.guardPowerupModel)
	addTorsoPowerup(C.PW_SCOUT, media.scoutPowerupModel)
	addTorsoPowerup(C.PW_DOUBLER, media.doublerPowerupModel)
	addTorsoPowerup(C.PW_AMMOREGEN, media.ammoRegenPowerupModel)

	if band(powerups, bit32.lshift(1, C.PW_INVULNERABILITY)) ~= 0 then
		if ci.invulnerabilityStartTime == 0 then
			ci.invulnerabilityStartTime = cg.time
		end
		ci.invulnerabilityStopTime = cg.time
	else
		ci.invulnerabilityStartTime = 0
	end
	if band(powerups, bit32.lshift(1, C.PW_INVULNERABILITY)) ~= 0 or cg.time - ci.invulnerabilityStopTime < 250 then
		local powerup = T.copy(torso)
		powerup.hModel = media.invulnerabilityPowerupModel
		powerup.customSkin = 0
		-- always draw
		powerup.renderfx = band(powerup.renderfx, bit32.bnot(C.RF_THIRD_PERSON))
		Q.VectorCopy(cent.lerpOrigin, powerup.origin)

		if cg.time - ci.invulnerabilityStartTime < 250 then
			c = (cg.time - ci.invulnerabilityStartTime) / 250
		elseif cg.time - ci.invulnerabilityStopTime < 250 then
			c = (250 - (cg.time - ci.invulnerabilityStopTime)) / 250
		else
			c = 1
		end
		Q.VectorSet(powerup.axis[0], c, 0, 0)
		Q.VectorSet(powerup.axis[1], 0, c, 0)
		Q.VectorSet(powerup.axis[2], 0, 0, c)
		trap.R_AddRefEntityToScene(powerup)
	end

	t = cg.time - ci.medkitUsageTime
	if ci.medkitUsageTime ~= 0 and t < 500 then
		local powerup = T.copy(torso)
		powerup.hModel = media.medkitUsageModel
		powerup.customSkin = 0
		-- always draw
		powerup.renderfx = band(powerup.renderfx, bit32.bnot(C.RF_THIRD_PERSON))
		Q.VectorClear(angles)
		Q.AnglesToAxis(angles, powerup.axis)
		Q.VectorCopy(cent.lerpOrigin, powerup.origin)
		powerup.origin[2] += -24 + t * 80 / 500
		if t > 400 then
			c = (t - 1000) * 0xff / 100
			powerup.shaderRGBA[0] = 0xff - c
			powerup.shaderRGBA[1] = 0xff - c
			powerup.shaderRGBA[2] = 0xff - c
			powerup.shaderRGBA[3] = 0xff - c
		else
			powerup.shaderRGBA[0] = 0xff
			powerup.shaderRGBA[1] = 0xff
			powerup.shaderRGBA[2] = 0xff
			powerup.shaderRGBA[3] = 0xff
		end
		trap.R_AddRefEntityToScene(powerup)
	end

	-- add the head
	head.hModel = ci.headModel
	if head.hModel == 0 then
		return
	end
	head.customSkin = ci.headSkin

	Q.VectorCopy(cent.lerpOrigin, head.lightingOrigin)

	G.CG_PositionRotatedEntityOnTag(head, torso, ci.torsoModel, "tag_head")

	head.shadowPlane = shadowPlane
	head.renderfx = renderfx

	G.CG_AddRefEntityWithPowerups(head, cent.currentState, ci.team, false)

	G.CG_BreathPuffs(cent, head)

	G.CG_DustTrail(cent)

	-- add the gun / barrel / flash
	G.CG_AddPlayerWeapon(torso, nil, cent, ci.team)

	-- add powerups floating behind the player
	G.CG_PlayerPowerups(cent, torso)
end

-- A player just came into view or teleported, so reset all animation info
function G.CG_ResetPlayerEntity(cent)
	local cg = G.cg
	cent.errorTime = -99999 -- guarantee no error decay added
	cent.extrapolated = false
	cent.avatar = nil -- not in OA: the Roblox avatar's lerp frames (cg_avatars.luau)

	G.CG_ClearLerpFrame(G.cgs.clientinfo[cent.currentState.clientNum], cent.pe.legs, cent.currentState.legsAnim)
	G.CG_ClearLerpFrame(G.cgs.clientinfo[cent.currentState.clientNum], cent.pe.torso, cent.currentState.torsoAnim)

	BG.BG_EvaluateTrajectory(cent.currentState.pos, cg.time, cent.lerpOrigin)
	BG.BG_EvaluateTrajectory(cent.currentState.apos, cg.time, cent.lerpAngles)

	Q.VectorCopy(cent.lerpOrigin, cent.rawOrigin)
	Q.VectorCopy(cent.lerpAngles, cent.rawAngles)

	T.reset(cent.pe.legs, T.lerpFrame_t)
	cent.pe.legs.yawAngle = cent.rawAngles[C.YAW]
	cent.pe.legs.yawing = false
	cent.pe.legs.pitchAngle = 0
	cent.pe.legs.pitching = false

	T.reset(cent.pe.torso, T.lerpFrame_t)
	cent.pe.torso.yawAngle = cent.rawAngles[C.YAW]
	cent.pe.torso.yawing = false
	cent.pe.torso.pitchAngle = cent.rawAngles[C.PITCH]
	cent.pe.torso.pitching = false

	if G.cg_debugPosition.integer ~= 0 then
		G.CG_Printf(Q.va("%i ResetPlayerEntity yaw=%i\n", cent.currentState.number, Q.int(cent.pe.torso.yawAngle)))
	end
end

return G
