-- Com_BlockChecksum (ioquake3 qcommon/md4.c): the MD4 digest's four words
-- xor-ed together, as a signed int. The engine stores it in
-- sv_mapChecksum and botlib refuses an .aas whose header names another BSP.
local band, bor, bxor, bnot, lrot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot, bit32.lrotate

local function md4(msg: buffer): (number, number, number, number)
	local len = buffer.len(msg)
	local padded = (len + 8) // 64 * 64 + 64
	local m = buffer.create(padded)
	buffer.copy(m, 0, msg, 0, len)
	buffer.writeu8(m, len, 0x80)
	buffer.writeu32(m, padded - 8, (len * 8) % 4294967296)
	buffer.writeu32(m, padded - 4, (len * 8) // 4294967296)
	local a, b, c, d = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
	local x = table.create(16, 0)
	local function F(p, q, r) return bor(band(p, q), band(bnot(p), r)) end
	local function Gf(p, q, r) return bor(band(p, q), band(p, r), band(q, r)) end
	local function H(p, q, r) return bxor(p, q, r) end
	for blk = 0, padded - 1, 64 do
		for i = 0, 15 do
			x[i] = buffer.readu32(m, blk + i * 4)
		end
		local aa, bb, cc, dd = a, b, c, d
		local s1 = { 3, 7, 11, 19 }
		for i = 0, 15 do
			local k = i % 4
			local t = (a + F(b, c, d) + x[i]) % 4294967296
			a, b, c, d = d, lrot(t, s1[k + 1]), b, c
		end
		local s2 = { 3, 5, 9, 13 }
		for i = 0, 15 do
			local idx = (i % 4) * 4 + i // 4
			local t = (a + Gf(b, c, d) + x[idx] + 0x5a827999) % 4294967296
			a, b, c, d = d, lrot(t, s2[i % 4 + 1]), b, c
		end
		local s3 = { 3, 9, 11, 15 }
		local order = { 0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15 }
		for i = 0, 15 do
			local t = (a + H(b, c, d) + x[order[i + 1]] + 0x6ed9eba1) % 4294967296
			a, b, c, d = d, lrot(t, s3[i % 4 + 1]), b, c
		end
		a, b, c, d = (a + aa) % 4294967296, (b + bb) % 4294967296, (c + cc) % 4294967296, (d + dd) % 4294967296
	end
	return a, b, c, d
end

return function(data: buffer): number
	local a, b, c, d = md4(data)
	local v = bxor(a, b, c, d)
	return if v >= 0x80000000 then v - 0x100000000 else v
end
