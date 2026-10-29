--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (qcommon/cm_patch.c).

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
Patch collision: curved surfaces become a set of facets bounded by border
planes, plus axial and edge bevels.

	patchCollide = { bounds = {[0]=mins, maxs}, numPlanes, planes = {[0]=patchPlane},
	                 numFacets, facets = {[0]=facet} }
	patchPlane   = { plane = {[0]=nx, ny, nz, dist}, signbits }
	facet        = { surfacePlane, numBorders, borderPlanes = {[0]=...},
	                 borderInward = {[0]=bool...}, borderNoAdjust = {[0]=bool...} }
]]

local Q = require("../q_math")
local L = require("./cm_local")
local P = require("./cm_polylib")

local f, vec3 = Q.f, Q.vec3
local abs = math.abs
local DotProduct, VectorSubtract, VectorCopy, VectorMA, CrossProduct =
	Q.DotProduct, Q.VectorSubtract, Q.VectorCopy, Q.VectorMA, Q.CrossProduct
local VectorNormalize = Q.VectorNormalizeIoq3
local SURFACE_CLIP_EPSILON = L.SURFACE_CLIP_EPSILON

local MAX_FACETS = 1024
local MAX_PATCH_PLANES = 4096
local MAX_GRID_SIZE = 129
local SUBDIVIDE_DISTANCE = 16
local PLANE_TRI_EPSILON = 0.1
local WRAP_POINT_EPSILON = 0.1
local POINT_EPSILON = 0.1
local NORMAL_EPSILON = 0.0001
local DIST_EPSILON = 0.02
local MAX_BORDERS = 4 + 6 + 16
local F01 = f(0.1) -- the 0.1f chop epsilon
local SIDE_FRONT, SIDE_BACK, SIDE_ON = 0, 1, 2

local EN_TOP, EN_RIGHT, EN_BOTTOM, EN_LEFT = 0, 1, 2, 3

local function vec4()
	return { [0] = 0, 0, 0, 0 }
end

local function CM_SignbitsForNormal(normal): number
	local bits = 0
	for j = 0, 2 do
		if normal[j] < 0 then
			bits = bit32.bor(bits, bit32.lshift(1, j))
		end
	end
	return bits
end

-- Returns false if the triangle is degenrate.
-- The normal will point out of the clock for clockwise ordered points
local function CM_PlaneFromPoints(plane, a, b, c): boolean
	local d1, d2 = vec3(), vec3()
	VectorSubtract(b, a, d1)
	VectorSubtract(c, a, d2)
	CrossProduct(d2, d1, plane)
	if VectorNormalize(plane) == 0 then
		return false
	end
	plane[3] = DotProduct(a, plane)
	return true
end

--[[
================================================================================
GRID SUBDIVISION
================================================================================
]]

-- Returns true if the given quadratic curve is not flat enough for our
-- collision detection purposes
local function CM_NeedsSubdivision(a, b, c): boolean
	local delta = vec3()
	for i = 0, 2 do
		-- linear midpoint and exact curve midpoint (0.5 is a double constant)
		local lmid = f(0.5 * f(a[i] + c[i]))
		local cmid = f(0.5 * (0.5 * f(a[i] + b[i]) + 0.5 * f(b[i] + c[i])))
		delta[i] = f(cmid - lmid)
	end
	local dist = Q.VectorLength(delta)
	return dist >= SUBDIVIDE_DISTANCE
end

-- a, b, and c are control points.
-- the subdivided sequence will be: a, out1, out2, out3, c
local function CM_Subdivide(a, b, c, out1, out2, out3)
	for i = 0, 2 do
		out1[i] = f(0.5 * f(a[i] + b[i]))
		out3[i] = f(0.5 * f(b[i] + c[i]))
		out2[i] = f(0.5 * f(out1[i] + out3[i]))
	end
end

-- grid.points[i][j], columns created on first touch (the C grid is a fixed
-- 129x129 array)
local function newGrid()
	local points = {}
	for i = 0, MAX_GRID_SIZE - 1 do
		local col = {}
		points[i] = col
	end
	return { width = 0, height = 0, wrapWidth = false, wrapHeight = false, points = points }
end

local function pt(grid, i: number, j: number)
	local col = grid.points[i]
	local p = col[j]
	if not p then
		p = vec3()
		col[j] = p
	end
	return p
end

-- Swaps the rows and columns in place
local function CM_TransposeGrid(grid)
	local temp = vec3()
	if grid.width > grid.height then
		for i = 0, grid.height - 1 do
			for j = i + 1, grid.width - 1 do
				if j < grid.height then
					-- swap the value
					VectorCopy(pt(grid, i, j), temp)
					VectorCopy(pt(grid, j, i), pt(grid, i, j))
					VectorCopy(temp, pt(grid, j, i))
				else
					-- just copy
					VectorCopy(pt(grid, j, i), pt(grid, i, j))
				end
			end
		end
	else
		for i = 0, grid.width - 1 do
			for j = i + 1, grid.height - 1 do
				if j < grid.width then
					-- swap the value
					VectorCopy(pt(grid, j, i), temp)
					VectorCopy(pt(grid, i, j), pt(grid, j, i))
					VectorCopy(temp, pt(grid, i, j))
				else
					-- just copy
					VectorCopy(pt(grid, i, j), pt(grid, j, i))
				end
			end
		end
	end

	grid.width, grid.height = grid.height, grid.width
	grid.wrapWidth, grid.wrapHeight = grid.wrapHeight, grid.wrapWidth
