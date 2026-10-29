-- Benchmark: 1000 collision traces (player box, point, capsule) and Pmove
-- frames on a real map.
--   lune run tests/bench/bench_trace.luau <map.bsp>
local process = require("@lune/process")
local Cm = require("../oracle/common")
local Collision = require("../../src/shared/Collision")
local S = require("../../src/shared/structs")
local Q = require("../../src/shared/q_math")
local C = require("../../src/shared/consts")
local BG = require("../../src/shared/bg/bg_pmove")

local mapPath = process.args[1]
Cm.loadMap(mapPath)

local wmins, wmaxs = Q.vec3(), Q.vec3()
Collision.ModelBounds(0, wmins, wmaxs)

-- deterministic xorshift
local rng = 12345
local function rnd()
	rng = bit32.bxor(rng, bit32.lshift(rng, 13))
	rng = bit32.bxor(rng, bit32.rshift(rng, 17))
	rng = bit32.bxor(rng, bit32.lshift(rng, 5))
	return rng / 4294967296
end
local function point()
	return Q.vec3(
		Q.f(wmins[0] + rnd() * (wmaxs[0] - wmins[0])),
		Q.f(wmins[1] + rnd() * (wmaxs[1] - wmins[1])),
		Q.f(wmins[2] + rnd() * (wmaxs[2] - wmins[2]))
	)
end

local N = 1000
local starts, ends = {}, {}
for i = 1, N do
	local a = point()
	-- mostly short moves, like movement code does; some long ones
	local b
	if i % 10 == 0 then
		b = point()
	else
		b = Q.vec3(Q.f(a[0] + (rnd() - 0.5) * 256), Q.f(a[1] + (rnd() - 0.5) * 256), Q.f(a[2] + (rnd() - 0.5) * 128))
	end
	starts[i], ends[i] = a, b
end
local pmins, pmaxs = Q.vec3(-15, -15, -24), Q.vec3(15, 15, 32)
local tr = S.trace_t()

local function bench(name, fn)
	fn() -- warm up
	local best = math.huge
	for _ = 1, 5 do
		local t0 = os.clock()
		fn()
		best = math.min(best, os.clock() - t0)
	end
	print(string.format("  %-28s %8.2f us/op (best of 5 x %d)", name, best / N * 1e6, N))
end

print(string.match(mapPath, "([^/]+)%.bsp$") or mapPath)
bench("player box (MASK_PLAYERSOLID)", function()
	for i = 1, N do
		Collision.BoxTrace(tr, starts[i], ends[i], pmins, pmaxs, 0, C.MASK_PLAYERSOLID, false)
	end
end)
bench("point (MASK_SHOT)", function()
	for i = 1, N do
		Collision.BoxTrace(tr, starts[i], ends[i], Q.vec3_origin, Q.vec3_origin, 0, C.MASK_SHOT, false)
	end
end)
bench("player capsule", function()
	for i = 1, N do
		Collision.BoxTrace(tr, starts[i], ends[i], pmins, pmaxs, 0, C.MASK_PLAYERSOLID, true)
	end
end)

-- Pmove: 1000 frames of running + jumping from a spawn-ish point
local ps = S.playerState_t()
-- first info_player_deathmatch / team spawn in the entity string
local QS = require("../../src/shared/q_shared")
local spawn = Q.vec3()
do
	local p = QS.cursor(Collision.EntityString())
	local cls, org = nil, nil
	while p.data do
		local tok = QS.COM_Parse(p)
		if tok == "{" then
			cls, org = nil, nil
		elseif tok == "}" then
			if cls and string.find(cls, "^info_player") or (cls and string.find(cls, "^team_CTF_")) then
				if org then
					local x, y, z = string.match(org, "(%S+) (%S+) (%S+)")
					spawn = Q.vec3(Q.f(tonumber(x) :: number), Q.f(tonumber(y) :: number), Q.f(tonumber(z) :: number + 9))
					break
				end
			end
		elseif tok ~= "" then
			local v = QS.COM_Parse(p)
			if tok == "classname" then
				cls = v
			elseif tok == "origin" then
				org = v
			end
		end
	end
end
local function resetPs()
	ps = S.playerState_t()
	Q.VectorCopy(spawn, ps.origin)
	ps.gravity = 800
	ps.speed = 320
	ps.groundEntityNum = C.ENTITYNUM_NONE
	ps.stats[C.STAT_HEALTH] = 100
	ps.commandTime = 1000
end
local pm = S.pmove_t()
pm.trace = function(results, start, mins, maxs, endp, pass, mask)
	Collision.BoxTrace(results, start, endp, mins, maxs, 0, mask, false)
	results.entityNum = if results.fraction ~= 1 then C.ENTITYNUM_WORLD else C.ENTITYNUM_NONE
end
pm.pointcontents = function(p, pass)
	return Collision.PointContents(p, 0)
end
bench("Pmove frame (8 ms)", function()
	resetPs()
	pm.ps = ps
	for i = 1, N do
		pm.cmd.serverTime = ps.commandTime + 8
		pm.cmd.forwardmove = 127
		pm.cmd.rightmove = if i % 120 < 60 then 127 else -127
		pm.cmd.upmove = 127
		pm.cmd.angles[1] = (i * 91) % 65536
		pm.tracemask = C.MASK_PLAYERSOLID
		BG.Pmove(pm)
		if ps.origin[2] < -10000 then
			resetPs()
			pm.ps = ps
		end
	end
end)
