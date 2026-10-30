--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Not a port: the settings of multiplayer on Roblox servers
-- (docs/ARCHITECTURE.md, "Multiplayer on Roblox servers").
--
-- `public` is the dedicated-style server config of the servers Roblox
-- matchmaking puts players in when they join the experience: a FFA / TDM /
-- CTF rotation through q3's `nextmap` cvar (d1 -> d2 -> ... -> d1), with
-- bot_minplayers filling the arena. Maps the place doesn't carry are
-- skipped.
return {
	public = {
		hostname = "OpenArena",
		maxclients = 12,
		bot_minplayers = 4,
		botskill = 3, -- g_spSkill, the skill bot_minplayers' bots get
		rotation = {
			{ gametype = 0, map = "oa_dm1", fraglimit = 20, timelimit = 10 },
			{ gametype = 3, map = "oa_dm4", fraglimit = 50, timelimit = 15 },
			{ gametype = 4, map = "oa_ctf2", capturelimit = 8, timelimit = 20 },
			{ gametype = 0, map = "oa_dm2", fraglimit = 20, timelimit = 10 },
			{ gametype = 3, map = "oa_dm7", fraglimit = 50, timelimit = 15 },
			{ gametype = 4, map = "ctf_gate1", capturelimit = 8, timelimit = 20 },
			{ gametype = 0, map = "oa_dm5", fraglimit = 20, timelimit = 10 },
			{ gametype = 4, map = "oa_bases7", capturelimit = 8, timelimit = 20 },
		},
	},

	-- the registry: a MemoryStore SortedMap, key = join code
	registry = {
		map = "OAServers",
		heartbeat = 10, -- s between a server's writes
		expiry = 30, -- s an entry outlives its last heartbeat
		listCache = 5, -- s a server reuses its last listing for every player
		listPages = 2, -- GetRangeAsync pages of 200 per listing at most
		backoffMax = 60, -- s, doubling from 2 after each failed call
	},
	-- Start Server / single player settings and access code, key = the
	-- reserved server's join code: read by the server on every start (which
	-- renews them), and how `connect <code>` restarts an empty private server
	reserved = { map = "OAReserved", expiry = 3600, arrivalWait = 30 },
	-- Favorites: one DataStore key per user, written at most every
	-- `minInterval` s and only while the write budget is above `minBudget`
	favorites = { store = "OAFavorites", max = 16, minInterval = 30, minBudget = 10 },
}