end

-- If the left and right columns are exactly equal, set grid->wrapWidth qtrue
local function CM_SetGridWrapWidth(grid)
	local i = 0
	while i < grid.height do
		local j = 0
		while j < 3 do
			local d = f(pt(grid, 0, i)[j] - pt(grid, grid.width - 1, i)[j])
			if d < -WRAP_POINT_EPSILON or d > WRAP_POINT_EPSILON then
				break
			end
			j += 1
		end
		if j ~= 3 then
			break
		end
		i += 1
	end
	grid.wrapWidth = i == grid.height
end

-- Adds columns as necessary to the grid until
-- all the aproximating points are within SUBDIVIDE_DISTANCE
-- from the true curve
local function CM_SubdivideGridColumns(grid)
	local i = 0
	while i < grid.width - 2 do
		-- grid->points[i][x] is an interpolating control point
		-- grid->points[i+1][x] is an aproximating control point
		-- grid->points[i+2][x] is an interpolating control point

		-- first see if we can collapse the aproximating collumn away
		local j = 0
		while j < grid.height do
			if CM_NeedsSubdivision(pt(grid, i, j), pt(grid, i + 1, j), pt(grid, i + 2, j)) then
				break
			end
			j += 1
		end
		if j == grid.height then
			-- all of the points were close enough to the linear midpoints
			-- that we can collapse the entire column away
			for jj = 0, grid.height - 1 do
				-- remove the column
				for k = i + 2, grid.width - 1 do
					VectorCopy(pt(grid, k, jj), pt(grid, k - 1, jj))
				end
			end
			grid.width -= 1
			-- go to the next curve segment
			i += 1
			continue
		end

		-- we need to subdivide the curve
		local prev, mid, nxt = vec3(), vec3(), vec3()
		for jj = 0, grid.height - 1 do
			-- save the control points now
			VectorCopy(pt(grid, i, jj), prev)
			VectorCopy(pt(grid, i + 1, jj), mid)
			VectorCopy(pt(grid, i + 2, jj), nxt)

			-- make room for two additional columns in the grid
			-- columns i+1 will be replaced, column i+2 will become i+4
			-- i+1, i+2, and i+3 will be generated
			for k = grid.width - 1, i + 2, -1 do
				VectorCopy(pt(grid, k, jj), pt(grid, k + 2, jj))
			end

			-- generate the subdivided points
			CM_Subdivide(prev, mid, nxt, pt(grid, i + 1, jj), pt(grid, i + 2, jj), pt(grid, i + 3, jj))
		end

		grid.width += 2
		-- the new aproximating point at i+1 may need to be removed
		-- or subdivided farther, so don't advance i
	end
end

local function CM_ComparePoints(a, b): boolean
	local d = f(a[0] - b[0])
	if d < -POINT_EPSILON or d > POINT_EPSILON then
		return false
	end
	d = f(a[1] - b[1])
	if d < -POINT_EPSILON or d > POINT_EPSILON then
		return false
	end
	d = f(a[2] - b[2])
	if d < -POINT_EPSILON or d > POINT_EPSILON then
		return false
	end
	return true
end

-- If there are any identical columns, remove them
local function CM_RemoveDegenerateColumns(grid)
	local i = 0
	while i < grid.width - 1 do
		local j = 0
		while j < grid.height do
			if not CM_ComparePoints(pt(grid, i, j), pt(grid, i + 1, j)) then
				break
			end
			j += 1
		end

		if j == grid.height then
			for jj = 0, grid.height - 1 do
				-- remove the column
				for k = i + 2, grid.width - 1 do
					VectorCopy(pt(grid, k, jj), pt(grid, k - 1, jj))
				end
			end
			grid.width -= 1
			-- check against the next column
			i -= 1
		end
		i += 1
	end
end

--[[
================================================================================
PATCH COLLIDE GENERATION
================================================================================
]]

-- generation scratch state (static in C)
local numPlanes = 0
local planes = {}
local numFacets = 0
local facets = {}

local function CM_PlaneEqual(p, plane): (boolean, boolean)
	local pp = p.plane
	if abs(f(pp[0] - plane[0])) < NORMAL_EPSILON
		and abs(f(pp[1] - plane[1])) < NORMAL_EPSILON
		and abs(f(pp[2] - plane[2])) < NORMAL_EPSILON
		and abs(f(pp[3] - plane[3])) < DIST_EPSILON
	then
		return true, false
	end

	local i0, i1, i2, i3 = -plane[0], -plane[1], -plane[2], -plane[3]
	if abs(f(pp[0] - i0)) < NORMAL_EPSILON
		and abs(f(pp[1] - i1)) < NORMAL_EPSILON
		and abs(f(pp[2] - i2)) < NORMAL_EPSILON
		and abs(f(pp[3] - i3)) < DIST_EPSILON
	then
		return true, true
	end

	return false, false
end

local function CM_SnapVector(normal)
	for i = 0, 2 do
		if abs(f(normal[i] - 1)) < NORMAL_EPSILON then
			Q.VectorClear(normal)
			normal[i] = 1
			break
		end
		if abs(f(normal[i] - -1)) < NORMAL_EPSILON then
			Q.VectorClear(normal)
			normal[i] = -1
			break
		end
	end
end

