--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Not a port: multiplayer on Roblox servers (docs/ARCHITECTURE.md,
-- "Multiplayer on Roblox servers"). Each Roblox server is one OA server:
--
--   public    a server Roblox matchmaking made: the dedicated-style
--             rotation of servers_config.public, listed
--   host      a reserved server made by Start Server, with its creator's
--             settings; listed when its "Public Server" toggle was on,
--             otherwise reachable by code only. The creator is the host.
--   sp        a reserved server for one player's single player arena
--   private   a reserved server that lost its settings: the rotation, unlisted
--   studio    no TeleportService / MemoryStore (Studio, rbx-native's own
--             runtime, lune): the single-server behaviour of before
--
-- Clients talk to it through ReplicatedStorage.OANet.Servers (a
-- RemoteFunction: list, local, lookup, join, host, sp, apply, rcon,
-- favorites, favsave) and hear teleport failures on OANet.ServersNote.
-- Services come in through `env` so the tests can stub them.
local S = require("../../shared/net/servers")
local Registry = require("./servers_registry")
local Config = require("./servers_config")

local CVAR_SERVERINFO, CVAR_ROM = 4, 64

local Servers = {}
Servers.__index = Servers
Servers.Config = Config

-- the Roblox side of env (services, ids, clock); nil fields mean "not live"
function Servers.fromGame()
	local RunService = game:GetService("RunService")
	local studio = true
	pcall(function()
		studio = RunService:IsStudio()
	end)
	local live = not studio and game.PlaceId ~= 0 and game.JobId ~= ""
	local env: any = {
		live = live,
		placeId = game.PlaceId,
		jobId = game.JobId,
		privateServerId = game.PrivateServerId,
		Players = game:GetService("Players"),
		now = os.clock,
		wait = task.wait,
		spawn = task.spawn,
		delay = task.delay,
	}
	if live then
		env.TeleportService = game:GetService("TeleportService")
		env.MemoryStoreService = game:GetService("MemoryStoreService")
		local DataStoreService = game:GetService("DataStoreService")
		env.favorites = DataStoreService:GetDataStore(Config.favorites.store)
		env.budget = function(): number
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync)
		end
		env.ascending = Enum.SortDirection.Ascending
		env.retryable = function(result: any): boolean
			return result == Enum.TeleportResult.Flooded or result == Enum.TeleportResult.Failure
		end
		env.newTeleportOptions = function()
			return Instance.new("TeleportOptions")
		end
		local TextService = game:GetService("TextService")
		-- nil when it fails (the user must be in this server)
		env.filter = function(text: string, userId: number): string?
			local ok, out = pcall(function()
				return TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
					:GetNonChatStringForBroadcastAsync()
			end)
			return if ok then out else nil
		end
		env.bindToClose = function(fn)
			game:BindToClose(fn)
		end
	end
	return env
end

function Servers.new(env: any, Game: any, mapExists: (string) -> boolean)
	local self = setmetatable({
		env = env,
		Game = Game,
		mapExists = mapExists,
		kind = "studio",
		code = S.code(if env.privateServerId ~= "" then env.privateServerId elseif env.jobId ~= "" then env.jobId else "studio"),
		public = false,
		host = nil :: number?,
		access = nil :: string?,
		buckets = {},
		favPending = {},
		pending = {},
		favLast = {},
		hostnameSource = nil :: string?,
	}, Servers)
	-- the join code, shown by the in-game SERVER INFO menu (registered
	-- before Game.Init so it is among the 16 lines that menu shows)
	Game.Cvar.Get("sv_code", self.code, bit32.bor(CVAR_SERVERINFO, CVAR_ROM))
	if env.live then
		self.registry = Registry.new(env.MemoryStoreService:GetSortedMap(Config.registry.map), env.ascending, env.now, Config.registry)
		self.reservedMap = env.MemoryStoreService:GetSortedMap(Config.reserved.map)
	end
	return self
end

