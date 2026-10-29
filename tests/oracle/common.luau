-- Helpers shared by the oracle replays: float <-> IEEE hex, map loading.
local fs = require("@lune/fs")
local Collision = require("../../src/shared/Collision")
local BSP = require("../../src/shared/cm/bsp")

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

function M.loadMap(path: string)
	local buf = buffer.fromstring(fs.readFile(path))
	local name = string.match(path, "([^/]+)%.bsp$") or path
	Collision.LoadMap(name, BSP.parse(buf))
end

function M.words(line: string)
	local t = {}
	for w in string.gmatch(line, "%S+") do
		table.insert(t, w)
	end
	return t
end

return M
