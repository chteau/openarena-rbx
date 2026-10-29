--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_move.c, part 1 of 5).

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
-- Luau port of be_ai_move.c (botlib/be_ai_move.c, part 1 of 5). Bot movement AI: move states, reachability areas.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("be_ai_move")

-- used to avoid reachability links for some time after being used
SF.AVOIDREACH_TIME = 6
SF.AVOIDREACH_TRIES = 4
-- prediction times
SF.PREDICTIONTIME_JUMP = 3
SF.PREDICTIONTIME_MOVE = 2
-- weapon indexes for weapon jumping
SF.WEAPONINDEX_ROCKET_LAUNCHER = 5
SF.WEAPONINDEX_BFG = 9

SF.MODELTYPE_FUNC_PLAT = 1
SF.MODELTYPE_FUNC_BOB = 2
SF.MODELTYPE_FUNC_DOOR = 3
SF.MODELTYPE_FUNC_STATIC = 4

SF.sv_maxstep = nil
SF.sv_maxbarrier = nil
SF.sv_gravity = nil
SF.weapindex_rocketlauncher = nil
SF.weapindex_bfg10k = nil
SF.weapindex_grapple = nil
SF.entitytypemissile = nil
SF.offhandgrapple = nil
SF.cmd_grappleoff = nil
SF.cmd_grappleon = nil
-- type of model, func_plat or func_bobbing
SF.modeltypes = B.zeros(BC.MAX_MODELS)

SF.botmovestates = {}

function B.BotAllocMoveState(): number
	local botmovestates = SF.botmovestates
	for i = 1, BC.MAX_CLIENTS do
		if botmovestates[i] == nil then
			botmovestates[i] = SB.bot_movestate_t()
			return i
		end
	end
	return 0
end

function B.BotFreeMoveState(handle: number)
	if handle <= 0 or handle > BC.MAX_CLIENTS then
		B.botimport.Print(BC.PRT_FATAL, "move state handle %d out of range\n", handle)
		return
	end
	if SF.botmovestates[handle] == nil then
		B.botimport.Print(BC.PRT_FATAL, "invalid move state %d\n", handle)
		return
	end
	SF.botmovestates[handle] = nil
end

function B.BotMoveStateFromHandle(handle: number)
	if handle <= 0 or handle > BC.MAX_CLIENTS then
		B.botimport.Print(BC.PRT_FATAL, "move state handle %d out of range\n", handle)
		return nil
	end
	if SF.botmovestates[handle] == nil then
		B.botimport.Print(BC.PRT_FATAL, "invalid move state %d\n", handle)
		return nil
	end
	return SF.botmovestates[handle]
end

function B.BotInitMoveState(handle: number, initmove)
	local ms = B.BotMoveStateFromHandle(handle)
	if ms == nil then return end
	Q.VectorCopy(initmove.origin, ms.origin)
	Q.VectorCopy(initmove.velocity, ms.velocity)
	Q.VectorCopy(initmove.viewoffset, ms.viewoffset)
	ms.entitynum = initmove.entitynum
	ms.client = initmove.client
	ms.thinktime = initmove.thinktime
	ms.presencetype = initmove.presencetype
	Q.VectorCopy(initmove.viewangles, ms.viewangles)
	--
	ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_ONGROUND))
	if bit32.band(initmove.or_moveflags, BC.MFL_ONGROUND) ~= 0 then ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_ONGROUND) end
	ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_TELEPORTED))
	if bit32.band(initmove.or_moveflags, BC.MFL_TELEPORTED) ~= 0 then ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_TELEPORTED) end
	ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_WATERJUMP))
	if bit32.band(initmove.or_moveflags, BC.MFL_WATERJUMP) ~= 0 then ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_WATERJUMP) end
	ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_WALK))
	if bit32.band(initmove.or_moveflags, BC.MFL_WALK) ~= 0 then ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_WALK) end
	ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_GRAPPLEPULL))
	if bit32.band(initmove.or_moveflags, BC.MFL_GRAPPLEPULL) ~= 0 then ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_GRAPPLEPULL) end
end

function B.AngleDiff(ang1: number, ang2: number): number
	local diff = ang1 - ang2
	if ang1 > ang2 then
		if diff > 180.0 then diff -= 360.0 end
	else
		if diff < -180.0 then diff += 360.0 end
	end
	return diff
end

