--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (qcommon/cm_trace.c).

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
Box, point and capsule traces through the BSP tree, through inline models and
through temporary box/capsule models (CM_TempBoxModel). Float rounding
follows the C code op for op (see q_math.luau), so results match the C
collision code bit for bit.

traceWork_t (one reused instance, traces never nest):
	start, end, size[2], offsets[8], maxOffset, extents, bounds[2], modelOrigin,
	contents, isPoint, trace (trace_t), sphere = { use, radius, halfheight, offset }
]]

local Q = require("../q_math")
local S = require("../structs")
local L = require("./cm_local")
require("./cm_test")
require("./cm_patch")

local f, vec3 = Q.f, Q.vec3
local abs = math.abs
local band = bit32.band
local DotProduct, VectorSubtract, VectorAdd, VectorCopy, VectorLengthSquared =
	Q.DotProduct, Q.VectorSubtract, Q.VectorAdd, Q.VectorCopy, Q.VectorLengthSquared
local SURFACE_CLIP_EPSILON = L.SURFACE_CLIP_EPSILON
local BOX_MODEL_HANDLE, CAPSULE_MODEL_HANDLE = L.BOX_MODEL_HANDLE, L.CAPSULE_MODEL_HANDLE
local CONTENTS_BODY = 0x2000000
local RADIUS_EPSILON = 1.0
local counters = L.counters

local function newTraceWork()
	local offsets = {}
	for i = 0, 7 do
		offsets[i] = vec3()
	end
	return {
		start = vec3(),
		["end"] = vec3(),
		size = { [0] = vec3(), vec3() },
		offsets = offsets,
		maxOffset = 0,
		extents = vec3(),
		bounds = { [0] = vec3(), vec3() },
		modelOrigin = vec3(),
		contents = 0,
		isPoint = false,
		trace = S.trace_t(),
		sphere = { use = false, radius = 0, halfheight = 0, offset = vec3() },
	}
end
local tw0 = newTraceWork()

--[[
===============================================================================
BASIC MATH
===============================================================================
]]

local function RotatePoint(point, matrix)
	local t0, t1, t2 = point[0], point[1], point[2]
	local tvec = { [0] = t0, t1, t2 }
	point[0] = DotProduct(matrix[0], tvec)
	point[1] = DotProduct(matrix[1], tvec)
	point[2] = DotProduct(matrix[2], tvec)
end

local function TransposeMatrix(matrix, transpose)
	for i = 0, 2 do
		for j = 0, 2 do
			transpose[i][j] = matrix[j][i]
		end
	end
end

local function CreateRotationMatrix(angles, matrix)
	Q.AngleVectors(angles, matrix[0], matrix[1], matrix[2])
	Q.VectorInverse(matrix[1])
end

local function CM_ProjectPointOntoVector(point, vStart, vDir, vProj)
	local pVec = vec3()
	VectorSubtract(point, vStart, pVec)
	-- project onto the directional vector for this segment
	Q.VectorMA(vStart, DotProduct(pVec, vDir), vDir, vProj)
end

local function CM_DistanceFromLineSquared(p, lp1, lp2, dir): number
	local proj, t = vec3(), vec3()
	CM_ProjectPointOntoVector(p, lp1, dir, proj)
	local j = 0
	while j < 3 do
		if (proj[j] > lp1[j] and proj[j] > lp2[j]) or (proj[j] < lp1[j] and proj[j] < lp2[j]) then
			break
		end
		j += 1
	end
	if j < 3 then
		if abs(f(proj[j] - lp1[j])) < abs(f(proj[j] - lp2[j])) then
			VectorSubtract(p, lp1, t)
		else
			VectorSubtract(p, lp2, t)
		end
		return VectorLengthSquared(t)
	end
	VectorSubtract(p, proj, t)
	return VectorLengthSquared(t)
end

local sqbuf = buffer.create(4)
-- the bit-hack inverse square root, times number
local function SquareRootFloat(number: number): number
	local x = f(number * 0.5)
	buffer.writef32(sqbuf, 0, number)
	buffer.writei32(sqbuf, 0, 0x5f3759df - bit32.arshift(buffer.readi32(sqbuf, 0), 1))
	local y = buffer.readf32(sqbuf, 0)
	y = f(y * f(1.5 - f(f(x * y) * y)))
	y = f(y * f(1.5 - f(f(x * y) * y)))
	return f(number * y)
end

--[[
===============================================================================
POSITION TESTING
===============================================================================
]]

