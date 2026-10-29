-- LocalScript (StarterPlayerScripts): starts the OpenArena client and wires
-- the hooks the place supplies (docs/client-notes.md, "Integration points"):
-- the current map's collision and light grid, which the server's boot script
-- copies into ReplicatedStorage.OAMap.<map> on every map load, and the
-- network transport over ReplicatedStorage.OANet.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local oa = ReplicatedStorage:WaitForChild("OA")
local client = oa:WaitForChild("client")
local sys = client:WaitForChild("sys")
local Client = require(sys.Client)
local CM = require(client.adapters.CM)
local LightGrid = require(sys.LightGrid)
local WorldFx = require(sys.WorldFx)
local Transport = require(sys.Transport)
local Blob = require(oa.shared.cm.blob)

-- a blob's index module and its chunk siblings (docs/formats/luau-blobs.md)
local function join(index: ModuleScript): buffer
	local info = require(index)
	local parts = {}
	for i, name in info.chunks do
		parts[i] = require(index.Parent[name])
	end
	local b = Blob.join(parts)
	assert(buffer.len(b) == info.size, "blob size mismatch: " .. index:GetFullName())
	return b
end

-- cgame names the map as its BSP path ("maps/oa_dm1.bsp")
local function mapData(name: string): Instance?
	local maps = ReplicatedStorage:FindFirstChild("OAMap")
	local key = string.lower(name):gsub("^maps/", ""):gsub("%.bsp$", "")
	return maps and maps:FindFirstChild(key)
end

CM.loadLumps = function(name: string)
	local m = mapData(name)
	if m == nil then
		warn("OpenArena: no collision data for " .. name)
		return nil
	end
	local entities = HttpService:JSONDecode(buffer.tostring(join(m.Entities)))
	return Blob.lumps(join(m.Collision), entities)
end

LightGrid.loadGrid = function(name: string)
	local m = mapData(name)
	local info = m and m:GetAttribute("LightGrid")
	if m == nil or info == nil or m:FindFirstChild("LightGrid") == nil then
		return nil, nil
	end
	return HttpService:JSONDecode(info), join(m.LightGrid)
end

WorldFx.mapRoot = workspace:WaitForChild("Map")
Transport.onGamestate = Client.RestartCGame
Transport.Start()
Client.Start()
