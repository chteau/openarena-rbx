--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/q3_ui/ui_servers2.c (OpenArena 0.8.8, gamecode 9e0f0c0).

-- C lines 1-1085 (up to ArenaServers_StopRefresh); the rest is ui_servers2b.luau.
--[[
=======================================================================

MULTIPLAYER MENU (SERVER BROWSER)

=======================================================================
]]

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot

local MAX_GLOBALSERVERS = 256
local MAX_PINGREQUESTS = 32
local MAX_ADDRESSLENGTH = 64
local MAX_HOSTNAMELENGTH = 31
local MAX_MAPNAMELENGTH = 20
local MAX_LISTBOXITEMS = 256
local MAX_LOCALSERVERS = 124
local MAX_STATUSLENGTH = 64
local MAX_LISTBOXWIDTH = 70





local UIAS_LOCAL = 0
local UIAS_GLOBAL1 = 1
local UIAS_GLOBAL2 = 2
local UIAS_GLOBAL3 = 3
local UIAS_GLOBAL4 = 4
local UIAS_GLOBAL5 = 5
local UIAS_FAVORITES = 6

local SORT_HOST = 0
local SORT_MAP = 1
local SORT_CLIENTS = 2
local SORT_GAME = 3
local SORT_PING = 4
local SORT_HUMANS = 5

local GAMES_ALL = 0
local GAMES_FFA = 1
local GAMES_TEAMPLAY = 2
local GAMES_TOURNEY = 3
local GAMES_CTF = 4
local GAMES_1FCTF = 5
local GAMES_OBELISK = 6
local GAMES_HARVESTER = 7
local GAMES_ELIMINATION = 8
local GAMES_CTF_ELIMINATION = 9
local GAMES_LMS = 10
local GAMES_DOUBLE_D = 11
local GAMES_DOM = 12

U.master_items = {
	[0] = "Local",
	"Internet",
	"Internet(2)",
	"Internet(3)",
	"Internet(4)",
	"Internet(5)",
	"Favorites",
}

U.servertype_items = {
	[0] = "All",
	"Free For All",
	"Team Deathmatch",
	"Tournament",
	"Capture the Flag",
	"One Flag Capture",
	"Overload",
	"Harvester",
	"Elimination",
	"CTF Elimination",
	"Last Man Standing",
	"Double Domination",
	"Domination",
}

U.sortkey_items = {
	[0] = "Server Name",
	"Map Name",
	"Open Player Spots",
	"Game Type",
	"Ping Time",
	"Human Players",
}

U.gamenames = {
	[0] = "DM ", -- deathmatch
	"1v1", -- tournament
	"SP ", -- single player
	"Team DM", -- team deathmatch
	"CTF", -- capture the flag
	"One Flag CTF", -- one flag ctf
	"OverLoad", -- Overload
	"Harvester", -- Harvester
	"Elimination",
	"CTF Elimination",
	"Last Man Standing",
	"Double Domination",
	"Domination", -- Dom replaces Rocket Arena 3
	"Q3F", -- Q3F
	"Urban Terror", -- Urban Terror
	"OSP", -- Orange Smoothie Productions
	"???", -- unknown
}

U.netnames = {
	[0] = "???",
	"IP4",
	"IP6",
	"RBX", -- Roblox: this place's own servers
}

U.quake3worldMessage = "Visit www.openarena.ws - News, Community, Events, Files"

-- GAMES_* filter entry -> the gametype a server must have to be listed
local gametypeFilter = {
	[GAMES_FFA] = C.GT_FFA,
	[GAMES_TEAMPLAY] = C.GT_TEAM,
	[GAMES_TOURNEY] = C.GT_TOURNAMENT,
	[GAMES_CTF] = C.GT_CTF,
	[GAMES_1FCTF] = C.GT_1FCTF,
	[GAMES_OBELISK] = C.GT_OBELISK,
	[GAMES_HARVESTER] = C.GT_HARVESTER,
	[GAMES_ELIMINATION] = C.GT_ELIMINATION,
	[GAMES_CTF_ELIMINATION] = C.GT_CTF_ELIMINATION,
	[GAMES_LMS] = C.GT_LMS,
	[GAMES_DOUBLE_D] = C.GT_DOUBLE_D,
	[GAMES_DOM] = C.GT_DOMINATION,
}

