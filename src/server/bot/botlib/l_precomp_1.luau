--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/l_precomp.c, part 1 of 4).

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
-- Luau port of l_precomp.c (botlib/l_precomp.c, part 1 of 4): pre compiler, token and define handling.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("l_precomp")

SF.MAX_DEFINEPARMS = 128
SF.DEFINEHASHSIZE = 1024
SF.TOKEN_HEAP_SIZE = 4096

SF.numtokens = 0

-- list with global defines added to every source loaded
SF.globaldefines = nil

local MAX_DEFINEPARMS = SF.MAX_DEFINEPARMS
local DEFINEHASHSIZE = SF.DEFINEHASHSIZE

function B.SourceError(source, str, ...)
	local text = QS.va(str, ...)
	B.botimport.Print(BC.PRT_ERROR, "file %s, line %d: %s\n", source.scriptstack.filename, source.scriptstack.line, text)
end

function B.SourceWarning(source, str, ...)
	local text = QS.va(str, ...)
	B.botimport.Print(BC.PRT_WARNING, "file %s, line %d: %s\n", source.scriptstack.filename, source.scriptstack.line, text)
end

function B.PC_PushIndent(source, type_, skip)
	local indent = SB.indent_t()
	indent.type = type_
	indent.script = source.scriptstack
	indent.skip = if skip ~= 0 then 1 else 0
	source.skip = source.skip + indent.skip
	indent.next = source.indentstack
	source.indentstack = indent
end

function B.PC_PopIndent(source)
	local type_ = 0
	local skip = 0

	local indent = source.indentstack
	if indent == nil then
		return type_, skip
	end

	-- must be an indent from the current script
	if source.indentstack.script ~= source.scriptstack then
		return type_, skip
	end

	type_ = indent.type
	skip = indent.skip
	source.indentstack = source.indentstack.next
	source.skip = source.skip - indent.skip
	return type_, skip
end

function B.PC_PushScript(source, script)
	local s = source.scriptstack
	while s ~= nil do
		if QS.Q_stricmp(s.filename, script.filename) == 0 then
			B.SourceError(source, "%s recursively included", script.filename)
			return
		end
		s = s.next
	end
	-- push the script on the script stack
	script.next = source.scriptstack
	source.scriptstack = script
end

function B.PC_InitTokenHeap()
end

function B.PC_CopyToken(token)
	local t = SB.token_t()
	SB.copy_token_t(t, token)
	t.next = nil
	SF.numtokens = SF.numtokens + 1
	return t
end

function B.PC_FreeToken(token)
	SF.numtokens = SF.numtokens - 1
end

function B.PC_ReadSourceToken(source, token)
	-- if there's no token already available
	while source.tokens == nil do
		-- if there's a token to read from the script
		if B.PS_ReadToken(source.scriptstack, token) ~= 0 then
			return 1
		end
		-- if at the end of the script
		if B.EndOfScript(source.scriptstack) ~= 0 then
			-- remove all indents of the script
			while source.indentstack ~= nil and source.indentstack.script == source.scriptstack do
				B.SourceWarning(source, "missing #endif")
				B.PC_PopIndent(source)
			end
		end
		-- if this was the initial script
		if source.scriptstack.next == nil then
			return 0
		end
		-- remove the script and return to the last one
		local script = source.scriptstack
		source.scriptstack = source.scriptstack.next
		B.FreeScript(script)
	end
	-- copy the already available token
	SB.copy_token_t(token, source.tokens)
	-- free the read token
	local t = source.tokens
	source.tokens = source.tokens.next
	B.PC_FreeToken(t)
	return 1
end

function B.PC_UnreadSourceToken(source, token)
	local t = B.PC_CopyToken(token)
	t.next = source.tokens
	source.tokens = t
	return 1
end

