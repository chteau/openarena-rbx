--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_file.c).

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
-- Luau port of be_aas_file.c: loads a map's .aas file into aasworld. The
-- file comes in whole as a buffer from botimport.FS_ReadFile (the Roblox
-- side joins the converter's Aas_NNN buffer modules into it), so the lump
-- reads are buffer reads instead of FS_Seek/FS_Read on a handle. The data
-- is little-endian on disk and in a Luau buffer alike, which makes
-- AAS_SwapAASData's LittleLong/LittleFloat calls the identity.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local QS = require("../../../shared/q_shared")

local readi32, readf32, readu16 = buffer.readi32, buffer.readf32, buffer.readu16

local function vec(b: buffer, o: number)
	return { [0] = readf32(b, o), readf32(b, o + 4), readf32(b, o + 8) }
end

-- record readers: sizeof(T) on x86_64 and how one record decodes
local LUMPS = {
	[BC.AASLUMP_BBOXES] = { 32, function(b, o)
		local t = SB.aas_bbox_t()
		t.presencetype, t.flags = readi32(b, o), readi32(b, o + 4)
		t.mins, t.maxs = vec(b, o + 8), vec(b, o + 20)
		return t
	end },
	[BC.AASLUMP_VERTEXES] = { 12, vec },
	[BC.AASLUMP_PLANES] = { 20, function(b, o)
		local t = SB.aas_plane_t()
		t.normal, t.dist, t.type = vec(b, o), readf32(b, o + 12), readi32(b, o + 16)
		return t
	end },
	[BC.AASLUMP_EDGES] = { 8, function(b, o)
		local t = SB.aas_edge_t()
		t.v[0], t.v[1] = readi32(b, o), readi32(b, o + 4)
		return t
	end },
	[BC.AASLUMP_EDGEINDEX] = { 4, readi32 },
	[BC.AASLUMP_FACES] = { 24, function(b, o)
		local t = SB.aas_face_t()
		t.planenum, t.faceflags, t.numedges = readi32(b, o), readi32(b, o + 4), readi32(b, o + 8)
		t.firstedge, t.frontarea, t.backarea = readi32(b, o + 12), readi32(b, o + 16), readi32(b, o + 20)
		return t
	end },
	[BC.AASLUMP_FACEINDEX] = { 4, readi32 },
	[BC.AASLUMP_AREAS] = { 48, function(b, o)
		local t = SB.aas_area_t()
		t.areanum, t.numfaces, t.firstface = readi32(b, o), readi32(b, o + 4), readi32(b, o + 8)
		t.mins, t.maxs, t.center = vec(b, o + 12), vec(b, o + 24), vec(b, o + 36)
		return t
	end },
	[BC.AASLUMP_AREASETTINGS] = { 28, function(b, o)
		local t = SB.aas_areasettings_t()
		t.contents, t.areaflags, t.presencetype = readi32(b, o), readi32(b, o + 4), readi32(b, o + 8)
		t.cluster, t.clusterareanum = readi32(b, o + 12), readi32(b, o + 16)
		t.numreachableareas, t.firstreachablearea = readi32(b, o + 20), readi32(b, o + 24)
		return t
	end },
	[BC.AASLUMP_REACHABILITY] = { 44, function(b, o)
		local t = SB.aas_reachability_t()
		t.areanum, t.facenum, t.edgenum = readi32(b, o), readi32(b, o + 4), readi32(b, o + 8)
		t.start, t.end_ = vec(b, o + 12), vec(b, o + 24)
		t.traveltype, t.traveltime = readi32(b, o + 36), readu16(b, o + 40)
		return t
	end },
	[BC.AASLUMP_NODES] = { 12, function(b, o)
		local t = SB.aas_node_t()
		t.planenum, t.children[0], t.children[1] = readi32(b, o), readi32(b, o + 4), readi32(b, o + 8)
		return t
	end },
	[BC.AASLUMP_PORTALS] = { 20, function(b, o)
		local t = SB.aas_portal_t()
		t.areanum, t.frontcluster, t.backcluster = readi32(b, o), readi32(b, o + 4), readi32(b, o + 8)
		t.clusterareanum[0], t.clusterareanum[1] = readi32(b, o + 12), readi32(b, o + 16)
		return t
	end },
	[BC.AASLUMP_PORTALINDEX] = { 4, readi32 },
	[BC.AASLUMP_CLUSTERS] = { 16, function(b, o)
		local t = SB.aas_cluster_t()
		t.numareas, t.numreachabilityareas = readi32(b, o), readi32(b, o + 4)
		t.numportals, t.firstportal = readi32(b, o + 8), readi32(b, o + 12)
		return t
	end },
}
-- aasworld field (array, count) per lump, in the order AAS_LoadAASFile reads them
local FIELDS = {
	[BC.AASLUMP_BBOXES] = { "bboxes", "numbboxes" },
	[BC.AASLUMP_VERTEXES] = { "vertexes", "numvertexes" },
	[BC.AASLUMP_PLANES] = { "planes", "numplanes" },
	[BC.AASLUMP_EDGES] = { "edges", "numedges" },
	[BC.AASLUMP_EDGEINDEX] = { "edgeindex", "edgeindexsize" },
	[BC.AASLUMP_FACES] = { "faces", "numfaces" },
	[BC.AASLUMP_FACEINDEX] = { "faceindex", "faceindexsize" },
	[BC.AASLUMP_AREAS] = { "areas", "numareas" },
	[BC.AASLUMP_AREASETTINGS] = { "areasettings", "numareasettings" },
	[BC.AASLUMP_REACHABILITY] = { "reachability", "reachabilitysize" },
	[BC.AASLUMP_NODES] = { "nodes", "numnodes" },
	[BC.AASLUMP_PORTALS] = { "portals", "numportals" },
	[BC.AASLUMP_PORTALINDEX] = { "portalindex", "portalindexsize" },
	[BC.AASLUMP_CLUSTERS] = { "clusters", "numclusters" },
}

--===========================================================================
-- AAS_SwapAASData: byte swapping is the identity on little-endian data,
-- which is what both the file and a Luau buffer hold.
--===========================================================================
function B.AAS_SwapAASData() end

--===========================================================================
-- dump the current loaded aas file
--===========================================================================
function B.AAS_DumpAASData()
	local aasworld = B.aasworld
	for _, f in FIELDS do
		aasworld[f[2]] = 0
		aasworld[f[1]] = nil
	end
	aasworld.loaded = 0
	aasworld.initialized = 0
	aasworld.savefile = 0
end

--===========================================================================
-- reads one lump into a 0-based array of records (a cleared dummy record
-- for an empty lump, like the C GetClearedHunkMemory(size+1))
--===========================================================================
local function AAS_LoadAASLump(b: buffer, lump: number, offset: number, length: number)
	local size, read = LUMPS[lump][1], LUMPS[lump][2]
	if length == 0 then
		return { [0] = read(buffer.create(size), 0) }
	end
	if offset < 0 or offset + length > buffer.len(b) then
		B.AAS_Error("can't seek to aas lump\n")
		B.AAS_DumpAASData()
		return nil
	end
	local n = length // size
	local t = table.create(n)
	for i = 0, n - 1 do
		t[i] = read(b, offset + i * size)
	end
	return t
end

--===========================================================================
-- AAS_DData: the header de-obfuscation of AAS version 5
--===========================================================================
function B.AAS_DData(data: buffer, start: number, size: number)
	for i = 0, size - 1 do
		local v = buffer.readu8(data, start + i)
		buffer.writeu8(data, start + i, bit32.bxor(v, bit32.band(i * 119, 0xFF)))
	end
end

--===========================================================================
-- load an aas file
--===========================================================================
function B.AAS_LoadAASFile(filename: string): number
	local aasworld = B.aasworld
	B.botimport.Print(BC.PRT_MESSAGE, "trying to load %s\n", filename)
	--dump current loaded aas file
	B.AAS_DumpAASData()
	--open the file
	local data = B.botimport.FS_ReadFile(filename)
	if data == nil then
		B.AAS_Error("can't open %s\n", filename)
		return BC.BLERR_CANNOTOPENAASFILE
	end
	local headersize = 12 + 8 * BC.AAS_LUMPS
	if buffer.len(data) < headersize then
		B.AAS_Error("%s is not an AAS file\n", filename)
		return BC.BLERR_WRONGAASFILEID
	end
	--read the header (a copy: AAS_DData works in place)
	local header = buffer.create(headersize)
	buffer.copy(header, 0, data, 0, headersize)
	--check header identification
	if readi32(header, 0) ~= BC.AASID then
		B.AAS_Error("%s is not an AAS file\n", filename)
		return BC.BLERR_WRONGAASFILEID
	end
	--check the version
	local version = readi32(header, 4)
	if version ~= BC.AASVERSION_OLD and version ~= BC.AASVERSION then
		B.AAS_Error("aas file %s is version %i, not %i\n", filename, version, BC.AASVERSION)
		return BC.BLERR_WRONGAASFILEVERSION
	end
	if version == BC.AASVERSION then
		B.AAS_DData(header, 8, headersize - 8)
	end
	aasworld.bspchecksum = QS.atoi(B.LibVarGetString("sv_mapChecksum"))
	if readi32(header, 8) ~= aasworld.bspchecksum then
		B.AAS_Error("aas file %s is out of date\n", filename)
		return BC.BLERR_WRONGAASFILEVERSION
	end
	--load the lumps
	for lump = 0, BC.AAS_LUMPS - 1 do
		local offset = readi32(header, 12 + lump * 8)
		local length = readi32(header, 16 + lump * 8)
		local arr = AAS_LoadAASLump(data, lump, offset, length)
		local f = FIELDS[lump]
		aasworld[f[1]] = arr
		aasworld[f[2]] = length // LUMPS[lump][1]
		if aasworld[f[2]] ~= 0 and arr == nil then
			return BC.BLERR_CANNOTREADAASLUMP
		end
	end
	--swap everything
	B.AAS_SwapAASData()
	--aas file is loaded
	aasworld.loaded = 1
	return BC.BLERR_NOERROR
end

--===========================================================================
-- AAS_WriteAASFile: botlib only writes an .aas when it computed the
-- reachabilities or clusters itself (forcereachability / forceclustering /
-- forcewrite libvars); the port has no writable file system, so the write
-- fails the way C does when it cannot open the file.
--===========================================================================
function B.AAS_WriteAASFile(filename: string): boolean
	B.botimport.Print(BC.PRT_MESSAGE, "writing %s\n", filename)
	B.AAS_Error("error opening %s\n", filename)
	return false
end

--===========================================================================
-- AAS_Optimize (be_aas_optimize.c) compacts the AAS data right before
-- AAS_WriteAASFile saves it ("aasoptimize" libvar). Saving cannot happen
-- here, so there is nothing to optimize for.
--===========================================================================
function B.AAS_Optimize() end

return nil
