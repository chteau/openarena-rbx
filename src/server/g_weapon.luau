--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_weapon.c).

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
-- Luau port of g_weapon.c: perform the server side effects of a weapon firing.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local s_quadFactor = 0
local forward = Q.vec3()
local right = Q.vec3()
local up = Q.vec3()
local muzzle = Q.vec3()

local NUM_NAILSHOTS = 15

-- challenges.h value (not present in the shared constant tables)
local AWARD_IMPRESSIVE = 200

local CHAINGUN_SPREAD = 600.0
local MACHINEGUN_SPREAD = 200
local MACHINEGUN_DAMAGE = 7
local MACHINEGUN_TEAM_DAMAGE = 5
local DEFAULT_SHOTGUN_DAMAGE = 10
local MAX_RAIL_HITS = 4

function G.G_BounceProjectile(start, impact, dir, endout)
	local v = Q.vec3()
	local newv = Q.vec3()

	Q.VectorSubtract(impact, start, v)
	local dot = Q.DotProduct(v, dir)
	Q.VectorMA(v, -2 * dot, dir, newv)

	Q.VectorNormalize(newv)
	Q.VectorMA(impact, 8192, newv, endout)
end

--[[
======================================================================

GAUNTLET

======================================================================
]]

function G.Weapon_Gauntlet(ent)
end

function G.CheckGauntletAttack(ent)
	local tr = S.trace_t()
	local ending = Q.vec3()

	-- set aiming directions
	Q.AngleVectors(ent.client.ps.viewangles, forward, right, up)

	G.CalcMuzzlePoint(ent, forward, right, up, muzzle)

	Q.VectorMA(muzzle, 32, forward, ending)

	G.trap_Trace(tr, muzzle, nil, nil, ending, ent.s.number, C.MASK_SHOT)
	if bit32.band(tr.surfaceFlags, C.SURF_NOIMPACT) ~= 0 then
		return false
	end

	if ent.client.noclip then
		return false
	end

	local traceEnt = G.g_entities[tr.entityNum]

	-- send blood impact
	if traceEnt.takedamage and traceEnt.client ~= nil then
		local tent = G.G_TempEntity(tr.endpos, C.EV_MISSILE_HIT)
		tent.s.otherEntityNum = traceEnt.s.number
		tent.s.eventParm = Q.DirToByte(tr.plane.normal)
		tent.s.weapon = ent.s.weapon
	end

	if not traceEnt.takedamage then
		return false
	end

	if ent.client.ps.powerups[C.PW_QUAD] ~= 0 then
		G.G_AddEvent(ent, C.EV_POWERUP_QUAD, 0)
		s_quadFactor = G.g_quadfactor.value
	else
		s_quadFactor = 1
	end
	if ent.client.persistantPowerup ~= nil and ent.client.persistantPowerup.item ~= nil and ent.client.persistantPowerup.item.giTag == C.PW_DOUBLER then
		s_quadFactor *= 2
	end

	local damage
	if G.g_instantgib.integer ~= 0 then
		damage = 500 -- High damage in instant gib (normally enough to gib)
	else
		damage = Q.trunc(50 * s_quadFactor)
	end
	G.G_Damage(traceEnt, ent, ent, forward, tr.endpos, damage, 0, C.MOD_GAUNTLET)

	return true
end

--[[
======================================================================

MACHINEGUN

======================================================================
]]

-- unlagged - attack prediction #3: moved from g_weapon.c
function G.SnapVectorTowards(v, to)
	for i = 0, 2 do
		if to[i] <= v[i] then
			v[i] = Q.trunc(v[i])
		else
			v[i] = Q.trunc(v[i]) + 1
		end
	end
end

