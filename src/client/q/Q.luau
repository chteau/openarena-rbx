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
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/qcommon/q_shared.c and q_math.c (OpenArena gamecode).

local Q = {}

local PITCH, YAW, ROLL = 0, 1, 2
local NUMVERTEXNORMALS = 162
local MAX_TOKEN_CHARS = 1024
local TRUNCATE_LENGTH = 64
local BIG_INFO_STRING = 8192
local MAX_INFO_STRING = 1024

local sin, cos, sqrt, abs, floor, ceil = math.sin, math.cos, math.sqrt, math.abs, math.floor, math.ceil
local byte, sub, upper, lower = string.byte, string.sub, string.upper, string.lower

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

function Q.vec3(x, y, z)
	return { [0] = x or 0, [1] = y or 0, [2] = z or 0 }
end

function Q.vec4(x, y, z, w)
	return { [0] = x or 0, [1] = y or 0, [2] = z or 0, [3] = w or 0 }
end

function Q.int(x)
	if x >= 0 then
		return floor(x)
	end
	return ceil(x)
end

function Q.idiv(a, b)
	return Q.int(a / b)
end

function Q.b2i(b)
	return b and 1 or 0
end

function Q.i2b(i)
	return i ~= 0
end

local seed = 1
function Q.rand()
	seed = (69069 * seed + 1) % 4294967296
	return bit32.band(bit32.rshift(seed, 16), 0x7fff)
end

function Q.random()
	return Q.rand() / 32768
end

function Q.crandom()
	return 2.0 * (Q.random() - 0.5)
end

function Q.Q_rand(s)
	s = (69069 * s + 1) % 4294967296
	return s
end

function Q.Q_random(s)
	return bit32.band(s, 0xffff) / 0x10000
end

function Q.Q_crandom(s)
	return 2.0 * (Q.Q_random(s) - 0.5)
end

function Q.va(format, ...)
	local args = { ... }
	local n = 0
	local out = string.gsub(format, "%%([%-%+ #0]*%*?%d*%.?%d*)l?l?([%a%%])", function(flags, conv)
		if conv == "%" then
			return "%"
		end
		n += 1
		local arg = args[n]
		if conv == "d" or conv == "i" or conv == "u" then
			return string.format("%" .. flags .. "d", Q.int(tonumber(arg) or 0))
		elseif conv == "x" or conv == "X" or conv == "o" or conv == "c" then
			local v = Q.int(tonumber(arg) or 0)
			if conv ~= "c" and v < 0 then
				v += 4294967296
			end
			return string.format("%" .. flags .. conv, v)
		elseif conv == "s" then
			return string.format("%" .. flags .. "s", tostring(arg))
		else
			return string.format("%" .. flags .. conv, tonumber(arg) or 0)
		end
	end)
	return out
end

----------------------------------------------------------------------
-- string functions
----------------------------------------------------------------------

function Q.Q_isprint(c)
	return (c >= 0x20 and c <= 0x7E) and 1 or 0
end

function Q.Q_islower(c)
	return (c >= 97 and c <= 122) and 1 or 0
end

function Q.Q_isupper(c)
	return (c >= 65 and c <= 90) and 1 or 0
end

function Q.Q_isalpha(c)
	return ((c >= 97 and c <= 122) or (c >= 65 and c <= 90)) and 1 or 0
end

local function cmp(a, b)
	if a == b then
		return 0
	end
	return a < b and -1 or 1
end

function Q.stricmpn(s1, s2, n)
	if s1 == nil then
		return s2 == nil and 0 or -1
	elseif s2 == nil then
		return 1
	end
	return cmp(upper(sub(s1, 1, n)), upper(sub(s2, 1, n)))
end

function Q.strncmp(s1, s2, n)
	return cmp(sub(s1, 1, n), sub(s2, 1, n))
end

function Q.stricmp(s1, s2)
	if s1 ~= nil and s2 ~= nil then
		return Q.stricmpn(s1, s2, 99999)
	end
	return -1
end

function Q.strlwr(s)
	return lower(s)
end

function Q.strupr(s)
	return upper(s)
end

function Q.strncpyz(src, destsize)
	return sub(src, 1, destsize - 1)
end

function Q.stristr(s, find)
	local i = string.find(lower(s), lower(find), 1, true)
	if i == nil then
		return nil
	end
	return sub(s, i)
end

function Q.IsColorString(s, i)
	return byte(s, i) == 94 and byte(s, i + 1) ~= nil and byte(s, i + 1) ~= 94
end

function Q.ColorIndex(c)
	return bit32.band(c - 48, 7)
end

function Q.PrintStrlen(s)
	if s == nil then
		return 0
	end
	local len = 0
	local i = 1
	local n = #s
	while i <= n do
		if Q.IsColorString(s, i) then
			i += 2
		else
			i += 1
			len += 1
		end
	end
	return len
end

function Q.CleanStr(s)
	while true do
		local out = {}
		local hadColor = false
		local i = 1
		local n = #s
		while i <= n do
			local c = byte(s, i)
			if Q.IsColorString(s, i) then
				i += 1
				hadColor = true
			elseif c >= 0x20 and c <= 0x7E then
				table.insert(out, string.char(c))
			end
			i += 1
		end
		s = table.concat(out)
		if not hadColor then
			return s
		end
	end
end

function Q.CountChar(s, tocount)
	local count = 0
	for i = 1, #s do
		if sub(s, i, i) == tocount then
			count += 1
		end
	end
	return count
