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
-- Luau port of code/q3_ui/ui_splevel.c (OpenArena 0.8.8, gamecode 9e0f0c0).

--[[
SINGLE PLAYER LEVEL SELECT MENU
]]

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_LEVELFRAME_FOCUS = "menu/art_blueish/maps_select"
local ART_LEVELFRAME_SELECTED = "menu/art_blueish/maps_selected"
local ART_ARROW = "menu/art_blueish/narrow_0"
local ART_ARROW_FOCUS = "menu/art_blueish/narrow_1"
local ART_MAP_UNKNOWN = "menu/art/unknownmap"
local ART_MAP_COMPLETE1 = "menu/art/level_complete1"
local ART_MAP_COMPLETE2 = "menu/art/level_complete2"
local ART_MAP_COMPLETE3 = "menu/art/level_complete3"
local ART_MAP_COMPLETE4 = "menu/art/level_complete4"
local ART_MAP_COMPLETE5 = "menu/art/level_complete5"
local ART_BACK0 = "menu/art_blueish/back_0"
local ART_BACK1 = "menu/art_blueish/back_1"
local ART_FIGHT0 = "menu/art_blueish/fight_0"
local ART_FIGHT1 = "menu/art_blueish/fight_1"
local ART_RESET0 = "menu/art_blueish/reset_0"
local ART_RESET1 = "menu/art_blueish/reset_1"
local ART_CUSTOM0 = "menu/art_blueish/skirmish_0"
local ART_CUSTOM1 = "menu/art_blueish/skirmish_1"

local ID_LEFTARROW = 10
local ID_PICTURE0 = 11
local ID_PICTURE1 = 12
local ID_PICTURE2 = 13
local ID_PICTURE3 = 14
local ID_RIGHTARROW = 15
local ID_PLAYERPIC = 16
local ID_AWARD1 = 17
local ID_BACK = 23
local ID_RESET = 24
local ID_CUSTOM = 25
local ID_NEXT = 26

local PLAYER_Y = 314
local AWARDS_Y = PLAYER_Y + 26

local function newGeneric()
	return {
		type = 0, subtype = 0, name = nil, id = 0, x = 0, y = 0,
		left = 0, top = 0, right = 0, bottom = 0,
		parent = nil, menuPosition = 0, flags = 0, callback = nil,
		statusbar = nil, ownerdraw = nil,
	}
end

local function newBitmap()
	return {
		generic = newGeneric(), focuspic = nil, errorpic = nil, shader = 0,
		focusshader = 0, width = 0, height = 0, focuscolor = nil,
	}
end

local function newInfo()
	local info = {
		menu = {
			cursor = 0, cursor_prev = 0, nitems = 0, items = {},
			draw = nil, key = nil, wrapAround = false, fullscreen = false,
			showlogo = false,
		},
		item_banner = { generic = newGeneric(), string = nil, style = 0, color = nil },
		item_leftarrow = newBitmap(),
		item_maps = {},
		item_rightarrow = newBitmap(),
		item_player = newBitmap(),
		item_awards = {},
		item_back = newBitmap(),
		item_reset = newBitmap(),
		item_custom = newBitmap(),
		item_next = newBitmap(),
		item_null = newBitmap(),
		reinit = false,
		selectedArenaInfo = nil,
		numMaps = 0,
		levelPicNames = {},
		levelNames = {},
		levelScores = {},
		levelScoresSkill = {},
		levelSelectedPic = 0,
		levelFocusPic = 0,
		levelCompletePic = {},
		playerModel = "",
		playerPicName = "",
		awardLevels = {},
		awardSounds = {},
		numBots = 0,
		botPics = {},
		botAccounts = {}, -- not in OA: bots.txt names, for the roster's headshots
		botNames = {},
	}
	for i = 0, 3 do
		info.item_maps[i] = newBitmap()
		info.levelPicNames[i] = ""
		info.levelNames[i] = ""
		info.levelScores[i] = 0
		info.levelScoresSkill[i] = 0
	end
	for i = 0, 4 do
		info.levelCompletePic[i] = 0
	end
	for i = 0, 5 do
		info.item_awards[i] = newBitmap()
		info.awardLevels[i] = 0
		info.awardSounds[i] = 0
	end
	for i = 0, 6 do
		info.botPics[i] = 0
		info.botNames[i] = ""
	end
	return info
