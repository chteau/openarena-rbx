--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/l_precomp.c, part 2 of 4).

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
-- Luau port of botlib/l_precomp.c (botlib/l_precomp.c, part 2 of 4): define expansion into source, include, #define/#undef, global defines, #ifdef/#else/#endif.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")

local SF = B.FileStatics("l_precomp")

local DEFINEHASHSIZE = 1024

function B.PC_ExpandDefineIntoSource(source, deftoken, define)
	local ok, firsttoken, lasttoken = B.PC_ExpandDefine(source, deftoken, define)
	if ok == 0 then
		return 0
	end

	if firsttoken ~= nil and lasttoken ~= nil then
		lasttoken.next = source.tokens
		source.tokens = firsttoken
		return 1
	end
	return 0
end

function B.PC_ConvertPath(path: string): string
	local p = string.gsub(path, "[\\/]+", "/")
	return p
end

function B.PC_Directive_include(source)
	local script
	local token = SB.token_t()
	local path = ""

	if source.skip > 0 then
		return 1
	end
	if B.PC_ReadSourceToken(source, token) == 0 then
		B.SourceError(source, "#include without file name")
		return 0
	end
	if token.linescrossed > 0 then
		B.SourceError(source, "#include without file name")
		return 0
	end
	if token.type == BC.TT_STRING then
		token.string = B.StripDoubleQuotes(token.string)
		token.string = B.PC_ConvertPath(token.string)
		script = B.LoadScriptFile(token.string)
		if script == nil then
			path = source.includepath .. token.string
			script = B.LoadScriptFile(path)
		end
	elseif token.type == BC.TT_PUNCTUATION and string.sub(token.string, 1, 1) == "<" then
		path = source.includepath
		while B.PC_ReadSourceToken(source, token) ~= 0 do
			if token.linescrossed > 0 then
				B.PC_UnreadSourceToken(source, token)
				break
			end
			if token.type == BC.TT_PUNCTUATION and string.sub(token.string, 1, 1) == ">" then
				break
			end
			path = path .. token.string
		end
		if string.sub(token.string, 1, 1) ~= ">" then
			B.SourceWarning(source, "#include missing trailing >")
		end
		if #path == 0 then
			B.SourceError(source, "#include without file name between < >")
			return 0
		end
		path = B.PC_ConvertPath(path)
		script = B.LoadScriptFile(path)
	else
		B.SourceError(source, "#include without file name")
		return 0
	end
	if script == nil then
		B.SourceError(source, "file %s not found", path)
		return 0
	end
	B.PC_PushScript(source, script)
	return 1
end

-- reads a token from the current line, continues reading on the next
-- line only if a backslash '\' is encountered.
function B.PC_ReadLine(source, token)
	local crossline = 0
	repeat
		if B.PC_ReadSourceToken(source, token) == 0 then
			return 0
		end

		if token.linescrossed > crossline then
			B.PC_UnreadSourceToken(source, token)
			return 0
		end
		crossline = 1
	until token.string ~= "\\"
	return 1
end

function B.PC_WhiteSpaceBeforeToken(token)
	local startp = token.whitespace_p or 0
	local endp = token.endwhitespace_p or 0
	return if endp - startp > 0 then 1 else 0
end

function B.PC_ClearTokenWhiteSpace(token)
	token.whitespace_p = nil
	token.endwhitespace_p = nil
	token.linescrossed = 0
end

function B.PC_Directive_undef(source)
	local token = SB.token_t()

	if source.skip > 0 then
		return 1
	end
	if B.PC_ReadLine(source, token) == 0 then
		B.SourceError(source, "undef without name")
		return 0
	end
	if token.type ~= BC.TT_NAME then
		B.PC_UnreadSourceToken(source, token)
		B.SourceError(source, "expected name, found %s", token.string)
		return 0
	end

	local hash = B.PC_NameHash(token.string)
	local lastdefine = nil
	local define = source.definehash[hash]
	while define ~= nil do
		if define.name == token.string then
			if bit32.band(define.flags, BC.DEFINE_FIXED) ~= 0 then
				B.SourceWarning(source, "can't undef %s", token.string)
			else
				if lastdefine ~= nil then
					lastdefine.hashnext = define.hashnext
				else
					source.definehash[hash] = define.hashnext
				end
				B.PC_FreeDefine(define)
			end
			break
		end
		lastdefine = define
		define = define.hashnext
	end
	return 1
