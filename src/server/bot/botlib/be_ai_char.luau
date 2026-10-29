--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ai_char.c).

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
-- Luau port of be_ai_char.c: bot characters.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local MAX_CHARACTERISTICS = 80

local CT_INTEGER = 1
local CT_FLOAT = 2
local CT_STRING = 3

local DEFAULT_CHARACTER = "bots/default_c.c"
local BOTFILESBASEFOLDER = "botfiles"

local MAX_CLIENTS = BC.MAX_CLIENTS

local botcharacters: { [number]: any } = {}

local function NewCharacter()
	local ch = SB.bot_character_t()
	for i = 0, MAX_CHARACTERISTICS - 1 do
		ch.c[i] = SB.bot_characteristic_t()
	end
	return ch
end

function B.BotCharacterFromHandle(handle)
	if handle <= 0 or handle > MAX_CLIENTS then
		B.botimport.Print(BC.PRT_FATAL, "character handle %d out of range\n", handle)
		return nil
	end
	if not botcharacters[handle] then
		B.botimport.Print(BC.PRT_FATAL, "invalid character %d\n", handle)
		return nil
	end
	return botcharacters[handle]
end

function B.BotDumpCharacter(ch)
	B.Log_Write("%s\n", ch.filename)
	B.Log_Write("skill %.1f\n", ch.skill)
	B.Log_Write("{\n")
	for i = 0, MAX_CHARACTERISTICS - 1 do
		local t = ch.c[i].type
		if t == CT_INTEGER then
			B.Log_Write(" %4d %d\n", i, ch.c[i].value)
		elseif t == CT_FLOAT then
			B.Log_Write(" %4d %f\n", i, ch.c[i].value)
		elseif t == CT_STRING then
			B.Log_Write(" %4d %s\n", i, ch.c[i].value)
		end
	end
	B.Log_Write("}\n")
end

function B.BotFreeCharacterStrings(ch)
	for i = 0, MAX_CHARACTERISTICS - 1 do
		if ch.c[i].type == CT_STRING then
			ch.c[i].value = ""
		end
	end
end

function B.BotFreeCharacter2(handle)
	if handle <= 0 or handle > MAX_CLIENTS then
		B.botimport.Print(BC.PRT_FATAL, "character handle %d out of range\n", handle)
		return
	end
	if not botcharacters[handle] then
		B.botimport.Print(BC.PRT_FATAL, "invalid character %d\n", handle)
		return
	end
	B.BotFreeCharacterStrings(botcharacters[handle])
	botcharacters[handle] = nil
end

function B.BotFreeCharacter(handle)
	if B.LibVarGetValue("bot_reloadcharacters") == 0 then
		return
	end
	B.BotFreeCharacter2(handle)
end

function B.BotDefaultCharacteristics(ch, defaultch)
	for i = 0, MAX_CHARACTERISTICS - 1 do
		if ch.c[i].type ~= 0 then
			continue
		end
		local dt = defaultch.c[i].type
		if dt == CT_FLOAT then
			ch.c[i].type = CT_FLOAT
			ch.c[i].value = defaultch.c[i].value
		elseif dt == CT_INTEGER then
			ch.c[i].type = CT_INTEGER
			ch.c[i].value = defaultch.c[i].value
		elseif dt == CT_STRING then
			ch.c[i].type = CT_STRING
			ch.c[i].value = defaultch.c[i].value
		end
	end
end