end

local levelMenuInfo = newInfo()

local selectedArenaSet = 0
local selectedArena = 0
local currentSet = 0
local currentGame = 0
local trainingTier = 0
local finalTier = 0
local minTier = 0
local maxTier = 0

local function atoi(s)
	return Q.int(tonumber(s) or 0)
end

local function PlayerIcon(modelAndSkin)
	local model = string.sub(modelAndSkin, 1, 63)
	local skin
	local slash = nil
	for i = #model, 1, -1 do
		if string.byte(model, i) == 47 then
			slash = i
			break
		end
	end
	if slash ~= nil then
		skin = string.sub(model, slash + 1)
		model = string.sub(model, 1, slash - 1)
	else
		skin = "default"
	end

	local iconName = Q.va("models/players/%s/icon_%s.tga", model, skin)

	if trap.R_RegisterShaderNoMip(iconName) == 0 and Q.stricmp(skin, "default") ~= 0 then
		iconName = Q.va("models/players/%s/icon_default.tga", model)
	end
	return iconName
end

local function PlayerIconHandle(modelAndSkin)
	return trap.R_RegisterShaderNoMip(PlayerIcon(modelAndSkin))
end

local function UI_SPLevelMenu_SetBots()
	levelMenuInfo.numBots = 0
	if selectedArenaSet > currentSet then
		return
	end

	local bots = string.sub(Q.Info_ValueForKey(levelMenuInfo.selectedArenaInfo or "", "bots"), 1, 1023)
	local len = #bots
	local p = 1
	while p <= len and levelMenuInfo.numBots < 7 do
		while p <= len and string.sub(bots, p, p) == " " do
			p += 1
		end
		local start = p
		while p <= len and string.sub(bots, p, p) ~= " " do
			p += 1
		end
		local bot = string.sub(bots, start, p - 1)
		if p <= len then
			p += 1
		end

		local botInfo = U.UI_GetBotInfoByName(bot)
		if botInfo == nil then
			botInfo = U.UI_GetBotInfoByNumber(levelMenuInfo.numBots)
		end
		local n = levelMenuInfo.numBots
		levelMenuInfo.botAccounts[n] = if botInfo ~= nil then Q.Info_ValueForKey(botInfo, "name") else bot
		if botInfo ~= nil then
			levelMenuInfo.botPics[n] = PlayerIconHandle(Q.Info_ValueForKey(botInfo, "model"))
			levelMenuInfo.botNames[n] = string.sub(Q.Info_ValueForKey(botInfo, "name"), 1, 9)
		else
			levelMenuInfo.botPics[n] = 0
			levelMenuInfo.botNames[n] = string.sub(bot, 1, 9)
		end
		levelMenuInfo.botNames[n] = Q.CleanStr(levelMenuInfo.botNames[n])
		levelMenuInfo.numBots += 1
	end
end

local function UI_SPLevelMenu_SetMenuArena(n, level, arenaInfo)
	local map = string.sub(Q.Info_ValueForKey(arenaInfo, "map"), 1, 63)

	levelMenuInfo.levelNames[n] = string.upper(string.sub(map, 1, 15))

	local score, skill = U.UI_GetBestScore(level)
	levelMenuInfo.levelScores[n] = score
	levelMenuInfo.levelScoresSkill[n] = skill
	if levelMenuInfo.levelScores[n] > 8 then
		levelMenuInfo.levelScores[n] = 8
	end

	levelMenuInfo.levelPicNames[n] = Q.va("levelshots/%s.tga", map)
	if trap.R_RegisterShaderNoMip(levelMenuInfo.levelPicNames[n]) == 0 then
		levelMenuInfo.levelPicNames[n] = ART_MAP_UNKNOWN
	end
	levelMenuInfo.item_maps[n].generic.name = levelMenuInfo.levelPicNames[n]
	levelMenuInfo.item_maps[n].shader = 0
	if selectedArenaSet > currentSet then
		levelMenuInfo.item_maps[n].generic.flags = bit32.bor(levelMenuInfo.item_maps[n].generic.flags, C.QMF_GRAYED)
	else
		levelMenuInfo.item_maps[n].generic.flags = bit32.band(levelMenuInfo.item_maps[n].generic.flags, bit32.bnot(C.QMF_GRAYED))
	end

	levelMenuInfo.item_maps[n].generic.flags = bit32.band(levelMenuInfo.item_maps[n].generic.flags, bit32.bnot(C.QMF_INACTIVE))
