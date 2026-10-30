--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_dmq3.c, part 6 of 7).

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
-- Luau port of OpenArena 0.8.8's ai_dmq3.c (gamecode 9e0f0c0), part 6 of 7. Activate goals, blocked handling, obstacle prediction, console messages.

local G = require("../g_local")
local C = require("./ai_defs")
local S = require("./ai_structs")
local Q = require("../../shared/q_math")
local QS = require("../../shared/q_shared")
local BG = require("../../shared/BG")

local SF = G.FileStatics("ai_dmq3")

-- from aasfile.h (defined at the top of ai_dmq3.c)
local AREACONTENTS_MOVER = 1024
local AREACONTENTS_MODELNUMSHIFT = 24
local AREACONTENTS_MAXMODELNUM = 0xFF
local AREACONTENTS_MODELNUM = bit32.lshift(AREACONTENTS_MAXMODELNUM, AREACONTENTS_MODELNUMSHIFT)

function G.BotFuncDoorActivateGoal(bs, bspent, activategoal)
	local mins, maxs, origin = Q.vec3(), Q.vec3(), Q.vec3()

	--shoot at the shootable door
	local _, model = G.trap_AAS_ValueForBSPEpairKey(bspent, "model", C.MAX_INFO_STRING)
	if model == "" then
		return 0
	end
	local modelindex = QS.atoi(string.sub(model, 2))
	if modelindex == 0 then
		return 0
	end
	local entitynum = G.BotModelMinsMaxs(modelindex, C.ET_MOVER, 0, mins, maxs)
	--door origin
	Q.VectorAdd(mins, maxs, origin)
	Q.VectorScale(origin, 0.5, origin)
	Q.VectorCopy(origin, activategoal.target)
	activategoal.shoot = 1
	--
	activategoal.goal.entitynum = entitynum --NOTE: this is the entity number of the shootable door
	activategoal.goal.number = 0
	activategoal.goal.flags = 0
	Q.VectorCopy(bs.origin, activategoal.goal.origin)
	activategoal.goal.areanum = bs.areanum
	Q.VectorSet(activategoal.goal.mins, -8, -8, -8)
	Q.VectorSet(activategoal.goal.maxs, 8, 8, 8)
	return 1
end

function G.BotTriggerMultipleActivateGoal(bs, bspent, activategoal)
	local areas = {}
	local start, end_, mins, maxs = Q.vec3(), Q.vec3(), Q.vec3(), Q.vec3()
	local origin, goalorigin = Q.vec3(), Q.vec3()

	activategoal.shoot = 0
	Q.VectorClear(activategoal.target)
	--create a bot goal towards the trigger
	local _, model = G.trap_AAS_ValueForBSPEpairKey(bspent, "model", 128)
	if model == "" then
		return 0
	end
	local modelindex = QS.atoi(string.sub(model, 2))
	if modelindex == 0 then
		return 0
	end
	local entitynum = G.BotModelMinsMaxs(modelindex, 0, C.CONTENTS_TRIGGER, mins, maxs)
	--trigger origin
	Q.VectorAdd(mins, maxs, origin)
	Q.VectorScale(origin, 0.5, origin)
	Q.VectorCopy(origin, goalorigin)
	--
	Q.VectorCopy(goalorigin, start)
	start[2] += 24
	Q.VectorCopy(start, end_)
	end_[2] -= 100
	local numareas = G.trap_AAS_TraceAreas(start, end_, areas, nil, 10)
	--
	local i = 0
	while i < numareas do
		if G.trap_AAS_AreaReachability(areas[i]) ~= 0 then
			break
		end
		i += 1
	end
	if i < numareas then
		Q.VectorCopy(origin, activategoal.goal.origin)
		activategoal.goal.areanum = areas[i]
		Q.VectorSubtract(mins, origin, activategoal.goal.mins)
		Q.VectorSubtract(maxs, origin, activategoal.goal.maxs)
		--
		activategoal.goal.entitynum = entitynum
		activategoal.goal.number = 0
		activategoal.goal.flags = 0
		return 1
	end
	return 0
