--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_active.c).

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
-- Luau port of OpenArena 0.8.8's g_active.c (gamecode 9e0f0c0), part 1. Per-frame client damage feedback, world effects, touches, spectators and events.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local SF = G.FileStatics("g_active")

--[[
===============
G_DamageFeedback

Called just before a snapshot is sent to the given player.
Totals up all damage and generates both the player_state_t
damage values to that client for pain blends and kicks, and
global pain sound events for all clients.
===============
]]
function G.P_DamageFeedback(player)
	local level = G.level
	local angles = Q.vec3()

	local client = player.client
	if client.ps.pm_type == C.PM_DEAD then
		return
	end

	-- total points of damage shot at the player this frame
	local count = client.damage_blood + client.damage_armor
	if count == 0 then
		return -- didn't take any damage
	end

	if count > 255 then
		count = 255
	end

	-- world damage (falling, slime, etc) uses a special code
	-- to make the blend blob centered instead of positional
	if client.damage_fromWorld then
		client.ps.damagePitch = 255
		client.ps.damageYaw = 255

		client.damage_fromWorld = false
	else
		Q.vectoangles(client.damage_from, angles)
		client.ps.damagePitch = Q.trunc(angles[C.PITCH] / 360.0 * 256)
		client.ps.damageYaw = Q.trunc(angles[C.YAW] / 360.0 * 256)
	end

	-- play an apropriate pain sound
	if level.time > player.pain_debounce_time and bit32.band(player.flags, C.FL_GODMODE) == 0 then
		player.pain_debounce_time = level.time + 700
		G.G_AddEvent(player, C.EV_PAIN, player.health)
		client.ps.damageEvent += 1
	end

	client.ps.damageCount = Q.trunc(count)

	-- clear totals
	client.damage_blood = 0
	client.damage_armor = 0
	client.damage_knockback = 0
end

--[[
=============
P_WorldEffects

Check for lava / slime contents and drowning
=============
]]
function G.P_WorldEffects(ent)
	local level = G.level

	if ent.client.noclip then
		ent.client.airOutTime = level.time + 12000 -- don't need air
		return
	end

	local waterlevel = ent.waterlevel

	local envirosuit = ent.client.ps.powerups[C.PW_BATTLESUIT] > level.time

	-- check for drowning
	if waterlevel == 3 then
		-- envirosuit give air
		if envirosuit then
			ent.client.airOutTime = level.time + 10000
		end

		-- if out of air, start drowning
		if ent.client.airOutTime < level.time then
			-- drown!
			ent.client.airOutTime += 1000
			if ent.health > 0 then
				-- take more damage the longer underwater
				ent.damage += 2
				if ent.damage > 15 then
					ent.damage = 15
				end

				-- don't play a normal pain sound
				ent.pain_debounce_time = level.time + 200

				G.G_Damage(ent, nil, nil, nil, nil, ent.damage, C.DAMAGE_NO_ARMOR, C.MOD_WATER)
			end
		end
	else
		ent.client.airOutTime = level.time + 12000
		ent.damage = 2
	end

	-- check for sizzle damage (move to pmove?)
	if waterlevel ~= 0 and bit32.band(ent.watertype, bit32.bor(C.CONTENTS_LAVA, C.CONTENTS_SLIME)) ~= 0 then
		if ent.health > 0 and ent.pain_debounce_time <= level.time then
			if envirosuit then
				G.G_AddEvent(ent, C.EV_POWERUP_BATTLESUIT, 0)
			else
				if bit32.band(ent.watertype, C.CONTENTS_LAVA) ~= 0 then
					G.G_Damage(ent, nil, nil, nil, nil, 30 * waterlevel, 0, C.MOD_LAVA)
				end

				if bit32.band(ent.watertype, C.CONTENTS_SLIME) ~= 0 then
					G.G_Damage(ent, nil, nil, nil, nil, 10 * waterlevel, 0, C.MOD_SLIME)
				end
			end
		end
	end
end

--[[
===============
G_SetClientSound
===============
]]
function G.G_SetClientSound(ent)
	if bit32.band(ent.s.eFlags, C.EF_TICKING) ~= 0 then
		ent.client.ps.loopSound = G.G_SoundIndex("sound/weapons/proxmine/wstbtick.wav")
	elseif ent.waterlevel ~= 0 and bit32.band(ent.watertype, bit32.bor(C.CONTENTS_LAVA, C.CONTENTS_SLIME)) ~= 0 then
		ent.client.ps.loopSound = G.level.snd_fry
	else
		ent.client.ps.loopSound = 0
	end
