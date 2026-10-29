--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_route.c, part 3 of 3).

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
-- Luau port of be_aas_route.c lines 1443-2218: portal routing caches, route queries, route prediction, hide areas.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local SF = B.FileStatics("be_aas_route")

local hidetraveltimes: { [number]: number }? = nil

function B.AAS_UpdatePortalRoutingCache(portalcache)
	local aasworld = B.aasworld

	local curupdate = aasworld.portalupdate[aasworld.numportals]
	curupdate.cluster = portalcache.cluster
	curupdate.areanum = portalcache.areanum
	curupdate.tmptraveltime = Q.trunc(portalcache.starttraveltime)
	local clusternum = aasworld.areasettings[portalcache.areanum].cluster
	if clusternum < 0 then
		portalcache.traveltimes[-clusternum] = Q.trunc(portalcache.starttraveltime)
	end
	curupdate.next = nil
	curupdate.prev = nil
	local updateliststart = curupdate
	local updatelistend = curupdate
	while updateliststart ~= nil do
		curupdate = updateliststart
		if curupdate.next ~= nil then
			curupdate.next.prev = nil
		else
			updatelistend = nil
		end
		updateliststart = curupdate.next
		curupdate.inlist = false
		local cluster = aasworld.clusters[curupdate.cluster]
		local cache = B.AAS_GetAreaRoutingCache(curupdate.cluster, curupdate.areanum, portalcache.travelflags)
		for i = 0, cluster.numportals - 1 do
			local portalnum = aasworld.portalindex[cluster.firstportal + i]
			local portal = aasworld.portals[portalnum]
			if portal.areanum == curupdate.areanum then
				continue
			end
			local clusterareanum = SF.AAS_ClusterAreaNum(curupdate.cluster, portal.areanum)
			if clusterareanum >= cluster.numreachabilityareas then
				continue
			end
			local t = cache.traveltimes[clusterareanum]
			if t == 0 then
				continue
			end
			t = bit32.band(t + curupdate.tmptraveltime, 0xFFFF)
			if portalcache.traveltimes[portalnum] == 0 or portalcache.traveltimes[portalnum] > t then
				portalcache.traveltimes[portalnum] = t
				local nextupdate = aasworld.portalupdate[portalnum]
				if portal.frontcluster == curupdate.cluster then
					nextupdate.cluster = portal.backcluster
				else
					nextupdate.cluster = portal.frontcluster
				end
				nextupdate.areanum = portal.areanum
				nextupdate.tmptraveltime = bit32.band(t + aasworld.portalmaxtraveltimes[portalnum], 0xFFFF)
				if not nextupdate.inlist then
					nextupdate.next = nil
					nextupdate.prev = updatelistend
					if updatelistend ~= nil then
						updatelistend.next = nextupdate
					else
						updateliststart = nextupdate
					end
					updatelistend = nextupdate
					nextupdate.inlist = true
				end
			end
		end
	end
end

function B.AAS_GetPortalRoutingCache(clusternum, areanum, travelflags)
	local aasworld = B.aasworld

	local cache = aasworld.portalcache[areanum]
	while cache ~= nil do
		if cache.travelflags == travelflags then
			break
		end
		cache = cache.next
	end
	if cache == nil then
		cache = B.AAS_AllocRoutingCache(aasworld.numportals)
		cache.cluster = clusternum
		cache.areanum = areanum
		Q.VectorCopy(aasworld.areas[areanum].center, cache.origin)
		cache.starttraveltime = 1
		cache.travelflags = travelflags
		cache.prev = nil
		cache.next = aasworld.portalcache[areanum]
		if aasworld.portalcache[areanum] ~= nil then
			aasworld.portalcache[areanum].prev = cache
		end
		aasworld.portalcache[areanum] = cache
		B.AAS_UpdatePortalRoutingCache(cache)
	else
		B.AAS_UnlinkCache(cache)
	end
	cache.time = SF.AAS_RoutingTime()
	cache.type = BC.CACHETYPE_PORTAL
	B.AAS_LinkCache(cache)
	return cache
end

