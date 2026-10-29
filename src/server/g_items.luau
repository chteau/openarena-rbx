--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_items.c).

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
-- Luau port of OpenArena 0.8.8's g_items.c (gamecode 9e0f0c0). Items: pickup rules, respawning, dropping and spawning.

local G = require("./g_local")
local C = require("./g_defs")
local S = require("./g_structs")
local Q = require("../shared/q_math")
local QS = require("../shared/q_shared")
local BG = require("../shared/BG")

local S_COLOR_YELLOW = "^3"

--[[
  Items are any object that a player can touch to gain some effect.

  Pickup will return the number of seconds until they should respawn.

  all items should pop when dropped in lava or slime

  Respawnable items don't actually go away when picked up, they are
  just made invisible and untouchable.  This allows them to ride
  movers and respawn apropriately.
]]

local RESPAWN_ARMOR = 25
local RESPAWN_HEALTH = 35
local RESPAWN_AMMO = 40
local RESPAWN_HOLDABLE = 60
local RESPAWN_MEGAHEALTH = 35 --120
local RESPAWN_POWERUP = 120

G.itemRegistered = {}
for i = 0, C.MAX_ITEMS - 1 do
	G.itemRegistered[i] = false
end

--======================================================================

function G.Pickup_Powerup(ent, other)
	local quantity
	local client

	if other.client.ps.powerups[ent.item.giTag] == 0 then
		-- round timing to seconds to make multiple powerup timers
		-- count in sync
		other.client.ps.powerups[ent.item.giTag] = G.level.time - Q.imod(G.level.time, 1000)
	end

	if ent.count ~= 0 then
		quantity = ent.count
	else
		quantity = ent.item.quantity
	end

	other.client.ps.powerups[ent.item.giTag] += quantity * 1000

	-- give any nearby players a "denied" anti-reward
	for i = 0, G.level.maxclients - 1 do
		local delta = Q.vec3()
		local len
		local forward = Q.vec3()
		local tr = S.trace_t()

		client = G.level.clients[i]
		if client == other.client then
			continue
		end
		if client.pers.connected == C.CON_DISCONNECTED then
			continue
		end
		if client.ps.stats[C.STAT_HEALTH] <= 0 then
			continue
		end

		-- if same team in team game, no sound
		-- cannot use OnSameTeam as it expects to g_entities, not clients
		if G.g_gametype.integer >= C.GT_TEAM and G.g_ffa_gt == 0 and other.client.sess.sessionTeam == client.sess.sessionTeam then
			continue
		end

		-- if too far away, no sound
		Q.VectorSubtract(ent.s.pos.trBase, client.ps.origin, delta)
		len = Q.VectorNormalize(delta)
		if len > 192 then
			continue
		end

		-- if not facing, no sound
		Q.AngleVectors(client.ps.viewangles, forward, nil, nil)
		if Q.DotProduct(delta, forward) < 0.4 then
			continue
		end

		-- if not line of sight, no sound
		G.trap_Trace(tr, client.ps.origin, nil, nil, ent.s.pos.trBase, C.ENTITYNUM_NONE, C.CONTENTS_SOLID)
		if tr.fraction ~= 1.0 then
			continue
		end

		-- anti-reward
		client.ps.persistant[C.PERS_PLAYEREVENTS] = bit32.bxor(client.ps.persistant[C.PERS_PLAYEREVENTS], C.PLAYEREVENT_DENIEDREWARD)
	end
	return RESPAWN_POWERUP
end

--======================================================================

