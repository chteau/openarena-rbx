--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_move.c, part 5 of 5).

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
-- Luau port of be_ai_move.c lines 2858-3561 (JumpPad travel, MoveToGoal, state resets, setup/shutdown).

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local SF = B.FileStatics("be_ai_move")

local AVOIDREACH_TIME = 6

function B.BotTravel_JumpPad(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	hordir[0] = reach.start[0] - ms.origin[0]
	hordir[1] = reach.start[1] - ms.origin[1]
	hordir[2] = 0

	B.BotCheckBlocked(ms, hordir, true, result)
	B.EA_Move(ms.client, hordir, 400)
	Q.VectorCopy(hordir, result.movedir)

	return result
end

function B.BotFinishTravel_JumpPad(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	local ok, speed = B.BotAirControl(ms.origin, ms.velocity, reach.end_, hordir)
	if not ok or ok == 0 then
		hordir[0] = reach.end_[0] - ms.origin[0]
		hordir[1] = reach.end_[1] - ms.origin[1]
		hordir[2] = 0
		Q.VectorNormalizeIoq3(hordir)
		speed = 400
	end
	B.BotCheckBlocked(ms, hordir, true, result)
	B.EA_Move(ms.client, hordir, speed)
	Q.VectorCopy(hordir, result.movedir)

	return result
end

function B.BotReachabilityTime(reach)
	local t = bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK)
	if t == BC.TRAVEL_WALK then return 5
	elseif t == BC.TRAVEL_CROUCH then return 5
	elseif t == BC.TRAVEL_BARRIERJUMP then return 5
	elseif t == BC.TRAVEL_LADDER then return 6
	elseif t == BC.TRAVEL_WALKOFFLEDGE then return 5
	elseif t == BC.TRAVEL_JUMP then return 5
	elseif t == BC.TRAVEL_SWIM then return 5
	elseif t == BC.TRAVEL_WATERJUMP then return 5
	elseif t == BC.TRAVEL_TELEPORT then return 5
	elseif t == BC.TRAVEL_ELEVATOR then return 10
	elseif t == BC.TRAVEL_GRAPPLEHOOK then return 8
	elseif t == BC.TRAVEL_ROCKETJUMP then return 6
	elseif t == BC.TRAVEL_BFGJUMP then return 6
	elseif t == BC.TRAVEL_JUMPPAD then return 10
	elseif t == BC.TRAVEL_FUNCBOB then return 10
	end
	B.botimport.Print(BC.PRT_ERROR, "travel type %d not implemented yet\n", reach.traveltype)
	return 8
end

function B.BotMoveInGoalArea(ms, goal)
	local result = SB.bot_moveresult_t()
	local dir = { [0] = 0, 0, 0 }

	dir[0] = goal.origin[0] - ms.origin[0]
	dir[1] = goal.origin[1] - ms.origin[1]
	if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 then
		dir[2] = goal.origin[2] - ms.origin[2]
		result.traveltype = BC.TRAVEL_SWIM
	else
		dir[2] = 0
		result.traveltype = BC.TRAVEL_WALK
	end

	local dist = Q.VectorNormalizeIoq3(dir)
	if dist > 100 then dist = 100 end
	local speed = 400 - (400 - 4 * dist)
	if speed < 10 then speed = 0 end

	B.BotCheckBlocked(ms, dir, true, result)
	B.EA_Move(ms.client, dir, speed)
	Q.VectorCopy(dir, result.movedir)

	if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 then
		Q.vectoangles(dir, result.ideal_viewangles)
		result.flags = bit32.bor(result.flags, BC.MOVERESULT_SWIMVIEW)
	end

	ms.lastreachnum = 0
	ms.lastareanum = 0
	ms.lastgoalareanum = goal.areanum
	Q.VectorCopy(ms.origin, ms.lastorigin)

	return result
end

function B.BotMoveToGoal(result, movestate, goal, travelflags)
	local reachnum
	local lastreachnum
	local foundjumppad
	local ent
	local resultflags
	local reach = SB.aas_reachability_t()
	local lastreach = SB.aas_reachability_t()

	result.failure = false
	result.type = 0
	result.blocked = false
	result.blockentity = 0
	result.traveltype = 0
	result.flags = 0

	local ms = B.BotMoveStateFromHandle(movestate)
	if ms == nil then return end
	B.BotResetGrapple(ms)

	if goal == nil then
		result.failure = true
		return
	end
	ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(bit32.bor(BC.MFL_SWIMMING, BC.MFL_AGAINSTLADDER)))
	if B.AAS_OnGround(ms.origin, ms.presencetype, ms.entitynum) ~= 0 then
		ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_ONGROUND)
	end

	if bit32.band(ms.moveflags, BC.MFL_ONGROUND) ~= 0 then
		ent = B.BotOnTopOfEntity(ms)

		if ent ~= -1 then
			local modelnum = B.AAS_EntityModelindex(ent)
			if modelnum >= 0 and modelnum < BC.MAX_MODELS then
				local modeltype = SF.modeltypes[modelnum]

				if modeltype == SF.MODELTYPE_FUNC_PLAT then
					B.AAS_ReachabilityFromNum(ms.lastreachnum, reach)
					if bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK) ~= BC.TRAVEL_ELEVATOR or
						bit32.band(reach.facenum, 0x0000FFFF) ~= modelnum then
						reachnum = B.AAS_NextModelReachability(0, modelnum)
						if reachnum ~= 0 then
							B.AAS_ReachabilityFromNum(reachnum, reach)
							ms.lastreachnum = reachnum
							ms.reachability_time = B.AAS_Time() + B.BotReachabilityTime(reach)
						else
							if B.botDeveloper ~= 0 then
								B.botimport.Print(BC.PRT_MESSAGE, "client %d: on func_plat without reachability\n", ms.client)
							end
							result.blocked = true
							result.blockentity = ent
							result.flags = bit32.bor(result.flags, BC.MOVERESULT_ONTOPOFOBSTACLE)
							return
						end
					end
					result.flags = bit32.bor(result.flags, BC.MOVERESULT_ONTOPOF_ELEVATOR)
				elseif modeltype == SF.MODELTYPE_FUNC_BOB then
					B.AAS_ReachabilityFromNum(ms.lastreachnum, reach)
					if bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK) ~= BC.TRAVEL_FUNCBOB or
						bit32.band(reach.facenum, 0x0000FFFF) ~= modelnum then
						reachnum = B.AAS_NextModelReachability(0, modelnum)
						if reachnum ~= 0 then
							B.AAS_ReachabilityFromNum(reachnum, reach)
							ms.lastreachnum = reachnum
							ms.reachability_time = B.AAS_Time() + B.BotReachabilityTime(reach)
						else
							if B.botDeveloper ~= 0 then
								B.botimport.Print(BC.PRT_MESSAGE, "client %d: on func_bobbing without reachability\n", ms.client)
							end
							result.blocked = true
							result.blockentity = ent
							result.flags = bit32.bor(result.flags, BC.MOVERESULT_ONTOPOFOBSTACLE)
							return
						end
					end
					result.flags = bit32.bor(result.flags, BC.MOVERESULT_ONTOPOF_FUNCBOB)
				elseif modeltype == SF.MODELTYPE_FUNC_STATIC or modeltype == SF.MODELTYPE_FUNC_DOOR then
					ms.areanum = B.BotFuzzyPointReachabilityArea(ms.origin)
					if B.AAS_AreaReachability(ms.areanum) == 0 then
						result.blocked = true
						result.blockentity = ent
						result.flags = bit32.bor(result.flags, BC.MOVERESULT_ONTOPOFOBSTACLE)
						return
					end
				else
					result.blocked = true
					result.blockentity = ent
					result.flags = bit32.bor(result.flags, BC.MOVERESULT_ONTOPOFOBSTACLE)
					return
				end
			end
		end
	end
	if B.AAS_Swimming(ms.origin) ~= 0 then ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_SWIMMING) end
	if B.AAS_AgainstLadder(ms.origin) ~= 0 then ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_AGAINSTLADDER) end
	if bit32.band(ms.moveflags, bit32.bor(BC.MFL_ONGROUND, BC.MFL_SWIMMING, BC.MFL_AGAINSTLADDER)) ~= 0 then
		B.AAS_ReachabilityFromNum(ms.lastreachnum, lastreach)
		ms.areanum = B.BotFuzzyPointReachabilityArea(ms.origin)

		if ms.areanum == 0 then
			result.failure = true
			result.blocked = true
			result.blockentity = 0
			result.type = BC.RESULTTYPE_INSOLIDAREA
			return
		end
		if ms.areanum == goal.areanum then
			SB.copy_bot_moveresult_t(result, B.BotMoveInGoalArea(ms, goal))
			return
		end
		reachnum = ms.lastreachnum
		if reachnum ~= 0 then
			B.AAS_ReachabilityFromNum(reachnum, reach)
			local tt = bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK)
			if bit32.band(B.AAS_TravelFlagForType(reach.traveltype), travelflags) == 0 then
				reachnum = 0
			elseif tt == BC.TRAVEL_GRAPPLEHOOK then
				if ms.reachability_time < B.AAS_Time() or
					bit32.band(ms.moveflags, BC.MFL_GRAPPLERESET) ~= 0 then
					reachnum = 0
				end
			elseif tt == BC.TRAVEL_ELEVATOR or tt == BC.TRAVEL_FUNCBOB then
				if bit32.band(result.flags, BC.MOVERESULT_ONTOPOF_ELEVATOR) ~= 0 or
					bit32.band(result.flags, BC.MOVERESULT_ONTOPOF_FUNCBOB) ~= 0 then
					ms.reachability_time = B.AAS_Time() + 5
				end
				if ms.areanum == reach.areanum or
					ms.reachability_time < B.AAS_Time() then
					reachnum = 0
				end
			else
				if ms.lastgoalareanum ~= goal.areanum or
					ms.reachability_time < B.AAS_Time() or
					ms.lastareanum ~= ms.areanum then
					reachnum = 0
				end
			end
		end
		resultflags = 0
		if reachnum == 0 then
			reachnum, resultflags = B.BotGetReachabilityToGoal(ms.origin, ms.areanum,
				ms.lastgoalareanum, ms.lastareanum,
				ms.avoidreach, ms.avoidreachtimes, ms.avoidreachtries,
				goal, travelflags,
				ms.avoidspots, ms.numavoidspots, resultflags)
			ms.reachareanum = ms.areanum
			ms.jumpreach = 0
			ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_GRAPPLERESET))
			if reachnum ~= 0 then
				B.AAS_ReachabilityFromNum(reachnum, reach)
				ms.reachability_time = B.AAS_Time() + B.BotReachabilityTime(reach)
				B.BotAddToAvoidReach(ms, reachnum, AVOIDREACH_TIME)
			end
		end
		ms.lastreachnum = reachnum
		ms.lastgoalareanum = goal.areanum
		ms.lastareanum = ms.areanum
		if reachnum ~= 0 then
			B.AAS_ReachabilityFromNum(reachnum, reach)
			result.traveltype = reach.traveltype
			local tt = bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK)
			if tt == BC.TRAVEL_WALK then SB.copy_bot_moveresult_t(result, B.BotTravel_Walk(ms, reach))
			elseif tt == BC.TRAVEL_CROUCH then SB.copy_bot_moveresult_t(result, B.BotTravel_Crouch(ms, reach))
			elseif tt == BC.TRAVEL_BARRIERJUMP then SB.copy_bot_moveresult_t(result, B.BotTravel_BarrierJump(ms, reach))
			elseif tt == BC.TRAVEL_LADDER then SB.copy_bot_moveresult_t(result, B.BotTravel_Ladder(ms, reach))
			elseif tt == BC.TRAVEL_WALKOFFLEDGE then SB.copy_bot_moveresult_t(result, B.BotTravel_WalkOffLedge(ms, reach))
			elseif tt == BC.TRAVEL_JUMP then SB.copy_bot_moveresult_t(result, B.BotTravel_Jump(ms, reach))
			elseif tt == BC.TRAVEL_SWIM then SB.copy_bot_moveresult_t(result, B.BotTravel_Swim(ms, reach))
			elseif tt == BC.TRAVEL_WATERJUMP then SB.copy_bot_moveresult_t(result, B.BotTravel_WaterJump(ms, reach))
			elseif tt == BC.TRAVEL_TELEPORT then SB.copy_bot_moveresult_t(result, B.BotTravel_Teleport(ms, reach))
			elseif tt == BC.TRAVEL_ELEVATOR then SB.copy_bot_moveresult_t(result, B.BotTravel_Elevator(ms, reach))
			elseif tt == BC.TRAVEL_GRAPPLEHOOK then SB.copy_bot_moveresult_t(result, B.BotTravel_Grapple(ms, reach))
			elseif tt == BC.TRAVEL_ROCKETJUMP then SB.copy_bot_moveresult_t(result, B.BotTravel_RocketJump(ms, reach))
			elseif tt == BC.TRAVEL_BFGJUMP then SB.copy_bot_moveresult_t(result, B.BotTravel_BFGJump(ms, reach))
			elseif tt == BC.TRAVEL_JUMPPAD then SB.copy_bot_moveresult_t(result, B.BotTravel_JumpPad(ms, reach))
			elseif tt == BC.TRAVEL_FUNCBOB then SB.copy_bot_moveresult_t(result, B.BotTravel_FuncBobbing(ms, reach))
			else
				B.botimport.Print(BC.PRT_FATAL, "travel type %d not implemented yet\n", tt)
			end
			result.traveltype = reach.traveltype
			result.flags = bit32.bor(result.flags, resultflags)
		else
			result.failure = true
			result.flags = bit32.bor(result.flags, resultflags)
			SB.copy_aas_reachability_t(reach, SB.aas_reachability_t())
		end
	else
		local areas = {}
		local end_ = { [0] = 0, 0, 0 }

		foundjumppad = false
		Q.VectorMA(ms.origin, -2 * ms.thinktime, ms.velocity, end_)
		local numareas = B.AAS_TraceAreas(ms.origin, end_, areas, nil, 16)
		local i = numareas - 1
		while i >= 0 do
			if B.AAS_AreaJumpPad(areas[i]) ~= 0 then
				foundjumppad = true
				lastreachnum = B.BotGetReachabilityToGoal(end_, areas[i],
					ms.lastgoalareanum, ms.lastareanum,
					ms.avoidreach, ms.avoidreachtimes, ms.avoidreachtries,
					goal, BC.TFL_JUMPPAD, ms.avoidspots, ms.numavoidspots, nil)
				if lastreachnum ~= 0 then
					ms.lastreachnum = lastreachnum
					ms.lastareanum = areas[i]
					break
				else
					lastreachnum = B.AAS_NextAreaReachability(areas[i], 0)
					while lastreachnum ~= 0 do
						B.AAS_ReachabilityFromNum(lastreachnum, reach)
						if bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK) == BC.TRAVEL_JUMPPAD then
							ms.lastreachnum = lastreachnum
							ms.lastareanum = areas[i]
						end
						lastreachnum = B.AAS_NextAreaReachability(areas[i], lastreachnum)
					end
					if lastreachnum ~= 0 then break end
				end
			end
			i = i - 1
		end
		if B.botDeveloper ~= 0 then
			if foundjumppad and ms.lastreachnum == 0 then
				B.botimport.Print(BC.PRT_MESSAGE, "client %d didn't find jumppad reachability\n", ms.client)
			end
		end

		if ms.lastreachnum ~= 0 then
			B.AAS_ReachabilityFromNum(ms.lastreachnum, reach)
			result.traveltype = reach.traveltype
			local tt = bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK)
			if tt == BC.TRAVEL_WALK then SB.copy_bot_moveresult_t(result, B.BotTravel_Walk(ms, reach))
			elseif tt == BC.TRAVEL_CROUCH then -- do nothing
			elseif tt == BC.TRAVEL_BARRIERJUMP then SB.copy_bot_moveresult_t(result, B.BotFinishTravel_BarrierJump(ms, reach))
			elseif tt == BC.TRAVEL_LADDER then SB.copy_bot_moveresult_t(result, B.BotTravel_Ladder(ms, reach))
			elseif tt == BC.TRAVEL_WALKOFFLEDGE then SB.copy_bot_moveresult_t(result, B.BotFinishTravel_WalkOffLedge(ms, reach))
			elseif tt == BC.TRAVEL_JUMP then SB.copy_bot_moveresult_t(result, B.BotFinishTravel_Jump(ms, reach))
			elseif tt == BC.TRAVEL_SWIM then SB.copy_bot_moveresult_t(result, B.BotTravel_Swim(ms, reach))
			elseif tt == BC.TRAVEL_WATERJUMP then SB.copy_bot_moveresult_t(result, B.BotFinishTravel_WaterJump(ms, reach))
			elseif tt == BC.TRAVEL_TELEPORT then -- do nothing
			elseif tt == BC.TRAVEL_ELEVATOR then SB.copy_bot_moveresult_t(result, B.BotFinishTravel_Elevator(ms, reach))
			elseif tt == BC.TRAVEL_GRAPPLEHOOK then SB.copy_bot_moveresult_t(result, B.BotTravel_Grapple(ms, reach))
			elseif tt == BC.TRAVEL_ROCKETJUMP or tt == BC.TRAVEL_BFGJUMP then
				SB.copy_bot_moveresult_t(result, B.BotFinishTravel_WeaponJump(ms, reach))
			elseif tt == BC.TRAVEL_JUMPPAD then SB.copy_bot_moveresult_t(result, B.BotFinishTravel_JumpPad(ms, reach))
			elseif tt == BC.TRAVEL_FUNCBOB then SB.copy_bot_moveresult_t(result, B.BotFinishTravel_FuncBobbing(ms, reach))
			else
				B.botimport.Print(BC.PRT_FATAL, "(last) travel type %d not implemented yet\n", tt)
			end
			result.traveltype = reach.traveltype
		end
	end
	if result.blocked then ms.reachability_time = ms.reachability_time - 10 * ms.thinktime end
	Q.VectorCopy(ms.origin, ms.lastorigin)