end

function G.BotPopFromActivateGoalStack(bs)
	if bs.activatestack == nil then
		return 0
	end
	G.BotEnableActivateGoalAreas(bs.activatestack, 1)
	bs.activatestack.inuse = 0
	bs.activatestack.justused_time = G.floattime
	bs.activatestack = bs.activatestack.next
	return 1
end

function G.BotPushOntoActivateGoalStack(bs, activategoal)
	local best = -1
	local besttime = G.floattime + 9999
	--
	for i = 0, C.MAX_ACTIVATESTACK - 1 do
		if bs.activategoalheap[i].inuse == 0 then
			if bs.activategoalheap[i].justused_time < besttime then
				besttime = bs.activategoalheap[i].justused_time
				best = i
			end
		end
	end
	if best ~= -1 then
		S.copy_bot_activategoal_t(bs.activategoalheap[best], activategoal)
		bs.activategoalheap[best].inuse = 1
		bs.activategoalheap[best].next = bs.activatestack
		bs.activatestack = bs.activategoalheap[best]
		return 1
	end
	return 0
end

function G.BotClearActivateGoalStack(bs)
	while bs.activatestack ~= nil do
		G.BotPopFromActivateGoalStack(bs)
	end
end

function G.BotEnableActivateGoalAreas(activategoal, enable)
	local en = enable ~= 0 and enable ~= false
	local notEnable = if en then 0 else 1
	if activategoal.areasdisabled == notEnable then
		return
	end
	for i = 0, activategoal.numareas - 1 do
		G.trap_AAS_EnableRoutingArea(activategoal.areas[i], if en then 1 else 0)
	end
	activategoal.areasdisabled = notEnable
end

function G.BotIsGoingToActivateEntity(bs, entitynum)
	local a = bs.activatestack
	while a ~= nil do
		if a.time >= G.floattime then
			if a.goal.entitynum == entitynum then
				return 1
			end
		end
		a = a.next
	end
	for i = 0, C.MAX_ACTIVATESTACK - 1 do
		if bs.activategoalheap[i].inuse == 0 then
			--
			if bs.activategoalheap[i].goal.entitynum == entitynum then
				-- if the bot went for this goal less than 2 seconds ago
				if bs.activategoalheap[i].justused_time > G.floattime - 2 then
					return 1
				end
			end
		end
	end
	return 0
end

