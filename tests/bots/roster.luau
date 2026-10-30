-- The roster on a running server with AAS (lune run tests/bots/roster.luau):
-- addbot for a bot tools/oaconv/roster.json drops says "not defined" as OA
-- does for any unknown bot, and bot_minplayers fills only with kept bots.
local Host = require("./simhost")
local QS = require("../../src/shared/q_shared")

local FRAME_MS = 50
local log = {}
local h = Host.new({ maps = { "oa_dm1" }, quiet = true, log = log })
local G = h.G
h.Game.Command("bot_enable 1")
h.Game.Command("map oa_dm1")
for _ = 1, 10 do
	h.frame(FRAME_MS)
end

local failures = 0
local function check(ok: boolean, what: string)
	if not ok then
		failures += 1
		print("FAIL: " .. what)
	end
end

local mark = #log + 1
for _, name in { "neko", "angelyss", "merman", "headcrash", "kyonshi", "major", "sorceress" } do
	h.Game.Command("addbot " .. name)
end
for _ = 1, 10 do
	h.frame(FRAME_MS)
end
local text = table.concat(log, "", mark)
for _, name in { "neko", "angelyss", "merman", "headcrash", "kyonshi", "major", "sorceress" } do
	check(string.find(text, "Bot '" .. name .. "' not defined", 1, true) ~= nil, "addbot " .. name .. " is unknown")
end

local DROPPED = { "neko", "angelyss", "major", "kyonshi", "sorceress", "merman", "arachna", "ayumi", "beret/headcrash", "beret/macho", "sarge/classic", "sarge/classicred", "sarge/classicblue" }
-- bot_minplayers adds one bot per check through G_AddRandomBot; pick the
-- rest the same way rather than waiting for every check
h.Game.Command("bot_minplayers 12")
for _ = 1, 200 do
	h.frame(FRAME_MS)
end
for _ = 1, 10 do
	G.G_AddRandomBot(-1)
	h.frame(FRAME_MS)
end
for _ = 1, 40 do
	h.frame(FRAME_MS)
end
local bots = {}
for i = 0, 63 do
	local ent = G.g_entities[i]
	if ent and ent.inuse and ent.client and bit32.band(ent.r.svFlags, 8) ~= 0 then
		local model = string.lower(QS.Info_ValueForKey(G.trap_GetUserinfo(i), "model"))
		table.insert(bots, model)
		for _, d in DROPPED do
			check(model ~= d and string.find(model, d .. "/", 1, true) ~= 1, "bot_minplayers picked " .. model)
		end
	end
end
check(#bots >= 6, "only " .. #bots .. " random bots joined")
print(string.format("roster: %d random bots (%s), %d failure(s)", #bots, table.concat(bots, " "), failures))
require("@lune/process").exit(if failures > 0 then 1 else 0)
