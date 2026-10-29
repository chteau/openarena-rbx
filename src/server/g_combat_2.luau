--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_combat.c).

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
-- Luau port of g_combat.c, part 2 of 2 (armor, invulnerability, G_Damage, radius damage, monster_die).

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_combat")

function G.CheckArmor(ent, damage, dflags)
	if damage == 0 then
		return 0
	end

	local client = ent.client

	if client == nil then
		return 0
	end

	if bit32.band(dflags, C.DAMAGE_NO_ARMOR) ~= 0 then
		return 0
	end

	-- armor
	local count = client.ps.stats[C.STAT_ARMOR]
	local save = math.ceil(damage * C.ARMOR_PROTECTION)
	if save >= count then
		save = count
	end

	if save == 0 then
		return 0
	end

	client.ps.stats[C.STAT_ARMOR] -= save

	return save
end

function G.RaySphereIntersections(origin, radius, point, dir, intersections)
	-- normalize dir so a = 1
	Q.VectorNormalize(dir)
	local b = 2 * (dir[0] * (point[0] - origin[0]) + dir[1] * (point[1] - origin[1]) + dir[2] * (point[2] - origin[2]))
	local c = (point[0] - origin[0]) * (point[0] - origin[0])
		+ (point[1] - origin[1]) * (point[1] - origin[1])
		+ (point[2] - origin[2]) * (point[2] - origin[2])
		- radius * radius

	local d = b * b - 4 * c
	if d > 0 then
		local t = (-b + math.sqrt(d)) / 2
		Q.VectorMA(point, t, dir, intersections[0])
		t = (-b - math.sqrt(d)) / 2
		Q.VectorMA(point, t, dir, intersections[1])
		return 2
	elseif d == 0 then
		local t = (-b) / 2
		Q.VectorMA(point, t, dir, intersections[0])
		return 1
	end
	return 0
end

function G.G_InvulnerabilityEffect(targ, dir, point, impactpoint, bouncedir)
	local intersections = { [0] = Q.vec3(), [1] = Q.vec3() }
	local vec = Q.vec3()

	if targ.client == nil then
		return false
	end
	Q.VectorCopy(dir, vec)
	vec[0] = -vec[0]
	vec[1] = -vec[1]
	vec[2] = -vec[2]
	-- sphere model radius = 42 units
	local n = G.RaySphereIntersections(targ.client.ps.origin, 42, point, vec, intersections)
	if n > 0 then
		local impact = G.G_TempEntity(targ.client.ps.origin, C.EV_INVUL_IMPACT)
		Q.VectorSubtract(intersections[0], targ.client.ps.origin, vec)
		Q.vectoangles(vec, impact.s.angles)
		impact.s.angles[0] = Q.f(impact.s.angles[0] + 90)
		if impact.s.angles[0] > 360 then
			impact.s.angles[0] = Q.f(impact.s.angles[0] - 360)
		end
		if impactpoint ~= nil then
			Q.VectorCopy(intersections[0], impactpoint)
		end
		if bouncedir ~= nil then
			Q.VectorCopy(vec, bouncedir)
			Q.VectorNormalize(bouncedir)
		end
		return true
	else
		return false
	end
end

function SF.catchup_damage(damage, attacker_points, target_points)
	if G.g_catchup.integer <= 0 then
		return damage
	end
	-- Reduce damage
	if attacker_points <= target_points + 5 then
		return damage -- Never reduce damage if only 5 points ahead.
	end

	local newdamage = damage - Q.idiv((attacker_points - target_points - 5) * (G.g_catchup.integer * damage), 100)
	if newdamage < Q.idiv(damage, 2) then
		return Q.idiv(damage, 2)
	end
	return newdamage
end

