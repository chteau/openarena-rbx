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
-- This part covers C lines 1-1220 of the 0.8.8 source.

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local MENU_ART_DIR = "art_blueish"

local GAMESERVER_BACK0 = "menu/" .. MENU_ART_DIR .. "/back_0"
local GAMESERVER_BACK1 = "menu/" .. MENU_ART_DIR .. "/back_1"
local GAMESERVER_NEXT0 = "menu/" .. MENU_ART_DIR .. "/next_0"
local GAMESERVER_NEXT1 = "menu/" .. MENU_ART_DIR .. "/next_1"
local GAMESERVER_FRAMEL = "menu/" .. MENU_ART_DIR .. "/frame2_l"
local GAMESERVER_FRAMER = "menu/" .. MENU_ART_DIR .. "/frame1_r"
local GAMESERVER_SELECT = "menu/" .. MENU_ART_DIR .. "/maps_select"
local GAMESERVER_SELECTED = "menu/" .. MENU_ART_DIR .. "/maps_selected"
local GAMESERVER_UNKNOWNMAP = "menu/art/unknownmap"
local GAMESERVER_ARROWS = "menu/" .. MENU_ART_DIR .. "/gs_arrows_0"
local GAMESERVER_ARROWSL = "menu/" .. MENU_ART_DIR .. "/gs_arrows_l"
local GAMESERVER_ARROWSR = "menu/" .. MENU_ART_DIR .. "/gs_arrows_r"

local MAX_MAPROWS = 4
local MAX_MAPCOLS = 2
local MAX_MAPSPERPAGE = MAX_MAPROWS * MAX_MAPCOLS

local MAX_NAMELENGTH = 16

local ID_GAMETYPE = 10
local ID_PICTURES = 11
local ID_PREVPAGE = 19
local ID_NEXTPAGE = 20
local ID_STARTSERVERBACK = 21
local ID_STARTSERVERNEXT = 22
local ID_AUTONEXTMAP = 23

local ID_PLAYER_TYPE = 25
local ID_MAXCLIENTS = 26
local ID_GO = 28
local ID_BACK = 29

local PLAYER_SLOTS = 12

local function newItem()
	return { generic = {} }
end

local function newMenu()
	if T.menuframework_s then
		return T.menuframework_s()
	end
	return { cursor = 0, cursor_prev = 0, nitems = 0, items = {}, wrapAround = false, fullscreen = false }
end

local function setFlag(item, f)
	item.generic.flags = bit32.bor(item.generic.flags or 0, f)
end

local function clearFlag(item, f)
	item.generic.flags = bit32.band(item.generic.flags or 0, bit32.bnot(f))
end

local function atoi(s)
	local m = string.match(s, "^%s*([+-]?%d+)")
	if m == nil then
		return 0
	end
	return tonumber(m)
end

local function clamp(minV, maxV, value)
	if value < minV then
		return minV
	end
	if value > maxV then
		return maxV
	end
	return value
end

local function cleanStr(s)
	local out = {}
	local i = 1
	local n = #s
	while i <= n do
		local ch = string.sub(s, i, i)
		if ch == "^" and i < n and string.sub(s, i + 1, i + 1) ~= "^" then
			i += 2
		else
			local b = string.byte(ch)
			if b >= 32 and b < 127 then
				table.insert(out, ch)
			end
			i += 1
		end
	end
	return table.concat(out)
end

local function newStartServer()
	local s = {
		menu = newMenu(),
		banner = newItem(),
		framel = newItem(),
		framer = newItem(),
		gametype = newItem(),
		autonextmap = newItem(),
		mappics = {},
		mapbuttons = {},
		arrows = newItem(),
		prevpage = newItem(),
		nextpage = newItem(),
		back = newItem(),
		next = newItem(),
		mapname = newItem(),
		item_null = newItem(),
		multiplayer = false,
		currentmap = 0,
		nummaps = 0,
		page = 0,
		maxpages = 0,
		maplist = {},
	}
	for i = 0, MAX_MAPSPERPAGE - 1 do
		s.mappics[i] = newItem()
		s.mapbuttons[i] = newItem()
	end
	s.autonextmap.curvalue = 0
	s.gametype.curvalue = 0
	s.mapname.string = ""
	return s
end