end

function Q.Q_StrToLower(s)
	return lower(s)
end

function Q.Q_strrchr(s, c)
	for i = #s, 1, -1 do
		if sub(s, i, i) == c then
			return sub(s, i)
		end
	end
	return nil
end

function Q.Com_Clamp(min, max, value)
	if value < min then
		return min
	end
	if value > max then
		return max
	end
	return value
end

function Q.COM_SkipPath(pathname)
	local last = 1
	for i = 1, #pathname do
		if byte(pathname, i) == 47 then
			last = i + 1
		end
	end
	return sub(pathname, last)
end

function Q.COM_GetExtension(name)
	local i = #name
	while i >= 1 do
		local c = byte(name, i)
		if c == 46 then
			return sub(name, i + 1)
		end
		if c == 47 or i == 1 then
			return ""
		end
		i -= 1
	end
	return ""
end

function Q.COM_StripExtension(inp, destsize)
	local out = destsize and sub(inp, 1, destsize - 1) or inp
	local length = #out - 1
	while length > 0 and byte(out, length + 1) ~= 46 do
		length -= 1
		if byte(out, length + 1) == 47 then
			return out
		end
	end
	if length ~= 0 then
		return sub(out, 1, length)
	end
	return out
end

function Q.COM_DefaultExtension(path, extension)
	local i = #path
	while i >= 1 and byte(path, i) ~= 47 do
		if byte(path, i) == 46 then
			return path
		end
		i -= 1
	end
	return path .. extension
end

