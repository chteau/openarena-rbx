--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_goal.c, part 1 of 3).

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
-- Luau port of be_ai_goal.c (botlib/be_ai_goal.c, part 1 of 3). Goal AI: item config, level items, info entities.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("be_ai_goal")

SF.BOTFILESBASEFOLDER = "botfiles"

--DROPPEDWEIGHT is defined (UNDECIDEDFUZZY only with RANDOMIZE)
SF.DROPPEDWEIGHT = true
--minimum avoid goal time
SF.AVOID_MINIMUM_TIME = 10
--default avoid goal time
SF.AVOID_DEFAULT_TIME = 30
--avoid dropped goal time
SF.AVOID_DROPPED_TIME = 10
SF.TRAVELTIME_SCALE = 0.01
--item flags
SF.IFL_NOTFREE = 1 --not in free for all
SF.IFL_NOTTEAM = 2 --not in team play
SF.IFL_NOTSINGLE = 4 --not in single player
SF.IFL_NOTBOT = 8 --bot should never go for this
SF.IFL_ROAM = 16 --bot roam goal

local IFL_NOTFREE = 1
local IFL_NOTTEAM = 2
local IFL_NOTSINGLE = 4
local IFL_NOTBOT = 8
local IFL_ROAM = 16

--FIXME: these are game specific
SF.GT_FFA = 0
SF.GT_TOURNAMENT = 1
SF.GT_SINGLE_PLAYER = 2
SF.GT_TEAM = 3
SF.GT_CTF = 4
SF.GT_MAX_GAME_TYPE = 5

local function fdef(name, ftype, maxarray)
	local fd = SB.fielddef_t()
	fd.name = name
	fd.offset = 0
	fd.type = ftype
	fd.maxarray = maxarray or 0
	return fd
end

SF.iteminfo_fields = {
	[0] = fdef("name", BC.FT_STRING),
	fdef("model", BC.FT_STRING),
	fdef("modelindex", BC.FT_INT),
	fdef("type", BC.FT_INT),
	fdef("index", BC.FT_INT),
	fdef("respawntime", BC.FT_FLOAT),
	fdef("mins", bit32.bor(BC.FT_FLOAT, BC.FT_ARRAY), 3),
	fdef("maxs", bit32.bor(BC.FT_FLOAT, BC.FT_ARRAY), 3),
	SB.fielddef_t(),
}

SF.iteminfo_struct = SB.structdef_t()
SF.iteminfo_struct.size = 0
SF.iteminfo_struct.fields = SF.iteminfo_fields

SF.botgoalstates = {}
--item configuration
SF.itemconfig = nil
--level items
SF.levelitemheap = nil
SF.freelevelitems = nil
SF.levelitems = nil
SF.numlevelitems = 0
--map locations
SF.maplocations = nil
--camp spots
SF.campspots = nil
--the game type
SF.g_gametype = 0
--additional dropped item weight
SF.droppedweight = nil

function B.BotGoalStateFromHandle(handle)
	if handle <= 0 or handle > BC.MAX_CLIENTS then
		B.botimport.Print(BC.PRT_FATAL, "goal state handle %d out of range\n", handle)
		return nil
	end
	if SF.botgoalstates[handle] == nil then
		B.botimport.Print(BC.PRT_FATAL, "invalid goal state %d\n", handle)
		return nil
	end
	return SF.botgoalstates[handle]
end

function B.BotInterbreedGoalFuzzyLogic(parent1, parent2, child)
	local p1 = B.BotGoalStateFromHandle(parent1)
	local p2 = B.BotGoalStateFromHandle(parent2)
	local c = B.BotGoalStateFromHandle(child)

	if p1 == nil or p2 == nil or c == nil then
		return
	end

	B.InterbreedWeightConfigs(p1.itemweightconfig, p2.itemweightconfig, c.itemweightconfig)
end

function B.BotSaveGoalFuzzyLogic(goalstate, filename)
end

function B.BotMutateGoalFuzzyLogic(goalstate, range)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	B.EvolveWeightConfig(gs.itemweightconfig)
end

