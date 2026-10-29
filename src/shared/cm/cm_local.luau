--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (qcommon/cm_local.h).

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
-- Shared state of the collision model (the C globals of cm_local.h).
-- Every cm_* module stores its functions in this table, so they can call
-- each other the way the C files do through the global namespace.

local L = {}

L.MAX_SUBMODELS = 256
L.BOX_MODEL_HANDLE = 255
L.CAPSULE_MODEL_HANDLE = 254
-- keep 1/8 unit away to keep the position valid before network snapping
L.SURFACE_CLIP_EPSILON = 0.125

-- cvars the collision code reads (cm_noAreas, cm_noCurves, cm_playerCurveClip)
L.cvars = { cm_noAreas = 0, cm_noCurves = 0, cm_playerCurveClip = 1 }

L.counters = { c_pointcontents = 0, c_traces = 0, c_brush_traces = 0, c_patch_traces = 0 }

-- clipMap_t; arrays are 0-based like the C ones
local function emptyMap()
	return {
		name = "",
		numShaders = 0,
		shaders = {},
		numBrushSides = 0,
		brushsides = {},
		numPlanes = 0,
		planes = {},
		numNodes = 0,
		nodes = {},
		numLeafs = 0,
		leafs = {},
		numLeafBrushes = 0,
		leafbrushes = {},
		numLeafSurfaces = 0,
		leafsurfaces = {},
		numSubModels = 0,
		cmodels = {},
		numBrushes = 0,
		brushes = {},
		numClusters = 0,
		clusterBytes = 0,
		visibility = nil :: buffer?,
		vised = false,
		numEntityChars = 0,
		entityString = "",
		numAreas = 0,
		areas = {},
		areaPortals = {},
		numSurfaces = 0,
		surfaces = {},
		floodvalid = 0,
		checkcount = 0,
	}
end
L.emptyMap = emptyMap
L.cm = emptyMap()

function L.Com_Error(fmt: string, ...)
	error(string.format(fmt, ...), 2)
end

return L