function G.Pickup_PersistantPowerup(ent, other)
	local clientNum
	local userinfo
	local handicap
	local max

	other.client.ps.stats[C.STAT_PERSISTANT_POWERUP] = ent.item.index
	other.client.persistantPowerup = ent

	local tag = ent.item.giTag
	if tag == C.PW_GUARD then
		clientNum = other.client.ps.clientNum
		userinfo = G.trap_GetUserinfo(clientNum)
		handicap = QS.atof(QS.Info_ValueForKey(userinfo, "handicap"))
		if handicap <= 0.0 or handicap > 100.0 then
			handicap = 100.0
		end
		max = Q.trunc(2 * handicap)

		other.health = max
		other.client.ps.stats[C.STAT_HEALTH] = max
		other.client.ps.stats[C.STAT_MAX_HEALTH] = max
		other.client.ps.stats[C.STAT_ARMOR] = max
		other.client.pers.maxHealth = max
	elseif tag == C.PW_SCOUT then
		clientNum = other.client.ps.clientNum
		userinfo = G.trap_GetUserinfo(clientNum)
		handicap = QS.atof(QS.Info_ValueForKey(userinfo, "handicap"))
		if handicap <= 0.0 or handicap > 100.0 then
			handicap = 100.0
		end
		other.client.pers.maxHealth = Q.trunc(handicap)
		other.client.ps.stats[C.STAT_ARMOR] = 0
	elseif tag == C.PW_DOUBLER then
		clientNum = other.client.ps.clientNum
		userinfo = G.trap_GetUserinfo(clientNum)
		handicap = QS.atof(QS.Info_ValueForKey(userinfo, "handicap"))
		if handicap <= 0.0 or handicap > 100.0 then
			handicap = 100.0
		end
		other.client.pers.maxHealth = Q.trunc(handicap)
	elseif tag == C.PW_AMMOREGEN then
		clientNum = other.client.ps.clientNum
		userinfo = G.trap_GetUserinfo(clientNum)
		handicap = QS.atof(QS.Info_ValueForKey(userinfo, "handicap"))
		if handicap <= 0.0 or handicap > 100.0 then
			handicap = 100.0
		end
		other.client.pers.maxHealth = Q.trunc(handicap)
		for i = 0, C.WP_NUM_WEAPONS - 1 do
			other.client.ammoTimes[i] = 0
		end
	else
		clientNum = other.client.ps.clientNum
		userinfo = G.trap_GetUserinfo(clientNum)
		handicap = QS.atof(QS.Info_ValueForKey(userinfo, "handicap"))
		if handicap <= 0.0 or handicap > 100.0 then
			handicap = 100.0
		end
		other.client.pers.maxHealth = Q.trunc(handicap)
	end

	return -1
end

--======================================================================

function G.Pickup_Holdable(ent, other)
	other.client.ps.stats[C.STAT_HOLDABLE_ITEM] = ent.item.index

	if ent.item.giTag == C.HI_KAMIKAZE then
		other.client.ps.eFlags = bit32.bor(other.client.ps.eFlags, C.EF_KAMIKAZE)
	end

	return RESPAWN_HOLDABLE
end

--======================================================================

function G.Add_Ammo(ent, weapon, count)
	ent.client.ps.ammo[weapon] += count
	if ent.client.ps.ammo[weapon] > 200 then
		ent.client.ps.ammo[weapon] = 200
	end
end

function G.Pickup_Ammo(ent, other)
	local quantity

	if ent.count ~= 0 then
		quantity = ent.count
	else
		quantity = ent.item.quantity
	end

	G.Add_Ammo(other, ent.item.giTag, quantity)

	return RESPAWN_AMMO
end

--======================================================================

function G.Pickup_Weapon(ent, other)
	local quantity

	if ent.count < 0 then
		quantity = 0 -- None for you, sir!
	else
		if ent.count ~= 0 then
			quantity = ent.count
		else
			quantity = ent.item.quantity
		end

		-- dropped items and teamplay weapons always have full ammo
		if bit32.band(ent.flags, C.FL_DROPPED_ITEM) == 0 and G.g_gametype.integer ~= C.GT_TEAM then
			-- respawning rules
			-- drop the quantity if the already have over the minimum
			if other.client.ps.ammo[ent.item.giTag] < quantity then
				quantity = quantity - other.client.ps.ammo[ent.item.giTag]
			else
				quantity = 1 -- only add a single shot
			end
		end
	end

	-- add the weapon
	other.client.ps.stats[C.STAT_WEAPONS] = bit32.bor(other.client.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, ent.item.giTag))

	G.Add_Ammo(other, ent.item.giTag, quantity)

	if ent.item.giTag == C.WP_GRAPPLING_HOOK then
		other.client.ps.ammo[ent.item.giTag] = -1 -- unlimited ammo
	end

	-- team deathmatch has slow weapon respawns
	if G.g_gametype.integer == C.GT_TEAM then
		return G.g_weaponTeamRespawn.integer
	end

	return G.g_weaponRespawn.integer
end

--======================================================================

