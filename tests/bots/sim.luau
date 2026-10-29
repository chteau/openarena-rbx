-- Headless bot match: N bots on a map through the real server (pmove,
-- items, weapons), reporting what they did and what thinking cost.
--   lune run tests/bots/sim.luau [map] [bots] [seconds] [g_gametype]
local process = require("@lune/process")
local Host = require("./simhost")
local C = require("../../src/shared/consts")
local BG = require("../../src/shared/BG")
local BGM = require("../../src/shared/bg/bg_misc")

local map = process.args[1] or "oa_dm1"
local nbots = tonumber(process.args[2]) or 4
local seconds = tonumber(process.args[3]) or 120
local FRAME_MS = 50
local log = {}
local h = Host.new({ maps = { map }, quiet = process.env.BOTS_VERBOSE == nil, log = log })
local G = h.G

-- every predictable event the players' pmove / touch code raises
local events: { [number]: { [number]: number } } = {}
local origAdd = BG.BG_AddPredictableEventToPlayerstate
local function counted(ev, parm, ps)
	local n = ps.clientNum
	events[n] = events[n] or {}
	events[n][ev] = (events[n][ev] or 0) + 1
	return origAdd(ev, parm, ps)
end
-- pmove and the jump pad touch call through bg_misc, the game through BG's copy
BG.BG_AddPredictableEventToPlayerstate = counted
BGM.BG_AddPredictableEventToPlayerstate = counted

-- trigger_teleport touches (respawns also flip EF_TELEPORT_BIT, so the flag alone can't tell)
local teleports: { [number]: number } = {}
local origTele = G.TeleportPlayer
G.TeleportPlayer = function(player, origin, angles)
	teleports[player.s.number] = (teleports[player.s.number] or 0) + 1
	return origTele(player, origin, angles)
end

h.Game.Command("bot_enable 1")
h.Game.Command("g_gametype " .. (process.args[4] or "0"))
h.Game.Command("map " .. map)
for _ = 1, 10 do
	h.frame(FRAME_MS)
end
local names = { "sarge", "grunt", "major", "kyonshi", "angelyss", "tanisha", "liz", "skelebot" }
local first = #log + 1
for i = 1, nbots do
	h.Game.Command(string.format("addbot %s 4", names[(i - 1) % #names + 1]))
end
local function botClients()
	local out = {}
	for i = 0, C.MAX_CLIENTS - 1 do
		local ent = G.g_entities[i]
		if ent and ent.inuse and ent.client and bit32.band(ent.r.svFlags, 8) ~= 0 then
			table.insert(out, i)
		end
	end
	return out
end
for _ = 1, 20 do
	h.frame(FRAME_MS)
end
for i = first, #log do
	if string.find(log[i], "rror") or string.find(log[i], "can't open") then
		print("log: " .. log[i])
	end
end
local bots = botClients()
print(string.format("sim: %d bots added (clients %s)", #bots, table.concat(bots, ",")))
if #bots == 0 then
	return
end

local stat = {}
for _, i in bots do
	stat[i] = { dist = 0, respawns = 0, last = nil }
end
h.botMs, h.gameMs, h.frames = 0, 0, 0
events = {}
teleports = {}
local mark = #log + 1
local frames = math.floor(seconds * 1000 / FRAME_MS)
for _ = 1, frames do
	h.frame(FRAME_MS)
	for _, i in bots do
		local ps = G.g_entities[i].client.ps
		local st = stat[i]
		local o = ps.origin
		if st.last then
			local dx, dy, dz = o[0] - st.last[0], o[1] - st.last[1], o[2] - st.last[2]
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if d > 100 then
				st.respawns += 1 -- teleport, respawn or pad launch spike: not walked
			else
				st.dist += d
			end
		end
		st.last = { [0] = o[0], o[1], o[2] }
	end
end

local items, kills, deaths = {}, {}, {}
for i = mark, #log do
	local c, cls = string.match(log[i], "Item: (%d+) (%S+)")
	if c then
		items[tonumber(c)] = items[tonumber(c)] or {}
		table.insert(items[tonumber(c)], cls)
	end
	local k, v = string.match(log[i], "Kill: (%d+) (%d+) %d+:")
	if k then
		k, v = tonumber(k), tonumber(v)
		kills[k] = (kills[k] or 0) + 1
		deaths[v] = (deaths[v] or 0) + 1
	end
end

print(string.format("== %s, %d bots, %d game seconds (%d frames of %d ms)", map, #bots, seconds, frames, FRAME_MS))
for _, i in bots do
	local st, ev = stat[i], events[i] or {}
	local cl = G.g_entities[i].client
	local n = items[i] and #items[i] or 0
	local seen, kinds = {}, 0
	for _, cls in items[i] or {} do
		if not seen[cls] then
			seen[cls] = true
			kinds += 1
		end
	end
	print(string.format(
		"bot %d %-10s items=%3d (%2d kinds) dist=%6.0f u pads=%2d teleports=%2d jumps=%3d shots=%3d kills=%2d deaths=%2d score=%d",
		i, cl.pers.netname, n, kinds, st.dist, ev[C.EV_JUMP_PAD] or 0, teleports[i] or 0,
		ev[C.EV_JUMP] or 0, ev[C.EV_FIRE_WEAPON] or 0, kills[i] or 0, deaths[i] or 0,
		cl.ps.persistant[C.PERS_SCORE]))
end
local n = #bots * h.frames
print(string.format("cost: bots %.3f ms/bot/frame (%.2f s total), server total %.3f ms/frame (game %.3f + bots %.3f)",
	h.botMs / n, h.botMs / 1000, h.gameMs / h.frames, (h.gameMs - h.botMs) / h.frames, h.botMs / h.frames))

print("sim: done")