function B.BotLoadCharacterFromFile(charfile, skill)
	local foundcharacter = false
	local token = SB.token_t()
	B.PC_SetBaseFolder(BOTFILESBASEFOLDER)
	local source = B.LoadSourceFile(charfile)
	if source == nil then
		B.botimport.Print(BC.PRT_ERROR, "couldn't load %s\n", charfile)
		return nil
	end
	local ch = NewCharacter()
	ch.filename = charfile
	while B.PC_ReadToken(source, token) ~= 0 do
		if token.string == "skill" then
			if B.PC_ExpectTokenType(source, BC.TT_NUMBER, 0, token) == 0 then
				B.FreeSource(source)
				B.BotFreeCharacterStrings(ch)
				return nil
			end
			if B.PC_ExpectTokenString(source, "{") == 0 then
				B.FreeSource(source)
				B.BotFreeCharacterStrings(ch)
				return nil
			end
			if skill < 0 or Q.trunc(token.intvalue) == skill then
				foundcharacter = true
				ch.skill = token.intvalue
				while B.PC_ExpectAnyToken(source, token) ~= 0 do
					if token.string == "}" then
						break
					end
					if token.type ~= BC.TT_NUMBER or bit32.band(token.subtype, BC.TT_INTEGER) == 0 then
						B.SourceError(source, "expected integer index, found %s", token.string)
						B.FreeSource(source)
						B.BotFreeCharacterStrings(ch)
						return nil
					end
					local index = token.intvalue
					if index < 0 or index > MAX_CHARACTERISTICS then
						B.SourceError(source, "characteristic index out of range [0, %d]", MAX_CHARACTERISTICS)
						B.FreeSource(source)
						B.BotFreeCharacterStrings(ch)
						return nil
					end
					if ch.c[index] ~= nil and ch.c[index].type ~= 0 then
						B.SourceError(source, "characteristic %d already initialized", index)
						B.FreeSource(source)
						B.BotFreeCharacterStrings(ch)
						return nil
					end
					if B.PC_ExpectAnyToken(source, token) == 0 then
						B.FreeSource(source)
						B.BotFreeCharacterStrings(ch)
						return nil
					end
					if ch.c[index] == nil then
						ch.c[index] = SB.bot_characteristic_t()
					end
					if token.type == BC.TT_NUMBER then
						if bit32.band(token.subtype, BC.TT_FLOAT) ~= 0 then
							ch.c[index].value = token.floatvalue
							ch.c[index].type = CT_FLOAT
						else
							ch.c[index].value = token.intvalue
							ch.c[index].type = CT_INTEGER
						end
					elseif token.type == BC.TT_STRING then
						token.string = B.StripDoubleQuotes(token.string)
						ch.c[index].value = token.string
						ch.c[index].type = CT_STRING
					else
						B.SourceError(source, "expected integer, float or string, found %s", token.string)
						B.FreeSource(source)
						B.BotFreeCharacterStrings(ch)
						return nil
					end
				end
				break
			else
				local indent = 1
				while indent ~= 0 do
					if B.PC_ExpectAnyToken(source, token) == 0 then
						B.FreeSource(source)
						B.BotFreeCharacterStrings(ch)
						return nil
					end
					if token.string == "{" then
						indent += 1
					elseif token.string == "}" then
						indent -= 1
					end
				end
			end
		else
			B.SourceError(source, "unknown definition %s", token.string)
			B.FreeSource(source)
			B.BotFreeCharacterStrings(ch)
			return nil
		end
	end
	B.FreeSource(source)
	if not foundcharacter then
		B.BotFreeCharacterStrings(ch)
		return nil
	end
	return ch
end

function B.BotFindCachedCharacter(charfile, skill)
	for handle = 1, MAX_CLIENTS do
		if not botcharacters[handle] then
			continue
		end
		if botcharacters[handle].filename == charfile
			and (skill < 0 or math.abs(botcharacters[handle].skill - skill) < 0.01) then
			return handle
		end
	end
	return 0
end

