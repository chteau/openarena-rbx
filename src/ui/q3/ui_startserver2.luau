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
-- Luau port of code/q3_ui/ui_startserver.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- This part covers C lines 1221-2397 of the 0.8.8 source.
local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local PLAYER_SLOTS = 12
local OPTIONS_X = 456

local GAMESERVER_BACK0 = "menu/art_blueish/back_0"
local GAMESERVER_BACK1 = "menu/art_blueish/back_1"
local GAMESERVER_NEXT0 = "menu/art_blueish/next_0"
local GAMESERVER_NEXT1 = "menu/art_blueish/next_1"
local GAMESERVER_FIGHT0 = "menu/art_blueish/fight_0"
local GAMESERVER_FIGHT1 = "menu/art_blueish/fight_1"
local GAMESERVER_SELECT = "menu/art/maps_select"
local GAMESERVER_UNKNOWNMAP = "menu/art/unknownmap"

local BOTSELECT_BACK0 = "menu/art_blueish/back_0"
local BOTSELECT_BACK1 = "menu/art_blueish/back_1"
local BOTSELECT_ACCEPT0 = "menu/art_blueish/accept_0"
local BOTSELECT_ACCEPT1 = "menu/art_blueish/accept_1"
local BOTSELECT_SELECT = "menu/art/opponents_select"
local BOTSELECT_SELECTED = "menu/art/opponents_selected"
local BOTSELECT_ARROWS = "menu/art_blueish/gs_arrows_0"
local BOTSELECT_ARROWSL = "menu/art_blueish/gs_arrows_l"
local BOTSELECT_ARROWSR = "menu/art_blueish/gs_arrows_r"

local PLAYERGRID_COLS = 4
local PLAYERGRID_ROWS = 4
local MAX_MODELSPERPAGE = PLAYERGRID_ROWS * PLAYERGRID_COLS

local function newItem()
	return {
		generic = {
			type = 0,
			id = 0,
			flags = 0,
			x = 0,
			y = 0,
			left = 0,
			top = 0,
			right = 0,
			bottom = 0,
			menuPosition = 0,
		},
		string = "",
		color = nil,
		style = 0,
		width = 0,
		height = 0,
		curvalue = 0,
		itemnames = nil,
		errorpic = nil,
		focuspic = nil,
		focuscolor = nil,
		shader = 0,
	}
end

local function newField()
	local f = newItem()
	f.field = { buffer = "", cursor = 0, scroll = 0, widthInChars = 0, maxchars = 0 }
	return f
end

local function newMenu()
	return { items = {}, nitems = 0, cursor = 0, cursor_prev = 0, wrapAround = false, fullscreen = false }
end

local function cpy(s, n)
	return string.sub(s, 1, n - 1)
end

local function setHeaderBuf(item, maxv, cvar)
	item.field.buffer = Q.va("%i", Q.int(Q.Com_Clamp(0, maxv, trap.Cvar_VariableValue(cvar))))
end

function U.ServerOptions_PlayerNameEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	local n = ptr.generic.id
	U.s_serveroptions.newBotIndex = n
	U.UI_BotSelectMenu(U.s_serveroptions.playerNameBuffers[n])
end

function U.ServerOptions_StatusBar(ptr)
	U.UI_DrawString(320, 440, "0 = NO LIMIT", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), Q.colorWhite)
end

function U.ServerOptions_StatusBar_Instantgib(ptr)
	U.UI_DrawString(320, 440, "Only railgun and instant kill", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), Q.colorWhite)
end

function U.ServerOptions_StatusBar_Allrockets(ptr)
	U.UI_DrawString(
		320,
		440,
		"Only Rocket launcher with Inf. ammo",
		bit32.bor(C.UI_CENTER, C.UI_SMALLFONT),
		Q.colorWhite
	)
end

function U.ServerOptions_StatusBar_Pure(ptr)
	-- Roblox: pure checks don't exist here; this toggle lists the server in
	-- Arena Servers (sv_public, sys/LAN.luau)
	U.UI_DrawString(320, 440, "List in Arena Servers, else join by code", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), Q.colorWhite)
end

function U.ServerOptions_StatusBar_Oneway(ptr)
	U.UI_DrawString(
		320,
		440,
		"Only one team can capture in a round",
		bit32.bor(C.UI_CENTER, C.UI_SMALLFONT),
		Q.colorWhite
	)
end

function U.ServerOptions_StatusBar_Pmove(ptr)
	local style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
	local v = ptr.curvalue
	if v == 0 then
		U.UI_DrawString(320, 440, "Physics depends on players framerates", style, Q.colorWhite)
		U.UI_DrawString(320, 460, "Not all players are equal", style, Q.colorWhite)
	elseif v == 1 or v == 2 then
		U.UI_DrawString(320, 440, "Physics are calculated at fixed intervals", style, Q.colorWhite)
		U.UI_DrawString(320, 460, "All players are equal", style, Q.colorWhite)
	elseif v == 3 then
		U.UI_DrawString(320, 440, "Physics are calculated exactly", style, Q.colorWhite)
		U.UI_DrawString(320, 460, "All players are equal", style, Q.colorWhite)
	else
		U.UI_DrawString(320, 440, "Framerate dependent or not", style, Q.colorWhite)
	end
end

