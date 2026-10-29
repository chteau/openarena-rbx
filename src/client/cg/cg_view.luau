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
-- Luau port of code/cgame/cg_view.c (OpenArena gamecode).
-- cg_view.c -- setup all the parameters (position, angle, etc)
-- for a 3D rendering

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)

--[[
Model testing: "testmodel <modelname>" or "testgun <modelname>".
Testmodel creates a fake entity 100 units in front of the current view
position, directly facing the viewer. Testgun makes the model follow the
player and suppresses the real view weapon model.
]]

-- Creates an entity in front of the current position, which can then be moved around
function G.CG_TestModel_f()
	local cg = G.cg
	local angles = Q.vec3(0, 0, 0)

	cg.testGun = false
	T.reset(cg.testModelEntity, T.refEntity_t)
	if trap.Argc() < 2 then
		return
	end

	cg.testModelName = string.sub(G.CG_Argv(1), 1, C.MAX_QPATH - 1)
	cg.testModelEntity.hModel = trap.R_RegisterModel(cg.testModelName)

	if trap.Argc() == 3 then
		cg.testModelEntity.backlerp = tonumber(G.CG_Argv(2)) or 0
		cg.testModelEntity.frame = 1
		cg.testModelEntity.oldframe = 0
	end
	if cg.testModelEntity.hModel == 0 then
		G.CG_Printf("Can't register model\n")
		return
	end

	Q.VectorMA(cg.refdef.vieworg, 100, cg.refdef.viewaxis[0], cg.testModelEntity.origin)

	angles[C.PITCH] = 0
	angles[C.YAW] = 180 + cg.refdefViewAngles[1]
	angles[C.ROLL] = 0

	Q.AnglesToAxis(angles, cg.testModelEntity.axis)
end

-- Replaces the current view weapon with the given model
function G.CG_TestGun_f()
	G.CG_TestModel_f()

	if G.cg.testModelEntity.hModel == 0 then
		return
	end

	G.cg.testGun = true
	G.cg.testModelEntity.renderfx = bit32.bor(C.RF_MINLIGHT, C.RF_DEPTHHACK, C.RF_FIRST_PERSON)
end

function G.CG_TestModelNextFrame_f()
	local e = G.cg.testModelEntity
	e.frame += 1
	G.CG_Printf(Q.va("frame %i\n", e.frame))
end

function G.CG_TestModelPrevFrame_f()
	local e = G.cg.testModelEntity
	e.frame -= 1
	if e.frame < 0 then
		e.frame = 0
	end
	G.CG_Printf(Q.va("frame %i\n", e.frame))
end

function G.CG_TestModelNextSkin_f()
	local e = G.cg.testModelEntity
	e.skinNum += 1
	G.CG_Printf(Q.va("skin %i\n", e.skinNum))
end

function G.CG_TestModelPrevSkin_f()
	local e = G.cg.testModelEntity
	e.skinNum -= 1
	if e.skinNum < 0 then
		e.skinNum = 0
	end
	G.CG_Printf(Q.va("skin %i\n", e.skinNum))
end

local function CG_AddTestModel()
	local cg = G.cg
	local ent = cg.testModelEntity

	-- re-register the model, because the level may have changed
	ent.hModel = trap.R_RegisterModel(cg.testModelName)
	if ent.hModel == 0 then
		G.CG_Printf("Can't register model\n")
		return
	end

	-- if testing a gun, set the origin reletive to the view origin
	if cg.testGun then
		local va = cg.refdef.viewaxis
		Q.VectorCopy(cg.refdef.vieworg, ent.origin)
		Q.VectorCopy(va[0], ent.axis[0])
		Q.VectorCopy(va[1], ent.axis[1])
		Q.VectorCopy(va[2], ent.axis[2])

		-- allow the position to be adjusted
		for i = 0, 2 do
			ent.origin[i] += va[0][i] * G.cg_gun_x.value
			ent.origin[i] += va[1][i] * G.cg_gun_y.value
			ent.origin[i] += va[2][i] * G.cg_gun_z.value
		end
	end

	trap.R_AddRefEntityToScene(ent)
