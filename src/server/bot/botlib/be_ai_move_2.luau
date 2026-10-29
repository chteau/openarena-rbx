--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_move.c, part 2 of 5).

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
-- Luau port of be_ai_move.c (botlib/be_ai_move.c, part 2 of 5): avoid spots, reachability to goal, gap/barrier checks, walking.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local SF = B.FileStatics("be_ai_move")

local AVOIDREACH_TRIES = 4
local PREDICTIONTIME_JUMP = 3

function B.BotAddAvoidSpot(movestate, origin, radius, type_)
	local ms = B.BotMoveStateFromHandle(movestate)
	if ms == nil then return end
	if type_ == BC.AVOID_CLEAR then
		ms.numavoidspots = 0
		return
	end

	if ms.numavoidspots >= BC.MAX_AVOIDSPOTS then
		return
	end
	local spot = ms.avoidspots[ms.numavoidspots]
	Q.VectorCopy(origin, spot.origin)
	spot.radius = radius
	spot.type = type_
	ms.numavoidspots = ms.numavoidspots + 1
end

function B.BotGetReachabilityToGoal(origin, areanum, lastgoalareanum, lastareanum, avoidreach, avoidreachtimes, avoidreachtries, goal, travelflags, avoidspots, numavoidspots, flags)
	local reach = SB.aas_reachability_t()

	if areanum == 0 then return 0, flags end
	if B.AAS_AreaDoNotEnter(areanum) ~= 0 or B.AAS_AreaDoNotEnter(goal.areanum) ~= 0 then
		travelflags = bit32.bor(travelflags, BC.TFL_DONOTENTER)
	end
	local besttime = 0
	local bestreachnum = 0
	local reachnum = B.AAS_NextAreaReachability(areanum, 0)
	while reachnum ~= 0 do
		local skip = false
		local i = 0
		while i < BC.MAX_AVOIDREACH do
			if avoidreach[i] == reachnum and avoidreachtimes[i] >= B.AAS_Time() then break end
			i = i + 1
		end
		if i ~= BC.MAX_AVOIDREACH and avoidreachtries[i] > AVOIDREACH_TRIES then
			skip = true
		end
		if not skip then
			B.AAS_ReachabilityFromNum(reachnum, reach)
			if lastgoalareanum == goal.areanum and reach.areanum == lastareanum then
				skip = true
			end
		end
		if not skip then
			if not B.BotValidTravel(origin, reach, travelflags) then
				skip = true
			end
		end
		if not skip then
			local t = B.AAS_AreaTravelTimeToGoalArea(reach.areanum, reach.end_, goal.areanum, travelflags)
			if t == 0 then
				skip = true
			else
				if B.BotAvoidSpots(origin, reach, avoidspots, numavoidspots) ~= 0 then
					if flags ~= nil then
						flags = bit32.bor(flags, BC.MOVERESULT_BLOCKEDBYAVOIDSPOT)
					end
				else
					t = t + reach.traveltime
					if besttime == 0 or t < besttime then
						besttime = t
						bestreachnum = reachnum
					end
				end
			end
		end
		reachnum = B.AAS_NextAreaReachability(areanum, reachnum)
	end
	return bestreachnum, flags
end

function B.BotAddToTarget(start, end_, maxdist, dist, target)
	local dir = {[0] = 0, 0, 0}

	Q.VectorSubtract(end_, start, dir)
	local curdist = Q.VectorNormalizeIoq3(dir)
	if dist + curdist < maxdist then
		Q.VectorCopy(end_, target)
		dist = dist + curdist
		return 0, dist
	else
		Q.VectorMA(start, maxdist - dist, dir, target)
		dist = maxdist
		return 1, dist
	end
end

