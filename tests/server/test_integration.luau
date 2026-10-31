-- Headless server integration test (lune run tests/server/test_integration.luau):
-- real maps, fake clients over the loopback transport.
--  1. wire format: every snapshot a client decodes is compared field by
--     field (bit patterns for floats) with the server's frame;
--  2. every game mode (and the instagib / rockets modifiers) spawns,
--     takes four clients through connect -> begin -> team join -> play
--     for 30 s of random input (moving, jumping, firing) with no error;
--  3. map_restart and map changes keep the clients;
--  4. the vote system and the tourney queue;
--  5. a reconnect from the same address keeps the slot with no drop, and
--     the client stays through map changes after it.
local W = require("./world")
local MSG = require("../../src/shared/net/msg")
local K = require("../../src/shared/consts")

local failures = 0
local function check(cond: any, what: string)
	if not cond then
		failures += 1
		print("FAIL: " .. what)
	end
end

local band = bit32.band

-- field-by-field comparison of what the client decoded with the frame the
-- server encoded; float fields by bit pattern except that -0 is sent as +0
local function same(fieldBits: number, a: number, b: number): boolean
	if fieldBits == 0 then
		if a == 0 and b == 0 then
			return true
		end
		return MSG.floatBits(a) == MSG.floatBits(b)
	end
	local nb = math.abs(fieldBits)
	if nb == 32 then
		return bit32.band(a, 0xFFFFFFFF) == bit32.band(b, 0xFFFFFFFF)
	end
	local mask = bit32.lshift(1, nb) - 1
	return band(a, mask) == band(b, mask)
end

local wire = { snapshots = 0, entities = 0, mismatches = 0, first = nil }
local function compareSnapshot(w, n, fc)
	local cl = w.SV.svs.clients[n]
	local frame = cl.frames[band(fc.serverMessageSequence, 31)]
	wire.snapshots += 1
	local snap = fc.snap
	for _, f in MSG.playerStateFields do
		if not same(f.bits, f.get(snap.ps), f.get(frame.ps)) then
			wire.mismatches += 1
			wire.first = wire.first or ("ps." .. f.name)
		end
	end
	for _, arr in { "stats", "persistant", "ammo", "powerups" } do
		for i = 0, 15 do
			local bits = if arr == "powerups" then 32 else 16
			if not same(bits, snap.ps[arr][i], frame.ps[arr][i]) then
				wire.mismatches += 1
				wire.first = wire.first or ("ps." .. arr)
			end
		end
	end
	local ents = fc:snapEntities()
	local count = 0
	for _ in ents do
		count += 1
	end
	if count ~= frame.num_entities then
		wire.mismatches += 1
		wire.first = wire.first or "entity count"
	end
	for i = 0, frame.num_entities - 1 do
		local es = frame.entities[i]
		local got = ents[es.number]
		wire.entities += 1
		if not got then
			wire.mismatches += 1
			wire.first = wire.first or ("missing entity " .. es.number)
			continue
		end
		for _, f in MSG.entityStateFields do
			if not same(f.bits, f.get(got), f.get(es)) then
				wire.mismatches += 1
				wire.first = wire.first or ("es." .. f.name)
			end
		end
	end
end

-- random but repeatable input
local seed = 12345
local function rnd(n: number): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end

local function randomInput(fc)
	local cmd = fc.wish
	if rnd(10) == 0 then
		cmd.forwardmove = ({ 127, 0, -127 })[rnd(3) + 1]
		cmd.rightmove = ({ 127, 0, -127 })[rnd(3) + 1]
		cmd.upmove = if rnd(4) == 0 then 127 else 0
	end
	cmd.angles[1] = band(cmd.angles[1] + rnd(800) - 300, 65535)
	cmd.angles[0] = band(rnd(2000) - 1000, 65535)
	cmd.buttons = if rnd(3) == 0 then 1 else 0 -- BUTTON_ATTACK
	if rnd(40) == 0 then
		cmd.weapon = 1 + rnd(9)
	end
end

local function runRandom(w, seconds)
	for _ = 1, seconds * 20 do
		for _, fc in w.clients do
			randomInput(fc)
		end
		w:step(50)
	end
end

local function active(w): number
	local n = 0
	for i, fc in w.clients do
		if w.SV.svs.clients[i].state == 4 then
			n += 1
		end
	end
	return n
end

local t0 = os.clock()

