--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_dmnet.c, part 1 of 5).

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
-- Luau port of OpenArena 0.8.8's ai_dmnet.c (gamecode 9e0f0c0), part 1 of 5. Node switch recording, air/nearby goals, goal reached checks.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmnet")

--goal flag, see ../botlib/be_ai_goal.h for the other GFL_*
SF.GFL_AIR = 128

G.numnodeswitches = 0
G.nodeswitch = {}
for i = 0, C.MAX_NODESWITCHES do
	G.nodeswitch[i] = ""
end

SF.LOOKAHEAD_DISTANCE = 300

function G.BotResetNodeSwitches()
	G.numnodeswitches = 0
end

function G.BotDumpNodeSwitches(bs)
	local netname = G.ClientName(bs.client, C.MAX_NETNAME)
	G.BotAI_Print(C.PRT_MESSAGE, "%s at %1.1f switched more than %d AI nodes\n", netname, G.floattime, C.MAX_NODESWITCHES)
	for i = 0, G.numnodeswitches - 1 do
		G.BotAI_Print(C.PRT_MESSAGE, "%s", G.nodeswitch[i])
	end
	G.BotAI_Print(C.PRT_FATAL, "")
end

function G.BotRecordNodeSwitch(bs, node, str, s)
	local netname = G.ClientName(bs.client, C.MAX_NETNAME)
	G.nodeswitch[G.numnodeswitches] = QS.Com_sprintf(144, "%s at %2.1f entered %s: %s from %s\n", netname, G.floattime, node, str, s)
	G.numnodeswitches = G.numnodeswitches + 1
end

function G.BotGetAirGoal(bs, goal)
	local bsptrace = S.bsp_trace_t()
	local end_ = Q.vec3()
	local mins = { [0] = -15, -15, -2 }
	local maxs = { [0] = 15, 15, 2 }

	--trace up until we hit solid
	Q.VectorCopy(bs.origin, end_)
	end_[2] = end_[2] + 1000
	G.BotAI_Trace(bsptrace, bs.origin, mins, maxs, end_, bs.entitynum, bit32.bor(C.CONTENTS_SOLID, C.CONTENTS_PLAYERCLIP))
	--trace down until we hit water
	Q.VectorCopy(bsptrace.endpos, end_)
	G.BotAI_Trace(bsptrace, end_, mins, maxs, bs.origin, bs.entitynum, bit32.bor(C.CONTENTS_WATER, C.CONTENTS_SLIME, C.CONTENTS_LAVA))
	--if we found the water surface
	if bsptrace.fraction > 0 then
		local areanum = G.BotPointAreaNum(bsptrace.endpos)
		if areanum ~= 0 then
			Q.VectorCopy(bsptrace.endpos, goal.origin)
			goal.origin[2] = goal.origin[2] - 2
			goal.areanum = areanum
			goal.mins[0] = -15
			goal.mins[1] = -15
			goal.mins[2] = -1
			goal.maxs[0] = 15
			goal.maxs[1] = 15
			goal.maxs[2] = 1
			goal.flags = SF.GFL_AIR
			goal.number = 0
			goal.iteminfo = 0
			goal.entitynum = 0
			return 1
		end
	end
	return 0
end

function G.BotGoForAir(bs, tfl, ltg, range)
	local goal = S.bot_goal_t()

	--if the bot needs air
	if bs.lastair_time < G.floattime - 6 then
		--if we can find an air goal
		if G.BotGetAirGoal(bs, goal) ~= 0 then
			G.trap_BotPushGoal(bs.gs, goal)
			return 1
		else
			--get a nearby goal outside the water
			while G.trap_BotChooseNBGItem(bs.gs, bs.origin, bs.inventory, tfl, ltg, range) ~= 0 do
				G.trap_BotGetTopGoal(bs.gs, goal)
				--if the goal is not in water
				if bit32.band(G.trap_AAS_PointContents(goal.origin), bit32.bor(C.CONTENTS_WATER, C.CONTENTS_SLIME, C.CONTENTS_LAVA)) == 0 then
					return 1
				end
				G.trap_BotPopGoal(bs.gs)
			end
			G.trap_BotResetAvoidGoals(bs.gs)
		end
	end
	return 0
end

function G.BotNearbyGoal(bs, tfl, ltg, range)
	--check if the bot should go for air
	if G.BotGoForAir(bs, tfl, ltg, range) ~= 0 then return 1 end
	-- if the bot is carrying a flag or cubes
	if G.BotCTFCarryingFlag(bs) ~= 0 then
		--if the bot is just a few secs away from the base
		if G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin,
				bs.teamgoal.areanum, C.TFL_DEFAULT) < 300 then
			--make the range really small
			range = 50
		end
	end
	local ret = G.trap_BotChooseNBGItem(bs.gs, bs.origin, bs.inventory, tfl, ltg, range)
	return ret
end

function G.BotReachedGoal(bs, goal)
	if bit32.band(goal.flags, C.GFL_ITEM) ~= 0 then
		--if touching the goal
		if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then
			if bit32.band(goal.flags, C.GFL_DROPPED) == 0 then
				G.trap_BotSetAvoidGoalTime(bs.gs, goal.number, -1)
			end
			return 1
		end
		--if the goal isn't there
		if G.trap_BotItemGoalInVisButNotVisible(bs.entitynum, bs.eye, bs.viewangles, goal) ~= 0 then
			return 1
		end
		--if in the goal area and below or above the goal and not swimming
		if bs.areanum == goal.areanum then
			if bs.origin[0] > goal.origin[0] + goal.mins[0] and bs.origin[0] < goal.origin[0] + goal.maxs[0] then
				if bs.origin[1] > goal.origin[1] + goal.mins[1] and bs.origin[1] < goal.origin[1] + goal.maxs[1] then
					if G.trap_AAS_Swimming(bs.origin) == 0 then
						return 1
					end
				end
			end
		end
	elseif bit32.band(goal.flags, SF.GFL_AIR) ~= 0 then
		--if touching the goal
		if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then return 1 end
		--if the bot got air
		if bs.lastair_time > G.floattime - 1 then return 1 end
	else
		--if touching the goal
		if G.trap_BotTouchingGoal(bs.origin, goal) ~= 0 then return 1 end
	end
	return 0
end

function G.BotGetItemLongTermGoal(bs, tfl, goal)
	--if the bot has no goal
	if G.trap_BotGetTopGoal(bs.gs, goal) == 0 then
		bs.ltg_time = 0
	--if the bot touches the current goal
	elseif G.BotReachedGoal(bs, goal) ~= 0 then
		G.BotChooseWeapon(bs)
		bs.ltg_time = 0
	end
	--if it is time to find a new long term goal
	if bs.ltg_time < G.floattime then
		--pop the current goal from the stack
		G.trap_BotPopGoal(bs.gs)
		--choose a new goal
		if G.trap_BotChooseLTGItem(bs.gs, bs.origin, bs.inventory, tfl) ~= 0 then
			bs.ltg_time = G.floattime + 20
		else --the bot gets sorta stuck with all the avoid timings, shouldn't happen though
			--reset the avoid goals and the avoid reach
			G.trap_BotResetAvoidGoals(bs.gs)
			G.trap_BotResetAvoidReach(bs.ms)
		end
		--get the goal at the top of the stack
		return G.trap_BotGetTopGoal(bs.gs, goal)
	end
	return 1
end

return nil