end

local function setSingleMap(arenaInfo)
	local level = atoi(Q.Info_ValueForKey(arenaInfo, "num"))
	UI_SPLevelMenu_SetMenuArena(0, level, arenaInfo)
	levelMenuInfo.selectedArenaInfo = arenaInfo

	levelMenuInfo.item_maps[0].generic.x = 256
	U.Bitmap_Init(levelMenuInfo.item_maps[0])
	levelMenuInfo.item_maps[0].generic.bottom += 32
	levelMenuInfo.numMaps = 1

	for i = 1, 3 do
		levelMenuInfo.item_maps[i].generic.flags = bit32.bor(levelMenuInfo.item_maps[i].generic.flags, C.QMF_INACTIVE)
		levelMenuInfo.levelPicNames[i] = ""
		levelMenuInfo.item_maps[i].generic.name = ""
		levelMenuInfo.item_maps[i].shader = 0
	end
end

local function UI_SPLevelMenu_SetMenuItems()
	if selectedArenaSet > currentSet then
		selectedArena = -1
	elseif selectedArena == -1 then
		selectedArena = 0
	end

	if selectedArenaSet == trainingTier or selectedArenaSet == finalTier then
		selectedArena = 0
	end

	if selectedArena ~= -1 then
		trap.Cvar_SetValue("ui_spSelection", selectedArenaSet * C.ARENAS_PER_TIER + selectedArena)
	end

	if selectedArenaSet == trainingTier then
		setSingleMap(U.UI_GetSpecialArenaInfo("training") or "")
	elseif selectedArenaSet == finalTier then
		setSingleMap(U.UI_GetSpecialArenaInfo("final") or "")
	else
		levelMenuInfo.item_maps[0].generic.x = 46
		U.Bitmap_Init(levelMenuInfo.item_maps[0])
		levelMenuInfo.item_maps[0].generic.bottom += 18
		levelMenuInfo.numMaps = 4

		for n = 0, 3 do
			local level = selectedArenaSet * C.ARENAS_PER_TIER + n
			local arenaInfo = U.UI_GetArenaInfoByNumber(level)
			UI_SPLevelMenu_SetMenuArena(n, level, arenaInfo or "")
		end

		if selectedArena ~= -1 then
			levelMenuInfo.selectedArenaInfo = U.UI_GetArenaInfoByNumber(selectedArenaSet * C.ARENAS_PER_TIER + selectedArena)
		end
	end

	local hidden = bit32.bor(C.QMF_INACTIVE, C.QMF_HIDDEN)
	if selectedArenaSet == minTier then
		levelMenuInfo.item_leftarrow.generic.flags = bit32.bor(levelMenuInfo.item_leftarrow.generic.flags, hidden)
	else
		levelMenuInfo.item_leftarrow.generic.flags = bit32.band(levelMenuInfo.item_leftarrow.generic.flags, bit32.bnot(hidden))
	end

	if selectedArenaSet == maxTier then
		levelMenuInfo.item_rightarrow.generic.flags = bit32.bor(levelMenuInfo.item_rightarrow.generic.flags, hidden)
	else
		levelMenuInfo.item_rightarrow.generic.flags = bit32.band(levelMenuInfo.item_rightarrow.generic.flags, bit32.bnot(hidden))
	end

	UI_SPLevelMenu_SetBots()
