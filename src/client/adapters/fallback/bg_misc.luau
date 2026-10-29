--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Open Arena source code.
Portions copied from Tremulous under GPL version 2 including any later version.

Open Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Open Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Open Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/game/bg_misc.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local clientRoot = script.Parent.Parent.Parent
local qFolder = clientRoot.q
local Q = require(qFolder.Q)
local C = require(qFolder.Consts)

local BG = {}

local function Com_Error(_level, msg)
	error(msg, 0)
end

local function strequal(a, b)
	return Q.stricmp(a, b) == 0
end

local function item(classname, sound, models, icon, pickup, quantity, giType, giTag, precaches, sounds)
	return {
		classname = classname or "",
		pickup_sound = sound or "",
		world_model = {
			[0] = models[1] or "",
			[1] = models[2] or "",
			[2] = models[3] or "",
			[3] = models[4] or "",
		},
		icon = icon or "",
		pickup_name = pickup or "",
		quantity = quantity,
		giType = giType,
		giTag = giTag,
		precaches = precaches or "",
		sounds = sounds or "",
	}
end

local list = {
	item(nil, nil, {}, nil, nil, 0, 0, 0, "", ""),
	item("item_armor_shard", "sound/misc/ar1_pkup.wav", { "models/powerups/armor/shard.md3", "models/powerups/armor/shard_sphere.md3" }, "icons/iconr_shard", "Armor Shard", 5, C.IT_ARMOR, 0),
	item("item_armor_combat", "sound/misc/ar2_pkup.wav", { "models/powerups/armor/armor_yel.md3" }, "icons/iconr_yellow", "Armor", 50, C.IT_ARMOR, 0),
	item("item_armor_body", "sound/misc/ar2_pkup.wav", { "models/powerups/armor/armor_red.md3" }, "icons/iconr_red", "Heavy Armor", 100, C.IT_ARMOR, 0),
	item("item_health_small", "sound/items/s_health.wav", { "models/powerups/health/small_cross.md3", "models/powerups/health/small_sphere.md3" }, "icons/iconh_green", "5 Health", 5, C.IT_HEALTH, 0),
	item("item_health", "sound/items/n_health.wav", { "models/powerups/health/medium_cross.md3", "models/powerups/health/medium_sphere.md3" }, "icons/iconh_yellow", "25 Health", 25, C.IT_HEALTH, 0),
	item("item_health_large", "sound/items/l_health.wav", { "models/powerups/health/large_cross.md3", "models/powerups/health/large_sphere.md3" }, "icons/iconh_red", "50 Health", 50, C.IT_HEALTH, 0),
	item("item_health_mega", "sound/items/m_health.wav", { "models/powerups/health/mega_cross.md3", "models/powerups/health/mega_sphere.md3" }, "icons/iconh_mega", "Mega Health", 100, C.IT_HEALTH, 0),

	item("weapon_gauntlet", "sound/misc/w_pkup.wav", { "models/weapons2/gauntlet/gauntlet.md3" }, "icons/iconw_gauntlet", "Gauntlet", 0, C.IT_WEAPON, C.WP_GAUNTLET),
	item("weapon_shotgun", "sound/misc/w_pkup.wav", { "models/weapons2/shotgun/shotgun.md3" }, "icons/iconw_shotgun", "Shotgun", 10, C.IT_WEAPON, C.WP_SHOTGUN),
	item("weapon_machinegun", "sound/misc/w_pkup.wav", { "models/weapons2/machinegun/machinegun.md3" }, "icons/iconw_machinegun", "Machinegun", 40, C.IT_WEAPON, C.WP_MACHINEGUN),
	item("weapon_grenadelauncher", "sound/misc/w_pkup.wav", { "models/weapons2/grenadel/grenadel.md3" }, "icons/iconw_grenade", "Grenade Launcher", 10, C.IT_WEAPON, C.WP_GRENADE_LAUNCHER, "", "sound/weapons/grenade/hgrenb1a.wav sound/weapons/grenade/hgrenb2a.wav"),
	item("weapon_rocketlauncher", "sound/misc/w_pkup.wav", { "models/weapons2/rocketl/rocketl.md3" }, "icons/iconw_rocket", "Rocket Launcher", 10, C.IT_WEAPON, C.WP_ROCKET_LAUNCHER),
	item("weapon_lightning", "sound/misc/w_pkup.wav", { "models/weapons2/lightning/lightning.md3" }, "icons/iconw_lightning", "Lightning Gun", 100, C.IT_WEAPON, C.WP_LIGHTNING),
	item("weapon_railgun", "sound/misc/w_pkup.wav", { "models/weapons2/railgun/railgun.md3" }, "icons/iconw_railgun", "Railgun", 10, C.IT_WEAPON, C.WP_RAILGUN),
	item("weapon_plasmagun", "sound/misc/w_pkup.wav", { "models/weapons2/plasma/plasma.md3" }, "icons/iconw_plasma", "Plasma Gun", 50, C.IT_WEAPON, C.WP_PLASMAGUN),
	item("weapon_bfg", "sound/misc/w_pkup.wav", { "models/weapons2/bfg/bfg.md3" }, "icons/iconw_bfg", "BFG10K", 20, C.IT_WEAPON, C.WP_BFG),
	item("weapon_grapplinghook", "sound/misc/w_pkup.wav", { "models/weapons2/grapple/grapple.md3" }, "icons/iconw_grapple", "Grappling Hook", 0, C.IT_WEAPON, C.WP_GRAPPLING_HOOK),

	item("ammo_shells", "sound/misc/am_pkup.wav", { "models/powerups/ammo/shotgunam.md3" }, "icons/icona_shotgun", "Shells", 10, C.IT_AMMO, C.WP_SHOTGUN),
	item("ammo_bullets", "sound/misc/am_pkup.wav", { "models/powerups/ammo/machinegunam.md3" }, "icons/icona_machinegun", "Bullets", 50, C.IT_AMMO, C.WP_MACHINEGUN),
	item("ammo_grenades", "sound/misc/am_pkup.wav", { "models/powerups/ammo/grenadeam.md3" }, "icons/icona_grenade", "Grenades", 5, C.IT_AMMO, C.WP_GRENADE_LAUNCHER),
	item("ammo_cells", "sound/misc/am_pkup.wav", { "models/powerups/ammo/plasmaam.md3" }, "icons/icona_plasma", "Cells", 30, C.IT_AMMO, C.WP_PLASMAGUN),
	item("ammo_lightning", "sound/misc/am_pkup.wav", { "models/powerups/ammo/lightningam.md3" }, "icons/icona_lightning", "Lightning", 60, C.IT_AMMO, C.WP_LIGHTNING),
	item("ammo_rockets", "sound/misc/am_pkup.wav", { "models/powerups/ammo/rocketam.md3" }, "icons/icona_rocket", "Rockets", 5, C.IT_AMMO, C.WP_ROCKET_LAUNCHER),
	item("ammo_slugs", "sound/misc/am_pkup.wav", { "models/powerups/ammo/railgunam.md3" }, "icons/icona_railgun", "Slugs", 10, C.IT_AMMO, C.WP_RAILGUN),
	item("ammo_bfg", "sound/misc/am_pkup.wav", { "models/powerups/ammo/bfgam.md3" }, "icons/icona_bfg", "Bfg Ammo", 15, C.IT_AMMO, C.WP_BFG),

	item("holdable_teleporter", "sound/items/holdable.wav", { "models/powerups/holdable/teleporter.md3" }, "icons/teleporter", "Personal Teleporter", 60, C.IT_HOLDABLE, C.HI_TELEPORTER),
	item("holdable_medkit", "sound/items/holdable.wav", { "models/powerups/holdable/medkit.md3", "models/powerups/holdable/medkit_sphere.md3" }, "icons/medkit", "Medkit", 60, C.IT_HOLDABLE, C.HI_MEDKIT, "", "sound/items/use_medkit.wav"),

	item("item_quad", "sound/items/quaddamage.wav", { "models/powerups/instant/quad.md3", "models/powerups/instant/quad_ring.md3" }, "icons/quad", "Quad Damage", 30, C.IT_POWERUP, C.PW_QUAD, "", "sound/items/damage2.wav sound/items/damage3.wav"),
	item("item_enviro", "sound/items/protect.wav", { "models/powerups/instant/enviro.md3", "models/powerups/instant/enviro_ring.md3" }, "icons/envirosuit", "Battle Suit", 30, C.IT_POWERUP, C.PW_BATTLESUIT, "", "sound/items/airout.wav sound/items/protect3.wav"),
	item("item_haste", "sound/items/haste.wav", { "models/powerups/instant/haste.md3", "models/powerups/instant/haste_ring.md3" }, "icons/haste", "Speed", 30, C.IT_POWERUP, C.PW_HASTE),
	item("item_invis", "sound/items/invisibility.wav", { "models/powerups/instant/invis.md3", "models/powerups/instant/invis_ring.md3" }, "icons/invis", "Invisibility", 30, C.IT_POWERUP, C.PW_INVIS),
	item("item_regen", "sound/items/regeneration.wav", { "models/powerups/instant/regen.md3", "models/powerups/instant/regen_ring.md3" }, "icons/regen", "Regeneration", 30, C.IT_POWERUP, C.PW_REGEN, "", "sound/items/regen.wav"),
	item("item_flight", "sound/items/flight.wav", { "models/powerups/instant/flight.md3", "models/powerups/instant/flight_ring.md3" }, "icons/flight", "Flight", 60, C.IT_POWERUP, C.PW_FLIGHT, "", "sound/items/flight.wav"),

	item("team_CTF_redflag", nil, { "models/flags/r_flag.md3" }, "icons/iconf_red1", "Red Flag", 0, C.IT_TEAM, C.PW_REDFLAG),
	item("team_CTF_blueflag", nil, { "models/flags/b_flag.md3" }, "icons/iconf_blu1", "Blue Flag", 0, C.IT_TEAM, C.PW_BLUEFLAG),

	item("holdable_kamikaze", "sound/items/holdable.wav", { "models/powerups/kamikazi.md3" }, "icons/kamikaze", "Kamikaze", 60, C.IT_HOLDABLE, C.HI_KAMIKAZE, "", "sound/items/kamikazerespawn.wav"),
	item("holdable_portal", "sound/items/holdable.wav", { "models/powerups/holdable/porter.md3" }, "icons/portal", "Portal", 60, C.IT_HOLDABLE, C.HI_PORTAL),
	item("holdable_invulnerability", "sound/items/holdable.wav", { "models/powerups/holdable/invulnerability.md3" }, "icons/invulnerability", "Invulnerability", 60, C.IT_HOLDABLE, C.HI_INVULNERABILITY),

	item("ammo_nails", "sound/misc/am_pkup.wav", { "models/powerups/ammo/nailgunam.md3" }, "icons/icona_nailgun", "Nails", 20, C.IT_AMMO, C.WP_NAILGUN),
	item("ammo_mines", "sound/misc/am_pkup.wav", { "models/powerups/ammo/proxmineam.md3" }, "icons/icona_proxlauncher", "Proximity Mines", 10, C.IT_AMMO, C.WP_PROX_LAUNCHER),
	item("ammo_belt", "sound/misc/am_pkup.wav", { "models/powerups/ammo/chaingunam.md3" }, "icons/icona_chaingun", "Chaingun Belt", 100, C.IT_AMMO, C.WP_CHAINGUN),

	item("item_scout", "sound/items/scout.wav", { "models/powerups/scout.md3" }, "icons/scout", "Scout", 30, C.IT_PERSISTANT_POWERUP, C.PW_SCOUT),
	item("item_guard", "sound/items/guard.wav", { "models/powerups/guard.md3" }, "icons/guard", "Guard", 30, C.IT_PERSISTANT_POWERUP, C.PW_GUARD),
	item("item_doubler", "sound/items/doubler.wav", { "models/powerups/doubler.md3" }, "icons/doubler", "Doubler", 30, C.IT_PERSISTANT_POWERUP, C.PW_DOUBLER),
	item("item_ammoregen", "sound/items/ammoregen.wav", { "models/powerups/ammo.md3" }, "icons/ammo_regen", "Ammo Regen", 30, C.IT_PERSISTANT_POWERUP, C.PW_AMMOREGEN),

	item("team_CTF_neutralflag", nil, { "models/flags/n_flag.md3" }, "icons/iconf_neutral1", "Neutral Flag", 0, C.IT_TEAM, C.PW_NEUTRALFLAG),
	item("item_redcube", "sound/misc/am_pkup.wav", { "models/powerups/orb/r_orb.md3" }, "icons/iconh_rorb", "Red Cube", 0, C.IT_TEAM, 0),
	item("item_bluecube", "sound/misc/am_pkup.wav", { "models/powerups/orb/b_orb.md3" }, "icons/iconh_borb", "Blue Cube", 0, C.IT_TEAM, 0),

	item("weapon_nailgun", "sound/misc/w_pkup.wav", { "models/weapons/nailgun/nailgun.md3" }, "icons/iconw_nailgun", "Nailgun", 10, C.IT_WEAPON, C.WP_NAILGUN),
	item("weapon_prox_launcher", "sound/misc/w_pkup.wav", { "models/weapons/proxmine/proxmine.md3" }, "icons/iconw_proxlauncher", "Prox Launcher", 5, C.IT_WEAPON, C.WP_PROX_LAUNCHER,
		"", "sound/weapons/proxmine/wstbtick.wav sound/weapons/proxmine/wstbactv.wav sound/weapons/proxmine/wstbimpl.wav sound/weapons/proxmine/wstbimpm.wav sound/weapons/proxmine/wstbimpd.wav sound/weapons/proxmine/wstbactv.wav"),
	item("weapon_chaingun", "sound/misc/w_pkup.wav", { "models/weapons/vulcan/vulcan.md3" }, "icons/iconw_chaingun", "Chaingun", 80, C.IT_WEAPON, C.WP_CHAINGUN, "", "sound/weapons/vulcan/wvulwind.wav"),

	item("team_DD_pointAblue", nil, { "models/dpoints/a_blue.md3" }, "icons/icona_blue", "Point A (Blue)", 0, C.IT_TEAM, C.DD_POINTABLUE),
	item("team_DD_pointBblue", nil, { "models/dpoints/b_blue.md3" }, "icons/iconb_blue", "Point B (Blue)", 0, C.IT_TEAM, C.DD_POINTBBLUE),
	item("team_DD_pointAred", nil, { "models/dpoints/a_red.md3" }, "icons/icona_red", "Point A (Red)", 0, C.IT_TEAM, C.DD_POINTARED),
	item("team_DD_pointBred", nil, { "models/dpoints/b_red.md3" }, "icons/iconb_red", "Point B (Red)", 0, C.IT_TEAM, C.DD_POINTBRED),
	item("team_DD_pointAwhite", nil, { "models/dpoints/a_white.md3" }, "icons/icona_white", "Point A (White)", 0, C.IT_TEAM, C.DD_POINTAWHITE),
	item("team_DD_pointBwhite", nil, { "models/dpoints/b_white.md3" }, "icons/iconb_white", "Point B (White)", 0, C.IT_TEAM, C.DD_POINTBWHITE),

	item("team_dom_pointWhite", nil, { "models/flags/n_flag.md3" }, "icons/iconf_neutral1", "Neutral domination point", 0, C.IT_TEAM, C.DOM_POINTWHITE),
	item("team_dom_pointRed", nil, { "models/flags/r_flag.md3" }, "icons/iconf_red1", "Red domination point", 0, C.IT_TEAM, C.DOM_POINTRED),
	item("team_dom_pointBlue", nil, { "models/flags/b_flag.md3" }, "icons/iconf_blu1", "Blue domination point", 0, C.IT_TEAM, C.DOM_POINTBLUE),
}