local function addPlane(plane): number
	if numPlanes == MAX_PATCH_PLANES then
		error("MAX_PATCH_PLANES")
	end
	planes[numPlanes] = {
		plane = { [0] = plane[0], plane[1], plane[2], plane[3] },
		signbits = CM_SignbitsForNormal(plane),
	}
	numPlanes += 1
	return numPlanes - 1
end

-- returns planeNum, flipped
local function CM_FindPlane2(plane): (number, boolean)
	-- see if the points are close enough to an existing plane
	for i = 0, numPlanes - 1 do
		local eq, flipped = CM_PlaneEqual(planes[i], plane)
		if eq then
			return i, flipped
		end
	end
	-- add a new plane
	return addPlane(plane), false
end

local function CM_FindPlane(p1, p2, p3): number
	local plane = vec4()
	if not CM_PlaneFromPoints(plane, p1, p2, p3) then
		return -1
	end

	-- see if the points are close enough to an existing plane
	for i = 0, numPlanes - 1 do
		local pp = planes[i].plane
		if DotProduct(plane, pp) < 0 then
			continue -- allow backwards planes?
		end

		local d = f(DotProduct(p1, pp) - pp[3])
		if d < -PLANE_TRI_EPSILON or d > PLANE_TRI_EPSILON then
			continue
		end

		d = f(DotProduct(p2, pp) - pp[3])
		if d < -PLANE_TRI_EPSILON or d > PLANE_TRI_EPSILON then
			continue
		end

		d = f(DotProduct(p3, pp) - pp[3])
		if d < -PLANE_TRI_EPSILON or d > PLANE_TRI_EPSILON then
			continue
		end

		-- found it
		return i
	end

	-- add a new plane
	return addPlane(plane)
end

local function CM_PointOnPlaneSide(p, planeNum: number): number
	if planeNum == -1 then
		return SIDE_ON
	end
	local plane = planes[planeNum].plane
	local d = f(DotProduct(p, plane) - plane[3])
	if d > PLANE_TRI_EPSILON then
		return SIDE_FRONT
	end
	if d < -PLANE_TRI_EPSILON then
		return SIDE_BACK
	end
	return SIDE_ON
end

local function CM_GridPlane(gridPlanes, i: number, j: number, tri: number): number
	local p = gridPlanes[i][j][tri]
	if p ~= -1 then
		return p
	end
	p = gridPlanes[i][j][1 - tri]
	if p ~= -1 then
		return p
	end
	-- should never happen
	print("WARNING: CM_GridPlane unresolvable")
	return -1
end

local function CM_EdgePlaneNum(grid, gridPlanes, i: number, j: number, k: number): number
	local p1, p2, p
	local up = vec3()
	if k == 0 then -- top border
		p1 = pt(grid, i, j)
		p2 = pt(grid, i + 1, j)
		p = CM_GridPlane(gridPlanes, i, j, 0)
		if p == -1 then
			return -1
		end
		VectorMA(p1, 4, planes[p].plane, up)
		return CM_FindPlane(p1, p2, up)
	elseif k == 2 then -- bottom border
		p1 = pt(grid, i, j + 1)
		p2 = pt(grid, i + 1, j + 1)
		p = CM_GridPlane(gridPlanes, i, j, 1)
		if p == -1 then
			return -1
		end
		VectorMA(p1, 4, planes[p].plane, up)
		return CM_FindPlane(p2, p1, up)
	elseif k == 3 then -- left border
		p1 = pt(grid, i, j)
		p2 = pt(grid, i, j + 1)
		p = CM_GridPlane(gridPlanes, i, j, 1)
		if p == -1 then
			return -1
		end
		VectorMA(p1, 4, planes[p].plane, up)
		return CM_FindPlane(p2, p1, up)
	elseif k == 1 then -- right border
		p1 = pt(grid, i + 1, j)
		p2 = pt(grid, i + 1, j + 1)
		p = CM_GridPlane(gridPlanes, i, j, 0)
		if p == -1 then
			return -1
		end
		VectorMA(p1, 4, planes[p].plane, up)
		return CM_FindPlane(p1, p2, up)
	elseif k == 4 then -- diagonal out of triangle 0
		p1 = pt(grid, i + 1, j + 1)
		p2 = pt(grid, i, j)
		p = CM_GridPlane(gridPlanes, i, j, 0)
		if p == -1 then
			return -1
		end
		VectorMA(p1, 4, planes[p].plane, up)
		return CM_FindPlane(p1, p2, up)
	elseif k == 5 then -- diagonal out of triangle 1
		p1 = pt(grid, i, j)
		p2 = pt(grid, i + 1, j + 1)
		p = CM_GridPlane(gridPlanes, i, j, 1)
		if p == -1 then
			return -1
		end
		VectorMA(p1, 4, planes[p].plane, up)
		return CM_FindPlane(p1, p2, up)
	end
	error("CM_EdgePlaneNum: bad k")
end