local function CM_TestBoxInBrush(tw, brush)
	if brush.numsides == 0 then
		return
	end

	-- special test for axial
	local tb0, tb1, bb0, bb1 = tw.bounds[0], tw.bounds[1], brush.bounds[0], brush.bounds[1]
	if tb0[0] > bb1[0] or tb0[1] > bb1[1] or tb0[2] > bb1[2] or tb1[0] < bb0[0] or tb1[1] < bb0[1] or tb1[2] < bb0[2] then
		return
	end

	local sides = brush.sides
	local s0, s1, s2 = tw.start[0], tw.start[1], tw.start[2]
	if tw.sphere.use then
		local sphere = tw.sphere
		local so = sphere.offset
		-- the first six planes are the axial planes, so we only
		-- need to test the remainder
		for i = 6, brush.numsides - 1 do
			local plane = sides[i].plane
			local n = plane.normal

			-- adjust the plane distance appropriately for radius
			local dist = f(plane.dist + sphere.radius)
			-- find the closest point on the capsule to the plane
			local t = DotProduct(n, so)
			local x, y, z
			if t > 0 then
				x, y, z = f(s0 - so[0]), f(s1 - so[1]), f(s2 - so[2])
			else
				x, y, z = f(s0 + so[0]), f(s1 + so[1]), f(s2 + so[2])
			end
			local d1 = f(f(f(f(x * n[0]) + f(y * n[1])) + f(z * n[2])) - dist)
			-- if completely in front of face, no intersection
			if d1 > 0 then
				return
			end
		end
	else
		local offsets = tw.offsets
		-- the first six planes are the axial planes, so we only
		-- need to test the remainder
		for i = 6, brush.numsides - 1 do
			local plane = sides[i].plane
			local n = plane.normal
			local n0, n1, n2 = n[0], n[1], n[2]
			local o = offsets[plane.signbits]

			-- adjust the plane distance appropriately for mins/maxs
			local dist = f(plane.dist - f(f(f(o[0] * n0) + f(o[1] * n1)) + f(o[2] * n2)))
			local d1 = f(f(f(f(s0 * n0) + f(s1 * n1)) + f(s2 * n2)) - dist)

			-- if completely in front of face, no intersection
			if d1 > 0 then
				return
			end
		end
	end

	-- inside this brush
	tw.trace.startsolid = true
	tw.trace.allsolid = true
	tw.trace.fraction = 0
	tw.trace.contents = brush.contents
end

local function CM_TestInLeaf(tw, leaf)
	local cm = L.cm
	local checkcount = cm.checkcount
	local leafbrushes, brushes = cm.leafbrushes, cm.brushes
	-- test box position against all brushes in the leaf
	for k = 0, leaf.numLeafBrushes - 1 do
		local b = brushes[leafbrushes[leaf.firstLeafBrush + k]]
		if b.checkcount == checkcount then
			continue -- already checked this brush in another leaf
		end
		b.checkcount = checkcount

		if band(b.contents, tw.contents) == 0 then
			continue
		end

		CM_TestBoxInBrush(tw, b)
		if tw.trace.allsolid then
			return
		end
	end

	-- test against all patches
	if L.cvars.cm_noCurves == 0 then
		for k = 0, leaf.numLeafSurfaces - 1 do
			local patch = cm.surfaces[cm.leafsurfaces[leaf.firstLeafSurface + k]]
			if not patch then
				continue
			end
			if patch.checkcount == checkcount then
				continue -- already checked this brush in another leaf
			end
			patch.checkcount = checkcount

			if band(patch.contents, tw.contents) == 0 then
				continue
			end

			if L.CM_PositionTestInPatchCollide(tw, patch.pc) then
				tw.trace.startsolid = true
				tw.trace.allsolid = true
				tw.trace.fraction = 0
				tw.trace.contents = patch.contents
				return
			end
		end
	end
end
L.CM_TestInLeaf = CM_TestInLeaf

-- capsule inside capsule check
local function CM_TestCapsuleInCapsule(tw, model: number)
	local mins, maxs = vec3(), vec3()
	L.CM_ModelBounds(model, mins, maxs)

	local top, bottom = vec3(), vec3()
	VectorAdd(tw.start, tw.sphere.offset, top)
	VectorSubtract(tw.start, tw.sphere.offset, bottom)
	local offset = vec3()
	local symetricSize = { [0] = vec3(), vec3() }
	for i = 0, 2 do
		offset[i] = f(f(mins[i] + maxs[i]) * 0.5)
		symetricSize[0][i] = f(mins[i] - offset[i])
		symetricSize[1][i] = f(maxs[i] - offset[i])
	end
	local halfwidth = symetricSize[1][0]
	local halfheight = symetricSize[1][2]
	local radius = if halfwidth > halfheight then halfheight else halfwidth
	local offs = f(halfheight - radius)

	local rr = f(tw.sphere.radius + radius)
	local r = f(rr * rr)
	local tmp = vec3()
	local function solid()
		tw.trace.startsolid = true
		tw.trace.allsolid = true
		tw.trace.fraction = 0
	end
	-- check if any of the spheres overlap
	local p1 = vec3(offset[0], offset[1], offset[2])
	p1[2] = f(p1[2] + offs)
	VectorSubtract(p1, top, tmp)
	if VectorLengthSquared(tmp) < r then
		solid()
	end
	VectorSubtract(p1, bottom, tmp)
	if VectorLengthSquared(tmp) < r then
		solid()
	end
	local p2 = vec3(offset[0], offset[1], offset[2])
	p2[2] = f(p2[2] - offs)
	VectorSubtract(p2, top, tmp)
	if VectorLengthSquared(tmp) < r then
		solid()
	end
	VectorSubtract(p2, bottom, tmp)
	if VectorLengthSquared(tmp) < r then
		solid()
	end
	-- if between cylinder up and lower bounds
	if (top[2] >= p1[2] and top[2] <= p2[2]) or (bottom[2] >= p1[2] and bottom[2] <= p2[2]) then
		-- 2d coordinates
		top[2] = 0
		p1[2] = 0
		-- if the cylinders overlap
		VectorSubtract(top, p1, tmp)
		if VectorLengthSquared(tmp) < r then
			solid()
		end
	end