function Q.Com_TruncateLongString(s)
	local length = #s
	if length <= TRUNCATE_LENGTH then
		return sub(s, 1, TRUNCATE_LENGTH - 1)
	end
	return sub(s, 1, TRUNCATE_LENGTH // 2 - 4) .. " ... " .. sub(s, length - TRUNCATE_LENGTH // 2 + 4)
end

local function charIsOneOf(c, set)
	return c ~= nil and string.find(set, c, 1, true) ~= nil
end

function Q.Com_SkipCharset(s, sep)
	local i = 1
	while i <= #s and charIsOneOf(sub(s, i, i), sep) do
		i += 1
	end
	return sub(s, i)
end

function Q.Com_SkipTokens(s, numTokens, sep)
	local sepCount = 0
	local p = 1
	while sepCount < numTokens do
		local c = sub(s, p, p)
		p += 1
		if c ~= "" and charIsOneOf(c, sep) then
			sepCount += 1
			while charIsOneOf(sub(s, p, p), sep) do
				p += 1
			end
		elseif sub(s, p, p) == "" then
			break
		end
	end
	if sepCount == numTokens then
		return sub(s, p)
	end
	return s
end

----------------------------------------------------------------------
-- parsing
----------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

function Q.COM_Parser(text, name)
	return setmetatable({ text = text, pos = 1, lines = 0, name = name or "", done = text == nil }, Parser)
end

function Parser:AtEnd()
	return self.done
end

function Parser:Parse()
	return self:ParseExt(true)
end

function Parser:ParseExt(allowLineBreaks)
	local text = self.text
	if self.done then
		return ""
	end
	local pos = self.pos
	local n = #text
	local hasNewLines = false
	local c
	while true do
		while true do
			c = byte(text, pos)
			if c == nil then
				self.done = true
				self.pos = pos
				return ""
			end
			if c > 32 then
				break
			end
			if c == 10 then
				self.lines += 1
				hasNewLines = true
			end
			pos += 1
		end
		if hasNewLines and not allowLineBreaks then
			self.pos = pos
			return ""
		end
		local c2 = byte(text, pos + 1)
		if c == 47 and c2 == 47 then
			pos += 2
			while pos <= n and byte(text, pos) ~= 10 do
				pos += 1
			end
		elseif c == 47 and c2 == 42 then
			pos += 2
			while pos <= n and not (byte(text, pos) == 42 and byte(text, pos + 1) == 47) do
				pos += 1
			end
			if pos <= n then
				pos += 2
			end
		else
			break
		end
	end

	local token = {}
	local len = 0
	if c == 34 then
		pos += 1
		while true do
			c = byte(text, pos)
			pos += 1
			if c == 34 or c == nil then
				self.pos = pos
				return table.concat(token)
			end
			if len < MAX_TOKEN_CHARS - 1 then
				len += 1
				token[len] = string.char(c)
			end
		end
	end

	repeat
		if len < MAX_TOKEN_CHARS - 1 then
			len += 1
			token[len] = string.char(c)
		end
		pos += 1
		c = byte(text, pos)
		if c == 10 then
			self.lines += 1
		end
	until c == nil or c <= 32

	self.pos = pos
	return table.concat(token)
end

function Parser:MatchToken(match)
	local token = self:Parse()
	if token ~= match then
		error(Q.va("MatchToken: %s != %s", token, match))
	end
end

function Parser:SkipBracedSection()
	local depth = 0
	repeat
		local token = self:ParseExt(true)
		if #token == 1 then
			if token == "{" then
				depth += 1
			elseif token == "}" then
				depth -= 1
			end
		end
	until depth == 0 or self.done
end

function Parser:SkipRestOfLine()
	local text = self.text
	local p = self.pos
	while true do
		local c = byte(text, p)
		p += 1
		if c == nil then
			break
		end
		if c == 10 then
			self.lines += 1
			break
		end
	end
	self.pos = p
end

function Parser:Parse1DMatrix(x, m)
	self:MatchToken("(")
	for i = 0, x - 1 do
		m[i] = tonumber(self:Parse()) or 0
	end
	self:MatchToken(")")
end

function Parser:Parse2DMatrix(y, x, m)
	self:MatchToken("(")
	for i = 0, y - 1 do
		m[i] = m[i] or {}
		self:Parse1DMatrix(x, m[i])
	end
	self:MatchToken(")")
end

function Parser:Parse3DMatrix(z, y, x, m)
	self:MatchToken("(")
	for i = 0, z - 1 do
		m[i] = m[i] or {}
		self:Parse2DMatrix(y, x, m[i])
	end
	self:MatchToken(")")
end

function Q.COM_Compress(data)
	local out = {}
	local newline, whitespace = false, false
	local i = 1
	local n = #data
	while i <= n do
		local c = byte(data, i)
		local c2 = byte(data, i + 1)
		if c == 47 and c2 == 47 then
			while i <= n and byte(data, i) ~= 10 do
				i += 1
			end
		elseif c == 47 and c2 == 42 then
			while i <= n and not (byte(data, i) == 42 and byte(data, i + 1) == 47) do
				i += 1
			end
			if i <= n then
				i += 2
			end
		elseif c == 10 or c == 13 then
			newline = true
			i += 1
		elseif c == 32 or c == 9 then
			whitespace = true
			i += 1
		else
			if newline then
				table.insert(out, "\n")
				newline = false
				whitespace = false
			end
			if whitespace then
				table.insert(out, " ")
				whitespace = false
			end
			if c == 34 then
				local j = i + 1
				while j <= n and byte(data, j) ~= 34 do
					j += 1
				end
				if j <= n then
					j += 1
				end
				table.insert(out, sub(data, i, j - 1))
				i = j
			else
				table.insert(out, string.char(c))
				i += 1
			end
		end
	end
	return table.concat(out)
end

----------------------------------------------------------------------
-- info strings (immutable: mutators return the new string)
----------------------------------------------------------------------

function Q.Info_ValueForKey(s, key)
	if s == nil or key == nil then
		return ""
	end
	if #s >= BIG_INFO_STRING then
		error("Info_ValueForKey: oversize infostring")
	end
	local pos = 1
	if byte(s, 1) == 92 then
		pos = 2
	end
	local n = #s
	while true do
		local e = string.find(s, "\\", pos, true)
		if e == nil then
			return ""
		end
		local pkey = sub(s, pos, e - 1)
		pos = e + 1
		local ve = string.find(s, "\\", pos, true) or (n + 1)
		local value = sub(s, pos, ve - 1)
		pos = ve
		if key == pkey then
			return value
		end
		if pos > n then
			break
		end
		pos += 1
	end
	return ""
end

-- Returns key, value, rest. rest is "" once all pairs are consumed.
function Q.Info_NextPair(head)
	local pos = 1
	if byte(head, 1) == 92 then
		pos = 2
	end
	local e = string.find(head, "\\", pos, true)
	if e == nil then
		return "", "", ""
	end
	local key = sub(head, pos, e - 1)
	pos = e + 1
	local ve = string.find(head, "\\", pos, true) or (#head + 1)
	return key, sub(head, pos, ve - 1), sub(head, ve)
end

function Q.Info_RemoveKey(s, key)
	if #s >= MAX_INFO_STRING then
		error("Info_RemoveKey: oversize infostring")
	end
	if string.find(key, "\\", 1, true) then
		return s
	end
	local n = #s
	local pos = 1
	while true do
		local start = pos
		if byte(s, pos) == 92 then
			pos += 1
		end
		local e = string.find(s, "\\", pos, true)
		if e == nil then
			return s
		end
		local pkey = sub(s, pos, e - 1)
		pos = e + 1
		local ve = string.find(s, "\\", pos, true) or (n + 1)
		pos = ve
		if key == pkey then
			return sub(s, 1, start - 1) .. sub(s, pos)
		end
		if pos > n then
			return s
		end
	end
end

function Q.Info_Validate(s)
	return string.find(s, '"', 1, true) == nil and string.find(s, ";", 1, true) == nil
end

function Q.Info_SetValueForKey(s, key, value)
	if #s >= MAX_INFO_STRING then
		error("Info_SetValueForKey: oversize infostring")
	end
	for _, ch in ipairs({ "\\", ";", '"' }) do
		if string.find(key, ch, 1, true) or (value and string.find(value, ch, 1, true)) then
			return s
		end
	end
	s = Q.Info_RemoveKey(s, key)
	if value == nil or #value == 0 then
		return s
	end
	local newi = "\\" .. key .. "\\" .. value
	if #newi + #s >= MAX_INFO_STRING then
		return s
	end
	return newi .. s
end

----------------------------------------------------------------------
-- vector macros
----------------------------------------------------------------------

function Q.DotProduct(a, b)
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
end

function Q.VectorSubtract(a, b, c)
	c[0] = a[0] - b[0]
	c[1] = a[1] - b[1]
	c[2] = a[2] - b[2]
end

function Q.VectorAdd(a, b, c)
	c[0] = a[0] + b[0]
	c[1] = a[1] + b[1]
	c[2] = a[2] + b[2]
end

function Q.VectorCopy(a, b)
	b[0] = a[0]
	b[1] = a[1]
	b[2] = a[2]
end

function Q.VectorScale(v, s, o)
	o[0] = v[0] * s
	o[1] = v[1] * s
	o[2] = v[2] * s
end

function Q.VectorMA(v, s, b, o)
	o[0] = v[0] + b[0] * s
	o[1] = v[1] + b[1] * s
	o[2] = v[2] + b[2] * s
end

function Q.VectorClear(a)
	a[0] = 0
	a[1] = 0
	a[2] = 0
end

function Q.VectorNegate(a, b)
	b[0] = -a[0]
	b[1] = -a[1]
	b[2] = -a[2]
end

function Q.VectorSet(v, x, y, z)
	v[0] = x
	v[1] = y
	v[2] = z
end

function Q.Vector4Copy(a, b)
	b[0] = a[0]
	b[1] = a[1]
	b[2] = a[2]
	b[3] = a[3]
end

function Q.Vector4Set(v, x, y, z, w)
	v[0] = x
	v[1] = y
	v[2] = z
	v[3] = w
end

function Q.Vector4Scale(v, s, o)
	o[0] = v[0] * s
	o[1] = v[1] * s
	o[2] = v[2] * s
	o[3] = v[3] * s
end

function Q.SnapVector(v)
	v[0] = Q.int(v[0] + (v[0] >= 0 and 0.5 or -0.5))
	v[1] = Q.int(v[1] + (v[1] >= 0 and 0.5 or -0.5))
	v[2] = Q.int(v[2] + (v[2] >= 0 and 0.5 or -0.5))
end

function Q.VectorCompare(v1, v2)
	return v1[0] == v2[0] and v1[1] == v2[1] and v1[2] == v2[2]
end

function Q.VectorLength(v)
	return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
end

function Q.VectorLengthSquared(v)
	return v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
end

function Q.Distance(p1, p2)
	local x, y, z = p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2]
	return sqrt(x * x + y * y + z * z)
end

function Q.DistanceSquared(p1, p2)
	local x, y, z = p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2]
	return x * x + y * y + z * z
