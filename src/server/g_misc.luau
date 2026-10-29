--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_misc.c).

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
-- Luau port of g_misc.c. Misc entities: teleporters, portals, shooters, spawnpoint counting.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

function G.SP_info_camp(self)
	G.G_SetOrigin(self, self.s.origin)
end

function G.SP_info_null(self)
	G.G_FreeEntity(self)
end

function G.SP_info_notnull(self)
	G.G_SetOrigin(self, self.s.origin)
end

function G.SP_light(self)
	G.G_FreeEntity(self)
end

function G.TeleportPlayer(player, origin, angles)
	local tent
	local noAngles

	noAngles = (angles[0] > 999999.0)
	if player.client.sess.sessionTeam ~= C.TEAM_SPECTATOR and player.client.ps.pm_type ~= C.PM_SPECTATOR then
		tent = G.G_TempEntity(player.client.ps.origin, C.EV_PLAYER_TELEPORT_OUT)
		tent.s.clientNum = player.s.clientNum

		tent = G.G_TempEntity(origin, C.EV_PLAYER_TELEPORT_IN)
		tent.s.clientNum = player.s.clientNum
	end

	G.trap_UnlinkEntity(player)

	Q.VectorCopy(origin, player.client.ps.origin)
	player.client.ps.origin[2] = Q.f(player.client.ps.origin[2] + 1)

	if not noAngles then
		Q.AngleVectors(angles, player.client.ps.velocity, nil, nil)
		Q.VectorScale(player.client.ps.velocity, 400, player.client.ps.velocity)
		player.client.ps.pm_time = 160
		player.client.ps.pm_flags = bit32.bor(player.client.ps.pm_flags, C.PMF_TIME_KNOCKBACK)

		G.SetClientViewAngle(player, angles)
	end

	player.client.ps.eFlags = bit32.bxor(player.client.ps.eFlags, C.EF_TELEPORT_BIT)

	G.G_ResetHistory(player)

	if player.client.sess.sessionTeam ~= C.TEAM_SPECTATOR and player.client.ps.pm_type ~= C.PM_SPECTATOR then
		G.G_KillBox(player)
	end

	BG.BG_PlayerStateToEntityState(player.client.ps, player.s, true)

	Q.VectorCopy(player.client.ps.origin, player.r.currentOrigin)

	if player.client.sess.sessionTeam ~= C.TEAM_SPECTATOR and player.client.ps.pm_type ~= C.PM_SPECTATOR then
		G.trap_LinkEntity(player)
	end
end

function G.SP_misc_teleporter_dest(ent)
end

function G.SP_misc_model(ent)
	G.G_FreeEntity(ent)
end

function G.locateCamera(ent)
	local dir = Q.vec3()
	local target
	local owner

	owner = G.G_PickTarget(ent.target)
	if owner == nil then
		G.G_Printf("Couldn't find target for misc_partal_surface\n")
		G.G_FreeEntity(ent)
		return
	end
	ent.r.ownerNum = owner.s.number

	if bit32.band(owner.spawnflags, 1) ~= 0 then
		ent.s.frame = 25
	elseif bit32.band(owner.spawnflags, 2) ~= 0 then
		ent.s.frame = 75
	end

	if bit32.band(owner.spawnflags, 4) ~= 0 then
		ent.s.powerups = 0
	else
		ent.s.powerups = 1
	end

	ent.s.clientNum = owner.s.clientNum

	Q.VectorCopy(owner.s.origin, ent.s.origin2)

	target = G.G_PickTarget(owner.target)
	if target ~= nil then
		Q.VectorSubtract(target.s.origin, owner.s.origin, dir)
		Q.VectorNormalize(dir)
	else
		G.G_SetMovedir(owner.s.angles, dir)
	end

	ent.s.eventParm = Q.DirToByte(dir)
end

function G.SP_misc_portal_surface(ent)
	Q.VectorClear(ent.r.mins)
	Q.VectorClear(ent.r.maxs)
	G.trap_LinkEntity(ent)

	ent.r.svFlags = C.SVF_PORTAL
	ent.s.eType = C.ET_PORTAL

	if ent.target == nil then
		Q.VectorCopy(ent.s.origin, ent.s.origin2)
	else
		ent.think = G.locateCamera
		ent.nextthink = G.level.time + 100
	end
end

function G.SP_misc_portal_camera(ent)
	local roll

	Q.VectorClear(ent.r.mins)
	Q.VectorClear(ent.r.maxs)
	G.trap_LinkEntity(ent)

	local _
	_, roll = G.G_SpawnFloat("roll", "0")

	ent.s.clientNum = Q.trunc(roll / 360.0 * 256)