function G.Pickup_Health(ent, other)
	local max
	local quantity

	if other.client == nil then
		return RESPAWN_HEALTH
	end

	-- small and mega healths will go over the max
	if other.client ~= nil and BG.bg_itemlist[other.client.ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_GUARD then
		max = other.client.ps.stats[C.STAT_MAX_HEALTH]
	elseif ent.item.quantity ~= 5 and ent.item.quantity ~= 100 then
		max = other.client.ps.stats[C.STAT_MAX_HEALTH]
	else
		max = other.client.ps.stats[C.STAT_MAX_HEALTH] * 2
	end

	if ent.count ~= 0 then
		quantity = ent.count
	else
		quantity = ent.item.quantity
	end

	other.health += quantity

	if other.health > max then
		other.health = max
	end
	other.client.ps.stats[C.STAT_HEALTH] = other.health

	if ent.item.quantity == 100 then -- mega health respawns slow
		return RESPAWN_MEGAHEALTH
	end

	return RESPAWN_HEALTH
end

--======================================================================

function G.Pickup_Armor(ent, other)
	local upperBound

	other.client.ps.stats[C.STAT_ARMOR] += ent.item.quantity

	if other.client ~= nil and BG.bg_itemlist[other.client.ps.stats[C.STAT_PERSISTANT_POWERUP]].giTag == C.PW_GUARD then
		upperBound = other.client.ps.stats[C.STAT_MAX_HEALTH]
	else
		upperBound = other.client.ps.stats[C.STAT_MAX_HEALTH] * 2
	end

	if other.client.ps.stats[C.STAT_ARMOR] > upperBound then
		other.client.ps.stats[C.STAT_ARMOR] = upperBound
	end

	return RESPAWN_ARMOR
end

--======================================================================

--[[
===============
RespawnItem
===============
]]
function G.RespawnItem(ent)
	--Don't spawn quad if quadfactor are 1.0 or less
	if ent.item.giType == C.IT_POWERUP and ent.item.giTag == C.PW_QUAD and G.g_quadfactor.value <= 1.0 then
		return
	end

	-- randomly select from teamed entities
	if ent.team ~= nil then
		local master
		local count
		local choice

		if ent.teammaster == nil then
			G.G_Error("RespawnItem: bad teammaster")
		end
		master = ent.teammaster

		count = 0
		ent = master
		while ent ~= nil do
			ent = ent.teamchain
			count += 1
		end

		choice = if count > 0 then Q.imod(Q.rand(), count) else 0

		count = 0
		ent = master
		while count < choice do
			ent = ent.teamchain
			count += 1
		end
	end

	ent.r.contents = C.CONTENTS_TRIGGER
	ent.s.eFlags = bit32.band(ent.s.eFlags, bit32.bnot(C.EF_NODRAW))
	ent.r.svFlags = bit32.band(ent.r.svFlags, bit32.bnot(C.SVF_NOCLIENT))
	G.trap_LinkEntity(ent)

	if ent.item.giType == C.IT_POWERUP then
		-- play powerup spawn sound to all clients
		local te

		-- if the powerup respawn sound should Not be global
		if ent.speed ~= 0 then
			te = G.G_TempEntity(ent.s.pos.trBase, C.EV_GENERAL_SOUND)
		else
			te = G.G_TempEntity(ent.s.pos.trBase, C.EV_GLOBAL_SOUND)
		end
		te.s.eventParm = G.G_SoundIndex("sound/items/poweruprespawn.wav")
		te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_BROADCAST)
	end

	if ent.item.giType == C.IT_HOLDABLE and ent.item.giTag == C.HI_KAMIKAZE then
		-- play powerup spawn sound to all clients
		local te

		-- if the powerup respawn sound should Not be global
		if ent.speed ~= 0 then
			te = G.G_TempEntity(ent.s.pos.trBase, C.EV_GENERAL_SOUND)
		else
			te = G.G_TempEntity(ent.s.pos.trBase, C.EV_GLOBAL_SOUND)
		end
		te.s.eventParm = G.G_SoundIndex("sound/items/kamikazerespawn.wav")
		te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_BROADCAST)
	end

	-- play the normal respawn sound only to nearby clients
	G.G_AddEvent(ent, C.EV_ITEM_RESPAWN, 0)

	ent.nextthink = 0
end