--[[
returns the number of the bsp entity to activate
goal->entitynum will be set to the game entity to activate
]]
function G.BotGetActivateGoal(bs, entitynum, activategoal)
	local cur_entities = {}
	local areas = {}
	local targetname = {}
	local entinfo = S.aas_entityinfo_t()
	local areainfo = S.aas_areainfo_t()
	local origin, absmins, absmaxs = Q.vec3(), Q.vec3(), Q.vec3()

	S.copy_bot_activategoal_t(activategoal, S.bot_activategoal_t())
	G.BotEntityInfo(entitynum, entinfo)
	local model = QS.Com_sprintf(C.MAX_INFO_STRING, "*%d", entinfo.modelindex)
	local ent = G.trap_AAS_NextBSPEntity(0)
	while ent ~= 0 do
		local ok, tmpmodel = G.trap_AAS_ValueForBSPEpairKey(ent, "model", 128)
		if ok ~= 0 then
			if model == tmpmodel then
				break
			end
		end
		ent = G.trap_AAS_NextBSPEntity(ent)
	end
	if ent == 0 then
		G.BotAI_Print(C.PRT_ERROR, "BotGetActivateGoal: no entity found with model %s\n", model)
		return 0
	end
	local _, classname = G.trap_AAS_ValueForBSPEpairKey(ent, "classname", 128)
	if classname == "" then
		G.BotAI_Print(C.PRT_ERROR, "BotGetActivateGoal: entity with model %s has no classname\n", model)
		return 0
	end
	--if it is a door
	if classname == "func_door" then
		local okh, health = G.trap_AAS_FloatForBSPEpairKey(ent, "health")
		if okh ~= 0 then
			--if the door has health then the door must be shot to open
			if health ~= 0 then
				G.BotFuncDoorActivateGoal(bs, ent, activategoal)
				return ent
			end
		end
		--
		local _, spawnflags = G.trap_AAS_IntForBSPEpairKey(ent, "spawnflags")
		spawnflags = spawnflags or 0
		-- if the door starts open then just wait for the door to return
		if bit32.band(spawnflags, 1) ~= 0 then
			return 0
		end
		--get the door origin
		if G.trap_AAS_VectorForBSPEpairKey(ent, "origin", origin) == 0 then
			Q.VectorClear(origin)
		end
		--if the door is open or opening already
		if not Q.VectorCompare(origin, entinfo.origin) then
			return 0
		end
		-- store all the areas the door is in
		local _, dmodel = G.trap_AAS_ValueForBSPEpairKey(ent, "model", C.MAX_INFO_STRING)
		model = dmodel
		if model ~= "" then
			local modelindex = QS.atoi(string.sub(model, 2))
			if modelindex ~= 0 then
				G.BotModelMinsMaxs(modelindex, C.ET_MOVER, 0, absmins, absmaxs)
				--
				local numareas = G.trap_AAS_BBoxAreas(absmins, absmaxs, areas, C.MAX_ACTIVATEAREAS * 2)
				-- store the areas with reachabilities first
				for i = 0, numareas - 1 do
					if activategoal.numareas >= C.MAX_ACTIVATEAREAS then
						break
					end
					if G.trap_AAS_AreaReachability(areas[i]) ~= 0 then
						G.trap_AAS_AreaInfo(areas[i], areainfo)
						if bit32.band(areainfo.contents, AREACONTENTS_MOVER) ~= 0 then
							activategoal.areas[activategoal.numareas] = areas[i]
							activategoal.numareas += 1
						end
					end
				end
				-- store any remaining areas
				for i = 0, numareas - 1 do
					if activategoal.numareas >= C.MAX_ACTIVATEAREAS then
						break
					end
					if G.trap_AAS_AreaReachability(areas[i]) == 0 then
						G.trap_AAS_AreaInfo(areas[i], areainfo)
						if bit32.band(areainfo.contents, AREACONTENTS_MOVER) ~= 0 then
							activategoal.areas[activategoal.numareas] = areas[i]
							activategoal.numareas += 1
						end
					end
				end
			end
		end
	end
	-- if the bot is blocked by or standing on top of a button
	if classname == "func_button" then
		return 0
	end
	-- get the targetname so we can find an entity with a matching target
	local oktn, tn0 = G.trap_AAS_ValueForBSPEpairKey(ent, "targetname", 128)
	if oktn == 0 then
		if G.bot_developer.integer ~= 0 then
			G.BotAI_Print(C.PRT_ERROR, "BotGetActivateGoal: entity with model \"%s\" has no targetname\n", model)
		end
		return 0
	end
	targetname[0] = tn0
	-- allow tree-like activation
	cur_entities[0] = G.trap_AAS_NextBSPEntity(0)
	local i = 0
	while i >= 0 and i < 10 do
		ent = cur_entities[i]
		while ent ~= 0 do
			local ok, target = G.trap_AAS_ValueForBSPEpairKey(ent, "target", 128)
			if ok ~= 0 then
				if targetname[i] == target then
					cur_entities[i] = G.trap_AAS_NextBSPEntity(ent)
					break
				end
			end
			ent = G.trap_AAS_NextBSPEntity(ent)
		end
		if ent == 0 then
			if G.bot_developer.integer ~= 0 then
				G.BotAI_Print(C.PRT_ERROR, "BotGetActivateGoal: no entity with target \"%s\"\n", targetname[i])
			end
			i -= 1
			continue
		end
		local okc, cn = G.trap_AAS_ValueForBSPEpairKey(ent, "classname", 128)
		if okc == 0 then
			if G.bot_developer.integer ~= 0 then
				G.BotAI_Print(C.PRT_ERROR, "BotGetActivateGoal: entity with target \"%s\" has no classname\n", targetname[i])
			end
			continue
		end
		classname = cn
		-- BSP button model
		if classname == "func_button" then
			--
			if G.BotFuncButtonActivateGoal(bs, ent, activategoal) == 0 then
				continue
			end
			-- if the bot tries to activate this button already
			if bs.activatestack ~= nil and bs.activatestack.inuse ~= 0 and
				bs.activatestack.goal.entitynum == activategoal.goal.entitynum and
				bs.activatestack.time > G.floattime and
				bs.activatestack.start_time < G.floattime - 2 then
				continue
			end
			-- if the bot is in a reachability area
			if G.trap_AAS_AreaReachability(bs.areanum) ~= 0 then
				-- disable all areas the blocking entity is in
				G.BotEnableActivateGoalAreas(activategoal, 0)
				--
				local t = G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin, activategoal.goal.areanum, bs.tfl)
				-- if the button is not reachable
				if t == 0 then
					continue
				end
				activategoal.time = G.floattime + t * 0.01 + 5
			end
			return ent
		-- invisible trigger multiple box
		elseif classname == "trigger_multiple" then
			--
			if G.BotTriggerMultipleActivateGoal(bs, ent, activategoal) == 0 then
				continue
			end
			-- if the bot tries to activate this trigger already
			if bs.activatestack ~= nil and bs.activatestack.inuse ~= 0 and
				bs.activatestack.goal.entitynum == activategoal.goal.entitynum and
				bs.activatestack.time > G.floattime and
				bs.activatestack.start_time < G.floattime - 2 then
				continue
			end
			-- if the bot is in a reachability area
			if G.trap_AAS_AreaReachability(bs.areanum) ~= 0 then
				-- disable all areas the blocking entity is in
				G.BotEnableActivateGoalAreas(activategoal, 0)
				--
				local t = G.trap_AAS_AreaTravelTimeToGoalArea(bs.areanum, bs.origin, activategoal.goal.areanum, bs.tfl)
				-- if the trigger is not reachable
				if t == 0 then
					continue
				end
				activategoal.time = G.floattime + t * 0.01 + 5
			end
			return ent
		elseif classname == "func_timer" then
			-- just skip the func_timer
			continue
		-- the actual button or trigger might be linked through a target_relay or target_delay
		elseif classname == "target_relay" or classname == "target_delay" then
			local okt, tnn = G.trap_AAS_ValueForBSPEpairKey(ent, "targetname", 128)
			if okt ~= 0 then
				targetname[i + 1] = tnn
				i += 1
				cur_entities[i] = G.trap_AAS_NextBSPEntity(0)
			end
		end
	end
	return 0
