--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Roblox avatars as player models (docs/client-notes.md, "Roblox avatars").
-- The server builds each player's R15 avatar into ReplicatedStorage.OAAvatars
-- ("c<clientNum>", attribute UserId). Here every player entity the cgame
-- draws with one gets a local copy, scaled to OA's standing height, that is
-- purely visual: no collision, queries or touches, the root part anchored
-- and placed from the entity each frame, the Humanoid passive (no state
-- machine) so its Animator only plays our tracks.
--
-- Animations: the R15 set in avatar/anims (tools/gen_avatar_anims.py) as
-- KeyframeSequences registered with AnimationClipProvider:
-- RegisterActiveAnimationClip, legs at Movement and torso at Action
-- priority, each held at the time OA's lerp frames give (speed 0). If the
-- registration fails or a track never loads, the same poses are written to
-- the Motor6Ds directly ("motors" mode). Live Roblox games refuse the
-- registration ("RegisterActiveKeyframeSequence can only be used in Solo
-- mode"), so there the motors mode is the one that runs.
local AnimationClipProvider = game:GetService("AnimationClipProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local A = require(script.Parent.Parent.avatar.AvatarAnim)
local C = require(script.Parent.Parent.q.Consts)
local Units = require(script.Parent.Units)
local Assets = require(script.Parent.Assets)

local Avatar = {}

Avatar.root = nil :: Instance?
Avatar.mode = "animator" -- or "motors"
-- weapon grip on the right hand, in the hand's frame (studs at scale 1):
-- the md3's origin is its handle, so it goes to the palm, below the hand's
-- centre; the gauntlet is worn over the fist
local GRIP = CFrame.new(0, -0.15, 0)
local GRIPS: { [number]: CFrame } = {
	[C.WP_GAUNTLET] = CFrame.new(0, -0.05, 0.1),
}

local zero = { [0] = 0, 0, 0 }

local function source(clientNum: number): Model?
	local folder = ReplicatedStorage:FindFirstChild("OAAvatars")
	local m = folder and folder:FindFirstChild("c" .. clientNum)
	return if m and m:IsA("Model") then m else nil
end

local function readRig(model: Model)
	local joints, sizes = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			joints[d.Part1.Name] = { part0 = d.Part0.Name, c0 = d.C0, c1 = d.C1, motor = d }
		elseif d:IsA("BasePart") and d.Parent == model then
			sizes[d.Name] = d.Size
		end
	end
	return A.rig(joints, sizes)
end

-- the per-player copy every entity of theirs clones from -------------------
local templates: { [Instance]: any } = {}
local retryAt: { [Instance]: number } = {}

-- CreateHumanoidModelFromDescription builds today's physics-ready rig: each
-- joint an AnimationConstraint between two attachments (with a
-- BallSocketConstraint limit) instead of a Motor6D. The local copy gets the
-- classic Motor6D back, same name and parent, C0/C1 being the attachments'
-- frames (Attachment1 = Attachment0 * Transform, as Part1 = Part0 * C0 *
-- Transform * C1^-1), so tracks, C0 writes and the motors path work on both.
local function toMotors(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("AnimationConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			local p0 = a0 and a0.Parent
			local p1 = a1 and a1.Parent
			if a0 and a1 and p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				local m = Instance.new("Motor6D")
				m.Name = d.Name
				m.Part0, m.Part1 = p0, p1
				m.C0, m.C1 = a0.CFrame, a1.CFrame
				m.Parent = p1
			end
			d:Destroy()
		elseif d:IsA("BallSocketConstraint") then
			d:Destroy()
		end
	end
end

-- nil while the model is incomplete (still replicating)
local function prepare(src: Model)
	local model = src:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("ForceField") then
			d:Destroy()
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hum == nil or hrp == nil then
		return nil
	end
	toMotors(model)
	hum.AutomaticScalingEnabled = false
	model.PrimaryPart = hrp :: BasePart
	local rig = readRig(model)
	local m = A.measure(rig)
	if m == nil then
		return nil
	end
	local s = A.fit(m.height)
	if math.abs(s - 1) > 1e-3 then
		model:ScaleTo(model:GetScale() * s)
		rig = readRig(model)
		m = A.measure(rig)
		if m == nil then
			return nil
		end
	end
	-- the clips carry character-axes rotations: a rig whose joints are turned
	-- at rest needs them per joint, which only the motors path does
	local aligned = true
	for _, j in rig.joints do
		local _, angle = j.r0:ToAxisAngle()
		if math.abs(angle) > math.rad(2) then
			aligned = false
		end
	end
	return { src = src, model = model, rig = rig, m = m, scale = model:GetScale(), aligned = aligned }
end

local function template(clientNum: number)
	local src = source(clientNum)
	if src == nil then
		return nil
	end
	local t = templates[src]
	if t == nil then
		if os.clock() < (retryAt[src] or 0) then
			return nil
		end
		local ok, res = pcall(prepare, src)
		if not ok then
			warn("Avatar: can't prepare " .. src.Name .. ": " .. tostring(res))
			templates[src] = false
		elseif res == nil then
			-- parts or joints not here yet: look again in a second
			retryAt[src] = os.clock() + 1
		else
			templates[src] = res
			retryAt[src] = nil
		end
		t = templates[src]
	end
	return t or nil
end

function Avatar.Ready(clientNum: number): boolean
	return template(clientNum) ~= nil
end

-- clips --------------------------------------------------------------------
local animations: { [string]: Animation | false } = {}
local registerError = nil

local function sequence(clip): KeyframeSequence
	local ks = Instance.new("KeyframeSequence")
	ks.Name = clip.kind .. ":" .. clip.name
	ks.Loop = clip.loop > 0
	ks.Priority = if clip.kind == "legs" then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
	local joints = if clip.kind == "legs" then A.LEGS_JOINTS else A.TORSO_JOINTS
	-- one keyframe per md3 frame, and the last again one frame later, so even
	-- a one-frame animation has a length
	for k = 1, clip.num + 1 do
		local frame = clip.frames[math.min(k, clip.num)]
		local kf = Instance.new("Keyframe")
		kf.Time = (k - 1) / clip.fps
		local poses = {}
		local function pose(name: string): Pose
			local p = poses[name]
			if p then
				return p
			end
			p = Instance.new("Pose")
			p.Name = name
			p.Weight = 0
			p.EasingStyle = Enum.PoseEasingStyle.Linear
			local parent = A.PARENT[name]
			p.Parent = if parent then pose(parent) else kf
			poses[name] = p
			return p
		end
		for _, j in joints do
			local p = pose(j)
			p.CFrame = frame[j]
			p.Weight = 1
		end
		kf.Parent = ks
	end
	return ks
end

local function animationFor(name: string): Animation?
	local a = animations[name]
	if a ~= nil then
		return a or nil
	end
	local ok, res = pcall(function()
		local id = AnimationClipProvider:RegisterActiveAnimationClip(sequence(A.clips[name]))
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		return anim
	end)
	if not ok then
		registerError = tostring(res)
		animations[name] = false
		return nil
	end
	animations[name] = res
	return res
end

-- whether the registered clips really play: the first track must get a length
local probe: { track: AnimationTrack, since: number }? = nil
local probed = false

local function useMotors(why: string)
	if Avatar.mode == "motors" then
		return
	end
	Avatar.mode = "motors"
	print("Avatar: animations drive the Motor6Ds directly (" .. why .. ")")
end

-- instances ----------------------------------------------------------------
local instances: { [number]: any } = {}

local function destroy(inst)
	inst.model:Destroy()
end

local function newInstance(t)
	local model = t.model:Clone()
	local parts, decals = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			d.Massless = true
			table.insert(parts, d)
		elseif d:IsA("Decal") then
			table.insert(decals, d)
		end
	end
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart
	hrp.Anchored = true
	hrp.Transparency = 1
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.EvaluateStateMachine = false
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local hl = Instance.new("Highlight")
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Enabled = false
	hl.Adornee = model
	hl.Parent = model
	-- the clone's own Motor6Ds, by the part they move
	local motors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 then
			motors[d.Part1.Name] = d
		end
	end
	return {
		t = t,
		model = model,
		hrp = hrp,
		animator = animator,
		highlight = hl,
		motors = motors,
		parts = parts,
		decals = decals,
		tracks = {},
		ltm = -1,
		used = false,
	}
end

local function track(inst, clip: string, slot: number): AnimationTrack?
	local key = clip .. "#" .. slot
	local tr = inst.tracks[key]
	if tr == nil then
		local anim = animationFor(clip)
		if anim == nil then
			useMotors("RegisterActiveAnimationClip failed: " .. tostring(registerError))
			return nil
		end
		tr = inst.animator:LoadAnimation(anim)
		tr.Priority = if string.sub(clip, 1, 5) == "legs:" then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
		tr.Looped = false
		inst.tracks[key] = tr
		if probe == nil and not probed then
			probe = { track = tr, since = os.clock() }
		end
	end
	return tr
end

local function stopTracks(inst)
	for _, tr in inst.tracks do
		if tr.IsPlaying then
			tr:Stop(0)
		end
	end
end

local function driveTracks(inst, list)
	local want = {}
	for _, e in list do
		local tr = track(inst, e.clip, e.slot)
		if tr == nil then
			return
		end
		want[tr] = e
	end
	for _, tr in inst.tracks do
		local e = want[tr]
		if e then
			if not tr.IsPlaying then
				tr:Play(0, e.weight, 0)
			end
			tr:AdjustSpeed(0)
			tr:AdjustWeight(e.weight, 0)
			tr.TimePosition = e.time
		elseif tr.IsPlaying then
			tr:Stop(0)
		end
	end
end

local function driveMotors(inst, transforms)
	local rig = inst.t.rig
	for name, rot in transforms do
		local motor = inst.motors[name]
		local j = rig.joints[name]
		if motor and j then
			motor.Transform = A.inJoint(j, rot)
		end
	end
end

local function setTransparency(inst, v: number)
	if inst.ltm == v then
		return
	end
	inst.ltm = v
	for _, p in inst.parts do
		p.LocalTransparencyModifier = v
	end
	for _, d in inst.decals do
		d.LocalTransparencyModifier = v
	end
end

-- Quake orientation of a CFrame (origin in units, axis forward/left/up)
local function toOrientation(cf: CFrame, out)
	Units.fromVector3(cf.Position, out.origin)
	local function dir(v: Vector3, s: number, o)
		o[0], o[1], o[2] = v.X * s, -v.Z * s, v.Y * s
	end
	dir(cf.LookVector, 1, out.axis[0])
	dir(cf.RightVector, -1, out.axis[1])
	dir(cf.UpVector, 1, out.axis[2])
end

-- Poses and shows entity av.entNum's avatar for this frame. av = { entNum,
-- clientNum, origin, legsAxis, torsoAxis, headAxis (CG_PlayerAngles'), legs,
-- torso (lerp states, see AvatarAnim.tracks), weapon, renderfx, team,
-- powerups, time, teamGame, dmflags }. Returns false when there is no avatar
-- to draw (the cgame then draws the OA model).
function Avatar.Draw(av): boolean
	local t = template(av.clientNum)
	if t == nil or Avatar.root == nil then
		return false
	end
	local legsTracks = A.tracks(av.legs, "legs")
	local torsoTracks = A.tracks(av.torso, "torso")
	local legs, torso = A.sample(legsTracks), A.sample(torsoTracks)
	if legs == nil or torso == nil then
		return false
	end
	local inst = instances[av.entNum]
	if inst and inst.t ~= t then
		destroy(inst)
		inst = nil
	end
	if inst == nil then
		inst = newInstance(t)
		instances[av.entNum] = inst
	end
	inst.used = true

	local entity = Units.toCFrame(av.origin, av.legsAxis)
	local torsoRel = A.relative(Units.toCFrame(zero, av.torsoAxis))
	local headRel = A.relative(Units.toCFrame(zero, av.headAxis))
	local root, transforms, extra, cfs = A.pose(t.rig, t.m, entity, legs, torso, torsoRel, headRel)
	inst.hrp.CFrame = root
	for name, rot in extra do
		local motor, j = inst.motors[name], t.rig.joints[name]
		if motor and j then
			motor.C0 = j.c0 * A.inJoint(j, rot)
		end
	end

	local hand = cfs.RightHand
	local g = GRIPS[av.weapon] or GRIP
	inst.grip = if hand then hand * CFrame.new(g.Position * t.scale) * A.rotation(g) else root
	inst.chest = cfs.UpperTorso or root
	inst.head = cfs.Head or root

	local look = A.look(av)
	local hidden = look.hidden or bit32.band(av.renderfx, C.RF_THIRD_PERSON) ~= 0
	local parent = if hidden then nil else Avatar.root
	if inst.model.Parent ~= parent then
		inst.model.Parent = parent
	end
	if hidden then
		-- our own body in first person: only its tags are used
		stopTracks(inst)
		return true
	end
	setTransparency(inst, look.transparency)
	local hl = inst.highlight
	hl.Enabled = look.enabled
	if look.enabled then
		hl.FillColor, hl.FillTransparency = look.fill, look.fillTransparency
		hl.OutlineColor, hl.OutlineTransparency = look.outline, look.outlineTransparency
	end

	-- the Animator needs the model in the world before it loads a track
	if Avatar.mode == "animator" and t.aligned then
		local list = table.clone(legsTracks)
		for _, e in torsoTracks do
			table.insert(list, e)
		end
		driveTracks(inst, list)
	end
	if Avatar.mode == "motors" or not t.aligned then
		-- nothing may write the Transforms but us
		if inst.animator.Parent then
			stopTracks(inst)
			inst.animator.Parent = nil
		end
		driveMotors(inst, transforms)
	end
	if probe and not probed then
		if probe.track.Length > 0 then
			probed = true
			print("Avatar: RegisterActiveAnimationClip works, tracks play on the Animator")
		elseif os.clock() - probe.since > 5 then
			probed = true
			useMotors("a registered clip never loaded")
		end
	end
	return true
end

-- An attachment point of the avatar drawn this frame: "tag_weapon" (the
-- grip in the right hand), "tag_torso" (the chest) or "tag_head".
function Avatar.Tag(entNum: number, name: string, out): boolean
	local inst = instances[entNum]
	if inst == nil or not inst.used then
		return false
	end
	local cf = if name == "tag_weapon" then inst.grip elseif name == "tag_head" then inst.head else inst.chest
	toOrientation(cf, out)
	return true
end

-- A Roblox account's headshot as a 2D shader (0 for no account): the head
-- icon of every client and bot wearing one, wherever OA draws a player's
-- icon. The rbxthumb image needs no request of ours; until it has
-- downloaded the ImageLabel draws nothing.
local heads: { [number]: number } = {}
function Avatar.Headshot(uid: any): number
	uid = tonumber(uid)
	if uid == nil or uid <= 0 then
		return 0
	end
	local h = heads[uid]
	if h == nil then
		local url = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", uid)
		h = Assets.RegisterImage("avatar/headshot/" .. uid, url, 150, 150)
		heads[uid] = h
	end
	return h
end

-- The account a client wears, as the server publishes it
-- (server/sv/avatars_roblox.luau), whether or not its avatar is drawn.
function Avatar.HeadShader(clientNum: number): number
	local folder = ReplicatedStorage:FindFirstChild("OAAvatars")
	return Avatar.Headshot(folder and folder:GetAttribute("User" .. clientNum))
end

-- A roster bot's account id and username by its bots.txt name, as the
-- server publishes them (server/sv/botroster.luau, Accounts).
local function rosterAccount(name: string): (string?, string?)
	local folder = ReplicatedStorage:FindFirstChild("OAAvatars")
	local list = folder and folder:GetAttribute("BotRoster")
	if type(list) ~= "string" then
		return nil, nil
	end
	for entry in string.gmatch(list, "[^;]+") do
		local bot, id, username = string.match(entry, "^([^=]+)=(%d+)=(.+)$")
		if bot == string.lower(name) then
			return id, username
		end
	end
	return nil, nil
end

-- A roster bot's face in the menus.
function Avatar.BotHeadShader(name: string): number
	return Avatar.Headshot((rosterAccount(name)))
end

-- A roster bot's name in the menus: its account's username, nil while
-- unknown (the menu keeps the OA name).
function Avatar.BotName(name: string): string?
	local _, username = rosterAccount(name)
	return username
end

function Avatar.LocalHeadShader(): number
	local player = Players.LocalPlayer
	return Avatar.Headshot(player and player.UserId)
end

-- The local player's whole avatar as a picture (the player settings menu),
-- 0 without an account.
local bodies: { [number]: number } = {}
function Avatar.LocalBodyShader(): number
	local player = Players.LocalPlayer
	local uid = player and player.UserId
	if uid == nil or uid <= 0 then
		return 0
	end
	local h = bodies[uid]
	if h == nil then
		local url = string.format("rbxthumb://type=Avatar&id=%d&w=420&h=420", uid)
		h = Assets.RegisterImage("avatar/body/" .. uid, url, 420, 420)
		bodies[uid] = h
	end
	return h
end

function Avatar.BeginFrame()
	for _, inst in instances do
		inst.used = false
	end
end

function Avatar.EndFrame()
	for n, inst in instances do
		if not inst.used and inst.model.Parent then
			stopTracks(inst)
			inst.model.Parent = nil
		end
		-- the player left, or the server dropped avatars
		if not inst.used and inst.t.src.Parent == nil then
			destroy(inst)
			instances[n] = nil
		end
	end
	for src in templates do
		if src.Parent == nil then
			templates[src] = nil
		end
	end
	for src in retryAt do
		if src.Parent == nil then
			retryAt[src] = nil
		end
	end
end

return Avatar