--[[
===============
Touch_Item
===============
]]
function G.Touch_Item(ent, other, trace)
	local respawn
	local predict

	--instant gib
	if (G.g_instantgib.integer ~= 0 or G.g_rockets.integer ~= 0 or G.g_gametype.integer == C.GT_CTF_ELIMINATION or G.g_elimination_allgametypes.integer ~= 0)
		and ent.item.giType ~= C.IT_TEAM then
		return
	end

	--Cannot touch flag before round starts
	if G.g_gametype.integer == C.GT_CTF_ELIMINATION and G.level.roundNumber ~= G.level.roundNumberStarted then
		return
	end

	--Cannot take ctf elimination oneway
	if G.g_gametype.integer == C.GT_CTF_ELIMINATION and G.g_elimination_ctf_oneway.integer ~= 0 and (
		(other.client.sess.sessionTeam == C.TEAM_BLUE and Q.imod(G.level.eliminationSides + G.level.roundNumber, 2) == 0) or
		(other.client.sess.sessionTeam == C.TEAM_RED and Q.imod(G.level.eliminationSides + G.level.roundNumber, 2) ~= 0)) then
		return
	end

	if G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_LMS then
		return --nothing to pick up in elimination
	end

	if other.client == nil then
		return
	end
	if other.health < 1 then
		return -- dead people can't pickup
	end

	-- the same pickup rules are used for client side and server side
	if not BG.BG_CanItemBeGrabbed(G.g_gametype.integer, ent.s, other.client.ps) then
		return
	end

	--In double DD we cannot "pick up" a flag we already got
	if G.g_gametype.integer == C.GT_DOUBLE_D then
		if QS.Q_strequal(ent.classname, "team_CTF_redflag") then
			if other.client.sess.sessionTeam == G.level.pointStatusA then
				return
			end
		end
		if QS.Q_strequal(ent.classname, "team_CTF_blueflag") then
			if other.client.sess.sessionTeam == G.level.pointStatusB then
				return
			end
		end
	end

	G.G_LogPrintf("Item: %i %s\n", other.s.number, ent.item.classname)

	predict = other.client.pers.predictItemPickup

	-- call the item-specific pickup function
	local giType = ent.item.giType
	if giType == C.IT_WEAPON then
		respawn = G.Pickup_Weapon(ent, other)
	elseif giType == C.IT_AMMO then
		respawn = G.Pickup_Ammo(ent, other)
	elseif giType == C.IT_ARMOR then
		respawn = G.Pickup_Armor(ent, other)
	elseif giType == C.IT_HEALTH then
		respawn = G.Pickup_Health(ent, other)
	elseif giType == C.IT_POWERUP then
		respawn = G.Pickup_Powerup(ent, other)
		predict = false
	elseif giType == C.IT_PERSISTANT_POWERUP then
		respawn = G.Pickup_PersistantPowerup(ent, other)
	elseif giType == C.IT_TEAM then
		respawn = G.Pickup_Team(ent, other)
		--If touching a team item remove spawnprotection
		if other.client.spawnprotected then
			other.client.spawnprotected = false
		end
	elseif giType == C.IT_HOLDABLE then
		respawn = G.Pickup_Holdable(ent, other)
	else
		return
	end

	if respawn == 0 then
		return
	end

	-- play the normal pickup sound
	if predict then
		G.G_AddPredictableEvent(other, C.EV_ITEM_PICKUP, ent.s.modelindex)
	else
		G.G_AddEvent(other, C.EV_ITEM_PICKUP, ent.s.modelindex)
	end

	-- powerup pickups are global broadcasts
	if ent.item.giType == C.IT_POWERUP or ent.item.giType == C.IT_TEAM then
		-- if we want the global sound to play
		if ent.speed == 0 then
			local te

			te = G.G_TempEntity(ent.s.pos.trBase, C.EV_GLOBAL_ITEM_PICKUP)
			te.s.eventParm = ent.s.modelindex
			te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_BROADCAST)
		else
			local te

			te = G.G_TempEntity(ent.s.pos.trBase, C.EV_GLOBAL_ITEM_PICKUP)
			te.s.eventParm = ent.s.modelindex
			-- only send this temp entity to a single client
			te.r.svFlags = bit32.bor(te.r.svFlags, C.SVF_SINGLECLIENT)
			te.r.singleClient = other.s.number
		end
	end

	-- fire item targets
	G.G_UseTargets(ent, other)

	-- wait of -1 will not respawn
	if ent.wait == -1 then
		ent.r.svFlags = bit32.bor(ent.r.svFlags, C.SVF_NOCLIENT)
		ent.s.eFlags = bit32.bor(ent.s.eFlags, C.EF_NODRAW)
		ent.r.contents = 0
		ent.unlinkAfterEvent = true
		return
	end

	-- non zero wait overrides respawn time
	if ent.wait ~= 0 then
		respawn = Q.trunc(ent.wait)
	end

	-- random can be used to vary the respawn time
	if ent.random ~= 0 then
		respawn = Q.trunc(respawn + Q.crandom() * ent.random)
		if respawn < 1 then
			respawn = 1
		end
	end

	-- dropped items will not respawn
	if bit32.band(ent.flags, C.FL_DROPPED_ITEM) ~= 0 then
		ent.freeAfterEvent = true
	end

	-- picked up items still stay around, they just don't
	-- draw anything.  This allows respawnable items
	-- to be placed on movers.
	ent.r.svFlags = bit32.bor(ent.r.svFlags, C.SVF_NOCLIENT)
	ent.s.eFlags = bit32.bor(ent.s.eFlags, C.EF_NODRAW)
	ent.r.contents = 0

	-- ZOID
	-- A negative respawn times means to never respawn this item (but don't
	-- delete it).  This is used by items that are respawned by third party
	-- events such as ctf flags
	if respawn <= 0 then
		ent.nextthink = 0
		ent.think = nil
	else
		ent.nextthink = G.level.time + respawn * 1000
		ent.think = G.RespawnItem
	end
	G.trap_LinkEntity(ent)
end

--======================================================================

