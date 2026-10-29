--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_sample.c, part 2 of 2).

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
-- Luau port of be_aas_sample.c lines 718-1394 (botlib/be_aas_sample.c, part 2 of 2): area tracing, face tests, entity linking.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local function AAS_OrthogonalToVectors(v1, v2, res)
	res[0] = Q.f(Q.f(v1[1] * v2[2]) - Q.f(v1[2] * v2[1]))
	res[1] = Q.f(Q.f(v1[2] * v2[0]) - Q.f(v1[0] * v2[2]))
	res[2] = Q.f(Q.f(v1[0] * v2[1]) - Q.f(v1[1] * v2[0]))
end

function B.AAS_TraceAreas(start, end_, areas, points, maxareas)
	local aasworld = B.aasworld
	local numareas = 0
	areas[0] = 0
	if aasworld.loaded == 0 then
		return numareas
	end

	local tracestack = {}
	local function entry(i)
		local e = tracestack[i]
		if e == nil then
			e = { start = { [0] = 0, 0, 0 }, end_ = { [0] = 0, 0, 0 }, planenum = 0, nodenum = 0 }
			tracestack[i] = e
		end
		return e
	end
	local cur_start = { [0] = 0, 0, 0 }
	local cur_end = { [0] = 0, 0, 0 }
	local cur_mid = { [0] = 0, 0, 0 }

	local tp = 0
	local e0 = entry(0)
	for k = 0, 2 do
		e0.start[k] = start[k]
		e0.end_[k] = end_[k]
	end
	e0.planenum = 0
	e0.nodenum = 1
	tp = tp + 1

	while true do
		tp = tp - 1
		if tp < 0 then
			return numareas
		end
		local ts = entry(tp)
		local nodenum = ts.nodenum
		if nodenum < 0 then
			areas[numareas] = -nodenum
			if points ~= nil then
				local p = points[numareas]
				p[0] = ts.start[0]
				p[1] = ts.start[1]
				p[2] = ts.start[2]
			end
			numareas = numareas + 1
			if numareas >= maxareas then
				return numareas
			end
			continue
		end
		if nodenum == 0 then
			continue
		end
		local aasnode = aasworld.nodes[nodenum]
		for k = 0, 2 do
			cur_start[k] = ts.start[k]
			cur_end[k] = ts.end_[k]
		end
		local plane = aasworld.planes[aasnode.planenum]

		local front = Q.f(Q.DotProduct(cur_start, plane.normal) - plane.dist)
		local back = Q.f(Q.DotProduct(cur_end, plane.normal) - plane.dist)

		if front > 0 and back > 0 then
			ts.nodenum = aasnode.children[0]
			tp = tp + 1
			if tp >= 127 then
				B.botimport.Print(BC.PRT_ERROR, "AAS_TraceAreas: stack overflow\n")
				return numareas
			end
		elseif front <= 0 and back <= 0 then
			ts.nodenum = aasnode.children[1]
			tp = tp + 1
			if tp >= 127 then
				B.botimport.Print(BC.PRT_ERROR, "AAS_TraceAreas: stack overflow\n")
				return numareas
			end
		else
			local tmpplanenum = ts.planenum
			local frac = Q.f(front / Q.f(front - back))
			if frac < 0 then
				frac = 0
			elseif frac > 1 then
				frac = 1
			end
			cur_mid[0] = Q.f(cur_start[0] + Q.f(Q.f(cur_end[0] - cur_start[0]) * frac))
			cur_mid[1] = Q.f(cur_start[1] + Q.f(Q.f(cur_end[1] - cur_start[1]) * frac))
			cur_mid[2] = Q.f(cur_start[2] + Q.f(Q.f(cur_end[2] - cur_start[2]) * frac))

			local side = if front < 0 then 1 else 0
			ts.start[0] = cur_mid[0]
			ts.start[1] = cur_mid[1]
			ts.start[2] = cur_mid[2]
			ts.planenum = aasnode.planenum
			ts.nodenum = aasnode.children[1 - side]
			tp = tp + 1
			if tp >= 127 then
				B.botimport.Print(BC.PRT_ERROR, "AAS_TraceAreas: stack overflow\n")
				return numareas
			end
			local t2 = entry(tp)
			for k = 0, 2 do
				t2.start[k] = cur_start[k]
				t2.end_[k] = cur_mid[k]
			end
			t2.planenum = tmpplanenum
			t2.nodenum = aasnode.children[side]
			tp = tp + 1
			if tp >= 127 then
				B.botimport.Print(BC.PRT_ERROR, "AAS_TraceAreas: stack overflow\n")
				return numareas
			end
		end
	end
end

