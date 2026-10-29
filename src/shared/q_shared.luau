--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (qcommon/q_shared.c).

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
-- Luau port of the string side of q_shared.c (parsing, info strings, safe
-- string helpers, printf). The math side lives in q_math.luau.
--
-- Porting conventions (used by the whole gamecode port):
--   * C char buffers become immutable Luau strings. A function that writes
--     into a caller's buffer returns the new string instead:
--         Q_strncpyz(dest, src, n)        ->  dest = QS.Q_strncpyz(src, n)
--         Info_SetValueForKey(s, k, v)    ->  s = QS.Info_SetValueForKey(s, k, v)
--   * A `char **data_p` parse cursor is a table { data = string?, pos = 1 }
--     (pos is the 1-based byte index of *data_p). COM_Parse sets data = nil
--     where C sets *data_p = NULL. QS.cursor(str) makes one.
--   * va / Com_sprintf take a C format string; %i/%u/%ld are accepted, a
--     qboolean (Luau boolean) prints as 0/1 under %d/%i, nil under %s prints
--     "(null)" like glibc.

local QS = {}

local byte, sub, char, find, lower, upper, format, len = string.byte, string.sub, string.char, string.find, string.lower, string.upper, string.format, string.len
local floor = math.floor

QS.MAX_TOKEN_CHARS = 1024
QS.MAX_INFO_STRING = 1024
QS.BIG_INFO_STRING = 8192
QS.MAX_STRING_CHARS = 1024
QS.Q_COLOR_ESCAPE = "^"

-- engine print/error hooks, replaced by the host (server/client/tests)
QS.Com_Printf = function(msg: string) end
QS.Com_Error = function(level: number, msg: string)
	error(msg, 2)
end

local function trunc(x: number): number
	if x >= 0 then
		return floor(x)
	end
	return -floor(-x)
end

------------------------------------------------------------------------------
-- printf

local function cformat(fmt: string, ...): string
	local args = table.pack(...)
	local out = {}
	local ai = 1
	local i, n = 1, #fmt
	while i <= n do
		local s, e = find(fmt, "%", i, true)
		if not s then
			table.insert(out, sub(fmt, i))
			break
		end
		if s > i then
			table.insert(out, sub(fmt, i, s - 1))
		end
		local spec_s, spec_e, flags, width, prec, lenmod, conv = find(fmt, "^%%([-+ #0]*)(%*?%d*)(%.?%d*)([hlLqjzt]*)([%a%%])", s)
		if not spec_s then
			table.insert(out, "%")
			i = s + 1
			continue
		end
		if conv == "%" then
			table.insert(out, "%")
			i = spec_e + 1
			continue
		end
		if width == "*" then
			width = tostring(trunc(args[ai] or 0))
			ai += 1
		end
		local v = args[ai]
		ai += 1
		if conv == "i" or conv == "u" or conv == "d" then
			conv = "d"
			if type(v) == "boolean" then
				v = if v then 1 else 0
			elseif type(v) ~= "number" then
				v = tonumber(v) or 0
			end
			v = trunc(v)
			if lenmod == "" and conv == "d" and v >= 2147483648 then
				v -= 4294967296
			end
		elseif conv == "x" or conv == "X" or conv == "o" then
			if type(v) == "boolean" then
				v = if v then 1 else 0
			end
			v = trunc(tonumber(v) or 0)
			if v < 0 then
				v += 4294967296
			end
		elseif conv == "c" then
			if type(v) == "string" then
				v = byte(v) or 0
			end
			v = trunc(tonumber(v) or 0) % 256
		elseif conv == "s" then
			if v == nil then
				v = "(null)"
			elseif type(v) ~= "string" then
				v = tostring(v)
			end
		elseif conv == "f" or conv == "F" or conv == "g" or conv == "G" or conv == "e" or conv == "E" then
			if conv == "F" then
				conv = "f"
			end
			v = tonumber(v) or 0
		elseif conv == "p" then
			conv = "s"
			v = tostring(v)
		end
		table.insert(out, format("%" .. flags .. width .. prec .. conv, v))
		i = spec_e + 1
	end
	return table.concat(out)