end

local function capsuleFromModel(tw, model: number)
	local mins, maxs = vec3(), vec3()
	-- mins maxs of the capsule
	L.CM_ModelBounds(model, mins, maxs)

	-- offset for capsule center
	local size1 = vec3()
	for i = 0, 2 do
		local offset = f(f(mins[i] + maxs[i]) * 0.5)
		size1[i] = f(maxs[i] - offset)
		tw.start[i] = f(tw.start[i] - offset)
		tw["end"][i] = f(tw["end"][i] - offset)
	end

	-- replace the bounding box with the capsule
	local sphere = tw.sphere
	sphere.use = true
	sphere.radius = if size1[0] > size1[2] then size1[2] else size1[0]
	sphere.halfheight = size1[2]
	Q.VectorSet(sphere.offset, 0, 0, f(size1[2] - sphere.radius))

	-- replace the capsule with the bounding box
	local h = L.CM_TempBoxModel(tw.size[0], tw.size[1], false)
	return L.CM_ClipHandleToModel(h)
end

-- bounding box inside capsule check
local function CM_TestBoundingBoxInCapsule(tw, model: number)
	local cmod = capsuleFromModel(tw, model)
	CM_TestInLeaf(tw, cmod.leaf)
end

local MAX_POSITION_LEAFS = 1024
local positionLeafs = {}
local function CM_PositionTest(tw)
	local cm = L.cm
	-- identify the leafs we are touching
	local mins, maxs = vec3(), vec3()
	VectorAdd(tw.start, tw.size[0], mins)
	VectorAdd(tw.start, tw.size[1], maxs)
	for i = 0, 2 do
		mins[i] = f(mins[i] - 1)
		maxs[i] = f(maxs[i] + 1)
	end
	local ll = L.newLeafList(mins, maxs, positionLeafs, MAX_POSITION_LEAFS, L.CM_StoreLeafs)

	cm.checkcount += 1
	L.CM_BoxLeafnums_r(ll, 0)
	cm.checkcount += 1

	-- test the contents of the leafs
	for i = 0, ll.count - 1 do
		CM_TestInLeaf(tw, cm.leafs[positionLeafs[i]])
		if tw.trace.allsolid then
			break
		end
	end
end

--[[
===============================================================================
TRACING
===============================================================================
]]

local function CM_TraceThroughPatch(tw, patch)
	counters.c_patch_traces += 1
	local oldFrac = tw.trace.fraction
	L.CM_TraceThroughPatchCollide(tw, patch.pc)
	if tw.trace.fraction < oldFrac then
		tw.trace.surfaceFlags = patch.surfaceFlags
		tw.trace.contents = patch.contents
	end
end

local function CM_TraceThroughBrush(tw, brush)
	local enterFrac, leaveFrac = -1.0, 1.0
	local clipplane = nil
	local numsides = brush.numsides

	if numsides == 0 then
		return
	end

	counters.c_brush_traces += 1

	local getout, startout = false, false
	local leadside = nil
	local sides = brush.sides
	local st, en = tw.start, tw["end"]
	local s0, s1, s2 = st[0], st[1], st[2]
	local e0, e1, e2 = en[0], en[1], en[2]

	if tw.sphere.use then
		-- compare the trace against all planes of the brush
		-- find the latest time the trace crosses a plane towards the interior
		-- and the earliest time the trace crosses a plane towards the exterior
		local sphere = tw.sphere
		local so = sphere.offset
		local o0, o1, o2 = so[0], so[1], so[2]
		for i = 0, numsides - 1 do
			local side = sides[i]
			local plane = side.plane
			local n = plane.normal
			local n0, n1, n2 = n[0], n[1], n[2]

			-- adjust the plane distance appropriately for radius
			local dist = f(plane.dist + sphere.radius)

			-- find the closest point on the capsule to the plane
			local t = f(f(f(n0 * o0) + f(n1 * o1)) + f(n2 * o2))
			local a0, a1, a2, b0, b1, b2
			if t > 0 then
				a0, a1, a2 = f(s0 - o0), f(s1 - o1), f(s2 - o2)
				b0, b1, b2 = f(e0 - o0), f(e1 - o1), f(e2 - o2)
			else
				a0, a1, a2 = f(s0 + o0), f(s1 + o1), f(s2 + o2)
				b0, b1, b2 = f(e0 + o0), f(e1 + o1), f(e2 + o2)
			end

			local d1 = f(f(f(f(a0 * n0) + f(a1 * n1)) + f(a2 * n2)) - dist)
			local d2 = f(f(f(f(b0 * n0) + f(b1 * n1)) + f(b2 * n2)) - dist)

			if d2 > 0 then
				getout = true -- endpoint is not in solid
			end
			if d1 > 0 then
				startout = true
			end

			-- if completely in front of face, no intersection with the entire brush
			if d1 > 0 and (d2 >= SURFACE_CLIP_EPSILON or d2 >= d1) then
				return
			end

			-- if it doesn't cross the plane, the plane isn't relevant
			if d1 <= 0 and d2 <= 0 then
				continue
			end

			-- crosses face
			if d1 > d2 then -- enter
				local fr = f((d1 - SURFACE_CLIP_EPSILON) / f(d1 - d2))
				if fr < 0 then
					fr = 0
				end
				if fr > enterFrac then
					enterFrac = fr
					clipplane = plane
					leadside = side
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
		end
	else
		-- compare the trace against all planes of the brush
		-- find the latest time the trace crosses a plane towards the interior
		-- and the earliest time the trace crosses a plane towards the exterior
		local offsets = tw.offsets
		for i = 0, numsides - 1 do
			local side = sides[i]
			local plane = side.plane
			local n = plane.normal
			local n0, n1, n2 = n[0], n[1], n[2]
			local o = offsets[plane.signbits]

			-- adjust the plane distance appropriately for mins/maxs
			local dist = f(plane.dist - f(f(f(o[0] * n0) + f(o[1] * n1)) + f(o[2] * n2)))

			local d1 = f(f(f(f(s0 * n0) + f(s1 * n1)) + f(s2 * n2)) - dist)
			local d2 = f(f(f(f(e0 * n0) + f(e1 * n1)) + f(e2 * n2)) - dist)

			if d2 > 0 then
				getout = true -- endpoint is not in solid
			end
			if d1 > 0 then
				startout = true
			end

			-- if completely in front of face, no intersection with the entire brush
			if d1 > 0 and (d2 >= SURFACE_CLIP_EPSILON or d2 >= d1) then
				return
			end

			-- if it doesn't cross the plane, the plane isn't relevant
			if d1 <= 0 and d2 <= 0 then
				continue
			end

			-- crosses face
			if d1 > d2 then -- enter
				local fr = f((d1 - SURFACE_CLIP_EPSILON) / f(d1 - d2))
				if fr < 0 then
					fr = 0
				end
				if fr > enterFrac then
					enterFrac = fr
					clipplane = plane
					leadside = side
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
		end
	end

	-- all planes have been checked, and the trace was not
	-- completely outside the brush
	local trace = tw.trace
	if not startout then -- original point was inside brush
		trace.startsolid = true
		if not getout then
			trace.allsolid = true
			trace.fraction = 0
			trace.contents = brush.contents
		end
		return
	end

	if enterFrac < leaveFrac then
		if enterFrac > -1 and enterFrac < trace.fraction then
			if enterFrac < 0 then
				enterFrac = 0
			end
			trace.fraction = enterFrac
			if clipplane ~= nil then
				S.copy_cplane_t(trace.plane, clipplane)
			end
			if leadside ~= nil then
				trace.surfaceFlags = leadside.surfaceFlags
			end
			trace.contents = brush.contents
		end
	end
