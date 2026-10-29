--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/l_precomp.c, part 4 of 4).

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
-- Luau port of l_precomp.c (botlib/l_precomp.c, part 4 of 4): eval directives, token reading, source loading.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("l_precomp")

local MAX_TOKEN = 1024
local DEFINEHASHSIZE = 1024
local MAX_SOURCEFILES = 64
local PATHSEPERATOR_STR = "/"

SF.sourceFiles = {}

function B.PC_Directive_eval(source)
	local ret, value = B.PC_Evaluate(source, 1)
	if ret == 0 then
		return 0
	end
	local token = SB.token_t()
	token.line = source.scriptstack.line
	token.whitespace_p = source.scriptstack.script_p
	token.endwhitespace_p = source.scriptstack.script_p
	token.linescrossed = 0
	token.string = QS.va("%d", math.abs(value))
	token.type = BC.TT_NUMBER
	token.subtype = bit32.bor(BC.TT_INTEGER, BC.TT_LONG, BC.TT_DECIMAL)
	B.PC_UnreadSourceToken(source, token)
	if value < 0 then
		B.UnreadSignToken(source)
	end
	return 1
end

function B.PC_Directive_evalfloat(source)
	local ret, _, value = B.PC_Evaluate(source, 0)
	if ret == 0 then
		return 0
	end
	local token = SB.token_t()
	token.line = source.scriptstack.line
	token.whitespace_p = source.scriptstack.script_p
	token.endwhitespace_p = source.scriptstack.script_p
	token.linescrossed = 0
	token.string = QS.va("%1.2f", math.abs(value))
	token.type = BC.TT_NUMBER
	token.subtype = bit32.bor(BC.TT_FLOAT, BC.TT_LONG, BC.TT_DECIMAL)
	B.PC_UnreadSourceToken(source, token)
	if value < 0 then
		B.UnreadSignToken(source)
	end
	return 1
end

local directives = {
	{ name = "if", func = function(s) return B.PC_Directive_if(s) end },
	{ name = "ifdef", func = function(s) return B.PC_Directive_ifdef(s) end },
	{ name = "ifndef", func = function(s) return B.PC_Directive_ifndef(s) end },
	{ name = "elif", func = function(s) return B.PC_Directive_elif(s) end },
	{ name = "else", func = function(s) return B.PC_Directive_else(s) end },
	{ name = "endif", func = function(s) return B.PC_Directive_endif(s) end },
	{ name = "include", func = function(s) return B.PC_Directive_include(s) end },
	{ name = "define", func = function(s) return B.PC_Directive_define(s) end },
	{ name = "undef", func = function(s) return B.PC_Directive_undef(s) end },
	{ name = "line", func = function(s) return B.PC_Directive_line(s) end },
	{ name = "error", func = function(s) return B.PC_Directive_error(s) end },
	{ name = "pragma", func = function(s) return B.PC_Directive_pragma(s) end },
	{ name = "eval", func = function(s) return B.PC_Directive_eval(s) end },
	{ name = "evalfloat", func = function(s) return B.PC_Directive_evalfloat(s) end },
}

function B.PC_ReadDirective(source)
	local token = SB.token_t()
	if B.PC_ReadSourceToken(source, token) == 0 then
		B.SourceError(source, "found # without name")
		return 0
	end
	if token.linescrossed > 0 then
		B.PC_UnreadSourceToken(source, token)
		B.SourceError(source, "found # at end of line")
		return 0
	end
	if token.type == BC.TT_NAME then
		for _, d in directives do
			if d.name == token.string then
				return d.func(source)
			end
		end
	end
	B.SourceError(source, "unknown precompiler directive %s", token.string)
	return 0
end

function B.PC_DollarDirective_evalint(source)
	local ret, value = B.PC_DollarEvaluate(source, 1)
	if ret == 0 then
		return 0
	end
	local token = SB.token_t()
	token.line = source.scriptstack.line
	token.whitespace_p = source.scriptstack.script_p
	token.endwhitespace_p = source.scriptstack.script_p
	token.linescrossed = 0
	token.string = QS.va("%d", math.abs(value))
	token.type = BC.TT_NUMBER
	token.subtype = bit32.bor(BC.TT_INTEGER, BC.TT_LONG, BC.TT_DECIMAL)

	token.intvalue = math.abs(value)
	token.floatvalue = token.intvalue

	B.PC_UnreadSourceToken(source, token)
	if value < 0 then
		B.UnreadSignToken(source)
	end
	return 1
end