function B.BotMovementViewTarget(movestate, goal, travelflags, lookahead, target)
	local reach = SB.aas_reachability_t()
	local end_ = {[0] = 0, 0, 0}

	local ms = B.BotMoveStateFromHandle(movestate)
	if ms == nil then return 0 end
	if ms.lastreachnum == 0 or goal == nil then return 0 end

	local reachnum = ms.lastreachnum
	Q.VectorCopy(ms.origin, end_)
	local lastareanum = ms.lastareanum
	local dist = 0
	while reachnum ~= 0 and dist < lookahead do
		B.AAS_ReachabilityFromNum(reachnum, reach)
		local r
		r, dist = B.BotAddToTarget(end_, reach.start, lookahead, dist, target)
		if r ~= 0 then return 1 end
		local tt = bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK)
		if tt == BC.TRAVEL_TELEPORT then return 1 end
		if tt == BC.TRAVEL_ROCKETJUMP then return 1 end
		if tt == BC.TRAVEL_BFGJUMP then return 1 end
		if tt ~= BC.TRAVEL_JUMPPAD and tt ~= BC.TRAVEL_ELEVATOR and tt ~= BC.TRAVEL_FUNCBOB then
			r, dist = B.BotAddToTarget(reach.start, reach.end_, lookahead, dist, target)
			if r ~= 0 then return 1 end
		end
		reachnum = B.BotGetReachabilityToGoal(reach.end_, reach.areanum, ms.lastgoalareanum, lastareanum, ms.avoidreach, ms.avoidreachtimes, ms.avoidreachtries, goal, travelflags, nil, 0, nil)
		Q.VectorCopy(reach.end_, end_)
		lastareanum = reach.areanum
		if lastareanum == goal.areanum then
			r, dist = B.BotAddToTarget(reach.end_, goal.origin, lookahead, dist, target)
			return 1
		end
	end
	return 0
end

function B.BotVisible(ent, eye, target)
	local trace = B.AAS_Trace(eye, nil, nil, target, ent, bit32.bor(BC.CONTENTS_SOLID, BC.CONTENTS_PLAYERCLIP))
	if trace.fraction >= 1 then return 1 end
	return 0
end

function B.BotPredictVisiblePosition(origin, areanum, goal, travelflags, target)
	local reach = SB.aas_reachability_t()
	local avoidreach = B.zeros(BC.MAX_AVOIDREACH)
	local avoidreachtimes = B.zeros(BC.MAX_AVOIDREACH)
	local avoidreachtries = B.zeros(BC.MAX_AVOIDREACH)
	local end_ = {[0] = 0, 0, 0}

	if goal == nil then return 0 end
	if areanum == 0 then return 0 end
	if goal.areanum == 0 then return 0 end

	local lastgoalareanum = goal.areanum
	local lastareanum = areanum
	Q.VectorCopy(origin, end_)
	local i = 0
	while i < 20 and areanum ~= goal.areanum do
		local reachnum = B.BotGetReachabilityToGoal(end_, areanum, lastgoalareanum, lastareanum, avoidreach, avoidreachtimes, avoidreachtries, goal, travelflags, nil, 0, nil)
		if reachnum == 0 then return 0 end
		B.AAS_ReachabilityFromNum(reachnum, reach)
		if B.BotVisible(goal.entitynum, goal.origin, reach.start) ~= 0 then
			Q.VectorCopy(reach.start, target)
			return 1
		end
		if B.BotVisible(goal.entitynum, goal.origin, reach.end_) ~= 0 then
			Q.VectorCopy(reach.end_, target)
			return 1
		end
		if reach.areanum == goal.areanum then
			Q.VectorCopy(reach.end_, target)
			return 1
		end
		lastareanum = areanum
		areanum = reach.areanum
		Q.VectorCopy(reach.end_, end_)
		i = i + 1
	end
	return 0
end

function B.MoverBottomCenter(reach, bottomcenter)
	local mins = {[0] = 0, 0, 0}
	local maxs = {[0] = 0, 0, 0}
	local origin = {[0] = 0, 0, 0}
	local mids = {[0] = 0, 0, 0}
	local angles = {[0] = 0, 0, 0}

	local modelnum = bit32.band(reach.facenum, 0x0000FFFF)
	B.AAS_BSPModelMinsMaxsOrigin(modelnum, angles, mins, maxs, origin)
	if B.AAS_OriginOfMoverWithModelNum(modelnum, origin) == 0 then
		B.botimport.Print(BC.PRT_MESSAGE, "no entity with model %d\n", modelnum)
	end
	Q.VectorAdd(mins, maxs, mids)
	Q.VectorMA(origin, 0.5, mids, bottomcenter)
	bottomcenter[2] = reach.start[2]
end

