--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Foobar; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/cgame/cg_weapons.c (OpenArena gamecode).
-- This part covers C lines 2266-3427 (CG_DrawWeaponSelect .. CG_OutOfAmmoChange).

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local trap = require(script.Parent.Parent.sys.Trap)

local function atoi(s: string): number
	local m = string.match(s, "^%s*([+-]?%d+)")
	return tonumber(m) or 0
end

-- Weapon order of the bars: the grapple (10) is drawn first.
local function barWeapons(bits: number): { number }
	local list = {}
	for i = 0, C.MAX_WEAPONS - 1 do
		if i ~= 10 then
			local j = i
			if i == 0 then
				j = 10
			end
			if bit32.band(bits, bit32.lshift(1, j)) ~= 0 then
				table.insert(list, j)
			end
		end
	end
	return list
end

local function maxAmmoFor(i: number): number
	if i == C.WP_MACHINEGUN then
		return 100
	elseif i == C.WP_SHOTGUN then
		return 10
	elseif i == C.WP_GRENADE_LAUNCHER then
		return 10
	elseif i == C.WP_ROCKET_LAUNCHER then
		return 10
	elseif i == C.WP_LIGHTNING then
		return 100
	elseif i == C.WP_RAILGUN then
		return 10
	elseif i == C.WP_PLASMAGUN then
		return 50
	elseif i == C.WP_BFG then
		return 10
	elseif i == C.WP_NAILGUN then
		return 10
	elseif i == C.WP_PROX_LAUNCHER then
		return 5
	elseif i == C.WP_CHAINGUN then
		return 100
	end
	return 1
end

local function col4(a: number, b: number, c: number, d: number)
	return { [0] = a, [1] = b, [2] = c, [3] = d }
end

local function drawAmmoNumber(x: number, y: number, i: number, color, offset: number)
	local ammo = G.cg.snap.ps.ammo[i]
	if ammo ~= -1 then
		local s = Q.va("%i", ammo)
		local w = G.CG_DrawStrlen(s) * C.SMALLCHAR_WIDTH
		G.CG_DrawSmallStringColor(x - Q.idiv(w, 2) + offset, y + (if offset == 32 then 4 else 20), s, color)
	end
end

function G.CG_DrawWeaponSelect()
	local cg = G.cg

	-- don't display if dead
	if cg.predictedPlayerState.stats[C.STAT_HEALTH] <= 0 then
		return
	end

	local color = G.CG_FadeColor(cg.weaponSelectTime, C.WEAPON_SELECT_TIME)

	--Elimination: Always show weapon bar
	if G.cg_alwaysWeaponBar.integer ~= 0 then
		color = col4(1.0, 1.0, 1.0, 1.0)
	end

	if color == nil then
		return
	end
	trap.R_SetColor(color)

	-- showing weapon select clears pickup item display, but not the blend blob
	cg.itemPickupTime = 0

	-- count the number of weapons owned
	local bits = cg.snap.ps.stats[C.STAT_WEAPONS]
	local count = 0
	for i = 1, C.MAX_WEAPONS - 1 do
		if bit32.band(bits, bit32.lshift(1, i)) ~= 0 then
			count += 1
		end
	end

	local style = G.cg_weaponBarStyle.integer
	if style == -1 then
		-- Don't display the weapon bar.
	elseif style == 1 then
		G.CG_DrawWeaponBar1(count, bits)
	elseif style == 2 then
		G.CG_DrawWeaponBar2(count, bits, color)
	elseif style == 3 then
		G.CG_DrawWeaponBar3(count, bits, color)
	elseif style == 4 then
		G.CG_DrawWeaponBar4(count, bits, color)
	elseif style == 5 then
		G.CG_DrawWeaponBar5(count, bits, color)
	elseif style == 6 then
		G.CG_DrawWeaponBar6(count, bits, color)
	elseif style == 7 then
		G.CG_DrawWeaponBar7(count, bits, color)
	else
		G.CG_DrawWeaponBar0(count, bits)
	end
	trap.R_SetColor(nil)
