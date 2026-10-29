--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_route.c, part 1 of 3).

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
-- Luau port of be_aas_route.c (botlib/be_aas_route.c, part 1 of 3): routing cache bookkeeping, travel flags, reversed reachability, area travel times.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local SF = B.FileStatics("be_aas_route")

-- ROUTING_DEBUG is defined

--travel time in hundreths of a second = distance * 100 / speed
SF.DISTANCEFACTOR_CROUCH = Q.f(1.3) --crouch speed = 100
SF.DISTANCEFACTOR_SWIM = 1 --should be 0.66, swim speed = 150
SF.DISTANCEFACTOR_WALK = Q.f(0.33) --walk speed = 300

--cache refresh time
SF.CACHE_REFRESHTIME = Q.f(15.0) --15 seconds refresh time

--maximum number of routing updates each frame
SF.MAX_FRAMEROUTINGUPDATES = 10

SF.numareacacheupdates = 0
SF.numportalcacheupdates = 0

SF.routingcachesize = 0
SF.max_routingcachesize = 0

local function PAD(base, alignment)
	return bit32.band(base + alignment - 1, bit32.bnot(alignment - 1))
end

function B.AAS_RoutingInfo()
	B.botimport.Print(BC.PRT_MESSAGE, "%d area cache updates\n", SF.numareacacheupdates)
	B.botimport.Print(BC.PRT_MESSAGE, "%d portal cache updates\n", SF.numportalcacheupdates)
	B.botimport.Print(BC.PRT_MESSAGE, "%d bytes routing cache\n", SF.routingcachesize)
end

-- returns the number of the area in the cluster
-- assumes the given area is in the given cluster or a portal of the cluster
function SF.AAS_ClusterAreaNum(cluster, areanum)
	local aasworld = B.aasworld
	local areacluster = aasworld.areasettings[areanum].cluster
	if areacluster > 0 then
		return aasworld.areasettings[areanum].clusterareanum
	else
		local side = if aasworld.portals[-areacluster].frontcluster ~= cluster then 1 else 0
		return aasworld.portals[-areacluster].clusterareanum[side]
	end
end

function B.AAS_InitTravelFlagFromType()
	local aasworld = B.aasworld
	for i = 0, BC.MAX_TRAVELTYPES - 1 do
		aasworld.travelflagfortype[i] = BC.TFL_INVALID
	end
	aasworld.travelflagfortype[BC.TRAVEL_INVALID] = BC.TFL_INVALID
	aasworld.travelflagfortype[BC.TRAVEL_WALK] = BC.TFL_WALK
	aasworld.travelflagfortype[BC.TRAVEL_CROUCH] = BC.TFL_CROUCH
	aasworld.travelflagfortype[BC.TRAVEL_BARRIERJUMP] = BC.TFL_BARRIERJUMP
	aasworld.travelflagfortype[BC.TRAVEL_JUMP] = BC.TFL_JUMP
	aasworld.travelflagfortype[BC.TRAVEL_LADDER] = BC.TFL_LADDER
	aasworld.travelflagfortype[BC.TRAVEL_WALKOFFLEDGE] = BC.TFL_WALKOFFLEDGE
	aasworld.travelflagfortype[BC.TRAVEL_SWIM] = BC.TFL_SWIM
	aasworld.travelflagfortype[BC.TRAVEL_WATERJUMP] = BC.TFL_WATERJUMP
	aasworld.travelflagfortype[BC.TRAVEL_TELEPORT] = BC.TFL_TELEPORT
	aasworld.travelflagfortype[BC.TRAVEL_ELEVATOR] = BC.TFL_ELEVATOR
	aasworld.travelflagfortype[BC.TRAVEL_ROCKETJUMP] = BC.TFL_ROCKETJUMP
	aasworld.travelflagfortype[BC.TRAVEL_BFGJUMP] = BC.TFL_BFGJUMP
	aasworld.travelflagfortype[BC.TRAVEL_GRAPPLEHOOK] = BC.TFL_GRAPPLEHOOK
	aasworld.travelflagfortype[BC.TRAVEL_DOUBLEJUMP] = BC.TFL_DOUBLEJUMP
	aasworld.travelflagfortype[BC.TRAVEL_RAMPJUMP] = BC.TFL_RAMPJUMP
	aasworld.travelflagfortype[BC.TRAVEL_STRAFEJUMP] = BC.TFL_STRAFEJUMP
	aasworld.travelflagfortype[BC.TRAVEL_JUMPPAD] = BC.TFL_JUMPPAD
	aasworld.travelflagfortype[BC.TRAVEL_FUNCBOB] = BC.TFL_FUNCBOB