function G.G_Damage(targ, inflictor, attacker, dir, point, damage, dflags, mod)
	local bouncedir = Q.vec3()
	local impactpoint = Q.vec3()

	if targ == nil then
		return
	end

	if not targ.takedamage then
		return
	end

	-- the intermission has already been qualified for, so don't
	-- allow any extra scoring
	if G.level.intermissionQueued ~= 0 then
		return
	end
	if targ.client ~= nil and mod ~= C.MOD_JUICED then
		if targ.client.invulnerabilityTime > G.level.time then
			if dir ~= nil and point ~= nil then
				G.G_InvulnerabilityEffect(targ, dir, point, impactpoint, bouncedir)
			end
			return
		end
	end
	local client = targ.client

	if inflictor == nil then
		inflictor = G.g_entities[C.ENTITYNUM_WORLD]
	end
	if attacker == nil then
		attacker = G.g_entities[C.ENTITYNUM_WORLD]
	end

	if
		(attacker == G.g_entities[C.ENTITYNUM_WORLD] or attacker == targ or attacker.s.eType ~= C.ET_PLAYER)
		and client ~= nil
		and client.lastSentFlying > -1
		and (mod == C.MOD_FALLING or mod == C.MOD_LAVA or mod == C.MOD_SLIME or mod == C.MOD_TRIGGER_HURT or mod == C.MOD_SUICIDE)
	then
		if client.lastSentFlyingTime + 5000 < G.level.time then
			-- More than 5 seconds, not a kill!
			client.lastSentFlying = -1
		else
			attacker = G.g_entities[client.lastSentFlying]
		end
	end

	-- shootable doors / buttons don't actually have any health
	if targ.s.eType == C.ET_MOVER then
		if targ.use ~= nil and targ.moverState == C.MOVER_POS1 then
			targ.use(targ, inflictor, attacker)
		end
		return
	end
	if G.g_gametype.integer == C.GT_OBELISK and G.CheckObeliskAttack(targ, attacker) then
		return
	end
	-- reduce damage by the attacker's handicap value
	-- unless they are rocket jumping
	if attacker.client ~= nil and attacker ~= targ then
		local max = attacker.client.ps.stats[C.STAT_MAX_HEALTH]
		if BG.bg_itemlist[attacker.client.ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_GUARD then
			max = Q.idiv(max, 2)
		end
		damage = Q.idiv(damage * max, 100)
	end

	if client ~= nil then
		if client.noclip then
			return
		end
	end

	if dir == nil then
		dflags = bit32.bor(dflags, C.DAMAGE_NO_KNOCKBACK)
	else
		Q.VectorNormalize(dir)
	end

	local knockback = damage
	if knockback > 200 then
		knockback = 200
	end
	if bit32.band(targ.flags, C.FL_NO_KNOCKBACK) ~= 0 then
		knockback = 0
	end
	if bit32.band(dflags, C.DAMAGE_NO_KNOCKBACK) ~= 0 then
		knockback = 0
	end

	-- figure momentum add, even if the damage won't be taken
	if knockback ~= 0 and targ.client ~= nil then
		local kvel = Q.vec3()
		local mass = 200

		Q.VectorScale(dir, G.g_knockback.value * knockback / mass, kvel)
		Q.VectorAdd(targ.client.ps.velocity, kvel, targ.client.ps.velocity)

		-- set the timer so that the other client can't cancel
		-- out the movement immediately
		if targ.client.ps.pm_time == 0 then
			local t = knockback * 2
			if t < 50 then
				t = 50
			end
			if t > 200 then
				t = 200
			end
			targ.client.ps.pm_time = t
			targ.client.ps.pm_flags = bit32.bor(targ.client.ps.pm_flags, C.PMF_TIME_KNOCKBACK)
		end
		-- Remeber the last person to hurt the player
		if G.g_awardpushing.integer == 0 or targ == attacker or G.OnSameTeam(targ, attacker) then
			targ.client.lastSentFlying = -1
		else
			targ.client.lastSentFlying = attacker.s.number
			targ.client.lastSentFlyingTime = G.level.time
		end
	end

	-- check for completely getting out of the damage
	if bit32.band(dflags, C.DAMAGE_NO_PROTECTION) == 0 then
		-- if TF_NO_FRIENDLY_FIRE is set, don't do damage to the target
		-- if the attacker was on the same team
		if
			mod ~= C.MOD_JUICED
			and mod ~= C.MOD_CRUSH
			and targ ~= attacker
			and bit32.band(dflags, C.DAMAGE_NO_TEAM_PROTECTION) == 0
			and G.OnSameTeam(targ, attacker)
		then
			if
				(G.g_friendlyFire.integer == 0 and G.g_gametype.integer ~= C.GT_ELIMINATION and G.g_gametype.integer ~= C.GT_CTF_ELIMINATION)
				or (G.g_elimination_selfdamage.integer < 2 and (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION))
			then
				return
			end
		end
		if mod == C.MOD_PROXIMITY_MINE then
			if inflictor ~= nil and inflictor.parent ~= nil and G.OnSameTeam(targ, inflictor.parent) then
				return
			end
			if targ == attacker then
				return
			end
		end

		-- check for godmode
		if bit32.band(targ.flags, C.FL_GODMODE) ~= 0 then
			return
		end

		if targ.client ~= nil and targ.client.spawnprotected then
			if G.level.time > targ.client.respawnTime + G.g_spawnprotect.integer then
				targ.client.spawnprotected = false
			else
				if (mod > C.MOD_UNKNOWN and mod < C.MOD_WATER) or mod == C.MOD_TELEFRAG or mod > C.MOD_TRIGGER_HURT then
					return
				end
			end
		end
	end

	-- battlesuit protects from all radius damage (but takes knockback)
	-- and protects 50% against all damage
	if client ~= nil and client.ps.powerups[C.PW_BATTLESUIT] ~= 0 then
		G.G_AddEvent(targ, C.EV_POWERUP_BATTLESUIT, 0)
		if bit32.band(dflags, C.DAMAGE_RADIUS) ~= 0 or mod == C.MOD_FALLING then
			return
		end
		damage = Q.trunc(damage * 0.5)
	end

	-- add to the attacker's hit counter (if the target isn't a general entity like a prox mine)
	if
		attacker.client ~= nil
		and client ~= nil
		and targ ~= attacker
		and targ.health > 0
		and targ.s.eType ~= C.ET_MISSILE
		and targ.s.eType ~= C.ET_GENERAL
	then
		if G.OnSameTeam(targ, attacker) then
			attacker.client.ps.persistant[C.PERS_HITS] -= 1
		else
			attacker.client.ps.persistant[C.PERS_HITS] += 1
		end
		attacker.client.ps.persistant[C.PERS_ATTACKEE_ARMOR] =
			Q.int32(bit32.bor(bit32.lshift(targ.health, 8), client.ps.stats[C.STAT_ARMOR]))
	end

	-- always give half damage if hurting self
	-- calculated after knockback, so rocket jumping works
	if targ == attacker then
		damage = Q.trunc(damage * 0.5)
	end

	if targ ~= nil and targ.client ~= nil and attacker.client ~= nil then
		damage = SF.catchup_damage(damage, attacker.client.ps.persistant[C.PERS_SCORE], targ.client.ps.persistant[C.PERS_SCORE])
	end

	if G.g_damageModifier.value > 0.01 then
		damage = Q.trunc(damage * G.g_damageModifier.value)
	end

	if damage < 1 then
		damage = 1
	end

	if targ == attacker and bit32.band(G.g_dmflags.integer, C.DF_NO_SELF_DAMAGE) ~= 0 then
		damage = 0
	end

	if
		(G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION or G.g_gametype.integer == C.GT_LMS or G.g_elimination_allgametypes.integer ~= 0)
		and G.g_elimination_selfdamage.integer < 1
		and (targ == attacker or mod == C.MOD_FALLING)
	then
		damage = 0
	end

	-- So people can be telefragged!
	if
		(G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION or G.g_gametype.integer == C.GT_LMS)
		and G.level.time < G.level.roundStartTime
		and (mod == C.MOD_LAVA or mod == C.MOD_SLIME)
	then
		damage = 1000
	end

	local take = damage

	-- save some from armor
	local asave = G.CheckArmor(targ, take, dflags)
	take -= asave

	if G.g_debugDamage.integer ~= 0 then
		G.G_Printf("%i: client:%i health:%i damage:%i armor:%i\n", G.level.time, targ.s.number, targ.health, take, asave)
	end

	-- add to the damage inflicted on a player this frame
	-- the total will be turned into screen blends and view angle kicks
	-- at the end of the frame
	if client ~= nil then
		if attacker ~= nil then
			client.ps.persistant[C.PERS_ATTACKER] = attacker.s.number
		elseif client.lastSentFlying > -1 then
			client.ps.persistant[C.PERS_ATTACKER] = client.lastSentFlying
		else
			client.ps.persistant[C.PERS_ATTACKER] = C.ENTITYNUM_WORLD
		end
		client.damage_armor += asave
		client.damage_blood += take
		client.damage_knockback += knockback
		if dir ~= nil then
			Q.VectorCopy(dir, client.damage_from)
			client.damage_fromWorld = false
		else
			Q.VectorCopy(targ.r.currentOrigin, client.damage_from)
			client.damage_fromWorld = true
		end
	end

	-- See if it's the player hurting the emeny flag carrier
	if G.g_gametype.integer == C.GT_CTF or G.g_gametype.integer == C.GT_1FCTF or G.g_gametype.integer == C.GT_CTF_ELIMINATION then
		G.Team_CheckHurtCarrier(targ, attacker)
	end

	if targ.client ~= nil then
		-- set the last client who damaged the target
		targ.client.lasthurt_client = attacker.s.number
		targ.client.lasthurt_mod = mod
	end

	-- If vampire is enabled, gain health but not from self or teammate, cannot steal more than targ has
	if
		G.g_vampire.value > 0.0
		and targ ~= attacker
		and take > 0
		and not G.OnSameTeam(targ, attacker)
		and attacker.health > 0
		and targ.health > 0
	then
		if take < targ.health then
			attacker.health += Q.trunc(take * G.g_vampire.value)
		else
			attacker.health += Q.trunc(targ.health * G.g_vampire.value)
		end
		if attacker.health > G.g_vampireMaxHealth.integer then
			attacker.health = G.g_vampireMaxHealth.integer
		end
	end

	-- do the damage
	if take ~= 0 then
		targ.health = targ.health - take
		if targ.client ~= nil then
			targ.client.ps.stats[C.STAT_HEALTH] = targ.health
		end

		if targ.health <= 0 then
			if client ~= nil then
				targ.flags = bit32.bor(targ.flags, C.FL_NO_KNOCKBACK)
			end

			if targ.health < -999 then
				targ.health = -999
			end

			targ.enemy = attacker
			targ.die(targ, inflictor, attacker, take, mod)
			return
		elseif targ.pain ~= nil then
			targ.pain(targ, attacker, take)
		end
	end