function G.Bullet_Fire(ent, spread, damage)
	local tr = S.trace_t()
	local ending = Q.vec3()
	local impactpoint = Q.vec3()
	local bouncedir = Q.vec3()

	-- we have to use something now that the client knows in advance
	local seed = { value = Q.imod(ent.client.attackTime, 256) }

	damage = Q.trunc(damage * s_quadFactor)

	-- this has to match what's on the client
	local r = Q.Q_random(seed) * math.pi * 2.0
	local u = math.sin(r) * Q.Q_crandom(seed) * spread * 16
	r = math.cos(r) * Q.Q_crandom(seed) * spread * 16

	Q.VectorMA(muzzle, 8192 * 16, forward, ending)
	Q.VectorMA(ending, r, right, ending)
	Q.VectorMA(ending, u, up, ending)

	local passent = ent.s.number
	for i = 0, 9 do
		-- backward-reconcile the other clients
		G.G_DoTimeShiftFor(ent)

		G.trap_Trace(tr, muzzle, nil, nil, ending, passent, C.MASK_SHOT)

		-- put them back
		G.G_UndoTimeShiftFor(ent)

		if bit32.band(tr.surfaceFlags, C.SURF_NOIMPACT) ~= 0 then
			return
		end

		local traceEnt = G.g_entities[tr.entityNum]

		-- snap the endpos to integers, but nudged towards the line
		G.SnapVectorTowards(tr.endpos, muzzle)

		-- send bullet impact
		local tent
		if traceEnt.takedamage and traceEnt.client ~= nil then
			tent = G.G_TempEntity(tr.endpos, C.EV_BULLET_HIT_FLESH)
			tent.s.eventParm = traceEnt.s.number
			-- we need the client number to determine whether or not to
			-- suppress this event
			tent.s.clientNum = ent.s.clientNum
			if G.LogAccuracyHit(traceEnt, ent) then
				ent.client.accuracy_hits += 1
			end
		else
			tent = G.G_TempEntity(tr.endpos, C.EV_BULLET_HIT_WALL)
			tent.s.eventParm = Q.DirToByte(tr.plane.normal)
			tent.s.clientNum = ent.s.clientNum
		end
		tent.s.otherEntityNum = ent.s.number

		if traceEnt.takedamage then
			if traceEnt.client ~= nil and traceEnt.client.invulnerabilityTime > G.level.time then
				if G.G_InvulnerabilityEffect(traceEnt, forward, tr.endpos, impactpoint, bouncedir) ~= 0 then
					G.G_BounceProjectile(muzzle, impactpoint, bouncedir, ending)
					Q.VectorCopy(impactpoint, muzzle)
					-- the player can hit him/herself with the bounced rail
					passent = C.ENTITYNUM_NONE
				else
					Q.VectorCopy(tr.endpos, muzzle)
					passent = traceEnt.s.number
				end
				continue
			else
				if spread == CHAINGUN_SPREAD then
					G.G_Damage(traceEnt, ent, ent, forward, tr.endpos, damage, 0, C.MOD_CHAINGUN)
					ent.client.accuracy[C.WP_CHAINGUN][1] += 1
				else
					G.G_Damage(traceEnt, ent, ent, forward, tr.endpos, damage, 0, C.MOD_MACHINEGUN)
					ent.client.accuracy[C.WP_MACHINEGUN][1] += 1
				end
			end
		end
		break
	end
end

--[[
======================================================================

BFG

======================================================================
]]

function G.BFG_Fire(ent)
	local m = G.fire_bfg(ent, muzzle, forward)
	m.damage = Q.trunc(m.damage * s_quadFactor)
	m.splashDamage = Q.trunc(m.splashDamage * s_quadFactor)
end

--[[
======================================================================

SHOTGUN

======================================================================
]]

function G.ShotgunPellet(start, ending, ent)
	local tr = S.trace_t()
	local impactpoint = Q.vec3()
	local bouncedir = Q.vec3()
	local tr_start = Q.vec3()
	local tr_end = Q.vec3()
	local hitClient = false

	local passent = ent.s.number
	Q.VectorCopy(start, tr_start)
	Q.VectorCopy(ending, tr_end)
	for i = 0, 9 do
		G.trap_Trace(tr, tr_start, nil, nil, tr_end, passent, C.MASK_SHOT)
		local traceEnt = G.g_entities[tr.entityNum]

		-- send bullet impact
		if bit32.band(tr.surfaceFlags, C.SURF_NOIMPACT) ~= 0 then
			return false
		end

		if traceEnt.takedamage then
			local damage = Q.trunc(DEFAULT_SHOTGUN_DAMAGE * s_quadFactor)
			if traceEnt.client ~= nil and traceEnt.client.invulnerabilityTime > G.level.time then
				if G.G_InvulnerabilityEffect(traceEnt, forward, tr.endpos, impactpoint, bouncedir) ~= 0 then
					G.G_BounceProjectile(tr_start, impactpoint, bouncedir, tr_end)
					Q.VectorCopy(impactpoint, tr_start)
					-- the player can hit him/herself with the bounced rail
					passent = C.ENTITYNUM_NONE
				else
					Q.VectorCopy(tr.endpos, tr_start)
					passent = traceEnt.s.number
				end
				continue
			end
			if G.LogAccuracyHit(traceEnt, ent) then
				hitClient = true
			end
			G.G_Damage(traceEnt, ent, ent, forward, tr.endpos, damage, 0, C.MOD_SHOTGUN)
			return hitClient
		end
		return false
	end
	return false