end

function SF.AAS_TravelFlagForType_inline(traveltype)
	local aasworld = B.aasworld
	local tfl = 0

	if bit32.band(traveltype, BC.TRAVELFLAG_NOTTEAM1) ~= 0 then
		tfl = bit32.bor(tfl, BC.TFL_NOTTEAM1)
	end
	if bit32.band(traveltype, BC.TRAVELFLAG_NOTTEAM2) ~= 0 then
		tfl = bit32.bor(tfl, BC.TFL_NOTTEAM2)
	end
	traveltype = bit32.band(traveltype, BC.TRAVELTYPE_MASK)
	if traveltype < 0 or traveltype >= BC.MAX_TRAVELTYPES then
		return BC.TFL_INVALID
	end
	tfl = bit32.bor(tfl, aasworld.travelflagfortype[traveltype])
	return tfl
end

function B.AAS_TravelFlagForType(traveltype)
	return SF.AAS_TravelFlagForType_inline(traveltype)
end

function B.AAS_UnlinkCache(cache)
	local aasworld = B.aasworld
	if cache.time_next ~= nil then
		cache.time_next.time_prev = cache.time_prev
	else
		aasworld.newestcache = cache.time_prev
	end
	if cache.time_prev ~= nil then
		cache.time_prev.time_next = cache.time_next
	else
		aasworld.oldestcache = cache.time_next
	end
	cache.time_next = nil
	cache.time_prev = nil
end

function B.AAS_LinkCache(cache)
	local aasworld = B.aasworld
	if aasworld.newestcache ~= nil then
		aasworld.newestcache.time_next = cache
		cache.time_prev = aasworld.newestcache
	else
		aasworld.oldestcache = cache
		cache.time_prev = nil
	end
	cache.time_next = nil
	aasworld.newestcache = cache
end

function B.AAS_FreeRoutingCache(cache)
	B.AAS_UnlinkCache(cache)
	SF.routingcachesize = SF.routingcachesize - cache.size
end

function B.AAS_RemoveRoutingCacheInCluster(clusternum)
	local aasworld = B.aasworld

	if aasworld.clusterareacache == nil then
		return
	end
	local cluster = aasworld.clusters[clusternum]
	for i = 0, cluster.numareas - 1 do
		local cache = aasworld.clusterareacache[clusternum][i]
		while cache ~= nil do
			local nextcache = cache.next
			B.AAS_FreeRoutingCache(cache)
			cache = nextcache
		end
		aasworld.clusterareacache[clusternum][i] = nil
	end
end

function B.AAS_RemoveRoutingCacheUsingArea(areanum)
	local aasworld = B.aasworld

	local clusternum = aasworld.areasettings[areanum].cluster
	if clusternum > 0 then
		--remove all the cache in the cluster the area is in
		B.AAS_RemoveRoutingCacheInCluster(clusternum)
	else
		-- if this is a portal remove all cache in both the front and back cluster
		B.AAS_RemoveRoutingCacheInCluster(aasworld.portals[-clusternum].frontcluster)
		B.AAS_RemoveRoutingCacheInCluster(aasworld.portals[-clusternum].backcluster)
	end
	-- remove all portal cache
	for i = 0, aasworld.numareas - 1 do
		--refresh portal cache
		local cache = aasworld.portalcache[i]
		while cache ~= nil do
			local nextcache = cache.next
			B.AAS_FreeRoutingCache(cache)
			cache = nextcache
		end
		aasworld.portalcache[i] = nil
	end
end

