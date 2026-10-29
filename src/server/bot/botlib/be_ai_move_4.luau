--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_move.c, part 4 of 5).

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
-- Luau port of be_ai_move.c lines 2188-2857: elevator, func_bobbing, grapple and weapon jump travel.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local SF = B.FileStatics("be_ai_move")

function B.BotFinishTravel_Elevator(ms, reach)
	local bottomcenter = { [0] = 0, 0, 0 }
	local bottomdir = { [0] = 0, 0, 0 }
	local topdir = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()

	B.MoverBottomCenter(reach, bottomcenter)
	Q.VectorSubtract(bottomcenter, ms.origin, bottomdir)
	Q.VectorSubtract(reach.end_, ms.origin, topdir)
	if math.abs(bottomdir[2]) < math.abs(topdir[2]) then
		Q.VectorNormalizeIoq3(bottomdir)
		B.EA_Move(ms.client, bottomdir, 300)
	else
		Q.VectorNormalizeIoq3(topdir)
		B.EA_Move(ms.client, topdir, 300)
	end
	return result
end

function B.BotFuncBobStartEnd(reach, start, end_, origin)
	local mins = { [0] = 0, 0, 0 }
	local maxs = { [0] = 0, 0, 0 }
	local mid = { [0] = 0, 0, 0 }
	local angles = { [0] = 0, 0, 0 }

	local modelnum = bit32.band(reach.facenum, 0x0000FFFF)
	if B.AAS_OriginOfMoverWithModelNum(modelnum, origin) == 0 then
		B.botimport.Print(BC.PRT_MESSAGE, "BotFuncBobStartEnd: no entity with model %d\n", modelnum)
		start[0], start[1], start[2] = 0, 0, 0
		end_[0], end_[1], end_[2] = 0, 0, 0
		return
	end
	B.AAS_BSPModelMinsMaxsOrigin(modelnum, angles, mins, maxs, nil)
	Q.VectorAdd(mins, maxs, mid)
	Q.VectorScale(mid, 0.5, mid)
	Q.VectorCopy(mid, start)
	Q.VectorCopy(mid, end_)
	local spawnflags = bit32.rshift(bit32.band(reach.facenum, 0xFFFFFFFF), 16)
	local num0 = bit32.rshift(bit32.band(reach.edgenum, 0xFFFFFFFF), 16)
	if num0 > 0x00007FFF then
		num0 = num0 - 0x10000
	end
	local num1 = bit32.band(reach.edgenum, 0x0000FFFF)
	if num1 > 0x00007FFF then
		num1 = num1 - 0x10000
	end
	if bit32.band(spawnflags, 1) ~= 0 then
		start[0] = num0
		end_[0] = num1
		origin[0] = origin[0] + mid[0]
		origin[1] = mid[1]
		origin[2] = mid[2]
	elseif bit32.band(spawnflags, 2) ~= 0 then
		start[1] = num0
		end_[1] = num1
		origin[0] = mid[0]
		origin[1] = origin[1] + mid[1]
		origin[2] = mid[2]
	else
		start[2] = num0
		end_[2] = num1
		origin[0] = mid[0]
		origin[1] = mid[1]
		origin[2] = origin[2] + mid[2]
	end
end

