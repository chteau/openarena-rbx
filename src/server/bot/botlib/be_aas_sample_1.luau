--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_sample.c, part 1 of 2).

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
-- Luau port of be_aas_sample.c (botlib/be_aas_sample.c, part 1 of 2). AAS environment sampling.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local SF = B.FileStatics("be_aas_sample")

SF.BBOX_NORMAL_EPSILON = 0.001
SF.ON_EPSILON = 0 --0.0005
SF.TRACEPLANE_EPSILON = 0.125

local BBOX_NORMAL_EPSILON = SF.BBOX_NORMAL_EPSILON
local ON_EPSILON = SF.ON_EPSILON
local TRACEPLANE_EPSILON = SF.TRACEPLANE_EPSILON

SF.numaaslinks = 0

-- aas_tracestack_t: { start, end_, planenum, nodenum }, preallocated (127 entries)
local tracestack = {}
for i = 0, 126 do
	tracestack[i] = {
		start = { [0] = 0, 0, 0 },
		end_ = { [0] = 0, 0, 0 },
		planenum = 0,
		nodenum = 0,
	}
end

local boxmins_tab = { [0] = { [0] = 0, 0, 0 }, { [0] = -15, -15, -24 }, { [0] = -15, -15, -24 } }
local boxmaxs_tab = { [0] = { [0] = 0, 0, 0 }, { [0] = 15, 15, 32 }, { [0] = 15, 15, 8 } }

function B.AAS_PresenceTypeBoundingBox(presencetype, mins, maxs)
	local index
	--bounding box size for each presence type
	if presencetype == BC.PRESENCE_NORMAL then
		index = 1
	elseif presencetype == BC.PRESENCE_CROUCH then
		index = 2
	else
		B.botimport.Print(BC.PRT_FATAL, "AAS_PresenceTypeBoundingBox: unknown presence type\n")
		index = 2
	end
	Q.VectorCopy(boxmins_tab[index], mins)
	Q.VectorCopy(boxmaxs_tab[index], maxs)
end

function B.AAS_InitAASLinkHeap()
	local aasworld = B.aasworld
	local max_aaslinks = aasworld.linkheapsize
	--if there's no link heap present
	if aasworld.linkheap == nil then
		max_aaslinks = Q.trunc(B.LibVarValue("max_aaslinks", "6144"))
		if max_aaslinks < 0 then max_aaslinks = 0 end
		aasworld.linkheapsize = max_aaslinks
		local heap = {}
		for i = 0, max_aaslinks - 1 do
			heap[i] = SB.aas_link_t()
		end
		aasworld.linkheap = heap
	end
	local linkheap = aasworld.linkheap
	--link the links on the heap
	linkheap[0].prev_ent = nil
	linkheap[0].next_ent = linkheap[1]
	for i = 1, max_aaslinks - 2 do
		linkheap[i].prev_ent = linkheap[i - 1]
		linkheap[i].next_ent = linkheap[i + 1]
	end
	linkheap[max_aaslinks - 1].prev_ent = linkheap[max_aaslinks - 2]
	linkheap[max_aaslinks - 1].next_ent = nil
	--pointer to the first free link
	aasworld.freelinks = linkheap[0]
	SF.numaaslinks = max_aaslinks
end

function B.AAS_FreeAASLinkHeap()
	local aasworld = B.aasworld
	aasworld.linkheap = nil
	aasworld.linkheapsize = 0
end

function B.AAS_AllocAASLink()
	local aasworld = B.aasworld
	local link = aasworld.freelinks
	if link == nil then
		local dev = B.botDeveloper
		if dev ~= nil and dev ~= false and dev ~= 0 then
			B.botimport.Print(BC.PRT_FATAL, "empty aas link heap\n")
		end
		return nil
	end
	if aasworld.freelinks ~= nil then aasworld.freelinks = aasworld.freelinks.next_ent end
	if aasworld.freelinks ~= nil then aasworld.freelinks.prev_ent = nil end
	SF.numaaslinks = SF.numaaslinks - 1
	return link
end

function B.AAS_DeAllocAASLink(link)
	local aasworld = B.aasworld
	if aasworld.freelinks ~= nil then aasworld.freelinks.prev_ent = link end
	link.prev_ent = nil
	link.next_ent = aasworld.freelinks
	link.prev_area = nil
	link.next_area = nil
	aasworld.freelinks = link
	SF.numaaslinks = SF.numaaslinks + 1
end

function B.AAS_InitAASLinkedEntities()
	local aasworld = B.aasworld
	if aasworld.loaded == 0 then return end
	aasworld.arealinkedentities = {}
