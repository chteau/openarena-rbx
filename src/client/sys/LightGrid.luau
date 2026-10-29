-- The map's light grid, for R_LightForPoint (model lighting).
--
-- Port of R_SetupEntityLightingGrid / R_LightForPoint and the grid half of
-- R_LoadLightGrid (ioquake3 renderergl1 tr_light.c, tr_bsp.c, GPL-2.0).
--
-- The converter ships the BSP light grid lump raw as the `LightGrid` blob
-- (8 bytes a cell: ambient rgb, directed rgb, lat, lng; x fastest, then y,
-- then z) and `map.json`'s `lightgrid` = { origin, size, bounds } in Quake
-- units and cell counts (conv docs/formats/luau-blobs.md). The colour shift
-- R_LoadLightGrid applies is done here, with the same overbright split as the
-- converter's baked lightmaps (r_mapOverBrightBits 2, r_overBrightBits 1).
local LightGrid = {}

-- Set by the place's boot code, like CM.loadLumps: returns the map's
-- `lightgrid` record and the joined blob (LightGrid.join), or nil.
LightGrid.loadGrid = nil :: ((name: string) -> (any, buffer?))?

local MAP_OVERBRIGHT_BITS = 2
local OVERBRIGHT_BITS = 1
local AMBIENT_SCALE = 0.6 -- r_ambientScale
local DIRECTED_SCALE = 1 -- r_directedScale
local FUNCTABLE_SIZE = 1024
local FUNCTABLE_MASK = FUNCTABLE_SIZE - 1

local sinTable = table.create(FUNCTABLE_SIZE)
for i = 0, FUNCTABLE_SIZE - 1 do
	sinTable[i] = math.sin(math.rad(i * 360 / FUNCTABLE_SIZE))
end

local grid: { origin: { number }, inv: { number }, bounds: { number }, data: buffer }? = nil

-- Joins a blob's chunk buffers (conv docs/formats/luau-blobs.md).
function LightGrid.join(parts: { buffer }): buffer
	local total = 0
	for _, b in parts do
		total += buffer.len(b)
	end
	local out = buffer.create(total)
	local o = 0
	for _, b in parts do
		buffer.copy(out, o, b)
		o += buffer.len(b)
	end
	return out
end

-- R_ColorShiftLightingBytes on the 3 bytes at `at`
local function colorShift(data: buffer, at: number)
	local shift = MAP_OVERBRIGHT_BITS - OVERBRIGHT_BITS
	local r = bit32.lshift(buffer.readu8(data, at), shift)
	local g = bit32.lshift(buffer.readu8(data, at + 1), shift)
	local b = bit32.lshift(buffer.readu8(data, at + 2), shift)
	-- normalize by color instead of saturating to white
	if bit32.bor(r, g, b) > 255 then
		local max = math.max(r, g, b)
		r = r * 255 // max
		g = g * 255 // max
		b = b * 255 // max
	end
	buffer.writeu8(data, at, r)
	buffer.writeu8(data, at + 1, g)
	buffer.writeu8(data, at + 2, b)
end

-- Installs a grid (nil clears it). `raw` is the unshifted lump; it is copied.
function LightGrid.set(info: any?, raw: buffer?)
	grid = nil
	if info == nil or raw == nil then
		return
	end
	local bounds = { [0] = info.bounds[1], info.bounds[2], info.bounds[3] }
	local points = bounds[0] * bounds[1] * bounds[2]
	if buffer.len(raw) ~= points * 8 then
		warn(("light grid mismatch: %d bytes, %d cells"):format(buffer.len(raw), points))
		return
	end
	local data = buffer.create(points * 8)
	buffer.copy(data, 0, raw)
	for i = 0, points - 1 do
		colorShift(data, i * 8)
		colorShift(data, i * 8 + 3)
	end
	grid = {
		origin = { [0] = info.origin[1], info.origin[2], info.origin[3] },
		inv = { [0] = 1 / info.size[1], 1 / info.size[2], 1 / info.size[3] },
		bounds = bounds,
		data = data,
	}
end

function LightGrid.Load(name: string)
	local info, raw = nil, nil
	if LightGrid.loadGrid then
		info, raw = LightGrid.loadGrid(name)
	end
	LightGrid.set(info, raw)
end

-- R_LightForPoint: false (and the out vectors untouched) without a grid.
function LightGrid.LightForPoint(point, ambientLight, directedLight, lightDir): boolean
	local g = grid
	if g == nil then
		return false
	end
	local pos, frac = {}, {}
	for i = 0, 2 do
		local v = (point[i] - g.origin[i]) * g.inv[i]
		pos[i] = math.floor(v)
		frac[i] = v - pos[i]
		if pos[i] < 0 then
			pos[i] = 0
		elseif pos[i] > g.bounds[i] - 1 then
			pos[i] = g.bounds[i] - 1
		end
	end
	local amb = { [0] = 0, 0, 0 }
	local dir = { [0] = 0, 0, 0 }
	local direction = { [0] = 0, 0, 0 }
	local gridStep = { [0] = 8, 8 * g.bounds[0], 8 * g.bounds[0] * g.bounds[1] }
	local base = pos[0] * gridStep[0] + pos[1] * gridStep[1] + pos[2] * gridStep[2]
	local data = g.data
	local totalFactor = 0
	for i = 0, 7 do
		local factor = 1.0
		local at = base
		local j = 0
		while j < 3 do
			if bit32.btest(i, bit32.lshift(1, j)) then
				if pos[j] + 1 > g.bounds[j] - 1 then
					break -- ignore values outside lightgrid
				end
				factor *= frac[j]
				at += gridStep[j]
			else
				factor *= 1.0 - frac[j]
			end
			j += 1
		end
		if j == 3 then
			local r, gg, b = buffer.readu8(data, at), buffer.readu8(data, at + 1), buffer.readu8(data, at + 2)
			-- samples in walls are black
			if r + gg + b ~= 0 then
				totalFactor += factor
				amb[0] += factor * r
				amb[1] += factor * gg
				amb[2] += factor * b
				dir[0] += factor * buffer.readu8(data, at + 3)
				dir[1] += factor * buffer.readu8(data, at + 4)
				dir[2] += factor * buffer.readu8(data, at + 5)
				local lat = buffer.readu8(data, at + 7) * (FUNCTABLE_SIZE / 256)
				local lng = buffer.readu8(data, at + 6) * (FUNCTABLE_SIZE / 256)
				-- X = cos(lat) * sin(lng), Y = sin(lat) * sin(lng), Z = cos(lng)
				direction[0] += factor * sinTable[bit32.band(lat + FUNCTABLE_SIZE / 4, FUNCTABLE_MASK)] * sinTable[lng]
				direction[1] += factor * sinTable[lat] * sinTable[lng]
				direction[2] += factor * sinTable[bit32.band(lng + FUNCTABLE_SIZE / 4, FUNCTABLE_MASK)]
			end
		end
	end
	if totalFactor > 0 and totalFactor < 0.99 then
		totalFactor = 1.0 / totalFactor
		for k = 0, 2 do
			amb[k] *= totalFactor
			dir[k] *= totalFactor
		end
	end
	local len = math.sqrt(direction[0] ^ 2 + direction[1] ^ 2 + direction[2] ^ 2)
	for k = 0, 2 do
		ambientLight[k] = amb[k] * AMBIENT_SCALE
		directedLight[k] = dir[k] * DIRECTED_SCALE
		lightDir[k] = if len ~= 0 then direction[k] / len else 0
	end
	return true
end

return LightGrid