end

--============================================================================

-- Sets the coordinates of the rendered window
local function CG_CalcVrect()
	local cg = G.cg
	local cgs = G.cgs
	local size

	-- the intermission should allways be full screen
	if cg.snap.ps.pm_type == C.PM_INTERMISSION then
		size = 100
	else
		-- bound normal viewsize
		if G.cg_viewsize.integer < 30 then
			trap.Cvar_Set("cg_viewsize", "30")
			size = 30
		elseif G.cg_viewsize.integer > 120 then
			trap.Cvar_Set("cg_viewsize", "120")
			size = 120
		else
			size = G.cg_viewsize.integer
		end
	end

	local size2 = size
	if size > 100 then
		size = 100
	end
	local notOne = bit32.bnot(1)
	cg.refdef.width = bit32.band(Q.idiv(cgs.glconfig.vidWidth * size, 100), notOne)
	cg.refdef.height = bit32.band(Q.idiv(cgs.glconfig.vidHeight * size, 100), notOne)

	cg.refdef.x = Q.idiv(cgs.glconfig.vidWidth - cg.refdef.width, 2)
	cg.refdef.y = Q.idiv(cgs.glconfig.vidHeight - cg.refdef.height, 2)

	-- leilei - nudge
	if G.cg_viewnudge.integer ~= 0 then
		local nudged = 0

		if size2 < 110 then
			nudged = 48
		elseif size2 < 120 then
			nudged = 24
		end

		nudged = Q.int(nudged * (cgs.glconfig.vidHeight / 480.0))
		cg.refdef.y = Q.idiv(cgs.glconfig.vidHeight - cg.refdef.height, 2) - nudged
	end
end

--==============================================================================