function B.AAS_AreaRouteToGoalArea(areanum, origin, goalareanum, travelflags)
	local aasworld = B.aasworld
	local traveltime = 0
	local reachnum = 0

	if aasworld.initialized == 0 then
		return 0, traveltime, reachnum
	end

	if areanum == goalareanum then
		return 1, 1, 0
	end
	if areanum <= 0 or areanum >= aasworld.numareas then
		if B.botDeveloper ~= 0 then
			B.botimport.Print(BC.PRT_ERROR, "AAS_AreaTravelTimeToGoalArea: areanum %d out of range\n", areanum)
		end
		return 0, traveltime, reachnum
	end
	if goalareanum <= 0 or goalareanum >= aasworld.numareas then
		if B.botDeveloper ~= 0 then
			B.botimport.Print(BC.PRT_ERROR, "AAS_AreaTravelTimeToGoalArea: goalareanum %d out of range\n", goalareanum)
		end
		return 0, traveltime, reachnum
	end
	if aasworld.areasettings[areanum].numreachableareas == 0 or aasworld.areasettings[goalareanum].numreachableareas == 0 then
		return 0, traveltime, reachnum
	end
	while B.botimport.AvailableMemory() < 1 * 1024 * 1024 do
		if B.AAS_FreeOldestCache() == 0 then
			break
		end
	end
	if B.AAS_AreaDoNotEnter(areanum) ~= 0 or B.AAS_AreaDoNotEnter(goalareanum) ~= 0 then
		travelflags = bit32.bor(travelflags, BC.TFL_DONOTENTER)
	end
	local clusternum = aasworld.areasettings[areanum].cluster
	local goalclusternum = aasworld.areasettings[goalareanum].cluster
	if clusternum < 0 and goalclusternum > 0 then
		local portal = aasworld.portals[-clusternum]
		if portal.frontcluster == goalclusternum or portal.backcluster == goalclusternum then
			clusternum = goalclusternum
		end
	elseif clusternum > 0 and goalclusternum < 0 then
		local portal = aasworld.portals[-goalclusternum]
		if portal.frontcluster == clusternum or portal.backcluster == clusternum then
			goalclusternum = clusternum
		end
	end
	if clusternum > 0 and goalclusternum > 0 and clusternum == goalclusternum then
		local areacache = B.AAS_GetAreaRoutingCache(clusternum, goalareanum, travelflags)
		local clusterareanum = SF.AAS_ClusterAreaNum(clusternum, areanum)
		local cluster = aasworld.clusters[clusternum]
		if clusterareanum >= cluster.numreachabilityareas then
			return 0, traveltime, reachnum
		end
		if areacache.traveltimes[clusterareanum] ~= 0 then
			reachnum = aasworld.areasettings[areanum].firstreachablearea + areacache.reachabilities[clusterareanum]
			if origin == nil then
				traveltime = areacache.traveltimes[clusterareanum]
				return 1, traveltime, reachnum
			end
			local reach = aasworld.reachability[reachnum]
			traveltime = areacache.traveltimes[clusterareanum] + B.AAS_AreaTravelTime(areanum, origin, reach.start)
			return 1, traveltime, reachnum
		end
	end
	clusternum = aasworld.areasettings[areanum].cluster
	goalclusternum = aasworld.areasettings[goalareanum].cluster
	if goalclusternum < 0 then
		local portal = aasworld.portals[-goalclusternum]
		goalclusternum = portal.frontcluster
	end
	local portalcache = B.AAS_GetPortalRoutingCache(goalclusternum, goalareanum, travelflags)
	if clusternum < 0 then
		traveltime = portalcache.traveltimes[-clusternum]
		reachnum = aasworld.areasettings[areanum].firstreachablearea + portalcache.reachabilities[-clusternum]
		return 1, traveltime, reachnum
	end
	local besttime = 0
	local bestreachnum = -1
	local cluster = aasworld.clusters[clusternum]
	for i = 0, cluster.numportals - 1 do
		local portalnum = aasworld.portalindex[cluster.firstportal + i]
		if portalcache.traveltimes[portalnum] == 0 then
			continue
		end
		local portal = aasworld.portals[portalnum]
		local areacache = B.AAS_GetAreaRoutingCache(clusternum, portal.areanum, travelflags)
		local clusterareanum = SF.AAS_ClusterAreaNum(clusternum, areanum)
		if clusterareanum >= cluster.numreachabilityareas then
			continue
		end
		if areacache.traveltimes[clusterareanum] == 0 then
			continue
		end
		local t = bit32.band(portalcache.traveltimes[portalnum] + areacache.traveltimes[clusterareanum], 0xFFFF)
		t = bit32.band(t + aasworld.portalmaxtraveltimes[portalnum], 0xFFFF)
		if origin ~= nil then
			reachnum = aasworld.areasettings[areanum].firstreachablearea + areacache.reachabilities[clusterareanum]
			local reach = aasworld.reachability[reachnum]
			t = bit32.band(t + B.AAS_AreaTravelTime(areanum, origin, reach.start), 0xFFFF)
		end
		if besttime == 0 or t < besttime then
			bestreachnum = reachnum
			besttime = t
		end
	end
	if bestreachnum < 0 then
		return 0, traveltime, reachnum
	end
	reachnum = bestreachnum
	traveltime = besttime
	return 1, traveltime, reachnum
