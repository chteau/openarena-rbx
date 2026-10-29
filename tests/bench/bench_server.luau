-- Server frame cost (lune run tests/bench/bench_server.luau [map] [clients]):
-- a headless server at sv_fps 20 with fake clients sending one usercmd per
-- frame (random movement and fire), timing SV_Frame (game frame, pmove for
-- every usercmd, snapshot building and delta encoding).
local process = require("@lune/process")
local W = require("../server/world")

local map = process.args[1] or "oa_dm4"
local n = tonumber(process.args[2]) or 8
local w = W.new()
w:command("set sv_maxclients " .. n)
w:command("set g_doWarmup 0")
w:command("map " .. map)
local cs = {}
for i = 1, n do
	cs[i] = w:connect("B" .. i)
end
w:run(3)
local seed = 7
local function rnd(k)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % k
end
local frames, total, worst = 0, 0, 0
local packetTime = 0
for _ = 1, 600 do
	for _, fc in cs do
		local c = fc.wish
		if rnd(10) == 0 then
			c.forwardmove = ({ 127, 0, -127 })[rnd(3) + 1]
			c.rightmove = ({ 127, 0, -127 })[rnd(3) + 1]
		end
		c.angles[1] = bit32.band(c.angles[1] + rnd(600) - 300, 65535)
		c.buttons = if rnd(3) == 0 then 1 else 0
	end
	local t0 = os.clock()
	w:step(50)
	local dt = os.clock() - t0
	frames += 1
	total += dt
	worst = math.max(worst, dt)
end
print(string.format(
	"%s, %d clients: %.2f ms per 50 ms server step (packets in + SV_Frame + snapshots out, fake-client decoding included), worst %.2f ms",
	map, n, total / frames * 1000, worst * 1000
))