function B.AAS_InsideFace(face, pnormal, point, epsilon)
	local aasworld = B.aasworld
	if aasworld.loaded == 0 then
		return false
	end

	local v0 = { [0] = 0, 0, 0 }
	local edgevec = { [0] = 0, 0, 0 }
	local pointvec = { [0] = 0, 0, 0 }
	local sepnormal = { [0] = 0, 0, 0 }

	for i = 0, face.numedges - 1 do
		local edgenum = aasworld.edgeindex[face.firstedge + i]
		local edge = aasworld.edges[math.abs(edgenum)]
		local firstvertex = if edgenum < 0 then 1 else 0
		local a = aasworld.vertexes[edge.v[firstvertex]]
		v0[0] = a[0]
		v0[1] = a[1]
		v0[2] = a[2]
		Q.VectorSubtract(aasworld.vertexes[edge.v[1 - firstvertex]], v0, edgevec)
		Q.VectorSubtract(point, v0, pointvec)
		AAS_OrthogonalToVectors(edgevec, pnormal, sepnormal)
		if Q.DotProduct(pointvec, sepnormal) < -epsilon then
			return false
		end
	end
	return true
end

function B.AAS_PointInsideFace(facenum, point, epsilon)
	local aasworld = B.aasworld
	if aasworld.loaded == 0 then
		return false
	end

	local edgevec = { [0] = 0, 0, 0 }
	local pointvec = { [0] = 0, 0, 0 }
	local sepnormal = { [0] = 0, 0, 0 }

	local face = aasworld.faces[facenum]
	local plane = aasworld.planes[face.planenum]
	for i = 0, face.numedges - 1 do
		local edgenum = aasworld.edgeindex[face.firstedge + i]
		local edge = aasworld.edges[math.abs(edgenum)]
		local firstvertex = if edgenum < 0 then 1 else 0
		local v1 = aasworld.vertexes[edge.v[firstvertex]]
		local v2 = aasworld.vertexes[edge.v[1 - firstvertex]]
		Q.VectorSubtract(v2, v1, edgevec)
		Q.VectorSubtract(point, v1, pointvec)
		Q.CrossProduct(edgevec, plane.normal, sepnormal)
		if Q.DotProduct(pointvec, sepnormal) < -epsilon then
			return false
		end
	end
	return true
end

function B.AAS_AreaGroundFace(areanum, point)
	local aasworld = B.aasworld
	if aasworld.loaded == 0 then
		return nil
	end

	local up = { [0] = 0, 0, 1 }
	local normal = { [0] = 0, 0, 0 }
	local area = aasworld.areas[areanum]
	for i = 0, area.numfaces - 1 do
		local facenum = aasworld.faceindex[area.firstface + i]
		local face = aasworld.faces[math.abs(facenum)]
		if bit32.band(face.faceflags, BC.FACE_GROUND) ~= 0 then
			if aasworld.planes[face.planenum].normal[2] < 0 then
				normal[0] = -up[0]
				normal[1] = -up[1]
				normal[2] = -up[2]
			else
				normal[0] = up[0]
				normal[1] = up[1]
				normal[2] = up[2]
			end
			if B.AAS_InsideFace(face, normal, point, Q.f(0.01)) then
				return face
			end
		end
	end
	return nil
end

function B.AAS_FacePlane(facenum, normal)
	local aasworld = B.aasworld
	local plane = aasworld.planes[aasworld.faces[facenum].planenum]
	normal[0] = plane.normal[0]
	normal[1] = plane.normal[1]
	normal[2] = plane.normal[2]
	return plane.dist
end

function B.AAS_TraceEndFace(trace)
	local aasworld = B.aasworld
	local firstface = nil

	if aasworld.loaded == 0 then
		return nil
	end

	if trace.startsolid then
		return nil
	end
	local area = aasworld.areas[trace.lastarea]
	for i = 0, area.numfaces - 1 do
		local facenum = aasworld.faceindex[area.firstface + i]
		local face = aasworld.faces[math.abs(facenum)]
		if bit32.band(face.planenum, bit32.bnot(1)) == bit32.band(trace.planenum, bit32.bnot(1)) then
			if B.AAS_InsideFace(face, aasworld.planes[face.planenum].normal, trace.endpos, Q.f(0.01)) then
				return face
			end
		end
	end
	return firstface
end

function B.AAS_BoxOnPlaneSide2(absmins, absmaxs, p)
	local corners = { [0] = { [0] = 0, 0, 0 }, { [0] = 0, 0, 0 } }

	for i = 0, 2 do
		if p.normal[i] < 0 then
			corners[0][i] = absmins[i]
			corners[1][i] = absmaxs[i]
		else
			corners[1][i] = absmins[i]
			corners[0][i] = absmaxs[i]
		end
	end
	local dist1 = Q.f(Q.DotProduct(p.normal, corners[0]) - p.dist)
	local dist2 = Q.f(Q.DotProduct(p.normal, corners[1]) - p.dist)
	local sides = 0
	if dist1 >= 0 then
		sides = 1
	end
	if dist2 < 0 then
		sides = bit32.bor(sides, 2)
	end

	return sides