local FOCUS_DISTANCE = 512
local function CG_OffsetThirdPersonView()
	local cg = G.cg
	local cgs = G.cgs
	local forward = Q.vec3(0, 0, 0)
	local right = Q.vec3(0, 0, 0)
	local up = Q.vec3(0, 0, 0)
	local view = Q.vec3(0, 0, 0)
	local focusAngles = Q.vec3(0, 0, 0)
	local focusPoint = Q.vec3(0, 0, 0)
	local focusDist
	local forwardScale, sideScale

	local range = G.cg_thirdPersonRange.value
	local pps = cg.predictedPlayerState

	cg.refdef.vieworg[2] += pps.viewheight

	Q.VectorCopy(cg.refdefViewAngles, focusAngles)

	-- if dead, look at killer
	if
		pps.stats[C.STAT_HEALTH] <= 0
		and (cgs.gametype ~= C.GT_ELIMINATION and cgs.gametype ~= C.GT_CTF_ELIMINATION and cgs.gametype ~= C.GT_LMS)
	then
		focusAngles[C.YAW] = pps.stats[C.STAT_DEAD_YAW]
		cg.refdefViewAngles[C.YAW] = pps.stats[C.STAT_DEAD_YAW]
	end

	if G.cg_deathcam.integer == 2 and pps.stats[C.STAT_HEALTH] <= 0 then -- leilei - deathcam
		range = 100
	end

	if G.cg_cameramode.integer ~= 0 and pps.stats[C.STAT_HEALTH] > 0 then
		-- leilei this mode is off to the player's right
		-- and should look towards a 3d crosshair
		Q.AngleVectors(focusAngles, forward, nil, nil)
		Q.VectorMA(cg.refdef.vieworg, FOCUS_DISTANCE, forward, focusPoint)
		Q.VectorCopy(cg.refdef.vieworg, view)

		view[2] += 3

		cg.refdefViewAngles[C.PITCH] *= 0.5

		Q.AngleVectors(focusAngles, forward, nil, nil)
		Q.VectorMA(cg.refdef.vieworg, FOCUS_DISTANCE, forward, focusPoint)
		Q.VectorCopy(cg.refdef.vieworg, view)

		Q.AngleVectors(cg.refdefViewAngles, forward, right, up)

		forwardScale = math.cos(0 / 180 * math.pi)
		sideScale = math.sin(0 / 180 * math.pi) - 0.465
		Q.VectorMA(view, -range * forwardScale, forward, view)
		Q.VectorMA(view, -range * sideScale, right, view)

		Q.VectorCopy(view, cg.refdef.vieworg)

		-- select pitch to look at focus point from vieword
		Q.VectorSubtract(focusPoint, cg.refdef.vieworg, focusPoint)
		focusDist = math.sqrt(focusPoint[0] * focusPoint[0] + focusPoint[1] * focusPoint[1])
		if focusDist < 1 then
			focusDist = 1 -- should never happen
		end
		cg.refdefViewAngles[C.PITCH] = -180 / math.pi * math.atan2(focusPoint[2], focusDist)

		-- leilei - make it look to a 3d cursor
		do
			local forward2 = Q.vec3(0, 0, 0)
			local up2 = Q.vec3(0, 0, 0)

			cg.refdef.vieworg[2] -= 24
			Q.AngleVectors(cg.refdefViewAngles, forward2, nil, up2)
			Q.VectorMA(cg.refdef.vieworg, 1, forward2, cg.refdef.vieworg)
			Q.VectorMA(cg.refdef.vieworg, 24, up2, cg.refdef.vieworg)
		end
	else
		if focusAngles[C.PITCH] > 45 then
			focusAngles[C.PITCH] = 45 -- don't go too far overhead
		end
		Q.AngleVectors(focusAngles, forward, nil, nil)

		Q.VectorMA(cg.refdef.vieworg, FOCUS_DISTANCE, forward, focusPoint)

		Q.VectorCopy(cg.refdef.vieworg, view)

		view[2] += 8

		cg.refdefViewAngles[C.PITCH] *= 0.5

		Q.AngleVectors(cg.refdefViewAngles, forward, right, up)

		forwardScale = math.cos(G.cg_thirdPersonAngle.value / 180 * math.pi)
		sideScale = math.sin(G.cg_thirdPersonAngle.value / 180 * math.pi)
		Q.VectorMA(view, -range * forwardScale, forward, view)
		Q.VectorMA(view, -range * sideScale, right, view)

		Q.VectorCopy(view, cg.refdef.vieworg)

		-- select pitch to look at focus point from vieword
		Q.VectorSubtract(focusPoint, cg.refdef.vieworg, focusPoint)
		focusDist = math.sqrt(focusPoint[0] * focusPoint[0] + focusPoint[1] * focusPoint[1])
		if focusDist < 1 then
			focusDist = 1 -- should never happen
		end
		cg.refdefViewAngles[C.PITCH] = -180 / math.pi * math.atan2(focusPoint[2], focusDist)
		cg.refdefViewAngles[C.YAW] -= G.cg_thirdPersonAngle.value
	end
end

-- smooth out stair climbing
local function CG_StepOffset()
	local cg = G.cg
	local timeDelta = cg.time - cg.stepTime
	if timeDelta < C.STEP_TIME then
		cg.refdef.vieworg[2] -= cg.stepChange * (C.STEP_TIME - timeDelta) / C.STEP_TIME
	end
end