end

function G.BotGoForActivateGoal(bs, activategoal)
	local activateinfo = S.aas_entityinfo_t()

	activategoal.inuse = 1
	if activategoal.time == 0 then
		activategoal.time = G.floattime + 10
	end
	activategoal.start_time = G.floattime
	G.BotEntityInfo(activategoal.goal.entitynum, activateinfo)
	Q.VectorCopy(activateinfo.origin, activategoal.origin)
	--
	if G.BotPushOntoActivateGoalStack(bs, activategoal) ~= 0 then
		-- enter the activate entity AI node
		G.AIEnter_Seek_ActivateEntity(bs, "BotGoForActivateGoal")
		return 1
	else
		-- enable any routing areas that were disabled
		G.BotEnableActivateGoalAreas(activategoal, 1)
		return 0
	end
end

function G.BotPrintActivateGoalInfo(bs, activategoal, bspent)
	local netname = G.ClientName(bs.client, C.MAX_NETNAME)
	local _, classname = G.trap_AAS_ValueForBSPEpairKey(bspent, "classname", 128)
	local buf
	if activategoal.shoot ~= 0 then
		buf = QS.Com_sprintf(128, "%s: I have to shoot at a %s from %1.1f %1.1f %1.1f in area %d\n",
			netname, classname,
			activategoal.goal.origin[0],
			activategoal.goal.origin[1],
			activategoal.goal.origin[2],
			activategoal.goal.areanum)
	else
		buf = QS.Com_sprintf(128, "%s: I have to activate a %s at %1.1f %1.1f %1.1f in area %d\n",
			netname, classname,
			activategoal.goal.origin[0],
			activategoal.goal.origin[1],
			activategoal.goal.origin[2],
			activategoal.goal.areanum)
	end
	G.trap_EA_Say(bs.client, buf)