local function atoi(s: string): number
	local n = string.match(s, "^%s*([+-]?%d+)")
	return if n ~= nil then tonumber(n) :: number else 0
end

-- pinglist_t
local function newPing()
	return { adrstr = "", start = 0 }
end

-- servernode_t, zeroed
local function newServernode()
	return {
		adrstr = "",
		hostname = "",
		mapname = "",
		numclients = 0,
		humanclients = 0,
		needPass = false,
		maxclients = 0,
		pingtime = 0,
		gametype = 0,
		gamename = "",
		nettype = 0,
		minPing = 0,
		maxPing = 0,
	}
end

local function newServerlist(n: number)
	local list = {}
	for i = 0, n - 1 do
		list[i] = newServernode()
	end
	return list
end

-- table_t
U.ArenaServers_newServernode = newServernode -- Roblox helper: a zeroed servernode_t

local function newTable()
	return { buff = "", servernode = nil }
end

-- arenaservers_t, zeroed
local function newArenaservers()
	local g = {
		menu = T.menuframework_s(),
		banner = T.menutext_s(),
		master = T.menulist_s(),
		gametype = T.menulist_s(),
		sortkey = T.menulist_s(),
		showfull = T.menuradiobutton_s(),
		showempty = T.menuradiobutton_s(),
		onlyhumans = T.menuradiobutton_s(),
		hideprivate = T.menuradiobutton_s(),
		list = T.menulist_s(),
		mappic = T.menubitmap_s(),
		arrows = T.menubitmap_s(),
		up = T.menubitmap_s(),
		down = T.menubitmap_s(),
		status = T.menutext_s(),
		statusbar = T.menutext_s(),
		remove = T.menubitmap_s(),
		back = T.menubitmap_s(),
		refresh = T.menubitmap_s(),
		specify = T.menubitmap_s(),
		create = T.menubitmap_s(),
		go = T.menubitmap_s(),
		pinglist = {},
		table = {},
		items = {},
		numqueriedservers = 0,
		numservers = nil, -- int *: one of the g_num*servers counters ({value = n})
		serverlist = nil,
		currentping = 0,
		refreshservers = false,
		nextpingtime = 0,
		maxservers = 0,
		refreshtime = 0,
		favoriteaddresses = {},
		numfavoriteaddresses = 0,
	}
	for i = 0, MAX_PINGREQUESTS - 1 do
		g.pinglist[i] = newPing()
	end
	for i = 0, MAX_LISTBOXITEMS - 1 do
		g.table[i] = newTable()
		g.items[i] = ""
	end
	for i = 0, C.MAX_FAVORITESERVERS - 1 do
		g.favoriteaddresses[i] = ""
	end
	return g
end

U.ArenaServers_newArenaservers = newArenaservers -- Roblox helper: a zeroed arenaservers_t
U.g_arenaservers = newArenaservers()

U.g_globalserverlist = newServerlist(MAX_GLOBALSERVERS)
U.g_numglobalservers = { value = 0 }
U.g_localserverlist = newServerlist(MAX_LOCALSERVERS)
U.g_numlocalservers = { value = 0 }
U.g_favoriteserverlist = newServerlist(C.MAX_FAVORITESERVERS)
U.g_numfavoriteservers = { value = 0 }
U.g_servertype = 0
U.g_gametype = 0
U.g_sortkey = 0
U.g_emptyservers = 0
U.g_fullservers = 0

U.g_onlyhumans = 0
U.g_hideprivate = 0

--[[
 *Removes illigal chars but keeps colors
]]
function U.Q_CleanStrWithColor(s: string): string
	local d = {}
	local i = 1
	while i <= #s do
		local c = string.byte(s, i)
		if Q.IsColorString(s, i) then
			table.insert(d, string.char(c))
		elseif c >= 0x20 and c <= 0x7E then
			table.insert(d, string.char(c))
		end
		i += 1
	end
	return table.concat(d)
