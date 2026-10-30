--!strict
--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Not a port: friend-bots (docs/bots-notes.md, "Friend-bots"). A bot can
-- wear the avatar and display name of a Roblox friend of a human player in
-- this server. This module only keeps who is here, their friend lists and
-- which bot wears whom; the host feeds it (avatars_roblox.luau on Roblox,
-- the tests under lune) and the game asks through G.trap_FriendBot*.
-- Nothing is stored beyond the server's life, and a player's list goes
-- with them when they leave.

export type Friend = { id: number, name: string }

local FriendBots = {}

local humans: { number } = {} -- UserIds of the humans in the server, in join order
local lists: { [number]: { Friend } } = {} -- by human UserId
local worn: { [number]: Friend } = {} -- by bot clientNum

-- host hook: a bot started (friend) or stopped (nil) wearing a friend
FriendBots.onWear = nil :: ((clientNum: number, friend: Friend?) -> ())?

function FriendBots.Reset()
	table.clear(humans)
	table.clear(lists)
	table.clear(worn)
end

function FriendBots.SetHuman(userId: number, here: boolean)
	local i = table.find(humans, userId)
	if here and i == nil then
		table.insert(humans, userId)
	elseif not here and i ~= nil then
		table.remove(humans, i)
		lists[userId] = nil
	end
end

function FriendBots.SetFriends(userId: number, list: { Friend })
	if table.find(humans, userId) then
		lists[userId] = list
	end
end

-- the name a friend-bot shows (before the game adds its tag): the display
-- name when OA's font and info strings can carry it, else the username,
-- which Roblox keeps to letters, digits and underscores
function FriendBots.Label(display: string?, username: string?): string
	if display and display ~= "" and #display <= 21 and not string.find(display, '[^\32-\126]') and not string.find(display, '[\\;"%^%%]') then
		return display
	end
	return string.sub(username or "Friend", 1, 21)
end

-- a player's whole friend list (GetFriendsAsync, page by page); empty when
-- the list is private or the service fails
function FriendBots.Fetch(players: any, userId: number): { Friend }
	local list: { Friend } = {}
	local ok, err = pcall(function()
		local pages = players:GetFriendsAsync(userId)
		while true do
			for _, item in pages:GetCurrentPage() do
				table.insert(list, { id = item.Id, name = FriendBots.Label(item.DisplayName, item.Username) })
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		warn("OpenArena: a friend list is unavailable, its bots keep OA models: " .. tostring(err))
	end
	return list
end

local function free(id: number): boolean
	if table.find(humans, id) then
		return false
	end
	for _, f in worn do
		if f.id == id then
			return false
		end
	end
	return true
end

-- the next friend a bot would wear: friends of the humans in `prefer` (the
-- bot's team) first, then of everyone, in join and list order
function FriendBots.Peek(prefer: { number }?): Friend?
	local order = {}
	for _, u in prefer or {} do
		if table.find(humans, u) and not table.find(order, u) then
			table.insert(order, u)
		end
	end
	for _, u in humans do
		if not table.find(order, u) then
			table.insert(order, u)
		end
	end
	for _, u in order do
		for _, f in lists[u] or {} do
			if free(f.id) then
				return f
			end
		end
	end
	return nil
end

function FriendBots.Release(clientNum: number)
	if worn[clientNum] then
		worn[clientNum] = nil
		if FriendBots.onWear then
			FriendBots.onWear(clientNum, nil)
		end
	end
end

function FriendBots.Pick(clientNum: number, prefer: { number }?): Friend?
	FriendBots.Release(clientNum)
	local f = FriendBots.Peek(prefer)
	if f then
		worn[clientNum] = f
		if FriendBots.onWear then
			FriendBots.onWear(clientNum, f)
		end
	end
	return f
end

function FriendBots.Worn(clientNum: number): Friend?
	return worn[clientNum]
end

-- still a friend of someone here, and not here as a human
function FriendBots.Valid(clientNum: number): boolean
	local f = worn[clientNum]
	if f == nil or table.find(humans, f.id) then
		return false
	end
	for _, u in humans do
		for _, g in lists[u] or {} do
			if g.id == f.id then
				return true
			end
		end
	end
	return false
end

return FriendBots
