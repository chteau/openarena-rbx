--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_goal.c, part 2 of 3).

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
-- Luau port of be_ai_goal.c (botlib/be_ai_goal.c, part 2 of 3): goal names, avoid goals, level item goals, entity items, goal stack push.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("be_ai_goal")

local MAX_AVOIDGOALS = 256
local MAX_GOALSTACK = 8
local AVOID_MINIMUM_TIME = 10
local AVOID_DEFAULT_TIME = 30
local IFL_NOTFREE = 1
local IFL_NOTTEAM = 2
local IFL_NOTSINGLE = 4
local IFL_NOTBOT = 8
local GFL_ITEM = 1
local GFL_DROPPED = 4
local GT_SINGLE_PLAYER = 2
local GT_TEAM = 3
local ET_ITEM = 2

function B.BotGoalName(number, size)
	local itemconfig = SF.itemconfig
	if itemconfig == nil then
		return ""
	end
	local li = SF.levelitems
	while li ~= nil do
		if li.number == number then
			return QS.Q_strncpyz(itemconfig.iteminfo[li.iteminfo].name, size)
		end
		li = li.next
	end
	return ""
end

function B.BotResetAvoidGoals(goalstate)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	for i = 0, MAX_AVOIDGOALS - 1 do
		gs.avoidgoals[i] = 0
		gs.avoidgoaltimes[i] = 0
	end
end

function B.BotDumpAvoidGoals(goalstate)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	for i = 0, MAX_AVOIDGOALS - 1 do
		if gs.avoidgoaltimes[i] >= B.AAS_Time() then
			local name = B.BotGoalName(gs.avoidgoals[i], 32)
			B.Log_Write("avoid goal %s, number %d for %f seconds", name,
				gs.avoidgoals[i], gs.avoidgoaltimes[i] - B.AAS_Time())
		end
	end
end

function B.BotAddToAvoidGoals(gs, number, avoidtime)
	for i = 0, MAX_AVOIDGOALS - 1 do
		if gs.avoidgoals[i] == number then
			gs.avoidgoals[i] = number
			gs.avoidgoaltimes[i] = B.AAS_Time() + avoidtime
			return
		end
	end

	for i = 0, MAX_AVOIDGOALS - 1 do
		if gs.avoidgoaltimes[i] < B.AAS_Time() then
			gs.avoidgoals[i] = number
			gs.avoidgoaltimes[i] = B.AAS_Time() + avoidtime
			return
		end
	end
end

function B.BotRemoveFromAvoidGoals(goalstate, number)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	for i = 0, MAX_AVOIDGOALS - 1 do
		if gs.avoidgoals[i] == number and gs.avoidgoaltimes[i] >= B.AAS_Time() then
			gs.avoidgoaltimes[i] = 0
			return
		end
	end
end

function B.BotAvoidGoalTime(goalstate, number)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return 0
	end
	for i = 0, MAX_AVOIDGOALS - 1 do
		if gs.avoidgoals[i] == number and gs.avoidgoaltimes[i] >= B.AAS_Time() then
			return gs.avoidgoaltimes[i] - B.AAS_Time()
		end
	end
	return 0
end

function B.BotSetAvoidGoalTime(goalstate, number, avoidtime)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	if avoidtime < 0 then
		local itemconfig = SF.itemconfig
		if itemconfig == nil then
			return
		end
		local li = SF.levelitems
		while li ~= nil do
			if li.number == number then
				avoidtime = itemconfig.iteminfo[li.iteminfo].respawntime
				if avoidtime == 0 then
					avoidtime = AVOID_DEFAULT_TIME
				end
				if avoidtime < AVOID_MINIMUM_TIME then
					avoidtime = AVOID_MINIMUM_TIME
				end
				B.BotAddToAvoidGoals(gs, number, avoidtime)
				return
			end
			li = li.next
		end
		return
	else
		B.BotAddToAvoidGoals(gs, number, avoidtime)
	end
end