-- 1 + 3: FFA wire check, movement, map_restart and map change
do
	local w = W.new()
	w.onSnapshot = function(n, fc)
		compareSnapshot(w, n, fc)
	end
	w:command("map oa_dm1")
	local a = w:connect("Alice")
	local b = w:connect("Bob")
	w:run(2)
	check(active(w) == 2, "FFA: both clients active")
	check(a.snap and a.snap.ps.clientNum == a.clientNum, "FFA: snapshot is for the right client")
	local start = { a.snap.ps.origin[0], a.snap.ps.origin[1] }
	a.wish.forwardmove = 127
	w:run(1)
	a.wish.forwardmove = 0
	local moved = math.abs(a.snap.ps.origin[0] - start[1]) + math.abs(a.snap.ps.origin[1] - start[2])
	check(moved > 50, "FFA: forwardmove moves the player (" .. moved .. " units)")
	runRandom(w, 20)
	check(active(w) == 2, "FFA: clients still active after random play")

	local gs = a.gamestates
	w:command("map_restart 0")
	w:run(1)
	check(a.gamestates == gs, "map_restart: no new gamestate")
	check(active(w) == 2, "map_restart: clients back in the game")
	w:command("map oa_dm4")
	w:run(2)
	check(a.gamestates == gs + 1, "map change: a new gamestate")
	check(active(w) == 2, "map change: clients back in the game")
	check(string.find(a.configstrings[K.CS_SERVERINFO] or "", "\\mapname\\oa_dm4", 1, true) ~= nil, "map change: serverinfo names the new map")
	runRandom(w, 5)
	print(string.format(
		"wire: %d snapshots, %d entity states compared, %d mismatches%s",
		wire.snapshots,
		wire.entities,
		wire.mismatches,
		if wire.first then " (first: " .. wire.first .. ")" else ""
	))
	check(wire.mismatches == 0, "wire: decoded snapshots equal the server frames")
end

-- 2: every game mode
local modes = {
	{ gt = 0, map = "oa_dm1", name = "FFA" },
	{ gt = 1, map = "oa_dm1", name = "Tourney" },
	{ gt = 3, map = "oa_dm4", name = "TDM", teams = true },
	{ gt = 4, map = "oa_ctf2", name = "CTF", teams = true },
	{ gt = 5, map = "oa_ctf2", name = "1FCTF", teams = true },
	{ gt = 6, map = "oa_ctf2", name = "Overload", teams = true },
	{ gt = 7, map = "oa_ctf2", name = "Harvester", teams = true },
	{ gt = 8, map = "oa_dm4", name = "Elimination", teams = true },
	{ gt = 9, map = "ps37ctf", name = "CTF Elimination", teams = true },
	{ gt = 10, map = "oa_dm5", name = "LMS" },
	{ gt = 11, map = "oa_ctf2", name = "Double Domination", teams = true },
	{ gt = 12, map = "oa_dm4", name = "Domination", teams = true, dom = true },
	{ gt = 0, map = "oa_dm1", name = "FFA instagib", cvars = "set g_instantgib 1" },
	{ gt = 3, map = "oa_dm4", name = "TDM rockets", teams = true, cvars = "set g_rockets 1" },
}

-- three domination points for oa_dm4 (it ships none)
local function domPoints(map: string, ents: string): string
	if map ~= "oa_dm4" then
		return ents
	end
	return ents
		.. '{\n"classname" "domination_point"\n"origin" "0 0 64"\n"message" "Alpha"\n}\n'
		.. '{\n"classname" "domination_point"\n"origin" "512 0 64"\n"message" "Bravo"\n}\n'
		.. '{\n"classname" "domination_point"\n"origin" "-512 0 64"\n"message" "Charlie"\n}\n'
end

for _, m in modes do
	local w = W.new({ patchEntities = if m.dom then domPoints else nil })
	local events = 0
	w.onSnapshot = function(n, fc)
		compareSnapshot(w, n, fc)
		for _, es in fc:snapEntities() do
			if es.eType > K.ET_EVENTS then
				events += 1
			end
		end
	end
	if m.cvars then
		w:command(m.cvars)
	end
	w:command("set g_gametype " .. m.gt)
	w:command("set fraglimit 0")
	w:command("set timelimit 0")
	w:command("set g_doWarmup 0")
	local ok, err = pcall(function()
		w:command("map " .. m.map)
		local cs = {}
		for i = 1, 4 do
			cs[i] = w:connect("P" .. i)
		end
		w:run(2)
		if m.teams then
			for i, fc in cs do
				fc:addReliableCommand("team " .. (if i % 2 == 0 then "blue" else "red"))
			end
		else
			for _, fc in cs do
				fc:addReliableCommand("team free")
			end
		end
		w:run(2)
		runRandom(w, 30)
	end)
	check(ok, m.name .. ": runs without errors" .. (if ok then "" else ": " .. tostring(err)))
	if ok then
		local gt = w.Game.Cvar.VariableIntegerValue("g_gametype")
		check(gt == m.gt, m.name .. ": g_gametype is " .. m.gt .. " (got " .. gt .. ")")
		local playing, score, deaths = 0, 0, 0
		for i = 0, 3 do
			local cl = w.G.g_clients[i]
			if cl.pers.connected == 2 then -- CON_CONNECTED
				playing += 1
			end
			score += cl.ps.persistant[K.PERS_SCORE]
			deaths += cl.ps.persistant[K.PERS_KILLED]
		end
		check(playing == 4, m.name .. ": four clients connected in the game (" .. playing .. ")")
		local ts = w.G.level.teamScores
		print(string.format(
			"%-18s ok  level.time %6d, %d clients, scores %d, deaths %d, team scores %d/%d, events %d",
			m.name, w.G.level.time, playing, score, deaths, ts[1], ts[2], events
		))
	end
