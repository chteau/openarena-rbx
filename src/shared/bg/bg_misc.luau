--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/bg_misc.c).

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
-- Luau port of OpenArena 0.8.8's bg_misc.c (gamecode 9e0f0c0): the item list, trajectory evaluation, predictable
-- events, jump pads and playerState -> entityState.
-- Items are tables from bg_itemlist.luau; an item "pointer" is the table and
-- ITEM_INDEX(it) is it.index.

local Q = require("../q_math")
local C = require("../consts")
local QS = require("../q_shared")
local IL = require("./bg_itemlist")

local f = Q.f
local band, bor, lshift, bnot = bit32.band, bit32.bor, bit32.lshift, bit32.bnot
local sin, cos, abs = math.sin, math.cos, math.abs
local VectorCopy, VectorMA, VectorClear, VectorScale, SnapVector = Q.VectorCopy, Q.VectorMA, Q.VectorClear, Q.VectorScale, Q.SnapVector

local BG = {}

local bg_itemlist = IL.bg_itemlist
BG.bg_itemlist = bg_itemlist
BG.bg_numItems = IL.bg_numItems

function BG.ITEM_INDEX(it): number
	return it.index
end

function BG.BG_FindItemForPowerup(pw: number)
	for i = 0, BG.bg_numItems - 1 do
		local it = bg_itemlist[i]
		if (it.giType == C.IT_POWERUP or it.giType == C.IT_TEAM or it.giType == C.IT_PERSISTANT_POWERUP) and it.giTag == pw then
			return it
		end
	end
	return nil
end

function BG.BG_FindItemForHoldable(pw: number)
	for i = 0, BG.bg_numItems - 1 do
		local it = bg_itemlist[i]
		if it.giType == C.IT_HOLDABLE and it.giTag == pw then
			return it
		end
	end
	QS.Com_Error(C.ERR_DROP, "HoldableItem not found")
	return nil
end

function BG.BG_FindItemForWeapon(weapon: number)
	local i = 1
	while bg_itemlist[i].classname do
		local it = bg_itemlist[i]
		if it.giType == C.IT_WEAPON and it.giTag == weapon then
			return it
		end
		i += 1
	end
	QS.Com_Error(C.ERR_DROP, QS.va("Couldn't find item for weapon %i", weapon))
	return nil
end

function BG.BG_FindItem(pickupName: string)
	local i = 1
	while bg_itemlist[i].classname do
		local it = bg_itemlist[i]
		if QS.Q_stricmp(it.pickup_name, pickupName) == 0 then
			return it
		end
		i += 1
	end
	return nil
end

-- Items can be picked up without actually touching their physical bounds to
-- make grabbing them easier
local tio = Q.vec3()
function BG.BG_PlayerTouchesItem(ps, item, atTime: number): boolean
	BG.BG_EvaluateTrajectory(item.pos, atTime, tio)

	-- we are ignoring ducked differences here
	local dx, dy, dz = f(ps.origin[0] - tio[0]), f(ps.origin[1] - tio[1]), f(ps.origin[2] - tio[2])
	if dx > 44 or dx < -50 or dy > 36 or dy < -36 or dz > 36 or dz < -36 then
		return false
	end

	return true
end