end

function B.AAS_FreeAASLinkedEntities()
	local aasworld = B.aasworld
	aasworld.arealinkedentities = nil
end

-- returns the AAS area the point is in
function B.AAS_PointAreaNum(point)
	local aasworld = B.aasworld
	if aasworld.loaded == 0 then
		B.botimport.Print(BC.PRT_ERROR, "AAS_PointAreaNum: aas not loaded\n")
		return 0
	end

	--start with node 1 because node zero is a dummy used for solid leafs
	local nodenum = 1
	while nodenum > 0 do
		local node = aasworld.nodes[nodenum]
		local plane = aasworld.planes[node.planenum]
		local dist = Q.f(Q.DotProduct(point, plane.normal) - plane.dist)
		if dist > 0 then
			nodenum = node.children[0]
		else
			nodenum = node.children[1]
		end
	end
	if nodenum == 0 then
		return 0
	end
	return -nodenum
end

function B.AAS_PointReachabilityAreaIndex(origin)
	local aasworld = B.aasworld
	if aasworld.initialized == 0 then
		return 0
	end

	if origin == nil then
		local index = 0
		for i = 0, aasworld.numclusters - 1 do
			index += aasworld.clusters[i].numreachabilityareas
		end
		return index
	end

	local areanum = B.AAS_PointAreaNum(origin)
	if areanum == 0 or B.AAS_AreaReachability(areanum) == 0 then
		return 0
	end
	local cluster = aasworld.areasettings[areanum].cluster
	areanum = aasworld.areasettings[areanum].clusterareanum
	if cluster < 0 then
		cluster = aasworld.portals[-cluster].frontcluster
		areanum = aasworld.portals[-cluster].clusterareanum[0]
	end

	local index = 0
	for i = 0, cluster - 1 do
		index += aasworld.clusters[i].numreachabilityareas
	end
	index += areanum
	return index
end

function B.AAS_AreaCluster(areanum)
	local aasworld = B.aasworld
	if areanum <= 0 or areanum >= aasworld.numareas then
		B.botimport.Print(BC.PRT_ERROR, "AAS_AreaCluster: invalid area number\n")
		return 0
	end
	return aasworld.areasettings[areanum].cluster
end

-- returns the presence types of the given area
function B.AAS_AreaPresenceType(areanum)
	local aasworld = B.aasworld
	if aasworld.loaded == 0 then return 0 end
	if areanum <= 0 or areanum >= aasworld.numareas then
		B.botimport.Print(BC.PRT_ERROR, "AAS_AreaPresenceType: invalid area number\n")
		return 0
	end
	return aasworld.areasettings[areanum].presencetype
end

-- returns the presence type at the given point
function B.AAS_PointPresenceType(point)
	local aasworld = B.aasworld
	if aasworld.loaded == 0 then return 0 end

	local areanum = B.AAS_PointAreaNum(point)
	if areanum == 0 then return BC.PRESENCE_NONE end
	return aasworld.areasettings[areanum].presencetype
end

-- calculates the minimum distance between the origin of the box and the
-- given plane when both will collide on the given side of the plane
--
-- normal	=	normal vector of plane to calculate distance from
-- mins		=	minimums of box relative to origin
-- maxs		=	maximums of box relative to origin
-- side		=	side of the plane we want to calculate the distance from
--					0 normal vector side
--					1 not normal vector side
function B.AAS_BoxOriginDistanceFromPlane(normal, mins, maxs, side)
	local v1 = { [0] = 0, 0, 0 }
	local v2 = { [0] = 0, 0, 0 }

	--swap maxs and mins when on the other side of the plane
	if side ~= 0 then
		--get a point of the box that would be one of the first
		--to collide with the plane
		for i = 0, 2 do
			if normal[i] > BBOX_NORMAL_EPSILON then
				v1[i] = maxs[i]
			elseif normal[i] < -BBOX_NORMAL_EPSILON then
				v1[i] = mins[i]
			else
				v1[i] = 0
			end
		end
	else
		--get a point of the box that would be one of the first
		--to collide with the plane
		for i = 0, 2 do
			if normal[i] > BBOX_NORMAL_EPSILON then
				v1[i] = mins[i]
			elseif normal[i] < -BBOX_NORMAL_EPSILON then
				v1[i] = maxs[i]
			else
				v1[i] = 0
			end
		end
	end
	Q.VectorCopy(normal, v2)
	Q.VectorInverse(v2)
	return Q.DotProduct(v1, v2)
end

