--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_debug.c).

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
-- Luau port of be_aas_debug.c. AAS debug drawing code.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local MAX_DEBUGLINES = 1024
local MAX_DEBUGPOLYGONS = 8192

B.debuglines = B.zeros(MAX_DEBUGLINES)
B.debuglinevisible = B.zeros(MAX_DEBUGLINES)
B.numdebuglines = 0

local debugpolygons = B.zeros(MAX_DEBUGPOLYGONS)

local showreach = SB.aas_reachability_t()
local showindex = 0
local showlastareanum = 0
local showlasttime = 0

function B.AAS_ClearShownPolygons()
	for i = 0, MAX_DEBUGPOLYGONS - 1 do
		if debugpolygons[i] ~= 0 then
			B.botimport.DebugPolygonDelete(debugpolygons[i])
		end
		debugpolygons[i] = 0
	end
end

function B.AAS_ShowPolygon(color, numpoints, points)
	for i = 0, MAX_DEBUGPOLYGONS - 1 do
		if debugpolygons[i] == 0 then
			debugpolygons[i] = B.botimport.DebugPolygonCreate(color, numpoints, points)
			break
		end
	end
end

function B.AAS_ClearShownDebugLines()
	local debuglines = B.debuglines
	local debuglinevisible = B.debuglinevisible
	for i = 0, MAX_DEBUGLINES - 1 do
		if debuglines[i] ~= 0 then
			B.botimport.DebugLineDelete(debuglines[i])
			debuglines[i] = 0
			debuglinevisible[i] = 0
		end
	end
end

function B.AAS_DebugLine(start, end_, color)
	local debuglines = B.debuglines
	local debuglinevisible = B.debuglinevisible
	for line = 0, MAX_DEBUGLINES - 1 do
		if debuglines[line] == 0 then
			debuglines[line] = B.botimport.DebugLineCreate()
			debuglinevisible[line] = 0
			B.numdebuglines = B.numdebuglines + 1
		end
		if debuglinevisible[line] == 0 then
			B.botimport.DebugLineShow(debuglines[line], start, end_, color)
			debuglinevisible[line] = 1
			return
		end
	end
end

function B.AAS_PermanentLine(start, end_, color)
	local line = B.botimport.DebugLineCreate()
	B.botimport.DebugLineShow(line, start, end_, color)
end

function B.AAS_DrawPermanentCross(origin, size, color)
	for i = 0, 2 do
		local start = {[0] = origin[0], origin[1], origin[2]}
		start[i] = start[i] + size
		local end_ = {[0] = origin[0], origin[1], origin[2]}
		end_[i] = end_[i] - size
		B.AAS_DebugLine(start, end_, color)
		local debugline = B.botimport.DebugLineCreate()
		B.botimport.DebugLineShow(debugline, start, end_, color)
	end
end

function B.AAS_DrawPlaneCross(point, normal, dist, type_, color)
	local debuglines = B.debuglines
	local debuglinevisible = B.debuglinevisible
	local lines = {[0] = 0, 0}
	local start1 = {[0] = point[0], point[1], point[2]}
	local end1 = {[0] = point[0], point[1], point[2]}
	local start2 = {[0] = point[0], point[1], point[2]}
	local end2 = {[0] = point[0], point[1], point[2]}

	local n0 = type_ % 3
	local n1 = (type_ + 1) % 3
	local n2 = (type_ + 2) % 3
	start1[n1] = start1[n1] - 6
	start1[n2] = start1[n2] - 6
	end1[n1] = end1[n1] + 6
	end1[n2] = end1[n2] + 6
	start2[n1] = start2[n1] + 6
	start2[n2] = start2[n2] - 6
	end2[n1] = end2[n1] - 6
	end2[n2] = end2[n2] + 6

	start1[n0] = (dist - (start1[n1] * normal[n1] + start1[n2] * normal[n2])) / normal[n0]
	end1[n0] = (dist - (end1[n1] * normal[n1] + end1[n2] * normal[n2])) / normal[n0]
	start2[n0] = (dist - (start2[n1] * normal[n1] + start2[n2] * normal[n2])) / normal[n0]
	end2[n0] = (dist - (end2[n1] * normal[n1] + end2[n2] * normal[n2])) / normal[n0]

	local j, line = 0, 0
	while j < 2 and line < MAX_DEBUGLINES do
		if debuglines[line] == 0 then
			debuglines[line] = B.botimport.DebugLineCreate()
			lines[j] = debuglines[line]
			j = j + 1
			debuglinevisible[line] = 1
			B.numdebuglines = B.numdebuglines + 1
		elseif debuglinevisible[line] == 0 then
			lines[j] = debuglines[line]
			j = j + 1
			debuglinevisible[line] = 1
		end
		line = line + 1
	end
	B.botimport.DebugLineShow(lines[0], start1, end1, color)
	B.botimport.DebugLineShow(lines[1], start2, end2, color)
