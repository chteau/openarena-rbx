--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_goal.c, part 3 of 3).

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
-- Luau port of be_ai_goal.c (botlib/be_ai_goal.c, part 3 of 3): goal stack, item choice, goal state management.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local SF = B.FileStatics("be_ai_goal")

local AVOID_MINIMUM_TIME = 10
local AVOID_DEFAULT_TIME = 30
local AVOID_DROPPED_TIME = 10
local TRAVELTIME_SCALE = 0.01
local IFL_NOTFREE = 1
local IFL_NOTTEAM = 2
local IFL_NOTSINGLE = 4
local IFL_NOTBOT = 8
local IFL_ROAM = 16
local GT_SINGLE_PLAYER = 2
local GT_TEAM = 3

local function ItemSkippedForGametype(li): boolean
	if SF.g_gametype == GT_SINGLE_PLAYER then
		if bit32.band(li.flags, IFL_NOTSINGLE) ~= 0 then
			return true
		end
	elseif SF.g_gametype >= GT_TEAM then
		if bit32.band(li.flags, IFL_NOTTEAM) ~= 0 then
			return true
		end
	else
		if bit32.band(li.flags, IFL_NOTFREE) ~= 0 then
			return true
		end
	end
	return false
end

local function BuildItemGoal(goalstate, gs, ic, bestitem)
	local goal = SB.bot_goal_t()
	local iteminfo = ic.iteminfo[bestitem.iteminfo]
	Q.VectorCopy(bestitem.goalorigin, goal.origin)
	Q.VectorCopy(iteminfo.mins, goal.mins)
	Q.VectorCopy(iteminfo.maxs, goal.maxs)
	goal.areanum = bestitem.goalareanum
	goal.entitynum = bestitem.entitynum
	goal.number = bestitem.number
	goal.flags = BC.GFL_ITEM
	if bestitem.timeout ~= 0 then
		goal.flags = bit32.bor(goal.flags, BC.GFL_DROPPED)
	end
	if bit32.band(bestitem.flags, IFL_ROAM) ~= 0 then
		goal.flags = bit32.bor(goal.flags, BC.GFL_ROAM)
	end
	goal.iteminfo = bestitem.iteminfo
	local avoidtime
	if bestitem.timeout ~= 0 then
		avoidtime = AVOID_DROPPED_TIME
	else
		avoidtime = iteminfo.respawntime
		if avoidtime == 0 then
			avoidtime = AVOID_DEFAULT_TIME
		end
		if avoidtime < AVOID_MINIMUM_TIME then
			avoidtime = AVOID_MINIMUM_TIME
		end
	end
	B.BotAddToAvoidGoals(gs, bestitem.number, avoidtime)
	B.BotPushGoal(goalstate, goal)
end

function B.BotPopGoal(goalstate)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	if gs.goalstacktop > 0 then
		gs.goalstacktop = gs.goalstacktop - 1
	end
end

function B.BotEmptyGoalStack(goalstate)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	gs.goalstacktop = 0
end

function B.BotGetTopGoal(goalstate, goal): number
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return 0
	end
	if gs.goalstacktop == 0 then
		return 0
	end
	SB.copy_bot_goal_t(goal, gs.goalstack[gs.goalstacktop])
	return 1
end

function B.BotGetSecondGoal(goalstate, goal): number
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return 0
	end
	if gs.goalstacktop <= 1 then
		return 0
	end
	SB.copy_bot_goal_t(goal, gs.goalstack[gs.goalstacktop - 1])
	return 1
end