end

function B.AAS_UnlinkFromAreas(areas)
	local aasworld = B.aasworld
	local link = areas
	while link ~= nil do
		local nextlink = link.next_area
		if link.prev_ent ~= nil then
			link.prev_ent.next_ent = link.next_ent
		else
			aasworld.arealinkedentities[link.areanum] = link.next_ent
		end
		if link.next_ent ~= nil then
			link.next_ent.prev_ent = link.prev_ent
		end
		B.AAS_DeAllocAASLink(link)
		link = nextlink
	end
end

function B.AAS_AASLinkEntity(absmins, absmaxs, entnum)
	local aasworld = B.aasworld
	if aasworld.loaded == 0 then
		B.botimport.Print(BC.PRT_ERROR, "AAS_LinkEntity: aas not loaded\n")
		return nil
	end

	local areas = nil
	local linkstack = {}
	local lp = 0
	linkstack[0] = 1
	lp = lp + 1

	while true do
		lp = lp - 1
		if lp < 0 then
			break
		end
		local nodenum = linkstack[lp]
		if nodenum < 0 then
			local link = aasworld.arealinkedentities[-nodenum]
			while link ~= nil do
				if link.entnum == entnum then
					break
				end
				link = link.next_ent
			end
			if link ~= nil then
				continue
			end
			link = B.AAS_AllocAASLink()
			if link == nil then
				return areas
			end
			link.entnum = entnum
			link.areanum = -nodenum
			link.prev_area = nil
			link.next_area = areas
			if areas ~= nil then
				areas.prev_area = link
			end
			areas = link
			link.prev_ent = nil
			link.next_ent = aasworld.arealinkedentities[-nodenum]
			if aasworld.arealinkedentities[-nodenum] ~= nil then
				aasworld.arealinkedentities[-nodenum].prev_ent = link
			end
			aasworld.arealinkedentities[-nodenum] = link
			continue
		end
		if nodenum == 0 then
			continue
		end
		local aasnode = aasworld.nodes[nodenum]
		local plane = aasworld.planes[aasnode.planenum]
		local side = B.AAS_BoxOnPlaneSide2(absmins, absmaxs, plane)
		if bit32.band(side, 1) ~= 0 then
			linkstack[lp] = aasnode.children[0]
			lp = lp + 1
		end
		if lp >= 127 then
			B.botimport.Print(BC.PRT_ERROR, "AAS_LinkEntity: stack overflow\n")
			break
		end
		if bit32.band(side, 2) ~= 0 then
			linkstack[lp] = aasnode.children[1]
			lp = lp + 1
		end
		if lp >= 127 then
			B.botimport.Print(BC.PRT_ERROR, "AAS_LinkEntity: stack overflow\n")
			break
		end
	end
	return areas
end

function B.AAS_LinkEntityClientBBox(absmins, absmaxs, entnum, presencetype)
	local mins = { [0] = 0, 0, 0 }
	local maxs = { [0] = 0, 0, 0 }
	local newabsmins = { [0] = 0, 0, 0 }
	local newabsmaxs = { [0] = 0, 0, 0 }

	B.AAS_PresenceTypeBoundingBox(presencetype, mins, maxs)
	Q.VectorSubtract(absmins, maxs, newabsmins)
	Q.VectorSubtract(absmaxs, mins, newabsmaxs)
	return B.AAS_AASLinkEntity(newabsmins, newabsmaxs, entnum)
end

function B.AAS_BBoxAreas(absmins, absmaxs, areas, maxareas)
	local linkedareas = B.AAS_AASLinkEntity(absmins, absmaxs, -1)
	local num = 0
	local link = linkedareas
	while link ~= nil do
		areas[num] = link.areanum
		num = num + 1
		if num >= maxareas then
			break
		end
		link = link.next_area
	end
	B.AAS_UnlinkFromAreas(linkedareas)
	return num
end

function B.AAS_AreaInfo(areanum, info)
	local aasworld = B.aasworld
	if info == nil then
		return 0
	end
	if areanum <= 0 or areanum >= aasworld.numareas then
		B.botimport.Print(BC.PRT_ERROR, "AAS_AreaInfo: areanum %d out of range\n", areanum)
		return 0
	end
	local settings = aasworld.areasettings[areanum]
	info.cluster = settings.cluster
	info.contents = settings.contents
	info.flags = settings.areaflags
	info.presencetype = settings.presencetype
	local area = aasworld.areas[areanum]
	for k = 0, 2 do
		info.mins[k] = area.mins[k]
		info.maxs[k] = area.maxs[k]
		info.center[k] = area.center[k]
	end
	return --[[sizeof(aas_areainfo_t)]] 52
end

function B.AAS_PlaneFromNum(planenum)
	local aasworld = B.aasworld
	if aasworld.loaded == 0 then
		return nil
	end

	return aasworld.planes[planenum]
end

return nil