end

function G.Use_Shooter(ent, other, activator)
	local dir = Q.vec3()
	local deg
	local up, right = Q.vec3(), Q.vec3()

	if ent.enemy ~= nil then
		Q.VectorSubtract(ent.enemy.r.currentOrigin, ent.s.origin, dir)
		Q.VectorNormalize(dir)
	else
		Q.VectorCopy(ent.movedir, dir)
	end

	Q.PerpendicularVector(up, dir)
	Q.CrossProduct(up, dir, right)

	deg = Q.crandom() * ent.random
	Q.VectorMA(dir, deg, up, dir)

	deg = Q.crandom() * ent.random
	Q.VectorMA(dir, deg, right, dir)

	Q.VectorNormalize(dir)

	local weapon = ent.s.weapon
	if weapon == C.WP_GRENADE_LAUNCHER then
		G.fire_grenade(ent, ent.s.origin, dir)
	elseif weapon == C.WP_ROCKET_LAUNCHER then
		G.fire_rocket(ent, ent.s.origin, dir)
	elseif weapon == C.WP_PLASMAGUN then
		G.fire_plasma(ent, ent.s.origin, dir)
	end

	G.G_AddEvent(ent, C.EV_FIRE_WEAPON, 0)
end

local function InitShooter_Finish(ent)
	ent.enemy = G.G_PickTarget(ent.target)
	ent.think = nil
	ent.nextthink = 0
end

function G.InitShooter(ent, weapon)
	ent.use = G.Use_Shooter
	ent.s.weapon = weapon

	G.RegisterItem(BG.BG_FindItemForWeapon(weapon))

	G.G_SetMovedir(ent.s.angles, ent.movedir)

	if ent.random == 0 then
		ent.random = 1.0
	end
	ent.random = math.sin(math.pi * ent.random / 180)
	if ent.target ~= nil then
		ent.think = InitShooter_Finish
		ent.nextthink = G.level.time + 500
	end
	G.trap_LinkEntity(ent)
end

function G.SP_shooter_rocket(ent)
	G.InitShooter(ent, C.WP_ROCKET_LAUNCHER)
end

function G.SP_shooter_plasma(ent)
	G.InitShooter(ent, C.WP_PLASMAGUN)
end

function G.SP_shooter_grenade(ent)
	G.InitShooter(ent, C.WP_GRENADE_LAUNCHER)
end

local function PortalDie(self, inflictor, attacker, damage, mod)
	G.G_FreeEntity(self)
end

function G.DropPortalDestination(player)
	local ent
	local snapped = Q.vec3()

	ent = G.G_Spawn()
	ent.s.modelindex = G.G_ModelIndex("models/powerups/teleporter/tele_exit.md3")

	Q.VectorCopy(player.s.pos.trBase, snapped)
	Q.SnapVector(snapped)
	G.G_SetOrigin(ent, snapped)
	Q.VectorCopy(player.r.mins, ent.r.mins)
	Q.VectorCopy(player.r.maxs, ent.r.maxs)

	ent.classname = "hi_portal destination"
	ent.s.pos.trType = C.TR_STATIONARY

	ent.r.contents = C.CONTENTS_CORPSE
	ent.takedamage = true
	ent.health = 200
	ent.die = PortalDie

	Q.VectorCopy(player.s.apos.trBase, ent.s.angles)

	ent.think = G.G_FreeEntity
	ent.nextthink = G.level.time + 2 * 60 * 1000

	G.trap_LinkEntity(ent)

	G.level.portalSequence = G.level.portalSequence + 1
	player.client.portalID = G.level.portalSequence
	ent.count = player.client.portalID

	player.client.ps.stats[C.STAT_HOLDABLE_ITEM] = BG.BG_FindItem("Portal").index
end

local function PortalTouch(self, other, trace)
	local destination

	if other.health <= 0 then
		return
	end
	if other.client == nil then
		return
	end

	if other.client.ps.powerups[C.PW_NEUTRALFLAG] ~= 0 then
		G.Drop_Item(other, BG.BG_FindItemForPowerup(C.PW_NEUTRALFLAG), 0)
		other.client.ps.powerups[C.PW_NEUTRALFLAG] = 0
	elseif other.client.ps.powerups[C.PW_REDFLAG] ~= 0 then
		G.Drop_Item(other, BG.BG_FindItemForPowerup(C.PW_REDFLAG), 0)
		other.client.ps.powerups[C.PW_REDFLAG] = 0
	elseif other.client.ps.powerups[C.PW_BLUEFLAG] ~= 0 then
		G.Drop_Item(other, BG.BG_FindItemForPowerup(C.PW_BLUEFLAG), 0)
		other.client.ps.powerups[C.PW_BLUEFLAG] = 0
	end

	destination = nil
	while true do
		destination = G.G_Find(destination, "classname", "hi_portal destination")
		if destination == nil then
			break
		end
		if destination.count == self.count then
			break
		end
	end

	if destination == nil then
		if self.pos1[0] ~= 0 or self.pos1[1] ~= 0 or self.pos1[2] ~= 0 then
			G.TeleportPlayer(other, self.pos1, self.s.angles)
		end
		G.G_Damage(other, other, other, nil, nil, 100000, C.DAMAGE_NO_PROTECTION, C.MOD_TELEFRAG)
		return
	end

	G.TeleportPlayer(other, destination.s.pos.trBase, destination.s.angles)
