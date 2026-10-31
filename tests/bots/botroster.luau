-- The bot roster (lune run tests/bots/botroster.luau): the fixed account
-- table, the name lookup against a stubbed UserService (a deleted account,
-- a failing service), then a running server with AAS: the single-player
-- arenas' bots wear their accounts with the tag (oa_minia's Tony and
-- Penguin, the Final arena's boss), a human on a bot's account sends that
-- bot back to its OA identity until they leave, a bot whose lookup failed
-- keeps its OA name, and with g_botRoster 0 bots take the friend-bots path.
local Host = require("./simhost")
local QS = require("../../src/shared/q_shared")
local FB = require("../../src/server/sv/friendbots")
local Roster = require("../../src/server/sv/botroster")
local C = require("../../src/server/g_defs")

local failures = 0
local function check(ok: boolean, what: string)
	if not ok then
		failures += 1
		print("FAIL: " .. what)
	end
end

-- the accounts Chee picked, by OA bot
local WANT = {
	grunt = 1274097373,
	liz = 73392736,
	tony = 260342963,
	penguin = 105519417,
	skelebot = 10138699399,
	ghost = 2678188290,
	beret = 3,
	broadklin = 66246631,
	morgan = 2,
	assassin = 1,
	["cyber-garg"] = 123757139,
	andriy = 5290932442,
	sergei = 58526171,
	metalbot = 156,
	gargoyle = 11759238920,
	sarge = 10595767136,
	grism = 8950832609,
	s_marine = 925308243,
	jiangshi = 8313172606,
}
local n = 0
for bot, id in Roster.ids do
	n += 1
	check(WANT[bot] == id, "roster id for " .. bot)
end
check(n == 19, "roster has " .. n .. " accounts")

