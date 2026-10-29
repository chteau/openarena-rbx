--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (qcommon/cm_load.c).

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
===========================================================================
]]
--!native
--[[
Builds the in-memory clip map (cm_local's L.cm) from parsed BSP lumps.

The loader never touches file bytes: it takes a `lumps` table, so any source
(a raw .bsp through bsp.luau, or the converter's collision blob through its
own adapter) only has to produce this shape. All arrays are 0-based:

	lumps = {
		shaders      = { [i] = { shader = string, surfaceFlags, contentFlags } },
		planes       = { [i] = { normal = {[0]=x,y,z}, dist } },
		nodes        = { [i] = { planeNum, children = {[0]=front, back} } },
		leafs        = { [i] = { cluster, area, firstLeafSurface, numLeafSurfaces,
		                         firstLeafBrush, numLeafBrushes } },
		leafsurfaces = { [i] = surfaceNum },
		leafbrushes  = { [i] = brushNum },
		models       = { [i] = { mins = vec3, maxs = vec3, firstSurface, numSurfaces,
		                         firstBrush, numBrushes } },
		brushes      = { [i] = { firstSide, numSides, shaderNum } },
		brushsides   = { [i] = { planeNum, shaderNum } },
		entities     = string,
		visibility   = buffer? (the raw lump: numClusters, clusterBytes, bits),
		numSurfaces  = number,
		patches      = { [surfaceNum] = { shaderNum, width, height, points = {[0]=vec3...} } },
	}

Floats must already be float32 values (they are, when read with readf32).
]]

local Q = require("../q_math")
local S = require("../structs")
local L = require("./cm_local")
require("./cm_test")
require("./cm_patch")

local f, vec3 = Q.f, Q.vec3

-- to allow boxes to be treated as brush models, we allocate
-- some extra indexes along with those needed by the map
local BOX_SIDES = 6
local BOX_PLANES = 12
local CONTENTS_BODY = 0x2000000
local MAX_SUBMODELS = L.MAX_SUBMODELS

local box_model = { mins = vec3(), maxs = vec3(), leaf = nil :: any }
local box_planes = {} -- [0..11] references into cm.planes
local box_brush = nil :: any

local function count(t): number
	local n = 0
	while t[n] ~= nil do
		n += 1
	end
	return n
end

local function newPlane(normal0: number, normal1: number, normal2: number, dist: number)
	local p = S.cplane_t()
	p.normal[0], p.normal[1], p.normal[2] = normal0, normal1, normal2
	p.dist = dist
	p.type = Q.PlaneTypeForNormal(p.normal)
	Q.SetPlaneSignbits(p)
	return p
end

local function newLeaf()
	return { cluster = 0, area = 0, firstLeafBrush = 0, numLeafBrushes = 0, firstLeafSurface = 0, numLeafSurfaces = 0 }
end

local function CMod_LoadShaders(lumps)
	local cm = L.cm
	local n = count(lumps.shaders)
	if n < 1 then
		error("Map with no shaders")
	end
	for i = 0, n - 1 do
		local s = lumps.shaders[i]
		cm.shaders[i] = { shader = s.shader, surfaceFlags = s.surfaceFlags, contentFlags = s.contentFlags }
	end
	cm.numShaders = n
end

local function CMod_LoadLeafs(lumps)
	local cm = L.cm
	local n = count(lumps.leafs)
	if n < 1 then
		error("Map with no leafs")
	end
	for i = 0, n - 1 do
		local s = lumps.leafs[i]
		local out = newLeaf()
		out.cluster = s.cluster
		out.area = s.area
		out.firstLeafBrush = s.firstLeafBrush
		out.numLeafBrushes = s.numLeafBrushes
		out.firstLeafSurface = s.firstLeafSurface
		out.numLeafSurfaces = s.numLeafSurfaces
		cm.leafs[i] = out
		if out.cluster >= cm.numClusters then
			cm.numClusters = out.cluster + 1
		end
		if out.area >= cm.numAreas then
			cm.numAreas = out.area + 1
		end
	end
	cm.numLeafs = n
	-- BOX_LEAFS extra leafs
	cm.leafs[n] = newLeaf()
	cm.leafs[n + 1] = newLeaf()

	for i = 0, cm.numAreas - 1 do
		cm.areas[i] = { floodnum = 0, floodvalid = 0 }
	end
	for i = 0, cm.numAreas * cm.numAreas - 1 do
		cm.areaPortals[i] = 0
	end
end

local function CMod_LoadLeafBrushes(lumps)
	local cm = L.cm
	local n = count(lumps.leafbrushes)
	for i = 0, n - 1 do
		cm.leafbrushes[i] = lumps.leafbrushes[i]
	end
	cm.numLeafBrushes = n
end

local function CMod_LoadLeafSurfaces(lumps)
	local cm = L.cm
	local n = count(lumps.leafsurfaces)
	for i = 0, n - 1 do
		cm.leafsurfaces[i] = lumps.leafsurfaces[i]
	end
	cm.numLeafSurfaces = n
end

local function CMod_LoadPlanes(lumps)
	local cm = L.cm
	local n = count(lumps.planes)
	if n < 1 then
		error("Map with no planes")
	end
	for i = 0, n - 1 do
		local s = lumps.planes[i]
		cm.planes[i] = newPlane(s.normal[0], s.normal[1], s.normal[2], s.dist)
	end
	cm.numPlanes = n
	for i = 0, BOX_PLANES - 1 do
		cm.planes[n + i] = S.cplane_t()
	end
end

local function CMod_LoadBrushSides(lumps)
	local cm = L.cm
	local n = count(lumps.brushsides)
	for i = 0, n - 1 do
		local s = lumps.brushsides[i]
		if s.shaderNum < 0 or s.shaderNum >= cm.numShaders then
			error(string.format("CMod_LoadBrushSides: bad shaderNum: %i", s.shaderNum))
		end
		cm.brushsides[i] = {
			plane = cm.planes[s.planeNum],
			shaderNum = s.shaderNum,
			surfaceFlags = cm.shaders[s.shaderNum].surfaceFlags,
		}
	end
	cm.numBrushSides = n
	for i = 0, BOX_SIDES - 1 do
		cm.brushsides[n + i] = { plane = nil :: any, shaderNum = 0, surfaceFlags = 0 }
	end
end

local function CM_BoundBrush(b)
	local s = b.sides
	b.bounds[0][0] = -s[0].plane.dist
	b.bounds[1][0] = s[1].plane.dist
	b.bounds[0][1] = -s[2].plane.dist
	b.bounds[1][1] = s[3].plane.dist
	b.bounds[0][2] = -s[4].plane.dist
	b.bounds[1][2] = s[5].plane.dist
end

local function sideList(first: number, n: number)
	local cm = L.cm
	local t = {}
	for i = 0, n - 1 do
		t[i] = cm.brushsides[first + i]
	end
	return t
end

local function CMod_LoadBrushes(lumps)
	local cm = L.cm
	local n = count(lumps.brushes)
	for i = 0, n - 1 do
		local s = lumps.brushes[i]
		if s.shaderNum < 0 or s.shaderNum >= cm.numShaders then
			error(string.format("CMod_LoadBrushes: bad shaderNum: %i", s.shaderNum))
		end
		local out = {
			shaderNum = s.shaderNum,
			contents = cm.shaders[s.shaderNum].contentFlags,
			bounds = { [0] = vec3(), vec3() },
			numsides = s.numSides,
			sides = sideList(s.firstSide, s.numSides),
			checkcount = 0,
		}
		CM_BoundBrush(out)
		cm.brushes[i] = out
	end
	cm.numBrushes = n
end

local function CMod_LoadSubmodels(lumps)
	local cm = L.cm
	local n = count(lumps.models)
	if n < 1 then
		error("Map with no models")
	end
	if n > MAX_SUBMODELS then
		error("MAX_SUBMODELS exceeded")
	end
	-- submodel brush/surface index lists live past the map's own lists and the
	-- box hull's slot (the C code allocates them on the hunk)
	local nextBrush = cm.numLeafBrushes + 1
	local nextSurf = cm.numLeafSurfaces
	for i = 0, n - 1 do
		local s = lumps.models[i]
		local out = { mins = vec3(), maxs = vec3(), leaf = newLeaf() }
		for j = 0, 2 do
			-- spread the mins / maxs by a pixel
			out.mins[j] = f(s.mins[j] - 1)
			out.maxs[j] = f(s.maxs[j] + 1)
		end
		cm.cmodels[i] = out
		if i == 0 then
			continue -- world model doesn't need other info
		end

		-- make a "leaf" just to hold the model's brushes and surfaces
		out.leaf.numLeafBrushes = s.numBrushes
		out.leaf.firstLeafBrush = nextBrush
		for j = 0, s.numBrushes - 1 do
			cm.leafbrushes[nextBrush + j] = s.firstBrush + j
		end
		nextBrush += s.numBrushes

		out.leaf.numLeafSurfaces = s.numSurfaces
		out.leaf.firstLeafSurface = nextSurf
		for j = 0, s.numSurfaces - 1 do
			cm.leafsurfaces[nextSurf + j] = s.firstSurface + j
		end
		nextSurf += s.numSurfaces
	end
	cm.numSubModels = n
end

local function CMod_LoadNodes(lumps)
	local cm = L.cm
	local n = count(lumps.nodes)
	if n < 1 then
		error("Map has no nodes")
	end
	for i = 0, n - 1 do
		local s = lumps.nodes[i]
		cm.nodes[i] = { plane = cm.planes[s.planeNum], children = { [0] = s.children[0], s.children[1] } }
	end
	cm.numNodes = n
end

local function CMod_LoadVisibility(lumps)
	local cm = L.cm
	local vis = lumps.visibility
	local len = if vis then buffer.len(vis) else 0
	if len == 0 then
		cm.clusterBytes = bit32.band(cm.numClusters + 31, bit32.bnot(31))
		cm.visibility = buffer.create(cm.clusterBytes)
		buffer.fill(cm.visibility :: buffer, 0, 255)
		return
	end
	cm.vised = true
	cm.numClusters = buffer.readi32(vis, 0)
	cm.clusterBytes = buffer.readi32(vis, 4)
	local v = buffer.create(len - 8)
	buffer.copy(v, 0, vis, 8, len - 8)
	cm.visibility = v
end

local function CMod_LoadPatches(lumps)
	local cm = L.cm
	cm.numSurfaces = lumps.numSurfaces or 0
	for i, p in lumps.patches or {} do
		-- FIXME: check for non-colliding patches
		local shader = cm.shaders[p.shaderNum]
		cm.surfaces[i] = {
			checkcount = 0,
			contents = shader.contentFlags,
			surfaceFlags = shader.surfaceFlags,
			-- create the internal facet structure
			pc = L.CM_GeneratePatchCollide(p.width, p.height, p.points),
		}
	end
end

-- Set up the planes and nodes so that the six floats of a bounding box
-- can just be stored out and get a proper clipping hull structure.
local function CM_InitBoxHull()
	local cm = L.cm
	for i = 0, BOX_PLANES - 1 do
		box_planes[i] = cm.planes[cm.numPlanes + i]
	end

	box_brush = {
		shaderNum = 0,
		contents = CONTENTS_BODY,
		bounds = { [0] = vec3(), vec3() },
		numsides = 6,
		sides = sideList(cm.numBrushSides, BOX_SIDES),
		checkcount = 0,
	}
	cm.brushes[cm.numBrushes] = box_brush

	local leaf = newLeaf()
	leaf.numLeafBrushes = 1
	leaf.firstLeafBrush = cm.numLeafBrushes
	cm.leafbrushes[cm.numLeafBrushes] = cm.numBrushes
	box_model.leaf = leaf

	for i = 0, 5 do
		local side = bit32.band(i, 1)

		-- brush sides
		local s = cm.brushsides[cm.numBrushSides + i]
		s.plane = cm.planes[cm.numPlanes + i * 2 + side]
		s.surfaceFlags = 0

		-- planes
		local p = box_planes[i * 2]
		p.type = bit32.rshift(i, 1)
		p.signbits = 0
		Q.VectorClear(p.normal)
		p.normal[bit32.rshift(i, 1)] = 1

		p = box_planes[i * 2 + 1]
		p.type = 3 + bit32.rshift(i, 1)
		p.signbits = 0
		Q.VectorClear(p.normal)
		p.normal[bit32.rshift(i, 1)] = -1

		Q.SetPlaneSignbits(p)
	end
end

-- Loads in the map and all submodels.
function L.CM_LoadMap(name: string, lumps)
	L.cm = L.emptyMap()
	L.CM_ClearLevelPatches()

	CMod_LoadShaders(lumps)
	CMod_LoadLeafs(lumps)
	CMod_LoadLeafBrushes(lumps)
	CMod_LoadLeafSurfaces(lumps)
	CMod_LoadPlanes(lumps)
	CMod_LoadBrushSides(lumps)
	CMod_LoadBrushes(lumps)
	CMod_LoadSubmodels(lumps)
	CMod_LoadNodes(lumps)
	L.cm.entityString = lumps.entities or ""
	L.cm.numEntityChars = #L.cm.entityString
	CMod_LoadVisibility(lumps)
	CMod_LoadPatches(lumps)

	CM_InitBoxHull()
	L.CM_FloodAreaConnections()

	L.cm.name = name
end

function L.CM_ClearMap()
	L.cm = L.emptyMap()
	L.CM_ClearLevelPatches()
end

function L.CM_ClipHandleToModel(handle: number)
	local cm = L.cm
	if handle < 0 then
		error(string.format("CM_ClipHandleToModel: bad handle %i", handle))
	end
	if handle < cm.numSubModels then
		return cm.cmodels[handle]
	end
	if handle == L.BOX_MODEL_HANDLE or handle == L.CAPSULE_MODEL_HANDLE then
		-- the capsule handle only reads the bounds CM_TempBoxModel stored
		return box_model
	end
	error(string.format("CM_ClipHandleToModel: bad handle %i", handle))
end

function L.CM_InlineModel(index: number): number
	if index < 0 or index >= L.cm.numSubModels then
		error("CM_InlineModel: bad number")
	end
	return index
end

function L.CM_NumClusters(): number
	return L.cm.numClusters
end

function L.CM_NumInlineModels(): number
	return L.cm.numSubModels
end

function L.CM_EntityString(): string
	return L.cm.entityString
end

function L.CM_LeafCluster(leafnum: number): number
	if leafnum < 0 or leafnum >= L.cm.numLeafs then
		error("CM_LeafCluster: bad number")
	end
	return L.cm.leafs[leafnum].cluster
end

function L.CM_LeafArea(leafnum: number): number
	if leafnum < 0 or leafnum >= L.cm.numLeafs then
		error("CM_LeafArea: bad number")
	end
	return L.cm.leafs[leafnum].area
end

-- To keep everything totally uniform, bounding boxes are turned into small
-- BSP trees instead of being compared directly.
-- Capsules are handled differently though.
function L.CM_TempBoxModel(mins, maxs, capsule: boolean?): number
	Q.VectorCopy(mins, box_model.mins)
	Q.VectorCopy(maxs, box_model.maxs)

	if capsule then
		return L.CAPSULE_MODEL_HANDLE
	end

	box_planes[0].dist = maxs[0]
	box_planes[1].dist = -maxs[0]
	box_planes[2].dist = mins[0]
	box_planes[3].dist = -mins[0]
	box_planes[4].dist = maxs[1]
	box_planes[5].dist = -maxs[1]
	box_planes[6].dist = mins[1]
	box_planes[7].dist = -mins[1]
	box_planes[8].dist = maxs[2]
	box_planes[9].dist = -maxs[2]
	box_planes[10].dist = mins[2]
	box_planes[11].dist = -mins[2]

	Q.VectorCopy(mins, box_brush.bounds[0])
	Q.VectorCopy(maxs, box_brush.bounds[1])

	return L.BOX_MODEL_HANDLE
end

function L.CM_ModelBounds(model: number, mins, maxs)
	local cmod = L.CM_ClipHandleToModel(model)
	Q.VectorCopy(cmod.mins, mins)
	Q.VectorCopy(cmod.maxs, maxs)
end

return L