function U.ServerOptions_LevelshotDraw(self)
	local so = U.s_serveroptions

	-- strange place for this, but it works
	if so.newBot then
		so.playerNameBuffers[so.newBotIndex] = cpy(so.newBotName, 16)
		so.newBot = false
	end

	local b = self

	U.Bitmap_Draw(b)

	local x = b.generic.x
	local y = b.generic.y + b.height
	U.UI_FillRect(x, y, b.width, 40, Q.colorBlack)

	x = x + Q.idiv(b.width, 2)
	y = y + 4
	U.UI_DrawString(x, y, so.mapnamebuffer, bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_orange)

	y = y + C.SMALLCHAR_HEIGHT
	U.UI_DrawString(
		x,
		y,
		U.gametype_items[U.gametype_remap2[so.gametype]],
		bit32.bor(C.UI_CENTER, C.UI_SMALLFONT),
		U.color_orange
	)
end

function U.ServerOptions_InitBotNames()
	local so = U.s_serveroptions

	-- Roblox port: OA seeds Kyonshi and Merman here; they are not in the
	-- shipped roster (tools/oaconv/roster.json), so their arena substitutes
	-- Sarge and Beret take the slots
	if so.gametype >= C.GT_TEAM and so.gametype ~= C.GT_LMS then
		local names = so.playerNameBuffers
		local types = so.playerType
		names[1] = cpy("gargoyle", 16)
		names[2] = cpy("sarge", 16)
		names[3] = cpy("grism", 16)
		if so.gametype ~= C.GT_TEAM then
			types[3].curvalue = 2
		end
		names[4] = cpy("beret", 16)
		types[4].curvalue = 2
		names[5] = cpy("skelebot", 16)
		types[5].curvalue = 2
		names[6] = cpy("sergei", 16)
		names[7] = cpy("assassin", 16)
		names[8] = cpy("grunt", 16)
		names[9] = cpy("skelebot", 16)
		if so.gametype ~= C.GT_TEAM then
			types[9].curvalue = 2
		end
		names[10] = cpy("beret", 16)
		types[10].curvalue = 2
		names[11] = cpy("skelebot", 16)
		types[11].curvalue = 2
		return
	end

	local count = 1 -- skip the first slot, reserved for a human

	-- get info for this map
	local arenaInfo = U.UI_GetArenaInfoByMap(so.mapnamebuffer)

	-- get the bot info - we'll seed with them if any are listed
	local bots = string.sub(Q.Info_ValueForKey(arenaInfo, "bots"), 1, C.MAX_INFO_STRING - 1)
	for token in string.gmatch(bots, "[^ ]+") do
		if count >= PLAYER_SLOTS then
			break
		end
		local botInfo = U.UI_GetBotInfoByName(token)
		local bot = Q.Info_ValueForKey(botInfo, "name")

		if bot == "" then
			bot = "Sarge"
		end

		so.playerNameBuffers[count] = cpy(bot, 16)
		count += 1
	end

	-- set the rest of the bot slots to to other bots
	for n = count, PLAYER_SLOTS - 1 do
		local m = n % 4
		if m == 0 then
			so.playerNameBuffers[n] = "Grunt"
		elseif m == 1 then
			so.playerNameBuffers[n] = "Beret"
		elseif m == 2 then
			so.playerNameBuffers[n] = "Sarge"
		else
			so.playerNameBuffers[n] = "Skelebot"
		end
	end

	-- pad up to #8 as open slots
	while count < 8 do
		so.playerType[count].curvalue = 0
		count += 1
	end

	-- close off the rest by default
	while count < PLAYER_SLOTS do
		if so.playerType[count].curvalue == 1 then
			so.playerType[count].curvalue = 2
		end
		count += 1
	end
end

