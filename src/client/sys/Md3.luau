-- MD3 models: parses the id Software MD3 format (qfiles.h) from a buffer
-- and answers tag/bounds queries (R_LerpTag). Vertex animation for display
-- is in R3D (EditableMesh). The model data comes from the asset index:
--   index.models[name] = { md3 = buffer }        raw MD3 bytes, or
--   index.models[name] = { md3b64 = string }     the same, base64
-- (the converter's buffers, see docs/formats/md3.md, are adapted here).
local Md3 = {}

local MD3_XYZ_SCALE = 1.0 / 64

local function cstr(b: buffer, at: number, len: number): string
	local s = buffer.readstring(b, at, len)
	local z = s:find("\0", 1, true)
	return string.lower(if z then s:sub(1, z - 1) else s)
end

local function vec(b: buffer, at: number)
	return { [0] = buffer.readf32(b, at), [1] = buffer.readf32(b, at + 4), [2] = buffer.readf32(b, at + 8) }
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64INV = {}
for i = 1, 64 do
	B64INV[string.byte(B64, i)] = i - 1
end

function Md3.decodeBase64(s: string): buffer
	s = s:gsub("[^%w%+/=]", "")
	local n = #s
	local pad = if s:sub(-2) == "==" then 2 elseif s:sub(-1) == "=" then 1 else 0
	local out = buffer.create(n // 4 * 3 - pad)
	local o = 0
	for i = 1, n, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local v = bit32.lshift(B64INV[a] or 0, 18) + bit32.lshift(B64INV[b] or 0, 12)
			+ bit32.lshift(B64INV[c] or 0, 6) + (B64INV[d] or 0)
		for k = 2, 0, -1 do
			if o < buffer.len(out) then
				buffer.writeu8(out, o, bit32.band(bit32.rshift(v, k * 8), 255))
				o += 1
			end
		end
	end
	return out
end

-- Parses MD3 bytes into the model table used by Assets/R3D.
function Md3.Parse(name: string, b: buffer)
	if buffer.readstring(b, 0, 4) ~= "IDP3" then
		return nil
	end
	local numFrames = buffer.readi32(b, 76)
	local numTags = buffer.readi32(b, 80)
	local numSurfaces = buffer.readi32(b, 84)
	local ofsFrames = buffer.readi32(b, 92)
	local ofsTags = buffer.readi32(b, 96)
	local ofsSurfaces = buffer.readi32(b, 100)
	local m = { name = name, numFrames = numFrames, frames = {}, numTags = numTags, tags = {}, surfaces = {} }
	for f = 0, numFrames - 1 do
		local at = ofsFrames + f * 56
		m.frames[f] = { mins = vec(b, at), maxs = vec(b, at + 12), localOrigin = vec(b, at + 24), radius = buffer.readf32(b, at + 36) }
	end
	for f = 0, numFrames - 1 do
		local frameTags = {}
		for t = 0, numTags - 1 do
			local at = ofsTags + (f * numTags + t) * 112
			frameTags[cstr(b, at, 64)] = {
				origin = vec(b, at + 64),
				axis = { [0] = vec(b, at + 76), [1] = vec(b, at + 88), [2] = vec(b, at + 100) },
			}
		end
		m.tags[f] = frameTags
	end
	local at = ofsSurfaces
	for _ = 1, numSurfaces do
		local s = {
			name = cstr(b, at + 4, 64),
			numFrames = buffer.readi32(b, at + 72),
			numVerts = buffer.readi32(b, at + 80),
			numTriangles = buffer.readi32(b, at + 84),
			shaders = {},
		}
		local numShaders = buffer.readi32(b, at + 76)
		local ofsTriangles = at + buffer.readi32(b, at + 88)
		local ofsShaders = at + buffer.readi32(b, at + 92)
		local ofsSt = at + buffer.readi32(b, at + 96)
		local ofsXyz = at + buffer.readi32(b, at + 100)
		for i = 0, numShaders - 1 do
			table.insert(s.shaders, cstr(b, ofsShaders + i * 68, 64))
		end
		-- triangles: 0-based vertex indices, 3 per triangle
		local tris = buffer.create(s.numTriangles * 12)
		buffer.copy(tris, 0, b, ofsTriangles, s.numTriangles * 12)
		s.triangles = tris
		local st = buffer.create(s.numVerts * 8)
		buffer.copy(st, 0, b, ofsSt, s.numVerts * 8)
		s.st = st
		-- per frame: numVerts * (x, y, z i16 scaled by 1/64, normal u16 lat/lng)
		local xyz = buffer.create(s.numFrames * s.numVerts * 8)
		buffer.copy(xyz, 0, b, ofsXyz, s.numFrames * s.numVerts * 8)
		s.xyz = xyz
		table.insert(m.surfaces, s)
		at += buffer.readi32(b, at + 104)
	end
	return m
end

function Md3.Load(name: string, data)
	if data == nil then
		return nil
	end
	if data.model then
		return data.model
	end
	local b = data.md3 or (data.md3b64 and Md3.decodeBase64(data.md3b64))
	if b == nil then
		return nil
	end
	local m = Md3.Parse(name, b)
	data.model = m
	return m
end

-- Position of vertex v of surface s at frame f, in Quake units.
function Md3.Vertex(s, f: number, v: number): (number, number, number)
	local at = (f * s.numVerts + v) * 8
	local xyz = s.xyz
	return buffer.readi16(xyz, at) * MD3_XYZ_SCALE, buffer.readi16(xyz, at + 2) * MD3_XYZ_SCALE, buffer.readi16(xyz, at + 4) * MD3_XYZ_SCALE
end

function Md3.TexCoord(s, v: number): (number, number)
	return buffer.readf32(s.st, v * 8), buffer.readf32(s.st, v * 8 + 4)
end

function Md3.Triangle(s, t: number): (number, number, number)
	local at = t * 12
	return buffer.readi32(s.triangles, at), buffer.readi32(s.triangles, at + 4), buffer.readi32(s.triangles, at + 8)
end

-- R_LerpTag: fills `tag` (orientation_t) from the named tag between frames.
function Md3.LerpTag(tag, m, startFrame: number, endFrame: number, frac: number, name: string): boolean
	if m.numFrames == 0 or m.numTags == 0 then
		return false
	end
	local function clampFrame(f)
		if f >= m.numFrames then
			return m.numFrames - 1
		elseif f < 0 then
			return 0
		end
		return f
	end
	local a = m.tags[clampFrame(startFrame)][string.lower(name)]
	local b = m.tags[clampFrame(endFrame)][string.lower(name)]
	if a == nil or b == nil then
		return false
	end
	local front, back = frac, 1.0 - frac
	for i = 0, 2 do
		tag.origin[i] = a.origin[i] * back + b.origin[i] * front
		tag.axis[0][i] = a.axis[0][i] * back + b.axis[0][i] * front
		tag.axis[1][i] = a.axis[1][i] * back + b.axis[1][i] * front
		tag.axis[2][i] = a.axis[2][i] * back + b.axis[2][i] * front
	end
	for i = 0, 2 do
		local v = tag.axis[i]
		local len = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
		if len > 0 then
			v[0], v[1], v[2] = v[0] / len, v[1] / len, v[2] / len
		end
	end
	return true
end

return Md3