end

-- 4a: votes
do
	local w = W.new()
	w:command("set g_allowVote 1")
	w:command("map oa_dm1")
	local cs = {}
	for i = 1, 3 do
		cs[i] = w:connect("V" .. i)
	end
	w:run(2)
	cs[1]:addReliableCommand("callvote timelimit 15")
	w:run(1)
	cs[2]:addReliableCommand("vote yes")
	cs[3]:addReliableCommand("vote yes")
	w:run(5)
	check(w.Game.Cvar.VariableIntegerValue("timelimit") == 15, "vote: timelimit 15 passed (got " .. w.Game.Cvar.VariableString("timelimit") .. ")")

	-- a map vote carrying a gametype changes both in one vote; single
	-- player and a gametype g_voteGametypes leaves out are refused
	w:command("set g_voteGametypes /0/1/3/4/")
	for _, bad in { "2", "5" } do
		cs[1]:addReliableCommand("callvote map oa_ctf2 " .. bad)
		w:run(1.5)
		check(w.G.level.voteTime == 0, "vote: map with gametype " .. bad .. " refused")
	end
	cs[1]:addReliableCommand("callvote map oa_ctf2 4")
	w:run(1.5)
	check(string.find(w.G.level.voteDisplayString, "Capture the Flag", 1, true) ~= nil, "vote: map + gametype display (" .. w.G.level.voteDisplayString .. ")")
	cs[2]:addReliableCommand("vote yes")
	cs[3]:addReliableCommand("vote yes")
	w:run(8)
	check(w.Game.Cvar.VariableIntegerValue("g_gametype") == 4, "vote: map + gametype set g_gametype 4 (got " .. w.Game.Cvar.VariableString("g_gametype") .. ")")
	check(w.Game.Cvar.VariableString("mapname") == "oa_ctf2", "vote: map + gametype changed the map (got " .. w.Game.Cvar.VariableString("mapname") .. ")")
end

-- 4b: tourney queue
do
	local w = W.new()
	w:command("set g_gametype 1")
	w:command("set g_doWarmup 0")
	w:command("map oa_dm1")
	local cs = {}
	for i = 1, 3 do
		cs[i] = w:connect("T" .. i)
		w:run(1)
	end
	w:run(2)
	local TEAM_FREE, TEAM_SPECTATOR = 0, 3
	local function team(i)
		return w.G.g_clients[i].sess.sessionTeam
	end
	check(team(0) == TEAM_FREE and team(1) == TEAM_FREE, "tourney: first two clients play")
	check(team(2) == TEAM_SPECTATOR, "tourney: the third waits as a spectator")
	-- the second player leaves: the queued spectator takes the slot
	w.SV.SV_Disconnect(1)
	w.clients[1] = nil
	w:run(3)
	check(team(2) == TEAM_FREE, "tourney: the queued spectator joins when a player leaves")
end

