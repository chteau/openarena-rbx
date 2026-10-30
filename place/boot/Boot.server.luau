-- Script (ServerScriptService.OA.Boot): starts the OpenArena server.
-- The place carries, from place/assemble.py:
--   ServerScriptService.OA.{server, shared}   the game, engine and bots
--   ServerStorage.OAMaps.<map>                attributes Checksum, LightGrid;
--       Data: Collision/Entities/LightGrid/Aas blob modules; Meshes: the
--       map's MeshParts
--   ServerStorage.OABotfiles                   the botfiles blob
--   ReplicatedStorage.OA.client.sys.Files      the text files of the pk3s
-- On every map load the current map's client half (collision, entities,
-- light grid and meshes) is copied to ReplicatedStorage.OAMap.<map> and
-- Workspace.Map, where the client's boot script finds it.
-- The console text in this script's `Startup` attribute runs once at start
-- on a public or Studio server; a reserved server (Start Server, single
-- player) starts with its creator's settings instead (sv/servers_roblox.luau).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local root = script.Parent
local Game = require(root.server.Game)
local Transport = require(root.server.sv.transport_roblox)
local Blob = require(root.shared.cm.blob)
local Servers = require(root.server.sv.servers_roblox)

Players.CharacterAutoLoads = false

local maps = ServerStorage:WaitForChild("OAMaps")

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

-- the client half of a map
local CLIENT_BLOBS = { Collision = true, Entities = true, LightGrid = true }
local function publish(m: Instance)
	local old = ReplicatedStorage:FindFirstChild("OAMap")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "OAMap"
	local cur = Instance.new("Folder")
	cur.Name = m.Name
	cur:SetAttribute("LightGrid", m:GetAttribute("LightGrid"))
	for _, child in m.Data:GetChildren() do
		local blob = string.match(child.Name, "^(%a+)")
		if blob and CLIENT_BLOBS[blob] then
			child:Clone().Parent = cur
		end
	end
	cur.Parent = folder
	folder.Parent = ReplicatedStorage

	local world = workspace:FindFirstChild("Map")
	if world == nil then
		world = Instance.new("Folder")
		world.Name = "Map"
		world.Parent = workspace
	end
	world:ClearAllChildren()
	world:SetAttribute("OAMap", m.Name)
	for _, child in m.Meshes:GetChildren() do
		child:Clone().Parent = world
	end
end

local function loadMap(name: string)
	local m = maps:FindFirstChild(string.lower(name))
	if m == nil then
		error("OpenArena: the place has no map " .. name)
	end
	local entities = HttpService:JSONDecode(buffer.tostring(join(m.Data.Entities)))
	local lumps = Blob.lumps(join(m.Data.Collision), entities)
	lumps.checksum = m:GetAttribute("Checksum")
	if m.Data:FindFirstChild("Aas") then
		lumps.aas = join(m.Data.Aas)
	end
	publish(m)
	return lumps
end

local names = {}
for _, m in maps:GetChildren() do
	table.insert(names, m.Name)
end
table.sort(names)

local files = require(ReplicatedStorage.OA.client.sys.Files).files
local botfiles = ServerStorage:FindFirstChild("OABotfiles")

Game.Init({
	loadMap = loadMap,
	mapExists = function(name: string)
		return maps:FindFirstChild(string.lower(name)) ~= nil
	end,
	maps = names,
	files = files,
	botfiles = if botfiles then join(botfiles.Botfiles) else nil,
	milliseconds = function()
		return math.floor(os.clock() * 1000)
	end,
})
local function mapExists(name: string): boolean
	return maps:FindFirstChild(string.lower(name)) ~= nil
end
local servers = Servers.new(Servers.fromGame(), Game, mapExists)
local startup = script:GetAttribute("Startup")
Game.Command(servers:Boot({ maps = names, startup = if type(startup) == "string" then startup else nil }))
Transport.Start(Game)
servers:Start(ReplicatedStorage:WaitForChild("OANet"))