end

function B.AAS_ShowBoundingBox(origin, mins, maxs)
	local debuglines = B.debuglines
	local debuglinevisible = B.debuglinevisible
	local bboxcorners = {}
	local lines = {[0] = 0, 0, 0}

	bboxcorners[0] = {[0] = origin[0] + maxs[0], origin[1] + maxs[1], origin[2] + maxs[2]}
	bboxcorners[1] = {[0] = origin[0] + mins[0], origin[1] + maxs[1], origin[2] + maxs[2]}
	bboxcorners[2] = {[0] = origin[0] + mins[0], origin[1] + mins[1], origin[2] + maxs[2]}
	bboxcorners[3] = {[0] = origin[0] + maxs[0], origin[1] + mins[1], origin[2] + maxs[2]}
	for i = 0, 3 do
		local c = bboxcorners[i]
		bboxcorners[4 + i] = {[0] = c[0], c[1], origin[2] + mins[2]}
	end
	for i = 0, 3 do
		local j, line = 0, 0
		while j < 3 and line < MAX_DEBUGLINES do
			if debuglines[line] == 0 then
				debuglines[line] = B.botimport.DebugLineCreate()
				lines[j] = debuglines[line]
				j = j + 1
				debuglinevisible[line] = 1
				B.numdebuglines = B.numdebuglines + 1
			elseif debuglinevisible[line] == 0 then
				lines[j] = debuglines[line]
				j = j + 1
				debuglinevisible[line] = 1
			end
			line = line + 1
		end
		B.botimport.DebugLineShow(lines[0], bboxcorners[i], bboxcorners[bit32.band(i + 1, 3)], BC.LINECOLOR_RED)
		B.botimport.DebugLineShow(lines[1], bboxcorners[4 + i], bboxcorners[4 + bit32.band(i + 1, 3)], BC.LINECOLOR_RED)
		B.botimport.DebugLineShow(lines[2], bboxcorners[i], bboxcorners[4 + i], BC.LINECOLOR_RED)
	end
end

function B.AAS_ShowFace(facenum)
	local aasworld = B.aasworld
	local color = BC.LINECOLOR_YELLOW
	if facenum >= aasworld.numfaces then
		B.botimport.Print(BC.PRT_ERROR, "facenum %d out of range\n", facenum)
	end
	local face = aasworld.faces[facenum]
	for i = 0, face.numedges - 1 do
		local edgenum = math.abs(aasworld.edgeindex[face.firstedge + i])
		if edgenum >= aasworld.numedges then
			B.botimport.Print(BC.PRT_ERROR, "edgenum %d out of range\n", edgenum)
		end
		local edge = aasworld.edges[edgenum]
		if color == BC.LINECOLOR_RED then
			color = BC.LINECOLOR_GREEN
		elseif color == BC.LINECOLOR_GREEN then
			color = BC.LINECOLOR_BLUE
		elseif color == BC.LINECOLOR_BLUE then
			color = BC.LINECOLOR_YELLOW
		else
			color = BC.LINECOLOR_RED
		end
		B.AAS_DebugLine(aasworld.vertexes[edge.v[0]], aasworld.vertexes[edge.v[1]], color)
	end
	local plane = aasworld.planes[face.planenum]
	local edgenum = math.abs(aasworld.edgeindex[face.firstedge])
	local edge = aasworld.edges[edgenum]
	local v = aasworld.vertexes[edge.v[0]]
	local start = {[0] = v[0], v[1], v[2]}
	local end_ = {[0] = 0, 0, 0}
	Q.VectorMA(start, 20, plane.normal, end_)
	B.AAS_DebugLine(start, end_, BC.LINECOLOR_RED)
end