end
QS.cformat = cformat

function QS.va(fmt: string, ...): string
	return sub(cformat(fmt, ...), 1, 31999)
end

-- Com_sprintf(dest, size, fmt, ...) -> dest = Com_sprintf(size, fmt, ...)
function QS.Com_sprintf(size: number, fmt: string, ...): string
	local s = cformat(fmt, ...)
	if #s >= size then
		QS.Com_Printf(cformat("Com_sprintf: overflow of %i in %i\n", #s, size))
	end
	return sub(s, 1, size - 1)
end

------------------------------------------------------------------------------
-- C library stand-ins

-- atoi: optional whitespace, sign, digits; stops at the first non digit
function QS.atoi(s: string?): number
	if not s then
		return 0
	end
	local m = string.match(s, "^%s*([-+]?%d+)")
	if not m then
		return 0
	end
	local v = tonumber(m) :: number
	-- wrap like a 32-bit int conversion in practice
	if v > 2147483647 or v < -2147483648 then
		v = ((v + 2147483648) % 4294967296) - 2147483648
	end
	return v
end

-- atof: the longest valid floating prefix (decimal, exponent, inf/nan)
function QS.atof(s: string?): number
	if not s then
		return 0
	end
	local m = string.match(s, "^%s*([-+]?%d*%.?%d*[eE][-+]?%d+)") or string.match(s, "^%s*([-+]?%d*%.?%d*)")
	if m then
		local v = tonumber(m)
		if v then
			return v
		end
		-- "1e" or "." style prefixes: retry without the exponent
		local m2 = string.match(m, "^([-+]?%d*%.?%d*)")
		v = m2 and tonumber(m2)
		if v then
			return v
		end
	end
	local w = string.match(s, "^%s*([-+]?)[iI][nN][fF]")
	if w then
		return if w == "-" then -math.huge else math.huge
	end
	return 0
end

function QS.strlen(s: string): number
	return #s
end

-- strchr / strstr presence tests
function QS.strchr(s: string, c: string): number?
	return (find(s, c, 1, true))
end
function QS.strstr(s: string, needle: string): number?
	return (find(s, needle, 1, true))
end

function QS.Com_Clamp(min: number, max: number, value: number): number
	if value < min then
		return min
	end
	if value > max then
		return max
	end
	return value
end

------------------------------------------------------------------------------
-- paths

function QS.COM_SkipPath(pathname: string): string
	local last = 1
	for i = 1, #pathname do
		if byte(pathname, i) == 47 then
			last = i + 1
		end
	end
	return sub(pathname, last)
end

function QS.COM_GetExtension(name: string): string
	local i = #name
	while i >= 1 and byte(name, i) ~= 46 do
		i -= 1
		if i <= 1 or byte(name, i) == 47 then
			return "" -- no extension
		end
	end
	if i < 1 then
		return ""
	end
	return sub(name, i + 1)
end

-- COM_StripExtension(in, out, destsize) -> out = COM_StripExtension(in, destsize)
function QS.COM_StripExtension(inp: string, destsize: number): string
	local out = sub(inp, 1, destsize - 1)
	local length = #out -- 1-based index of out[strlen-1]
	while length > 1 and byte(out, length) ~= 46 do
		length -= 1
		if byte(out, length) == 47 then
			return out -- no extension
		end
	end
	if length > 1 then
		out = sub(out, 1, length - 1)
	end
	return out
end

-- COM_DefaultExtension(path, maxSize, ext) -> path = COM_DefaultExtension(path, maxSize, ext)
function QS.COM_DefaultExtension(path: string, maxSize: number, extension: string): string
	local i = #path
	while i > 1 and byte(path, i) ~= 47 do
		if byte(path, i) == 46 then
			return path -- it has an extension
		end
		i -= 1
	end
	return QS.Com_sprintf(maxSize, "%s%s", sub(path, 1, 63), extension)
end

------------------------------------------------------------------------------
-- parsing

local com_lines = 0
local com_parsename = ""

function QS.cursor(s: string?)
	return { data = s, pos = 1 }
end

function QS.COM_BeginParseSession(name: string)
	com_lines = 0
	com_parsename = sub(name, 1, 1023)
end

function QS.COM_GetCurrentParseLine(): number
	return com_lines
end

function QS.COM_ParseError(fmt: string, ...)
	QS.Com_Printf(cformat("ERROR: %s, line %d: %s\n", com_parsename, com_lines, cformat(fmt, ...)))
end

function QS.COM_ParseWarning(fmt: string, ...)
	QS.Com_Printf(cformat("WARNING: %s, line %d: %s\n", com_parsename, com_lines, cformat(fmt, ...)))
end

-- returns the new position, or nil at the end of the data; second result
-- reports newlines crossed
local function SkipWhitespace(data: string, pos: number): (number?, boolean)
	local hasNewLines = false
	while true do
		local c = byte(data, pos) or 0
		if c > 32 then
			return pos, hasNewLines
		end
		if c == 0 then
			return nil, hasNewLines
		end
		if c == 10 then
			com_lines += 1
			hasNewLines = true
		end
		pos += 1
	end
end

function QS.COM_ParseExt(p, allowLineBreaks: boolean): string
	local data = p.data
	if not data then
		p.data = nil
		return ""
	end
	local pos = p.pos
	local c = 0
	local hadNewLines = false

	while true do
		-- skip whitespace
		local np, nl = SkipWhitespace(data, pos)
		hadNewLines = hadNewLines or nl
		if not np then
			p.data = nil
			return ""
		end
		pos = np
		if hadNewLines and not allowLineBreaks then
			p.pos = pos
			return ""
		end

		c = byte(data, pos) or 0

		-- skip double slash comments
		if c == 47 and byte(data, pos + 1) == 47 then
			pos += 2
			while true do
				local d = byte(data, pos)
				if not d or d == 0 or d == 10 then
					break
				end
				pos += 1
			end
		-- skip /* */ comments
		elseif c == 47 and byte(data, pos + 1) == 42 then
			pos += 2
			while true do
				local d = byte(data, pos)
				if not d or d == 0 or (d == 42 and byte(data, pos + 1) == 47) then
					break
				end
				pos += 1
			end
			if (byte(data, pos) or 0) ~= 0 then
				pos += 2
			end
		else
			break
		end
	end

	local tok = {}
	local tlen = 0
	-- handle quoted strings
	if c == 34 then
		pos += 1
		while true do
			c = byte(data, pos) or 0
			pos += 1
			if c == 34 or c == 0 then
				p.pos = pos
				if c == 0 then
					-- C leaves data_p one past the terminator; the next call sees
					-- the bytes after it (none here), so the string is exhausted
					p.pos = #data + 1
				end
				return table.concat(tok)
			end
			if tlen < QS.MAX_TOKEN_CHARS - 1 then
				tlen += 1
				tok[tlen] = char(c)
			end
		end
	end

	-- parse a regular word
	repeat
		if tlen < QS.MAX_TOKEN_CHARS - 1 then
			tlen += 1
			tok[tlen] = char(c)
		end
		pos += 1
		c = byte(data, pos) or 0
		if c == 10 then
			com_lines += 1
		end
	until c <= 32

	p.pos = pos
	return table.concat(tok)
end

function QS.COM_Parse(p): string
	return QS.COM_ParseExt(p, true)
end

-- COM_Compress(data) -> (newdata, length)
function QS.COM_Compress(data: string?): (string, number)
	if not data then
		return "", 0
	end
	local out = {}
	local newline, whitespace = false, false
	local i, n = 1, #data
	while i <= n do
		local c = byte(data, i)
		if c == 0 then
			break
		end
		if c == 47 and byte(data, i + 1) == 47 then
			while i <= n and byte(data, i) ~= 10 do
				i += 1
			end
		elseif c == 47 and byte(data, i + 1) == 42 then
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
					table.insert(out, sub(data, i, j))
					i = j + 1
				else
					table.insert(out, sub(data, i))
					i = n + 1
				end
			else
				table.insert(out, char(c))
				i += 1
			end
		end
	end
	local s = table.concat(out)
	return s, #s
end

function QS.COM_MatchToken(p, match: string)
	local token = QS.COM_Parse(p)
	if token ~= match then
		QS.Com_Error(1, cformat("MatchToken: %s != %s", token, match))
	end
end

function QS.SkipBracedSection(p)
	local depth = 0
	repeat
		local token = QS.COM_ParseExt(p, true)
		if #token == 1 then
			if token == "{" then
				depth += 1
			elseif token == "}" then
				depth -= 1
			end
		end
	until not (depth ~= 0 and p.data)
end

function QS.SkipRestOfLine(p)
	local data = p.data
	if not data then
		return
	end
	local pos = p.pos
	while true do
		local c = byte(data, pos) or 0
		pos += 1
		if c == 0 then
			break
		end
		if c == 10 then
			com_lines += 1
			break
		end
	end
	p.pos = pos
end

function QS.Parse1DMatrix(p, x: number, m, base: number?)
	base = base or 0
	QS.COM_MatchToken(p, "(")
	for i = 0, x - 1 do
		m[base + i] = QS.f(QS.atof(QS.COM_Parse(p)))
	end
	QS.COM_MatchToken(p, ")")
end

function QS.Parse2DMatrix(p, y: number, x: number, m, base: number?)
	base = base or 0
	QS.COM_MatchToken(p, "(")
	for i = 0, y - 1 do
		QS.Parse1DMatrix(p, x, m, base + i * x)
	end
	QS.COM_MatchToken(p, ")")
end

function QS.Parse3DMatrix(p, z: number, y: number, x: number, m, base: number?)
	base = base or 0
	QS.COM_MatchToken(p, "(")
	for i = 0, z - 1 do
		QS.Parse2DMatrix(p, y, x, m, base + i * x * y)
	end
	QS.COM_MatchToken(p, ")")
end

------------------------------------------------------------------------------
-- library replacement functions

function QS.Q_isprint(c: number): boolean
	return c >= 0x20 and c <= 0x7E
end
function QS.Q_islower(c: number): boolean
	return c >= 97 and c <= 122
end
function QS.Q_isupper(c: number): boolean
	return c >= 65 and c <= 90
end
function QS.Q_isalpha(c: number): boolean
	return (c >= 97 and c <= 122) or (c >= 65 and c <= 90)
end

-- returns the 1-based index of the last c in string (nil if absent)
function QS.Q_strrchr(s: string, c: string): number?
	local last = nil
	local cb = byte(c)
	for i = 1, #s do
		if byte(s, i) == cb then
			last = i
		end
	end
	return last
end

-- Q_strncpyz(dest, src, destsize) -> dest = Q_strncpyz(src, destsize)
function QS.Q_strncpyz(src: string, destsize: number): string
	if not src then
		QS.Com_Error(0, "Q_strncpyz: NULL src")
	end
	if destsize < 1 then
		QS.Com_Error(0, "Q_strncpyz: destsize < 1")
	end
	-- a C string stops at the first NUL
	local z = find(src, "\0", 1, true)
	if z then
		src = sub(src, 1, z - 1)
	end
	return sub(src, 1, destsize - 1)
end

local function upc(c: number): number
	if c >= 97 and c <= 122 then
		return c - 32
	end
	return c
end

function QS.Q_stricmpn(s1: string?, s2: string?, n: number): number
	if s1 == nil then
		return if s2 == nil then 0 else -1
	elseif s2 == nil then
		return 1
	end
	local i = 1
	while true do
		local c1 = byte(s1, i) or 0
		local c2 = byte(s2, i) or 0
		if n == 0 then
			return 0 -- strings are equal until end point
		end
		n -= 1
		if c1 ~= c2 then
			c1, c2 = upc(c1), upc(c2)
			if c1 ~= c2 then
				return if c1 < c2 then -1 else 1
			end
		end
		if c1 == 0 then
			return 0
		end
		i += 1
	end
end

function QS.Q_strncmp(s1: string, s2: string, n: number): number
	local i = 1
	while true do
		local c1 = byte(s1, i) or 0
		local c2 = byte(s2, i) or 0
		if n == 0 then
			return 0
		end
		n -= 1
		if c1 ~= c2 then
			return if c1 < c2 then -1 else 1
		end
		if c1 == 0 then
			return 0
		end
		i += 1
	end
end

function QS.strcmp(s1: string, s2: string): number
	if s1 == s2 then
		return 0
	end
	return if s1 < s2 then -1 else 1
end

function QS.Q_stricmp(s1: string?, s2: string?): number
	if s1 and s2 then
		return QS.Q_stricmpn(s1, s2, 99999)
	end
	return -1
end

function QS.Q_strequal(s1: string?, s2: string?): boolean
	return QS.Q_stricmp(s1, s2) == 0
end
function QS.Q_strequaln(s1: string?, s2: string?, n: number): boolean
	return QS.Q_stricmpn(s1, s2, n) == 0
end

function QS.Q_strlwr(s: string): string
	return lower(s)
end
function QS.Q_strupr(s: string): string
	return upper(s)
end
QS.Q_StrToLower = QS.Q_strlwr

-- Q_strcat(dest, size, src) -> dest = Q_strcat(dest, size, src)
function QS.Q_strcat(dest: string, size: number, src: string): string
	if #dest >= size then
		QS.Com_Error(0, "Q_strcat: already overflowed")
	end
	return dest .. QS.Q_strncpyz(src, size - #dest)
end

-- returns the 1-based index of the first case-insensitive match, or nil
function QS.Q_stristr(s: string, findstr: string): number?
	if #findstr == 0 then
		return 1
	end
	local r = find(upper(s), upper(findstr), 1, true)
	return r
end

local function IsColorString(s: string, i: number): boolean
	if byte(s, i) ~= 94 then
		return false
	end
	local c = byte(s, i + 1)
	return c ~= nil and c >= 48 and c <= 56
end
QS.Q_IsColorString = IsColorString

function QS.ColorIndex(c: number): number
	return c - 48
end

function QS.Q_PrintStrlen(s: string?): number
	if not s then
		return 0
	end
	local n, i = 0, 1
	while i <= #s do
		if IsColorString(s, i) then
			i += 2
		else
			i += 1
			n += 1
		end
	end
	return n
end

-- Q_CleanStr(string) -> string = Q_CleanStr(string)
function QS.Q_CleanStr(s: string): string
	while true do
		local out = {}
		local hadColor = false
		local i = 1
		while i <= #s do
			local c = byte(s, i)
			if c == 0 then
				break
			end
			if IsColorString(s, i) then
				i += 1
				hadColor = true
			elseif c >= 0x20 and c <= 0x7E then
				table.insert(out, char(c))
			end
			i += 1
		end
		s = table.concat(out)
		if not hadColor then
			return s
		end
	end
end

function QS.Q_CountChar(s: string, tocount: string): number
	local n = 0
	local b = byte(tocount)
	for i = 1, #s do
		if byte(s, i) == b then
			n += 1
		end
	end
	return n
end

QS.TRUNCATE_LENGTH = 64
function QS.Com_TruncateLongString(s: string): string
	local L = QS.TRUNCATE_LENGTH
	local length = #s
	if length <= L then
		return QS.Q_strncpyz(s, L)
	end
	local buffer = QS.Q_strncpyz(s, (L // 2) - 3)
	buffer = QS.Q_strcat(buffer, L, " ... ")
	buffer = QS.Q_strcat(buffer, L, sub(s, length - (L // 2) + 3 + 1))
	return buffer
end

------------------------------------------------------------------------------
-- info strings

-- Searches the string for the given key and returns the associated value,
-- or an empty string.
function QS.Info_ValueForKey(s: string?, key: string?): string
	if not s or not key then
		return ""
	end
	if #s >= QS.BIG_INFO_STRING then
		QS.Com_Error(1, "Info_ValueForKey: oversize infostring")
	end
	local i = 1
	if byte(s, 1) == 92 then
		i = 2
	end
	local n = #s
	while true do
		local ks = i
		while byte(s, i) ~= 92 do
			if i > n then
				return ""
			end
			i += 1
		end
		local pkey = sub(s, ks, i - 1)
		i += 1
		local vs = i
		while i <= n and byte(s, i) ~= 92 do
			i += 1
		end
		local value = sub(s, vs, i - 1)
		if QS.Q_strequal(key, pkey) then
			return value
		end
		if i > n then
			break
		end
		i += 1
	end
	return ""
end

-- Info_NextPair(&head, key, value) -> key, value = Info_NextPair(p) with p a
-- cursor ({ data = s, pos = i }); p.pos advances like *head.
function QS.Info_NextPair(p): (string, string)
	local s, i = p.data :: string, p.pos
	local n = #s
	if byte(s, i) == 92 then
		i += 1
	end
	local ks = i
	while byte(s, i) ~= 92 do
		if i > n then
			p.pos = i
			return sub(s, ks, i - 1), ""
		end
		i += 1
	end
	local key = sub(s, ks, i - 1)
	i += 1
	local vs = i
	while i <= n and byte(s, i) ~= 92 do
		i += 1
	end
	p.pos = i
	return key, sub(s, vs, i - 1)
end

-- Info_RemoveKey(s, key) -> s = Info_RemoveKey(s, key)
function QS.Info_RemoveKey(s: string, key: string): string
	if #s >= QS.MAX_INFO_STRING then
		QS.Com_Error(1, "Info_RemoveKey: oversize infostring")
	end
	if find(key, "\\", 1, true) then
		return s
	end
	local i, n = 1, #s
	while true do
		local start = i
		if byte(s, i) == 92 then
			i += 1
		end
		local ks = i
		while byte(s, i) ~= 92 do
			if i > n then
				return s
			end
			i += 1
		end
		local pkey = sub(s, ks, i - 1)
		i += 1
		while i <= n and byte(s, i) ~= 92 do
			i += 1
		end
		if key == pkey then
			return sub(s, 1, start - 1) .. sub(s, i) -- remove this part
		end
		if i > n then
			return s
		end
	end
end

-- Some characters are illegal in info strings because they can mess up the
-- server's parsing
function QS.Info_Validate(s: string): boolean
	if find(s, '"', 1, true) then
		return false
	end
	if find(s, ";", 1, true) then
		return false
	end
	return true
end

-- Info_SetValueForKey(s, key, value) -> s = Info_SetValueForKey(s, key, value)
function QS.Info_SetValueForKey(s: string, key: string, value: string?): string
	if #s >= QS.MAX_INFO_STRING then
		QS.Com_Error(1, "Info_SetValueForKey: oversize infostring")
	end
	for _, bl in { "\\", ";", '"' } do
		if find(key, bl, 1, true) or (value and find(value, bl, 1, true)) then
			QS.Com_Printf(cformat("^3Can't use keys or values with a '%s': %s = %s\n", bl, key, value or ""))
			return s
		end
	end

	s = QS.Info_RemoveKey(s, key)
	if not value or #value == 0 then
		return s
	end

	local newi = QS.Com_sprintf(QS.MAX_INFO_STRING, "\\%s\\%s", key, value)
	if #newi + #s >= QS.MAX_INFO_STRING then
		QS.Com_Printf("Info string length exceeded\n")
		return s
	end
	return newi .. s
end

------------------------------------------------------------------------------

local function CharIsOneOfCharset(c: number?, set: string): boolean
	if not c then
		return false
	end
	return find(set, char(c), 1, true) ~= nil
end

-- returns the 1-based index of the first char not in sep
function QS.Com_SkipCharset(s: string, sep: string, pos: number?): number
	local i = pos or 1
	while CharIsOneOfCharset(byte(s, i), sep) do
		i += 1
	end
	return i
end

-- returns the 1-based index after numTokens separated tokens (or 1)
function QS.Com_SkipTokens(s: string, numTokens: number, sep: string): number
	local sepCount = 0
	local i = 1
	while sepCount < numTokens do
		local c = byte(s, i)
		i += 1
		if CharIsOneOfCharset(c, sep) then
			sepCount += 1
			while CharIsOneOfCharset(byte(s, i), sep) do
				i += 1
			end
		elseif (byte(s, i) or 0) == 0 then
			break
		end
	end
	if sepCount == numTokens then
		return i
	end
	return 1
end

QS.f = require("./q_math").f

return QS
