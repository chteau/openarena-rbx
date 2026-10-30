--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Not a port: the maths behind Roblox avatars as OpenArena players
-- (docs/client-notes.md, "Roblox avatars"). No instances here, so lune can
-- test it; sys/Avatar.luau does the Roblox side.
--
--   animations()       OA's animation table for the R15 set (CG_ParseAnimationFile's
--                      shape, from sarge's animation.cfg, which the set follows)
--   tracks(half)       an OA lerp state -> the clip(s), time(s) and weight(s) to play
--   sample(kind, ts)   the pose those tracks give, joint by joint (CFrames)
--   fit(height)        the uniform scale that gives an avatar OA's standing height
--   hipFrame(...)      where the hips go: the bbox origin, legs axis and leg length
--   look(...)          team outline and powerup shells as Highlight settings
local C = require(script.Parent.Parent.q.Consts)
local Legs = require(script.Parent.anims.Legs)
local Torso = require(script.Parent.anims.Torso)

local A = {}

A.STUD = 8
-- the player box's floor below the entity origin (MINS z), in studs
A.FLOOR = -24 / 8
-- sarge standing (idle legs, stand torso, head), sole to crown, in studs
A.HEIGHT = Legs.height / 8
-- how far avatar scales may go: a tiny or giant body still has to read as a
-- player, so it is fitted to the height, but within reason
A.MIN_SCALE, A.MAX_SCALE = 0.2, 5

A.LEGS_JOINTS = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
A.TORSO_JOINTS = { "UpperTorso", "Head", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand" }
-- each joint's parent part in an R15 rig (Pose hierarchy)
A.PARENT = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftLowerArm",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightLowerArm",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftLowerLeg",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightLowerLeg",
}

local function q(t): CFrame
	return CFrame.new(0, 0, 0, t[1], t[2], t[3], t[4])
end