function B.BotGapDistance(origin, hordir, entnum)
	local start = {[0] = 0, 0, 0}
	local end_ = {[0] = 0, 0, 0}
	local startz

	do
		Q.VectorCopy(origin, start)
		Q.VectorCopy(origin, end_)
		end_[2] = end_[2] - 60
		local trace = B.AAS_TraceClientBBox(start, end_, BC.PRESENCE_CROUCH, entnum)
		if trace.fraction >= 1 then return 1 end
		startz = trace.endpos[2] + 1
	end
	local dist = 8
	while dist <= 100 do
		Q.VectorMA(origin, dist, hordir, start)
		start[2] = startz + 24
		Q.VectorCopy(start, end_)
		end_[2] = end_[2] - (48 + SF.sv_maxbarrier.value)
		local trace = B.AAS_TraceClientBBox(start, end_, BC.PRESENCE_CROUCH, entnum)
		if not trace.startsolid then
			if trace.endpos[2] < startz - SF.sv_maxstep.value - 8 then
				Q.VectorCopy(trace.endpos, end_)
				end_[2] = end_[2] - 20
				if bit32.band(B.AAS_PointContents(end_), BC.CONTENTS_WATER) ~= 0 then break end
				return dist
			end
			startz = trace.endpos[2]
		end
		dist = dist + 8
	end
	return 0
end

function B.BotCheckBarrierJump(ms, dir, speed)
	local start = {[0] = 0, 0, 0}
	local hordir = {[0] = 0, 0, 0}
	local end_ = {[0] = 0, 0, 0}

	Q.VectorCopy(ms.origin, end_)
	end_[2] = end_[2] + SF.sv_maxbarrier.value
	local trace = B.AAS_TraceClientBBox(ms.origin, end_, BC.PRESENCE_NORMAL, ms.entitynum)
	if trace.startsolid then return 0 end
	if trace.endpos[2] - ms.origin[2] < SF.sv_maxstep.value then return 0 end
	hordir[0] = dir[0]
	hordir[1] = dir[1]
	hordir[2] = 0
	Q.VectorNormalizeIoq3(hordir)
	Q.VectorMA(ms.origin, ms.thinktime * speed * 0.5, hordir, end_)
	Q.VectorCopy(trace.endpos, start)
	end_[2] = trace.endpos[2]
	trace = B.AAS_TraceClientBBox(start, end_, BC.PRESENCE_NORMAL, ms.entitynum)
	if trace.startsolid then return 0 end
	Q.VectorCopy(trace.endpos, start)
	Q.VectorCopy(trace.endpos, end_)
	end_[2] = ms.origin[2]
	trace = B.AAS_TraceClientBBox(start, end_, BC.PRESENCE_NORMAL, ms.entitynum)
	if trace.startsolid then return 0 end
	if trace.fraction >= 1.0 then return 0 end
	if trace.endpos[2] - ms.origin[2] < SF.sv_maxstep.value then return 0 end
	B.EA_Jump(ms.client)
	B.EA_Move(ms.client, hordir, speed)
	ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_BARRIERJUMP)
	return 1
end

function B.BotSwimInDirection(ms, dir, speed, type_)
	local normdir = {[0] = 0, 0, 0}

	Q.VectorCopy(dir, normdir)
	Q.VectorNormalizeIoq3(normdir)
	B.EA_Move(ms.client, normdir, speed)
	return 1
end