end

function Q.VectorInverse(v)
	v[0] = -v[0]
	v[1] = -v[1]
	v[2] = -v[2]
end

function Q.CrossProduct(v1, v2, cross)
	cross[0] = v1[1] * v2[2] - v1[2] * v2[1]
	cross[1] = v1[2] * v2[0] - v1[0] * v2[2]
	cross[2] = v1[0] * v2[1] - v1[1] * v2[0]
end

function Q.DEG2RAD(a)
	return (a * math.pi) / 180.0
end

function Q.RAD2DEG(a)
	return (a * 180.0) / math.pi
end

function Q.ANGLE2SHORT(x)
	return bit32.band(Q.int(x * 65536 / 360), 65535)
end

function Q.SHORT2ANGLE(x)
	return x * (360.0 / 65536)
end

----------------------------------------------------------------------
-- q_math globals
----------------------------------------------------------------------

Q.vec3_origin = Q.vec3(0, 0, 0)
Q.axisDefault = { [0] = Q.vec3(1, 0, 0), [1] = Q.vec3(0, 1, 0), [2] = Q.vec3(0, 0, 1) }

Q.colorBlack = Q.vec4(0, 0, 0, 1)
Q.colorRed = Q.vec4(1, 0, 0, 1)
Q.colorGreen = Q.vec4(0, 1, 0, 1)
Q.colorBlue = Q.vec4(0, 0, 1, 1)
Q.colorYellow = Q.vec4(1, 1, 0, 1)
Q.colorMagenta = Q.vec4(1, 0, 1, 1)
Q.colorCyan = Q.vec4(0, 1, 1, 1)
Q.colorWhite = Q.vec4(1, 1, 1, 1)
Q.colorLtGrey = Q.vec4(0.75, 0.75, 0.75, 1)
Q.colorMdGrey = Q.vec4(0.5, 0.5, 0.5, 1)
Q.colorDkGrey = Q.vec4(0.25, 0.25, 0.25, 1)

Q.g_color_table = {
	[0] = Q.vec4(0.0, 0.0, 0.0, 1.0),
	Q.vec4(1.0, 0.0, 0.0, 1.0),
	Q.vec4(0.0, 1.0, 0.0, 1.0),
	Q.vec4(1.0, 1.0, 0.0, 1.0),
	Q.vec4(0.0, 0.0, 1.0, 1.0),
	Q.vec4(0.0, 1.0, 1.0, 1.0),
	Q.vec4(1.0, 0.0, 1.0, 1.0),
	Q.vec4(1.0, 1.0, 1.0, 1.0),
	Q.vec4(1.00, 0.43, 0.00, 1.00),
}