end

local function UI_SPLevelMenu_ResetDraw()
	local H = C.PROP_HEIGHT
	local flags = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
	U.UI_DrawProportionalString(C.SCREEN_WIDTH / 2, 356 + H * 0, "WARNING: This resets all of the", flags, U.color_yellow)
	U.UI_DrawProportionalString(C.SCREEN_WIDTH / 2, 356 + H * 1, "single player game variables.", flags, U.color_yellow)
	U.UI_DrawProportionalString(C.SCREEN_WIDTH / 2, 356 + H * 2, "Do this only if you want to", flags, U.color_yellow)
	U.UI_DrawProportionalString(C.SCREEN_WIDTH / 2, 356 + H * 3, "start over from the beginning.", flags, U.color_yellow)
end

local function UI_SPLevelMenu_ResetAction(result)
	if not result then
		return
	end

	U.UI_NewGame()
	trap.Cvar_SetValue("ui_spSelection", -4)

	U.UI_PopMenu()
	U.UI_SPLevelMenu()
end

local function UI_SPLevelMenu_ResetEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	U.UI_ConfirmMenu("RESET GAME?", UI_SPLevelMenu_ResetDraw, UI_SPLevelMenu_ResetAction)
end

local function UI_SPLevelMenu_LevelEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	if selectedArenaSet == trainingTier or selectedArenaSet == finalTier then
		return
	end

	selectedArena = ptr.generic.id - ID_PICTURE0
	levelMenuInfo.selectedArenaInfo = U.UI_GetArenaInfoByNumber(selectedArenaSet * C.ARENAS_PER_TIER + selectedArena)
	UI_SPLevelMenu_SetBots()

	trap.Cvar_SetValue("ui_spSelection", selectedArenaSet * C.ARENAS_PER_TIER + selectedArena)
end

local function UI_SPLevelMenu_LeftArrowEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	if selectedArenaSet == minTier then
		return
	end

	selectedArenaSet -= 1
	UI_SPLevelMenu_SetMenuItems()
end

local function UI_SPLevelMenu_RightArrowEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	if selectedArenaSet == maxTier then
		return
	end

	selectedArenaSet += 1
	UI_SPLevelMenu_SetMenuItems()
end

local function UI_SPLevelMenu_PlayerEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	U.UI_PlayerSettingsMenu()
end

local function UI_SPLevelMenu_AwardEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	local n = ptr.generic.id - ID_AWARD1
	trap.S_StartLocalSound(levelMenuInfo.awardSounds[n], C.CHAN_ANNOUNCER)
end

local function UI_SPLevelMenu_NextEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	if selectedArenaSet > currentSet then
		return
	end

	if selectedArena == -1 then
		selectedArena = 0
	end

	U.UI_SPSkillMenu(levelMenuInfo.selectedArenaInfo)
end

local function UI_SPLevelMenu_BackEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	if selectedArena == -1 then
		selectedArena = 0
	end

	U.UI_PopMenu()
end

local function UI_SPLevelMenu_CustomEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	U.UI_StartServerMenu(false)
end

