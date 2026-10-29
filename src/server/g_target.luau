--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/g_target.c).

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
-- Luau port of g_target.c. Target entities: give, delay, score, print, speaker, laser, teleporter, relay, kill, position, location.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

--==========================================================

--QUAKED target_give (1 0 0) (-8 -8 -8) (8 8 8)
-- Gives the activator all the items pointed to.
function G.Use_Target_Give(ent, other, activator)
	if activator.client == nil then
		return
	end

	if ent.target == nil then
		return
	end

	local trace = S.trace_t()
	local t = nil
	while true do
		t = G.G_Find(t, "targetname", ent.target)
		if t == nil then
			break
		end
		if t.item == nil then
			continue
		end
		G.Touch_Item(t, activator, trace)

		-- make sure it isn't going to respawn or show any events
		t.nextthink = 0
		G.trap_UnlinkEntity(t)
	end
end

function G.SP_target_give(ent)
	ent.use = function(e, o, a) G.Use_Target_Give(e, o, a) end
end

--==========================================================

--QUAKED target_remove_powerups (1 0 0) (-8 -8 -8) (8 8 8)
-- takes away all the activators powerups.
-- Used to drop flight powerups into death puts.
function G.Use_target_remove_powerups(ent, other, activator)
	if activator.client == nil then
		return
	end

	local powerups = activator.client.ps.powerups
	if powerups[C.PW_REDFLAG] ~= 0 then
		G.Team_ReturnFlag(C.TEAM_RED)
	elseif powerups[C.PW_BLUEFLAG] ~= 0 then
		G.Team_ReturnFlag(C.TEAM_BLUE)
	elseif powerups[C.PW_NEUTRALFLAG] ~= 0 then
		G.Team_ReturnFlag(C.TEAM_FREE)
	end

	for i = 0, C.MAX_POWERUPS - 1 do
		powerups[i] = 0
	end
end

function G.SP_target_remove_powerups(ent)
	ent.use = function(e, o, a) G.Use_target_remove_powerups(e, o, a) end
end

--==========================================================

--QUAKED target_delay (1 0 0) (-8 -8 -8) (8 8 8)
-- "wait" seconds to pause before firing targets.
-- "random" delay variance, total delay = delay +/- random seconds
function G.Think_Target_Delay(ent)
	G.G_UseTargets(ent, ent.activator)
end

function G.Use_Target_Delay(ent, other, activator)
	ent.nextthink = Q.trunc(G.level.time + (ent.wait + ent.random * Q.crandom()) * 1000)
	ent.think = function(e) G.Think_Target_Delay(e) end
	ent.activator = activator
end

function G.SP_target_delay(ent)
	-- check delay for backwards compatability
	local found, _
	found, ent.wait = G.G_SpawnFloat("delay", "0")
	if not found then
		_, ent.wait = G.G_SpawnFloat("wait", "1")
	end

	if ent.wait == 0 then
		ent.wait = 1
	end
	ent.use = function(e, o, a) G.Use_Target_Delay(e, o, a) end
end

--==========================================================

--QUAKED target_score (1 0 0) (-8 -8 -8) (8 8 8)
-- "count" number of points to add, default 1
--
-- The activator is given this many points.
function G.Use_Target_Score(ent, other, activator)
	G.AddScore(activator, ent.r.currentOrigin, ent.count)
end

function G.SP_target_score(ent)
	if ent.count == 0 then
		ent.count = 1
	end
	ent.use = function(e, o, a) G.Use_Target_Score(e, o, a) end
end

--==========================================================

--QUAKED target_print (1 0 0) (-8 -8 -8) (8 8 8) redteam blueteam private
-- "message"	text to print
-- If "private", only the activator gets the message.  If no checks, all clients get the message.
function G.Use_Target_Print(ent, other, activator)
	if activator.client ~= nil and bit32.band(ent.spawnflags, 4) ~= 0 then
		G.trap_SendServerCommand(activator.index, QS.va("cp \"%s\"", ent.message))
		return
	end

	if bit32.band(ent.spawnflags, 3) ~= 0 then
		if bit32.band(ent.spawnflags, 1) ~= 0 then
			G.G_TeamCommand(C.TEAM_RED, QS.va("cp \"%s\"", ent.message))
		end
		if bit32.band(ent.spawnflags, 2) ~= 0 then
			G.G_TeamCommand(C.TEAM_BLUE, QS.va("cp \"%s\"", ent.message))
		end
		return
	end

	G.trap_SendServerCommand(-1, QS.va("cp \"%s\"", ent.message))
end

function G.SP_target_print(ent)
	ent.use = function(e, o, a) G.Use_Target_Print(e, o, a) end
end

--==========================================================