local function CM_SetBorderInward(facet, grid, i: number, j: number, which: number)
	local points
	if which == -1 then
		points = { [0] = pt(grid, i, j), pt(grid, i + 1, j), pt(grid, i + 1, j + 1), pt(grid, i, j + 1) }
	elseif which == 0 then
		points = { [0] = pt(grid, i, j), pt(grid, i + 1, j), pt(grid, i + 1, j + 1) }
	elseif which == 1 then
		points = { [0] = pt(grid, i + 1, j + 1), pt(grid, i, j + 1), pt(grid, i, j) }
	else
		error("CM_SetBorderInward: bad parameter")
	end
	local numPoints = if which == -1 then 4 else 3

	for k = 0, facet.numBorders - 1 do
		local front, back = 0, 0
		for l = 0, numPoints - 1 do
			local side = CM_PointOnPlaneSide(points[l], facet.borderPlanes[k])
			if side == SIDE_FRONT then
				front += 1
			end
			if side == SIDE_BACK then
				back += 1
			end
		end

		if front ~= 0 and back == 0 then
			facet.borderInward[k] = true
		elseif back ~= 0 and front == 0 then
			facet.borderInward[k] = false
		elseif front == 0 and back == 0 then
			-- flat side border
			facet.borderPlanes[k] = -1
		else
			-- bisecting side border
			facet.borderInward[k] = false
		end
	end
end

local function negatedPlane(src, inward: boolean)
	local plane = { [0] = src[0], src[1], src[2], src[3] }
	if not inward then
		plane[0], plane[1], plane[2] = -plane[0], -plane[1], -plane[2]
		plane[3] = -plane[3]
	end
	return plane
end

-- If the facet isn't bounded by its borders, we screwed up.
local function CM_ValidateFacet(facet): boolean
	if facet.surfacePlane == -1 then
		return false
	end

	local plane = planes[facet.surfacePlane].plane
	local w = P.BaseWindingForPlane(plane, plane[3])
	local j = 0
	while j < facet.numBorders and w do
		if facet.borderPlanes[j] == -1 then
			return false
		end
		local p = negatedPlane(planes[facet.borderPlanes[j]].plane, facet.borderInward[j])
		w = P.ChopWindingInPlace(w, p, p[3], F01)
		j += 1
	end

	if not w then
		return false -- winding was completely chopped away
	end

	-- see if the facet is unreasonably large
	local mins, maxs = vec3(), vec3()
	P.WindingBounds(w, mins, maxs)
	for jj = 0, 2 do
		if f(maxs[jj] - mins[jj]) > P.MAX_MAP_BOUNDS then
			return false -- we must be missing a plane
		end
		if mins[jj] >= P.MAX_MAP_BOUNDS then
			return false
		end
		if maxs[jj] <= -P.MAX_MAP_BOUNDS then
			return false
		end
	end
	return true -- winding is fine
end

local function CM_AddFacetBevels(facet)
	local plane = planes[facet.surfacePlane].plane
	local w = P.BaseWindingForPlane(plane, plane[3])
	local j = 0
	while j < facet.numBorders and w do
		if facet.borderPlanes[j] == facet.surfacePlane then
			j += 1
			continue
		end
		local p = negatedPlane(planes[facet.borderPlanes[j]].plane, facet.borderInward[j])
		w = P.ChopWindingInPlace(w, p, p[3], F01)
		j += 1
	end
	if not w then
		return
	end

	local mins, maxs = vec3(), vec3()
	P.WindingBounds(w, mins, maxs)

	-- add the axial planes
	local bp = vec4()
	for axis = 0, 2 do
		for dir = -1, 1, 2 do
			bp[0], bp[1], bp[2] = 0, 0, 0
			bp[axis] = dir
			if dir == 1 then
				bp[3] = maxs[axis]
			else
				bp[3] = -mins[axis]
			end
			-- if it's the surface plane
			if (CM_PlaneEqual(planes[facet.surfacePlane], bp)) then
				continue
			end
			-- see if the plane is already present
			local i = 0
			while i < facet.numBorders do
				if (CM_PlaneEqual(planes[facet.borderPlanes[i]], bp)) then
					break
				end
				i += 1
			end

			if i == facet.numBorders then
				if facet.numBorders >= MAX_BORDERS then
					print("ERROR: too many bevels")
					continue
				end
				local pn, flipped = CM_FindPlane2(bp)
				facet.borderPlanes[facet.numBorders] = pn
				facet.borderNoAdjust[facet.numBorders] = false
				facet.borderInward[facet.numBorders] = flipped
				facet.numBorders += 1
			end
		end
	end

	-- add the edge bevels
	-- test the non-axial plane edges
	local vec, vec2 = vec3(), vec3()
	for jj = 0, w.numpoints - 1 do
		local k = (jj + 1) % w.numpoints
		VectorSubtract(w.p[jj], w.p[k], vec)
		-- if it's a degenerate edge
		if VectorNormalize(vec) < 0.5 then
			continue
		end
		CM_SnapVector(vec)
		k = 0
		while k < 3 do
			if vec[k] == -1 or vec[k] == 1 then
				break -- axial
			end
			k += 1
		end
		if k < 3 then
			continue -- only test non-axial edges
		end

		-- try the six possible slanted axials from this edge
		for axis = 0, 2 do
			for dir = -1, 1, 2 do
				-- construct a plane
				Q.VectorClear(vec2)
				vec2[axis] = dir
				CrossProduct(vec, vec2, bp)
				if VectorNormalize(bp) < 0.5 then
					continue
				end
				bp[3] = DotProduct(w.p[jj], bp)

				-- if all the points of the facet winding are
				-- behind this plane, it is a proper edge bevel
				local l = 0
				while l < w.numpoints do
					local d = f(DotProduct(w.p[l], bp) - bp[3])
					if d > 0.1 then
						break -- point in front
					end
					l += 1
				end
				if l < w.numpoints then
					continue
				end

				-- if it's the surface plane
				if (CM_PlaneEqual(planes[facet.surfacePlane], bp)) then
					continue
				end
				-- see if the plane is already present
				local i = 0
				while i < facet.numBorders do
					if (CM_PlaneEqual(planes[facet.borderPlanes[i]], bp)) then
						break
					end
					i += 1
				end

				if i == facet.numBorders then
					if facet.numBorders >= MAX_BORDERS then
						print("ERROR: too many bevels")
						continue
					end
					local pn, flipped = CM_FindPlane2(bp)
					facet.borderPlanes[facet.numBorders] = pn
					facet.borderNoAdjust[facet.numBorders] = false
					facet.borderInward[facet.numBorders] = flipped

					local newplane = negatedPlane(planes[pn].plane, flipped)
					local w2 = P.ChopWindingInPlace(P.CopyWinding(w), newplane, newplane[3], F01)
					if not w2 then
						-- invalid bevel
						continue
					end
					facet.numBorders += 1
				end
			end
		end
	end

	-- add opposite plane
	if facet.numBorders >= MAX_BORDERS then
		print("ERROR: too many bevels")
		return
	end
	facet.borderPlanes[facet.numBorders] = facet.surfacePlane
	facet.borderNoAdjust[facet.numBorders] = false
	facet.borderInward[facet.numBorders] = true
	facet.numBorders += 1