end

-- this should match CG_ShotgunPattern
function G.ShotgunPattern(origin, origin2, seedValue, ent)
	local ending = Q.vec3()
	local fwd = Q.vec3()
	local rgt = Q.vec3()
	local upv = Q.vec3()
	local hitClient = false
	local seed = { value = seedValue }

	-- derive the right and up vectors from the forward vector, because
	-- the client won't have any other information
	Q.VectorNormalize2(origin2, fwd)
	Q.PerpendicularVector(rgt, fwd)
	Q.CrossProduct(fwd, rgt, upv)

	-- backward-reconcile the other clients
	G.G_DoTimeShiftFor(ent)

	-- generate the "random" spread pattern
	for i = 0, C.DEFAULT_SHOTGUN_COUNT - 1 do
		local r = Q.Q_crandom(seed) * C.DEFAULT_SHOTGUN_SPREAD * 16
		local u = Q.Q_crandom(seed) * C.DEFAULT_SHOTGUN_SPREAD * 16
		Q.VectorMA(origin, 8192 * 16, fwd, ending)
		Q.VectorMA(ending, r, rgt, ending)
		Q.VectorMA(ending, u, upv, ending)
		if G.ShotgunPellet(origin, ending, ent) and not hitClient then
			hitClient = true
			ent.client.accuracy_hits += 1
		end
	end
	if hitClient then
		ent.client.accuracy[C.WP_SHOTGUN][1] += 1
	end

	-- put them back
	G.G_UndoTimeShiftFor(ent)
end

function G.weapon_supershotgun_fire(ent)
	-- send shotgun blast
	local tent = G.G_TempEntity(muzzle, C.EV_SHOTGUN)
	Q.VectorScale(forward, 4096, tent.s.origin2)
	Q.SnapVector(tent.s.origin2)
	-- this has to be something the client can predict now
	tent.s.eventParm = Q.imod(ent.client.attackTime, 256) -- seed for spread pattern
	tent.s.otherEntityNum = ent.s.number

	G.ShotgunPattern(tent.s.pos.trBase, tent.s.origin2, tent.s.eventParm, ent)
end

--[[
======================================================================

GRENADE LAUNCHER

======================================================================
]]

function G.weapon_grenadelauncher_fire(ent)
	-- extra vertical velocity
	forward[2] += 0.2
	Q.VectorNormalize(forward)

	local m = G.fire_grenade(ent, muzzle, forward)
	m.damage = Q.trunc(m.damage * s_quadFactor)
	m.splashDamage = Q.trunc(m.splashDamage * s_quadFactor)
end

--[[
======================================================================

ROCKET

======================================================================
]]

function G.Weapon_RocketLauncher_Fire(ent)
	local m = G.fire_rocket(ent, muzzle, forward)
	m.damage = Q.trunc(m.damage * s_quadFactor)
	m.splashDamage = Q.trunc(m.splashDamage * s_quadFactor)
end

--[[
======================================================================

PLASMA GUN

======================================================================
]]

function G.Weapon_Plasmagun_Fire(ent)
	local m = G.fire_plasma(ent, muzzle, forward)
	m.damage = Q.trunc(m.damage * s_quadFactor)
	m.splashDamage = Q.trunc(m.splashDamage * s_quadFactor)
end

--[[
======================================================================

RAILGUN

======================================================================
]]

