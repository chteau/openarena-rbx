-- Friend-bots (lune run tests/bots/friendbots.luau): the friend list fetch
-- against a stubbed Players service, the assignment rules, then a running
-- server with AAS: friend-bots get a friend's tagged name on every name the
-- server sends or prints, fall back to their OA name, stay quiet with
-- bot_friendChat 0, answer to kick by either name, give up a friend whose
-- player left at the map change, and with g_friendBots 0 nothing changes.
local Host = require("./simhost")
local QS = require("../../src/shared/q_shared")
local FB = require("../../src/server/sv/friendbots")
local C = require("../../src/server/g_defs")

local failures = 0
local function check(ok: boolean, what: string)
	if not ok then
		failures += 1
		print("FAIL: " .. what)
	end
end

-- a FriendPages stand-in: `pages` lists of { Id, Username, DisplayName }
local function stubPlayers(pages: { { any } }?, err: string?)
	return {
		GetFriendsAsync = function(_, userId: number)
			if err then
				error(err)
			end
			local i = 1
			local p = {}
			function p.GetCurrentPage()
				return (pages :: any)[i]
			end
			function p.AdvanceToNextPageAsync()
				i += 1
				p.IsFinished = i == #(pages :: any)
			end
			p.IsFinished = #(pages :: any) == 1
			return p
		end,
	}
end