end

local function newFacet()
	return { surfacePlane = 0, numBorders = 0, borderPlanes = {}, borderInward = {}, borderNoAdjust = {} }
end

local function CM_PatchCollideFromGrid(grid, pf)
	numPlanes = 0
	numFacets = 0
	planes = {}
	facets = {}

	-- find the planes for each triangle of the grid
	local gridPlanes = {}
	for i = 0, grid.width - 2 do
		local col = {}
		gridPlanes[i] = col
		for j = 0, grid.height - 2 do
			local t = {}
			col[j] = t
			t[0] = CM_FindPlane(pt(grid, i, j), pt(grid, i + 1, j), pt(grid, i + 1, j + 1))
			t[1] = CM_FindPlane(pt(grid, i + 1, j + 1), pt(grid, i, j + 1), pt(grid, i, j))
		end
	end

	-- create the borders for each facet
	local borders, noAdjust = {}, {}
	for i = 0, grid.width - 2 do
		for j = 0, grid.height - 2 do
			local gp = gridPlanes[i][j]

			borders[EN_TOP] = -1
			if j > 0 then
				borders[EN_TOP] = gridPlanes[i][j - 1][1]
			elseif grid.wrapHeight then
				borders[EN_TOP] = gridPlanes[i][grid.height - 2][1]
			end
			noAdjust[EN_TOP] = borders[EN_TOP] == gp[0]
			if borders[EN_TOP] == -1 or noAdjust[EN_TOP] then
				borders[EN_TOP] = CM_EdgePlaneNum(grid, gridPlanes, i, j, 0)
			end

			borders[EN_BOTTOM] = -1
			if j < grid.height - 2 then
				borders[EN_BOTTOM] = gridPlanes[i][j + 1][0]
			elseif grid.wrapHeight then
				borders[EN_BOTTOM] = gridPlanes[i][0][0]
			end
			noAdjust[EN_BOTTOM] = borders[EN_BOTTOM] == gp[1]
			if borders[EN_BOTTOM] == -1 or noAdjust[EN_BOTTOM] then
				borders[EN_BOTTOM] = CM_EdgePlaneNum(grid, gridPlanes, i, j, 2)
			end

			borders[EN_LEFT] = -1
			if i > 0 then
				borders[EN_LEFT] = gridPlanes[i - 1][j][0]
			elseif grid.wrapWidth then
				borders[EN_LEFT] = gridPlanes[grid.width - 2][j][0]
			end
			noAdjust[EN_LEFT] = borders[EN_LEFT] == gp[1]
			if borders[EN_LEFT] == -1 or noAdjust[EN_LEFT] then
				borders[EN_LEFT] = CM_EdgePlaneNum(grid, gridPlanes, i, j, 3)
			end

			borders[EN_RIGHT] = -1
			if i < grid.width - 2 then
				borders[EN_RIGHT] = gridPlanes[i + 1][j][1]
			elseif grid.wrapWidth then
				borders[EN_RIGHT] = gridPlanes[0][j][1]
			end
			noAdjust[EN_RIGHT] = borders[EN_RIGHT] == gp[0]
			if borders[EN_RIGHT] == -1 or noAdjust[EN_RIGHT] then
				borders[EN_RIGHT] = CM_EdgePlaneNum(grid, gridPlanes, i, j, 1)
			end

			if numFacets == MAX_FACETS then
				error("MAX_FACETS")
			end
			local facet = newFacet()

			if gp[0] == gp[1] then
				if gp[0] == -1 then
					continue -- degenrate
				end
				facet.surfacePlane = gp[0]
				facet.numBorders = 4
				facet.borderPlanes[0] = borders[EN_TOP]
				facet.borderNoAdjust[0] = noAdjust[EN_TOP]
				facet.borderPlanes[1] = borders[EN_RIGHT]
				facet.borderNoAdjust[1] = noAdjust[EN_RIGHT]
				facet.borderPlanes[2] = borders[EN_BOTTOM]
				facet.borderNoAdjust[2] = noAdjust[EN_BOTTOM]
				facet.borderPlanes[3] = borders[EN_LEFT]
				facet.borderNoAdjust[3] = noAdjust[EN_LEFT]
				for b = 0, 3 do
					facet.borderInward[b] = false
				end
				CM_SetBorderInward(facet, grid, i, j, -1)
				if CM_ValidateFacet(facet) then
					CM_AddFacetBevels(facet)
					facets[numFacets] = facet
					numFacets += 1
				end
			else
				-- two separate triangles
				facet.surfacePlane = gp[0]
				facet.numBorders = 3
				facet.borderPlanes[0] = borders[EN_TOP]
				facet.borderNoAdjust[0] = noAdjust[EN_TOP]
				facet.borderPlanes[1] = borders[EN_RIGHT]
				facet.borderNoAdjust[1] = noAdjust[EN_RIGHT]
				facet.borderPlanes[2] = gp[1]
				facet.borderNoAdjust[2] = false
				if facet.borderPlanes[2] == -1 then
					facet.borderPlanes[2] = borders[EN_BOTTOM]
					if facet.borderPlanes[2] == -1 then
						facet.borderPlanes[2] = CM_EdgePlaneNum(grid, gridPlanes, i, j, 4)
					end
				end
				for b = 0, 2 do
					facet.borderInward[b] = false
				end
				CM_SetBorderInward(facet, grid, i, j, 0)
				if CM_ValidateFacet(facet) then
					CM_AddFacetBevels(facet)
					facets[numFacets] = facet
					numFacets += 1
				end

				if numFacets == MAX_FACETS then
					error("MAX_FACETS")
				end
				facet = newFacet()

				facet.surfacePlane = gp[1]
				facet.numBorders = 3
				facet.borderPlanes[0] = borders[EN_BOTTOM]
				facet.borderNoAdjust[0] = noAdjust[EN_BOTTOM]
				facet.borderPlanes[1] = borders[EN_LEFT]
				facet.borderNoAdjust[1] = noAdjust[EN_LEFT]
				facet.borderPlanes[2] = gp[0]
				facet.borderNoAdjust[2] = false
				if facet.borderPlanes[2] == -1 then
					facet.borderPlanes[2] = borders[EN_TOP]
					if facet.borderPlanes[2] == -1 then
						facet.borderPlanes[2] = CM_EdgePlaneNum(grid, gridPlanes, i, j, 5)
					end
				end
				for b = 0, 2 do
					facet.borderInward[b] = false
				end
				CM_SetBorderInward(facet, grid, i, j, 1)
				if CM_ValidateFacet(facet) then
					CM_AddFacetBevels(facet)
					facets[numFacets] = facet
					numFacets += 1
				end
			end
		end
	end

	-- copy the results out
	pf.numPlanes = numPlanes
	pf.numFacets = numFacets
	pf.facets = facets
	pf.planes = planes