local function newServerOptions()
	local s = {
		menu = newMenu(),
		banner = newItem(),
		mappic = newItem(),
		picframe = newItem(),
		timelimit = newItem(),
		fraglimit = newItem(),
		flaglimit = newItem(),
		friendlyfire = newItem(),
		hostname = newItem(),
		pure = newItem(),
		lan = newItem(),
		pmove = newItem(),
		oneway = newItem(),
		instantgib = newItem(),
		rockets = newItem(),
		lmsMode = newItem(),
		botSkill = newItem(),
		player0 = newItem(),
		playerType = {},
		playerName = {},
		playerTeam = {},
		go = newItem(),
		next = newItem(),
		back = newItem(),
		multiplayer = false,
		gametype = 0,
		mapnamebuffer = "",
		playerNameBuffers = {},
		newBot = false,
		newBotIndex = 0,
		newBotName = "",
	}
	for i = 0, PLAYER_SLOTS - 1 do
		s.playerType[i] = newItem()
		s.playerName[i] = newItem()
		s.playerTeam[i] = newItem()
		s.playerType[i].curvalue = 0
		s.playerTeam[i].curvalue = 0
		s.playerNameBuffers[i] = ""
	end
	for _, k in { "timelimit", "fraglimit", "flaglimit", "hostname" } do
		s[k].field = { buffer = "" }
	end
	for _, k in { "friendlyfire", "pure", "lan", "pmove", "oneway", "instantgib", "rockets", "lmsMode", "botSkill" } do
		s[k].curvalue = 0
	end
	return s
end

U.s_startserver = newStartServer()
U.s_serveroptions = newServerOptions()

