--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_entity.c).

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
-- Luau port of be_aas_entity.c. AAS entities.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

--FIXME: these might change
local ET_MOVER = 4

function B.AAS_UpdateEntity(entnum, state)
	local aasworld = B.aasworld
	local relink
	local absmins = { [0] = 0, 0, 0 }
	local absmaxs = { [0] = 0, 0, 0 }

	if aasworld.loaded == 0 then
		B.botimport.Print(BC.PRT_MESSAGE, "AAS_UpdateEntity: not loaded\n")
		return BC.BLERR_NOAASFILE
	end

	local ent = aasworld.entities[entnum]

	if state == nil then
		--unlink the entity
		B.AAS_UnlinkFromAreas(ent.areas)
		--unlink the entity from the BSP leaves
		B.AAS_UnlinkFromBSPLeaves(ent.leaves)
		ent.areas = nil
		ent.leaves = nil
		return BC.BLERR_NOERROR
	end

	ent.i.update_time = Q.f(B.AAS_Time() - ent.i.ltime)
	ent.i.type = state.type
	ent.i.flags = state.flags
	ent.i.ltime = B.AAS_Time()
	Q.VectorCopy(ent.i.origin, ent.i.lastvisorigin)
	Q.VectorCopy(state.old_origin, ent.i.old_origin)
	ent.i.solid = state.solid
	ent.i.groundent = state.groundent
	ent.i.modelindex = state.modelindex
	ent.i.modelindex2 = state.modelindex2
	ent.i.frame = state.frame
	ent.i.event = state.event
	ent.i.eventParm = state.eventParm
	ent.i.powerups = state.powerups
	ent.i.weapon = state.weapon
	ent.i.legsAnim = state.legsAnim
	ent.i.torsoAnim = state.torsoAnim
	--number of the entity
	ent.i.number = entnum
	--updated so set valid flag
	ent.i.valid = 1
	--link everything the first frame
	if aasworld.numframes == 1 then
		relink = true
	else
		relink = false
	end
	if ent.i.solid == BC.SOLID_BSP then
		--if the angles of the model changed
		if not Q.VectorCompare(state.angles, ent.i.angles) then
			Q.VectorCopy(state.angles, ent.i.angles)
			relink = true
		end
		--get the mins and maxs of the model
		--FIXME: rotate mins and maxs
		B.AAS_BSPModelMinsMaxsOrigin(ent.i.modelindex, ent.i.angles, ent.i.mins, ent.i.maxs, nil)
	elseif ent.i.solid == BC.SOLID_BBOX then
		--if the bounding box size changed
		if not Q.VectorCompare(state.mins, ent.i.mins) or not Q.VectorCompare(state.maxs, ent.i.maxs) then
			Q.VectorCopy(state.mins, ent.i.mins)
			Q.VectorCopy(state.maxs, ent.i.maxs)
			relink = true
		end
		Q.VectorCopy(state.angles, ent.i.angles)
	end
	--if the origin changed
	if not Q.VectorCompare(state.origin, ent.i.origin) then
		Q.VectorCopy(state.origin, ent.i.origin)
		relink = true
	end
	--if the entity should be relinked
	if relink then
		--don't link the world model
		if entnum ~= BC.ENTITYNUM_WORLD then
			--absolute mins and maxs
			Q.VectorAdd(ent.i.mins, ent.i.origin, absmins)
			Q.VectorAdd(ent.i.maxs, ent.i.origin, absmaxs)
			--unlink the entity
			B.AAS_UnlinkFromAreas(ent.areas)
			--relink the entity to the AAS areas (use the larges bbox)
			ent.areas = B.AAS_LinkEntityClientBBox(absmins, absmaxs, entnum, BC.PRESENCE_NORMAL)
			--unlink the entity from the BSP leaves
			B.AAS_UnlinkFromBSPLeaves(ent.leaves)
			--link the entity to the world BSP tree
			ent.leaves = B.AAS_BSPLinkEntity(absmins, absmaxs, entnum, 0)
		end
	end
	return BC.BLERR_NOERROR
end

function B.AAS_EntityInfo(entnum, info)
	local aasworld = B.aasworld
	if aasworld.initialized == 0 then
		B.botimport.Print(BC.PRT_FATAL, "AAS_EntityInfo: aasworld not initialized\n")
		SB.copy_aas_entityinfo_t(info, SB.aas_entityinfo_t())
		return
	end

	if entnum < 0 or entnum >= aasworld.maxentities then
		B.botimport.Print(BC.PRT_FATAL, "AAS_EntityInfo: entnum %d out of range\n", entnum)
		SB.copy_aas_entityinfo_t(info, SB.aas_entityinfo_t())
		return
	end

	SB.copy_aas_entityinfo_t(info, aasworld.entities[entnum].i)
end

function B.AAS_EntityOrigin(entnum, origin)
	local aasworld = B.aasworld
	if entnum < 0 or entnum >= aasworld.maxentities then
		B.botimport.Print(BC.PRT_FATAL, "AAS_EntityOrigin: entnum %d out of range\n", entnum)
		origin[0], origin[1], origin[2] = 0, 0, 0
		return
	end

	Q.VectorCopy(aasworld.entities[entnum].i.origin, origin)
