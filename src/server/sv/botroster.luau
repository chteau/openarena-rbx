--!strict
--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Not a port: the bot roster (docs/bots-notes.md, "Bot roster"). Every OA
-- bot is a fixed Roblox account, the same in every server: it keeps its
-- botfiles character and wears the account's avatar and display name, the
-- way a friend-bot does (friendbots.luau, which also keeps who wears whom).
-- The accounts' names are looked up once per server (avatars_roblox.luau
-- on Roblox, a stub under lune).

local FriendBots = require("./friendbots")

local BotRoster = {}

-- by lower-case bots.txt name
BotRoster.ids = {
	grunt = 828726934,
	liz = 73392736,
	tony = 260342963,
	penguin = 105519417,
	skelebot = 10138699399,
	ghost = 1633902010,
	beret = 374845493,
	broadklin = 66246631,
	morgan = 5746191400,
	assassin = 1318896233,
	["cyber-garg"] = 123757139,
	andriy = 5290932442,
	sergei = 58526171,
	metalbot = 1116532733,
	gargoyle = 10120477760,
	sarge = 10595767136,
	grism = 8950832609,
	s_marine = 925308243,
	jiangshi = 8313172606, -- the Final arena's boss
} :: { [string]: number }

-- the name each account shows (FriendBots.Label), false for an account the
-- lookup didn't return (deleted or banned); empty until Fetch succeeds
local names: { [number]: string | false } = {}

function BotRoster.Reset()
	table.clear(names)
end

-- every account's name in one call (UserService:GetUserInfosByUserIdsAsync);
-- false when the service fails, so the host can try again
function BotRoster.Fetch(userService: any): boolean
	local list = {}
	for _, id in BotRoster.ids do
		table.insert(list, id)
	end
	local ok, res = pcall(function()
		return userService:GetUserInfosByUserIdsAsync(list)
	end)
	if not ok then
		warn("OpenArena: the bot roster's names are unavailable, bots keep OA names: " .. tostring(res))
		return false
	end
	for _, id in list do
		names[id] = false
	end
	for _, info in res do
		names[info.Id] = FriendBots.Label(info.DisplayName, info.Username)
	end
	return true
end

function BotRoster.Listed(oabot: string): boolean
	return BotRoster.ids[string.lower(oabot)] ~= nil
end

-- the account a roster bot wears now: nil while its name is unknown or its
-- account is in the server as a human
function BotRoster.Account(oabot: string): FriendBots.Friend?
	local id = BotRoster.ids[string.lower(oabot)]
	local name = id and names[id]
	if not name or FriendBots.Here(id) then
		return nil
	end
	return { id = id, name = name }
end

return BotRoster
