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

--[[
ui_servers2.c, second part: ArenaServers_DoRefresh to the end (C lines 1087-1850).
The first part is ui_servers2.luau (C lines 1-1085). Every function and file-scope
variable lives in U under its C name so the two parts can reach each other.
]]

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot

local MAX_PINGREQUESTS = 32
local MAX_LOCALSERVERS = 124
local MAX_GLOBALSERVERS = 256
local MAX_LISTBOXITEMS = 256
local MAX_LISTBOXWIDTH = 70

local ART_BACK0 = "menu/art_blueish/back_0"
local ART_BACK1 = "menu/art_blueish/back_1"
local ART_CREATE0 = "menu/art_blueish/create_0"
local ART_CREATE1 = "menu/art_blueish/create_1"
local ART_SPECIFY0 = "menu/art_blueish/specify_0"
local ART_SPECIFY1 = "menu/art_blueish/specify_1"
local ART_REFRESH0 = "menu/art_blueish/refresh_0"
local ART_REFRESH1 = "menu/art_blueish/refresh_1"
local ART_CONNECT0 = "menu/art_blueish/fight_0"
local ART_CONNECT1 = "menu/art_blueish/fight_1"
local ART_ARROWS0 = "menu/art_blueish/arrows_vert_0"
local ART_ARROWS_UP = "menu/art_blueish/arrows_vert_top"
local ART_ARROWS_DOWN = "menu/art_blueish/arrows_vert_bot"
local ART_UNKNOWNMAP = "menu/art_blueish/unknownmap"
local ART_REMOVE0 = "menu/art_blueish/delete_0"
local ART_REMOVE1 = "menu/art_blueish/delete_1"

local ID_MASTER = 10
local ID_GAMETYPE = 11
local ID_SORTKEY = 12
local ID_SHOW_FULL = 13
local ID_SHOW_EMPTY = 14

local ID_LIST = 15
local ID_SCROLL_UP = 16
local ID_SCROLL_DOWN = 17
local ID_BACK = 18
local ID_REFRESH = 19
local ID_SPECIFY = 20
local ID_CREATE = 21
local ID_CONNECT = 22
local ID_REMOVE = 23

--Beta 23
local ID_ONLY_HUMANS = 24
local ID_HIDE_PRIVATE = 25

local UIAS_LOCAL = 0
local UIAS_GLOBAL1 = 1
local UIAS_GLOBAL5 = 5
local UIAS_FAVORITES = 6

local GAMES_FFA = 1
local GAMES_TEAMPLAY = 2
local GAMES_TOURNEY = 3
local GAMES_CTF = 4
local GAMES_ELIMINATION = 8
local GAMES_CTF_ELIMINATION = 9
local GAMES_LMS = 10
local GAMES_DOUBLE_D = 11
local GAMES_DOM = 12