local gametype_items = {
	[0] = "Free For All",
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

local gametype_remap = {
	[0] = C.GT_FFA,
	C.GT_TEAM,
	C.GT_TOURNAMENT,
	C.GT_CTF,
	C.GT_1FCTF,
	C.GT_OBELISK,
	C.GT_HARVESTER,
	C.GT_ELIMINATION,
	C.GT_CTF_ELIMINATION,
	C.GT_LMS,
	C.GT_DOUBLE_D,
	C.GT_DOMINATION,
}

local gametype_remap2 = { [0] = 0, 2, 0, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }

local playerType_list = { [0] = "Open", "Bot", "----" }
local playerTeam_list = { [0] = "Blue", "Red" }
local botSkill_list = { [0] = "I Can Win", "Bring It On", "Hurt Me Plenty", "Hardcore", "Nightmare!" }
local lmsMode_list = { [0] = "Round+OT", "Round-OT", "Kill+OT", "Kill-OT" }
local pmove_list = { [0] = "Framerate dependent", "Fixed framerate 125Hz", "Fixed framerate 91Hz", "Accurate" }

U.gametype_items = gametype_items
U.gametype_remap = gametype_remap
U.gametype_remap2 = gametype_remap2
U.playerType_list = playerType_list
U.playerTeam_list = playerTeam_list
U.botSkill_list = botSkill_list
U.lmsMode_list = lmsMode_list
U.pmove_list = pmove_list

local gametypeTokenBits = {
	ffa = { C.GT_FFA },
	tourney = { C.GT_TOURNAMENT },
	single = { C.GT_SINGLE_PLAYER },
	team = { C.GT_TEAM },
	ctf = { C.GT_CTF },
	oneflag = { C.GT_1FCTF },
	overload = { C.GT_OBELISK },
	harvester = { C.GT_HARVESTER },
	elimination = { C.GT_ELIMINATION },
	ctfelimination = { C.GT_CTF_ELIMINATION },
	lms = { C.GT_LMS },
	dd = { C.GT_DOUBLE_D },
	dom = { C.GT_DOMINATION },
}

-- GametypeBits from arenas.txt + .arena files
function U.GametypeBits(str)
	local bits = 0
	for token in string.gmatch(str, "%S+") do
		local list = gametypeTokenBits[string.lower(token)]
		if list ~= nil then
			for _, gt in list do
				bits = bit32.bor(bits, bit32.lshift(1, gt))
			end
		end
	end
	return bits
end

local picname = {}
for i = 0, MAX_MAPSPERPAGE - 1 do
	picname[i] = ""
end

function U.StartServer_Update()
	local s = U.s_startserver
	local top = s.page * MAX_MAPSPERPAGE

	local i = 0
	while i < MAX_MAPSPERPAGE do
		if top + i >= s.nummaps then
			break
		end
		local info = U.UI_GetArenaInfoByNumber(s.maplist[top + i])
		local mapname = string.upper(string.sub(Q.Info_ValueForKey(info, "map"), 1, MAX_NAMELENGTH - 1))

		picname[i] = Q.va("levelshots/%s", mapname)

		clearFlag(s.mappics[i], C.QMF_HIGHLIGHT)
		s.mappics[i].generic.name = picname[i]
		s.mappics[i].shader = 0

		setFlag(s.mapbuttons[i], C.QMF_PULSEIFFOCUS)
		clearFlag(s.mapbuttons[i], C.QMF_INACTIVE)
		i += 1
	end

	while i < MAX_MAPSPERPAGE do
		clearFlag(s.mappics[i], C.QMF_HIGHLIGHT)
		s.mappics[i].generic.name = nil
		s.mappics[i].shader = 0

		clearFlag(s.mapbuttons[i], C.QMF_PULSEIFFOCUS)
		setFlag(s.mapbuttons[i], C.QMF_INACTIVE)
		i += 1
	end

	if s.nummaps == 0 then
		setFlag(s.next, C.QMF_INACTIVE)
		s.mapname.string = "NO MAPS FOUND"
	else
		clearFlag(s.next, C.QMF_INACTIVE)
		i = s.currentmap - top
		if i >= 0 and i < MAX_MAPSPERPAGE then
			setFlag(s.mappics[i], C.QMF_HIGHLIGHT)
			clearFlag(s.mapbuttons[i], C.QMF_PULSEIFFOCUS)
		end

		local info = U.UI_GetArenaInfoByNumber(s.maplist[s.currentmap])
		s.mapname.string = string.sub(Q.Info_ValueForKey(info, "map"), 1, MAX_NAMELENGTH - 1)
	end

	s.mapname.string = string.upper(s.mapname.string)
end

function U.StartServer_MapEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local s = U.s_startserver
	s.currentmap = (s.page * MAX_MAPSPERPAGE) + (ptr.generic.id - ID_PICTURES)
	U.StartServer_Update()
end

function U.WriteMapList2File(gametype, filename)
	local len, f = trap.FS_FOpenFile(filename, C.FS_WRITE)

	if len < 0 then
		trap.Print(Q.va("WriteMapList2File: Failed to open file %s, length: %i\n", filename, len))
		return
	end

	local count = U.UI_GetNumArenas()
	local matchbits = bit32.lshift(1, gametype)
	for i = 0, count - 1 do
		local info = U.UI_GetArenaInfoByNumber(i)

		local gamebits = U.GametypeBits(Q.Info_ValueForKey(info, "type"))
		if bit32.band(gamebits, matchbits) == 0 then
			continue
		end
		local mapname = Q.va("%s ", Q.Info_ValueForKey(info, "map"))
		trap.FS_Write(mapname, #mapname, f)
	end
	trap.FS_FCloseFile(f)
end

function U.WriteMapList()
	local mappoolstring = trap.Cvar_VariableStringBuffer("g_mappools")
	trap.Print(Q.va("g_mappools: %s\n", mappoolstring))
	for i = 0, C.GT_MAX_GAME_TYPE - 1 do
		local filename = string.sub(Q.Info_ValueForKey(mappoolstring, Q.va("%i", i)), 1, 143)
		if #filename > 0 then
			trap.Print(Q.va("Writing gamtype %i to %s\n", i, filename))
			U.WriteMapList2File(i, filename)
		end
	end
end

function U.StartServer_GametypeEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local s = U.s_startserver
	local count = U.UI_GetNumArenas()
	s.nummaps = 0
	local gt = gametype_remap[s.gametype.curvalue]
	local matchbits = bit32.lshift(1, gt)
	if gt == C.GT_FFA then
		matchbits = bit32.bor(matchbits, bit32.lshift(1, C.GT_SINGLE_PLAYER))
	end
	for i = 0, count - 1 do
		local info = U.UI_GetArenaInfoByNumber(i)

		local gamebits = U.GametypeBits(Q.Info_ValueForKey(info, "type"))
		if bit32.band(gamebits, matchbits) == 0 then
			continue
		end

		s.maplist[s.nummaps] = i
		s.nummaps += 1
	end
	s.maxpages = Q.idiv(s.nummaps + MAX_MAPSPERPAGE - 1, MAX_MAPSPERPAGE)
	s.page = 0
	s.currentmap = 0

	U.StartServer_Update()
end

function U.StartServer_MenuEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local s = U.s_startserver
	local id = ptr.generic.id
	if id == ID_PREVPAGE then
		if s.page > 0 then
			s.page -= 1
			U.StartServer_Update()
		end
	elseif id == ID_NEXTPAGE then
		if s.page < s.maxpages - 1 then
			s.page += 1
			U.StartServer_Update()
		end
	elseif id == ID_STARTSERVERNEXT then
		trap.Cvar_SetValue("g_gameType", gametype_remap[s.gametype.curvalue])
		U.UI_ServerOptionsMenu(s.multiplayer)
	elseif id == ID_AUTONEXTMAP then
		trap.Cvar_SetValue("g_autonextmap", s.autonextmap.curvalue)
	elseif id == ID_STARTSERVERBACK then
		U.UI_PopMenu()
	end
end

function U.StartServer_LevelshotDraw(b)
	local s = U.s_startserver

	if b.generic.name == nil then
		return
	end

	if b.generic.name ~= nil and (b.shader == nil or b.shader == 0) then
		b.shader = trap.R_RegisterShaderNoMip(b.generic.name)
		if b.shader == 0 and b.errorpic ~= nil then
			b.shader = trap.R_RegisterShaderNoMip(b.errorpic)
		end
	end

	if b.focuspic ~= nil and (b.focusshader == nil or b.focusshader == 0) then
		b.focusshader = trap.R_RegisterShaderNoMip(b.focuspic)
	end

	local x = b.generic.x
	local y = b.generic.y
	local w = b.width
	local h = b.height
	if b.shader ~= 0 then
		U.UI_DrawHandlePic(x, y, w, h, b.shader)
	end

	x = b.generic.x
	y = b.generic.y + b.height
	U.UI_FillRect(x, y, b.width, 28, Q.colorBlack)

	x += Q.idiv(b.width, 2)
	y += 4
	local n = s.page * MAX_MAPSPERPAGE + b.generic.id - ID_PICTURES

	local info = U.UI_GetArenaInfoByNumber(s.maplist[n])
	U.UI_DrawString(x, y, Q.Info_ValueForKey(info, "map"), bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_orange)

	x = b.generic.x
	y = b.generic.y
	w = b.width
	h = b.height + 28
	if bit32.band(b.generic.flags, C.QMF_HIGHLIGHT) ~= 0 then
		U.UI_DrawHandlePic(x, y, w, h, b.focusshader)
	end
end

function U.StartServer_MenuInit()
	U.s_startserver = newStartServer()
	local s = U.s_startserver

	U.StartServer_Cache()

	s.autonextmap.curvalue = trap.Cvar_VariableValue("g_autonextmap") ~= 0 and 1 or 0

	s.menu.wrapAround = true
	s.menu.fullscreen = true

	s.banner.generic.type = C.MTYPE_BTEXT
	s.banner.generic.x = 320
	s.banner.generic.y = 16
	s.banner.string = "GAME SERVER"
	s.banner.color = U.color_white
	s.banner.style = C.UI_CENTER

	s.framel.generic.type = C.MTYPE_BITMAP
	s.framel.generic.name = GAMESERVER_FRAMEL
	s.framel.generic.flags = C.QMF_INACTIVE
	s.framel.generic.x = 0
	s.framel.generic.y = 78
	s.framel.width = 256
	s.framel.height = 329

	s.framer.generic.type = C.MTYPE_BITMAP
	s.framer.generic.name = GAMESERVER_FRAMER
	s.framer.generic.flags = C.QMF_INACTIVE
	s.framer.generic.x = 376
	s.framer.generic.y = 76
	s.framer.width = 256
	s.framer.height = 334

	s.autonextmap.generic.type = C.MTYPE_RADIOBUTTON
	s.autonextmap.generic.name = "Auto change map:"
	s.autonextmap.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	s.autonextmap.generic.callback = U.StartServer_MenuEvent
	s.autonextmap.generic.id = ID_AUTONEXTMAP
	s.autonextmap.generic.x = 320 + 24
	s.autonextmap.generic.y = 368

	s.gametype.generic.type = C.MTYPE_SPINCONTROL
	s.gametype.generic.name = "Game Type:"
	s.gametype.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	s.gametype.generic.callback = U.StartServer_GametypeEvent
	s.gametype.generic.id = ID_GAMETYPE
	s.gametype.generic.x = 320 - 24
	s.gametype.generic.y = 70
	s.gametype.itemnames = gametype_items

	for i = 0, MAX_MAPSPERPAGE - 1 do
		local x = Q.idiv(640 - MAX_MAPROWS * 140, 2) + ((i % MAX_MAPROWS) * 140)
		local y = 96 + (Q.idiv(i, MAX_MAPROWS) * 140)

		local pic = s.mappics[i]
		pic.generic.type = C.MTYPE_BITMAP
		pic.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
		pic.generic.x = x
		pic.generic.y = y
		pic.generic.id = ID_PICTURES + i
		pic.width = 128
		pic.height = 96
		pic.focuspic = GAMESERVER_SELECTED
		pic.errorpic = GAMESERVER_UNKNOWNMAP
		pic.generic.ownerdraw = U.StartServer_LevelshotDraw

		local btn = s.mapbuttons[i]
		btn.generic.type = C.MTYPE_BITMAP
		btn.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS, C.QMF_NODEFAULTINIT)
		btn.generic.id = ID_PICTURES + i
		btn.generic.callback = U.StartServer_MapEvent
		btn.generic.x = x - 30
		btn.generic.y = y - 32
		btn.width = 256
		btn.height = 248
		btn.generic.left = x
		btn.generic.top = y
		btn.generic.right = x + 128
		btn.generic.bottom = y + 128
		btn.focuspic = GAMESERVER_SELECT
	end

	s.arrows.generic.type = C.MTYPE_BITMAP
	s.arrows.generic.name = GAMESERVER_ARROWS
	s.arrows.generic.flags = C.QMF_INACTIVE
	s.arrows.generic.x = 260
	s.arrows.generic.y = 400
	s.arrows.width = 128
	s.arrows.height = 32

	s.prevpage.generic.type = C.MTYPE_BITMAP
	s.prevpage.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.prevpage.generic.callback = U.StartServer_MenuEvent
	s.prevpage.generic.id = ID_PREVPAGE
	s.prevpage.generic.x = 260
	s.prevpage.generic.y = 400
	s.prevpage.width = 64
	s.prevpage.height = 32
	s.prevpage.focuspic = GAMESERVER_ARROWSL

	s.nextpage.generic.type = C.MTYPE_BITMAP
	s.nextpage.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.nextpage.generic.callback = U.StartServer_MenuEvent
	s.nextpage.generic.id = ID_NEXTPAGE
	s.nextpage.generic.x = 321
	s.nextpage.generic.y = 400
	s.nextpage.width = 64
	s.nextpage.height = 32
	s.nextpage.focuspic = GAMESERVER_ARROWSR

	s.mapname.generic.type = C.MTYPE_PTEXT
	s.mapname.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_INACTIVE)
	s.mapname.generic.x = 320
	s.mapname.generic.y = 440
	s.mapname.string = ""
	s.mapname.style = bit32.bor(C.UI_CENTER, C.UI_BIGFONT)
	s.mapname.color = U.text_color_normal

	s.back.generic.type = C.MTYPE_BITMAP
	s.back.generic.name = GAMESERVER_BACK0
	s.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.back.generic.callback = U.StartServer_MenuEvent
	s.back.generic.id = ID_STARTSERVERBACK
	s.back.generic.x = 0
	s.back.generic.y = 480 - 64
	s.back.width = 128
	s.back.height = 64
	s.back.focuspic = GAMESERVER_BACK1

	s.next.generic.type = C.MTYPE_BITMAP
	s.next.generic.name = GAMESERVER_NEXT0
	s.next.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.next.generic.callback = U.StartServer_MenuEvent
	s.next.generic.id = ID_STARTSERVERNEXT
	s.next.generic.x = 640
	s.next.generic.y = 480 - 64
	s.next.width = 128
	s.next.height = 64
	s.next.focuspic = GAMESERVER_NEXT1

	s.item_null.generic.type = C.MTYPE_BITMAP
	s.item_null.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_MOUSEONLY, C.QMF_SILENT)
	s.item_null.generic.x = 0
	s.item_null.generic.y = 0
	s.item_null.width = 640
	s.item_null.height = 480

	U.Menu_AddItem(s.menu, s.banner)
	U.Menu_AddItem(s.menu, s.framel)
	U.Menu_AddItem(s.menu, s.framer)

	U.Menu_AddItem(s.menu, s.gametype)
	U.Menu_AddItem(s.menu, s.autonextmap)
	for i = 0, MAX_MAPSPERPAGE - 1 do
		U.Menu_AddItem(s.menu, s.mappics[i])
		U.Menu_AddItem(s.menu, s.mapbuttons[i])
	end

	U.Menu_AddItem(s.menu, s.arrows)
	U.Menu_AddItem(s.menu, s.prevpage)
	U.Menu_AddItem(s.menu, s.nextpage)
	U.Menu_AddItem(s.menu, s.back)
	U.Menu_AddItem(s.menu, s.next)
	U.Menu_AddItem(s.menu, s.mapname)
	U.Menu_AddItem(s.menu, s.item_null)

	U.StartServer_GametypeEvent(nil, C.QM_ACTIVATED)
