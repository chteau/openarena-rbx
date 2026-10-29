--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (qcommon/cm_polylib.c (the winding routines cm_patch.c uses)).

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
-- A winding is { numpoints = n, p = { [0] = vec3, ... } }; nil plays NULL.

local Q = require("../q_math")
local f, vec3 = Q.f, Q.vec3
local abs = math.abs

local P = {}

local MAX_MAP_BOUNDS = 65535
local MAX_POINTS_ON_WINDING = 64
local SIDE_FRONT, SIDE_BACK, SIDE_ON = 0, 1, 2
P.MAX_MAP_BOUNDS = MAX_MAP_BOUNDS

local function AllocWinding(points: number)
	local p = {}
	for i = 0, points - 1 do
		p[i] = vec3()
	end
	return { numpoints = 0, p = p }
end
P.AllocWinding = AllocWinding

function P.WindingBounds(w, mins, maxs)
	mins[0], mins[1], mins[2] = MAX_MAP_BOUNDS, MAX_MAP_BOUNDS, MAX_MAP_BOUNDS
	maxs[0], maxs[1], maxs[2] = -MAX_MAP_BOUNDS, -MAX_MAP_BOUNDS, -MAX_MAP_BOUNDS
	for i = 0, w.numpoints - 1 do
		local pt = w.p[i]
		for j = 0, 2 do
			local v = pt[j]
			if v < mins[j] then
				mins[j] = v
			end
			if v > maxs[j] then
				maxs[j] = v
			end
		end
	end
end

function P.BaseWindingForPlane(normal, dist: number)
	-- find the major axis
	local max = -MAX_MAP_BOUNDS
	local x = -1
	for i = 0, 2 do
		local v = abs(normal[i])
		if v > max then
			x = i
			max = v
		end
	end
	if x == -1 then
		error("BaseWindingForPlane: no axis found")
	end

	local vup = vec3()
	if x == 0 or x == 1 then
		vup[2] = 1
	else
		vup[0] = 1
	end

	local v = Q.DotProduct(vup, normal)
	Q.VectorMA(vup, -v, normal, vup)
	Q.VectorNormalize2Ioq3(vup, vup)

	local org = vec3()
	Q.VectorScale(normal, dist, org)

	local vright = vec3()
	Q.CrossProduct(vup, normal, vright)

	Q.VectorScale(vup, MAX_MAP_BOUNDS, vup)
	Q.VectorScale(vright, MAX_MAP_BOUNDS, vright)

	-- project a really big axis aligned box onto the plane
	local w = AllocWinding(4)
	local p = w.p
	Q.VectorSubtract(org, vright, p[0])
	Q.VectorAdd(p[0], vup, p[0])

	Q.VectorAdd(org, vright, p[1])
	Q.VectorAdd(p[1], vup, p[1])

	Q.VectorAdd(org, vright, p[2])
	Q.VectorSubtract(p[2], vup, p[2])

	Q.VectorSubtract(org, vright, p[3])
	Q.VectorSubtract(p[3], vup, p[3])

	w.numpoints = 4
	return w
end

function P.CopyWinding(w)
	local c = AllocWinding(w.numpoints)
	for i = 0, w.numpoints - 1 do
		Q.VectorCopy(w.p[i], c.p[i])
	end
	c.numpoints = w.numpoints
	return c
end

-- ChopWindingInPlace: returns the clipped winding, or nil when nothing is
-- left in front of the plane (the C version writes it through *inout).
function P.ChopWindingInPlace(inw, normal, dist: number, epsilon: number)
	local dists, sides = {}, {}
	local counts = { [0] = 0, 0, 0 }
	local n = inw.numpoints

	-- determine sides for each point
	for i = 0, n - 1 do
		local dot = Q.DotProduct(inw.p[i], normal)
		dot = f(dot - dist)
		dists[i] = dot
		local s
		if dot > epsilon then
			s = SIDE_FRONT
		elseif dot < -epsilon then
			s = SIDE_BACK
		else
			s = SIDE_ON
		end
		sides[i] = s
		counts[s] += 1
	end
	sides[n] = sides[0]
	dists[n] = dists[0]

	if counts[0] == 0 then
		return nil
	end
	if counts[1] == 0 then
		return inw -- inout stays the same
	end

	local maxpts = n + 4 -- can't use counts[0]+2 because of fp grouping errors
	local fw = AllocWinding(maxpts)
	local fp = fw.p

	for i = 0, n - 1 do
		local p1 = inw.p[i]

		if sides[i] == SIDE_ON then
			Q.VectorCopy(p1, fp[fw.numpoints])
			fw.numpoints += 1
			continue
		end

		if sides[i] == SIDE_FRONT then
			Q.VectorCopy(p1, fp[fw.numpoints])
			fw.numpoints += 1
		end

		if sides[i + 1] == SIDE_ON or sides[i + 1] == sides[i] then
			continue
		end

		-- generate a split point
		local p2 = inw.p[(i + 1) % n]
		local dot = f(dists[i] / f(dists[i] - dists[i + 1]))
		local mid = fp[fw.numpoints]
		for j = 0, 2 do
			-- avoid round off error when possible
			if normal[j] == 1 then
				mid[j] = dist
			elseif normal[j] == -1 then
				mid[j] = -dist
			else
				mid[j] = f(p1[j] + f(dot * f(p2[j] - p1[j])))
			end
		end
		fw.numpoints += 1
	end

	if fw.numpoints > maxpts then
		error("ClipWinding: points exceeded estimate")
	end
	if fw.numpoints > MAX_POINTS_ON_WINDING then
		error("ClipWinding: MAX_POINTS_ON_WINDING")
	end
	return fw
end

return P