--[[
=================
ArenaServers_DoRefresh
=================
]]
function U.ArenaServers_DoRefresh()
	local g = U.g_arenaservers

	if U.uis.realtime < g.refreshtime then
		if U.g_servertype ~= UIAS_FAVORITES then
			if U.g_servertype == UIAS_LOCAL then
				if trap.LAN_GetServerCount(U.g_servertype) == 0 then
					return
				end
			end
			if trap.LAN_GetServerCount(U.g_servertype) < 0 then
				-- still waiting for response
				return
			end
		end
	end

	if U.uis.realtime < g.nextpingtime then
		-- wait for time trigger
		return
	end

	-- trigger at 10Hz intervals
	g.nextpingtime = U.uis.realtime + 10

	-- process ping results
	local maxPing = U.ArenaServers_MaxPing()
	for i = 0, MAX_PINGREQUESTS - 1 do
		local adrstr, time = trap.LAN_GetPing(i)
		if adrstr == "" then
			-- ignore empty or pending pings
			continue
		end

		-- find ping result in our local list
		local j = 0
		while j < MAX_PINGREQUESTS do
			if Q.stricmp(adrstr, g.pinglist[j].adrstr) == 0 then
				break
			end
			j += 1
		end

		if j < MAX_PINGREQUESTS then
			-- found it
			if time == 0 then
				time = U.uis.realtime - g.pinglist[j].start
				if time < maxPing then
					-- still waiting
					continue
				end
			end

			local info
			if time > maxPing then
				-- stale it out
				info = ""
				time = maxPing
			else
				info = trap.LAN_GetPingInfo(i)
			end

			-- insert ping results
			U.ArenaServers_Insert(adrstr, info, time)

			-- clear this query from internal list
			g.pinglist[j].adrstr = ""
		end

		-- clear this query from external list
		trap.LAN_ClearPing(i)
	end

	-- get results of servers query
	-- counts can increase as servers respond
	if U.g_servertype == UIAS_FAVORITES then
		g.numqueriedservers = g.numfavoriteaddresses
	else
		g.numqueriedservers = trap.LAN_GetServerCount(U.g_servertype)
	end

	--	if (g_arenaservers.numqueriedservers > g_arenaservers.maxservers)
	--		g_arenaservers.numqueriedservers = g_arenaservers.maxservers;

	-- send ping requests in reasonable bursts
	-- iterate ping through all found servers
	local i = 0
	while i < MAX_PINGREQUESTS and g.currentping < g.numqueriedservers do
		if trap.LAN_GetPingQueueCount() >= MAX_PINGREQUESTS then
			-- ping queue is full
			break
		end

		-- find empty slot
		local j = 0
		while j < MAX_PINGREQUESTS do
			if g.pinglist[j].adrstr == "" then
				break
			end
			j += 1
		end

		if j >= MAX_PINGREQUESTS then
			-- no empty slots available yet - wait for timeout
			break
		end

		-- get an address to ping
		local adrstr
		if U.g_servertype == UIAS_FAVORITES then
			adrstr = g.favoriteaddresses[g.currentping]
		else
			adrstr = trap.LAN_GetServerAddressString(U.g_servertype, g.currentping)
		end

		g.pinglist[j].adrstr = adrstr
		g.pinglist[j].start = U.uis.realtime

		trap.Cmd_ExecuteText(C.EXEC_NOW, Q.va("ping %s\n", adrstr))

		-- advance to next server
		g.currentping += 1
		i += 1
	end

	if trap.LAN_GetPingQueueCount() == 0 then
		-- all pings completed
		U.ArenaServers_StopRefresh()
		return
	end

	-- update the user interface with ping status
	U.ArenaServers_UpdateMenu()
end

--[[
=================
ArenaServers_StartRefresh
=================
]]
function U.ArenaServers_StartRefresh()
	local g = U.g_arenaservers

	for i = 0, g.maxservers - 1 do
		g.serverlist[i] = U.ArenaServers_newServernode()
	end

	for i = 0, MAX_PINGREQUESTS - 1 do
		g.pinglist[i].adrstr = ""
		trap.LAN_ClearPing(i)
	end

	g.refreshservers = true
	g.currentping = 0
	g.nextpingtime = 0
	g.numservers.value = 0
	g.numqueriedservers = 0

	-- allow max 5 seconds for responses
	g.refreshtime = U.uis.realtime + 5000

	-- place menu in zeroed state
	U.ArenaServers_UpdateMenu()

	if U.g_servertype == UIAS_LOCAL then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "localservers\n")
		return
	end

	if U.g_servertype >= UIAS_GLOBAL1 and U.g_servertype <= UIAS_GLOBAL5 then
		local myargs
		local gt = g.gametype.curvalue
		if gt == GAMES_FFA then
			myargs = " ffa"
		elseif gt == GAMES_TEAMPLAY then
			myargs = " team"
		elseif gt == GAMES_TOURNEY then
			myargs = " tourney"
		elseif gt == GAMES_CTF then
			myargs = " ctf"
		elseif gt == GAMES_ELIMINATION then
			myargs = " elimination"
		elseif gt == GAMES_CTF_ELIMINATION then
			myargs = " ctfelimination"
		elseif gt == GAMES_LMS then
			myargs = " lms"
		elseif gt == GAMES_DOUBLE_D then
			myargs = " dd"
		elseif gt == GAMES_DOM then
			myargs = " dom"
		else -- default, GAMES_ALL
			myargs = ""
		end

		if U.g_emptyservers ~= 0 then
			myargs ..= " empty"
		end

		if U.g_fullservers ~= 0 then
			myargs ..= " full"
		end

		local protocol = trap.Cvar_VariableStringBuffer("debug_protocol")
		if #protocol ~= 0 then
			trap.Cmd_ExecuteText(
				C.EXEC_APPEND,
				Q.va("globalservers %d %s%s\n", U.g_servertype - 1, protocol, myargs)
			)
		else
			trap.Cmd_ExecuteText(
				C.EXEC_APPEND,
				Q.va("globalservers %d %d%s\n", U.g_servertype - 1, Q.int(trap.Cvar_VariableValue("protocol")), myargs)
			)
		end
	end