end

--==============================================================

--[[
==============
ClientImpacts
==============
]]
function G.ClientImpacts(ent, pm)
	local trace = S.trace_t()
	for i = 0, pm.numtouch - 1 do
		local j = 0
		while j < i do
			if pm.touchents[j] == pm.touchents[i] then
				break
			end
			j += 1
		end
		if j ~= i then
			continue -- duplicated
		end
		local other = G.g_entities[pm.touchents[i]]

		if bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 and ent.touch ~= nil then
			ent.touch(ent, other, trace)
		end

		if other.touch == nil then
			continue
		end

		other.touch(other, ent, trace)
	end
end

local touchRange = Q.vec3()
touchRange[0] = 40
touchRange[1] = 40
touchRange[2] = 52

--[[
============
G_TouchTriggers

Find all trigger entities that ent's current position touches.
Spectators will only interact with teleporters.
============
]]
function G.G_TouchTriggers(ent)
	local level = G.level
	local touch = {}
	local mins = Q.vec3()
	local maxs = Q.vec3()

	if ent.client == nil then
		return
	end

	-- ELIMINATION LMS
	-- dead clients don't activate triggers! The reason our pm_spectators can't do anything
	if ent.client.ps.stats[C.STAT_HEALTH] <= 0 and ent.client.ps.pm_type ~= C.PM_SPECTATOR then
		return
	end

	Q.VectorSubtract(ent.client.ps.origin, touchRange, mins)
	Q.VectorAdd(ent.client.ps.origin, touchRange, maxs)

	local num = G.trap_EntitiesInBox(mins, maxs, touch, C.MAX_GENTITIES)

	-- can't use ent->absmin, because that has a one unit pad
	Q.VectorAdd(ent.client.ps.origin, ent.r.mins, mins)
	Q.VectorAdd(ent.client.ps.origin, ent.r.maxs, maxs)

	for i = 0, num - 1 do
		local hit = G.g_entities[touch[i]]

		if hit.touch == nil and ent.touch == nil then
			continue
		end
		if bit32.band(hit.r.contents, C.CONTENTS_TRIGGER) == 0 then
			continue
		end

		-- ignore most entities if a spectator
		if ent.client.sess.sessionTeam == C.TEAM_SPECTATOR or ent.client.ps.pm_type == C.PM_SPECTATOR then
			if hit.s.eType ~= C.ET_TELEPORT_TRIGGER
				-- this is ugly but adding a new ET_? type will
				-- most likely cause network incompatibilities
				-- We need to stop eliminated players from opening doors somewhere else /Sago007 20070814
				and hit.touch ~= G.Touch_DoorTrigger then
				continue
			end
		end

		-- use seperate code for determining if an item is picked up
		-- so you don't have to actually contact its bounding box
		if hit.s.eType == C.ET_ITEM then
			if not BG.BG_PlayerTouchesItem(ent.client.ps, hit.s, level.time) then
				continue
			end
		else
			if not G.trap_EntityContact(mins, maxs, hit) then
				continue
			end
		end

		local trace = S.trace_t()

		if hit.touch ~= nil then
			hit.touch(hit, ent, trace)
		end

		if bit32.band(ent.r.svFlags, C.SVF_BOT) ~= 0 and ent.touch ~= nil then
			ent.touch(ent, hit, trace)
		end
	end

	-- if we didn't touch a jump pad this pmove frame
	if ent.client.ps.jumppad_frame ~= ent.client.ps.pmove_framecount then
		ent.client.ps.jumppad_frame = 0
		ent.client.ps.jumppad_ent = 0
	end
end