end

function G.CanDamage(targ, origin)
	local dest = Q.vec3()
	local tr = S.trace_t()
	local midpoint = Q.vec3()

	-- use the midpoint of the bounds instead of the origin, because
	-- bmodels may have their origin is 0,0,0
	Q.VectorAdd(targ.r.absmin, targ.r.absmax, midpoint)
	Q.VectorScale(midpoint, 0.5, midpoint)

	Q.VectorCopy(midpoint, dest)
	G.trap_Trace(tr, origin, Q.vec3_origin, Q.vec3_origin, dest, C.ENTITYNUM_NONE, C.MASK_SOLID)
	if tr.fraction == 1.0 or tr.entityNum == targ.s.number then
		return true
	end

	-- this should probably check in the plane of projection,
	-- rather than in world coordinate, and also include Z
	Q.VectorCopy(midpoint, dest)
	dest[0] += 15.0
	dest[1] += 15.0
	G.trap_Trace(tr, origin, Q.vec3_origin, Q.vec3_origin, dest, C.ENTITYNUM_NONE, C.MASK_SOLID)
	if tr.fraction == 1.0 then
		return true
	end

	Q.VectorCopy(midpoint, dest)
	dest[0] += 15.0
	dest[1] -= 15.0
	G.trap_Trace(tr, origin, Q.vec3_origin, Q.vec3_origin, dest, C.ENTITYNUM_NONE, C.MASK_SOLID)
	if tr.fraction == 1.0 then
		return true
	end

	Q.VectorCopy(midpoint, dest)
	dest[0] -= 15.0
	dest[1] += 15.0
	G.trap_Trace(tr, origin, Q.vec3_origin, Q.vec3_origin, dest, C.ENTITYNUM_NONE, C.MASK_SOLID)
	if tr.fraction == 1.0 then
		return true
	end

	Q.VectorCopy(midpoint, dest)
	dest[0] -= 15.0
	dest[1] -= 15.0
	G.trap_Trace(tr, origin, Q.vec3_origin, Q.vec3_origin, dest, C.ENTITYNUM_NONE, C.MASK_SOLID)
	if tr.fraction == 1.0 then
		return true
	end

	return false
