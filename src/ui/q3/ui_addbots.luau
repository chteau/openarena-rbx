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
-- Luau port of code/q3_ui/ui_addbots.c (OpenArena 0.8.8, gamecode 9e0f0c0).

--[[
=======================================================================

ADD BOTS MENU

=======================================================================
]]

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_BACK0 = "menu/art_blueish/back_0"
local ART_BACK1 = "menu/art_blueish/back_1"
local ART_FIGHT0 = "menu/art_blueish/accept_0"
local ART_FIGHT1 = "menu/art_blueish/accept_1"
local ART_BACKGROUND = "menu/art_blueish/addbotframe"
local ART_ARROWS = "menu/art_blueish/arrows_vert_0"
local ART_ARROWUP = "menu/art_blueish/arrows_vert_top"
local ART_ARROWDOWN = "menu/art_blueish/arrows_vert_bot"

local ID_BACK = 10
local ID_GO = 11
local ID_UP = 13
local ID_DOWN = 14
local ID_SKILL = 15
local ID_TEAM = 16
local ID_BOTNAME0 = 20

local function newItem()
	return { generic = {} }
end

local addBotsMenuInfo

local function resetInfo()
	addBotsMenuInfo = {
		menu = { items = {}, nitems = 0 },
		arrows = newItem(),
		up = newItem(),
		down = newItem(),
		bots = {},
		skill = newItem(),
		team = newItem(),
		go = newItem(),
		back = newItem(),
		numBots = 0,
		delay = 0,
		baseBotNum = 0,
		selectedBotNum = 0,
		sortedBotNums = {},
		botnames = {},
	}
	for i = 0, 6 do
		addBotsMenuInfo.bots[i] = newItem()
		addBotsMenuInfo.botnames[i] = ""
	end
end
resetInfo()

local function UI_AddBotsMenu_FightEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local team = addBotsMenuInfo.team.itemnames[addBotsMenuInfo.team.curvalue]
	local skill = addBotsMenuInfo.skill.curvalue + 1

	trap.Cmd_ExecuteText(
		C.EXEC_APPEND,
		Q.va(
			"addbot %s %i %s %i\n",
			addBotsMenuInfo.botnames[addBotsMenuInfo.selectedBotNum],
			skill,
			team,
			addBotsMenuInfo.delay
		)
	)

	addBotsMenuInfo.delay += 1500
end

local function UI_AddBotsMenu_BotEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	addBotsMenuInfo.bots[addBotsMenuInfo.selectedBotNum].color = U.color_orange
	addBotsMenuInfo.selectedBotNum = ptr.generic.id - ID_BOTNAME0
	addBotsMenuInfo.bots[addBotsMenuInfo.selectedBotNum].color = U.color_white
end

local function UI_AddBotsMenu_BackEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	U.UI_PopMenu()
end

local function UI_AddBotsMenu_SetBotNames()
	for n = 0, 6 do
		local info = U.UI_GetBotInfoByNumber(addBotsMenuInfo.sortedBotNums[addBotsMenuInfo.baseBotNum + n])
		addBotsMenuInfo.botnames[n] = string.sub(Q.Info_ValueForKey(info, "name"), 1, 31)
		-- C's items point at the botnames buffers; a Luau string is a copy
		addBotsMenuInfo.bots[n].string = addBotsMenuInfo.botnames[n]
	end
end

local function UI_AddBotsMenu_UpEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	if addBotsMenuInfo.baseBotNum > 0 then
		addBotsMenuInfo.baseBotNum -= 1
		UI_AddBotsMenu_SetBotNames()
	end
end

local function UI_AddBotsMenu_DownEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	if addBotsMenuInfo.baseBotNum + 7 < addBotsMenuInfo.numBots then
		addBotsMenuInfo.baseBotNum += 1
		UI_AddBotsMenu_SetBotNames()
	end
end

local function UI_AddBotsMenu_GetSortedBotNums()
	local list = {}
	for n = 0, addBotsMenuInfo.numBots - 1 do
		addBotsMenuInfo.sortedBotNums[n] = n
		list[n + 1] = n
	end

	local names = {}
	for _, num in list do
		names[num] = Q.Info_ValueForKey(U.UI_GetBotInfoByNumber(num), "name")
	end
	table.sort(list, function(a, b)
		return Q.stricmp(names[a], names[b]) < 0
	end)
	for i, num in list do
		addBotsMenuInfo.sortedBotNums[i - 1] = num
	end
end

local function UI_AddBotsMenu_Draw()
	U.UI_DrawBannerString(320, 16, "ADD BOTS", C.UI_CENTER, Q.colorWhite)
	U.UI_DrawNamedPic(320 - 233, 240 - 166, 466, 332, ART_BACKGROUND)

	-- standard menu drawing
	U.Menu_Draw(addBotsMenuInfo.menu)

	-- not in OA: the Roblox friend the bot will wear (friend-bots)
	local m = addBotsMenuInfo
	local team = string.lower(m.team.itemnames[m.team.curvalue])
	local friend = trap.FriendBotNext(if team == "free" then "" else team)
	if friend then
		U.UI_DrawString(320, m.wearsY, "Wears: " .. friend .. " ^3[BOT]", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_white)
	end