--[[
=================
SpectatorThink
=================
]]
function G.SpectatorThink(ent, ucmd)
	local client = ent.client

	if (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION)
		and client.sess.spectatorState ~= C.SPECTATOR_FOLLOW
		and G.g_elimination_lockspectator.integer > 1
		and ent.client.sess.sessionTeam ~= C.TEAM_SPECTATOR then
		G.Cmd_FollowCycle_f(ent)
	end

	if client.sess.spectatorState ~= C.SPECTATOR_FOLLOW then
		client.ps.pm_type = C.PM_SPECTATOR
		client.ps.speed = 400 -- faster than normal

		-- set up for pmove
		local pm = S.pmove_t()
		pm.ps = client.ps
		S.copy_usercmd_t(pm.cmd, ucmd)
		pm.tracemask = bit32.band(C.MASK_PLAYERSOLID, bit32.bnot(C.CONTENTS_BODY)) -- spectators can fly through bodies
		pm.trace = function(...)
			return G.trap_Trace(...)
		end
		pm.pointcontents = function(...)
			return G.trap_PointContents(...)
		end

		-- perform a pmove
		BG.Pmove(pm)
		-- save results of pmove
		Q.VectorCopy(client.ps.origin, ent.s.origin)

		G.G_TouchTriggers(ent)
		G.trap_UnlinkEntity(ent)
	end

	client.oldbuttons = client.buttons
	client.buttons = ucmd.buttons

	-- KK-OAX Changed to keep followcycle functional
	-- attack button cycles through spectators
	if bit32.band(client.buttons, C.BUTTON_ATTACK) ~= 0 and bit32.band(client.oldbuttons, C.BUTTON_ATTACK) == 0 then
		G.Cmd_FollowCycle_f(ent)
	end

	if bit32.band(client.buttons, C.BUTTON_USE_HOLDABLE) ~= 0 and bit32.band(client.oldbuttons, C.BUTTON_USE_HOLDABLE) == 0 then
		if (G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION)
			and G.g_elimination_lockspectator.integer > 1
			and ent.client.sess.sessionTeam ~= C.TEAM_SPECTATOR then
			return
		end
		G.StopFollowing(ent)
	end
end

--[[
=================
ClientInactivityTimer

Returns qfalse if the client is dropped
=================
]]
function G.ClientInactivityTimer(client)
	local level = G.level
	if G.g_inactivity.integer == 0 then
		-- give everyone some time, so if the operator sets g_inactivity during
		-- gameplay, everyone isn't kicked
		client.inactivityTime = level.time + 60 * 1000
		client.inactivityWarning = false
	elseif client.pers.cmd.forwardmove ~= 0
		or client.pers.cmd.rightmove ~= 0
		or client.pers.cmd.upmove ~= 0
		or bit32.band(client.pers.cmd.buttons, C.BUTTON_ATTACK) ~= 0 then
		client.inactivityTime = level.time + G.g_inactivity.integer * 1000
		client.inactivityWarning = false
	elseif not client.pers.localClient then
		if level.time > client.inactivityTime then
			G.trap_DropClient(client.index, "Dropped due to inactivity")
			return false
		end
		if level.time > client.inactivityTime - 10000 and not client.inactivityWarning then
			client.inactivityWarning = true
			G.trap_SendServerCommand(client.index, "cp \"Ten seconds until inactivity drop!\n\"")
		end
	end
	return true
end