end

-- Default weapon bar. Displays only if a weapon has ammo or not (marked with an X).
function G.CG_DrawWeaponBar0(count: number, bits: number)
	local y = 380
	local x = 320 - count * 20

	for _, i in barWeapons(bits) do
		G.CG_RegisterWeapon(i)
		-- draw weapon icon
		G.CG_DrawPic(x, y, 32, 32, G.cg_weapons[i].weaponIcon)

		-- draw selection marker
		if i == G.cg.weaponSelect then
			G.CG_DrawPic(x - 4, y - 4, 40, 40, G.cgs.media.selectShader)
		end

		-- no ammo cross on top
		if G.cg.snap.ps.ammo[i] == 0 then
			G.CG_DrawPic(x, y, 32, 32, G.cgs.media.noammoShader)
		end

		x += 40
	end
end

-- Displays ammo left for the weapon below it with a bar.
function G.CG_DrawWeaponBar1(count: number, bits: number)
	local y = 380
	local x = 320 - count * 20
	local red = col4(1.0, 0, 0, 1.0)
	local yellow = col4(1.0, 0.6, 0, 1.0)
	local green = col4(0, 1.0, 0, 1.0)

	for _, i in barWeapons(bits) do
		local ammo = G.cg.snap.ps.ammo[i]
		local max = maxAmmoFor(i)

		ammo = Q.idiv(ammo * 100, max)
		if ammo >= 100 then
			ammo = 100
		end

		local br = Q.idiv(ammo * 32, 100)

		if i ~= C.WP_GAUNTLET and i ~= C.WP_GRAPPLING_HOOK then
			if ammo <= 20 then
				G.CG_FillRect(x, y + 38, br, 4, red)
			end
			if ammo > 20 and ammo <= 50 then
				G.CG_FillRect(x, y + 38, br, 4, yellow)
			end
			if ammo > 50 then
				G.CG_FillRect(x, y + 38, br, 4, green)
			end
		end

		G.CG_RegisterWeapon(i)
		G.CG_DrawPic(x, y, 32, 32, G.cg_weapons[i].weaponIcon)

		if i == G.cg.weaponSelect then
			G.CG_DrawPic(x - 4, y - 4, 40, 40, G.cgs.media.selectShader)
		end

		if G.cg.snap.ps.ammo[i] == 0 then
			G.CG_DrawPic(x, y, 32, 32, G.cgs.media.noammoShader)
		end

		x += 40
	end
end

-- Displays weapons in the left side of the screen with a number showing remaining ammo.
-- Weapons with less than 10 ammo units have a red-ish background.
function G.CG_DrawWeaponBar2(count: number, bits: number, color)
	local y = 200 + count * 12
	local x = 0
	local red = col4(1.0, 0, 0, 0.4)
	local yellow = col4(1.0, 1.0, 0, 1.0)
	local blue = col4(0, 0, 1.0, 0.4)

	for _, i in barWeapons(bits) do
		local bg = if G.cg.snap.ps.ammo[i] ~= 0 then blue else red
		G.CG_FillRect(x, y, 50, 24, bg)
		if i == G.cg.weaponSelect then
			G.CG_DrawRect(x, y, 50, 24, 2, yellow)
		end

		G.CG_RegisterWeapon(i)
		G.CG_DrawPic(x + 2, y + 4, 16, 16, G.cg_weapons[i].weaponIcon)

		drawAmmoNumber(x, y, i, color, 32)

		y -= 24
	end
end