end

function B.PC_Directive_define(source)
	local token = SB.token_t()

	if source.skip > 0 then
		return 1
	end
	if B.PC_ReadLine(source, token) == 0 then
		B.SourceError(source, "#define without name")
		return 0
	end
	if token.type ~= BC.TT_NAME then
		B.PC_UnreadSourceToken(source, token)
		B.SourceError(source, "expected name after #define, found %s", token.string)
		return 0
	end
	local define = B.PC_FindHashedDefine(source.definehash, token.string)
	if define ~= nil then
		if bit32.band(define.flags, BC.DEFINE_FIXED) ~= 0 then
			B.SourceError(source, "can't redefine %s", token.string)
			return 0
		end
		B.SourceWarning(source, "redefinition of %s", token.string)
		B.PC_UnreadSourceToken(source, token)
		if B.PC_Directive_undef(source) == 0 then
			return 0
		end
	end
	define = SB.define_t()
	define.name = token.string
	B.PC_AddDefineToHash(define, source.definehash)
	if B.PC_ReadLine(source, token) == 0 then
		return 1
	end
	local last
	local t
	if B.PC_WhiteSpaceBeforeToken(token) == 0 and token.string == "(" then
		last = nil
		if B.PC_CheckTokenString(source, ")") == 0 then
			while true do
				if B.PC_ReadLine(source, token) == 0 then
					B.SourceError(source, "expected define parameter")
					return 0
				end
				if token.type ~= BC.TT_NAME then
					B.SourceError(source, "invalid define parameter")
					return 0
				end
				if B.PC_FindDefineParm(define, token.string) >= 0 then
					B.SourceError(source, "two the same define parameters")
					return 0
				end
				t = B.PC_CopyToken(token)
				B.PC_ClearTokenWhiteSpace(t)
				t.next = nil
				if last ~= nil then
					last.next = t
				else
					define.parms = t
				end
				last = t
				define.numparms += 1
				if B.PC_ReadLine(source, token) == 0 then
					B.SourceError(source, "define parameters not terminated")
					return 0
				end
				if token.string == ")" then
					break
				end
				if token.string ~= "," then
					B.SourceError(source, "define not terminated")
					return 0
				end
			end
		end
		if B.PC_ReadLine(source, token) == 0 then
			return 1
		end
	end
	last = nil
	repeat
		t = B.PC_CopyToken(token)
		if t.type == BC.TT_NAME and t.string == define.name then
			B.SourceError(source, "recursive define (removed recursion)")
		else
			B.PC_ClearTokenWhiteSpace(t)
			t.next = nil
			if last ~= nil then
				last.next = t
			else
				define.tokens = t
			end
			last = t
		end
	until B.PC_ReadLine(source, token) == 0
	if last ~= nil then
		if define.tokens.string == "##" or last.string == "##" then
			B.SourceError(source, "define with misplaced ##")
			return 0
		end
	end
	return 1
end