end

function U.StartServer_Cache()
	trap.R_RegisterShaderNoMip(GAMESERVER_BACK0)
	trap.R_RegisterShaderNoMip(GAMESERVER_BACK1)
	trap.R_RegisterShaderNoMip(GAMESERVER_NEXT0)
	trap.R_RegisterShaderNoMip(GAMESERVER_NEXT1)
	trap.R_RegisterShaderNoMip(GAMESERVER_FRAMEL)
	trap.R_RegisterShaderNoMip(GAMESERVER_FRAMER)
	trap.R_RegisterShaderNoMip(GAMESERVER_SELECT)
	trap.R_RegisterShaderNoMip(GAMESERVER_SELECTED)
	trap.R_RegisterShaderNoMip(GAMESERVER_UNKNOWNMAP)
	trap.R_RegisterShaderNoMip(GAMESERVER_ARROWS)
	trap.R_RegisterShaderNoMip(GAMESERVER_ARROWSL)
	trap.R_RegisterShaderNoMip(GAMESERVER_ARROWSR)

	local precache = trap.Cvar_VariableValue("com_buildscript") ~= 0

	if precache then
		for i = 0, U.UI_GetNumArenas() - 1 do
			local info = U.UI_GetArenaInfoByNumber(i)
			local mapname = string.upper(string.sub(Q.Info_ValueForKey(info, "map"), 1, MAX_NAMELENGTH - 1))

			trap.R_RegisterShaderNoMip(Q.va("levelshots/%s", mapname))
		end
	end
