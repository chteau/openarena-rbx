--[[
Adapter from the converter's shipped map blobs to the `lumps` table
cm_load.CM_LoadMap consumes (the shape documented in cm_load.luau).

	Blob.join(chunks)              -- {buffer} in chunk order -> one buffer
	Blob.lumps(collision, entities) -- OACM collision blob (docs/formats/collision.md)
	                                -- + decoded Entities JSON (docs/formats/entities.md) -> lumps
	Blob.entityString(entities)     -- the decoded Entities JSON -> a BSP-style entity string

Patches arrive with their collision already generated offline (PATC, PPLN,
FACE), so cm_load uses them as they are instead of running
CM_GeneratePatchCollide. Shader names are not in the blob; collision never
reads them.
]]

local Q = require("../q_math")

local Blob = {}

local ri32, rf32, ru32, ru8 = buffer.readi32, buffer.readf32, buffer.readu32, buffer.readu8
local vec3 = Q.vec3

function Blob.join(chunks: { buffer }): buffer
	local total = 0
	for _, b in chunks do
		total += buffer.len(b)
	end
	local out = buffer.create(total)
	local o = 0
	for _, b in chunks do
		buffer.copy(out, o, b)
		o += buffer.len(b)
	end
	return out
end

local function vec(buf: buffer, o: number)
	return vec3(rf32(buf, o), rf32(buf, o + 4), rf32(buf, o + 8))
end

-- section fourcc -> { count, offset, length }
local function sections(buf: buffer)
	if buffer.readstring(buf, 0, 4) ~= "OACM" then
		error("collision blob: bad magic")
	end
	if ru32(buf, 4) ~= 1 then
		error("collision blob: unsupported version " .. ru32(buf, 4))
	end
	local t = {}
	for i = 0, ru32(buf, 8) - 1 do
		local e = 12 + i * 16
		t[buffer.readstring(buf, e, 4)] = { count = ru32(buf, e + 4), offset = ru32(buf, e + 8), length = ru32(buf, e + 12) }
	end
	return t
end

local function records(buf: buffer, sec, size: number, read)
	local out = {}
	for i = 0, sec.count - 1 do
		out[i] = read(sec.offset + i * size)
	end
	return out
end

local function quote(s: string): string
	return '"' .. s .. '"'
end

-- Rebuilds the entity lump text from entities.json. JSON objects carry no
-- key order (the converter writes them sorted) and keep the last of
-- duplicate keys, so each entity's pairs come out sorted by key, classname
-- first, as distinct keys.
function Blob.entityString(entities): string
	local out = {}
	for _, e in entities.entities do
		local keys = {}
		for k in e.keys do
			if k ~= "classname" then
				table.insert(keys, k)
			end
		end
		table.sort(keys)
		table.insert(out, "{\n")
		if e.keys.classname ~= nil then
			table.insert(out, quote("classname") .. " " .. quote(e.keys.classname) .. "\n")
		end
		for _, k in keys do
			table.insert(out, quote(k) .. " " .. quote(e.keys[k]) .. "\n")
		end
		table.insert(out, "}\n")
	end
	return table.concat(out)
end

