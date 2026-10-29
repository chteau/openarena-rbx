--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_weap.c).

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
-- Luau port of be_ai_weap.c. Weapon AI.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local BOTFILESBASEFOLDER = "botfiles"

local function fdef(name, ftype, maxarray)
	local fd = SB.fielddef_t()
	fd.name = name
	fd.offset = 0
	fd.type = ftype
	fd.maxarray = maxarray or 0
	return fd
end

local FLOAT_ARRAY = bit32.bor(BC.FT_FLOAT, BC.FT_ARRAY)

--weapon definition
local weaponinfo_fields = {
	[0] = fdef("number", BC.FT_INT),
	fdef("name", BC.FT_STRING),
	fdef("level", BC.FT_INT),
	fdef("model", BC.FT_STRING),
	fdef("weaponindex", BC.FT_INT),
	fdef("flags", BC.FT_INT),
	fdef("projectile", BC.FT_STRING),
	fdef("numprojectiles", BC.FT_INT),
	fdef("hspread", BC.FT_FLOAT),
	fdef("vspread", BC.FT_FLOAT),
	fdef("speed", BC.FT_FLOAT),
	fdef("acceleration", BC.FT_FLOAT),
	fdef("recoil", FLOAT_ARRAY, 3),
	fdef("offset", FLOAT_ARRAY, 3),
	fdef("angleoffset", FLOAT_ARRAY, 3),
	fdef("extrazvelocity", BC.FT_FLOAT),
	fdef("ammoamount", BC.FT_INT),
	fdef("ammoindex", BC.FT_INT),
	fdef("activate", BC.FT_FLOAT),
	fdef("reload", BC.FT_FLOAT),
	fdef("spinup", BC.FT_FLOAT),
	fdef("spindown", BC.FT_FLOAT),
	SB.fielddef_t(),
}

--projectile definition
local projectileinfo_fields = {
	[0] = fdef("name", BC.FT_STRING),
	fdef("model", BC.FT_STRING),
	fdef("flags", BC.FT_INT),
	fdef("gravity", BC.FT_FLOAT),
	fdef("damage", BC.FT_INT),
	fdef("radius", BC.FT_FLOAT),
	fdef("visdamage", BC.FT_INT),
	fdef("damagetype", BC.FT_INT),
	fdef("healthinc", BC.FT_INT),
	fdef("push", BC.FT_FLOAT),
	fdef("detonation", BC.FT_FLOAT),
	fdef("bounce", BC.FT_FLOAT),
	fdef("bouncefric", BC.FT_FLOAT),
	fdef("bouncestop", BC.FT_FLOAT),
	SB.fielddef_t(),
}

local weaponinfo_struct = SB.structdef_t()
weaponinfo_struct.size = 0
weaponinfo_struct.fields = weaponinfo_fields

local projectileinfo_struct = SB.structdef_t()
projectileinfo_struct.size = 0
projectileinfo_struct.fields = projectileinfo_fields

local botweaponstates = {}
local weaponconfig = nil

function B.BotValidWeaponNumber(weaponnum)
	if weaponnum <= 0 or weaponnum > weaponconfig.numweapons then
		B.botimport.Print(BC.PRT_ERROR, "weapon number out of range\n")
		return 0
	end
	return 1
end

function B.BotWeaponStateFromHandle(handle)
	if handle <= 0 or handle > BC.MAX_CLIENTS then
		B.botimport.Print(BC.PRT_FATAL, "weapon state handle %d out of range\n", handle)
		return nil
	end
	if botweaponstates[handle] == nil then
		B.botimport.Print(BC.PRT_FATAL, "invalid weapon state %d\n", handle)
		return nil
	end
	return botweaponstates[handle]
end