--[[
================
LaunchItem

Spawns an item and tosses it forward
================
]]
function G.LaunchItem(item, origin, velocity)
	local dropped

	dropped = G.G_Spawn()

	dropped.s.eType = C.ET_ITEM
	dropped.s.modelindex = item.index -- store item number in modelindex
	dropped.s.modelindex2 = 1 -- This is non-zero is it's a dropped item

	dropped.classname = item.classname
	dropped.item = item
	Q.VectorSet(dropped.r.mins, -C.ITEM_RADIUS, -C.ITEM_RADIUS, -C.ITEM_RADIUS)
	Q.VectorSet(dropped.r.maxs, C.ITEM_RADIUS, C.ITEM_RADIUS, C.ITEM_RADIUS)
	dropped.r.contents = C.CONTENTS_TRIGGER

	dropped.touch = G.Touch_Item

	G.G_SetOrigin(dropped, origin)
	dropped.s.pos.trType = C.TR_GRAVITY
	dropped.s.pos.trTime = G.level.time
	Q.VectorCopy(velocity, dropped.s.pos.trDelta)

	dropped.s.eFlags = bit32.bor(dropped.s.eFlags, C.EF_BOUNCE_HALF)
	if (G.g_gametype.integer == C.GT_CTF or G.g_gametype.integer == C.GT_1FCTF or
		G.g_gametype.integer == C.GT_CTF_ELIMINATION or G.g_gametype.integer == C.GT_DOUBLE_D)
		and item.giType == C.IT_TEAM then -- Special case for CTF flags
		dropped.think = G.Team_DroppedFlagThink
		dropped.nextthink = G.level.time + 30000
		G.Team_CheckDroppedItem(dropped)
	else -- auto-remove after 30 seconds
		dropped.think = G.G_FreeEntity
		dropped.nextthink = G.level.time + 30000
	end

	dropped.flags = C.FL_DROPPED_ITEM

	G.trap_LinkEntity(dropped)

	return dropped
end

--[[
================
Drop_Item

Spawns an item and tosses it forward
================
]]
function G.Drop_Item(ent, item, angle)
	local velocity = Q.vec3()
	local angles = Q.vec3()

	Q.VectorCopy(ent.s.apos.trBase, angles)
	angles[C.YAW] += angle
	angles[C.PITCH] = 0 -- always forward

	Q.AngleVectors(angles, velocity, nil, nil)
	Q.VectorScale(velocity, 150, velocity)
	velocity[2] += 200 + Q.crandom() * 50

	return G.LaunchItem(item, ent.s.pos.trBase, velocity)
end

--[[
================
Use_Item

Respawn the item
================
]]
function G.Use_Item(ent, other, activator)
	G.RespawnItem(ent)
end

--======================================================================

--[[
================
FinishSpawningItem

Traces down to find where an item should rest, instead of letting them
free fall from their spawn points
================
]]
function G.FinishSpawningItem(ent)
	local tr = S.trace_t()
	local dest = Q.vec3()

	Q.VectorSet(ent.r.mins, -C.ITEM_RADIUS, -C.ITEM_RADIUS, -C.ITEM_RADIUS)
	Q.VectorSet(ent.r.maxs, C.ITEM_RADIUS, C.ITEM_RADIUS, C.ITEM_RADIUS)

	ent.s.eType = C.ET_ITEM
	ent.s.modelindex = ent.item.index -- store item number in modelindex
	ent.s.modelindex2 = 0 -- zero indicates this isn't a dropped item

	ent.r.contents = C.CONTENTS_TRIGGER
	ent.touch = G.Touch_Item
	-- using an item causes it to respawn
	ent.use = G.Use_Item

	if bit32.band(ent.spawnflags, 1) ~= 0 then
		-- suspended
		G.G_SetOrigin(ent, ent.s.origin)
	else
		-- drop to floor
		Q.VectorSet(dest, ent.s.origin[0], ent.s.origin[1], ent.s.origin[2] - 4096)
		G.trap_Trace(tr, ent.s.origin, ent.r.mins, ent.r.maxs, dest, ent.s.number, C.MASK_SOLID)
		if tr.startsolid then
			G.G_Printf("FinishSpawningItem: %s startsolid at %s\n", ent.classname, G.vtos(ent.s.origin))
			G.G_FreeEntity(ent)
			return
		end

		-- allow to ride movers
		ent.s.groundEntityNum = tr.entityNum

		G.G_SetOrigin(ent, tr.endpos)
	end

	-- team slaves and targeted items aren't present at start
	if bit32.band(ent.flags, C.FL_TEAMSLAVE) ~= 0 or ent.targetname ~= nil then
		ent.s.eFlags = bit32.bor(ent.s.eFlags, C.EF_NODRAW)
		ent.r.contents = 0
		return
	end

	-- powerups don't spawn in for a while (but not in elimination)
	if G.g_gametype.integer ~= C.GT_ELIMINATION and G.g_gametype.integer ~= C.GT_CTF_ELIMINATION and G.g_gametype.integer ~= C.GT_LMS
		and G.g_instantgib.integer == 0 and G.g_elimination_allgametypes.integer == 0 and G.g_rockets.integer == 0 then
		if ent.item.giType == C.IT_POWERUP then
			local respawn

			respawn = 45 + Q.crandom() * 15
			ent.s.eFlags = bit32.bor(ent.s.eFlags, C.EF_NODRAW)
			ent.r.contents = 0
			ent.nextthink = Q.trunc(G.level.time + respawn * 1000)
			ent.think = G.RespawnItem
			return
		end
	end

	G.trap_LinkEntity(ent)