end

local function CM_TraceThroughLeaf(tw, leaf)
	local cm = L.cm
	local checkcount = cm.checkcount
	local leafbrushes, brushes = cm.leafbrushes, cm.brushes
	local tb0, tb1 = tw.bounds[0], tw.bounds[1]
	local trace = tw.trace

	-- trace line against all brushes in the leaf
	for k = 0, leaf.numLeafBrushes - 1 do
		local b = brushes[leafbrushes[leaf.firstLeafBrush + k]]
		if b.checkcount == checkcount then
			continue -- already checked this brush in another leaf
		end
		b.checkcount = checkcount

		if band(b.contents, tw.contents) == 0 then
			continue
		end

		-- CM_BoundsIntersect
		local bb0, bb1 = b.bounds[0], b.bounds[1]
		if tb1[0] < bb0[0] - SURFACE_CLIP_EPSILON or tb1[1] < bb0[1] - SURFACE_CLIP_EPSILON
			or tb1[2] < bb0[2] - SURFACE_CLIP_EPSILON or tb0[0] > bb1[0] + SURFACE_CLIP_EPSILON
			or tb0[1] > bb1[1] + SURFACE_CLIP_EPSILON or tb0[2] > bb1[2] + SURFACE_CLIP_EPSILON
		then
			continue
		end

		CM_TraceThroughBrush(tw, b)
		if trace.fraction == 0 then
			return
		end
	end

	-- trace line against all patches in the leaf
	if L.cvars.cm_noCurves == 0 then
		for k = 0, leaf.numLeafSurfaces - 1 do
			local patch = cm.surfaces[cm.leafsurfaces[leaf.firstLeafSurface + k]]
			if not patch then
				continue
			end
			if patch.checkcount == checkcount then
				continue -- already checked this patch in another leaf
			end
			patch.checkcount = checkcount

			if band(patch.contents, tw.contents) == 0 then
				continue
			end

			CM_TraceThroughPatch(tw, patch)
			if trace.fraction == 0 then
				return
			end
		end
	end
end

