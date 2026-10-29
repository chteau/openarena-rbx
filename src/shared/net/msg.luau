--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (ioquake3 code/qcommon/msg.c).

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
-- Network message encoding (ioquake3 code/qcommon/msg.c), shared by the
-- server and the client: a bit stream with ioq3's delta compression for
-- usercmd_t, entityState_t and playerState_t, using the same netField
-- tables, field order and bit widths.
--
-- Differences from the C file (see docs/formats/net.md): the stream is a
-- plain LSB-first bit packing in a Luau buffer instead of ioq3's adaptive
-- Huffman coding (Roblox already compresses remote payloads), so a
-- message is MSG_WriteBits output verbatim. Every bit sequence the C code
-- writes is written here in the same order and width.

local Q = require("../q_math")
local K = require("../consts")
local S = require("../structs")

local band, bor, bxor, lshift, rshift = bit32.band, bit32.bor, bit32.bxor, bit32.lshift, bit32.rshift

local MSG = {}

local GENTITYNUM_BITS = K.GENTITYNUM_BITS
local MAX_GENTITIES = K.MAX_GENTITIES
local MAX_STATS, MAX_PERSISTANT, MAX_WEAPONS, MAX_POWERUPS =
	K.MAX_STATS, K.MAX_PERSISTANT, K.MAX_WEAPONS, K.MAX_POWERUPS
local MAX_STRING_CHARS = K.MAX_STRING_CHARS
local BIG_INFO_STRING = K.BIG_INFO_STRING

local FLOAT_INT_BITS = 13
local FLOAT_INT_BIAS = lshift(1, FLOAT_INT_BITS - 1)

-- server to client ops (qcommon.h svc_ops_e)
MSG.svc_bad = 0
MSG.svc_nop = 1
MSG.svc_gamestate = 2
MSG.svc_configstring = 3
MSG.svc_baseline = 4
MSG.svc_serverCommand = 5
MSG.svc_download = 6
MSG.svc_snapshot = 7
MSG.svc_EOF = 8

-- client to server ops (clc_ops_e)
MSG.clc_bad = 0
MSG.clc_nop = 1
MSG.clc_move = 2
MSG.clc_moveNoDelta = 3
MSG.clc_clientCommand = 4
MSG.clc_EOF = 5

MSG.MAX_PACKET_USERCMDS = 32
MSG.MAX_MSGLEN = 16384

-- float <-> int bit pattern (floatint_t)
local fib = buffer.create(4)
local function floatBits(x: number): number
	buffer.writef32(fib, 0, x)
	return buffer.readi32(fib, 0)
end
local function bitsFloat(i: number): number
	buffer.writei32(fib, 0, i)
	return buffer.readf32(fib, 0)
end
MSG.floatBits = floatBits
MSG.bitsFloat = bitsFloat