end

--[[
=================
U.ArenaServers_MaxPing
=================
]]
function U.ArenaServers_MaxPing(): number
	local maxPing = Q.int(trap.Cvar_VariableValue("cl_maxPing"))
	if maxPing < 100 then
		maxPing = 100
	end
	return maxPing
end

--[[
=================
ArenaServers_Compare
=================
]]
function U.ArenaServers_Compare(t1, t2): number
	if U.g_sortkey == SORT_HOST then
		return Q.stricmp(t1.hostname, t2.hostname)
	elseif U.g_sortkey == SORT_MAP then
		return Q.stricmp(t1.mapname, t2.mapname)
	elseif U.g_sortkey == SORT_CLIENTS then
		local f1 = t1.maxclients - t1.numclients
		if f1 < 0 then
			f1 = 0
		end

		local f2 = t2.maxclients - t2.numclients
		if f2 < 0 then
			f2 = 0
		end

		if f1 < f2 then
			return 1
		end
		if f1 == f2 then
			return 0
		end
		return -1
	elseif U.g_sortkey == SORT_HUMANS then
		local f1 = t1.humanclients
		local f2 = t2.humanclients

		if f1 < f2 then
			return 1
		end
		if f1 == f2 then
			return 0
		end
		return -1
	elseif U.g_sortkey == SORT_GAME then
		if t1.gametype < t2.gametype then
			return -1
		end
		if t1.gametype == t2.gametype then
			return 0
		end
		return 1
	elseif U.g_sortkey == SORT_PING then
		-- Roblox: a ping of -1 is "unknown" and sorts after every known ping
		if t1.pingtime == -1 and t2.pingtime ~= -1 then
			return 1
		end
		if t2.pingtime == -1 and t1.pingtime ~= -1 then
			return -1
		end
		if t1.pingtime < t2.pingtime then
			return -1
		end
		if t1.pingtime > t2.pingtime then
			return 1
		end
		return Q.stricmp(t1.hostname, t2.hostname)
	end

	return 0
end

-- Roblox: lets a test pick the key ArenaServers_Compare reads
function U.ArenaServers_SetSortKey(k: number)
	U.g_sortkey = k
end

-- qsort( serverlist, n, sizeof( servernode_t ), ArenaServers_Compare )
function U.ArenaServers_QSort(list, n: number)
	local t = {}
	for i = 0, n - 1 do
		t[i + 1] = list[i]
	end
	table.sort(t, function(a, b)
		return U.ArenaServers_Compare(a, b) < 0
	end)
	for i = 0, n - 1 do
		list[i] = t[i + 1]
	end
end

--[[
=================
U.ArenaServers_Go
=================
]]
function U.ArenaServers_Go()
	local servernode = U.g_arenaservers.table[U.g_arenaservers.list.curvalue].servernode
	if servernode ~= nil then
		-- Roblox: needPass is always 0 here and the password dialog
		-- (UI_SpecifyPasswordMenu) isn't ported, so a private server is
		-- connected to plainly
		trap.Cmd_ExecuteText(C.EXEC_APPEND, Q.va("connect %s\n", servernode.adrstr))
	end
end

--[[
=================
U.ArenaServers_UpdatePicture
=================
]]
function U.ArenaServers_UpdatePicture()
	if U.g_arenaservers.list.numitems == 0 then
		U.g_arenaservers.mappic.generic.name = nil
	else
		local servernodeptr = U.g_arenaservers.table[U.g_arenaservers.list.curvalue].servernode
		U.g_arenaservers.mappic.generic.name = string.sub(Q.va("levelshots/%s.tga", servernodeptr.mapname), 1, 63)
	end

	-- force shader update during draw
	U.g_arenaservers.mappic.shader = 0
end