function B.BotWalkInDirection(ms, dir, speed, type_)
	local hordir = {[0] = 0, 0, 0}
	local cmdmove = {[0] = 0, 0, 0}
	local velocity = {[0] = 0, 0, 0}
	local tmpdir = {[0] = 0, 0, 0}
	local origin = {[0] = 0, 0, 0}
	local presencetype, maxframes, cmdframes, stopevent
	local move = SB.aas_clientmove_t()

	if B.AAS_OnGround(ms.origin, ms.presencetype, ms.entitynum) ~= 0 then
		ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_ONGROUND)
	end
	if bit32.band(ms.moveflags, BC.MFL_ONGROUND) ~= 0 then
		if B.BotCheckBarrierJump(ms, dir, speed) ~= 0 then return 1 end
		ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_BARRIERJUMP))
		if bit32.band(type_, BC.MOVE_CROUCH) ~= 0 and bit32.band(type_, BC.MOVE_JUMP) == 0 then
			presencetype = BC.PRESENCE_CROUCH
		else
			presencetype = BC.PRESENCE_NORMAL
		end
		hordir[0] = dir[0]
		hordir[1] = dir[1]
		hordir[2] = 0
		Q.VectorNormalizeIoq3(hordir)
		if bit32.band(type_, BC.MOVE_JUMP) == 0 then
			if B.BotGapDistance(ms.origin, hordir, ms.entitynum) > 0 then
				type_ = bit32.bor(type_, BC.MOVE_JUMP)
			end
		end
		Q.VectorScale(hordir, speed, cmdmove)
		Q.VectorCopy(ms.velocity, velocity)
		if bit32.band(type_, BC.MOVE_JUMP) ~= 0 then
			cmdmove[2] = 400
			maxframes = Q.trunc(PREDICTIONTIME_JUMP / 0.1)
			cmdframes = 1
			stopevent = bit32.bor(BC.SE_HITGROUND, BC.SE_HITGROUNDDAMAGE, BC.SE_ENTERWATER, BC.SE_ENTERSLIME, BC.SE_ENTERLAVA)
		else
			maxframes = 2
			cmdframes = 2
			stopevent = bit32.bor(BC.SE_HITGROUNDDAMAGE, BC.SE_ENTERWATER, BC.SE_ENTERSLIME, BC.SE_ENTERLAVA)
		end
		Q.VectorCopy(ms.origin, origin)
		origin[2] = origin[2] + 0.5
		B.AAS_PredictClientMovement(move, ms.entitynum, origin, presencetype, 1, velocity, cmdmove, cmdframes, maxframes, Q.f(0.1), stopevent, 0, 0)
		if move.frames >= maxframes and bit32.band(type_, BC.MOVE_JUMP) ~= 0 then
			return 0
		end
		if bit32.band(move.stopevent, bit32.bor(BC.SE_ENTERSLIME, BC.SE_ENTERLAVA, BC.SE_HITGROUNDDAMAGE)) ~= 0 then
			return 0
		end
		if bit32.band(move.stopevent, BC.SE_HITGROUND) ~= 0 then
			Q.VectorNormalize2Ioq3(move.velocity, tmpdir)
			local dist = B.BotGapDistance(move.endpos, tmpdir, ms.entitynum)
			if dist > 0 then return 0 end
			dist = B.BotGapDistance(move.endpos, hordir, ms.entitynum)
			if dist > 0 then return 0 end
		end
		tmpdir[0] = move.endpos[0] - ms.origin[0]
		tmpdir[1] = move.endpos[1] - ms.origin[1]
		tmpdir[2] = 0
		if Q.VectorLength(tmpdir) < speed * ms.thinktime * 0.5 then return 0 end
		if bit32.band(type_, BC.MOVE_JUMP) ~= 0 then B.EA_Jump(ms.client) end
		if bit32.band(type_, BC.MOVE_CROUCH) ~= 0 then B.EA_Crouch(ms.client) end
		B.EA_Move(ms.client, hordir, speed)
		return 1
	else
		if bit32.band(ms.moveflags, BC.MFL_BARRIERJUMP) ~= 0 then
			if ms.velocity[2] < 50 then
				B.EA_Move(ms.client, dir, speed)
			end
		end
		return 1
	end
end

function B.BotMoveInDirection(movestate, dir, speed, type_)
	local ms = B.BotMoveStateFromHandle(movestate)
	if ms == nil then return 0 end
	if B.AAS_Swimming(ms.origin) ~= 0 then
		return B.BotSwimInDirection(ms, dir, speed, type_)
	else
		return B.BotWalkInDirection(ms, dir, speed, type_)
	end
end

function B.Intersection(p1, p2, p3, p4, out)
	local dx1 = p2[0] - p1[0]
	local dy1 = p2[1] - p1[1]
	local dx2 = p4[0] - p3[0]
	local dy2 = p4[1] - p3[1]

	local d = dy1 * dx2 - dx1 * dy2
	if d ~= 0 then
		local x1 = p1[1] * dx1 - p1[0] * dy1
		local x2 = p3[1] * dx2 - p3[0] * dy2
		out[0] = Q.trunc((dx1 * x2 - dx2 * x1) / d)
		out[1] = Q.trunc((dy1 * x2 - dy2 * x1) / d)
		return 1
	else
		return 0
	end