function B.AAS_EnableRoutingArea(areanum, enable)
	local aasworld = B.aasworld

	if areanum <= 0 or areanum >= aasworld.numareas then
		local dev = B.botDeveloper
		if dev ~= nil and dev ~= 0 and dev ~= false then
			B.botimport.Print(BC.PRT_ERROR, "AAS_EnableRoutingArea: areanum %d out of range\n", areanum)
		end
		return 0
	end
	local flags = bit32.band(aasworld.areasettings[areanum].areaflags, BC.AREA_DISABLED)
	if enable < 0 then
		return if flags == 0 then 1 else 0
	end

	if enable ~= 0 then
		aasworld.areasettings[areanum].areaflags = bit32.band(aasworld.areasettings[areanum].areaflags, bit32.bnot(BC.AREA_DISABLED))
	else
		aasworld.areasettings[areanum].areaflags = bit32.bor(aasworld.areasettings[areanum].areaflags, BC.AREA_DISABLED)
	end
	-- if the status of the area changed
	if bit32.band(flags, BC.AREA_DISABLED) ~= bit32.band(aasworld.areasettings[areanum].areaflags, BC.AREA_DISABLED) then
		--remove all routing cache involving this area
		B.AAS_RemoveRoutingCacheUsingArea(areanum)
	end
	return if flags == 0 then 1 else 0
end

function SF.AAS_RoutingTime()
	return B.AAS_Time()
end

function B.AAS_GetAreaContentsTravelFlags(areanum)
	local aasworld = B.aasworld

	local contents = aasworld.areasettings[areanum].contents
	local tfl = 0
	if bit32.band(contents, BC.AREACONTENTS_WATER) ~= 0 then
		tfl = bit32.bor(tfl, BC.TFL_WATER)
	elseif bit32.band(contents, BC.AREACONTENTS_SLIME) ~= 0 then
		tfl = bit32.bor(tfl, BC.TFL_SLIME)
	elseif bit32.band(contents, BC.AREACONTENTS_LAVA) ~= 0 then
		tfl = bit32.bor(tfl, BC.TFL_LAVA)
	else
		tfl = bit32.bor(tfl, BC.TFL_AIR)
	end
	if bit32.band(contents, BC.AREACONTENTS_DONOTENTER) ~= 0 then
		tfl = bit32.bor(tfl, BC.TFL_DONOTENTER)
	end
	if bit32.band(contents, BC.AREACONTENTS_NOTTEAM1) ~= 0 then
		tfl = bit32.bor(tfl, BC.TFL_NOTTEAM1)
	end
	if bit32.band(contents, BC.AREACONTENTS_NOTTEAM2) ~= 0 then
		tfl = bit32.bor(tfl, BC.TFL_NOTTEAM2)
	end
	if bit32.band(aasworld.areasettings[areanum].areaflags, BC.AREA_BRIDGE) ~= 0 then
		tfl = bit32.bor(tfl, BC.TFL_BRIDGE)
	end
	return tfl
end

function SF.AAS_AreaContentsTravelFlags_inline(areanum)
	return B.aasworld.areacontentstravelflags[areanum]
end

function B.AAS_AreaContentsTravelFlags(areanum)
	return B.aasworld.areacontentstravelflags[areanum]
end

function B.AAS_InitAreaContentsTravelFlags()
	local aasworld = B.aasworld

	aasworld.areacontentstravelflags = B.zeros(aasworld.numareas)
	for i = 0, aasworld.numareas - 1 do
		aasworld.areacontentstravelflags[i] = B.AAS_GetAreaContentsTravelFlags(i)
	end
end

function B.AAS_CreateReversedReachability()
	local aasworld = B.aasworld

	--free reversed links that have already been created
	--allocate memory for the reversed reachability links
	local revs = {}
	for i = 0, aasworld.numareas - 1 do
		revs[i] = SB.aas_reversedreachability_t()
	end
	aasworld.reversedreachability = revs
	--check all reachabilities of all areas
	for i = 1, aasworld.numareas - 1 do
		--settings of the area
		local settings = aasworld.areasettings[i]
		--
		if settings.numreachableareas >= 128 then
			B.botimport.Print(BC.PRT_WARNING, "area %d has more than 128 reachabilities\n", i)
		end
		--create reversed links for the reachabilities
		local n = 0
		while n < settings.numreachableareas and n < 128 do
			--reachability link
			local reach = aasworld.reachability[settings.firstreachablearea + n]
			--
			local revlink = SB.aas_reversedlink_t()
			--
			revlink.areanum = i
			revlink.linknum = settings.firstreachablearea + n
			revlink.next = revs[reach.areanum].first
			revs[reach.areanum].first = revlink
			revs[reach.areanum].numlinks = revs[reach.areanum].numlinks + 1
			n = n + 1
		end
	end
end

