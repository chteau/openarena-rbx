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
-- Luau port of code/q3_ui/ui_removebots.c (OpenArena 0.8.8, gamecode 9e0f0c0).

--[[
=======================================================================

REMOVE BOTS MENU

=======================================================================
]]

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_BACKGROUND = "menu/art_blueish/addbotframe"
local ART_BACK0 = "menu/art_blueish/back_0"
local ART_BACK1 = "menu/art_blueish/back_1"
local ART_DELETE0 = "menu/art_blueish/delete_0"
local ART_DELETE1 = "menu/art_blueish/delete_1"
local ART_ARROWS = "menu/art_blueish/arrows_vert_0"
local ART_ARROWUP = "menu/art_blueish/arrows_vert_top"
local ART_ARROWDOWN = "menu/art_blueish/arrows_vert_bot"

local ID_UP = 10
local ID_DOWN = 11
local ID_DELETE = 12
local ID_BACK = 13
local ID_BOTNAME0 = 20

local function newItem()
	return { generic = {} }
end

local removeBotsMenuInfo

local function resetInfo()
	removeBotsMenuInfo = {
		menu = { items = {}, nitems = 0 },
		banner = newItem(),
		background = newItem(),
		arrows = newItem(),
		up = newItem(),
		down = newItem(),
		bots = {},
		delete = newItem(),
		back = newItem(),
		numBots = 0,
		baseBotNum = 0,
		selectedBotNum = 0,
		botnames = {},
		botClientNums = {},
	}
	for i = 0, 6 do
		removeBotsMenuInfo.bots[i] = newItem()
		removeBotsMenuInfo.botnames[i] = ""
	end
end
resetInfo()

local function UI_RemoveBotsMenu_SetBotNames()
	local n = 0
	while n < 7 and removeBotsMenuInfo.baseBotNum + n < removeBotsMenuInfo.numBots do
		local info =
			trap.GetConfigString(C.CS_PLAYERS + removeBotsMenuInfo.botClientNums[removeBotsMenuInfo.baseBotNum + n])
		removeBotsMenuInfo.botnames[n] = Q.CleanStr(string.sub(Q.Info_ValueForKey(info, "n"), 1, 31))
		-- C's items point at the botnames buffers; a Luau string is a copy
		removeBotsMenuInfo.bots[n].string = removeBotsMenuInfo.botnames[n]
		n += 1
	end
end

local function UI_RemoveBotsMenu_DeleteEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	trap.Cmd_ExecuteText(
		C.EXEC_APPEND,
		Q.va(
			"clientkick %i\n",
			removeBotsMenuInfo.botClientNums[removeBotsMenuInfo.baseBotNum + removeBotsMenuInfo.selectedBotNum]
		)
	)
end

local function UI_RemoveBotsMenu_BotEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	removeBotsMenuInfo.bots[removeBotsMenuInfo.selectedBotNum].color = U.color_orange
	removeBotsMenuInfo.selectedBotNum = ptr.generic.id - ID_BOTNAME0
	removeBotsMenuInfo.bots[removeBotsMenuInfo.selectedBotNum].color = U.color_white
end

local function UI_RemoveBotsMenu_BackEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	U.UI_PopMenu()
end

local function UI_RemoveBotsMenu_UpEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	if removeBotsMenuInfo.baseBotNum > 0 then
		removeBotsMenuInfo.baseBotNum -= 1
		UI_RemoveBotsMenu_SetBotNames()
	end
end

local function UI_RemoveBotsMenu_DownEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	if removeBotsMenuInfo.baseBotNum + 7 < removeBotsMenuInfo.numBots then
		removeBotsMenuInfo.baseBotNum += 1
		UI_RemoveBotsMenu_SetBotNames()
	end
end

local function UI_RemoveBotsMenu_GetBots()
	local info = trap.GetConfigString(C.CS_SERVERINFO)
	local numPlayers = Q.int(tonumber(Q.Info_ValueForKey(info, "sv_maxclients")) or 0)
	removeBotsMenuInfo.numBots = 0

	for n = 0, numPlayers - 1 do
		info = trap.GetConfigString(C.CS_PLAYERS + n)

		local isBot = Q.int(tonumber(Q.Info_ValueForKey(info, "skill")) or 0)
		if isBot ~= 0 then
			removeBotsMenuInfo.botClientNums[removeBotsMenuInfo.numBots] = n
			removeBotsMenuInfo.numBots += 1
		end
	end
end

