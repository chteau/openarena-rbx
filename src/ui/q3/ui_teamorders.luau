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
-- Luau port of code/q3_ui/ui_teamorders.c (OpenArena gamecode).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_FRAME = "menu/" .. C.MENU_ART_DIR .. "/addbotframe"
local ART_BACK0 = "menu/" .. C.MENU_ART_DIR .. "/back_0"
local ART_BACK1 = "menu/" .. C.MENU_ART_DIR .. "/back_1"

local ID_LIST_BOTS = 10
local ID_LIST_CTF_ORDERS = 11
local ID_LIST_CTF1F_ORDERS = 12
local ID_LIST_BASE_ORDERS = 13
local ID_LIST_TEAM_ORDERS = 14
local ID_LIST_DD_ORDERS = 15

local function newMenu()
	return { items = {}, nitems = 0, cursor = 0, cursor_prev = 0, wrapAround = false, fullscreen = false }
end

local function newItem()
	return { generic = { flags = 0, id = 0, x = 0, y = 0 } }
end

local function newInfo()
	local botNames = {}
	for n = 0, 8 do
		botNames[n] = ""
	end
	return {
		menu = newMenu(),
		banner = newItem(),
		frame = newItem(),
		list = newItem(),
		back = newItem(),
		gametype = 0,
		numBots = 0,
		selectedBot = 0,
		bots = {},
		botNames = botNames,
	}
end

local teamOrdersMenuInfo = newInfo()

local NUM_CTF_ORDERS = 7
local ctfOrders = {
	[0] = "I Am the Leader",
	"Defend the Base",
	"Follow Me",
	"Get Enemy Flag",
	"Camp Here",
	"Report",
	"I Relinquish Command",
}
local ctfMessages = {
	[0] = "i am the leader",
	"%s defend the base",
	"%s follow me",
	"%s get the enemy flag",
	"%s camp here",
	"%s report",
	"i stop being the leader",
}

local NUM_CTF1F_ORDERS = 7
local ctf1fOrders = {
	[0] = "I Am the Leader",
	"Defend the Base",
	"Follow Me",
	"Get The Flag",
	"Camp Here",
	"Report",
	"I Relinquish Command",
}
local ctf1fMessages = {
	[0] = "i am the leader",
	"%s defend the base",
	"%s follow me",
	"%s get the flag",
	"%s camp here",
	"%s report",
	"i stop being the leader",
}

local NUM_BASE_ORDERS = 7
local baseOrders = {
	[0] = "I Am the Leader",
	"Defend the Base",
	"Follow Me",
	"Attack the Enemy Base",
	"Camp Here",
	"Report",
	"I Relinquish Command",
}
local baseMessages = {
	[0] = "i am the leader",
	"%s defend the base",
	"%s follow me",
	"%s attack the base",
	"%s camp here",
	"%s report",
	"i stop being the leader",
}

local NUM_TEAM_ORDERS = 6
local teamOrders = {
	[0] = "I Am the Leader",
	"Follow Me",
	"Roam",
	"Camp Here",
	"Report",
	"I Relinquish Command",
}
local teamMessages = {
	[0] = "i am the leader",
	"%s follow me",
	"%s roam",
	"%s camp here",
	"%s report",
	"i stop being the leader",
}

local NUM_DD_ORDERS = 8
local ddOrders = {
	[0] = "I Am the Leader",
	"Follow Me",
	"Roam",
	"Dominate Point A",
	"Dominate Point B",
	"Camp Here",
	"Report",
	"I Relinquish Command",
}
local ddMessages = {
	[0] = "i am the leader",
	"%s follow me",
	"%s roam",
	"%s dominate point A",
	"%s dominate point B",
	"%s camp here",
	"%s report",
	"i stop being the leader",
}

local function atoi(s)
	local m = string.match(s, "^%s*([+-]?%d+)")
	if m == nil then
		return 0
	end
	return tonumber(m) :: number
end

local function infoValueForKey(info, key)
	local s = info
	if string.sub(s, 1, 1) == "\\" then
		s = string.sub(s, 2)
	end
	while s ~= "" do
		local sep = string.find(s, "\\", 1, true)
		if sep == nil then
			return ""
		end
		local k = string.sub(s, 1, sep - 1)
		s = string.sub(s, sep + 1)
		local nxt = string.find(s, "\\", 1, true)
		local v
		if nxt == nil then
			v = s
			s = ""
		else
			v = string.sub(s, 1, nxt - 1)
			s = string.sub(s, nxt + 1)
		end
		if string.lower(k) == string.lower(key) then
			return v
		end
	end
	return ""
end

local function cleanStr(str)
	local out = {}
	local i = 1
	local n = #str
	while i <= n do
		local c = string.sub(str, i, i)
		if c == "^" and i < n and string.sub(str, i + 1, i + 1) ~= "^" then
			i += 2
		else
			local b = string.byte(c)
			if b >= 32 and b <= 126 then
				table.insert(out, c)
			end
			i += 1
		end
	end
	return table.concat(out)
end

local function UI_TeamOrdersMenu_BackEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	U.UI_PopMenu()
end