function B.AAS_AreaEntityCollision(areanum, start, end_, presencetype, passent, trace)
	local aasworld = B.aasworld
	local boxmins = { [0] = 0, 0, 0 }
	local boxmaxs = { [0] = 0, 0, 0 }
	local bsptrace = SB.bsp_trace_t()

	B.AAS_PresenceTypeBoundingBox(presencetype, boxmins, boxmaxs)

	--assume no collision
	bsptrace.fraction = 1
	local collision = false
	local link = aasworld.arealinkedentities[areanum]
	while link ~= nil do
		--ignore the pass entity
		if link.entnum ~= passent then
			if B.AAS_EntityCollision(link.entnum, start, boxmins, boxmaxs, end_,
				bit32.bor(BC.CONTENTS_SOLID, BC.CONTENTS_PLAYERCLIP), bsptrace) then
				collision = true
			end
		end
		link = link.next_ent
	end
	if collision then
		trace.startsolid = bsptrace.startsolid
		trace.ent = bsptrace.ent
		Q.VectorCopy(bsptrace.endpos, trace.endpos)
		trace.area = 0
		trace.planenum = 0
		return true
	end
	return false
end

-- recursive subdivision of the line by the BSP tree.
function B.AAS_TraceClientBBox(start, end_, presencetype, passent)
	local aasworld = B.aasworld
	local cur_start = { [0] = 0, 0, 0 }
	local cur_end = { [0] = 0, 0, 0 }
	local cur_mid = { [0] = 0, 0, 0 }
	local v1 = { [0] = 0, 0, 0 }
	local v2 = { [0] = 0, 0, 0 }
	local front, back, frac
	local trace = SB.aas_trace_t()

	if aasworld.loaded == 0 then return trace end

	local tp = 0
	--we start with the whole line on the stack
	local e = tracestack[tp]
	Q.VectorCopy(start, e.start)
	Q.VectorCopy(end_, e.end_)
	e.planenum = 0
	--start with node 1 because node zero is a dummy for a solid leaf
	e.nodenum = 1 --starting at the root of the tree
	tp += 1

	while true do
		--pop up the stack
		tp -= 1
		--if the trace stack is empty (ended up with a piece of the
		--line to be traced in an area)
		if tp < 0 then
			tp += 1
			--nothing was hit
			trace.startsolid = false
			trace.fraction = 1.0
			--endpos is the end of the line
			Q.VectorCopy(end_, trace.endpos)
			--nothing hit
			trace.ent = 0
			trace.area = 0
			trace.planenum = 0
			return trace
		end
		e = tracestack[tp]
		--number of the current node to test the line against
		local nodenum = e.nodenum
		--if it is an area
		if nodenum < 0 then
			--if can't enter the area because it hasn't got the right presence type
			if bit32.band(aasworld.areasettings[-nodenum].presencetype, presencetype) == 0 then
				--if the start point is still the initial start point
				--NOTE: no need for epsilons because the points will be
				--exactly the same when they're both the start point
				if e.start[0] == start[0] and
					e.start[1] == start[1] and
					e.start[2] == start[2] then
					trace.startsolid = true
					trace.fraction = 0.0
					Q.VectorClear(v1)
				else
					trace.startsolid = false
					Q.VectorSubtract(end_, start, v1)
					Q.VectorSubtract(e.start, start, v2)
					trace.fraction = Q.f(Q.VectorLength(v2) / Q.VectorNormalizeIoq3(v1))
					Q.VectorMA(e.start, -0.125, v1, e.start)
				end
				Q.VectorCopy(e.start, trace.endpos)
				trace.ent = 0
				trace.area = -nodenum
				trace.planenum = e.planenum
				--always take the plane with normal facing towards the trace start
				local plane = aasworld.planes[trace.planenum]
				if Q.DotProduct(v1, plane.normal) > 0 then trace.planenum = bit32.bxor(trace.planenum, 1) end
				return trace
			else
				if passent >= 0 then
					if B.AAS_AreaEntityCollision(-nodenum, e.start, e.end_, presencetype, passent, trace) then
						if not trace.startsolid then
							Q.VectorSubtract(end_, start, v1)
							Q.VectorSubtract(trace.endpos, start, v2)
							trace.fraction = Q.f(Q.VectorLength(v2) / Q.VectorLength(v1))
						end
						return trace
					end
				end
			end
			trace.lastarea = -nodenum
			continue
		end
		--if it is a solid leaf
		if nodenum == 0 then
			--if the start point is still the initial start point
			--NOTE: no need for epsilons because the points will be
			--exactly the same when they're both the start point
			if e.start[0] == start[0] and
				e.start[1] == start[1] and
				e.start[2] == start[2] then
				trace.startsolid = true
				trace.fraction = 0.0
				Q.VectorClear(v1)
			else
				trace.startsolid = false
				Q.VectorSubtract(end_, start, v1)
				Q.VectorSubtract(e.start, start, v2)
				trace.fraction = Q.f(Q.VectorLength(v2) / Q.VectorNormalizeIoq3(v1))
				Q.VectorMA(e.start, -0.125, v1, e.start)
			end
			Q.VectorCopy(e.start, trace.endpos)
			trace.ent = 0
			trace.area = 0 --hit solid leaf
			trace.planenum = e.planenum
			--always take the plane with normal facing towards the trace start
			local plane = aasworld.planes[trace.planenum]
			if Q.DotProduct(v1, plane.normal) > 0 then trace.planenum = bit32.bxor(trace.planenum, 1) end
			return trace
		end
		--the node to test against
		local aasnode = aasworld.nodes[nodenum]
		--start point of current line to test against node
		Q.VectorCopy(e.start, cur_start)
		--end point of the current line to test against node
		Q.VectorCopy(e.end_, cur_end)
		--the current node plane
		local plane = aasworld.planes[aasnode.planenum]

		--gee it's not an axial plane
		front = Q.f(Q.DotProduct(cur_start, plane.normal) - plane.dist)
		back = Q.f(Q.DotProduct(cur_end, plane.normal) - plane.dist)

		--if the whole to be traced line is totally at the front of this node
		--only go down the tree with the front child
		if front >= -ON_EPSILON and back >= -ON_EPSILON then
			--keep the current start and end point on the stack
			--and go down the tree with the front child
			e.nodenum = aasnode.children[0]
			tp += 1
			if tp >= 127 then
				B.botimport.Print(BC.PRT_ERROR, "AAS_TraceBoundingBox: stack overflow\n")
				return trace
			end
		--if the whole to be traced line is totally at the back of this node
		--only go down the tree with the back child
		elseif front < ON_EPSILON and back < ON_EPSILON then
			--keep the current start and end point on the stack
			--and go down the tree with the back child
			e.nodenum = aasnode.children[1]
			tp += 1
			if tp >= 127 then
				B.botimport.Print(BC.PRT_ERROR, "AAS_TraceBoundingBox: stack overflow\n")
				return trace
			end
		--go down the tree both at the front and back of the node
		else
			local tmpplanenum = e.planenum
			if front == back then front = Q.f(front - Q.f(0.001)) end
			--calculate the hitpoint with the node (split point of the line)
			--put the crosspoint TRACEPLANE_EPSILON pixels on the near side
			if front < 0 then
				frac = Q.f(Q.f(front + TRACEPLANE_EPSILON) / Q.f(front - back))
			else
				frac = Q.f(Q.f(front - TRACEPLANE_EPSILON) / Q.f(front - back))
			end
			if frac < 0 then
				frac = Q.f(0.001)
			elseif frac > 1 then
				frac = Q.f(0.999)
			end
			cur_mid[0] = Q.f(cur_start[0] + Q.f(Q.f(cur_end[0] - cur_start[0]) * frac))
			cur_mid[1] = Q.f(cur_start[1] + Q.f(Q.f(cur_end[1] - cur_start[1]) * frac))
			cur_mid[2] = Q.f(cur_start[2] + Q.f(Q.f(cur_end[2] - cur_start[2]) * frac))

			--side the front part of the line is on
			local side = if front < 0 then 1 else 0
			--first put the end part of the line on the stack (back side)
			Q.VectorCopy(cur_mid, e.start)
			e.planenum = aasnode.planenum
			e.nodenum = aasnode.children[1 - side]
			tp += 1
			if tp >= 127 then
				B.botimport.Print(BC.PRT_ERROR, "AAS_TraceBoundingBox: stack overflow\n")
				return trace
			end
			--now put the part near the start of the line on the stack so we will
			--continue with thats part first. This way we'll find the first
			--hit of the bbox
			e = tracestack[tp]
			Q.VectorCopy(cur_start, e.start)
			Q.VectorCopy(cur_mid, e.end_)
			e.planenum = tmpplanenum
			e.nodenum = aasnode.children[side]
			tp += 1
			if tp >= 127 then
				B.botimport.Print(BC.PRT_ERROR, "AAS_TraceBoundingBox: stack overflow\n")
				return trace
			end
		end
	end
end

return nil
