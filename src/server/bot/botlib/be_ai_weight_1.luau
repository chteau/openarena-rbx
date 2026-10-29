--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_weight.c, part 1 of 2).

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
-- Luau port of be_ai_weight.c (botlib/be_ai_weight.c, part 1 of 2): fuzzy logic weight config reading.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("be_ai_weight")

SF.MAX_INVENTORYVALUE = 999999
SF.MAX_WEIGHT_FILES = 128
SF.BOTFILESBASEFOLDER = "botfiles"
SF.weightFileList = {}

local MAX_INVENTORYVALUE = 999999
local MAX_WEIGHT_FILES = 128

-- returns success (qboolean as boolean) and the value
local function ReadValue(source, value_unused)
	local token = SB.token_t()

	if B.PC_ExpectAnyToken(source, token) == 0 then return false, 0 end
	if token.string == "-" then
		B.SourceWarning(source, "negative value set to zero")

		if B.PC_ExpectAnyToken(source, token) == 0 then
			B.SourceError(source, "Missing return value")
			return false, 0
		end
	end

	if token.type ~= BC.TT_NUMBER then
		B.SourceError(source, "invalid return value %s", token.string)
		return false, 0
	end

	return true, token.floatvalue
end

function B.ReadValue(source)
	local ok, value = ReadValue(source, nil)
	if ok then return 1, value end
	return 0, 0
end

function B.ReadFuzzyWeight(source, fs)
	local ok, v
	if B.PC_CheckTokenString(source, "balance") ~= 0 then
		fs.type = BC.WT_BALANCE
		if B.PC_ExpectTokenString(source, "(") == 0 then return 0 end
		ok, v = ReadValue(source, nil)
		fs.weight = v
		if not ok then return 0 end
		if B.PC_ExpectTokenString(source, ",") == 0 then return 0 end
		ok, v = ReadValue(source, nil)
		fs.minweight = v
		if not ok then return 0 end
		if B.PC_ExpectTokenString(source, ",") == 0 then return 0 end
		ok, v = ReadValue(source, nil)
		fs.maxweight = v
		if not ok then return 0 end
		if B.PC_ExpectTokenString(source, ")") == 0 then return 0 end
	else
		fs.type = 0
		ok, v = ReadValue(source, nil)
		fs.weight = v
		if not ok then return 0 end
		fs.minweight = fs.weight
		fs.maxweight = fs.weight
	end
	if B.PC_ExpectTokenString(source, ";") == 0 then return 0 end
	return 1
end

function B.FreeFuzzySeperators_r(fs)
	if fs == nil then return end
	if fs.child ~= nil then B.FreeFuzzySeperators_r(fs.child) end
	if fs.next ~= nil then B.FreeFuzzySeperators_r(fs.next) end
end

function B.FreeWeightConfig2(config)
	for i = 0, config.numweights - 1 do
		B.FreeFuzzySeperators_r(config.weights[i].firstseperator)
		config.weights[i].name = nil
	end
end

function B.FreeWeightConfig(config)
	if B.LibVarGetValue("bot_reloadcharacters") == 0 then return end
	B.FreeWeightConfig2(config)
end

function B.ReadFuzzySeperators_r(source)
	local newindent, index, def
	local founddefault = false
	local token = SB.token_t()
	local fs
	local lastfs = nil
	local firstfs = nil

	if B.PC_ExpectTokenString(source, "(") == 0 then return nil end
	if B.PC_ExpectTokenType(source, BC.TT_NUMBER, BC.TT_INTEGER, token) == 0 then return nil end
	index = token.intvalue
	if B.PC_ExpectTokenString(source, ")") == 0 then return nil end
	if B.PC_ExpectTokenString(source, "{") == 0 then return nil end
	if B.PC_ExpectAnyToken(source, token) == 0 then return nil end
	repeat
		def = token.string == "default"
		if def or token.string == "case" then
			fs = SB.fuzzyseperator_t()
			fs.index = index
			if lastfs ~= nil then
				lastfs.next = fs
			else
				firstfs = fs
			end
			lastfs = fs
			if def then
				if founddefault then
					B.SourceError(source, "switch already has a default")
					B.FreeFuzzySeperators_r(firstfs)
					return nil
				end
				fs.value = MAX_INVENTORYVALUE
				founddefault = true
			else
				if B.PC_ExpectTokenType(source, BC.TT_NUMBER, BC.TT_INTEGER, token) == 0 then
					B.FreeFuzzySeperators_r(firstfs)
					return nil
				end
				fs.value = token.intvalue
			end
			if B.PC_ExpectTokenString(source, ":") == 0 or B.PC_ExpectAnyToken(source, token) == 0 then
				B.FreeFuzzySeperators_r(firstfs)
				return nil
			end
			newindent = false
			if token.string == "{" then
				newindent = true
				if B.PC_ExpectAnyToken(source, token) == 0 then
					B.FreeFuzzySeperators_r(firstfs)
					return nil
				end
			end
			if token.string == "return" then
				if B.ReadFuzzyWeight(source, fs) == 0 then
					B.FreeFuzzySeperators_r(firstfs)
					return nil
				end
			elseif token.string == "switch" then
				fs.child = B.ReadFuzzySeperators_r(source)
				if fs.child == nil then
					B.FreeFuzzySeperators_r(firstfs)
					return nil
				end
			else
				B.SourceError(source, "invalid name %s", token.string)
				return nil
			end
			if newindent then
				if B.PC_ExpectTokenString(source, "}") == 0 then
					B.FreeFuzzySeperators_r(firstfs)
					return nil
				end
			end
		else
			B.FreeFuzzySeperators_r(firstfs)
			B.SourceError(source, "invalid name %s", token.string)
			return nil
		end
		if B.PC_ExpectAnyToken(source, token) == 0 then
			B.FreeFuzzySeperators_r(firstfs)
			return nil
		end
	until not (token.string ~= "}")
	--
	if not founddefault then
		B.SourceWarning(source, "switch without default")
		fs = SB.fuzzyseperator_t()
		fs.index = index
		fs.value = MAX_INVENTORYVALUE
		fs.weight = 0
		fs.next = nil
		fs.child = nil
		if lastfs ~= nil then
			lastfs.next = fs
		else
			firstfs = fs
		end
	end
	--
	return firstfs