function G.weapon_railgun_fire(ent)
	local ending = Q.vec3()
	local impactpoint = Q.vec3()
	local bouncedir = Q.vec3()
	local trace = S.trace_t()
	local unlinkedEntities = {}

	local damage = Q.trunc(100 * s_quadFactor)
	if G.g_instantgib.integer ~= 0 then
		damage = 800
	end

	Q.VectorMA(muzzle, 8192, forward, ending)

	-- backward-reconcile the other clients
	G.G_DoTimeShiftFor(ent)

	-- trace only against the solids, so the railgun will go through people
	local unlinked = 0
	local hits = 0
	local passent = ent.s.number
	repeat
		G.trap_Trace(trace, muzzle, nil, nil, ending, passent, C.MASK_SHOT)
		if trace.entityNum >= C.ENTITYNUM_MAX_NORMAL then
			break
		end
		local traceEnt = G.g_entities[trace.entityNum]
		if traceEnt.takedamage then
			if traceEnt.client ~= nil and traceEnt.client.invulnerabilityTime > G.level.time then
				if G.G_InvulnerabilityEffect(traceEnt, forward, trace.endpos, impactpoint, bouncedir) ~= 0 then
					G.G_BounceProjectile(muzzle, impactpoint, bouncedir, ending)
					-- snap the endpos to integers to save net bandwidth, but nudged towards the line
					G.SnapVectorTowards(trace.endpos, muzzle)
					-- send railgun beam effect
					local tent = G.G_TempEntity(trace.endpos, C.EV_RAILTRAIL)
					-- set player number for custom colors on the railtrail
					tent.s.clientNum = ent.s.clientNum
					Q.VectorCopy(muzzle, tent.s.origin2)
					-- move origin a bit to come closer to the drawn gun muzzle
					Q.VectorMA(tent.s.origin2, 4, right, tent.s.origin2)
					Q.VectorMA(tent.s.origin2, -1, up, tent.s.origin2)
					tent.s.eventParm = 255 -- don't make the explosion at the end
					--
					Q.VectorCopy(impactpoint, muzzle)
					-- the player can hit him/herself with the bounced rail
					passent = C.ENTITYNUM_NONE
				end
			else
				if G.LogAccuracyHit(traceEnt, ent) then
					hits += 1
				end
				G.G_Damage(traceEnt, ent, ent, forward, trace.endpos, damage, 0, C.MOD_RAILGUN)
			end
		end
		if bit32.band(trace.contents, C.CONTENTS_SOLID) ~= 0 then
			break -- we hit something solid enough to stop the beam
		end
		-- unlink this entity, so the next trace will go past it
		G.trap_UnlinkEntity(traceEnt)
		unlinkedEntities[unlinked] = traceEnt
		unlinked += 1
	until not (unlinked < MAX_RAIL_HITS)

	-- put them back
	G.G_UndoTimeShiftFor(ent)

	-- link back in any entities we unlinked
	for i = 0, unlinked - 1 do
		G.trap_LinkEntity(unlinkedEntities[i])
	end

	-- the final trace endpos will be the terminal point of the rail trail

	-- snap the endpos to integers to save net bandwidth, but nudged towards the line
	G.SnapVectorTowards(trace.endpos, muzzle)

	-- send railgun beam effect
	local tent = G.G_TempEntity(trace.endpos, C.EV_RAILTRAIL)

	-- set player number for custom colors on the railtrail
	tent.s.clientNum = ent.s.clientNum

	Q.VectorCopy(muzzle, tent.s.origin2)
	-- move origin a bit to come closer to the drawn gun muzzle
	Q.VectorMA(tent.s.origin2, 4, right, tent.s.origin2)
	Q.VectorMA(tent.s.origin2, -1, up, tent.s.origin2)

	-- no explosion at end if SURF_NOIMPACT, but still make the trail
	if bit32.band(trace.surfaceFlags, C.SURF_NOIMPACT) ~= 0 then
		tent.s.eventParm = 255 -- don't make the explosion at the end
	else
		tent.s.eventParm = Q.DirToByte(trace.plane.normal)
	end
	tent.s.clientNum = ent.s.clientNum

	-- give the shooter a reward sound if they have made two railgun hits in a row
	if hits == 0 then
		-- complete miss
		ent.client.accurateCount = 0
	else
		-- check for "impressive" reward sound
		ent.client.accurateCount += hits
		if ent.client.accurateCount >= 2 then
			ent.client.accurateCount -= 2
			ent.client.ps.persistant[C.PERS_IMPRESSIVE_COUNT] += 1
			G.G_LogPrintf("Award: %i %i: %s gained the %s award!\n", ent.client.ps.clientNum, 2, ent.client.pers.netname, "IMPRESSIVE")
			if not G.level.hadBots then -- There has not been any bots
				G.ChallengeMessage(ent, AWARD_IMPRESSIVE)
			end
			-- add the sprite over the player's head
			ent.client.ps.eFlags = bit32.band(ent.client.ps.eFlags, bit32.bnot(bit32.bor(C.EF_AWARD_IMPRESSIVE, C.EF_AWARD_EXCELLENT, C.EF_AWARD_GAUNTLET, C.EF_AWARD_ASSIST, C.EF_AWARD_DEFEND, C.EF_AWARD_CAP)))
			ent.client.ps.eFlags = bit32.bor(ent.client.ps.eFlags, C.EF_AWARD_IMPRESSIVE)
			ent.client.rewardTime = G.level.time + C.REWARD_SPRITE_TIME
		end
		ent.client.accuracy_hits += 1
		ent.client.accuracy[C.WP_RAILGUN][1] += 1
	end
