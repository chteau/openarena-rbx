--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_missile.c).

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
-- Luau port of g_missile.c. Missile entities: impact, bounce, explosion, proximity mines and fire_* spawners.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local MISSILE_PRESTEP_TIME = 50
local NAILGUN_SPREAD = 500

--[[
================
G_BounceMissile
================
]]
function G.G_BounceMissile(ent, trace)
	local velocity = Q.vec3()

	-- reflect the velocity on the trace plane
	local hitTime = Q.trunc(G.level.previousTime + (G.level.time - G.level.previousTime) * trace.fraction)
	BG.BG_EvaluateTrajectoryDelta(ent.s.pos, hitTime, velocity)
	local dot = Q.DotProduct(velocity, trace.plane.normal)
	Q.VectorMA(velocity, -2 * dot, trace.plane.normal, ent.s.pos.trDelta)

	if bit32.band(ent.s.eFlags, C.EF_BOUNCE_HALF) ~= 0 then
		Q.VectorScale(ent.s.pos.trDelta, 0.65, ent.s.pos.trDelta)
		-- check for stop
		if trace.plane.normal[2] > 0.2 and Q.VectorLength(ent.s.pos.trDelta) < 40 then
			G.G_SetOrigin(ent, trace.endpos)
			ent.s.time = Q.idiv(G.level.time, 4)
			return
		end
	end

	Q.VectorAdd(ent.r.currentOrigin, trace.plane.normal, ent.r.currentOrigin)
	Q.VectorCopy(ent.r.currentOrigin, ent.s.pos.trBase)
	ent.s.pos.trTime = G.level.time
end

--[[
================
G_ExplodeMissile

Explode a missile without an impact
================
]]
function G.G_ExplodeMissile(ent)
	local dir = Q.vec3()
	local origin = Q.vec3()

	BG.BG_EvaluateTrajectory(ent.s.pos, G.level.time, origin)
	Q.SnapVector(origin)
	G.G_SetOrigin(ent, origin)

	-- we don't have a valid direction, so just point straight up
	dir[0] = 0
	dir[1] = 0
	dir[2] = 1

	ent.s.eType = C.ET_GENERAL
	G.G_AddEvent(ent, C.EV_MISSILE_MISS, Q.DirToByte(dir))

	ent.freeAfterEvent = true

	-- splash damage
	if ent.splashDamage ~= 0 then
		if G.G_RadiusDamage(ent.r.currentOrigin, ent.parent, ent.splashDamage, ent.splashRadius, ent, ent.splashMethodOfDeath) then
			local cl = G.g_entities[ent.r.ownerNum].client
			cl.accuracy_hits = cl.accuracy_hits + 1
			cl.accuracy[ent.s.weapon][1] = cl.accuracy[ent.s.weapon][1] + 1
		end
	end

	G.trap_LinkEntity(ent)
end

--[[
================
ProximityMine_Explode
================
]]
local function ProximityMine_Explode(mine)
	G.G_ExplodeMissile(mine)
	-- if the prox mine has a trigger free it
	if mine.activator ~= nil then
		G.G_FreeEntity(mine.activator)
		mine.activator = nil
	end
end

--[[
================
ProximityMine_Die
================
]]
local function ProximityMine_Die(ent, inflictor, attacker, damage, mod)
	ent.think = ProximityMine_Explode
	ent.nextthink = G.level.time + 1
end

--[[
================
ProximityMine_Trigger
================
]]
function G.ProximityMine_Trigger(trigger, other, trace)
	local v = Q.vec3()

	if other.client == nil then
		return
	end

	-- trigger is a cube, do a distance test now to act as if it's a sphere
	Q.VectorSubtract(trigger.s.pos.trBase, other.s.pos.trBase, v)
	if Q.VectorLength(v) > trigger.parent.splashRadius then
		return
	end

	if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt ~= 1 then
		-- don't trigger same team mines
		if trigger.parent.s.generic1 == other.client.sess.sessionTeam then
			return
		end
	end

	-- ok, now check for ability to damage so we don't get triggered thru walls, closed doors, etc...
	if not G.CanDamage(other, trigger.s.pos.trBase) then
		return
	end

	-- trigger the mine!
	local mine = trigger.parent
	mine.s.loopSound = 0
	G.G_AddEvent(mine, C.EV_PROXIMITY_MINE_TRIGGER, 0)
	mine.nextthink = G.level.time + 500

	G.G_FreeEntity(trigger)