--QUAKED target_speaker (1 0 0) (-8 -8 -8) (8 8 8) looped-on looped-off global activator
-- "noise"		wav file to play
--
-- A global sound will play full volume throughout the level.
-- Activator sounds will play on the player that activated the target.
-- Global and activator sounds can't be combined with looping.
-- Normal sounds play each time the target is used.
-- Looped sounds will be toggled by use functions.
-- Multiple identical looping sounds will just increase volume without any speed cost.
-- "wait" : Seconds between auto triggerings, 0 = don't auto trigger
-- "random"	wait variance, default is 0
function G.Use_Target_Speaker(ent, other, activator)
	if bit32.band(ent.spawnflags, 3) ~= 0 then -- looping sound toggles
		if ent.s.loopSound ~= 0 then
			ent.s.loopSound = 0 -- turn it off
		else
			ent.s.loopSound = ent.noise_index -- start it
		end
	else -- normal sound
		if bit32.band(ent.spawnflags, 8) ~= 0 then
			G.G_AddEvent(activator, C.EV_GENERAL_SOUND, ent.noise_index)
		elseif bit32.band(ent.spawnflags, 4) ~= 0 then
			G.G_AddEvent(ent, C.EV_GLOBAL_SOUND, ent.noise_index)
		else
			G.G_AddEvent(ent, C.EV_GENERAL_SOUND, ent.noise_index)
		end
	end
end

function G.SP_target_speaker(ent)
	local buffer
	local s
	local found, _

	_, ent.wait = G.G_SpawnFloat("wait", "0")
	_, ent.random = G.G_SpawnFloat("random", "0")

	found, s = G.G_SpawnString("noise", "NOSOUND")
	if not found then
		G.G_Error("target_speaker without a noise key at %s", G.vtos(ent.s.origin))
	end

	-- force all client reletive sounds to be "activator" speakers that
	-- play on the entity that activates it
	if string.sub(s, 1, 1) == "*" then
		ent.spawnflags = bit32.bor(ent.spawnflags, 8)
	end

	if QS.strstr(s, ".wav") == nil then
		buffer = QS.Com_sprintf(C.MAX_QPATH, "%s.wav", s)
	else
		buffer = QS.Q_strncpyz(s, C.MAX_QPATH)
	end
	ent.noise_index = G.G_SoundIndex(buffer)

	-- a repeating speaker can be done completely client side
	ent.s.eType = C.ET_SPEAKER
	ent.s.eventParm = ent.noise_index
	ent.s.frame = Q.trunc(ent.wait * 10)
	ent.s.clientNum = Q.trunc(ent.random * 10)

	-- check for prestarted looping sound
	if bit32.band(ent.spawnflags, 1) ~= 0 then
		ent.s.loopSound = ent.noise_index
	end

	ent.use = function(e, o, a) G.Use_Target_Speaker(e, o, a) end

	if bit32.band(ent.spawnflags, 4) ~= 0 then
		ent.r.svFlags = bit32.bor(ent.r.svFlags, C.SVF_BROADCAST)
	end

	Q.VectorCopy(ent.s.origin, ent.s.pos.trBase)

	-- must link the entity so we get areas and clusters so
	-- the server can determine who to send updates to
	G.trap_LinkEntity(ent)
end

--==========================================================

--QUAKED target_laser (0 .5 .8) (-8 -8 -8) (8 8 8) START_ON
-- When triggered, fires a laser.  You can either set a target or a direction.
function G.target_laser_think(self)
	local end_ = Q.vec3()
	local tr = S.trace_t()
	local point = Q.vec3()

	-- if pointed at another entity, set movedir to point at it
	if self.enemy ~= nil then
		Q.VectorMA(self.enemy.s.origin, 0.5, self.enemy.r.mins, point)
		Q.VectorMA(point, 0.5, self.enemy.r.maxs, point)
		Q.VectorSubtract(point, self.s.origin, self.movedir)
		Q.VectorNormalize(self.movedir)
	end

	-- fire forward and see what we hit
	Q.VectorMA(self.s.origin, 2048, self.movedir, end_)

	G.trap_Trace(tr, self.s.origin, nil, nil, end_, self.s.number,
		bit32.bor(C.CONTENTS_SOLID, C.CONTENTS_BODY, C.CONTENTS_CORPSE))

	if tr.entityNum ~= 0 then
		-- hurt it if we can
		G.G_Damage(G.g_entities[tr.entityNum], self, self.activator, self.movedir,
			tr.endpos, self.damage, C.DAMAGE_NO_KNOCKBACK, C.MOD_TARGET_LASER)
	end

	Q.VectorCopy(tr.endpos, self.s.origin2)

	G.trap_LinkEntity(self)
	self.nextthink = G.level.time + C.FRAMETIME
end

function G.target_laser_on(self)
	if self.activator == nil then
		self.activator = self
	end
	G.target_laser_think(self)
end

function G.target_laser_off(self)
	G.trap_UnlinkEntity(self)
	self.nextthink = 0
end

function G.target_laser_use(self, other, activator)
	self.activator = activator
	if self.nextthink > 0 then
		G.target_laser_off(self)
	else
		G.target_laser_on(self)
	end