-- pops a new long term goal on the goal stack in the goalstate
function B.BotChooseLTGItem(goalstate, origin, inventory, travelflags): number
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return 0
	end
	if gs.itemweightconfig == nil then
		return 0
	end
	local areanum = B.BotReachabilityArea(origin, gs.client)
	if areanum == 0 or B.AAS_AreaReachability(areanum) == 0 then
		areanum = gs.lastreachabilityarea
	end
	gs.lastreachabilityarea = areanum
	if areanum == 0 then
		return 0
	end
	local ic = SF.itemconfig
	if ic == nil then
		return 0
	end
	local bestweight = 0
	local bestitem = nil
	local li = SF.levelitems
	while li ~= nil do
		local continue = ItemSkippedForGametype(li)
		if not continue and bit32.band(li.flags, IFL_NOTBOT) ~= 0 then
			continue = true
		end
		if not continue and li.goalareanum == 0 then
			continue = true
		end
		if not continue and li.entitynum == 0 and bit32.band(li.flags, IFL_ROAM) == 0 then
			continue = true
		end
		if not continue then
			local iteminfo = ic.iteminfo[li.iteminfo]
			local weightnum = gs.itemweightindex[iteminfo.number]
			if weightnum < 0 then
				continue = true
			else
				local weight = B.FuzzyWeight(inventory, gs.itemweightconfig, weightnum)
				if li.timeout ~= 0 then
					weight = weight + SF.droppedweight.value
				end
				if bit32.band(li.flags, IFL_ROAM) ~= 0 then
					weight = weight * li.weight
				end
				if weight > 0 then
					local t = B.AAS_AreaTravelTimeToGoalArea(areanum, origin, li.goalareanum, travelflags)
					if t > 0 then
						local avoidtime = B.BotAvoidGoalTime(goalstate, li.number)
						if avoidtime - t * 0.009 <= 0 then
							weight = weight / (t * TRAVELTIME_SCALE)
							if weight > bestweight then
								bestweight = weight
								bestitem = li
							end
						end
					end
				end
			end
		end
		li = li.next
	end
	if bestitem == nil then
		return 0
	end
	BuildItemGoal(goalstate, gs, ic, bestitem)
	return 1
end

function B.BotChooseNBGItem(goalstate, origin, inventory, travelflags, ltg, maxtime): number
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return 0
	end
	if gs.itemweightconfig == nil then
		return 0
	end
	local areanum = B.BotReachabilityArea(origin, gs.client)
	if areanum == 0 or B.AAS_AreaReachability(areanum) == 0 then
		areanum = gs.lastreachabilityarea
	end
	gs.lastreachabilityarea = areanum
	if areanum == 0 then
		return 0
	end
	local ltg_time
	if ltg ~= nil then
		ltg_time = B.AAS_AreaTravelTimeToGoalArea(areanum, origin, ltg.areanum, travelflags)
	else
		ltg_time = 99999
	end
	local ic = SF.itemconfig
	if ic == nil then
		return 0
	end
	local bestweight = 0
	local bestitem = nil
	local li = SF.levelitems
	while li ~= nil do
		local continue = ItemSkippedForGametype(li)
		if not continue and bit32.band(li.flags, IFL_NOTBOT) ~= 0 then
			continue = true
		end
		if not continue and li.goalareanum == 0 then
			continue = true
		end
		if not continue and li.entitynum == 0 and bit32.band(li.flags, IFL_ROAM) == 0 then
			continue = true
		end
		if not continue then
			local iteminfo = ic.iteminfo[li.iteminfo]
			local weightnum = gs.itemweightindex[iteminfo.number]
			if weightnum < 0 then
				continue = true
			else
				local weight = B.FuzzyWeight(inventory, gs.itemweightconfig, weightnum)
				if li.timeout ~= 0 then
					weight = weight + SF.droppedweight.value
				end
				if bit32.band(li.flags, IFL_ROAM) ~= 0 then
					weight = weight * li.weight
				end
				if weight > 0 then
					local t = B.AAS_AreaTravelTimeToGoalArea(areanum, origin, li.goalareanum, travelflags)
					if t > 0 and t < maxtime then
						local avoidtime = B.BotAvoidGoalTime(goalstate, li.number)
						if avoidtime - t * 0.009 <= 0 then
							weight = weight / (t * TRAVELTIME_SCALE)
							if weight > bestweight then
								t = 0
								if ltg ~= nil and li.timeout == 0 then
									t = B.AAS_AreaTravelTimeToGoalArea(li.goalareanum, li.goalorigin, ltg.areanum, travelflags)
								end
								if t <= ltg_time then
									bestweight = weight
									bestitem = li
								end
							end
						end
					end
				end
			end
		end
		li = li.next
	end
	if bestitem == nil then
		return 0
	end
	BuildItemGoal(goalstate, gs, ic, bestitem)
	return 1
end

function B.BotTouchingGoal(origin, goal): number
	local boxmins = { [0] = 0, 0, 0 }
	local boxmaxs = { [0] = 0, 0, 0 }
	local absmins = { [0] = 0, 0, 0 }
	local absmaxs = { [0] = 0, 0, 0 }
	local safety_maxs = { [0] = 0, 0, 0 }
	local safety_mins = { [0] = 0, 0, 0 }

	B.AAS_PresenceTypeBoundingBox(BC.PRESENCE_NORMAL, boxmins, boxmaxs)
	Q.VectorSubtract(goal.mins, boxmaxs, absmins)
	Q.VectorSubtract(goal.maxs, boxmins, absmaxs)
	Q.VectorAdd(absmins, goal.origin, absmins)
	Q.VectorAdd(absmaxs, goal.origin, absmaxs)
	Q.VectorSubtract(absmaxs, safety_maxs, absmaxs)
	Q.VectorSubtract(absmins, safety_mins, absmins)

	for i = 0, 2 do
		if origin[i] < absmins[i] or origin[i] > absmaxs[i] then
			return 0
		end
	end
	return 1