local bytedirData = {
	-0.525731, 0.000000, 0.850651, -0.442863, 0.238856, 0.864188,
	-0.295242, 0.000000, 0.955423, -0.309017, 0.500000, 0.809017,
	-0.162460, 0.262866, 0.951056, 0.000000, 0.000000, 1.000000,
	0.000000, 0.850651, 0.525731, -0.147621, 0.716567, 0.681718,
	0.147621, 0.716567, 0.681718, 0.000000, 0.525731, 0.850651,
	0.309017, 0.500000, 0.809017, 0.525731, 0.000000, 0.850651,
	0.295242, 0.000000, 0.955423, 0.442863, 0.238856, 0.864188,
	0.162460, 0.262866, 0.951056, -0.681718, 0.147621, 0.716567,
	-0.809017, 0.309017, 0.500000, -0.587785, 0.425325, 0.688191,
	-0.850651, 0.525731, 0.000000, -0.864188, 0.442863, 0.238856,
	-0.716567, 0.681718, 0.147621, -0.688191, 0.587785, 0.425325,
	-0.500000, 0.809017, 0.309017, -0.238856, 0.864188, 0.442863,
	-0.425325, 0.688191, 0.587785, -0.716567, 0.681718, -0.147621,
	-0.500000, 0.809017, -0.309017, -0.525731, 0.850651, 0.000000,
	0.000000, 0.850651, -0.525731, -0.238856, 0.864188, -0.442863,
	0.000000, 0.955423, -0.295242, -0.262866, 0.951056, -0.162460,
	0.000000, 1.000000, 0.000000, 0.000000, 0.955423, 0.295242,
	-0.262866, 0.951056, 0.162460, 0.238856, 0.864188, 0.442863,
	0.262866, 0.951056, 0.162460, 0.500000, 0.809017, 0.309017,
	0.238856, 0.864188, -0.442863, 0.262866, 0.951056, -0.162460,
	0.500000, 0.809017, -0.309017, 0.850651, 0.525731, 0.000000,
	0.716567, 0.681718, 0.147621, 0.716567, 0.681718, -0.147621,
	0.525731, 0.850651, 0.000000, 0.425325, 0.688191, 0.587785,
	0.864188, 0.442863, 0.238856, 0.688191, 0.587785, 0.425325,
	0.809017, 0.309017, 0.500000, 0.681718, 0.147621, 0.716567,
	0.587785, 0.425325, 0.688191, 0.955423, 0.295242, 0.000000,
	1.000000, 0.000000, 0.000000, 0.951056, 0.162460, 0.262866,
	0.850651, -0.525731, 0.000000, 0.955423, -0.295242, 0.000000,
	0.864188, -0.442863, 0.238856, 0.951056, -0.162460, 0.262866,
	0.809017, -0.309017, 0.500000, 0.681718, -0.147621, 0.716567,
	0.850651, 0.000000, 0.525731, 0.864188, 0.442863, -0.238856,
	0.809017, 0.309017, -0.500000, 0.951056, 0.162460, -0.262866,
	0.525731, 0.000000, -0.850651, 0.681718, 0.147621, -0.716567,
	0.681718, -0.147621, -0.716567, 0.850651, 0.000000, -0.525731,
	0.809017, -0.309017, -0.500000, 0.864188, -0.442863, -0.238856,
	0.951056, -0.162460, -0.262866, 0.147621, 0.716567, -0.681718,
	0.309017, 0.500000, -0.809017, 0.425325, 0.688191, -0.587785,
	0.442863, 0.238856, -0.864188, 0.587785, 0.425325, -0.688191,
	0.688191, 0.587785, -0.425325, -0.147621, 0.716567, -0.681718,
	-0.309017, 0.500000, -0.809017, 0.000000, 0.525731, -0.850651,
	-0.525731, 0.000000, -0.850651, -0.442863, 0.238856, -0.864188,
	-0.295242, 0.000000, -0.955423, -0.162460, 0.262866, -0.951056,
	0.000000, 0.000000, -1.000000, 0.295242, 0.000000, -0.955423,
	0.162460, 0.262866, -0.951056, -0.442863, -0.238856, -0.864188,
	-0.309017, -0.500000, -0.809017, -0.162460, -0.262866, -0.951056,
	0.000000, -0.850651, -0.525731, -0.147621, -0.716567, -0.681718,
	0.147621, -0.716567, -0.681718, 0.000000, -0.525731, -0.850651,
	0.309017, -0.500000, -0.809017, 0.442863, -0.238856, -0.864188,
	0.162460, -0.262866, -0.951056, 0.238856, -0.864188, -0.442863,
	0.500000, -0.809017, -0.309017, 0.425325, -0.688191, -0.587785,
	0.716567, -0.681718, -0.147621, 0.688191, -0.587785, -0.425325,
	0.587785, -0.425325, -0.688191, 0.000000, -0.955423, -0.295242,
	0.000000, -1.000000, 0.000000, 0.262866, -0.951056, -0.162460,
	0.000000, -0.850651, 0.525731, 0.000000, -0.955423, 0.295242,
	0.238856, -0.864188, 0.442863, 0.262866, -0.951056, 0.162460,
	0.500000, -0.809017, 0.309017, 0.716567, -0.681718, 0.147621,
	0.525731, -0.850651, 0.000000, -0.238856, -0.864188, -0.442863,
	-0.500000, -0.809017, -0.309017, -0.262866, -0.951056, -0.162460,
	-0.850651, -0.525731, 0.000000, -0.716567, -0.681718, -0.147621,
	-0.716567, -0.681718, 0.147621, -0.525731, -0.850651, 0.000000,
	-0.500000, -0.809017, 0.309017, -0.238856, -0.864188, 0.442863,
	-0.262866, -0.951056, 0.162460, -0.864188, -0.442863, 0.238856,
	-0.809017, -0.309017, 0.500000, -0.688191, -0.587785, 0.425325,
	-0.681718, -0.147621, 0.716567, -0.442863, -0.238856, 0.864188,
	-0.587785, -0.425325, 0.688191, -0.309017, -0.500000, 0.809017,
	-0.147621, -0.716567, 0.681718, -0.425325, -0.688191, 0.587785,
	-0.162460, -0.262866, 0.951056, 0.442863, -0.238856, 0.864188,
	0.162460, -0.262866, 0.951056, 0.309017, -0.500000, 0.809017,
	0.147621, -0.716567, 0.681718, 0.000000, -0.525731, 0.850651,
	0.425325, -0.688191, 0.587785, 0.587785, -0.425325, 0.688191,
	0.688191, -0.587785, 0.425325, -0.955423, 0.295242, 0.000000,
	-0.951056, 0.162460, 0.262866, -1.000000, 0.000000, 0.000000,
	-0.850651, 0.000000, 0.525731, -0.955423, -0.295242, 0.000000,
	-0.951056, -0.162460, 0.262866, -0.864188, 0.442863, -0.238856,
	-0.951056, 0.162460, -0.262866, -0.809017, 0.309017, -0.500000,
	-0.864188, -0.442863, -0.238856, -0.951056, -0.162460, -0.262866,
	-0.809017, -0.309017, -0.500000, -0.681718, 0.147621, -0.716567,
	-0.681718, -0.147621, -0.716567, -0.850651, 0.000000, -0.525731,
	-0.688191, 0.587785, -0.425325, -0.587785, 0.425325, -0.688191,
	-0.425325, 0.688191, -0.587785, -0.425325, -0.688191, -0.587785,
	-0.587785, -0.425325, -0.688191, -0.688191, -0.587785, -0.425325,
}

