--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_main.c).

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
-- Luau port of be_aas_main.c. AAS setup, per-frame update, map load and shutdown.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

B.aasworld = SB.aas_t()

local saveroutingcache = nil

function B.AAS_Error(fmt, ...)
	local str = QS.va(fmt, ...)
	B.botimport.Print(BC.PRT_FATAL, "%s", str)
end

function B.AAS_Loaded()
	return B.aasworld.loaded
end

function B.AAS_Initialized()
	return B.aasworld.initialized
end

function B.AAS_SetInitialized()
	B.aasworld.initialized = 1
	B.botimport.Print(BC.PRT_MESSAGE, "AAS initialized.\n")
end

function B.AAS_ContinueInit(time)
	local aasworld = B.aasworld
	--if no AAS file loaded
	if aasworld.loaded == 0 then
		return
	end
	--if AAS is already initialized
	if aasworld.initialized ~= 0 then
		return
	end
	--calculate reachability, if not finished return
	if B.AAS_ContinueInitReachability(time) ~= 0 then
		return
	end
	--initialize clustering for the new map
	B.AAS_InitClustering()
	--if reachability has been calculated and an AAS file should be written
	--or there is a forced data optimization
	if aasworld.savefile ~= 0 or Q.trunc(B.LibVarGetValue("forcewrite")) ~= 0 then
		--optimize the AAS data
		if Q.trunc(B.LibVarValue("aasoptimize", "0")) ~= 0 then
			B.AAS_Optimize()
		end
		--save the AAS file
		if B.AAS_WriteAASFile(aasworld.filename) then
			B.botimport.Print(BC.PRT_MESSAGE, "%s written successfully\n", aasworld.filename)
		else
			B.botimport.Print(BC.PRT_ERROR, "couldn't write %s\n", aasworld.filename)
		end
	end
	--initialize the routing
	B.AAS_InitRouting()
	--at this point AAS is initialized
	B.AAS_SetInitialized()
end

-- called at the start of every frame
function B.AAS_StartFrame(time)
	local aasworld = B.aasworld
	aasworld.time = time
	--unlink all entities that were not updated last frame
	B.AAS_UnlinkInvalidEntities()
	--invalidate the entities
	B.AAS_InvalidateEntities()
	--initialize AAS
	B.AAS_ContinueInit(time)
	aasworld.frameroutingupdates = 0
	if B.botDeveloper then
		if B.LibVarGetValue("showcacheupdates") ~= 0 then
			B.AAS_RoutingInfo()
			B.LibVarSet("showcacheupdates", "0")
		end
		if B.LibVarGetValue("showmemoryusage") ~= 0 then
			B.PrintUsedMemorySize()
			B.LibVarSet("showmemoryusage", "0")
		end
		if B.LibVarGetValue("memorydump") ~= 0 then
			B.PrintMemoryLabels()
			B.LibVarSet("memorydump", "0")
		end
	end
	if saveroutingcache.value ~= 0 then
		B.AAS_WriteRouteCache()
		B.LibVarSet("saveroutingcache", "0")
	end
	aasworld.numframes = aasworld.numframes + 1
	return BC.BLERR_NOERROR
end

function B.AAS_Time()
	return B.aasworld.time
end

function B.AAS_ProjectPointOntoVector(point, vStart, vEnd, vProj)
	local pVec = { [0] = 0, 0, 0 }
	local vec = { [0] = 0, 0, 0 }

	Q.VectorSubtract(point, vStart, pVec)
	Q.VectorSubtract(vEnd, vStart, vec)
	Q.VectorNormalizeIoq3(vec)
	-- project onto the directional vector for this segment
	Q.VectorMA(vStart, Q.DotProduct(pVec, vec), vec, vProj)
end

function B.AAS_LoadFiles(mapname)
	local aasworld = B.aasworld

	aasworld.mapname = QS.Q_strncpyz(mapname, BC.MAX_QPATH)
	--NOTE: first reset the entity links into the AAS areas and BSP leaves
	-- the AAS link heap and BSP link heap are reset after respectively the
	-- AAS file and BSP file are loaded
	B.AAS_ResetEntityLinks()
	-- load bsp info
	B.AAS_LoadBSPFile()

	--load the aas file
	local aasfile = QS.Com_sprintf(BC.MAX_QPATH, "maps/%s.aas", mapname)
	local errnum = B.AAS_LoadAASFile(aasfile)
	if errnum ~= BC.BLERR_NOERROR then
		return errnum
	end

	B.botimport.Print(BC.PRT_MESSAGE, "loaded %s\n", aasfile)
	aasworld.filename = QS.Q_strncpyz(aasfile, BC.MAX_QPATH)
	return BC.BLERR_NOERROR
end

-- called every time a map changes
function B.AAS_LoadMap(mapname)
	local aasworld = B.aasworld

	--if no mapname is provided then the string indexes are updated
	if mapname == nil then
		return 0
	end
	aasworld.initialized = 0
	--NOTE: free the routing caches before loading a new map because
	-- to free the caches the old number of areas, number of clusters
	-- and number of areas in a clusters must be available
	B.AAS_FreeRoutingCaches()
	--load the map
	local errnum = B.AAS_LoadFiles(mapname)
	if errnum ~= BC.BLERR_NOERROR then
		aasworld.loaded = 0
		return errnum
	end
	B.AAS_InitSettings()
	--initialize the AAS link heap for the new map
	B.AAS_InitAASLinkHeap()
	--initialize the AAS linked entities for the new map
	B.AAS_InitAASLinkedEntities()
	--initialize reachability for the new map
	B.AAS_InitReachability()
	--initialize the alternative routing
	B.AAS_InitAlternativeRouting()
	--everything went ok
	return 0
end

-- called when the library is first loaded
function B.AAS_Setup()
	local aasworld = B.aasworld

	aasworld.maxclients = Q.trunc(B.LibVarValue("maxclients", "128"))
	aasworld.maxentities = Q.trunc(B.LibVarValue("maxentities", "1024"))
	-- as soon as it's set to 1 the routing cache will be saved
	saveroutingcache = B.LibVar("saveroutingcache", "0")
	--allocate memory for the entities
	aasworld.entities = nil
	local entities = {}
	for i = 0, aasworld.maxentities - 1 do
		entities[i] = SB.aas_entity_t()
	end
	aasworld.entities = entities
	--invalidate all the entities
	B.AAS_InvalidateEntities()
	aasworld.numframes = 0
	return BC.BLERR_NOERROR
end

function B.AAS_Shutdown()
	local aasworld = B.aasworld

	B.AAS_ShutdownAlternativeRouting()
	B.AAS_DumpBSPData()
	--free routing caches
	B.AAS_FreeRoutingCaches()
	--free aas link heap
	B.AAS_FreeAASLinkHeap()
	--free aas linked entities
	B.AAS_FreeAASLinkedEntities()
	--free the aas data
	B.AAS_DumpAASData()
	--free the entities
	aasworld.entities = nil
	--clear the aasworld structure
	SB.copy_aas_t(aasworld, SB.aas_t())
	--aas has not been initialized
	aasworld.initialized = 0
	--NOTE: as soon as a new .bsp file is loaded the .bsp file memory is
	-- freed and reallocated, so there's no need to free that memory here
	--print shutdown
	B.botimport.Print(BC.PRT_MESSAGE, "AAS shutdown.\n")
end

return nil