end

--[[
======================================================================

GRAPPLING HOOK

======================================================================
]]

function G.Weapon_GrapplingHook_Fire(ent)
	if not ent.client.fireHeld and ent.client.hook == nil then
		G.fire_grapple(ent, muzzle, forward)
	end

	ent.client.fireHeld = true
end

function G.Weapon_HookFree(ent)
	ent.parent.client.hook = nil
	ent.parent.client.ps.pm_flags = bit32.band(ent.parent.client.ps.pm_flags, bit32.bnot(C.PMF_GRAPPLE_PULL))
	G.G_FreeEntity(ent)
end

function G.Weapon_HookThink(ent)
	if ent.enemy ~= nil then
		local v = Q.vec3()
		local oldorigin = Q.vec3()

		Q.VectorCopy(ent.r.currentOrigin, oldorigin)
		v[0] = ent.enemy.r.currentOrigin[0] + (ent.enemy.r.mins[0] + ent.enemy.r.maxs[0]) * 0.5
		v[1] = ent.enemy.r.currentOrigin[1] + (ent.enemy.r.mins[1] + ent.enemy.r.maxs[1]) * 0.5
		v[2] = ent.enemy.r.currentOrigin[2] + (ent.enemy.r.mins[2] + ent.enemy.r.maxs[2]) * 0.5
		G.SnapVectorTowards(v, oldorigin) -- save net bandwidth

		G.G_SetOrigin(ent, v)
	end

	Q.VectorCopy(ent.r.currentOrigin, ent.parent.client.ps.grapplePoint)
end

--[[
======================================================================

LIGHTNING GUN

======================================================================
]]

function G.Weapon_LightningFire(ent)
	local tr = S.trace_t()
	local ending = Q.vec3()
	local impactpoint = Q.vec3()
	local bouncedir = Q.vec3()

	local damage = Q.trunc(8 * s_quadFactor)

	local passent = ent.s.number
	for i = 0, 9 do
		Q.VectorMA(muzzle, C.LIGHTNING_RANGE, forward, ending)

		-- backward-reconcile the other clients
		G.G_DoTimeShiftFor(ent)

		G.trap_Trace(tr, muzzle, nil, nil, ending, passent, C.MASK_SHOT)

		-- put them back
		G.G_UndoTimeShiftFor(ent)

		-- if not the first trace (the lightning bounced of an invulnerability sphere)
		if i ~= 0 then
			-- add bounced off lightning bolt temp entity
			-- the first lightning bolt is a cgame only visual
			--
			local tent = G.G_TempEntity(muzzle, C.EV_LIGHTNINGBOLT)
			Q.VectorCopy(tr.endpos, ending)
			Q.SnapVector(ending)
			Q.VectorCopy(ending, tent.s.origin2)
		end
		if tr.entityNum == C.ENTITYNUM_NONE then
			return
		end

		local traceEnt = G.g_entities[tr.entityNum]

		if traceEnt.takedamage then
			if traceEnt.client ~= nil and traceEnt.client.invulnerabilityTime > G.level.time then
				if G.G_InvulnerabilityEffect(traceEnt, forward, tr.endpos, impactpoint, bouncedir) ~= 0 then
					G.G_BounceProjectile(muzzle, impactpoint, bouncedir, ending)
					Q.VectorCopy(impactpoint, muzzle)
					Q.VectorSubtract(ending, impactpoint, forward)
					Q.VectorNormalize(forward)
					-- the player can hit him/herself with the bounced lightning
					passent = C.ENTITYNUM_NONE
				else
					Q.VectorCopy(tr.endpos, muzzle)
					passent = traceEnt.s.number
				end
				continue
			end
			if G.LogAccuracyHit(traceEnt, ent) then
				ent.client.accuracy_hits += 1
			end
			G.G_Damage(traceEnt, ent, ent, forward, tr.endpos, damage, 0, C.MOD_LIGHTNING)
		end

		if traceEnt.takedamage and traceEnt.client ~= nil then
			local tent = G.G_TempEntity(tr.endpos, C.EV_MISSILE_HIT)
			tent.s.otherEntityNum = traceEnt.s.number
			tent.s.eventParm = Q.DirToByte(tr.plane.normal)
			tent.s.weapon = ent.s.weapon
		elseif bit32.band(tr.surfaceFlags, C.SURF_NOIMPACT) == 0 then
			local tent = G.G_TempEntity(tr.endpos, C.EV_MISSILE_MISS)
			tent.s.eventParm = Q.DirToByte(tr.plane.normal)
		end

		break
	end