end

function B.AAS_AreaTravelTimeToGoalArea(areanum, origin, goalareanum, travelflags)
	local ret, traveltime = B.AAS_AreaRouteToGoalArea(areanum, origin, goalareanum, travelflags)
	if ret ~= 0 then
		return traveltime
	end
	return 0
end

function B.AAS_AreaReachabilityToGoalArea(areanum, origin, goalareanum, travelflags)
	local ret, _, reachnum = B.AAS_AreaRouteToGoalArea(areanum, origin, goalareanum, travelflags)
	if ret ~= 0 then
		return reachnum
	end
	return 0
end

function B.AAS_PredictRoute(route, areanum, origin, goalareanum, travelflags, maxareas, maxtime, stopevent, stopcontents, stoptfl, stopareanum)
	local aasworld = B.aasworld

	route.stopevent = BC.RSE_NONE
	route.endarea = goalareanum
	route.endcontents = 0
	route.endtravelflags = 0
	Q.VectorCopy(origin, route.endpos)
	route.time = 0

	local curareanum = areanum
	local curorigin = { [0] = 0, 0, 0 }
	Q.VectorCopy(origin, curorigin)

	local i = 0
	while curareanum ~= goalareanum and (maxareas == 0 or i < maxareas) and i < aasworld.numareas do
		local reachnum = B.AAS_AreaReachabilityToGoalArea(curareanum, curorigin, goalareanum, travelflags)
		if reachnum == 0 then
			route.stopevent = BC.RSE_NOROUTE
			return 0
		end
		local reach = aasworld.reachability[reachnum]
		if bit32.band(stopevent, BC.RSE_USETRAVELTYPE) ~= 0 then
			if bit32.band(SF.AAS_TravelFlagForType_inline(reach.traveltype), stoptfl) ~= 0 then
				route.stopevent = BC.RSE_USETRAVELTYPE
				route.endarea = curareanum
				route.endcontents = aasworld.areasettings[curareanum].contents
				route.endtravelflags = SF.AAS_TravelFlagForType_inline(reach.traveltype)
				Q.VectorCopy(reach.start, route.endpos)
				return 1
			end
			if bit32.band(SF.AAS_AreaContentsTravelFlags_inline(reach.areanum), stoptfl) ~= 0 then
				route.stopevent = BC.RSE_USETRAVELTYPE
				route.endarea = reach.areanum
				route.endcontents = aasworld.areasettings[reach.areanum].contents
				route.endtravelflags = SF.AAS_AreaContentsTravelFlags_inline(reach.areanum)
				Q.VectorCopy(reach.end_, route.endpos)
				route.time = route.time + B.AAS_AreaTravelTime(areanum, origin, reach.start)
				route.time = route.time + reach.traveltime
				return 1
			end
		end
		local reachareas = aasworld.reachabilityareas[reachnum]
		for j = 0, reachareas.numareas do
			local testareanum
			if j >= reachareas.numareas then
				testareanum = reach.areanum
			else
				testareanum = aasworld.reachabilityareaindex[reachareas.firstarea + j]
			end
			if bit32.band(stopevent, BC.RSE_ENTERCONTENTS) ~= 0 then
				if bit32.band(aasworld.areasettings[testareanum].contents, stopcontents) ~= 0 then
					route.stopevent = BC.RSE_ENTERCONTENTS
					route.endarea = testareanum
					route.endcontents = aasworld.areasettings[testareanum].contents
					Q.VectorCopy(reach.end_, route.endpos)
					route.time = route.time + B.AAS_AreaTravelTime(areanum, origin, reach.start)
					route.time = route.time + reach.traveltime
					return 1
				end
			end
			if bit32.band(stopevent, BC.RSE_ENTERAREA) ~= 0 then
				if testareanum == stopareanum then
					route.stopevent = BC.RSE_ENTERAREA
					route.endarea = testareanum
					route.endcontents = aasworld.areasettings[testareanum].contents
					Q.VectorCopy(reach.start, route.endpos)
					return 1
				end
			end
		end

		route.time = route.time + B.AAS_AreaTravelTime(areanum, origin, reach.start)
		route.time = route.time + reach.traveltime
		route.endarea = reach.areanum
		route.endcontents = aasworld.areasettings[reach.areanum].contents
		route.endtravelflags = SF.AAS_TravelFlagForType_inline(reach.traveltype)
		Q.VectorCopy(reach.end_, route.endpos)
		curareanum = reach.areanum
		Q.VectorCopy(reach.end_, curorigin)
		if maxtime ~= 0 and route.time > maxtime then
			break
		end
		i = i + 1
	end
	if curareanum ~= goalareanum then
		return 0
	end
	return 1
