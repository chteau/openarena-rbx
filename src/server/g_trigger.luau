--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_trigger.c).

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
-- Luau port of g_trigger.c. Trigger entities: multiple, always, push, teleport, hurt, func_timer.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

function G.InitTrigger(self)
	if not Q.VectorCompare(self.s.angles, Q.vec3_origin) then
		G.G_SetMovedir(self.s.angles, self.movedir)
	end

	G.trap_SetBrushModel(self, self.model)
	self.r.contents = C.CONTENTS_TRIGGER -- replaces the -1 from trap_SetBrushModel
	self.r.svFlags = C.SVF_NOCLIENT
end

-- the wait time has passed, so set back up for another activation
function G.multi_wait(ent)
	ent.nextthink = 0
end

-- the trigger was just activated
-- ent.activator should be set to the activator so it can be held through a delay
-- so wait for the delay time before firing
function G.multi_trigger(ent, activator)
	ent.activator = activator
	if ent.nextthink ~= 0 then
		return -- can't retrigger until the wait is over
	end

	if activator.client then
		if bit32.band(ent.spawnflags, 1) ~= 0 and activator.client.sess.sessionTeam ~= C.TEAM_RED then
			return
		end
		if bit32.band(ent.spawnflags, 2) ~= 0 and activator.client.sess.sessionTeam ~= C.TEAM_BLUE then
			return
		end
	end

	G.G_UseTargets(ent, ent.activator)

	if ent.wait > 0 then
		ent.think = G.multi_wait
		ent.nextthink = Q.trunc(G.level.time + (ent.wait + ent.random * Q.crandom()) * 1000)
	else
		-- we can't just remove (self) here, because this is a touch function
		-- called while looping through area links...
		ent.touch = nil
		ent.nextthink = G.level.time + C.FRAMETIME
		ent.think = G.G_FreeEntity
	end
end

function G.Use_Multi(ent, other, activator)
	G.multi_trigger(ent, activator)
end

function G.Touch_Multi(self, other, trace)
	if not other.client then
		return
	end
	G.multi_trigger(self, other)
end

--QUAKED trigger_multiple (.5 .5 .5) ? RED_ONLY BLUE_ONLY
--"wait" : Seconds between triggerings, 0.5 default, -1 = one time only.
--"random"	wait variance, default is 0
--Variable sized repeatable trigger.  Must be targeted at one or more entities.
--so, the basic time between firing is a random time between
--(wait - random) and (wait + random)
function G.SP_trigger_multiple(ent)
	local _
	_, ent.wait = G.G_SpawnFloat("wait", "0.5")
	_, ent.random = G.G_SpawnFloat("random", "0")

	if ent.random >= ent.wait and ent.wait >= 0 then
		ent.random = ent.wait - C.FRAMETIME
		G.G_Printf("trigger_multiple has random >= wait\n")
	end

	ent.touch = G.Touch_Multi
	ent.use = G.Use_Multi

	G.InitTrigger(ent)
	G.trap_LinkEntity(ent)
end

--==============================================================================
-- trigger_always
--==============================================================================

function G.trigger_always_think(ent)
	G.G_UseTargets(ent, ent)
	G.G_FreeEntity(ent)
end

--QUAKED trigger_always (.5 .5 .5) (-8 -8 -8) (8 8 8)
--This trigger will always fire.  It is activated by the world.
function G.SP_trigger_always(ent)
	-- we must have some delay to make sure our use targets are present
	ent.nextthink = G.level.time + 300
	ent.think = G.trigger_always_think
end

--==============================================================================
-- trigger_push
--==============================================================================

function G.trigger_push_touch(self, other, trace)
	if not other.client then
		return
	end

	BG.BG_TouchJumpPad(other.client.ps, self.s)
end

