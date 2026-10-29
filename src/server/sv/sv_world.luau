--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (ioquake3 code/server/sv_world.c).

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
-- Luau port of ioquake3's server/sv_world.c: the entity area tree, entity
-- linking (clusters/areas for the PVS), area queries, and traces/point
-- contents against the world plus every solid entity.

local SV = require("./server")
local Collision = require("../../shared/Collision")
local Q = require("../../shared/q_math")
local S = require("../../shared/structs")
local C = require("../g_defs")

local f = Q.f
local band, bor, lshift = bit32.band, bit32.bor, bit32.lshift
local VectorCopy, VectorAdd, VectorSubtract = Q.VectorCopy, Q.VectorAdd, Q.VectorSubtract
local vec3 = Q.vec3
local sv = SV.sv

local W = {}

function W.SV_GentityNum(num: number)
	return sv.gentities[num]
end

function W.SV_SvEntityForGentity(gEnt)
	if not gEnt or gEnt.s.number < 0 or gEnt.s.number >= C.MAX_GENTITIES then
		error("SV_SvEntityForGentity: bad gEnt")
	end
	return sv.svEntities[gEnt.s.number]
end

function W.SV_GEntityForSvEntity(svEnt)
	return W.SV_GentityNum(svEnt.index)
end

-- Returns a headnode that can be used for testing or clipping to a given
-- entity. If the entity is a bsp model, the headnode will be returned,
-- otherwise a custom box tree will be constructed.
function W.SV_ClipHandleForEntity(ent): number
	if ent.r.bmodel then
		-- explicit hulls in the BSP model
		return Collision.InlineModel(ent.s.modelindex)
	end
	if band(ent.r.svFlags, C.SVF_CAPSULE) ~= 0 then
		-- create a temp capsule from bounding box sizes
		return Collision.TempBoxModel(ent.r.mins, ent.r.maxs, true)
	end
	-- create a temp tree from bounding box sizes
	return Collision.TempBoxModel(ent.r.mins, ent.r.maxs, false)
end

--[[
ENTITY CHECKING

To avoid linearly searching through lists of entities during environment
testing, the world is carved up with an evenly spaced, axially aligned bsp
tree. Entities are kept in chains either at the final leafs, or at the
first node that splits them, which prevents having to deal with multiple
fragments of a single entity.
]]

local AREA_DEPTH = 4
local AREA_NODES = 64

local sv_worldSectors = {}
local sv_numworldSectors = 0
for i = 0, AREA_NODES - 1 do
	sv_worldSectors[i] = { axis = 0, dist = 0, children = { [0] = nil, nil }, entities = nil }
end

function W.SV_SectorList_f(print)
	for i = 0, AREA_NODES - 1 do
		local c = 0
		local ent = sv_worldSectors[i].entities
		while ent do
			c += 1
			ent = ent.nextEntityInWorldSector
		end
		print(string.format("sector %i: %i entities\n", i, c))
	end
end

-- Builds a uniformly subdivided tree for the given world size
local function SV_CreateworldSector(depth: number, mins, maxs)
	local anode = sv_worldSectors[sv_numworldSectors]
	sv_numworldSectors += 1

	if depth == AREA_DEPTH then
		anode.axis = -1
		anode.children[0] = nil
		anode.children[1] = nil
		return anode
	end

	local size = vec3()
	VectorSubtract(maxs, mins, size)
	if size[0] > size[1] then
		anode.axis = 0
	else
		anode.axis = 1
	end

	anode.dist = f(0.5 * f(maxs[anode.axis] + mins[anode.axis]))
	local mins1, mins2, maxs1, maxs2 = vec3(), vec3(), vec3(), vec3()
	VectorCopy(mins, mins1)
	VectorCopy(mins, mins2)
	VectorCopy(maxs, maxs1)
	VectorCopy(maxs, maxs2)

	maxs1[anode.axis] = anode.dist
	mins2[anode.axis] = anode.dist

	anode.children[0] = SV_CreateworldSector(depth + 1, mins2, maxs2)
	anode.children[1] = SV_CreateworldSector(depth + 1, mins1, maxs1)

	return anode
end