end

--[[
==================
G_CheckTeamItems
==================
]]
function G.G_CheckTeamItems()
	-- Set up team stuff
	G.Team_InitGame()

	if G.g_gametype.integer == C.GT_CTF or G.g_gametype.integer == C.GT_CTF_ELIMINATION or G.g_gametype.integer == C.GT_DOUBLE_D then
		local item

		-- check for the two flags
		item = BG.BG_FindItem("Red Flag")
		if item == nil or not G.itemRegistered[item.index] then
			G.G_Printf(S_COLOR_YELLOW .. "WARNING: No team_CTF_redflag in map\n")
		end
		item = BG.BG_FindItem("Blue Flag")
		if item == nil or not G.itemRegistered[item.index] then
			G.G_Printf(S_COLOR_YELLOW .. "WARNING: No team_CTF_blueflag in map\n")
		end
	end
	if G.g_gametype.integer == C.GT_1FCTF then
		local item

		-- check for all three flags
		item = BG.BG_FindItem("Red Flag")
		if item == nil or not G.itemRegistered[item.index] then
			G.G_Printf(S_COLOR_YELLOW .. "WARNING: No team_CTF_redflag in map\n")
		end
		item = BG.BG_FindItem("Blue Flag")
		if item == nil or not G.itemRegistered[item.index] then
			G.G_Printf(S_COLOR_YELLOW .. "WARNING: No team_CTF_blueflag in map\n")
		end
		item = BG.BG_FindItem("Neutral Flag")
		if item == nil or not G.itemRegistered[item.index] then
			G.G_Printf(S_COLOR_YELLOW .. "WARNING: No team_CTF_neutralflag in map\n")
		end
	end

	if G.g_gametype.integer == C.GT_OBELISK then
		local ent

		-- check for the two obelisks
		ent = nil
		ent = G.G_Find(ent, "classname", "team_redobelisk")
		if ent == nil then
			G.G_Printf(S_COLOR_YELLOW .. "WARNING: No team_redobelisk in map\n")
		end

		ent = nil
		ent = G.G_Find(ent, "classname", "team_blueobelisk")
		if ent == nil then
			G.G_Printf(S_COLOR_YELLOW .. "WARNING: No team_blueobelisk in map\n")
		end
	end

	if G.g_gametype.integer == C.GT_HARVESTER then
		local ent

		-- check for all three obelisks
		ent = nil
		ent = G.G_Find(ent, "classname", "team_redobelisk")
		if ent == nil then
			G.G_Printf(S_COLOR_YELLOW .. "WARNING: No team_redobelisk in map\n")
		end

		ent = nil
		ent = G.G_Find(ent, "classname", "team_blueobelisk")
		if ent == nil then
			G.G_Printf(S_COLOR_YELLOW .. "WARNING: No team_blueobelisk in map\n")
		end

		ent = nil
		ent = G.G_Find(ent, "classname", "team_neutralobelisk")
		if ent == nil then
			G.G_Printf(S_COLOR_YELLOW .. "WARNING: No team_neutralobelisk in map\n")
		end
	end
end

