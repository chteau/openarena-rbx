-- The virtual screen (src/ui/Screen.luau): Hor+ FOV, HUD anchors, menus.

local Screen = H.require("ui/Screen")
local NONE = { left = 0, top = 0, right = 0, bottom = 0 }
local PLACES = { Screen.LEFT, Screen.CENTER, Screen.RIGHT, Screen.STRETCH }

local function cgs(w, h, insets)
	Screen.insets = insets or NONE
	local c = { glconfig = { vidWidth = w, vidHeight = h } }
	Screen.cgSetup(c)
	Screen.insets = NONE
	return c
end

-- CG_CalcFov before Hor+: fov_y from fov_x and the view's own aspect
local function oldFovY(fovX, w, h)
	return math.atan2(h, w / math.tan(fovX / 360 * math.pi)) * 360 / math.pi
end

H.test("screen.fov", function()
	-- 4:3: exactly the old fov_x / fov_y, for cg_fov, zoom and intermission
	for _, fov in { 22.5, 90, 110, 160 } do
		for _, size in { { 640, 480 }, { 1024, 768 }, { 1600, 1200 } } do
			local fx, fy = Screen.fov(fov, size[1], size[2])
			H.near(fx, fov, 1e-9)
			H.near(fy, oldFovY(fov, size[1], size[2]), 1e-9)
		end
	end
	-- wider: the 4:3 vertical FOV, more at the sides
	local vy = oldFovY(90, 640, 480)
	for _, c in { { 1280, 720, 106.2602 }, { 1680, 1050, 100.3888 }, { 2560, 1080, 121.2845 } } do
		local fx, fy = Screen.fov(90, c[1], c[2])
		H.near(fy, vy, 1e-9)
		H.near(fx, c[3])
		-- the real camera only takes fov_y; fov_x matches its aspect
		H.near(math.tan(math.rad(fx) / 2) / math.tan(math.rad(fy) / 2), c[1] / c[2], 1e-9)
	end
	-- zoom keeps its 4:3 meaning too
	local _, zy = Screen.fov(22.5, 1280, 720)
	H.near(zy, oldFovY(22.5, 640, 480), 1e-9)
	-- narrower: cg_fov stays horizontal, more above and below
	local fx, fy = Screen.fov(90, 768, 1024)
	H.near(fx, 90, 1e-9)
	H.near(fy, 106.2602)
end)

H.test("screen.identity_4_3", function()
	-- every placement at 4:3 is 0.8.8's stretch: x * w/640, y * h/480
	for _, size in { { 640, 480 }, { 1024, 768 }, { 1600, 1200 }, { 962, 721.5 } } do
		local w, h = size[1], size[2]
		local c = cgs(w, h)
		for _, hp in PLACES do
			for _, vp in PLACES do
				Screen.cgPlace(c, hp, vp)
				for _, r in { { 0, 0, 640, 480 }, { 185, 432, 48, 48 }, { 592, 432, 48, 48 }, { 8, 384, 48, 48 } } do
					local x, y, rw, rh = Screen.cgAdjust(c, r[1], r[2], r[3], r[4])
					H.near(x, r[1] * w / 640, 1e-9)
					H.near(y, r[2] * h / 480, 1e-9)
					H.near(rw, r[3] * w / 640, 1e-9)
					H.near(rh, r[4] * h / 480, 1e-9)
				end
			end
		end
		local uis = { glconfig = { vidWidth = w, vidHeight = h } }
		Screen.uiSetup(uis)
		H.near(uis.bias, 0)
		H.near(uis.ybias, 0)
		H.near(uis.xscale, w / 640, 1e-9)
		H.eq(select("#", Screen.cover(w, h)), 4)
		local s1, t1, s2, t2 = Screen.cover(w, h)
		H.near(s1 + t1, 0, 1e-9)
		H.near(s2 + t2, 2, 1e-9)
	end
end)

-- where a 4:3 point lands per placement: { scale, left, centre, right, top, middle, bottom }
local CASES = {
	["16:9"] = { 1280, 720, 1.5, 0, 160, 320, 0, 0, 0 },
	["16:10"] = { 1680, 1050, 2.1875, 0, 140, 280, 0, 0, 0 },
	["21:9"] = { 2560, 1080, 2.25, 0, 560, 1120, 0, 0, 0 },
	["3:4"] = { 768, 1024, 1.2, 0, 0, 0, 0, 224, 448 },
}

