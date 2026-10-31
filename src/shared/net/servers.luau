--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
--!strict
-- Not a port: multiplayer on Roblox servers (docs/ARCHITECTURE.md,
-- "Multiplayer on Roblox servers"). What crosses between servers and
-- clients (registry entries, host specs, TeleportData), the short join
-- codes, and the checks both sides run on it. Nothing here touches Roblox.
local S = {}

S.CODE_LEN = 6
S.MAX_HOSTNAME = 31
S.MAX_BOTS = 11
S.GT_SINGLE_PLAYER = 2
S.GT_MAX = 13
S.NETTYPE_RBX = 3 -- ui_servers2's netnames[3]

-- no 0/O, 1/I: codes are read off a screen and typed
local ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

-- FNV-1a, 32 bits (h * 16777619 split so it stays exact in a double)
local function fnv(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return h
end

-- The name a Roblox player plays under, on the server and in the client's
-- name cvar: the display name (moderated by Roblox), or the username when it
-- has characters OA's font lacks.
function S.playerName(displayName: string, username: string): string
	if displayName == "" or string.find(displayName, "[^%w_ ]") then
		return username
	end
	return displayName
end

-- the join code of a server: its JobId (public) or PrivateServerId
-- (reserved). It starts with a digit, as q3_ui's favorites and Specify
-- expect of an address ("first character must be numeric").
function S.code(id: string): string
	local h = fnv(id)
	local out = table.create(S.CODE_LEN)
	for i = 1, S.CODE_LEN do
		local d = h % (if i == 1 then 8 else 32)
		out[i] = string.sub(ALPHABET, d + 1, d + 1)
		h = h // (if i == 1 then 8 else 32)
	end
	return table.concat(out)
end

-- what a player typed ("abc234", or "ABC234:27960" from Specify's port
-- field) as a code, or nil
function S.parseCode(s: any): string?
	if type(s) ~= "string" then
		return nil
	end
	local c = string.upper(string.match(s, "^%s*([^:%s]*)") or "")
	if #c ~= S.CODE_LEN or string.find(c, "[^2-9A-HJ-NP-Z]") or not string.find(c, "^[2-9]") then
		return nil
	end
	return c
end

local function cleanText(s: any, max: number): string?
	if type(s) ~= "string" then
		return nil
	end
	return string.sub((string.gsub(s, '[%c\\;"]', "")), 1, max)
end

local function int(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v then
		return nil
	end
	return math.clamp(math.floor(v), lo, hi)
end

-- the cvars ServerOptions_Start (and the start server page) set, with the
-- ranges the game accepts
S.HOST_CVARS = {
	sv_maxclients = { 1, 12 },
	timelimit = { 0, 999 },
	fraglimit = { 0, 999 },
	capturelimit = { 0, 999 },
	g_friendlyfire = { 0, 1 },
	g_instantgib = { 0, 2 },
	g_rockets = { 0, 1 },
	g_lms_mode = { 0, 3 },
	elimination_ctf_oneway = { 0, 1 },
	pmove_fixed = { 0, 1 },
	pmove_msec = { 8, 33 },
	pmove_float = { 0, 1 },
	g_autonextmap = { 0, 1 },
}
-- the ones UI_SPArena_Start and the skill menu set
S.SP_CVARS = {
	g_spSkill = { 1, 5 },
}

-- the single player ladder q3config.cfg keeps (ui_main.luau's g_spScores1-5,
-- g_spAwards, g_spVideos), saved per user like the favorites
S.PROGRESS_CVARS = { "g_spScores1", "g_spScores2", "g_spScores3", "g_spScores4", "g_spScores5", "g_spAwards", "g_spVideos" }

function S.validateProgress(raw: any): { [string]: string }?
	if type(raw) ~= "table" then
		return nil
	end
	local out = {}
	for _, name in S.PROGRESS_CVARS do
		local v = raw[name]
		if type(v) == "string" and #v <= 256 and not string.find(v, "[%c]") then
			out[name] = v
		end
	end
	return out
end

export type Bot = { name: string, skill: number, team: string? }
export type Spec = {
	kind: string, -- "host" (Start Server) or "sp" (a single player arena)
	gametype: number,
	map: string,
	hostname: string,
	public: boolean,
	cvars: { [string]: number },
	bots: { Bot },
}

-- q3_ui's start server menu writes "Red" / "Blue"
local function team(v: any): string?
	local t = if type(v) == "string" then string.lower(v) else nil
	if t == "red" or t == "blue" then
		return t
	end
	return nil
end

-- A Start Server / single player request as it came off the wire (from a
-- client, or from TeleportData), checked: nil and a reason if unusable.
-- mapExists says whether the place carries the map.
function S.validateSpec(raw: any, mapExists: (string) -> boolean): (Spec?, string?)
	if type(raw) ~= "table" then
		return nil, "bad request"
	end
	local kind = raw.kind
	if kind ~= "host" and kind ~= "sp" then
		return nil, "bad request"
	end
	local map = if type(raw.map) == "string" then string.lower(raw.map) else ""
	if #map > 64 or not string.match(map, "^[%w_]+$") or not mapExists(map) then
		return nil, "unknown map"
	end
	local gametype = if kind == "sp" then S.GT_SINGLE_PLAYER else int(raw.gametype, 0, S.GT_MAX - 1)
	if gametype == nil then
		return nil, "bad gametype"
	end
	local cvars = {}
	local allowed = if kind == "sp" then S.SP_CVARS else S.HOST_CVARS
	if type(raw.cvars) == "table" then
		for name, range in allowed do
			cvars[name] = int(raw.cvars[name], range[1], range[2])
		end
	end
	local bots = {}
	if kind == "host" and type(raw.bots) == "table" then
		for _, b in raw.bots do
			if #bots >= S.MAX_BOTS then
				break
			end
			if type(b) == "table" and type(b.name) == "string" and #b.name <= 32 and string.match(b.name, "^[%w_][%w_%-]*$") then
				table.insert(bots, { name = b.name, skill = int(b.skill, 1, 5) or 3, team = team(b.team) })
			end
		end
	end
	return {
		kind = kind,
		gametype = gametype,
		map = map,
		hostname = cleanText(raw.hostname, S.MAX_HOSTNAME) or "",
		public = kind == "host" and raw.public == true,
		cvars = cvars,
		bots = bots,
	}
end

-- The server console text that applies a spec on arrival: the cvars the
-- menu would have set on a listen server, then its map and addbot lines.
function S.startupText(spec: Spec): string
	local lines = {}
	local names = {}
	for name in spec.cvars do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		table.insert(lines, ("set %s %d"):format(name, spec.cvars[name]))
	end
	if spec.kind == "sp" then
		table.insert(lines, "spmap " .. spec.map)
		return table.concat(lines, "\n")
	end
	table.insert(lines, ("set g_gametype %d"):format(spec.gametype))
	if spec.hostname ~= "" then
		table.insert(lines, ('set sv_hostname "%s"'):format(spec.hostname))
	end
	-- bots on, as OA's default: the host may add some later (ADD BOTS)
	table.insert(lines, "set bot_enable 1")
	table.insert(lines, "map " .. spec.map)
	for _, b in spec.bots do
		table.insert(lines, if b.team then ("addbot %s %d %s"):format(b.name, b.skill, b.team) else ("addbot %s %d"):format(b.name, b.skill))
	end
	return table.concat(lines, "\n")
end

-- TeleportData a client brings: { oa = 1, kind = "join" | "host" | "sp",
-- cvars = { name = value }, team = "red" | "blue" | nil, map = "oa_dm1" | nil,
-- shot = "rbxassetid://123" | nil } (its archived cvars, so name, model,
-- colours and single player progress survive the teleport; the team the
-- start server menu picked; the map and levelshot the loading screen shows
-- if the teleport's own can't be carried). Checked: nil if not ours.
S.MAX_ARRIVAL_CVARS = 512
local function arrivalMap(v: any): string?
	return if type(v) == "string" and #v <= 64 and string.match(v, "^[%w_%-]+$") then string.lower(v) else nil
end

local function arrivalShot(v: any): string?
	return if type(v) == "string" and #v <= 40 and string.match(v, "^rbxassetid://%d+$") then v else nil
end

function S.validateArrival(raw: any): { kind: string, cvars: { [string]: string }, team: string?, map: string?, shot: string? }?
	if type(raw) ~= "table" or raw.oa ~= 1 then
		return nil
	end
	local kind = raw.kind
	if kind ~= "join" and kind ~= "host" and kind ~= "sp" then
		return nil
	end
	local cvars = {}
	local n = 0
	if type(raw.cvars) == "table" then
		for name, value in raw.cvars do
			if n >= S.MAX_ARRIVAL_CVARS then
				break
			end
			if type(name) == "string" and #name <= 32 and string.match(name, "^[%a_][%w_]*$") and type(value) == "string" and #value <= 256 and not string.find(value, "[%c]") then
				cvars[name] = value
				n += 1
			end
		end
	end
	return { kind = kind, cvars = cvars, team = team(raw.team), map = arrivalMap(raw.map), shot = arrivalShot(raw.shot) }
end

-- A registry entry (servers_registry.luau) as clients see it: the access
-- code of a reserved server never leaves the servers.
export type Entry = {
	code: string,
	hostname: string,
	map: string,
	gametype: number,
	clients: number,
	bots: number,
	maxclients: number,
	reserved: boolean,
	public: boolean,
	here: boolean?, -- the viewer's own server
}
function S.publicEntry(e: any): Entry
	return {
		code = e.code,
		hostname = e.hostname,
		map = e.map,
		gametype = e.gametype,
		clients = e.clients,
		bots = e.bots,
		maxclients = e.maxclients,
		reserved = e.reserved,
		public = e.public,
	}
end

-- the info string ui_servers2 reads from a ping answer
function S.infoString(e: Entry): string
	return ("\\hostname\\%s\\mapname\\%s\\clients\\%d\\g_humanplayers\\%d\\sv_maxclients\\%d\\gametype\\%d\\nettype\\%d\\g_needpass\\0"):format(
		e.hostname,
		e.map,
		e.clients,
		math.max(0, e.clients - e.bots),
		e.maxclients,
		e.gametype,
		S.NETTYPE_RBX
	)
end

-- globalservers' filter words (the master protocol's): a gametype keyword,
-- "empty" and "full" to include those (left out by default)
local GAMETYPE_WORDS = { ffa = 0, tourney = 1, team = 3, ctf = 4, elimination = 8, ctfelimination = 9, lms = 10, dd = 11, dom = 12 }
function S.filter(entries: { Entry }, words: { string }): { Entry }
	local gametype, empty, full = nil, false, false
	for _, w in words do
		w = string.lower(w)
		if GAMETYPE_WORDS[w] then
			gametype = GAMETYPE_WORDS[w]
		elseif w == "empty" then
			empty = true
		elseif w == "full" then
			full = true
		end
	end
	local out = {}
	for _, e in entries do
		-- the server you're on is always there, listed or not
		if (e.public or e.here) and (gametype == nil or e.gametype == gametype) and (empty or e.clients > 0) and (full or e.clients < e.maxclients) then
			table.insert(out, e)
		end
	end
	return out
end

return S