local function UI_TeamOrdersMenu_SetList(id)
	local info = teamOrdersMenuInfo
	if id == ID_LIST_CTF_ORDERS then
		info.list.generic.id = id
		info.list.numitems = NUM_CTF_ORDERS
		info.list.itemnames = ctfOrders
	elseif id == ID_LIST_CTF1F_ORDERS then
		info.list.generic.id = id
		info.list.numitems = NUM_CTF1F_ORDERS
		info.list.itemnames = ctf1fOrders
	elseif id == ID_LIST_BASE_ORDERS then
		info.list.generic.id = id
		info.list.numitems = NUM_BASE_ORDERS
		info.list.itemnames = baseOrders
	elseif id == ID_LIST_TEAM_ORDERS then
		info.list.generic.id = id
		info.list.numitems = NUM_TEAM_ORDERS
		info.list.itemnames = teamOrders
	elseif id == ID_LIST_DD_ORDERS then
		info.list.generic.id = id
		info.list.numitems = NUM_DD_ORDERS
		info.list.itemnames = ddOrders
	else
		info.list.generic.id = id
		info.list.numitems = info.numBots
		info.list.itemnames = info.bots
	end

	info.list.generic.bottom = info.list.generic.top + info.list.numitems * C.PROP_HEIGHT
end

function U.UI_TeamOrdersMenu_Key(key)
	local l = U.Menu_ItemAtCursor(teamOrdersMenuInfo.menu)
	if l ~= teamOrdersMenuInfo.list then
		return U.Menu_DefaultKey(teamOrdersMenuInfo.menu, key)
	end

	if key == C.K_MOUSE1 then
		local x = l.generic.left
		local y = l.generic.top
		if U.UI_CursorInRect(x, y, l.generic.right - x, l.generic.bottom - y) then
			local index = math.floor((U.uis.cursory - y) / C.PROP_HEIGHT)
			l.oldvalue = l.curvalue
			l.curvalue = index

			if l.generic.callback ~= nil then
				l.generic.callback(l, C.QM_ACTIVATED)
				return U.menu_move_sound
			end
		end
		return U.menu_null_sound
	elseif key == C.K_KP_UPARROW or key == C.K_UPARROW then
		l.oldvalue = l.curvalue

		if l.curvalue == 0 then
			l.curvalue = l.numitems - 1
		else
			l.curvalue -= 1
		end
		return U.menu_move_sound
	elseif key == C.K_KP_DOWNARROW or key == C.K_DOWNARROW then
		l.oldvalue = l.curvalue

		if l.curvalue == l.numitems - 1 then
			l.curvalue = 0
		else
			l.curvalue += 1
		end
		return U.menu_move_sound
	end

	return U.Menu_DefaultKey(teamOrdersMenuInfo.menu, key)
end

local function UI_TeamOrdersMenu_ListDraw(self)
	local l = self

	local hasfocus = (l.generic.parent.cursor == l.generic.menuPosition)

	local x = 320 --l.generic.x
	local y = l.generic.y
	for i = 0, l.numitems - 1 do
		local style = bit32.bor(C.UI_LEFT, C.UI_SMALLFONT, C.UI_CENTER)
		local color
		if i == l.curvalue then
			color = U.color_yellow
			if hasfocus then
				style = bit32.bor(style, C.UI_PULSE)
			end
		else
			color = U.color_orange
		end

		U.UI_DrawProportionalString(x, y, l.itemnames[i], style, color)
		y += C.PROP_HEIGHT
	end
end

local function UI_TeamOrdersMenu_ListEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local info = teamOrdersMenuInfo
	local id = ptr.generic.id
	local selection = ptr.curvalue
	local message = ""

	if id == ID_LIST_BOTS then
		info.selectedBot = selection
		local gt = info.gametype
		if gt == C.GT_CTF or gt == C.GT_CTF_ELIMINATION then
			UI_TeamOrdersMenu_SetList(ID_LIST_CTF_ORDERS)
		end
		if gt == C.GT_1FCTF then
			UI_TeamOrdersMenu_SetList(ID_LIST_CTF1F_ORDERS)
		end
		if gt == C.GT_OBELISK or gt == C.GT_HARVESTER then
			UI_TeamOrdersMenu_SetList(ID_LIST_BASE_ORDERS)
		end
		if gt == C.GT_TEAM or gt == C.GT_ELIMINATION or gt == C.GT_DOMINATION then
			UI_TeamOrdersMenu_SetList(ID_LIST_TEAM_ORDERS)
		end
		if gt == C.GT_DOUBLE_D then
			UI_TeamOrdersMenu_SetList(ID_LIST_DD_ORDERS)
		end

		return
	end

	local botName = info.botNames[info.selectedBot]
	if id == ID_LIST_CTF_ORDERS then
		message = string.format(ctfMessages[selection], botName)
	end
	if id == ID_LIST_CTF1F_ORDERS then
		message = string.format(ctf1fMessages[selection], botName)
	end
	if id == ID_LIST_BASE_ORDERS then
		message = string.format(baseMessages[selection], botName)
	end
	if id == ID_LIST_TEAM_ORDERS then
		message = string.format(teamMessages[selection], botName)
	end
	if id == ID_LIST_DD_ORDERS then
		message = string.format(ddMessages[selection], botName)
	end

	trap.Cmd_ExecuteText(C.EXEC_APPEND, string.format("say_team \"%s\"\n", message))
	U.UI_PopMenu()