Q.bytedirs = {}
for i = 0, NUMVERTEXNORMALS - 1 do
	Q.bytedirs[i] = Q.vec3(bytedirData[i * 3 + 1], bytedirData[i * 3 + 2], bytedirData[i * 3 + 3])
end

----------------------------------------------------------------------
-- q_math functions
----------------------------------------------------------------------

function Q.ClampChar(i)
	if i < -128 then
		return -128
	end
	if i > 127 then
		return 127
	end
	return i
end

function Q.ClampShort(i)
	if i < -32768 then
		return -32768
	end
	if i > 0x7fff then
		return 0x7fff
	end
	return i
end

function Q.DirToByte(dir)
	if dir == nil then
		return 0
	end
	local bestd = 0
	local best = 0
	for i = 0, NUMVERTEXNORMALS - 1 do
		local d = Q.DotProduct(dir, Q.bytedirs[i])
		if d > bestd then
			bestd = d
			best = i
		end
	end
	return best
end

function Q.ByteToDir(b, dir)
	if b < 0 or b >= NUMVERTEXNORMALS then
		Q.VectorCopy(Q.vec3_origin, dir)
		return
	end
	Q.VectorCopy(Q.bytedirs[b], dir)
end

function Q.ColorBytes3(r, g, b)
	return Q.int(r * 255) + Q.int(g * 255) * 256 + Q.int(b * 255) * 65536
end

function Q.ColorBytes4(r, g, b, a)
	return Q.ColorBytes3(r, g, b) + Q.int(a * 255) * 16777216
end

function Q.NormalizeColor(inp, out)
	local max = inp[0]
	if inp[1] > max then
		max = inp[1]
	end
	if inp[2] > max then
		max = inp[2]
	end
	if max == 0 then
		Q.VectorClear(out)
	else
		out[0] = inp[0] / max
		out[1] = inp[1] / max
		out[2] = inp[2] / max
	end
	return max
end

function Q.VectorNormalize(v)
	local length = v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
	length = sqrt(length)
	if length ~= 0 then
		local ilength = 1 / length
		v[0] *= ilength
		v[1] *= ilength
		v[2] *= ilength
	end
	return length
end

function Q.VectorNormalize2(v, out)
	local length = v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
	length = sqrt(length)
	if length ~= 0 then
		local ilength = 1 / length
		out[0] = v[0] * ilength
		out[1] = v[1] * ilength
		out[2] = v[2] * ilength
	else
		Q.VectorClear(out)
	end
	return length
end

function Q.PlaneFromPoints(plane, a, b, c)
	local d1, d2 = Q.vec3(), Q.vec3()
	Q.VectorSubtract(b, a, d1)
	Q.VectorSubtract(c, a, d2)
	Q.CrossProduct(d2, d1, plane)
	if Q.VectorNormalize(plane) == 0 then
		return false
	end
	plane[3] = Q.DotProduct(a, plane)
	return true
end

local function mat3()
	return { [0] = { [0] = 0, 0, 0 }, [1] = { [0] = 0, 0, 0 }, [2] = { [0] = 0, 0, 0 } }
end

function Q.MatrixMultiply(in1, in2, out)
	for i = 0, 2 do
		for j = 0, 2 do
			out[i][j] = in1[i][0] * in2[0][j] + in1[i][1] * in2[1][j] + in1[i][2] * in2[2][j]
		end
	end
end

function Q.ProjectPointOnPlane(dst, p, normal)
	local inv_denom = Q.DotProduct(normal, normal)
	inv_denom = 1.0 / inv_denom
	local d = Q.DotProduct(normal, p) * inv_denom
	local n0 = normal[0] * inv_denom
	local n1 = normal[1] * inv_denom
	local n2 = normal[2] * inv_denom
	dst[0] = p[0] - d * n0
	dst[1] = p[1] - d * n1
	dst[2] = p[2] - d * n2
end

