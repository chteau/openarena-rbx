-- LocalScript (StarterPlayerScripts): starts the OpenArena client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local oa = ReplicatedStorage:WaitForChild("OA")
require(oa:WaitForChild("client"):WaitForChild("sys"):WaitForChild("Client")).Start()