function B.AAS_ShowFacePolygon(facenum, color, flip)
	local aasworld = B.aasworld
	local points = {}
	if facenum >= aasworld.numfaces then
		B.botimport.Print(BC.PRT_ERROR, "facenum %d out of range\n", facenum)
	end
	local face = aasworld.faces[facenum]
	local numpoints = 0
	if flip ~= 0 then
		for i = face.numedges - 1, 0, -1 do
			local edgenum = aasworld.edgeindex[face.firstedge + i]
			local edge = aasworld.edges[math.abs(edgenum)]
			local v = aasworld.vertexes[edge.v[if edgenum < 0 then 1 else 0]]
			points[numpoints] = {[0] = v[0], v[1], v[2]}
			numpoints = numpoints + 1
		end
	else
		for i = 0, face.numedges - 1 do
			local edgenum = aasworld.edgeindex[face.firstedge + i]
			local edge = aasworld.edges[math.abs(edgenum)]
			local v = aasworld.vertexes[edge.v[if edgenum < 0 then 1 else 0]]
			points[numpoints] = {[0] = v[0], v[1], v[2]}
			numpoints = numpoints + 1
		end
	end
	B.AAS_ShowPolygon(color, numpoints, points)
end

function B.AAS_ShowArea(areanum, groundfacesonly)
	local aasworld = B.aasworld
	local debuglines = B.debuglines
	local debuglinevisible = B.debuglinevisible
	local areaedges = {}
	local numareaedges = 0
	local color = 0

	if areanum < 0 or areanum >= aasworld.numareas then
		B.botimport.Print(BC.PRT_ERROR, "area %d out of range [0, %d]\n", areanum, aasworld.numareas)
		return
	end
	local area = aasworld.areas[areanum]
	for i = 0, area.numfaces - 1 do
		local facenum = math.abs(aasworld.faceindex[area.firstface + i])
		if facenum >= aasworld.numfaces then
			B.botimport.Print(BC.PRT_ERROR, "facenum %d out of range\n", facenum)
		end
		local face = aasworld.faces[facenum]
		local skip = false
		if groundfacesonly ~= 0 then
			if bit32.band(face.faceflags, bit32.bor(BC.FACE_GROUND, BC.FACE_LADDER)) == 0 then
				skip = true
			end
		end
		if not skip then
			for j = 0, face.numedges - 1 do
				local edgenum = math.abs(aasworld.edgeindex[face.firstedge + j])
				if edgenum >= aasworld.numedges then
					B.botimport.Print(BC.PRT_ERROR, "edgenum %d out of range\n", edgenum)
				end
				local n = 0
				while n < numareaedges do
					if areaedges[n] == edgenum then
						break
					end
					n = n + 1
				end
				if n == numareaedges and numareaedges < MAX_DEBUGLINES then
					areaedges[numareaedges] = edgenum
					numareaedges = numareaedges + 1
				end
			end
		end
	end
	for n = 0, numareaedges - 1 do
		local line = 0
		while line < MAX_DEBUGLINES do
			if debuglines[line] == 0 then
				debuglines[line] = B.botimport.DebugLineCreate()
				debuglinevisible[line] = 0
				B.numdebuglines = B.numdebuglines + 1
			end
			if debuglinevisible[line] == 0 then
				break
			end
			line = line + 1
		end
		if line >= MAX_DEBUGLINES then
			return
		end
		local edge = aasworld.edges[areaedges[n]]
		if color == BC.LINECOLOR_RED then
			color = BC.LINECOLOR_BLUE
		elseif color == BC.LINECOLOR_BLUE then
			color = BC.LINECOLOR_GREEN
		elseif color == BC.LINECOLOR_GREEN then
			color = BC.LINECOLOR_YELLOW
		else
			color = BC.LINECOLOR_RED
		end
		B.botimport.DebugLineShow(debuglines[line], aasworld.vertexes[edge.v[0]], aasworld.vertexes[edge.v[1]], color)
		debuglinevisible[line] = 1
	end
end