function B.PC_ReadDefineParms(source, define, parms, maxparms)
	local token = SB.token_t()

	if B.PC_ReadSourceToken(source, token) == 0 then
		B.SourceError(source, "define %s missing parms", define.name)
		return 0
	end
	--
	if define.numparms > maxparms then
		B.SourceError(source, "define with more than %d parameters", maxparms)
		return 0
	end
	--
	for i = 0, define.numparms - 1 do
		parms[i] = nil
	end
	-- if no leading "("
	if token.string ~= "(" then
		B.PC_UnreadSourceToken(source, token)
		B.SourceError(source, "define %s missing parms", define.name)
		return 0
	end
	-- read the define parameters
	local done = false
	local numparms = 0
	local indent = 0
	while not done do
		if numparms >= maxparms then
			B.SourceError(source, "define %s with too many parms", define.name)
			return 0
		end
		if numparms >= define.numparms then
			B.SourceWarning(source, "define %s has too many parms", define.name)
			return 0
		end
		parms[numparms] = nil
		local lastcomma = true
		local last = nil
		while not done do
			--
			if B.PC_ReadSourceToken(source, token) == 0 then
				B.SourceError(source, "define %s incomplete", define.name)
				return 0
			end
			--
			if token.string == "," then
				if indent <= 0 then
					if lastcomma then
						B.SourceWarning(source, "too many comma's")
					end
					break
				end
			end
			lastcomma = false
			--
			if token.string == "(" then
				indent = indent + 1
				continue
			elseif token.string == ")" then
				indent = indent - 1
				if indent <= 0 then
					if parms[define.numparms - 1] == nil then
						B.SourceWarning(source, "too few define parms")
					end
					done = true
					break
				end
			end
			--
			if numparms < define.numparms then
				--
				local t = B.PC_CopyToken(token)
				t.next = nil
				if last ~= nil then
					last.next = t
				else
					parms[numparms] = t
				end
				last = t
			end
		end
		numparms = numparms + 1
	end
	return 1
end

function B.PC_StringizeTokens(tokens, token)
	token.type = BC.TT_STRING
	token.whitespace_p = nil
	token.endwhitespace_p = nil
	local s = "\""
	local t = tokens
	while t ~= nil do
		s = string.sub(s .. t.string, 1, BC.MAX_TOKEN - 1)
		t = t.next
	end
	if #s < BC.MAX_TOKEN - 1 then
		s = s .. "\""
	end
	token.string = s
	return 1
end

