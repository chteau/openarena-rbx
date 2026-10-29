--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_aas_move.c, part 1 of 2).

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
-- Luau port of be_aas_move.c, part 1 of 2: floor drop, settings, ladder/ground/swim tests, jump helpers, acceleration and friction.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")

local SF = B.FileStatics("be_aas_move")

B.aassettings = SB.aas_settings_t()

local VEC_UP = { [0] = 0, -1, 0 }
local MOVEDIR_UP = { [0] = 0, 0, 1 }
local VEC_DOWN = { [0] = 0, -2, 0 }
local MOVEDIR_DOWN = { [0] = 0, 0, -1 }
SF.VEC_UP = VEC_UP
SF.MOVEDIR_UP = MOVEDIR_UP
SF.VEC_DOWN = VEC_DOWN
SF.MOVEDIR_DOWN = MOVEDIR_DOWN

local vec3_origin = { [0] = 0, 0, 0 }

local function LV(name: string, value: string): number
	return Q.f(B.LibVarValue(name, value))
end

function B.AAS_DropToFloor(origin, mins, maxs): number
	local end_ = { [0] = 0, 0, 0 }
	Q.VectorCopy(origin, end_)
	end_[2] = Q.f(end_[2] - 100)
	local trace = B.AAS_Trace(origin, mins, maxs, end_, 0, BC.CONTENTS_SOLID)
	if trace.startsolid then
		return 0
	end
	Q.VectorCopy(trace.endpos, origin)
	return 1
end

function B.AAS_InitSettings()
	local aassettings = B.aassettings
	aassettings.phys_gravitydirection[0] = 0
	aassettings.phys_gravitydirection[1] = 0
	aassettings.phys_gravitydirection[2] = -1
	aassettings.phys_friction = LV("phys_friction", "6")
	aassettings.phys_stopspeed = LV("phys_stopspeed", "100")
	aassettings.phys_gravity = LV("phys_gravity", "800")
	aassettings.phys_waterfriction = LV("phys_waterfriction", "1")
	aassettings.phys_watergravity = LV("phys_watergravity", "400")
	aassettings.phys_maxvelocity = LV("phys_maxvelocity", "320")
	aassettings.phys_maxwalkvelocity = LV("phys_maxwalkvelocity", "320")
	aassettings.phys_maxcrouchvelocity = LV("phys_maxcrouchvelocity", "100")
	aassettings.phys_maxswimvelocity = LV("phys_maxswimvelocity", "150")
	aassettings.phys_walkaccelerate = LV("phys_walkaccelerate", "10")
	aassettings.phys_airaccelerate = LV("phys_airaccelerate", "1")
	aassettings.phys_swimaccelerate = LV("phys_swimaccelerate", "4")
	aassettings.phys_maxstep = LV("phys_maxstep", "19")
	aassettings.phys_maxsteepness = LV("phys_maxsteepness", "0.7")
	aassettings.phys_maxwaterjump = LV("phys_maxwaterjump", "18")
	aassettings.phys_maxbarrier = LV("phys_maxbarrier", "33")
	aassettings.phys_jumpvel = LV("phys_jumpvel", "270")
	aassettings.phys_falldelta5 = LV("phys_falldelta5", "40")
	aassettings.phys_falldelta10 = LV("phys_falldelta10", "60")
	aassettings.rs_waterjump = LV("rs_waterjump", "400")
	aassettings.rs_teleport = LV("rs_teleport", "50")
	aassettings.rs_barrierjump = LV("rs_barrierjump", "100")
	aassettings.rs_startcrouch = LV("rs_startcrouch", "300")
	aassettings.rs_startgrapple = LV("rs_startgrapple", "500")
	aassettings.rs_startwalkoffledge = LV("rs_startwalkoffledge", "70")
	aassettings.rs_startjump = LV("rs_startjump", "300")
	aassettings.rs_rocketjump = LV("rs_rocketjump", "500")
	aassettings.rs_bfgjump = LV("rs_bfgjump", "500")
	aassettings.rs_jumppad = LV("rs_jumppad", "250")
	aassettings.rs_aircontrolledjumppad = LV("rs_aircontrolledjumppad", "300")
	aassettings.rs_funcbob = LV("rs_funcbob", "300")
	aassettings.rs_startelevator = LV("rs_startelevator", "50")
	aassettings.rs_falldamage5 = LV("rs_falldamage5", "300")
	aassettings.rs_falldamage10 = LV("rs_falldamage10", "500")
	aassettings.rs_maxfallheight = LV("rs_maxfallheight", "0")
	aassettings.rs_maxjumpfallheight = LV("rs_maxjumpfallheight", "450")
end

