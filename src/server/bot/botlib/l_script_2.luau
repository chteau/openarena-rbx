--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/l_script.c, part 2 of 2).

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
-- Luau port of l_script.c (botlib/l_script.c, part 2 of 2): token reading and script loading.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("l_script")

local QUOTE_DOUBLE = 34
local QUOTE_SINGLE = 39

function B.PS_ReadLiteral(script, token)
	token.type = BC.TT_LITERAL
	local buf = script.buffer
	--first quote
	local s = string.char(B.ch(buf, script.script_p))
	script.script_p = script.script_p + 1
	--check for end of file
	if B.ch(buf, script.script_p) == 0 then
		B.ScriptError(script, "end of file before trailing '")
		return 0
	end
	local c1
	--if it is an escape character
	if B.ch(buf, script.script_p) == 92 then
		local ok, ch = B.PS_ReadEscapeCharacter(script)
		if ok == 0 then
			return 0
		end
		if type(ch) == "number" then
			c1 = string.char(ch)
		else
			c1 = ch
		end
	else
		c1 = string.char(B.ch(buf, script.script_p))
		script.script_p = script.script_p + 1
	end
	--check for trailing quote
	if B.ch(buf, script.script_p) ~= QUOTE_SINGLE then
		B.ScriptWarning(script, "too many characters in literal, ignored")
		while
			B.ch(buf, script.script_p) ~= 0
			and B.ch(buf, script.script_p) ~= QUOTE_SINGLE
			and B.ch(buf, script.script_p) ~= 10
		do
			script.script_p = script.script_p + 1
		end
		if B.ch(buf, script.script_p) == QUOTE_SINGLE then
			script.script_p = script.script_p + 1
		end
	end
	--store the trailing quote
	local c2 = string.char(B.ch(buf, script.script_p))
	script.script_p = script.script_p + 1
	token.string = s .. c1 .. c2
	--the sub type is the integer literal value
	token.subtype = string.byte(c1)
	return 1
end

function B.PS_ReadPunctuation(script, token)
	local buf = script.buffer
	local punc = script.punctuationtable[B.ch(buf, script.script_p)]
	while punc ~= nil do
		local p = punc.p
		local len = #p
		--if the script contains at least as much characters as the punctuation
		if script.script_p + len <= script.end_p then
			--if the script contains the punctuation
			if string.sub(buf, script.script_p + 1, script.script_p + len) == p then
				token.string = QS.Q_strncpyz(p, BC.MAX_TOKEN)
				script.script_p = script.script_p + len
				token.type = BC.TT_PUNCTUATION
				--sub type is the number of the punctuation
				token.subtype = punc.n
				return 1
			end
		end
		punc = punc.next
	end
	return 0
end

function B.PS_ReadPrimitive(script, token)
	local buf = script.buffer
	local len = 0
	local parts = {}
	while B.ch(buf, script.script_p) > 32 and B.ch(buf, script.script_p) ~= 59 do
		if len >= BC.MAX_TOKEN - 1 then
			B.ScriptError(script, "primitive token longer than MAX_TOKEN = %d", BC.MAX_TOKEN)
			return 0
		end
		len = len + 1
		parts[len] = string.char(B.ch(buf, script.script_p))
		script.script_p = script.script_p + 1
	end
	token.string = table.concat(parts)
	--copy the token into the script structure
	SB.copy_token_t(script.token, token)
	--primitive reading successful
	return 1
end

