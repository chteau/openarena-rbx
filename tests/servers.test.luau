-- Multiplayer on Roblox servers with stubbed services: the registry
-- (heartbeat, expiry, paging, back-off), the browser's filter and sort,
-- request and TeleportData checks, how a server boots (reserved settings,
-- rotation, Studio), the RemoteFunction's join/rcon/favorites, and the
-- client's LAN traps and Start Server capture.
local S = H.require("shared/net/servers")
local Registry = H.require("server/sv/servers_registry")
local Servers = H.require("server/sv/servers_roblox")

-- a MemoryStoreSortedMap on a fake clock
local function sortedMap(clock)
	local m = { data = {}, calls = 0, fail = false }
	local function live(k)
		local d = m.data[k]
		return d and d.expires > clock.t and d or nil
	end
	function m:SetAsync(k, v, exp)
		m.calls += 1
		if m.fail then
			error("RequestThrottled")
		end
		m.data[k] = { value = v, expires = clock.t + exp }
	end
	function m:GetAsync(k)
		m.calls += 1
		local d = live(k)
		return d and d.value
	end
	function m:RemoveAsync(k)
		m.data[k] = nil
	end
	function m:GetRangeAsync(_dir, count, after)
		m.calls += 1
		if m.fail then
			error("RequestThrottled")
		end
		local keys = {}
		for k in m.data do
			if live(k) and (after == nil or k > after) then
				table.insert(keys, k)
			end
		end
		table.sort(keys)
		local out = {}
		for i = 1, math.min(count, #keys) do
			table.insert(out, { key = keys[i], value = m.data[keys[i]].value })
		end
		return out
	end
	return m
end

local CFG = { heartbeat = 10, expiry = 30, listCache = 5, listPages = 2, backoffMax = 60 }

H.test("servers.code", function()
	local a = S.code("6f1c0b2e-1111-2222-3333-444455556666")
	H.eq(#a, 6)
	H.eq(S.code("6f1c0b2e-1111-2222-3333-444455556666"), a)
	H.eq(S.parseCode(string.lower(a) .. ":27960"), a)
	assert(string.find(a, "^[2-9]"))
	H.eq(S.parseCode("O0I1ZZ"), nil)
	H.eq(S.parseCode("ABC234"), nil) -- a code starts with a digit
	H.eq(S.parseCode(42), nil)
end)

H.test("servers.registry_heartbeat_expiry", function()
	local clock = { t = 100 }
	local map = sortedMap(clock)
	local r = Registry.new(map, "asc", function()
		return clock.t
	end, CFG)
	H.eq(r:heartbeat({ code = "2AAAAA", public = true }), true)
	H.eq(#r:list(), 1)
	-- the listing is cached for listCache seconds
	local calls = map.calls
	r:list()
	H.eq(map.calls, calls)
	-- a heartbeat every 10 s keeps it; none for 30 s drops it
	clock.t += 10
	r:heartbeat({ code = "2AAAAA", public = true })
	clock.t += 29
	H.eq(#r:list(), 1)
	clock.t += 6 -- past the expiry and the listing cache
	H.eq(#r:list(), 0)
	H.eq(r:lookup("2AAAAA"), nil)
	-- BindToClose removes at once
	r:heartbeat({ code = "3BBBBB" })
	r:remove("3BBBBB")
	clock.t += 6
	H.eq(#r:list(), 0)
end)

H.test("servers.registry_paging", function()
	local clock = { t = 0 }
	local map = sortedMap(clock)
	for i = 1, 250 do
		map:SetAsync(("K%03d"):format(i), { code = ("K%03d"):format(i) }, 30)
	end
	local r = Registry.new(map, "asc", function()
		return clock.t
	end, CFG)
	H.eq(#r:list(), 250)
end)

H.test("servers.registry_backoff", function()
	local clock = { t = 0 }
	local map = sortedMap(clock)
	local r = Registry.new(map, "asc", function()
		return clock.t
	end, CFG)
	r:heartbeat({ code = "2AAAAA" })
	r:list()
	map.fail = true
	clock.t += 6
	H.eq(r:heartbeat({ code = "2AAAAA" }), false)
	H.eq(r.backoff, 2)
	-- while backing off nothing reaches MemoryStore, the last listing stays
	local calls = map.calls
	H.eq(r:heartbeat({ code = "2AAAAA" }), false)
	H.eq(#r:list(), 1)
	H.eq(map.calls, calls)
	clock.t += 2
	r:heartbeat({ code = "2AAAAA" })
	H.eq(r.backoff, 4)
	for _ = 1, 10 do
		clock.t += r.backoff
		r:heartbeat({ code = "2AAAAA" })
	end
	H.eq(r.backoff, 60)
	map.fail = false
	clock.t += 60
	H.eq(r:heartbeat({ code = "2AAAAA" }), true)
	H.eq(r.backoff, 0)
end)

local function entry(code, gt, clients, max, extra)
	local e = { code = code, hostname = code, map = "oa_dm1", gametype = gt, clients = clients, bots = 0, maxclients = max, reserved = false, public = true }
	for k, v in extra or {} do
		e[k] = v
	end
	return e
end

H.test("servers.filter", function()
	local all = {
		entry("2FA001", 0, 3, 12),
		entry("2CTF01", 4, 2, 12),
		entry("2EMPTY", 0, 0, 12),
		entry("2FULL1", 0, 12, 12),
		entry("2PRIV1", 0, 2, 12, { public = false }),
		entry("2HERE1", 0, 2, 12, { public = false, here = true }),
	}
	local function codes(list)
		local out = {}
		for _, e in list do
			table.insert(out, e.code)
		end
		table.sort(out)
		return table.concat(out, ",")
	end
	H.eq(codes(S.filter(all, {})), "2CTF01,2FA001,2HERE1")
	H.eq(codes(S.filter(all, { "ffa" })), "2FA001,2HERE1")
	H.eq(codes(S.filter(all, { "ffa", "empty", "full" })), "2EMPTY,2FA001,2FULL1,2HERE1")
	H.eq(codes(S.filter(all, { "ctf", "full" })), "2CTF01")
	local info = S.infoString(entry("2FA001", 3, 5, 12, { bots = 2 }))
	H.eq(string.match(info, "\\g_humanplayers\\(%d+)"), "3")
	H.eq(string.match(info, "\\nettype\\(%d+)"), "3")
end)

H.test("servers.sort", function()
	local U = H.require("ui/q3/U")
	H.require("ui/q3/ui_servers2")
	H.require("ui/q3/ui_servers2b")
	local function node(host, ping, clients)
		local n = U.ArenaServers_newServernode()
		n.hostname, n.pingtime, n.numclients, n.maxclients = host, ping, clients or 0, 12
		return n
	end
	U.ArenaServers_SetSortKey(4) -- SORT_PING
	local list = { node("UNKNOWN", -1), node("FAR", 300), node("NEAR", 40) }
	table.sort(list, function(a, b)
		return U.ArenaServers_Compare(a, b) < 0
	end)
	H.eq(list[1].hostname .. list[2].hostname .. list[3].hostname, "NEARFARUNKNOWN")
	U.ArenaServers_SetSortKey(0) -- SORT_HOST
	table.sort(list, function(a, b)
		return U.ArenaServers_Compare(a, b) < 0
	end)
	H.eq(list[1].hostname, "FAR")
end)

H.test("servers.dead_favorite", function()
	local U = H.require("ui/q3/U")
	H.require("ui/q3/ui_servers2")
	H.require("ui/q3/ui_servers2b")
	local g = U.g_arenaservers
	local keep = { g.numservers, g.maxservers, g.serverlist, U.g_servertype }
	U.g_servertype = H.require("client/sys/LAN").UIAS_FAVORITES
	g.numservers, g.maxservers, g.serverlist = { value = 0 }, 4, { [0] = U.ArenaServers_newServernode() }
	U.ArenaServers_Insert("2DEAD2", U.ArenaServers_NoResponse("2DEAD2"), U.ArenaServers_MaxPing())
	local n = g.serverlist[0]
	H.eq(n.adrstr, "2DEAD2")
	H.eq(n.hostname, "2DEAD2")
	H.eq(n.mapname, "NO RESPONSE")
	H.eq(n.maxclients, 0)
	-- a favorite not pinged yet shows its code too
	local Cvar = H.require("client/sys/Cvar")
	Cvar.Set("server1", "2NEW22")
	U.ArenaServers_LoadFavorites()
	H.eq(U.g_favoriteserverlist[0].hostname, "2NEW22")
	Cvar.Set("server1", "")
	g.numservers, g.maxservers, g.serverlist, U.g_servertype = keep[1], keep[2], keep[3], keep[4]
end)

local function maps(name)
	return name == "oa_dm1" or name == "oa_ctf2"
end

H.test("servers.validate_spec", function()
	local spec = S.validateSpec({
		kind = "host",
		map = "OA_DM1",
		gametype = 4,
		hostname = 'my "server";\nsay hi\\x',
		public = true,
		cvars = { fraglimit = 5000, timelimit = 15.7, rconpassword = 1, sv_maxclients = "8" },
		bots = { { name = "sarge", skill = 9, team = "Red" }, { name = "-none" }, { name = "x; quit" }, { name = "tony", team = "green" } },
	}, maps)
	assert(spec)
	H.eq(spec.map, "oa_dm1")
	H.eq(spec.hostname, "my serversay hix")
	H.eq(spec.cvars.fraglimit, 999)
	H.eq(spec.cvars.timelimit, 15)
	H.eq(spec.cvars.rconpassword, nil)
	H.eq(spec.cvars.sv_maxclients, nil)
	H.eq(#spec.bots, 2)
	H.eq(spec.bots[1].skill, 5)
	H.eq(spec.bots[1].team, "red")
	H.eq(spec.bots[2].team, nil)
	H.eq(S.validateSpec({ kind = "host", map = "oa_dm9", gametype = 0 }, maps), nil)
	H.eq(S.validateSpec({ kind = "rcon", map = "oa_dm1" }, maps), nil)
	-- single player: gametype forced, only g_spSkill, no bots, never listed
	local sp = S.validateSpec({ kind = "sp", map = "oa_dm1", gametype = 4, public = true, cvars = { g_spSkill = 3, fraglimit = 1 }, bots = { { name = "sarge" } } }, maps)
	assert(sp)
	H.eq(sp.gametype, 2)
	H.eq(sp.public, false)
	H.eq(#sp.bots, 0)
	H.eq(sp.cvars.fraglimit, nil)
	H.eq(S.startupText(sp), "set g_spSkill 3\nspmap oa_dm1")
end)

H.test("servers.validate_arrival", function()
	H.eq(S.validateArrival({ kind = "join" }), nil)
	H.eq(S.validateArrival({ oa = 1, kind = "admin" }), nil)
	local a = S.validateArrival({
		oa = 1,
		kind = "host",
		team = "red",
		cvars = { name = "Chee", model = "sarge/red", ["bad name"] = "x", long = string.rep("x", 300), ctl = "a\nb", num = 5 },
	})
	assert(a)
	H.eq(a.cvars.name, "Chee")
	H.eq(a.cvars.model, "sarge/red")
	H.eq(a.cvars["bad name"], nil)
	H.eq(a.cvars.long, nil)
	H.eq(a.cvars.ctl, nil)
	H.eq(a.cvars.num, nil)
	H.eq(a.team, "red")
end)

-- a stub Roblox env around a fake Game (cvars only)
local function fakeGame()
	local cvars = { sv_maxclients = "12", mapname = "oa_dm1", g_gametype = "0", sv_hostname = "noname" }
	local commands = {}
	return {
		cvars = cvars,
		commands = commands,
		Command = function(text)
			table.insert(commands, text)
		end,
		Cmd = { Cbuf_AddText = function(text)
			table.insert(commands, (string.gsub(text, "\n$", "")))
		end },
		Cvar = {
			Get = function(name, value)
				cvars[name] = cvars[name] or value
			end,
			Set = function(name, value)
				cvars[name] = value
			end,
			VariableString = function(name)
				return cvars[name] or ""
			end,
			VariableIntegerValue = function(name)
				return tonumber(cvars[name]) or 0
			end,
		},
		SV = { CS_CONNECTED = 2, svs = { clients = { [0] = { state = 4, isBot = false }, [1] = { state = 4, isBot = true } } } },
	}
end

local function stubEnv(opts)
	local clock = { t = 0 }
	local stores = {}
	local teleports = {}
	local env = {
		live = opts.live ~= false,
		placeId = 1234,
		jobId = opts.jobId or "job-a",
		privateServerId = opts.privateServerId or "",
		now = function()
			return clock.t
		end,
		wait = function(s)
			clock.t += s
		end,
		spawn = function() end,
		delay = function() end,
		ascending = "asc",
		Players = { GetPlayers = function()
			return opts.players or {}
		end },
		MemoryStoreService = { GetSortedMap = function(_, name)
			stores[name] = stores[name] or sortedMap(clock)
			return stores[name]
		end },
		TeleportService = {
			ReserveServer = function()
				return "ACCESS-1", "psid-1"
			end,
			TeleportAsync = function(_, placeId, players, options)
				table.insert(teleports, { placeId = placeId, players = players, options = options })
			end,
		},
		newTeleportOptions = function()
			local o = {}
			function o:SetTeleportData(d)
				o.data = d
			end
			return o
		end,
		filter = function(text)
			return (string.gsub(text, "badword", "#######"))
		end,
		budget = function()
			return opts.budget or 100
		end,
		favorites = opts.favorites,
	}
	return env, clock, stores, teleports
end

H.test("servers.boot", function()
	-- Studio: the old single-server path
	local env = stubEnv({ live = false })
	local s = Servers.new(env, fakeGame(), maps)
	H.eq(s:Boot({ maps = { "oa_ctf2", "oa_dm1" } }), "map oa_ctf2")
	H.eq(s.kind, "studio")
	-- public: the rotation, maps the place lacks skipped, `nextmap` chain
	env = stubEnv({})
	local g = fakeGame()
	s = Servers.new(env, g, maps)
	local text = s:Boot({ maps = { "oa_ctf2", "oa_dm1" } })
	H.eq(s.kind, "public")
	H.eq(g.cvars.sv_code, S.code("job-a"))
	assert(string.find(text, 'set d1 "g_gametype 0; fraglimit 20; timelimit 10; capturelimit 0; map oa_dm1; set nextmap vstr d2"', 1, true))
	assert(string.find(text, 'set d2 "g_gametype 4; fraglimit 0; timelimit 20; capturelimit 8; map oa_ctf2; set nextmap vstr d1"', 1, true))
	assert(not string.find(text, "oa_dm4", 1, true))
	assert(string.find(text, "set bot_minplayers 4", 1, true))
	H.eq(s:Boot({ maps = { "oa_dm1" }, startup = "map oa_dm1; addbot sarge" }), "map oa_dm1; addbot sarge")
	-- reserved: the settings the reserving server left in MemoryStore
	local stores
	env, _, stores = stubEnv({ privateServerId = "psid-1" })
	local spec = S.validateSpec({ kind = "host", map = "oa_ctf2", gametype = 4, hostname = "Chee", public = false, cvars = { capturelimit = 5 } }, maps)
	env.MemoryStoreService:GetSortedMap("OAReserved"):SetAsync(S.code("psid-1"), { spec = spec, host = 77, access = "ACCESS-1" }, 3600)
	g = fakeGame()
	s = Servers.new(env, g, maps)
	text = s:Boot({ maps = { "oa_dm1" }, startup = "map oa_dm1" })
	H.eq(s.kind, "host")
	H.eq(s.host, 77)
	H.eq(s.public, false)
	H.eq(s.code, S.code("psid-1"))
	H.eq(text, S.startupText(spec))
	-- reserved, MemoryStore empty: the first player's TeleportData (checked)
	local player = { UserId = 88, GetJoinData = function()
		return { TeleportData = { oa = 1, kind = "sp", spec = { kind = "sp", map = "oa_dm1", cvars = { g_spSkill = 4 } } } }
	end }
	env = stubEnv({ privateServerId = "psid-2", players = { player } })
	s = Servers.new(env, fakeGame(), maps)
	H.eq(s:Boot({ maps = { "oa_dm1" } }), "set g_spSkill 4\nspmap oa_dm1")
	H.eq(s.kind, "sp")
	H.eq(s.host, 88)
	-- reserved with nothing: rotation, unlisted
	env = stubEnv({ privateServerId = "psid-3" })
	s = Servers.new(env, fakeGame(), maps)
	s:Boot({ maps = { "oa_dm1" } })
	H.eq(s.kind, "private")
	H.eq(s.public, false)
end)

H.test("servers.join_and_host", function()
	local env, _, stores, teleports = stubEnv({})
	local s = Servers.new(env, fakeGame(), maps)
	s:Boot({ maps = { "oa_dm1" } })
	s:heartbeat()
	local e = stores.OAServers:GetAsync(s.code)
	H.eq(e.clients, 2)
	H.eq(e.bots, 1)
	H.eq(e.public, true)
	-- another public server and a private hosted one in the registry
	stores.OAServers:SetAsync("2PUB22", entry("2PUB22", 0, 1, 12, { job = "job-b", place = 1234 }), 30)
	stores.OAServers:SetAsync("2PRV33", entry("2PRV33", 4, 1, 12, { reserved = true, public = false, access = "ACCESS-9", place = 1234 }), 30)
	local p = { UserId = 5 }
	local res = s:handle(p, "list")
	H.eq(#res.entries, 1)
	H.eq(res.entries[1].code, "2PUB22")
	H.eq(res.entries[1].access, nil)
	H.eq(res.self.here, true)
	-- join a public server by its instance, a private one by its access code
	H.eq(s:handle(p, "join", "2pub22", { oa = 1, kind = "join", cvars = { name = "Chee", ["x y"] = "1" } }).ok, true)
	H.eq(teleports[1].options.ServerInstanceId, "job-b")
	H.eq(teleports[1].options.data.cvars.name, "Chee")
	H.eq(teleports[1].options.data.cvars["x y"], nil)
	H.eq(s:handle(p, "join", "2PRV33").ok, true)
	H.eq(teleports[2].options.ReservedServerAccessCode, "ACCESS-9")
	H.eq(s:handle(p, "join", s.code).err, "here")
	H.eq(s:handle(p, "join", "9ZZZZZ").ok, false)
	-- Start Server: reserve, leave the settings for the new server, teleport
	res = s:handle(p, "host", { kind = "host", map = "oa_ctf2", gametype = 4, hostname = "badword arena", public = true, team = "blue" }, { oa = 1, kind = "host", team = "blue" })
	H.eq(res.ok, true)
	H.eq(res.code, S.code("psid-1"))
	local rec = stores.OAReserved:GetAsync(res.code)
	H.eq(rec.host, 5)
	H.eq(rec.spec.hostname, "####### arena")
	H.eq(teleports[3].options.ReservedServerAccessCode, "ACCESS-1")
	H.eq(teleports[3].options.data.team, "blue")
	-- its code restarts it once nobody is on it (no registry entry)
	H.eq(s:handle(p, "join", res.code).ok, true)
	H.eq(teleports[4].options.ReservedServerAccessCode, "ACCESS-1")
	H.eq(s:handle(p, "host", { kind = "sp", map = "oa_dm1" }).ok, false)
end)

H.test("servers.rcon_and_apply", function()
	local env, _, stores = stubEnv({ privateServerId = "psid-1" })
	local spec = S.validateSpec({ kind = "host", map = "oa_dm1", gametype = 0 }, maps)
	env.MemoryStoreService:GetSortedMap("OAReserved"):SetAsync(S.code("psid-1"), { spec = spec, host = 77 }, 3600)
	local g = fakeGame()
	local s = Servers.new(env, g, maps)
	s:Boot({ maps = { "oa_dm1" } })
	local host, guest = { UserId = 77 }, { UserId = 78 }
	H.eq(s:handle(guest, "rcon", "addbot sarge 3").err, "Not the host")
	H.eq(s:handle(host, "rcon", "addbot sarge 3 red 1500").ok, true)
	H.eq(s:handle(host, "rcon", "clientkick 2; map_restart 0").ok, true)
	H.eq(s:handle(host, "rcon", "set fraglimit 30").ok, true)
	H.eq(s:handle(host, "rcon", "say hello").ok, false)
	H.eq(s:handle(host, "rcon", 'set sv_hostname "x"; say hi').ok, false)
	H.eq(s:handle(host, "rcon", "spmap oa_dm1").ok, false)
	H.eq(#g.commands, 3)
	-- the host's own hostname goes through the filter before anyone sees it
	s:handle(host, "rcon", "sv_hostname badword")
	g.cvars.sv_hostname = "badword"
	H.eq(s:entry().hostname, "#######")
	-- Start Server from the host: this server restarts with it
	H.eq(s:handle(host, "apply", { kind = "host", map = "oa_ctf2", gametype = 4, public = true }).ok, true)
	H.eq(g.commands[#g.commands], "set g_gametype 4\nset bot_enable 1\nmap oa_ctf2")
	H.eq(s.public, true)
	H.eq(s:handle(guest, "apply", { kind = "host", map = "oa_ctf2", gametype = 4 }).ok, false)
end)

H.test("servers.favorites_budget", function()
	local saved = {}
	local fav = {
		GetAsync = function(_, key)
			return saved[key]
		end,
		SetAsync = function(_, key, v)
			saved[key] = v
		end,
	}
	local env, clock = stubEnv({ favorites = fav, budget = 0 })
	local s = Servers.new(env, fakeGame(), maps)
	s:Boot({ maps = { "oa_dm1" } })
	local p = { UserId = 9 }
	-- no budget: kept pending, not written
	H.eq(s:handle(p, "favsave", { "2BC234", "nope", "2bc235" }).saved, false)
	H.eq(saved.u9, nil)
	env.budget = function()
		return 50
	end
	clock.t += 31
	H.eq(s:flushFavorites(9), true)
	H.eq(table.concat(saved.u9, ","), "2BC234,2BC235")
	-- at most one write per interval
	s:handle(p, "favsave", { "2BC236" })
	H.eq(#saved.u9, 2)
	H.eq(s:flushFavorites(9, true), true)
	H.eq(saved.u9[1], "2BC236")
	H.eq(s:handle(p, "favorites").codes[1], "2BC236")
end)

H.test("servers.lan_client", function()
	local LAN = H.require("client/sys/LAN")
	local Cmd = H.require("client/sys/Cmd")
	local Cvar = H.require("client/sys/Cvar")
	local C = H.require("client/q/Consts")
	LAN.Register() -- Client.luau does this at load, and routes `map` like this
	Cmd.AddCommand("map", function()
		LAN.Map(Cmd.Argv(0), Cmd.Argv(1))
	end)
	local pending = {}
	local calls = {}
	LAN.spawn = function(fn)
		table.insert(pending, fn)
	end
	LAN.delay = function(_, fn)
		table.insert(pending, fn)
	end
	local function run()
		while #pending > 0 do
			table.remove(pending, 1)()
		end
	end
	LAN.server = function()
		return { live = true, kind = "public", code = "2HERE2", host = 0 }
	end
	LAN.userId = function()
		return 5
	end
	LAN.selfPing = function()
		return 48
	end
	LAN.invoke = function(op, arg, arrival)
		table.insert(calls, { op = op, arg = arg, arrival = arrival })
		if op == "list" then
			return { ok = true, self = entry("2HERE2", 0, 2, 12, { here = true }), entries = { entry("2PUB22", 4, 1, 12), entry("2EMPTY", 0, 0, 12) } }
		elseif op == "lookup" then
			return { ok = true, entry = entry(arg, 0, 1, 12) }
		end
		return { ok = true }
	end
	Cmd.ExecuteText(C.EXEC_NOW, "globalservers 0 71 full")
	H.eq(LAN.GetServerCount(1), -1)
	run()
	H.eq(LAN.GetServerCount(1), 2)
	H.eq(LAN.GetServerAddressString(1, 0), "2HERE2")
	-- this server answers with the measured ping, the rest with -1 (unknown)
	Cmd.ExecuteText(C.EXEC_NOW, "ping 2HERE2")
	Cmd.ExecuteText(C.EXEC_NOW, "ping 2PUB22")
	Cmd.ExecuteText(C.EXEC_NOW, "ping 2FAV33")
	H.eq(LAN.GetPingQueueCount(), 3)
	H.eq(select(2, LAN.GetPing(0)), 48)
	H.eq(select(2, LAN.GetPing(1)), -1)
	H.eq(select(2, LAN.GetPing(2)), 0) -- pending lookup
	run()
	H.eq(select(2, LAN.GetPing(2)), -1)
	H.eq(string.match(LAN.GetPingInfo(1), "\\gametype\\(%d+)"), "4")
	for i = 0, 2 do
		LAN.ClearPing(i)
	end
	H.eq(LAN.GetPingQueueCount(), 0)
	-- Start Server: map + the addbot/team lines become one host request
	Cvar.Set("g_gametype", "4")
	Cvar.Set("fraglimit", "0")
	Cvar.Set("capturelimit", "6")
	Cvar.Set("sv_hostname", "Chee's")
	Cvar.Set("sv_public", "0")
	calls = {}
	Cmd.ExecuteText(C.EXEC_NOW, "map oa_ctf2")
	Cmd.ExecuteText(C.EXEC_NOW, "addbot sarge 4 red")
	Cmd.ExecuteText(C.EXEC_NOW, "addbot tony 4 blue")
	Cmd.ExecuteText(C.EXEC_NOW, "team blue")
	run()
	H.eq(calls[1].op, "host")
	local spec = calls[1].arg
	H.eq(spec.map, "oa_ctf2")
	H.eq(spec.gametype, 4)
	H.eq(spec.public, false)
	H.eq(spec.cvars.capturelimit, 6)
	H.eq(#spec.bots, 2)
	H.eq(spec.bots[2].team, "blue")
	H.eq(calls[1].arrival.oa, 1)
	H.eq(calls[1].arrival.team, "blue")
	-- the same from the host of a hosted server: applied here
	LAN.server = function()
		return { live = true, kind = "host", code = "2HERE2", host = 5 }
	end
	calls = {}
	Cmd.ExecuteText(C.EXEC_NOW, "map oa_dm1")
	run()
	H.eq(calls[1].op, "apply")
	-- the host's ADD BOTS goes to rcon
	calls = {}
	Cmd.ExecuteText(C.EXEC_NOW, "addbot sarge 3 red 0")
	run()
	H.eq(calls[1].op, "rcon")
	H.eq(calls[1].arg, "addbot sarge 3 red 0")
	-- a teleport's settings are applied, then the client connects
	local connected = false
	LAN.connect = function()
		connected = true
	end
	LAN.Start({ oa = 1, kind = "join", cvars = { name = "Teleported", ["bad name"] = "x" } })
	run()
	H.eq(Cvar.VariableString("name"), "Teleported")
	H.eq(connected, true)
	H.eq(Cvar.VariableString("sv_running"), "1")
	-- Studio: no capture, the caller keeps the old vote path
	LAN.server = function()
		return { live = false, kind = "studio", code = "2HERE2", host = 0 }
	end
	H.eq(LAN.Map("map", "oa_dm1"), false)
end)