end

--[[
======================================================================

NAILGUN

======================================================================
]]

function G.Weapon_Nailgun_Fire(ent)
	for count = 0, NUM_NAILSHOTS - 1 do
		local m = G.fire_nail(ent, muzzle, forward, right, up)
		m.damage = Q.trunc(m.damage * s_quadFactor)
		m.splashDamage = Q.trunc(m.splashDamage * s_quadFactor)
	end
end

--[[
======================================================================

PROXIMITY MINE LAUNCHER

======================================================================
]]

function G.weapon_proxlauncher_fire(ent)
	-- extra vertical velocity
	forward[2] += 0.2
	Q.VectorNormalize(forward)

	local m = G.fire_prox(ent, muzzle, forward)
	m.damage = Q.trunc(m.damage * s_quadFactor)
	m.splashDamage = Q.trunc(m.splashDamage * s_quadFactor)
end

--======================================================================

function G.LogAccuracyHit(target, attacker)
	if not target.takedamage then
		return false
	end

	if target == attacker then
		return false
	end

	if target.client == nil then
		return false
	end

	if attacker.client == nil then
		return false
	end

	if target.client.ps.stats[C.STAT_HEALTH] <= 0 then
		return false
	end

	if G.OnSameTeam(target, attacker) then
		return false
	end

	return true
end

--[[
===============
CalcMuzzlePoint

set muzzle location relative to pivoting eye
===============
]]
function G.CalcMuzzlePoint(ent, fwd, rgt, upv, muzzlePoint)
	Q.VectorCopy(ent.s.pos.trBase, muzzlePoint)
	muzzlePoint[2] += ent.client.ps.viewheight
	Q.VectorMA(muzzlePoint, 14, fwd, muzzlePoint)
	-- snap to integer coordinates for more efficient network bandwidth usage
	Q.SnapVector(muzzlePoint)
end

function G.CalcMuzzlePointOrigin(ent, origin, fwd, rgt, upv, muzzlePoint)
	Q.VectorCopy(ent.s.pos.trBase, muzzlePoint)
	muzzlePoint[2] += ent.client.ps.viewheight
	Q.VectorMA(muzzlePoint, 14, fwd, muzzlePoint)
	-- snap to integer coordinates for more efficient network bandwidth usage
	Q.SnapVector(muzzlePoint)
end

function G.FireWeapon(ent)
	-- Make people drop out of follow mode (this should be moved, so people can change betwean players.)
	if ent.client.sess.spectatorState == C.SPECTATOR_FOLLOW then
		G.StopFollowing(ent)
		return
	end

	if ent.client.ps.powerups[C.PW_QUAD] ~= 0 then
		s_quadFactor = G.g_quadfactor.value
	else
		s_quadFactor = 1
	end
	if ent.client.persistantPowerup ~= nil and ent.client.persistantPowerup.item ~= nil and ent.client.persistantPowerup.item.giTag == C.PW_DOUBLER then
		s_quadFactor *= 2
	end

	if ent.client.spawnprotected then
		ent.client.spawnprotected = false
	end

	-- track shots taken for accuracy tracking.  Grapple is not a weapon and gauntet is just not tracked
	if ent.s.weapon ~= C.WP_GRAPPLING_HOOK and ent.s.weapon ~= C.WP_GAUNTLET then
		if ent.s.weapon == C.WP_NAILGUN then
			ent.client.accuracy_shots += NUM_NAILSHOTS
			ent.client.accuracy[C.WP_NAILGUN][0] += 1
		else
			ent.client.accuracy_shots += 1
			ent.client.accuracy[ent.s.weapon][0] += 1
		end
	end

	-- set aiming directions
	Q.AngleVectors(ent.client.ps.viewangles, forward, right, up)

	G.CalcMuzzlePointOrigin(ent, ent.client.oldOrigin, forward, right, up, muzzle)

	-- fire the specific weapon
	local w = ent.s.weapon
	if w == C.WP_GAUNTLET then
		G.Weapon_Gauntlet(ent)
	elseif w == C.WP_LIGHTNING then
		G.Weapon_LightningFire(ent)
	elseif w == C.WP_SHOTGUN then
		G.weapon_supershotgun_fire(ent)
	elseif w == C.WP_MACHINEGUN then
		if G.g_gametype.integer ~= C.GT_TEAM then
			G.Bullet_Fire(ent, MACHINEGUN_SPREAD, MACHINEGUN_DAMAGE)
		else
			G.Bullet_Fire(ent, MACHINEGUN_SPREAD, MACHINEGUN_TEAM_DAMAGE)
		end
	elseif w == C.WP_GRENADE_LAUNCHER then
		G.weapon_grenadelauncher_fire(ent)
	elseif w == C.WP_ROCKET_LAUNCHER then
		G.Weapon_RocketLauncher_Fire(ent)
	elseif w == C.WP_PLASMAGUN then
		G.Weapon_Plasmagun_Fire(ent)
	elseif w == C.WP_RAILGUN then
		G.weapon_railgun_fire(ent)
	elseif w == C.WP_BFG then
		G.BFG_Fire(ent)
	elseif w == C.WP_GRAPPLING_HOOK then
		G.Weapon_GrapplingHook_Fire(ent)
	elseif w == C.WP_NAILGUN then
		G.Weapon_Nailgun_Fire(ent)
	elseif w == C.WP_PROX_LAUNCHER then
		G.weapon_proxlauncher_fire(ent)
	elseif w == C.WP_CHAINGUN then
		G.Bullet_Fire(ent, CHAINGUN_SPREAD, MACHINEGUN_DAMAGE)
	end