end

local function UI_TeamOrdersMenu_BuildBotList()
	local info = teamOrdersMenuInfo

	for n = 0, 8 do
		info.bots[n] = info.botNames[n]
	end

	local cs = {}
	trap.GetClientState(cs)

	info.botNames[0] = "Everyone"
	info.bots[0] = info.botNames[0]
	info.numBots = 1

	local infoStr = trap.GetConfigString(C.CS_SERVERINFO)
	local numPlayers = atoi(infoValueForKey(infoStr, "sv_maxclients"))
	info.gametype = atoi(infoValueForKey(infoStr, "g_gametype"))

	infoStr = trap.GetConfigString(C.CS_PLAYERS + cs.clientNum)
	local playerTeam = string.sub(infoValueForKey(infoStr, "t"), 1, 1)

	local n = 0
	while n < numPlayers and info.numBots < 9 do
		if n ~= cs.clientNum then
			infoStr = trap.GetConfigString(C.CS_PLAYERS + n)

			local isBot = atoi(infoValueForKey(infoStr, "skill"))
			if isBot ~= 0 then
				local botTeam = string.sub(infoValueForKey(infoStr, "t"), 1, 1)
				if botTeam == playerTeam then
					local name = cleanStr(string.sub(infoValueForKey(infoStr, "n"), 1, 15))
					info.botNames[info.numBots] = name
					info.bots[info.numBots] = name
					info.numBots += 1
				end
			end
		end
		n += 1
	end
end

function U.UI_TeamOrdersMenu_Cache()
	trap.R_RegisterShaderNoMip(ART_FRAME)
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
end

local function UI_TeamOrdersMenu_Init()
	U.UI_TeamOrdersMenu_Cache()

	teamOrdersMenuInfo = newInfo()
	local info = teamOrdersMenuInfo
	info.menu.fullscreen = false
	info.menu.key = U.UI_TeamOrdersMenu_Key

	UI_TeamOrdersMenu_BuildBotList()

	info.banner.generic.type = C.MTYPE_BTEXT
	info.banner.generic.x = 320
	info.banner.generic.y = 16
	info.banner.string = "TEAM ORDERS"
	info.banner.color = U.color_white
	info.banner.style = C.UI_CENTER

	info.frame.generic.type = C.MTYPE_BITMAP
	info.frame.generic.flags = C.QMF_INACTIVE
	info.frame.generic.name = ART_FRAME
	info.frame.generic.x = 320 - 233
	info.frame.generic.y = 240 - 166
	info.frame.width = 466
	info.frame.height = 332

	info.list.generic.type = C.MTYPE_SCROLLLIST
	info.list.generic.flags = C.QMF_PULSEIFFOCUS
	info.list.generic.ownerdraw = UI_TeamOrdersMenu_ListDraw
	info.list.generic.callback = UI_TeamOrdersMenu_ListEvent
	info.list.generic.x = 320 - 64
	info.list.generic.y = 120
	info.list.curvalue = 0
	info.list.oldvalue = 0

	info.back.generic.type = C.MTYPE_BITMAP
	info.back.generic.name = ART_BACK0
	info.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	info.back.generic.callback = UI_TeamOrdersMenu_BackEvent
	info.back.generic.x = 0
	info.back.generic.y = 480 - 64
	info.back.width = 128
	info.back.height = 64
	info.back.focuspic = ART_BACK1

	U.Menu_AddItem(info.menu, info.banner)
	U.Menu_AddItem(info.menu, info.frame)
	U.Menu_AddItem(info.menu, info.list)
	U.Menu_AddItem(info.menu, info.back)

	info.list.generic.left = 220
	info.list.generic.top = info.list.generic.y
	info.list.generic.right = 420
	UI_TeamOrdersMenu_SetList(ID_LIST_BOTS)
end

function U.UI_TeamOrdersMenu()
	UI_TeamOrdersMenu_Init()
	U.UI_PushMenu(teamOrdersMenuInfo.menu)
end

function U.UI_TeamOrdersMenu_f()
	-- make sure it's a team game
	local infoStr = trap.GetConfigString(C.CS_SERVERINFO)
	teamOrdersMenuInfo.gametype = atoi(infoValueForKey(infoStr, "g_gametype"))
	if teamOrdersMenuInfo.gametype < C.GT_TEAM or teamOrdersMenuInfo.gametype == C.GT_LMS or teamOrdersMenuInfo.gametype == C.GT_POSSESSION then
		return
	end

	-- not available to spectators
	local cs = {}
	trap.GetClientState(cs)
	infoStr = trap.GetConfigString(C.CS_PLAYERS + cs.clientNum)
	local team = atoi(infoValueForKey(infoStr, "t"))
	if team == C.TEAM_SPECTATOR then
		return
	end

	U.UI_TeamOrdersMenu()
end

return U
