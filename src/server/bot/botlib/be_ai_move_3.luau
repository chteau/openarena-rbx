--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_move.c, part 3 of 5).

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
-- Luau port of be_ai_move.c lines 1411-2187: crouch, barrier jump, swim, water jump, ledge, jump, ladder, teleport and elevator travel.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local SF = B.FileStatics("be_ai_move")

function B.BotTravel_Crouch(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	local speed = 400
	-- walk straight to reachability end
	hordir[0] = reach.end_[0] - ms.origin[0]
	hordir[1] = reach.end_[1] - ms.origin[1]
	hordir[2] = 0
	Q.VectorNormalizeIoq3(hordir)
	--
	B.BotCheckBlocked(ms, hordir, 1, result)
	-- elemantary actions
	B.EA_Crouch(ms.client)
	B.EA_Move(ms.client, hordir, speed)
	--
	Q.VectorCopy(hordir, result.movedir)
	--
	return result
end

function B.BotTravel_BarrierJump(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	-- walk straight to reachability start
	hordir[0] = reach.start[0] - ms.origin[0]
	hordir[1] = reach.start[1] - ms.origin[1]
	hordir[2] = 0
	local dist = Q.VectorNormalizeIoq3(hordir)
	--
	B.BotCheckBlocked(ms, hordir, 1, result)
	-- if pretty close to the barrier
	if dist < 9 then
		B.EA_Jump(ms.client)
	else
		if dist > 60 then dist = 60 end
		local speed = 360 - (360 - 6 * dist)
		B.EA_Move(ms.client, hordir, speed)
	end
	Q.VectorCopy(hordir, result.movedir)
	--
	return result
end

function B.BotFinishTravel_BarrierJump(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	-- if near the top or going down
	if ms.velocity[2] < 250 then
		hordir[0] = reach.end_[0] - ms.origin[0]
		hordir[1] = reach.end_[1] - ms.origin[1]
		hordir[2] = 0
		--
		B.BotCheckBlocked(ms, hordir, 1, result)
		--
		B.EA_Move(ms.client, hordir, 400)
		Q.VectorCopy(hordir, result.movedir)
	end
	--
	return result
end

function B.BotTravel_Swim(ms, reach)
	local dir = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	-- swim straight to reachability end
	Q.VectorSubtract(reach.start, ms.origin, dir)
	Q.VectorNormalizeIoq3(dir)
	--
	B.BotCheckBlocked(ms, dir, 1, result)
	-- elemantary actions
	B.EA_Move(ms.client, dir, 400)
	--
	Q.VectorCopy(dir, result.movedir)
	Q.vectoangles(dir, result.ideal_viewangles)
	result.flags = bit32.bor(result.flags, BC.MOVERESULT_SWIMVIEW)
	--
	return result
end

function B.BotTravel_WaterJump(ms, reach)
	local dir = { [0] = 0, 0, 0 }
	local hordir = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	-- swim straight to reachability end
	Q.VectorSubtract(reach.end_, ms.origin, dir)
	Q.VectorCopy(dir, hordir)
	hordir[2] = 0
	dir[2] = dir[2] + (15 + Q.crandom() * 40)
	Q.VectorNormalizeIoq3(dir)
	local dist = Q.VectorNormalizeIoq3(hordir)
	-- elemantary actions
	B.EA_MoveForward(ms.client)
	-- move up if close to the actual out of water jump spot
	if dist < 40 then B.EA_MoveUp(ms.client) end
	-- set the ideal view angles
	Q.vectoangles(dir, result.ideal_viewangles)
	result.flags = bit32.bor(result.flags, BC.MOVERESULT_MOVEMENTVIEW)
	--
	Q.VectorCopy(dir, result.movedir)
	--
	return result
end

function B.BotFinishTravel_WaterJump(ms, reach)
	local dir = { [0] = 0, 0, 0 }
	local pnt = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	-- if waterjumping there's nothing to do
	if bit32.band(ms.moveflags, BC.MFL_WATERJUMP) ~= 0 then return result end
	-- if not touching any water anymore don't do anything
	-- otherwise the bot sometimes keeps jumping?
	Q.VectorCopy(ms.origin, pnt)
	pnt[2] = pnt[2] - 32 -- extra for q2dm4 near red armor/mega health
	if bit32.band(B.AAS_PointContents(pnt), bit32.bor(BC.CONTENTS_LAVA, BC.CONTENTS_SLIME, BC.CONTENTS_WATER)) == 0 then
		return result
	end
	-- swim straight to reachability end
	Q.VectorSubtract(reach.end_, ms.origin, dir)
	dir[0] = dir[0] + Q.crandom() * 10
	dir[1] = dir[1] + Q.crandom() * 10
	dir[2] = dir[2] + (70 + Q.crandom() * 10)
	-- elemantary actions
	B.EA_Move(ms.client, dir, 400)
	-- set the ideal view angles
	Q.vectoangles(dir, result.ideal_viewangles)
	result.flags = bit32.bor(result.flags, BC.MOVERESULT_MOVEMENTVIEW)
	--
	Q.VectorCopy(dir, result.movedir)
	--
	return result
end

function B.BotTravel_WalkOffLedge(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local dir = { [0] = 0, 0, 0 }
	local speed = 0
	local result = SB.bot_moveresult_t()

	-- check if the bot is blocked by anything
	Q.VectorSubtract(reach.start, ms.origin, dir)
	Q.VectorNormalizeIoq3(dir)
	B.BotCheckBlocked(ms, dir, 1, result)
	-- if the reachability start and end are practically above each other
	Q.VectorSubtract(reach.end_, reach.start, dir)
	dir[2] = 0
	local reachhordist = Q.VectorLength(dir)
	-- walk straight to the reachability start
	hordir[0] = reach.start[0] - ms.origin[0]
	hordir[1] = reach.start[1] - ms.origin[1]
	hordir[2] = 0
	local dist = Q.VectorNormalizeIoq3(hordir)
	-- if pretty close to the start focus on the reachability end
	if dist < 48 then
		hordir[0] = reach.end_[0] - ms.origin[0]
		hordir[1] = reach.end_[1] - ms.origin[1]
		hordir[2] = 0
		Q.VectorNormalizeIoq3(hordir)
		--
		if reachhordist < 20 then
			speed = 100
		else
			local ok, vel = B.AAS_HorizontalVelocityForJump(0, reach.start, reach.end_)
			if ok == 0 then
				speed = 400
			else
				speed = vel
			end
		end
	else
		if reachhordist < 20 then
			if dist > 64 then dist = 64 end
			speed = 400 - (256 - 4 * dist)
		else
			speed = 400
		end
	end
	--
	B.BotCheckBlocked(ms, hordir, 1, result)
	-- elemantary action
	B.EA_Move(ms.client, hordir, speed)
	Q.VectorCopy(hordir, result.movedir)
	--
	return result
end

function B.BotAirControl(origin, velocity, goal, dir)
	local org = { [0] = 0, 0, 0 }
	local vel = { [0] = 0, 0, 0 }

	Q.VectorCopy(origin, org)
	Q.VectorScale(velocity, 0.1, vel)
	for _ = 0, 49 do
		vel[2] = vel[2] - SF.sv_gravity.value * 0.01
		-- if going down and next position would be below the goal
		if vel[2] < 0 and org[2] + vel[2] < goal[2] then
			Q.VectorScale(vel, (goal[2] - org[2]) / vel[2], vel)
			Q.VectorAdd(org, vel, org)
			Q.VectorSubtract(goal, org, dir)
			local dist = Q.VectorNormalizeIoq3(dir)
			if dist > 32 then dist = 32 end
			return 1, 400 - (400 - 13 * dist)
		else
			Q.VectorAdd(org, vel, org)
		end
	end
	Q.VectorSet(dir, 0, 0, 0)
	return 0, 400
end

function B.BotFinishTravel_WalkOffLedge(ms, reach)
	local dir = { [0] = 0, 0, 0 }
	local hordir = { [0] = 0, 0, 0 }
	local end_ = { [0] = 0, 0, 0 }
	local v = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	--
	Q.VectorSubtract(reach.end_, ms.origin, dir)
	B.BotCheckBlocked(ms, dir, 1, result)
	--
	Q.VectorSubtract(reach.end_, ms.origin, v)
	v[2] = 0
	local dist = Q.VectorNormalizeIoq3(v)
	if dist > 16 then
		Q.VectorMA(reach.end_, 16, v, end_)
	else
		Q.VectorCopy(reach.end_, end_)
	end
	--
	local ok, speed = B.BotAirControl(ms.origin, ms.velocity, end_, hordir)
	if ok == 0 then
		-- go straight to the reachability end
		Q.VectorCopy(dir, hordir)
		hordir[2] = 0
		--
		speed = 400
	end
	--
	B.EA_Move(ms.client, hordir, speed)
	Q.VectorCopy(hordir, result.movedir)
	--
	return result
end

function B.BotTravel_Jump(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local dir1 = { [0] = 0, 0, 0 }
	local dir2 = { [0] = 0, 0, 0 }
	local start = { [0] = 0, 0, 0 }
	local end_ = { [0] = 0, 0, 0 }
	local runstart = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	--
	B.AAS_JumpReachRunStart(reach, runstart)
	--
	hordir[0] = runstart[0] - reach.start[0]
	hordir[1] = runstart[1] - reach.start[1]
	hordir[2] = 0
	Q.VectorNormalizeIoq3(hordir)
	--
	Q.VectorCopy(reach.start, start)
	start[2] = start[2] + 1
	Q.VectorMA(reach.start, 80, hordir, runstart)
	-- check for a gap
	local gapdist = 0
	while gapdist < 80 do
		Q.VectorMA(start, gapdist + 10, hordir, end_)
		end_[2] = end_[2] + 1
		if B.AAS_PointAreaNum(end_) ~= ms.reachareanum then break end
		gapdist = gapdist + 10
	end
	if gapdist < 80 then Q.VectorMA(reach.start, gapdist, hordir, runstart) end
	--
	Q.VectorSubtract(ms.origin, reach.start, dir1)
	dir1[2] = 0
	local dist1 = Q.VectorNormalizeIoq3(dir1)
	Q.VectorSubtract(ms.origin, runstart, dir2)
	dir2[2] = 0
	local dist2 = Q.VectorNormalizeIoq3(dir2)
	-- if just before the reachability start
	if Q.DotProduct(dir1, dir2) < -0.8 or dist2 < 5 then
		hordir[0] = reach.end_[0] - ms.origin[0]
		hordir[1] = reach.end_[1] - ms.origin[1]
		hordir[2] = 0
		Q.VectorNormalizeIoq3(hordir)
		-- elemantary action jump
		if dist1 < 24 then
			B.EA_Jump(ms.client)
		elseif dist1 < 32 then
			B.EA_DelayedJump(ms.client)
		end
		B.EA_Move(ms.client, hordir, 600)
		--
		ms.jumpreach = ms.lastreachnum
	else
		hordir[0] = runstart[0] - ms.origin[0]
		hordir[1] = runstart[1] - ms.origin[1]
		hordir[2] = 0
		Q.VectorNormalizeIoq3(hordir)
		--
		if dist2 > 80 then dist2 = 80 end
		local speed = 400 - (400 - 5 * dist2)
		B.EA_Move(ms.client, hordir, speed)
	end
	Q.VectorCopy(hordir, result.movedir)
	--
	return result
end

function B.BotFinishTravel_Jump(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local hordir2 = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	-- if not jumped yet
	if ms.jumpreach == 0 then return result end
	-- go straight to the reachability end
	hordir[0] = reach.end_[0] - ms.origin[0]
	hordir[1] = reach.end_[1] - ms.origin[1]
	hordir[2] = 0
	local dist = Q.VectorNormalizeIoq3(hordir)
	--
	hordir2[0] = reach.end_[0] - reach.start[0]
	hordir2[1] = reach.end_[1] - reach.start[1]
	hordir2[2] = 0
	Q.VectorNormalizeIoq3(hordir2)
	--
	if Q.DotProduct(hordir, hordir2) < -0.5 and dist < 24 then return result end
	-- always use max speed when traveling through the air
	local speed = 800
	--
	B.EA_Move(ms.client, hordir, speed)
	Q.VectorCopy(hordir, result.movedir)
	--
	return result
end

function B.BotTravel_Ladder(ms, reach)
	local dir = { [0] = 0, 0, 0 }
	local viewdir = { [0] = 0, 0, 0 }
	local origin = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	Q.VectorSubtract(reach.end_, ms.origin, dir)
	Q.VectorNormalizeIoq3(dir)
	-- set the ideal view angles, facing the ladder up or down
	viewdir[0] = dir[0]
	viewdir[1] = dir[1]
	viewdir[2] = 3 * dir[2]
	Q.vectoangles(viewdir, result.ideal_viewangles)
	-- elemantary action
	B.EA_Move(ms.client, origin, 0)
	B.EA_MoveForward(ms.client)
	-- set movement view flag so the AI can see the view is focussed
	result.flags = bit32.bor(result.flags, BC.MOVERESULT_MOVEMENTVIEW)
	-- save the movement direction
	Q.VectorCopy(dir, result.movedir)
	--
	return result
end

function B.BotTravel_Teleport(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	-- if the bot is being teleported
	if bit32.band(ms.moveflags, BC.MFL_TELEPORTED) ~= 0 then return result end

	-- walk straight to center of the teleporter
	Q.VectorSubtract(reach.start, ms.origin, hordir)
	if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 then hordir[2] = 0 end
	local dist = Q.VectorNormalizeIoq3(hordir)
	--
	B.BotCheckBlocked(ms, hordir, 1, result)

	if dist < 30 then
		B.EA_Move(ms.client, hordir, 200)
	else
		B.EA_Move(ms.client, hordir, 400)
	end

	if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 then
		result.flags = bit32.bor(result.flags, BC.MOVERESULT_SWIMVIEW)
	end

	Q.VectorCopy(hordir, result.movedir)
	return result
end

function B.BotTravel_Elevator(ms, reach)
	local dir = { [0] = 0, 0, 0 }
	local dir1 = { [0] = 0, 0, 0 }
	local dir2 = { [0] = 0, 0, 0 }
	local hordir = { [0] = 0, 0, 0 }
	local bottomcenter = { [0] = 0, 0, 0 }
	local dist = 0
	local speed = 0
	local result = SB.bot_moveresult_t()

	-- if standing on the plat
	if B.BotOnMover(ms.origin, ms.entitynum, reach) ~= 0 then
		-- if vertically not too far from the end point
		if math.abs(ms.origin[2] - reach.end_[2]) < SF.sv_maxbarrier.value then
			-- move to the end point
			Q.VectorSubtract(reach.end_, ms.origin, hordir)
			hordir[2] = 0
			Q.VectorNormalizeIoq3(hordir)
			if B.BotCheckBarrierJump(ms, hordir, 100) == 0 then
				B.EA_Move(ms.client, hordir, 400)
			end
			Q.VectorCopy(hordir, result.movedir)
		else
			-- if not really close to the center of the elevator
			B.MoverBottomCenter(reach, bottomcenter)
			Q.VectorSubtract(bottomcenter, ms.origin, hordir)
			hordir[2] = 0
			dist = Q.VectorNormalizeIoq3(hordir)
			--
			if dist > 10 then
				-- move to the center of the plat
				if dist > 100 then dist = 100 end
				speed = 400 - (400 - 4 * dist)
				--
				B.EA_Move(ms.client, hordir, speed)
				Q.VectorCopy(hordir, result.movedir)
			end
		end
	else
		-- if very near the reachability end
		Q.VectorSubtract(reach.end_, ms.origin, dir)
		dist = Q.VectorLength(dir)
		if dist < 64 then
			if dist > 60 then dist = 60 end
			speed = 360 - (360 - 6 * dist)
			--
			if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 or B.BotCheckBarrierJump(ms, dir, 50) == 0 then
				if speed > 5 then B.EA_Move(ms.client, dir, speed) end
			end
			Q.VectorCopy(dir, result.movedir)
			--
			if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 then
				result.flags = bit32.bor(result.flags, BC.MOVERESULT_SWIMVIEW)
			end
			-- stop using this reachability
			ms.reachability_time = 0
			return result
		end
		-- get direction and distance to reachability start
		Q.VectorSubtract(reach.start, ms.origin, dir1)
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 then dir1[2] = 0 end
		local dist1 = Q.VectorNormalizeIoq3(dir1)
		-- if the elevator isn't down
		if B.MoverDown(reach) == 0 then
			dist = dist1
			Q.VectorCopy(dir1, dir)
			--
			B.BotCheckBlocked(ms, dir, 0, result)
			--
			if dist > 60 then dist = 60 end
			speed = 360 - (360 - 6 * dist)
			--
			if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 and B.BotCheckBarrierJump(ms, dir, 50) == 0 then
				if speed > 5 then B.EA_Move(ms.client, dir, speed) end
			end
			Q.VectorCopy(dir, result.movedir)
			--
			if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 then
				result.flags = bit32.bor(result.flags, BC.MOVERESULT_SWIMVIEW)
			end
			-- this isn't a failure... just wait till the elevator comes down
			result.type = BC.RESULTTYPE_ELEVATORUP
			result.flags = bit32.bor(result.flags, BC.MOVERESULT_WAITING)
			return result
		end
		-- get direction and distance to elevator bottom center
		B.MoverBottomCenter(reach, bottomcenter)
		Q.VectorSubtract(bottomcenter, ms.origin, dir2)
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 then dir2[2] = 0 end
		local dist2 = Q.VectorNormalizeIoq3(dir2)
		-- if very close to the reachability start or
		-- closer to the elevator center or
		-- between reachability start and elevator center
		if dist1 < 20 or dist2 < dist1 or Q.DotProduct(dir1, dir2) < 0 then
			dist = dist2
			Q.VectorCopy(dir2, dir)
		else -- closer to the reachability start
			dist = dist1
			Q.VectorCopy(dir1, dir)
		end
		--
		B.BotCheckBlocked(ms, dir, 0, result)
		--
		if dist > 60 then dist = 60 end
		speed = 400 - (400 - 6 * dist)
		--
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 and B.BotCheckBarrierJump(ms, dir, 50) == 0 then
			B.EA_Move(ms.client, dir, speed)
		end
		Q.VectorCopy(dir, result.movedir)
		--
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 then
			result.flags = bit32.bor(result.flags, BC.MOVERESULT_SWIMVIEW)
		end
	end
	return result
end

return nil