function W.SV_ClearWorld()
	for i = 0, AREA_NODES - 1 do
		local s = sv_worldSectors[i]
		s.axis = 0
		s.dist = 0
		s.children[0] = nil
		s.children[1] = nil
		s.entities = nil
	end
	sv_numworldSectors = 0
	for i = 0, C.MAX_GENTITIES - 1 do
		local e = sv.svEntities[i]
		e.worldSector = nil
		e.nextEntityInWorldSector = nil
	end

	-- get world map bounds
	local h = Collision.InlineModel(0)
	local mins, maxs = vec3(), vec3()
	Collision.ModelBounds(h, mins, maxs)
	SV_CreateworldSector(0, mins, maxs)
end

function W.SV_UnlinkEntity(gEnt)
	local ent = W.SV_SvEntityForGentity(gEnt)

	gEnt.r.linked = false

	local ws = ent.worldSector
	if not ws then
		return -- not linked in anywhere
	end
	ent.worldSector = nil

	if ws.entities == ent then
		ws.entities = ent.nextEntityInWorldSector
		return
	end

	local scan = ws.entities
	while scan do
		if scan.nextEntityInWorldSector == ent then
			scan.nextEntityInWorldSector = ent.nextEntityInWorldSector
			return
		end
		scan = scan.nextEntityInWorldSector
	end

	print("WARNING: SV_UnlinkEntity: not found in worldSector")
end

local MAX_TOTAL_ENT_LEAFS = 128
local leafs = {}

function W.SV_LinkEntity(gEnt)
	local ent = W.SV_SvEntityForGentity(gEnt)
	local r, s = gEnt.r, gEnt.s

	if ent.worldSector then
		W.SV_UnlinkEntity(gEnt) -- unlink from old position
	end

	-- encode the size into the entityState_t for client prediction
	if r.bmodel then
		s.solid = C.SOLID_BMODEL -- a solid_box will never create this value
	elseif band(r.contents, bor(C.CONTENTS_SOLID, C.CONTENTS_BODY)) ~= 0 then
		-- assume that x/y are equal and symetric
		local i = Q.trunc(r.maxs[0])
		if i < 1 then
			i = 1
		end
		if i > 255 then
			i = 255
		end

		-- z is not symetric
		local j = Q.trunc(-r.mins[2])
		if j < 1 then
			j = 1
		end
		if j > 255 then
			j = 255
		end

		-- and z maxs can be negative...
		local k = Q.trunc(f(r.maxs[2] + 32))
		if k < 1 then
			k = 1
		end
		if k > 255 then
			k = 255
		end

		s.solid = bor(lshift(k, 16), lshift(j, 8), i)
	else
		s.solid = 0
	end

	-- get the position
	local origin = r.currentOrigin
	local angles = r.currentAngles

	-- set the abs box
	if r.bmodel and (angles[0] ~= 0 or angles[1] ~= 0 or angles[2] ~= 0) then
		-- expand for rotation
		local max = Q.RadiusFromBounds(r.mins, r.maxs)
		for i = 0, 2 do
			r.absmin[i] = f(origin[i] - max)
			r.absmax[i] = f(origin[i] + max)
		end
	else
		-- normal
		VectorAdd(origin, r.mins, r.absmin)
		VectorAdd(origin, r.maxs, r.absmax)
	end

	-- because movement is clipped an epsilon away from an actual edge,
	-- we must fully check even when bounding boxes don't quite touch
	r.absmin[0] = f(r.absmin[0] - 1)
	r.absmin[1] = f(r.absmin[1] - 1)
	r.absmin[2] = f(r.absmin[2] - 1)
	r.absmax[0] = f(r.absmax[0] + 1)
	r.absmax[1] = f(r.absmax[1] + 1)
	r.absmax[2] = f(r.absmax[2] + 1)

	-- link to PVS leafs
	ent.numClusters = 0
	ent.lastCluster = 0
	ent.areanum = -1
	ent.areanum2 = -1

	--get all leafs, including solids
	local num_leafs, lastLeaf = Collision.BoxLeafnums(r.absmin, r.absmax, leafs, MAX_TOTAL_ENT_LEAFS)

	-- if none of the leafs were inside the map, the
	-- entity is outside the world and can be considered unlinked
	if num_leafs == 0 then
		return
	end

	-- set areas, even from clusters that don't fit in the entity array
	for i = 0, num_leafs - 1 do
		local area = Collision.LeafArea(leafs[i])
		if area ~= -1 then
			-- doors may legally straggle two areas,
			-- but nothing should evern need more than that
			if ent.areanum ~= -1 and ent.areanum ~= area then
				ent.areanum2 = area
			else
				ent.areanum = area
			end
		end
	end

	-- store as many explicit clusters as we can
	ent.numClusters = 0
	local i = 0
	while i < num_leafs do
		local cluster = Collision.LeafCluster(leafs[i])
		if cluster ~= -1 then
			ent.clusternums[ent.numClusters] = cluster
			ent.numClusters += 1
			if ent.numClusters == SV.MAX_ENT_CLUSTERS then
				break
			end
		end
		i += 1
	end

	-- store off a last cluster if we need to
	if i ~= num_leafs then
		ent.lastCluster = Collision.LeafCluster(lastLeaf)
	end

	r.linkcount += 1

	-- find the first world sector node that the ent's box crosses
	local node = sv_worldSectors[0]
	while true do
		if node.axis == -1 then
			break
		end
		if r.absmin[node.axis] > node.dist then
			node = node.children[0]
		elseif r.absmax[node.axis] < node.dist then
			node = node.children[1]
		else
			break -- crosses the node
		end
	end

	-- link it in
	ent.worldSector = node
	ent.nextEntityInWorldSector = node.entities
	node.entities = ent

	r.linked = true