local function CG_OffsetFirstPersonView()
	local cg = G.cg
	local cgs = G.cgs
	local bob, ratio, delta, speed, f
	local predictedVelocity = Q.vec3(0, 0, 0)
	local timeDelta

	if cg.snap.ps.pm_type == C.PM_INTERMISSION then
		return
	end

	local origin = cg.refdef.vieworg
	local angles = cg.refdefViewAngles

	-- if dead, fix the angle and don't add any kick
	if cg.snap.ps.stats[C.STAT_HEALTH] <= 0 then
		angles[C.ROLL] = 40
		angles[C.PITCH] = -15
		angles[C.YAW] = cg.snap.ps.stats[C.STAT_DEAD_YAW]
		origin[2] += cg.predictedPlayerState.viewheight
		return
	end

	-- add angles based on weapon kick
	Q.VectorAdd(angles, cg.kick_angles, angles)

	-- add angles based on damage kick
	if
		cg.damageTime ~= 0
		and cgs.gametype ~= C.GT_ELIMINATION
		and cgs.gametype ~= C.GT_CTF_ELIMINATION
		and cgs.gametype ~= C.GT_LMS
	then
		ratio = cg.time - cg.damageTime
		if ratio < C.DAMAGE_DEFLECT_TIME then
			ratio /= C.DAMAGE_DEFLECT_TIME
			angles[C.PITCH] += ratio * cg.v_dmg_pitch * G.cg_kickScale.value
			angles[C.ROLL] += ratio * cg.v_dmg_roll * G.cg_kickScale.value
		else
			ratio = 1.0 - (ratio - C.DAMAGE_DEFLECT_TIME) / C.DAMAGE_RETURN_TIME
			if ratio > 0 then
				angles[C.PITCH] += ratio * cg.v_dmg_pitch * G.cg_kickScale.value
				angles[C.ROLL] += ratio * cg.v_dmg_roll * G.cg_kickScale.value
			end
		end
	end

	-- add angles based on velocity
	Q.VectorCopy(cg.predictedPlayerState.velocity, predictedVelocity)

	delta = Q.DotProduct(predictedVelocity, cg.refdef.viewaxis[0])
	angles[C.PITCH] += delta * G.cg_runpitch.value

	delta = Q.DotProduct(predictedVelocity, cg.refdef.viewaxis[1])
	angles[C.ROLL] -= delta * G.cg_runroll.value

	-- add angles based on bob
	local bobMode = G.cg_bob.integer
	if bobMode == 6 then -- leilei - sweeney bob
		local forward = Q.vec3(0, 0, 0)
		local right = Q.vec3(0, 0, 0)
		local up = Q.vec3(0, 0, 0)
		speed = cg.xyspeed
		if speed > 320 then
			speed = 320
		end
		delta = cg.bobfracsin * 0.006 * speed
		if bit32.band(cg.bobcycle, 1) ~= 0 then
			delta = -delta
		end
		Q.AngleVectors(angles, forward, right, up)
		Q.VectorMA(origin, delta, right, origin)
	elseif bobMode ~= 0 then
		-- make sure the bob is visible even at low speeds
		speed = if cg.xyspeed > 200 then cg.xyspeed else 200

		delta = cg.bobfracsin * G.cg_bobpitch.value * speed
		if bit32.band(cg.predictedPlayerState.pm_flags, C.PMF_DUCKED) ~= 0 then
			delta *= 3 -- crouching
		end
		-- leilei - no pitch for 3 or 4
		if bobMode == 1 or bobMode == 2 then
			angles[C.PITCH] += delta
		end
		delta = cg.bobfracsin * G.cg_bobroll.value * speed
		if bit32.band(cg.predictedPlayerState.pm_flags, C.PMF_DUCKED) ~= 0 then
			delta *= 3 -- crouching accentuates roll
		end
		if bit32.band(cg.bobcycle, 1) ~= 0 then
			delta = -delta
		end
		-- leilei - no roll for 2 or 4
		if bobMode == 1 or bobMode == 3 or bobMode == 5 then
			angles[C.ROLL] += delta
		end
	end

	--===================================

	-- add view height
	origin[2] += cg.predictedPlayerState.viewheight

	-- smooth out duck height changes
	timeDelta = cg.time - cg.duckTime
	if timeDelta < C.DUCK_TIME then
		cg.refdef.vieworg[2] -= cg.duckChange * (C.DUCK_TIME - timeDelta) / C.DUCK_TIME
	end

	if bobMode ~= 0 then
		-- add bob height
		bob = cg.bobfracsin * cg.xyspeed * G.cg_bobup.value
		if bob > 6 then
			bob = 6
		end
		origin[2] += bob
	end

	-- add fall height
	delta = cg.time - cg.landTime
	if delta < C.LAND_DEFLECT_TIME then
		f = delta / C.LAND_DEFLECT_TIME
		cg.refdef.vieworg[2] += cg.landChange * f
	elseif delta < C.LAND_DEFLECT_TIME + C.LAND_RETURN_TIME then
		delta -= C.LAND_DEFLECT_TIME
		f = 1.0 - (delta / C.LAND_RETURN_TIME)
		cg.refdef.vieworg[2] += cg.landChange * f
	end

	-- add step offset
	CG_StepOffset()

	-- add kick offset
	Q.VectorAdd(origin, cg.kick_origin, origin)