end

function B.BotResetAvoidReach(movestate)
	local ms = B.BotMoveStateFromHandle(movestate)
	if ms == nil then return end
	for i = 0, BC.MAX_AVOIDREACH - 1 do
		ms.avoidreach[i] = 0
		ms.avoidreachtimes[i] = 0
		ms.avoidreachtries[i] = 0
	end
end

function B.BotResetLastAvoidReach(movestate)
	local ms = B.BotMoveStateFromHandle(movestate)
	if ms == nil then return end
	local latesttime = 0
	local latest = 0
	for i = 0, BC.MAX_AVOIDREACH - 1 do
		if ms.avoidreachtimes[i] > latesttime then
			latesttime = ms.avoidreachtimes[i]
			latest = i
		end
	end
	if latesttime ~= 0 then
		ms.avoidreachtimes[latest] = 0
		if ms.avoidreachtries[latest] > 0 then ms.avoidreachtries[latest] = ms.avoidreachtries[latest] - 1 end
	end
end

function B.BotResetMoveState(movestate)
	local ms = B.BotMoveStateFromHandle(movestate)
	if ms == nil then return end
	SB.copy_bot_movestate_t(ms, SB.bot_movestate_t())
end

function B.BotSetupMoveAI()
	B.BotSetBrushModelTypes()
	SF.sv_maxstep = B.LibVar("sv_step", "18")
	SF.sv_maxbarrier = B.LibVar("sv_maxbarrier", "32")
	SF.sv_gravity = B.LibVar("sv_gravity", "800")
	SF.weapindex_rocketlauncher = B.LibVar("weapindex_rocketlauncher", "5")
	SF.weapindex_bfg10k = B.LibVar("weapindex_bfg10k", "9")
	SF.weapindex_grapple = B.LibVar("weapindex_grapple", "10")
	SF.entitytypemissile = B.LibVar("entitytypemissile", "3")
	SF.offhandgrapple = B.LibVar("offhandgrapple", "0")
	SF.cmd_grappleon = B.LibVar("cmd_grappleon", "grappleon")
	SF.cmd_grappleoff = B.LibVar("cmd_grappleoff", "grappleoff")
	return BC.BLERR_NOERROR
end

function B.BotShutdownMoveAI()
	for i = 1, BC.MAX_CLIENTS do
		if SF.botmovestates[i] ~= nil then
			SF.botmovestates[i] = nil
		end
	end
end

return nil
