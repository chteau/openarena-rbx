--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (qcommon/q_math.c and the inline math of qcommon/q_shared.h).

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
-- Luau port of q_math.c. Vectors are 0-based tables {[0]=x, y, z}, exactly as
-- the C code indexes them. Every float operation is rounded to IEEE single
-- precision with f() after each step, matching what the C code computes on
-- an SSE build (each float op rounds; float*double promotes, then the store
-- rounds), so ported code stays bit-for-bit with the C original.

local Q = {}

local fbuf = buffer.create(4)
local writef32, readf32 = buffer.writef32, buffer.readf32
local sqrt, floor, ceil, abs, sin, cos, atan2 = math.sqrt, math.floor, math.ceil, math.abs, math.sin, math.cos, math.atan2

-- Round a double to the nearest float32 (ties to even), like a C float store.
local function f(x: number): number
	writef32(fbuf, 0, x)
	return readf32(fbuf, 0)
end
Q.f = f

-- C (int) cast: truncate toward zero.
local function trunc(x: number): number
	if x >= 0 then
		return floor(x)
	end
	return ceil(x)
end
Q.trunc = trunc

-- C integer division and remainder (truncating).
function Q.idiv(a: number, b: number): number
	return trunc(a / b)
end
function Q.imod(a: number, b: number): number
	return a - trunc(a / b) * b
end

-- Wrap to a signed 32/16/8 bit integer.
function Q.int32(x: number): number
	x = x % 4294967296
	if x >= 2147483648 then
		x -= 4294967296
	end
	return x
end
function Q.short(x: number): number
	return (x + 32768) % 65536 - 32768
end
function Q.schar(x: number): number
	return (x + 128) % 256 - 128
end
function Q.byte(x: number): number
	return x % 256
end

-- rint(): round to nearest, ties to even (cvtps2dq, as trap_SnapVector uses).
local function rint(x: number): number
	local r = floor(x + 0.5)
	if r - x == 0.5 and r % 2 ~= 0 then
		r -= 1
	end
	return r
end
Q.rint = rint

-- <math.h>'s double M_PI is the one native builds see (q_shared.h only
-- defines its float fallback when M_PI is missing)
local M_PI = math.pi
Q.M_PI = M_PI
local DEG2RAD_F = M_PI * 2 / 360
Q.DEG2RAD_F = DEG2RAD_F

function Q.DEG2RAD(a: number): number
	return f(a * M_PI / 180.0)
end
function Q.RAD2DEG(a: number): number
	return f(a * 180.0 / M_PI)
end

function Q.vec3(x: number?, y: number?, z: number?)
	return { [0] = x or 0, y or 0, z or 0 }
end
local vec3 = Q.vec3
Q.vec3_origin = vec3()
Q.axisDefault = { [0] = vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1) }

function Q.ANGLE2SHORT(x: number): number
	return trunc(f(f(x * 65536) / 360)) % 65536
end
function Q.SHORT2ANGLE(x: number): number
	return f(x * (360.0 / 65536))
end

function Q.DotProduct(a, b): number
	return f(f(f(a[0] * b[0]) + f(a[1] * b[1])) + f(a[2] * b[2]))
end
function Q.VectorSubtract(a, b, o)
	o[0] = f(a[0] - b[0])
	o[1] = f(a[1] - b[1])
	o[2] = f(a[2] - b[2])
end
function Q.VectorAdd(a, b, o)
	o[0] = f(a[0] + b[0])
	o[1] = f(a[1] + b[1])
	o[2] = f(a[2] + b[2])
end
function Q.VectorCopy(a, o)
	o[0] = a[0]
	o[1] = a[1]
	o[2] = a[2]
end
-- s must already be the float (or int) the C code multiplies by
function Q.VectorScale(v, s: number, o)
	o[0] = f(v[0] * s)
	o[1] = f(v[1] * s)
	o[2] = f(v[2] * s)
end
function Q.VectorMA(v, s: number, b, o)
	o[0] = f(v[0] + f(b[0] * s))
	o[1] = f(v[1] + f(b[1] * s))
	o[2] = f(v[2] + f(b[2] * s))
end
function Q.VectorClear(a)
	a[0] = 0
	a[1] = 0
	a[2] = 0
end
function Q.VectorNegate(a, o)
	o[0] = -a[0]
	o[1] = -a[1]
	o[2] = -a[2]