--[[
==============
ClearRegisteredItems
==============
]]
function G.ClearRegisteredItems()
	for i = 0, C.MAX_ITEMS - 1 do
		G.itemRegistered[i] = false
	end

	if G.g_instantgib.integer ~= 0 then
		if bit32.band(G.g_instantgib.integer, 2) ~= 0 then
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_GAUNTLET))
		end
		G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_RAILGUN))
	elseif G.g_rockets.integer ~= 0 then
		G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_ROCKET_LAUNCHER))
	else
		-- players always start with the base weapon
		G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_MACHINEGUN))
		G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_GAUNTLET))
		if G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_CTF_ELIMINATION
			or G.g_gametype.integer == C.GT_LMS or G.g_elimination_allgametypes.integer ~= 0 then
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_SHOTGUN))
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_GRENADE_LAUNCHER))
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_ROCKET_LAUNCHER))
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_LIGHTNING))
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_RAILGUN))
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_PLASMAGUN))
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_BFG))
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_NAILGUN))
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_PROX_LAUNCHER))
			G.RegisterItem(BG.BG_FindItemForWeapon(C.WP_CHAINGUN))
		end
	end
	if G.g_gametype.integer == C.GT_HARVESTER then
		G.RegisterItem(BG.BG_FindItem("Red Cube"))
		G.RegisterItem(BG.BG_FindItem("Blue Cube"))
	end

	if G.g_gametype.integer == C.GT_DOUBLE_D then
		G.RegisterItem(BG.BG_FindItem("Point A (Blue)"))
		G.RegisterItem(BG.BG_FindItem("Point A (Red)"))
		G.RegisterItem(BG.BG_FindItem("Point A (White)"))
		G.RegisterItem(BG.BG_FindItem("Point B (Blue)"))
		G.RegisterItem(BG.BG_FindItem("Point B (Red)"))
		G.RegisterItem(BG.BG_FindItem("Point B (White)"))
	end

	if G.g_gametype.integer == C.GT_DOMINATION then
		G.RegisterItem(BG.BG_FindItem("Neutral domination point"))
		G.RegisterItem(BG.BG_FindItem("Red domination point"))
		G.RegisterItem(BG.BG_FindItem("Blue domination point"))
	end
end

--[[
===============
RegisterItem

The item will be added to the precache list
===============
]]
function G.RegisterItem(item)
	if item == nil then
		G.G_Error("RegisterItem: NULL")
	end
	G.itemRegistered[item.index] = true
end

--[[
===============
SaveRegisteredItems

Write the needed items to a config string
so the client will know which ones to precache
===============
]]
function G.SaveRegisteredItems()
	local chars = {}
	local count

	count = 0
	for i = 0, BG.bg_numItems - 1 do
		if G.itemRegistered[i] then
			count += 1
			chars[i + 1] = "1"
		else
			chars[i + 1] = "0"
		end
	end
	local str = table.concat(chars)
	G.G_Printf("%i items registered\n", count)
	G.trap_SetConfigstring(C.CS_ITEMS, str)
end

--[[
============
G_ItemDisabled
============
]]
function G.G_ItemDisabled(item)
	local name

	name = QS.Com_sprintf(128, "disable_%s", item.classname)
	return G.trap_Cvar_VariableIntegerValue(name)
end

--[[
============
G_SpawnItem

Sets the clipping size and plants the object on the floor.

Items can't be immediately dropped to floor, because they might
be on an entity that hasn't spawned yet.
============
]]
function G.G_SpawnItem(ent, item)
	local _
	_, ent.random = G.G_SpawnFloat("random", "0")
	_, ent.wait = G.G_SpawnFloat("wait", "0")

	if (item.giType == C.IT_TEAM and (G.g_instantgib.integer ~= 0 or G.g_rockets.integer ~= 0))
		or (G.g_instantgib.integer == 0 and G.g_rockets.integer == 0) then
		-- Don't load pickups in Elimination (or maybe... gives warnings)
		if G.g_gametype.integer ~= C.GT_ELIMINATION and G.g_gametype.integer ~= C.GT_CTF_ELIMINATION and G.g_gametype.integer ~= C.GT_LMS then
			G.RegisterItem(item)
		end
		-- Registrer flags anyway in CTF Elimination:
		if G.g_gametype.integer == C.GT_CTF_ELIMINATION and item.giType == C.IT_TEAM then
			G.RegisterItem(item)
		end
		if G.G_ItemDisabled(item) ~= 0 then
			return
		end
	end
	if G.g_persistantpowerups.integer == 0 and item.giType == C.IT_PERSISTANT_POWERUP then
		return
	end

	ent.item = item
	-- some movers spawn on the second frame, so delay item
	-- spawns until the third frame so they can ride trains
	ent.nextthink = G.level.time + C.FRAMETIME * 2
	ent.think = G.FinishSpawningItem

	ent.physicsBounce = 0.50 -- items are bouncy

	if G.g_gametype.integer == C.GT_ELIMINATION or G.g_gametype.integer == C.GT_LMS or
		(item.giType ~= C.IT_TEAM and (G.g_instantgib.integer ~= 0 or G.g_rockets.integer ~= 0 or G.g_elimination_allgametypes.integer ~= 0 or G.g_gametype.integer == C.GT_CTF_ELIMINATION)) then
		ent.s.eFlags = bit32.bor(ent.s.eFlags, C.EF_NODRAW) --Invisible in elimination
		ent.r.svFlags = bit32.bor(ent.r.svFlags, C.SVF_NOCLIENT) --Don't broadcast
	end

	if G.g_gametype.integer == C.GT_DOUBLE_D and (QS.Q_strequal(ent.classname, "team_CTF_redflag") or QS.Q_strequal(ent.classname, "team_CTF_blueflag")
		or QS.Q_strequal(ent.classname, "team_CTF_neutralflag") or item.giType == C.IT_PERSISTANT_POWERUP) then
		ent.s.eFlags = bit32.bor(ent.s.eFlags, C.EF_NODRAW) --Don't draw the flag models/persistant powerups
	end

	if G.g_gametype.integer ~= C.GT_1FCTF and QS.Q_strequal(ent.classname, "team_CTF_neutralflag") then
		ent.s.eFlags = bit32.bor(ent.s.eFlags, C.EF_NODRAW) -- Don't draw the flag in CTF_elimination
	end

	if QS.Q_strequal(ent.classname, "domination_point") then
		ent.s.eFlags = bit32.bor(ent.s.eFlags, C.EF_NODRAW) -- Don't draw domination_point. It is just a pointer to where the Domination points should be placed
	end
	if item.giType == C.IT_POWERUP then
		G.G_SoundIndex("sound/items/poweruprespawn.wav")
		_, ent.speed = G.G_SpawnFloat("noglobalsound", "0")
	end

	if item.giType == C.IT_PERSISTANT_POWERUP then
		ent.s.generic1 = ent.spawnflags
	end
