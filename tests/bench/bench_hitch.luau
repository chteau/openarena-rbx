-- Server hitches: a bot match driven the way Roblox drives it (one
-- Game.Frame per Heartbeat, ~60 Hz), timing every host tick and splitting
-- the slow ones into bots, game frames, snapshots and the rest.
--   lune run tests/bench/bench_hitch.luau [map] [bots] [seconds] [g_gametype]
local process = require("@lune/process")
local Host = require("../bots/simhost")

local map = process.args[1] or "oa_dm4"
local nbots = tonumber(process.args[2]) or 8
local seconds = tonumber(process.args[3]) or 180
local h = Host.new({ maps = { map }, quiet = true, log = {} })
local G, SV = h.G, h.SV

local bucket = { bots = 0, game = 0, snap = 0 }
local function timed(t: any, k: string, name: string)
	local f = t[k]
	t[k] = function(...)
		local c = os.clock()
		local a, b = f(...)
		bucket[name] += os.clock() - c
		return a, b
	end
end
timed(h.Bots, "Frame", "bots")
timed(G, "vmMain", "game")
timed(SV, "SV_SendClientMessages", "snap")

h.Game.Command("bot_enable 1")
h.Game.Command("g_gametype " .. (process.args[4] or "0"))
h.Game.Command("map " .. map)
for _ = 1, 10 do
	h.frame(50)
end
local names = { "sarge", "grunt", "sergei", "tony", "gargoyle", "assassin", "liz", "skelebot" }
for i = 1, nbots do
	h.Game.Command(string.format("addbot %s 4", names[(i - 1) % #names + 1]))
end

-- Heartbeat steps alternate 16/17 ms like a 60 Hz frame clock
local edges = { 2, 4, 8, 16, 33, 50, 100, 250 }
local hist = table.create(#edges + 1, 0)
local spikes = {}
local all = {}
local heap0 = collectgarbage("count")
local heapMax = heap0
local ticks = math.floor(seconds * 60)
-- one more bot joins halfway, as a friend-bot does when a player joins
local joinAt = ticks // 2
for i = 1, ticks do
	bucket.bots, bucket.game, bucket.snap = 0, 0, 0
	local c = os.clock()
	if i == joinAt then
		h.Game.Command("addbot grunt 4")
		print(string.format("addbot mid-match: %.2f ms in the command", (os.clock() - c) * 1000))
	end
	h.frame(if i % 3 == 0 then 16 else 17)
	local ms = (os.clock() - c) * 1000
	table.insert(all, ms)
	heapMax = math.max(heapMax, collectgarbage("count"))
	local k = #edges + 1
	for j, e in edges do
		if ms < e then
			k = j
			break
		end
	end
	hist[k] += 1
	if ms >= 16 then
		table.insert(spikes, {
			t = i / 60,
			ms = ms,
			bots = bucket.bots * 1000,
			game = (bucket.game - bucket.bots) * 1000,
			snap = bucket.snap * 1000,
		})
	end
end
table.sort(all)
local sum = 0
for _, v in all do
	sum += v
end
print(string.format("== %s, %d bots, %d s, %d ticks: mean %.2f ms, p50 %.2f, p99 %.2f, p99.9 %.2f, max %.2f",
	map, nbots, seconds, ticks, sum / ticks, all[ticks // 2], all[math.ceil(ticks * 0.99)],
	all[math.ceil(ticks * 0.999)], all[ticks]))
local lo = 0
for j = 1, #edges + 1 do
	local e = edges[j]
	print(string.format("  %5s-%-5s ms %6d", tostring(lo), if e then tostring(e) else "", hist[j]))
	lo = e
end
print(string.format("heap: start %.0f KB, max %.0f KB, end %.0f KB", heap0, heapMax, collectgarbage("count")))
table.sort(spikes, function(a, b)
	return a.ms > b.ms
end)
print(string.format("%d ticks >= 16 ms; worst:", #spikes))
for i = 1, math.min(15, #spikes) do
	local s = spikes[i]
	print(string.format("  t=%7.2fs %7.2f ms  bots %7.2f  game(excl. bots) %7.2f  snap %6.2f  other %6.2f",
		s.t, s.ms, s.bots, s.game, s.snap, s.ms - s.bots - s.game - s.snap))
end