-- to a signed 32-bit int (what C's int holds after the bit operations)
local function s32(v: number): number
	v = band(v, 0xFFFFFFFF)
	if v >= 0x80000000 then
		return v - 0x100000000
	end
	return v
end

--
-- msg_t
--

export type Msg = {
	data: buffer,
	maxsize: number, -- bytes
	cursize: number, -- bytes written / available
	bit: number, -- bit cursor (write or read)
	readcount: number, -- bytes consumed (C's readcount, for the overrun checks)
	overflowed: boolean,
}

function MSG.Init(maxsize: number?): Msg
	local n = maxsize or MSG.MAX_MSGLEN
	return {
		data = buffer.create(n),
		maxsize = n,
		cursize = 0,
		bit = 0,
		readcount = 0,
		overflowed = false,
	}
end

-- wrap a received payload for reading
function MSG.FromBuffer(b: buffer): Msg
	local n = buffer.len(b)
	return {
		data = b,
		maxsize = n,
		cursize = n,
		bit = 0,
		readcount = 0,
		overflowed = false,
	}
end

-- the bytes written so far, as a new buffer to send
function MSG.ToBuffer(msg: Msg): buffer
	local out = buffer.create(msg.cursize)
	buffer.copy(out, 0, msg.data, 0, msg.cursize)
	return out
end

function MSG.BeginReading(msg: Msg)
	msg.readcount = 0
	msg.bit = 0
end

function MSG.WriteBits(msg: Msg, value: number, bits: number)
	if msg.overflowed then
		return
	end
	if bits == 0 or bits < -31 or bits > 32 then
		error(string.format("MSG_WriteBits: bad bits %i", bits))
	end
	if bits < 0 then
		bits = -bits
	end
	if msg.bit + bits > msg.maxsize * 8 then
		msg.overflowed = true
		return
	end
	value = band(value, if bits == 32 then 0xFFFFFFFF else lshift(1, bits) - 1)
	local data = msg.data
	local pos = msg.bit
	local left = bits
	while left > 0 do
		local byte = rshift(pos, 3)
		local off = band(pos, 7)
		local n = math.min(8 - off, left)
		local chunk = band(value, lshift(1, n) - 1)
		local cur = if off == 0 then 0 else buffer.readu8(data, byte)
		buffer.writeu8(data, byte, bor(cur, lshift(chunk, off)))
		value = rshift(value, n)
		pos += n
		left -= n
	end
	msg.bit = pos
	msg.cursize = rshift(pos + 7, 3)
end

function MSG.ReadBits(msg: Msg, bits: number): number
	local sgn = false
	if bits < 0 then
		bits = -bits
		sgn = true
	end
	if msg.bit + bits > msg.cursize * 8 then
		-- past the end: C reads zeros and readcount passes cursize
		msg.bit = msg.cursize * 8 + 8
		msg.readcount = msg.cursize + 1
		return 0
	end
	local data = msg.data
	local pos = msg.bit
	local value = 0
	local got = 0
	while got < bits do
		local byte = rshift(pos, 3)
		local off = band(pos, 7)
		local n = math.min(8 - off, bits - got)
		local chunk = band(rshift(buffer.readu8(data, byte), off), lshift(1, n) - 1)
		value = bor(value, lshift(chunk, got))
		pos += n
		got += n
	end
	msg.bit = pos
	msg.readcount = rshift(pos + 7, 3)
	if sgn and bits < 32 then
		if band(value, lshift(1, bits - 1)) ~= 0 then
			value -= lshift(1, bits)
		end
		return value
	end
	if bits == 32 then
		return s32(value)
	end
	return value
end

-- true once a read went past the end of the message
function MSG.Overrun(msg: Msg): boolean
	return msg.readcount > msg.cursize
end

--
-- writing functions
--

function MSG.WriteChar(msg: Msg, c: number)
	MSG.WriteBits(msg, c, 8)
end

function MSG.WriteByte(msg: Msg, c: number)
	MSG.WriteBits(msg, c, 8)
end

function MSG.WriteData(msg: Msg, data: buffer, length: number)
	for i = 0, length - 1 do
		MSG.WriteByte(msg, buffer.readu8(data, i))
	end
end

function MSG.WriteShort(msg: Msg, c: number)
	MSG.WriteBits(msg, c, 16)
end

function MSG.WriteLong(msg: Msg, c: number)
	MSG.WriteBits(msg, c, 32)
end

function MSG.WriteFloat(msg: Msg, f: number)
	MSG.WriteBits(msg, floatBits(f), 32)
end

local function writeStringLimited(msg: Msg, s: string?, limit: number)
	if not s then
		MSG.WriteByte(msg, 0)
		return
	end
	local l = #s
	if l >= limit then
		MSG.WriteByte(msg, 0)
		return
	end
	-- get rid of 0x80+ and '%' chars, because old clients don't like them
	for i = 1, l do
		local c = string.byte(s, i)
		if c == 0 then
			break
		end
		if c > 127 or c == 37 then
			c = 46
		end
		MSG.WriteByte(msg, c)
	end
	MSG.WriteByte(msg, 0)
end

function MSG.WriteString(msg: Msg, s: string?)
	writeStringLimited(msg, s, MAX_STRING_CHARS)
end

function MSG.WriteBigString(msg: Msg, s: string?)
	writeStringLimited(msg, s, BIG_INFO_STRING)
end

function MSG.WriteAngle16(msg: Msg, f: number)
	MSG.WriteShort(msg, Q.ANGLE2SHORT(f))
end

--
-- reading functions
--

function MSG.ReadChar(msg: Msg): number
	local c = MSG.ReadBits(msg, -8)
	if msg.readcount > msg.cursize then
		c = -1
	end
	return c
end

-- returns -1 if no more characters are available
function MSG.ReadByte(msg: Msg): number
	local c = MSG.ReadBits(msg, 8)
	if msg.readcount > msg.cursize then
		c = -1
	end
	return c
end

function MSG.ReadShort(msg: Msg): number
	local c = MSG.ReadBits(msg, -16)
	if msg.readcount > msg.cursize then
		c = -1
	end
	return c
end

function MSG.ReadLong(msg: Msg): number
	local c = MSG.ReadBits(msg, 32)
	if msg.readcount > msg.cursize then
		c = -1
	end
	return c
end

function MSG.ReadFloat(msg: Msg): number
	local i = MSG.ReadBits(msg, 32)
	if msg.readcount > msg.cursize then
		return -1
	end
	return bitsFloat(i)
end

local function readStringLimited(msg: Msg, size: number): string
	local out = {}
	local l = 0
	while true do
		local c = MSG.ReadByte(msg) -- use ReadByte so -1 is out of bounds
		if c == -1 or c == 0 then
			break
		end
		-- translate all fmt spec to avoid crash bugs
		if c == 37 then
			c = 46
		end
		-- don't allow higher ascii values
		if c > 127 then
			c = 46
		end
		-- break only after reading all expected data from bitstream
		if l >= size - 1 then
			break
		end
		l += 1
		out[l] = string.char(c)
	end
	return table.concat(out)
end

function MSG.ReadString(msg: Msg): string
	return readStringLimited(msg, MAX_STRING_CHARS)
end

function MSG.ReadBigString(msg: Msg): string
	return readStringLimited(msg, BIG_INFO_STRING)
end

function MSG.ReadAngle16(msg: Msg): number
	return Q.SHORT2ANGLE(MSG.ReadShort(msg))
end

function MSG.ReadData(msg: Msg, out: buffer, len: number)
	for i = 0, len - 1 do
		buffer.writeu8(out, i, band(MSG.ReadByte(msg), 255))
	end
end

function MSG.HashKey(s: string, maxlen: number): number
	local hash = 0
	local i = 0
	while i < maxlen and i < #s do
		local c = string.byte(s, i + 1)
		if c == 0 then
			break
		end
		if band(c, 0x80) ~= 0 or c == 37 then
			hash += 46 * (119 + i)
		else
			-- C's char is signed, but values >= 0x80 took the branch above
			hash += c * (119 + i)
		end
		i += 1
	end
	hash = s32(hash)
	return s32(bxor(hash, bit32.arshift(hash, 10), bit32.arshift(hash, 20)))
end

--
-- delta functions with keys
--

local kbitmask = {}
for i = 1, 32 do
	kbitmask[i - 1] = if i == 32 then 0xFFFFFFFF else lshift(1, i) - 1
end

function MSG.WriteDeltaKey(msg: Msg, key: number, oldV: number, newV: number, bits: number)
	if oldV == newV then
		MSG.WriteBits(msg, 0, 1)
		return
	end
	MSG.WriteBits(msg, 1, 1)
	MSG.WriteBits(msg, bxor(newV, key), bits)
end

function MSG.ReadDeltaKey(msg: Msg, key: number, oldV: number, bits: number): number
	if MSG.ReadBits(msg, 1) ~= 0 then
		return bxor(MSG.ReadBits(msg, bits), band(key, kbitmask[bits - 1]))
	end
	return oldV
end

--
-- usercmd_t communication
--

local function sbyte(v: number): number
	v = band(v, 255)
	return if v >= 128 then v - 256 else v
end

function MSG.WriteDeltaUsercmdKey(msg: Msg, key: number, from, to)
	if to.serverTime - from.serverTime < 256 then
		MSG.WriteBits(msg, 1, 1)
		MSG.WriteBits(msg, to.serverTime - from.serverTime, 8)
	else
		MSG.WriteBits(msg, 0, 1)
		MSG.WriteBits(msg, to.serverTime, 32)
	end
	if
		from.angles[0] == to.angles[0]
		and from.angles[1] == to.angles[1]
		and from.angles[2] == to.angles[2]
		and from.forwardmove == to.forwardmove
		and from.rightmove == to.rightmove
		and from.upmove == to.upmove
		and from.buttons == to.buttons
		and from.weapon == to.weapon
	then
		MSG.WriteBits(msg, 0, 1) -- no change
		return
	end
	key = bxor(key, to.serverTime)
	MSG.WriteBits(msg, 1, 1)
	MSG.WriteDeltaKey(msg, key, from.angles[0], to.angles[0], 16)
	MSG.WriteDeltaKey(msg, key, from.angles[1], to.angles[1], 16)
	MSG.WriteDeltaKey(msg, key, from.angles[2], to.angles[2], 16)
	MSG.WriteDeltaKey(msg, key, from.forwardmove, to.forwardmove, 8)
	MSG.WriteDeltaKey(msg, key, from.rightmove, to.rightmove, 8)
	MSG.WriteDeltaKey(msg, key, from.upmove, to.upmove, 8)
	MSG.WriteDeltaKey(msg, key, from.buttons, to.buttons, 16)
	MSG.WriteDeltaKey(msg, key, from.weapon, to.weapon, 8)
end

function MSG.ReadDeltaUsercmdKey(msg: Msg, key: number, from, to)
	if MSG.ReadBits(msg, 1) ~= 0 then
		to.serverTime = s32(from.serverTime + MSG.ReadBits(msg, 8))
	else
		to.serverTime = MSG.ReadBits(msg, 32)
	end
	if MSG.ReadBits(msg, 1) ~= 0 then
		key = bxor(key, to.serverTime)
		-- angles are int: the 16 read bits stay unsigned
		to.angles[0] = MSG.ReadDeltaKey(msg, key, from.angles[0], 16)
		to.angles[1] = MSG.ReadDeltaKey(msg, key, from.angles[1], 16)
		to.angles[2] = MSG.ReadDeltaKey(msg, key, from.angles[2], 16)
		-- forwardmove/rightmove/upmove are signed char
		to.forwardmove = sbyte(MSG.ReadDeltaKey(msg, key, from.forwardmove, 8))
		if to.forwardmove == -128 then
			to.forwardmove = -127
		end
		to.rightmove = sbyte(MSG.ReadDeltaKey(msg, key, from.rightmove, 8))
		if to.rightmove == -128 then
			to.rightmove = -127
		end
		to.upmove = sbyte(MSG.ReadDeltaKey(msg, key, from.upmove, 8))
		if to.upmove == -128 then
			to.upmove = -127
		end
		to.buttons = MSG.ReadDeltaKey(msg, key, from.buttons, 16)
		-- weapon is a byte
		to.weapon = band(MSG.ReadDeltaKey(msg, key, from.weapon, 8), 255)
	else
		to.angles[0] = from.angles[0]
		to.angles[1] = from.angles[1]
		to.angles[2] = from.angles[2]
		to.forwardmove = from.forwardmove
		to.rightmove = from.rightmove
		to.upmove = from.upmove
		to.buttons = from.buttons
		to.weapon = from.weapon
	end
end

--
-- netField tables
--

type Field = {
	name: string,
	bits: number,
	get: (any) -> number,
	set: (any, number) -> (),
}

-- "pos.trBase[0]" -> accessors on the Luau struct
local function field(name: string, bits: number): Field
	local a, b, idx = string.match(name, "^([%w_]+)%.([%w_]+)%[(%d)%]$")
	if a then
		local i = tonumber(idx) :: number
		return {
			name = name,
			bits = bits,
			get = function(s)
				return s[a][b][i]
			end,
			set = function(s, v)
				s[a][b][i] = v
			end,
		}
	end
	local a2, b2 = string.match(name, "^([%w_]+)%.([%w_]+)$")
	if a2 then
		return {
			name = name,
			bits = bits,
			get = function(s)
				return s[a2][b2]
			end,
			set = function(s, v)
				s[a2][b2] = v
			end,
		}
	end
	local c, idx2 = string.match(name, "^([%w_]+)%[(%d)%]$")
	if c then
		local i = tonumber(idx2) :: number
		return {
			name = name,
			bits = bits,
			get = function(s)
				return s[c][i]
			end,
			set = function(s, v)
				s[c][i] = v
			end,
		}
	end
	return {
		name = name,
		bits = bits,
		get = function(s)
			return s[name]
		end,
		set = function(s, v)
			s[name] = v
		end,
	}
end

local G = GENTITYNUM_BITS
MSG.entityStateFields = {
	field("pos.trTime", 32),
	field("pos.trBase[0]", 0),
	field("pos.trBase[1]", 0),
	field("pos.trDelta[0]", 0),
	field("pos.trDelta[1]", 0),
	field("pos.trBase[2]", 0),
	field("apos.trBase[1]", 0),
	field("pos.trDelta[2]", 0),
	field("apos.trBase[0]", 0),
	field("event", 10),
	field("angles2[1]", 0),
	field("eType", 8),
	field("torsoAnim", 8),
	field("eventParm", 8),
	field("legsAnim", 8),
	field("groundEntityNum", G),
	field("pos.trType", 8),
	field("eFlags", 19),
	field("otherEntityNum", G),
	field("weapon", 8),
	field("clientNum", 8),
	field("angles[1]", 0),
	field("pos.trDuration", 32),
	field("apos.trType", 8),
	field("origin[0]", 0),
	field("origin[1]", 0),
	field("origin[2]", 0),
	field("solid", 24),
	field("powerups", MAX_POWERUPS),
	field("modelindex", 8),
	field("otherEntityNum2", G),
	field("loopSound", 8),
	field("generic1", 8),
	field("origin2[2]", 0),
	field("origin2[0]", 0),
	field("origin2[1]", 0),
	field("modelindex2", 8),
	field("angles[0]", 0),
	field("time", 32),
	field("apos.trTime", 32),
	field("apos.trDuration", 32),
	field("apos.trBase[2]", 0),
	field("apos.trDelta[0]", 0),
	field("apos.trDelta[1]", 0),
	field("apos.trDelta[2]", 0),
	field("time2", 32),
	field("angles[2]", 0),
	field("angles2[0]", 0),
	field("angles2[2]", 0),
	field("constantLight", 32),
	field("frame", 16),
}

MSG.playerStateFields = {
	field("commandTime", 32),
	field("origin[0]", 0),
	field("origin[1]", 0),
	field("bobCycle", 8),
	field("velocity[0]", 0),
	field("velocity[1]", 0),
	field("viewangles[1]", 0),
	field("viewangles[0]", 0),
	field("weaponTime", -16),
	field("origin[2]", 0),
	field("velocity[2]", 0),
	field("legsTimer", 8),
	field("pm_time", -16),
	field("eventSequence", 16),
	field("torsoAnim", 8),
	field("movementDir", 4),
	field("events[0]", 8),
	field("legsAnim", 8),
	field("events[1]", 8),
	field("pm_flags", 16),
	field("groundEntityNum", G),
	field("weaponstate", 4),
	field("eFlags", 16),
	field("externalEvent", 10),
	field("gravity", 16),
	field("speed", 16),
	field("delta_angles[1]", 16),
	field("externalEventParm", 8),
	field("viewheight", -8),
	field("damageEvent", 8),
	field("damageYaw", 8),
	field("damagePitch", 8),
	field("damageCount", 8),
	field("generic1", 8),
	field("pm_type", 8),
	field("delta_angles[0]", 16),
	field("delta_angles[2]", 16),
	field("torsoTimer", 12),
	field("eventParms[0]", 8),
	field("eventParms[1]", 8),
	field("clientNum", 8),
	field("weapon", 5),
	field("viewangles[2]", 0),
	field("grapplePoint[0]", 0),
	field("grapplePoint[1]", 0),
	field("grapplePoint[2]", 0),
	field("jumppad_ent", G),
	field("loopSound", 16),
}

-- C compares fields as 32-bit ints: floats by bit pattern (-0 ~= +0),
-- ints by their low 32 bits
local function fieldBits(f: Field, s): number
	local v = f.get(s)
	if f.bits == 0 then
		return floatBits(v)
	end
	return s32(v)
end

-- an integer field read back the way C stores it: the low `bits` of the
-- value land in a 32-bit int (sign-extended only for negative widths)
local function storeInt(v: number): number
	return s32(v)
end

local function writeFloatField(msg: Msg, v: number, allowZeroBit: boolean)
	local trunc = Q.trunc(v)
	if allowZeroBit and v == 0 then
		MSG.WriteBits(msg, 0, 1)
		return
	end
	if allowZeroBit then
		MSG.WriteBits(msg, 1, 1)
	end
	if trunc == v and trunc + FLOAT_INT_BIAS >= 0 and trunc + FLOAT_INT_BIAS < lshift(1, FLOAT_INT_BITS) then
		-- send as small integer
		MSG.WriteBits(msg, 0, 1)
		MSG.WriteBits(msg, trunc + FLOAT_INT_BIAS, FLOAT_INT_BITS)
	else
		-- send as full floating point value
		MSG.WriteBits(msg, 1, 1)
		MSG.WriteBits(msg, floatBits(v), 32)
	end
end

local function readFloatField(msg: Msg): number
	if MSG.ReadBits(msg, 1) == 0 then
		-- integral float; bias to allow equal parts positive and negative
		local trunc = MSG.ReadBits(msg, FLOAT_INT_BITS)
		trunc -= FLOAT_INT_BIAS
		return trunc
	end
	-- full floating point value
	return bitsFloat(MSG.ReadBits(msg, 32))
end

--
-- entityState_t communication
--

local nullEntity = S.entityState_t()
MSG.nullEntityState = nullEntity

-- Writes part of a packetentities message, including the entity number.
-- Can delta from either a baseline or a previous packet_entity. If to is
-- nil, a remove entity update will be sent. If force is not set, then
-- nothing at all will be generated if the entity is identical, under the
-- assumption that the in-order delta code will catch it.
function MSG.WriteDeltaEntity(msg: Msg, from, to, force: boolean)
	local fields = MSG.entityStateFields
	local numFields = #fields

	-- a nil to is a delta remove message
	if to == nil then
		if from == nil then
			return
		end
		MSG.WriteBits(msg, from.number, GENTITYNUM_BITS)
		MSG.WriteBits(msg, 1, 1)
		return
	end

	if to.number < 0 or to.number >= MAX_GENTITIES then
		error(string.format("MSG_WriteDeltaEntity: Bad entity number: %i", to.number))
	end

	local lc = 0
	-- build the change vector
	for i = 1, numFields do
		local fl = fields[i]
		if fieldBits(fl, from) ~= fieldBits(fl, to) then
			lc = i
		end
	end

	if lc == 0 then
		-- nothing at all changed
		if not force then
			return -- nothing at all
		end
		-- write two bits for no change
		MSG.WriteBits(msg, to.number, GENTITYNUM_BITS)
		MSG.WriteBits(msg, 0, 1) -- not removed
		MSG.WriteBits(msg, 0, 1) -- no delta
		return
	end

	MSG.WriteBits(msg, to.number, GENTITYNUM_BITS)
	MSG.WriteBits(msg, 0, 1) -- not removed
	MSG.WriteBits(msg, 1, 1) -- we have a delta

	MSG.WriteByte(msg, lc) -- # of changes

	for i = 1, lc do
		local fl = fields[i]
		if fieldBits(fl, from) == fieldBits(fl, to) then
			MSG.WriteBits(msg, 0, 1) -- no change
			continue
		end
		MSG.WriteBits(msg, 1, 1) -- changed
		if fl.bits == 0 then
			-- float
			writeFloatField(msg, fl.get(to), true)
		else
			local v = fl.get(to)
			if s32(v) == 0 then
				MSG.WriteBits(msg, 0, 1)
			else
				MSG.WriteBits(msg, 1, 1)
				-- integer
				MSG.WriteBits(msg, v, fl.bits)
			end
		end
	end
end

-- The entity number has already been read from the message, which is how
-- the from state is identified. If the delta removes the entity,
-- to.number will be set to MAX_GENTITIES-1. Can go from either a baseline
-- or a previous packet_entity.
function MSG.ReadDeltaEntity(msg: Msg, from, to, number: number)
	if number < 0 or number >= MAX_GENTITIES then
		error(string.format("Bad delta entity number: %i", number))
	end

	-- check for a remove
	if MSG.ReadBits(msg, 1) == 1 then
		S.copy_entityState_t(to, nullEntity)
		to.number = MAX_GENTITIES - 1
		return
	end

	-- check for no delta
	if MSG.ReadBits(msg, 1) == 0 then
		S.copy_entityState_t(to, from)
		to.number = number
		return
	end

	local fields = MSG.entityStateFields
	local numFields = #fields
	local lc = MSG.ReadByte(msg)
	if lc > numFields or lc < 0 then
		error("invalid entityState field count")
	end

	-- fields past lc and unchanged ones come from `from`; copy first so
	-- reading into the same table as `from` works too
	if to ~= from then
		S.copy_entityState_t(to, from)
	end
	to.number = number

	for i = 1, lc do
		local fl = fields[i]
		if MSG.ReadBits(msg, 1) == 0 then
			-- no change
			continue
		end
		if fl.bits == 0 then
			-- float
			if MSG.ReadBits(msg, 1) == 0 then
				fl.set(to, 0)
			else
				fl.set(to, readFloatField(msg))
			end
		else
			if MSG.ReadBits(msg, 1) == 0 then
				fl.set(to, 0)
			else
				-- integer
				fl.set(to, storeInt(MSG.ReadBits(msg, fl.bits)))
			end
		end
	end
end

--
-- playerState_t communication
--

local nullPlayer = S.playerState_t()

function MSG.WriteDeltaPlayerstate(msg: Msg, from, to)
	if not from then
		from = nullPlayer
	end

	local fields = MSG.playerStateFields
	local numFields = #fields

	local lc = 0
	for i = 1, numFields do
		local fl = fields[i]
		if fieldBits(fl, from) ~= fieldBits(fl, to) then
			lc = i
		end
	end

	MSG.WriteByte(msg, lc) -- # of changes

	for i = 1, lc do
		local fl = fields[i]
		if fieldBits(fl, from) == fieldBits(fl, to) then
			MSG.WriteBits(msg, 0, 1) -- no change
			continue
		end
		MSG.WriteBits(msg, 1, 1) -- changed
		if fl.bits == 0 then
			-- float
			writeFloatField(msg, fl.get(to), false)
		else
			-- integer
			MSG.WriteBits(msg, fl.get(to), fl.bits)
		end
	end

	--
	-- send the arrays
	--
	local statsbits = 0
	for i = 0, MAX_STATS - 1 do
		if to.stats[i] ~= from.stats[i] then
			statsbits = bor(statsbits, lshift(1, i))
		end
	end
	local persistantbits = 0
	for i = 0, MAX_PERSISTANT - 1 do
		if to.persistant[i] ~= from.persistant[i] then
			persistantbits = bor(persistantbits, lshift(1, i))
		end
	end
	local ammobits = 0
	for i = 0, MAX_WEAPONS - 1 do
		if to.ammo[i] ~= from.ammo[i] then
			ammobits = bor(ammobits, lshift(1, i))
		end
	end
	local powerupbits = 0
	for i = 0, MAX_POWERUPS - 1 do
		if to.powerups[i] ~= from.powerups[i] then
			powerupbits = bor(powerupbits, lshift(1, i))
		end
	end

	if statsbits == 0 and persistantbits == 0 and ammobits == 0 and powerupbits == 0 then
		MSG.WriteBits(msg, 0, 1) -- no change
		return
	end
	MSG.WriteBits(msg, 1, 1) -- changed

	if statsbits ~= 0 then
		MSG.WriteBits(msg, 1, 1) -- changed
		MSG.WriteBits(msg, statsbits, MAX_STATS)
		for i = 0, MAX_STATS - 1 do
			if band(statsbits, lshift(1, i)) ~= 0 then
				MSG.WriteShort(msg, to.stats[i])
			end
		end
	else
		MSG.WriteBits(msg, 0, 1) -- no change
	end

	if persistantbits ~= 0 then
		MSG.WriteBits(msg, 1, 1) -- changed
		MSG.WriteBits(msg, persistantbits, MAX_PERSISTANT)
		for i = 0, MAX_PERSISTANT - 1 do
			if band(persistantbits, lshift(1, i)) ~= 0 then
				MSG.WriteShort(msg, to.persistant[i])
			end
		end
	else
		MSG.WriteBits(msg, 0, 1) -- no change
	end

	if ammobits ~= 0 then
		MSG.WriteBits(msg, 1, 1) -- changed
		MSG.WriteBits(msg, ammobits, MAX_WEAPONS)
		for i = 0, MAX_WEAPONS - 1 do
			if band(ammobits, lshift(1, i)) ~= 0 then
				MSG.WriteShort(msg, to.ammo[i])
			end
		end
	else
		MSG.WriteBits(msg, 0, 1) -- no change
	end

	if powerupbits ~= 0 then
		MSG.WriteBits(msg, 1, 1) -- changed
		MSG.WriteBits(msg, powerupbits, MAX_POWERUPS)
		for i = 0, MAX_POWERUPS - 1 do
			if band(powerupbits, lshift(1, i)) ~= 0 then
				MSG.WriteLong(msg, to.powerups[i])
			end
		end
	else
		MSG.WriteBits(msg, 0, 1) -- no change
	end
end

function MSG.ReadDeltaPlayerstate(msg: Msg, from, to)
	if not from then
		from = nullPlayer
	end
	if to ~= from then
		S.copy_playerState_t(to, from)
	end

	local fields = MSG.playerStateFields
	local numFields = #fields
	local lc = MSG.ReadByte(msg)
	if lc > numFields or lc < 0 then
		error("invalid playerState field count")
	end

	for i = 1, lc do
		local fl = fields[i]
		if MSG.ReadBits(msg, 1) == 0 then
			-- no change
			continue
		end
		if fl.bits == 0 then
			-- float
			fl.set(to, readFloatField(msg))
		else
			-- integer
			fl.set(to, storeInt(MSG.ReadBits(msg, fl.bits)))
		end
	end

	-- read the arrays
	if MSG.ReadBits(msg, 1) ~= 0 then
		-- parse stats
		if MSG.ReadBits(msg, 1) ~= 0 then
			local bits = MSG.ReadBits(msg, MAX_STATS)
			for i = 0, MAX_STATS - 1 do
				if band(bits, lshift(1, i)) ~= 0 then
					to.stats[i] = MSG.ReadShort(msg)
				end
			end
		end
		-- parse persistant stats
		if MSG.ReadBits(msg, 1) ~= 0 then
			local bits = MSG.ReadBits(msg, MAX_PERSISTANT)
			for i = 0, MAX_PERSISTANT - 1 do
				if band(bits, lshift(1, i)) ~= 0 then
					to.persistant[i] = MSG.ReadShort(msg)
				end
			end
		end
		-- parse ammo
		if MSG.ReadBits(msg, 1) ~= 0 then
			local bits = MSG.ReadBits(msg, MAX_WEAPONS)
			for i = 0, MAX_WEAPONS - 1 do
				if band(bits, lshift(1, i)) ~= 0 then
					to.ammo[i] = MSG.ReadShort(msg)
				end
			end
		end
		-- parse powerups
		if MSG.ReadBits(msg, 1) ~= 0 then
			local bits = MSG.ReadBits(msg, MAX_POWERUPS)
			for i = 0, MAX_POWERUPS - 1 do
				if band(bits, lshift(1, i)) ~= 0 then
					to.powerups[i] = MSG.ReadLong(msg)
				end
			end
		end
	end
end

return MSG
