--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (qcommon/cm_test.c).

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

local Q = require("../q_math")
local L = require("./cm_local")

local f = Q.f
local SURFACE_CLIP_EPSILON = L.SURFACE_CLIP_EPSILON
local BoxOnPlaneSide = Q.BoxOnPlaneSide

local function CM_PointLeafnum_r(p, num: number): number
	local cm = L.cm
	local nodes = cm.nodes
	while num >= 0 do
		local node = nodes[num]
		local plane = node.plane
		local d
		if plane.type < 3 then
			d = f(p[plane.type] - plane.dist)
		else
			d = f(Q.DotProduct(plane.normal, p) - plane.dist)
		end
		if d < 0 then
			num = node.children[1]
		else
			num = node.children[0]
		end
	end
	L.counters.c_pointcontents += 1 -- optimize counter
	return -1 - num
end
L.CM_PointLeafnum_r = CM_PointLeafnum_r

function L.CM_PointLeafnum(p): number
	if L.cm.numNodes == 0 then -- map not loaded
		return 0
	end
	return CM_PointLeafnum_r(p, 0)
end

--[[
======================================================================
LEAF LISTING
======================================================================
	leafList = { count, maxcount, overflowed, list = {[0]=...}, bounds = {[0]=mins, maxs},
	             lastLeaf, storeLeafs = function(ll, nodenum) }
]]

function L.CM_StoreLeafs(ll, nodenum: number)
	local leafNum = -1 - nodenum

	-- store the lastLeaf even if the list is overflowed
	if L.cm.leafs[leafNum].cluster ~= -1 then
		ll.lastLeaf = leafNum
	end

	if ll.count >= ll.maxcount then
		ll.overflowed = true
		return
	end
	ll.list[ll.count] = leafNum
	ll.count += 1
end

function L.CM_StoreBrushes(ll, nodenum: number)
	local cm = L.cm
	local leafnum = -1 - nodenum
	local leaf = cm.leafs[leafnum]

	for k = 0, leaf.numLeafBrushes - 1 do
		local brushnum = cm.leafbrushes[leaf.firstLeafBrush + k]
		local b = cm.brushes[brushnum]
		if b.checkcount == cm.checkcount then
			continue -- already checked this brush in another leaf
		end
		b.checkcount = cm.checkcount
		local i = 0
		while i < 3 do
			if b.bounds[0][i] >= ll.bounds[1][i] or b.bounds[1][i] <= ll.bounds[0][i] then
				break
			end
			i += 1
		end
		if i ~= 3 then
			continue
		end
		if ll.count >= ll.maxcount then
			ll.overflowed = true
			return
		end
		ll.list[ll.count] = b
		ll.count += 1
	end
end

-- Fills in a list of all the leafs touched
local function CM_BoxLeafnums_r(ll, nodenum: number)
	local nodes = L.cm.nodes
	while true do
		if nodenum < 0 then
			ll.storeLeafs(ll, nodenum)
			return
		end

		local node = nodes[nodenum]
		local s = BoxOnPlaneSide(ll.bounds[0], ll.bounds[1], node.plane)
		if s == 1 then
			nodenum = node.children[0]
		elseif s == 2 then
			nodenum = node.children[1]
		else
			-- go down both
			CM_BoxLeafnums_r(ll, node.children[0])
			nodenum = node.children[1]
		end
	end
end
L.CM_BoxLeafnums_r = CM_BoxLeafnums_r

local function newLeafList(mins, maxs, list, listsize: number, store)
	return {
		bounds = { [0] = { [0] = mins[0], mins[1], mins[2] }, { [0] = maxs[0], maxs[1], maxs[2] } },
		count = 0,
		maxcount = listsize,
		list = list,
		storeLeafs = store,
		lastLeaf = 0,
		overflowed = false,
	}
end
L.newLeafList = newLeafList