end

function G.BotRandomMove(bs, moveresult)
	local dir, angles = Q.vec3(), Q.vec3()

	angles[0] = 0
	angles[1] = Q.random() * 360
	angles[2] = 0
	Q.AngleVectors(angles, dir, nil, nil)

	G.trap_BotMoveInDirection(bs.ms, dir, 400, C.MOVE_WALK)

	moveresult.failure = 0
	Q.VectorCopy(dir, moveresult.movedir)
end

--[[
Very basic handling of bots being blocked by other entities.
Check what kind of entity is blocking the bot and try to activate
it. If that's not an option then try to walk around or over the entity.
Before the bot ends in this part of the AI it should predict which doors to
open, which buttons to activate etc.
]]
function G.BotAIBlocked(bs, moveresult, activate)
	local hordir, start, sideward, angles = Q.vec3(), Q.vec3(), Q.vec3(), Q.vec3()
	local up = Q.vec3()
	up[2] = 1
	local entinfo = S.aas_entityinfo_t()
	local activategoal = S.bot_activategoal_t()

	-- if the bot is not blocked by anything
	if moveresult.blocked == 0 then
		bs.notblocked_time = G.floattime
		return
	end
	-- if stuck in a solid area
	if moveresult.type == C.RESULTTYPE_INSOLIDAREA then
		-- move in a random direction in the hope to get out
		G.BotRandomMove(bs, moveresult)
		--
		return
	end
	-- get info for the entity that is blocking the bot
	G.BotEntityInfo(moveresult.blockentity, entinfo)
	-- if blocked by a bsp model and the bot wants to activate it
	if activate ~= 0 and activate ~= false and entinfo.modelindex > 0 and entinfo.modelindex <= G.max_bspmodelindex then
		-- find the bsp entity which should be activated in order to get the blocking entity out of the way
		local bspent = G.BotGetActivateGoal(bs, entinfo.number, activategoal)
		if bspent ~= 0 then
			--
			if bs.activatestack ~= nil and bs.activatestack.inuse == 0 then
				bs.activatestack = nil
			end
			-- if not already trying to activate this entity
			if G.BotIsGoingToActivateEntity(bs, activategoal.goal.entitynum) == 0 then
				--
				G.BotGoForActivateGoal(bs, activategoal)
			end
			-- if ontop of an obstacle or
			-- if the bot is not in a reachability area it'll still
			-- need some dynamic obstacle avoidance, otherwise return
			if bit32.band(moveresult.flags, C.MOVERESULT_ONTOPOFOBSTACLE) == 0 and
				G.trap_AAS_AreaReachability(bs.areanum) ~= 0 then
				return
			end
		else
			-- enable any routing areas that were disabled
			G.BotEnableActivateGoalAreas(activategoal, 1)
		end
	end
	-- just some basic dynamic obstacle avoidance code
	hordir[0] = moveresult.movedir[0]
	hordir[1] = moveresult.movedir[1]
	hordir[2] = 0
	-- if no direction just take a random direction
	if Q.VectorNormalize(hordir) < 0.1 then
		Q.VectorSet(angles, 0, 360 * Q.random(), 0)
		Q.AngleVectors(angles, hordir, nil, nil)
	end
	--
	local movetype = C.MOVE_WALK
	-- if there's an obstacle at the bot's feet and head then
	-- the bot might be able to crouch through
	Q.VectorCopy(bs.origin, start)
	start[2] += 18
	--
	-- get the sideward vector
	Q.CrossProduct(hordir, up, sideward)
	--
	if bit32.band(bs.flags, C.BFL_AVOIDRIGHT) ~= 0 then
		Q.VectorNegate(sideward, sideward)
	end
	-- try to crouch straight forward?
	if movetype ~= C.MOVE_CROUCH or G.trap_BotMoveInDirection(bs.ms, hordir, 400, movetype) == 0 then
		-- perform the movement
		if G.trap_BotMoveInDirection(bs.ms, sideward, 400, movetype) == 0 then
			-- flip the avoid direction flag
			bs.flags = bit32.bxor(bs.flags, C.BFL_AVOIDRIGHT)
			-- flip the direction
			Q.VectorMA(sideward, -1, hordir, sideward)
			-- move in the other direction
			G.trap_BotMoveInDirection(bs.ms, sideward, 400, movetype)
		end
	end
	--
	if bs.notblocked_time < G.floattime - 0.4 then
		-- just reset goals and hope the bot will go into another direction?
		-- is this still needed??
		if bs.ainode == G.AINode_Seek_NBG then
			bs.nbg_time = 0
		elseif bs.ainode == G.AINode_Seek_LTG then
			bs.ltg_time = 0
		end
	end