end

--[[
================
ProximityMine_Activate
================
]]
local function ProximityMine_Activate(ent)
	local v1 = Q.vec3()
	local flag
	local c = nil
	local nearFlag = false

	-- find the flag
	if ent.s.generic1 == C.TEAM_RED then
		c = "team_CTF_redflag"
	elseif ent.s.generic1 == C.TEAM_BLUE then
		c = "team_CTF_blueflag"
	else
		c = nil
	end

	if G.g_gametype.integer == C.GT_TEAM or G.g_gametype.integer == C.GT_DOMINATION or G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_DOUBLE_D then
		c = nil
	end

	if G.g_gametype.integer == C.GT_OBELISK or G.g_gametype.integer == C.GT_HARVESTER then
		if ent.s.generic1 == C.TEAM_RED then
			c = "team_redobelisk"
		elseif ent.s.generic1 == C.TEAM_BLUE then
			c = "team_blueobelisk"
		else
			c = nil
		end
	end

	if c ~= nil then
		flag = nil
		while true do
			flag = G.G_Find(flag, "classname", c)
			if flag == nil then
				break
			end
			if bit32.band(flag.flags, C.FL_DROPPED_ITEM) == 0 then
				break
			end
		end

		if flag ~= nil then
			Q.VectorSubtract(ent.r.currentOrigin, flag.r.currentOrigin, v1)
			if Q.VectorLength(v1) < 500 then
				nearFlag = true
			end
		end
	end

	ent.think = ProximityMine_Explode
	if nearFlag then
		ent.nextthink = G.level.time + Q.idiv(G.g_proxMineTimeout.integer, 15)
	else
		ent.nextthink = G.level.time + G.g_proxMineTimeout.integer
	end

	ent.takedamage = true
	ent.health = 1
	ent.die = ProximityMine_Die

	ent.s.loopSound = G.G_SoundIndex("sound/weapons/proxmine/wstbtick.wav")

	-- build the proximity trigger
	local trigger = G.G_Spawn()

	trigger.classname = "proxmine_trigger"

	local r = ent.splashRadius
	Q.VectorSet(trigger.r.mins, -r, -r, -r)
	Q.VectorSet(trigger.r.maxs, r, r, r)

	G.G_SetOrigin(trigger, ent.s.pos.trBase)

	trigger.parent = ent
	trigger.r.contents = C.CONTENTS_TRIGGER
	trigger.touch = G.ProximityMine_Trigger

	G.trap_LinkEntity(trigger)

	-- set pointer to trigger so the entity can be freed when the mine explodes
	ent.activator = trigger
end

--[[
================
ProximityMine_ExplodeOnPlayer
================
]]
local function ProximityMine_ExplodeOnPlayer(mine)
	local player = mine.enemy
	player.client.ps.eFlags = bit32.band(player.client.ps.eFlags, bit32.bnot(C.EF_TICKING))

	if player.client.invulnerabilityTime > G.level.time then
		G.G_Damage(player, mine.parent, mine.parent, Q.vec3_origin, mine.s.origin, 1000, C.DAMAGE_NO_KNOCKBACK, C.MOD_JUICED)
		player.client.invulnerabilityTime = 0
		G.G_TempEntity(player.client.ps.origin, C.EV_JUICED)
	else
		G.G_SetOrigin(mine, player.s.pos.trBase)
		-- make sure the explosion gets to the client
		mine.r.svFlags = bit32.band(mine.r.svFlags, bit32.bnot(C.SVF_NOCLIENT))
		mine.splashMethodOfDeath = C.MOD_PROXIMITY_MINE
		G.G_ExplodeMissile(mine)
	end
