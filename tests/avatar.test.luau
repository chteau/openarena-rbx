local CFrame, Vector3 = H.roblox.CFrame, H.roblox.Vector3
-- Roblox avatars (src/client/avatar/AvatarAnim.luau, cg_avatars.luau):
-- timing against sarge's animation.cfg, the lerp state -> track mapping,
-- the fit and feet maths, and the yaw/pitch split onto the joints.

local A = H.require("client/avatar/AvatarAnim")
local C = H.require("client/q/Consts")
local T = H.require("client/q/Types")
local Q = H.require("client/q/Q")
local Units = H.require("client/sys/Units")

-- models/players/sarge/animation.cfg from OpenArena 0.8.8's pak0.pk3
local SARGE_CFG = [[
// animation config file

sex	m

// first frame, num frames, looping frames, frames per second

0	30	0	25		// BOTH_DEATH1
29	1	0	25		// BOTH_DEAD1
30	30	0	25		// BOTH_DEATH2
59	1	0	25		// BOTH_DEAD2
60	30	0	25		// BOTH_DEATH3
89	1	0	25		// BOTH_DEAD3

90	40	0	13		// TORSO_GESTURE

130	6	0	15		// TORSO_ATTACK		(MUST NOT CHANGE -- hand animation is synced to this)
136	6	0	15		// TORSO_ATTACK2	(MUST NOT CHANGE -- hand animation is synced to this)

142	5	0	20		// TORSO_DROP		(MUST NOT CHANGE -- hand animation is synced to this)
147	4	0	20		// TORSO_RAISE		(MUST NOT CHANGE -- hand animation is synced to this)

151	1	0	15		// TORSO_STAND
152	1	0	15		// TORSO_STAND2

153	8	8	20		// LEGS_WALKCR
161	12	12	20		// LEGS_WALK
173	9	9	15		// LEGS_RUN
182	10	10	18		// LEGS_BACK
185	10	10	15		// LEGS_SWIM

202	8	0	15		// LEGS_JUMP
211	8	0	20		// LEGS_LAND

219	9	0	15		// LEGS_JUMPB
228	6	0	20		// LEGS_LANDB

234	10	10	10		// LEGS_IDLE
244	10	10	10		// LEGS_IDLECR

254	7	7	18		// LEGS_TURN
]]

local function cgame()
	local G = H.require("client/cg/G")
	H.require("client/cg/cg_main")
	H.require("client/cg/cg_players")
	H.require("client/cg/cg_players2")
	G.cg_animSpeed.integer = 1
	G.cg_debugAnim.integer = 0
	return G
end

