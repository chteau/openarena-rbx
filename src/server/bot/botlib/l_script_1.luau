--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/l_script.c, part 1 of 2).

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
-- Luau port of l_script.c (botlib/l_script.c, part 1 of 2). Lexicographical parser: punctuation table, white space, strings, names, numbers.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("l_script")

SF.MAX_TOKEN = BC.MAX_TOKEN

-- longer punctuations first
local defaultList = {
	{ ">>=", BC.P_RSHIFT_ASSIGN },
	{ "<<=", BC.P_LSHIFT_ASSIGN },
	{ "...", BC.P_PARMS },
	{ "##", BC.P_PRECOMPMERGE },
	{ "&&", BC.P_LOGIC_AND },
	{ "||", BC.P_LOGIC_OR },
	{ ">=", BC.P_LOGIC_GEQ },
	{ "<=", BC.P_LOGIC_LEQ },
	{ "==", BC.P_LOGIC_EQ },
	{ "!=", BC.P_LOGIC_UNEQ },
	{ "*=", BC.P_MUL_ASSIGN },
	{ "/=", BC.P_DIV_ASSIGN },
	{ "%=", BC.P_MOD_ASSIGN },
	{ "+=", BC.P_ADD_ASSIGN },
	{ "-=", BC.P_SUB_ASSIGN },
	{ "++", BC.P_INC },
	{ "--", BC.P_DEC },
	{ "&=", BC.P_BIN_AND_ASSIGN },
	{ "|=", BC.P_BIN_OR_ASSIGN },
	{ "^=", BC.P_BIN_XOR_ASSIGN },
	{ ">>", BC.P_RSHIFT },
	{ "<<", BC.P_LSHIFT },
	{ "->", BC.P_POINTERREF },
	{ "::", BC.P_CPP1 },
	{ ".*", BC.P_CPP2 },
	{ "*", BC.P_MUL },
	{ "/", BC.P_DIV },
	{ "%", BC.P_MOD },
	{ "+", BC.P_ADD },
	{ "-", BC.P_SUB },
	{ "=", BC.P_ASSIGN },
	{ "&", BC.P_BIN_AND },
	{ "|", BC.P_BIN_OR },
	{ "^", BC.P_BIN_XOR },
	{ "~", BC.P_BIN_NOT },
	{ "!", BC.P_LOGIC_NOT },
	{ ">", BC.P_LOGIC_GREATER },
	{ "<", BC.P_LOGIC_LESS },
	{ ".", BC.P_REF },
	{ ",", BC.P_COMMA },
	{ ";", BC.P_SEMICOLON },
	{ ":", BC.P_COLON },
	{ "?", BC.P_QUESTIONMARK },
	{ "(", BC.P_PARENTHESESOPEN },
	{ ")", BC.P_PARENTHESESCLOSE },
	{ "{", BC.P_BRACEOPEN },
	{ "}", BC.P_BRACECLOSE },
	{ "[", BC.P_SQBRACKETOPEN },
	{ "]", BC.P_SQBRACKETCLOSE },
	{ "\\", BC.P_BACKSLASH },
	{ "#", BC.P_PRECOMP },
	{ "$", BC.P_DOLLAR },
}

local default_punctuations = {}
for i, e in ipairs(defaultList) do
	local entry = SB.punctuation_t()
	entry.p = e[1]
	entry.n = e[2]
	entry.next = nil
	default_punctuations[i - 1] = entry
