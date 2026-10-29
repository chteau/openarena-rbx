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
-- Luau port of code/q3_ui/ui_spskill.c (OpenArena gamecode).

--[[
=============================================================================

SINGLE PLAYER SKILL MENU

=============================================================================
]]

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_FRAME = "menu/" .. C.MENU_ART_DIR .. "/cut_frame"
local ART_BACK = "menu/" .. C.MENU_ART_DIR .. "/back_0.tga"
local ART_BACK_FOCUS = "menu/" .. C.MENU_ART_DIR .. "/back_1.tga"
local ART_FIGHT = "menu/" .. C.MENU_ART_DIR .. "/fight_0"
local ART_FIGHT_FOCUS = "menu/" .. C.MENU_ART_DIR .. "/fight_1"
local ART_MAP_COMPLETE1 = "menu/art/level_complete1"
local ART_MAP_COMPLETE2 = "menu/art/level_complete2"
local ART_MAP_COMPLETE3 = "menu/art/level_complete3"
local ART_MAP_COMPLETE4 = "menu/art/level_complete4"
local ART_MAP_COMPLETE5 = "menu/art/level_complete5"

local ID_BABY = 10
local ID_EASY = 11
local ID_MEDIUM = 12
local ID_HARD = 13
local ID_NIGHTMARE = 14
local ID_BACK = 15
local ID_FIGHT = 16

local function newSkillMenuInfo()
	return {
		menu = T.menuframework_s(),
		art_frame = T.menubitmap_s(),
		art_banner = T.menutext_s(),
		item_baby = T.menutext_s(),
		item_easy = T.menutext_s(),
		item_medium = T.menutext_s(),
		item_hard = T.menutext_s(),
		item_nightmare = T.menutext_s(),
		art_skillPic = T.menubitmap_s(),
		item_back = T.menubitmap_s(),
		item_fight = T.menubitmap_s(),
		arenaInfo = "",
		skillpics = { [0] = 0, 0, 0, 0, 0 },
		nightmareSound = 0,
		silenceSound = 0,
	}
end

local skillMenuInfo = newSkillMenuInfo()

local function SetSkillColor(skill, color)
	if skill == 1 then
		skillMenuInfo.item_baby.color = color
	elseif skill == 2 then
		skillMenuInfo.item_easy.color = color
	elseif skill == 3 then
		skillMenuInfo.item_medium.color = color
	elseif skill == 4 then
		skillMenuInfo.item_hard.color = color
	elseif skill == 5 then
		skillMenuInfo.item_nightmare.color = color
	end
end

local function UI_SPSkillMenu_SkillEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	SetSkillColor(Q.int(trap.Cvar_VariableValue("g_spSkill")), Q.colorRed)

	local id = ptr.generic.id
	local skill = id - ID_BABY + 1
	trap.Cvar_SetValue("g_spSkill", skill)

	SetSkillColor(skill, Q.colorWhite)
	skillMenuInfo.art_skillPic.shader = skillMenuInfo.skillpics[skill - 1]

	if id == ID_NIGHTMARE then
		trap.S_StartLocalSound(skillMenuInfo.nightmareSound, C.CHAN_ANNOUNCER)
	else
		trap.S_StartLocalSound(skillMenuInfo.silenceSound, C.CHAN_ANNOUNCER)
	end
end

local function UI_SPSkillMenu_FightEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	U.UI_SPArena_Start(skillMenuInfo.arenaInfo)
end

local function UI_SPSkillMenu_BackEvent(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	trap.S_StartLocalSound(skillMenuInfo.silenceSound, C.CHAN_ANNOUNCER)
	U.UI_PopMenu()
end

local function UI_SPSkillMenu_Key(key)
	if key == C.K_MOUSE2 or key == C.K_ESCAPE then
		trap.S_StartLocalSound(skillMenuInfo.silenceSound, C.CHAN_ANNOUNCER)
	end
	return U.Menu_DefaultKey(skillMenuInfo.menu, key)
end

function U.UI_SPSkillMenu_Cache()
	trap.R_RegisterShaderNoMip(ART_FRAME)
	trap.R_RegisterShaderNoMip(ART_BACK)
	trap.R_RegisterShaderNoMip(ART_BACK_FOCUS)
	trap.R_RegisterShaderNoMip(ART_FIGHT)
	trap.R_RegisterShaderNoMip(ART_FIGHT_FOCUS)
	skillMenuInfo.skillpics[0] = trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE1)
	skillMenuInfo.skillpics[1] = trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE2)
	skillMenuInfo.skillpics[2] = trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE3)
	skillMenuInfo.skillpics[3] = trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE4)
	skillMenuInfo.skillpics[4] = trap.R_RegisterShaderNoMip(ART_MAP_COMPLETE5)

	skillMenuInfo.nightmareSound = trap.S_RegisterSound("sound/misc/nightmare.wav", false)
	skillMenuInfo.silenceSound = trap.S_RegisterSound("sound/misc/silence.wav", false)
end

local function setSkillText(item, y, id, str)
	item.generic.type = C.MTYPE_PTEXT
	item.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	item.generic.x = 320
	item.generic.y = y
	item.generic.callback = UI_SPSkillMenu_SkillEvent
	item.generic.id = id
	item.string = str
	item.color = Q.colorRed
	item.style = C.UI_CENTER