end

function B.BotCheckBlocked(ms, dir, checkbottom, result)
	local mins = {[0] = 0, 0, 0}
	local maxs = {[0] = 0, 0, 0}
	local end_ = {[0] = 0, 0, 0}
	local up = {[0] = 0, 0, 1}

	B.AAS_PresenceTypeBoundingBox(ms.presencetype, mins, maxs)
	if math.abs(Q.DotProduct(dir, up)) < 0.7 then
		mins[2] = mins[2] + SF.sv_maxstep.value
		maxs[2] = maxs[2] - 10
	end
	Q.VectorMA(ms.origin, 3, dir, end_)
	local trace = B.AAS_Trace(ms.origin, mins, maxs, end_, ms.entitynum, bit32.bor(BC.CONTENTS_SOLID, BC.CONTENTS_PLAYERCLIP, BC.CONTENTS_BODY))
	if not trace.startsolid and (trace.ent ~= BC.ENTITYNUM_WORLD and trace.ent ~= BC.ENTITYNUM_NONE) then
		result.blocked = 1
		result.blockentity = trace.ent
	elseif checkbottom ~= 0 and B.AAS_AreaReachability(ms.areanum) == 0 then
		B.AAS_PresenceTypeBoundingBox(ms.presencetype, mins, maxs)
		Q.VectorMA(ms.origin, -3, up, end_)
		trace = B.AAS_Trace(ms.origin, mins, maxs, end_, ms.entitynum, bit32.bor(BC.CONTENTS_SOLID, BC.CONTENTS_PLAYERCLIP))
		if not trace.startsolid and (trace.ent ~= BC.ENTITYNUM_WORLD and trace.ent ~= BC.ENTITYNUM_NONE) then
			result.blocked = 1
			result.blockentity = trace.ent
			result.flags = bit32.bor(result.flags, BC.MOVERESULT_ONTOPOFOBSTACLE)
		end
	end
end

function B.BotTravel_Walk(ms, reach)
	local hordir = {[0] = 0, 0, 0}
	local speed
	local result = SB.bot_moveresult_t()

	hordir[0] = reach.start[0] - ms.origin[0]
	hordir[1] = reach.start[1] - ms.origin[1]
	hordir[2] = 0
	local dist = Q.VectorNormalizeIoq3(hordir)
	B.BotCheckBlocked(ms, hordir, 1, result)
	if dist < 10 then
		hordir[0] = reach.end_[0] - ms.origin[0]
		hordir[1] = reach.end_[1] - ms.origin[1]
		hordir[2] = 0
		dist = Q.VectorNormalizeIoq3(hordir)
	end
	if bit32.band(B.AAS_AreaPresenceType(reach.areanum), BC.PRESENCE_NORMAL) == 0 then
		if dist < 20 then B.EA_Crouch(ms.client) end
	end
	dist = B.BotGapDistance(ms.origin, hordir, ms.entitynum)
	if bit32.band(ms.moveflags, BC.MFL_WALK) ~= 0 then
		if dist > 0 then speed = 200 - (180 - 1 * dist)
		else speed = 200 end
		B.EA_Walk(ms.client)
	else
		if dist > 0 then speed = 400 - (360 - 2 * dist)
		else speed = 400 end
	end
	B.EA_Move(ms.client, hordir, speed)
	Q.VectorCopy(hordir, result.movedir)
	return result
end

function B.BotFinishTravel_Walk(ms, reach)
	local hordir = {[0] = 0, 0, 0}
	local result = SB.bot_moveresult_t()

	hordir[0] = reach.end_[0] - ms.origin[0]
	hordir[1] = reach.end_[1] - ms.origin[1]
	hordir[2] = 0
	local dist = Q.VectorNormalizeIoq3(hordir)
	if dist > 100 then dist = 100 end
	local speed = 400 - (400 - 3 * dist)
	B.EA_Move(ms.client, hordir, speed)
	Q.VectorCopy(hordir, result.movedir)
	return result
end

return nil