end

function U.UI_StartServerMenu(multiplayer)
	U.StartServer_MenuInit()
	U.s_startserver.multiplayer = multiplayer
	U.UI_PushMenu(U.s_startserver.menu)
end

--[[
=============================================================================

SERVER OPTIONS MENU *****

=============================================================================
]]

local function isTeamMode(gametype)
	return gametype >= C.GT_TEAM and gametype ~= C.GT_LMS
end

function U.BotAlreadySelected(checkName)
	local so = U.s_serveroptions
	for n = 1, PLAYER_SLOTS - 1 do
		if so.playerType[n].curvalue ~= 1 then
			continue
		end
		if
			isTeamMode(so.gametype)
			and so.playerTeam[n].curvalue ~= so.playerTeam[so.newBotIndex].curvalue
		then
			continue
		end
		if Q.stricmp(checkName, so.playerNameBuffers[n]) == 0 then
			return true
		end
	end

	return false
end

local limitCvars = {
	[C.GT_TOURNAMENT] = { "ui_tourney_fraglimit", "ui_tourney_timelimit", nil },
	[C.GT_TEAM] = { "ui_team_fraglimit", "ui_team_timelimit", "ui_team_friendlt" },
	[C.GT_CTF] = { "ui_ctf_fraglimit", "ui_ctf_timelimit", "ui_ctf_friendlt" },
	[C.GT_1FCTF] = { "ui_1fctf_capturelimit", "ui_1fctf_timelimit", "ui_1fctf_friendlt" },
	[C.GT_OBELISK] = { "ui_overload_capturelimit", "ui_overload_timelimit", "ui_overload_friendlt" },
	[C.GT_HARVESTER] = { "ui_harvester_capturelimit", "ui_harvester_timelimit", "ui_harvester_friendlt" },
	[C.GT_ELIMINATION] = { "ui_elimination_capturelimit", "ui_elimination_timelimit", nil },
	[C.GT_CTF_ELIMINATION] = { "ui_ctf_elimination_capturelimit", "ui_ctf_elimination_timelimit", nil },
	[C.GT_LMS] = { "ui_lms_fraglimit", "ui_lms_timelimit", nil },
	[C.GT_DOUBLE_D] = { "ui_dd_capturelimit", "ui_dd_timelimit", "ui_dd_friendlt" },
}
local defaultLimitCvars = { "ui_ffa_fraglimit", "ui_ffa_timelimit", nil }