end

-- Creates an internal structure that will be used to perform
-- collision detection with a patch mesh.
-- Points is packed as concatenated rows (0-based array of vec3).
function L.CM_GeneratePatchCollide(width: number, height: number, points)
	if width <= 2 or height <= 2 or not points then
		error(string.format("CM_GeneratePatchFacets: bad parameters: (%i, %i)", width, height))
	end
	if width % 2 == 0 or height % 2 == 0 then
		error("CM_GeneratePatchFacets: even sizes are invalid for quadratic meshes")
	end
	if width > MAX_GRID_SIZE or height > MAX_GRID_SIZE then
		error("CM_GeneratePatchFacets: source is > MAX_GRID_SIZE")
	end

	-- build a grid
	local grid = newGrid()
	grid.width = width
	grid.height = height
	grid.wrapWidth = false
	grid.wrapHeight = false
	for i = 0, width - 1 do
		for j = 0, height - 1 do
			VectorCopy(points[j * width + i], pt(grid, i, j))
		end
	end

	-- subdivide the grid
	CM_SetGridWrapWidth(grid)
	CM_SubdivideGridColumns(grid)
	CM_RemoveDegenerateColumns(grid)

	CM_TransposeGrid(grid)

	CM_SetGridWrapWidth(grid)
	CM_SubdivideGridColumns(grid)
	CM_RemoveDegenerateColumns(grid)

	-- we now have a grid of points exactly on the curve
	-- the approximate surface defined by these points will be
	-- collided against
	local pf = { bounds = { [0] = vec3(), vec3() }, numPlanes = 0, planes = {}, numFacets = 0, facets = {} }
	Q.ClearBounds(pf.bounds[0], pf.bounds[1])
	for i = 0, grid.width - 1 do
		for j = 0, grid.height - 1 do
			Q.AddPointToBounds(pt(grid, i, j), pf.bounds[0], pf.bounds[1])
		end
	end

	-- generate a bsp tree for the surface
	CM_PatchCollideFromGrid(grid, pf)

	-- expand by one unit for epsilon purposes
	for i = 0, 2 do
		pf.bounds[0][i] = f(pf.bounds[0][i] - 1)
		pf.bounds[1][i] = f(pf.bounds[1][i] + 1)
	end

	return pf
end

--[[
================================================================================
TRACE TESTING
================================================================================
]]