--[[
=================
	Q_strcpyColor - This function will return the real length of the string if numChars
		len of character data is desired. It looks for color codes and adds 2 to the length
		for each combo found. This is used to make color strings show up correctly in column
		formatted environments. Otherwise, the columns will be off 2 * num of color codes.
=================
]]
-- Returns the filled-in dest string and the length.
function U.Q_strcpyColor(src: string?, numChars: number): (string, number)
	if src == nil then
		return "", 0
	end

	local count, len = 0, 0
	local d = {}
	local i = 1
	local n = #src

	while i <= n and count < numChars do
		if Q.IsColorString(src, i) then
			table.insert(d, string.sub(src, i, i + 1))
			i += 2
			len += 2
			continue
		end
		table.insert(d, string.sub(src, i, i))
		i += 1
		count += 1
		len += 1
	end

	-- Now fill up the end of the string with space characters if needed...
	while count < numChars do
		table.insert(d, " ")
		len += 1
		count += 1
	end
	return table.concat(d), len
end

local function grayed(item, on: boolean)
	if on then
		item.generic.flags = bor(item.generic.flags, C.QMF_GRAYED)
	else
		item.generic.flags = band(item.generic.flags, bnot(C.QMF_GRAYED))
	end
end

--[[
=================
U.ArenaServers_UpdateMenu
=================
]]
function U.ArenaServers_UpdateMenu()
	local g = U.g_arenaservers

	if g.numqueriedservers > 0 then
		-- servers found
		if g.refreshservers and g.currentping <= g.numqueriedservers then
			-- show progress
			g.status.string = string.sub(
				Q.va("%d of %d Arena Servers.", g.currentping, g.numqueriedservers),
				1,
				MAX_STATUSLENGTH - 1
			)
			g.statusbar.string = "Press SPACE to stop"
			U.ArenaServers_QSort(g.serverlist, g.numservers.value)
		else
			-- all servers pinged - enable controls
			grayed(g.master, false)
			grayed(g.gametype, false)
			grayed(g.sortkey, false)
			grayed(g.showempty, false)
			grayed(g.onlyhumans, false)
			grayed(g.hideprivate, false)
			grayed(g.showfull, false)
			grayed(g.list, false)
			grayed(g.refresh, false)
			grayed(g.go, false)

			-- update status bar
			if U.g_servertype >= UIAS_GLOBAL1 and U.g_servertype <= UIAS_GLOBAL5 then
				g.statusbar.string = U.quake3worldMessage
			else
				g.statusbar.string = ""
			end
		end
	else
		-- no servers found
		if g.refreshservers then
			g.status.string = "Scanning For Servers."
			g.statusbar.string = "Press SPACE to stop"

			-- disable controls during refresh
			grayed(g.master, true)
			grayed(g.gametype, true)
			grayed(g.sortkey, true)
			grayed(g.showempty, true)
			grayed(g.onlyhumans, true)
			grayed(g.hideprivate, true)
			grayed(g.showfull, true)
			grayed(g.list, true)
			grayed(g.refresh, true)
			grayed(g.go, true)
		else
			if g.numqueriedservers < 0 then
				g.status.string = "No Response From Master Server."
			else
				g.status.string = "No Servers Found."
			end

			-- update status bar
			if U.g_servertype >= UIAS_GLOBAL1 and U.g_servertype <= UIAS_GLOBAL5 then
				g.statusbar.string = U.quake3worldMessage
			else
				g.statusbar.string = ""
			end

			-- end of refresh - set control state
			grayed(g.master, false)
			grayed(g.gametype, false)
			grayed(g.sortkey, false)
			grayed(g.showempty, false)
			grayed(g.onlyhumans, false)
			grayed(g.hideprivate, false)
			grayed(g.showfull, false)
			grayed(g.list, true)
			grayed(g.refresh, false)
			grayed(g.go, true)
		end

		-- zero out list box
		g.list.numitems = 0
		g.list.curvalue = 0
		g.list.top = 0

		-- update picture
		U.ArenaServers_UpdatePicture()
		return
	end

	-- build list box strings - apply culling filters
	local count = g.numservers.value
	local j = 0
	for i = 0, count - 1 do
		local servernodeptr = g.serverlist[i]
		local tableptr = g.table[j]
		tableptr.servernode = servernodeptr

		-- can only cull valid results
		if U.g_emptyservers == 0 and servernodeptr.numclients == 0 then
			continue
		end

		--If "Show only humans" and "Hide empty server" are enabled hide servers that only have bots
		if U.g_emptyservers == 0 and U.g_onlyhumans ~= 0 and servernodeptr.humanclients == 0 then
			continue
		end

		if U.g_fullservers == 0 and servernodeptr.numclients == servernodeptr.maxclients then
			continue
		end

		local wanted = gametypeFilter[U.g_gametype]
		if wanted ~= nil and servernodeptr.gametype ~= wanted then
			continue
		end

		if U.g_hideprivate ~= 0 and servernodeptr.needPass then
			continue
		end

		local pingColor
		if servernodeptr.pingtime < servernodeptr.minPing then
			pingColor = C.S_COLOR_BLUE
		elseif servernodeptr.maxPing ~= 0 and servernodeptr.pingtime > servernodeptr.maxPing then
			pingColor = C.S_COLOR_BLUE
		elseif servernodeptr.pingtime < 200 then
			pingColor = C.S_COLOR_GREEN
		elseif servernodeptr.pingtime < 400 then
			pingColor = C.S_COLOR_YELLOW
		else
			pingColor = C.S_COLOR_RED
		end

		local b = { "^7" }
		local s = U.Q_strcpyColor(servernodeptr.hostname, 30)
		table.insert(b, s)
		table.insert(b, " ^7")

		s = U.Q_strcpyColor(servernodeptr.mapname, 16)
		table.insert(b, s)
		table.insert(b, " ")

		-- Com_sprintf( b, 8, ... ) then b += 6
		if servernodeptr.maxclients == 0 then
			s = "--/-- " -- no answer, no counts
		elseif U.g_onlyhumans == 0 then
			s = string.sub(Q.va("%2d/%2d ", servernodeptr.numclients, servernodeptr.maxclients), 1, 6)
		else
			s = string.sub(Q.va("%2d/%2d ", servernodeptr.humanclients, servernodeptr.maxclients), 1, 6)
		end
		table.insert(b, s)

		s = U.Q_strcpyColor(servernodeptr.gamename, 8)
		table.insert(b, s)
		table.insert(b, " ")

		s = U.Q_strcpyColor(U.netnames[servernodeptr.nettype], 3)
		table.insert(b, s)
		table.insert(b, " ")

		-- Roblox: a ping of -1 is unknown, shown as "  ?" in white instead of the number
		if servernodeptr.pingtime == -1 then
			s = "^7  ? "
		else
			s = Q.va("%s%3d ", pingColor, servernodeptr.pingtime)
		end
		table.insert(b, string.sub(s, 1, 11))

		tableptr.buff = table.concat(b)
		g.items[j] = tableptr.buff
		j += 1
	end

	g.list.numitems = j
	g.list.curvalue = 0
	g.list.top = 0

	-- update picture
	U.ArenaServers_UpdatePicture()