function B.BotGetLevelItemGoal(index, name, goal)
	local itemconfig = SF.itemconfig
	if itemconfig == nil then
		return -1
	end
	local li = SF.levelitems
	if index >= 0 then
		while li ~= nil do
			if li.number == index then
				li = li.next
				break
			end
			li = li.next
		end
	end
	while li ~= nil do
		local skip = false
		if SF.g_gametype == GT_SINGLE_PLAYER then
			if bit32.band(li.flags, IFL_NOTSINGLE) ~= 0 then
				skip = true
			end
		elseif SF.g_gametype >= GT_TEAM then
			if bit32.band(li.flags, IFL_NOTTEAM) ~= 0 then
				skip = true
			end
		else
			if bit32.band(li.flags, IFL_NOTFREE) ~= 0 then
				skip = true
			end
		end
		if not skip and bit32.band(li.flags, IFL_NOTBOT) ~= 0 then
			skip = true
		end
		if not skip and QS.Q_stricmp(name, itemconfig.iteminfo[li.iteminfo].name) == 0 then
			goal.areanum = li.goalareanum
			Q.VectorCopy(li.goalorigin, goal.origin)
			goal.entitynum = li.entitynum
			Q.VectorCopy(itemconfig.iteminfo[li.iteminfo].mins, goal.mins)
			Q.VectorCopy(itemconfig.iteminfo[li.iteminfo].maxs, goal.maxs)
			goal.number = li.number
			goal.flags = GFL_ITEM
			if li.timeout ~= 0 then
				goal.flags = bit32.bor(goal.flags, GFL_DROPPED)
			end
			goal.iteminfo = li.iteminfo
			return li.number
		end
		li = li.next
	end
	return -1
end

function B.BotGetMapLocationGoal(name, goal)
	local mins = { [0] = -8, -8, -8 }
	local maxs = { [0] = 8, 8, 8 }

	local ml = SF.maplocations
	while ml ~= nil do
		if QS.Q_stricmp(ml.name, name) == 0 then
			goal.areanum = ml.areanum
			Q.VectorCopy(ml.origin, goal.origin)
			goal.entitynum = 0
			Q.VectorCopy(mins, goal.mins)
			Q.VectorCopy(maxs, goal.maxs)
			goal.number = 0
			goal.flags = 0
			goal.iteminfo = 0
			return true
		end
		ml = ml.next
	end
	return false
end

function B.BotGetNextCampSpotGoal(num, goal)
	local mins = { [0] = -8, -8, -8 }
	local maxs = { [0] = 8, 8, 8 }

	if num < 0 then
		num = 0
	end
	local i = num
	local cs = SF.campspots
	while cs ~= nil do
		i = i - 1
		if i < 0 then
			goal.areanum = cs.areanum
			Q.VectorCopy(cs.origin, goal.origin)
			goal.entitynum = 0
			Q.VectorCopy(mins, goal.mins)
			Q.VectorCopy(maxs, goal.maxs)
			goal.number = 0
			goal.flags = 0
			goal.iteminfo = 0
			return num + 1
		end
		cs = cs.next
	end
	return 0
end

function B.BotFindEntityForLevelItem(li)
	local ic = SF.itemconfig
	if SF.itemconfig == nil then
		return
	end
	local entinfo = SB.aas_entityinfo_t()
	local dir = { [0] = 0, 0, 0 }
	local ent = B.AAS_NextEntity(0)
	while ent ~= 0 do
		local modelindex = B.AAS_EntityModelindex(ent)
		if modelindex ~= 0 then
			B.AAS_EntityInfo(ent, entinfo)
			if not (entinfo.origin[0] ~= entinfo.lastvisorigin[0] or
				entinfo.origin[1] ~= entinfo.lastvisorigin[1] or
				entinfo.origin[2] ~= entinfo.lastvisorigin[2]) then
				if ic.iteminfo[li.iteminfo].modelindex == modelindex then
					Q.VectorSubtract(li.origin, entinfo.origin, dir)
					if Q.VectorLength(dir) < 30 then
						li.entitynum = ent
					end
				end
			end
		end
		ent = B.AAS_NextEntity(ent)
	end
end