function B.BotTravel_FuncBobbing(ms, reach)
	local dir = { [0] = 0, 0, 0 }
	local dir1 = { [0] = 0, 0, 0 }
	local dir2 = { [0] = 0, 0, 0 }
	local hordir = { [0] = 0, 0, 0 }
	local bottomcenter = { [0] = 0, 0, 0 }
	local bob_start = { [0] = 0, 0, 0 }
	local bob_end = { [0] = 0, 0, 0 }
	local bob_origin = { [0] = 0, 0, 0 }
	local dist, dist1, dist2, speed
	local result = SB.bot_moveresult_t()

	B.BotFuncBobStartEnd(reach, bob_start, bob_end, bob_origin)
	if B.BotOnMover(ms.origin, ms.entitynum, reach) ~= 0 then
		Q.VectorSubtract(bob_origin, bob_end, dir)
		if Q.VectorLength(dir) < 24 then
			Q.VectorSubtract(reach.end_, ms.origin, hordir)
			hordir[2] = 0
			Q.VectorNormalizeIoq3(hordir)
			if B.BotCheckBarrierJump(ms, hordir, 100) == 0 then
				B.EA_Move(ms.client, hordir, 400)
			end
			Q.VectorCopy(hordir, result.movedir)
		else
			B.MoverBottomCenter(reach, bottomcenter)
			Q.VectorSubtract(bottomcenter, ms.origin, hordir)
			hordir[2] = 0
			dist = Q.VectorNormalizeIoq3(hordir)
			if dist > 10 then
				if dist > 100 then
					dist = 100
				end
				speed = 400 - (400 - 4 * dist)
				B.EA_Move(ms.client, hordir, speed)
				Q.VectorCopy(hordir, result.movedir)
			end
		end
	else
		Q.VectorSubtract(reach.end_, ms.origin, dir)
		dist = Q.VectorLength(dir)
		if dist < 64 then
			if dist > 60 then
				dist = 60
			end
			speed = 360 - (360 - 6 * dist)
			if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 or B.BotCheckBarrierJump(ms, dir, 50) == 0 then
				if speed > 5 then
					B.EA_Move(ms.client, dir, speed)
				end
			end
			Q.VectorCopy(dir, result.movedir)
			if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 then
				result.flags = bit32.bor(result.flags, BC.MOVERESULT_SWIMVIEW)
			end
			ms.reachability_time = 0
			return result
		end
		Q.VectorSubtract(reach.start, ms.origin, dir1)
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 then
			dir1[2] = 0
		end
		dist1 = Q.VectorNormalizeIoq3(dir1)
		Q.VectorSubtract(bob_origin, bob_start, dir)
		if Q.VectorLength(dir) > 16 then
			dist = dist1
			Q.VectorCopy(dir1, dir)
			B.BotCheckBlocked(ms, dir, 0, result)
			if dist > 60 then
				dist = 60
			end
			speed = 360 - (360 - 6 * dist)
			if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 and B.BotCheckBarrierJump(ms, dir, 50) == 0 then
				if speed > 5 then
					B.EA_Move(ms.client, dir, speed)
				end
			end
			Q.VectorCopy(dir, result.movedir)
			if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 then
				result.flags = bit32.bor(result.flags, BC.MOVERESULT_SWIMVIEW)
			end
			result.type = BC.RESULTTYPE_WAITFORFUNCBOBBING
			result.flags = bit32.bor(result.flags, BC.MOVERESULT_WAITING)
			return result
		end
		B.MoverBottomCenter(reach, bottomcenter)
		Q.VectorSubtract(bottomcenter, ms.origin, dir2)
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 then
			dir2[2] = 0
		end
		dist2 = Q.VectorNormalizeIoq3(dir2)
		if dist1 < 20 or dist2 < dist1 or Q.DotProduct(dir1, dir2) < 0 then
			dist = dist2
			Q.VectorCopy(dir2, dir)
		else
			dist = dist1
			Q.VectorCopy(dir1, dir)
		end
		B.BotCheckBlocked(ms, dir, 0, result)
		if dist > 60 then
			dist = 60
		end
		speed = 400 - (400 - 6 * dist)
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 and B.BotCheckBarrierJump(ms, dir, 50) == 0 then
			B.EA_Move(ms.client, dir, speed)
		end
		Q.VectorCopy(dir, result.movedir)
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 then
			result.flags = bit32.bor(result.flags, BC.MOVERESULT_SWIMVIEW)
		end
	end
	return result
end