end

--[[
=================
U.ArenaServers_Remove
=================
]]
function U.ArenaServers_Remove()
	local g = U.g_arenaservers

	if g.list.numitems == 0 then
		return
	end

	-- remove selected item from display list
	-- items are in scattered order due to sort and cull
	-- perform delete on list box contents, resync all lists

	local tableptr = g.table[g.list.curvalue]
	local servernodeptr = tableptr.servernode

	-- find address in master list
	for i = 0, g.numfavoriteaddresses - 1 do
		if Q.stricmp(g.favoriteaddresses[i], servernodeptr.adrstr) == 0 then
			-- delete address from master list
			if i < g.numfavoriteaddresses - 1 then
				-- shift items up
				for k = i, g.numfavoriteaddresses - 2 do
					g.favoriteaddresses[k] = g.favoriteaddresses[k + 1]
				end
			end
			g.numfavoriteaddresses -= 1
			g.favoriteaddresses[g.numfavoriteaddresses] = ""
			break
		end
	end

	-- find address in server list
	for i = 0, U.g_numfavoriteservers.value - 1 do
		if U.g_favoriteserverlist[i] == servernodeptr then
			-- delete address from server list
			if i < U.g_numfavoriteservers.value - 1 then
				-- shift items up
				for k = i, U.g_numfavoriteservers.value - 2 do
					U.g_favoriteserverlist[k] = U.g_favoriteserverlist[k + 1]
				end
			end
			U.g_numfavoriteservers.value -= 1
			U.g_favoriteserverlist[U.g_numfavoriteservers.value] = newServernode()
			break
		end
	end

	g.numqueriedservers = g.numfavoriteaddresses
	g.currentping = g.numfavoriteaddresses