function B.BotFuzzyPointReachabilityArea(origin): number
	local areas = B.zeros(10)
	local points = {}
	for i = 0, 9 do points[i] = { [0] = 0, 0, 0 } end
	local v = { [0] = 0, 0, 0 }
	local en = { [0] = 0, 0, 0 }

	local firstareanum = 0
	local areanum = B.AAS_PointAreaNum(origin)
	if areanum ~= 0 then
		firstareanum = areanum
		if B.AAS_AreaReachability(areanum) ~= 0 then return areanum end
	end
	Q.VectorCopy(origin, en)
	en[2] += 4
	local numareas = B.AAS_TraceAreas(origin, en, areas, points, 10)
	for j = 0, numareas - 1 do
		if B.AAS_AreaReachability(areas[j]) ~= 0 then return areas[j] end
	end
	local bestdist = 999999
	local bestareanum = 0
	for z = 1, -1, -1 do
		for x = 1, -1, -1 do
			for y = 1, -1, -1 do
				Q.VectorCopy(origin, en)
				en[0] += x * 8
				en[1] += y * 8
				en[2] += z * 12
				numareas = B.AAS_TraceAreas(origin, en, areas, points, 10)
				for j = 0, numareas - 1 do
					if B.AAS_AreaReachability(areas[j]) ~= 0 then
						Q.VectorSubtract(points[j], origin, v)
						local dist = Q.VectorLength(v)
						if dist < bestdist then
							bestareanum = areas[j]
							bestdist = dist
						end
					end
					if firstareanum == 0 then firstareanum = areas[j] end
				end
			end
		end
		if bestareanum ~= 0 then return bestareanum end
	end
	return firstareanum
end

function B.BotReachabilityArea(origin, client: number): number
	local reach = SB.aas_reachability_t()
	local org = { [0] = 0, 0, 0 }
	local en = { [0] = 0, 0, 0 }
	local mins = { [0] = 0, 0, 0 }
	local maxs = { [0] = 0, 0, 0 }
	local up = { [0] = 0, 0, 1 }

	-- check if the bot is standing on something
	B.AAS_PresenceTypeBoundingBox(BC.PRESENCE_CROUCH, mins, maxs)
	Q.VectorMA(origin, -3, up, en)
	local bsptrace = B.AAS_Trace(origin, mins, maxs, en, client, bit32.bor(BC.CONTENTS_SOLID, BC.CONTENTS_PLAYERCLIP))
	if not bsptrace.startsolid and bsptrace.fraction < 1 and bsptrace.ent ~= BC.ENTITYNUM_NONE then
		-- if standing on the world the bot should be in a valid area
		if bsptrace.ent == BC.ENTITYNUM_WORLD then
			return B.BotFuzzyPointReachabilityArea(origin)
		end

		local modelnum = B.AAS_EntityModelindex(bsptrace.ent)
		local modeltype = SF.modeltypes[modelnum]

		-- if standing on a func_plat or func_bobbing then the bot is assumed to be
		-- in the area the reachability points to
		if modeltype == SF.MODELTYPE_FUNC_PLAT or modeltype == SF.MODELTYPE_FUNC_BOB then
			local reachnum = B.AAS_NextModelReachability(0, modelnum)
			if reachnum ~= 0 then
				B.AAS_ReachabilityFromNum(reachnum, reach)
				return reach.areanum
			end
		end

		-- if the bot is swimming the bot should be in a valid area
		if B.AAS_Swimming(origin) ~= 0 then
			return B.BotFuzzyPointReachabilityArea(origin)
		end
		--
		local areanum = B.BotFuzzyPointReachabilityArea(origin)
		-- if the bot is in an area with reachabilities
		if areanum ~= 0 and B.AAS_AreaReachability(areanum) ~= 0 then return areanum end
		-- trace down till the ground is hit because the bot is standing on some other entity
		Q.VectorCopy(origin, org)
		Q.VectorCopy(org, en)
		en[2] -= 800
		local trace = B.AAS_TraceClientBBox(org, en, BC.PRESENCE_CROUCH, -1)
		if not trace.startsolid then
			Q.VectorCopy(trace.endpos, org)
		end
		--
		return B.BotFuzzyPointReachabilityArea(org)
	end
	--
	return B.BotFuzzyPointReachabilityArea(origin)
end

