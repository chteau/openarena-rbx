-- LocalScript (ReplicatedFirst): a player arriving by teleport keeps the
-- loading screen they left with (or a rebuilt one) until the OA client has
-- its map up (it sets the LocalPlayer's OAReady attribute, sys/Client.luau).
-- Joining without a teleport leaves Roblox's own loading screen alone.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")

-- never stick: a map that doesn't come up lets the player see why
local TIMEOUT = 120

local LoadingScreen = require(script.Parent:WaitForChild("OALoadingScreen"))

local gui = TeleportService:GetArrivingTeleportGui()
local ours, map, shot = LoadingScreen.fromData(TeleportService:GetLocalPlayerTeleportData())
if gui == nil and not ours then
	return
end
if gui == nil then
	gui = LoadingScreen.build(map, shot)
end

local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local done = false
local function finish()
	if not done then
		done = true
		LoadingScreen.dismiss(gui)
	end
end
if player:GetAttribute(LoadingScreen.ready) then
	finish()
else
	player:GetAttributeChangedSignal(LoadingScreen.ready):Connect(function()
		if player:GetAttribute(LoadingScreen.ready) then
			finish()
		end
	end)
	task.delay(TIMEOUT, finish)
end
