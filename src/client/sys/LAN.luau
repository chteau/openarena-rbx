-- The client half of multiplayer on Roblox servers (docs/ARCHITECTURE.md,
-- "Multiplayer on Roblox servers"): ioq3's server browser engine side
-- (cl_main.c's localservers / globalservers / ping and the LAN_* traps
-- q3_ui's ui_servers2 reads), `connect <code>`, Start Server and single
-- player as reserved servers, the host's rcon, Favorites in a DataStore and
-- what a teleport brings along. An "address" is a server's join code.
--
-- Everything goes through ReplicatedStorage.OANet.Servers
-- (sv/servers_roblox.luau). Where the server says it isn't live (Studio,
-- rbx-native's own runtime) the browser lists this server alone and maps
-- start through the old single-server path (Client.luau's votes).
local C = require(script.Parent.Parent.q.Consts)
local Cmd = require(script.Parent.Cmd)
local Cvar = require(script.Parent.Cvar)
local Net = require(script.Parent.Net)
local S = require(script.Parent.Parent.Parent.shared.net.servers)

local LAN = {}

local MAX_PINGREQUESTS = 32
local UIAS_LOCAL, UIAS_FAVORITES = 0, 6

-- hooks (Client.luau sets them; the tests replace invoke/spawn/delay)
LAN.connect = function() end -- Client.Connect
LAN.fail = function(_msg: string) end -- back to the main menu with an error
LAN.spawn = function(fn: () -> ())
	task.spawn(fn)
end
LAN.delay = function(s: number, fn: () -> ())
	task.delay(s, fn)
end

local function folder(): Instance?
	return game:GetService("ReplicatedStorage"):FindFirstChild("OANet")
end

function LAN.note(): RemoteEvent?
	local f = folder()
	return f and f:FindFirstChild("ServersNote") :: RemoteEvent?
end

-- one call to the server's Servers RemoteFunction (yields)
LAN.invoke = function(op: string, arg: any, arrival: any): any
	local f = folder()
	local fn = f and f:FindFirstChild("Servers")
	if fn == nil then
		return { ok = false, err = "No server list here" }
	end
	local ok, res = pcall(function()
		return (fn :: RemoteFunction):InvokeServer(op, arg, arrival)
	end)
	return if ok and type(res) == "table" then res else { ok = false, err = tostring(res) }
end

-- what this server is (the attributes servers_roblox sets)
LAN.server = function(): { live: boolean, kind: string, code: string, host: number }
	local f = folder()
	return {
		live = f ~= nil and f:GetAttribute("ServersLive") == true,
		kind = f and f:GetAttribute("ServersKind") or "studio",
		code = f and f:GetAttribute("ServersCode") or "",
		host = f and f:GetAttribute("ServersHost") or 0,
	}
end
LAN.userId = function(): number
	return game:GetService("Players").LocalPlayer.UserId
end
-- the round trip to this server, ms (Player:GetNetworkPing); no other
-- server can be pinged from a Roblox client
LAN.selfPing = function(): number
	return math.floor(game:GetService("Players").LocalPlayer:GetNetworkPing() * 1000 + 0.5)
end

function LAN.isHost(): boolean
	local s = LAN.server()
	return s.host ~= 0 and s.host == LAN.userId()
end

-- browser state: per source, the listing (nil while the query runs), and
-- the ping queue
local lists: { [number]: { S.Entry }? } = { [0] = {}, [1] = {} }
local pings: { [number]: any } = {}

local function sourceList(source: number): { S.Entry }?
	return lists[if source == UIAS_LOCAL then 0 else 1]
end

local function pingOf(e: S.Entry): number
	return if e.here then math.max(1, LAN.selfPing()) else -1
end

local function query(slot: number, op: string, arg: any, words: { string }?)
	lists[slot] = nil
	LAN.spawn(function()
		local res = LAN.invoke(op, arg)
		local entries = if res.ok then res.entries else {}
		if res.self then
			table.insert(entries, 1, res.self)
		end
		lists[slot] = if words then S.filter(entries, words) else entries
	end)
end

-- the archived cvars a teleport carries (name, model, SP progress, ...)
local function arrival(team: string?): any
	return { oa = 1, kind = "join", cvars = Cvar.Archived(), team = team }
end

function LAN.Join(code: string)
	local s = LAN.server()
	local c = S.parseCode(code)
	if c ~= nil and c == s.code then
		LAN.connect()
		return
	end
	if not s.live then
		-- one place, one match: the single-server behaviour of before
		LAN.connect()
		return
	end
	print(("Joining %s...\n"):format(code))
	LAN.spawn(function()
		local res = LAN.invoke("join", code, arrival())
		if res.ok and res.err == "here" then
			LAN.connect()
		elseif not res.ok then
			LAN.fail(res.err or "Couldn't join " .. code)
		end
	end)
end

-- Start Server / single player: `map`, `devmap` and `spmap` start a
-- reserved server with the settings the menu just put in the cvars, after
-- catching the addbot and team lines the menu queues behind it (or, from
-- the host of this server, restart it with them). False: not live, the
-- caller keeps the old path.
local capture: any = nil
function LAN.Map(cmd: string, map: string): boolean
	if not LAN.server().live or map == "" then
		return false
	end
	local sp = cmd == "spmap"
	local spec = {
		kind = if sp then "sp" else "host",
		map = map,
		gametype = Cvar.VariableIntegerValue("g_gametype"),
		hostname = Cvar.VariableString("sv_hostname"),
		public = Cvar.VariableIntegerValue("sv_public") ~= 0,
		cvars = {},
		bots = {},
	}
	for name in (if sp then S.SP_CVARS else S.HOST_CVARS) do
		spec.cvars[name] = Cvar.VariableValue(name)
	end
	capture = { spec = spec }
	LAN.delay(1, LAN.Flush)
	return true
end

function LAN.Flush()
	local c = capture
	if c == nil then
		return
	end
	capture = nil
	local spec = c.spec
	local s = LAN.server()
	local here = LAN.isHost() and (if spec.kind == "sp" then s.kind == "sp" else s.kind == "host")
	local op = if here then "apply" else spec.kind
	LAN.spawn(function()
		local res = LAN.invoke(op, spec, arrival(c.team))
		if not res.ok then
			LAN.fail(res.err or "Couldn't start the server")
		elseif here then
			LAN.Team(c.team)
		end
	end)
end

-- the team the start server menu picked, once the game is up
function LAN.Team(team: string?)
	if team == nil then
		return
	end
	LAN.spawn(function()
		for _ = 1, 600 do
			if Net.state == C.CA_ACTIVE then
				Net.SendClientCommand("team " .. team)
				return
			end
			task.wait(0.1)
		end
	end)
end

-- the server commands q3_ui's host menus run (ADD BOTS, REMOVE BOTS,
-- RESTART ARENA) and rcon: to this server's rcon for its host, into the
-- capture while Start Server is collecting, else to the game as before
LAN.forward = function(_text: string) end
local function hostCommand(name: string)
	return function()
		local args = Cmd.Args()
		local text = if args ~= "" then name .. " " .. args else name
		if capture and name == "addbot" then
			table.insert(capture.spec.bots, { name = Cmd.Argv(1), skill = tonumber(Cmd.Argv(2)) or 3, team = Cmd.Argv(3) })
		elseif LAN.isHost() then
			if name == "rcon" then
				text = args
			end
			LAN.spawn(function()
				local res = LAN.invoke("rcon", text)
				if not res.ok then
					print(("rcon: %s\n"):format(res.err or "failed"))
				end
			end)
		elseif name == "rcon" then
			print("rcon: only the host of this server can use it\n")
		else
			LAN.forward(text)
		end
	end
end

-- favorites (q3_ui keeps them in the server1..16 cvars) mirror a per-user
-- DataStore key; writing back waits 2 s for the menu to finish
local loadingFavorites, favSaveQueued = false, false
local function saveFavorites()
	favSaveQueued = false
	local codes = {}
	for i = 1, 16 do
		local v = Cvar.VariableString("server" .. i)
		if v ~= "" then
			table.insert(codes, v)
		end
	end
	LAN.spawn(function()
		LAN.invoke("favsave", codes)
	end)
end

function LAN.Register()
	Cvar.Get("sv_master1", "roblox", C.CVAR_ROM)
	Cvar.Get("sv_public", "1", C.CVAR_ARCHIVE)
	Cmd.AddCommand("localservers", function()
		lists[0] = nil
		LAN.spawn(function()
			local jobs = {}
			pcall(function()
				for _, f in game:GetService("Players").LocalPlayer:GetFriendsOnline(200) do
					if f.PlaceId == game.PlaceId and f.GameId then
						table.insert(jobs, f.GameId)
					end
				end
			end)
			query(0, "local", jobs)
		end)
	end)
	Cmd.AddCommand("globalservers", function()
		local words = {}
		for i = 3, Cmd.Argc() - 1 do
			table.insert(words, Cmd.Argv(i))
		end
		query(1, "list", nil, words)
	end)
	Cmd.AddCommand("ping", function()
		local adr = Cmd.Argv(1)
		for n = 0, MAX_PINGREQUESTS - 1 do
			if pings[n] == nil then
				local p = { adr = adr, time = 0 }
				pings[n] = p
				local code = S.parseCode(adr)
				for _, slot in { 0, 1 } do
					for _, e in lists[slot] or {} do
						if e.code == code then
							p.entry, p.time = e, pingOf(e)
							return
						end
					end
				end
				-- not in a listing (a favorite): ask the registry; no answer
				-- leaves it pending and the menu times it out, like a dead server
				if code then
					LAN.spawn(function()
						local res = LAN.invoke("lookup", code)
						if res.ok and pings[n] == p then
							p.entry, p.time = res.entry, pingOf(res.entry)
						end
					end)
				end
				return
			end
		end
	end)
	for _, name in { "addbot", "clientkick", "kick", "map_restart", "rcon" } do
		Cmd.AddCommand(name, hostCommand(name))
	end
	Cmd.AddCommand("team", function()
		if capture then
			capture.team = Cmd.Argv(1)
		else
			LAN.forward("team " .. Cmd.Args())
		end
	end)
	local prev = Cvar.onChange
	Cvar.onChange = function(v)
		if prev then
			prev(v)
		end
		if not loadingFavorites and not favSaveQueued and string.match(v.name, "^server%d+$") and LAN.server().live then
			favSaveQueued = true
			LAN.delay(2, saveFavorites)
		end
	end
end

-- after the ui is up: this server's code for SERVER INFO's "add to
-- favorites", host powers, saved favorites, and a teleport's settings
-- (straight into the game when it brought any)
function LAN.Start(teleportData: any)
	LAN.spawn(function()
		-- the server publishes what it is once it has booted
		for _ = 1, 100 do
			if LAN.server().code ~= "" or folder() == nil then
				break
			end
			task.wait(0.2)
		end
		local s = LAN.server()
		Cvar.Set("cl_currentServerAddress", s.code, true)
		if LAN.isHost() then
			-- what q3_ui checks before offering a listen server's host menus
			Cvar.Set("sv_running", "1", true)
			Cvar.Set("bot_enable", "1", true)
		end
		if not s.live then
			return
		end
		local res = LAN.invoke("favorites")
		if res.ok and type(res.codes) == "table" then
			loadingFavorites = true
			for i = 1, 16 do
				local c = S.parseCode(res.codes[i])
				Cvar.Set("server" .. i, c or "")
			end
			loadingFavorites = false
		end
	end)
	local a = S.validateArrival(teleportData)
	if a == nil then
		return
	end
	for name, value in a.cvars do
		Cvar.Set(name, value)
	end
	LAN.connect()
	LAN.Team(a.team)
end

-- the LAN_* traps (cl_ui.c)
function LAN.GetServerCount(source: number): number
	local l = sourceList(source)
	return if l then #l else -1
end

function LAN.GetServerAddressString(source: number, n: number): string
	local l = sourceList(source)
	local e = l and l[n + 1]
	return if e then e.code else ""
end

function LAN.GetPing(n: number): (string, number)
	local p = pings[n]
	if p == nil then
		return "", 0
	end
	return p.adr, p.time
end

function LAN.GetPingInfo(n: number): string
	local p = pings[n]
	return if p and p.entry then S.infoString(p.entry) else ""
end

function LAN.ClearPing(n: number)
	pings[n] = nil
end

function LAN.GetPingQueueCount(): number
	local count = 0
	for _ in pings do
		count += 1
	end
	return count
end

LAN.UIAS_FAVORITES = UIAS_FAVORITES
return LAN