-- 5: reconnect (sv_client.c SV_DirectConnect: same address, same slot,
-- no drop) and map changes after it
do
	local w = W.new()
	w:command("set g_doWarmup 0")
	w:command("map oa_dm1")
	local a = w:connect("Alice")
	local b = w:connect("Bob")
	w:run(2)
	check(active(w) == 2, "reconnect: both clients active first")
	local addr = w.SV.svs.clients[a.clientNum].address
	local sentBefore = w.SV.svs.clients[a.clientNum].outgoingSequence
	-- the client restarts its connection (the transport's "connect" again)
	local a2 = require("./fakeclient").new("Alice")
	a2.outgoingSequence = a.outgoingSequence
	a2.wish = require("../../src/shared/structs").usercmd_t()
	local n = w.SV.SV_DirectConnect(
		"\\name\\Alice\\model\\sarge\\headmodel\\sarge\\handicap\\100\\snaps\\20\\rate\\25000",
		a2, addr, w.SV.GuidFor(1), a2.outgoingSequence
	)
	check(n == a.clientNum, "reconnect: same slot")
	check(a.disconnected == nil, "reconnect: no disconnect command to the old connection")
	local dropLine = false
	for _, text in b.commands do
		if string.find(text, "disconnected", 1, true) or string.find(text, "reconnect", 1, true) then
			dropLine = true
		end
	end
	check(not dropLine, "reconnect: no drop broadcast")
	check(w.SV.svs.clients[a.clientNum].outgoingSequence >= sentBefore, "reconnect: packet numbers keep counting")
	w.clients[a.clientNum] = a2
	a2.clientNum = a.clientNum
	a2.serverMessageSequence = w.SV.svs.clients[a.clientNum].outgoingSequence - 1
	w:run(2)
	check(a2.gamestates == 1, "reconnect: the new connection gets a gamestate")
	check(active(w) == 2, "reconnect: both clients back in the game")
	check(b.disconnected == nil, "reconnect: the other client is untouched")
	-- an old-connection packet arriving late is ignored
	local late = w.SV.svs.clients[a.clientNum].incomingSequence
	w.SV.SV_PacketEvent(a.clientNum, a:writePacket({}))
	check(w.SV.svs.clients[a.clientNum].incomingSequence == late, "reconnect: a late old packet is dropped")

	w:command("map oa_dm5")
	w:run(2)
	check(active(w) == 2, "reconnect then map change: both in the game")
	w:command("map_restart 0")
	w:run(2)
	check(active(w) == 2, "reconnect then map_restart: both in the game")
	check(a2.disconnected == nil and b.disconnected == nil, "no client was ever disconnected")
end

-- 6. match end: single player sends its player the postgame line the
-- ui menu reads and waits there; multiplayer shows the scoreboard, then
-- runs `nextmap` even when nobody presses fire
local function fragTo(w, fc, n)
	local ent = w.G.g_entities[fc.clientNum]
	w.G.AddScore(ent, ent.r.currentOrigin, n)
end
local function hasCommand(fc, prefix): string?
	for _, c in fc.commands do
		if string.sub(c, 1, #prefix) == prefix then
			return c
		end
	end
	return nil
end
do
	local w = W.new()
	w:command("set g_gametype 2")
	w:command("set g_doWarmup 0")
	w:command("spmap oa_dm1")
	w:command("set fraglimit 1") -- after the arena sets its own
	-- q3 ends no match with fewer than two playing
	local a = w:connect("Alice")
	w:connect("Bob")
	w:run(2)
	check(active(w) == 2, "SP: players in the game")
	fragTo(w, a, 1)
	w:run(3)
	check(w.G.level.intermissiontime ~= 0, "SP: fraglimit starts the intermission")
	local pg = hasCommand(a, "postgame ")
	check(pg ~= nil and string.match(pg, "^postgame 2 " .. a.clientNum .. " ") ~= nil, "SP: the player gets the postgame line (" .. tostring(pg) .. ")")
	check(not w:printed("[Uu]nknown command"), "SP: no unknown command at match end")
	w:run(40)
	check(w.G.level.intermissiontime ~= 0, "SP: stays at the intermission for the menu")
	w:command("map_restart 0")
	w:run(2)
	check(w.G.level.intermissiontime == 0 and active(w) == 2, "SP: Replay restarts the map")
end
do
	local w = W.new()
	w:command("capturelimit 8") -- the rotation's d1 runs it before the game loads
	w:command("set g_gametype 0")
	w:command("set fraglimit 1")
	w:command("set g_doWarmup 0")
	w:command("map oa_dm1")
	w:command("set nextmap \"map oa_dm4\"")
	local a = w:connect("Alice")
	w:connect("Bob")
	w:run(2)
	fragTo(w, a, 1)
	w:run(3)
	check(w.G.level.intermissiontime ~= 0, "FFA: fraglimit starts the intermission")
	check(hasCommand(a, "postgame") == nil, "FFA: no postgame line")
	w:run(35)
	check(string.find(a.configstrings[K.CS_SERVERINFO] or "", "\\mapname\\oa_dm4", 1, true) ~= nil, "FFA: idle intermission moves to nextmap")
	check(active(w) == 2, "FFA: clients in the next map")
	check(not w:printed("[Uu]nknown command"), "FFA: no unknown command at match end")
end

print(string.format("integration: %d failure(s), %.1fs", failures, os.clock() - t0))
local process = require("@lune/process")
process.exit(if failures > 0 then 1 else 0)