end
-- terminator {NULL, 0}
default_punctuations[#defaultList] = SB.punctuation_t()
SF.default_punctuations = default_punctuations

SF.basefolder = ""

local function cur(script, off: number): number
	return B.ch(script.buffer, script.script_p + off)
end

function B.PS_CreatePunctuationTable(script, punctuations)
	if script.punctuationtable == nil then
		script.punctuationtable = {}
	end
	script.punctuationtable = {}
	local i = 0
	while punctuations[i].p ~= nil do
		local newp = punctuations[i]
		local lastp = nil
		local idx = B.ch(newp.p, 0)
		local p = script.punctuationtable[idx]
		while p ~= nil do
			if #p.p < #newp.p then
				newp.next = p
				if lastp ~= nil then
					lastp.next = newp
				else
					script.punctuationtable[idx] = newp
				end
				break
			end
			lastp = p
			p = p.next
		end
		if p == nil then
			newp.next = nil
			if lastp ~= nil then
				lastp.next = newp
			else
				script.punctuationtable[idx] = newp
			end
		end
		i = i + 1
	end
end

function B.PunctuationFromNum(script, num: number): string
	local i = 0
	while script.punctuations[i].p ~= nil do
		if script.punctuations[i].n == num then
			return script.punctuations[i].p
		end
		i = i + 1
	end
	return "unknown punctuation"
end

function B.ScriptError(script, str: string, ...)
	if bit32.band(script.flags, BC.SCFL_NOERRORS) ~= 0 then
		return
	end
	local text = string.sub(QS.va(str, ...), 1, 1023)
	B.botimport.Print(BC.PRT_ERROR, "file %s, line %d: %s\n", script.filename, script.line, text)
end

function B.ScriptWarning(script, str: string, ...)
	if bit32.band(script.flags, BC.SCFL_NOWARNINGS) ~= 0 then
		return
	end
	local text = string.sub(QS.va(str, ...), 1, 1023)
	B.botimport.Print(BC.PRT_WARNING, "file %s, line %d: %s\n", script.filename, script.line, text)
end

function B.SetScriptPunctuations(script, p)
	if p ~= nil then
		B.PS_CreatePunctuationTable(script, p)
	else
		B.PS_CreatePunctuationTable(script, default_punctuations)
	end
	if p ~= nil then
		script.punctuations = p
	else
		script.punctuations = default_punctuations
	end
end

-- Reads spaces, tabs, C-like comments etc.
-- When a newline character is found the scripts line counter is increased.
function B.PS_ReadWhiteSpace(script): number
	while true do
		-- skip white space (C char is signed, so bytes >= 128 count as white space)
		while true do
			local c = cur(script, 0)
			if c >= 128 then
				c = c - 256
			end
			if not (c <= 32) then
				break
			end
			if c == 0 then
				return 0
			end
			if c == 10 then
				script.line = script.line + 1
			end
			script.script_p = script.script_p + 1
		end
		-- skip comments
		if cur(script, 0) == 47 then
			-- comments //
			if cur(script, 1) == 47 then
				script.script_p = script.script_p + 1
				repeat
					script.script_p = script.script_p + 1
					if cur(script, 0) == 0 then
						return 0
					end
				until cur(script, 0) == 10
				script.line = script.line + 1
				script.script_p = script.script_p + 1
				if cur(script, 0) == 0 then
					return 0
				end
				continue
			-- comments /* */
			elseif cur(script, 1) == 42 then
				script.script_p = script.script_p + 1
				repeat
					script.script_p = script.script_p + 1
					if cur(script, 0) == 0 then
						return 0
					end
					if cur(script, 0) == 10 then
						script.line = script.line + 1
					end
				until cur(script, 0) == 42 and cur(script, 1) == 47
				script.script_p = script.script_p + 1
				if cur(script, 0) == 0 then
					return 0
				end
				script.script_p = script.script_p + 1
				if cur(script, 0) == 0 then
					return 0
				end
				continue
			end
		end
		break
	end
	return 1
end

-- Reads an escape character. Returns (success, ch).
function B.PS_ReadEscapeCharacter(script): (number, number)
	local c, val

	-- step over the leading '\\'
	script.script_p = script.script_p + 1
	-- determine the escape character
	local e = cur(script, 0)
	if e == 92 then
		c = 92
	elseif e == 110 then
		c = 10
	elseif e == 114 then
		c = 13
	elseif e == 116 then
		c = 9
	elseif e == 118 then
		c = 11
	elseif e == 98 then
		c = 8
	elseif e == 102 then
		c = 12
	elseif e == 97 then
		c = 7
	elseif e == 39 then
		c = 39
	elseif e == 34 then
		c = 34
	elseif e == 63 then
		c = 63
	elseif e == 120 then
		script.script_p = script.script_p + 1
		val = 0
		while true do
			c = cur(script, 0)
			if c >= 48 and c <= 57 then
				c = c - 48
			elseif c >= 65 and c <= 90 then
				c = c - 65 + 10
			elseif c >= 97 and c <= 122 then
				c = c - 97 + 10
			else
				break
			end
			val = val * 16 + c
			script.script_p = script.script_p + 1
		end
		script.script_p = script.script_p - 1
		if val > 0xFF then
			B.ScriptWarning(script, "too large value in escape character")
			val = 0xFF
		end
		c = val
	else -- NOTE: decimal ASCII code, NOT octal
		if e < 48 or e > 57 then
			B.ScriptError(script, "unknown escape char")
		end
		val = 0
		while true do
			c = cur(script, 0)
			if c >= 48 and c <= 57 then
				c = c - 48
			else
				break
			end
			val = val * 10 + c
			script.script_p = script.script_p + 1
		end
		script.script_p = script.script_p - 1
		if val > 0xFF then
			B.ScriptWarning(script, "too large value in escape character")
			val = 0xFF
		end
		c = val
	end
	-- step over the escape character or the last digit of the number
	script.script_p = script.script_p + 1
	return 1, c
end

-- Reads C-like string. Escape characters are interpretted.
-- Quotes are included with the string.
-- Reads two strings with a white space between them as one string.
function B.PS_ReadString(script, token, quote: number): number
	if quote == 34 then
		token.type = BC.TT_STRING
	else
		token.type = BC.TT_LITERAL
	end

	-- leading quote
	local s = string.char(cur(script, 0))
	script.script_p = script.script_p + 1

	while true do
		-- minus 2 because trailing double quote and zero have to be appended
		if #s >= BC.MAX_TOKEN - 2 then
			token.string = s
			B.ScriptError(script, "string longer than MAX_TOKEN = %d", BC.MAX_TOKEN)
			return 0
		end
		-- if there is an escape character and
		-- if escape characters inside a string are allowed
		if cur(script, 0) == 92 and bit32.band(script.flags, BC.SCFL_NOSTRINGESCAPECHARS) == 0 then
			local ok, ech = B.PS_ReadEscapeCharacter(script)
			if ok == 0 then
				token.string = s
				return 0
			end
			s = s .. string.char(ech)
		-- if a trailing quote
		elseif cur(script, 0) == quote then
			-- step over the double quote
			script.script_p = script.script_p + 1
			-- if white spaces in a string are not allowed
			if bit32.band(script.flags, BC.SCFL_NOSTRINGWHITESPACES) ~= 0 then
				break
			end

			local tmpscript_p = script.script_p
			local tmpline = script.line
			-- read unusefull stuff between possible two following strings
			if B.PS_ReadWhiteSpace(script) == 0 then
				script.script_p = tmpscript_p
				script.line = tmpline
				break
			end
			-- if there's no leading double qoute
			if cur(script, 0) ~= quote then
				script.script_p = tmpscript_p
				script.line = tmpline
				break
			end
			-- step over the new leading double quote
			script.script_p = script.script_p + 1
		else
			if cur(script, 0) == 0 then
				token.string = s
				B.ScriptError(script, "missing trailing quote")
				return 0
			end
			if cur(script, 0) == 10 then
				token.string = s
				B.ScriptError(script, "newline inside string %s", token.string)
				return 0
			end
			s = s .. string.char(cur(script, 0))
			script.script_p = script.script_p + 1
		end
	end
	-- trailing quote
	s = s .. string.char(quote)
	token.string = s
	-- the sub type is the length of the string
	token.subtype = #s
	return 1
end

function B.PS_ReadName(script, token): number
	local len = 0
	local s = ""

	token.type = BC.TT_NAME
	repeat
		s = s .. string.char(cur(script, 0))
		script.script_p = script.script_p + 1
		len = len + 1
		if len >= BC.MAX_TOKEN then
			token.string = s
			B.ScriptError(script, "name longer than MAX_TOKEN = %d", BC.MAX_TOKEN)
			return 0
		end
		local c = cur(script, 0)
	until not ((c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 95)
	token.string = s
	-- the sub type is the length of the name
	token.subtype = len
	return 1
end

-- Returns (intvalue, floatvalue)
function B.NumberValue(str: string, subtype: number): (number, number)
	local dotfound = 0
	local intvalue = 0
	local floatvalue = 0
	local i = 0

	-- floating point number
	if bit32.band(subtype, BC.TT_FLOAT) ~= 0 then
		while B.ch(str, i) ~= 0 do
			if B.ch(str, i) == 46 then
				if dotfound ~= 0 then
					return intvalue, floatvalue
				end
				dotfound = 10
				i = i + 1
			end
			if dotfound ~= 0 then
				floatvalue = Q.f(floatvalue + Q.f(Q.f(B.ch(str, i) - 48) / Q.f(dotfound)))
				dotfound = dotfound * 10
			else
				floatvalue = Q.f(floatvalue * 10.0 + Q.f(B.ch(str, i) - 48))
			end
			i = i + 1
		end
		intvalue = Q.trunc(floatvalue)
	elseif bit32.band(subtype, BC.TT_DECIMAL) ~= 0 then
		while B.ch(str, i) ~= 0 do
			intvalue = intvalue * 10 + (B.ch(str, i) - 48)
			i = i + 1
		end
		floatvalue = Q.f(intvalue)
	elseif bit32.band(subtype, BC.TT_HEX) ~= 0 then
		-- step over the leading 0x or 0X
		i = i + 2
		while B.ch(str, i) ~= 0 do
			local c = B.ch(str, i)
			intvalue = intvalue * 16
			if c >= 97 and c <= 102 then
				intvalue = intvalue + (c - 97 + 10)
			elseif c >= 65 and c <= 70 then
				intvalue = intvalue + (c - 65 + 10)
			else
				intvalue = intvalue + (c - 48)
			end
			i = i + 1
		end
		floatvalue = Q.f(intvalue)
	elseif bit32.band(subtype, BC.TT_OCTAL) ~= 0 then
		-- step over the first zero
		i = i + 1
		while B.ch(str, i) ~= 0 do
			intvalue = intvalue * 8 + (B.ch(str, i) - 48)
			i = i + 1
		end
		floatvalue = Q.f(intvalue)
	elseif bit32.band(subtype, BC.TT_BINARY) ~= 0 then
		-- step over the leading 0b or 0B
		i = i + 2
		while B.ch(str, i) ~= 0 do
			intvalue = intvalue * 2 + (B.ch(str, i) - 48)
			i = i + 1
		end
		floatvalue = Q.f(intvalue)
	end
	return intvalue, floatvalue
end

function B.PS_ReadNumber(script, token): number
	local len = 0
	local s = ""
	local c

	token.type = BC.TT_NUMBER
	-- check for a hexadecimal number
	if cur(script, 0) == 48 and (cur(script, 1) == 120 or cur(script, 1) == 88) then
		s = s .. string.char(cur(script, 0), cur(script, 1))
		len = len + 2
		script.script_p = script.script_p + 2
		c = cur(script, 0)
		-- hexadecimal
		while (c >= 48 and c <= 57) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70) do
			s = s .. string.char(cur(script, 0))
			len = len + 1
			script.script_p = script.script_p + 1
			if len >= BC.MAX_TOKEN then
				token.string = s
				B.ScriptError(script, "hexadecimal number longer than MAX_TOKEN = %d", BC.MAX_TOKEN)
				return 0
			end
			c = cur(script, 0)
		end
		token.subtype = bit32.bor(token.subtype, BC.TT_HEX)
	-- check for a binary number
	elseif cur(script, 0) == 48 and (cur(script, 1) == 98 or cur(script, 1) == 66) then
		s = s .. string.char(cur(script, 0), cur(script, 1))
		len = len + 2
		script.script_p = script.script_p + 2
		c = cur(script, 0)
		-- binary
		while c == 48 or c == 49 do
			s = s .. string.char(cur(script, 0))
			len = len + 1
			script.script_p = script.script_p + 1
			if len >= BC.MAX_TOKEN then
				token.string = s
				B.ScriptError(script, "binary number longer than MAX_TOKEN = %d", BC.MAX_TOKEN)
				return 0
			end
			c = cur(script, 0)
		end
		token.subtype = bit32.bor(token.subtype, BC.TT_BINARY)
	else -- decimal or octal integer or floating point number
		local octal = false
		local dot = false
		if cur(script, 0) == 48 then
			octal = true
		end
		while true do
			c = cur(script, 0)
			if c == 46 then
				dot = true
			elseif c == 56 or c == 57 then
				octal = false
			elseif c < 48 or c > 57 then
				break
			end
			s = s .. string.char(cur(script, 0))
			len = len + 1
			script.script_p = script.script_p + 1
			if len >= BC.MAX_TOKEN - 1 then
				token.string = s
				B.ScriptError(script, "number longer than MAX_TOKEN = %d", BC.MAX_TOKEN)
				return 0
			end
		end
		if octal then
			token.subtype = bit32.bor(token.subtype, BC.TT_OCTAL)
		else
			token.subtype = bit32.bor(token.subtype, BC.TT_DECIMAL)
		end
		if dot then
			token.subtype = bit32.bor(token.subtype, BC.TT_FLOAT)
		end
	end
	for _ = 0, 1 do
		c = cur(script, 0)
		-- check for a LONG number
		if (c == 108 or c == 76) and bit32.band(token.subtype, BC.TT_LONG) == 0 then
			script.script_p = script.script_p + 1
			token.subtype = bit32.bor(token.subtype, BC.TT_LONG)
		-- check for an UNSIGNED number
		elseif (c == 117 or c == 85) and bit32.band(token.subtype, bit32.bor(BC.TT_UNSIGNED, BC.TT_FLOAT)) == 0 then
			script.script_p = script.script_p + 1
			token.subtype = bit32.bor(token.subtype, BC.TT_UNSIGNED)
		end
	end
	token.string = s
	token.intvalue, token.floatvalue = B.NumberValue(token.string, token.subtype)
	if bit32.band(token.subtype, BC.TT_FLOAT) == 0 then
		token.subtype = bit32.bor(token.subtype, BC.TT_INTEGER)
	end
	return 1
end

return nil