-- get the first intersection of the ray with the sphere
local function CM_TraceThroughSphere(tw, origin, radius: number, start, endp)
	local dir, v1, intersection = vec3(), vec3(), vec3()
	local trace = tw.trace
	local radius2 = f(radius * radius)

	-- if inside the sphere
	VectorSubtract(start, origin, dir)
	local l1 = VectorLengthSquared(dir)
	if l1 < radius2 then
		trace.fraction = 0
		trace.startsolid = true
		-- test for allsolid
		VectorSubtract(endp, origin, dir)
		l1 = VectorLengthSquared(dir)
		if l1 < radius2 then
			trace.allsolid = true
		end
		return
	end

	VectorSubtract(endp, start, dir)
	local length = Q.VectorNormalizeIoq3(dir)

	l1 = CM_DistanceFromLineSquared(origin, start, endp, dir)
	VectorSubtract(endp, origin, v1)
	local l2 = VectorLengthSquared(v1)
	-- if no intersection with the sphere and the end point is at least an epsilon away
	local re = radius + SURFACE_CLIP_EPSILON
	if l1 >= radius2 and l2 > re * re then
		return
	end

	--	| origin - (start + t * dir) | = radius
	VectorSubtract(start, origin, v1)
	-- dir is normalized so a = 1
	local b = f(2.0 * f(f(f(dir[0] * v1[0]) + f(dir[1] * v1[1])) + f(dir[2] * v1[2])))
	local rr = f(radius + RADIUS_EPSILON)
	local c = f(f(f(f(v1[0] * v1[0]) + f(v1[1] * v1[1])) + f(v1[2] * v1[2])) - f(rr * rr))

	local d = f(f(b * b) - f(4.0 * c))
	if d > 0 then
		local sqrtd = SquareRootFloat(d)
		local fraction = f(f(-b - sqrtd) * 0.5)
		if fraction < 0 then
			fraction = 0
		else
			fraction = f(fraction / length)
		end
		if fraction < trace.fraction then
			trace.fraction = fraction
			VectorSubtract(endp, start, dir)
			Q.VectorMA(start, fraction, dir, intersection)
			VectorSubtract(intersection, origin, dir)
			local scale = f(1 / rr)
			Q.VectorScale(dir, scale, dir)
			VectorCopy(dir, trace.plane.normal)
			VectorAdd(tw.modelOrigin, intersection, intersection)
			trace.plane.dist = DotProduct(trace.plane.normal, intersection)
			trace.contents = CONTENTS_BODY
		end
	end
	-- d == 0: slide along the sphere; otherwise no intersection at all
end

-- get the first intersection of the ray with the cylinder
-- the cylinder extends halfheight above and below the origin
local function CM_TraceThroughVerticalCylinder(tw, origin, radius: number, halfheight: number, start, endp)
	local trace = tw.trace
	local dir, v1, intersection = vec3(), vec3(), vec3()
	local radius2 = f(radius * radius)

	-- 2d coordinates
	local start2d = vec3(start[0], start[1], 0)
	local end2d = vec3(endp[0], endp[1], 0)
	local org2d = vec3(origin[0], origin[1], 0)
	-- if between lower and upper cylinder bounds
	if start[2] <= f(origin[2] + halfheight) and start[2] >= f(origin[2] - halfheight) then
		-- if inside the cylinder
		VectorSubtract(start2d, org2d, dir)
		local l1 = VectorLengthSquared(dir)
		if l1 < radius2 then
			trace.fraction = 0
			trace.startsolid = true
			VectorSubtract(end2d, org2d, dir)
			l1 = VectorLengthSquared(dir)
			if l1 < radius2 then
				trace.allsolid = true
			end
			return
		end
	end

	VectorSubtract(end2d, start2d, dir)
	local length = Q.VectorNormalizeIoq3(dir)

	local l1 = CM_DistanceFromLineSquared(org2d, start2d, end2d, dir)
	VectorSubtract(end2d, org2d, v1)
	local l2 = VectorLengthSquared(v1)
	-- if no intersection with the cylinder and the end point is at least an epsilon away
	local re = radius + SURFACE_CLIP_EPSILON
	if l1 >= radius2 and l2 > re * re then
		return
	end

	VectorSubtract(start, origin, v1)
	-- dir is normalized so we can use a = 1
	local b = f(2.0 * f(f(v1[0] * dir[0]) + f(v1[1] * dir[1])))
	local rr = f(radius + RADIUS_EPSILON)
	local c = f(f(f(v1[0] * v1[0]) + f(v1[1] * v1[1])) - f(rr * rr))

	local d = f(f(b * b) - f(4.0 * c))
	if d > 0 then
		local sqrtd = SquareRootFloat(d)
		local fraction = f(f(-b - sqrtd) * 0.5)
		if fraction < 0 then
			fraction = 0
		else
			fraction = f(fraction / length)
		end
		if fraction < trace.fraction then
			VectorSubtract(endp, start, dir)
			Q.VectorMA(start, fraction, dir, intersection)
			-- if the intersection is between the cylinder lower and upper bound
			if intersection[2] <= f(origin[2] + halfheight) and intersection[2] >= f(origin[2] - halfheight) then
				trace.fraction = fraction
				VectorSubtract(intersection, origin, dir)
				dir[2] = 0
				local scale = f(1 / rr)
				Q.VectorScale(dir, scale, dir)
				VectorCopy(dir, trace.plane.normal)
				VectorAdd(tw.modelOrigin, intersection, intersection)
				trace.plane.dist = DotProduct(trace.plane.normal, intersection)
				trace.contents = CONTENTS_BODY
			end
		end
	end
	-- d == 0: slide along the cylinder; otherwise no intersection at all
end