end
function Q.VectorSet(v, x: number, y: number, z: number)
	v[0] = x
	v[1] = y
	v[2] = z
end
function Q.VectorInverse(v)
	v[0] = -v[0]
	v[1] = -v[1]
	v[2] = -v[2]
end
function Q.VectorCompare(a, b): boolean
	return a[0] == b[0] and a[1] == b[1] and a[2] == b[2]
end
function Q.Vector4Copy(a, o)
	o[0] = a[0]
	o[1] = a[1]
	o[2] = a[2]
	o[3] = a[3]
end
local function lensq(v): number
	return f(f(f(v[0] * v[0]) + f(v[1] * v[1])) + f(v[2] * v[2]))
end
Q.VectorLengthSquared = lensq
function Q.VectorLength(v): number
	return f(sqrt(lensq(v)))
end
function Q.Distance(a, b): number
	local x, y, z = f(b[0] - a[0]), f(b[1] - a[1]), f(b[2] - a[2])
	return f(sqrt(f(f(f(x * x) + f(y * y)) + f(z * z))))
end
function Q.DistanceSquared(a, b): number
	local x, y, z = f(b[0] - a[0]), f(b[1] - a[1]), f(b[2] - a[2])
	return f(f(f(x * x) + f(y * y)) + f(z * z))
end
function Q.CrossProduct(a, b, o)
	local x = f(f(a[1] * b[2]) - f(a[2] * b[1]))
	local y = f(f(a[2] * b[0]) - f(a[0] * b[2]))
	local z = f(f(a[0] * b[1]) - f(a[1] * b[0]))
	o[0], o[1], o[2] = x, y, z
end

-- OpenArena's VectorNormalize (gamecode q_math.c): sqrt, then 1/length.
function Q.VectorNormalize(v): number
	local length = f(sqrt(lensq(v)))
	if length ~= 0 then
		local ilength = f(1 / length)
		v[0] = f(v[0] * ilength)
		v[1] = f(v[1] * ilength)
		v[2] = f(v[2] * ilength)
	end
	return length
end
function Q.VectorNormalize2(v, o): number
	local length = f(sqrt(lensq(v)))
	if length ~= 0 then
		local ilength = f(1 / length)
		o[0] = f(v[0] * ilength)
		o[1] = f(v[1] * ilength)
		o[2] = f(v[2] * ilength)
	else
		o[0], o[1], o[2] = 0, 0, 0
	end
	return length
end

-- ioquake3's VectorNormalize (qcommon/q_math.c), used by the collision code:
-- ilength = 1/(float)sqrt(len), length *= ilength.
function Q.VectorNormalizeIoq3(v): number
	local length = lensq(v)
	if length ~= 0 then
		local ilength = f(1 / f(sqrt(length)))
		length = f(length * ilength)
		v[0] = f(v[0] * ilength)
		v[1] = f(v[1] * ilength)
		v[2] = f(v[2] * ilength)
	end
	return length
end
function Q.VectorNormalize2Ioq3(v, o): number
	local length = lensq(v)
	if length ~= 0 then
		local ilength = f(1 / f(sqrt(length)))
		length = f(length * ilength)
		o[0] = f(v[0] * ilength)
		o[1] = f(v[1] * ilength)
		o[2] = f(v[2] * ilength)
	else
		o[0], o[1], o[2] = 0, 0, 0
	end
	return length
end

function Q.VectorNormalizeFast(v)
	local ilength = Q.Q_rsqrt(Q.DotProduct(v, v))
	v[0] = f(v[0] * ilength)
	v[1] = f(v[1] * ilength)
	v[2] = f(v[2] * ilength)
end

local ibuf = buffer.create(4)
function Q.Q_rsqrt(number: number): number
	local x2 = f(number * 0.5)
	writef32(ibuf, 0, number)
	local i = buffer.readi32(ibuf, 0)
	i = 0x5f3759df - bit32.arshift(i, 1)
	buffer.writei32(ibuf, 0, i)
	local y = readf32(ibuf, 0)
	y = f(y * f(1.5 - f(f(x2 * y) * y)))
	return y
end