local function UI_SPLevelMenu_MenuDraw()
	if levelMenuInfo.reinit then
		U.UI_PopMenu()
		U.UI_SPLevelMenu()
		return
	end

	-- draw player name
	local str = trap.Cvar_VariableStringBuffer("name")
	str = Q.CleanStr(string.sub(str, 1, 31))
	U.UI_DrawProportionalString(320, PLAYER_Y, str, bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_orange)

	-- check for model changes
	local buf = trap.Cvar_VariableStringBuffer("model")
	if Q.stricmp(buf, levelMenuInfo.playerModel) ~= 0 then
		levelMenuInfo.playerModel = string.sub(buf, 1, 63)
		levelMenuInfo.playerPicName = PlayerIcon(levelMenuInfo.playerModel)
		levelMenuInfo.item_player.generic.name = levelMenuInfo.playerPicName
		levelMenuInfo.item_player.shader = 0
	end
	-- not in OA: the player's face is their Roblox headshot
	local head = trap.R_LocalHeadShader()
	if head ~= 0 then
		levelMenuInfo.item_player.shader = head
	end

	-- standard menu drawing
	U.Menu_Draw(levelMenuInfo.menu)

	-- draw player award levels
	local x, y = 0, AWARDS_Y
	local i = 0
	for n = 0, 5 do
		local level = levelMenuInfo.awardLevels[n]
		if level > 0 then
			if bit32.band(i, 1) ~= 0 then
				x = 224 - Q.idiv(i - 1, 2) * (48 + 16)
			else
				x = 368 + Q.idiv(i, 2) * (48 + 16)
			end
			i += 1

			if level == 1 then
				continue
			end

			if level >= 1000000 then
				str = Q.va("%im", Q.idiv(level, 1000000))
			elseif level >= 1000 then
				str = Q.va("%ik", Q.idiv(level, 1000))
			else
				str = Q.va("%i", level)
			end

			U.UI_DrawString(x + 24, y + 48, str, C.UI_CENTER, U.color_yellow)
		end
	end

	U.UI_DrawProportionalString(18, 38, Q.va("Tier %i", selectedArenaSet + 1), bit32.bor(C.UI_LEFT, C.UI_SMALLFONT), U.color_orange)

	for n = 0, levelMenuInfo.numMaps - 1 do
		x = levelMenuInfo.item_maps[n].generic.x
		y = levelMenuInfo.item_maps[n].generic.y
		U.UI_FillRect(x, y + 96, 128, 18, U.color_black)
	end

	if selectedArenaSet > currentSet then
		U.UI_DrawProportionalString(320, 216, "ACCESS DENIED", bit32.bor(C.UI_CENTER, C.UI_BIGFONT), U.color_red)
		return
	end

	-- show levelshots for levels of current tier
	local color = Q.vec4(1, 1, 1, 1)
	Q.Vector4Copy(U.color_white, color)
	color[3] = 0.5 + 0.5 * math.sin(U.uis.realtime / C.PULSE_DIVISOR)
	for n = 0, levelMenuInfo.numMaps - 1 do
		x = levelMenuInfo.item_maps[n].generic.x
		y = levelMenuInfo.item_maps[n].generic.y

		U.UI_DrawString(x + 64, y + 96, levelMenuInfo.levelNames[n], bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_orange)

		if levelMenuInfo.levelScores[n] == 1 then
			U.UI_DrawHandlePic(x, y, 128, 96, levelMenuInfo.levelCompletePic[levelMenuInfo.levelScoresSkill[n] - 1])
		end

		if n == selectedArena then
			if U.Menu_ItemAtCursor(levelMenuInfo.menu) == levelMenuInfo.item_maps[n] then
				trap.R_SetColor(color)
			end
			U.UI_DrawHandlePic(x - 1, y - 1, 130, 130 - 14, levelMenuInfo.levelSelectedPic)
			trap.R_SetColor(nil)
		elseif U.Menu_ItemAtCursor(levelMenuInfo.menu) == levelMenuInfo.item_maps[n] then
			trap.R_SetColor(color)
			U.UI_DrawHandlePic(x - 31, y - 30, 256, 256 - 27, levelMenuInfo.levelFocusPic)
			trap.R_SetColor(nil)
		end
	end

	-- show map name and long name of selected level
	y = 192
	local info = levelMenuInfo.selectedArenaInfo or ""
	buf = string.upper(string.sub(Q.Info_ValueForKey(info, "map"), 1, 19))
	str = Q.va("%s: %s", buf, Q.Info_ValueForKey(info, "longname"))
	U.UI_DrawProportionalString(320, y, str, bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_orange)

	-- draw bot opponents
	y += 24
	local pad = Q.idiv((7 - levelMenuInfo.numBots) * (64 + 26), 2)
	for n = 0, levelMenuInfo.numBots - 1 do
		x = 18 + pad + (64 + 26) * n
		-- not in OA: a roster bot's face is its account's headshot
		local pic = trap.R_BotHeadShader(levelMenuInfo.botAccounts[n])
		if pic == 0 then
			pic = levelMenuInfo.botPics[n]
		end
		if pic ~= 0 then
			U.UI_DrawHandlePic(x, y, 64, 64, pic)
		else
			U.UI_FillRect(x, y, 64, 64, U.color_black)
			U.UI_DrawProportionalString(x + 22, y + 18, "?", C.UI_BIGFONT, U.color_orange)
		end
		-- not in OA: centred under the face, a roster bot's username
		local name = trap.BotName(levelMenuInfo.botAccounts[n]) or levelMenuInfo.botNames[n]
		U.UI_DrawStringFit(x + 32, y + 64, name, 64 + 24, U.color_orange)
	end