function B.AAS_ShowAreaPolygons(areanum, color, groundfacesonly)
	local aasworld = B.aasworld
	if areanum < 0 or areanum >= aasworld.numareas then
		B.botimport.Print(BC.PRT_ERROR, "area %d out of range [0, %d]\n", areanum, aasworld.numareas)
		return
	end
	local area = aasworld.areas[areanum]
	for i = 0, area.numfaces - 1 do
		local facenum = math.abs(aasworld.faceindex[area.firstface + i])
		if facenum >= aasworld.numfaces then
			B.botimport.Print(BC.PRT_ERROR, "facenum %d out of range\n", facenum)
		end
		local face = aasworld.faces[facenum]
		local skip = false
		if groundfacesonly ~= 0 then
			if bit32.band(face.faceflags, bit32.bor(BC.FACE_GROUND, BC.FACE_LADDER)) == 0 then
				skip = true
			end
		end
		if not skip then
			B.AAS_ShowFacePolygon(facenum, color, if face.frontarea ~= areanum then 1 else 0)
		end
	end
end

function B.AAS_DrawCross(origin, size, color)
	for i = 0, 2 do
		local start = {[0] = origin[0], origin[1], origin[2]}
		start[i] = start[i] + size
		local end_ = {[0] = origin[0], origin[1], origin[2]}
		end_[i] = end_[i] - size
		B.AAS_DebugLine(start, end_, color)
	end
end

function B.AAS_PrintTravelType(traveltype)
end

function B.AAS_DrawArrow(start, end_, linecolor, arrowcolor)
	local dir = {[0] = 0, 0, 0}
	local cross = {[0] = 0, 0, 0}
	local p1 = {[0] = 0, 0, 0}
	local p2 = {[0] = 0, 0, 0}
	local up = {[0] = 0, 0, 1}

	Q.VectorSubtract(end_, start, dir)
	Q.VectorNormalizeIoq3(dir)
	local dot = Q.DotProduct(dir, up)
	if dot > 0.99 or dot < -0.99 then
		cross[0], cross[1], cross[2] = 1, 0, 0
	else
		Q.CrossProduct(dir, up, cross)
	end

	Q.VectorMA(end_, -6, dir, p1)
	p2[0], p2[1], p2[2] = p1[0], p1[1], p1[2]
	Q.VectorMA(p1, 6, cross, p1)
	Q.VectorMA(p2, -6, cross, p2)

	B.AAS_DebugLine(start, end_, linecolor)
	B.AAS_DebugLine(p1, end_, arrowcolor)
	B.AAS_DebugLine(p2, end_, arrowcolor)
end

function B.AAS_ShowReachability(reach)
	local dir = {[0] = 0, 0, 0}
	local cmdmove = {[0] = 0, 0, 0}
	local velocity = {[0] = 0, 0, 0}
	local move = SB.aas_clientmove_t()
	local aassettings = B.aassettings
	local ttype = bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK)

	B.AAS_ShowAreaPolygons(reach.areanum, 5, 1)
	B.AAS_DrawArrow(reach.start, reach.end_, BC.LINECOLOR_BLUE, BC.LINECOLOR_YELLOW)
	if ttype == BC.TRAVEL_JUMP or ttype == BC.TRAVEL_WALKOFFLEDGE then
		local _, speed = B.AAS_HorizontalVelocityForJump(aassettings.phys_jumpvel, reach.start, reach.end_)
		Q.VectorSubtract(reach.end_, reach.start, dir)
		dir[2] = 0
		Q.VectorNormalizeIoq3(dir)
		Q.VectorScale(dir, speed, velocity)
		cmdmove[0], cmdmove[1], cmdmove[2] = 0, 0, 0
		cmdmove[2] = aassettings.phys_jumpvel
		B.AAS_PredictClientMovement(move, -1, reach.start, BC.PRESENCE_NORMAL, 1,
			velocity, cmdmove, 3, 30, Q.f(0.1),
			bit32.bor(BC.SE_HITGROUND, BC.SE_ENTERWATER, BC.SE_ENTERSLIME,
				BC.SE_ENTERLAVA, BC.SE_HITGROUNDDAMAGE), 0, 1)
		if ttype == BC.TRAVEL_JUMP then
			B.AAS_JumpReachRunStart(reach, dir)
			B.AAS_DrawCross(dir, 4, BC.LINECOLOR_BLUE)
		end
	elseif ttype == BC.TRAVEL_ROCKETJUMP then
		local zvel = B.AAS_RocketJumpZVelocity(reach.start)
		local _, speed = B.AAS_HorizontalVelocityForJump(zvel, reach.start, reach.end_)
		Q.VectorSubtract(reach.end_, reach.start, dir)
		dir[2] = 0
		Q.VectorNormalizeIoq3(dir)
		Q.VectorScale(dir, speed, cmdmove)
		velocity[0], velocity[1], velocity[2] = 0, 0, zvel
		B.AAS_PredictClientMovement(move, -1, reach.start, BC.PRESENCE_NORMAL, 1,
			velocity, cmdmove, 30, 30, Q.f(0.1),
			bit32.bor(BC.SE_ENTERWATER, BC.SE_ENTERSLIME, BC.SE_ENTERLAVA,
				BC.SE_HITGROUNDDAMAGE, BC.SE_TOUCHJUMPPAD, BC.SE_HITGROUNDAREA), reach.areanum, 1)
	elseif ttype == BC.TRAVEL_JUMPPAD then
		cmdmove[0], cmdmove[1], cmdmove[2] = 0, 0, 0
		Q.VectorSubtract(reach.end_, reach.start, dir)
		dir[2] = 0
		Q.VectorNormalizeIoq3(dir)
		Q.VectorScale(dir, reach.edgenum, velocity)
		velocity[2] = reach.facenum
		B.AAS_PredictClientMovement(move, -1, reach.start, BC.PRESENCE_NORMAL, 1,
			velocity, cmdmove, 30, 30, Q.f(0.1),
			bit32.bor(BC.SE_ENTERWATER, BC.SE_ENTERSLIME, BC.SE_ENTERLAVA,
				BC.SE_HITGROUNDDAMAGE, BC.SE_TOUCHJUMPPAD, BC.SE_HITGROUNDAREA), reach.areanum, 1)
	end
