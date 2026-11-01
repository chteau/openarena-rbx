-- Settings applied on arrival (lune run tests/server/test_servers.luau):
-- the console text a reserved server starts with (shared/net/servers
-- startupText) and the public rotation (sv/servers_roblox rotationText),
-- run on the real game; the cvars must be what the start server menu
-- would have set on a listen server, and the registry entry must count
-- the bots it added.
local W = require("./world")
local S = require("../../src/shared/net/servers")
local Servers = require("../../src/server/sv/servers_roblox")
local fs = require("@lune/fs")

local failures, passes = 0, 0
local function eq(got: any, want: any, what: string)
	if got == want then
		passes += 1
	else
		failures += 1
		print(("FAIL %s: got %s, want %s"):format(what, tostring(got), tostring(want)))
	end
end
local function mapExists(name: string): boolean
	return fs.isFile("build/maps/" .. name .. ".bsp")
end

-- single player arena
do
	local w = W.new()
	local spec = assert(S.validateSpec({ kind = "sp", map = "oa_dm1", cvars = { g_spSkill = 4 } }, mapExists))
	w:command(S.startupText(spec))
	w:run(1)
	eq(w.Game.Cvar.VariableIntegerValue("g_gametype"), 2, "sp gametype")
	eq(w.Game.Cvar.VariableIntegerValue("g_spSkill"), 4, "sp skill")
	eq(w.Game.Cvar.VariableString("mapname"), "oa_dm1", "sp map")
end

-- public rotation
do
	local w = W.new()
	w:command(Servers.rotationText(Servers.Config.public, mapExists, "oa_dm1"))
	w:run(2)
	local Cvar = w.Game.Cvar
	eq(Cvar.VariableString("mapname"), "oa_dm1", "rotation map")
	eq(Cvar.VariableIntegerValue("g_gametype"), 0, "rotation gametype")
	eq(Cvar.VariableIntegerValue("fraglimit"), 20, "rotation fraglimit")
	eq(Cvar.VariableString("nextmap"), "vstr d2", "rotation nextmap")
	eq(Cvar.VariableIntegerValue("bot_minplayers"), 4, "bot_minplayers")
	-- the next level: TDM on oa_dm4
	w:command("vstr nextmap")
	w:run(2)
	eq(Cvar.VariableString("mapname"), "oa_dm4", "rotation map 2")
	eq(Cvar.VariableIntegerValue("g_gametype"), 3, "rotation gametype 2")
	eq(Cvar.VariableString("nextmap"), "vstr d3", "rotation nextmap 2")
end

-- Start Server: TDM on oa_dm1 with three bots (the BSP and map.json the
-- bots host needs are there for oa_dm1)
do
	-- the bots need botlib's files: tests/bots' host mounts them (last,
	-- since it doesn't reset the game singletons like world.luau does)
	local host = require("../bots/simhost").new({ maps = { "oa_dm1" }, quiet = true })
	local spec = assert(S.validateSpec({
		kind = "host",
		map = "oa_dm1",
		gametype = 3,
		hostname = "Chee's TDM",
		public = true,
		cvars = { capturelimit = 5, timelimit = 15, fraglimit = 40, g_friendlyfire = 1, sv_maxclients = 10, g_instantgib = 1, pmove_fixed = 1, pmove_msec = 8 },
		bots = { { name = "sarge", skill = 3, team = "red" }, { name = "tony", skill = 3, team = "blue" }, { name = "penguin", skill = 2, team = "blue" } },
	}, mapExists))
	local game = host.Game
	local s = Servers.new({ live = false, jobId = "", placeId = 0, privateServerId = "", now = os.clock }, game, mapExists)
	game.Command(S.startupText(spec))
	for _ = 1, 40 do
		host.frame(50)
	end
	local Cvar = game.Cvar
	eq(Cvar.VariableString("mapname"), "oa_dm1", "map")
	eq(Cvar.VariableIntegerValue("g_gametype"), 3, "g_gametype")
	eq(Cvar.VariableIntegerValue("fraglimit"), 40, "fraglimit")
	eq(Cvar.VariableIntegerValue("capturelimit"), 5, "capturelimit")
	eq(Cvar.VariableIntegerValue("timelimit"), 15, "timelimit")
	eq(Cvar.VariableIntegerValue("g_friendlyfire"), 1, "g_friendlyfire")
	eq(Cvar.VariableIntegerValue("sv_maxclients"), 10, "sv_maxclients")
	eq(Cvar.VariableIntegerValue("g_instantgib"), 1, "g_instantgib")
	eq(Cvar.VariableIntegerValue("pmove_msec"), 8, "pmove_msec")
	eq(Cvar.VariableString("sv_hostname"), "Chee's TDM", "sv_hostname")
	local e = s:entry()
	eq(e.clients, 3, "entry clients")
	eq(e.bots, 3, "entry bots")
	eq(e.maxclients, 10, "entry maxclients")
	eq(e.map, "oa_dm1", "entry map")
	eq(e.gametype, 3, "entry gametype")
	-- the bots joined the teams the menu gave them
	local red, blue = 0, 0
	for i = 0, 9 do
		local cl = game.G.level.clients[i]
		if cl and cl.pers and cl.pers.connected == 2 then
			if cl.sess.sessionTeam == 1 then
				red += 1
			elseif cl.sess.sessionTeam == 2 then
				blue += 1
			end
		end
	end
	eq(red, 1, "red bots")
	eq(blue, 2, "blue bots")
	-- in game, the host's ADD BOTS (rcon) adds one; a guest's is refused
	s.host = 77
	eq(s:handle({ UserId = 5 }, "rcon", "addbot gargoyle 3 red 0").err, "Not the host", "guest addbot")
	eq(s:handle({ UserId = 77 }, "rcon", "addbot gargoyle 3 red 0").ok, true, "host addbot")
	for _ = 1, 10 do
		host.frame(50)
	end
	eq(s:entry().bots, 4, "bots after host addbot")
end

print(("servers: passed %d, failed %d"):format(passes, failures))
require("@lune/process").exit(if failures > 0 then 1 else 0)