end

function G.target_laser_start(self)
	local ent

	self.s.eType = C.ET_BEAM

	if self.target ~= nil then
		ent = G.G_Find(nil, "targetname", self.target)
		if ent == nil then
			G.G_Printf("%s at %s: %s is a bad target\n", self.classname, G.vtos(self.s.origin), self.target)
		end
		self.enemy = ent
	else
		G.G_SetMovedir(self.s.angles, self.movedir)
	end

	self.use = function(e, o, a) G.target_laser_use(e, o, a) end
	self.think = function(e) G.target_laser_think(e) end

	if self.damage == 0 then
		self.damage = 1
	end

	if bit32.band(self.spawnflags, 1) ~= 0 then
		G.target_laser_on(self)
	else
		G.target_laser_off(self)
	end
end

function G.SP_target_laser(self)
	-- let everything else get spawned before we start firing
	self.think = function(e) G.target_laser_start(e) end
	self.nextthink = G.level.time + C.FRAMETIME
end

--==========================================================

function G.target_teleporter_use(self, other, activator)
	local dest

	if activator.client == nil then
		return
	end
	dest = G.G_PickTarget(self.target)
	if dest == nil then
		G.G_Printf("Couldn't find teleporter destination\n")
		return
	end

	G.TeleportPlayer(activator, dest.s.origin, dest.s.angles)
end

--QUAKED target_teleporter (1 0 0) (-8 -8 -8) (8 8 8)
-- The activator will be teleported away.
function G.SP_target_teleporter(self)
	if self.targetname == nil then
		G.G_Printf("untargeted %s at %s\n", self.classname, G.vtos(self.s.origin))
	end

	self.use = function(e, o, a) G.target_teleporter_use(e, o, a) end
end

--==========================================================

--QUAKED target_relay (.5 .5 .5) (-8 -8 -8) (8 8 8) RED_ONLY BLUE_ONLY RANDOM
-- This doesn't perform any actions except fire its targets.
-- The activator can be forced to be from a certain team.
-- if RANDOM is checked, only one of the targets will be fired, not all of them
function G.target_relay_use(self, other, activator)
	if bit32.band(self.spawnflags, 1) ~= 0 and activator.client ~= nil
		and activator.client.sess.sessionTeam ~= C.TEAM_RED then
		return
	end
	if bit32.band(self.spawnflags, 2) ~= 0 and activator.client ~= nil
		and activator.client.sess.sessionTeam ~= C.TEAM_BLUE then
		return
	end
	if bit32.band(self.spawnflags, 4) ~= 0 then
		local ent = G.G_PickTarget(self.target)
		if ent ~= nil and ent.use ~= nil then
			ent.use(ent, self, activator)
		end
		return
	end
	G.G_UseTargets(self, activator)
end

function G.SP_target_relay(self)
	self.use = function(e, o, a) G.target_relay_use(e, o, a) end
end

--==========================================================

--QUAKED target_kill (.5 .5 .5) (-8 -8 -8) (8 8 8)
-- Kills the activator.
function G.target_kill_use(self, other, activator)
	G.G_Damage(activator, nil, nil, nil, nil, 100000, C.DAMAGE_NO_PROTECTION, C.MOD_TELEFRAG)
end

function G.SP_target_kill(self)
	self.use = function(e, o, a) G.target_kill_use(e, o, a) end
end

--QUAKED target_position (0 0.5 0) (-4 -4 -4) (4 4 4)
-- Used as a positional target for in-game calculation, like jumppad targets.
function G.SP_target_position(self)
	G.G_SetOrigin(self, self.s.origin)
end

local function target_location_linkup(ent)
	if G.level.locationLinked then
		return
	end

	G.level.locationLinked = true

	G.level.locationHead = nil

	G.trap_SetConfigstring(C.CS_LOCATIONS, "unknown")

	local n = 1
	for i = 0, G.level.num_entities - 1 do
		ent = G.g_entities[i]
		if ent.classname ~= nil and QS.Q_strequal(ent.classname, "target_location") then
			-- lets overload some variables!
			ent.health = n -- use for location marking
			G.trap_SetConfigstring(C.CS_LOCATIONS + n, ent.message)
			n = n + 1
			ent.nextTrain = G.level.locationHead
			G.level.locationHead = ent
		end
	end

	-- All linked together now
end

--QUAKED target_location (0 0.5 0) (-8 -8 -8) (8 8 8)
-- Set "message" to the name of this location.
-- Set "count" to 0-7 for color.
-- 0:white 1:red 2:green 3:yellow 4:blue 5:cyan 6:magenta 7:white
--
-- Closest target_location in sight used for the location, if none
-- in site, closest in distance
function G.SP_target_location(self)
	self.think = target_location_linkup
	self.nextthink = G.level.time + 200 -- Let them all spawn first

	G.G_SetOrigin(self, self.s.origin)
end

return nil
