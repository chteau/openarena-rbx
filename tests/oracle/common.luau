-- Helpers shared by the oracle replays: float <-> IEEE hex, map loading.
local fs = require("@lune/fs")
local Collision = require("../../src/shared/Collision")
local BSP = require("../../src/shared/cm/bsp")
local Blob = require("../../src/shared/cm/blob")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

local M = {}
local b = buffer.create(4)

function M.hf(h: string): number
	buffer.writeu32(b, 0, tonumber(h, 16) :: number)
	return buffer.readf32(b, 0)
end

function M.fh(x: number): string
	buffer.writef32(b, 0, x)
	return string.format("%08x", buffer.readu32(b, 0))
end

-- ULP distance between two float32 values (0 = identical bits)
function M.ulps(a: number, c: number): number
	buffer.writef32(b, 0, a)
	local ia = buffer.readi32(b, 0)
	buffer.writef32(b, 0, c)
	local ic = buffer.readi32(b, 0)
	if ia < 0 then
		ia = -2147483648 - ia
	end
	if ic < 0 then
		ic = -2147483648 - ic
	end
	return math.abs(ia - ic)
end

-- a converted map directory (build/maps/<map>/, oaconv's output): join the
-- chunk modules of a blob the way the place does
function M.readBlob(dir: string, name: string): buffer
	local info = luau.load(fs.readFile(dir .. "/luau/" .. name .. ".luau"))()
	local chunks = {}
	for i, c in info.chunks do
		chunks[i] = luau.load(fs.readFile(dir .. "/luau/" .. c .. ".luau"))()
	end
	local b = Blob.join(chunks)
	assert(buffer.len(b) == info.size, "blob size mismatch")
	return b
end

-- the lumps of <map>.bsp, or of a converted map directory through the blob adapter
function M.lumps(path: string)
	if fs.isDir(path) then
		local entities = serde.decode("json", buffer.tostring(M.readBlob(path, "Entities")))
		return Blob.lumps(M.readBlob(path, "Collision"), entities)
	end
	return BSP.parse(buffer.fromstring(fs.readFile(path)))
end

function M.loadMap(path: string)
	local name = string.match(path, "([^/]+)%.bsp$") or string.match(path, "([^/]+)/?$") or path
	Collision.LoadMap(name, M.lumps(path))
end

function M.words(line: string)
	local t = {}
	for w in string.gmatch(line, "%S+") do
		table.insert(t, w)
	end
	return t
end

return M