--[[
=================
AimAtTarget

Calculate origin2 so the target apogee will be hit
=================
]]
function G.AimAtTarget(self)
	local origin = Q.vec3()

	Q.VectorAdd(self.r.absmin, self.r.absmax, origin)
	Q.VectorScale(origin, 0.5, origin)

	local ent = G.G_PickTarget(self.target)
	if not ent then
		G.G_FreeEntity(self)
		return
	end

	local height = ent.s.origin[2] - origin[2]
	local gravity = G.g_gravity.value * G.g_gravityModifier.value
	local time = math.sqrt(height / (0.5 * gravity))
	if time == 0 or time ~= time then
		-- C: !time is false for NaN, so only a true zero frees the entity
		if time == 0 then
			G.G_FreeEntity(self)
			return
		end
	end

	-- set s.origin2 to the push velocity
	Q.VectorSubtract(ent.s.origin, origin, self.s.origin2)
	self.s.origin2[2] = 0
	local dist = Q.VectorNormalize(self.s.origin2)

	local forward = dist / time
	Q.VectorScale(self.s.origin2, forward, self.s.origin2)

	self.s.origin2[2] = Q.f(time * gravity)
end

--QUAKED trigger_push (.5 .5 .5) ?
--Must point at a target_position, which will be the apex of the leap.
--This will be client side predicted, unlike target_push
function G.SP_trigger_push(self)
	G.InitTrigger(self)

	-- unlike other triggers, we need to send this one to the client
	self.r.svFlags = bit32.band(self.r.svFlags, bit32.bnot(C.SVF_NOCLIENT))

	-- make sure the client precaches this sound
	G.G_SoundIndex("sound/world/jumppad.wav")

	self.s.eType = C.ET_PUSH_TRIGGER
	self.touch = G.trigger_push_touch
	self.think = G.AimAtTarget
	self.nextthink = G.level.time + C.FRAMETIME
	G.trap_LinkEntity(self)
end

function G.Use_target_push(self, other, activator)
	if not activator.client then
		return
	end

	if activator.client.ps.pm_type ~= C.PM_NORMAL then
		return
	end
	if activator.client.ps.powerups[C.PW_FLIGHT] ~= 0 then
		return
	end

	Q.VectorCopy(self.s.origin2, activator.client.ps.velocity)

	-- play fly sound every 1.5 seconds
	if activator.fly_sound_debounce_time < G.level.time then
		activator.fly_sound_debounce_time = G.level.time + 1500
		G.G_Sound(activator, C.CHAN_AUTO, self.noise_index)
	end
end

--QUAKED target_push (.5 .5 .5) (-8 -8 -8) (8 8 8) bouncepad
--Pushes the activator in the direction.of angle, or towards a target apex.
--"speed"		defaults to 1000
--if "bouncepad", play bounce noise instead of windfly
function G.SP_target_push(self)
	if self.speed == 0 then
		self.speed = 1000
	end
	G.G_SetMovedir(self.s.angles, self.s.origin2)
	Q.VectorScale(self.s.origin2, self.speed, self.s.origin2)

	if bit32.band(self.spawnflags, 1) ~= 0 then
		self.noise_index = G.G_SoundIndex("sound/world/jumppad.wav")
	else
		self.noise_index = G.G_SoundIndex("sound/misc/windfly.wav")
	end
	if self.target ~= nil then
		Q.VectorCopy(self.s.origin, self.r.absmin)
		Q.VectorCopy(self.s.origin, self.r.absmax)
		self.think = G.AimAtTarget
		self.nextthink = G.level.time + C.FRAMETIME
	end
	self.use = G.Use_target_push
end

--==============================================================================
-- trigger_teleport
--==============================================================================

function G.trigger_teleporter_touch(self, other, trace)
	if not other.client then
		return
	end

	if other.client.ps.pm_type == C.PM_DEAD then
		return
	end
	-- Spectators only?
	if
		bit32.band(self.spawnflags, 1) ~= 0
		and (other.client.sess.sessionTeam ~= C.TEAM_SPECTATOR and other.client.ps.pm_type ~= C.PM_SPECTATOR)
	then
		return
	end

	local dest = G.G_PickTarget(self.target)
	if not dest then
		G.G_Printf("Couldn't find teleporter destination\n")
		return
	end

	G.TeleportPlayer(other, dest.s.origin, dest.s.angles)
end