end

function B.ReadWeightConfig(filename)
	local newindent
	local avail = 0
	local token = SB.token_t()
	local source
	local fs
	local config = nil

	if B.LibVarGetValue("bot_reloadcharacters") == 0 then
		avail = -1
		for n = 0, MAX_WEIGHT_FILES - 1 do
			config = SF.weightFileList[n]
			if config == nil then
				if avail == -1 then
					avail = n
				end
				continue
			end
			if filename == config.filename then
				return config
			end
		end

		if avail == -1 then
			B.botimport.Print(BC.PRT_ERROR, "weightFileList was full trying to load %s\n", filename)
			return nil
		end
	end

	B.PC_SetBaseFolder(SF.BOTFILESBASEFOLDER)
	source = B.LoadSourceFile(filename)
	if source == nil then
		B.botimport.Print(BC.PRT_ERROR, "couldn't load %s\n", filename)
		return nil
	end
	--
	config = SB.weightconfig_t()
	config.numweights = 0
	config.filename = QS.Q_strncpyz(filename, 64)
	--parse the item config file
	while B.PC_ReadToken(source, token) ~= 0 do
		if token.string == "weight" then
			if config.numweights >= BC.MAX_WEIGHTS then
				B.SourceWarning(source, "too many fuzzy weights")
				break
			end
			if B.PC_ExpectTokenType(source, BC.TT_STRING, 0, token) == 0 then
				B.FreeWeightConfig(config)
				B.FreeSource(source)
				return nil
			end
			token.string = B.StripDoubleQuotes(token.string)
			config.weights[config.numweights].name = token.string
			if B.PC_ExpectAnyToken(source, token) == 0 then
				B.FreeWeightConfig(config)
				B.FreeSource(source)
				return nil
			end
			newindent = false
			if token.string == "{" then
				newindent = true
				if B.PC_ExpectAnyToken(source, token) == 0 then
					B.FreeWeightConfig(config)
					B.FreeSource(source)
					return nil
				end
			end
			if token.string == "switch" then
				fs = B.ReadFuzzySeperators_r(source)
				if fs == nil then
					B.FreeWeightConfig(config)
					B.FreeSource(source)
					return nil
				end
				config.weights[config.numweights].firstseperator = fs
			elseif token.string == "return" then
				fs = SB.fuzzyseperator_t()
				fs.index = 0
				fs.value = MAX_INVENTORYVALUE
				fs.next = nil
				fs.child = nil
				if B.ReadFuzzyWeight(source, fs) == 0 then
					B.FreeWeightConfig(config)
					B.FreeSource(source)
					return nil
				end
				config.weights[config.numweights].firstseperator = fs
			else
				B.SourceError(source, "invalid name %s", token.string)
				B.FreeWeightConfig(config)
				B.FreeSource(source)
				return nil
			end
			if newindent then
				if B.PC_ExpectTokenString(source, "}") == 0 then
					B.FreeWeightConfig(config)
					B.FreeSource(source)
					return nil
				end
			end
			config.numweights = config.numweights + 1
		else
			B.SourceError(source, "invalid name %s", token.string)
			B.FreeWeightConfig(config)
			B.FreeSource(source)
			return nil
		end
	end
	--free the source at the end of a pass
	B.FreeSource(source)
	--if the file was located in a pak file
	B.botimport.Print(BC.PRT_MESSAGE, "loaded %s\n", filename)
	--
	if B.LibVarGetValue("bot_reloadcharacters") == 0 then
		SF.weightFileList[avail] = config
	end
	--
	return config
end

return nil