function U.ServerOptions_Start()
	local so = U.s_serveroptions
	local ss = U.s_startserver

	local timelimit = atoi(so.timelimit.field.buffer)
	local fraglimit = atoi(so.fraglimit.field.buffer)
	local flaglimit = atoi(so.flaglimit.field.buffer)
	local friendlyfire = so.friendlyfire.curvalue
	local pure = so.pure.curvalue
	local lan = so.lan.curvalue
	local pmove = so.pmove.curvalue
	local instantgib = so.instantgib.curvalue
	local rockets = so.rockets.curvalue
	local oneway = so.oneway.curvalue
	local lmsMode = so.lmsMode.curvalue
	local skill = so.botSkill.curvalue + 1

	local maxclients = 0
	for n = 0, PLAYER_SLOTS - 1 do
		if so.playerType[n].curvalue == 2 then
			continue
		end
		if so.playerType[n].curvalue == 1 and so.playerNameBuffers[n] == "" then
			continue
		end
		maxclients += 1
	end

	local names = limitCvars[so.gametype] or defaultLimitCvars
	trap.Cvar_SetValue(names[1], fraglimit)
	trap.Cvar_SetValue(names[2], timelimit)
	if names[3] ~= nil then
		trap.Cvar_SetValue(names[3], friendlyfire)
	end

	trap.Cvar_SetValue("sv_maxclients", clamp(0, 12, maxclients))
	trap.Cvar_SetValue("timelimit", clamp(0, timelimit, timelimit))
	trap.Cvar_SetValue("fraglimit", clamp(0, fraglimit, fraglimit))
	trap.Cvar_SetValue("capturelimit", clamp(0, flaglimit, flaglimit))
	trap.Cvar_SetValue("g_friendlyfire", friendlyfire)
	trap.Cvar_SetValue("sv_public", pure) -- Roblox: the Public Server toggle, was sv_pure
	trap.Cvar_SetValue("sv_lanForceRate", lan)
	trap.Cvar_SetValue("g_instantgib", instantgib)
	trap.Cvar_SetValue("g_rockets", rockets)
	trap.Cvar_SetValue("g_lms_mode", lmsMode)
	trap.Cvar_SetValue("elimination_ctf_oneway", oneway)
	if pmove == 1 then
		trap.Cvar_SetValue("pmove_fixed", 1)
		trap.Cvar_SetValue("pmove_msec", 8)
		trap.Cvar_SetValue("pmove_float", 0)
	elseif pmove == 2 then
		trap.Cvar_SetValue("pmove_fixed", 1)
		trap.Cvar_SetValue("pmove_msec", 11)
		trap.Cvar_SetValue("pmove_float", 0)
	elseif pmove == 3 then
		trap.Cvar_SetValue("pmove_fixed", 0)
		trap.Cvar_SetValue("pmove_float", 1)
	else
		trap.Cvar_SetValue("pmove_fixed", 0)
		trap.Cvar_SetValue("pmove_float", 0)
	end
	trap.Cvar_Set("sv_hostname", so.hostname.field.buffer)

	-- the wait commands will allow the dedicated to take effect
	local info = U.UI_GetArenaInfoByNumber(ss.maplist[ss.currentmap])
	trap.Cmd_ExecuteText(C.EXEC_APPEND, Q.va("wait ; wait ; map %s\n", Q.Info_ValueForKey(info, "map")))

	-- add bots
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "wait 3\n")
	for n = 1, PLAYER_SLOTS - 1 do
		if so.playerType[n].curvalue ~= 1 then
			continue
		end
		if so.playerNameBuffers[n] == "" then
			continue
		end
		if string.sub(so.playerNameBuffers[n], 1, 1) == "-" then
			continue
		end
		local buf
		if isTeamMode(so.gametype) then
			buf = Q.va("addbot %s %i %s\n", so.playerNameBuffers[n], skill, playerTeam_list[so.playerTeam[n].curvalue])
		else
			buf = Q.va("addbot %s %i\n", so.playerNameBuffers[n], skill)
		end
		trap.Cmd_ExecuteText(C.EXEC_APPEND, buf)
	end

	-- set player's team
	if isTeamMode(so.gametype) then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, Q.va("wait 5; team %s\n", playerTeam_list[so.playerTeam[0].curvalue]))
	end