end

local function UI_SPSkillMenu_Init()
	skillMenuInfo = newSkillMenuInfo()
	skillMenuInfo.menu.fullscreen = true
	skillMenuInfo.menu.key = UI_SPSkillMenu_Key

	U.UI_SPSkillMenu_Cache()

	skillMenuInfo.art_frame.generic.type = C.MTYPE_BITMAP
	skillMenuInfo.art_frame.generic.name = ART_FRAME
	skillMenuInfo.art_frame.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	skillMenuInfo.art_frame.generic.x = 142
	skillMenuInfo.art_frame.generic.y = 118
	skillMenuInfo.art_frame.width = 359
	skillMenuInfo.art_frame.height = 256

	skillMenuInfo.art_banner.generic.type = C.MTYPE_BTEXT
	skillMenuInfo.art_banner.generic.flags = C.QMF_CENTER_JUSTIFY
	skillMenuInfo.art_banner.generic.x = 320
	skillMenuInfo.art_banner.generic.y = 16
	skillMenuInfo.art_banner.string = "DIFFICULTY"
	skillMenuInfo.art_banner.color = Q.colorWhite
	skillMenuInfo.art_banner.style = C.UI_CENTER

	setSkillText(skillMenuInfo.item_baby, 170, ID_BABY, "I Can Win")
	setSkillText(skillMenuInfo.item_easy, 198, ID_EASY, "Bring It On")
	setSkillText(skillMenuInfo.item_medium, 227, ID_MEDIUM, "Hurt Me Plenty")
	setSkillText(skillMenuInfo.item_hard, 255, ID_HARD, "Hardcore")
	setSkillText(skillMenuInfo.item_nightmare, 283, ID_NIGHTMARE, "NIGHTMARE!")

	skillMenuInfo.item_back.generic.type = C.MTYPE_BITMAP
	skillMenuInfo.item_back.generic.name = ART_BACK
	skillMenuInfo.item_back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	skillMenuInfo.item_back.generic.x = 0
	skillMenuInfo.item_back.generic.y = 480 - 64
	skillMenuInfo.item_back.generic.callback = UI_SPSkillMenu_BackEvent
	skillMenuInfo.item_back.generic.id = ID_BACK
	skillMenuInfo.item_back.width = 128
	skillMenuInfo.item_back.height = 64
	skillMenuInfo.item_back.focuspic = ART_BACK_FOCUS

	skillMenuInfo.art_skillPic.generic.type = C.MTYPE_BITMAP
	skillMenuInfo.art_skillPic.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	skillMenuInfo.art_skillPic.generic.x = 320 - 64
	skillMenuInfo.art_skillPic.generic.y = 368
	skillMenuInfo.art_skillPic.width = 128
	skillMenuInfo.art_skillPic.height = 96

	skillMenuInfo.item_fight.generic.type = C.MTYPE_BITMAP
	skillMenuInfo.item_fight.generic.name = ART_FIGHT
	skillMenuInfo.item_fight.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	skillMenuInfo.item_fight.generic.callback = UI_SPSkillMenu_FightEvent
	skillMenuInfo.item_fight.generic.id = ID_FIGHT
	skillMenuInfo.item_fight.generic.x = 640
	skillMenuInfo.item_fight.generic.y = 480 - 64
	skillMenuInfo.item_fight.width = 128
	skillMenuInfo.item_fight.height = 64
	skillMenuInfo.item_fight.focuspic = ART_FIGHT_FOCUS

	U.Menu_AddItem(skillMenuInfo.menu, skillMenuInfo.art_frame)
	U.Menu_AddItem(skillMenuInfo.menu, skillMenuInfo.art_banner)
	U.Menu_AddItem(skillMenuInfo.menu, skillMenuInfo.item_baby)
	U.Menu_AddItem(skillMenuInfo.menu, skillMenuInfo.item_easy)
	U.Menu_AddItem(skillMenuInfo.menu, skillMenuInfo.item_medium)
	U.Menu_AddItem(skillMenuInfo.menu, skillMenuInfo.item_hard)
	U.Menu_AddItem(skillMenuInfo.menu, skillMenuInfo.item_nightmare)
	U.Menu_AddItem(skillMenuInfo.menu, skillMenuInfo.art_skillPic)
	U.Menu_AddItem(skillMenuInfo.menu, skillMenuInfo.item_back)
	U.Menu_AddItem(skillMenuInfo.menu, skillMenuInfo.item_fight)

	local skill = Q.int(Q.Com_Clamp(1, 5, trap.Cvar_VariableValue("g_spSkill")))
	SetSkillColor(skill, Q.colorWhite)
	skillMenuInfo.art_skillPic.shader = skillMenuInfo.skillpics[skill - 1]
	if skill == 5 then
		trap.S_StartLocalSound(skillMenuInfo.nightmareSound, C.CHAN_ANNOUNCER)
	end
end

function U.UI_SPSkillMenu(arenaInfo)
	UI_SPSkillMenu_Init()
	skillMenuInfo.arenaInfo = arenaInfo
	U.UI_PushMenu(skillMenuInfo.menu)
	U.Menu_SetCursorToItem(skillMenuInfo.menu, skillMenuInfo.item_fight)
end

return U