function B.PC_DollarDirective_evalfloat(source)
	local ret, _, value = B.PC_DollarEvaluate(source, 0)
	if ret == 0 then
		return 0
	end
	local token = SB.token_t()
	token.line = source.scriptstack.line
	token.whitespace_p = source.scriptstack.script_p
	token.endwhitespace_p = source.scriptstack.script_p
	token.linescrossed = 0
	token.string = QS.va("%1.2f", math.abs(value))
	token.type = BC.TT_NUMBER
	token.subtype = bit32.bor(BC.TT_FLOAT, BC.TT_LONG, BC.TT_DECIMAL)

	token.floatvalue = math.abs(value)
	token.intvalue = math.floor(token.floatvalue)

	B.PC_UnreadSourceToken(source, token)
	if value < 0 then
		B.UnreadSignToken(source)
	end
	return 1
end

local dollardirectives = {
	{ name = "evalint", func = function(s) return B.PC_DollarDirective_evalint(s) end },
	{ name = "evalfloat", func = function(s) return B.PC_DollarDirective_evalfloat(s) end },
}

function B.PC_ReadDollarDirective(source)
	local token = SB.token_t()
	if B.PC_ReadSourceToken(source, token) == 0 then
		B.SourceError(source, "found $ without name")
		return 0
	end
	if token.linescrossed > 0 then
		B.PC_UnreadSourceToken(source, token)
		B.SourceError(source, "found $ at end of line")
		return 0
	end
	if token.type == BC.TT_NAME then
		for _, d in dollardirectives do
			if d.name == token.string then
				return d.func(source)
			end
		end
	end
	B.PC_UnreadSourceToken(source, token)
	B.SourceError(source, "unknown precompiler directive %s", token.string)
	return 0
end