function B.BotFinishTravel_FuncBobbing(ms, reach)
	local bob_origin = { [0] = 0, 0, 0 }
	local bob_start = { [0] = 0, 0, 0 }
	local bob_end = { [0] = 0, 0, 0 }
	local dir = { [0] = 0, 0, 0 }
	local hordir = { [0] = 0, 0, 0 }
	local bottomcenter = { [0] = 0, 0, 0 }
	local result = SB.bot_moveresult_t()
	local dist, speed

	B.BotFuncBobStartEnd(reach, bob_start, bob_end, bob_origin)
	Q.VectorSubtract(bob_origin, bob_end, dir)
	dist = Q.VectorLength(dir)
	if dist < 16 then
		Q.VectorSubtract(reach.end_, ms.origin, hordir)
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 then
			hordir[2] = 0
		end
		dist = Q.VectorNormalizeIoq3(hordir)
		if dist > 60 then
			dist = 60
		end
		speed = 360 - (360 - 6 * dist)
		if speed > 5 then
			B.EA_Move(ms.client, dir, speed)
		end
		Q.VectorCopy(dir, result.movedir)
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) ~= 0 then
			result.flags = bit32.bor(result.flags, BC.MOVERESULT_SWIMVIEW)
		end
	else
		B.MoverBottomCenter(reach, bottomcenter)
		Q.VectorSubtract(bottomcenter, ms.origin, hordir)
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 then
			hordir[2] = 0
		end
		dist = Q.VectorNormalizeIoq3(hordir)
		if dist > 5 then
			if dist > 100 then
				dist = 100
			end
			speed = 400 - (400 - 4 * dist)
			B.EA_Move(ms.client, hordir, speed)
			Q.VectorCopy(hordir, result.movedir)
		end
	end
	return result
end

-- 0  no valid grapple hook visible
-- 1  the grapple hook is still flying
-- 2  the grapple hooked into a wall
function B.GrappleState(ms, reach)
	local entinfo = SB.aas_entityinfo_t()

	if bit32.band(ms.moveflags, BC.MFL_GRAPPLEPULL) ~= 0 then
		return 2
	end
	local i = B.AAS_NextEntity(0)
	while i ~= 0 do
		if B.AAS_EntityType(i) == Q.trunc(SF.entitytypemissile.value) then
			B.AAS_EntityInfo(i, entinfo)
			if entinfo.weapon == Q.trunc(SF.weapindex_grapple.value) then
				return 1
			end
		end
		i = B.AAS_NextEntity(i)
	end
	return 0
end

function B.BotResetGrapple(ms)
	local reach = SB.aas_reachability_t()

	B.AAS_ReachabilityFromNum(ms.lastreachnum, reach)
	if bit32.band(reach.traveltype, BC.TRAVELTYPE_MASK) ~= BC.TRAVEL_GRAPPLEHOOK then
		if bit32.band(ms.moveflags, BC.MFL_ACTIVEGRAPPLE) ~= 0 or ms.grapplevisible_time ~= 0 then
			if SF.offhandgrapple.value ~= 0 then
				B.EA_Command(ms.client, SF.cmd_grappleoff.string)
			end
			ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_ACTIVEGRAPPLE))
			ms.grapplevisible_time = 0
		end
	end
end