-- clips: "legs:<NAME>" / "torso:<NAME>" -> { name, kind, fps, loop, num, frames }
-- where frames[k + 1] holds CFrames (and the legs' pos as a Vector3)
A.clips = {}
local function addClips(kind: string, data)
	for name, a in data.anims do
		local frames = table.create(#a.frames)
		for k, f in a.frames do
			local out = {}
			for joint, v in f do
				out[joint] = if joint == "pos" then Vector3.new(v[1], v[2], v[3]) elseif type(v) == "number" then v else q(v)
			end
			frames[k] = out
		end
		A.clips[kind .. ":" .. name] =
			{ name = name, kind = kind, fps = a.fps, loop = a.loop, num = a.num, first = a.first, frames = frames }
	end
end
addClips("legs", Legs)
addClips("torso", Torso)

-- CG_ParseAnimationFile on sarge's animation.cfg, plus the clip each
-- animation plays. Reversed / flipflop copies share their source's clip,
-- and the frame numbers are sarge's, so frame - firstFrame indexes the clip.
function A.animations()
	local anims = {}
	local cfg = {}
	for _, data in { Legs, Torso } do
		for name, a in data.anims do
			cfg[name] = a
		end
	end
	local skip = cfg.LEGS_WALKCR.first - cfg.TORSO_GESTURE.first
	local function entry(name: string)
		local a = cfg[name]
		local lerp = math.floor(1000 / a.fps)
		local isLegs = string.sub(name, 1, 5) == "LEGS_"
		return {
			firstFrame = if isLegs then a.first - skip else a.first,
			numFrames = a.num,
			loopFrames = a.loop,
			frameLerp = lerp,
			initialLerp = lerp,
			reversed = false,
			flipflop = false,
			clip = if isLegs then "legs:" .. name elseif string.sub(name, 1, 6) == "TORSO_" then "torso:" .. name else name,
		}
	end
	for name in cfg do
		anims[C[name]] = entry(name)
	end
	local function copy(src, patch)
		local t = table.clone(src)
		for k, v in patch do
			t[k] = v
		end
		return t
	end
	for i = C.TORSO_GETFLAG, C.TORSO_NEGATIVE do
		anims[i] = copy(anims[C.TORSO_GESTURE], { flipflop = i ~= C.TORSO_FOLLOWME })
	end
	anims[C.LEGS_BACKCR] = copy(anims[C.LEGS_WALKCR], { reversed = true })
	anims[C.LEGS_BACKWALK] = copy(anims[C.LEGS_WALK], { reversed = true })
	-- the flag's own animations are not the player's; kept so a lookup of
	-- any animation number finds an entry
	anims[C.FLAG_RUN] = { firstFrame = 0, numFrames = 16, loopFrames = 16, frameLerp = 66, initialLerp = 66, reversed = false, flipflop = false }
	anims[C.FLAG_STAND] = { firstFrame = 16, numFrames = 5, loopFrames = 0, frameLerp = 50, initialLerp = 50, reversed = false, flipflop = false }
	anims[C.FLAG_STAND2RUN] = { firstFrame = 16, numFrames = 5, loopFrames = 1, frameLerp = 66, initialLerp = 66, reversed = true, flipflop = false }
	for i = 0, C.MAX_TOTALANIMATIONS - 1 do
		if anims[i] == nil then
			anims[i] = { firstFrame = 0, numFrames = 0, loopFrames = 0, frameLerp = 0, initialLerp = 0, reversed = false, flipflop = false }
		end
	end
	return anims
end

-- The clip a half ("legs" / "torso") plays for an animation entry: BOTH_*
-- has a legs and a torso clip.
function A.clipName(anim, kind: string): string?
	local c = anim and anim.clip
	if c == nil then
		return nil
	end
	if string.find(c, ":", 1, true) then
		return c
	end
	return kind .. ":" .. c
end

-- An OA lerp state -> what to play. `half` = { anim, frame, oldAnim,
-- oldFrame, backlerp } as cg_avatars.luau tracks them (oldAnim is the
-- animation oldFrame came from). OA lerps the vertices of oldFrame and
-- frame; the clip has one keyframe per md3 frame, so neighbouring frames are
-- one track at an in-between time, anything else (a loop wrapping, a new
-- animation) two tracks weighted backlerp / 1 - backlerp.
function A.tracks(half, kind: string): { { clip: string, time: number, weight: number, slot: number } }
	local out = {}
	local newName = A.clipName(half.anim, kind)
	local oldName = A.clipName(half.oldAnim or half.anim, kind)
	local new = newName and A.clips[newName]
	local old = oldName and A.clips[oldName]
	if new == nil then
		return out
	end
	local function local_(clip, anim, frame): number
		return math.clamp(frame - anim.firstFrame, 0, clip.num - 1)
	end
	local k1 = local_(new, half.anim, half.frame)
	local back = math.clamp(half.backlerp or 0, 0, 1)
	if old == nil or back <= 0 then
		table.insert(out, { clip = newName :: string, time = k1 / new.fps, weight = 1, slot = 1 })
		return out
	end
	local k0 = local_(old, half.oldAnim or half.anim, half.oldFrame)
	if old == new and math.abs(k1 - k0) <= 1 then
		local k = k0 + (k1 - k0) * (1 - back)
		table.insert(out, { clip = newName :: string, time = k / new.fps, weight = 1, slot = 1 })
		return out
	end
	table.insert(out, { clip = oldName :: string, time = k0 / old.fps, weight = back, slot = 1 })
	table.insert(out, { clip = newName :: string, time = k1 / new.fps, weight = 1 - back, slot = if old == new then 2 else 1 })
	return out
end

local function mix(a, b, f: number)
	if b == nil then
		return a
	elseif type(a) == "number" then
		return a + (b - a) * f
	end
	return a:Lerp(b, f)
end

-- one clip's pose at a time (keyframes linearly interpolated, as a
-- KeyframeSequence with Linear poses plays)
local function poseAt(clip, time: number)
	local k = math.clamp(time * clip.fps, 0, clip.num - 1)
	local i = math.floor(k)
	local f = k - i
	local a = clip.frames[i + 1]
	local b = clip.frames[math.min(i + 2, clip.num)]
	if f < 1e-6 or a == b then
		return a
	end
	local out = {}
	for joint, v in a do
		out[joint] = mix(v, b[joint], f)
	end
	return out
end

-- The pose of a set of tracks: joint -> CFrame (legs: plus pos, pelvis, waist).
function A.sample(tracks)
	local pose, total = nil, 0
	for _, t in tracks do
		local clip = A.clips[t.clip]
		if clip and t.weight > 0 then
			local p = poseAt(clip, t.time)
			if pose == nil then
				pose = table.clone(p)
			else
				local f = t.weight / (total + t.weight)
				for joint, v in pose do
					pose[joint] = mix(v, p[joint], f)
				end
				-- a death (no foot clearance) blending in: it decides
				if p.clear == nil then
					pose.clear = nil
				end
			end
			total += t.weight
		end
	end
	return pose
end

-- Uniform scale for an avatar `height` studs tall (sole to crown, at rest).
function A.fit(height: number): number
	if not (height > 0) then
		return 1
	end
	return math.clamp(A.HEIGHT / height, A.MIN_SCALE, A.MAX_SCALE)
end

-- Where the middle of the hips goes: the entity's CFrame (bbox origin, legs
-- axis), the legs pose (pos: hips over the floor in leg lengths, pelvis
-- rotation) and the avatar's own leg length (hip joint to sole, straight).
function A.hipFrame(entity: CFrame, legs, legLength: number): CFrame
	local p = legs.pos
	return entity * CFrame.new(p.X * legLength, A.FLOOR + p.Y * legLength, p.Z * legLength) * legs.pelvis