-- capsule vs. capsule collision (not rotated)
local function CM_TraceCapsuleThroughCapsule(tw, model: number)
	local mins, maxs = vec3(), vec3()
	L.CM_ModelBounds(model, mins, maxs)
	-- test trace bounds vs. capsule bounds
	local tb0, tb1 = tw.bounds[0], tw.bounds[1]
	if tb0[0] > f(maxs[0] + RADIUS_EPSILON) or tb0[1] > f(maxs[1] + RADIUS_EPSILON) or tb0[2] > f(maxs[2] + RADIUS_EPSILON)
		or tb1[0] < f(mins[0] - RADIUS_EPSILON) or tb1[1] < f(mins[1] - RADIUS_EPSILON) or tb1[2] < f(mins[2] - RADIUS_EPSILON)
	then
		return
	end
	-- top origin and bottom origin of each sphere at start and end of trace
	local starttop, startbottom, endtop, endbottom = vec3(), vec3(), vec3(), vec3()
	VectorAdd(tw.start, tw.sphere.offset, starttop)
	VectorSubtract(tw.start, tw.sphere.offset, startbottom)
	VectorAdd(tw["end"], tw.sphere.offset, endtop)
	VectorSubtract(tw["end"], tw.sphere.offset, endbottom)

	-- calculate top and bottom of the capsule spheres to collide with
	local offset = vec3()
	local symetricSize = { [0] = vec3(), vec3() }
	for i = 0, 2 do
		offset[i] = f(f(mins[i] + maxs[i]) * 0.5)
		symetricSize[0][i] = f(mins[i] - offset[i])
		symetricSize[1][i] = f(maxs[i] - offset[i])
	end
	local halfwidth = symetricSize[1][0]
	local halfheight = symetricSize[1][2]
	local radius = if halfwidth > halfheight then halfheight else halfwidth
	local offs = f(halfheight - radius)
	local top = vec3(offset[0], offset[1], f(offset[2] + offs))
	local bottom = vec3(offset[0], offset[1], f(offset[2] - offs))
	-- expand radius of spheres
	radius = f(radius + tw.sphere.radius)
	-- if there is horizontal movement
	if tw.start[0] ~= tw["end"][0] or tw.start[1] ~= tw["end"][1] then
		-- height of the expanded cylinder is the height of both cylinders minus the radius of both spheres
		local h = f(f(halfheight + tw.sphere.halfheight) - radius)
		-- if the cylinder has a height
		if h > 0 then
			-- test for collisions between the cylinders
			CM_TraceThroughVerticalCylinder(tw, offset, radius, h, tw.start, tw["end"])
		end
	end
	-- test for collision between the spheres
	CM_TraceThroughSphere(tw, top, radius, startbottom, endbottom)
	CM_TraceThroughSphere(tw, bottom, radius, starttop, endtop)
end

-- bounding box vs. capsule collision
local function CM_TraceBoundingBoxThroughCapsule(tw, model: number)
	local cmod = capsuleFromModel(tw, model)
	CM_TraceThroughLeaf(tw, cmod.leaf)
end

--=========================================================================================

-- Traverse all the contacted leafs from the start to the end position.
-- If the trace is a point, they will be exactly in order, but for larger
-- trace volumes it is possible to hit something in a later leaf with
-- a smaller intercept fraction.
-- p1/p2 are passed as components to avoid allocating the C stack vectors.
local function CM_TraceThroughTree(tw, num: number, p1f: number, p2f: number,
	p10: number, p11: number, p12: number, p20: number, p21: number, p22: number)
	if tw.trace.fraction <= p1f then
		return -- already hit something nearer
	end

	-- if < 0, we are in a leaf node
	if num < 0 then
		CM_TraceThroughLeaf(tw, L.cm.leafs[-1 - num])
		return
	end

	-- find the point distances to the separating plane
	-- and the offset for the size of the box
	local node = L.cm.nodes[num]
	local plane = node.plane
	local ptype = plane.type
	local t1, t2, offset

	-- adjust the plane distance appropriately for mins/maxs
	if ptype < 3 then
		local pd = plane.dist
		if ptype == 0 then
			t1, t2 = f(p10 - pd), f(p20 - pd)
		elseif ptype == 1 then
			t1, t2 = f(p11 - pd), f(p21 - pd)
		else
			t1, t2 = f(p12 - pd), f(p22 - pd)
		end
		offset = tw.extents[ptype]
	else
		local n = plane.normal
		local n0, n1, n2 = n[0], n[1], n[2]
		t1 = f(f(f(f(n0 * p10) + f(n1 * p11)) + f(n2 * p12)) - plane.dist)
		t2 = f(f(f(f(n0 * p20) + f(n1 * p21)) + f(n2 * p22)) - plane.dist)
		if tw.isPoint then
			offset = 0
		else
			-- this is silly
			offset = 2048
		end
	end

	-- see which sides we need to consider
	local op1 = f(offset + 1)
	if t1 >= op1 and t2 >= op1 then
		CM_TraceThroughTree(tw, node.children[0], p1f, p2f, p10, p11, p12, p20, p21, p22)
		return
	end
	local om1 = f(-offset - 1)
	if t1 < om1 and t2 < om1 then
		CM_TraceThroughTree(tw, node.children[1], p1f, p2f, p10, p11, p12, p20, p21, p22)
		return
	end

	-- put the crosspoint SURFACE_CLIP_EPSILON pixels on the near side
	local side, frac, frac2
	if t1 < t2 then
		local idist = f(1.0 / f(t1 - t2))
		side = 1
		frac2 = f((f(t1 + offset) + SURFACE_CLIP_EPSILON) * idist)
		frac = f((f(t1 - offset) + SURFACE_CLIP_EPSILON) * idist)
	elseif t1 > t2 then
		local idist = f(1.0 / f(t1 - t2))
		side = 0
		frac2 = f((f(t1 - offset) - SURFACE_CLIP_EPSILON) * idist)
		frac = f((f(t1 + offset) + SURFACE_CLIP_EPSILON) * idist)
	else
		side = 0
		frac = 1
		frac2 = 0
	end

	-- move up to the node
	if frac < 0 then
		frac = 0
	end
	if frac > 1 then
		frac = 1
	end

	local midf = f(p1f + f(f(p2f - p1f) * frac))
	local m0 = f(p10 + f(frac * f(p20 - p10)))
	local m1 = f(p11 + f(frac * f(p21 - p11)))
	local m2 = f(p12 + f(frac * f(p22 - p12)))

	CM_TraceThroughTree(tw, node.children[side], p1f, midf, p10, p11, p12, m0, m1, m2)

	-- go past the node
	if frac2 < 0 then
		frac2 = 0
	end
	if frac2 > 1 then
		frac2 = 1
	end

	midf = f(p1f + f(f(p2f - p1f) * frac2))
	m0 = f(p10 + f(frac2 * f(p20 - p10)))
	m1 = f(p11 + f(frac2 * f(p21 - p11)))
	m2 = f(p12 + f(frac2 * f(p22 - p12)))

	CM_TraceThroughTree(tw, node.children[1 - side], midf, p2f, m0, m1, m2, p20, p21, p22)