-- Same as 2, but displays ammo left at the right of the number as a bar.
-- Weapons with less than 10 ammo units have a red-ish background and don't display the bar.
function G.CG_DrawWeaponBar3(count: number, bits: number, color)
	local y = 200 + count * 12
	local x = 0
	local red = col4(1.0, 0, 0, 0.4)
	local yellow = col4(1.0, 1.0, 0, 1.0)
	local green = col4(0, 1.0, 0, 1.0)
	local blue = col4(0, 0, 1.0, 0.4)

	for _, i in barWeapons(bits) do
		local ammo = G.cg.snap.ps.ammo[i]
		local max = maxAmmoFor(i)

		ammo = Q.idiv(ammo * 100, max)
		if ammo >= 100 then
			ammo = 100
		end

		local br = Q.idiv(ammo * 20, 100)

		if i ~= C.WP_GAUNTLET and i ~= C.WP_GRAPPLING_HOOK then
			if ammo <= 20 then
				G.CG_FillRect(51, y + 2 + 20 - br, 4, br, red)
			end
			if ammo > 20 and ammo <= 50 then
				G.CG_FillRect(51, y + 2 + 20 - br, 4, br, yellow)
			end
			if ammo > 50 then
				G.CG_FillRect(51, y + 2 + 20 - br, 4, br, green)
			end
		end

		local bg = if G.cg.snap.ps.ammo[i] ~= 0 then blue else red
		G.CG_FillRect(x, y, 50, 24, bg)
		if i == G.cg.weaponSelect then
			G.CG_DrawRect(x, y, 50, 24, 2, yellow)
		end
		G.CG_RegisterWeapon(i)
		G.CG_DrawPic(x + 2, y + 4, 16, 16, G.cg_weapons[i].weaponIcon)

		drawAmmoNumber(x, y, i, color, 32)

		y -= 24
	end
end

-- Apparently same as 2, even if the code is different. Weird.
function G.CG_DrawWeaponBar4(count: number, bits: number, color)
	local y = 200 + count * 12
	local x = 0
	local boxColor = col4(0, 0, 0, 0.4)
	local yellow = col4(1.0, 1.0, 0, 1.0)

	for _, i in barWeapons(bits) do
		local ammo = G.cg.snap.ps.ammo[i]
		local max = maxAmmoFor(i)

		ammo = (ammo * 100) / max

		if ammo >= 100 or ammo < 0 then
			ammo = 100
		end

		boxColor[2] = (ammo / 100.0) * 1.0
		boxColor[0] = 1.0 - (ammo / 100.0) * 1.0

		G.CG_FillRect(x, y, 50, 24, boxColor)
		if i == G.cg.weaponSelect then
			G.CG_DrawRect(x, y, 50, 24, 2, yellow)
		end
		G.CG_RegisterWeapon(i)
		G.CG_DrawPic(x + 2, y + 4, 16, 16, G.cg_weapons[i].weaponIcon)

		drawAmmoNumber(x, y, i, color, 32)

		y -= 24
	end
end

-- Weapons have a blue background and a number representing ammo.
-- Less than 10 ammo units have a red-ish background.
function G.CG_DrawWeaponBar5(count: number, bits: number, color)
	local y = 380
	local x = 320 - count * 15
	local red = col4(1.0, 0, 0, 0.4)
	local yellow = col4(1.0, 1.0, 0, 1.0)
	local blue = col4(0, 0, 1.0, 0.4)

	for _, i in barWeapons(bits) do
		local bg = if G.cg.snap.ps.ammo[i] ~= 0 then blue else red
		G.CG_FillRect(x, y, 30, 38, bg)
		if i == G.cg.weaponSelect then
			G.CG_DrawRect(x, y, 30, 38, 2, yellow)
		end
		G.CG_RegisterWeapon(i)
		G.CG_DrawPic(x + 7, y + 2, 16, 16, G.cg_weapons[i].weaponIcon)

		drawAmmoNumber(x, y, i, color, 15)

		x += 30
	end
end