end

--[[
=================
U.ArenaServers_Insert
=================
]]
function U.ArenaServers_Insert(adrstr: string, info: string, pingtime: number)
	local g = U.g_arenaservers

	-- Roblox: -1 is "unknown ping", never slow
	if pingtime ~= -1 and pingtime >= U.ArenaServers_MaxPing() and U.g_servertype ~= UIAS_FAVORITES then
		-- slow global or local servers do not get entered
		return
	end

	local servernodeptr
	if g.numservers.value >= g.maxservers then
		-- list full;
		servernodeptr = g.serverlist[g.numservers.value - 1]
	else
		-- next slot
		servernodeptr = g.serverlist[g.numservers.value]
		g.numservers.value += 1
	end

	servernodeptr.adrstr = Q.strncpyz(adrstr, MAX_ADDRESSLENGTH)

	servernodeptr.hostname = Q.strncpyz(Q.Info_ValueForKey(info, "hostname"), MAX_HOSTNAMELENGTH)
	servernodeptr.hostname = U.Q_CleanStrWithColor(servernodeptr.hostname)
	servernodeptr.hostname = Q.strupr(servernodeptr.hostname)

	servernodeptr.mapname = Q.strncpyz(Q.Info_ValueForKey(info, "mapname"), MAX_MAPNAMELENGTH)
	servernodeptr.mapname = Q.CleanStr(servernodeptr.mapname)
	servernodeptr.mapname = Q.strupr(servernodeptr.mapname)

	servernodeptr.numclients = atoi(Q.Info_ValueForKey(info, "clients"))
	servernodeptr.humanclients = atoi(Q.Info_ValueForKey(info, "g_humanplayers"))
	servernodeptr.needPass = Q.i2b(atoi(Q.Info_ValueForKey(info, "g_needpass")))
	servernodeptr.maxclients = atoi(Q.Info_ValueForKey(info, "sv_maxclients"))
	servernodeptr.pingtime = pingtime
	servernodeptr.minPing = atoi(Q.Info_ValueForKey(info, "minPing"))
	servernodeptr.maxPing = atoi(Q.Info_ValueForKey(info, "maxPing"))

	local s = Q.Info_ValueForKey(info, "nettype")
	local i = 0
	while true do
		if U.netnames[i] == nil then
			servernodeptr.nettype = 0
			break
		elseif Q.stricmp(U.netnames[i], s) == 0 then
			servernodeptr.nettype = i
			break
		end
		i += 1
	end

	servernodeptr.nettype = atoi(Q.Info_ValueForKey(info, "nettype"))

	s = Q.Info_ValueForKey(info, "game")
	i = atoi(Q.Info_ValueForKey(info, "gametype"))
	if i < 0 then
		i = 0
	elseif i > 11 then
		i = 12
	end
	if s ~= "" then
		servernodeptr.gametype = i --//-1;
		servernodeptr.gamename = Q.strncpyz(s, 16)
	else
		servernodeptr.gametype = i
		servernodeptr.gamename = Q.strncpyz(U.gamenames[i], 16)
	end
end

-- Roblox: a server that doesn't answer (a dead join code) is listed by its
-- code and marked "No Response", not as a blank row
function U.ArenaServers_NoResponse(adrstr: string): string
	return Q.Info_SetValueForKey(Q.Info_SetValueForKey("", "hostname", adrstr), "mapname", "No Response")
