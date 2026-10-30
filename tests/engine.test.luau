-- The engine layer and the pure logic the HUD/menus/animation stand on.

H.test("shaderfx.wave", function()
	local Fx = H.require("client/sys/ShaderFx")
	H.near(Fx.wave({ func = "sin", base = 1, amp = 0.5, phase = 0.25, freq = 1 }, 0), 1.5)
	H.near(Fx.wave({ func = "sin", base = 0, amp = 1, phase = 0, freq = 2 }, 0.125), 1)
	H.near(Fx.wave({ func = "square", base = 0, amp = 1, phase = 0, freq = 1 }, 0.75), -1)
	H.near(Fx.wave({ func = "triangle", base = 0, amp = 1, phase = 0, freq = 1 }, 0.25), 1)
	H.near(Fx.wave({ func = "sawtooth", base = 0, amp = 1, phase = 0, freq = 1 }, 0.3), 0.3)
	H.near(Fx.wave({ func = "inversesawtooth", base = 0, amp = 1, phase = 0, freq = 1 }, 0.3), 0.7)
	H.eq(Fx.wave(nil, 3), 1)
end)

H.test("shaderparse.stages", function()
	local P = H.require("client/sys/ShaderParse")
	local s = P.parse([[
// comment
gfx/2d/test
{
	nopicmip
	{
		map gfx/2d/test.tga
		blendfunc add
		rgbGen wave sin 0 1 0 2
		tcMod scroll 0.5 0
	}
}
]])["gfx/2d/test"]
	assert(s, "parsed")
	H.eq(#s.stages, 1)
	local st = s.stages[1]
	H.eq(st.map, "gfx/2d/test.tga")
	H.eq(H.require("client/sys/ShaderFx").blendMode(st), "add")
end)

H.test("cmd.tokenize", function()
	local Cmd = H.require("client/sys/Cmd")
	Cmd.TokenizeString('bind w "+forward" // trailing comment')
	H.eq(Cmd.Argc(), 3)
	H.eq(Cmd.Argv(0), "bind")
	H.eq(Cmd.Argv(2), "+forward")
	H.eq(Cmd.Argv(5), "")
end)

H.test("cvar.basics", function()
	local Cvar = H.require("client/sys/Cvar")
	local v = Cvar.Get("test_cvar", "12.5", 0)
	H.eq(v.string, "12.5")
	H.near(Cvar.VariableValue("test_cvar"), 12.5)
	Cvar.Set("test_cvar", "3")
	H.eq(Cvar.VariableString("test_cvar"), "3")
	H.eq(Cvar.VariableValue("no_such_cvar"), 0)
end)

H.test("keys.names", function()
	local Keys = H.require("client/sys/Keys")
	local C = H.require("client/q/Consts")
	H.eq(Keys.StringToKeynum("MOUSE1"), C.K_MOUSE1)
	H.eq(Keys.StringToKeynum("a"), 97)
	H.eq(Keys.StringToKeynum("uparrow"), C.K_UPARROW)
	H.eq(Keys.KeynumToString(C.K_UPARROW), "UPARROW")
	Keys.SetBinding(97, "+moveleft")
	H.eq(Keys.GetBinding(97), "+moveleft")
end)

H.test("md3.parse", function()
	local Md3 = H.require("client/sys/Md3")
	-- header + 1 frame + 1 tag, no surfaces
	local b = buffer.create(108 + 56 + 112)
	buffer.writestring(b, 0, "IDP3")
	buffer.writei32(b, 4, 15)
	buffer.writei32(b, 76, 1) -- numFrames
	buffer.writei32(b, 80, 1) -- numTags
	buffer.writei32(b, 84, 0) -- numSurfaces
	buffer.writei32(b, 92, 108) -- ofsFrames
	buffer.writei32(b, 96, 108 + 56) -- ofsTags
	buffer.writei32(b, 100, 108 + 56 + 112) -- ofsSurfaces
	buffer.writei32(b, 104, 108 + 56 + 112) -- ofsEnd
	buffer.writef32(b, 108 + 12, 8) -- maxs.x
	local at = 108 + 56
	buffer.writestring(b, at, "tag_torso")
	buffer.writef32(b, at + 64 + 8, 24) -- origin.z
	buffer.writef32(b, at + 76, 1) -- axis[0].x
	buffer.writef32(b, at + 88 + 4, 1) -- axis[1].y
	buffer.writef32(b, at + 100 + 8, 1) -- axis[2].z
	local m = Md3.Parse("test", b)
	H.eq(m.numFrames, 1)
	H.near(m.frames[0].maxs[0], 8)
	local tag = m.tags[0].tag_torso
	assert(tag, "tag_torso")
	H.near(tag.origin[2], 24)
	H.near(tag.axis[1][1], 1)
end)

H.test("cg.lerpframe", function()
	local G = H.require("client/cg/G")
	H.require("client/cg/cg_main")
	H.require("client/cg/cg_players")
	local C = H.require("client/q/Consts")
	G.cg_animSpeed.integer = 1
	G.cg_debugAnim.integer = 0
	local anim = { firstFrame = 10, numFrames = 4, loopFrames = 4, frameLerp = 50, initialLerp = 50,
		reversed = false, flipflop = false }
	local ci = { animations = { [C.LEGS_RUN] = anim } }
	local lf = { oldFrame = 0, frame = 0, oldFrameTime = 0, frameTime = 1000, backlerp = 0,
		animationNumber = -1, animation = nil, animationTime = 0, yawAngle = 0, yawing = false,
		pitchAngle = 0, pitching = false }
	local frames = {}
	for t = 1000, 1400, 50 do
		G.cg.time = t
		G.CG_RunLerpFrame(ci, lf, C.LEGS_RUN, 1)
		table.insert(frames, lf.frame)
	end
	-- 50 ms a frame from the initial lerp on, looping over 10..13
	H.eq(table.concat(frames, ","), "10,11,12,13,10,11,12,13,10")
	-- reversed walks the same frames backwards
	anim.reversed = true
	lf.animationNumber = -1
	lf.frameTime = G.cg.time
	G.CG_RunLerpFrame(ci, lf, C.LEGS_RUN, 1)
	H.eq(lf.frame, 13)
end)

H.test("md3.oam3", function()
	local Md3 = H.require("client/sys/Md3")
	-- feat/conv's packed form: header, 1 frame, 1 tag, no surfaces
	local b = buffer.create(12 + 40 + 12 + 48)
	buffer.writestring(b, 0, "OAM3")
	buffer.writeu16(b, 4, 1)
	buffer.writeu16(b, 6, 1) -- frames
	buffer.writeu16(b, 8, 1) -- tags
	buffer.writeu16(b, 10, 0) -- surfaces
	buffer.writef32(b, 12 + 12 + 8, 56) -- maxs.z
	buffer.writeu8(b, 52, 9)
	buffer.writestring(b, 53, "tag_flash") -- 1 + 9 = 10, padded to 12
	buffer.writef32(b, 64, 7) -- origin.x
	buffer.writef32(b, 64 + 12, 1) -- axis[0].x
	local m = Md3.Load("x", { oam3 = b })
	H.eq(m.numFrames, 1)
	H.near(m.frames[0].maxs[2], 56)
	H.near(m.tags[0].tag_flash.origin[0], 7)
	H.near(m.tags[0].tag_flash.axis[0][0], 1)
end)