function B.AAS_AgainstLadder(origin): number
	local aasworld = B.aasworld
	local org = { [0] = 0, 0, 0 }
	Q.VectorCopy(origin, org)
	local areanum = B.AAS_PointAreaNum(org)
	if areanum == 0 then
		org[0] = Q.f(org[0] + 1)
		areanum = B.AAS_PointAreaNum(org)
		if areanum == 0 then
			org[1] = Q.f(org[1] + 1)
			areanum = B.AAS_PointAreaNum(org)
			if areanum == 0 then
				org[0] = Q.f(org[0] - 2)
				areanum = B.AAS_PointAreaNum(org)
				if areanum == 0 then
					org[1] = Q.f(org[1] - 2)
					areanum = B.AAS_PointAreaNum(org)
				end
			end
		end
	end
	--if in solid... wrrr shouldn't happen
	if areanum == 0 then
		return 0
	end
	--if not in a ladder area
	if bit32.band(aasworld.areasettings[areanum].areaflags, BC.AREA_LADDER) == 0 then
		return 0
	end
	--if a crouch only area
	if bit32.band(aasworld.areasettings[areanum].presencetype, BC.PRESENCE_NORMAL) == 0 then
		return 0
	end
	local area = aasworld.areas[areanum]
	for i = 0, area.numfaces - 1 do
		local facenum = aasworld.faceindex[area.firstface + i]
		local side = if facenum < 0 then 1 else 0
		local face = aasworld.faces[math.abs(facenum)]
		--if the face isn't a ladder face
		if bit32.band(face.faceflags, BC.FACE_LADDER) == 0 then
			continue
		end
		--get the plane the face is in
		local plane = aasworld.planes[bit32.bxor(face.planenum, side)]
		--if the origin is pretty close to the plane
		if math.abs(Q.f(Q.DotProduct(plane.normal, origin) - plane.dist)) < 3 then
			if B.AAS_PointInsideFace(math.abs(facenum), origin, Q.f(0.1)) then
				return 1
			end
		end
	end
	return 0
end

function B.AAS_OnGround(origin, presencetype, passent): number
	local up = { [0] = 0, 0, 1 }
	local end_ = { [0] = 0, 0, 0 }
	Q.VectorCopy(origin, end_)
	end_[2] = Q.f(end_[2] - 10)

	local trace = B.AAS_TraceClientBBox(origin, end_, presencetype, passent)

	--if in solid
	if trace.startsolid then
		return 0
	end
	--if nothing hit at all
	if trace.fraction >= 1.0 then
		return 0
	end
	--if too far from the hit plane
	if Q.f(origin[2] - trace.endpos[2]) > 10 then
		return 0
	end
	--check if the plane isn't too steep
	local plane = B.AAS_PlaneFromNum(trace.planenum)
	if Q.DotProduct(plane.normal, up) < B.aassettings.phys_maxsteepness then
		return 0
	end
	--the bot is on the ground
	return 1
end

function B.AAS_Swimming(origin): number
	local testorg = { [0] = 0, 0, 0 }
	Q.VectorCopy(origin, testorg)
	testorg[2] = Q.f(testorg[2] - 2)
	if bit32.band(B.AAS_PointContents(testorg), bit32.bor(BC.CONTENTS_LAVA, BC.CONTENTS_SLIME, BC.CONTENTS_WATER)) ~= 0 then
		return 1
	end
	return 0
end

function B.AAS_SetMovedir(angles, movedir)
	if Q.VectorCompare(angles, VEC_UP) then
		Q.VectorCopy(MOVEDIR_UP, movedir)
	elseif Q.VectorCompare(angles, VEC_DOWN) then
		Q.VectorCopy(MOVEDIR_DOWN, movedir)
	else
		Q.AngleVectors(angles, movedir, nil, nil)
	end
end

function B.AAS_JumpReachRunStart(reach, runstart)
	local hordir = { [0] = 0, 0, 0 }
	local start = { [0] = 0, 0, 0 }
	local cmdmove = { [0] = 0, 0, 0 }
	local move = SB.aas_clientmove_t()

	hordir[0] = Q.f(reach.start[0] - reach.end_[0])
	hordir[1] = Q.f(reach.start[1] - reach.end_[1])
	hordir[2] = 0
	Q.VectorNormalizeIoq3(hordir)
	--start point
	Q.VectorCopy(reach.start, start)
	start[2] = Q.f(start[2] + 1)
	--get command movement
	Q.VectorScale(hordir, 400, cmdmove)
	--
	B.AAS_PredictClientMovement(move, -1, start, BC.PRESENCE_NORMAL, 1,
		vec3_origin, cmdmove, 1, 2, Q.f(0.1),
		bit32.bor(BC.SE_ENTERWATER, BC.SE_ENTERSLIME, BC.SE_ENTERLAVA, BC.SE_HITGROUNDDAMAGE, BC.SE_GAP), 0, 0)
	Q.VectorCopy(move.endpos, runstart)
	--don't enter slime or lava and don't fall from too high
	if bit32.band(move.stopevent, bit32.bor(BC.SE_ENTERSLIME, BC.SE_ENTERLAVA, BC.SE_HITGROUNDDAMAGE)) ~= 0 then
		Q.VectorCopy(start, runstart)
	end