function B.LoadItemConfig(filename)
	local token = SB.token_t()

	local max_iteminfo = Q.trunc(B.LibVarValue("max_iteminfo", "256"))
	if max_iteminfo < 0 then
		B.botimport.Print(BC.PRT_ERROR, "max_iteminfo = %d\n", max_iteminfo)
		max_iteminfo = 256
		B.LibVarSet("max_iteminfo", "256")
	end

	local path = QS.Q_strncpyz(filename, BC.MAX_QPATH)
	B.PC_SetBaseFolder(SF.BOTFILESBASEFOLDER)
	local source = B.LoadSourceFile(path)
	if source == nil then
		B.botimport.Print(BC.PRT_ERROR, "couldn't load %s\n", path)
		return nil
	end
	--initialize item config
	local ic = SB.itemconfig_t()
	local iteminfo = {}
	for k = 0, max_iteminfo - 1 do
		iteminfo[k] = SB.iteminfo_t()
	end
	ic.iteminfo = iteminfo
	ic.numiteminfo = 0
	--parse the item config file
	while B.PC_ReadToken(source, token) ~= 0 do
		if token.string == "iteminfo" then
			if ic.numiteminfo >= max_iteminfo then
				B.SourceError(source, "more than %d item info defined", max_iteminfo)
				B.FreeSource(source)
				return nil
			end
			local ii = ic.iteminfo[ic.numiteminfo]
			SB.copy_iteminfo_t(ii, SB.iteminfo_t())
			if B.PC_ExpectTokenType(source, BC.TT_STRING, 0, token) == 0 then
				B.FreeSource(source)
				return nil
			end
			token.string = B.StripDoubleQuotes(token.string)
			ii.classname = QS.Q_strncpyz(token.string, 32)
			if B.ReadStructure(source, SF.iteminfo_struct, ii) == 0 then
				B.FreeSource(source)
				return nil
			end
			ii.number = ic.numiteminfo
			ic.numiteminfo = ic.numiteminfo + 1
		else
			B.SourceError(source, "unknown definition %s", token.string)
			B.FreeSource(source)
			return nil
		end
	end
	B.FreeSource(source)
	--
	if ic.numiteminfo == 0 then
		B.botimport.Print(BC.PRT_WARNING, "no item info loaded\n")
	end
	B.botimport.Print(BC.PRT_MESSAGE, "loaded %s\n", path)
	return ic
end

-- index to find the weight function of an iteminfo
function B.ItemWeightIndex(iwc, ic)
	--initialize item weight index
	local index = B.zeros(ic.numiteminfo)

	for i = 0, ic.numiteminfo - 1 do
		index[i] = B.FindFuzzyWeight(iwc, ic.iteminfo[i].classname)
		if index[i] < 0 then
			B.Log_Write("item info %d \"%s\" has no fuzzy weight\r\n", i, ic.iteminfo[i].classname)
		end
	end
	return index
end

function B.InitLevelItemHeap()
	SF.levelitemheap = nil

	local max_levelitems = Q.trunc(B.LibVarValue("max_levelitems", "256"))
	local heap = {}
	for i = 0, max_levelitems - 1 do
		heap[i] = SB.levelitem_t()
	end
	SF.levelitemheap = heap

	for i = 0, max_levelitems - 2 do
		heap[i].next = heap[i + 1]
	end
	heap[max_levelitems - 1].next = nil
	--
	SF.freelevelitems = heap[0]
end

function B.AllocLevelItem()
	local li = SF.freelevelitems
	if li == nil then
		B.botimport.Print(BC.PRT_FATAL, "out of level items\n")
		return nil
	end
	--
	SF.freelevelitems = SF.freelevelitems.next
	SB.copy_levelitem_t(li, SB.levelitem_t())
	li.prev = nil
	li.next = nil
	return li
end

function B.FreeLevelItem(li)
	li.next = SF.freelevelitems
	SF.freelevelitems = li
end

function B.AddLevelItemToList(li)
	if SF.levelitems ~= nil then
		SF.levelitems.prev = li
	end
	li.prev = nil
	li.next = SF.levelitems
	SF.levelitems = li
end

function B.RemoveLevelItemFromList(li)
	if li.prev ~= nil then
		li.prev.next = li.next
	else
		SF.levelitems = li.next
	end
	if li.next ~= nil then
		li.next.prev = li.prev
	end