function B.LoadWeaponConfig(filename)
	local max_weaponinfo = Q.trunc(B.LibVarValue("max_weaponinfo", "32"))
	if max_weaponinfo < 0 then
		B.botimport.Print(BC.PRT_ERROR, "max_weaponinfo = %d\n", max_weaponinfo)
		max_weaponinfo = 32
		B.LibVarSet("max_weaponinfo", "32")
	end
	local max_projectileinfo = Q.trunc(B.LibVarValue("max_projectileinfo", "32"))
	if max_projectileinfo < 0 then
		B.botimport.Print(BC.PRT_ERROR, "max_projectileinfo = %d\n", max_projectileinfo)
		max_projectileinfo = 32
		B.LibVarSet("max_projectileinfo", "32")
	end
	local path = QS.Q_strncpyz(filename, BC.MAX_QPATH)
	B.PC_SetBaseFolder(BOTFILESBASEFOLDER)
	local source = B.LoadSourceFile(path)
	if source == nil then
		B.botimport.Print(BC.PRT_ERROR, "couldn't load %s\n", path)
		return nil
	end
	--initialize weapon config
	local wc = SB.weaponconfig_t()
	wc.weaponinfo = {}
	for i = 0, max_weaponinfo - 1 do
		wc.weaponinfo[i] = SB.weaponinfo_t()
	end
	wc.projectileinfo = {}
	for i = 0, max_projectileinfo - 1 do
		wc.projectileinfo[i] = SB.projectileinfo_t()
	end
	wc.numweapons = max_weaponinfo
	wc.numprojectiles = 0
	local token = SB.token_t()
	--parse the source file
	while B.PC_ReadToken(source, token) ~= 0 do
		if token.string == "weaponinfo" then
			local weaponinfo = SB.weaponinfo_t()
			if B.ReadStructure(source, weaponinfo_struct, weaponinfo) == 0 then
				B.FreeSource(source)
				return nil
			end
			if weaponinfo.number < 0 or weaponinfo.number >= max_weaponinfo then
				B.botimport.Print(BC.PRT_ERROR, "weapon info number %d out of range in %s\n", weaponinfo.number, path)
				B.FreeSource(source)
				return nil
			end
			SB.copy_weaponinfo_t(wc.weaponinfo[weaponinfo.number], weaponinfo)
			wc.weaponinfo[weaponinfo.number].valid = 1
		elseif token.string == "projectileinfo" then
			if wc.numprojectiles >= max_projectileinfo then
				B.botimport.Print(BC.PRT_ERROR, "more than %d projectiles defined in %s\n", max_projectileinfo, path)
				B.FreeSource(source)
				return nil
			end
			SB.copy_projectileinfo_t(wc.projectileinfo[wc.numprojectiles], SB.projectileinfo_t())
			if B.ReadStructure(source, projectileinfo_struct, wc.projectileinfo[wc.numprojectiles]) == 0 then
				B.FreeSource(source)
				return nil
			end
			wc.numprojectiles = wc.numprojectiles + 1
		else
			B.botimport.Print(BC.PRT_ERROR, "unknown definition %s in %s\n", token.string, path)
			B.FreeSource(source)
			return nil
		end
	end
	B.FreeSource(source)
	--fix up weapons
	for i = 0, wc.numweapons - 1 do
		local wi = wc.weaponinfo[i]
		if wi.valid == 0 then
			continue
		end
		if wi.name == "" then
			B.botimport.Print(BC.PRT_ERROR, "weapon %d has no name in %s\n", i, path)
			return nil
		end
		if wi.projectile == "" then
			B.botimport.Print(BC.PRT_ERROR, "weapon %s has no projectile in %s\n", wi.name, path)
			return nil
		end
		--find the projectile info and copy it to the weapon info
		local j = 0
		while j < wc.numprojectiles do
			if wc.projectileinfo[j].name == wi.projectile then
				SB.copy_projectileinfo_t(wi.proj, wc.projectileinfo[j])
				break
			end
			j = j + 1
		end
		if j == wc.numprojectiles then
			B.botimport.Print(BC.PRT_ERROR, "weapon %s uses undefined projectile in %s\n", wi.name, path)
			return nil
		end
	end
	if wc.numweapons == 0 then
		B.botimport.Print(BC.PRT_WARNING, "no weapon info loaded\n")
	end
	B.botimport.Print(BC.PRT_MESSAGE, "loaded %s\n", path)
	return wc
end

function B.WeaponWeightIndex(wwc, wc)
	--initialize item weight index
	local index = B.zeros(wc.numweapons)
	for i = 0, wc.numweapons - 1 do
		index[i] = B.FindFuzzyWeight(wwc, wc.weaponinfo[i].name)
	end
	return index