end

local function PortalEnable(self)
	self.touch = PortalTouch
	self.think = G.G_FreeEntity
	self.nextthink = G.level.time + 2 * 60 * 1000
end

function G.DropPortalSource(player)
	local ent
	local destination
	local snapped = Q.vec3()

	ent = G.G_Spawn()
	ent.s.modelindex = G.G_ModelIndex("models/powerups/teleporter/tele_enter.md3")

	Q.VectorCopy(player.s.pos.trBase, snapped)
	Q.SnapVector(snapped)
	G.G_SetOrigin(ent, snapped)
	Q.VectorCopy(player.r.mins, ent.r.mins)
	Q.VectorCopy(player.r.maxs, ent.r.maxs)

	ent.classname = "hi_portal source"
	ent.s.pos.trType = C.TR_STATIONARY

	ent.r.contents = bit32.bor(C.CONTENTS_CORPSE, C.CONTENTS_TRIGGER)
	ent.takedamage = true
	ent.health = 200
	ent.die = PortalDie

	G.trap_LinkEntity(ent)

	ent.count = player.client.portalID
	player.client.portalID = 0

	ent.nextthink = G.level.time + 1000
	ent.think = PortalEnable

	destination = nil
	while true do
		destination = G.G_Find(destination, "classname", "hi_portal destination")
		if destination == nil then
			break
		end
		if destination.count == ent.count then
			Q.VectorCopy(destination.s.pos.trBase, ent.pos1)
			break
		end
	end
end

local function countItems(itemname, exclude_no_bots)
	local spot
	local count

	count = 0
	spot = nil

	while true do
		spot = G.G_Find(spot, "classname", itemname)
		if spot == nil then
			break
		end
		if exclude_no_bots and bit32.band(spot.flags, bit32.bor(C.FL_NO_BOTS, C.FL_NO_HUMANS)) ~= 0 then
			continue
		end
		count = count + 1
	end
	G.G_Printf("Number of %s: %i\n", itemname, count)
	return count
end

local function countFfaSpawnpoints()
	return countItems("info_player_deathmatch", true)
end

local function countDdSpawnpoints()
	local mincount, tmp
	mincount = 100

	tmp = countItems("info_player_dd_red", true)
	if tmp == 0 then
		tmp = countFfaSpawnpoints()
	end
	if tmp < mincount then
		mincount = tmp
	end

	tmp = countItems("info_player_dd_blue", true)
	if tmp == 0 then
		tmp = countFfaSpawnpoints()
	end
	if tmp < mincount then
		mincount = tmp
	end

	return mincount
end

local function countCtfSpawnpoints()
	local mincount, tmp

	mincount = 100

	tmp = countItems("team_CTF_redplayer", true)
	if tmp == 0 then
		tmp = countFfaSpawnpoints()
	end
	if tmp < mincount then
		mincount = tmp
	end

	tmp = countItems("team_CTF_blueplayer", true)
	if tmp == 0 then
		tmp = countFfaSpawnpoints()
	end
	if tmp < mincount then
		mincount = tmp
	end

	tmp = countItems("team_CTF_redspawn", true)
	if tmp == 0 then
		tmp = countFfaSpawnpoints()
	end
	if tmp < mincount then
		mincount = tmp
	end

	tmp = countItems("team_CTF_bluespawn", true)
	if tmp == 0 then
		tmp = countFfaSpawnpoints()
	end
	if tmp < mincount then
		mincount = tmp
	end

	return mincount
end

function G.MinSpawnpointCount()
	if G.g_gametype.integer < C.GT_CTF or G.g_ffa_gt > 0 then
		return countFfaSpawnpoints()
	end
	if G.g_gametype.integer == C.GT_DOUBLE_D then
		return countDdSpawnpoints()
	end
	return countCtfSpawnpoints()
end

return nil