function U.ServerOptions_SetMenuItems()
	local so = U.s_serveroptions
	local gt = so.gametype
	local cv = trap.Cvar_VariableValue

	local function frag(cvarFrag, cvarTime)
		setHeaderBuf(so.fraglimit, 999, cvarFrag)
		setHeaderBuf(so.timelimit, 999, cvarTime)
	end
	local function flag(maxFlag, cvarFlag, cvarTime)
		setHeaderBuf(so.flaglimit, maxFlag, cvarFlag)
		setHeaderBuf(so.timelimit, 999, cvarTime)
	end
	local function friendly(cvar)
		so.friendlyfire.curvalue = Q.int(Q.Com_Clamp(0, 1, cv(cvar)))
	end

	if gt == C.GT_TOURNAMENT then
		frag("ui_tourney_fraglimit", "ui_tourney_timelimit")
	elseif gt == C.GT_TEAM then
		frag("ui_team_fraglimit", "ui_team_timelimit")
		friendly("ui_team_friendly")
	elseif gt == C.GT_CTF then
		flag(100, "ui_ctf_capturelimit", "ui_ctf_timelimit")
		friendly("ui_ctf_friendly")
	elseif gt == C.GT_1FCTF then
		flag(100, "ui_1fctf_capturelimit", "ui_1fctf_timelimit")
		friendly("ui_1fctf_friendly")
	elseif gt == C.GT_OBELISK then
		flag(100, "ui_overload_capturelimit", "ui_overload_timelimit")
		friendly("ui_overload_friendly")
	elseif gt == C.GT_HARVESTER then
		flag(100, "ui_harvester_capturelimit", "ui_harvester_timelimit")
		friendly("ui_harvester_friendly")
	elseif gt == C.GT_ELIMINATION then
		flag(999, "ui_elimination_capturelimit", "ui_elimination_timelimit")
	elseif gt == C.GT_CTF_ELIMINATION then
		flag(999, "ui_ctf_elimination_capturelimit", "ui_ctf_elimination_timelimit")
	elseif gt == C.GT_LMS then
		frag("ui_lms_fraglimit", "ui_lms_timelimit")
	elseif gt == C.GT_DOUBLE_D then
		flag(100, "ui_dd_capturelimit", "ui_dd_timelimit")
		friendly("ui_dd_friendly")
	elseif gt == C.GT_DOMINATION then
		flag(999, "ui_dom_capturelimit", "ui_dom_timelimit")
		friendly("ui_dom_friendly")
	else
		frag("ui_ffa_fraglimit", "ui_ffa_timelimit")
	end

	so.hostname.field.buffer = string.sub(U.UI_Cvar_VariableString("sv_hostname"), 1, 63)
	so.pure.curvalue = Q.Com_Clamp(0, 1, cv("sv_public")) -- Roblox: was sv_pure
	so.lan.curvalue = Q.Com_Clamp(0, 1, cv("sv_lanforcerate"))
	so.instantgib.curvalue = Q.Com_Clamp(0, 1, cv("g_instantgib"))
	so.rockets.curvalue = Q.Com_Clamp(0, 1, cv("g_rockets"))
	so.lmsMode.curvalue = Q.Com_Clamp(0, 3, cv("g_lms_mode"))
	so.oneway.curvalue = Q.Com_Clamp(0, 1, cv("elimination_ctf_oneway"))
	so.pmove.curvalue = 0
	if cv("pmove_fixed") ~= 0 then
		so.pmove.curvalue = 1
	end
	if cv("pmove_fixed") ~= 0 and cv("pmove_msec") == 11 then
		so.pmove.curvalue = 2
	end
	if cv("pmove_float") ~= 0 then
		so.pmove.curvalue = 3
	end

	-- set the map pic
	local info = U.UI_GetArenaInfoByNumber(U.s_startserver.maplist[U.s_startserver.currentmap])
	so.mappic.generic.name = Q.va("levelshots/%s", Q.Info_ValueForKey(info, "map"))

	-- set the map name
	so.mapnamebuffer = string.upper(string.sub(U.s_startserver.mapname.string, 1, 31))

	-- get the player selections initialized
	U.ServerOptions_InitPlayerItems()
	U.ServerOptions_SetPlayerItems()

	-- seed bot names
	U.ServerOptions_InitBotNames()
	U.ServerOptions_SetPlayerItems()
end

function U.PlayerName_Draw(item)
	local s = item

	local x = s.generic.x
	local y = s.generic.y

	local style = C.UI_SMALLFONT
	local focus = (s.generic.parent.cursor == s.generic.menuPosition)
	local color

	if bit32.band(s.generic.flags, C.QMF_GRAYED) ~= 0 then
		color = U.text_color_disabled
	elseif focus then
		color = U.text_color_highlight
		style = bit32.bor(style, C.UI_PULSE)
	elseif bit32.band(s.generic.flags, C.QMF_BLINK) ~= 0 then
		color = U.text_color_highlight
		style = bit32.bor(style, C.UI_BLINK)
	else
		color = U.text_color_normal
	end

	if focus then
		-- draw cursor
		U.UI_FillRect(
			s.generic.left,
			s.generic.top,
			s.generic.right - s.generic.left + 1,
			s.generic.bottom - s.generic.top + 1,
			U.listbar_color
		)
		U.UI_DrawChar(x, y, 13, bit32.bor(C.UI_CENTER, C.UI_BLINK, C.UI_SMALLFONT), color)
	end

	U.UI_DrawString(x - C.SMALLCHAR_WIDTH, y, s.generic.name, bit32.bor(style, C.UI_RIGHT), color)
	U.UI_DrawString(x + C.SMALLCHAR_WIDTH, y, s.string, bit32.bor(style, C.UI_LEFT), color)
end