-- fetch: every page, display names when OA can show them
do
	local list = FB.Fetch(stubPlayers({
		{ { Id = 11, Username = "alice_1", DisplayName = "Alice" }, { Id = 12, Username = "bob_2", DisplayName = "B\u{f6}b" } },
		{ { Id = 13, Username = "cara_3", DisplayName = "Ca^1ra" }, { Id = 14, Username = "dan_4", DisplayName = "Dan" } },
		{ { Id = 15, Username = "eve_5", DisplayName = "" } },
	}), 1)
	local names = {}
	for _, f in list do
		table.insert(names, f.id .. "=" .. f.name)
	end
	check(table.concat(names, ",") == "11=Alice,12=bob_2,13=cara_3,14=Dan,15=eve_5", "fetch: " .. table.concat(names, ","))
	check(#FB.Fetch(stubPlayers(nil, "HTTP 403 (private)"), 1) == 0, "a private list is empty")
end

-- assignment: no duplicates, never a human who is here, team side first,
-- nothing left = nil, a leaver's friends invalid
do
	FB.Reset()
	FB.SetHuman(1, true)
	FB.SetHuman(2, true)
	FB.SetFriends(1, { { id = 2, name = "Two" }, { id = 10, name = "Ten" }, { id = 20, name = "Twenty" } })
	FB.SetFriends(2, { { id = 20, name = "Twenty" }, { id = 30, name = "Thirty" } })
	FB.SetFriends(99, { { id = 40, name = "Forty" } }) -- not here: ignored
	check(FB.Peek({ 2 }).name == "Twenty", "team side first")
	local got = {}
	for n = 5, 9 do
		local f = FB.Pick(n)
		table.insert(got, if f then f.name else "-")
	end
	check(table.concat(got, ",") == "Ten,Twenty,Thirty,-,-", "pick order: " .. table.concat(got, ","))
	check(FB.Valid(5) and FB.Valid(7), "worn friends valid")
	FB.Release(6)
	check(FB.Pick(8).name == "Twenty", "a released friend is free again")
	FB.SetHuman(30, true) -- Thirty joins as a human
	check(not FB.Valid(7), "a friend who joined as a human is invalid")
	FB.SetHuman(1, false)
	check(not FB.Valid(5) and FB.Valid(8), "only the leaver's friends are invalid")
	FB.Reset()
end

-- the running server
local FRAME_MS = 50
local log = {}
local h = Host.new({ maps = { "oa_dm1" }, quiet = true, log = log })
local G, SV = h.G, h.SV
local logged = {}
local logPrintf = G.G_LogPrintf
G.G_LogPrintf = function(fmt, ...)
	table.insert(logged, QS.va(fmt, ...))
	logPrintf(fmt, ...)
end
local sent = {}
local send = G.trap_SendServerCommand
G.trap_SendServerCommand = function(n, text)
	table.insert(sent, text)
	send(n, text)
end
local trapCalls = 0
local friendBot = G.trap_FriendBot
G.trap_FriendBot = function(...)
	trapCalls += 1
	return friendBot(...)
end
local wearing = {}
FB.onWear = function(n, f)
	wearing[n] = f and f.id
end

local function frames(n: number)
	for _ = 1, n do
		h.frame(FRAME_MS)
	end
end
local function bots(): { [string]: number }
	local out = {}
	for i = 0, G.level.maxclients - 1 do
		local cs = G.trap_GetConfigstring(C.CS_PLAYERS + i)
		if cs ~= "" and QS.Info_ValueForKey(cs, "skill") ~= "" then
			out[QS.Info_ValueForKey(cs, "n")] = i
		end
	end
	return out
end
local function names(): string
	local list = {}
	for n in bots() do
		table.insert(list, n)
	end
	table.sort(list)
	return table.concat(list, ",")
end
local function has(list: { string }, pat: string): boolean
	for _, s in list do
		if string.find(s, pat, 1, true) then
			return true
		end
	end
	return false
end

h.Game.Command("bot_enable 1")
h.Game.Command("map oa_dm1")
frames(10)

FB.SetHuman(1001, true)
FB.SetHuman(1002, true)
FB.SetFriends(1001, { { id = 1002, name = "Human" }, { id = 2001, name = "Alice" }, { id = 2002, name = "Bob" } })
for _, b in { "sarge", "grism", "assassin" } do
	h.Game.Command("addbot " .. b)
end
frames(10)

local TAG = "^3[BOT]^7 "
local B = bots()
check(names() == "Assassin," .. TAG .. "Alice," .. TAG .. "Bob", "bot names: " .. names())
local alice, bob = B[TAG .. "Alice"], B[TAG .. "Bob"]
check(alice ~= nil and wearing[alice] == 2001 and wearing[bob] == 2002 and wearing[B.Assassin] == nil, "avatars worn")
check(QS.Info_ValueForKey(G.trap_GetUserinfo(alice), "oabot") == "Sarge", "OA name kept")
check(QS.Info_ValueForKey(G.trap_GetUserinfo(alice), "characterfile") == "bots/sarge_c.c", "character kept")
check(SV.svs.clients[alice].name == TAG .. "Alice", "server client name")
-- the console and the log
check(has(logged, "ClientUserinfoChanged: " .. alice .. " n\\" .. TAG .. "Alice\\"), "log: userinfo")
check(has(sent, TAG .. "Alice^7 entered the game"), "broadcast: entered the game")

-- kill feed / obituary log line: Alice frags Bob
local abot, bbot = G.g_entities[alice], G.g_entities[bob]
G.G_Damage(bbot, abot, abot, nil, nil, 1000, C.DAMAGE_NO_PROTECTION, C.MOD_RAILGUN)
frames(2)
check(has(logged, ": " .. TAG .. "Alice killed " .. TAG .. "Bob by "), "log: kill line")

-- chat: the tag on the line, and the friend chat setting
G.G_Say(abot, nil, C.SAY_ALL, "hello")
check(has(sent, 'chat "' .. TAG .. "Alice^7: ") or has(sent, TAG .. "Alice^7\x19: "), "chat line tagged")
check(G.BotNoChat({ client = alice }) and not G.BotNoChat({ client = B.Assassin }), "bot_friendChat 0: only the friend-bot is quiet")
h.Game.Command("bot_friendChat 1")
frames(1)
check(not G.BotNoChat({ client = alice }), "bot_friendChat 1: friend-bots chat")
h.Game.Command("bot_nochat 1")
frames(1)
check(G.BotNoChat({ client = B.Assassin }), "bot_nochat still applies")
h.Game.Command("bot_nochat 0")
h.Game.Command("bot_friendChat 0")

-- kick by the OA name, then by the shown name
h.Game.Command("kick Sarge")
frames(5)
check(bots()[TAG .. "Alice"] == nil and FB.Worn(alice) == nil and wearing[alice] == nil, "kick by OA name releases the friend")
h.Game.Command('kick "[BOT] Bob"')
frames(5)
check(bots()[TAG .. "Bob"] == nil, "kick by shown name")

-- map change: Bob's player leaves, another human brings Cara
h.Game.Command("addbot sarge")
h.Game.Command("addbot grism")
frames(10)
check(names() == "Assassin," .. TAG .. "Alice," .. TAG .. "Bob", "re-added: " .. names())
FB.SetHuman(1003, true)
FB.SetFriends(1003, { { id = 2003, name = "Cara" } })
FB.SetHuman(1001, false)
h.Game.Command("map oa_dm1")
frames(20)
check(names() == "Assassin,Grism," .. TAG .. "Cara" or names() == "Assassin,Sarge," .. TAG .. "Cara", "after the map change: " .. names())

-- g_friendBots 0: bots exactly as OA adds them
h.Game.Command("kick allbots")
frames(5)
FB.SetFriends(1003, { { id = 2003, name = "Cara" }, { id = 2004, name = "Dee" } })
h.Game.Command("g_friendBots 0")
h.Game.Command("map oa_dm1")
frames(10)
trapCalls = 0
h.Game.Command("addbot sarge")
frames(10)
local s = bots().Sarge
check(s ~= nil and trapCalls == 0, "g_friendBots 0: OA name, no friend asked")
check(s ~= nil and QS.Info_ValueForKey(G.trap_GetUserinfo(s), "oabot") == "", "g_friendBots 0: userinfo untouched")

print(string.format("friendbots: %d failure(s)", failures))
require("@lune/process").exit(if failures > 0 then 1 else 0)