end

--[[
AREA QUERY

Fills in a list of all entities who's absmin / absmax intersects the given
bounds. This does NOT mean that they actually touch in the case of bmodels.
]]

local function SV_AreaEntities_r(node, ap)
	local check = node.entities
	while check do
		local nextc = check.nextEntityInWorldSector

		local gcheck = sv.gentities[check.index]

		local amin, amax = gcheck.r.absmin, gcheck.r.absmax
		if amin[0] > ap.maxs[0] or amin[1] > ap.maxs[1] or amin[2] > ap.maxs[2] or amax[0] < ap.mins[0] or amax[1] < ap.mins[1] or amax[2] < ap.mins[2] then
			check = nextc
			continue
		end

		if ap.count == ap.maxcount then
			print("SV_AreaEntities: MAXCOUNT")
			return
		end

		ap.list[ap.count] = check.index
		ap.count += 1
		check = nextc
	end

	if node.axis == -1 then
		return -- terminal node
	end

	-- recurse down both sides
	if ap.maxs[node.axis] > node.dist then
		SV_AreaEntities_r(node.children[0], ap)
	end
	if ap.mins[node.axis] < node.dist then
		SV_AreaEntities_r(node.children[1], ap)
	end
end

function W.SV_AreaEntities(mins, maxs, entityList, maxcount: number): number
	local ap = { mins = mins, maxs = maxs, list = entityList, count = 0, maxcount = maxcount }
	SV_AreaEntities_r(sv_worldSectors[0], ap)
	return ap.count
end

--===========================================================================

local zeroTrace = S.trace_t()

function W.SV_ClipToEntity(trace, start, mins, maxs, endp, entityNum: number, contentmask: number, capsule: boolean)
	local touch = W.SV_GentityNum(entityNum)

	S.copy_trace_t(trace, zeroTrace)

	-- if it doesn't have any brushes of a type we
	-- are looking for, ignore it
	if band(contentmask, touch.r.contents) == 0 then
		trace.fraction = 1.0
		return
	end

	-- might intersect, so do an exact clip
	local clipHandle = W.SV_ClipHandleForEntity(touch)

	local origin = touch.r.currentOrigin
	local angles = touch.r.currentAngles

	if not touch.r.bmodel then
		angles = Q.vec3_origin -- boxes don't rotate
	end

	Collision.TransformedBoxTrace(trace, start, endp, mins or Q.vec3_origin, maxs or Q.vec3_origin, clipHandle, contentmask, origin, angles, capsule)

	if trace.fraction < 1 then
		trace.entityNum = touch.s.number
	end
end

local touchlist = {}
local ctrace = S.trace_t()

