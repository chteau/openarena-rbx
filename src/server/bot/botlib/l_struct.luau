--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/l_struct.c).

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
-- Luau port of l_struct.c. Structure reading / writing.
-- A field's C byte offset is the field NAME here; arrays are 0-based tables.
-- There is no file system: the "FILE *fp" of the writers is a table to which
-- text chunks are appended (fp[#fp + 1]); the writers always succeed.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local function fprintf(fp, s)
	fp[#fp + 1] = s
end

function B.FindField(defs, name)
	local i = 0
	while defs[i] ~= nil and defs[i].name ~= nil do
		if defs[i].name == name then
			return defs[i]
		end
		i = i + 1
	end
	return nil
end

-- p is addressed as container[key]
function B.ReadNumber(source, fd, container, key)
	local token = SB.token_t()
	local negative = false
	local intval
	local intmin, intmax = 0, 0
	local floatval

	if B.PC_ExpectAnyToken(source, token) == 0 then
		return false
	end

	if token.type == BC.TT_PUNCTUATION then
		if bit32.band(fd.type, BC.FT_UNSIGNED) ~= 0 then
			B.SourceError(source, "expected unsigned value, found %s", token.string)
			return false
		end
		if token.string ~= "-" then
			B.SourceError(source, "unexpected punctuation %s", token.string)
			return false
		end
		negative = true
		if B.PC_ExpectAnyToken(source, token) == 0 then
			return false
		end
	end
	if token.type ~= BC.TT_NUMBER then
		B.SourceError(source, "expected number, found %s", token.string)
		return false
	end
	local ftype = bit32.band(fd.type, BC.FT_TYPE)
	if bit32.band(token.subtype, BC.TT_FLOAT) ~= 0 then
		if ftype ~= BC.FT_FLOAT then
			B.SourceError(source, "unexpected float")
			return false
		end
		floatval = token.floatvalue
		if negative then
			floatval = -floatval
		end
		if bit32.band(fd.type, BC.FT_BOUNDED) ~= 0 then
			if floatval < fd.floatmin or floatval > fd.floatmax then
				B.SourceError(source, "float out of range [%f, %f]", fd.floatmin, fd.floatmax)
				return false
			end
		end
		container[key] = Q.f(floatval)
		return true
	end
	intval = token.intvalue
	if negative then
		intval = -intval
	end
	if ftype == BC.FT_CHAR then
		if bit32.band(fd.type, BC.FT_UNSIGNED) ~= 0 then
			intmin = 0
			intmax = 255
		else
			intmin = -128
			intmax = 127
		end
	end
	if ftype == BC.FT_INT then
		if bit32.band(fd.type, BC.FT_UNSIGNED) ~= 0 then
			intmin = 0
			intmax = 65535
		else
			intmin = -32768
			intmax = 32767
		end
	end
	if ftype == BC.FT_CHAR or ftype == BC.FT_INT then
		if bit32.band(fd.type, BC.FT_BOUNDED) ~= 0 then
			intmin = Q.trunc(math.max(intmin, fd.floatmin))
			intmax = Q.trunc(math.min(intmax, fd.floatmax))
		end
		if intval < intmin or intval > intmax then
			B.SourceError(source, "value %d out of range [%d, %d]", intval, intmin, intmax)
			return false
		end
	elseif ftype == BC.FT_FLOAT then
		if bit32.band(fd.type, BC.FT_BOUNDED) ~= 0 then
			if intval < fd.floatmin or intval > fd.floatmax then
				B.SourceError(source, "value %d out of range [%f, %f]", intval, fd.floatmin, fd.floatmax)
				return false
			end
		end
	end
	if ftype == BC.FT_CHAR then
		container[key] = intval
	elseif ftype == BC.FT_INT then
		container[key] = intval
	elseif ftype == BC.FT_FLOAT then
		container[key] = Q.f(intval)
	end
	return true
end

function B.ReadChar(source, fd, container, key)
	local token = SB.token_t()

	if B.PC_ExpectAnyToken(source, token) == 0 then
		return false
	end

	if token.type == BC.TT_LITERAL then
		token.string = B.StripSingleQuotes(token.string)
		container[key] = string.byte(token.string, 1) or 0
	else
		B.PC_UnreadLastToken(source)
		if not B.ReadNumber(source, fd, container, key) then
			return false
		end
	end
	return true
end

function B.ReadString(source, fd, container, key)
	local token = SB.token_t()

	if B.PC_ExpectTokenType(source, BC.TT_STRING, 0, token) == 0 then
		return 0
	end
	token.string = B.StripDoubleQuotes(token.string)
	container[key] = QS.Q_strncpyz(token.string, BC.MAX_STRINGFIELD)
	return 1
end

function B.ReadStructure(source, def, structure)
	local token = SB.token_t()

	if B.PC_ExpectTokenString(source, "{") == 0 then
		return 0
	end
	while true do
		if B.PC_ExpectAnyToken(source, token) == 0 then
			return 0
		end
		if token.string == "}" then
			break
		end
		local fd = B.FindField(def.fields, token.string)
		if fd == nil then
			B.SourceError(source, "unknown structure field %s", token.string)
			return 0
		end
		local num
		local isarray = bit32.band(fd.type, BC.FT_ARRAY) ~= 0
		if isarray then
			num = fd.maxarray
			if B.PC_ExpectTokenString(source, "{") == 0 then
				return 0
			end
		else
			num = 1
		end
		local container, key
		if isarray then
			if structure[fd.name] == nil then
				structure[fd.name] = {}
			end
			container = structure[fd.name]
			key = 0
		else
			container = structure
			key = fd.name
		end
		while true do
			local cur = num
			num = num - 1
			if not (cur > 0) then
				break
			end
			if isarray then
				if B.PC_CheckTokenString(source, "}") ~= 0 then
					break
				end
			end
			local ftype = bit32.band(fd.type, BC.FT_TYPE)
			if ftype == BC.FT_CHAR then
				if not B.ReadChar(source, fd, container, key) then
					return 0
				end
			elseif ftype == BC.FT_INT then
				if not B.ReadNumber(source, fd, container, key) then
					return 0
				end
			elseif ftype == BC.FT_FLOAT then
				if not B.ReadNumber(source, fd, container, key) then
					return 0
				end
			elseif ftype == BC.FT_STRING then
				if B.ReadString(source, fd, container, key) == 0 then
					return 0
				end
			elseif ftype == BC.FT_STRUCT then
				if fd.substruct == nil then
					B.SourceError(source, "BUG: no sub structure defined")
					return 0
				end
				if container[key] == nil then
					container[key] = {}
				end
				B.ReadStructure(source, fd.substruct, container[key])
			end
			if isarray then
				key = key + 1
			end
			if isarray then
				if B.PC_ExpectAnyToken(source, token) == 0 then
					return 0
				end
				if token.string == "}" then
					break
				end
				if token.string ~= "," then
					B.SourceError(source, "expected a comma, found %s", token.string)
					return 0
				end
			end
		end
	end
	return 1
end

function B.WriteIndent(fp, indent)
	while true do
		local cur = indent
		indent = indent - 1
		if not (cur > 0) then
			break
		end
		fprintf(fp, "\t")
	end
	return 1
end

function B.WriteFloat(fp, value)
	local buf = QS.Com_sprintf(128, "%f", value)
	local l = #buf
	while true do
		local cur = l
		l = l - 1
		if not (cur > 1) then
			break
		end
		local c = string.sub(buf, l + 1, l + 1)
		if c ~= "0" and c ~= "." then
			break
		end
		if c == "." then
			buf = string.sub(buf, 1, l)
			break
		end
		buf = string.sub(buf, 1, l)
	end
	fprintf(fp, buf)
	return 1
end

function B.WriteStructWithIndent(fp, def, structure, indent)
	if B.WriteIndent(fp, indent) == 0 then
		return 0
	end
	fprintf(fp, "{\r\n")

	indent = indent + 1
	local i = 0
	while def.fields[i] ~= nil and def.fields[i].name ~= nil do
		local fd = def.fields[i]
		if B.WriteIndent(fp, indent) == 0 then
			return 0
		end
		fprintf(fp, fd.name .. "\t")
		local isarray = bit32.band(fd.type, BC.FT_ARRAY) ~= 0
		local num
		local container, key
		if isarray then
			num = fd.maxarray
			fprintf(fp, "{")
			container = structure[fd.name]
			key = 0
		else
			num = 1
			container = structure
			key = fd.name
		end
		while true do
			local cur = num
			num = num - 1
			if not (cur > 0) then
				break
			end
			local ftype = bit32.band(fd.type, BC.FT_TYPE)
			if ftype == BC.FT_CHAR then
				fprintf(fp, QS.va("%d", container[key]))
			elseif ftype == BC.FT_INT then
				fprintf(fp, QS.va("%d", container[key]))
			elseif ftype == BC.FT_FLOAT then
				if B.WriteFloat(fp, container[key]) == 0 then
					return 0
				end
			elseif ftype == BC.FT_STRING then
				fprintf(fp, "\"" .. container[key] .. "\"")
			elseif ftype == BC.FT_STRUCT then
				if B.WriteStructWithIndent(fp, fd.substruct, structure, indent) == 0 then
					return 0
				end
			end
			if isarray then
				key = key + 1
			end
			if isarray then
				if num > 0 then
					fprintf(fp, ",")
				else
					fprintf(fp, "}")
				end
			end
		end
		fprintf(fp, "\r\n")
		i = i + 1
	end
	indent = indent - 1

	if B.WriteIndent(fp, indent) == 0 then
		return 0
	end
	fprintf(fp, "}\r\n")
	return 1
end

function B.WriteStructure(fp, def, structure)
	return B.WriteStructWithIndent(fp, def, structure, 0)
end

return nil