end

function G.G_RadiusDamage(origin, attacker, damage, radius, ignore, mod)
	local entityList = {}
	local mins = Q.vec3()
	local maxs = Q.vec3()
	local v = Q.vec3()
	local dir = Q.vec3()
	local hitClient = false

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

		if ent == ignore then
			continue
		end
		if not ent.takedamage then
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

		local points = damage * (1.0 - dist / radius)

		if G.CanDamage(ent, origin) then
			if G.LogAccuracyHit(ent, attacker) then
				hitClient = true
			end
			Q.VectorSubtract(ent.r.currentOrigin, origin, dir)
			-- push the center of mass higher than the origin so players
			-- get knocked into the air more
			dir[2] += 24
			G.G_Damage(ent, nil, attacker, dir, origin, Q.trunc(points), C.DAMAGE_RADIUS, mod)
		end
	end

	return hitClient
end

-- Monster code

-- definitely mangled from player_die with less about the player
function G.monster_die(self, inflictor, attacker, damage, meansOfDeath)
	local killer = 0

	if self.client ~= nil and self.client.hook ~= nil then
		G.Weapon_HookFree(self.client.hook)
	end
	if bit32.band(self.client.ps.eFlags, C.EF_TICKING) ~= 0 and self.activator ~= nil then
		self.client.ps.eFlags = bit32.band(self.client.ps.eFlags, bit32.bnot(C.EF_TICKING))
		self.activator.think = function(e)
			G.G_FreeEntity(e)
		end
		self.activator.nextthink = G.level.time
	end
	self.enemy = attacker
	self.takedamage = true -- can still be gibbed

	self.s.weapon = C.WP_NONE
	self.s.powerups = 0
	self.r.contents = C.CONTENTS_CORPSE

	self.s.angles[0] = 0
	self.s.angles[2] = 0
	G.LookAtKiller(self, inflictor, attacker)

	Q.VectorCopy(self.s.angles, self.client.ps.viewangles)

	self.s.loopSound = 0

	self.r.maxs[2] = -8

	-- never gib in a nodrop
	local contents = G.trap_PointContents(self.r.currentOrigin, -1)

	if
		(self.health <= C.GIB_HEALTH and bit32.band(contents, C.CONTENTS_NODROP) == 0 and G.g_blood.integer ~= 0)
		or meansOfDeath == C.MOD_SUICIDE
	then
		-- gib death
		G.GibEntity(self, killer)
	else
		-- normal death

		-- for the no-blood option, we need to prevent the health
		-- from going to gib level
		if self.health <= C.GIB_HEALTH then
			self.health = C.GIB_HEALTH + 1
		end

		-- the body can still be gibbed
		self.die = function(s, i, a, d, m)
			G.body_die(s, i, a, d, m)
		end
	end

	G.trap_LinkEntity(self)
end

return nil