end

-- A CFrame's rotation part
function A.rotation(cf: CFrame): CFrame
	return cf - cf.Position
end

-- Units.toCFrame of an axis that is relative to another (CG_PlayerAngles'
-- torso and head) maps Quake's axes onto the world's; as a rotation inside
-- the character (forward -Z, left -X) it is that, seen from the identity
-- axis' CFrame.
local BASE = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(0, 1, 0), Vector3.new(-1, 0, 0))
function A.relative(cf: CFrame): CFrame
	return BASE:Inverse() * A.rotation(cf)
end

-- Rigs: { joints = { [Part1 name] = { part0 = name, c0, c1, r0, r0inv } },
-- sizes = { [part name] = Vector3 } }, read off an R15 model's Motor6Ds.
-- The data's rotations are in the character's axes; a joint whose C0 is
-- itself turned gets them turned into its own frame (r0).
function A.rig(joints: { [string]: { part0: string, c0: CFrame, c1: CFrame } }, sizes: { [string]: Vector3 })
	local out = { joints = {}, sizes = sizes }
	for name, j in joints do
		local r0 = A.rotation(j.c0)
		out.joints[name] = { part0 = j.part0, c0 = j.c0, c1 = j.c1, r0 = r0, r0inv = r0:Inverse() }
	end
	return out
end

-- a character-axes rotation as this joint's Transform / C0 offset
function A.inJoint(j, rot: CFrame): CFrame
	return j.r0inv * rot * j.r0
end

-- Forward kinematics: every part's CFrame for the root part's CFrame, the
-- joints' Transforms (character axes) and extra C0 rotations.
function A.fk(rig, root: CFrame, transforms: { [string]: CFrame }, extra: { [string]: CFrame }?)
	local cfs = { HumanoidRootPart = root }
	local function get(name: string): CFrame?
		local cf = cfs[name]
		if cf then
			return cf
		end
		local j = rig.joints[name]
		if j == nil then
			return nil
		end
		local p0 = get(j.part0)
		if p0 == nil then
			return nil
		end
		local c0 = j.c0
		local e = extra and extra[name]
		if e then
			c0 = c0 * A.inJoint(j, e)
		end
		local t = transforms[name]
		cf = p0 * c0 * (if t then A.inJoint(j, t) else CFrame.identity) * j.c1:Inverse()
		cfs[name] = cf
		return cf
	end
	for name in rig.joints do
		get(name)
	end
	return cfs
end

-- the lowest point of the body parts (world Y)
function A.lowest(rig, cfs): number
	local low = math.huge
	for name, cf in cfs do
		local s = rig.sizes[name]
		if s and name ~= "HumanoidRootPart" then
			local h = s / 2
			local y = cf.Y - (math.abs(cf.RightVector.Y) * h.X + math.abs(cf.UpVector.Y) * h.Y + math.abs(cf.LookVector.Y) * h.Z)
			low = math.min(low, y)
		end
	end
	return low
end

-- An avatar at rest, root part at the origin: its height (sole to crown),
-- leg length (hip joints to sole, straight) and the hips' middle relative
-- to the root part.
function A.measure(rig)
	local cfs = A.fk(rig, CFrame.identity, {})
	local head, lf, rf, lt = cfs.Head, cfs.LeftFoot, cfs.RightFoot, cfs.LowerTorso
	local lh, rh = rig.joints.LeftUpperLeg, rig.joints.RightUpperLeg
	if not (head and lf and rf and lt and lh and rh) then
		return nil
	end
	local sole = math.min(lf.Y - rig.sizes.LeftFoot.Y / 2, rf.Y - rig.sizes.RightFoot.Y / 2)
	local crown = head.Y + rig.sizes.Head.Y / 2
	local hips = ((lt * lh.c0).Position + (lt * rh.c0).Position) / 2
	return { height = crown - sole, legLength = hips.Y - sole, hipOffset = CFrame.new(hips) }