end

local function KamikazeRadiusDamage(origin, attacker, damage, radius)
	local entityList = {}
	local mins = Q.vec3()
	local maxs = Q.vec3()
	local v = Q.vec3()
	local dir = Q.vec3()

	if radius < 1 then
		radius = 1
	end

	for i = 0, 2 do
		mins[i] = origin[i] - radius
		maxs[i] = origin[i] + radius
	end

	local numListedEntities = G.trap_EntitiesInBox(mins, maxs, entityList, C.MAX_GENTITIES)

	for e = 0, numListedEntities - 1 do
		local ent = G.g_entities[entityList[e]]

		if not ent.takedamage then
			continue
		end

		-- dont hit things we have already hit
		if ent.kamikazeTime > G.level.time then
			continue
		end

		-- find the distance from the edge of the bounding box
		for i = 0, 2 do
			if origin[i] < ent.r.absmin[i] then
				v[i] = ent.r.absmin[i] - origin[i]
			elseif origin[i] > ent.r.absmax[i] then
				v[i] = origin[i] - ent.r.absmax[i]
			else
				v[i] = 0
			end
		end

		local dist = Q.VectorLength(v)
		if dist >= radius then
			continue
		end

		Q.VectorSubtract(ent.r.currentOrigin, origin, dir)
		-- push the center of mass higher than the origin so players
		-- get knocked into the air more
		dir[2] += 24
		G.G_Damage(ent, nil, attacker, dir, origin, Q.trunc(damage), bit32.bor(C.DAMAGE_RADIUS, C.DAMAGE_NO_TEAM_PROTECTION), C.MOD_KAMIKAZE)
		ent.kamikazeTime = G.level.time + 3000
	end
end

local function KamikazeShockWave(origin, attacker, damage, push, radius)
	local entityList = {}
	local mins = Q.vec3()
	local maxs = Q.vec3()
	local v = Q.vec3()
	local dir = Q.vec3()

	if radius < 1 then
		radius = 1
	end

	for i = 0, 2 do
		mins[i] = origin[i] - radius
		maxs[i] = origin[i] + radius
	end

	local numListedEntities = G.trap_EntitiesInBox(mins, maxs, entityList, C.MAX_GENTITIES)

	for e = 0, numListedEntities - 1 do
		local ent = G.g_entities[entityList[e]]

		-- dont hit things we have already hit
		if ent.kamikazeShockTime > G.level.time then
			continue
		end

		-- find the distance from the edge of the bounding box
		for i = 0, 2 do
			if origin[i] < ent.r.absmin[i] then
				v[i] = ent.r.absmin[i] - origin[i]
			elseif origin[i] > ent.r.absmax[i] then
				v[i] = origin[i] - ent.r.absmax[i]
			else
				v[i] = 0
			end
		end

		local dist = Q.VectorLength(v)
		if dist >= radius then
			continue
		end

		Q.VectorSubtract(ent.r.currentOrigin, origin, dir)
		dir[2] += 24
		G.G_Damage(ent, nil, attacker, dir, origin, Q.trunc(damage), bit32.bor(C.DAMAGE_RADIUS, C.DAMAGE_NO_TEAM_PROTECTION), C.MOD_KAMIKAZE)
		--
		dir[2] = 0
		Q.VectorNormalize(dir)
		if ent.client ~= nil then
			ent.client.ps.velocity[0] = Q.f(dir[0] * push)
			ent.client.ps.velocity[1] = Q.f(dir[1] * push)
			ent.client.ps.velocity[2] = 100
		end
		ent.kamikazeShockTime = G.level.time + 3000
	end