function Q.AngleVectors(angles, forward, right, up)
	local angle = f(angles[1] * DEG2RAD_F)
	local sy, cy = f(sin(angle)), f(cos(angle))
	angle = f(angles[0] * DEG2RAD_F)
	local sp, cp = f(sin(angle)), f(cos(angle))
	angle = f(angles[2] * DEG2RAD_F)
	local sr, cr = f(sin(angle)), f(cos(angle))
	if forward then
		forward[0] = f(cp * cy)
		forward[1] = f(cp * sy)
		forward[2] = -sp
	end
	if right then
		right[0] = f(f(f(-sr * sp) * cy) + f(-cr * -sy))
		right[1] = f(f(f(-sr * sp) * sy) + f(-cr * cy))
		right[2] = f(-sr * cp)
	end
	if up then
		up[0] = f(f(f(cr * sp) * cy) + f(-sr * -sy))
		up[1] = f(f(f(cr * sp) * sy) + f(-sr * cy))
		up[2] = f(cr * cp)
	end
end

function Q.vectoangles(value1, angles)
	local yaw, pitch
	if value1[1] == 0 and value1[0] == 0 then
		yaw = 0
		pitch = if value1[2] > 0 then 90 else 270
	else
		if value1[0] ~= 0 then
			yaw = f(atan2(value1[1], value1[0]) * 180 / M_PI)
		elseif value1[1] > 0 then
			yaw = 90
		else
			yaw = 270
		end
		if yaw < 0 then
			yaw = f(yaw + 360)
		end
		local forward = f(sqrt(f(f(value1[0] * value1[0]) + f(value1[1] * value1[1]))))
		pitch = f(atan2(value1[2], forward) * 180 / M_PI)
		if pitch < 0 then
			pitch = f(pitch + 360)
		end
	end
	angles[0] = -pitch
	angles[1] = yaw
	angles[2] = 0
end

function Q.AnglesToAxis(angles, axis)
	local right = vec3()
	Q.AngleVectors(angles, axis[0], right, axis[2])
	Q.VectorSubtract(Q.vec3_origin, right, axis[1])
end
function Q.AxisClear(axis)
	axis[0][0], axis[0][1], axis[0][2] = 1, 0, 0
	axis[1][0], axis[1][1], axis[1][2] = 0, 1, 0
	axis[2][0], axis[2][1], axis[2][2] = 0, 0, 1
end
function Q.AxisCopy(i, o)
	Q.VectorCopy(i[0], o[0])
	Q.VectorCopy(i[1], o[1])
	Q.VectorCopy(i[2], o[2])
end

function Q.AngleMod(a: number): number
	return f((360.0 / 65536) * bit32.band(trunc(a * (65536 / 360.0)), 65535))
end
function Q.AngleNormalize360(angle: number): number
	return f((360.0 / 65536) * bit32.band(trunc(angle * (65536 / 360.0)), 65535))
end
function Q.AngleNormalize180(angle: number): number
	angle = Q.AngleNormalize360(angle)
	if angle > 180.0 then
		angle = f(angle - 360.0)
	end
	return angle
end
function Q.AngleDelta(angle1: number, angle2: number): number
	return Q.AngleNormalize180(f(angle1 - angle2))
end
function Q.AngleSubtract(a1: number, a2: number): number
	local a = f(a1 - a2)
	while a > 180 do
		a = f(a - 360)
	end
	while a < -180 do
		a = f(a + 360)
	end
	return a
end
function Q.AnglesSubtract(v1, v2, v3)
	v3[0] = Q.AngleSubtract(v1[0], v2[0])
	v3[1] = Q.AngleSubtract(v1[1], v2[1])
	v3[2] = Q.AngleSubtract(v1[2], v2[2])
end
function Q.LerpAngle(from: number, to: number, frac: number): number
	if f(to - from) > 180 then
		to = f(to - 360)
	end
	if f(to - from) < -180 then
		to = f(to + 360)
	end
	return f(from + f(frac * f(to - from)))
end

function Q.ProjectPointOnPlane(dst, p, normal)
	local inv_denom = Q.DotProduct(normal, normal)
	inv_denom = f(1.0 / inv_denom)
	local d = f(Q.DotProduct(normal, p) * inv_denom)
	local n0, n1, n2 = f(normal[0] * inv_denom), f(normal[1] * inv_denom), f(normal[2] * inv_denom)
	dst[0] = f(p[0] - f(d * n0))
	dst[1] = f(p[1] - f(d * n1))
	dst[2] = f(p[2] - f(d * n2))
end

function Q.PerpendicularVector(dst, src)
	local pos, minelem = 0, 1.0
	for i = 0, 2 do
		if abs(src[i]) < minelem then
			pos = i
			minelem = abs(src[i])
		end
	end
	local tempvec = vec3()
	tempvec[pos] = 1.0
	Q.ProjectPointOnPlane(dst, tempvec, src)
	Q.VectorNormalize(dst)
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