end

function B.BotFreeWeaponWeights(weaponstate)
	local ws = B.BotWeaponStateFromHandle(weaponstate)
	if ws == nil then
		return
	end
	if ws.weaponweightconfig ~= nil then
		B.FreeWeightConfig(ws.weaponweightconfig)
	end
	if ws.weaponweightindex ~= nil then
		ws.weaponweightindex = nil
	end
end

function B.BotLoadWeaponWeights(weaponstate, filename)
	local ws = B.BotWeaponStateFromHandle(weaponstate)
	if ws == nil then
		return BC.BLERR_CANNOTLOADWEAPONWEIGHTS
	end
	B.BotFreeWeaponWeights(weaponstate)
	--
	ws.weaponweightconfig = B.ReadWeightConfig(filename)
	if ws.weaponweightconfig == nil then
		B.botimport.Print(BC.PRT_FATAL, "couldn't load weapon config %s\n", filename)
		return BC.BLERR_CANNOTLOADWEAPONWEIGHTS
	end
	if weaponconfig == nil then
		return BC.BLERR_CANNOTLOADWEAPONCONFIG
	end
	ws.weaponweightindex = B.WeaponWeightIndex(ws.weaponweightconfig, weaponconfig)
	return BC.BLERR_NOERROR
end

function B.BotGetWeaponInfo(weaponstate, weapon, weaponinfo)
	if B.BotValidWeaponNumber(weapon) == 0 then
		return
	end
	local ws = B.BotWeaponStateFromHandle(weaponstate)
	if ws == nil then
		return
	end
	if weaponconfig == nil then
		return
	end
	SB.copy_weaponinfo_t(weaponinfo, weaponconfig.weaponinfo[weapon])
end

function B.BotChooseBestFightWeapon(weaponstate, inventory)
	local ws = B.BotWeaponStateFromHandle(weaponstate)
	if ws == nil then
		return 0
	end
	local wc = weaponconfig
	if weaponconfig == nil then
		return 0
	end

	--if the bot has no weapon weight configuration
	if ws.weaponweightconfig == nil then
		return 0
	end

	local bestweight = 0
	local bestweapon = 0
	for i = 0, wc.numweapons - 1 do
		if wc.weaponinfo[i].valid == 0 then
			continue
		end
		local index = ws.weaponweightindex[i]
		if index < 0 then
			continue
		end
		local weight = B.FuzzyWeight(inventory, ws.weaponweightconfig, index)
		if weight > bestweight then
			bestweight = weight
			bestweapon = i
		end
	end
	return bestweapon
end

function B.BotResetWeaponState(weaponstate)
end

function B.BotAllocWeaponState()
	for i = 1, BC.MAX_CLIENTS do
		if botweaponstates[i] == nil then
			botweaponstates[i] = SB.bot_weaponstate_t()
			return i
		end
	end
	return 0
end

function B.BotFreeWeaponState(handle)
	if handle <= 0 or handle > BC.MAX_CLIENTS then
		B.botimport.Print(BC.PRT_FATAL, "weapon state handle %d out of range\n", handle)
		return
	end
	if botweaponstates[handle] == nil then
		B.botimport.Print(BC.PRT_FATAL, "invalid weapon state %d\n", handle)
		return
	end
	B.BotFreeWeaponWeights(handle)
	botweaponstates[handle] = nil
end

function B.BotSetupWeaponAI()
	local file = B.LibVarString("weaponconfig", "weapons.c")
	weaponconfig = B.LoadWeaponConfig(file)
	if weaponconfig == nil then
		B.botimport.Print(BC.PRT_FATAL, "couldn't load the weapon config\n")
		return BC.BLERR_CANNOTLOADWEAPONCONFIG
	end
	--
	return BC.BLERR_NOERROR
end

function B.BotShutdownWeaponAI()
	weaponconfig = nil

	for i = 1, BC.MAX_CLIENTS do
		if botweaponstates[i] ~= nil then
			B.BotFreeWeaponState(i)
		end
	end
end

return nil