-- assumes "src" is normalized
function Q.PerpendicularVector(dst, src)
	local pos = 0
	local minelem = 1.0
	for i = 0, 2 do
		if abs(src[i]) < minelem then
			pos = i
			minelem = abs(src[i])
		end
	end
	local tempvec = Q.vec3(0, 0, 0)
	tempvec[pos] = 1.0
	Q.ProjectPointOnPlane(dst, tempvec, src)
	Q.VectorNormalize(dst)
end

function Q.RotatePointAroundVector(dst, dir, point, degrees)
	local m, im, zrot, tmpmat, rot = mat3(), mat3(), mat3(), mat3(), mat3()
	local vr, vup, vf = Q.vec3(), Q.vec3(), Q.vec3()

	vf[0] = dir[0]
	vf[1] = dir[1]
	vf[2] = dir[2]

	Q.PerpendicularVector(vr, dir)
	Q.CrossProduct(vr, vf, vup)

	m[0][0] = vr[0]
	m[1][0] = vr[1]
	m[2][0] = vr[2]
	m[0][1] = vup[0]
	m[1][1] = vup[1]
	m[2][1] = vup[2]
	m[0][2] = vf[0]
	m[1][2] = vf[1]
	m[2][2] = vf[2]

	for i = 0, 2 do
		for j = 0, 2 do
			im[i][j] = m[i][j]
		end
	end
	im[0][1] = m[1][0]
	im[0][2] = m[2][0]
	im[1][0] = m[0][1]
	im[1][2] = m[2][1]
	im[2][0] = m[0][2]
	im[2][1] = m[1][2]

	zrot[0][0] = 1.0
	zrot[1][1] = 1.0
	zrot[2][2] = 1.0

	local rad = Q.DEG2RAD(degrees)
	zrot[0][0] = cos(rad)
	zrot[0][1] = sin(rad)
	zrot[1][0] = -sin(rad)
	zrot[1][1] = cos(rad)

	Q.MatrixMultiply(m, zrot, tmpmat)
	Q.MatrixMultiply(tmpmat, im, rot)

	for i = 0, 2 do
		dst[i] = rot[i][0] * point[0] + rot[i][1] * point[1] + rot[i][2] * point[2]
	end
end

function Q.RotateAroundDirection(axis, yaw)
	Q.PerpendicularVector(axis[1], axis[0])
	if yaw ~= 0 then
		local temp = Q.vec3()
		Q.VectorCopy(axis[1], temp)
		Q.RotatePointAroundVector(axis[1], axis[0], temp, yaw)
	end
	Q.CrossProduct(axis[0], axis[1], axis[2])
end

function Q.vectoangles(value1, angles)
	local yaw, pitch
	if value1[1] == 0 and value1[0] == 0 then
		yaw = 0
		if value1[2] > 0 then
			pitch = 90
		else
			pitch = 270
		end
	else
		if value1[0] ~= 0 then
			yaw = (math.atan2(value1[1], value1[0]) * 180 / math.pi)
		elseif value1[1] > 0 then
			yaw = 90
		else
			yaw = 270
		end
		if yaw < 0 then
			yaw += 360
		end
		local forward = sqrt(value1[0] * value1[0] + value1[1] * value1[1])
		pitch = (math.atan2(value1[2], forward) * 180 / math.pi)
		if pitch < 0 then
			pitch += 360
		end
	end
	angles[PITCH] = -pitch
	angles[YAW] = yaw
	angles[ROLL] = 0
end

function Q.AngleVectors(angles, forward, right, up)
	local angle = angles[YAW] * (math.pi * 2 / 360)
	local sy = sin(angle)
	local cy = cos(angle)
	angle = angles[PITCH] * (math.pi * 2 / 360)
	local sp = sin(angle)
	local cp = cos(angle)
	angle = angles[ROLL] * (math.pi * 2 / 360)
	local sr = sin(angle)
	local cr = cos(angle)

	if forward then
		forward[0] = cp * cy
		forward[1] = cp * sy
		forward[2] = -sp
	end
	if right then
		right[0] = (-1 * sr * sp * cy + -1 * cr * -sy)
		right[1] = (-1 * sr * sp * sy + -1 * cr * cy)
		right[2] = -1 * sr * cp
	end
	if up then
		up[0] = (cr * sp * cy + -sr * -sy)
		up[1] = (cr * sp * sy + -sr * cy)
		up[2] = cr * cp
	end
end

function Q.AnglesToAxis(angles, axis)
	local right = Q.vec3()
	Q.AngleVectors(angles, axis[0], right, axis[2])
	Q.VectorSubtract(Q.vec3_origin, right, axis[1])
end

function Q.AxisClear(axis)
	Q.VectorSet(axis[0], 1, 0, 0)
	Q.VectorSet(axis[1], 0, 1, 0)
	Q.VectorSet(axis[2], 0, 0, 1)
end

function Q.AxisCopy(inp, out)
	Q.VectorCopy(inp[0], out[0])
	Q.VectorCopy(inp[1], out[1])
	Q.VectorCopy(inp[2], out[2])
end

function Q.MakeNormalVectors(forward, right, up)
	right[1] = -forward[0]
	right[2] = forward[1]
	right[0] = forward[2]
	local d = Q.DotProduct(right, forward)
	Q.VectorMA(right, -d, forward, right)
	Q.VectorNormalize(right)
	Q.CrossProduct(right, forward, up)
end