end

--======================================================================

function G.CG_ZoomDown_f()
	if G.cg.zoomed then
		return
	end
	G.cg.zoomed = true
	G.cg.zoomTime = G.cg.time
end

function G.CG_ZoomUp_f()
	if not G.cg.zoomed then
		return
	end
	G.cg.zoomed = false
	G.cg.zoomTime = G.cg.time
end

-- Fixed fov at intermissions, otherwise account for fov variable and zooms.
local WAVE_AMPLITUDE = 1
local WAVE_FREQUENCY = 0.4

local function CG_CalcFov(): number
	local cg = G.cg
	local cgs = G.cgs
	local fov_x, fov_y
	local zoomFov
	local f
	local inwater

	if cg.predictedPlayerState.pm_type == C.PM_INTERMISSION then
		-- if in intermission, use a fixed value
		fov_x = 90
	else
		-- user selectable
		if bit32.band(cgs.dmflags, C.DF_FIXED_FOV) ~= 0 then
			-- dmflag to prevent wide fov for all clients
			fov_x = 90
		else
			fov_x = G.cg_fov.value
			if fov_x < 1 then
				fov_x = 1
			elseif fov_x > 160 then
				fov_x = 160
			end
			if bit32.band(cgs.videoflags, C.VF_LOCK_CVARS_BASIC) ~= 0 and fov_x > 140 then
				fov_x = 140
			end
		end

		if bit32.band(cgs.dmflags, C.DF_FIXED_FOV) ~= 0 then
			-- dmflag to prevent wide fov for all clients
			zoomFov = 22.5
		else
			-- account for zooms
			zoomFov = G.cg_zoomFov.value
			if zoomFov < 1 then
				zoomFov = 1
			elseif zoomFov > 160 then
				zoomFov = 160
			end

			if bit32.band(cgs.videoflags, C.VF_LOCK_CVARS_BASIC) ~= 0 and zoomFov > 140 then
				zoomFov = 140
			end
		end

		if cg.zoomed then
			f = (cg.time - cg.zoomTime) / C.ZOOM_TIME
			if f > 1.0 then
				fov_x = zoomFov
			else
				fov_x = fov_x + f * (zoomFov - fov_x)
			end
		else
			f = (cg.time - cg.zoomTime) / C.ZOOM_TIME
			if f <= 1.0 then
				fov_x = zoomFov + f * (fov_x - zoomFov)
			end
		end
	end

	if G.cg_cameramode.integer == 1 and G.cg_thirdPerson.integer ~= 0 then
		-- fov scaling for the modern third person view
		fov_x = fov_x * 0.93 * (cg.xyspeed * 0.0006 + 1)
	end

	local x = cg.refdef.width / math.tan(fov_x / 360 * math.pi)
	fov_y = math.atan2(cg.refdef.height, x)
	fov_y = fov_y * 360 / math.pi

	-- warp if underwater
	local contents = G.CG_PointContents(cg.refdef.vieworg, -1)
	if bit32.band(contents, bit32.bor(C.CONTENTS_WATER, C.CONTENTS_SLIME, C.CONTENTS_LAVA)) ~= 0 then
		local phase = cg.time / 1000.0 * WAVE_FREQUENCY * math.pi * 2
		local v = WAVE_AMPLITUDE * math.sin(phase)
		fov_x += v
		fov_y -= v
		inwater = 1
	else
		inwater = 0
	end

	-- set it
	cg.refdef.fov_x = fov_x
	cg.refdef.fov_y = fov_y

	if not cg.zoomed then
		cg.zoomSensitivity = 1
	else
		cg.zoomSensitivity = cg.refdef.fov_y / 75.0
	end

	return inwater
