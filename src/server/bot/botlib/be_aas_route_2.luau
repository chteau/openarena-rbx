--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_route.c, part 2 of 3).

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
-- Luau port of be_aas_route.c (botlib/be_aas_route.c, part 2 of 3): routing cache allocation, init and area cache update.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("be_aas_route")

local MAX_REACHABILITYPASSAREAS = 32

function B.AAS_AllocRoutingCache(numtraveltimes)
	local size = --[[sizeof(aas_routingcache_t)]] 88
		+ numtraveltimes * 2
		+ numtraveltimes * 1
	SF.routingcachesize = SF.routingcachesize + size
	local cache = SB.aas_routingcache_t()
	cache.traveltimes = B.zeros(numtraveltimes)
	cache.reachabilities = B.zeros(numtraveltimes)
	cache.size = size
	return cache
end

function B.AAS_FreeAllClusterAreaCache()
	local aasworld = B.aasworld
	if aasworld.clusterareacache == nil then return end
	for i = 0, aasworld.numclusters - 1 do
		local cluster = aasworld.clusters[i]
		for j = 0, cluster.numareas - 1 do
			local cache = aasworld.clusterareacache[i][j]
			while cache ~= nil do
				local nextcache = cache.next
				B.AAS_FreeRoutingCache(cache)
				cache = nextcache
			end
			aasworld.clusterareacache[i][j] = nil
		end
	end
	aasworld.clusterareacache = nil
end

function B.AAS_InitClusterAreaCache()
	local aasworld = B.aasworld
	aasworld.clusterareacache = {}
	for i = 0, aasworld.numclusters - 1 do
		aasworld.clusterareacache[i] = {}
	end
end

function B.AAS_FreeAllPortalCache()
	local aasworld = B.aasworld
	if aasworld.portalcache == nil then return end
	for i = 0, aasworld.numareas - 1 do
		local cache = aasworld.portalcache[i]
		while cache ~= nil do
			local nextcache = cache.next
			B.AAS_FreeRoutingCache(cache)
			cache = nextcache
		end
		aasworld.portalcache[i] = nil
	end
	aasworld.portalcache = nil
end

function B.AAS_InitPortalCache()
	B.aasworld.portalcache = {}
end

function B.AAS_InitRoutingUpdate()
	local aasworld = B.aasworld
	aasworld.areaupdate = nil
	local maxreachabilityareas = 0
	for i = 0, aasworld.numclusters - 1 do
		if aasworld.clusters[i].numreachabilityareas > maxreachabilityareas then
			maxreachabilityareas = aasworld.clusters[i].numreachabilityareas
		end
	end
	local areaupdate = {}
	for i = 0, maxreachabilityareas - 1 do
		areaupdate[i] = SB.aas_routingupdate_t()
	end
	aasworld.areaupdate = areaupdate
	aasworld.portalupdate = nil
	local portalupdate = {}
	for i = 0, aasworld.numportals do
		portalupdate[i] = SB.aas_routingupdate_t()
	end
	aasworld.portalupdate = portalupdate
end

function B.AAS_CreateAllRoutingCache()
	local aasworld = B.aasworld
	aasworld.initialized = 1
	B.botimport.Print(BC.PRT_MESSAGE, "AAS_CreateAllRoutingCache\n")
	for i = 1, aasworld.numareas - 1 do
		if B.AAS_AreaReachability(i) ~= 0 then
			for j = 1, aasworld.numareas - 1 do
				if i ~= j and B.AAS_AreaReachability(j) ~= 0 then
					B.AAS_AreaTravelTimeToGoalArea(i, aasworld.areas[i].center, j, BC.TFL_DEFAULT)
				end
			end
		end
	end
	aasworld.initialized = 0
end

function B.AAS_WriteRouteCache()
	local aasworld = B.aasworld
	local filename = QS.Com_sprintf(BC.MAX_QPATH, "maps/%s.rcd", aasworld.mapname)
	B.AAS_Error("Unable to open file: %s\n", filename)