-- special case for point traces because the patch collide "brushes" have no volume
local frontFacing = {}
local intersection = {}
local function CM_TracePointThroughPatchCollide(tw, pc)
	if L.cvars.cm_playerCurveClip == 0 or not tw.isPoint then
		return
	end

	-- determine the trace's relationship to all planes
	local pcPlanes = pc.planes
	local offsets, start, endp = tw.offsets, tw.start, tw["end"]
	for i = 0, pc.numPlanes - 1 do
		local pp = pcPlanes[i]
		local plane = pp.plane
		local offset = DotProduct(offsets[pp.signbits], plane)
		local d1 = f(f(DotProduct(start, plane) - plane[3]) + offset)
		local d2 = f(f(DotProduct(endp, plane) - plane[3]) + offset)
		frontFacing[i] = not (d1 <= 0)
		if d1 == d2 then
			intersection[i] = 99999
		else
			local x = f(d1 / f(d1 - d2))
			if x <= 0 then
				x = 99999
			end
			intersection[i] = x
		end
	end

	-- see if any of the surface planes are intersected
	for i = 0, pc.numFacets - 1 do
		local facet = pc.facets[i]
		if not frontFacing[facet.surfacePlane] then
			continue
		end
		local intersect = intersection[facet.surfacePlane]
		if intersect < 0 then
			continue -- surface is behind the starting point
		end
		if intersect > tw.trace.fraction then
			continue -- already hit something closer
		end
		local j = 0
		local nb = facet.numBorders
		while j < nb do
			local k = facet.borderPlanes[j]
			if frontFacing[k] ~= facet.borderInward[j] then
				if intersection[k] > intersect then
					break
				end
			else
				if intersection[k] < intersect then
					break
				end
			end
			j += 1
		end
		if j == nb then
			-- we hit this facet
			local pp = pcPlanes[facet.surfacePlane]
			local plane = pp.plane

			-- calculate intersection with a slight pushoff
			local offset = DotProduct(offsets[pp.signbits], plane)
			local d1 = f(f(DotProduct(start, plane) - plane[3]) + offset)
			local d2 = f(f(DotProduct(endp, plane) - plane[3]) + offset)
			local frac = f((d1 - SURFACE_CLIP_EPSILON) / f(d1 - d2))
			if frac < 0 then
				frac = 0
			end
			tw.trace.fraction = frac

			local n = tw.trace.plane.normal
			n[0], n[1], n[2] = plane[0], plane[1], plane[2]
			tw.trace.plane.dist = plane[3]
		end
	end
end

-- returns (notInFront, enterFrac, leaveFrac, hit)
local function CM_CheckFacetPlane(p0: number, p1: number, p2: number, p3: number, start, endp, enterFrac: number, leaveFrac: number)
	local d1 = f(f(f(f(start[0] * p0) + f(start[1] * p1)) + f(start[2] * p2)) - p3)
	local d2 = f(f(f(f(endp[0] * p0) + f(endp[1] * p1)) + f(endp[2] * p2)) - p3)

	-- if completely in front of face, no intersection with the entire facet
	if d1 > 0 and (d2 >= SURFACE_CLIP_EPSILON or d2 >= d1) then
		return false, enterFrac, leaveFrac, false
	end

	-- if it doesn't cross the plane, the plane isn't relevant
	if d1 <= 0 and d2 <= 0 then
		return true, enterFrac, leaveFrac, false
	end

	-- crosses face
	if d1 > d2 then -- enter
		local fr = f((d1 - SURFACE_CLIP_EPSILON) / f(d1 - d2))
		if fr < 0 then
			fr = 0
		end
		-- always favor previous plane hits and thus also the surface plane hit
		if fr > enterFrac then
			return true, fr, leaveFrac, true
		end
	else -- leave
		local fr = f((d1 + SURFACE_CLIP_EPSILON) / f(d1 - d2))
		if fr > 1 then
			fr = 1
		end
		if fr < leaveFrac then
			leaveFrac = fr
		end
	end
	return true, enterFrac, leaveFrac, false
end