end

--======================================================================

local ZERO = vec3()

local function resetTrace(t)
	t.allsolid = false
	t.startsolid = false
	t.fraction = 0
	local e, p = t.endpos, t.plane
	e[0], e[1], e[2] = 0, 0, 0
	p.normal[0], p.normal[1], p.normal[2] = 0, 0, 0
	p.dist, p.type, p.signbits = 0, 0, 0
	t.surfaceFlags, t.contents, t.entityNum = 0, 0, 0
end

-- sphere: optional { use, radius, halfheight, offset } (CM_TransformedBoxTrace)
local function CM_Trace(results, start, endp, mins, maxs, model: number, origin, brushmask: number, capsule: boolean, sphere)
	local cm = L.cm
	local cmod = L.CM_ClipHandleToModel(model)

	cm.checkcount += 1 -- for multi-check avoidance
	counters.c_traces += 1 -- for statistics, may be zeroed

	-- fill in a default trace
	local tw = tw0
	resetTrace(tw.trace)
	tw.trace.fraction = 1 -- assume it goes the entire distance until shown otherwise
	VectorCopy(origin, tw.modelOrigin)
	tw.isPoint = false
	tw.maxOffset = 0
	Q.VectorClear(tw.extents)

	if cm.numNodes == 0 then
		S.copy_trace_t(results, tw.trace)
		return -- map not loaded, shouldn't happen
	end

	-- allow NULL to be passed in for 0,0,0
	mins = mins or ZERO
	maxs = maxs or ZERO

	-- set basic parms
	tw.contents = brushmask

	-- adjust so that mins and maxs are always symetric, which
	-- avoids some complications with plane expanding of rotated
	-- bmodels
	local size0, size1, twstart, twend = tw.size[0], tw.size[1], tw.start, tw["end"]
	for i = 0, 2 do
		local offset = f(f(mins[i] + maxs[i]) * 0.5)
		size0[i] = f(mins[i] - offset)
		size1[i] = f(maxs[i] - offset)
		twstart[i] = f(start[i] + offset)
		twend[i] = f(endp[i] + offset)
	end

	-- if a sphere is already specified
	local tsphere = tw.sphere
	if sphere then
		tsphere.use = sphere.use
		tsphere.radius = sphere.radius
		tsphere.halfheight = sphere.halfheight
		VectorCopy(sphere.offset, tsphere.offset)
	else
		tsphere.use = capsule
		tsphere.radius = if size1[0] > size1[2] then size1[2] else size1[0]
		tsphere.halfheight = size1[2]
		Q.VectorSet(tsphere.offset, 0, 0, f(size1[2] - tsphere.radius))
	end

	tw.maxOffset = f(f(size1[0] + size1[1]) + size1[2])

	-- tw.offsets[signbits] = vector to appropriate corner from origin
	local offs = tw.offsets
	for sb = 0, 7 do
		local o = offs[sb]
		o[0] = if band(sb, 1) ~= 0 then size1[0] else size0[0]
		o[1] = if band(sb, 2) ~= 0 then size1[1] else size0[1]
		o[2] = if band(sb, 4) ~= 0 then size1[2] else size0[2]
	end

	-- calculate bounds
	local b0, b1 = tw.bounds[0], tw.bounds[1]
	if tsphere.use then
		for i = 0, 2 do
			local so = abs(tsphere.offset[i])
			if twstart[i] < twend[i] then
				b0[i] = f(f(twstart[i] - so) - tsphere.radius)
				b1[i] = f(f(twend[i] + so) + tsphere.radius)
			else
				b0[i] = f(f(twend[i] - so) - tsphere.radius)
				b1[i] = f(f(twstart[i] + so) + tsphere.radius)
			end
		end
	else
		for i = 0, 2 do
			if twstart[i] < twend[i] then
				b0[i] = f(twstart[i] + size0[i])
				b1[i] = f(twend[i] + size1[i])
			else
				b0[i] = f(twend[i] + size0[i])
				b1[i] = f(twstart[i] + size1[i])
			end
		end
	end

	-- check for position test special case
	if start[0] == endp[0] and start[1] == endp[1] and start[2] == endp[2] then
		if model ~= 0 then
			if model == CAPSULE_MODEL_HANDLE then
				if tsphere.use then
					CM_TestCapsuleInCapsule(tw, model)
				else
					CM_TestBoundingBoxInCapsule(tw, model)
				end
			else
				CM_TestInLeaf(tw, cmod.leaf)
			end
		else
			CM_PositionTest(tw)
		end
	else
		-- check for point special case
		if size0[0] == 0 and size0[1] == 0 and size0[2] == 0 then
			tw.isPoint = true
			Q.VectorClear(tw.extents)
		else
			tw.isPoint = false
			tw.extents[0] = size1[0]
			tw.extents[1] = size1[1]
			tw.extents[2] = size1[2]
		end

		-- general sweeping through world
		if model ~= 0 then
			if model == CAPSULE_MODEL_HANDLE then
				if tsphere.use then
					CM_TraceCapsuleThroughCapsule(tw, model)
				else
					CM_TraceBoundingBoxThroughCapsule(tw, model)
				end
			else
				CM_TraceThroughLeaf(tw, cmod.leaf)
			end
		else
			CM_TraceThroughTree(tw, 0, 0, 1, twstart[0], twstart[1], twstart[2], twend[0], twend[1], twend[2])
		end
	end

	-- generate endpos from the original, unmodified start/end
	local trace = tw.trace
	if trace.fraction == 1 then
		VectorCopy(endp, trace.endpos)
	else
		local fr = trace.fraction
		for i = 0, 2 do
			trace.endpos[i] = f(start[i] + f(fr * f(endp[i] - start[i])))
		end
	end

	S.copy_trace_t(results, trace)