end

local function CG_DamageBlendBlob()
	local cg = G.cg
	local cgs = G.cgs

	if cg.damageValue == 0 then
		return
	end

	if cg.cameraMode then
		return
	end

	-- ragePro systems can't fade blends, so don't obscure the screen
	if cgs.glconfig.hardwareType == C.GLHW_RAGEPRO then
		return
	end

	local maxTime = C.DAMAGE_TIME
	local t = cg.time - cg.damageTime
	if t <= 0 or t >= maxTime then
		return
	end

	local ent = T.refEntity_t()
	ent.reType = C.RT_SPRITE
	ent.renderfx = C.RF_FIRST_PERSON

	Q.VectorMA(cg.refdef.vieworg, 8, cg.refdef.viewaxis[0], ent.origin)
	Q.VectorMA(ent.origin, cg.damageX * -8, cg.refdef.viewaxis[1], ent.origin)
	Q.VectorMA(ent.origin, cg.damageY * 8, cg.refdef.viewaxis[2], ent.origin)

	ent.radius = cg.damageValue * 3
	ent.customShader = cgs.media.viewBloodShader
	ent.shaderRGBA[0] = 255
	ent.shaderRGBA[1] = 255
	ent.shaderRGBA[2] = 255
	ent.shaderRGBA[3] = Q.int(200 * (1.0 - (t / maxTime)))
	trap.R_AddRefEntityToScene(ent)
end

-- Sets cg.refdef view values
local function CG_CalcViewValues(): number
	local cg = G.cg

	T.reset(cg.refdef, T.refdef_t)

	-- calculate size of 3D view
	CG_CalcVrect()

	local ps = cg.predictedPlayerState

	-- intermission view
	if ps.pm_type == C.PM_INTERMISSION then
		Q.VectorCopy(ps.origin, cg.refdef.vieworg)
		Q.VectorCopy(ps.viewangles, cg.refdefViewAngles)
		Q.AnglesToAxis(cg.refdefViewAngles, cg.refdef.viewaxis)
		return CG_CalcFov()
	end

	local bc = ps.bobCycle
	cg.bobcycle = bit32.rshift(bit32.band(bc, 128), 7)
	cg.bobfracsin = math.abs(math.sin(bit32.band(bc, 127) / 127.0 * math.pi))

	cg.bobfraccos = math.abs(math.cos(bit32.band(bc, 127) / 127.0 * math.pi))
	cg.bobfracsin2 = math.abs(math.sin(bit32.band(bc, 127) / 127.0 * math.pi))

	cg.xyspeed = math.sqrt(ps.velocity[0] * ps.velocity[0] + ps.velocity[1] * ps.velocity[1])

	cg.bobcycle2 = ps.bobCycle -- leilei - copy the bobcycle so we can use it directly elsewhere

	Q.VectorCopy(ps.origin, cg.refdef.vieworg)
	Q.VectorCopy(ps.viewangles, cg.refdefViewAngles)

	if G.cg_cameraOrbit.integer ~= 0 then
		if cg.time > cg.nextOrbitTime then
			cg.nextOrbitTime = cg.time + G.cg_cameraOrbitDelay.integer
			G.cg_thirdPersonAngle.value += G.cg_cameraOrbit.value
		end
	end
	-- add error decay
	if G.cg_errorDecay.value > 0 then
		local t = cg.time - cg.predictedErrorTime
		local f = (G.cg_errorDecay.value - t) / G.cg_errorDecay.value
		if f > 0 and f < 1 then
			Q.VectorMA(cg.refdef.vieworg, f, cg.predictedError, cg.refdef.vieworg)
		else
			cg.predictedErrorTime = 0
		end
	end

	if cg.renderingThirdPerson then
		-- back away from character
		CG_OffsetThirdPersonView()
	else
		-- offset for local bobbing and kicks
		CG_OffsetFirstPersonView()
	end

	-- leilei - View-from-the-model-eyes feature, aka "fullbody awareness" lol
	if G.cg_cameraEyes.integer ~= 0 and not cg.renderingThirdPerson then
		local forward = Q.vec3(0, 0, 0)
		local up = Q.vec3(0, 0, 0)
		local headang = G.headang
		local headpos = G.headpos
		cg.refdefViewAngles[C.ROLL] = headang[C.ROLL]
		cg.refdefViewAngles[C.PITCH] = headang[C.PITCH]
		cg.refdefViewAngles[C.YAW] = headang[C.YAW]

		Q.AngleVectors(headang, forward, nil, up)
		if G.cg_cameraEyes.integer == 2 then
			Q.VectorMA(headpos, 0, forward, headpos)
			Q.VectorMA(headpos, 4, up, headpos)
		else
			Q.VectorMA(headpos, G.cg_cameraEyes_Fwd.value, forward, headpos)
			Q.VectorMA(headpos, G.cg_cameraEyes_Up.value, up, headpos)
		end

		cg.refdef.vieworg[0] = ps.origin[0] + headpos[0]
		cg.refdef.vieworg[1] = ps.origin[1] + headpos[1]
		cg.refdef.vieworg[2] = ps.origin[2] + headpos[2]
	end

	-- position eye reletive to origin
	Q.AnglesToAxis(cg.refdefViewAngles, cg.refdef.viewaxis)

	if cg.hyperspace then
		cg.refdef.rdflags = bit32.bor(cg.refdef.rdflags, C.RDF_NOWORLDMODEL, C.RDF_HYPERSPACE)
	end

	-- field of view
	return CG_CalcFov()