end

function U.ServerOptions_InitPlayerItems()
	local so = U.s_serveroptions

	local v
	if so.multiplayer then
		v = 0
	else
		v = 1
	end

	for n = 0, PLAYER_SLOTS - 1 do
		so.playerType[n].curvalue = v
	end

	if so.multiplayer and (so.gametype < C.GT_TEAM or so.gametype == C.GT_LMS) then
		for n = 8, PLAYER_SLOTS - 1 do
			so.playerType[n].curvalue = 2
		end
	end

	-- if not a dedicated server, first slot is reserved for the human on the server
	setFlag(so.playerType[0], C.QMF_INACTIVE)
	so.playerType[0].curvalue = 0
	so.playerNameBuffers[0] = string.sub(trap.Cvar_VariableStringBuffer("name"), 1, 15)
	so.playerNameBuffers[0] = cleanStr(so.playerNameBuffers[0])

	if isTeamMode(so.gametype) then
		local n = 0
		while n < PLAYER_SLOTS // 2 do
			so.playerTeam[n].curvalue = 0
			n += 1
		end
		while n < PLAYER_SLOTS do
			so.playerTeam[n].curvalue = 1
			n += 1
		end
	else
		for n = 0, PLAYER_SLOTS - 1 do
			setFlag(so.playerTeam[n], bit32.bor(C.QMF_INACTIVE, C.QMF_HIDDEN))
		end
	end