-- the public servers' console text: the rotation as q3 dedicated configs
-- wrote it (d1 .. dN, each setting `nextmap` to the next)
function Servers.rotationText(pub: any, mapExists: (string) -> boolean, fallback: string): string
	local slots = {}
	for _, r in pub.rotation do
		if mapExists(r.map) then
			table.insert(slots, r)
		end
	end
	if #slots == 0 then
		slots = { { gametype = 0, map = fallback, fraglimit = 20, timelimit = 10 } }
	end
	local lines = {
		('set sv_hostname "%s"'):format(pub.hostname),
		("set sv_maxclients %d"):format(pub.maxclients),
		"set bot_enable 1",
		("set bot_minplayers %d"):format(pub.bot_minplayers),
		("set g_spSkill %d"):format(pub.botskill),
	}
	for i, r in slots do
		table.insert(
			lines,
			('set d%d "g_gametype %d; fraglimit %d; timelimit %d; capturelimit %d; map %s; set nextmap vstr d%d"'):format(
				i,
				r.gametype,
				r.fraglimit or 0,
				r.timelimit or 0,
				r.capturelimit or 0,
				r.map,
				i % #slots + 1
			)
		)
	end
	table.insert(lines, "vstr d1")
	return table.concat(lines, "\n")
end

-- A reserved server's settings: written by the server that reserved it
-- (trusted), or, if that read fails, the TeleportData its first player
-- brought (checked like any client input; that player is then the host).
function Servers:arrival(): any?
	local env = self.env
	local ok, rec = pcall(function()
		return self.reservedMap:GetAsync(self.code)
	end)
	if ok and type(rec) == "table" then
		local spec = S.validateSpec(rec.spec, self.mapExists)
		if spec then
			-- every start keeps the code working for another `expiry`
			pcall(function()
				self.reservedMap:SetAsync(self.code, rec, Config.reserved.expiry)
			end)
			return { spec = spec, host = tonumber(rec.host), access = if type(rec.access) == "string" then rec.access else nil, trusted = true }
		end
	end
	local deadline = env.now() + Config.reserved.arrivalWait
	while env.now() < deadline do
		local p = env.Players:GetPlayers()[1]
		if p then
			local data = p:GetJoinData()
			local td = data and data.TeleportData
			local spec = type(td) == "table" and S.validateSpec(td.spec, self.mapExists)
			if spec then
				return { spec = spec, host = p.UserId, access = if type(td.access) == "string" then td.access else nil }
			end
			return nil
		end
		env.wait(0.25)
	end
	return nil
end

-- Decides what this server is and returns the console text to start it
-- with. `startup` is the place's Startup attribute (dev playtests), used
-- by public and Studio servers when set.
function Servers:Boot(opts: { maps: { string }, startup: string? }): string
	local env = self.env
	local first = opts.maps[1] or "oa_dm1"
	local startup = if opts.startup ~= nil and opts.startup ~= "" then opts.startup else nil
	local text
	if not env.live then
		self.kind = "studio"
		text = startup or ("map " .. first)
	elseif env.privateServerId ~= "" then
		local rec = self:arrival()
		if rec then
			self.kind, self.host, self.access, self.public = rec.spec.kind, rec.host, rec.access, rec.spec.public
			if rec.trusted then
				self.hostnameShown = rec.spec.hostname -- filtered when it was reserved
			end
			text = S.startupText(rec.spec)
		else
			self.kind = "private"
			text = Servers.rotationText(Config.public, self.mapExists, first)
		end
	else
		self.kind, self.public = "public", true
		text = startup or Servers.rotationText(Config.public, self.mapExists, first)
	end
	return text
end

-- this server's registry entry
function Servers:entry(): any
	local SV, Cvar = self.Game.SV, self.Game.Cvar
	local max = Cvar.VariableIntegerValue("sv_maxclients")
	local clients, bots = 0, 0
	for i = 0, max - 1 do
		local cl = SV.svs.clients[i]
		if cl and cl.state >= SV.CS_CONNECTED then
			clients += 1
			if cl.isBot then
				bots += 1
			end
		end
	end
	return {
		code = self.code,
		job = self.env.jobId,
		place = self.env.placeId,
		access = self.access,
		kind = self.kind,
		hostname = self:hostname(),
		map = Cvar.VariableString("mapname"),
		gametype = Cvar.VariableIntegerValue("g_gametype"),
		clients = clients,
		bots = bots,
		maxclients = max,
		reserved = self.env.privateServerId ~= "",
		public = self.public,
	}
end