H.test("avatar.timing", function()
	local G = cgame()
	H.require("client/sys/FS").Mount({ files = { ["models/players/sarge/animation.cfg"] = SARGE_CFG } })
	local ci = T.clientInfo_t()
	assert(G.CG_ParseAnimationFile("models/players/sarge/animation.cfg", ci), "parsed")
	local mine = A.animations()
	for i = 0, C.MAX_TOTALANIMATIONS - 1 do
		local a, b = ci.animations[i], mine[i]
		for _, f in { "firstFrame", "numFrames", "loopFrames", "frameLerp", "initialLerp", "reversed", "flipflop" } do
			H.eq(b[f], a[f], ("anim %d %s"):format(i, f))
		end
	end
	-- every animation a player plays has a clip of its own frame count
	for i = 0, C.MAX_TOTALANIMATIONS - 1 do
		if i < C.FLAG_RUN then
			local anim = mine[i]
			local kinds = if i <= C.BOTH_DEAD3 then { "legs", "torso" } elseif string.sub(anim.clip or "", 1, 5) == "legs:" then { "legs" } else { "torso" }
			for _, kind in if anim.numFrames > 0 then kinds else {} do
				local clip = A.clips[A.clipName(anim, kind) :: string]
				assert(clip, ("anim %d has a %s clip"):format(i, kind))
				H.eq(clip.num, anim.numFrames, ("anim %d frames"):format(i))
				H.eq(math.floor(1000 / clip.fps), anim.frameLerp, ("anim %d fps"):format(i))
				H.eq(#clip.frames, clip.num)
			end
		end
	end
end)

H.test("avatar.tracks", function()
	local anims = A.animations()
	local run, idle = anims[C.LEGS_RUN], anims[C.LEGS_IDLE]
	-- neighbouring frames: one track between their keyframes
	local t = A.tracks({ anim = run, oldAnim = run, frame = run.firstFrame + 3, oldFrame = run.firstFrame + 2, backlerp = 0.25 }, "legs")
	H.eq(#t, 1)
	H.eq(t[1].clip, "legs:LEGS_RUN")
	H.near(t[1].time, 2.75 / 15)
	-- the loop wrapping (last frame -> first): the same clip twice, weighted
	t = A.tracks({ anim = run, oldAnim = run, frame = run.firstFrame, oldFrame = run.firstFrame + 8, backlerp = 0.4 }, "legs")
	H.eq(#t, 2)
	H.near(t[1].time, 8 / 15)
	H.near(t[1].weight, 0.4)
	H.near(t[2].time, 0)
	H.near(t[2].weight, 0.6)
	H.eq(t[1].slot ~= t[2].slot, true)
	-- a new animation: the old one fades out over the initial lerp
	t = A.tracks({ anim = run, oldAnim = idle, frame = run.firstFrame, oldFrame = idle.firstFrame + 4, backlerp = 0.7 }, "legs")
	H.eq(#t, 2)
	H.eq(t[1].clip, "legs:LEGS_IDLE")
	H.near(t[1].time, 4 / 10)
	H.eq(t[2].clip, "legs:LEGS_RUN")
	-- reversed copies play their source backwards
	local back = anims[C.LEGS_BACKWALK]
	t = A.tracks({ anim = back, oldAnim = back, frame = back.firstFrame + 4, oldFrame = back.firstFrame + 5, backlerp = 0.5 }, "legs")
	H.eq(t[1].clip, "legs:LEGS_WALK")
	H.near(t[1].time, 4.5 / 20)
	-- BOTH_* has a legs and a torso clip
	local death = anims[C.BOTH_DEATH2]
	H.eq(A.tracks({ anim = death, frame = death.firstFrame }, "torso")[1].clip, "torso:BOTH_DEATH2")
	H.eq(A.tracks({ anim = death, frame = death.firstFrame }, "legs")[1].clip, "legs:BOTH_DEATH2")
	-- a gesture variant shares the gesture clip
	H.eq(A.tracks({ anim = anims[C.TORSO_AFFIRMATIVE], frame = 95 }, "torso")[1].clip, "torso:TORSO_GESTURE")
end)

H.test("avatar.lerp_timing", function()
	-- OA's own lerp frames on the avatar table: the clip time follows the
	-- cfg's frame rate, looping over the cfg's loop frames
	local G = cgame()
	local ci = { animations = A.animations() }
	local lf = T.lerpFrame_t()
	G.cg.time = 1000
	G.CG_ClearLerpFrame(ci, lf, C.LEGS_RUN)
	local times = {}
	for ms = 1000, 1000 + 2 * 600, 1000 / 15 do
		G.cg.time = math.floor(ms)
		G.CG_RunLerpFrame(ci, lf, C.LEGS_RUN, 1)
		local tr = A.tracks({ anim = lf.animation, oldAnim = lf.animation, frame = lf.frame, oldFrame = lf.oldFrame, backlerp = lf.backlerp }, "legs")
		table.insert(times, tr[#tr].time)
	end
	for _, v in times do
		assert(v >= 0 and v <= 8 / 15 + 1e-9, "inside the 9-frame cycle: " .. v)
	end
	-- 9 frames at 15 fps: back to the cycle's start every 0.6 s
	H.near(times[1], times[10], 1e-6)
end)

-- A blocky R15 rig at rest, sole at y = 0, root part at its centre.
local function testRig(s: number)
	local parts = {
		HumanoidRootPart = { 0, 3.4, 0, 2, 2, 1 },
		LowerTorso = { 0, 3.2, 0, 2, 0.4, 1 },
		UpperTorso = { 0, 4.2, 0, 2, 1.6, 1 },
		Head = { 0, 5.6, 0, 1.2, 1.2, 1.2 },
		LeftUpperLeg = { -0.5, 2.4, 0, 1, 1.2, 1 },
		LeftLowerLeg = { -0.5, 1.2, 0, 1, 1.2, 1 },
		LeftFoot = { -0.5, 0.2, 0, 1, 0.4, 1 },
		RightUpperLeg = { 0.5, 2.4, 0, 1, 1.2, 1 },
		RightLowerLeg = { 0.5, 1.2, 0, 1, 1.2, 1 },
		RightFoot = { 0.5, 0.2, 0, 1, 0.4, 1 },
		LeftUpperArm = { -1.5, 4.4, 0, 1, 1.2, 1 },
		LeftLowerArm = { -1.5, 3.4, 0, 1, 1.0, 1 },
		LeftHand = { -1.5, 2.6, 0, 1, 0.6, 1 },
		RightUpperArm = { 1.5, 4.4, 0, 1, 1.2, 1 },
		RightLowerArm = { 1.5, 3.4, 0, 1, 1.0, 1 },
		RightHand = { 1.5, 2.6, 0, 1, 0.6, 1 },
	}
	local at = {
		LowerTorso = { 0, 3.2 }, UpperTorso = { 0, 3.4 }, Head = { 0, 5.0 },
		LeftUpperLeg = { -0.5, 3.0 }, LeftLowerLeg = { -0.5, 1.8 }, LeftFoot = { -0.5, 0.6 },
		RightUpperLeg = { 0.5, 3.0 }, RightLowerLeg = { 0.5, 1.8 }, RightFoot = { 0.5, 0.6 },
		LeftUpperArm = { -1.5, 5.0 }, LeftLowerArm = { -1.5, 3.9 }, LeftHand = { -1.5, 2.9 },
		RightUpperArm = { 1.5, 5.0 }, RightLowerArm = { 1.5, 3.9 }, RightHand = { 1.5, 2.9 },
	}
	local function cf(p)
		return CFrame.new(p[1] * s, p[2] * s, p[3] * s)
	end
	local joints, sizes = {}, {}
	for name, p in parts do
		sizes[name] = Vector3.new(p[4], p[5], p[6]) * s
	end
	for name, j in at do
		local parent = A.PARENT[name]
		local w = CFrame.new(j[1] * s, j[2] * s, 0)
		joints[name] = { part0 = parent, c0 = cf(parts[parent]):Inverse() * w, c1 = cf(parts[name]):Inverse() * w }
	end
	return A.rig(joints, sizes)
end

H.test("avatar.fit_and_feet", function()
	local rig = testRig(1)
	local m = A.measure(rig)
	assert(m, "measured")
	H.near(m.height, 6.2, 1e-6)
	H.near(m.legLength, 3.0, 1e-6)
	-- the scale that makes it sarge's height (53.24 u standing)
	local s = A.fit(m.height)
	H.near(s * m.height, A.HEIGHT, 1e-6)
	H.near(A.HEIGHT * 8, 53.24, 0.01)
	-- tiny and giant bodies are clamped, nonsense is left alone
	H.eq(A.fit(0.001), A.MAX_SCALE)
	H.eq(A.fit(1000), A.MIN_SCALE)
	H.eq(A.fit(0), 1)

	-- scaled to fit, standing idle at an origin: the soles rest on the box's
	-- floor (MINS z = -24) and the crown is near sarge's height above it
	rig = testRig(s)
	m = A.measure(rig) :: any
	local origin = { [0] = 100, 200, 50 }
	local entity = Units.toCFrame(origin, { [0] = Q.vec3(1, 0, 0), Q.vec3(0, 1, 0), Q.vec3(0, 0, 1) })
	local floor = (50 - 24) / 8
	local function stand(name, k)
		local legs = A.clips["legs:" .. name].frames[k]
		local torso = A.clips["torso:TORSO_STAND"].frames[1]
		local _, _, _, cfs = A.pose(rig, m, entity, legs, torso, CFrame.identity, CFrame.identity)
		local soles = math.min(A.lowest(rig, { LeftFoot = cfs.LeftFoot }), A.lowest(rig, { RightFoot = cfs.RightFoot }))
		return cfs, soles
	end
	for k = 1, 10 do
		local cfs, soles = stand("LEGS_IDLE", k)
		H.near(soles, floor, 0.1, "idle frame " .. k .. " on the floor")
		local crown = cfs.Head.Y + rig.sizes.Head.Y / 2 - floor
		-- (a little over: the feet pitch toe-down like sarge's, and are lifted
		-- so no corner sinks)
		assert(crown > A.HEIGHT * 0.9 and crown <= A.HEIGHT * 1.03, "standing height " .. crown)
	end
	-- crouching lowers the hips, the feet stay down
	local idle = stand("LEGS_IDLE", 1)
	local cr, crSoles = stand("LEGS_IDLECR", 1)
	assert(cr.LowerTorso.Y < idle.LowerTorso.Y - 0.5, "crouched hips lower")
	H.near(crSoles, floor, 0.15, "crouched feet on the floor")
	-- the run never pushes a foot through the floor, and touches it
	local lowest = math.huge
	for k = 1, 9 do
		local _, soles = stand("LEGS_RUN", k)
		assert(soles >= floor - 1e-6, "run frame " .. k .. " above the floor")
		lowest = math.min(lowest, soles)
	end
	H.near(lowest, floor, 0.15, "a run frame plants a foot")
	-- dying and dead: the body (arms aside) rests on the floor, and lies low
	local ARMS = { LeftUpperArm = 1, LeftLowerArm = 1, LeftHand = 1, RightUpperArm = 1, RightLowerArm = 1, RightHand = 1 }
	for _, name in { "BOTH_DEAD1", "BOTH_DEAD2", "BOTH_DEAD3", "BOTH_DEATH1", "BOTH_DEATH2", "BOTH_DEATH3" } do
		local clip = A.clips["legs:" .. name]
		local tclip = A.clips["torso:" .. name]
		for k = 1, clip.num do
			local _, _, _, cfs = A.pose(rig, m, entity, clip.frames[k], tclip.frames[k], CFrame.identity, CFrame.identity)
			local body = {}
			for part, cf in cfs do
				if not ARMS[part] then
					body[part] = cf
				end
			end
			H.near(A.lowest(rig, body), floor, 1e-4, name .. " frame " .. k .. " on the floor")
			if string.sub(name, 1, 9) == "BOTH_DEAD" then
				assert(cfs.Head.Y - floor < A.HEIGHT * 0.4, name .. " lies down " .. (cfs.Head.Y - floor))
			end
		end
	end
end)

H.test("avatar.angle_split", function()
	-- CG_PlayerAngles' legs / torso / head axes (torso relative to legs,
	-- head relative to torso) become the root, Waist and Neck rotations:
	-- composed, the head looks along the view angles
	local G = cgame()
	local cent = T.centity_t()
	cent.currentState.legsAnim = C.LEGS_RUN
	cent.currentState.torsoAnim = C.TORSO_STAND
	cent.currentState.angles2[C.YAW] = 0
	cent.currentState.clientNum = 0
	Q.VectorSet(cent.lerpAngles, 40, 120, 0)
	G.cg.frametime = 10000
	G.cg_swingSpeed.value = 0.3
	cent.pe.legs.yawAngle, cent.pe.torso.yawAngle = 120, 120
	local legs = { [0] = Q.vec3(0, 0, 0), Q.vec3(0, 0, 0), Q.vec3(0, 0, 0) }
	local torso = { [0] = Q.vec3(0, 0, 0), Q.vec3(0, 0, 0), Q.vec3(0, 0, 0) }
	local head = { [0] = Q.vec3(0, 0, 0), Q.vec3(0, 0, 0), Q.vec3(0, 0, 0) }
	for _ = 1, 20 do
		G.CG_PlayerAngles(cent, legs, torso, head)
	end
	local zero = Q.vec3(0, 0, 0)
	local root = A.rotation(Units.toCFrame(zero, legs))
	local waist = A.relative(Units.toCFrame(zero, torso))
	local neck = A.relative(Units.toCFrame(zero, head))
	local fwd = Q.vec3(0, 0, 0)
	Q.AngleVectors(Q.vec3(40, 120, 0), fwd, nil, nil)
	local look = (root * waist * neck).LookVector
	local want = Units.toDirection(fwd)
	H.near(look.X, want.X, 1e-3)
	H.near(look.Y, want.Y, 1e-3)
	H.near(look.Z, want.Z, 1e-3)
	-- the torso takes 3/4 of the pitch (OA's split), the head the rest
	local tl = (root * waist).LookVector
	H.near(math.deg(math.asin(-tl.Y)), 30, 0.5)
	-- and the legs stay level
	H.near(root.LookVector.Y, 0, 1e-6)
end)

H.test("avatar.look", function()
	local base = { team = C.TEAM_FREE, powerups = 0, time = 0, teamGame = false, dmflags = 0 }
	H.eq(A.look(base).enabled, false)
	local red = A.look({ team = C.TEAM_RED, powerups = 0, time = 0, teamGame = true, dmflags = 0 })
	H.eq(red.enabled, true)
	H.eq(red.outlineTransparency, 0)
	assert(red.outline.R > red.outline.B, "red outline")
	assert(red.fillTransparency >= 0.8, "a light tint keeps the avatar recognisable")
	local quad = A.look({ team = C.TEAM_FREE, powerups = bit32.lshift(1, C.PW_QUAD), time = 0, teamGame = false, dmflags = 0 })
	H.eq(quad.enabled, true)
	assert(quad.fill.B > quad.fill.R, "blue quad shell")
	local invis = A.look({ team = C.TEAM_FREE, powerups = bit32.lshift(1, C.PW_INVIS), time = 0, teamGame = false, dmflags = 0 })
	H.eq(invis.hidden, false)
	assert(invis.transparency > 0.5, "see-through")
	H.eq(A.look({ team = C.TEAM_FREE, powerups = bit32.lshift(1, C.PW_INVIS), time = 0, teamGame = false, dmflags = C.DF_INVIS }).hidden, true)
	-- regen flashes on the 100 ms tick OA uses
	local regen = { team = C.TEAM_FREE, powerups = bit32.lshift(1, C.PW_REGEN), time = 100, teamGame = false, dmflags = 0 }
	H.eq(A.look(regen).enabled, true)
	regen.time = 300
	H.eq(A.look(regen).enabled, false)
end)

H.test("avatar.headshots", function()
	local Avatar = H.require("client/sys/Avatar")
	local Assets = H.require("client/sys/Assets")
	local function image(h: number): string?
		local sh = Assets.Shader(h)
		local img = sh and Assets.Image(sh.name)
		return img and img.id
	end
	local rs = H.game:GetService("ReplicatedStorage")
	local folder = H.roblox.Instance.new("Folder")
	folder.Name = "OAAvatars"
	folder.Parent = rs
	H.eq(Avatar.HeadShader(3), 0)
	-- a client wearing an account, avatar model or not
	folder:SetAttribute("User3", "260342963")
	local h = Avatar.HeadShader(3)
	H.eq(image(h), "rbxthumb://type=AvatarHeadShot&id=260342963&w=150&h=150")
	H.eq(Avatar.HeadShader(3), h)
	folder:SetAttribute("User4", "-1") -- a Studio test player
	H.eq(Avatar.HeadShader(4), 0)
	-- roster bots in the menus, by bots.txt name
	H.eq(Avatar.BotHeadShader("tony"), 0)
	folder:SetAttribute("BotRoster", "cyber-garg=123757139 tony=260342963")
	H.eq(Avatar.BotHeadShader("Tony"), h)
	H.eq(image(Avatar.BotHeadShader("Cyber-Garg")), "rbxthumb://type=AvatarHeadShot&id=123757139&w=150&h=150")
	H.eq(Avatar.BotHeadShader("sarge"), 0)
	-- the player settings preview: nothing drawn without a local account
	H.eq(Avatar.LocalBodyShader(), 0)
	folder:Destroy()
end)