-- returns count, lastLeaf; list is filled 0-based
function L.CM_BoxLeafnums(mins, maxs, list, listsize: number): (number, number)
	local cm = L.cm
	cm.checkcount += 1
	local ll = newLeafList(mins, maxs, list, listsize, L.CM_StoreLeafs)
	CM_BoxLeafnums_r(ll, 0)
	return ll.count, ll.lastLeaf
end

function L.CM_BoxBrushes(mins, maxs, list, listsize: number): number
	local cm = L.cm
	cm.checkcount += 1
	local ll = newLeafList(mins, maxs, list, listsize, L.CM_StoreBrushes)
	CM_BoxLeafnums_r(ll, 0)
	return ll.count
end

--====================================================================

function L.CM_PointContents(p, model: number): number
	local cm = L.cm
	if cm.numNodes == 0 then -- map not loaded
		return 0
	end

	local leaf
	if model ~= 0 then
		local clipm = L.CM_ClipHandleToModel(model)
		leaf = clipm.leaf
	else
		local leafnum = CM_PointLeafnum_r(p, 0)
		leaf = cm.leafs[leafnum]
	end

	local contents = 0
	local p0, p1, p2 = p[0], p[1], p[2]
	for k = 0, leaf.numLeafBrushes - 1 do
		local brushnum = cm.leafbrushes[leaf.firstLeafBrush + k]
		local b = cm.brushes[brushnum]

		if not L.CM_BoundsIntersectPoint(b.bounds[0], b.bounds[1], p) then
			continue
		end

		-- see if the point is in the brush
		local sides = b.sides
		local n = b.numsides
		local i = 0
		while i < n do
			local pl = sides[i].plane
			local nrm = pl.normal
			local d = f(f(f(p0 * nrm[0]) + f(p1 * nrm[1])) + f(p2 * nrm[2]))
			if d > pl.dist then
				break
			end
			i += 1
		end

		if i == n then
			contents = bit32.bor(contents, b.contents)
		end
	end

	return Q.int32(contents)
end

-- Handles offseting and rotation of the end points for moving and
-- rotating entities
function L.CM_TransformedPointContents(p, model: number, origin, angles): number
	local p_l = Q.vec3()
	-- subtract origin offset
	Q.VectorSubtract(p, origin, p_l)

	-- rotate start and end into the models frame of reference
	if model ~= L.BOX_MODEL_HANDLE and (angles[0] ~= 0 or angles[1] ~= 0 or angles[2] ~= 0) then
		local forward, right, up = Q.vec3(), Q.vec3(), Q.vec3()
		Q.AngleVectors(angles, forward, right, up)
		local temp = Q.vec3(p_l[0], p_l[1], p_l[2])
		p_l[0] = Q.DotProduct(temp, forward)
		p_l[1] = -Q.DotProduct(temp, right)
		p_l[2] = Q.DotProduct(temp, up)
	end

	return L.CM_PointContents(p_l, model)
end

--[[
===============================================================================
PVS
===============================================================================
]]

-- Returns the visibility buffer and the byte offset of the cluster's row.
function L.CM_ClusterPVS(cluster: number): (buffer?, number)
	local cm = L.cm
	if cluster < 0 or cluster >= cm.numClusters or not cm.vised then
		return cm.visibility, 0
	end
	return cm.visibility, cluster * cm.clusterBytes
end

--[[
===============================================================================
AREAPORTALS
===============================================================================
]]

local function CM_FloodArea_r(areaNum: number, floodnum: number)
	local cm = L.cm
	local area = cm.areas[areaNum]

	if area.floodvalid == cm.floodvalid then
		if area.floodnum == floodnum then
			return
		end
		error("FloodArea_r: reflooded")
	end

	area.floodnum = floodnum
	area.floodvalid = cm.floodvalid
	local base = areaNum * cm.numAreas
	for i = 0, cm.numAreas - 1 do
		if cm.areaPortals[base + i] > 0 then
			CM_FloodArea_r(i, floodnum)
		end
	end