end

function B.AAS_EntityModelindex(entnum)
	local aasworld = B.aasworld
	if entnum < 0 or entnum >= aasworld.maxentities then
		B.botimport.Print(BC.PRT_FATAL, "AAS_EntityModelindex: entnum %d out of range\n", entnum)
		return 0
	end
	return aasworld.entities[entnum].i.modelindex
end

function B.AAS_EntityType(entnum)
	local aasworld = B.aasworld
	if aasworld.initialized == 0 then
		return 0
	end

	if entnum < 0 or entnum >= aasworld.maxentities then
		B.botimport.Print(BC.PRT_FATAL, "AAS_EntityType: entnum %d out of range\n", entnum)
		return 0
	end
	return aasworld.entities[entnum].i.type
end

function B.AAS_EntityModelNum(entnum)
	local aasworld = B.aasworld
	if aasworld.initialized == 0 then
		return 0
	end

	if entnum < 0 or entnum >= aasworld.maxentities then
		B.botimport.Print(BC.PRT_FATAL, "AAS_EntityModelNum: entnum %d out of range\n", entnum)
		return 0
	end
	return aasworld.entities[entnum].i.modelindex
end

function B.AAS_OriginOfMoverWithModelNum(modelnum, origin)
	local aasworld = B.aasworld
	for i = 0, aasworld.maxentities - 1 do
		local ent = aasworld.entities[i]
		if ent.i.type == ET_MOVER then
			if ent.i.modelindex == modelnum then
				Q.VectorCopy(ent.i.origin, origin)
				return 1
			end
		end
	end
	return 0
end

function B.AAS_EntitySize(entnum, mins, maxs)
	local aasworld = B.aasworld
	if aasworld.initialized == 0 then
		return
	end

	if entnum < 0 or entnum >= aasworld.maxentities then
		B.botimport.Print(BC.PRT_FATAL, "AAS_EntitySize: entnum %d out of range\n", entnum)
		return
	end

	local ent = aasworld.entities[entnum]
	Q.VectorCopy(ent.i.mins, mins)
	Q.VectorCopy(ent.i.maxs, maxs)
end

function B.AAS_EntityBSPData(entnum, entdata)
	local aasworld = B.aasworld
	local ent = aasworld.entities[entnum]
	Q.VectorCopy(ent.i.origin, entdata.origin)
	Q.VectorCopy(ent.i.angles, entdata.angles)
	Q.VectorAdd(ent.i.origin, ent.i.mins, entdata.absmins)
	Q.VectorAdd(ent.i.origin, ent.i.maxs, entdata.absmaxs)
	entdata.solid = ent.i.solid
	entdata.modelnum = ent.i.modelindex - 1
end

function B.AAS_ResetEntityLinks()
	local aasworld = B.aasworld
	for i = 0, aasworld.maxentities - 1 do
		aasworld.entities[i].areas = nil
		aasworld.entities[i].leaves = nil
	end
end

function B.AAS_InvalidateEntities()
	local aasworld = B.aasworld
	for i = 0, aasworld.maxentities - 1 do
		aasworld.entities[i].i.valid = 0
		aasworld.entities[i].i.number = i
	end
end

function B.AAS_UnlinkInvalidEntities()
	local aasworld = B.aasworld
	for i = 0, aasworld.maxentities - 1 do
		local ent = aasworld.entities[i]
		if ent.i.valid == 0 then
			B.AAS_UnlinkFromAreas(ent.areas)
			ent.areas = nil
			B.AAS_UnlinkFromBSPLeaves(ent.leaves)
			ent.leaves = nil
		end
	end
end

function B.AAS_NearestEntity(origin, modelindex)
	local aasworld = B.aasworld
	local dir = { [0] = 0, 0, 0 }

	local bestentnum = 0
	local bestdist = 99999
	for i = 0, aasworld.maxentities - 1 do
		local ent = aasworld.entities[i]
		if ent.i.modelindex ~= modelindex then
			continue
		end
		Q.VectorSubtract(ent.i.origin, origin, dir)
		if math.abs(dir[0]) < 40 then
			if math.abs(dir[1]) < 40 then
				local dist = Q.VectorLength(dir)
				if dist < bestdist then
					bestdist = dist
					bestentnum = i
				end
			end
		end
	end
	return bestentnum
end

function B.AAS_BestReachableEntityArea(entnum)
	local ent = B.aasworld.entities[entnum]
	return B.AAS_BestReachableLinkArea(ent.areas)
end

function B.AAS_NextEntity(entnum)
	local aasworld = B.aasworld
	if aasworld.loaded == 0 then
		return 0
	end

	if entnum < 0 then
		entnum = -1
	end
	entnum = entnum + 1
	while entnum < aasworld.maxentities do
		if aasworld.entities[entnum].i.valid ~= 0 then
			return entnum
		end
		entnum = entnum + 1
	end
	return 0
end

return nil