end

function U.UI_SPLevelMenu_Cache()
	trap.R_RegisterShaderNoMip(ART_LEVELFRAME_FOCUS)
	trap.R_RegisterShaderNoMip(ART_LEVELFRAME_SELECTED)
	trap.R_RegisterShaderNoMip(ART_ARROW)
	trap.R_RegisterShaderNoMip(ART_ARROW_FOCUS)
	trap.R_RegisterShaderNoMip(ART_MAP_UNKNOWN)
	trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE1)
	trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE2)
	trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE3)
	trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE4)
	trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE5)
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
	trap.R_RegisterShaderNoMip(ART_FIGHT0)
	trap.R_RegisterShaderNoMip(ART_FIGHT1)
	trap.R_RegisterShaderNoMip(ART_RESET0)
	trap.R_RegisterShaderNoMip(ART_RESET1)
	trap.R_RegisterShaderNoMip(ART_CUSTOM0)
	trap.R_RegisterShaderNoMip(ART_CUSTOM1)

	for n = 0, 5 do
		trap.R_RegisterShaderNoMip(U.ui_medalPicNames[n])
		levelMenuInfo.awardSounds[n] = trap.S_RegisterSound(U.ui_medalSounds[n], false)
	end

	levelMenuInfo.levelSelectedPic = trap.R_RegisterShaderNoMip(ART_LEVELFRAME_SELECTED)
	levelMenuInfo.levelFocusPic = trap.R_RegisterShaderNoMip(ART_LEVELFRAME_FOCUS)
	levelMenuInfo.levelCompletePic[0] = trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE1)
	levelMenuInfo.levelCompletePic[1] = trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE2)
	levelMenuInfo.levelCompletePic[2] = trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE3)
	levelMenuInfo.levelCompletePic[3] = trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE4)
	levelMenuInfo.levelCompletePic[4] = trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE5)
end