--QUAKED trigger_teleport (.5 .5 .5) ? SPECTATOR
--Allows client side prediction of teleportation events.
--Must point at a target_position, which will be the teleport destination.
--
--If spectator is set, only spectators can use this teleport
--Spectator teleporters are not normally placed in the editor, but are created
--automatically near doors to allow spectators to move through them
function G.SP_trigger_teleport(self)
	G.InitTrigger(self)

	-- unlike other triggers, we need to send this one to the client
	-- unless is a spectator trigger
	if bit32.band(self.spawnflags, 1) ~= 0 then
		self.r.svFlags = bit32.bor(self.r.svFlags, C.SVF_NOCLIENT)
	else
		self.r.svFlags = bit32.band(self.r.svFlags, bit32.bnot(C.SVF_NOCLIENT))
	end

	-- make sure the client precaches this sound
	G.G_SoundIndex("sound/world/jumppad.wav")

	self.s.eType = C.ET_TELEPORT_TRIGGER
	self.touch = G.trigger_teleporter_touch

	G.trap_LinkEntity(self)
end

--==============================================================================
-- trigger_hurt
--==============================================================================

--QUAKED trigger_hurt (.5 .5 .5) ? START_OFF - SILENT NO_PROTECTION SLOW
--Any entity that touches this will be hurt.
--It does dmg points of damage each server frame
--Targeting the trigger will toggle its on / off state.
--
--SILENT			supresses playing the sound
--SLOW			changes the damage rate to once per second
--NO_PROTECTION	*nothing* stops the damage
--
--"dmg"			default 5 (whole numbers only)
function G.hurt_use(self, other, activator)
	if self.r.linked then
		G.trap_UnlinkEntity(self)
	else
		G.trap_LinkEntity(self)
	end
end

function G.hurt_touch(self, other, trace)
	local dflags

	if not other.takedamage then
		return
	end

	if self.timestamp > G.level.time then
		return
	end

	if bit32.band(self.spawnflags, 16) ~= 0 then
		self.timestamp = G.level.time + 1000
	else
		self.timestamp = G.level.time + C.FRAMETIME
	end

	-- play sound
	if bit32.band(self.spawnflags, 4) == 0 then
		G.G_Sound(other, C.CHAN_AUTO, self.noise_index)
	end

	if bit32.band(self.spawnflags, 8) ~= 0 then
		dflags = C.DAMAGE_NO_PROTECTION
	else
		dflags = 0
	end
	G.G_Damage(other, self, self, nil, nil, self.damage, dflags, C.MOD_TRIGGER_HURT)
end

function G.SP_trigger_hurt(self)
	G.InitTrigger(self)

	self.noise_index = G.G_SoundIndex("sound/world/electro.wav")
	self.touch = G.hurt_touch

	if self.damage == 0 then
		self.damage = 5
	end

	self.r.contents = C.CONTENTS_TRIGGER

	self.use = G.hurt_use

	-- link in to the world if starting active
	if bit32.band(self.spawnflags, 1) ~= 0 then
		G.trap_UnlinkEntity(self)
	else
		G.trap_LinkEntity(self)
	end
end

--==============================================================================
-- timer
--==============================================================================

--QUAKED func_timer (0.3 0.1 0.6) (-8 -8 -8) (8 8 8) START_ON
--This should be renamed trigger_timer...
--Repeatedly fires its targets.
--Can be turned on or off by using.
--
--"wait"			base time between triggering all targets, default is 1
--"random"		wait variance, default is 0
--so, the basic time between firing is a random time between
--(wait - random) and (wait + random)
function G.func_timer_think(self)
	G.G_UseTargets(self, self.activator)
	-- set time before next firing
	self.nextthink = Q.trunc(G.level.time + 1000 * (self.wait + Q.crandom() * self.random))
end

function G.func_timer_use(self, other, activator)
	self.activator = activator

	-- if on, turn it off
	if self.nextthink ~= 0 then
		self.nextthink = 0
		return
	end

	-- turn it on
	G.func_timer_think(self)
end

function G.SP_func_timer(self)
	local _
	_, self.random = G.G_SpawnFloat("random", "1")
	_, self.wait = G.G_SpawnFloat("wait", "1")

	self.use = G.func_timer_use
	self.think = G.func_timer_think

	if self.random >= self.wait then
		self.random = self.wait - C.FRAMETIME
		G.G_Printf("func_timer at %s has random >= wait\n", G.vtos(self.s.origin))
	end

	if bit32.band(self.spawnflags, 1) ~= 0 then
		self.nextthink = G.level.time + C.FRAMETIME
		self.activator = self
	end

	self.r.svFlags = C.SVF_NOCLIENT
end

return nil