function B.PC_MergeTokens(t1, t2)
	-- merging of a name with a name or number
	if t1.type == BC.TT_NAME and (t2.type == BC.TT_NAME or t2.type == BC.TT_NUMBER) then
		t1.string = t1.string .. t2.string
		return 1
	end
	-- merging of two strings
	if t1.type == BC.TT_STRING and t2.type == BC.TT_STRING then
		-- remove trailing double quote
		-- concat without leading double quote
		t1.string = string.sub(t1.string, 1, #t1.string - 1) .. string.sub(t2.string, 2)
		return 1
	end
	-- FIXME: merging of two number of the same sub type
	return 0
end

function B.PC_PrintDefineHashTable(definehash)
	for i = 0, DEFINEHASHSIZE - 1 do
		B.Log_Write("%4d:", i)
		local d = definehash[i]
		while d ~= nil do
			B.Log_Write(" %s", d.name)
			d = d.hashnext
		end
		B.Log_Write("\n")
	end
end

function B.PC_NameHash(name)
	local hash = 0
	for i = 0, #name - 1 do
		local c = string.byte(name, i + 1)
		if c >= 128 then
			c = c - 256
		end
		hash = hash + c * (119 + i)
	end
	hash = bit32.band(bit32.bxor(hash, bit32.arshift(hash, 10), bit32.arshift(hash, 20)), DEFINEHASHSIZE - 1)
	return hash
end

function B.PC_AddDefineToHash(define, definehash)
	local hash = B.PC_NameHash(define.name)
	define.hashnext = definehash[hash]
	definehash[hash] = define
end

function B.PC_FindHashedDefine(definehash, name)
	local hash = B.PC_NameHash(name)
	local d = definehash[hash]
	while d ~= nil do
		if d.name == name then
			return d
		end
		d = d.hashnext
	end
	return nil
end

function B.PC_FindDefine(defines, name)
	local d = defines
	while d ~= nil do
		if d.name == name then
			return d
		end
		d = d.next
	end
	return nil
end

-- returns number of the parm, if no parm found with the given name -1 is returned
function B.PC_FindDefineParm(define, name)
	local i = 0
	local p = define.parms
	while p ~= nil do
		if p.string == name then
			return i
		end
		i = i + 1
		p = p.next
	end
	return -1
end

function B.PC_FreeDefine(define)
	-- free the define parameters
	local t = define.parms
	while t ~= nil do
		local next_ = t.next
		B.PC_FreeToken(t)
		t = next_
	end
	-- free the define tokens
	t = define.tokens
	while t ~= nil do
		local next_ = t.next
		B.PC_FreeToken(t)
		t = next_
	end
end

function B.PC_AddBuiltinDefines(source)
	local builtin = {
		{ "__LINE__", BC.BUILTIN_LINE },
		{ "__FILE__", BC.BUILTIN_FILE },
		{ "__DATE__", BC.BUILTIN_DATE },
		{ "__TIME__", BC.BUILTIN_TIME },
	}

	for i = 1, #builtin do
		local define = SB.define_t()
		define.name = builtin[i][1]
		define.flags = bit32.bor(define.flags, BC.DEFINE_FIXED)
		define.builtin = builtin[i][2]
		-- add the define to the source
		B.PC_AddDefineToHash(define, source.definehash)
	end
end

function B.PC_ExpandBuiltinDefine(source, deftoken, define)
	local token = B.PC_CopyToken(deftoken)
	local firsttoken = nil
	local lasttoken = nil
	if define.builtin == BC.BUILTIN_LINE then
		token.string = QS.va("%d", deftoken.line)
		token.intvalue = deftoken.line
		token.floatvalue = deftoken.line
		token.type = BC.TT_NUMBER
		token.subtype = bit32.bor(BC.TT_DECIMAL, BC.TT_INTEGER)
		firsttoken = token
		lasttoken = token
	elseif define.builtin == BC.BUILTIN_FILE then
		token.string = source.scriptstack.filename
		token.type = BC.TT_NAME
		token.subtype = #token.string
		firsttoken = token
		lasttoken = token
	elseif define.builtin == BC.BUILTIN_DATE then
		token.string = "\"Jan  1 1970\""
		token.type = BC.TT_NAME
		token.subtype = #token.string
		firsttoken = token
		lasttoken = token
	elseif define.builtin == BC.BUILTIN_TIME then
		token.string = "\"00:00:00\""
		token.type = BC.TT_NAME
		token.subtype = #token.string
		firsttoken = token
		lasttoken = token
	end
	return 1, firsttoken, lasttoken
end

function B.PC_ExpandDefine(source, deftoken, define)
	local parms = {}
	local token = SB.token_t()

	-- if it is a builtin define
	if define.builtin ~= 0 then
		return B.PC_ExpandBuiltinDefine(source, deftoken, define)
	end
	-- if the define has parameters
	if define.numparms ~= 0 then
		if B.PC_ReadDefineParms(source, define, parms, MAX_DEFINEPARMS) == 0 then
			return 0, nil, nil
		end
	end
	-- empty list at first
	local first = nil
	local last = nil
	-- create a list with tokens of the expanded define
	local dt = define.tokens
	while dt ~= nil do
		local parmnum = -1
		-- if the token is a name, it could be a define parameter
		if dt.type == BC.TT_NAME then
			parmnum = B.PC_FindDefineParm(define, dt.string)
		end
		-- if it is a define parameter
		if parmnum >= 0 then
			local pt = parms[parmnum]
			while pt ~= nil do
				local t = B.PC_CopyToken(pt)
				-- add the token to the list
				t.next = nil
				if last ~= nil then
					last.next = t
				else
					first = t
				end
				last = t
				pt = pt.next
			end
		else
			local t = nil
			local skipadd = false
			-- if stringizing operator
			if dt.string == "#" then
				-- the stringizing operator must be followed by a define parameter
				if dt.next ~= nil then
					parmnum = B.PC_FindDefineParm(define, dt.next.string)
				else
					parmnum = -1
				end
				--
				if parmnum >= 0 then
					-- step over the stringizing operator
					dt = dt.next
					-- stringize the define parameter tokens
					if B.PC_StringizeTokens(parms[parmnum], token) == 0 then
						B.SourceError(source, "can't stringize tokens")
						return 0, nil, nil
					end
					t = B.PC_CopyToken(token)
				else
					B.SourceWarning(source, "stringizing operator without define parameter")
					skipadd = true
				end
			else
				t = B.PC_CopyToken(dt)
			end
			if not skipadd then
				-- add the token to the list
				t.next = nil
				if last ~= nil then
					last.next = t
				else
					first = t
				end
				last = t
			end
		end
		dt = dt.next
	end
	-- check for the merging operator
	local t = first
	while t ~= nil do
		local merged = false
		if t.next ~= nil then
			-- if the merging operator
			if string.sub(t.next.string, 1, 2) == "##" then
				local t1 = t
				local t2 = t.next.next
				if t2 ~= nil then
					if B.PC_MergeTokens(t1, t2) == 0 then
						B.SourceError(source, "can't merge %s with %s", t1.string, t2.string)
						return 0, nil, nil
					end
					B.PC_FreeToken(t1.next)
					t1.next = t2.next
					if t2 == last then
						last = t1
					end
					B.PC_FreeToken(t2)
					merged = true
				end
			end
		end
		if not merged then
			t = t.next
		end
	end
	-- free all the parameter tokens
	for i = 0, define.numparms - 1 do
		local pt = parms[i]
		while pt ~= nil do
			local nextpt = pt.next
			B.PC_FreeToken(pt)
			pt = nextpt
		end
	end
	--
	return 1, first, last
end

return nil