function B.BotTravel_Grapple(ms, reach)
	local result = SB.bot_moveresult_t()
	local dist, speed
	local dir = { [0] = 0, 0, 0 }
	local viewdir = { [0] = 0, 0, 0 }
	local org = { [0] = 0, 0, 0 }
	local state, areanum

	if bit32.band(ms.moveflags, BC.MFL_GRAPPLERESET) ~= 0 then
		if SF.offhandgrapple.value ~= 0 then
			B.EA_Command(ms.client, SF.cmd_grappleoff.string)
		end
		ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_ACTIVEGRAPPLE))
		return result
	end
	if Q.trunc(SF.offhandgrapple.value) == 0 then
		result.weapon = SF.weapindex_grapple.value
		result.flags = bit32.bor(result.flags, BC.MOVERESULT_MOVEMENTWEAPON)
	end
	if bit32.band(ms.moveflags, BC.MFL_ACTIVEGRAPPLE) ~= 0 then
		state = B.GrappleState(ms, reach)
		Q.VectorSubtract(reach.end_, ms.origin, dir)
		dir[2] = 0
		dist = Q.VectorLength(dir)
		if state ~= 0 and dist < 48 then
			if ms.lastgrappledist - dist < 1 then
				if SF.offhandgrapple.value ~= 0 then
					B.EA_Command(ms.client, SF.cmd_grappleoff.string)
				end
				ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_ACTIVEGRAPPLE))
				ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_GRAPPLERESET)
				ms.reachability_time = 0
				return result
			end
		elseif state == 0 or (state == 2 and dist > ms.lastgrappledist - 2) then
			if ms.grapplevisible_time < B.AAS_Time() - 0.4 then
				if SF.offhandgrapple.value ~= 0 then
					B.EA_Command(ms.client, SF.cmd_grappleoff.string)
				end
				ms.moveflags = bit32.band(ms.moveflags, bit32.bnot(BC.MFL_ACTIVEGRAPPLE))
				ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_GRAPPLERESET)
				ms.reachability_time = 0
				return result
			end
		else
			ms.grapplevisible_time = B.AAS_Time()
		end
		if Q.trunc(SF.offhandgrapple.value) == 0 then
			B.EA_Attack(ms.client)
		end
		ms.lastgrappledist = dist
	else
		ms.grapplevisible_time = B.AAS_Time()
		Q.VectorSubtract(reach.start, ms.origin, dir)
		if bit32.band(ms.moveflags, BC.MFL_SWIMMING) == 0 then
			dir[2] = 0
		end
		Q.VectorAdd(ms.origin, ms.viewoffset, org)
		Q.VectorSubtract(reach.end_, org, viewdir)
		dist = Q.VectorNormalizeIoq3(dir)
		Q.vectoangles(viewdir, result.ideal_viewangles)
		result.flags = bit32.bor(result.flags, BC.MOVERESULT_MOVEMENTVIEW)
		if
			dist < 5
			and math.abs(B.AngleDiff(result.ideal_viewangles[0], ms.viewangles[0])) < 2
			and math.abs(B.AngleDiff(result.ideal_viewangles[1], ms.viewangles[1])) < 2
		then
			Q.VectorAdd(ms.origin, ms.viewoffset, org)
			local trace = B.AAS_Trace(org, nil, nil, reach.end_, ms.entitynum, BC.CONTENTS_SOLID)
			Q.VectorSubtract(reach.end_, trace.endpos, dir)
			if Q.VectorLength(dir) > 16 then
				result.failure = 1
				return result
			end
			if SF.offhandgrapple.value ~= 0 then
				B.EA_Command(ms.client, SF.cmd_grappleon.string)
			else
				B.EA_Attack(ms.client)
			end
			ms.moveflags = bit32.bor(ms.moveflags, BC.MFL_ACTIVEGRAPPLE)
			ms.lastgrappledist = 999999
		else
			if dist < 70 then
				speed = 300 - (300 - 4 * dist)
			else
				speed = 400
			end
			B.BotCheckBlocked(ms, dir, 1, result)
			B.EA_Move(ms.client, dir, speed)
			Q.VectorCopy(dir, result.movedir)
		end
		areanum = B.AAS_PointAreaNum(ms.origin)
		if areanum ~= 0 and areanum ~= ms.reachareanum then
			ms.reachability_time = 0
		end
	end
	return result
end

