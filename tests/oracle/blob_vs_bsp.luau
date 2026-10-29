-- Loads a map twice, from its .bsp and from the converter's blobs
-- (build/maps/<map>/luau/Collision*, Entities*, through cm/blob.luau), and
-- diffs the resulting clip maps field by field and the entity strings
-- key by key.
--   lune run tests/oracle/blob_vs_bsp.luau <map.bsp> <converted map dir>
-- The trace / pmove replays also take the converted directory in place of
-- the .bsp, to check the blob path against the C oracle's logs directly.
local process = require("@lune/process")
local Cm = require("./common")
local Collision = require("../../src/shared/Collision")

local bspPath, dir = process.args[1], process.args[2]
local lumpsA, lumpsB = Cm.lumps(bspPath), Cm.lumps(dir)
Collision.LoadMap("bsp", lumpsA)
local A = Collision.state.cm
Collision.LoadMap("blob", lumpsB)
local B = Collision.state.cm

local diffs = 0
local function report(...)
	diffs += 1
	if diffs <= 10 then
		print(...)
	end
end

-- facets keep 26 border slots in the blob; only the used ones count
local function cmp(path: string, a, b, used: number?)
	if type(a) == "table" and type(b) == "table" then
		if a.numBorders ~= nil then
			for k, v in a do
				if k ~= "borderPlanes" and k ~= "borderInward" and k ~= "borderNoAdjust" then
					cmp(path .. "." .. k, v, b[k])
				end
			end
			for _, k in { "borderPlanes", "borderInward", "borderNoAdjust" } do
				for i = 0, a.numBorders - 1 do
					cmp(path .. "." .. k .. "." .. i, a[k][i], b[k][i])
				end
			end
			return
		end
		for k, v in a do
			cmp(path .. "." .. tostring(k), v, b[k])
		end
		for k in b do
			if a[k] == nil then
				report("only in blob:", path .. "." .. tostring(k))
			end
		end
	elseif type(a) == "buffer" and type(b) == "buffer" then
		if buffer.tostring(a) ~= buffer.tostring(b) then
			report(path, "buffers differ")
		end
	elseif a ~= b then
		report(path, a, b)
	end
end

for _, k in {
	"numShaders", "planes", "nodes", "leafs", "leafbrushes", "leafsurfaces", "brushsides", "brushes", "cmodels",
	"numClusters", "clusterBytes", "visibility", "numAreas", "areas", "areaPortals", "numSurfaces", "surfaces",
} do
	cmp(k, A[k], B[k])
end
print(string.format("clip map: %d difference(s)", diffs))

-- entities: same entities, same values for every key (G_SpawnString takes
-- the first of duplicate keys, so the first is kept here)
local function parse(s: string)
	local out = {}
	for body in string.gmatch(s, "%b{}") do
		local e = {}
		for k, v in string.gmatch(body, '"([^"]*)"%s+"([^"]*)"') do
			if e[k] == nil then
				e[k] = v
			end
		end
		table.insert(out, e)
	end
	return out
end
local ea, eb = parse(lumpsA.entities), parse(lumpsB.entities)
local entDiffs = if #ea == #eb then 0 else 1
for i = 1, math.min(#ea, #eb) do
	for k, v in ea[i] do
		if eb[i][k] ~= v then
			entDiffs += 1
		end
	end
	for k in eb[i] do
		if ea[i][k] == nil then
			entDiffs += 1
		end
	end
end
print(string.format("entities: %d in the BSP, %d from the JSON, %d difference(s)", #ea, #eb, entDiffs))
process.exit(if diffs + entDiffs == 0 then 0 else 1)