local function UI_SPLevelMenu_Init()
	local skill = Q.int(trap.Cvar_VariableValue("g_spSkill"))
	if skill < 1 or skill > 5 then
		trap.Cvar_Set("g_spSkill", "2")
		skill = 2
	end

	levelMenuInfo = newInfo()
	local m = levelMenuInfo
	m.menu.fullscreen = true
	m.menu.wrapAround = true
	m.menu.draw = UI_SPLevelMenu_MenuDraw

	U.UI_SPLevelMenu_Cache()

	m.item_banner.generic.type = C.MTYPE_BTEXT
	m.item_banner.generic.x = 320
	m.item_banner.generic.y = 16
	m.item_banner.string = "CHOOSE LEVEL"
	m.item_banner.color = U.color_red
	m.item_banner.style = C.UI_CENTER

	m.item_leftarrow.generic.type = C.MTYPE_BITMAP
	m.item_leftarrow.generic.name = ART_ARROW
	m.item_leftarrow.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.item_leftarrow.generic.x = 18
	m.item_leftarrow.generic.y = 64
	m.item_leftarrow.generic.callback = UI_SPLevelMenu_LeftArrowEvent
	m.item_leftarrow.generic.id = ID_LEFTARROW
	m.item_leftarrow.width = 16
	m.item_leftarrow.height = 114
	m.item_leftarrow.focuspic = ART_ARROW_FOCUS

	local mapX = { [0] = 46, 186, 326, 466 }
	for i = 0, 3 do
		local it = m.item_maps[i]
		it.generic.type = C.MTYPE_BITMAP
		it.generic.name = m.levelPicNames[i]
		it.generic.flags = C.QMF_LEFT_JUSTIFY
		it.generic.x = mapX[i]
		it.generic.y = 64
		it.generic.id = ID_PICTURE0 + i
		it.generic.callback = UI_SPLevelMenu_LevelEvent
		it.width = 128
		it.height = 96
	end

	m.item_rightarrow.generic.type = C.MTYPE_BITMAP
	m.item_rightarrow.generic.name = ART_ARROW
	m.item_rightarrow.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.item_rightarrow.generic.x = 606
	m.item_rightarrow.generic.y = 64
	m.item_rightarrow.generic.callback = UI_SPLevelMenu_RightArrowEvent
	m.item_rightarrow.generic.id = ID_RIGHTARROW
	m.item_rightarrow.width = -16
	m.item_rightarrow.height = 114
	m.item_rightarrow.focuspic = ART_ARROW_FOCUS

	m.playerModel = string.sub(trap.Cvar_VariableStringBuffer("model"), 1, 63)
	m.playerPicName = PlayerIcon(m.playerModel)
	m.item_player.generic.type = C.MTYPE_BITMAP
	m.item_player.generic.name = m.playerPicName
	m.item_player.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_MOUSEONLY)
	m.item_player.generic.x = 288
	m.item_player.generic.y = AWARDS_Y
	m.item_player.generic.id = ID_PLAYERPIC
	m.item_player.generic.callback = UI_SPLevelMenu_PlayerEvent
	m.item_player.width = 64
	m.item_player.height = 64

	for n = 0, 5 do
		m.awardLevels[n] = U.UI_GetAwardLevel(n)
	end
	m.awardLevels[C.AWARD_FRAGS] = 100 * Q.idiv(m.awardLevels[C.AWARD_FRAGS], 100)

	local y = AWARDS_Y
	local count = 0
	for n = 0, 5 do
		if m.awardLevels[n] ~= 0 then
			local x
			if bit32.band(count, 1) ~= 0 then
				x = 224 - Q.idiv(count - 1, 2) * (48 + 16)
			else
				x = 368 + Q.idiv(count, 2) * (48 + 16)
			end

			local it = m.item_awards[count]
			it.generic.type = C.MTYPE_BITMAP
			it.generic.name = U.ui_medalPicNames[n]
			it.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_SILENT, C.QMF_MOUSEONLY)
			it.generic.x = x
			it.generic.y = y
			it.generic.id = ID_AWARD1 + n
			it.generic.callback = UI_SPLevelMenu_AwardEvent
			it.width = 48
			it.height = 48
			count += 1
		end
	end

	m.item_back.generic.type = C.MTYPE_BITMAP
	m.item_back.generic.name = ART_BACK0
	m.item_back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.item_back.generic.x = 0
	m.item_back.generic.y = 480 - 64
	m.item_back.generic.callback = UI_SPLevelMenu_BackEvent
	m.item_back.generic.id = ID_BACK
	m.item_back.width = 128
	m.item_back.height = 64
	m.item_back.focuspic = ART_BACK1

	m.item_reset.generic.type = C.MTYPE_BITMAP
	m.item_reset.generic.name = ART_RESET0
	m.item_reset.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.item_reset.generic.x = 170
	m.item_reset.generic.y = 480 - 64
	m.item_reset.generic.callback = UI_SPLevelMenu_ResetEvent
	m.item_reset.generic.id = ID_RESET
	m.item_reset.width = 128
	m.item_reset.height = 64
	m.item_reset.focuspic = ART_RESET1

	m.item_custom.generic.type = C.MTYPE_BITMAP
	m.item_custom.generic.name = ART_CUSTOM0
	m.item_custom.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.item_custom.generic.x = 342
	m.item_custom.generic.y = 480 - 64
	m.item_custom.generic.callback = UI_SPLevelMenu_CustomEvent
	m.item_custom.generic.id = ID_CUSTOM
	m.item_custom.width = 128
	m.item_custom.height = 64
	m.item_custom.focuspic = ART_CUSTOM1

	m.item_next.generic.type = C.MTYPE_BITMAP
	m.item_next.generic.name = ART_FIGHT0
	m.item_next.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	m.item_next.generic.x = 640
	m.item_next.generic.y = 480 - 64
	m.item_next.generic.callback = UI_SPLevelMenu_NextEvent
	m.item_next.generic.id = ID_NEXT
	m.item_next.width = 128
	m.item_next.height = 64
	m.item_next.focuspic = ART_FIGHT1

	m.item_null.generic.type = C.MTYPE_BITMAP
	m.item_null.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_MOUSEONLY, C.QMF_SILENT)
	m.item_null.generic.x = 0
	m.item_null.generic.y = 0
	m.item_null.width = 640
	m.item_null.height = 480

	U.Menu_AddItem(m.menu, m.item_banner)

	U.Menu_AddItem(m.menu, m.item_leftarrow)
	for i = 0, 3 do
		U.Menu_AddItem(m.menu, m.item_maps[i])
	end
	for i = 0, 3 do
		m.item_maps[i].generic.bottom += 18
	end
	U.Menu_AddItem(m.menu, m.item_rightarrow)

	U.Menu_AddItem(m.menu, m.item_player)

	for n = 0, count - 1 do
		U.Menu_AddItem(m.menu, m.item_awards[n])
	end
	U.Menu_AddItem(m.menu, m.item_back)
	U.Menu_AddItem(m.menu, m.item_reset)
	U.Menu_AddItem(m.menu, m.item_custom)
	U.Menu_AddItem(m.menu, m.item_next)
	U.Menu_AddItem(m.menu, m.item_null)

	local buf = trap.Cvar_VariableStringBuffer("ui_spSelection")
	if buf ~= "" then
		local n = atoi(buf)
		selectedArenaSet = Q.idiv(n, C.ARENAS_PER_TIER)
		selectedArena = math.fmod(n, C.ARENAS_PER_TIER)
	else
		selectedArenaSet = currentSet
		selectedArena = currentGame
	end

	UI_SPLevelMenu_SetMenuItems()