end

--[[
Predict the route towards the goal and check if the bot
will be blocked by certain obstacles. When the bot has obstacles
on it's path the bot should figure out if they can be removed
by activating certain entities.
]]
function G.BotAIPredictObstacles(bs, goal)
	local activategoal = S.bot_activategoal_t()
	local route = S.aas_predictroute_t()

	if G.bot_predictobstacles.integer == 0 then
		return 0
	end

	-- always predict when the goal change or at regular intervals
	if bs.predictobstacles_goalareanum == goal.areanum and
		bs.predictobstacles_time > G.floattime - 6 then
		return 0
	end
	bs.predictobstacles_goalareanum = goal.areanum
	bs.predictobstacles_time = G.floattime

	-- predict at most 100 areas or 1 second ahead
	G.trap_AAS_PredictRoute(route, bs.areanum, bs.origin,
		goal.areanum, bs.tfl, 100, 1000,
		bit32.bor(C.RSE_USETRAVELTYPE, C.RSE_ENTERCONTENTS),
		AREACONTENTS_MOVER, C.TFL_BRIDGE, 0)
	-- if bot has to travel through an area with a mover
	if bit32.band(route.stopevent, C.RSE_ENTERCONTENTS) ~= 0 then
		-- if the bot will run into a mover
		if bit32.band(route.endcontents, AREACONTENTS_MOVER) ~= 0 then
			--NOTE: this only works with bspc 2.1 or higher
			local modelnum = bit32.rshift(bit32.band(route.endcontents, AREACONTENTS_MODELNUM), AREACONTENTS_MODELNUMSHIFT)
			if modelnum ~= 0 then
				--
				local entitynum = G.BotModelMinsMaxs(modelnum, C.ET_MOVER, 0, nil, nil)
				if entitynum ~= 0 then
					--NOTE: BotGetActivateGoal already checks if the door is open or not
					local bspent = G.BotGetActivateGoal(bs, entitynum, activategoal)
					if bspent ~= 0 then
						--
						if bs.activatestack ~= nil and bs.activatestack.inuse == 0 then
							bs.activatestack = nil
						end
						-- if not already trying to activate this entity
						if G.BotIsGoingToActivateEntity(bs, activategoal.goal.entitynum) == 0 then
							--
							G.BotGoForActivateGoal(bs, activategoal)
							return 1
						else
							-- enable any routing areas that were disabled
							G.BotEnableActivateGoalAreas(activategoal, 1)
						end
					end
				end
			end
		end
	elseif bit32.band(route.stopevent, C.RSE_USETRAVELTYPE) ~= 0 then
		if bit32.band(route.endtravelflags, C.TFL_BRIDGE) ~= 0 then
			--FIXME: check if the bridge is available to travel over
		end
	end
	return 0
end