end

local function KamikazeDamage(self)
	local newangles = Q.vec3()

	self.count += 100

	if self.count >= C.KAMI_SHOCKWAVE_STARTTIME then
		-- shockwave push back
		local t = self.count - C.KAMI_SHOCKWAVE_STARTTIME
		KamikazeShockWave(self.s.pos.trBase, self.activator, 25, 400, Q.idiv(Q.trunc(t) * C.KAMI_SHOCKWAVE_MAXRADIUS, C.KAMI_SHOCKWAVE_ENDTIME - C.KAMI_SHOCKWAVE_STARTTIME))
	end
	--
	if self.count >= C.KAMI_EXPLODE_STARTTIME then
		-- do our damage
		local t = self.count - C.KAMI_EXPLODE_STARTTIME
		KamikazeRadiusDamage(self.s.pos.trBase, self.activator, 400, Q.idiv(Q.trunc(t) * C.KAMI_BOOMSPHERE_MAXRADIUS, C.KAMI_IMPLODE_STARTTIME - C.KAMI_EXPLODE_STARTTIME))
	end

	-- either cycle or kill self
	if self.count >= C.KAMI_SHOCKWAVE_ENDTIME then
		G.G_FreeEntity(self)
		return
	end
	self.nextthink = G.level.time + 100

	-- add earth quake effect
	newangles[0] = Q.crandom() * 2
	newangles[1] = Q.crandom() * 2
	newangles[2] = 0
	for i = 0, C.MAX_CLIENTS - 1 do
		local ent = G.g_entities[i]
		if not ent.inuse then
			continue
		end
		if ent.client == nil then
			continue
		end

		if ent.client.ps.groundEntityNum ~= C.ENTITYNUM_NONE then
			ent.client.ps.velocity[0] = Q.f(ent.client.ps.velocity[0] + Q.crandom() * 120)
			ent.client.ps.velocity[1] = Q.f(ent.client.ps.velocity[1] + Q.crandom() * 120)
			ent.client.ps.velocity[2] = Q.f(30 + Q.random() * 25)
		end

		ent.client.ps.delta_angles[0] += Q.ANGLE2SHORT(newangles[0] - self.movedir[0])
		ent.client.ps.delta_angles[1] += Q.ANGLE2SHORT(newangles[1] - self.movedir[1])
		ent.client.ps.delta_angles[2] += Q.ANGLE2SHORT(newangles[2] - self.movedir[2])
	end
	Q.VectorCopy(newangles, self.movedir)
end

function G.G_StartKamikaze(ent)
	local snapped = Q.vec3()

	-- start up the explosion logic
	local explosion = G.G_Spawn()

	explosion.s.eType = C.ET_EVENTS + C.EV_KAMIKAZE
	explosion.eventTime = G.level.time

	if ent.client ~= nil then
		Q.VectorCopy(ent.s.pos.trBase, snapped)
	else
		Q.VectorCopy(ent.activator.s.pos.trBase, snapped)
	end
	Q.SnapVector(snapped) -- save network bandwidth
	G.G_SetOrigin(explosion, snapped)

	explosion.classname = "kamikaze"
	explosion.s.pos.trType = C.TR_STATIONARY

	explosion.kamikazeTime = G.level.time

	explosion.think = KamikazeDamage
	explosion.nextthink = G.level.time + 100
	explosion.count = 0
	Q.VectorClear(explosion.movedir)

	G.trap_LinkEntity(explosion)

	if ent.client ~= nil then
		--
		explosion.activator = ent
		--
		ent.s.eFlags = bit32.band(ent.s.eFlags, bit32.bnot(C.EF_KAMIKAZE))
		-- nuke the guy that used it
		G.G_Damage(ent, ent, ent, nil, nil, 100000, C.DAMAGE_NO_PROTECTION, C.MOD_KAMIKAZE)
	else
		if ent.activator.classname == "bodyque" then
			explosion.activator = G.g_entities[ent.activator.r.ownerNum]
		else
			explosion.activator = ent.activator
		end
	end

	-- play global sound at all clients
	local te = G.G_TempEntity(snapped, C.EV_GLOBAL_TEAM_SOUND)
	te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_BROADCAST)
	te.s.eventParm = C.GTS_KAMIKAZE
end

return nil