end

local function CG_PowerupTimerSounds()
	local cg = G.cg

	-- powerup timers going away
	for i = 0, C.MAX_POWERUPS - 1 do
		local t = cg.snap.ps.powerups[i]
		if t <= cg.time then
			continue
		end
		if t - cg.time >= C.POWERUP_BLINKS * C.POWERUP_BLINK_TIME then
			continue
		end
		if Q.idiv(t - cg.time, C.POWERUP_BLINK_TIME) ~= Q.idiv(t - cg.oldTime, C.POWERUP_BLINK_TIME) then
			trap.S_StartSound(nil, cg.snap.ps.clientNum, C.CHAN_ITEM, G.cgs.media.wearOffSound)
		end
	end
end

function G.CG_AddBufferedSound(sfx)
	local cg = G.cg
	if sfx == 0 then
		return
	end
	cg.soundBuffer[cg.soundBufferIn] = sfx
	cg.soundBufferIn = (cg.soundBufferIn + 1) % C.MAX_SOUNDBUFFER
	if cg.soundBufferIn == cg.soundBufferOut then
		cg.soundBufferOut += 1
	end
end

local function CG_PlayBufferedSounds()
	local cg = G.cg
	if cg.soundTime < cg.time then
		if cg.soundBufferOut ~= cg.soundBufferIn and (cg.soundBuffer[cg.soundBufferOut] or 0) ~= 0 then
			trap.S_StartLocalSound(cg.soundBuffer[cg.soundBufferOut], C.CHAN_ANNOUNCER)
			cg.soundBuffer[cg.soundBufferOut] = 0
			cg.soundBufferOut = (cg.soundBufferOut + 1) % C.MAX_SOUNDBUFFER
			cg.soundTime = cg.time + 750
		end
	end
end

--=========================================================================