-- Returns false if the item should not be picked up.
-- This needs to be the same for client side prediction and server use.
function BG.BG_CanItemBeGrabbed(gametype: number, ent, ps): boolean
	local upperBound

	if ent.modelindex < 1 or ent.modelindex >= BG.bg_numItems then
		QS.Com_Error(C.ERR_DROP, "BG_CanItemBeGrabbed: index out of range")
	end

	local item = bg_itemlist[ent.modelindex]
	local t = item.giType
	local team = ps.persistant[C.PERS_TEAM]

	if t == C.IT_WEAPON then
		return true -- weapons are always picked up
	elseif t == C.IT_AMMO then
		if ps.ammo[item.giTag] >= 200 then
			return false -- can't hold any more
		end
		return true
	elseif t == C.IT_ARMOR then
		if bg_itemlist[ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_SCOUT then
			return false
		end

		-- we also clamp armor to the maxhealth for handicapping
		if bg_itemlist[ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_GUARD then
			upperBound = ps.stats[C.STAT_MAX_HEALTH]
		else
			upperBound = ps.stats[C.STAT_MAX_HEALTH] * 2
		end

		if ps.stats[C.STAT_ARMOR] >= upperBound then
			return false
		end
		return true
	elseif t == C.IT_HEALTH then
		-- small and mega healths will go over the max, otherwise
		-- don't pick up if already at max
		if bg_itemlist[ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_GUARD then
			upperBound = ps.stats[C.STAT_MAX_HEALTH]
		elseif item.quantity == 5 or item.quantity == 100 then
			if ps.stats[C.STAT_HEALTH] >= ps.stats[C.STAT_MAX_HEALTH] * 2 then
				return false
			end
			return true
		end

		if ps.stats[C.STAT_HEALTH] >= ps.stats[C.STAT_MAX_HEALTH] then
			return false
		end
		return true
	elseif t == C.IT_POWERUP then
		return true -- powerups are always picked up
	elseif t == C.IT_PERSISTANT_POWERUP then
		--In Double D we don't want persistant Powerups (or maybe, can be discussed)
		if gametype == C.GT_DOUBLE_D then
			return false
		end

		-- can only hold one item at a time
		if ps.stats[C.STAT_PERSISTANT_POWERUP] ~= 0 then
			return false
		end

		-- check team only
		if band(ent.generic1, 2) ~= 0 and team ~= C.TEAM_RED then
			return false
		end
		if band(ent.generic1, 4) ~= 0 and team ~= C.TEAM_BLUE then
			return false
		end

		return true
	elseif t == C.IT_TEAM then -- team items, such as flags
		local tag = item.giTag
		if gametype == C.GT_1FCTF then
			-- neutral flag can always be picked up
			if tag == C.PW_NEUTRALFLAG then
				return true
			end
			if team == C.TEAM_RED then
				if tag == C.PW_BLUEFLAG and ps.powerups[C.PW_NEUTRALFLAG] ~= 0 then
					return true
				end
			elseif team == C.TEAM_BLUE then
				if tag == C.PW_REDFLAG and ps.powerups[C.PW_NEUTRALFLAG] ~= 0 then
					return true
				end
			end
		end
		if gametype == C.GT_CTF or gametype == C.GT_CTF_ELIMINATION then
			-- ent->modelindex2 is non-zero on items if they are dropped
			-- we need to know this because we can pick up our dropped flag (and return it)
			-- but we can't pick up our flag at base
			if team == C.TEAM_RED then
				if tag == C.PW_BLUEFLAG or (tag == C.PW_REDFLAG and ent.modelindex2 ~= 0) or (tag == C.PW_REDFLAG and ps.powerups[C.PW_BLUEFLAG] ~= 0) then
					return true
				end
			elseif team == C.TEAM_BLUE then
				if tag == C.PW_REDFLAG or (tag == C.PW_BLUEFLAG and ent.modelindex2 ~= 0) or (tag == C.PW_BLUEFLAG and ps.powerups[C.PW_REDFLAG] ~= 0) then
					return true
				end
			end
		end

		if gametype == C.GT_DOUBLE_D then
			--We can touch both flags
			if tag == C.PW_BLUEFLAG or tag == C.PW_REDFLAG then
				return true
			end
		end

		if gametype == C.GT_DOMINATION then
			if tag == C.DOM_POINTWHITE then
				return true
			end
			if team == C.TEAM_RED then
				if tag == C.DOM_POINTBLUE then
					return true
				end
			elseif team == C.TEAM_BLUE then
				if tag == C.DOM_POINTRED then
					return true
				end
			end
		end

		if gametype == C.GT_HARVESTER then
			return true
		end
		return false
	elseif t == C.IT_HOLDABLE then
		-- can only hold one item at a time
		if ps.stats[C.STAT_HOLDABLE_ITEM] ~= 0 then
			return false
		end
		return true
	elseif t == C.IT_BAD then
		QS.Com_Error(C.ERR_DROP, "BG_CanItemBeGrabbed: IT_BAD")
	end

	return false
end

--======================================================================

local DEFAULT_GRAVITY = C.DEFAULT_GRAVITY
local M_PI = Q.M_PI

function BG.BG_EvaluateTrajectory(tr, atTime: number, result)
	local t = tr.trType
	local deltaTime
	if t == C.TR_STATIONARY or t == C.TR_INTERPOLATE then
		VectorCopy(tr.trBase, result)
	elseif t == C.TR_LINEAR then
		deltaTime = f((atTime - tr.trTime) * 0.001) -- milliseconds to seconds
		VectorMA(tr.trBase, deltaTime, tr.trDelta, result)
	elseif t == C.TR_SINE then
		deltaTime = f(f(atTime - tr.trTime) / tr.trDuration)
		local phase = f(sin(deltaTime * M_PI * 2))
		VectorMA(tr.trBase, phase, tr.trDelta, result)
	elseif t == C.TR_LINEAR_STOP then
		if atTime > tr.trTime + tr.trDuration then
			atTime = tr.trTime + tr.trDuration
		end
		deltaTime = f((atTime - tr.trTime) * 0.001) -- milliseconds to seconds
		if deltaTime < 0 then
			deltaTime = 0
		end
		VectorMA(tr.trBase, deltaTime, tr.trDelta, result)
	elseif t == C.TR_GRAVITY then
		deltaTime = f((atTime - tr.trTime) * 0.001) -- milliseconds to seconds
		VectorMA(tr.trBase, deltaTime, tr.trDelta, result)
		result[2] = f(result[2] - 0.5 * DEFAULT_GRAVITY * deltaTime * deltaTime) -- FIXME: local gravity...
	else
		QS.Com_Error(C.ERR_DROP, QS.va("BG_EvaluateTrajectory: unknown trType: %i", tr.trTime))
	end
end

-- For determining velocity at a given time
function BG.BG_EvaluateTrajectoryDelta(tr, atTime: number, result)
	local t = tr.trType
	if t == C.TR_STATIONARY or t == C.TR_INTERPOLATE then
		VectorClear(result)
	elseif t == C.TR_LINEAR then
		VectorCopy(tr.trDelta, result)
	elseif t == C.TR_SINE then
		local deltaTime = f(f(atTime - tr.trTime) / tr.trDuration)
		local phase = f(cos(deltaTime * M_PI * 2)) -- derivative of sin = cos
		phase = f(phase * 0.5)
		VectorScale(tr.trDelta, phase, result)
	elseif t == C.TR_LINEAR_STOP then
		if atTime > tr.trTime + tr.trDuration then
			VectorClear(result)
			return
		end
		VectorCopy(tr.trDelta, result)
	elseif t == C.TR_GRAVITY then
		local deltaTime = f((atTime - tr.trTime) * 0.001) -- milliseconds to seconds
		VectorCopy(tr.trDelta, result)
		result[2] = f(result[2] - f(DEFAULT_GRAVITY * deltaTime)) -- FIXME: local gravity...
	else
		QS.Com_Error(C.ERR_DROP, QS.va("BG_EvaluateTrajectoryDelta: unknown trType: %i", tr.trTime))
	end
end

BG.eventnames = {
	[0] = "EV_NONE",
	"EV_FOOTSTEP", "EV_FOOTSTEP_METAL", "EV_FOOTSPLASH", "EV_FOOTWADE", "EV_SWIM",
	"EV_STEP_4", "EV_STEP_8", "EV_STEP_12", "EV_STEP_16",
	"EV_FALL_SHORT", "EV_FALL_MEDIUM", "EV_FALL_FAR",
	"EV_JUMP_PAD",
	"EV_JUMP", "EV_WATER_TOUCH", "EV_WATER_LEAVE", "EV_WATER_UNDER", "EV_WATER_CLEAR",
	"EV_ITEM_PICKUP", "EV_GLOBAL_ITEM_PICKUP",
	"EV_NOAMMO", "EV_CHANGE_WEAPON", "EV_FIRE_WEAPON",
	"EV_USE_ITEM0", "EV_USE_ITEM1", "EV_USE_ITEM2", "EV_USE_ITEM3", "EV_USE_ITEM4", "EV_USE_ITEM5",
	"EV_USE_ITEM6", "EV_USE_ITEM7", "EV_USE_ITEM8", "EV_USE_ITEM9", "EV_USE_ITEM10", "EV_USE_ITEM11",
	"EV_USE_ITEM12", "EV_USE_ITEM13", "EV_USE_ITEM14", "EV_USE_ITEM15",
	"EV_ITEM_RESPAWN", "EV_ITEM_POP", "EV_PLAYER_TELEPORT_IN", "EV_PLAYER_TELEPORT_OUT",
	"EV_GRENADE_BOUNCE",
	"EV_GENERAL_SOUND", "EV_GLOBAL_SOUND", "EV_GLOBAL_TEAM_SOUND",
	"EV_BULLET_HIT_FLESH", "EV_BULLET_HIT_WALL",
	"EV_MISSILE_HIT", "EV_MISSILE_MISS", "EV_MISSILE_MISS_METAL", "EV_RAILTRAIL", "EV_SHOTGUN", "EV_BULLET",
	"EV_PAIN", "EV_DEATH1", "EV_DEATH2", "EV_DEATH3", "EV_OBITUARY",
	"EV_POWERUP_QUAD", "EV_POWERUP_BATTLESUIT", "EV_POWERUP_REGEN",
	"EV_GIB_PLAYER", "EV_SCOREPLUM",
	"EV_PROXIMITY_MINE_STICK", "EV_PROXIMITY_MINE_TRIGGER", "EV_KAMIKAZE", "EV_OBELISKEXPLODE",
	"EV_INVUL_IMPACT", "EV_JUICED", "EV_LIGHTNINGBOLT",
	"EV_DEBUG_LINE", "EV_STOPLOOPINGSOUND", "EV_TAUNT",
}

-- Handles the sequence numbers
function BG.BG_AddPredictableEventToPlayerstate(newEvent: number, eventParm: number, ps)
	local MAX_PS_EVENTS = C.MAX_PS_EVENTS
	ps.events[band(ps.eventSequence, MAX_PS_EVENTS - 1)] = newEvent
	ps.eventParms[band(ps.eventSequence, MAX_PS_EVENTS - 1)] = eventParm
	ps.eventSequence += 1
end

local tjangles = Q.vec3()
function BG.BG_TouchJumpPad(ps, jumppad)
	-- spectators don't use jump pads
	if ps.pm_type ~= C.PM_NORMAL then
		return
	end

	-- flying characters don't hit bounce pads
	if ps.powerups[C.PW_FLIGHT] ~= 0 then
		return
	end

	-- if we didn't hit this same jumppad the previous frame
	-- then don't play the event sound again if we are in a fat trigger
	if ps.jumppad_ent ~= jumppad.number then
		Q.vectoangles(jumppad.origin2, tjangles)
		local p = abs(Q.AngleNormalize180(tjangles[C.PITCH]))
		local effectNum
		if p < 45 then
			effectNum = 0
		else
			effectNum = 1
		end
		BG.BG_AddPredictableEventToPlayerstate(C.EV_JUMP_PAD, effectNum, ps)
	end
	-- remember hitting this jumppad this frame
	ps.jumppad_ent = jumppad.number
	ps.jumppad_frame = ps.pmove_framecount
	-- give the player the velocity from the jumppad
	VectorCopy(jumppad.origin2, ps.velocity)
end

local function psToEs(ps, s)
	if ps.pm_type == C.PM_INTERMISSION or ps.pm_type == C.PM_SPECTATOR then
		s.eType = C.ET_INVISIBLE
	elseif ps.stats[C.STAT_HEALTH] <= C.GIB_HEALTH then
		s.eType = C.ET_INVISIBLE
	else
		s.eType = C.ET_PLAYER
	end
	s.number = ps.clientNum
end

local function psToEsTail(ps, s)
	s.angles2[C.YAW] = ps.movementDir
	s.legsAnim = ps.legsAnim
	s.torsoAnim = ps.torsoAnim
	s.clientNum = ps.clientNum -- ET_PLAYER looks here instead of at number
	-- so corpses can also reference the proper config
	s.eFlags = ps.eFlags
	if ps.stats[C.STAT_HEALTH] <= 0 then
		s.eFlags = bor(s.eFlags, C.EF_DEAD)
	else
		s.eFlags = band(s.eFlags, bnot(C.EF_DEAD))
	end

	local MAX_PS_EVENTS = C.MAX_PS_EVENTS
	if ps.externalEvent ~= 0 then
		s.event = ps.externalEvent
		s.eventParm = ps.externalEventParm
	elseif ps.entityEventSequence < ps.eventSequence then
		if ps.entityEventSequence < ps.eventSequence - MAX_PS_EVENTS then
			ps.entityEventSequence = ps.eventSequence - MAX_PS_EVENTS
		end
		local seq = band(ps.entityEventSequence, MAX_PS_EVENTS - 1)
		s.event = bor(ps.events[seq], lshift(band(ps.entityEventSequence, 3), 8))
		s.eventParm = ps.eventParms[seq]
		ps.entityEventSequence += 1
	end

	s.weapon = ps.weapon
	s.groundEntityNum = ps.groundEntityNum

	s.powerups = 0
	for i = 0, C.MAX_POWERUPS - 1 do
		if ps.powerups[i] ~= 0 then
			s.powerups = bor(s.powerups, lshift(1, i))
		end
	end

	s.loopSound = ps.loopSound
	s.generic1 = ps.generic1
end

-- This is done after each set of usercmd_t on the server,
-- and after local prediction on the client
function BG.BG_PlayerStateToEntityState(ps, s, snap: boolean)
	psToEs(ps, s)

	s.pos.trType = C.TR_INTERPOLATE
	VectorCopy(ps.origin, s.pos.trBase)
	if snap then
		SnapVector(s.pos.trBase)
	end
	-- set the trDelta for flag direction
	VectorCopy(ps.velocity, s.pos.trDelta)

	s.apos.trType = C.TR_INTERPOLATE
	VectorCopy(ps.viewangles, s.apos.trBase)
	if snap then
		SnapVector(s.apos.trBase)
	end

	psToEsTail(ps, s)
end

function BG.BG_PlayerStateToEntityStateExtraPolate(ps, s, time: number, snap: boolean)
	psToEs(ps, s)

	s.pos.trType = C.TR_LINEAR_STOP
	VectorCopy(ps.origin, s.pos.trBase)
	if snap then
		SnapVector(s.pos.trBase)
	end
	-- set the trDelta for flag direction and linear prediction
	VectorCopy(ps.velocity, s.pos.trDelta)
	-- set the time for linear prediction
	s.pos.trTime = time
	-- set maximum extra polation time
	s.pos.trDuration = 50 -- 1000 / sv_fps (default = 20)

	s.apos.trType = C.TR_INTERPOLATE
	VectorCopy(ps.viewangles, s.apos.trBase)
	if snap then
		SnapVector(s.apos.trBase)
	end

	psToEsTail(ps, s)
end

-- KK-OAX Copied from Tremulous
function BG.BG_TeamName(team: number): string
	if team == C.TEAM_NONE then
		return "spectator"
	end
	if team == C.TEAM_RED then
		return "Red"
	end
	if team == C.TEAM_BLUE then
		return "Blue"
	end
	if team == C.TEAM_FREE then
		return "Free For All"
	end
	return "<team>"
end

return BG