end

local skillNames = {
	[0] = "I Can Win",
	"Bring It On",
	"Hurt Me Plenty",
	"Hardcore",
	"Nightmare!",
}

local teamNames1 = {
	[0] = "Free",
}

local teamNames2 = {
	[0] = "Red",
	"Blue",
}

function U.UI_AddBots_Cache()
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
	trap.R_RegisterShaderNoMip(ART_FIGHT0)
	trap.R_RegisterShaderNoMip(ART_FIGHT1)
	trap.R_RegisterShaderNoMip(ART_BACKGROUND)
	trap.R_RegisterShaderNoMip(ART_ARROWS)
	trap.R_RegisterShaderNoMip(ART_ARROWUP)
	trap.R_RegisterShaderNoMip(ART_ARROWDOWN)
end

local function UI_AddBotsMenu_Init()
	local info = trap.GetConfigString(C.CS_SERVERINFO)
	local gametype = Q.int(tonumber(Q.Info_ValueForKey(info, "g_gametype")) or 0)

	resetInfo()
	local m = addBotsMenuInfo
	m.menu.draw = UI_AddBotsMenu_Draw
	m.menu.fullscreen = false
	m.menu.wrapAround = true
	m.delay = 1000

	U.UI_AddBots_Cache()

	m.numBots = U.UI_GetNumBots()
	local count = if m.numBots < 7 then m.numBots else 7

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
	m.up.generic.callback = UI_AddBotsMenu_UpEvent
	m.up.width = 64
	m.up.height = 64
	m.up.focuspic = ART_ARROWUP

	m.down.generic.type = C.MTYPE_BITMAP
	m.down.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.down.generic.x = 200
	m.down.generic.y = 128 + 64
	m.down.generic.id = ID_DOWN
	m.down.generic.callback = UI_AddBotsMenu_DownEvent
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
		m.bots[n].generic.callback = UI_AddBotsMenu_BotEvent
		m.bots[n].string = m.botnames[n]
		m.bots[n].color = U.color_orange
		m.bots[n].style = bit32.bor(C.UI_LEFT, C.UI_SMALLFONT)
		y += 20
	end

	y += 12
	m.skill.generic.type = C.MTYPE_SPINCONTROL
	m.skill.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	m.skill.generic.x = 320
	m.skill.generic.y = y
	m.skill.generic.name = "Skill:"
	m.skill.generic.id = ID_SKILL
	m.skill.itemnames = skillNames
	m.skill.curvalue = Q.Com_Clamp(0, 4, Q.int(trap.Cvar_VariableValue("g_spSkill")) - 1)

	y += C.SMALLCHAR_HEIGHT
	m.team.generic.type = C.MTYPE_SPINCONTROL
	m.team.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	m.team.generic.x = 320
	m.team.generic.y = y
	m.team.generic.name = "Team: "
	m.team.generic.id = ID_TEAM
	m.team.curvalue = 0
	if gametype >= C.GT_TEAM and gametype ~= C.GT_LMS then
		m.team.itemnames = teamNames2
	else
		m.team.itemnames = teamNames1
		m.team.generic.flags = C.QMF_GRAYED
	end

	m.wearsY = y + C.SMALLCHAR_HEIGHT

	m.go.generic.type = C.MTYPE_BITMAP
	m.go.generic.name = ART_FIGHT0
	m.go.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.go.generic.id = ID_GO
	m.go.generic.callback = UI_AddBotsMenu_FightEvent
	m.go.generic.x = 320 + 128 - 128
	m.go.generic.y = 256 + 128 - 64
	m.go.width = 128
	m.go.height = 64
	m.go.focuspic = ART_FIGHT1

	m.back.generic.type = C.MTYPE_BITMAP
	m.back.generic.name = ART_BACK0
	m.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.back.generic.id = ID_BACK
	m.back.generic.callback = UI_AddBotsMenu_BackEvent
	m.back.generic.x = 320 - 128
	m.back.generic.y = 256 + 128 - 64
	m.back.width = 128
	m.back.height = 64
	m.back.focuspic = ART_BACK1

	m.baseBotNum = 0
	m.selectedBotNum = 0
	m.bots[0].color = U.color_white

	UI_AddBotsMenu_GetSortedBotNums()
	UI_AddBotsMenu_SetBotNames()

	U.Menu_AddItem(m.menu, m.arrows)

	U.Menu_AddItem(m.menu, m.up)
	U.Menu_AddItem(m.menu, m.down)
	for n = 0, count - 1 do
		U.Menu_AddItem(m.menu, m.bots[n])
	end
	U.Menu_AddItem(m.menu, m.skill)
	U.Menu_AddItem(m.menu, m.team)
	U.Menu_AddItem(m.menu, m.go)
	U.Menu_AddItem(m.menu, m.back)
end

function U.UI_AddBotsMenu()
	UI_AddBotsMenu_Init()
	U.UI_PushMenu(addBotsMenuInfo.menu)
end

return U