function B.PS_ReadToken(script, token)
	--if there is a token available (from UnreadToken)
	if script.tokenavailable ~= 0 then
		script.tokenavailable = 0
		SB.copy_token_t(token, script.token)
		return 1
	end
	--save script pointer
	script.lastscript_p = script.script_p
	--save line counter
	script.lastline = script.line
	--clear the token stuff
	SB.copy_token_t(token, SB.token_t())
	--start of the white space
	script.whitespace_p = script.script_p
	token.whitespace_p = script.script_p
	--read unusefull stuff
	if B.PS_ReadWhiteSpace(script) == 0 then
		return 0
	end
	--end of the white space
	script.endwhitespace_p = script.script_p
	token.endwhitespace_p = script.script_p
	--line the token is on
	token.line = script.line
	--number of lines crossed before token
	token.linescrossed = script.line - script.lastline
	local buf = script.buffer
	local c = B.ch(buf, script.script_p)
	local c1 = B.ch(buf, script.script_p + 1)
	--if there is a leading double quote
	if c == QUOTE_DOUBLE then
		if B.PS_ReadString(script, token, QUOTE_DOUBLE) == 0 then
			return 0
		end
	--if a literal
	elseif c == QUOTE_SINGLE then
		if B.PS_ReadString(script, token, QUOTE_SINGLE) == 0 then
			return 0
		end
	--if there is a number
	elseif (c >= 48 and c <= 57) or (c == 46 and (c1 >= 48 and c1 <= 57)) then
		if B.PS_ReadNumber(script, token) == 0 then
			return 0
		end
	--if this is a primitive script
	elseif bit32.band(script.flags, BC.SCFL_PRIMITIVE) ~= 0 then
		return B.PS_ReadPrimitive(script, token)
	--if there is a name
	elseif (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or c == 95 then
		if B.PS_ReadName(script, token) == 0 then
			return 0
		end
	--check for punctuations
	elseif B.PS_ReadPunctuation(script, token) == 0 then
		B.ScriptError(script, "can't read token")
		return 0
	end
	--copy the token into the script structure
	SB.copy_token_t(script.token, token)
	--successfully read a token
	return 1
end

function B.PS_ExpectTokenString(script, str)
	local token = SB.token_t()

	if B.PS_ReadToken(script, token) == 0 then
		B.ScriptError(script, "couldn't find expected %s", str)
		return 0
	end

	if token.string ~= str then
		B.ScriptError(script, "expected %s, found %s", str, token.string)
		return 0
	end
	return 1
end

function B.PS_ExpectTokenType(script, type_, subtype, token)
	if B.PS_ReadToken(script, token) == 0 then
		B.ScriptError(script, "couldn't read expected token")
		return 0
	end

	if token.type ~= type_ then
		local str = ""
		if type_ == BC.TT_STRING then
			str = "string"
		end
		if type_ == BC.TT_LITERAL then
			str = "literal"
		end
		if type_ == BC.TT_NUMBER then
			str = "number"
		end
		if type_ == BC.TT_NAME then
			str = "name"
		end
		if type_ == BC.TT_PUNCTUATION then
			str = "punctuation"
		end
		B.ScriptError(script, "expected a %s, found %s", str, token.string)
		return 0
	end
	if token.type == BC.TT_NUMBER then
		if bit32.band(token.subtype, subtype) ~= subtype then
			local str = ""
			if bit32.band(subtype, BC.TT_DECIMAL) ~= 0 then
				str = "decimal"
			end
			if bit32.band(subtype, BC.TT_HEX) ~= 0 then
				str = "hex"
			end
			if bit32.band(subtype, BC.TT_OCTAL) ~= 0 then
				str = "octal"
			end
			if bit32.band(subtype, BC.TT_BINARY) ~= 0 then
				str = "binary"
			end
			if bit32.band(subtype, BC.TT_LONG) ~= 0 then
				str = str .. " long"
			end
			if bit32.band(subtype, BC.TT_UNSIGNED) ~= 0 then
				str = str .. " unsigned"
			end
			if bit32.band(subtype, BC.TT_FLOAT) ~= 0 then
				str = str .. " float"
			end
			if bit32.band(subtype, BC.TT_INTEGER) ~= 0 then
				str = str .. " integer"
			end
			B.ScriptError(script, "expected %s, found %s", str, token.string)
			return 0
		end
	elseif token.type == BC.TT_PUNCTUATION then
		if subtype < 0 then
			B.ScriptError(script, "BUG: wrong punctuation subtype")
			return 0
		end
		if token.subtype ~= subtype then
			B.ScriptError(script, "expected %s, found %s", script.punctuations[subtype].p, token.string)
			return 0
		end
	end
	return 1
end

function B.PS_ExpectAnyToken(script, token)
	if B.PS_ReadToken(script, token) == 0 then
		B.ScriptError(script, "couldn't read expected token")
		return 0
	else
		return 1
	end
end

function B.PS_CheckTokenString(script, str)
	local tok = SB.token_t()

	if B.PS_ReadToken(script, tok) == 0 then
		return 0
	end
	--if the token is available
	if tok.string == str then
		return 1
	end
	--token not available
	script.script_p = script.lastscript_p
	return 0
end

function B.PS_CheckTokenType(script, type_, subtype, token)
	local tok = SB.token_t()

	if B.PS_ReadToken(script, tok) == 0 then
		return 0
	end
	--if the type matches
	if tok.type == type_ and bit32.band(tok.subtype, subtype) == subtype then
		SB.copy_token_t(token, tok)
		return 1
	end
	--token is not available
	script.script_p = script.lastscript_p
	return 0
end

function B.PS_SkipUntilString(script, str)
	local token = SB.token_t()

	while B.PS_ReadToken(script, token) ~= 0 do
		if token.string == str then
			return 1
		end
	end
	return 0
end

function B.PS_UnreadLastToken(script)
	script.tokenavailable = 1
end

function B.PS_UnreadToken(script, token)
	SB.copy_token_t(script.token, token)
	script.tokenavailable = 1
end

-- returns the next character of the read white space, returns 0 if none
function B.PS_NextWhiteSpaceChar(script)
	if script.whitespace_p ~= script.endwhitespace_p then
		local c = B.ch(script.buffer, script.whitespace_p)
		script.whitespace_p = script.whitespace_p + 1
		return c
	else
		return 0
	end
end

function B.StripDoubleQuotes(str)
	if B.ch(str, 0) == QUOTE_DOUBLE then
		str = string.sub(str, 2)
	end
	if #str > 0 and B.ch(str, #str - 1) == QUOTE_DOUBLE then
		str = string.sub(str, 1, #str - 1)
	end
	return str
end

function B.StripSingleQuotes(str)
	if B.ch(str, 0) == QUOTE_SINGLE then
		str = string.sub(str, 2)
	end
	if #str > 0 and B.ch(str, #str - 1) == QUOTE_SINGLE then
		str = string.sub(str, 1, #str - 1)
	end
	return str
end

function B.ReadSignedFloat(script)
	local token = SB.token_t()
	local sign = 1.0

	B.PS_ExpectAnyToken(script, token)
	if token.string == "-" then
		if B.PS_ExpectAnyToken(script, token) == 0 then
			B.ScriptError(script, "Missing float value")
			return 0
		end

		sign = -1.0
	end

	if token.type ~= BC.TT_NUMBER then
		B.ScriptError(script, "expected float value, found %s", token.string)
		return 0
	end

	return sign * token.floatvalue
end

function B.ReadSignedInt(script)
	local token = SB.token_t()
	local sign = 1

	B.PS_ExpectAnyToken(script, token)
	if token.string == "-" then
		if B.PS_ExpectAnyToken(script, token) == 0 then
			B.ScriptError(script, "Missing integer value")
			return 0
		end

		sign = -1
	end

	if token.type ~= BC.TT_NUMBER or token.subtype == BC.TT_FLOAT then
		B.ScriptError(script, "expected integer value, found %s", token.string)
		return 0
	end

	return sign * token.intvalue
end

function B.SetScriptFlags(script, flags)
	script.flags = flags
end

function B.GetScriptFlags(script)
	return script.flags
end

function B.ResetScript(script)
	--pointer in script buffer
	script.script_p = 0
	--pointer in script buffer before reading token
	script.lastscript_p = 0
	--begin of white space
	script.whitespace_p = nil
	--end of white space
	script.endwhitespace_p = nil
	--set if there's a token available in script->token
	script.tokenavailable = 0
	script.line = 1
	script.lastline = 1
	--clear the saved token
	SB.copy_token_t(script.token, SB.token_t())
end

-- returns true if at the end of the script
function B.EndOfScript(script)
	if script.script_p >= script.end_p then
		return 1
	end
	return 0
end

function B.NumLinesCrossed(script)
	return script.line - script.lastline
end

function B.ScriptSkipTo(script, value)
	local firstchar = B.ch(value, 0)
	local len = #value
	while true do
		if B.PS_ReadWhiteSpace(script) == 0 then
			return 0
		end
		if B.ch(script.buffer, script.script_p) == firstchar then
			if string.sub(script.buffer, script.script_p + 1, script.script_p + len) == value then
				return 1
			end
		end
		script.script_p = script.script_p + 1
	end
end

function B.LoadScriptFile(filename)
	local pathname
	local basefolder = SF.basefolder or ""
	if #basefolder ~= 0 then
		pathname = QS.Com_sprintf(BC.MAX_QPATH, "%s/%s", basefolder, filename)
	else
		pathname = QS.Com_sprintf(BC.MAX_QPATH, "%s", filename)
	end
	local data = B.botimport.FS_ReadFile(pathname)
	if data == nil then
		return nil
	end
	local length = buffer.len(data)

	local script = SB.script_t()
	script.filename = QS.Q_strncpyz(filename, 1024)
	script.buffer = buffer.tostring(data)
	script.length = length
	--pointer in script buffer
	script.script_p = 0
	--pointer in script buffer before reading token
	script.lastscript_p = 0
	--pointer to end of script buffer
	script.end_p = length
	--set if there's a token available in script->token
	script.tokenavailable = 0
	script.line = 1
	script.lastline = 1
	B.SetScriptPunctuations(script, nil)

	return script
end

function B.LoadScriptMemory(ptr, length, name)
	local script = SB.script_t()
	script.filename = QS.Q_strncpyz(name, 1024)
	script.buffer = string.sub(ptr, 1, length)
	script.length = length
	--pointer in script buffer
	script.script_p = 0
	--pointer in script buffer before reading token
	script.lastscript_p = 0
	--pointer to end of script buffer
	script.end_p = length
	--set if there's a token available in script->token
	script.tokenavailable = 0
	script.line = 1
	script.lastline = 1
	B.SetScriptPunctuations(script, nil)

	return script
end

function B.FreeScript(script)
	script.punctuationtable = nil
end

function B.PS_SetBaseFolder(path)
	SF.basefolder = QS.Com_sprintf(BC.MAX_QPATH, "%s", path)
end

return nil