-- the lookup: display names when OA can draw them, the username otherwise;
-- an account missing from the answer (deleted or banned) has none
local DISPLAY = {
	[260342963] = { "Berzappy", "Berzappy" },
	[105519417] = { "Syveric", "Viken" },
	[925308243] = { "Cheeteau", "Cheeteau" },
	[8313172606] = { "miilkyww", "misaa" },
	[10595767136] = { "HeyDepoo", "D\u{e9}po" },
}
local asked
local userService = {
	GetUserInfosByUserIdsAsync = function(_, ids: { number })
		asked = ids
		local out = {}
		for _, id in ids do
			local d = DISPLAY[id]
			if d then
				table.insert(out, { Id = id, Username = d[1], DisplayName = d[2] })
			elseif id ~= 2678188290 then -- Ghost's account is "deleted"
				table.insert(out, { Id = id, Username = "user" .. id, DisplayName = "User" .. id })
			end
		end
		return out
	end,
}
check(Roster.Account("Tony") == nil, "no name before the lookup")
check(not Roster.Fetch({ GetUserInfosByUserIdsAsync = function()
	error("HTTP 500")
end }), "a failing service reports failure")
check(Roster.Account("Tony") == nil, "no name after a failed lookup")
check(Roster.Fetch(userService) and #asked == 19, "one lookup for every account")
check(Roster.Account("tony").name == "Berzappy", "Tony's name")
check(Roster.Account("Penguin").name == "Viken", "display name")
check(Roster.Account("Sarge").name == "HeyDepoo", "username when OA can't draw the display name")
check(Roster.Account("Ghost") == nil, "a deleted account has no name")
check(not Roster.Listed("Kyonshi") and Roster.Account("Kyonshi") == nil, "a bot with no account")
local accounts = Roster.Accounts()
check(string.find(accounts, "tony=260342963", 1, true) ~= nil, "the menus' list has Tony's account")
check(string.find(accounts, "ghost=", 1, true) == nil, "and not a deleted account")

-- the running server
local FRAME_MS = 50
local h = Host.new({ maps = { "oa_minia", "czest1tourney", "oa_dm1" }, quiet = true })
local G, SV = h.G, h.SV
local wearing = {}
FB.onWear = function(c, f)
	wearing[c] = f and f.id
end
local function frames(k: number)
	for _ = 1, k do
		h.frame(FRAME_MS)
	end
end
-- shown name -> { client, oabot }
local function bots(): { [string]: { number | string } }
	local out = {}
	for i = 0, G.level.maxclients - 1 do
		local cs = G.trap_GetConfigstring(C.CS_PLAYERS + i)
		if cs ~= "" and QS.Info_ValueForKey(cs, "skill") ~= "" then
			out[QS.Info_ValueForKey(cs, "n")] = { i, QS.Info_ValueForKey(G.trap_GetUserinfo(i), "oabot") }
		end
	end
	return out
end
local function names(): string
	local list = {}
	for s in bots() do
		table.insert(list, s)
	end
	table.sort(list)
	return table.concat(list, ",")
end
local TAG = "^3[BOT]^7 "

h.Game.Command("bot_enable 1")
-- the single-player arenas: their bots come from the arena info
h.Game.Command("spmap oa_minia")
frames(120)
check(names() == TAG .. "Berzappy," .. TAG .. "Viken", "oa_minia bots: " .. names())
local B = bots()
local tony = B[TAG .. "Berzappy"]
check(tony and tony[2] == "Tony" and wearing[tony[1] :: number] == 260342963, "Tony wears his account")
check(tony and QS.Info_ValueForKey(G.trap_GetUserinfo(tony[1] :: number), "characterfile") == "bots/tony_c.c", "Tony keeps his character")

h.Game.Command("spmap czest1tourney")
frames(120)
check(names() == TAG .. "misaa", "the Final arena's bot: " .. names())
local boss = bots()[TAG .. "misaa"]
check(boss and boss[2] == "Jiangshi" and wearing[boss[1] :: number] == 8313172606, "the boss wears its account")
local ui = boss and G.trap_GetUserinfo(boss[1] :: number) or ""
check(QS.Info_ValueForKey(ui, "characterfile") == "bots/kyonshi_c.c", "the boss has Kyonshi's character")
check(QS.Info_ValueForKey(ui, "model") == "beret/cooldude", "the boss's OA model")
check(G.G_GetBotInfoByName("Sarge") ~= nil and not string.find(names(), "Depo", 1, true), "no Sarge in the Final arena")

-- free for all from here
h.Game.Command("kick allbots")
h.Game.Command("g_gametype 0")
h.Game.Command("map oa_dm1")
frames(10)

-- a human on a bot's account: the bot is S_Marine again while they're here
for _, b in { "s_marine", "ghost", "sarge" } do
	h.Game.Command("addbot " .. b)
end
frames(10)
check(names() == "Ghost," .. TAG .. "Cheeteau," .. TAG .. "HeyDepoo", "added: " .. names())
local chee = bots()[TAG .. "Cheeteau"][1] :: number
FB.SetHuman(925308243, true)
SV.BotRosterRefresh()
check(bots().S_Marine ~= nil and bots().S_Marine[1] == chee and wearing[chee] == nil, "Chee here: S_Marine is OA's")
h.Game.Command("map oa_dm1")
frames(20)
check(bots().S_Marine ~= nil and wearing[chee] == nil, "still OA's after the map change while Chee is here")
FB.SetHuman(925308243, false)
SV.BotRosterRefresh()
check(bots()[TAG .. "Cheeteau"] ~= nil and wearing[chee] == 925308243, "Chee left: S_Marine wears his account again")
check(bots().Ghost ~= nil and wearing[bots().Ghost[1] :: number] == nil, "a failed lookup keeps the OA name and model")
check(G.BotNoChat({ client = chee }) and not G.BotNoChat({ client = bots().Ghost[1] }), "roster bots stay out of the chat")

-- g_botRoster 0: the friend-bots path (g_friendBots 1), else OA's bots
h.Game.Command("kick allbots")
frames(5)
FB.SetHuman(1001, true)
FB.SetFriends(1001, { { id = 2001, name = "Alice" } })
h.Game.Command("g_botRoster 0")
h.Game.Command("g_friendBots 1")
frames(1)
h.Game.Command("addbot tony")
h.Game.Command("addbot sarge")
frames(10)
check(names() == "Sarge," .. TAG .. "Alice", "g_botRoster 0: friend-bots: " .. names())
h.Game.Command("g_friendBots 0")
h.Game.Command("map oa_dm1")
frames(20)
check(names() == "Sarge,Tony", "g_botRoster 0, g_friendBots 0: OA's bots: " .. names())
h.Game.Command("g_botRoster 1")
h.Game.Command("map oa_dm1")
frames(20)
check(names() == TAG .. "Berzappy," .. TAG .. "HeyDepoo", "g_botRoster 1 again at the map change: " .. names())

print(string.format("botroster: %d failure(s)", failures))
require("@lune/process").exit(if failures > 0 then 1 else 0)