-- sv_hostname as others may see it: a host's text goes through Roblox's
-- filter (again whenever it changes, e.g. over rcon)
function Servers:hostname(): string
	local Cvar = self.Game.Cvar
	local name = Cvar.VariableString("sv_hostname")
	if self.host == nil or name == self.hostnameShown then
		return name
	end
	local shown = if self.env.filter then self.env.filter(name, self.host) else name
	if shown == nil then
		return "" -- not filtered yet (the host hasn't arrived): try again next time
	end
	self.hostnameShown = shown
	if shown ~= name then
		Cvar.Set("sv_hostname", shown)
	end
	return shown
end

function Servers:heartbeat()
	if self.registry and self.kind ~= "sp" then
		self.registry:heartbeat(self:entry())
	end
end

-- per player: a bucket of 30 calls refilling 5 a second
function Servers:allow(player: any, cost: number): boolean
	local now = self.env.now()
	local b = self.buckets[player.UserId] or { n = 30, t = now }
	b.n = math.min(30, b.n + (now - b.t) * 5)
	b.t = now
	self.buckets[player.UserId] = b
	if b.n < cost then
		return false
	end
	b.n -= cost
	return true
end

local function arrivalData(kind: string, raw: any): any
	local a = S.validateArrival(raw)
	return {
		oa = 1,
		kind = kind,
		cvars = if a then a.cvars else {},
		team = if a then a.team else nil,
		map = if a then a.map else nil,
		shot = if a then a.shot else nil,
	}
end

function Servers:teleport(player: any, placeId: number, data: any, set: (any) -> ()): (boolean, string?)
	local env = self.env
	local opts = env.newTeleportOptions()
	set(opts)
	opts:SetTeleportData(data)
	local ok, err = pcall(function()
		env.TeleportService:TeleportAsync(placeId, { player }, opts)
	end)
	-- kept so TeleportInitFailed can send the very same teleport again
	self.pending[player.UserId] = if ok then { placeId = placeId, opts = opts, tries = 0 } else nil
	return ok, if ok then nil else tostring(err)
end

-- TeleportInitFailed: a retryable result is sent again (after a growing
-- pause) up to Config.teleport.retries times; anything else, or the last
-- failure, goes to the player (notify) so its loading screen can go.
function Servers:teleportFailed(player: any, result: any, message: any, notify: (any, string) -> ())
	local env = self.env
	local uid = player.UserId
	local p = self.pending[uid]
	if p == nil or p.tries >= Config.teleport.retries or not env.retryable(result) then
		self.pending[uid] = nil
		notify(player, tostring(message))
		return
	end
	p.tries += 1
	env.delay(Config.teleport.backoff * 2 ^ (p.tries - 1), function()
		if self.pending[uid] ~= p then
			return
		end
		local ok, err = pcall(function()
			env.TeleportService:TeleportAsync(p.placeId, { player }, p.opts)
		end)
		if not ok then
			self.pending[uid] = nil
			notify(player, tostring(err))
		end
	end)
end

function Servers:selfEntry(): any
	local e = S.publicEntry(self:entry())
	e.here = true
	return e
end

-- the listing clients get: public entries, minus SP servers, plus this one
function Servers:listing(): { any }
	local out = {}
	if self.registry then
		for _, e in self.registry:list() do
			if e.public and e.kind ~= "sp" and e.code ~= self.code then
				table.insert(out, S.publicEntry(e))
			end
		end
	end
	return out
end

local RCON_COMMANDS = {
	addbot = true,
	kick = true,
	clientkick = true,
	kicknum = true,
	map_restart = true,
	map = true,
	vstr = true,
	forceteam = true,
	status = true,
	serverinfo = true,
}
local RCON_CVARS = { g_gametype = true, sv_hostname = true, bot_minplayers = true, bot_enable = true, g_doWarmup = true }

-- OA's rcon for the host, limited to what the menus and a server admin
-- need (no `say`: text others see must go through Roblox's filter)
function Servers:rconAllowed(text: string): boolean
	for piece in string.gmatch(text, "[^;\n]+") do
		local first, second = string.match(piece, "^%s*(%S+)%s*(%S*)")
		if first ~= nil then
			first = string.lower(first)
			local cvar = if first == "set" then string.lower(second) else first
			if not (RCON_COMMANDS[first] or RCON_CVARS[cvar] or S.HOST_CVARS[cvar] or (first == "spmap" and self.kind == "sp") or (cvar == "g_spskill" and self.kind == "sp")) then
				return false
			end
		end
	end
	return true
end

function Servers:reserve(player: any, raw: any, arrival: any): (boolean, string?)
	local env = self.env
	local spec, why = S.validateSpec(raw, self.mapExists)
	if not spec then
		return false, why
	end
	if spec.hostname ~= "" and env.filter then
		spec.hostname = env.filter(spec.hostname, player.UserId) or ""
	end
	local ok, access, psid = pcall(function()
		return env.TeleportService:ReserveServer(env.placeId)
	end)
	if not ok then
		return false, tostring(access)
	end
	pcall(function()
		self.reservedMap:SetAsync(S.code(psid), { spec = spec, host = player.UserId, access = access }, Config.reserved.expiry)
	end)
	local data = arrivalData(spec.kind, arrival)
	data.spec, data.access, data.map = spec, access, spec.map
	local sent, err = self:teleport(player, env.placeId, data, function(o)
		o.ReservedServerAccessCode = access
	end)
	return sent, if sent then S.code(psid) else err
end

function Servers:join(player: any, raw: any, arrival: any): (boolean, string?)
	local code = S.parseCode(raw)
	if not code then
		return false, "Bad server code"
	end
	if code == self.code then
		return true, "here"
	end
	if not self.registry then
		return false, "Only this server is available here"
	end
	local e = self.registry:lookup(code)
	if type(e) ~= "table" then
		-- a reserved server nobody is on: its access code starts it again,
		-- with the settings it was made with
		local ok, rec = pcall(function()
			return self.reservedMap:GetAsync(code)
		end)
		if ok and type(rec) == "table" and type(rec.spec) == "table" and rec.spec.kind == "host" and type(rec.access) == "string" then
			e = { reserved = true, access = rec.access, place = self.env.placeId, map = rec.spec.map }
		end
	end
	if type(e) ~= "table" or e.kind == "sp" then
		return false, "Server not found"
	end
	if e.reserved and type(e.access) ~= "string" then
		return false, "Server not found"
	end
	local data = arrivalData("join", arrival)
	if type(e.map) == "string" and S.validateArrival({ oa = 1, kind = "join", map = e.map }).map then
		data.map = string.lower(e.map)
	end
	return self:teleport(player, e.place, data, function(o)
		if e.reserved then
			o.ReservedServerAccessCode = e.access
		else
			o.ServerInstanceId = e.job
		end
	end)
end

function Servers:loadFavorites(player: any): { string }
	local out = {}
	local store = self.env.favorites
	if store then
		local ok, v = pcall(function()
			return store:GetAsync("u" .. player.UserId)
		end)
		if ok and type(v) == "table" then
			for _, c in v do
				local code = S.parseCode(c)
				if code and #out < Config.favorites.max then
					table.insert(out, code)
				end
			end
		end
	end
	return out
end

-- writes a player's pending favorites if the interval and the DataStore
-- budget allow; otherwise they wait for the next try
function Servers:flushFavorites(userId: number, force: boolean?): boolean
	local env = self.env
	local codes = self.favPending[userId]
	if codes == nil or env.favorites == nil then
		return true
	end
	local last = self.favLast[userId] or -math.huge
	if not force and env.now() - last < Config.favorites.minInterval then
		return false
	end
	if env.budget() < Config.favorites.minBudget then
		return false
	end
	self.favLast[userId] = env.now()
	local ok = pcall(function()
		env.favorites:SetAsync("u" .. userId, codes, { userId })
	end)
	if ok then
		self.favPending[userId] = nil
	end
	return ok
end

-- one RemoteFunction call
function Servers:handle(player: any, op: any, arg: any, arrival: any): any
	if type(op) ~= "string" or not self:allow(player, if op == "host" or op == "sp" then 10 else 1) then
		return { ok = false, err = "Too many requests" }
	end
	local isHost = self.host ~= nil and player.UserId == self.host
	if op == "list" then
		return { ok = true, entries = self:listing(), self = self:selfEntry() }
	elseif op == "local" then
		-- this server, and the public ones friends are on (their JobIds)
		local out = { self:selfEntry() }
		if type(arg) == "table" and self.registry then
			local jobs = {}
			for _, j in arg do
				if type(j) == "string" then
					jobs[j] = true
				end
			end
			for _, e in self.registry:list() do
				if jobs[e.job] and e.public and e.code ~= self.code then
					table.insert(out, S.publicEntry(e))
				end
			end
		end
		return { ok = true, entries = out }
	elseif op == "lookup" then
		local code = S.parseCode(arg)
		if code == self.code then
			return { ok = true, entry = self:selfEntry() }
		end
		local e = code and self.registry and self.registry:lookup(code)
		if type(e) == "table" and e.kind ~= "sp" then
			return { ok = true, entry = S.publicEntry(e) }
		end
		return { ok = false }
	elseif op == "join" then
		local ok, err = self:join(player, arg, arrival)
		return { ok = ok, err = err }
	elseif op == "host" or op == "sp" then
		if not self.env.live then
			return { ok = false, err = "Teleports need a published place" }
		end
		if type(arg) ~= "table" or arg.kind ~= op then
			return { ok = false, err = "bad request" }
		end
		local ok, res = self:reserve(player, arg, arrival)
		return { ok = ok, err = if ok then nil else res, code = if ok then res else nil }
	elseif op == "apply" then
		-- Start Server / an arena from the host of this server: restart it
		-- with the new settings, as OA's listen server does
		local spec = isHost and S.validateSpec(arg, self.mapExists)
		if not spec or spec.kind ~= (if self.kind == "sp" then "sp" else "host") then
			return { ok = false, err = "Not the host" }
		end
		if spec.kind == "host" then
			self.public = spec.public
		end
		-- through the command buffer the frame loop runs, like ioq3's rcon
		self.Game.Cmd.Cbuf_AddText(S.startupText(spec) .. "\n")
		return { ok = true }
	elseif op == "rcon" then
		if not isHost or type(arg) ~= "string" or #arg > 1024 or not self:rconAllowed(arg) then
			return { ok = false, err = if isHost then "Not allowed" else "Not the host" }
		end
		self.Game.Cmd.Cbuf_AddText(arg .. "\n")
		return { ok = true }
	elseif op == "favorites" then
		return { ok = true, codes = self:loadFavorites(player) }
	elseif op == "favsave" then
		if type(arg) ~= "table" then
			return { ok = false }
		end
		local codes = {}
		for _, c in arg do
			local code = S.parseCode(c)
			if code and #codes < Config.favorites.max then
				table.insert(codes, code)
			end
		end
		self.favPending[player.UserId] = codes
		self.env.delay(Config.favorites.minInterval, function()
			self:flushFavorites(player.UserId)
		end)
		return { ok = true, saved = self:flushFavorites(player.UserId) }
	end
	return { ok = false, err = "bad request" }
end

-- remotes, heartbeat, close; call after Transport.Start
function Servers:Start(remotes: Instance)
	local env = self.env
	remotes:SetAttribute("ServersLive", env.live)
	remotes:SetAttribute("ServersKind", self.kind)
	remotes:SetAttribute("ServersCode", self.code)
	remotes:SetAttribute("ServersHost", self.host or 0)
	local fn = Instance.new("RemoteFunction")
	fn.Name = "Servers"
	fn.OnServerInvoke = function(player, op, arg, arrival)
		return self:handle(player, op, arg, arrival)
	end
	fn.Parent = remotes
	local note = Instance.new("RemoteEvent")
	note.Name = "ServersNote"
	note.Parent = remotes
	env.Players.PlayerRemoving:Connect(function(player)
		self.buckets[player.UserId] = nil
		self.pending[player.UserId] = nil
		self:flushFavorites(player.UserId, true)
	end)
	if not env.live then
		return
	end
	env.TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		self:teleportFailed(player, result, message, function(who, msg)
			note:FireClient(who, "teleportfailed", msg)
		end)
	end)
	env.spawn(function()
		while true do
			self:heartbeat()
			env.wait(Config.registry.heartbeat)
		end
	end)
	env.bindToClose(function()
		for userId in self.favPending do
			self:flushFavorites(userId, true)
		end
		if self.registry and self.kind ~= "sp" then
			self.registry:remove(self.code)
		end
	end)
end

return Servers