function Q.VectorRotate(i, matrix, o)
	o[0] = Q.DotProduct(i, matrix[0])
	o[1] = Q.DotProduct(i, matrix[1])
	o[2] = Q.DotProduct(i, matrix[2])
end

local function MatrixMultiply(in1, in2, out)
	for i = 0, 2 do
		for j = 0, 2 do
			out[i][j] = f(f(f(in1[i][0] * in2[0][j]) + f(in1[i][1] * in2[1][j])) + f(in1[i][2] * in2[2][j]))
		end
	end
end
Q.MatrixMultiply = MatrixMultiply
local function mat3()
	return { [0] = vec3(), vec3(), vec3() }
end
Q.mat3 = mat3

function Q.RotatePointAroundVector(dst, dir, point, degrees: number)
	local m, im, zrot, tmpmat, rot = mat3(), mat3(), mat3(), mat3(), mat3()
	local vr, vup, vf = vec3(), vec3(), vec3(dir[0], dir[1], dir[2])
	Q.PerpendicularVector(vr, dir)
	Q.CrossProduct(vr, vf, vup)
	m[0][0], m[1][0], m[2][0] = vr[0], vr[1], vr[2]
	m[0][1], m[1][1], m[2][1] = vup[0], vup[1], vup[2]
	m[0][2], m[1][2], m[2][2] = vf[0], vf[1], vf[2]
	for i = 0, 2 do
		for j = 0, 2 do
			im[i][j] = m[i][j]
		end
	end
	im[0][1], im[0][2], im[1][0] = m[1][0], m[2][0], m[0][1]
	im[1][2], im[2][0], im[2][1] = m[2][1], m[0][2], m[1][2]
	zrot[2][2] = 1.0
	local rad = Q.DEG2RAD(degrees)
	zrot[0][0] = f(cos(rad))
	zrot[0][1] = f(sin(rad))
	zrot[1][0] = f(-sin(rad))
	zrot[1][1] = f(cos(rad))
	MatrixMultiply(m, zrot, tmpmat)
	MatrixMultiply(tmpmat, im, rot)
	for i = 0, 2 do
		dst[i] = f(f(f(rot[i][0] * point[0]) + f(rot[i][1] * point[1])) + f(rot[i][2] * point[2]))
	end
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
function Q.RadiusFromBounds(mins, maxs): number
	local corner = vec3()
	for i = 0, 2 do
		local a, b = abs(mins[i]), abs(maxs[i])
		corner[i] = if a > b then a else b
	end
	return Q.VectorLength(corner)
end

function Q.PlaneTypeForNormal(x): number
	if x[0] == 1.0 then
		return 0
	elseif x[1] == 1.0 then
		return 1
	elseif x[2] == 1.0 then
		return 2
	end
	return 3
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

-- ioquake3 BoxOnPlaneSide: 1 = front, 2 = back, 3 = both
function Q.BoxOnPlaneSide(emins, emaxs, p): number
	local ptype = p.type
	if ptype < 3 then
		if p.dist <= emins[ptype] then
			return 1
		end
		if p.dist >= emaxs[ptype] then
			return 2
		end
		return 3
	end
	local d0, d1 = 0, 0
	local signbits, normal = p.signbits, p.normal
	if signbits < 8 then
		for i = 0, 2 do
			local nmax, nmin = f(normal[i] * emaxs[i]), f(normal[i] * emins[i])
			if bit32.band(bit32.rshift(signbits, i), 1) == 1 then
				d1 = f(d1 + nmax)
				d0 = f(d0 + nmin)
			else
				d0 = f(d0 + nmax)
				d1 = f(d1 + nmin)
			end
		end
	end
	local sides = 0
	if d0 >= p.dist then
		sides = 1
	end
	if d1 < p.dist then
		sides = bit32.bor(sides, 2)
	end
	return sides
end

function Q.ClampChar(i: number): number
	if i < -128 then
		return -128
	end
	if i > 127 then
		return 127
	end
	return i
end
function Q.ClampShort(i: number): number
	if i < -32768 then
		return -32768
	end
	if i > 0x7fff then
		return 0x7fff
	end
	return i
end