function B.BotTravel_RocketJump(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local dist, speed
	local result = SB.bot_moveresult_t()

	hordir[0] = reach.start[0] - ms.origin[0]
	hordir[1] = reach.start[1] - ms.origin[1]
	hordir[2] = 0
	dist = Q.VectorNormalizeIoq3(hordir)
	Q.vectoangles(hordir, result.ideal_viewangles)
	result.ideal_viewangles[BC.PITCH] = 90
	if
		dist < 5
		and math.abs(B.AngleDiff(result.ideal_viewangles[0], ms.viewangles[0])) < 5
		and math.abs(B.AngleDiff(result.ideal_viewangles[1], ms.viewangles[1])) < 5
	then
		hordir[0] = reach.end_[0] - ms.origin[0]
		hordir[1] = reach.end_[1] - ms.origin[1]
		hordir[2] = 0
		Q.VectorNormalizeIoq3(hordir)
		B.EA_Jump(ms.client)
		B.EA_Attack(ms.client)
		B.EA_Move(ms.client, hordir, 800)
		ms.jumpreach = ms.lastreachnum
	else
		if dist > 80 then
			dist = 80
		end
		speed = 400 - (400 - 5 * dist)
		B.EA_Move(ms.client, hordir, speed)
	end
	Q.vectoangles(hordir, result.ideal_viewangles)
	result.ideal_viewangles[BC.PITCH] = 90
	B.EA_View(ms.client, result.ideal_viewangles)
	result.flags = bit32.bor(result.flags, BC.MOVERESULT_MOVEMENTVIEWSET)
	B.EA_SelectWeapon(ms.client, Q.trunc(SF.weapindex_rocketlauncher.value))
	result.weapon = Q.trunc(SF.weapindex_rocketlauncher.value)
	result.flags = bit32.bor(result.flags, BC.MOVERESULT_MOVEMENTWEAPON)
	Q.VectorCopy(hordir, result.movedir)
	return result
end

function B.BotTravel_BFGJump(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local dist, speed
	local result = SB.bot_moveresult_t()

	hordir[0] = reach.start[0] - ms.origin[0]
	hordir[1] = reach.start[1] - ms.origin[1]
	hordir[2] = 0
	dist = Q.VectorNormalizeIoq3(hordir)
	if
		dist < 5
		and math.abs(B.AngleDiff(result.ideal_viewangles[0], ms.viewangles[0])) < 5
		and math.abs(B.AngleDiff(result.ideal_viewangles[1], ms.viewangles[1])) < 5
	then
		hordir[0] = reach.end_[0] - ms.origin[0]
		hordir[1] = reach.end_[1] - ms.origin[1]
		hordir[2] = 0
		Q.VectorNormalizeIoq3(hordir)
		B.EA_Jump(ms.client)
		B.EA_Attack(ms.client)
		B.EA_Move(ms.client, hordir, 800)
		ms.jumpreach = ms.lastreachnum
	else
		if dist > 80 then
			dist = 80
		end
		speed = 400 - (400 - 5 * dist)
		B.EA_Move(ms.client, hordir, speed)
	end
	Q.vectoangles(hordir, result.ideal_viewangles)
	result.ideal_viewangles[BC.PITCH] = 90
	B.EA_View(ms.client, result.ideal_viewangles)
	result.flags = bit32.bor(result.flags, BC.MOVERESULT_MOVEMENTVIEWSET)
	B.EA_SelectWeapon(ms.client, Q.trunc(SF.weapindex_bfg10k.value))
	result.weapon = Q.trunc(SF.weapindex_bfg10k.value)
	result.flags = bit32.bor(result.flags, BC.MOVERESULT_MOVEMENTWEAPON)
	Q.VectorCopy(hordir, result.movedir)
	return result
end

function B.BotFinishTravel_WeaponJump(ms, reach)
	local hordir = { [0] = 0, 0, 0 }
	local speed
	local result = SB.bot_moveresult_t()

	if ms.jumpreach == 0 then
		return result
	end
	local ok
	ok, speed = B.BotAirControl(ms.origin, ms.velocity, reach.end_, hordir)
	if ok == 0 then
		Q.VectorSubtract(reach.end_, ms.origin, hordir)
		hordir[2] = 0
		Q.VectorNormalizeIoq3(hordir)
		speed = 400
	end
	B.EA_Move(ms.client, hordir, speed)
	Q.VectorCopy(hordir, result.movedir)
	return result
end

return nil