end

function B.AAS_ReadCache(fp)
	return nil
end

function B.AAS_ReadRouteCache()
	local aasworld = B.aasworld
	local filename = QS.Com_sprintf(BC.MAX_QPATH, "maps/%s.rcd", aasworld.mapname)
	if B.botimport.FS_ReadFile(filename) == nil then
		return 0
	end
	return 0
end

function B.AAS_InitReachabilityAreas()
	local aasworld = B.aasworld
	aasworld.reachabilityareas = nil
	aasworld.reachabilityareaindex = nil

	local reachabilityareas = {}
	for i = 0, aasworld.reachabilitysize - 1 do
		reachabilityareas[i] = SB.aas_reachabilityareas_t()
	end
	aasworld.reachabilityareas = reachabilityareas
	aasworld.reachabilityareaindex = B.zeros(aasworld.reachabilitysize * MAX_REACHABILITYPASSAREAS)
	local numreachareas = 0
	local start = {[0] = 0, 0, 0}
	local end_ = {[0] = 0, 0, 0}
	for i = 0, aasworld.reachabilitysize - 1 do
		local reach = aasworld.reachability[i]
		local numareas = 0
		local areas = {}
		local tt = bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK)
		if tt == BC.TRAVEL_BARRIERJUMP or tt == BC.TRAVEL_WATERJUMP then
			Q.VectorCopy(reach.start, end_)
			end_[2] = reach.end_[2]
			numareas = B.AAS_TraceAreas(reach.start, end_, areas, nil, MAX_REACHABILITYPASSAREAS)
		elseif tt == BC.TRAVEL_WALKOFFLEDGE then
			Q.VectorCopy(reach.end_, start)
			start[2] = reach.start[2]
			numareas = B.AAS_TraceAreas(start, reach.end_, areas, nil, MAX_REACHABILITYPASSAREAS)
		elseif tt == BC.TRAVEL_GRAPPLEHOOK then
			numareas = B.AAS_TraceAreas(reach.start, reach.end_, areas, nil, MAX_REACHABILITYPASSAREAS)
		end
		aasworld.reachabilityareas[i].firstarea = numreachareas
		aasworld.reachabilityareas[i].numareas = numareas
		for j = 0, numareas - 1 do
			aasworld.reachabilityareaindex[numreachareas] = areas[j]
			numreachareas = numreachareas + 1
		end
	end
end

function B.AAS_InitRouting()
	B.AAS_InitTravelFlagFromType()
	B.AAS_InitAreaContentsTravelFlags()
	B.AAS_InitRoutingUpdate()
	B.AAS_CreateReversedReachability()
	B.AAS_InitClusterAreaCache()
	B.AAS_InitPortalCache()
	B.AAS_CalculateAreaTravelTimes()
	B.AAS_InitPortalMaxTravelTimes()
	B.AAS_InitReachabilityAreas()
	SF.numareacacheupdates = 0
	SF.numportalcacheupdates = 0
	SF.routingcachesize = 0
	SF.max_routingcachesize = 1024 * Q.trunc(B.LibVarValue("max_routingcache", "4096"))
	B.AAS_ReadRouteCache()
end

function B.AAS_FreeRoutingCaches()
	local aasworld = B.aasworld
	B.AAS_FreeAllClusterAreaCache()
	B.AAS_FreeAllPortalCache()
	aasworld.areatraveltimes = nil
	aasworld.portalmaxtraveltimes = nil
	aasworld.reversedreachability = nil
	aasworld.areaupdate = nil
	aasworld.portalupdate = nil
	aasworld.reachabilityareas = nil
	aasworld.reachabilityareaindex = nil
	aasworld.areacontentstravelflags = nil
end