end

--[[
================
ProximityMine_Player
================
]]
local function ProximityMine_Player(mine, player)
	if bit32.band(mine.s.eFlags, C.EF_NODRAW) ~= 0 then
		return
	end

	G.G_AddEvent(mine, C.EV_PROXIMITY_MINE_STICK, 0)

	if bit32.band(player.s.eFlags, C.EF_TICKING) ~= 0 then
		player.activator.splashDamage = player.activator.splashDamage + mine.splashDamage
		player.activator.splashRadius = Q.trunc(player.activator.splashRadius * 1.50)
		mine.think = G.G_FreeEntity
		mine.nextthink = G.level.time
		return
	end

	player.client.ps.eFlags = bit32.bor(player.client.ps.eFlags, C.EF_TICKING)
	player.activator = mine

	mine.s.eFlags = bit32.bor(mine.s.eFlags, C.EF_NODRAW)
	mine.r.svFlags = bit32.bor(mine.r.svFlags, C.SVF_NOCLIENT)
	mine.s.pos.trType = C.TR_LINEAR
	Q.VectorClear(mine.s.pos.trDelta)

	mine.enemy = player
	mine.think = ProximityMine_ExplodeOnPlayer
	if player.client.invulnerabilityTime > G.level.time then
		mine.nextthink = G.level.time + 2 * 1000
	else
		mine.nextthink = G.level.time + 10 * 1000
	end
end

--[[
 *=================
 *ProximityMine_RemoveAll
 *=================
 ]]
function G.ProximityMine_RemoveAll()
	local mine = nil

	while true do
		mine = G.G_Find(mine, "classname", "prox mine")
		if mine == nil then
			break
		end
		mine.think = ProximityMine_Explode
		mine.nextthink = G.level.time + 1
	end
end