end

function B.AAS_ShowReachableAreas(areanum)
	local aasworld = B.aasworld
	if areanum ~= showlastareanum then
		showindex = 0
		showlastareanum = areanum
	end
	local settings = aasworld.areasettings[areanum]
	if settings.numreachableareas == 0 then
		return
	end
	if showindex >= settings.numreachableareas then
		showindex = 0
	end
	if B.AAS_Time() - showlasttime > 1.5 then
		SB.copy_aas_reachability_t(showreach, aasworld.reachability[settings.firstreachablearea + showindex])
		showindex = showindex + 1
		showlasttime = B.AAS_Time()
		B.AAS_PrintTravelType(bit32.band(showreach.traveltype, BC.TRAVELTYPE_MASK))
		B.botimport.Print(BC.PRT_MESSAGE, "\n")
	end
	B.AAS_ShowReachability(showreach)
end

function B.AAS_FloodAreas_r(areanum, cluster, done)
	local aasworld = B.aasworld
	B.AAS_ShowAreaPolygons(areanum, 1, 1)
	local area = aasworld.areas[areanum]
	local settings = aasworld.areasettings[areanum]
	for i = 0, area.numfaces - 1 do
		local facenum = math.abs(aasworld.faceindex[area.firstface + i])
		local face = aasworld.faces[facenum]
		local nextareanum
		if face.frontarea == areanum then
			nextareanum = face.backarea
		else
			nextareanum = face.frontarea
		end
		if nextareanum ~= 0 and done[nextareanum] == 0 then
			done[nextareanum] = 1
			if bit32.band(aasworld.areasettings[nextareanum].contents, BC.AREACONTENTS_VIEWPORTAL) == 0
				and B.AAS_AreaCluster(nextareanum) == cluster then
				B.AAS_FloodAreas_r(nextareanum, cluster, done)
			end
		end
	end
	for i = 0, settings.numreachableareas - 1 do
		local reach = aasworld.reachability[settings.firstreachablearea + i]
		local nextareanum = reach.areanum
		if nextareanum ~= 0 and done[nextareanum] == 0 then
			done[nextareanum] = 1
			if bit32.band(aasworld.areasettings[nextareanum].contents, BC.AREACONTENTS_VIEWPORTAL) == 0
				and B.AAS_AreaCluster(nextareanum) == cluster then
				B.AAS_FloodAreas_r(nextareanum, cluster, done)
			end
		end
	end
end

function B.AAS_FloodAreas(origin)
	local aasworld = B.aasworld
	local done = B.zeros(aasworld.numareas)
	local areanum = B.AAS_PointAreaNum(origin)
	local cluster = B.AAS_AreaCluster(areanum)
	B.AAS_FloodAreas_r(areanum, cluster, done)
end

return nil