-- Same as 5, but also displays a bar, except when there's no ammo.
function G.CG_DrawWeaponBar6(count: number, bits: number, color)
	local y = 380
	local x = 320 - count * 15
	local red = col4(1.0, 0, 0, 0.4)
	local yellow = col4(1.0, 1.0, 0, 1.0)
	local green = col4(0, 1.0, 0, 1.0)
	local blue = col4(0, 0, 1.0, 0.4)

	for _, i in barWeapons(bits) do
		local ammo = G.cg.snap.ps.ammo[i]
		local max = maxAmmoFor(i)

		ammo = Q.idiv(ammo * 100, max)

		if ammo >= 100 then
			ammo = 100
		end

		local br = Q.idiv(ammo * 26, 100)

		if i ~= C.WP_GAUNTLET and i ~= C.WP_GRAPPLING_HOOK then
			if ammo <= 20 then
				G.CG_FillRect(x + 2, y + 40, br, 4, red)
			end
			if ammo > 20 and ammo <= 50 then
				G.CG_FillRect(x + 2, y + 40, br, 4, yellow)
			end
			if ammo > 50 then
				G.CG_FillRect(x + 2, y + 40, br, 4, green)
			end
		end

		local bg = if G.cg.snap.ps.ammo[i] ~= 0 then blue else red
		G.CG_FillRect(x, y, 30, 38, bg)
		if i == G.cg.weaponSelect then
			G.CG_DrawRect(x, y, 30, 38, 2, yellow)
		end
		G.CG_RegisterWeapon(i)
		G.CG_DrawPic(x + 7, y + 2, 16, 16, G.cg_weapons[i].weaponIcon)

		drawAmmoNumber(x, y, i, color, 15)

		x += 30
	end
end

-- Apparently same as 5, even if the code is different. Weird.
function G.CG_DrawWeaponBar7(count: number, bits: number, color)
	local y = 380
	local x = 320 - count * 15
	local yellow = col4(1.0, 1.0, 0, 1.0)
	local boxColor = col4(0, 0, 0, 0.4)

	for _, i in barWeapons(bits) do
		local ammo = G.cg.snap.ps.ammo[i]
		local max = maxAmmoFor(i)

		ammo = (ammo * 100) / max

		if ammo >= 100 or ammo < 0 then
			ammo = 100
		end

		boxColor[2] = (ammo / 100.0) * 1.0
		boxColor[0] = 1.0 - (ammo / 100.0) * 1.0

		G.CG_FillRect(x, y, 30, 38, boxColor)
		if i == G.cg.weaponSelect then
			G.CG_DrawRect(x, y, 30, 38, 2, yellow)
		end
		G.CG_RegisterWeapon(i)
		G.CG_DrawPic(x + 7, y + 2, 16, 16, G.cg_weapons[i].weaponIcon)

		drawAmmoNumber(x, y, i, color, 15)

		x += 30
	end
end

function G.CG_WeaponSelectable(i: number): boolean
	local ammo = G.cg.snap.ps.ammo[i]
	if ammo == nil or ammo == 0 then
		return false
	end
	if bit32.band(G.cg.snap.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, i)) == 0 then
		return false
	end

	return true
end

-- Gives the best weapon with ammo based on cg_weaponOrder
-- If it cannot find a weapon WP_NONE is returned
function G.CG_GetBestWeapon(): number
	local ret = C.WP_NONE
	local order = G.cg_weaponOrder.string
	local pos = string.find(order, "/", 1, true)
	while pos ~= nil do
		local place = pos + 1
		local newWeaponNumber = atoi(string.sub(order, place))
		if G.CG_WeaponSelectable(newWeaponNumber) then
			ret = newWeaponNumber
		end
		pos = string.find(order, "/", place, true)
	end
	return ret
end

function G.CG_BestWeapon_f()
	local cg = G.cg
	if cg.snap == nil then
		return
	end
	if bit32.band(cg.snap.ps.pm_flags, C.PMF_FOLLOW) ~= 0 then
		return
	end

	local newW = G.CG_GetBestWeapon()
	if newW ~= C.WP_NONE then
		cg.weaponSelectTime = cg.time
		cg.weaponSelect = newW
	end
end