local bg_itemlist = {}
for i, it in ipairs(list) do
	it.index = i - 1
	bg_itemlist[i - 1] = it
end

-- end of list marker
local endMarker = item(nil, nil, {}, nil, nil, 0, 0, 0, "", "")
endMarker.index = #list
bg_itemlist[#list] = endMarker

BG.bg_itemlist = bg_itemlist
BG.bg_numItems = #list

function BG.BG_FindItemForPowerup(pw)
	for i = 0, BG.bg_numItems - 1 do
		local it = bg_itemlist[i]
		if (it.giType == C.IT_POWERUP or it.giType == C.IT_TEAM or it.giType == C.IT_PERSISTANT_POWERUP) and it.giTag == pw then
			return it
		end
	end
	return nil
end

function BG.BG_FindItemForHoldable(pw)
	for i = 0, BG.bg_numItems - 1 do
		local it = bg_itemlist[i]
		if it.giType == C.IT_HOLDABLE and it.giTag == pw then
			return it
		end
	end
	Com_Error(C.ERR_DROP, "HoldableItem not found")
	return nil
end

function BG.BG_FindItemForWeapon(weapon)
	for i = 1, BG.bg_numItems - 1 do
		local it = bg_itemlist[i]
		if it.giType == C.IT_WEAPON and it.giTag == weapon then
			return it
		end
	end
	Com_Error(C.ERR_DROP, string.format("Couldn't find item for weapon %d", weapon))
	return nil
end

function BG.BG_FindItem(pickupName)
	for i = 1, BG.bg_numItems - 1 do
		local it = bg_itemlist[i]
		if strequal(it.pickup_name, pickupName) then
			return it
		end
	end
	return nil
end

function BG.BG_EvaluateTrajectory(tr, atTime, result)
	local t = tr.trType
	local base, delta = tr.trBase, tr.trDelta
	if t == C.TR_STATIONARY or t == C.TR_INTERPOLATE then
		result[0], result[1], result[2] = base[0], base[1], base[2]
	elseif t == C.TR_LINEAR then
		local dt = (atTime - tr.trTime) * 0.001
		result[0] = base[0] + delta[0] * dt
		result[1] = base[1] + delta[1] * dt
		result[2] = base[2] + delta[2] * dt
	elseif t == C.TR_SINE then
		local dt = (atTime - tr.trTime) / tr.trDuration
		local phase = math.sin(dt * math.pi * 2)
		result[0] = base[0] + delta[0] * phase
		result[1] = base[1] + delta[1] * phase
		result[2] = base[2] + delta[2] * phase
	elseif t == C.TR_LINEAR_STOP then
		if atTime > tr.trTime + tr.trDuration then
			atTime = tr.trTime + tr.trDuration
		end
		local dt = (atTime - tr.trTime) * 0.001
		if dt < 0 then
			dt = 0
		end
		result[0] = base[0] + delta[0] * dt
		result[1] = base[1] + delta[1] * dt
		result[2] = base[2] + delta[2] * dt
	elseif t == C.TR_GRAVITY then
		local dt = (atTime - tr.trTime) * 0.001
		result[0] = base[0] + delta[0] * dt
		result[1] = base[1] + delta[1] * dt
		result[2] = base[2] + delta[2] * dt
		result[2] = result[2] - 0.5 * C.DEFAULT_GRAVITY * dt * dt
	else
		Com_Error(C.ERR_DROP, string.format("BG_EvaluateTrajectory: unknown trType: %d", tr.trTime))
	end
end

function BG.BG_EvaluateTrajectoryDelta(tr, atTime, result)
	local t = tr.trType
	local delta = tr.trDelta
	if t == C.TR_STATIONARY or t == C.TR_INTERPOLATE then
		result[0], result[1], result[2] = 0, 0, 0
	elseif t == C.TR_LINEAR then
		result[0], result[1], result[2] = delta[0], delta[1], delta[2]
	elseif t == C.TR_SINE then
		local dt = (atTime - tr.trTime) / tr.trDuration
		local phase = math.cos(dt * math.pi * 2)
		phase = phase * 0.5
		result[0], result[1], result[2] = delta[0] * phase, delta[1] * phase, delta[2] * phase
	elseif t == C.TR_LINEAR_STOP then
		if atTime > tr.trTime + tr.trDuration then
			result[0], result[1], result[2] = 0, 0, 0
			return
		end
		result[0], result[1], result[2] = delta[0], delta[1], delta[2]
	elseif t == C.TR_GRAVITY then
		local dt = (atTime - tr.trTime) * 0.001
		result[0], result[1], result[2] = delta[0], delta[1], delta[2]
		result[2] = result[2] - C.DEFAULT_GRAVITY * dt
	else
		Com_Error(C.ERR_DROP, string.format("BG_EvaluateTrajectoryDelta: unknown trType: %d", tr.trTime))
	end
end

-- Items can be picked up without actually touching their physical bounds
function BG.BG_PlayerTouchesItem(ps, it, atTime)
	local origin = Q.vec3(0, 0, 0)
	BG.BG_EvaluateTrajectory(it.pos, atTime, origin)

	-- we are ignoring ducked differences here
	if ps.origin[0] - origin[0] > 44
		or ps.origin[0] - origin[0] < -50
		or ps.origin[1] - origin[1] > 36
		or ps.origin[1] - origin[1] < -36
		or ps.origin[2] - origin[2] > 36
		or ps.origin[2] - origin[2] < -36 then
		return false
	end
	return true
end

-- Returns false if the item should not be picked up.
-- This needs to be the same for client side prediction and server use.
function BG.BG_CanItemBeGrabbed(gametype, ent, ps)
	if ent.modelindex < 1 or ent.modelindex >= BG.bg_numItems then
		Com_Error(C.ERR_DROP, "BG_CanItemBeGrabbed: index out of range")
	end

	local it = bg_itemlist[ent.modelindex]
	local giType = it.giType
	local stats = ps.stats
	local persTag = bg_itemlist[stats[C.STAT_PERSISTANT_POWERUP]].giTag

	if giType == C.IT_WEAPON then
		return true
	elseif giType == C.IT_AMMO then
		if ps.ammo[it.giTag] >= 200 then
			return false
		end
		return true
	elseif giType == C.IT_ARMOR then
		if persTag == C.PW_SCOUT then
			return false
		end
		local upperBound
		if persTag == C.PW_GUARD then
			upperBound = stats[C.STAT_MAX_HEALTH]
		else
			upperBound = stats[C.STAT_MAX_HEALTH] * 2
		end
		if stats[C.STAT_ARMOR] >= upperBound then
			return false
		end
		return true
	elseif giType == C.IT_HEALTH then
		-- small and mega healths will go over the max, otherwise
		-- don't pick up if already at max
		if persTag ~= C.PW_GUARD and (it.quantity == 5 or it.quantity == 100) then
			if stats[C.STAT_HEALTH] >= stats[C.STAT_MAX_HEALTH] * 2 then
				return false
			end
			return true
		end
		if stats[C.STAT_HEALTH] >= stats[C.STAT_MAX_HEALTH] then
			return false
		end
		return true
	elseif giType == C.IT_POWERUP then
		return true
	elseif giType == C.IT_PERSISTANT_POWERUP then
		if gametype == C.GT_DOUBLE_D then
			return false
		end
		-- can only hold one item at a time
		if stats[C.STAT_PERSISTANT_POWERUP] ~= 0 then
			return false
		end
		-- check team only
		if bit32.band(ent.generic1, 2) ~= 0 and ps.persistant[C.PERS_TEAM] ~= C.TEAM_RED then
			return false
		end
		if bit32.band(ent.generic1, 4) ~= 0 and ps.persistant[C.PERS_TEAM] ~= C.TEAM_BLUE then
			return false
		end
		return true
	elseif giType == C.IT_TEAM then
		local tag = it.giTag
		local team = ps.persistant[C.PERS_TEAM]
		if gametype == C.GT_1FCTF then
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
				if tag == C.PW_BLUEFLAG
					or (tag == C.PW_REDFLAG and ent.modelindex2 ~= 0)
					or (tag == C.PW_REDFLAG and ps.powerups[C.PW_BLUEFLAG] ~= 0) then
					return true
				end
			elseif team == C.TEAM_BLUE then
				if tag == C.PW_REDFLAG
					or (tag == C.PW_BLUEFLAG and ent.modelindex2 ~= 0)
					or (tag == C.PW_BLUEFLAG and ps.powerups[C.PW_REDFLAG] ~= 0) then
					return true
				end
			end
		end
		if gametype == C.GT_DOUBLE_D then
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
	elseif giType == C.IT_HOLDABLE then
		if stats[C.STAT_HOLDABLE_ITEM] ~= 0 then
			return false
		end
		return true
	elseif giType == C.IT_BAD then
		Com_Error(C.ERR_DROP, "BG_CanItemBeGrabbed: IT_BAD")
	end
	return false
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
	"EV_USE_ITEM0", "EV_USE_ITEM1", "EV_USE_ITEM2", "EV_USE_ITEM3", "EV_USE_ITEM4",
	"EV_USE_ITEM5", "EV_USE_ITEM6", "EV_USE_ITEM7", "EV_USE_ITEM8", "EV_USE_ITEM9",
	"EV_USE_ITEM10", "EV_USE_ITEM11", "EV_USE_ITEM12", "EV_USE_ITEM13", "EV_USE_ITEM14", "EV_USE_ITEM15",
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
function BG.BG_AddPredictableEventToPlayerstate(newEvent, eventParm, ps)
	local slot = bit32.band(ps.eventSequence, C.MAX_PS_EVENTS - 1)
	ps.events[slot] = newEvent
	ps.eventParms[slot] = eventParm
	ps.eventSequence = ps.eventSequence + 1
end

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
		local angles = Q.vec3(0, 0, 0)
		Q.vectoangles(jumppad.origin2, angles)
		local p = math.abs(Q.AngleNormalize180(angles[C.PITCH]))
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
	local o2 = jumppad.origin2
	ps.velocity[0], ps.velocity[1], ps.velocity[2] = o2[0], o2[1], o2[2]
end

local function roundEven(x)
	local f = math.floor(x)
	local d = x - f
	if d < 0.5 then
		return f
	elseif d > 0.5 then
		return f + 1
	end
	return f % 2 == 0 and f or f + 1
end

local function snapVector(v)
	v[0], v[1], v[2] = roundEven(v[0]), roundEven(v[1]), roundEven(v[2])
end

local function playerStateToEntityState(ps, s, snap, extrapolateTime)
	if ps.pm_type == C.PM_INTERMISSION or ps.pm_type == C.PM_SPECTATOR then
		s.eType = C.ET_INVISIBLE
	elseif ps.stats[C.STAT_HEALTH] <= C.GIB_HEALTH then
		s.eType = C.ET_INVISIBLE
	else
		s.eType = C.ET_PLAYER
	end

	s.number = ps.clientNum

	local pos = s.pos
	local o, v = ps.origin, ps.velocity
	pos.trBase[0], pos.trBase[1], pos.trBase[2] = o[0], o[1], o[2]
	if snap then
		snapVector(pos.trBase)
	end
	pos.trDelta[0], pos.trDelta[1], pos.trDelta[2] = v[0], v[1], v[2]
	if extrapolateTime ~= nil then
		pos.trType = C.TR_LINEAR_STOP
		pos.trTime = extrapolateTime
		pos.trDuration = 50
	else
		pos.trType = C.TR_INTERPOLATE
	end

	local apos = s.apos
	local va = ps.viewangles
	apos.trType = C.TR_INTERPOLATE
	apos.trBase[0], apos.trBase[1], apos.trBase[2] = va[0], va[1], va[2]
	if snap then
		snapVector(apos.trBase)
	end

	s.angles2[C.YAW] = ps.movementDir
	s.legsAnim = ps.legsAnim
	s.torsoAnim = ps.torsoAnim
	s.clientNum = ps.clientNum
	s.eFlags = ps.eFlags
	if ps.stats[C.STAT_HEALTH] <= 0 then
		s.eFlags = bit32.bor(s.eFlags, C.EF_DEAD)
	else
		s.eFlags = bit32.band(s.eFlags, bit32.bnot(C.EF_DEAD))
	end

	if ps.externalEvent ~= 0 then
		s.event = ps.externalEvent
		s.eventParm = ps.externalEventParm
	elseif ps.entityEventSequence < ps.eventSequence then
		if ps.entityEventSequence < ps.eventSequence - C.MAX_PS_EVENTS then
			ps.entityEventSequence = ps.eventSequence - C.MAX_PS_EVENTS
		end
		local seq = bit32.band(ps.entityEventSequence, C.MAX_PS_EVENTS - 1)
		s.event = bit32.bor(ps.events[seq], bit32.lshift(bit32.band(ps.entityEventSequence, 3), 8))
		s.eventParm = ps.eventParms[seq]
		ps.entityEventSequence = ps.entityEventSequence + 1
	end

	s.weapon = ps.weapon
	s.groundEntityNum = ps.groundEntityNum

	s.powerups = 0
	for i = 0, C.MAX_POWERUPS - 1 do
		if ps.powerups[i] ~= 0 then
			s.powerups = bit32.bor(s.powerups, bit32.lshift(1, i))
		end
	end

	s.loopSound = ps.loopSound
	s.generic1 = ps.generic1
end

-- This is done after each set of usercmd_t on the server,
-- and after local prediction on the client
function BG.BG_PlayerStateToEntityState(ps, s, snap)
	playerStateToEntityState(ps, s, snap, nil)
end

function BG.BG_PlayerStateToEntityStateExtraPolate(ps, s, time, snap)
	playerStateToEntityState(ps, s, snap, time)
end

function BG.BG_TeamName(team)
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