end

--[[
=================
ArenaServers_SaveChanges
=================
]]
function U.ArenaServers_SaveChanges()
	local g = U.g_arenaservers
	local i = 0

	while i < g.numfavoriteaddresses do
		trap.Cvar_Set(Q.va("server%d", i + 1), g.favoriteaddresses[i])
		i += 1
	end

	while i < C.MAX_FAVORITESERVERS do
		trap.Cvar_Set(Q.va("server%d", i + 1), "")
		i += 1
	end
end

--[[
=================
ArenaServers_Sort
=================
]]
function U.ArenaServers_Sort(type: number)
	if U.g_sortkey == type then
		return
	end

	U.g_sortkey = type
	U.ArenaServers_QSort(U.g_arenaservers.serverlist, U.g_arenaservers.numservers.value)
end

--[[
=================
ArenaServers_SetType
=================
]]
function U.ArenaServers_SetType(type: number): number
	local g = U.g_arenaservers

	if type >= UIAS_GLOBAL1 and type <= UIAS_GLOBAL5 then
		while type <= UIAS_GLOBAL5 do
			local cvarname = Q.va("sv_master%d", type)
			local masterstr = trap.Cvar_VariableStringBuffer(cvarname)
			if masterstr ~= "" then
				break
			end

			type += 1
		end
	end

	U.g_servertype = type

	if type >= UIAS_GLOBAL1 and type <= UIAS_GLOBAL5 then
		g.remove.generic.flags = bor(g.remove.generic.flags, bor(C.QMF_INACTIVE, C.QMF_HIDDEN))
		g.serverlist = U.g_globalserverlist
		g.numservers = U.g_numglobalservers
		g.maxservers = MAX_GLOBALSERVERS
	elseif type == UIAS_FAVORITES then
		g.remove.generic.flags = band(g.remove.generic.flags, bnot(bor(C.QMF_INACTIVE, C.QMF_HIDDEN)))
		g.serverlist = U.g_favoriteserverlist
		g.numservers = U.g_numfavoriteservers
		g.maxservers = C.MAX_FAVORITESERVERS
	else -- default, UIAS_LOCAL
		g.remove.generic.flags = bor(g.remove.generic.flags, bor(C.QMF_INACTIVE, C.QMF_HIDDEN))
		g.serverlist = U.g_localserverlist
		g.numservers = U.g_numlocalservers
		g.maxservers = MAX_LOCALSERVERS
	end

	if g.numservers.value == 0 then
		U.ArenaServers_StartRefresh()
	else
		-- avoid slow operation, use existing results
		g.currentping = g.numservers.value
		g.numqueriedservers = g.numservers.value
		U.ArenaServers_UpdateMenu()
		g.status.string = "hit refresh to update"
	end

	return type
end