function G.CG_NextWeapon_f()
	local cg = G.cg
	if cg.snap == nil then
		return
	end
	if bit32.band(cg.snap.ps.pm_flags, C.PMF_FOLLOW) ~= 0 then
		return
	end

	cg.weaponSelectTime = cg.time
	local original = cg.weaponSelect
	--Part of mad hook select code:
	if cg.weaponSelect == C.WP_GRAPPLING_HOOK then
		cg.weaponSelect = 0
	end

	local i = 0
	while i < C.MAX_WEAPONS do
		cg.weaponSelect += 1
		if cg.weaponSelect == C.MAX_WEAPONS then
			cg.weaponSelect = 0
		end
		-- never cycle to gauntlet; Sago: mad change of grapple order
		if cg.weaponSelect ~= C.WP_GAUNTLET and cg.weaponSelect ~= C.WP_GRAPPLING_HOOK then
			if cg.weaponSelect == 0 then
				cg.weaponSelect = C.WP_GRAPPLING_HOOK
			end
			if cg.weaponSelect == C.WP_GRAPPLING_HOOK and G.cg_cyclegrapple.integer == 0 then
				-- never cycle to grapple unless the client wants it
				cg.weaponSelect = 0
			else
				if G.CG_WeaponSelectable(cg.weaponSelect) then
					break
				end
				if cg.weaponSelect == C.WP_GRAPPLING_HOOK then
					cg.weaponSelect = 0
				end
			end
		end
		i += 1
	end
	if i == C.MAX_WEAPONS then
		cg.weaponSelect = original
	end
end

function G.CG_PrevWeapon_f()
	local cg = G.cg
	if cg.snap == nil then
		return
	end
	if bit32.band(cg.snap.ps.pm_flags, C.PMF_FOLLOW) ~= 0 then
		return
	end

	cg.weaponSelectTime = cg.time
	local original = cg.weaponSelect
	--Part of mad hook select code:
	if cg.weaponSelect == C.WP_GRAPPLING_HOOK then
		cg.weaponSelect = 0
	end

	local i = 0
	while i < C.MAX_WEAPONS do
		cg.weaponSelect -= 1
		if cg.weaponSelect == -1 then
			cg.weaponSelect = C.MAX_WEAPONS - 1
		end
		-- never cycle to gauntlet; Sago: mad change of grapple order
		if cg.weaponSelect ~= C.WP_GAUNTLET and cg.weaponSelect ~= C.WP_GRAPPLING_HOOK then
			if cg.weaponSelect == 0 then
				cg.weaponSelect = C.WP_GRAPPLING_HOOK
			end
			if cg.weaponSelect == C.WP_GRAPPLING_HOOK and G.cg_cyclegrapple.integer == 0 then
				-- never cycle to grapple unless the client wants it
				cg.weaponSelect = 0
			else
				if G.CG_WeaponSelectable(cg.weaponSelect) then
					break
				end
				if cg.weaponSelect == C.WP_GRAPPLING_HOOK then
					cg.weaponSelect = 0
				end
			end
		end
		i += 1
	end
	if i == C.MAX_WEAPONS then
		cg.weaponSelect = original
	end
end

function G.CG_Weapon_f()
	local cg = G.cg
	if cg.snap == nil then
		return
	end
	if bit32.band(cg.snap.ps.pm_flags, C.PMF_FOLLOW) ~= 0 then
		return
	end

	local num = atoi(G.CG_Argv(1))

	if num < 1 or num > C.MAX_WEAPONS - 1 then
		return
	end

	cg.weaponSelectTime = cg.time

	if bit32.band(cg.snap.ps.stats[C.STAT_WEAPONS], bit32.lshift(1, num)) == 0 then
		return -- don't have the weapon
	end

	cg.weaponSelect = num
end

-- The current weapon has just run out of ammo
function G.CG_OutOfAmmoChange()
	local cg = G.cg
	cg.weaponSelectTime = cg.time
	cg.weaponSelect = G.CG_GetBestWeapon()
	if cg.weaponSelect == C.WP_NONE then
		for i = C.MAX_WEAPONS - 1, 1, -1 do
			if G.CG_WeaponSelectable(i) and i ~= C.WP_GRAPPLING_HOOK then
				cg.weaponSelect = i
				break
			end
		end
	end
end

return G