function U.UI_RemoveBots_Cache()
	trap.R_RegisterShaderNoMip(ART_BACKGROUND)
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
	trap.R_RegisterShaderNoMip(ART_DELETE0)
	trap.R_RegisterShaderNoMip(ART_DELETE1)
end

local function UI_RemoveBotsMenu_Init()
	resetInfo()
	local m = removeBotsMenuInfo
	m.menu.fullscreen = false
	m.menu.wrapAround = true

	U.UI_RemoveBots_Cache()

	UI_RemoveBotsMenu_GetBots()
	UI_RemoveBotsMenu_SetBotNames()
	local count = if m.numBots < 7 then m.numBots else 7

	m.banner.generic.type = C.MTYPE_BTEXT
	m.banner.generic.x = 320
	m.banner.generic.y = 16
	m.banner.string = "REMOVE BOTS"
	m.banner.color = U.color_white
	m.banner.style = C.UI_CENTER

	m.background.generic.type = C.MTYPE_BITMAP
	m.background.generic.name = ART_BACKGROUND
	m.background.generic.flags = C.QMF_INACTIVE
	m.background.generic.x = 320 - 233
	m.background.generic.y = 240 - 166
	m.background.width = 466
	m.background.height = 332

	m.arrows.generic.type = C.MTYPE_BITMAP
	m.arrows.generic.name = ART_ARROWS
	m.arrows.generic.flags = C.QMF_INACTIVE
	m.arrows.generic.x = 200
	m.arrows.generic.y = 128
	m.arrows.width = 64
	m.arrows.height = 128

	m.up.generic.type = C.MTYPE_BITMAP
	m.up.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.up.generic.x = 200
	m.up.generic.y = 128
	m.up.generic.id = ID_UP
	m.up.generic.callback = UI_RemoveBotsMenu_UpEvent
	m.up.width = 64
	m.up.height = 64
	m.up.focuspic = ART_ARROWUP

	m.down.generic.type = C.MTYPE_BITMAP
	m.down.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.down.generic.x = 200
	m.down.generic.y = 128 + 64
	m.down.generic.id = ID_DOWN
	m.down.generic.callback = UI_RemoveBotsMenu_DownEvent
	m.down.width = 64
	m.down.height = 64
	m.down.focuspic = ART_ARROWDOWN

	local y = 120
	for n = 0, count - 1 do
		m.bots[n].generic.type = C.MTYPE_PTEXT
		m.bots[n].generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
		m.bots[n].generic.id = ID_BOTNAME0 + n
		m.bots[n].generic.x = 320 - 56
		m.bots[n].generic.y = y
		m.bots[n].generic.callback = UI_RemoveBotsMenu_BotEvent
		m.bots[n].string = m.botnames[n]
		m.bots[n].color = U.color_orange
		m.bots[n].style = bit32.bor(C.UI_LEFT, C.UI_SMALLFONT)
		y += 20
	end

	m.delete.generic.type = C.MTYPE_BITMAP
	m.delete.generic.name = ART_DELETE0
	m.delete.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.delete.generic.id = ID_DELETE
	m.delete.generic.callback = UI_RemoveBotsMenu_DeleteEvent
	m.delete.generic.x = 320 + 128 - 128
	m.delete.generic.y = 256 + 128 - 64
	m.delete.width = 128
	m.delete.height = 64
	m.delete.focuspic = ART_DELETE1

	m.back.generic.type = C.MTYPE_BITMAP
	m.back.generic.name = ART_BACK0
	m.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.back.generic.id = ID_BACK
	m.back.generic.callback = UI_RemoveBotsMenu_BackEvent
	m.back.generic.x = 320 - 128
	m.back.generic.y = 256 + 128 - 64
	m.back.width = 128
	m.back.height = 64
	m.back.focuspic = ART_BACK1

	U.Menu_AddItem(m.menu, m.background)
	U.Menu_AddItem(m.menu, m.banner)
	U.Menu_AddItem(m.menu, m.arrows)
	U.Menu_AddItem(m.menu, m.up)
	U.Menu_AddItem(m.menu, m.down)
	for n = 0, count - 1 do
		U.Menu_AddItem(m.menu, m.bots[n])
	end
	U.Menu_AddItem(m.menu, m.delete)
	U.Menu_AddItem(m.menu, m.back)

	m.baseBotNum = 0
	m.selectedBotNum = 0
	m.bots[0].color = U.color_white
end

function U.UI_RemoveBotsMenu()
	UI_RemoveBotsMenu_Init()
	U.UI_PushMenu(removeBotsMenuInfo.menu)
end

return U