end

function U.UI_SPLevelMenu()
	trainingTier = -1
	local arenaInfo = U.UI_GetSpecialArenaInfo("training")
	local trainingLevel
	if arenaInfo ~= nil then
		minTier = trainingTier
		trainingLevel = atoi(Q.Info_ValueForKey(arenaInfo, "num"))
	else
		minTier = 0
		trainingLevel = -2
	end

	finalTier = U.UI_GetNumSPTiers()
	arenaInfo = U.UI_GetSpecialArenaInfo("final")
	if arenaInfo ~= nil then
		maxTier = finalTier
	else
		maxTier = finalTier - 1
		if maxTier < minTier then
			maxTier = minTier
		end
	end

	local level = U.UI_GetCurrentGame()
	if level == -1 then
		level = U.UI_GetNumSPArenas() - 1
		if maxTier == finalTier then
			level += 1
		end
	end

	if level == trainingLevel then
		currentSet = -1
		currentGame = 0
	else
		currentSet = Q.idiv(level, C.ARENAS_PER_TIER)
		currentGame = math.fmod(level, C.ARENAS_PER_TIER)
	end

	UI_SPLevelMenu_Init()
	U.UI_PushMenu(levelMenuInfo.menu)
	U.Menu_SetCursorToItem(levelMenuInfo.menu, levelMenuInfo.item_next)
end

function U.UI_SPLevelMenu_f()
	trap.Key_SetCatcher(C.KEYCATCH_UI)
	U.uis.menusp = 0
	U.UI_SPLevelMenu()
end

function U.UI_SPLevelMenu_ReInit()
	levelMenuInfo.reinit = true
end

return U