function U.ServerOptions_MenuInit(multiplayer)
	local so = {
		menu = newMenu(),
		banner = newItem(),
		mappic = newItem(),
		picframe = newItem(),
		fraglimit = newField(),
		flaglimit = newField(),
		timelimit = newField(),
		friendlyfire = newItem(),
		oneway = newItem(),
		pure = newItem(),
		instantgib = newItem(),
		rockets = newItem(),
		lmsMode = newItem(),
		pmove = newItem(),
		lan = newItem(),
		hostname = newField(),
		botSkill = newItem(),
		player0 = newItem(),
		playerType = {},
		playerName = {},
		playerTeam = {},
		playerNameBuffers = {},
		back = newItem(),
		next = newItem(),
		go = newItem(),
		multiplayer = multiplayer,
		gametype = 0,
		mapnamebuffer = "",
		newBot = false,
		newBotName = "",
		newBotIndex = 0,
	}
	for n = 0, PLAYER_SLOTS - 1 do
		so.playerType[n] = newItem()
		so.playerName[n] = newItem()
		so.playerTeam[n] = newItem()
		so.playerNameBuffers[n] = ""
	end
	U.s_serveroptions = so

	-- so the new gametypes work
	so.gametype = Q.int(Q.Com_Clamp(0, C.GT_MAX_GAME_TYPE - 1, trap.Cvar_VariableValue("g_gameType")))

	U.ServerOptions_Cache()

	so.menu.wrapAround = true
	so.menu.fullscreen = true

	so.banner.generic.type = C.MTYPE_BTEXT
	so.banner.generic.x = 320
	so.banner.generic.y = 16
	so.banner.string = "GAME SERVER"
	so.banner.color = U.color_white
	so.banner.style = C.UI_CENTER

	so.mappic.generic.type = C.MTYPE_BITMAP
	so.mappic.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	so.mappic.generic.x = 352
	so.mappic.generic.y = 80
	so.mappic.width = 160
	so.mappic.height = 120
	so.mappic.errorpic = GAMESERVER_UNKNOWNMAP
	so.mappic.generic.ownerdraw = U.ServerOptions_LevelshotDraw

	so.picframe.generic.type = C.MTYPE_BITMAP
	so.picframe.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE, C.QMF_HIGHLIGHT)
	so.picframe.generic.x = 352 - 38
	so.picframe.generic.y = 80 - 40
	so.picframe.width = 320
	so.picframe.height = 320
	so.picframe.focuspic = GAMESERVER_SELECT

	local fieldFlags = bit32.bor(C.QMF_NUMBERSONLY, C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	local radioFlags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	local step = C.BIGCHAR_HEIGHT + 2

	local function limitField(f, name, y)
		f.generic.type = C.MTYPE_FIELD
		f.generic.name = name
		f.generic.flags = fieldFlags
		f.generic.x = OPTIONS_X
		f.generic.y = y
		f.generic.statusbar = U.ServerOptions_StatusBar
		f.field.widthInChars = 3
		f.field.maxchars = 3
	end

	local y = 268
	if so.gametype < C.GT_CTF or so.gametype == C.GT_LMS then
		limitField(so.fraglimit, "Frag Limit:", y)
	else
		limitField(so.flaglimit, "Capture Limit:", y)
	end

	y += step
	limitField(so.timelimit, "Time Limit:", y)

	local hasFriendly = so.gametype >= C.GT_TEAM
		and so.gametype ~= C.GT_LMS
		and so.gametype ~= C.GT_ELIMINATION
		and so.gametype ~= C.GT_CTF_ELIMINATION

	local function radio(item, name, yy, statusbar)
		item.generic.type = C.MTYPE_RADIOBUTTON
		item.generic.flags = radioFlags
		item.generic.x = OPTIONS_X
		item.generic.y = yy
		item.generic.name = name
		item.generic.statusbar = statusbar
	end

	if hasFriendly then
		y += step
		radio(so.friendlyfire, "Friendly Fire:", y, nil)
	end

	if so.gametype == C.GT_CTF_ELIMINATION then
		y += step
		radio(so.oneway, "Oneway attack:", y, U.ServerOptions_StatusBar_Oneway)
	end

	y += step
	radio(so.pure, "Public Server:", y, U.ServerOptions_StatusBar_Pure)

	if so.multiplayer then
		y += step
		radio(so.lan, "Optimize for LAN:", y, nil)
	end

	-- Insantgib option
	y += step
	radio(so.instantgib, "Instantgib:", y, U.ServerOptions_StatusBar_Instantgib)

	-- Rockets option
	y += step
	radio(so.rockets, "All rockets:", y, U.ServerOptions_StatusBar_Allrockets)

	if so.gametype == C.GT_LMS then
		y += step
		so.lmsMode.generic.type = C.MTYPE_SPINCONTROL
		so.lmsMode.generic.flags = radioFlags
		so.lmsMode.generic.name = "Score mode:"
		so.lmsMode.generic.x = OPTIONS_X
		so.lmsMode.generic.y = y
		so.lmsMode.itemnames = U.lmsMode_list
	end

	y += step
	so.pmove.generic.type = C.MTYPE_SPINCONTROL
	so.pmove.generic.flags = radioFlags
	so.pmove.generic.name = "Physics:"
	so.pmove.generic.x = OPTIONS_X
	so.pmove.generic.y = y
	so.pmove.itemnames = U.pmove_list
	so.pmove.generic.statusbar = U.ServerOptions_StatusBar_Pmove

	if so.multiplayer then
		y += step
		so.hostname.generic.type = C.MTYPE_FIELD
		so.hostname.generic.name = "Hostname:"
		so.hostname.generic.flags = C.QMF_SMALLFONT
		so.hostname.generic.x = OPTIONS_X
		so.hostname.generic.y = y
		so.hostname.field.widthInChars = 18
		so.hostname.field.maxchars = 64
	end

	y = 80
	so.botSkill.generic.type = C.MTYPE_SPINCONTROL
	so.botSkill.generic.flags = radioFlags
	so.botSkill.generic.name = "Bot Skill:"
	so.botSkill.generic.x = 32 + (#so.botSkill.generic.name + 2) * C.SMALLCHAR_WIDTH
	so.botSkill.generic.y = y
	so.botSkill.itemnames = U.botSkill_list
	so.botSkill.curvalue = 1

	y += 2 * C.SMALLCHAR_HEIGHT
	so.player0.generic.type = C.MTYPE_TEXT
	so.player0.generic.flags = C.QMF_SMALLFONT
	so.player0.generic.x = 32 + C.SMALLCHAR_WIDTH
	so.player0.generic.y = y
	so.player0.color = U.color_orange
	so.player0.style = bit32.bor(C.UI_LEFT, C.UI_SMALLFONT)

	for n = 0, PLAYER_SLOTS - 1 do
		local pt = so.playerType[n]
		pt.generic.type = C.MTYPE_SPINCONTROL
		pt.generic.flags = C.QMF_SMALLFONT
		pt.generic.id = U.ID_PLAYER_TYPE
		pt.generic.callback = U.ServerOptions_Event
		pt.generic.x = 32
		pt.generic.y = y
		pt.itemnames = U.playerType_list

		local pn = so.playerName[n]
		pn.generic.type = C.MTYPE_TEXT
		pn.generic.flags = C.QMF_SMALLFONT
		pn.generic.x = 96
		pn.generic.y = y
		pn.generic.callback = U.ServerOptions_PlayerNameEvent
		pn.generic.id = n
		pn.generic.ownerdraw = U.PlayerName_Draw
		pn.color = U.color_orange
		pn.style = C.UI_SMALLFONT
		pn.string = so.playerNameBuffers[n]
		pn.generic.top = pn.generic.y
		pn.generic.bottom = pn.generic.y + C.SMALLCHAR_HEIGHT
		pn.generic.left = pn.generic.x - Q.idiv(C.SMALLCHAR_HEIGHT, 2)
		pn.generic.right = pn.generic.x + 16 * C.SMALLCHAR_WIDTH

		local pteam = so.playerTeam[n]
		pteam.generic.type = C.MTYPE_SPINCONTROL
		pteam.generic.flags = C.QMF_SMALLFONT
		pteam.generic.x = 240
		pteam.generic.y = y
		pteam.itemnames = U.playerTeam_list

		y += C.SMALLCHAR_HEIGHT + 4
	end

	so.back.generic.type = C.MTYPE_BITMAP
	so.back.generic.name = GAMESERVER_BACK0
	so.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	so.back.generic.callback = U.ServerOptions_Event
	so.back.generic.id = U.ID_BACK
	so.back.generic.x = 0
	so.back.generic.y = 480 - 64
	so.back.width = 128
	so.back.height = 64
	so.back.focuspic = GAMESERVER_BACK1

	so.next.generic.type = C.MTYPE_BITMAP
	so.next.generic.name = GAMESERVER_NEXT0
	so.next.generic.flags = bit32.bor(
		C.QMF_RIGHT_JUSTIFY,
		C.QMF_PULSEIFFOCUS,
		C.QMF_INACTIVE,
		C.QMF_GRAYED,
		C.QMF_HIDDEN
	)
	so.next.generic.callback = U.ServerOptions_Event
	so.next.generic.id = U.ID_STARTSERVERNEXT
	so.next.generic.x = 640
	so.next.generic.y = 480 - 64 - 72
	so.next.generic.statusbar = U.ServerOptions_StatusBar
	so.next.width = 128
	so.next.height = 64
	so.next.focuspic = GAMESERVER_NEXT1

	so.go.generic.type = C.MTYPE_BITMAP
	so.go.generic.name = GAMESERVER_FIGHT0
	so.go.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	so.go.generic.callback = U.ServerOptions_Event
	so.go.generic.id = U.ID_GO
	so.go.generic.x = 640
	so.go.generic.y = 480 - 64
	so.go.width = 128
	so.go.height = 64
	so.go.focuspic = GAMESERVER_FIGHT1

	U.Menu_AddItem(so.menu, so.banner)

	U.Menu_AddItem(so.menu, so.mappic)
	U.Menu_AddItem(so.menu, so.picframe)

	U.Menu_AddItem(so.menu, so.botSkill)
	U.Menu_AddItem(so.menu, so.player0)
	for n = 0, PLAYER_SLOTS - 1 do
		if n ~= 0 then
			U.Menu_AddItem(so.menu, so.playerType[n])
		end
		U.Menu_AddItem(so.menu, so.playerName[n])
		if so.gametype >= C.GT_TEAM and so.gametype ~= C.GT_LMS then
			U.Menu_AddItem(so.menu, so.playerTeam[n])
		end
	end

	if so.gametype < C.GT_CTF or so.gametype == C.GT_LMS then
		U.Menu_AddItem(so.menu, so.fraglimit)
	else
		U.Menu_AddItem(so.menu, so.flaglimit)
	end
	U.Menu_AddItem(so.menu, so.timelimit)
	if hasFriendly then
		U.Menu_AddItem(so.menu, so.friendlyfire)
	end
	U.Menu_AddItem(so.menu, so.pure)
	U.Menu_AddItem(so.menu, so.instantgib)
	U.Menu_AddItem(so.menu, so.rockets)
	if so.gametype == C.GT_LMS then
		U.Menu_AddItem(so.menu, so.lmsMode)
	end
	if so.gametype == C.GT_CTF_ELIMINATION then
		U.Menu_AddItem(so.menu, so.oneway)
	end
	U.Menu_AddItem(so.menu, so.pmove)
	if so.multiplayer then
		U.Menu_AddItem(so.menu, so.lan)
		U.Menu_AddItem(so.menu, so.hostname)
	end

	U.Menu_AddItem(so.menu, so.back)
	U.Menu_AddItem(so.menu, so.next)
	U.Menu_AddItem(so.menu, so.go)

	U.ServerOptions_SetMenuItems()
end

function U.ServerOptions_Cache()
	trap.R_RegisterShaderNoMip(GAMESERVER_BACK0)
	trap.R_RegisterShaderNoMip(GAMESERVER_BACK1)
	trap.R_RegisterShaderNoMip(GAMESERVER_FIGHT0)
	trap.R_RegisterShaderNoMip(GAMESERVER_FIGHT1)
	trap.R_RegisterShaderNoMip(GAMESERVER_SELECT)
	trap.R_RegisterShaderNoMip(GAMESERVER_UNKNOWNMAP)
end

function U.UI_ServerOptionsMenu(multiplayer)
	U.ServerOptions_MenuInit(multiplayer)
	U.UI_PushMenu(U.s_serveroptions.menu)
end

-- BOT SELECT MENU

local function newBotSelectInfo()
	local info = {
		menu = newMenu(),
		banner = newItem(),
		pics = {},
		picbuttons = {},
		picnames = {},
		arrows = newItem(),
		left = newItem(),
		right = newItem(),
		go = newItem(),
		back = newItem(),
		numBots = 0,
		modelpage = 0,
		numpages = 0,
		selectedmodel = 0,
		sortedBotNums = {},
		boticons = {},
		botnames = {},
	}
	for i = 0, MAX_MODELSPERPAGE - 1 do
		info.pics[i] = newItem()
		info.picbuttons[i] = newItem()
		info.picnames[i] = newItem()
		info.boticons[i] = ""
		info.botnames[i] = ""
	end
	return info
end

U.botSelectInfo = newBotSelectInfo()

function U.UI_BotSelectMenu_SortCompare(arg1, arg2)
	local info1 = U.UI_GetBotInfoByNumber(arg1)
	local info2 = U.UI_GetBotInfoByNumber(arg2)

	local name1 = Q.Info_ValueForKey(info1, "name")
	local name2 = Q.Info_ValueForKey(info2, "name")

	return Q.stricmp(name1, name2)
end

function U.UI_BotSelectMenu_BuildList()
	local bsi = U.botSelectInfo

	bsi.modelpage = 0
	bsi.numBots = U.UI_GetNumBots()
	bsi.numpages = Q.idiv(bsi.numBots, MAX_MODELSPERPAGE)
	if bsi.numBots % MAX_MODELSPERPAGE ~= 0 then
		bsi.numpages += 1
	end

	-- initialize the array
	local list = {}
	for n = 0, bsi.numBots - 1 do
		list[n + 1] = n
	end

	-- now sort it
	table.sort(list, function(a, b)
		return U.UI_BotSelectMenu_SortCompare(a, b) < 0
	end)
	for n = 0, bsi.numBots - 1 do
		bsi.sortedBotNums[n] = list[n + 1]
	end
end

function U.ServerPlayerIcon(modelAndSkin, iconNameMaxSize)
	local model = string.sub(modelAndSkin, 1, C.MAX_QPATH - 1)
	local skin = "default"
	local slash
	for i = #model, 1, -1 do
		if string.byte(model, i) == 47 then
			slash = i
			break
		end
	end
	if slash ~= nil then
		skin = string.sub(model, slash + 1)
		model = string.sub(model, 1, slash - 1)
	end

	local iconName = string.sub(Q.va("models/players/%s/icon_%s.tga", model, skin), 1, iconNameMaxSize - 1)

	if trap.R_RegisterShaderNoMip(iconName) == 0 and Q.stricmp(skin, "default") ~= 0 then
		iconName = string.sub(Q.va("models/players/%s/icon_default.tga", model), 1, iconNameMaxSize - 1)
	end
	return iconName
end

function U.UI_BotSelectMenu_UpdateGrid()
	local bsi = U.botSelectInfo
	local notInactive = bit32.bnot(C.QMF_INACTIVE)
	local notHighlight = bit32.bnot(C.QMF_HIGHLIGHT)
	local notPulse = bit32.bnot(C.QMF_PULSEIFFOCUS)

	local j = bsi.modelpage * MAX_MODELSPERPAGE
	for i = 0, PLAYERGRID_ROWS * PLAYERGRID_COLS - 1 do
		local pic = bsi.pics[i]
		local button = bsi.picbuttons[i]
		if j < bsi.numBots then
			local info = U.UI_GetBotInfoByNumber(bsi.sortedBotNums[j])
			bsi.boticons[i] = U.ServerPlayerIcon(Q.Info_ValueForKey(info, "model"), C.MAX_QPATH)
			bsi.botnames[i] = Q.CleanStr(cpy(Q.Info_ValueForKey(info, "name"), 16))
			pic.generic.name = bsi.boticons[i]
			if U.BotAlreadySelected(bsi.botnames[i]) then
				bsi.picnames[i].color = U.color_red
			else
				bsi.picnames[i].color = U.color_orange
			end
			button.generic.flags = bit32.band(button.generic.flags, notInactive)
		else
			-- dead slot
			pic.generic.name = nil
			button.generic.flags = bit32.bor(button.generic.flags, C.QMF_INACTIVE)
			bsi.botnames[i] = ""
		end
		bsi.picnames[i].string = bsi.botnames[i]

		pic.generic.flags = bit32.band(pic.generic.flags, notHighlight)
		pic.shader = 0
		button.generic.flags = bit32.bor(button.generic.flags, C.QMF_PULSEIFFOCUS)
		j += 1
	end

	-- set selected model
	local i = bsi.selectedmodel % MAX_MODELSPERPAGE
	bsi.pics[i].generic.flags = bit32.bor(bsi.pics[i].generic.flags, C.QMF_HIGHLIGHT)
	bsi.picbuttons[i].generic.flags = bit32.band(bsi.picbuttons[i].generic.flags, notPulse)

	if bsi.numpages > 1 then
		if bsi.modelpage > 0 then
			bsi.left.generic.flags = bit32.band(bsi.left.generic.flags, notInactive)
		else
			bsi.left.generic.flags = bit32.bor(bsi.left.generic.flags, C.QMF_INACTIVE)
		end

		if bsi.modelpage < bsi.numpages - 1 then
			bsi.right.generic.flags = bit32.band(bsi.right.generic.flags, notInactive)
		else
			bsi.right.generic.flags = bit32.bor(bsi.right.generic.flags, C.QMF_INACTIVE)
		end
	else
		-- hide left/right markers
		bsi.left.generic.flags = bit32.bor(bsi.left.generic.flags, C.QMF_INACTIVE)
		bsi.right.generic.flags = bit32.bor(bsi.right.generic.flags, C.QMF_INACTIVE)
	end
end

function U.UI_BotSelectMenu_Default(bot)
	local bsi = U.botSelectInfo

	local n = 0
	while n < bsi.numBots do
		local botInfo = U.UI_GetBotInfoByNumber(n)
		local test = Q.Info_ValueForKey(botInfo, "name")
		if Q.stricmp(bot, test) == 0 then
			break
		end
		n += 1
	end
	if n == bsi.numBots then
		bsi.selectedmodel = 0
		return
	end

	local i = 0
	while i < bsi.numBots do
		if bsi.sortedBotNums[i] == n then
			break
		end
		i += 1
	end
	if i == bsi.numBots then
		bsi.selectedmodel = 0
		return
	end

	bsi.selectedmodel = i
end

function U.UI_BotSelectMenu_LeftEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	local bsi = U.botSelectInfo
	if bsi.modelpage > 0 then
		bsi.modelpage -= 1
		bsi.selectedmodel = bsi.modelpage * MAX_MODELSPERPAGE
		U.UI_BotSelectMenu_UpdateGrid()
	end
end

function U.UI_BotSelectMenu_RightEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	local bsi = U.botSelectInfo
	if bsi.modelpage < bsi.numpages - 1 then
		bsi.modelpage += 1
		bsi.selectedmodel = bsi.modelpage * MAX_MODELSPERPAGE
		U.UI_BotSelectMenu_UpdateGrid()
	end
end

function U.UI_BotSelectMenu_BotEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	local bsi = U.botSelectInfo

	for i = 0, PLAYERGRID_ROWS * PLAYERGRID_COLS - 1 do
		bsi.pics[i].generic.flags = bit32.band(bsi.pics[i].generic.flags, bit32.bnot(C.QMF_HIGHLIGHT))
		bsi.picbuttons[i].generic.flags = bit32.bor(bsi.picbuttons[i].generic.flags, C.QMF_PULSEIFFOCUS)
	end

	-- set selected
	local i = ptr.generic.id
	bsi.pics[i].generic.flags = bit32.bor(bsi.pics[i].generic.flags, C.QMF_HIGHLIGHT)
	bsi.picbuttons[i].generic.flags = bit32.band(bsi.picbuttons[i].generic.flags, bit32.bnot(C.QMF_PULSEIFFOCUS))
	bsi.selectedmodel = bsi.modelpage * MAX_MODELSPERPAGE + i
end

function U.UI_BotSelectMenu_BackEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	U.UI_PopMenu()
end

function U.UI_BotSelectMenu_SelectEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	U.UI_PopMenu()

	U.s_serveroptions.newBot = true
	U.s_serveroptions.newBotName = cpy(U.botSelectInfo.botnames[U.botSelectInfo.selectedmodel % MAX_MODELSPERPAGE], 16)
end

function U.UI_BotSelectMenu_Cache()
	trap.R_RegisterShaderNoMip(BOTSELECT_BACK0)
	trap.R_RegisterShaderNoMip(BOTSELECT_BACK1)
	trap.R_RegisterShaderNoMip(BOTSELECT_ACCEPT0)
	trap.R_RegisterShaderNoMip(BOTSELECT_ACCEPT1)
	trap.R_RegisterShaderNoMip(BOTSELECT_SELECT)
	trap.R_RegisterShaderNoMip(BOTSELECT_SELECTED)
	trap.R_RegisterShaderNoMip(BOTSELECT_ARROWS)
	trap.R_RegisterShaderNoMip(BOTSELECT_ARROWSL)
	trap.R_RegisterShaderNoMip(BOTSELECT_ARROWSR)
end

function U.UI_BotSelectMenu_Init(bot)
	U.botSelectInfo = newBotSelectInfo()
	local bsi = U.botSelectInfo
	bsi.menu.wrapAround = true
	bsi.menu.fullscreen = true

	U.UI_BotSelectMenu_Cache()

	bsi.banner.generic.type = C.MTYPE_BTEXT
	bsi.banner.generic.x = 320
	bsi.banner.generic.y = 16
	bsi.banner.string = "SELECT BOT"
	bsi.banner.color = U.color_white
	bsi.banner.style = C.UI_CENTER

	local y = 80
	local k = 0
	for _ = 0, PLAYERGRID_ROWS - 1 do
		local x = 180
		for _ = 0, PLAYERGRID_COLS - 1 do
			local pic = bsi.pics[k]
			pic.generic.type = C.MTYPE_BITMAP
			pic.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
			pic.generic.x = x
			pic.generic.y = y
			pic.generic.name = bsi.boticons[k]
			pic.width = 64
			pic.height = 64
			pic.focuspic = BOTSELECT_SELECTED
			pic.focuscolor = Q.colorRed

			local pb = bsi.picbuttons[k]
			pb.generic.type = C.MTYPE_BITMAP
			pb.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_NODEFAULTINIT, C.QMF_PULSEIFFOCUS)
			pb.generic.callback = U.UI_BotSelectMenu_BotEvent
			pb.generic.id = k
			pb.generic.x = x - 16
			pb.generic.y = y - 16
			pb.generic.left = x
			pb.generic.top = y
			pb.generic.right = x + 64
			pb.generic.bottom = y + 64
			pb.width = 128
			pb.height = 128
			pb.focuspic = BOTSELECT_SELECT
			pb.focuscolor = Q.colorRed

			local pn = bsi.picnames[k]
			pn.generic.type = C.MTYPE_TEXT
			pn.generic.flags = C.QMF_SMALLFONT
			pn.generic.x = x + 32
			pn.generic.y = y + 64
			pn.string = bsi.botnames[k]
			pn.color = U.color_orange
			pn.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)

			x += 64 + 6
			k += 1
		end
		y += 64 + C.SMALLCHAR_HEIGHT + 6
	end

	bsi.arrows.generic.type = C.MTYPE_BITMAP
	bsi.arrows.generic.name = BOTSELECT_ARROWS
	bsi.arrows.generic.flags = C.QMF_INACTIVE
	bsi.arrows.generic.x = 260
	bsi.arrows.generic.y = 440
	bsi.arrows.width = 128
	bsi.arrows.height = 32

	bsi.left.generic.type = C.MTYPE_BITMAP
	bsi.left.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	bsi.left.generic.callback = U.UI_BotSelectMenu_LeftEvent
	bsi.left.generic.x = 260
	bsi.left.generic.y = 440
	bsi.left.width = 64
	bsi.left.height = 32
	bsi.left.focuspic = BOTSELECT_ARROWSL

	bsi.right.generic.type = C.MTYPE_BITMAP
	bsi.right.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	bsi.right.generic.callback = U.UI_BotSelectMenu_RightEvent
	bsi.right.generic.x = 321
	bsi.right.generic.y = 440
	bsi.right.width = 64
	bsi.right.height = 32
	bsi.right.focuspic = BOTSELECT_ARROWSR

	bsi.back.generic.type = C.MTYPE_BITMAP
	bsi.back.generic.name = BOTSELECT_BACK0
	bsi.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	bsi.back.generic.callback = U.UI_BotSelectMenu_BackEvent
	bsi.back.generic.x = 0
	bsi.back.generic.y = 480 - 64
	bsi.back.width = 128
	bsi.back.height = 64
	bsi.back.focuspic = BOTSELECT_BACK1

	bsi.go.generic.type = C.MTYPE_BITMAP
	bsi.go.generic.name = BOTSELECT_ACCEPT0
	bsi.go.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	bsi.go.generic.callback = U.UI_BotSelectMenu_SelectEvent
	bsi.go.generic.x = 640
	bsi.go.generic.y = 480 - 64
	bsi.go.width = 128
	bsi.go.height = 64
	bsi.go.focuspic = BOTSELECT_ACCEPT1

	U.Menu_AddItem(bsi.menu, bsi.banner)
	for i = 0, MAX_MODELSPERPAGE - 1 do
		U.Menu_AddItem(bsi.menu, bsi.pics[i])
		U.Menu_AddItem(bsi.menu, bsi.picbuttons[i])
		U.Menu_AddItem(bsi.menu, bsi.picnames[i])
	end
	U.Menu_AddItem(bsi.menu, bsi.arrows)
	U.Menu_AddItem(bsi.menu, bsi.left)
	U.Menu_AddItem(bsi.menu, bsi.right)
	U.Menu_AddItem(bsi.menu, bsi.back)
	U.Menu_AddItem(bsi.menu, bsi.go)

	U.UI_BotSelectMenu_BuildList()
	U.UI_BotSelectMenu_Default(bot)
	bsi.modelpage = Q.idiv(bsi.selectedmodel, MAX_MODELSPERPAGE)
	U.UI_BotSelectMenu_UpdateGrid()
end

function U.UI_BotSelectMenu(bot)
	U.UI_BotSelectMenu_Init(bot)
	U.UI_PushMenu(U.botSelectInfo.menu)
end

return U