function B.PC_DefineFromString(str: string)
	B.PC_InitTokenHeap()

	local script = B.LoadScriptMemory(str, #str, "*extern")
	local src = SB.source_t()
	src.filename = "*extern"
	src.scriptstack = script
	src.definehash = {}
	local res = B.PC_Directive_define(src)
	local t = src.tokens
	while t ~= nil do
		src.tokens = src.tokens.next
		B.PC_FreeToken(t)
		t = src.tokens
	end
	local def = nil
	for i = 0, DEFINEHASHSIZE - 1 do
		if src.definehash[i] ~= nil then
			def = src.definehash[i]
			break
		end
	end
	src.definehash = nil
	B.FreeScript(script)
	if res > 0 then
		return def
	end
	if src.defines ~= nil then
		B.PC_FreeDefine(def)
	end
	return nil
end

function B.PC_AddDefine(source, str: string)
	local define = B.PC_DefineFromString(str)
	if define == nil then
		return 0
	end
	B.PC_AddDefineToHash(define, source.definehash)
	return 1
end

-- add a globals define that will be added to all opened sources
function B.PC_AddGlobalDefine(str: string)
	local define = B.PC_DefineFromString(str)
	if define == nil then
		return 0
	end
	define.next = SF.globaldefines
	SF.globaldefines = define
	return 1
end

-- remove the given global define
function B.PC_RemoveGlobalDefine(name: string)
	local define = B.PC_FindDefine(SF.globaldefines, name)
	if define ~= nil then
		B.PC_FreeDefine(define)
		return 1
	end
	return 0
end

-- remove all globals defines
function B.PC_RemoveAllGlobalDefines()
	local define = SF.globaldefines
	while define ~= nil do
		SF.globaldefines = SF.globaldefines.next
		B.PC_FreeDefine(define)
		define = SF.globaldefines
	end
end

function B.PC_CopyDefine(source, define)
	local newdefine = SB.define_t()
	newdefine.name = define.name
	newdefine.flags = define.flags
	newdefine.builtin = define.builtin
	newdefine.numparms = define.numparms
	newdefine.next = nil
	newdefine.hashnext = nil
	newdefine.tokens = nil
	local lasttoken = nil
	local token = define.tokens
	while token ~= nil do
		local newtoken = B.PC_CopyToken(token)
		newtoken.next = nil
		if lasttoken ~= nil then
			lasttoken.next = newtoken
		else
			newdefine.tokens = newtoken
		end
		lasttoken = newtoken
		token = token.next
	end
	newdefine.parms = nil
	lasttoken = nil
	token = define.parms
	while token ~= nil do
		local newtoken = B.PC_CopyToken(token)
		newtoken.next = nil
		if lasttoken ~= nil then
			lasttoken.next = newtoken
		else
			newdefine.parms = newtoken
		end
		lasttoken = newtoken
		token = token.next
	end
	return newdefine
end

function B.PC_AddGlobalDefinesToSource(source)
	local define = SF.globaldefines
	while define ~= nil do
		local newdefine = B.PC_CopyDefine(source, define)
		B.PC_AddDefineToHash(newdefine, source.definehash)
		define = define.next
	end
end

function B.PC_Directive_if_def(source, itype: number)
	local token = SB.token_t()

	if B.PC_ReadLine(source, token) == 0 then
		B.SourceError(source, "#ifdef without name")
		return 0
	end
	if token.type ~= BC.TT_NAME then
		B.PC_UnreadSourceToken(source, token)
		B.SourceError(source, "expected name after #ifdef, found %s", token.string)
		return 0
	end
	local d = B.PC_FindHashedDefine(source.definehash, token.string)
	local skip = if (itype == BC.INDENT_IFDEF) == (d == nil) then 1 else 0
	B.PC_PushIndent(source, itype, skip)
	return 1
end

function B.PC_Directive_ifdef(source)
	return B.PC_Directive_if_def(source, BC.INDENT_IFDEF)
end

function B.PC_Directive_ifndef(source)
	return B.PC_Directive_if_def(source, BC.INDENT_IFNDEF)
end

function B.PC_Directive_else(source)
	local itype, skip = B.PC_PopIndent(source)
	if itype == 0 then
		B.SourceError(source, "misplaced #else")
		return 0
	end
	if itype == BC.INDENT_ELSE then
		B.SourceError(source, "#else after #else")
		return 0
	end
	B.PC_PushIndent(source, BC.INDENT_ELSE, if skip == 0 then 1 else 0)
	return 1
end

function B.PC_Directive_endif(source)
	local itype, _skip = B.PC_PopIndent(source)
	if itype == 0 then
		B.SourceError(source, "misplaced #endif")
		return 0
	end
	return 1
end

return nil
