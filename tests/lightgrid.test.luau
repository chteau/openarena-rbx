-- sys/LightGrid: R_LoadLightGrid's colour shift and R_SetupEntityLightingGrid's trilerp.

local function grid(cells: { { number } })
	local b = buffer.create(#cells * 8)
	for i, c in cells do
		for k = 1, 8 do
			buffer.writeu8(b, (i - 1) * 8 + k - 1, c[k])
		end
	end
	return b
end

H.test("lightgrid.none", function()
	local LG = H.require("client/sys/LightGrid")
	LG.set(nil, nil)
	H.eq(LG.LightForPoint({ [0] = 0, 0, 0 }, {}, {}, {}), false)
end)

H.test("lightgrid.trilerp", function()
	local LG = H.require("client/sys/LightGrid")
	-- 2x1x1 grid, 64 u cells from the origin; lng 0 = straight up
	LG.set({ origin = { 0, 0, 0 }, size = { 64, 64, 128 }, bounds = { 2, 1, 1 } },
		grid({ { 10, 20, 30, 40, 50, 60, 0, 0 }, { 30, 40, 50, 60, 70, 80, 0, 0 } }))
	local amb, dir, ldir = {}, {}, {}
	H.eq(LG.LightForPoint({ [0] = 32, 0, 0 }, amb, dir, ldir), true)
	-- shifted left one bit, halfway between the two cells, ambient x 0.6
	H.near(amb[0], 40 * 0.6)
	H.near(amb[2], 80 * 0.6)
	H.near(dir[1], 120)
	H.near(ldir[2], 1)
	-- a black (in-wall) cell is skipped and the rest renormalised
	LG.set({ origin = { 0, 0, 0 }, size = { 64, 64, 128 }, bounds = { 2, 1, 1 } },
		grid({ { 0, 0, 0, 0, 0, 0, 0, 0 }, { 30, 40, 50, 60, 70, 80, 0, 0 } }))
	LG.LightForPoint({ [0] = 16, 0, 0 }, amb, dir, ldir)
	H.near(amb[0], 60 * 0.6)
end)

H.test("lightgrid.shift-normalises", function()
	local LG = H.require("client/sys/LightGrid")
	LG.set({ origin = { 0, 0, 0 }, size = { 64, 64, 128 }, bounds = { 1, 1, 1 } },
		grid({ { 200, 100, 50, 0, 0, 0, 0, 64 } }))
	local amb, dir, ldir = {}, {}, {}
	LG.LightForPoint({ [0] = 0, 0, 0 }, amb, dir, ldir)
	-- 400,200,100 scaled by colour to 255,127,63
	H.near(amb[0], 255 * 0.6)
	H.near(amb[1], 127 * 0.6)
	H.near(amb[2], 63 * 0.6)
	-- dir bytes are all zero: black directed light; lat 64 lng 0 -> up
	H.near(ldir[2], 1)
end)
