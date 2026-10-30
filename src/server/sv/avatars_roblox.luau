--!strict
--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Not a port: every connected player's Roblox avatar, for clients to draw
-- in place of an OA model (docs/client-notes.md, "Roblox avatars"). Built
-- from the player's HumanoidDescription as an R15 model, whatever rig they
-- use on Roblox (accessories, clothing, body colours, face and bundle
-- parts come with the description), and put in ReplicatedStorage.OAAvatars
-- as "c<clientNum>" with a UserId attribute. The models are never
-- characters: nothing simulates them, the game's own pmove and bbox stay
-- authoritative. Bots have no avatar and keep their OA model.
--
-- g_robloxAvatars (serverinfo, default 1): 0 removes them all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Avatars = {}

local wanted: { [number]: Player } = {}
local built: { [number]: Model } = {} -- by UserId: the copy every map change clones again
local enabled = false

local function folder(): Folder
	local f = ReplicatedStorage:FindFirstChild("OAAvatars")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "OAAvatars"
		nf.Parent = ReplicatedStorage
		f = nf
	end
	return f :: Folder
end

local function remove(clientNum: number)
	local old = folder():FindFirstChild("c" .. clientNum)
	if old then
		old:Destroy()
	end
end

local function place(clientNum: number, player: Player, model: Model)
	local copy = model:Clone()
	copy.Name = "c" .. clientNum
	copy:SetAttribute("UserId", player.UserId)
	copy:SetAttribute("ClientNum", clientNum)
	remove(clientNum)
	copy.Parent = folder()
end

local function build(clientNum: number, player: Player)
	local model = built[player.UserId]
	if model then
		place(clientNum, player, model)
		return
	end
	task.spawn(function()
		local ok, res = pcall(function()
			local desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		if not ok or res == nil then
			-- a test player (negative id), or the avatar service failing: the
			-- player keeps an OA model
			warn("OpenArena: no Roblox avatar for " .. player.Name .. ": " .. tostring(res))
			return
		end
		local m = res :: Model
		for _, d in m:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		built[player.UserId] = m
		if enabled and wanted[clientNum] == player then
			place(clientNum, player, m)
		end
	end)
end

function Avatars.Set(clientNum: number, player: Player)
	wanted[clientNum] = player
	if enabled then
		build(clientNum, player)
	end
end

function Avatars.Clear(clientNum: number)
	wanted[clientNum] = nil
	remove(clientNum)
end

function Avatars.Start(Game: any)
	Game.Cvar.Get("g_robloxAvatars", "1", bit32.bor(Game.C.CVAR_SERVERINFO, Game.C.CVAR_ARCHIVE))
	local since = math.huge
	local function update()
		local on = Game.Cvar.VariableIntegerValue("g_robloxAvatars") ~= 0
		if on == enabled then
			return
		end
		enabled = on
		if on then
			for n, player in wanted do
				build(n, player)
			end
		else
			folder():ClearAllChildren()
		end
	end
	update()
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since >= 1 then
			since = 0
			update()
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		built[player.UserId] = nil
	end)
end

return Avatars