local function SV_ClipMoveToEntities(clip)
	local num = W.SV_AreaEntities(clip.boxmins, clip.boxmaxs, touchlist, C.MAX_GENTITIES)

	local passOwnerNum
	if clip.passEntityNum ~= C.ENTITYNUM_NONE then
		passOwnerNum = W.SV_GentityNum(clip.passEntityNum).r.ownerNum
		if passOwnerNum == C.ENTITYNUM_NONE then
			passOwnerNum = -1
		end
	else
		passOwnerNum = -1
	end

	local trace = ctrace
	for i = 0, num - 1 do
		if clip.trace.allsolid then
			return
		end
		local touch = W.SV_GentityNum(touchlist[i])

		-- see if we should ignore this entity
		if clip.passEntityNum ~= C.ENTITYNUM_NONE then
			if touchlist[i] == clip.passEntityNum then
				continue -- don't clip against the pass entity
			end
			if touch.r.ownerNum == clip.passEntityNum then
				continue -- don't clip against own missiles
			end
			if touch.r.ownerNum == passOwnerNum then
				continue -- don't clip against other missiles from our owner
			end
		end

		-- if it doesn't have any brushes of a type we
		-- are looking for, ignore it
		if band(clip.contentmask, touch.r.contents) == 0 then
			continue
		end

		-- might intersect, so do an exact clip
		local clipHandle = W.SV_ClipHandleForEntity(touch)

		local origin = touch.r.currentOrigin
		local angles = touch.r.currentAngles

		if not touch.r.bmodel then
			angles = Q.vec3_origin -- boxes don't rotate
		end

		Collision.TransformedBoxTrace(trace, clip.start, clip["end"], clip.mins, clip.maxs, clipHandle, clip.contentmask, origin, angles, clip.capsule)

		if trace.allsolid then
			clip.trace.allsolid = true
			trace.entityNum = touch.s.number
		elseif trace.startsolid then
			clip.trace.startsolid = true
			trace.entityNum = touch.s.number
		end

		if trace.fraction < clip.trace.fraction then
			-- make sure we keep a startsolid from a previous trace
			local oldStart = clip.trace.startsolid

			trace.entityNum = touch.s.number
			S.copy_trace_t(clip.trace, trace)
			clip.trace.startsolid = clip.trace.startsolid or oldStart
		end
	end
end

local clip = {
	boxmins = vec3(),
	boxmaxs = vec3(),
	mins = nil,
	maxs = nil,
	start = nil,
	["end"] = vec3(),
	trace = S.trace_t(),
	passEntityNum = 0,
	contentmask = 0,
	capsule = false,
}

-- Moves the given mins/maxs volume through the world from start to end.
-- passEntityNum and entities owned by passEntityNum are explicitly not checked.
function W.SV_Trace(results, start, mins, maxs, endp, passEntityNum: number, contentmask: number, capsule: boolean)
	if not mins then
		mins = Q.vec3_origin
	end
	if not maxs then
		maxs = Q.vec3_origin
	end

	S.copy_trace_t(clip.trace, zeroTrace)

	-- clip to world
	Collision.BoxTrace(clip.trace, start, endp, mins, maxs, 0, contentmask, capsule)
	clip.trace.entityNum = if clip.trace.fraction ~= 1.0 then C.ENTITYNUM_WORLD else C.ENTITYNUM_NONE
	if clip.trace.fraction == 0 then
		S.copy_trace_t(results, clip.trace)
		return -- blocked immediately by the world
	end

	clip.contentmask = contentmask
	clip.start = start
	VectorCopy(endp, clip["end"])
	clip.mins = mins
	clip.maxs = maxs
	clip.passEntityNum = passEntityNum
	clip.capsule = capsule

	-- create the bounding box of the entire move
	-- we can limit it to the part of the move not
	-- already clipped off by the world, which can be
	-- a significant savings for line of sight and shot traces
	for i = 0, 2 do
		if endp[i] > start[i] then
			clip.boxmins[i] = f(f(f(clip.start[i] + clip.mins[i]) - 1))
			clip.boxmaxs[i] = f(f(f(clip["end"][i] + clip.maxs[i]) + 1))
		else
			clip.boxmins[i] = f(f(f(clip["end"][i] + clip.mins[i]) - 1))
			clip.boxmaxs[i] = f(f(f(clip.start[i] + clip.maxs[i]) + 1))
		end
	end

	-- clip to other solid entities
	SV_ClipMoveToEntities(clip)

	S.copy_trace_t(results, clip.trace)