function B.AAS_UpdateAreaRoutingCache(areacache)
	local aasworld = B.aasworld
	SF.numareacacheupdates = SF.numareacacheupdates + 1
	local numreachabilityareas = aasworld.clusters[areacache.cluster].numreachabilityareas
	aasworld.frameroutingupdates = aasworld.frameroutingupdates + 1
	local badtravelflags = bit32.bnot(areacache.travelflags)
	local clusterareanum = SF.AAS_ClusterAreaNum(areacache.cluster, areacache.areanum)
	if clusterareanum >= numreachabilityareas then return end

	local startareatraveltimes = B.zeros(128)

	local curupdate = aasworld.areaupdate[clusterareanum]
	curupdate.areanum = areacache.areanum
	curupdate.areatraveltimes = startareatraveltimes
	curupdate.tmptraveltime = bit32.band(Q.trunc(areacache.starttraveltime), 0xFFFF)

	areacache.traveltimes[clusterareanum] = bit32.band(Q.trunc(areacache.starttraveltime), 0xFFFF)
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
		local revreach = aasworld.reversedreachability[curupdate.areanum]
		local i = 0
		local revlink = revreach.first
		while revlink ~= nil do
			local linknum = revlink.linknum
			local reach = aasworld.reachability[linknum]
			local skip = false
			if bit32.band(SF.AAS_TravelFlagForType_inline(reach.traveltype), badtravelflags) ~= 0 then
				skip = true
			elseif bit32.band(aasworld.areasettings[reach.areanum].areaflags, BC.AREA_DISABLED) ~= 0 then
				skip = true
			elseif bit32.band(SF.AAS_AreaContentsTravelFlags_inline(reach.areanum), badtravelflags) ~= 0 then
				skip = true
			end
			if not skip then
				local nextareanum = revlink.areanum
				local cluster = aasworld.areasettings[nextareanum].cluster
				if not (cluster > 0 and cluster ~= areacache.cluster) then
					clusterareanum = SF.AAS_ClusterAreaNum(areacache.cluster, nextareanum)
					if clusterareanum < numreachabilityareas then
						local t = bit32.band(curupdate.tmptraveltime + curupdate.areatraveltimes[i] + reach.traveltime, 0xFFFF)
						if areacache.traveltimes[clusterareanum] == 0 or areacache.traveltimes[clusterareanum] > t then
							areacache.traveltimes[clusterareanum] = t
							areacache.reachabilities[clusterareanum] = bit32.band(linknum - aasworld.areasettings[nextareanum].firstreachablearea, 0xFF)
							local nextupdate = aasworld.areaupdate[clusterareanum]
							nextupdate.areanum = nextareanum
							nextupdate.tmptraveltime = t
							nextupdate.areatraveltimes = aasworld.areatraveltimes[nextareanum][linknum - aasworld.areasettings[nextareanum].firstreachablearea]
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
			revlink = revlink.next
			i = i + 1
		end
	end
end

function B.AAS_GetAreaRoutingCache(clusternum, areanum, travelflags)
	local aasworld = B.aasworld
	local clusterareanum = SF.AAS_ClusterAreaNum(clusternum, areanum)
	local clustercache = aasworld.clusterareacache[clusternum][clusterareanum]
	local cache = clustercache
	while cache ~= nil do
		if cache.travelflags == travelflags then break end
		cache = cache.next
	end
	if cache == nil then
		cache = B.AAS_AllocRoutingCache(aasworld.clusters[clusternum].numreachabilityareas)
		cache.cluster = clusternum
		cache.areanum = areanum
		Q.VectorCopy(aasworld.areas[areanum].center, cache.origin)
		cache.starttraveltime = 1
		cache.travelflags = travelflags
		cache.prev = nil
		cache.next = clustercache
		if clustercache ~= nil then clustercache.prev = cache end
		aasworld.clusterareacache[clusternum][clusterareanum] = cache
		B.AAS_UpdateAreaRoutingCache(cache)
	else
		B.AAS_UnlinkCache(cache)
	end
	cache.time = SF.AAS_RoutingTime()
	cache.type = BC.CACHETYPE_AREA
	B.AAS_LinkCache(cache)
	return cache
end

return nil