--[[
================
G_MissileImpact
================
]]
function G.G_MissileImpact(ent, trace)
	local hitClient = false
	local forward = Q.vec3()
	local impactpoint = Q.vec3()
	local bouncedir = Q.vec3()
	local other = G.g_entities[trace.entityNum]

	-- check for bounce
	if not other.takedamage and bit32.band(ent.s.eFlags, bit32.bor(C.EF_BOUNCE, C.EF_BOUNCE_HALF)) ~= 0 then
		G.G_BounceMissile(ent, trace)
		G.G_AddEvent(ent, C.EV_GRENADE_BOUNCE, 0)
		return
	end

	if other.takedamage then
		if ent.s.weapon ~= C.WP_PROX_LAUNCHER then
			if other.client ~= nil and other.client.invulnerabilityTime > G.level.time then
				Q.VectorCopy(ent.s.pos.trDelta, forward)
				Q.VectorNormalize(forward)
				if G.G_InvulnerabilityEffect(other, forward, ent.s.pos.trBase, impactpoint, bouncedir) then
					Q.VectorCopy(bouncedir, trace.plane.normal)
					local eFlags = bit32.band(ent.s.eFlags, C.EF_BOUNCE_HALF)
					ent.s.eFlags = bit32.band(ent.s.eFlags, bit32.bnot(C.EF_BOUNCE_HALF))
					G.G_BounceMissile(ent, trace)
					ent.s.eFlags = bit32.bor(ent.s.eFlags, eFlags)
				end
				ent.target_ent = other
				return
			end
		end
	end
	-- impact damage
	if other.takedamage then
		-- FIXME: wrong damage direction?
		if ent.damage ~= 0 then
			local velocity = Q.vec3()

			if G.LogAccuracyHit(other, G.g_entities[ent.r.ownerNum]) then
				local cl = G.g_entities[ent.r.ownerNum].client
				cl.accuracy_hits = cl.accuracy_hits + 1
				hitClient = true
				cl.accuracy[ent.s.weapon][1] = cl.accuracy[ent.s.weapon][1] + 1
			end
			BG.BG_EvaluateTrajectoryDelta(ent.s.pos, G.level.time, velocity)
			if Q.VectorLength(velocity) == 0 then
				velocity[2] = 1 -- stepped on a grenade
			end
			G.G_Damage(other, ent, G.g_entities[ent.r.ownerNum], velocity,
				ent.s.origin, ent.damage,
				0, ent.methodOfDeath)
		end
	end

	if ent.s.weapon == C.WP_PROX_LAUNCHER then
		if ent.s.pos.trType ~= C.TR_GRAVITY then
			return
		end

		-- if it's a player, stick it on to them (flag them and remove this entity)
		if other.s.eType == C.ET_PLAYER and other.health > 0 then
			ProximityMine_Player(ent, other)
			return
		end

		G.SnapVectorTowards(trace.endpos, ent.s.pos.trBase)
		G.G_SetOrigin(ent, trace.endpos)
		ent.s.pos.trType = C.TR_STATIONARY
		Q.VectorClear(ent.s.pos.trDelta)

		G.G_AddEvent(ent, C.EV_PROXIMITY_MINE_STICK, trace.surfaceFlags)

		ent.think = ProximityMine_Activate
		ent.nextthink = G.level.time + 2000

		Q.vectoangles(trace.plane.normal, ent.s.angles)
		ent.s.angles[0] = Q.f(ent.s.angles[0] + 90)

		-- link the prox mine to the other entity
		ent.enemy = other
		ent.die = ProximityMine_Die
		Q.VectorCopy(trace.plane.normal, ent.movedir)
		Q.VectorSet(ent.r.mins, -4, -4, -4)
		Q.VectorSet(ent.r.maxs, 4, 4, 4)
		G.trap_LinkEntity(ent)

		return
	end

	if ent.classname == "hook" then
		local v = Q.vec3()

		local nent = G.G_Spawn()
		if other.takedamage and other.client ~= nil then
			G.G_AddEvent(nent, C.EV_MISSILE_HIT, Q.DirToByte(trace.plane.normal))
			nent.s.otherEntityNum = other.s.number

			ent.enemy = other

			v[0] = other.r.currentOrigin[0] + (other.r.mins[0] + other.r.maxs[0]) * 0.5
			v[1] = other.r.currentOrigin[1] + (other.r.mins[1] + other.r.maxs[1]) * 0.5
			v[2] = other.r.currentOrigin[2] + (other.r.mins[2] + other.r.maxs[2]) * 0.5

			G.SnapVectorTowards(v, ent.s.pos.trBase) -- save net bandwidth
		else
			Q.VectorCopy(trace.endpos, v)
			G.G_AddEvent(nent, C.EV_MISSILE_MISS, Q.DirToByte(trace.plane.normal))
			ent.enemy = nil
		end

		G.SnapVectorTowards(v, ent.s.pos.trBase) -- save net bandwidth

		nent.freeAfterEvent = true
		-- change over to a normal entity right at the point of impact
		nent.s.eType = C.ET_GENERAL
		ent.s.eType = C.ET_GRAPPLE

		G.G_SetOrigin(ent, v)
		G.G_SetOrigin(nent, v)

		ent.think = G.Weapon_HookThink
		ent.nextthink = G.level.time + C.FRAMETIME

		ent.parent.client.ps.pm_flags = bit32.bor(ent.parent.client.ps.pm_flags, C.PMF_GRAPPLE_PULL)
		Q.VectorCopy(ent.r.currentOrigin, ent.parent.client.ps.grapplePoint)

		G.trap_LinkEntity(ent)
		G.trap_LinkEntity(nent)

		return
	end

	-- is it cheaper in bandwidth to just remove this ent and create a new
	-- one, rather than changing the missile into the explosion?

	if other.takedamage and other.client ~= nil then
		G.G_AddEvent(ent, C.EV_MISSILE_HIT, Q.DirToByte(trace.plane.normal))
		ent.s.otherEntityNum = other.s.number
	elseif bit32.band(trace.surfaceFlags, C.SURF_METALSTEPS) ~= 0 then
		G.G_AddEvent(ent, C.EV_MISSILE_MISS_METAL, Q.DirToByte(trace.plane.normal))
	else
		G.G_AddEvent(ent, C.EV_MISSILE_MISS, Q.DirToByte(trace.plane.normal))
	end

	ent.freeAfterEvent = true

	-- change over to a normal entity right at the point of impact
	ent.s.eType = C.ET_GENERAL

	G.SnapVectorTowards(trace.endpos, ent.s.pos.trBase) -- save net bandwidth

	G.G_SetOrigin(ent, trace.endpos)

	-- splash damage (doesn't apply to person directly hit)
	if ent.splashDamage ~= 0 then
		if G.G_RadiusDamage(trace.endpos, ent.parent, ent.splashDamage, ent.splashRadius,
			other, ent.splashMethodOfDeath) then
			if not hitClient then
				local cl = G.g_entities[ent.r.ownerNum].client
				cl.accuracy_hits = cl.accuracy_hits + 1
				cl.accuracy[ent.s.weapon][1] = cl.accuracy[ent.s.weapon][1] + 1
			end
		end
	end

	G.trap_LinkEntity(ent)
end

--[[
================
G_RunMissile
================
]]
function G.G_RunMissile(ent)
	local origin = Q.vec3()
	local tr = S.trace_t()
	local passent

	-- get current position
	BG.BG_EvaluateTrajectory(ent.s.pos, G.level.time, origin)

	-- if this missile bounced off an invulnerability sphere
	if ent.target_ent ~= nil then
		passent = ent.target_ent.s.number
	-- prox mines that left the owner bbox will attach to anything, even the owner
	elseif ent.s.weapon == C.WP_PROX_LAUNCHER and ent.count ~= 0 then
		passent = C.ENTITYNUM_NONE
	else
		-- ignore interactions with the missile owner
		passent = ent.r.ownerNum
	end
	-- trace a line from the previous position to the current position
	G.trap_Trace(tr, ent.r.currentOrigin, ent.r.mins, ent.r.maxs, origin, passent, ent.clipmask)

	if tr.startsolid or tr.allsolid then
		-- make sure the tr.entityNum is set to the entity we're stuck in
		G.trap_Trace(tr, ent.r.currentOrigin, ent.r.mins, ent.r.maxs, ent.r.currentOrigin, passent, ent.clipmask)
		tr.fraction = 0
	else
		Q.VectorCopy(tr.endpos, ent.r.currentOrigin)
	end

	G.trap_LinkEntity(ent)

	if tr.fraction ~= 1 then
		-- never explode or bounce on sky
		if bit32.band(tr.surfaceFlags, C.SURF_NOIMPACT) ~= 0 then
			-- If grapple, reset owner
			if ent.parent ~= nil and ent.parent.client ~= nil and ent.parent.client.hook == ent then
				ent.parent.client.hook = nil
			end
			G.G_FreeEntity(ent)
			return
		end
		G.G_MissileImpact(ent, tr)
		if ent.s.eType ~= C.ET_MISSILE then
			return -- exploded
		end
	end
	-- if the prox mine wasn't yet outside the player body
	if ent.s.weapon == C.WP_PROX_LAUNCHER and ent.count == 0 then
		-- check if the prox mine is outside the owner bbox
		G.trap_Trace(tr, ent.r.currentOrigin, ent.r.mins, ent.r.maxs, ent.r.currentOrigin, C.ENTITYNUM_NONE, ent.clipmask)
		if not tr.startsolid or tr.entityNum ~= ent.r.ownerNum then
			ent.count = 1
		end
	end
	-- check think function after bouncing
	G.G_RunThink(ent)
end

--=============================================================================

--[[
=================
fire_plasma

=================
]]
function G.fire_plasma(self, start, dir)
	Q.VectorNormalize(dir)

	local bolt = G.G_Spawn()
	bolt.classname = "plasma"
	bolt.nextthink = G.level.time + 10000
	bolt.think = G.G_ExplodeMissile
	bolt.s.eType = C.ET_MISSILE
	bolt.r.svFlags = C.SVF_USE_CURRENT_ORIGIN
	bolt.s.weapon = C.WP_PLASMAGUN
	bolt.r.ownerNum = self.s.number
	--unlagged - projectile nudge
	-- we'll need this for nudging projectiles later
	bolt.s.otherEntityNum = self.s.number
	--unlagged - projectile nudge
	bolt.parent = self
	bolt.damage = 20
	bolt.splashDamage = 15
	bolt.splashRadius = 20
	bolt.methodOfDeath = C.MOD_PLASMA
	bolt.splashMethodOfDeath = C.MOD_PLASMA_SPLASH
	bolt.clipmask = C.MASK_SHOT
	bolt.target_ent = nil

	bolt.s.pos.trType = C.TR_LINEAR
	bolt.s.pos.trTime = G.level.time - MISSILE_PRESTEP_TIME -- move a bit on the very first frame
	Q.VectorCopy(start, bolt.s.pos.trBase)
	Q.VectorScale(dir, 2000, bolt.s.pos.trDelta)
	Q.SnapVector(bolt.s.pos.trDelta) -- save net bandwidth

	Q.VectorCopy(start, bolt.r.currentOrigin)

	return bolt
end

--=============================================================================

--[[
=================
fire_grenade
=================
]]
function G.fire_grenade(self, start, dir)
	Q.VectorNormalize(dir)

	local bolt = G.G_Spawn()
	bolt.classname = "grenade"
	bolt.nextthink = G.level.time + 2500
	bolt.think = G.G_ExplodeMissile
	bolt.s.eType = C.ET_MISSILE
	bolt.r.svFlags = C.SVF_USE_CURRENT_ORIGIN
	bolt.s.weapon = C.WP_GRENADE_LAUNCHER
	bolt.s.eFlags = C.EF_BOUNCE_HALF
	bolt.r.ownerNum = self.s.number
	--unlagged - projectile nudge
	-- we'll need this for nudging projectiles later
	bolt.s.otherEntityNum = self.s.number
	--unlagged - projectile nudge
	bolt.parent = self
	bolt.damage = 100
	bolt.splashDamage = 100
	bolt.splashRadius = 150
	bolt.methodOfDeath = C.MOD_GRENADE
	bolt.splashMethodOfDeath = C.MOD_GRENADE_SPLASH
	bolt.clipmask = C.MASK_SHOT
	bolt.target_ent = nil

	bolt.s.pos.trType = C.TR_GRAVITY
	bolt.s.pos.trTime = G.level.time - MISSILE_PRESTEP_TIME -- move a bit on the very first frame
	Q.VectorCopy(start, bolt.s.pos.trBase)
	Q.VectorScale(dir, 700, bolt.s.pos.trDelta)
	Q.SnapVector(bolt.s.pos.trDelta) -- save net bandwidth

	Q.VectorCopy(start, bolt.r.currentOrigin)

	return bolt
end

--=============================================================================

--[[
=================
fire_bfg
=================
]]
function G.fire_bfg(self, start, dir)
	Q.VectorNormalize(dir)

	local bolt = G.G_Spawn()
	bolt.classname = "bfg"
	bolt.nextthink = G.level.time + 10000
	bolt.think = G.G_ExplodeMissile
	bolt.s.eType = C.ET_MISSILE
	bolt.r.svFlags = C.SVF_USE_CURRENT_ORIGIN
	bolt.s.weapon = C.WP_BFG
	bolt.r.ownerNum = self.s.number
	--unlagged - projectile nudge
	-- we'll need this for nudging projectiles later
	bolt.s.otherEntityNum = self.s.number
	--unlagged - projectile nudge
	bolt.parent = self
	bolt.damage = 100
	bolt.splashDamage = 100
	bolt.splashRadius = 120
	bolt.methodOfDeath = C.MOD_BFG
	bolt.splashMethodOfDeath = C.MOD_BFG_SPLASH
	bolt.clipmask = C.MASK_SHOT
	bolt.target_ent = nil

	bolt.s.pos.trType = C.TR_LINEAR
	bolt.s.pos.trTime = G.level.time - MISSILE_PRESTEP_TIME -- move a bit on the very first frame
	Q.VectorCopy(start, bolt.s.pos.trBase)
	Q.VectorScale(dir, 2000, bolt.s.pos.trDelta)
	Q.SnapVector(bolt.s.pos.trDelta) -- save net bandwidth
	Q.VectorCopy(start, bolt.r.currentOrigin)

	return bolt
end

--=============================================================================

--[[
=================
fire_rocket
=================
]]
function G.fire_rocket(self, start, dir)
	Q.VectorNormalize(dir)

	local bolt = G.G_Spawn()
	bolt.classname = "rocket"
	bolt.nextthink = G.level.time + 15000
	bolt.think = G.G_ExplodeMissile
	bolt.s.eType = C.ET_MISSILE
	bolt.r.svFlags = C.SVF_USE_CURRENT_ORIGIN
	bolt.s.weapon = C.WP_ROCKET_LAUNCHER
	bolt.r.ownerNum = self.s.number
	--unlagged - projectile nudge
	-- we'll need this for nudging projectiles later
	bolt.s.otherEntityNum = self.s.number
	--unlagged - projectile nudge
	bolt.parent = self
	bolt.damage = 100
	bolt.splashDamage = 100
	bolt.splashRadius = 120
	bolt.methodOfDeath = C.MOD_ROCKET
	bolt.splashMethodOfDeath = C.MOD_ROCKET_SPLASH
	bolt.clipmask = C.MASK_SHOT
	bolt.target_ent = nil

	bolt.s.pos.trType = C.TR_LINEAR
	bolt.s.pos.trTime = G.level.time - MISSILE_PRESTEP_TIME -- move a bit on the very first frame
	Q.VectorCopy(start, bolt.s.pos.trBase)
	Q.VectorScale(dir, 900, bolt.s.pos.trDelta)
	Q.SnapVector(bolt.s.pos.trDelta) -- save net bandwidth
	Q.VectorCopy(start, bolt.r.currentOrigin)

	return bolt
end

--[[
=================
fire_grapple
=================
]]
function G.fire_grapple(self, start, dir)
	local hooktime

	Q.VectorNormalize(dir)

	local hook = G.G_Spawn()
	hook.classname = "hook"
	hook.nextthink = G.level.time + 10000
	hook.think = G.Weapon_HookFree
	hook.s.eType = C.ET_MISSILE
	hook.r.svFlags = C.SVF_USE_CURRENT_ORIGIN
	hook.s.weapon = C.WP_GRAPPLING_HOOK
	hook.r.ownerNum = self.s.number
	hook.methodOfDeath = C.MOD_GRAPPLE
	hook.clipmask = C.MASK_SHOT
	hook.parent = self
	hook.target_ent = nil

	--unlagged - grapple
	-- we might want this later
	hook.s.otherEntityNum = self.s.number

	-- setting the projectile base time back makes the hook's first
	-- step larger

	if self.client ~= nil then
		hooktime = self.client.pers.cmd.serverTime + 50
	else
		hooktime = G.level.time - MISSILE_PRESTEP_TIME
	end

	hook.s.pos.trTime = hooktime
	--unlagged - grapple

	hook.s.pos.trType = C.TR_LINEAR
	hook.s.otherEntityNum = self.s.number -- use to match beam in client
	Q.VectorCopy(start, hook.s.pos.trBase)
	Q.VectorScale(dir, 800, hook.s.pos.trDelta)
	Q.SnapVector(hook.s.pos.trDelta) -- save net bandwidth
	Q.VectorCopy(start, hook.r.currentOrigin)

	if self.client ~= nil then
		self.client.hook = hook
	end

	return hook
end

--[[
=================
fire_nail
=================
]]
function G.fire_nail(self, start, forward, right, up)
	local dir = Q.vec3()
	local end_ = Q.vec3()

	local bolt = G.G_Spawn()
	bolt.classname = "nail"
	bolt.nextthink = G.level.time + 10000
	bolt.think = G.G_ExplodeMissile
	bolt.s.eType = C.ET_MISSILE
	bolt.r.svFlags = C.SVF_USE_CURRENT_ORIGIN
	bolt.s.weapon = C.WP_NAILGUN
	bolt.r.ownerNum = self.s.number
	--unlagged - projectile nudge
	-- we'll need this for nudging projectiles later
	bolt.s.otherEntityNum = self.s.number
	--unlagged - projectile nudge
	bolt.parent = self
	bolt.damage = 20
	bolt.methodOfDeath = C.MOD_NAIL
	bolt.clipmask = C.MASK_SHOT
	bolt.target_ent = nil

	bolt.s.pos.trType = C.TR_LINEAR
	bolt.s.pos.trTime = G.level.time
	Q.VectorCopy(start, bolt.s.pos.trBase)

	local r = Q.random() * math.pi * 2.0
	local u = math.sin(r) * Q.crandom() * NAILGUN_SPREAD * 16
	r = math.cos(r) * Q.crandom() * NAILGUN_SPREAD * 16
	Q.VectorMA(start, 8192 * 16, forward, end_)
	Q.VectorMA(end_, r, right, end_)
	Q.VectorMA(end_, u, up, end_)
	Q.VectorSubtract(end_, start, dir)
	Q.VectorNormalize(dir)

	local scale = 555 + Q.random() * 1800
	Q.VectorScale(dir, scale, bolt.s.pos.trDelta)
	Q.SnapVector(bolt.s.pos.trDelta)

	Q.VectorCopy(start, bolt.r.currentOrigin)

	return bolt
end

--[[
=================
fire_prox
=================
]]
function G.fire_prox(self, start, dir)
	Q.VectorNormalize(dir)

	local bolt = G.G_Spawn()
	bolt.classname = "prox mine"
	bolt.nextthink = G.level.time + 3000
	bolt.think = G.G_ExplodeMissile
	bolt.s.eType = C.ET_MISSILE
	bolt.r.svFlags = C.SVF_USE_CURRENT_ORIGIN
	bolt.s.weapon = C.WP_PROX_LAUNCHER
	bolt.s.eFlags = 0
	bolt.r.ownerNum = self.s.number
	--unlagged - projectile nudge
	-- we'll need this for nudging projectiles later
	bolt.s.otherEntityNum = self.s.number
	--unlagged - projectile nudge
	bolt.parent = self
	bolt.damage = 0
	bolt.splashDamage = 100
	bolt.splashRadius = 150
	bolt.methodOfDeath = C.MOD_PROXIMITY_MINE
	bolt.splashMethodOfDeath = C.MOD_PROXIMITY_MINE
	bolt.clipmask = C.MASK_SHOT
	bolt.target_ent = nil
	-- count is used to check if the prox mine left the player bbox
	-- if count == 1 then the prox mine left the player bbox and can attack to it
	bolt.count = 0

	--FIXME: we prolly wanna abuse another field
	bolt.s.generic1 = self.client.sess.sessionTeam

	bolt.s.pos.trType = C.TR_GRAVITY
	bolt.s.pos.trTime = G.level.time - MISSILE_PRESTEP_TIME -- move a bit on the very first frame
	Q.VectorCopy(start, bolt.s.pos.trBase)
	Q.VectorScale(dir, 700, bolt.s.pos.trDelta)
	Q.SnapVector(bolt.s.pos.trDelta) -- save net bandwidth

	Q.VectorCopy(start, bolt.r.currentOrigin)

	return bolt
end

return nil