local startp_s, endp_s = vec3(), vec3()
function L.CM_TraceThroughPatchCollide(tw, pc)
	if not L.CM_BoundsIntersect(tw.bounds[0], tw.bounds[1], pc.bounds[0], pc.bounds[1]) then
		return
	end

	if tw.isPoint then
		CM_TracePointThroughPatchCollide(tw, pc)
		return
	end

	local sphere = tw.sphere
	local useSphere = sphere.use
	local soff = sphere.offset
	local start, endt = tw.start, tw["end"]
	local offsets = tw.offsets
	local startp, endp = startp_s, endp_s
	local b0, b1, b2, b3 = 0, 0, 0, 0
	for i = 0, pc.numFacets - 1 do
		local facet = pc.facets[i]
		local enterFrac, leaveFrac = -1.0, 1.0
		local hitnum = -1

		local pp = pc.planes[facet.surfacePlane]
		local pl = pp.plane
		local p0, p1, p2, p3 = pl[0], pl[1], pl[2], pl[3]
		if useSphere then
			-- adjust the plane distance appropriately for radius
			p3 = f(p3 + sphere.radius)

			-- find the closest point on the capsule to the plane
			local t = f(f(f(p0 * soff[0]) + f(p1 * soff[1])) + f(p2 * soff[2]))
			if t > 0 then
				VectorSubtract(start, soff, startp)
				VectorSubtract(endt, soff, endp)
			else
				Q.VectorAdd(start, soff, startp)
				Q.VectorAdd(endt, soff, endp)
			end
		else
			local o = offsets[pp.signbits]
			local offset = f(f(f(o[0] * p0) + f(o[1] * p1)) + f(o[2] * p2))
			p3 = f(p3 - offset)
			VectorCopy(start, startp)
			VectorCopy(endt, endp)
		end

		local ok, hit
		ok, enterFrac, leaveFrac, hit = CM_CheckFacetPlane(p0, p1, p2, p3, startp, endp, enterFrac, leaveFrac)
		if not ok then
			continue
		end
		if hit then
			b0, b1, b2, b3 = p0, p1, p2, p3
		end

		local nb = facet.numBorders
		local j = 0
		while j < nb do
			pp = pc.planes[facet.borderPlanes[j]]
			pl = pp.plane
			if facet.borderInward[j] then
				p0, p1, p2, p3 = -pl[0], -pl[1], -pl[2], -pl[3]
			else
				p0, p1, p2, p3 = pl[0], pl[1], pl[2], pl[3]
			end
			if useSphere then
				-- adjust the plane distance appropriately for radius
				p3 = f(p3 + sphere.radius)

				-- find the closest point on the capsule to the plane
				local t = f(f(f(p0 * soff[0]) + f(p1 * soff[1])) + f(p2 * soff[2]))
				if t > 0 then
					VectorSubtract(start, soff, startp)
					VectorSubtract(endt, soff, endp)
				else
					Q.VectorAdd(start, soff, startp)
					Q.VectorAdd(endt, soff, endp)
				end
			else
				-- NOTE: this works even though the plane might be flipped because the bbox is centered
				local o = offsets[pp.signbits]
				local offset = f(f(f(o[0] * p0) + f(o[1] * p1)) + f(o[2] * p2))
				p3 = f(p3 + abs(offset))
				VectorCopy(start, startp)
				VectorCopy(endt, endp)
			end

			ok, enterFrac, leaveFrac, hit = CM_CheckFacetPlane(p0, p1, p2, p3, startp, endp, enterFrac, leaveFrac)
			if not ok then
				break
			end
			if hit then
				hitnum = j
				b0, b1, b2, b3 = p0, p1, p2, p3
			end
			j += 1
		end
		if j < nb then
			continue
		end
		-- never clip against the back side
		if hitnum == nb - 1 then
			continue
		end

		if enterFrac < leaveFrac and enterFrac >= 0 then
			if enterFrac < tw.trace.fraction then
				if enterFrac < 0 then
					enterFrac = 0
				end
				tw.trace.fraction = enterFrac
				local n = tw.trace.plane.normal
				n[0], n[1], n[2] = b0, b1, b2
				tw.trace.plane.dist = b3
			end
		end
	end
end

--[[
=======================================================================
POSITION TEST
=======================================================================
]]

function L.CM_PositionTestInPatchCollide(tw, pc): boolean
	if tw.isPoint then
		return false
	end
	local sphere = tw.sphere
	local soff = sphere.offset
	local start = tw.start
	local s0, s1, s2
	for i = 0, pc.numFacets - 1 do
		local facet = pc.facets[i]
		local pp = pc.planes[facet.surfacePlane]
		local pl = pp.plane
		local p0, p1, p2, p3 = pl[0], pl[1], pl[2], pl[3]
		if sphere.use then
			-- adjust the plane distance appropriately for radius
			p3 = f(p3 + sphere.radius)
			-- find the closest point on the capsule to the plane
			local t = f(f(f(p0 * soff[0]) + f(p1 * soff[1])) + f(p2 * soff[2]))
			if t > 0 then
				s0, s1, s2 = f(start[0] - soff[0]), f(start[1] - soff[1]), f(start[2] - soff[2])
			else
				s0, s1, s2 = f(start[0] + soff[0]), f(start[1] + soff[1]), f(start[2] + soff[2])
			end
		else
			local o = tw.offsets[pp.signbits]
			local offset = f(f(f(o[0] * p0) + f(o[1] * p1)) + f(o[2] * p2))
			p3 = f(p3 - offset)
			s0, s1, s2 = start[0], start[1], start[2]
		end

		if f(f(f(f(p0 * s0) + f(p1 * s1)) + f(p2 * s2)) - p3) > 0 then
			continue
		end

		local nb = facet.numBorders
		local j = 0
		while j < nb do
			pp = pc.planes[facet.borderPlanes[j]]
			pl = pp.plane
			if facet.borderInward[j] then
				p0, p1, p2, p3 = -pl[0], -pl[1], -pl[2], -pl[3]
			else
				p0, p1, p2, p3 = pl[0], pl[1], pl[2], pl[3]
			end
			if sphere.use then
				-- adjust the plane distance appropriately for radius
				p3 = f(p3 + sphere.radius)
				-- find the closest point on the capsule to the plane
				local t = f(f(f(p0 * soff[0]) + f(p1 * soff[1])) + f(p2 * soff[2]))
				if t > 0 then
					s0, s1, s2 = f(start[0] - soff[0]), f(start[1] - soff[1]), f(start[2] - soff[2])
				else
					s0, s1, s2 = f(start[0] + soff[0]), f(start[1] + soff[1]), f(start[2] + soff[2])
				end
			else
				-- NOTE: this works even though the plane might be flipped because the bbox is centered
				local o = tw.offsets[pp.signbits]
				local offset = f(f(f(o[0] * p0) + f(o[1] * p1)) + f(o[2] * p2))
				p3 = f(p3 + abs(offset))
				s0, s1, s2 = start[0], start[1], start[2]
			end

			if f(f(f(f(p0 * s0) + f(p1 * s1)) + f(p2 * s2)) - p3) > 0 then
				break
			end
			j += 1
		end
		if j < nb then
			continue
		end
		-- inside this patch facet
		return true
	end
	return false
end

function L.CM_ClearLevelPatches() end

return L