function B.BotOnMover(origin, entnum: number, reach): number
	local mins = { [0] = 0, 0, 0 }
	local maxs = { [0] = 0, 0, 0 }
	local modelorigin = { [0] = 0, 0, 0 }
	local org = { [0] = 0, 0, 0 }
	local en = { [0] = 0, 0, 0 }
	local angles = { [0] = 0, 0, 0 }
	local boxmins = { [0] = -16, -16, -8 }
	local boxmaxs = { [0] = 16, 16, 8 }

	local modelnum = bit32.band(reach.facenum, 0x0000FFFF)
	-- get some bsp model info
	B.AAS_BSPModelMinsMaxsOrigin(modelnum, angles, mins, maxs, nil)
	--
	if B.AAS_OriginOfMoverWithModelNum(modelnum, modelorigin) == 0 then
		B.botimport.Print(BC.PRT_MESSAGE, "no entity with model %d\n", modelnum)
		return 0
	end
	--
	for i = 0, 1 do
		if origin[i] > modelorigin[i] + maxs[i] + 16 then return 0 end
		if origin[i] < modelorigin[i] + mins[i] - 16 then return 0 end
	end
	--
	Q.VectorCopy(origin, org)
	org[2] += 24
	Q.VectorCopy(origin, en)
	en[2] -= 48
	--
	local trace = B.AAS_Trace(org, boxmins, boxmaxs, en, entnum, bit32.bor(BC.CONTENTS_SOLID, BC.CONTENTS_PLAYERCLIP))
	if not trace.startsolid and not trace.allsolid then
		-- NOTE: the reachability face number is the model number of the elevator
		if trace.ent ~= BC.ENTITYNUM_NONE and B.AAS_EntityModelNum(trace.ent) == modelnum then
			return 1
		end
	end
	return 0
end

function B.MoverDown(reach): number
	local mins = { [0] = 0, 0, 0 }
	local maxs = { [0] = 0, 0, 0 }
	local origin = { [0] = 0, 0, 0 }
	local angles = { [0] = 0, 0, 0 }

	local modelnum = bit32.band(reach.facenum, 0x0000FFFF)
	-- get some bsp model info
	B.AAS_BSPModelMinsMaxsOrigin(modelnum, angles, mins, maxs, origin)
	--
	if B.AAS_OriginOfMoverWithModelNum(modelnum, origin) == 0 then
		B.botimport.Print(BC.PRT_MESSAGE, "no entity with model %d\n", modelnum)
		return 0
	end
	-- if the top of the plat is below the reachability start point
	if origin[2] + maxs[2] < reach.start[2] then return 1 end
	return 0
end

function B.BotSetBrushModelTypes()
	local modeltypes = SF.modeltypes
	for i = 0, BC.MAX_MODELS - 1 do modeltypes[i] = 0 end
	--
	local ent = B.AAS_NextBSPEntity(0)
	while ent ~= 0 do
		local continue = false
		local ok1, classname = B.AAS_ValueForBSPEpairKey(ent, "classname", BC.MAX_EPAIRKEY)
		local ok2, model = nil, ""
		if ok1 == 0 then
			continue = true
		else
			ok2, model = B.AAS_ValueForBSPEpairKey(ent, "model", BC.MAX_EPAIRKEY)
			if ok2 == 0 then continue = true end
		end
		if not continue then
			local modelnum
			if model ~= "" then
				modelnum = QS.atoi(string.sub(model, 2))
			else
				modelnum = 0
			end

			if modelnum < 0 or modelnum >= BC.MAX_MODELS then
				B.botimport.Print(BC.PRT_MESSAGE, "entity %s model number out of range\n", classname)
			elseif QS.Q_stricmp(classname, "func_bobbing") == 0 then
				modeltypes[modelnum] = SF.MODELTYPE_FUNC_BOB
			elseif QS.Q_stricmp(classname, "func_plat") == 0 then
				modeltypes[modelnum] = SF.MODELTYPE_FUNC_PLAT
			elseif QS.Q_stricmp(classname, "func_door") == 0 then
				modeltypes[modelnum] = SF.MODELTYPE_FUNC_DOOR
			elseif QS.Q_stricmp(classname, "func_static") == 0 then
				modeltypes[modelnum] = SF.MODELTYPE_FUNC_STATIC
			end
		end
		ent = B.AAS_NextBSPEntity(ent)
	end
end

function B.BotOnTopOfEntity(ms): number
	local mins = { [0] = 0, 0, 0 }
	local maxs = { [0] = 0, 0, 0 }
	local en = { [0] = 0, 0, 0 }
	local up = { [0] = 0, 0, 1 }

	B.AAS_PresenceTypeBoundingBox(ms.presencetype, mins, maxs)
	Q.VectorMA(ms.origin, -3, up, en)
	local trace = B.AAS_Trace(ms.origin, mins, maxs, en, ms.entitynum, bit32.bor(BC.CONTENTS_SOLID, BC.CONTENTS_PLAYERCLIP))
	if not trace.startsolid and (trace.ent ~= BC.ENTITYNUM_WORLD and trace.ent ~= BC.ENTITYNUM_NONE) then
		return trace.ent
	end
	return -1
end

function B.BotValidTravel(origin, reach, travelflags: number): number
	-- if the reachability uses an unwanted travel type
	if bit32.band(B.AAS_TravelFlagForType(reach.traveltype), bit32.bnot(travelflags)) ~= 0 then return 0 end
	-- don't go into areas with bad travel types
	if bit32.band(B.AAS_AreaContentsTravelFlags(reach.areanum), bit32.bnot(travelflags)) ~= 0 then return 0 end
	return 1
