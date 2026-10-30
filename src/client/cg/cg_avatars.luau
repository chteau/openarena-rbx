--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Not a port: players drawn as their Roblox avatar (docs/client-notes.md,
-- "Roblox avatars"). CG_Player hands a player over here when the server
-- built an avatar for them (g_robloxAvatars) and cg_robloxAvatars is on;
-- bots and everyone else keep their OA model. The avatar is visual only:
-- the entity's origin, CG_PlayerAngles and OA's own lerp frames drive it,
-- and the weapon, flags and effects hang off it like they would off the md3.

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local trap = require(script.Parent.Parent.sys.Trap)

local band = bit32.band
local ANIM_MASK = bit32.bnot(C.ANIM_TOGGLEBIT)

-- The avatar animation set follows sarge's animation.cfg, whatever OA
-- model the player picked, so its lerp frames run on that table.
local avatarInfo = nil
local function info()
	if avatarInfo == nil then
		avatarInfo = { animations = trap.R_AvatarAnimations() }
	end
	return avatarInfo
end

function G.CG_AvatarActive(clientNum)
	return G.cg_robloxAvatars.integer ~= 0 and trap.R_AvatarReady(clientNum)
end

-- One half's lerp frame, remembering which animation oldFrame came from
-- (OA lerps across an animation change; the avatar blends two clips there).
local function runHalf(lf, st, newAnimation, speedScale)
	local stepping = G.cg_animSpeed.integer ~= 0 and G.cg.time >= lf.frameTime
	G.CG_RunLerpFrame(info(), lf, newAnimation, speedScale)
	if stepping then
		st.old = st.cur
		st.cur = lf.animation
	end
	return { anim = st.cur, frame = lf.frame, oldAnim = st.old, oldFrame = lf.oldFrame, backlerp = lf.backlerp }
end

local function avatarState(cent)
	local s = cent.avatar
	if s == nil then
		s = { legs = T.lerpFrame_t(), torso = T.lerpFrame_t(), l = {}, t = {} }
		G.CG_ClearLerpFrame(info(), s.legs, cent.currentState.legsAnim)
		G.CG_ClearLerpFrame(info(), s.torso, cent.currentState.torsoAnim)
		s.l.cur, s.l.old = s.legs.animation, s.legs.animation
		s.t.cur, s.t.old = s.torso.animation, s.torso.animation
		cent.avatar = s
	end
	return s
end

-- CG_PlayerAnimation on the avatar's lerp frames
local function avatarAnimation(cent)
	local s = avatarState(cent)
	local speedScale = if band(cent.currentState.powerups, bit32.lshift(1, C.PW_HASTE)) ~= 0 then 1.5 else 1
	local legsAnim = cent.currentState.legsAnim
	-- do the shuffle turn frames locally
	if cent.pe.legs.yawing and band(legsAnim, ANIM_MASK) == C.LEGS_IDLE then
		legsAnim = C.LEGS_TURN
	end
	local legs = runHalf(s.legs, s.l, legsAnim, speedScale)
	local torso = runHalf(s.torso, s.t, cent.currentState.torsoAnim, speedScale)
	return legs, torso, s
end

local function refOnTag(entNum, tag, src)
	local o = T.orientation_t()
	if not trap.R_AvatarTag(entNum, tag, o) then
		return false
	end
	Q.VectorCopy(o.origin, src.origin)
	for i = 0, 2 do
		Q.VectorCopy(o.axis[i], src.axis[i])
	end
	return true
end

-- CG_Player for an avatar; false when the avatar can't be drawn (the OA
-- model is drawn instead). renderfx is CG_Player's (RF_THIRD_PERSON for
-- our own first-person body).
function G.CG_AvatarPlayer(cent, ci, renderfx)
	local cg = G.cg
	local cgs = G.cgs
	local legs = T.refEntity_t()
	local torso = T.refEntity_t()
	local head = T.refEntity_t()

	G.CG_PlayerAngles(cent, legs.axis, torso.axis, head.axis)
	local legsAnim, torsoAnim, s = avatarAnimation(cent)

	local drawn = trap.R_AddAvatarToScene({
		entNum = cent.currentState.number,
		clientNum = cent.currentState.clientNum,
		origin = cent.lerpOrigin,
		legsAxis = legs.axis,
		torsoAxis = torso.axis,
		headAxis = head.axis,
		legs = legsAnim,
		torso = torsoAnim,
		weapon = cent.currentState.weapon,
		renderfx = renderfx,
		team = ci.team,
		powerups = cent.currentState.powerups,
		time = cg.time,
		teamGame = cgs.gametype >= C.GT_TEAM,
		dmflags = cgs.dmflags,
	})
	if not drawn then
		return false
	end

	G.CG_PlayerSprites(cent)
	local shadow, shadowPlane = G.CG_PlayerShadow(cent)
	G.CG_PlayerSplash(cent)
	if G.cg_shadows.integer == 3 and shadow then
		renderfx = bit32.bor(renderfx, C.RF_SHADOW_PLANE)
	end
	renderfx = bit32.bor(renderfx, C.RF_LIGHTING_ORIGIN)
	if cgs.gametype == C.GT_HARVESTER then
		G.CG_PlayerTokens(cent, renderfx)
	end

	-- the md3 parts' stand-ins: what flags, breath and powerups attach to
	for _, e in { torso, head } do
		Q.VectorCopy(cent.lerpOrigin, e.lightingOrigin)
		e.shadowPlane = shadowPlane
		e.renderfx = renderfx
	end
	refOnTag(cent.currentState.number, "tag_torso", torso)
	refOnTag(cent.currentState.number, "tag_head", head)
	torso.hModel = ci.torsoModel
	torso.oldframe, torso.frame, torso.backlerp = s.torso.oldFrame, s.torso.frame, s.torso.backlerp

	G.CG_BreathPuffs(cent, head)
	G.CG_DustTrail(cent)

	-- the gun in the right hand: the hand's grip stands in for tag_weapon
	local grip = T.refEntity_t()
	if refOnTag(cent.currentState.number, "tag_weapon", grip) then
		Q.VectorCopy(cent.lerpOrigin, grip.lightingOrigin)
		grip.shadowPlane = shadowPlane
		grip.renderfx = renderfx
		grip.avatarGrip = true
		G.CG_AddPlayerWeapon(grip, nil, cent, ci.team)
	end

	G.CG_PlayerPowerups(cent, torso)
	return true
end

-- The status bar / scoreboard face of an avatar player: their headshot.
function G.CG_AvatarHeadShader(clientNum)
	if not G.CG_AvatarActive(clientNum) then
		return 0
	end
	return trap.R_AvatarHeadShader(clientNum)
end

return G