end

function B.AAS_WeaponJumpZVelocity(origin, radiusdamage): number
	local kvel = { [0] = 0, 0, 0 }
	local v = { [0] = 0, 0, 0 }
	local start = { [0] = 0, 0, 0 }
	local end_ = { [0] = 0, 0, 0 }
	local forward = { [0] = 0, 0, 0 }
	local right = { [0] = 0, 0, 0 }
	local viewangles = { [0] = 0, 0, 0 }
	local dir = { [0] = 0, 0, 0 }
	local rocketoffset = { [0] = 8, 8, -8 }
	local botmins = { [0] = -16, -16, -24 }
	local botmaxs = { [0] = 16, 16, 32 }

	--look down (90 degrees)
	viewangles[0] = 90
	viewangles[1] = 0
	viewangles[2] = 0
	--get the start point shooting from
	Q.VectorCopy(origin, start)
	start[2] = Q.f(start[2] + 8) --view offset Z
	Q.AngleVectors(viewangles, forward, right, nil)
	start[0] = Q.f(start[0] + Q.f(Q.f(forward[0] * rocketoffset[0]) + Q.f(right[0] * rocketoffset[1])))
	start[1] = Q.f(start[1] + Q.f(Q.f(forward[1] * rocketoffset[0]) + Q.f(right[1] * rocketoffset[1])))
	start[2] = Q.f(start[2] + Q.f(Q.f(Q.f(forward[2] * rocketoffset[0]) + Q.f(right[2] * rocketoffset[1])) + rocketoffset[2]))
	--end point of the trace
	Q.VectorMA(start, 500, forward, end_)
	--trace a line to get the impact point
	local bsptrace = B.AAS_Trace(start, nil, nil, end_, 1, BC.CONTENTS_SOLID)
	--calculate the damage the bot will get from the rocket impact
	Q.VectorAdd(botmins, botmaxs, v)
	Q.VectorMA(origin, 0.5, v, v)
	Q.VectorSubtract(bsptrace.endpos, v, v)
	--
	local points = Q.f(radiusdamage - 0.5 * Q.VectorLength(v))
	if points < 0 then
		points = 0
	end
	--the owner of the rocket gets half the damage
	points = Q.f(points * 0.5)
	--mass of the bot (p_client.c: PutClientInServer)
	local mass = 200
	--knockback is the same as the damage points
	local knockback = points
	--direction of the damage (from trace.endpos to bot origin)
	Q.VectorSubtract(origin, bsptrace.endpos, dir)
	Q.VectorNormalizeIoq3(dir)
	--damage velocity
	Q.VectorScale(dir, Q.f(1600.0 * knockback / mass), kvel) --the rocket jump hack...
	--rocket impact velocity + jump velocity
	return Q.f(kvel[2] + B.aassettings.phys_jumpvel)
end

function B.AAS_RocketJumpZVelocity(origin): number
	--rocket radius damage is 120 (p_weapon.c: Weapon_RocketLauncher_Fire)
	return B.AAS_WeaponJumpZVelocity(origin, 120)
end

function B.AAS_BFGJumpZVelocity(origin): number
	--bfg radius damage is 1000 (p_weapon.c: weapon_bfg_fire)
	return B.AAS_WeaponJumpZVelocity(origin, 120)
end

function B.AAS_Accelerate(velocity, frametime, wishdir, wishspeed, accel)
	-- q2 style
	local currentspeed = Q.DotProduct(velocity, wishdir)
	local addspeed = Q.f(wishspeed - currentspeed)
	if addspeed <= 0 then
		return
	end
	local accelspeed = Q.f(Q.f(accel * frametime) * wishspeed)
	if accelspeed > addspeed then
		accelspeed = addspeed
	end

	for i = 0, 2 do
		velocity[i] = Q.f(velocity[i] + Q.f(accelspeed * wishdir[i]))
	end
end

function B.AAS_ApplyFriction(vel, friction, stopspeed, frametime)
	--horizontal speed
	local speed = Q.f(math.sqrt(Q.f(Q.f(vel[0] * vel[0]) + Q.f(vel[1] * vel[1]))))
	if speed ~= 0 then
		local control = if speed < stopspeed then stopspeed else speed
		local newspeed = Q.f(speed - Q.f(Q.f(frametime * control) * friction))
		if newspeed < 0 then
			newspeed = 0
		end
		newspeed = Q.f(newspeed / speed)
		vel[0] = Q.f(vel[0] * newspeed)
		vel[1] = Q.f(vel[1] * newspeed)
	end
end

return nil