function Blob.lumps(buf: buffer, entities)
	local sec = sections(buf)
	local lumps: any = {}

	lumps.shaders = records(buf, sec.SHDR, 8, function(o)
		return { shader = "", surfaceFlags = ri32(buf, o), contentFlags = ri32(buf, o + 4) }
	end)
	lumps.planes = records(buf, sec.PLAN, 16, function(o)
		return { normal = vec(buf, o), dist = rf32(buf, o + 12) }
	end)
	lumps.nodes = records(buf, sec.NODE, 12, function(o)
		return { planeNum = ri32(buf, o), children = { [0] = ri32(buf, o + 4), ri32(buf, o + 8) } }
	end)
	lumps.leafs = records(buf, sec.LEAF, 24, function(o)
		return {
			cluster = ri32(buf, o),
			area = ri32(buf, o + 4),
			firstLeafBrush = ri32(buf, o + 8),
			numLeafBrushes = ri32(buf, o + 12),
			firstLeafSurface = ri32(buf, o + 16),
			numLeafSurfaces = ri32(buf, o + 20),
		}
	end)
	lumps.leafbrushes = records(buf, sec.LBRK, 4, function(o)
		return ri32(buf, o)
	end)
	lumps.leafsurfaces = records(buf, sec.LSRF, 4, function(o)
		return ri32(buf, o)
	end)
	lumps.brushes = records(buf, sec.BRSH, 12, function(o)
		return { firstSide = ri32(buf, o), numSides = ri32(buf, o + 4), shaderNum = ri32(buf, o + 8) }
	end)
	lumps.brushsides = records(buf, sec.BSID, 8, function(o)
		return { planeNum = ri32(buf, o), shaderNum = ri32(buf, o + 4) }
	end)
	lumps.models = records(buf, sec.MODL, 40, function(o)
		return {
			mins = vec(buf, o),
			maxs = vec(buf, o + 12),
			firstBrush = ri32(buf, o + 24),
			numBrushes = ri32(buf, o + 28),
			firstSurface = ri32(buf, o + 32),
			numSurfaces = ri32(buf, o + 36),
		}
	end)

	-- VISI: numClusters, clusterBytes, bits; the same bytes as the raw lump
	local vis = sec.VISI
	if vis.count > 0 then
		local v = buffer.create(8 + vis.count)
		buffer.copy(v, 0, buf, vis.offset, 8 + vis.count)
		lumps.visibility = v
	end

	-- the surface count is what CM_LoadPatches sizes cm.surfaces with: every
	-- leaf and model surface index is below it
	local numSurfaces = 0
	for i = 0, sec.LSRF.count - 1 do
		numSurfaces = math.max(numSurfaces, lumps.leafsurfaces[i] + 1)
	end
	for _, m in lumps.models do
		numSurfaces = math.max(numSurfaces, m.firstSurface + m.numSurfaces)
	end

	local ppln, face = sec.PPLN, sec.FACE
	local patches = {}
	for i = 0, sec.PATC.count - 1 do
		local o = sec.PATC.offset + i * 60
		local surface = ri32(buf, o)
		local planeFirst, planeCount = ri32(buf, o + 44), ri32(buf, o + 48)
		local facetFirst, facetCount = ri32(buf, o + 52), ri32(buf, o + 56)
		local planes = {}
		for p = 0, planeCount - 1 do
			local po = ppln.offset + (planeFirst + p) * 20
			planes[p] = {
				plane = { [0] = rf32(buf, po), rf32(buf, po + 4), rf32(buf, po + 8), rf32(buf, po + 12) },
				signbits = ri32(buf, po + 16),
			}
		end
		local facets = {}
		for fi = 0, facetCount - 1 do
			local fo = face.offset + (facetFirst + fi) * 164
			local numBorders = ri32(buf, fo + 4)
			local borderPlanes, borderInward, borderNoAdjust = {}, {}, {}
			for k = 0, 25 do
				borderPlanes[k] = ri32(buf, fo + 8 + k * 4)
				borderInward[k] = ru8(buf, fo + 112 + k) ~= 0
				borderNoAdjust[k] = ru8(buf, fo + 138 + k) ~= 0
			end
			facets[fi] = {
				surfacePlane = ri32(buf, fo),
				numBorders = numBorders,
				borderPlanes = borderPlanes,
				borderInward = borderInward,
				borderNoAdjust = borderNoAdjust,
			}
		end
		patches[surface] = {
			contents = ri32(buf, o + 4),
			surfaceFlags = ri32(buf, o + 8),
			width = ri32(buf, o + 12),
			height = ri32(buf, o + 16),
			pc = {
				bounds = { [0] = vec(buf, o + 20), vec(buf, o + 32) },
				numPlanes = planeCount,
				planes = planes,
				numFacets = facetCount,
				facets = facets,
			},
		}
		numSurfaces = math.max(numSurfaces, surface + 1)
	end
	lumps.patches = patches
	lumps.numSurfaces = numSurfaces
	lumps.entities = if entities then Blob.entityString(entities) else ""
	return lumps
end

return Blob