function B.AAS_AreaTravelTime(areanum, start, end_)
	local dir = { [0] = 0, 0, 0 }

	Q.VectorSubtract(start, end_, dir)
	local dist = Q.VectorLength(dir)
	--if crouch only area
	if B.AAS_AreaCrouch(areanum) ~= 0 then
		dist = Q.f(dist * SF.DISTANCEFACTOR_CROUCH)
	--if swim area
	elseif B.AAS_AreaSwim(areanum) ~= 0 then
		dist = Q.f(dist * SF.DISTANCEFACTOR_SWIM)
	--normal walk area
	else
		dist = Q.f(dist * SF.DISTANCEFACTOR_WALK)
	end
	--
	local intdist = Q.trunc(dist)
	--make sure the distance isn't zero
	if intdist <= 0 then
		intdist = 1
	end
	return bit32.band(intdist, 0xFFFF)
end

function B.AAS_CalculateAreaTravelTimes()
	local aasworld = B.aasworld
	local end_ = { [0] = 0, 0, 0 }

	--if there are still area travel times, free the memory
	aasworld.areatraveltimes = {}
	--calcluate the travel times for all the areas
	for i = 0, aasworld.numareas - 1 do
		--reversed reachabilities of this area
		local revreach = aasworld.reversedreachability[i]
		--settings of the area
		local settings = aasworld.areasettings[i]
		--
		local perarea = {}
		aasworld.areatraveltimes[i] = perarea
		--
		for l = 0, settings.numreachableareas - 1 do
			perarea[l] = B.zeros(PAD(revreach.numlinks, 8))
			--reachability link
			local reach = aasworld.reachability[settings.firstreachablearea + l]
			--
			local n = 0
			local revlink = revreach.first
			while revlink ~= nil do
				local r = aasworld.reachability[revlink.linknum].end_
				end_[0] = r[0]
				end_[1] = r[1]
				end_[2] = r[2]
				--
				perarea[l][n] = B.AAS_AreaTravelTime(i, end_, reach.start)
				revlink = revlink.next
				n = n + 1
			end
		end
	end
end

function B.AAS_PortalMaxTravelTime(portalnum)
	local aasworld = B.aasworld

	local portal = aasworld.portals[portalnum]
	--reversed reachabilities of this portal area
	local revreach = aasworld.reversedreachability[portal.areanum]
	--settings of the portal area
	local settings = aasworld.areasettings[portal.areanum]
	--
	local maxt = 0
	for l = 0, settings.numreachableareas - 1 do
		local n = 0
		local revlink = revreach.first
		while revlink ~= nil do
			local t = aasworld.areatraveltimes[portal.areanum][l][n]
			if t > maxt then
				maxt = t
			end
			revlink = revlink.next
			n = n + 1
		end
	end
	return maxt
end

function B.AAS_InitPortalMaxTravelTimes()
	local aasworld = B.aasworld

	aasworld.portalmaxtraveltimes = B.zeros(aasworld.numportals)

	for i = 0, aasworld.numportals - 1 do
		aasworld.portalmaxtraveltimes[i] = B.AAS_PortalMaxTravelTime(i)
	end
end

function B.AAS_FreeOldestCache()
	local aasworld = B.aasworld

	local cache = aasworld.oldestcache
	while cache ~= nil do
		-- never free area cache leading towards a portal
		if not (cache.type == BC.CACHETYPE_AREA and aasworld.areasettings[cache.areanum].cluster < 0) then
			break
		end
		cache = cache.time_next
	end
	if cache ~= nil then
		-- unlink the cache
		if cache.type == BC.CACHETYPE_AREA then
			--number of the area in the cluster
			local clusterareanum = SF.AAS_ClusterAreaNum(cache.cluster, cache.areanum)
			-- unlink from cluster area cache
			if cache.prev ~= nil then
				cache.prev.next = cache.next
			else
				aasworld.clusterareacache[cache.cluster][clusterareanum] = cache.next
			end
			if cache.next ~= nil then
				cache.next.prev = cache.prev
			end
		else
			-- unlink from portal cache
			if cache.prev ~= nil then
				cache.prev.next = cache.next
			else
				aasworld.portalcache[cache.areanum] = cache.next
			end
			if cache.next ~= nil then
				cache.next.prev = cache.prev
			end
		end
		B.AAS_FreeRoutingCache(cache)
		return 1
	end
	return 0
end

return nil
