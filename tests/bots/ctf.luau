-- CTF check: bots on oa_ctf2 (g_gametype 4) must capture flags within 20
-- minutes of game time (native OA 0.8.8's bots, same setup: 3 captures in
-- 21 minutes, most deaths in the map's void). Counts the game log's "CTF:"
-- lines (0 flag taken, 1 capture, 2 return, 3 carrier fragged) and fails
-- without enough captures.
--   lune run tests/bots/ctf.luau [minutes] [bots] [min captures]
local process = require("@lune/process")
local Host = require("./simhost")
local C = require("../../src/shared/consts")

local minutes = tonumber(process.args[1]) or 20
local nbots = tonumber(process.args[2]) or 6
local want = tonumber(process.args[3]) or 1
local FRAME_MS = 50

local log = {}
local h = Host.new({ maps = { "oa_ctf2" }, quiet = process.env.BOTS_VERBOSE == nil, log = log })
h.Game.Command("bot_enable 1")
h.Game.Command("g_gametype 4")
h.Game.Command("map oa_ctf2")
for _ = 1, 10 do
	h.frame(FRAME_MS)
end
local names = { "sarge", "grunt", "major", "kyonshi", "angelyss", "tanisha", "liz", "skelebot" }
for i = 1, nbots do
	h.Game.Command(string.format("addbot %s 4 %s", names[(i - 1) % #names + 1], if i % 2 == 1 then "red" else "blue"))
end

local mark = #log + 1
h.botMs, h.gameMs, h.frames = 0, 0, 0
local frames = minutes * 60 * 1000 // FRAME_MS
local firstCapture
for f = 1, frames do
	h.frame(FRAME_MS)
	if not firstCapture then
		for i = mark, #log do
			if string.match(log[i], "^CTF: %-?%d+ %d+ 1:") then
				firstCapture = f * FRAME_MS / 1000
				break
			end
		end
	end
end

local counts = { [0] = 0, 0, 0, 0 }
for i = mark, #log do
	local kind, text = string.match(log[i], "^CTF: %-?%d+ %d+ (%d+): (.*)")
	if kind then
		kind = tonumber(kind)
		counts[kind] += 1
		if kind == 1 then
			print("  " .. string.gsub(text, "%s+$", ""))
		end
	end
end
local level = h.G.level
print(string.format("== oa_ctf2 CTF, %d bots, %d game minutes", nbots, minutes))
print(string.format("captures %d (first after %s s), flags taken %d, returned %d, carriers fragged %d, score red %d blue %d",
	counts[1], if firstCapture then string.format("%.1f", firstCapture) else "-", counts[0], counts[2], counts[3],
	level.teamScores[C.TEAM_RED], level.teamScores[C.TEAM_BLUE]))
print(string.format("cost: bots %.3f ms/bot/frame, server total %.3f ms/frame",
	h.botMs / (nbots * h.frames), h.gameMs / h.frames))
if counts[1] < want then
	print(string.format("ctf: FAILED, %d capture(s), wanted at least %d", counts[1], want))
	process.exit(1)
end
print("ctf: ok")