end

--[[
================
G_BounceItem

================
]]
function G.G_BounceItem(ent, trace)
	local velocity = Q.vec3()
	local dot
	local hitTime

	-- reflect the velocity on the trace plane
	hitTime = Q.trunc(G.level.previousTime + (G.level.time - G.level.previousTime) * trace.fraction)
	BG.BG_EvaluateTrajectoryDelta(ent.s.pos, hitTime, velocity)
	dot = Q.DotProduct(velocity, trace.plane.normal)
	Q.VectorMA(velocity, -2 * dot, trace.plane.normal, ent.s.pos.trDelta)

	-- cut the velocity to keep from bouncing forever
	Q.VectorScale(ent.s.pos.trDelta, ent.physicsBounce, ent.s.pos.trDelta)

	-- check for stop
	if trace.plane.normal[2] > 0 and ent.s.pos.trDelta[2] < 40 then
		trace.endpos[2] += 1.0 -- make sure it is off ground
		Q.SnapVector(trace.endpos)
		G.G_SetOrigin(ent, trace.endpos)
		ent.s.groundEntityNum = trace.entityNum
		return
	end

	Q.VectorAdd(ent.r.currentOrigin, trace.plane.normal, ent.r.currentOrigin)
	Q.VectorCopy(ent.r.currentOrigin, ent.s.pos.trBase)
	ent.s.pos.trTime = G.level.time
end

--[[
================
G_RunItem

================
]]
function G.G_RunItem(ent)
	local origin = Q.vec3()
	local tr = S.trace_t()
	local contents
	local mask

	-- if groundentity has been set to -1, it may have been pushed off an edge
	if ent.s.groundEntityNum == -1 then
		if ent.s.pos.trType ~= C.TR_GRAVITY then
			ent.s.pos.trType = C.TR_GRAVITY
			ent.s.pos.trTime = G.level.time
		end
	end

	if ent.s.pos.trType == C.TR_STATIONARY then
		-- check think function
		G.G_RunThink(ent)
		return
	end

	-- get current position
	BG.BG_EvaluateTrajectory(ent.s.pos, G.level.time, origin)

	-- trace a line from the previous position to the current position
	if ent.clipmask ~= 0 then
		mask = ent.clipmask
	else
		mask = bit32.band(C.MASK_PLAYERSOLID, bit32.bnot(C.CONTENTS_BODY)) --MASK_SOLID;
	end
	G.trap_Trace(tr, ent.r.currentOrigin, ent.r.mins, ent.r.maxs, origin,
		ent.r.ownerNum, mask)

	Q.VectorCopy(tr.endpos, ent.r.currentOrigin)

	if tr.startsolid then
		tr.fraction = 0
	end

	G.trap_LinkEntity(ent) -- FIXME: avoid this for stationary?

	-- check think function
	G.G_RunThink(ent)

	if tr.fraction == 1 then
		return
	end

	-- if it is in a nodrop volume, remove it
	contents = G.trap_PointContents(ent.r.currentOrigin, -1)
	if bit32.band(contents, C.CONTENTS_NODROP) ~= 0 then
		if ent.item ~= nil and ent.item.giType == C.IT_TEAM then
			G.Team_FreeEntity(ent)
		else
			G.G_FreeEntity(ent)
		end
		return
	end

	G.G_BounceItem(ent, tr)
end

return nil