end

function B.BotAddToAvoidReach(ms, number: number, avoidtime: number)
	for i = 0, BC.MAX_AVOIDREACH - 1 do
		if ms.avoidreach[i] == number then
			if ms.avoidreachtimes[i] > B.AAS_Time() then
				ms.avoidreachtries[i] += 1
			else
				ms.avoidreachtries[i] = 1
			end
			ms.avoidreachtimes[i] = B.AAS_Time() + avoidtime
			return
		end
	end
	-- add the reachability to the reachabilities to avoid for a while
	for i = 0, BC.MAX_AVOIDREACH - 1 do
		if ms.avoidreachtimes[i] < B.AAS_Time() then
			ms.avoidreach[i] = number
			ms.avoidreachtimes[i] = B.AAS_Time() + avoidtime
			ms.avoidreachtries[i] = 1
			return
		end
	end
end

function B.DistanceFromLineSquared(p, lp1, lp2): number
	local proj = { [0] = 0, 0, 0 }
	local dir = { [0] = 0, 0, 0 }

	B.AAS_ProjectPointOntoVector(p, lp1, lp2, proj)
	local j = 0
	while j < 3 do
		if (proj[j] > lp1[j] and proj[j] > lp2[j]) or (proj[j] < lp1[j] and proj[j] < lp2[j]) then
			break
		end
		j += 1
	end
	if j < 3 then
		if math.abs(proj[j] - lp1[j]) < math.abs(proj[j] - lp2[j]) then
			Q.VectorSubtract(p, lp1, dir)
		else
			Q.VectorSubtract(p, lp2, dir)
		end
		return Q.VectorLengthSquared(dir)
	end
	Q.VectorSubtract(p, proj, dir)
	return Q.VectorLengthSquared(dir)
end

function B.VectorDistanceSquared(p1, p2): number
	local dir = { [0] = 0, 0, 0 }
	Q.VectorSubtract(p2, p1, dir)
	return Q.VectorLengthSquared(dir)
end

function B.BotAvoidSpots(origin, reach, avoidspots, numavoidspots: number): number
	local checkbetween
	local tt = bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK)
	if tt == BC.TRAVEL_WALK then checkbetween = true
	elseif tt == BC.TRAVEL_CROUCH then checkbetween = true
	elseif tt == BC.TRAVEL_BARRIERJUMP then checkbetween = true
	elseif tt == BC.TRAVEL_LADDER then checkbetween = true
	elseif tt == BC.TRAVEL_WALKOFFLEDGE then checkbetween = false
	elseif tt == BC.TRAVEL_JUMP then checkbetween = false
	elseif tt == BC.TRAVEL_SWIM then checkbetween = true
	elseif tt == BC.TRAVEL_WATERJUMP then checkbetween = true
	elseif tt == BC.TRAVEL_TELEPORT then checkbetween = false
	elseif tt == BC.TRAVEL_ELEVATOR then checkbetween = false
	elseif tt == BC.TRAVEL_GRAPPLEHOOK then checkbetween = false
	elseif tt == BC.TRAVEL_ROCKETJUMP then checkbetween = false
	elseif tt == BC.TRAVEL_BFGJUMP then checkbetween = false
	elseif tt == BC.TRAVEL_JUMPPAD then checkbetween = false
	elseif tt == BC.TRAVEL_FUNCBOB then checkbetween = false
	else checkbetween = true end

	local etype = BC.AVOID_CLEAR
	local squareddist = 0
	for i = 0, numavoidspots - 1 do
		local squaredradius = avoidspots[i].radius * avoidspots[i].radius
		squareddist = B.DistanceFromLineSquared(avoidspots[i].origin, origin, reach.start)
		-- if moving towards the avoid spot
		if squareddist < squaredradius and B.VectorDistanceSquared(avoidspots[i].origin, origin) > squareddist then
			etype = avoidspots[i].type
		elseif checkbetween then
			squareddist = B.DistanceFromLineSquared(avoidspots[i].origin, reach.start, reach.end_)
			-- if moving towards the avoid spot
			if squareddist < squaredradius and B.VectorDistanceSquared(avoidspots[i].origin, reach.start) > squareddist then
				etype = avoidspots[i].type
			end
		else
			B.VectorDistanceSquared(avoidspots[i].origin, reach.end_)
			-- if the reachability leads closer to the avoid spot
			if squareddist < squaredradius and B.VectorDistanceSquared(avoidspots[i].origin, reach.start) > squareddist then
				etype = avoidspots[i].type
			end
		end
		if etype == BC.AVOID_ALWAYS then
			return etype
		end
	end
	return etype
end

return nil