function B.BotLoadCachedCharacter(charfile, skill, reload)
	local handle = 1
	while handle <= MAX_CLIENTS do
		if not botcharacters[handle] then
			break
		end
		handle += 1
	end
	if handle > MAX_CLIENTS then
		return 0
	end
	if reload == 0 then
		local cachedhandle = B.BotFindCachedCharacter(charfile, skill)
		if cachedhandle ~= 0 then
			B.botimport.Print(BC.PRT_MESSAGE, "loaded cached skill %f from %s\n", skill, charfile)
			return cachedhandle
		end
	end
	local intskill = Q.trunc(skill + 0.5)
	local ch = B.BotLoadCharacterFromFile(charfile, intskill)
	if ch then
		botcharacters[handle] = ch
		B.botimport.Print(BC.PRT_MESSAGE, "loaded skill %d from %s\n", intskill, charfile)
		return handle
	end
	B.botimport.Print(BC.PRT_WARNING, "couldn't find skill %d in %s\n", intskill, charfile)
	if reload == 0 then
		local cachedhandle = B.BotFindCachedCharacter(DEFAULT_CHARACTER, skill)
		if cachedhandle ~= 0 then
			B.botimport.Print(BC.PRT_MESSAGE, "loaded cached default skill %d from %s\n", intskill, charfile)
			return cachedhandle
		end
	end
	ch = B.BotLoadCharacterFromFile(DEFAULT_CHARACTER, intskill)
	if ch then
		botcharacters[handle] = ch
		B.botimport.Print(BC.PRT_MESSAGE, "loaded default skill %d from %s\n", intskill, charfile)
		return handle
	end
	if reload == 0 then
		local cachedhandle = B.BotFindCachedCharacter(charfile, -1)
		if cachedhandle ~= 0 then
			B.botimport.Print(BC.PRT_MESSAGE, "loaded cached skill %f from %s\n", botcharacters[cachedhandle].skill, charfile)
			return cachedhandle
		end
	end
	ch = B.BotLoadCharacterFromFile(charfile, -1)
	if ch then
		botcharacters[handle] = ch
		B.botimport.Print(BC.PRT_MESSAGE, "loaded skill %f from %s\n", ch.skill, charfile)
		return handle
	end
	if reload == 0 then
		local cachedhandle = B.BotFindCachedCharacter(DEFAULT_CHARACTER, -1)
		if cachedhandle ~= 0 then
			B.botimport.Print(BC.PRT_MESSAGE, "loaded cached default skill %f from %s\n", botcharacters[cachedhandle].skill, charfile)
			return cachedhandle
		end
	end
	ch = B.BotLoadCharacterFromFile(DEFAULT_CHARACTER, -1)
	if ch then
		botcharacters[handle] = ch
		B.botimport.Print(BC.PRT_MESSAGE, "loaded default skill %f from %s\n", ch.skill, charfile)
		return handle
	end
	B.botimport.Print(BC.PRT_WARNING, "couldn't load any skill from %s\n", charfile)
	return 0
end

function B.BotLoadCharacterSkill(charfile, skill)
	local defaultch = B.BotLoadCachedCharacter(DEFAULT_CHARACTER, skill, 0)
	local ch = B.BotLoadCachedCharacter(charfile, skill, Q.trunc(B.LibVarGetValue("bot_reloadcharacters")))
	if defaultch ~= 0 and ch ~= 0 then
		B.BotDefaultCharacteristics(botcharacters[ch], botcharacters[defaultch])
	end
	return ch
end

function B.BotInterpolateCharacters(handle1, handle2, desiredskill)
	local ch1 = B.BotCharacterFromHandle(handle1)
	local ch2 = B.BotCharacterFromHandle(handle2)
	if not ch1 or not ch2 then
		return 0
	end
	local handle = 1
	while handle <= MAX_CLIENTS do
		if not botcharacters[handle] then
			break
		end
		handle += 1
	end
	if handle > MAX_CLIENTS then
		return 0
	end
	local out = NewCharacter()
	out.skill = desiredskill
	out.filename = ch1.filename
	botcharacters[handle] = out

	local scale = Q.f((desiredskill - ch1.skill) / (ch2.skill - ch1.skill))
	for i = 0, MAX_CHARACTERISTICS - 1 do
		if ch1.c[i].type == CT_FLOAT and ch2.c[i].type == CT_FLOAT then
			out.c[i].type = CT_FLOAT
			out.c[i].value = Q.f(ch1.c[i].value + (ch2.c[i].value - ch1.c[i].value) * scale)
		elseif ch1.c[i].type == CT_INTEGER then
			out.c[i].type = CT_INTEGER
			out.c[i].value = ch1.c[i].value
		elseif ch1.c[i].type == CT_STRING then
			out.c[i].type = CT_STRING
			out.c[i].value = ch1.c[i].value
		end
	end
	return handle
end