function B.PC_ReadToken(source, token)
	while true do
		if B.PC_ReadSourceToken(source, token) == 0 then
			return 0
		end
		-- check for precompiler directives
		if token.type == BC.TT_PUNCTUATION and B.ch(token.string, 0) == string.byte("#") then
			if B.PC_ReadDirective(source) == 0 then
				return 0
			end
			continue
		end
		if token.type == BC.TT_PUNCTUATION and B.ch(token.string, 0) == string.byte("$") then
			if B.PC_ReadDollarDirective(source) == 0 then
				return 0
			end
			continue
		end
		-- recursively concatenate strings that are behind each other still resolving defines
		if token.type == BC.TT_STRING then
			local newtoken = SB.token_t()
			if B.PC_ReadToken(source, newtoken) ~= 0 then
				if newtoken.type == BC.TT_STRING then
					token.string = string.sub(token.string, 1, #token.string - 1)
					if #token.string + (#newtoken.string - 1) + 1 >= MAX_TOKEN then
						B.SourceError(source, "string longer than MAX_TOKEN %d", MAX_TOKEN)
						return 0
					end
					token.string = token.string .. string.sub(newtoken.string, 2)
				else
					B.PC_UnreadToken(source, newtoken)
				end
			end
		end
		-- if skipping source because of conditional compilation
		if source.skip ~= 0 then
			continue
		end
		if token.type == BC.TT_NAME then
			local define = B.PC_FindHashedDefine(source.definehash, token.string)
			if define ~= nil then
				if B.PC_ExpandDefineIntoSource(source, token, define) == 0 then
					return 0
				end
				continue
			end
		end
		-- copy token for unreading
		SB.copy_token_t(source.token, token)
		return 1
	end
end

function B.PC_ExpectTokenString(source, string_)
	local token = SB.token_t()
	if B.PC_ReadToken(source, token) == 0 then
		B.SourceError(source, "couldn't find expected %s", string_)
		return 0
	end
	if token.string ~= string_ then
		B.SourceError(source, "expected %s, found %s", string_, token.string)
		return 0
	end
	return 1
end

function B.PC_ExpectTokenType(source, type_, subtype, token)
	if B.PC_ReadToken(source, token) == 0 then
		B.SourceError(source, "couldn't read expected token")
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
		B.SourceError(source, "expected a %s, found %s", str, token.string)
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
			B.SourceError(source, "expected %s, found %s", str, token.string)
			return 0
		end
	elseif token.type == BC.TT_PUNCTUATION then
		if token.subtype ~= subtype then
			B.SourceError(source, "found %s", token.string)
			return 0
		end
	end
	return 1
end

function B.PC_ExpectAnyToken(source, token)
	if B.PC_ReadToken(source, token) == 0 then
		B.SourceError(source, "couldn't read expected token")
		return 0
	else
		return 1
	end
end

function B.PC_CheckTokenString(source, string_)
	local tok = SB.token_t()
	if B.PC_ReadToken(source, tok) == 0 then
		return 0
	end
	-- if the token is available
	if tok.string == string_ then
		return 1
	end
	B.PC_UnreadSourceToken(source, tok)
	return 0
end

function B.PC_CheckTokenType(source, type_, subtype, token)
	local tok = SB.token_t()
	if B.PC_ReadToken(source, tok) == 0 then
		return 0
	end
	-- if the type matches
	if tok.type == type_ and bit32.band(tok.subtype, subtype) == subtype then
		SB.copy_token_t(token, tok)
		return 1
	end
	B.PC_UnreadSourceToken(source, tok)
	return 0
end

function B.PC_SkipUntilString(source, string_)
	local token = SB.token_t()
	while B.PC_ReadToken(source, token) ~= 0 do
		if token.string == string_ then
			return 1
		end
	end
	return 0
end

function B.PC_UnreadLastToken(source)
	B.PC_UnreadSourceToken(source, source.token)
end

function B.PC_UnreadToken(source, token)
	B.PC_UnreadSourceToken(source, token)
end

function B.PC_SetIncludePath(source, path)
	source.includepath = QS.Q_strncpyz(path, 1024 - 1)

	local len = #source.includepath
	-- add trailing path seperator
	if len > 0 and B.ch(source.includepath, len) ~= string.byte("\\") and B.ch(source.includepath, len) ~= string.byte("/") then
		source.includepath = source.includepath .. PATHSEPERATOR_STR
	end
end

function B.PC_SetPunctuations(source, p)
	source.punctuations = p
end

local function NewSource(script, name)
	script.next = nil

	local source = SB.source_t()
	source.filename = QS.Q_strncpyz(name, 1024)
	source.scriptstack = script
	source.tokens = nil
	source.defines = nil
	source.indentstack = nil
	source.skip = 0

	source.definehash = {}
	B.PC_AddGlobalDefinesToSource(source)
	return source
end

function B.LoadSourceFile(filename)
	B.PC_InitTokenHeap()

	local script = B.LoadScriptFile(filename)
	if script == nil then
		return nil
	end
	return NewSource(script, filename)
end

function B.LoadSourceMemory(ptr, length, name)
	B.PC_InitTokenHeap()

	local script = B.LoadScriptMemory(ptr, length, name)
	if script == nil then
		return nil
	end
	return NewSource(script, name)
end

function B.FreeSource(source)
	-- free all the scripts
	while source.scriptstack ~= nil do
		local script = source.scriptstack
		source.scriptstack = source.scriptstack.next
		B.FreeScript(script)
	end
	-- free all the tokens
	while source.tokens ~= nil do
		local token = source.tokens
		source.tokens = source.tokens.next
		B.PC_FreeToken(token)
	end
	for i = 0, DEFINEHASHSIZE - 1 do
		while source.definehash[i] ~= nil do
			local define = source.definehash[i]
			source.definehash[i] = source.definehash[i].hashnext
			B.PC_FreeDefine(define)
		end
	end
	-- free all indents
	while source.indentstack ~= nil do
		local indent = source.indentstack
		source.indentstack = source.indentstack.next
		indent.next = nil
	end
	source.definehash = nil
end

function B.PC_LoadSourceHandle(filename)
	local sourceFiles = SF.sourceFiles
	local i = 1
	while i < MAX_SOURCEFILES do
		if sourceFiles[i] == nil then
			break
		end
		i = i + 1
	end
	if i >= MAX_SOURCEFILES then
		return 0
	end
	B.PS_SetBaseFolder("")
	local source = B.LoadSourceFile(filename)
	if source == nil then
		return 0
	end
	sourceFiles[i] = source
	return i
end

function B.PC_FreeSourceHandle(handle)
	if handle < 1 or handle >= MAX_SOURCEFILES then
		return 0
	end
	if SF.sourceFiles[handle] == nil then
		return 0
	end

	B.FreeSource(SF.sourceFiles[handle])
	SF.sourceFiles[handle] = nil
	return 1
end

function B.PC_ReadTokenHandle(handle, pc_token)
	if handle < 1 or handle >= MAX_SOURCEFILES then
		return 0
	end
	if SF.sourceFiles[handle] == nil then
		return 0
	end

	local token = SB.token_t()
	local ret = B.PC_ReadToken(SF.sourceFiles[handle], token)
	pc_token.string = token.string
	pc_token.type = token.type
	pc_token.subtype = token.subtype
	pc_token.intvalue = token.intvalue
	pc_token.floatvalue = token.floatvalue
	if pc_token.type == BC.TT_STRING then
		pc_token.string = B.StripDoubleQuotes(pc_token.string)
	end
	return ret
end

function B.PC_SourceFileAndLine(handle)
	if handle < 1 or handle >= MAX_SOURCEFILES then
		return 0, "", 0
	end
	local source = SF.sourceFiles[handle]
	if source == nil then
		return 0, "", 0
	end

	local line = 0
	if source.scriptstack ~= nil then
		line = source.scriptstack.line
	end
	return 1, source.filename, line
end

function B.PC_SetBaseFolder(path)
	B.PS_SetBaseFolder(path)
end

function B.PC_CheckOpenSourceHandles()
	for i = 1, MAX_SOURCEFILES - 1 do
		if SF.sourceFiles[i] ~= nil then
			B.botimport.Print(BC.PRT_ERROR, "file %s still open in precompiler\n", SF.sourceFiles[i].scriptstack.filename)
		end
	end
end

return nil