function Q.VectorRotate(inp, matrix, out)
	out[0] = Q.DotProduct(inp, matrix[0])
	out[1] = Q.DotProduct(inp, matrix[1])
	out[2] = Q.DotProduct(inp, matrix[2])
end

function Q.Q_rsqrt(number)
	return 1 / sqrt(number)
end

function Q.Q_fabs(f)
	return abs(f)
end

function Q.LerpAngle(from, to, frac)
	if to - from > 180 then
		to -= 360
	end
	if to - from < -180 then
		to += 360
	end
	return from + frac * (to - from)
end

function Q.AngleSubtract(a1, a2)
	local a = a1 - a2
	while a > 180 do
		a -= 360
	end
	while a < -180 do
		a += 360
	end
	return a
end

function Q.AnglesSubtract(v1, v2, v3)
	v3[0] = Q.AngleSubtract(v1[0], v2[0])
	v3[1] = Q.AngleSubtract(v1[1], v2[1])
	v3[2] = Q.AngleSubtract(v1[2], v2[2])
end

function Q.AngleMod(a)
	return (360.0 / 65536) * bit32.band(Q.int(a * (65536 / 360.0)), 65535)
end

function Q.AngleNormalize360(angle)
	return (360.0 / 65536) * bit32.band(Q.int(angle * (65536 / 360.0)), 65535)
end

function Q.AngleNormalize180(angle)
	angle = Q.AngleNormalize360(angle)
	if angle > 180.0 then
		angle -= 360.0
	end
	return angle
end

function Q.AngleDelta(angle1, angle2)
	return Q.AngleNormalize180(angle1 - angle2)
end

function Q.SetPlaneSignbits(out)
	local bits = 0
	for j = 0, 2 do
		if out.normal[j] < 0 then
			bits = bit32.bor(bits, bit32.lshift(1, j))
		end
	end
	out.signbits = bits
end

function Q.BoxOnPlaneSide(emins, emaxs, p)
	if p.type < 3 then
		if p.dist <= emins[p.type] then
			return 1
		end
		if p.dist >= emaxs[p.type] then
			return 2
		end
		return 3
	end

	local dist1, dist2 = 0, 0
	local bits = p.signbits
	if bits >= 0 and bits <= 7 then
		local n = p.normal
		local lo, hi = {}, {}
		for j = 0, 2 do
			if bit32.band(bits, bit32.lshift(1, j)) ~= 0 then
				hi[j], lo[j] = emins[j], emaxs[j]
			else
				hi[j], lo[j] = emaxs[j], emins[j]
			end
		end
		dist1 = n[0] * hi[0] + n[1] * hi[1] + n[2] * hi[2]
		dist2 = n[0] * lo[0] + n[1] * lo[1] + n[2] * lo[2]
	end

	local sides = 0
	if dist1 >= p.dist then
		sides = 1
	end
	if dist2 < p.dist then
		sides = bit32.bor(sides, 2)
	end
	return sides
end

function Q.RadiusFromBounds(mins, maxs)
	local corner = Q.vec3()
	for i = 0, 2 do
		local a = abs(mins[i])
		local b = abs(maxs[i])
		corner[i] = a > b and a or b
	end
	return Q.VectorLength(corner)
end

function Q.ClearBounds(mins, maxs)
	mins[0], mins[1], mins[2] = 99999, 99999, 99999
	maxs[0], maxs[1], maxs[2] = -99999, -99999, -99999
end

function Q.AddPointToBounds(v, mins, maxs)
	for i = 0, 2 do
		if v[i] < mins[i] then
			mins[i] = v[i]
		end
		if v[i] > maxs[i] then
			maxs[i] = v[i]
		end
	end
end

function Q.BoundsIntersect(mins, maxs, mins2, maxs2)
	if
		maxs[0] < mins2[0]
		or maxs[1] < mins2[1]
		or maxs[2] < mins2[2]
		or mins[0] > maxs2[0]
		or mins[1] > maxs2[1]
		or mins[2] > maxs2[2]
	then
		return false
	end
	return true
end

function Q.BoundsIntersectSphere(mins, maxs, origin, radius)
	if
		origin[0] - radius > maxs[0]
		or origin[0] + radius < mins[0]
		or origin[1] - radius > maxs[1]
		or origin[1] + radius < mins[1]
		or origin[2] - radius > maxs[2]
		or origin[2] + radius < mins[2]
	then
		return false
	end
	return true
end

function Q.BoundsIntersectPoint(mins, maxs, origin)
	if
		origin[0] > maxs[0]
		or origin[0] < mins[0]
		or origin[1] > maxs[1]
		or origin[1] < mins[1]
		or origin[2] > maxs[2]
		or origin[2] < mins[2]
	then
		return false
	end
	return true
end

function Q.Q_log2(val)
	local answer = 0
	val = bit32.rshift(val, 1)
	while val ~= 0 do
		answer += 1
		val = bit32.rshift(val, 1)
	end
	return answer
end

function Q.Q_isnan(x)
	return x ~= x and 1 or 0
end

-- SnapVectorTowards (moved to q_shared.c by unlagged): round toward `to`
-- so a snapped point never ends up inside a wall.
function Q.SnapVectorTowards(v, to)
	for i = 0, 2 do
		if to[i] <= v[i] then
			v[i] = Q.int(v[i])
		else
			v[i] = Q.int(v[i]) + 1
		end
	end
end

return Q