end

function L.CM_FloodAreaConnections()
	local cm = L.cm
	-- all current floods are now invalid
	cm.floodvalid += 1
	local floodnum = 0

	for i = 0, cm.numAreas - 1 do
		local area = cm.areas[i]
		if area.floodvalid == cm.floodvalid then
			continue -- already flooded into
		end
		floodnum += 1
		CM_FloodArea_r(i, floodnum)
	end
end

function L.CM_AdjustAreaPortalState(area1: number, area2: number, open: boolean)
	local cm = L.cm
	if area1 < 0 or area2 < 0 then
		return
	end

	if area1 >= cm.numAreas or area2 >= cm.numAreas then
		error("CM_ChangeAreaPortalState: bad area number")
	end

	local ap = cm.areaPortals
	if open then
		ap[area1 * cm.numAreas + area2] += 1
		ap[area2 * cm.numAreas + area1] += 1
	else
		ap[area1 * cm.numAreas + area2] -= 1
		ap[area2 * cm.numAreas + area1] -= 1
		if ap[area2 * cm.numAreas + area1] < 0 then
			error("CM_AdjustAreaPortalState: negative reference count")
		end
	end

	L.CM_FloodAreaConnections()
end

function L.CM_AreasConnected(area1: number, area2: number): boolean
	local cm = L.cm
	if L.cvars.cm_noAreas ~= 0 then
		return true
	end

	if area1 < 0 or area2 < 0 then
		return false
	end

	if area1 >= cm.numAreas or area2 >= cm.numAreas then
		error("area >= cm.numAreas")
	end

	return cm.areas[area1].floodnum == cm.areas[area2].floodnum
end

-- Writes a bit vector of all the areas that are in the same flood as the area
-- parameter into the buffer (OR'd in). Returns the number of bytes needed.
function L.CM_WriteAreaBits(buf: buffer, area: number): number
	local cm = L.cm
	local bytes = bit32.rshift(cm.numAreas + 7, 3)

	if L.cvars.cm_noAreas ~= 0 or area == -1 then
		-- for debugging, send everything
		for i = 0, bytes - 1 do
			buffer.writeu8(buf, i, 255)
		end
	else
		local floodnum = cm.areas[area].floodnum
		for i = 0, cm.numAreas - 1 do
			if cm.areas[i].floodnum == floodnum or area == -1 then
				local o = bit32.rshift(i, 3)
				buffer.writeu8(buf, o, bit32.bor(buffer.readu8(buf, o), bit32.lshift(1, bit32.band(i, 7))))
			end
		end
	end

	return bytes
end

function L.CM_BoundsIntersect(mins, maxs, mins2, maxs2): boolean
	if maxs[0] < mins2[0] - SURFACE_CLIP_EPSILON
		or maxs[1] < mins2[1] - SURFACE_CLIP_EPSILON
		or maxs[2] < mins2[2] - SURFACE_CLIP_EPSILON
		or mins[0] > maxs2[0] + SURFACE_CLIP_EPSILON
		or mins[1] > maxs2[1] + SURFACE_CLIP_EPSILON
		or mins[2] > maxs2[2] + SURFACE_CLIP_EPSILON
	then
		return false
	end
	return true
end

function L.CM_BoundsIntersectPoint(mins, maxs, point): boolean
	if maxs[0] < point[0] - SURFACE_CLIP_EPSILON
		or maxs[1] < point[1] - SURFACE_CLIP_EPSILON
		or maxs[2] < point[2] - SURFACE_CLIP_EPSILON
		or mins[0] > point[0] + SURFACE_CLIP_EPSILON
		or mins[1] > point[1] + SURFACE_CLIP_EPSILON
		or mins[2] > point[2] + SURFACE_CLIP_EPSILON
	then
		return false
	end
	return true
end

return L