function B.BotLoadCharacter(charfile, skill)
	if skill < 1.0 then
		skill = 1.0
	elseif skill > 5.0 then
		skill = 5.0
	end
	if skill == 1.0 or skill == 4.0 or skill == 5.0 then
		return B.BotLoadCharacterSkill(charfile, skill)
	end
	local handle = B.BotFindCachedCharacter(charfile, skill)
	if handle ~= 0 then
		B.botimport.Print(BC.PRT_MESSAGE, "loaded cached skill %f from %s\n", skill, charfile)
		return handle
	end
	local firstskill, secondskill
	if skill < 4.0 then
		firstskill = B.BotLoadCharacterSkill(charfile, 1)
		if firstskill == 0 then
			return 0
		end
		secondskill = B.BotLoadCharacterSkill(charfile, 4)
		if secondskill == 0 then
			return firstskill
		end
	else
		firstskill = B.BotLoadCharacterSkill(charfile, 4)
		if firstskill == 0 then
			return 0
		end
		secondskill = B.BotLoadCharacterSkill(charfile, 5)
		if secondskill == 0 then
			return firstskill
		end
	end
	handle = B.BotInterpolateCharacters(firstskill, secondskill, skill)
	if handle == 0 then
		return 0
	end
	B.BotDumpCharacter(botcharacters[handle])
	return handle
end

function B.CheckCharacteristicIndex(character, index)
	local ch = B.BotCharacterFromHandle(character)
	if not ch then
		return false
	end
	if index < 0 or index >= MAX_CHARACTERISTICS then
		B.botimport.Print(BC.PRT_ERROR, "characteristic %d does not exist\n", index)
		return false
	end
	if ch.c[index].type == 0 then
		B.botimport.Print(BC.PRT_ERROR, "characteristic %d is not initialized\n", index)
		return false
	end
	return true
end

function B.Characteristic_Float(character, index)
	local ch = B.BotCharacterFromHandle(character)
	if not ch then
		return 0
	end
	if not B.CheckCharacteristicIndex(character, index) then
		return 0
	end
	if ch.c[index].type == CT_INTEGER then
		return Q.f(ch.c[index].value)
	elseif ch.c[index].type == CT_FLOAT then
		return ch.c[index].value
	else
		B.botimport.Print(BC.PRT_ERROR, "characteristic %d is not a float\n", index)
		return 0
	end
end

function B.Characteristic_BFloat(character, index, min, max)
	local ch = B.BotCharacterFromHandle(character)
	if not ch then
		return 0
	end
	if min > max then
		B.botimport.Print(BC.PRT_ERROR, "cannot bound characteristic %d between %f and %f\n", index, min, max)
		return 0
	end
	local value = B.Characteristic_Float(character, index)
	if value < min then
		return min
	end
	if value > max then
		return max
	end
	return value
end

function B.Characteristic_Integer(character, index)
	local ch = B.BotCharacterFromHandle(character)
	if not ch then
		return 0
	end
	if not B.CheckCharacteristicIndex(character, index) then
		return 0
	end
	if ch.c[index].type == CT_INTEGER then
		return ch.c[index].value
	elseif ch.c[index].type == CT_FLOAT then
		return Q.trunc(ch.c[index].value)
	else
		B.botimport.Print(BC.PRT_ERROR, "characteristic %d is not an integer\n", index)
		return 0
	end
end

function B.Characteristic_BInteger(character, index, min, max)
	local ch = B.BotCharacterFromHandle(character)
	if not ch then
		return 0
	end
	if min > max then
		B.botimport.Print(BC.PRT_ERROR, "cannot bound characteristic %d between %d and %d\n", index, min, max)
		return 0
	end
	local value = B.Characteristic_Integer(character, index)
	if value < min then
		return min
	end
	if value > max then
		return max
	end
	return value
end

function B.Characteristic_String(character, index, size)
	local ch = B.BotCharacterFromHandle(character)
	if not ch then
		return ""
	end
	if not B.CheckCharacteristicIndex(character, index) then
		return ""
	end
	if ch.c[index].type == CT_STRING then
		return QS.Q_strncpyz(ch.c[index].value, size)
	else
		B.botimport.Print(BC.PRT_ERROR, "characteristic %d is not a string\n", index)
	end
	return ""
end

function B.BotShutdownCharacters()
	for handle = 1, MAX_CLIENTS do
		if botcharacters[handle] then
			B.BotFreeCharacter2(handle)
		end
	end
end

return nil