function Q.NormalizeColor(i, o): number
	local max = i[0]
	if i[1] > max then
		max = i[1]
	end
	if i[2] > max then
		max = i[2]
	end
	if max == 0 then
		Q.VectorClear(o)
	else
		o[0], o[1], o[2] = f(i[0] / max), f(i[1] / max), f(i[2] / max)
	end
	return max
end

function Q.PlaneFromPoints(plane, a, b, c): boolean
	local d1, d2 = vec3(), vec3()
	Q.VectorSubtract(b, a, d1)
	Q.VectorSubtract(c, a, d2)
	Q.CrossProduct(d2, d1, plane)
	if Q.VectorNormalize(plane) == 0 then
		return false
	end
	plane[3] = Q.DotProduct(a, plane)
	return true
end

function Q.Q_log2(val: number): number
	local answer = 0
	val = bit32.rshift(val, 1)
	while val ~= 0 do
		answer += 1
		val = bit32.rshift(val, 1)
	end
	return answer
end

-- Unsigned 32-bit multiply without losing bits to double rounding.
local function mul32(a: number, b: number): number
	local alo, ahi = a % 65536, floor(a / 65536) % 65536
	return (alo * b + ((ahi * b) % 65536) * 65536) % 4294967296
end
Q.mul32 = mul32

-- bg_lib.c rand(): the generator the QVM build of the gamecode uses.
local randSeed = 0
function Q.srand(seed: number)
	randSeed = seed % 4294967296
end
function Q.rand(): number
	randSeed = (mul32(1103515245, randSeed) + 12345) % 4294967296
	return bit32.band(bit32.rshift(randSeed, 16), 0x7fff)
end
-- #define random() ((rand () & 0x7fff) / ((float)0x7fff))
function Q.random(): number
	return f(bit32.band(Q.rand(), 0x7fff) / 0x7fff)
end
-- #define crandom() (2.0 * (random() - 0.5))
function Q.crandom(): number
	return 2.0 * (Q.random() - 0.5)
end

-- Q_random / Q_crandom (q_math.c), seeded variants. seed is a table {value}.
function Q.Q_rand(seed): number
	seed.value = Q.int32(mul32(seed.value % 4294967296, 69069) + 1)
	return seed.value
end
function Q.Q_random(seed): number
	return f(bit32.band(Q.Q_rand(seed), 0xffff) / 0x10000)
end
function Q.Q_crandom(seed): number
	return f(2.0 * f(Q.Q_random(seed) - 0.5))
end