end

--[[
=================
ArenaServers_InsertFavorites

Insert nonresponsive address book entries into display lists.
=================
]]
function U.ArenaServers_InsertFavorites()
	local g = U.g_arenaservers

	-- resync existing results with new or deleted cvars
	for i = 0, g.numfavoriteaddresses - 1 do
		-- find favorite address in refresh list
		local j = 0
		while j < U.g_numfavoriteservers.value do
			if Q.stricmp(g.favoriteaddresses[i], U.g_favoriteserverlist[j].adrstr) == 0 then
				break
			end
			j += 1
		end

		if j >= U.g_numfavoriteservers.value then
			-- not in list, add it
			U.ArenaServers_Insert(g.favoriteaddresses[i], U.ArenaServers_NoResponse(g.favoriteaddresses[i]), U.ArenaServers_MaxPing())
		end
	end
end

--[[
=================
ArenaServers_LoadFavorites

Load cvar address book entries into local lists.
=================
]]
function U.ArenaServers_LoadFavorites()
	local found = false

	-- copy the old
	local templist = {}
	for i = 0, C.MAX_FAVORITESERVERS - 1 do
		templist[i] = U.g_favoriteserverlist[i]
	end
	local numtempitems = U.g_numfavoriteservers.value

	-- clear the current for sync
	for i = 0, C.MAX_FAVORITESERVERS - 1 do
		U.g_favoriteserverlist[i] = newServernode()
	end
	U.g_numfavoriteservers.value = 0

	-- resync existing results with new or deleted cvars
	for i = 0, C.MAX_FAVORITESERVERS - 1 do
		local adrstr = Q.strncpyz(trap.Cvar_VariableStringBuffer(Q.va("server%d", i + 1)), MAX_ADDRESSLENGTH)
		if adrstr == "" then
			continue
		end

		-- quick sanity check to avoid slow domain name resolving
		-- first character must be numeric
		local c = string.byte(adrstr, 1)
		if c < 48 or c > 57 then
			continue
		end

		-- favorite server addresses must be maintained outside refresh list
		-- this mimics local and global netadr's stored in client
		-- these can be fetched to fill ping list
		U.g_arenaservers.favoriteaddresses[U.g_numfavoriteservers.value] = adrstr

		-- find this server in the old list
		local j = 0
		while j < numtempitems do
			if Q.stricmp(templist[j].adrstr, adrstr) == 0 then
				break
			end
			j += 1
		end

		if j < numtempitems then
			-- found server - add exisiting results
			U.g_favoriteserverlist[U.g_numfavoriteservers.value] = templist[j]
			found = true
		else
			-- add new server
			U.g_favoriteserverlist[U.g_numfavoriteservers.value].adrstr = adrstr
			U.g_favoriteserverlist[U.g_numfavoriteservers.value].pingtime = U.ArenaServers_MaxPing()
		end

		U.g_numfavoriteservers.value += 1
	end

	U.g_arenaservers.numfavoriteaddresses = U.g_numfavoriteservers.value

	if not found then
		-- no results were found, reset server list
		-- list will be automatically refreshed when selected
		U.g_numfavoriteservers.value = 0
	end
end

--[[
=================
U.ArenaServers_StopRefresh
=================
]]
function U.ArenaServers_StopRefresh()
	local g = U.g_arenaservers

	if not g.refreshservers then
		-- not currently refreshing
		return
	end

	g.refreshservers = false

	if U.g_servertype == UIAS_FAVORITES then
		-- nonresponsive favorites must be shown
		U.ArenaServers_InsertFavorites()
	end

	-- final tally
	if g.numqueriedservers >= 0 then
		g.currentping = g.numservers.value
		g.numqueriedservers = g.numservers.value
	end

	-- sort
	U.ArenaServers_QSort(g.serverlist, g.numservers.value)

	U.ArenaServers_UpdateMenu()
end

return U