end

function B.BotFreeInfoEntities()
	SF.maplocations = nil
	SF.campspots = nil
end

function B.BotInitInfoEntities()
	B.BotFreeInfoEntities()
	--
	local numlocations = 0
	local numcampspots = 0
	local ent = B.AAS_NextBSPEntity(0)
	while ent ~= 0 do
		local ok, classname = B.AAS_ValueForBSPEpairKey(ent, "classname", BC.MAX_EPAIRKEY)
		if ok ~= 0 then
			--map locations
			if classname == "target_location" then
				local ml = SB.maplocation_t()
				B.AAS_VectorForBSPEpairKey(ent, "origin", ml.origin)
				local _, name = B.AAS_ValueForBSPEpairKey(ent, "message", BC.MAX_EPAIRKEY)
				ml.name = name
				ml.areanum = B.AAS_PointAreaNum(ml.origin)
				ml.next = SF.maplocations
				SF.maplocations = ml
				numlocations = numlocations + 1
			--camp spots
			elseif classname == "info_camp" then
				local cs = SB.campspot_t()
				B.AAS_VectorForBSPEpairKey(ent, "origin", cs.origin)
				--cs->origin[2] += 16;
				local _, name = B.AAS_ValueForBSPEpairKey(ent, "message", BC.MAX_EPAIRKEY)
				cs.name = name
				local fok, fval = B.AAS_FloatForBSPEpairKey(ent, "range")
				if fok ~= 0 then cs.range = fval end
				fok, fval = B.AAS_FloatForBSPEpairKey(ent, "weight")
				if fok ~= 0 then cs.weight = fval end
				fok, fval = B.AAS_FloatForBSPEpairKey(ent, "wait")
				if fok ~= 0 then cs.wait = fval end
				fok, fval = B.AAS_FloatForBSPEpairKey(ent, "random")
				if fok ~= 0 then cs.random = fval end
				cs.areanum = B.AAS_PointAreaNum(cs.origin)
				if cs.areanum == 0 then
					B.botimport.Print(BC.PRT_MESSAGE, "camp spot at %1.1f %1.1f %1.1f in solid\n", cs.origin[0], cs.origin[1], cs.origin[2])
				else
					cs.next = SF.campspots
					SF.campspots = cs
					numcampspots = numcampspots + 1
				end
			end
		end
		ent = B.AAS_NextBSPEntity(ent)
	end
	if B.botDeveloper then
		B.botimport.Print(BC.PRT_MESSAGE, "%d map locations\n", numlocations)
		B.botimport.Print(BC.PRT_MESSAGE, "%d camp spots\n", numcampspots)
	end
end