--[[
=================
ArenaServers_Event
=================
]]
function U.ArenaServers_Event(ptr, event)
	local g = U.g_arenaservers
	local id = ptr.generic.id

	if event ~= C.QM_ACTIVATED and id ~= ID_LIST then
		return
	end

	if id == ID_MASTER then
		g.master.curvalue = U.ArenaServers_SetType(g.master.curvalue)
		trap.Cvar_SetValue("ui_browserMaster", g.master.curvalue)
	elseif id == ID_GAMETYPE then
		trap.Cvar_SetValue("ui_browserGameType", g.gametype.curvalue)
		U.g_gametype = g.gametype.curvalue
		U.ArenaServers_UpdateMenu()
	elseif id == ID_SORTKEY then
		trap.Cvar_SetValue("ui_browserSortKey", g.sortkey.curvalue)
		U.ArenaServers_Sort(g.sortkey.curvalue)
		U.ArenaServers_UpdateMenu()
	elseif id == ID_SHOW_FULL then
		trap.Cvar_SetValue("ui_browserShowFull", g.showfull.curvalue)
		U.g_fullservers = g.showfull.curvalue
		U.ArenaServers_UpdateMenu()
	elseif id == ID_SHOW_EMPTY then
		trap.Cvar_SetValue("ui_browserShowEmpty", g.showempty.curvalue)
		U.g_emptyservers = g.showempty.curvalue
		U.ArenaServers_UpdateMenu()
	elseif id == ID_ONLY_HUMANS then
		trap.Cvar_SetValue("ui_browserOnlyHumans", g.onlyhumans.curvalue)
		U.g_onlyhumans = g.onlyhumans.curvalue
		U.ArenaServers_UpdateMenu()
	elseif id == ID_HIDE_PRIVATE then
		--trap_Cvar_SetValue( "ui_browserHidePrivate", g_arenaservers.hideprivate.curvalue );
		U.g_hideprivate = g.hideprivate.curvalue
		U.ArenaServers_UpdateMenu()
	elseif id == ID_LIST then
		if event == C.QM_GOTFOCUS then
			U.ArenaServers_UpdatePicture()
		end
	elseif id == ID_SCROLL_UP then
		U.ScrollList_Key(g.list, C.K_UPARROW)
	elseif id == ID_SCROLL_DOWN then
		U.ScrollList_Key(g.list, C.K_DOWNARROW)
	elseif id == ID_BACK then
		U.ArenaServers_StopRefresh()
		U.ArenaServers_SaveChanges()
		U.UI_PopMenu()
	elseif id == ID_REFRESH then
		U.ArenaServers_StartRefresh()
	elseif id == ID_SPECIFY then
		U.UI_SpecifyServerMenu()
	elseif id == ID_CREATE then
		U.UI_StartServerMenu(true)
	elseif id == ID_CONNECT then
		U.ArenaServers_Go()
	elseif id == ID_REMOVE then
		U.ArenaServers_Remove()
		U.ArenaServers_UpdateMenu()
	end
end

--[[
=================
ArenaServers_MenuDraw
=================
]]
function U.ArenaServers_MenuDraw()
	if U.g_arenaservers.refreshservers then
		U.ArenaServers_DoRefresh()
	end

	U.Menu_Draw(U.g_arenaservers.menu)
end

--[[
=================
ArenaServers_MenuKey
=================
]]
function U.ArenaServers_MenuKey(key)
	local g = U.g_arenaservers

	if key == C.K_SPACE and g.refreshservers then
		U.ArenaServers_StopRefresh()
		return U.menu_move_sound
	end

	if
		(key == C.K_DEL or key == C.K_KP_DEL)
		and U.g_servertype == UIAS_FAVORITES
		and U.Menu_ItemAtCursor(g.menu) == g.list
	then
		U.ArenaServers_Remove()
		U.ArenaServers_UpdateMenu()
		return U.menu_move_sound
	end

	if key == C.K_MOUSE2 or key == C.K_ESCAPE then
		U.ArenaServers_StopRefresh()
		U.ArenaServers_SaveChanges()
	end

	if key == C.K_MWHEELUP then
		U.ScrollList_Key(g.list, C.K_UPARROW)
	end

	if key == C.K_MWHEELDOWN then
		U.ScrollList_Key(g.list, C.K_DOWNARROW)
	end

	return U.Menu_DefaultKey(g.menu, key)
end