end

function B.AAS_BridgeWalkable(areanum)
	return 0
end

function B.AAS_ReachabilityFromNum(num, reach)
	local aasworld = B.aasworld
	if aasworld.initialized == 0 then
		SB.copy_aas_reachability_t(reach, SB.aas_reachability_t())
		return
	end
	if num < 0 or num >= aasworld.reachabilitysize then
		SB.copy_aas_reachability_t(reach, SB.aas_reachability_t())
		return
	end
	SB.copy_aas_reachability_t(reach, aasworld.reachability[num])
end

function B.AAS_NextAreaReachability(areanum, reachnum)
	local aasworld = B.aasworld
	if aasworld.initialized == 0 then
		return 0
	end

	if areanum <= 0 or areanum >= aasworld.numareas then
		B.botimport.Print(BC.PRT_ERROR, "AAS_NextAreaReachability: areanum %d out of range\n", areanum)
		return 0
	end

	local settings = aasworld.areasettings[areanum]
	if reachnum == 0 then
		return settings.firstreachablearea
	end
	if reachnum < settings.firstreachablearea then
		B.botimport.Print(BC.PRT_FATAL, "AAS_NextAreaReachability: reachnum < settings->firstreachableara")
		return 0
	end
	reachnum = reachnum + 1
	if reachnum >= settings.firstreachablearea + settings.numreachableareas then
		return 0
	end
	return reachnum
end

function B.AAS_NextModelReachability(num, modelnum)
	local aasworld = B.aasworld
	if num <= 0 then
		num = 1
	elseif num >= aasworld.reachabilitysize then
		return 0
	else
		num = num + 1
	end
	for i = num, aasworld.reachabilitysize - 1 do
		local reach = aasworld.reachability[i]
		local tt = bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK)
		if tt == BC.TRAVEL_ELEVATOR then
			if reach.facenum == modelnum then
				return i
			end
		elseif tt == BC.TRAVEL_FUNCBOB then
			if bit32.band(reach.facenum, 0x0000FFFF) == modelnum then
				return i
			end
		end
	end
	return 0
end

function B.AAS_RandomGoalArea(areanum, travelflags, goalareanum, goalorigin)
	local aasworld = B.aasworld
	local start = { [0] = 0, 0, 0 }
	local end_ = { [0] = 0, 0, 0 }

	if B.AAS_AreaReachability(areanum) == 0 then
		return 0, goalareanum
	end
	local n = Q.trunc(aasworld.numareas * Q.random())
	for _ = 0, aasworld.numareas - 1 do
		if n <= 0 then
			n = 1
		end
		if n >= aasworld.numareas then
			n = 1
		end
		if B.AAS_AreaReachability(n) ~= 0 then
			local t = B.AAS_AreaTravelTimeToGoalArea(areanum, aasworld.areas[areanum].center, n, travelflags)
			if t > 0 then
				if B.AAS_AreaSwim(n) ~= 0 then
					goalareanum = n
					Q.VectorCopy(aasworld.areas[n].center, goalorigin)
					return 1, goalareanum
				end
				Q.VectorCopy(aasworld.areas[n].center, start)
				if B.AAS_PointAreaNum(start) == 0 then
					B.Log_Write("area %d center %f %f %f in solid?", n, start[0], start[1], start[2])
				end
				Q.VectorCopy(start, end_)
				end_[2] = Q.f(end_[2] - 300)
				local trace = B.AAS_TraceClientBBox(start, end_, BC.PRESENCE_CROUCH, -1)
				if not trace.startsolid and trace.fraction < 1 and B.AAS_PointAreaNum(trace.endpos) == n then
					if B.AAS_AreaGroundFaceArea(n) > 300 then
						goalareanum = n
						Q.VectorCopy(trace.endpos, goalorigin)
						return 1, goalareanum
					end
				end
			end
		end
		n = n + 1
	end
	return 0, goalareanum
end

function B.AAS_AreaVisible(srcarea, destarea)
	return 0
end