function B.BotInitLevelItems()
	local origin = { [0] = 0, 0, 0 }
	local end_ = { [0] = 0, 0, 0 }
	local value = 0

	--initialize the map locations and camp spots
	B.BotInitInfoEntities()

	--initialize the level item heap
	B.InitLevelItemHeap()
	SF.levelitems = nil
	SF.numlevelitems = 0
	--
	local ic = SF.itemconfig
	if ic == nil then
		return
	end

	--if there's no AAS file loaded
	if B.AAS_Loaded() == 0 then
		return
	end

	--validate the modelindexes of the item info
	for i = 0, ic.numiteminfo - 1 do
		if ic.iteminfo[i].modelindex == 0 then
			B.Log_Write("item %s has modelindex 0", ic.iteminfo[i].classname)
		end
	end

	local ent = B.AAS_NextBSPEntity(0)
	while ent ~= 0 do
		local ok, classname = B.AAS_ValueForBSPEpairKey(ent, "classname", BC.MAX_EPAIRKEY)
		if ok ~= 0 then
			--
			local spawnflags = 0
			local iok, ival = B.AAS_IntForBSPEpairKey(ent, "spawnflags")
			if iok ~= 0 then spawnflags = ival end
			--
			local i = 0
			while i < ic.numiteminfo do
				if classname == ic.iteminfo[i].classname then
					break
				end
				i = i + 1
			end
			if i >= ic.numiteminfo then
				B.Log_Write("entity %s unknown item\r\n", classname)
			elseif B.AAS_VectorForBSPEpairKey(ent, "origin", origin) == 0 then
				--get the origin of the item
				B.botimport.Print(BC.PRT_ERROR, "item %s without origin\n", classname)
			else
				--
				local goalareanum = 0
				local skip = false
				--if it is a floating item
				if bit32.band(spawnflags, 1) ~= 0 then
					--if the item is not floating in water
					if bit32.band(B.AAS_PointContents(origin), BC.CONTENTS_WATER) == 0 then
						Q.VectorCopy(origin, end_)
						end_[2] = Q.f(end_[2] - 32)
						local trace = B.AAS_Trace(origin, ic.iteminfo[i].mins, ic.iteminfo[i].maxs, end_, -1, bit32.bor(BC.CONTENTS_SOLID, BC.CONTENTS_PLAYERCLIP))
						--if the item not near the ground
						if trace.fraction >= 1 then
							--if the item is not reachable from a jumppad
							goalareanum = B.AAS_BestReachableFromJumpPadArea(origin, ic.iteminfo[i].mins, ic.iteminfo[i].maxs)
							B.Log_Write("item %s reachable from jumppad area %d\r\n", ic.iteminfo[i].classname, goalareanum)
							if goalareanum == 0 then
								skip = true
							end
						end
					end
				end

				if not skip then
					local li = B.AllocLevelItem()
					if li == nil then
						return
					end
					--
					SF.numlevelitems = SF.numlevelitems + 1
					li.number = SF.numlevelitems
					li.timeout = 0
					li.entitynum = 0
					--
					li.flags = 0
					iok, ival = B.AAS_IntForBSPEpairKey(ent, "notfree")
					if iok ~= 0 then value = ival end
					if value ~= 0 then li.flags = bit32.bor(li.flags, IFL_NOTFREE) end
					iok, ival = B.AAS_IntForBSPEpairKey(ent, "notteam")
					if iok ~= 0 then value = ival end
					if value ~= 0 then li.flags = bit32.bor(li.flags, IFL_NOTTEAM) end
					iok, ival = B.AAS_IntForBSPEpairKey(ent, "notsingle")
					if iok ~= 0 then value = ival end
					if value ~= 0 then li.flags = bit32.bor(li.flags, IFL_NOTSINGLE) end
					iok, ival = B.AAS_IntForBSPEpairKey(ent, "notbot")
					if iok ~= 0 then value = ival end
					if value ~= 0 then li.flags = bit32.bor(li.flags, IFL_NOTBOT) end
					if classname == "item_botroam" then
						li.flags = bit32.bor(li.flags, IFL_ROAM)
						local fok, fval = B.AAS_FloatForBSPEpairKey(ent, "weight")
						if fok ~= 0 then li.weight = fval end
					end
					--if not a stationary item
					if bit32.band(spawnflags, 1) == 0 then
						if B.AAS_DropToFloor(origin, ic.iteminfo[i].mins, ic.iteminfo[i].maxs) == 0 then
							B.botimport.Print(BC.PRT_MESSAGE, "%s in solid at (%1.1f %1.1f %1.1f)\n",
								classname, origin[0], origin[1], origin[2])
						end
					end
					--item info of the level item
					li.iteminfo = i
					--origin of the item
					Q.VectorCopy(origin, li.origin)
					--
					if goalareanum ~= 0 then
						li.goalareanum = goalareanum
						Q.VectorCopy(origin, li.goalorigin)
					else
						--get the item goal area and goal origin
						li.goalareanum = B.AAS_BestReachableArea(origin,
							ic.iteminfo[i].mins, ic.iteminfo[i].maxs,
							li.goalorigin)
						if li.goalareanum == 0 then
							B.botimport.Print(BC.PRT_MESSAGE, "%s not reachable for bots at (%1.1f %1.1f %1.1f)\n",
								classname, origin[0], origin[1], origin[2])
						end
					end
					--
					B.AddLevelItemToList(li)
				end
			end
		end
		ent = B.AAS_NextBSPEntity(ent)
	end
	B.botimport.Print(BC.PRT_MESSAGE, "found %d level items\n", SF.numlevelitems)
end

return nil