H.test("screen.anchors", function()
	for name, k in CASES do
		local w, h, s = k[1], k[2], k[3]
		local c = cgs(w, h)
		local xs = { [Screen.LEFT] = k[4], [Screen.CENTER] = k[5], [Screen.RIGHT] = k[6] }
		local ys = { [Screen.TOP] = k[7], [Screen.CENTER] = k[8], [Screen.BOTTOM] = k[9] }
		for hp, bx in xs do
			for vp, by in ys do
				Screen.cgPlace(c, hp, vp)
				local x, y, rw, rh = Screen.cgAdjust(c, 100, 50, 48, 48)
				H.near(x, 100 * s + bx, 1e-9, name)
				H.near(y, 50 * s + by, 1e-9, name)
				-- uniform: never stretched
				H.near(rw, rh, 1e-9, name)
			end
		end
		-- a right-pinned element keeps its 4:3 distance from the right edge
		Screen.cgPlace(c, Screen.RIGHT, Screen.BOTTOM)
		local x, y, rw, rh = Screen.cgAdjust(c, 640 - 48, 480 - 48, 48, 48)
		H.near(x + rw, w, 1e-9, name)
		H.near(y + rh, h, 1e-9, name)
		-- nothing leaves the screen, also narrower than 4:3
		Screen.cgPlace(c, Screen.LEFT, Screen.TOP)
		local x0, y0 = Screen.cgAdjust(c, 0, 0, 0, 0)
		H.eq(x0 >= 0 and y0 >= 0, true, name)
		-- full-screen overlays fill it
		Screen.cgPlace(c, Screen.STRETCH, Screen.STRETCH)
		local fx, fy, fw, fh = Screen.cgAdjust(c, 0, 0, 640, 480)
		H.near(fx + fy, 0, 1e-9, name)
		H.near(fw, w, 1e-9, name)
		H.near(fh, h, 1e-9, name)
	end
end)

H.test("screen.insets", function()
	-- a phone in landscape: notches at the sides, the topbar on top
	local c = cgs(1280, 720, { left = 44, top = 36, right = 44, bottom = 20 })
	H.near(c.screenLayout.scale, 1.5)
	Screen.cgPlace(c, Screen.LEFT, Screen.TOP)
	local x, y = Screen.cgAdjust(c, 0, 0, 0, 0)
	H.near(x, 44)
	H.near(y, 36)
	Screen.cgPlace(c, Screen.RIGHT, Screen.BOTTOM)
	x, y = Screen.cgAdjust(c, 640, 480, 0, 0)
	H.near(x, 1280 - 44)
	H.near(y, 720 - 20)
	-- the centre stays the screen's (crosshair, center prints)
	Screen.cgPlace(c, Screen.CENTER, Screen.CENTER)
	x, y = Screen.cgAdjust(c, 320, 240, 0, 0)
	H.near(x, 640)
	H.near(y, 360)
	-- side insets wider than the spare width shrink the layout to fit
	c = cgs(1024, 768, { left = 32, top = 0, right = 32, bottom = 0 })
	H.near(c.screenLayout.scale, 960 / 640)
	Screen.cgPlace(c, Screen.RIGHT, Screen.TOP)
	x = Screen.cgAdjust(c, 640, 0, 0, 0)
	H.near(x, 1024 - 32)
end)

H.test("screen.ui", function()
	local uis = { glconfig = { vidWidth = 1280, vidHeight = 720 } }
	Screen.uiSetup(uis)
	H.near(uis.bias, 160)
	H.near(uis.ybias, 0)
	H.near(uis.xscale, 1.5)
	H.near(uis.yscale, 1.5)
	local vx, vy = Screen.uiToVirtual(uis, 640, 360)
	H.near(vx, 320)
	H.near(vy, 240)
	-- the cursor's reach: the whole screen, side areas included
	vx = Screen.uiToVirtual(uis, 0, 0)
	H.near(vx, -160 / 1.5)
	-- narrower than 4:3: centred vertically, never cropped
	local u2 = { glconfig = { vidWidth = 768, vidHeight = 1024 } }
	Screen.uiSetup(u2)
	H.near(u2.xscale, 1.2)
	H.near(u2.bias, 0)
	H.near(u2.ybias, 224)
	local x, y = Screen.uiAdjust(u2, 640, 480, 0, 0)
	H.near(x, 768)
	H.near(y, 224 + 576)
	-- backgrounds cover: crop top/bottom on wide screens, sides on narrow ones
	local s1, t1, s2, t2 = Screen.cover(1280, 720)
	H.near(s1, 0)
	H.near(t1, 0.125)
	H.near(s2, 1)
	H.near(t2, 0.875)
	s1, t1, s2, t2 = Screen.cover(768, 1024)
	H.near(s1, 0.21875)
	H.near(t1, 0)
	H.near(s2, 0.78125)
	H.near(t2, 1)
end)