function B.BotUpdateEntityItems()
	local dir = { [0] = 0, 0, 0 }
	local entinfo = SB.aas_entityinfo_t()

	local li = SF.levelitems
	while li ~= nil do
		local nextli = li.next
		if li.timeout ~= 0 then
			if li.timeout < B.AAS_Time() then
				B.RemoveLevelItemFromList(li)
				B.FreeLevelItem(li)
			end
		end
		li = nextli
	end
	local ic = SF.itemconfig
	if SF.itemconfig == nil then
		return
	end

	local ent = B.AAS_NextEntity(0)
	while ent ~= 0 do
		repeat
			if B.AAS_EntityType(ent) ~= ET_ITEM then
				break
			end
			local modelindex = B.AAS_EntityModelindex(ent)
			if modelindex == 0 then
				break
			end
			B.AAS_EntityInfo(ent, entinfo)
			if entinfo.origin[0] ~= entinfo.lastvisorigin[0] or
				entinfo.origin[1] ~= entinfo.lastvisorigin[1] or
				entinfo.origin[2] ~= entinfo.lastvisorigin[2] then
				break
			end
			li = SF.levelitems
			while li ~= nil do
				if li.entitynum ~= 0 and li.entitynum == ent then
					if ic.iteminfo[li.iteminfo].modelindex ~= modelindex then
						B.RemoveLevelItemFromList(li)
						B.FreeLevelItem(li)
						li = nil
						break
					else
						if entinfo.origin[0] ~= li.origin[0] or
							entinfo.origin[1] ~= li.origin[1] or
							entinfo.origin[2] ~= li.origin[2] then
							Q.VectorCopy(entinfo.origin, li.origin)
							li.goalareanum = B.AAS_BestReachableArea(li.origin,
								ic.iteminfo[li.iteminfo].mins, ic.iteminfo[li.iteminfo].maxs,
								li.goalorigin)
						end
						break
					end
				end
				li = li.next
			end
			if li ~= nil then
				break
			end
			li = SF.levelitems
			while li ~= nil do
				local skip = false
				if li.entitynum ~= 0 then
					skip = true
				elseif SF.g_gametype == GT_SINGLE_PLAYER then
					if bit32.band(li.flags, IFL_NOTSINGLE) ~= 0 then
						skip = true
					end
				elseif SF.g_gametype >= GT_TEAM then
					if bit32.band(li.flags, IFL_NOTTEAM) ~= 0 then
						skip = true
					end
				else
					if bit32.band(li.flags, IFL_NOTFREE) ~= 0 then
						skip = true
					end
				end
				if not skip and ic.iteminfo[li.iteminfo].modelindex == modelindex then
					Q.VectorSubtract(li.origin, entinfo.origin, dir)
					if Q.VectorLength(dir) < 30 then
						li.entitynum = ent
						if entinfo.origin[0] ~= li.origin[0] or
							entinfo.origin[1] ~= li.origin[1] or
							entinfo.origin[2] ~= li.origin[2] then
							Q.VectorCopy(entinfo.origin, li.origin)
							li.goalareanum = B.AAS_BestReachableArea(li.origin,
								ic.iteminfo[li.iteminfo].mins, ic.iteminfo[li.iteminfo].maxs,
								li.goalorigin)
						end
						break
					end
				end
				li = li.next
			end
			if li ~= nil then
				break
			end
			local i = 0
			while i < ic.numiteminfo do
				if ic.iteminfo[i].modelindex == modelindex then
					break
				end
				i = i + 1
			end
			if i >= ic.numiteminfo then
				break
			end
			li = B.AllocLevelItem()
			if li == nil then
				break
			end
			li.entitynum = ent
			li.number = SF.numlevelitems + ent
			li.iteminfo = i
			Q.VectorCopy(entinfo.origin, li.origin)
			li.goalareanum = B.AAS_BestReachableArea(li.origin,
				ic.iteminfo[i].mins, ic.iteminfo[i].maxs,
				li.goalorigin)
			if B.AAS_AreaJumpPad(li.goalareanum) ~= 0 then
				B.FreeLevelItem(li)
				break
			end
			li.timeout = B.AAS_Time() + 30
			B.AddLevelItemToList(li)
		until true
		ent = B.AAS_NextEntity(ent)
	end
end

function B.BotDumpGoalStack(goalstate)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	for i = 1, gs.goalstacktop do
		local name = B.BotGoalName(gs.goalstack[i].number, 32)
		B.Log_Write("%d: %s", i, name)
	end
end

function B.BotPushGoal(goalstate, goal)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	if gs.goalstacktop >= MAX_GOALSTACK - 1 then
		B.botimport.Print(BC.PRT_ERROR, "goal heap overflow\n")
		B.BotDumpGoalStack(goalstate)
		return
	end
	gs.goalstacktop = gs.goalstacktop + 1
	SB.copy_bot_goal_t(gs.goalstack[gs.goalstacktop], goal)
end

return nil