local NUMVERTEXNORMALS = 162
Q.NUMVERTEXNORMALS = NUMVERTEXNORMALS
local bytedirs = {
	{[0]=-0.525731,0.000000,0.850651},
	{[0]=-0.442863,0.238856,0.864188},
	{[0]=-0.295242,0.000000,0.955423},
	{[0]=-0.309017,0.500000,0.809017},
	{[0]=-0.162460,0.262866,0.951056},
	{[0]=0.000000,0.000000,1.000000},
	{[0]=0.000000,0.850651,0.525731},
	{[0]=-0.147621,0.716567,0.681718},
	{[0]=0.147621,0.716567,0.681718},
	{[0]=0.000000,0.525731,0.850651},
	{[0]=0.309017,0.500000,0.809017},
	{[0]=0.525731,0.000000,0.850651},
	{[0]=0.295242,0.000000,0.955423},
	{[0]=0.442863,0.238856,0.864188},
	{[0]=0.162460,0.262866,0.951056},
	{[0]=-0.681718,0.147621,0.716567},
	{[0]=-0.809017,0.309017,0.500000},
	{[0]=-0.587785,0.425325,0.688191},
	{[0]=-0.850651,0.525731,0.000000},
	{[0]=-0.864188,0.442863,0.238856},
	{[0]=-0.716567,0.681718,0.147621},
	{[0]=-0.688191,0.587785,0.425325},
	{[0]=-0.500000,0.809017,0.309017},
	{[0]=-0.238856,0.864188,0.442863},
	{[0]=-0.425325,0.688191,0.587785},
	{[0]=-0.716567,0.681718,-0.147621},
	{[0]=-0.500000,0.809017,-0.309017},
	{[0]=-0.525731,0.850651,0.000000},
	{[0]=0.000000,0.850651,-0.525731},
	{[0]=-0.238856,0.864188,-0.442863},
	{[0]=0.000000,0.955423,-0.295242},
	{[0]=-0.262866,0.951056,-0.162460},
	{[0]=0.000000,1.000000,0.000000},
	{[0]=0.000000,0.955423,0.295242},
	{[0]=-0.262866,0.951056,0.162460},
	{[0]=0.238856,0.864188,0.442863},
	{[0]=0.262866,0.951056,0.162460},
	{[0]=0.500000,0.809017,0.309017},
	{[0]=0.238856,0.864188,-0.442863},
	{[0]=0.262866,0.951056,-0.162460},
	{[0]=0.500000,0.809017,-0.309017},
	{[0]=0.850651,0.525731,0.000000},
	{[0]=0.716567,0.681718,0.147621},
	{[0]=0.716567,0.681718,-0.147621},
	{[0]=0.525731,0.850651,0.000000},
	{[0]=0.425325,0.688191,0.587785},
	{[0]=0.864188,0.442863,0.238856},
	{[0]=0.688191,0.587785,0.425325},
	{[0]=0.809017,0.309017,0.500000},
	{[0]=0.681718,0.147621,0.716567},
	{[0]=0.587785,0.425325,0.688191},
	{[0]=0.955423,0.295242,0.000000},
	{[0]=1.000000,0.000000,0.000000},
	{[0]=0.951056,0.162460,0.262866},
	{[0]=0.850651,-0.525731,0.000000},
	{[0]=0.955423,-0.295242,0.000000},
	{[0]=0.864188,-0.442863,0.238856},
	{[0]=0.951056,-0.162460,0.262866},
	{[0]=0.809017,-0.309017,0.500000},
	{[0]=0.681718,-0.147621,0.716567},
	{[0]=0.850651,0.000000,0.525731},
	{[0]=0.864188,0.442863,-0.238856},
	{[0]=0.809017,0.309017,-0.500000},
	{[0]=0.951056,0.162460,-0.262866},
	{[0]=0.525731,0.000000,-0.850651},
	{[0]=0.681718,0.147621,-0.716567},
	{[0]=0.681718,-0.147621,-0.716567},
	{[0]=0.850651,0.000000,-0.525731},
	{[0]=0.809017,-0.309017,-0.500000},
	{[0]=0.864188,-0.442863,-0.238856},
	{[0]=0.951056,-0.162460,-0.262866},
	{[0]=0.147621,0.716567,-0.681718},
	{[0]=0.309017,0.500000,-0.809017},
	{[0]=0.425325,0.688191,-0.587785},
	{[0]=0.442863,0.238856,-0.864188},
	{[0]=0.587785,0.425325,-0.688191},
	{[0]=0.688191,0.587785,-0.425325},
	{[0]=-0.147621,0.716567,-0.681718},
	{[0]=-0.309017,0.500000,-0.809017},
	{[0]=0.000000,0.525731,-0.850651},
	{[0]=-0.525731,0.000000,-0.850651},
	{[0]=-0.442863,0.238856,-0.864188},
	{[0]=-0.295242,0.000000,-0.955423},
	{[0]=-0.162460,0.262866,-0.951056},
	{[0]=0.000000,0.000000,-1.000000},
	{[0]=0.295242,0.000000,-0.955423},
	{[0]=0.162460,0.262866,-0.951056},
	{[0]=-0.442863,-0.238856,-0.864188},
	{[0]=-0.309017,-0.500000,-0.809017},
	{[0]=-0.162460,-0.262866,-0.951056},
	{[0]=0.000000,-0.850651,-0.525731},
	{[0]=-0.147621,-0.716567,-0.681718},
	{[0]=0.147621,-0.716567,-0.681718},
	{[0]=0.000000,-0.525731,-0.850651},
	{[0]=0.309017,-0.500000,-0.809017},
	{[0]=0.442863,-0.238856,-0.864188},
	{[0]=0.162460,-0.262866,-0.951056},
	{[0]=0.238856,-0.864188,-0.442863},
	{[0]=0.500000,-0.809017,-0.309017},
	{[0]=0.425325,-0.688191,-0.587785},
	{[0]=0.716567,-0.681718,-0.147621},
	{[0]=0.688191,-0.587785,-0.425325},
	{[0]=0.587785,-0.425325,-0.688191},
	{[0]=0.000000,-0.955423,-0.295242},
	{[0]=0.000000,-1.000000,0.000000},
	{[0]=0.262866,-0.951056,-0.162460},
	{[0]=0.000000,-0.850651,0.525731},
	{[0]=0.000000,-0.955423,0.295242},
	{[0]=0.238856,-0.864188,0.442863},
	{[0]=0.262866,-0.951056,0.162460},
	{[0]=0.500000,-0.809017,0.309017},
	{[0]=0.716567,-0.681718,0.147621},
	{[0]=0.525731,-0.850651,0.000000},
	{[0]=-0.238856,-0.864188,-0.442863},
	{[0]=-0.500000,-0.809017,-0.309017},
	{[0]=-0.262866,-0.951056,-0.162460},
	{[0]=-0.850651,-0.525731,0.000000},
	{[0]=-0.716567,-0.681718,-0.147621},
	{[0]=-0.716567,-0.681718,0.147621},
	{[0]=-0.525731,-0.850651,0.000000},
	{[0]=-0.500000,-0.809017,0.309017},
	{[0]=-0.238856,-0.864188,0.442863},
	{[0]=-0.262866,-0.951056,0.162460},
	{[0]=-0.864188,-0.442863,0.238856},
	{[0]=-0.809017,-0.309017,0.500000},
	{[0]=-0.688191,-0.587785,0.425325},
	{[0]=-0.681718,-0.147621,0.716567},
	{[0]=-0.442863,-0.238856,0.864188},
	{[0]=-0.587785,-0.425325,0.688191},
	{[0]=-0.309017,-0.500000,0.809017},
	{[0]=-0.147621,-0.716567,0.681718},
	{[0]=-0.425325,-0.688191,0.587785},
	{[0]=-0.162460,-0.262866,0.951056},
	{[0]=0.442863,-0.238856,0.864188},
	{[0]=0.162460,-0.262866,0.951056},
	{[0]=0.309017,-0.500000,0.809017},
	{[0]=0.147621,-0.716567,0.681718},
	{[0]=0.000000,-0.525731,0.850651},
	{[0]=0.425325,-0.688191,0.587785},
	{[0]=0.587785,-0.425325,0.688191},
	{[0]=0.688191,-0.587785,0.425325},
	{[0]=-0.955423,0.295242,0.000000},
	{[0]=-0.951056,0.162460,0.262866},
	{[0]=-1.000000,0.000000,0.000000},
	{[0]=-0.850651,0.000000,0.525731},
	{[0]=-0.955423,-0.295242,0.000000},
	{[0]=-0.951056,-0.162460,0.262866},
	{[0]=-0.864188,0.442863,-0.238856},
	{[0]=-0.951056,0.162460,-0.262866},
	{[0]=-0.809017,0.309017,-0.500000},
	{[0]=-0.864188,-0.442863,-0.238856},
	{[0]=-0.951056,-0.162460,-0.262866},
	{[0]=-0.809017,-0.309017,-0.500000},
	{[0]=-0.681718,0.147621,-0.716567},
	{[0]=-0.681718,-0.147621,-0.716567},
	{[0]=-0.850651,0.000000,-0.525731},
	{[0]=-0.688191,0.587785,-0.425325},
	{[0]=-0.587785,0.425325,-0.688191},
	{[0]=-0.425325,0.688191,-0.587785},
	{[0]=-0.425325,-0.688191,-0.587785},
	{[0]=-0.587785,-0.425325,-0.688191},
	{[0]=-0.688191,-0.587785,-0.425325}
}
local byted = {}
for i, d in bytedirs do
	byted[i - 1] = { [0] = f(d[0]), f(d[1]), f(d[2]) }
end
Q.bytedirs = byted

function Q.DirToByte(dir): number
	if not dir then
		return 0
	end
	local bestd, best = 0, 0
	for i = 0, NUMVERTEXNORMALS - 1 do
		local d = Q.DotProduct(dir, byted[i])
		if d > bestd then
			bestd = d
			best = i
		end
	end
	return best
end
function Q.ByteToDir(b: number, dir)
	if b < 0 or b >= NUMVERTEXNORMALS then
		Q.VectorCopy(Q.vec3_origin, dir)
		return
	end
	Q.VectorCopy(byted[b], dir)
end

-- trap_SnapVector (engine side): round each component to the nearest integer.
function Q.SnapVectorRint(v)
	v[0] = rint(v[0])
	v[1] = rint(v[1])
	v[2] = rint(v[2])
end
-- #define SnapVector(v): truncate each component (the gamecode macro)
function Q.SnapVector(v)
	v[0] = trunc(v[0])
	v[1] = trunc(v[1])
	v[2] = trunc(v[2])
end

return Q