end

-- The pose of one frame: root CFrame, every joint's Transform and the extra
-- C0 rotations (Waist: the legs' tag_torso turn and CG_PlayerAngles' torso
-- angles; Neck: the head angles), lifted so no part dips under the floor.
local ARMS = {
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true,
}

function A.pose(rig, m, entity: CFrame, legs, torso, torsoRel: CFrame, headRel: CFrame)
	local root = A.hipFrame(entity, legs, m.legLength) * m.hipOffset:Inverse()
	local transforms = {}
	for _, j in A.LEGS_JOINTS do
		transforms[j] = legs[j]
	end
	for _, j in A.TORSO_JOINTS do
		transforms[j] = torso[j]
	end
	local extra = { UpperTorso = legs.waist * torsoRel, Head = headRel }
	local cfs = A.fk(rig, root, transforms, extra)
	local floor = (entity * CFrame.new(0, A.FLOOR, 0)).Y
	local lift = floor - A.lowest(rig, cfs)
	if legs.clear == nil then
		-- dying and dead (BOTH_*): the body lies on the floor, whatever the
		-- avatar's proportions. Its lowest part goes to the floor, up or down;
		-- arms are left out, so a hand the IK put under the floor doesn't
		-- hold the corpse up in the air
		local body = {}
		for name, cf in cfs do
			if not ARMS[name] then
				body[name] = cf
			end
		end
		lift = floor - A.lowest(rig, body)
	else
		-- standing, walking, jumping: the lower sole sits on the floor, or as
		-- far off it as sarge's does; the IK's limb lengths are sarge's, so
		-- this, not the pelvis height alone, keeps the feet planted
		local soles = math.huge
		for _, foot in { "LeftFoot", "RightFoot" } do
			if cfs[foot] then
				soles = math.min(soles, A.lowest(rig, { [foot] = cfs[foot] }))
			end
		end
		if soles < math.huge then
			lift = math.max(lift, floor + legs.clear * m.legLength - soles)
		end
	end
	if lift ~= 0 then
		local up = Vector3.new(0, lift, 0)
		root += up
		for name, cf in cfs do
			cfs[name] = cf + up
		end
	end
	return root, transforms, extra, cfs
end

-- Team outline and powerup shells (CG_AddRefEntityWithPowerups' shaders) as
-- one Highlight: { hidden, transparency, enabled, fill, fillTransparency,
-- outline, outlineTransparency }.
local RED = Color3.fromRGB(255, 60, 60)
local BLUE = Color3.fromRGB(70, 110, 255)
local QUAD = Color3.fromRGB(60, 120, 255)
local GOLD = Color3.fromRGB(255, 200, 60)
function A.look(o: { team: number, powerups: number, time: number, teamGame: boolean, dmflags: number })
	local has = function(pw)
		return bit32.band(o.powerups, bit32.lshift(1, pw)) ~= 0
	end
	local out = { hidden = false, transparency = 0, enabled = false, fill = Color3.new(1, 1, 1), fillTransparency = 1,
		outline = Color3.new(1, 1, 1), outlineTransparency = 1 }
	if has(C.PW_INVIS) then
		-- OA draws only the refracting invisibility shell, or nothing at all
		-- with DF_INVIS
		out.hidden = bit32.band(o.dmflags, C.DF_INVIS) ~= 0
		out.transparency = 0.85
		return out
	end
	if o.teamGame and (o.team == C.TEAM_RED or o.team == C.TEAM_BLUE) then
		out.enabled = true
		out.outline = if o.team == C.TEAM_RED then RED else BLUE
		out.outlineTransparency = 0
		out.fill = out.outline
		out.fillTransparency = 0.85
	end
	local shell = nil
	if has(C.PW_REGEN) and math.fmod(o.time // 100, 10) == 1 then
		shell = { RED, 0.35 }
	elseif has(C.PW_QUAD) then
		-- the quad shell pulses (its shader's rgbGen wave)
		shell = { if o.team == C.TEAM_RED then RED else QUAD, 0.45 + 0.15 * math.sin(o.time / 1000 * math.pi * 2) }
	elseif has(C.PW_BATTLESUIT) then
		shell = { GOLD, 0.5 }
	end
	if shell then
		out.enabled = true
		out.fill, out.fillTransparency = shell[1], shell[2]
		if out.outlineTransparency >= 1 then
			out.outline, out.outlineTransparency = shell[1], 0.3
		end
	end
	return out
end

return A
