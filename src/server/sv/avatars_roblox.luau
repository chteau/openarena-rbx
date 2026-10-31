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
-- authoritative. A bot wearing an account (botroster.luau, friendbots.luau)
-- gets that account's avatar the same way; other bots keep their OA model.
--
-- Always on: g_robloxAvatars, which could turn them off, is gone, and an
-- old saved value of it is ignored.
--
-- Head icons: the folder's User<clientNum>
-- attribute is the account each client wears (a string: ids outgrow
-- float attributes in some runtimes), and BotRoster lists the
-- roster bots' accounts ("grunt=1274097373 liz=..."), so the client can
-- draw the account's headshot in place of an OA icon.
--
-- Bot roster: the accounts' names are fetched once (retried every 30 s
-- while the service fails); when they arrive and whenever a human joins or
-- leaves, the roster bots are rechecked (a human on a bot's account sends
-- that bot back to its OA identity while they are here).
--
-- Friend-bots: each human's friend list is fetched once when they join and
-- dropped when they leave. The friend the next added bot would wear is
-- published on the folder (attributes NextFriendBot, NextFriendBotred,
-- NextFriendBotblue) for the add bot menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local BotRoster = require("./botroster")
local FriendBots = require("./friendbots")

local Avatars = {}

local wanted: { [number]: number } = {} -- UserId by clientNum
local built: { [number]: Model } = {} -- by UserId: the copy every map change clones again
local rosterDirty = false

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

local function place(clientNum: number, userId: number, model: Model)
	local copy = model:Clone()
	copy.Name = "c" .. clientNum
	copy:SetAttribute("UserId", userId)
	copy:SetAttribute("ClientNum", clientNum)
	remove(clientNum)
	copy.Parent = folder()
end

local function build(clientNum: number, userId: number)
	local model = built[userId]
	if model then
		place(clientNum, userId, model)
		return
	end
	task.spawn(function()
		local ok, res = pcall(function()
			local desc = Players:GetHumanoidDescriptionFromUserId(userId)
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		if not ok or res == nil then
			-- a test player (negative id), or the avatar service failing: the
			-- player keeps an OA model
			warn("OpenArena: no Roblox avatar for client " .. clientNum .. ": " .. tostring(res))
			return
		end
		local m = res :: Model
		for _, d in m:GetDescendants() do
			if d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		built[userId] = m
		if wanted[clientNum] == userId then
			place(clientNum, userId, m)
		end
	end)
end

function Avatars.Set(clientNum: number, userId: number)
	wanted[clientNum] = userId
	folder():SetAttribute("User" .. clientNum, tostring(userId))
	build(clientNum, userId)
end

function Avatars.Clear(clientNum: number)
	local userId = wanted[clientNum]
	wanted[clientNum] = nil
	folder():SetAttribute("User" .. clientNum, nil)
	remove(clientNum)
	-- a friend-bot's friend isn't in the server: forget their model
	if userId and Players:GetPlayerByUserId(userId) == nil then
		built[userId] = nil
	end
end

local function joined(player: Player)
	if player.UserId <= 0 then
		return -- a test player has no friends to fetch
	end
	FriendBots.SetHuman(player.UserId, true)
	rosterDirty = true
	task.spawn(function()
		FriendBots.SetFriends(player.UserId, FriendBots.Fetch(Players, player.UserId))
	end)
end

function Avatars.Start(Game: any)
	local since = math.huge
	local function preview()
		local on = Game.Cvar.VariableIntegerValue("g_friendBots") ~= 0
		for _, side in { "", "red", "blue" } do
			folder():SetAttribute("NextFriendBot" .. side, if on then Game.SV.FriendBotNext(side) else nil)
		end
		local roster = Game.Cvar.VariableIntegerValue("g_botRoster") ~= 0
		folder():SetAttribute("BotRoster", if roster then BotRoster.Accounts() else nil)
	end
	FriendBots.onWear = function(clientNum: number, friend)
		if friend then
			Avatars.Set(clientNum, friend.id)
		else
			Avatars.Clear(clientNum)
		end
	end
	task.spawn(function()
		while not BotRoster.Fetch(UserService) do
			task.wait(30)
		end
		rosterDirty = true
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since >= 1 then
			since = 0
			preview()
			if rosterDirty then
				rosterDirty = false
				Game.SV.BotRosterRefresh()
			end
		end
	end)
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		built[player.UserId] = nil
		FriendBots.SetHuman(player.UserId, false)
		rosterDirty = true
	end)
end

return Avatars