end

function B.BotItemGoalInVisButNotVisible(viewer, eye, viewangles, goal): number
	local entinfo = SB.aas_entityinfo_t()
	local middle = { [0] = 0, 0, 0 }

	if bit32.band(goal.flags, BC.GFL_ITEM) == 0 then
		return 0
	end
	Q.VectorAdd(goal.mins, goal.mins, middle)
	Q.VectorScale(middle, 0.5, middle)
	Q.VectorAdd(goal.origin, middle, middle)

	local trace = B.AAS_Trace(eye, nil, nil, middle, viewer, BC.CONTENTS_SOLID)
	if trace.fraction >= 1 then
		if goal.entitynum <= 0 then
			return 0
		end
		B.AAS_EntityInfo(goal.entitynum, entinfo)
		if entinfo.ltime < B.AAS_Time() - 0.5 then
			return 1
		end
	end
	return 0
end

function B.BotResetGoalState(goalstate)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	for i = 0, BC.MAX_GOALSTACK - 1 do
		SB.copy_bot_goal_t(gs.goalstack[i], SB.bot_goal_t())
	end
	gs.goalstacktop = 0
	B.BotResetAvoidGoals(goalstate)
end

function B.BotLoadItemWeights(goalstate, filename): number
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return BC.BLERR_CANNOTLOADITEMWEIGHTS
	end
	gs.itemweightconfig = B.ReadWeightConfig(filename)
	if gs.itemweightconfig == nil then
		B.botimport.Print(BC.PRT_FATAL, "couldn't load weights\n")
		return BC.BLERR_CANNOTLOADITEMWEIGHTS
	end
	if SF.itemconfig == nil then
		return BC.BLERR_CANNOTLOADITEMWEIGHTS
	end
	gs.itemweightindex = B.ItemWeightIndex(gs.itemweightconfig, SF.itemconfig)
	return BC.BLERR_NOERROR
end

function B.BotFreeItemWeights(goalstate)
	local gs = B.BotGoalStateFromHandle(goalstate)
	if gs == nil then
		return
	end
	if gs.itemweightconfig ~= nil then
		B.FreeWeightConfig(gs.itemweightconfig)
	end
	if gs.itemweightindex ~= nil then
		gs.itemweightindex = nil
	end
end

function B.BotAllocGoalState(client): number
	for i = 1, BC.MAX_CLIENTS do
		if SF.botgoalstates[i] == nil then
			SF.botgoalstates[i] = SB.bot_goalstate_t()
			SF.botgoalstates[i].client = client
			return i
		end
	end
	return 0
end

function B.BotFreeGoalState(handle)
	if handle <= 0 or handle > BC.MAX_CLIENTS then
		B.botimport.Print(BC.PRT_FATAL, "goal state handle %d out of range\n", handle)
		return
	end
	if SF.botgoalstates[handle] == nil then
		B.botimport.Print(BC.PRT_FATAL, "invalid goal state handle %d\n", handle)
		return
	end
	B.BotFreeItemWeights(handle)
	SF.botgoalstates[handle] = nil
end

function B.BotSetupGoalAI(): number
	SF.g_gametype = B.LibVarValue("g_gametype", "0")
	local filename = B.LibVarString("itemconfig", "items.c")
	SF.itemconfig = B.LoadItemConfig(filename)
	if SF.itemconfig == nil then
		B.botimport.Print(BC.PRT_FATAL, "couldn't load item config\n")
		return BC.BLERR_CANNOTLOADITEMCONFIG
	end
	SF.droppedweight = B.LibVar("droppedweight", "1000")
	return BC.BLERR_NOERROR
end

function B.BotShutdownGoalAI()
	SF.itemconfig = nil
	SF.levelitemheap = nil
	SF.freelevelitems = nil
	SF.levelitems = nil
	SF.numlevelitems = 0

	B.BotFreeInfoEntities()

	for i = 1, BC.MAX_CLIENTS do
		if SF.botgoalstates[i] ~= nil then
			B.BotFreeGoalState(i)
		end
	end
end

return nil