function B.DistancePointToLine(v1, v2, point)
	local vec = { [0] = 0, 0, 0 }
	local p2 = { [0] = 0, 0, 0 }

	B.AAS_ProjectPointOntoVector(point, v1, v2, p2)
	Q.VectorSubtract(point, p2, vec)
	return Q.VectorLength(vec)
end

function B.AAS_NearestHideArea(srcnum, origin, areanum, enemynum, enemyorigin, enemyareanum, travelflags)
	local aasworld = B.aasworld
	local v1 = { [0] = 0, 0, 0 }
	local v2 = { [0] = 0, 0, 0 }
	local p = { [0] = 0, 0, 0 }

	local hide = hidetraveltimes
	if hide == nil then
		hide = B.zeros(aasworld.numareas)
		hidetraveltimes = hide
	else
		for k = 0, aasworld.numareas - 1 do
			hide[k] = 0
		end
	end
	local besttraveltime = 0
	local bestarea = 0
	local startVisible = true
	local badtravelflags = bit32.bnot(travelflags)

	local curupdate = aasworld.areaupdate[areanum]
	curupdate.areanum = areanum
	Q.VectorCopy(origin, curupdate.start)
	curupdate.areatraveltimes = aasworld.areatraveltimes[areanum][0]
	curupdate.tmptraveltime = 0
	curupdate.next = nil
	curupdate.prev = nil
	local updateliststart = curupdate
	local updatelistend = curupdate
	while updateliststart ~= nil do
		curupdate = updateliststart
		if curupdate.next ~= nil then
			curupdate.next.prev = nil
		else
			updatelistend = nil
		end
		updateliststart = curupdate.next
		curupdate.inlist = false
		local numreach = aasworld.areasettings[curupdate.areanum].numreachableareas
		local firstreach = aasworld.areasettings[curupdate.areanum].firstreachablearea
		for i = 0, numreach - 1 do
			local reach = aasworld.reachability[firstreach + i]
			if bit32.band(SF.AAS_TravelFlagForType_inline(reach.traveltype), badtravelflags) ~= 0 then
				continue
			end
			if bit32.band(SF.AAS_AreaContentsTravelFlags_inline(reach.areanum), badtravelflags) ~= 0 then
				continue
			end
			local nextareanum = reach.areanum
			if nextareanum == enemyareanum then
				continue
			end
			local t = bit32.band(
				curupdate.tmptraveltime + B.AAS_AreaTravelTime(curupdate.areanum, curupdate.start, reach.start) + reach.traveltime,
				0xFFFF
			)

			B.AAS_ProjectPointOntoVector(enemyorigin, curupdate.start, reach.end_, p)
			local j = 0
			while j < 3 do
				if
					(p[j] > curupdate.start[j] and p[j] > reach.end_[j])
					or (p[j] < curupdate.start[j] and p[j] < reach.end_[j])
				then
					break
				end
				j = j + 1
			end
			if j < 3 then
				Q.VectorSubtract(enemyorigin, reach.end_, v2)
			else
				Q.VectorSubtract(enemyorigin, p, v2)
			end
			local dist2 = Q.VectorLength(v2)
			if dist2 < 40 then
				continue
			end
			Q.VectorSubtract(enemyorigin, curupdate.start, v1)
			local dist1 = Q.VectorLength(v1)
			if dist2 < dist1 then
				t = bit32.band(Q.trunc(Q.f(t + Q.f(Q.f(dist1 - dist2) * 10))), 0xFFFF)
			end
			if not startVisible and B.AAS_AreaVisible(enemyareanum, nextareanum) ~= 0 then
				continue
			end
			if besttraveltime ~= 0 and t >= besttraveltime then
				continue
			end
			if hide[nextareanum] == 0 or hide[nextareanum] > t then
				if B.AAS_AreaVisible(enemyareanum, nextareanum) == 0 then
					besttraveltime = t
					bestarea = nextareanum
				end
				hide[nextareanum] = t
				local nextupdate = aasworld.areaupdate[nextareanum]
				nextupdate.areanum = nextareanum
				nextupdate.tmptraveltime = t
				Q.VectorCopy(reach.end_, nextupdate.start)
				if not nextupdate.inlist then
					nextupdate.next = nil
					nextupdate.prev = updatelistend
					if updatelistend ~= nil then
						updatelistend.next = nextupdate
					else
						updateliststart = nextupdate
					end
					updatelistend = nextupdate
					nextupdate.inlist = true
				end
			end
		end
	end
	return bestarea
end

return nil