end

function L.CM_BoxTrace(results, start, endp, mins, maxs, model: number, brushmask: number, capsule: boolean?)
	CM_Trace(results, start, endp, mins, maxs, model, Q.vec3_origin, brushmask, capsule == true, nil)
end

-- Handles offseting and rotation of the end points for moving and
-- rotating entities
function L.CM_TransformedBoxTrace(results, start, endp, mins, maxs, model: number, brushmask: number, origin, angles, capsule: boolean?)
	mins = mins or ZERO
	maxs = maxs or ZERO

	-- adjust so that mins and maxs are always symetric, which
	-- avoids some complications with plane expanding of rotated
	-- bmodels
	local symetricSize = { [0] = vec3(), vec3() }
	local start_l, end_l = vec3(), vec3()
	for i = 0, 2 do
		local offset = f(f(mins[i] + maxs[i]) * 0.5)
		symetricSize[0][i] = f(mins[i] - offset)
		symetricSize[1][i] = f(maxs[i] - offset)
		start_l[i] = f(start[i] + offset)
		end_l[i] = f(endp[i] + offset)
	end

	-- subtract origin offset
	VectorSubtract(start_l, origin, start_l)
	VectorSubtract(end_l, origin, end_l)

	-- rotate start and end into the models frame of reference
	local rotated = model ~= BOX_MODEL_HANDLE and (angles[0] ~= 0 or angles[1] ~= 0 or angles[2] ~= 0)

	local halfwidth = symetricSize[1][0]
	local halfheight = symetricSize[1][2]

	local sphere = { use = capsule == true, radius = 0, halfheight = 0, offset = vec3() }
	sphere.radius = if halfwidth > halfheight then halfheight else halfwidth
	sphere.halfheight = halfheight
	local t = f(halfheight - sphere.radius)

	local matrix = Q.mat3()
	if rotated then
		-- rotation on trace line (start-end) instead of rotating the bmodel
		-- NOTE: This is still incorrect for bounding boxes because the actual bounding
		--		 box that is swept through the model is not rotated. We cannot rotate
		--		 the bounding box or the bmodel because that would make all the brush
		--		 bevels invalid.
		--		 However this is correct for capsules since a capsule itself is rotated too.
		CreateRotationMatrix(angles, matrix)
		RotatePoint(start_l, matrix)
		RotatePoint(end_l, matrix)
		-- rotated sphere offset for capsule
		sphere.offset[0] = f(matrix[0][2] * t)
		sphere.offset[1] = f(-matrix[1][2] * t)
		sphere.offset[2] = f(matrix[2][2] * t)
	else
		Q.VectorSet(sphere.offset, 0, 0, t)
	end

	-- sweep the box through the model
	local trace = S.trace_t()
	CM_Trace(trace, start_l, end_l, symetricSize[0], symetricSize[1], model, origin, brushmask, capsule == true, sphere)

	-- if the bmodel was rotated and there was a collision
	if rotated and trace.fraction ~= 1.0 then
		-- rotation of bmodel collision plane
		local transpose = Q.mat3()
		TransposeMatrix(matrix, transpose)
		RotatePoint(trace.plane.normal, transpose)
	end

	-- re-calculate the end position of the trace because the trace.endpos
	-- calculated by CM_Trace could be rotated and have an offset
	local fr = trace.fraction
	for i = 0, 2 do
		trace.endpos[i] = f(start[i] + f(fr * f(endp[i] - start[i])))
	end

	S.copy_trace_t(results, trace)
end

return L