--[[
=================
ArenaServers_MenuInit
=================
]]
function U.ArenaServers_MenuInit()
	-- zero set all our globals
	U.g_arenaservers = U.ArenaServers_newArenaservers()
	local g = U.g_arenaservers

	U.ArenaServers_Cache()

	g.menu.fullscreen = true
	g.menu.wrapAround = true
	g.menu.draw = U.ArenaServers_MenuDraw
	g.menu.key = U.ArenaServers_MenuKey

	g.banner.generic.type = C.MTYPE_BTEXT
	g.banner.generic.flags = C.QMF_CENTER_JUSTIFY
	g.banner.generic.x = 320
	g.banner.generic.y = 16
	g.banner.string = "ARENA SERVERS"
	g.banner.style = C.UI_CENTER
	g.banner.color = U.color_white

	local smallflags = bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)

	local y = 80 - C.SMALLCHAR_HEIGHT
	g.master.generic.type = C.MTYPE_SPINCONTROL
	g.master.generic.name = "Servers:"
	g.master.generic.flags = smallflags
	g.master.generic.callback = U.ArenaServers_Event
	g.master.generic.id = ID_MASTER
	g.master.generic.x = 320
	g.master.generic.y = y
	g.master.itemnames = U.master_items

	y += C.SMALLCHAR_HEIGHT
	g.gametype.generic.type = C.MTYPE_SPINCONTROL
	g.gametype.generic.name = "Game Type:"
	g.gametype.generic.flags = smallflags
	g.gametype.generic.callback = U.ArenaServers_Event
	g.gametype.generic.id = ID_GAMETYPE
	g.gametype.generic.x = 320
	g.gametype.generic.y = y
	g.gametype.itemnames = U.servertype_items

	y += C.SMALLCHAR_HEIGHT
	g.sortkey.generic.type = C.MTYPE_SPINCONTROL
	g.sortkey.generic.name = "Sort By:"
	g.sortkey.generic.flags = smallflags
	g.sortkey.generic.callback = U.ArenaServers_Event
	g.sortkey.generic.id = ID_SORTKEY
	g.sortkey.generic.x = 320
	g.sortkey.generic.y = y
	g.sortkey.itemnames = U.sortkey_items

	y += C.SMALLCHAR_HEIGHT
	g.showfull.generic.type = C.MTYPE_RADIOBUTTON
	g.showfull.generic.name = "Show Full:"
	g.showfull.generic.flags = smallflags
	g.showfull.generic.callback = U.ArenaServers_Event
	g.showfull.generic.id = ID_SHOW_FULL
	g.showfull.generic.x = 320
	g.showfull.generic.y = y

	y += C.SMALLCHAR_HEIGHT
	g.showempty.generic.type = C.MTYPE_RADIOBUTTON
	g.showempty.generic.name = "Show Empty:"
	g.showempty.generic.flags = smallflags
	g.showempty.generic.callback = U.ArenaServers_Event
	g.showempty.generic.id = ID_SHOW_EMPTY
	g.showempty.generic.x = 320
	g.showempty.generic.y = y

	y += C.SMALLCHAR_HEIGHT
	g.onlyhumans.generic.type = C.MTYPE_RADIOBUTTON
	g.onlyhumans.generic.name = "Only humans:"
	g.onlyhumans.generic.flags = smallflags
	g.onlyhumans.generic.callback = U.ArenaServers_Event
	g.onlyhumans.generic.id = ID_ONLY_HUMANS
	g.onlyhumans.generic.x = 320
	g.onlyhumans.generic.y = y

	y += C.SMALLCHAR_HEIGHT
	g.hideprivate.generic.type = C.MTYPE_RADIOBUTTON
	g.hideprivate.generic.name = "Hide private:"
	g.hideprivate.generic.flags = smallflags
	g.hideprivate.generic.callback = U.ArenaServers_Event
	g.hideprivate.generic.id = ID_HIDE_PRIVATE
	g.hideprivate.generic.x = 320
	g.hideprivate.generic.y = y

	y += 2 * C.SMALLCHAR_HEIGHT
	g.list.generic.type = C.MTYPE_SCROLLLIST
	g.list.generic.flags = C.QMF_HIGHLIGHT_IF_FOCUS
	g.list.generic.id = ID_LIST
	g.list.generic.callback = U.ArenaServers_Event
	g.list.generic.x = 22
	g.list.generic.y = y
	g.list.width = MAX_LISTBOXWIDTH
	g.list.height = 11
	g.list.itemnames = g.items
	for i = 0, MAX_LISTBOXITEMS - 1 do
		g.items[i] = g.table[i].buff
	end

	g.mappic.generic.type = C.MTYPE_BITMAP
	g.mappic.generic.flags = bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	g.mappic.generic.x = 72
	g.mappic.generic.y = 80
	g.mappic.width = 128
	g.mappic.height = 96
	g.mappic.errorpic = ART_UNKNOWNMAP

	g.arrows.generic.type = C.MTYPE_BITMAP
	g.arrows.generic.name = ART_ARROWS0
	g.arrows.generic.flags = bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	g.arrows.generic.callback = U.ArenaServers_Event
	g.arrows.generic.x = 512 + 48 + 12
	g.arrows.generic.y = 240 - 64 + 48
	g.arrows.width = 64
	g.arrows.height = 128

	g.up.generic.type = C.MTYPE_BITMAP
	g.up.generic.flags = bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS, C.QMF_MOUSEONLY)
	g.up.generic.callback = U.ArenaServers_Event
	g.up.generic.id = ID_SCROLL_UP
	g.up.generic.x = 512 + 48 + 12
	g.up.generic.y = 240 - 64 + 48
	g.up.width = 64
	g.up.height = 64
	g.up.focuspic = ART_ARROWS_UP

	g.down.generic.type = C.MTYPE_BITMAP
	g.down.generic.flags = bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS, C.QMF_MOUSEONLY)
	g.down.generic.callback = U.ArenaServers_Event
	g.down.generic.id = ID_SCROLL_DOWN
	g.down.generic.x = 512 + 48 + 12
	g.down.generic.y = 240 + 48
	g.down.width = 64
	g.down.height = 64
	g.down.focuspic = ART_ARROWS_DOWN

	y = 376
	g.status.generic.type = C.MTYPE_TEXT
	g.status.generic.x = 320
	g.status.generic.y = y
	g.status.string = ""
	g.status.style = bor(C.UI_CENTER, C.UI_SMALLFONT)
	g.status.color = U.menu_text_color

	y += C.SMALLCHAR_HEIGHT
	g.statusbar.generic.type = C.MTYPE_TEXT
	g.statusbar.generic.x = 320
	g.statusbar.generic.y = y
	g.statusbar.string = ""
	g.statusbar.style = bor(C.UI_CENTER, C.UI_SMALLFONT)
	g.statusbar.color = U.text_color_normal

	g.remove.generic.type = C.MTYPE_BITMAP
	g.remove.generic.name = ART_REMOVE0
	g.remove.generic.flags = bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	g.remove.generic.callback = U.ArenaServers_Event
	g.remove.generic.id = ID_REMOVE
	g.remove.generic.x = 450
	g.remove.generic.y = 86
	g.remove.width = 96
	g.remove.height = 48
	g.remove.focuspic = ART_REMOVE1

	g.back.generic.type = C.MTYPE_BITMAP
	g.back.generic.name = ART_BACK0
	g.back.generic.flags = bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	g.back.generic.callback = U.ArenaServers_Event
	g.back.generic.id = ID_BACK
	g.back.generic.x = 0
	g.back.generic.y = 480 - 64
	g.back.width = 128
	g.back.height = 64
	g.back.focuspic = ART_BACK1

	g.specify.generic.type = C.MTYPE_BITMAP
	g.specify.generic.name = ART_SPECIFY0
	g.specify.generic.flags = bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	g.specify.generic.callback = U.ArenaServers_Event
	g.specify.generic.id = ID_SPECIFY
	g.specify.generic.x = 128
	g.specify.generic.y = 480 - 64
	g.specify.width = 128
	g.specify.height = 64
	g.specify.focuspic = ART_SPECIFY1

	g.refresh.generic.type = C.MTYPE_BITMAP
	g.refresh.generic.name = ART_REFRESH0
	g.refresh.generic.flags = bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	g.refresh.generic.callback = U.ArenaServers_Event
	g.refresh.generic.id = ID_REFRESH
	g.refresh.generic.x = 256
	g.refresh.generic.y = 480 - 64
	g.refresh.width = 128
	g.refresh.height = 64
	g.refresh.focuspic = ART_REFRESH1

	g.create.generic.type = C.MTYPE_BITMAP
	g.create.generic.name = ART_CREATE0
	g.create.generic.flags = bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	g.create.generic.callback = U.ArenaServers_Event
	g.create.generic.id = ID_CREATE
	g.create.generic.x = 384
	g.create.generic.y = 480 - 64
	g.create.width = 128
	g.create.height = 64
	g.create.focuspic = ART_CREATE1

	g.go.generic.type = C.MTYPE_BITMAP
	g.go.generic.name = ART_CONNECT0
	g.go.generic.flags = bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	g.go.generic.callback = U.ArenaServers_Event
	g.go.generic.id = ID_CONNECT
	g.go.generic.x = 640
	g.go.generic.y = 480 - 64
	g.go.width = 128
	g.go.height = 64
	g.go.focuspic = ART_CONNECT1

	U.Menu_AddItem(g.menu, g.banner)

	U.Menu_AddItem(g.menu, g.master)
	U.Menu_AddItem(g.menu, g.gametype)
	U.Menu_AddItem(g.menu, g.sortkey)
	U.Menu_AddItem(g.menu, g.showfull)
	U.Menu_AddItem(g.menu, g.showempty)
	U.Menu_AddItem(g.menu, g.onlyhumans)
	U.Menu_AddItem(g.menu, g.hideprivate)

	U.Menu_AddItem(g.menu, g.mappic)
	U.Menu_AddItem(g.menu, g.list)
	U.Menu_AddItem(g.menu, g.status)
	U.Menu_AddItem(g.menu, g.statusbar)
	U.Menu_AddItem(g.menu, g.arrows)
	U.Menu_AddItem(g.menu, g.up)
	U.Menu_AddItem(g.menu, g.down)

	U.Menu_AddItem(g.menu, g.remove)
	U.Menu_AddItem(g.menu, g.back)
	U.Menu_AddItem(g.menu, g.specify)
	U.Menu_AddItem(g.menu, g.refresh)
	U.Menu_AddItem(g.menu, g.create)
	U.Menu_AddItem(g.menu, g.go)

	U.ArenaServers_LoadFavorites()

	U.g_servertype = Q.Com_Clamp(0, 3, U.ui_browserMaster.integer)
	-- hack to get rid of MPlayer stuff
	local value = U.g_servertype
	if value >= 1 then
		value -= 1
	end
	g.master.curvalue = value

	U.g_gametype = Q.Com_Clamp(0, 12, U.ui_browserGameType.integer)
	g.gametype.curvalue = U.g_gametype

	U.g_sortkey = Q.Com_Clamp(0, 5, U.ui_browserSortKey.integer)
	g.sortkey.curvalue = U.g_sortkey

	U.g_fullservers = Q.Com_Clamp(0, 1, U.ui_browserShowFull.integer)
	g.showfull.curvalue = U.g_fullservers

	U.g_emptyservers = Q.Com_Clamp(0, 1, U.ui_browserShowEmpty.integer)
	g.showempty.curvalue = U.g_emptyservers

	g.onlyhumans.curvalue = Q.Com_Clamp(0, 1, U.ui_browserOnlyHumans.integer)
	U.g_onlyhumans = U.ui_browserOnlyHumans.integer

	g.hideprivate.curvalue = 1 --Com_Clamp( 0, 1, ui_browserOnlyHumans.integer );
	U.g_hideprivate = 1 --ui_browserOnlyHumans.integer;

	-- force to initial state and refresh
	U.g_servertype = U.ArenaServers_SetType(U.g_servertype)
	g.master.curvalue = U.g_servertype

	trap.Cvar_Register(nil, "debug_protocol", "", 0)
end

--[[
=================
ArenaServers_Cache
=================
]]
function U.ArenaServers_Cache()
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
	trap.R_RegisterShaderNoMip(ART_CREATE0)
	trap.R_RegisterShaderNoMip(ART_CREATE1)
	trap.R_RegisterShaderNoMip(ART_SPECIFY0)
	trap.R_RegisterShaderNoMip(ART_SPECIFY1)
	trap.R_RegisterShaderNoMip(ART_REFRESH0)
	trap.R_RegisterShaderNoMip(ART_REFRESH1)
	trap.R_RegisterShaderNoMip(ART_CONNECT0)
	trap.R_RegisterShaderNoMip(ART_CONNECT1)
	trap.R_RegisterShaderNoMip(ART_ARROWS0)
	trap.R_RegisterShaderNoMip(ART_ARROWS_UP)
	trap.R_RegisterShaderNoMip(ART_ARROWS_DOWN)
	trap.R_RegisterShaderNoMip(ART_UNKNOWNMAP)
end

--[[
=================
UI_ArenaServersMenu
=================
]]
function U.UI_ArenaServersMenu()
	U.ArenaServers_MenuInit()
	U.UI_PushMenu(U.g_arenaservers.menu)
end

return U
