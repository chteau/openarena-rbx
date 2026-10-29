--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (the BSP lump layout of qcommon/qfiles.h).

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
-- Parses a raw Quake III BSP (IBSP version 46) buffer into the `lumps` table
-- cm_load.CM_LoadMap consumes. Only the collision lumps are read; patch
-- surfaces keep just their control points.

local Q = require("../q_math")

local BSP = {}

local LUMP_ENTITIES, LUMP_SHADERS, LUMP_PLANES, LUMP_NODES, LUMP_LEAFS = 0, 1, 2, 3, 4
local LUMP_LEAFSURFACES, LUMP_LEAFBRUSHES, LUMP_MODELS, LUMP_BRUSHES, LUMP_BRUSHSIDES = 5, 6, 7, 8, 9
local LUMP_DRAWVERTS, LUMP_SURFACES, LUMP_VISIBILITY = 10, 13, 16
local BSP_VERSION = 46
local MST_PATCH = 2

local ri32, rf32 = buffer.readi32, buffer.readf32

local function lump(buf: buffer, n: number): (number, number)
	return ri32(buf, 8 + n * 8), ri32(buf, 12 + n * 8)
end

local function vec(buf: buffer, o: number)
	return Q.vec3(rf32(buf, o), rf32(buf, o + 4), rf32(buf, o + 8))
end

local function cstring(buf: buffer, o: number, max: number): string
	local s = buffer.readstring(buf, o, max)
	local z = string.find(s, "\0", 1, true)
	return if z then string.sub(s, 1, z - 1) else s
end

local function records(buf: buffer, n: number, size: number, read)
	local ofs, len = lump(buf, n)
	if len % size ~= 0 then
		error("BSP: funny lump size in lump " .. n)
	end
	local out = {}
	for i = 0, len // size - 1 do
		out[i] = read(ofs + i * size)
	end
	return out, len // size
end

function BSP.parse(buf: buffer)
	if buffer.readstring(buf, 0, 4) ~= "IBSP" then
		error("BSP: not an IBSP file")
	end
	local version = ri32(buf, 4)
	if version ~= BSP_VERSION then
		error(string.format("BSP: wrong version number (%i should be %i)", version, BSP_VERSION))
	end

	local lumps: any = {}
	lumps.shaders = records(buf, LUMP_SHADERS, 72, function(o)
		return { shader = cstring(buf, o, 64), surfaceFlags = ri32(buf, o + 64), contentFlags = ri32(buf, o + 68) }
	end)
	lumps.planes = records(buf, LUMP_PLANES, 16, function(o)
		return { normal = vec(buf, o), dist = rf32(buf, o + 12) }
	end)
	lumps.nodes = records(buf, LUMP_NODES, 36, function(o)
		return { planeNum = ri32(buf, o), children = { [0] = ri32(buf, o + 4), ri32(buf, o + 8) } }
	end)
	lumps.leafs = records(buf, LUMP_LEAFS, 48, function(o)
		return {
			cluster = ri32(buf, o),
			area = ri32(buf, o + 4),
			firstLeafSurface = ri32(buf, o + 32),
			numLeafSurfaces = ri32(buf, o + 36),
			firstLeafBrush = ri32(buf, o + 40),
			numLeafBrushes = ri32(buf, o + 44),
		}
	end)
	lumps.leafsurfaces = records(buf, LUMP_LEAFSURFACES, 4, function(o)
		return ri32(buf, o)
	end)
	lumps.leafbrushes = records(buf, LUMP_LEAFBRUSHES, 4, function(o)
		return ri32(buf, o)
	end)
	lumps.models = records(buf, LUMP_MODELS, 40, function(o)
		return {
			mins = vec(buf, o),
			maxs = vec(buf, o + 12),
			firstSurface = ri32(buf, o + 24),
			numSurfaces = ri32(buf, o + 28),
			firstBrush = ri32(buf, o + 32),
			numBrushes = ri32(buf, o + 36),
		}
	end)
	lumps.brushes = records(buf, LUMP_BRUSHES, 12, function(o)
		return { firstSide = ri32(buf, o), numSides = ri32(buf, o + 4), shaderNum = ri32(buf, o + 8) }
	end)
	lumps.brushsides = records(buf, LUMP_BRUSHSIDES, 8, function(o)
		return { planeNum = ri32(buf, o), shaderNum = ri32(buf, o + 4) }
	end)

	local eofs, elen = lump(buf, LUMP_ENTITIES)
	lumps.entities = cstring(buf, eofs, elen)

	local vofs, vlen = lump(buf, LUMP_VISIBILITY)
	if vlen > 0 then
		local v = buffer.create(vlen)
		buffer.copy(v, 0, buf, vofs, vlen)
		lumps.visibility = v
	end

	-- patches: only their control points matter for collision
	local dvofs, dvlen = lump(buf, LUMP_DRAWVERTS)
	if dvlen % 44 ~= 0 then
		error("BSP: funny drawvert lump size")
	end
	local sofs, slen = lump(buf, LUMP_SURFACES)
	if slen % 104 ~= 0 then
		error("BSP: funny surface lump size")
	end
	local numSurfaces = slen // 104
	local patches = {}
	for i = 0, numSurfaces - 1 do
		local o = sofs + i * 104
		if ri32(buf, o + 8) ~= MST_PATCH then
			continue
		end
		local width, height = ri32(buf, o + 96), ri32(buf, o + 100)
		local firstVert = ri32(buf, o + 12)
		local points = {}
		for j = 0, width * height - 1 do
			points[j] = vec(buf, dvofs + (firstVert + j) * 44)
		end
		patches[i] = { shaderNum = ri32(buf, o), width = width, height = height, points = points }
	end
	lumps.numSurfaces = numSurfaces
	lumps.patches = patches

	return lumps
end

return BSP