end

local ptouch = {}
function W.SV_PointContents(p, passEntityNum: number): number
	-- get base contents from world
	local contents = Collision.PointContents(p, 0)

	-- or in contents from all the other entities
	local num = W.SV_AreaEntities(p, p, ptouch, C.MAX_GENTITIES)

	for i = 0, num - 1 do
		if ptouch[i] == passEntityNum then
			continue
		end
		local hit = W.SV_GentityNum(ptouch[i])
		-- might intersect, so do an exact clip
		local clipHandle = W.SV_ClipHandleForEntity(hit)
		local angles = hit.r.currentAngles
		if not hit.r.bmodel then
			angles = Q.vec3_origin -- boxes don't rotate
		end

		local c2 = Collision.TransformedPointContents(p, clipHandle, hit.r.currentOrigin, angles)

		contents = bor(contents, c2)
	end

	return Q.int32(contents)
end

-- sv_game.c helpers that need the world

function W.SV_SetBrushModel(ent, name: string?)
	if not name then
		error("SV_SetBrushModel: NULL")
	end
	if string.sub(name, 1, 1) ~= "*" then
		error(string.format("SV_SetBrushModel: %s isn't a brush model", name))
	end

	ent.s.modelindex = tonumber(string.match(name, "^%*(%d+)")) or 0
	local h = Collision.InlineModel(ent.s.modelindex)
	Collision.ModelBounds(h, ent.r.mins, ent.r.maxs)
	ent.r.bmodel = true

	ent.r.contents = -1 -- we don't know exactly what is in the brushes

	W.SV_LinkEntity(ent) -- FIXME: remove
end

-- mask[cluster >> 3] & (1 << (cluster & 7)), reading the visibility
-- buffer the way the C pointer would (cluster -1 reads the byte before)
local function pvsBit(mask: buffer?, off: number, cluster: number): boolean
	if not mask then
		return true
	end
	local idx = off + bit32.arshift(cluster, 3)
	if idx < 0 or idx >= buffer.len(mask) then
		return false
	end
	return band(buffer.readu8(mask, idx), lshift(1, band(cluster, 7))) ~= 0
end
W.pvsBit = pvsBit

-- Also checks portalareas so that doors block sight
function W.SV_inPVS(p1, p2): boolean
	local leafnum = Collision.PointLeafnum(p1)
	local cluster = Collision.LeafCluster(leafnum)
	local area1 = Collision.LeafArea(leafnum)
	local mask, off = Collision.ClusterPVS(cluster)
	leafnum = Collision.PointLeafnum(p2)
	cluster = Collision.LeafCluster(leafnum)
	local area2 = Collision.LeafArea(leafnum)
	if mask and not pvsBit(mask, off, cluster) then
		return false
	end
	if not Collision.AreasConnected(area1, area2) then
		return false -- a door blocks sight
	end
	return true
end

-- Does NOT check portalareas
function W.SV_inPVSIgnorePortals(p1, p2): boolean
	local leafnum = Collision.PointLeafnum(p1)
	local cluster = Collision.LeafCluster(leafnum)
	local mask, off = Collision.ClusterPVS(cluster)
	leafnum = Collision.PointLeafnum(p2)
	cluster = Collision.LeafCluster(leafnum)
	if mask and not pvsBit(mask, off, cluster) then
		return false
	end
	return true
end

function W.SV_AdjustAreaPortalState(ent, open: boolean)
	local svEnt = W.SV_SvEntityForGentity(ent)
	if svEnt.areanum2 == -1 then
		return
	end
	Collision.AdjustAreaPortalState(svEnt.areanum, svEnt.areanum2, open)
end

local etrace = S.trace_t()
function W.SV_EntityContact(mins, maxs, gEnt, capsule: boolean): boolean
	-- check for exact collision
	local origin = gEnt.r.currentOrigin
	local angles = gEnt.r.currentAngles

	local ch = W.SV_ClipHandleForEntity(gEnt)
	Collision.TransformedBoxTrace(etrace, Q.vec3_origin, Q.vec3_origin, mins, maxs, ch, -1, origin, angles, capsule)

	return etrace.startsolid
end

return W