end

function U.ServerOptions_SetPlayerItems()
	local so = U.s_serveroptions

	so.player0.string = "Human"
	clearFlag(so.playerName[0], C.QMF_HIDDEN)

	local start = 1
	for n = start, PLAYER_SLOTS - 1 do
		if so.playerType[n].curvalue == 1 then
			clearFlag(so.playerName[n], bit32.bor(C.QMF_INACTIVE, C.QMF_HIDDEN))
		else
			setFlag(so.playerName[n], bit32.bor(C.QMF_INACTIVE, C.QMF_HIDDEN))
		end
	end

	if so.gametype < C.GT_TEAM or so.gametype == C.GT_LMS then
		return
	end
	for n = start, PLAYER_SLOTS - 1 do
		if so.playerType[n].curvalue == 2 then
			setFlag(so.playerTeam[n], bit32.bor(C.QMF_INACTIVE, C.QMF_HIDDEN))
		else
			clearFlag(so.playerTeam[n], bit32.bor(C.QMF_INACTIVE, C.QMF_HIDDEN))
		end
	end
end

function U.ServerOptions_Event(ptr, event)
	local id = ptr.generic.id

	if id == ID_PLAYER_TYPE then
		if event ~= C.QM_ACTIVATED then
			return
		end
		U.ServerOptions_SetPlayerItems()
	elseif id == ID_MAXCLIENTS then
		U.ServerOptions_SetPlayerItems()
	elseif id == ID_GO then
		if event ~= C.QM_ACTIVATED then
			return
		end
		U.ServerOptions_Start()
	elseif id == ID_BACK then
		if event ~= C.QM_ACTIVATED then
			return
		end
		U.UI_PopMenu()
	end
end

return U