--[[
==================
ClientTimerActions

Actions that happen once a second
==================
]]
function G.ClientTimerActions(ent, msec)
	local level = G.level
	local client = ent.client
	local maxHealth
	client.timeResidual += msec

	while client.timeResidual >= 1000 do
		client.timeResidual -= 1000

		-- Stop in elimination!!!
		if bit32.band(client.ps.pm_flags, C.PMF_ELIMWARMUP) ~= 0 then
			continue
		end

		-- regenerate
		if BG.bg_itemlist[client.ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_GUARD then
			maxHealth = Q.idiv(client.ps.stats[C.STAT_MAX_HEALTH], 2)
		elseif client.ps.powerups[C.PW_REGEN] ~= 0 then
			maxHealth = client.ps.stats[C.STAT_MAX_HEALTH]
		else
			maxHealth = 0
		end
		if maxHealth ~= 0 then
			if ent.health < maxHealth then
				ent.health += 15
				if ent.health > maxHealth * 1.1 then
					ent.health = Q.trunc(maxHealth * 1.1)
				end
				G.G_AddEvent(ent, C.EV_POWERUP_REGEN, 0)
			elseif ent.health < maxHealth * 2 then
				ent.health += 5
				if ent.health > maxHealth * 2 then
					ent.health = maxHealth * 2
				end
				G.G_AddEvent(ent, C.EV_POWERUP_REGEN, 0)
			end
		else
			-- count down health when over max
			if ent.health > client.ps.stats[C.STAT_MAX_HEALTH] then
				ent.health -= 1
			end
			-- Start killing players in LMS, if we are in overtime
			if G.g_elimination_roundtime.integer ~= 0 and G.g_gametype.integer == C.GT_LMS and G.TeamHealthCount(-1, C.TEAM_FREE) ~= ent.health
				and level.roundNumber == level.roundNumberStarted and level.time >= level.roundStartTime + 1000 * G.g_elimination_roundtime.integer then
				ent.damage = 5
				G.G_Damage(ent, nil, nil, nil, nil, ent.damage, C.DAMAGE_NO_ARMOR, C.MOD_UNKNOWN)
			elseif ent.health < client.ps.stats[C.STAT_MAX_HEALTH] then
				ent.health += G.g_regen.integer
				if ent.health > client.ps.stats[C.STAT_MAX_HEALTH] then
					ent.health = client.ps.stats[C.STAT_MAX_HEALTH]
				end
			end
		end

		-- count down armor when over max
		if client.ps.stats[C.STAT_ARMOR] > client.ps.stats[C.STAT_MAX_HEALTH] then
			client.ps.stats[C.STAT_ARMOR] -= 1
		end
	end
	if BG.bg_itemlist[client.ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_AMMOREGEN then
		local max, inc, t
		local weapList = {
			C.WP_MACHINEGUN, C.WP_SHOTGUN, C.WP_GRENADE_LAUNCHER, C.WP_ROCKET_LAUNCHER, C.WP_LIGHTNING,
			C.WP_RAILGUN, C.WP_PLASMAGUN, C.WP_BFG, C.WP_NAILGUN, C.WP_PROX_LAUNCHER, C.WP_CHAINGUN,
		}
		local weapCount = #weapList

		for i = 1, weapCount do
			local w = weapList[i]

			if w == C.WP_MACHINEGUN then
				max = 50; inc = 4; t = 1000
			elseif w == C.WP_SHOTGUN then
				max = 10; inc = 1; t = 1500
			elseif w == C.WP_GRENADE_LAUNCHER then
				max = 10; inc = 1; t = 2000
			elseif w == C.WP_ROCKET_LAUNCHER then
				max = 10; inc = 1; t = 1750
			elseif w == C.WP_LIGHTNING then
				max = 50; inc = 5; t = 1500
			elseif w == C.WP_RAILGUN then
				max = 10; inc = 1; t = 1750
			elseif w == C.WP_PLASMAGUN then
				max = 50; inc = 5; t = 1500
			elseif w == C.WP_BFG then
				max = 10; inc = 1; t = 4000
			elseif w == C.WP_NAILGUN then
				max = 10; inc = 1; t = 1250
			elseif w == C.WP_PROX_LAUNCHER then
				max = 5; inc = 1; t = 2000
			elseif w == C.WP_CHAINGUN then
				max = 100; inc = 5; t = 1000
			else
				max = 0; inc = 0; t = 1000
			end
			client.ammoTimes[w] += msec
			if client.ps.ammo[w] >= max then
				client.ammoTimes[w] = 0
			end
			if client.ammoTimes[w] >= t then
				while client.ammoTimes[w] >= t do
					client.ammoTimes[w] -= t
				end
				client.ps.ammo[w] += inc
				if client.ps.ammo[w] > max then
					client.ps.ammo[w] = max
				end
			end
		end
	end
end

--[[
====================
ClientIntermissionThink
====================
]]
function G.ClientIntermissionThink(client)
	client.ps.eFlags = bit32.band(client.ps.eFlags, bit32.bnot(C.EF_TALK))
	client.ps.eFlags = bit32.band(client.ps.eFlags, bit32.bnot(C.EF_FIRING))

	-- the level will exit when everyone wants to or after timeouts

	if bit32.band(G.g_entities[client.ps.clientNum].r.svFlags, C.SVF_BOT) ~= 0 then
		return -- Bots cannot mark themself as ready
	end

	-- swap and latch button actions
	client.oldbuttons = client.buttons
	client.buttons = client.pers.cmd.buttons
	if bit32.band(client.buttons, bit32.bor(C.BUTTON_ATTACK, C.BUTTON_USE_HOLDABLE), bit32.bxor(client.oldbuttons, client.buttons)) ~= 0 then
		-- this used to be an ^1 but once a player says ready, it should stick
		client.readyToExit = true
	end
end

--[[
================
ClientEvents

Events will be passed on to the clients for presentation,
but any server game effects are handled here
================
]]
function G.ClientEvents(ent, oldEventSequence)
	local level = G.level
	local dir = Q.vec3()
	local origin = Q.vec3()
	local angles = Q.vec3()

	local client = ent.client

	if oldEventSequence < client.ps.eventSequence - C.MAX_PS_EVENTS then
		oldEventSequence = client.ps.eventSequence - C.MAX_PS_EVENTS
	end
	for i = oldEventSequence, client.ps.eventSequence - 1 do
		local event = client.ps.events[bit32.band(i, C.MAX_PS_EVENTS - 1)]

		if event == C.EV_FALL_MEDIUM or event == C.EV_FALL_FAR then
			if ent.s.eType ~= C.ET_PLAYER then
				continue -- not in the player model
			end
			if bit32.band(G.g_dmflags.integer, C.DF_NO_FALLING) ~= 0 then
				continue
			end
			local damage
			if event == C.EV_FALL_FAR then
				damage = 10
			else
				damage = 5
			end
			Q.VectorSet(dir, 0, 0, 1)
			ent.pain_debounce_time = level.time + 200 -- no normal pain sound
			G.G_Damage(ent, nil, nil, nil, nil, damage, 0, C.MOD_FALLING)
		elseif event == C.EV_FIRE_WEAPON then
			G.FireWeapon(ent)
		elseif event == C.EV_USE_ITEM1 then -- teleporter
			-- drop flags in CTF
			local item = nil
			local j = 0

			if ent.client.ps.powerups[C.PW_REDFLAG] ~= 0 then
				item = BG.BG_FindItemForPowerup(C.PW_REDFLAG)
				j = C.PW_REDFLAG
			elseif ent.client.ps.powerups[C.PW_BLUEFLAG] ~= 0 then
				item = BG.BG_FindItemForPowerup(C.PW_BLUEFLAG)
				j = C.PW_BLUEFLAG
			elseif ent.client.ps.powerups[C.PW_NEUTRALFLAG] ~= 0 then
				item = BG.BG_FindItemForPowerup(C.PW_NEUTRALFLAG)
				j = C.PW_NEUTRALFLAG
			end

			if item ~= nil then
				local drop = G.Drop_Item(ent, item, 0)
				-- decide how many seconds it has left
				drop.count = Q.idiv(ent.client.ps.powerups[j] - level.time, 1000)
				if drop.count < 1 then
					drop.count = 1
				end

				ent.client.ps.powerups[j] = 0
			end

			if G.g_gametype.integer == C.GT_HARVESTER then
				if ent.client.ps.generic1 > 0 then
					if ent.client.sess.sessionTeam == C.TEAM_RED then
						item = BG.BG_FindItem("Blue Cube")
					else
						item = BG.BG_FindItem("Red Cube")
					end
					if item ~= nil then
						for _ = 0, ent.client.ps.generic1 - 1 do
							local drop = G.Drop_Item(ent, item, 0)
							if ent.client.sess.sessionTeam == C.TEAM_RED then
								drop.spawnflags = C.TEAM_BLUE
							else
								drop.spawnflags = C.TEAM_RED
							end
						end
					end
					ent.client.ps.generic1 = 0
				end
			end
			G.SelectSpawnPoint(ent.client.ps.origin, origin, angles)
			G.TeleportPlayer(ent, origin, angles)
		elseif event == C.EV_USE_ITEM2 then -- medkit
			ent.health = ent.client.ps.stats[C.STAT_MAX_HEALTH] + 25
		elseif event == C.EV_USE_ITEM3 then -- kamikaze
			-- make sure the invulnerability is off
			ent.client.invulnerabilityTime = 0
			-- start the kamikze
			G.G_StartKamikaze(ent)
		elseif event == C.EV_USE_ITEM4 then -- portal
			if ent.client.portalID ~= 0 then
				G.DropPortalSource(ent)
			else
				G.DropPortalDestination(ent)
			end
		elseif event == C.EV_USE_ITEM5 then -- invulnerability
			ent.client.invulnerabilityTime = level.time + 10000
		end
	end
end

return nil