function G.BotCheckConsoleMessages(bs)
	local m = S.bot_consolemessage_t()
	local match = S.bot_match_t()
	local context = 0

	--the name of this bot
	local botname = G.ClientName(bs.client, C.MAX_NETNAME)
	--
	while true do
		local handle = G.trap_BotNextConsoleMessage(bs.cs, m)
		if handle == 0 then
			break
		end
		--if the chat state is flooded with messages the bot will read them quickly
		if G.trap_BotNumConsoleMessages(bs.cs) < 10 then
			--if it is a chat message the bot needs some time to read it
			if m.type == C.CMS_CHAT and m.time > G.floattime - (1 + Q.random()) then
				break
			end
		end
		--
		local offset = 0
		--if it is a chat message then don't unify white spaces and don't
		--replace synonyms in the netname
		if m.type == C.CMS_CHAT then
			--
			if G.trap_BotFindMatch(m.message, match, C.MTCONTEXT_REPLYCHAT) ~= 0 then
				offset = match.variables[C.MESSAGE].offset
			end
		end
		local ptr = string.sub(m.message, offset + 1)
		--unify the white spaces in the message
		ptr = G.trap_UnifyWhiteSpaces(ptr)
		--replace synonyms in the right context
		context = G.BotSynonymContext(bs)
		ptr = G.trap_BotReplaceSynonyms(ptr, context)
		m.message = string.sub(m.message, 1, offset) .. ptr
		--if there's no match
		if G.BotMatchMessage(bs, m.message) == 0 then
			--if it is a chat message
			if m.type == C.CMS_CHAT and not G.BotNoChat(bs) then
				--
				if G.trap_BotFindMatch(m.message, match, C.MTCONTEXT_REPLYCHAT) == 0 then
					G.trap_BotRemoveConsoleMessage(bs.cs, handle)
					continue
				end
				--don't use eliza chats with team messages
				if bit32.band(match.subtype, C.ST_TEAM) ~= 0 then
					G.trap_BotRemoveConsoleMessage(bs.cs, handle)
					continue
				end
				--
				local netname = G.trap_BotMatchVariable(match, C.NETNAME, C.MAX_NETNAME)
				local message = G.trap_BotMatchVariable(match, C.MESSAGE, C.MAX_MESSAGE_SIZE)
				--if this is a message from the bot self
				if bs.client == G.ClientFromName(netname) then
					G.trap_BotRemoveConsoleMessage(bs.cs, handle)
					continue
				end
				--unify the message
				message = G.trap_UnifyWhiteSpaces(message)
				--
				G.trap_Cvar_Update(G.bot_testrchat)
				if G.bot_testrchat.integer ~= 0 then
					--
					G.trap_BotLibVarSet("bot_testrchat", "1")
					--if bot replies with a chat message
					if G.trap_BotReplyChat(bs.cs, message, context, C.CONTEXT_REPLY,
						nil, nil,
						nil, nil,
						nil, nil,
						botname, netname) ~= 0 then
						G.BotAI_Print(C.PRT_MESSAGE, "------------------------\n")
					else
						G.BotAI_Print(C.PRT_MESSAGE, "**** no valid reply ****\n")
					end
				--if at a valid chat position and not chatting already and not in teamplay
				elseif bs.ainode ~= G.AINode_Stand and G.BotValidChatPosition(bs) ~= 0 and G.TeamPlayIsOn() == 0 then
					local chat_reply = G.trap_Characteristic_BFloat(bs.character, C.CHARACTERISTIC_CHAT_REPLY, 0, 1)
					if Q.random() < 1.5 / (G.NumBots() + 1) and Q.random() < chat_reply then
						--if bot replies with a chat message
						if G.trap_BotReplyChat(bs.cs, message, context, C.CONTEXT_REPLY,
							nil, nil,
							nil, nil,
							nil, nil,
							botname, netname) ~= 0 then
							--remove the console message
							G.trap_BotRemoveConsoleMessage(bs.cs, handle)
							bs.stand_time = G.floattime + G.BotChatTime(bs)
							G.AIEnter_Stand(bs, "BotCheckConsoleMessages: reply chat")
							break
						end
					end
				end
			end
		end
		--remove the console message
		G.trap_BotRemoveConsoleMessage(bs.cs, handle)
	end
end

return nil
