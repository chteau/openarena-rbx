--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_routealt.c).

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
-- Luau port of be_aas_routealt.c. Finds alternative route goals between a start and a goal area.

local B = require("./b_local")
local BC = require("./consts")
local Q = require("../../../shared/q_math")

-- midrangearea_t: { valid, starttime, goaltime }
local midrangeareas: { [number]: { valid: boolean, starttime: number, goaltime: number } }? = nil
local clusterareas: { [number]: number }? = nil
local numclusterareas = 0

local function AAS_AltRoutingFloodCluster_r(areanum: number)
	local aasworld = B.aasworld
	local mid = midrangeareas :: any
	local cl = clusterareas :: any

	--add the current area to the areas of the current cluster
	cl[numclusterareas] = areanum
	numclusterareas = numclusterareas + 1
	--remove the area from the mid range areas
	mid[areanum].valid = false
	--flood to other areas through the faces of this area
	local area = aasworld.areas[areanum]
	local i = 0
	while i < area.numfaces do
		local face = aasworld.faces[math.abs(aasworld.faceindex[area.firstface + i])]
		local otherareanum
		--get the area at the other side of the face
		if face.frontarea == areanum then
			otherareanum = face.backarea
		else
			otherareanum = face.frontarea
		end
		--if there is an area at the other side of this face
		--if the other area is not a midrange area
		if otherareanum ~= 0 and mid[otherareanum].valid then
			AAS_AltRoutingFloodCluster_r(otherareanum)
		end
		i = i + 1
	end
end

function B.AAS_AltRoutingFloodCluster_r(areanum: number)
	AAS_AltRoutingFloodCluster_r(areanum)
end

function B.AAS_AlternativeRouteGoals(start, startareanum, goal, goalareanum, travelflags, altroutegoals, maxaltroutegoals, type_): number
	local aasworld = B.aasworld
	local mid = midrangeareas :: any
	local cl = clusterareas :: any

	if startareanum == 0 or goalareanum == 0 then
		return 0
	end
	--travel time towards the goal area
	local goaltraveltime = B.AAS_AreaTravelTimeToGoalArea(startareanum, start, goalareanum, travelflags)
	--clear the midrange areas
	for k = 0, aasworld.numareas - 1 do
		local m = mid[k]
		m.valid = false
		m.starttime = 0
		m.goaltime = 0
	end
	local numaltroutegoals = 0
	local nummidrangeareas = 0

	for i = 1, aasworld.numareas - 1 do
		if bit32.band(type_, BC.ALTROUTEGOAL_ALL) == 0 then
			local clusterportal = bit32.band(type_, BC.ALTROUTEGOAL_CLUSTERPORTALS) ~= 0
				and bit32.band(aasworld.areasettings[i].contents, BC.AREACONTENTS_CLUSTERPORTAL) ~= 0
			if not clusterportal then
				local viewportal = bit32.band(type_, BC.ALTROUTEGOAL_VIEWPORTALS) ~= 0
					and bit32.band(aasworld.areasettings[i].contents, BC.AREACONTENTS_VIEWPORTAL) ~= 0
				if not viewportal then
					continue
				end
			end
		end
		--if the area has no reachabilities
		if B.AAS_AreaReachability(i) == 0 then continue end
		--tavel time from the area to the start area
		local starttime = B.AAS_AreaTravelTimeToGoalArea(startareanum, start, i, travelflags)
		if starttime == 0 then continue end
		--if the travel time from the start to the area is greater than the shortest goal travel time
		if starttime > Q.f(Q.f(1.1) * goaltraveltime) then continue end
		--travel time from the area to the goal area
		local goaltime = B.AAS_AreaTravelTimeToGoalArea(i, nil, goalareanum, travelflags)
		if goaltime == 0 then continue end
		--if the travel time from the area to the goal is greater than the shortest goal travel time
		if goaltime > Q.f(Q.f(0.8) * goaltraveltime) then continue end
		--this is a mid range area
		mid[i].valid = true
		mid[i].starttime = bit32.band(starttime, 0xFFFF)
		mid[i].goaltime = bit32.band(goaltime, 0xFFFF)
		B.Log_Write("%d midrange area %d", nummidrangeareas, i)
		nummidrangeareas = nummidrangeareas + 1
	end

	for i = 1, aasworld.numareas - 1 do
		if not mid[i].valid then continue end
		--get the areas in one cluster
		numclusterareas = 0
		AAS_AltRoutingFloodCluster_r(i)
		--now we've got a cluster with areas through which an alternative route could go
		--get the 'center' of the cluster
		local midpt = { [0] = 0, 0, 0 }
		for j = 0, numclusterareas - 1 do
			Q.VectorAdd(midpt, aasworld.areas[cl[j]].center, midpt)
		end
		Q.VectorScale(midpt, Q.f(1.0 / numclusterareas), midpt)
		--get the area closest to the center of the cluster
		local bestdist = 999999
		local bestareanum = 0
		local dir = { [0] = 0, 0, 0 }
		for j = 0, numclusterareas - 1 do
			Q.VectorSubtract(midpt, aasworld.areas[cl[j]].center, dir)
			local dist = Q.VectorLength(dir)
			if dist < bestdist then
				bestdist = dist
				bestareanum = cl[j]
			end
		end
		--now we've got an area for an alternative route
		--FIXME: add alternative goal origin
		local g = altroutegoals[numaltroutegoals]
		Q.VectorCopy(aasworld.areas[bestareanum].center, g.origin)
		g.areanum = bestareanum
		g.starttraveltime = mid[bestareanum].starttime
		g.goaltraveltime = mid[bestareanum].goaltime
		g.extratraveltime = (mid[bestareanum].starttime + mid[bestareanum].goaltime) - goaltraveltime
		numaltroutegoals = numaltroutegoals + 1
		--don't return more than the maximum alternative route goals
		if numaltroutegoals >= maxaltroutegoals then break end
	end
	return numaltroutegoals
end

function B.AAS_InitAlternativeRouting()
	local aasworld = B.aasworld
	local mid = {}
	for i = 0, aasworld.numareas - 1 do
		mid[i] = { valid = false, starttime = 0, goaltime = 0 }
	end
	midrangeareas = mid
	clusterareas = B.zeros(aasworld.numareas)
end

function B.AAS_ShutdownAlternativeRouting()
	midrangeareas = nil
	clusterareas = nil
	numclusterareas = 0
end

return nil