-- Generates and draws a game scene and status information at the given time.
function G.CG_DrawActiveFrame(serverTime, stereoView, demoPlayback)
	local cg = G.cg
	local inwater

	cg.time = serverTime
	cg.demoPlayback = demoPlayback

	-- update cvars
	G.CG_UpdateCvars()

	-- if we are only updating the screen as a loading
	-- pacifier, don't even try to read snapshots
	if cg.infoScreenText ~= "" then
		G.CG_DrawInformation()
		return
	end

	-- any looped sounds will be respecified as entities
	-- are added to the render list
	trap.S_ClearLoopingSounds(false)

	-- clear all the render lists
	trap.R_ClearScene()

	-- set up cg.snap and possibly cg.nextSnap
	G.CG_ProcessSnapshots()

	-- if we haven't received any snapshots yet, all
	-- we can draw is the information screen
	if cg.snap == nil or bit32.band(cg.snap.snapFlags, C.SNAPFLAG_NOT_ACTIVE) ~= 0 then
		G.CG_DrawInformation()
		return
	end

	-- let the client system know what our weapon and zoom settings are
	trap.SetUserCmdValue(cg.weaponSelect, cg.zoomSensitivity)

	-- this counter will be bumped for every valid scene we generate
	cg.clientFrame += 1

	-- update cg.predictedPlayerState
	G.CG_PredictPlayerState()

	-- decide on third person view
	if G.cg_deathcam.integer == 0 then
		-- leilei - allow first person deathcam
		cg.renderingThirdPerson = G.cg_thirdPerson.integer ~= 0
	else
		cg.renderingThirdPerson = cg.snap.ps.persistant[C.PERS_TEAM] ~= C.TEAM_SPECTATOR
			and (G.cg_thirdPerson.integer ~= 0 or cg.snap.ps.stats[C.STAT_HEALTH] <= 0)
	end

	-- build cg.refdef
	inwater = CG_CalcViewValues()

	-- first person blend blobs, done after AnglesToAxis
	if not cg.renderingThirdPerson then
		CG_DamageBlendBlob()
	end

	-- build the render lists
	if not cg.hyperspace then
		G.CG_AddPacketEntities() -- adter calcViewValues, so predicted player state is correct
		G.CG_AddMarks()
		G.CG_AddLocalEntities()
	end
	G.CG_AddViewWeapon(cg.predictedPlayerState)

	-- add buffered sounds
	CG_PlayBufferedSounds()

	-- play buffered voice chats
	G.CG_PlayBufferedVoiceChats()

	-- finish up the rest of the refdef
	if cg.testModelEntity.hModel ~= 0 then
		CG_AddTestModel()
	end
	cg.refdef.time = cg.time
	for i = 0, 31 do
		cg.refdef.areamask[i] = cg.snap.areamask[i]
	end

	-- warning sounds when powerup is wearing off
	CG_PowerupTimerSounds()

	-- update audio positions
	trap.S_Respatialize(cg.snap.ps.clientNum, cg.refdef.vieworg, cg.refdef.viewaxis, inwater)

	-- make sure the lagometerSample and frame timing isn't done twice when in stereo
	if stereoView ~= C.STEREO_RIGHT then
		cg.frametime = cg.time - cg.oldTime
		if cg.frametime < 0 then
			cg.frametime = 0
		end
		cg.oldTime = cg.time
		G.CG_AddLagometerFrameInfo()
	end
	local ts = G.cg_timescale
	local fadeEnd = G.cg_timescaleFadeEnd
	if ts.value ~= fadeEnd.value then
		if ts.value < fadeEnd.value then
			ts.value += G.cg_timescaleFadeSpeed.value * cg.frametime / 1000
			if ts.value > fadeEnd.value then
				ts.value = fadeEnd.value
			end
		else
			ts.value -= G.cg_timescaleFadeSpeed.value * cg.frametime / 1000
			if ts.value < fadeEnd.value then
				ts.value = fadeEnd.value
			end
		end
		if G.cg_timescaleFadeSpeed.value ~= 0 then
			trap.Cvar_Set("timescale", Q.va("%f", ts.value))
		end
	end

	-- actually issue the rendering calls
	G.CG_DrawActive(stereoView)

	if G.cg_stats.integer ~= 0 then
		G.CG_Printf(Q.va("cg.clientFrame:%i\n", cg.clientFrame))
	end
end

return G
