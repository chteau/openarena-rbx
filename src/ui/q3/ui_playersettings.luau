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
-- Luau port of code/q3_ui/ui_playersettings.c (OpenArena gamecode).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_FRAMEL = "menu/" .. C.MENU_ART_DIR .. "/frame2_l"
local ART_FRAMER = "menu/" .. C.MENU_ART_DIR .. "/frame1_r"
local ART_MODEL0 = "menu/" .. C.MENU_ART_DIR .. "/model_0"
local ART_MODEL1 = "menu/" .. C.MENU_ART_DIR .. "/model_1"
local ART_BACK0 = "menu/" .. C.MENU_ART_DIR .. "/back_0"
local ART_BACK1 = "menu/" .. C.MENU_ART_DIR .. "/back_1"
local ART_FX_BASE = "menu/art/fx_base"
local ART_FX_BLUE = "menu/art/fx_blue"
local ART_FX_CYAN = "menu/art/fx_cyan"
local ART_FX_GREEN = "menu/art/fx_grn"
local ART_FX_RED = "menu/art/fx_red"
local ART_FX_TEAL = "menu/art/fx_teal"
local ART_FX_WHITE = "menu/art/fx_white"
local ART_FX_YELLOW = "menu/art/fx_yel"

local ID_NAME = 10
local ID_HANDICAP = 11
local ID_EFFECTS = 12
local ID_EFFECTS2 = 13
local ID_BACK = 14
local ID_MODEL = 15

local MAX_NAMELENGTH = 20

local s_playersettings = {
	fxBasePic = 0,
	fxPic = { [0] = 0, 0, 0, 0, 0, 0, 0 },
	current_fx = 0,
	playerModel = "",
}

local gamecodetoui = { [0] = 4, 2, 3, 0, 5, 1, 6 }
local uitogamecode = { [0] = 4, 6, 2, 3, 1, 5, 7 }

local handicap_items = {
	[0] = "100", "95", "90", "85", "80", "75", "70", "65", "60", "55",
	"50", "45", "40", "35", "30", "25", "20", "15", "10", "5",
}

local function PlayerSettings_DrawName(self)
	local f = self
	local basex = f.generic.x
	local y = f.generic.y
	local focus = (f.generic.parent.cursor == f.generic.menuPosition)

	local style = bit32.bor(C.UI_LEFT, C.UI_SMALLFONT)
	local color = U.text_color_normal
	if focus then
		style = bit32.bor(style, C.UI_PULSE)
		color = U.text_color_highlight
	end

	U.UI_DrawProportionalString(basex, y, "Name", style, color)

	basex += 64
	y += C.PROP_HEIGHT
	local txt = f.field.buffer
	color = Q.g_color_table[7]
	local x = basex
	local i = 1
	local len = #txt
	while i <= len do
		local c = string.byte(txt, i)
		if not focus and c == 94 and i < len and string.byte(txt, i + 1) ~= 94 then
			local n = bit32.band(string.byte(txt, i + 1) - 48, 7)
			if n == 0 then
				n = 7
			end
			color = Q.g_color_table[n]
			i += 2
			continue
		end
		U.UI_DrawChar(x, y, c, style, color)
		i += 1
		x += C.SMALLCHAR_WIDTH
	end

	if focus then
		local c
		if trap.Key_GetOverstrikeMode() then
			c = 11
		else
			c = 10
		end

		style = bit32.band(style, bit32.bnot(C.UI_PULSE))
		style = bit32.bor(style, C.UI_BLINK)

		U.UI_DrawChar(basex + f.field.cursor * C.SMALLCHAR_WIDTH, y, c, style, Q.colorWhite)
	end

	local name = string.sub(f.field.buffer, 1, 31)
	local clean = {}
	local k = 1
	while k <= #name do
		local c = string.byte(name, k)
		if c == 94 and k < #name and string.byte(name, k + 1) ~= 94 then
			k += 2
		else
			if c >= 32 and c <= 126 then
				table.insert(clean, string.char(c))
			end
			k += 1
		end
	end
	name = table.concat(clean)
	U.UI_DrawProportionalString(320, 440, name, bit32.bor(C.UI_CENTER, C.UI_BIGFONT), U.text_color_normal)
end

local function PlayerSettings_DrawHandicap(self)
	local item = self
	local focus = (item.generic.parent.cursor == item.generic.menuPosition)

	local style = bit32.bor(C.UI_LEFT, C.UI_SMALLFONT)
	local color = U.text_color_normal
	if focus then
		style = bit32.bor(style, C.UI_PULSE)
		color = U.text_color_highlight
	end

	U.UI_DrawProportionalString(item.generic.x, item.generic.y, "Handicap", style, color)
	U.UI_DrawProportionalString(item.generic.x + 64, item.generic.y + C.PROP_HEIGHT, handicap_items[item.curvalue], style, color)
end

local function PlayerSettings_DrawEffects(self)
	local item = self
	local focus = (item.generic.parent.cursor == item.generic.menuPosition)

	local style = bit32.bor(C.UI_LEFT, C.UI_SMALLFONT)
	local color = U.text_color_normal
	if focus then
		style = bit32.bor(style, C.UI_PULSE)
		color = U.text_color_highlight
	end

	U.UI_DrawProportionalString(item.generic.x, item.generic.y, "Effects", style, color)

	U.UI_DrawHandlePic(item.generic.x + 64, item.generic.y + C.PROP_HEIGHT + 8, 128, 8, s_playersettings.fxBasePic)
	U.UI_DrawHandlePic(item.generic.x + 64 + item.curvalue * 16 + 8, item.generic.y + C.PROP_HEIGHT + 6, 16, 12, s_playersettings.fxPic[item.curvalue])
end

local function PlayerSettings_DrawEffects2(self)
	local item = self

	U.UI_DrawHandlePic(item.generic.x + 64, item.generic.y + 8, 128, 8, s_playersettings.fxBasePic)
	U.UI_DrawHandlePic(item.generic.x + 64 + item.curvalue * 16 + 8, item.generic.y + 6, 16, 12, s_playersettings.fxPic[item.curvalue])
end

local function PlayerSettings_DrawPlayer(self)
	local buf = trap.Cvar_VariableStringBuffer("model")
	if buf ~= s_playersettings.playerModel then
		U.UI_PlayerInfo_SetModel(s_playersettings.playerinfo, buf)
		s_playersettings.playerModel = buf

		local viewangles = Q.vec3(0, 180 - 30, 0)
		U.UI_PlayerInfo_SetInfo(s_playersettings.playerinfo, C.LEGS_IDLE, C.TORSO_STAND, viewangles, Q.vec3_origin, C.WP_MACHINEGUN, false)
	end

	local b = self
	U.UI_DrawPlayer(b.generic.x, b.generic.y, b.width, b.height, s_playersettings.playerinfo, Q.int(U.uis.realtime / 2))
end

local function PlayerSettings_SaveChanges()
	trap.Cvar_Set("name", s_playersettings.name.field.buffer)
	trap.Cvar_SetValue("handicap", 100 - s_playersettings.handicap.curvalue * 5)
	trap.Cvar_SetValue("color1", uitogamecode[s_playersettings.effects.curvalue])
	trap.Cvar_SetValue("color2", uitogamecode[s_playersettings.effects2.curvalue])
end

local function PlayerSettings_MenuKey(key)
	if key == C.K_MOUSE2 or key == C.K_ESCAPE then
		PlayerSettings_SaveChanges()
	end
	return U.Menu_DefaultKey(s_playersettings.menu, key)
end

local function PlayerSettings_SetMenuItems()
	s_playersettings.name.field.buffer = string.sub(U.UI_Cvar_VariableString("name"), 1, 255)

	local c = Q.int(trap.Cvar_VariableValue("color1") - 1)
	if c < 0 or c > 6 then
		c = 6
	end
	s_playersettings.effects.curvalue = gamecodetoui[c]

	c = Q.int(trap.Cvar_VariableValue("color2") - 1)
	if c < 0 or c > 6 then
		c = 6
	end
	s_playersettings.effects2.curvalue = gamecodetoui[c]

	s_playersettings.playerinfo = T.playerInfo_t()

	local viewangles = Q.vec3(0, 180 - 30, 0)

	U.UI_PlayerInfo_SetModel(s_playersettings.playerinfo, U.UI_Cvar_VariableString("model"))
	U.UI_PlayerInfo_SetInfo(s_playersettings.playerinfo, C.LEGS_IDLE, C.TORSO_STAND, viewangles, Q.vec3_origin, C.WP_MACHINEGUN, false)

	local h = Q.int(Q.Com_Clamp(5, 100, trap.Cvar_VariableValue("handicap")))
	s_playersettings.handicap.curvalue = 20 - Q.idiv(h, 5)
end

local function PlayerSettings_MenuEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local id = ptr.generic.id
	if id == ID_HANDICAP then
		trap.Cvar_Set("handicap", Q.va("%i", 100 - 25 * s_playersettings.handicap.curvalue))
	elseif id == ID_MODEL then
		PlayerSettings_SaveChanges()
		U.UI_PlayerModelMenu()
	elseif id == ID_BACK then
		PlayerSettings_SaveChanges()
		U.UI_PopMenu()
	end
end

local function PlayerSettings_StatusBar(ptr)
	U.UI_DrawString(320, 400, "Lower handicap makes you weaker", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), Q.colorWhite)
	U.UI_DrawString(320, 420, "giving you more challenge", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), Q.colorWhite)
end

local function PlayerSettings_Cache()
	trap.R_RegisterShaderNoMip(ART_FRAMEL)
	trap.R_RegisterShaderNoMip(ART_FRAMER)
	trap.R_RegisterShaderNoMip(ART_MODEL0)
	trap.R_RegisterShaderNoMip(ART_MODEL1)
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)

	s_playersettings.fxBasePic = trap.R_RegisterShaderNoMip(ART_FX_BASE)
	s_playersettings.fxPic[0] = trap.R_RegisterShaderNoMip(ART_FX_RED)
	s_playersettings.fxPic[1] = trap.R_RegisterShaderNoMip(ART_FX_YELLOW)
	s_playersettings.fxPic[2] = trap.R_RegisterShaderNoMip(ART_FX_GREEN)
	s_playersettings.fxPic[3] = trap.R_RegisterShaderNoMip(ART_FX_TEAL)
	s_playersettings.fxPic[4] = trap.R_RegisterShaderNoMip(ART_FX_BLUE)
	s_playersettings.fxPic[5] = trap.R_RegisterShaderNoMip(ART_FX_CYAN)
	s_playersettings.fxPic[6] = trap.R_RegisterShaderNoMip(ART_FX_WHITE)
end

local function PlayerSettings_MenuInit()
	local s = s_playersettings
	s.menu = T.menuframework_s()
	s.banner = T.menutext_s()
	s.framel = T.menubitmap_s()
	s.framer = T.menubitmap_s()
	s.player = T.menubitmap_s()
	s.name = T.menufield_s()
	s.handicap = T.menulist_s()
	s.effects = T.menulist_s()
	s.effects2 = T.menulist_s()
	s.back = T.menubitmap_s()
	s.model = T.menubitmap_s()
	s.item_null = T.menubitmap_s()
	s.playerinfo = T.playerInfo_t()
	s.current_fx = 0
	s.playerModel = ""

	PlayerSettings_Cache()

	s.menu.key = PlayerSettings_MenuKey
	s.menu.wrapAround = true
	s.menu.fullscreen = true

	s.banner.generic.type = C.MTYPE_BTEXT
	s.banner.generic.x = 320
	s.banner.generic.y = 16
	s.banner.string = "PLAYER SETTINGS"
	s.banner.color = U.color_white
	s.banner.style = C.UI_CENTER

	s.framel.generic.type = C.MTYPE_BITMAP
	s.framel.generic.name = ART_FRAMEL
	s.framel.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	s.framel.generic.x = 0
	s.framel.generic.y = 78
	s.framel.width = 256
	s.framel.height = 329

	s.framer.generic.type = C.MTYPE_BITMAP
	s.framer.generic.name = ART_FRAMER
	s.framer.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	s.framer.generic.x = 376
	s.framer.generic.y = 76
	s.framer.width = 256
	s.framer.height = 334

	local y = 144
	s.name.generic.type = C.MTYPE_FIELD
	s.name.generic.flags = C.QMF_NODEFAULTINIT
	s.name.generic.ownerdraw = PlayerSettings_DrawName
	s.name.field.widthInChars = MAX_NAMELENGTH
	s.name.field.maxchars = MAX_NAMELENGTH
	s.name.generic.x = 192
	s.name.generic.y = y
	s.name.generic.left = 192 - 8
	s.name.generic.top = y - 8
	s.name.generic.right = 192 + 200
	s.name.generic.bottom = y + 2 * C.PROP_HEIGHT

	y += 3 * C.PROP_HEIGHT
	s.handicap.generic.type = C.MTYPE_SPINCONTROL
	s.handicap.generic.flags = C.QMF_NODEFAULTINIT
	s.handicap.generic.id = ID_HANDICAP
	s.handicap.generic.ownerdraw = PlayerSettings_DrawHandicap
	s.handicap.generic.x = 192
	s.handicap.generic.y = y
	s.handicap.generic.left = 192 - 8
	s.handicap.generic.top = y - 8
	s.handicap.generic.right = 192 + 200
	s.handicap.generic.bottom = y + 2 * C.PROP_HEIGHT
	s.handicap.generic.statusbar = PlayerSettings_StatusBar
	s.handicap.numitems = 20

	y += 3 * C.PROP_HEIGHT
	s.effects.generic.type = C.MTYPE_SPINCONTROL
	s.effects.generic.flags = C.QMF_NODEFAULTINIT
	s.effects.generic.id = ID_EFFECTS
	s.effects.generic.ownerdraw = PlayerSettings_DrawEffects
	s.effects.generic.x = 192
	s.effects.generic.y = y
	s.effects.generic.left = 192 - 8
	s.effects.generic.top = y - 8
	s.effects.generic.right = 192 + 200
	s.effects.generic.bottom = y + 2 * C.PROP_HEIGHT
	s.effects.numitems = 7

	y += 2 * C.PROP_HEIGHT
	s.effects2.generic.type = C.MTYPE_SPINCONTROL
	s.effects2.generic.flags = C.QMF_NODEFAULTINIT
	s.effects2.generic.id = ID_EFFECTS2
	s.effects2.generic.ownerdraw = PlayerSettings_DrawEffects2
	s.effects2.generic.x = 192
	s.effects2.generic.y = y
	s.effects2.generic.left = 192 - 8
	s.effects2.generic.top = y - 8
	s.effects2.generic.right = 192 + 200
	s.effects2.generic.bottom = y + 2 * C.PROP_HEIGHT
	s.effects2.numitems = 7

	s.model.generic.type = C.MTYPE_BITMAP
	s.model.generic.name = ART_MODEL0
	s.model.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.model.generic.id = ID_MODEL
	s.model.generic.callback = PlayerSettings_MenuEvent
	s.model.generic.x = 640
	s.model.generic.y = 480 - 64
	s.model.width = 128
	s.model.height = 64
	s.model.focuspic = ART_MODEL1

	s.player.generic.type = C.MTYPE_BITMAP
	s.player.generic.flags = C.QMF_INACTIVE
	s.player.generic.ownerdraw = PlayerSettings_DrawPlayer
	s.player.generic.x = 400
	s.player.generic.y = -40
	s.player.width = 32 * 10
	s.player.height = 56 * 10

	s.back.generic.type = C.MTYPE_BITMAP
	s.back.generic.name = ART_BACK0
	s.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.back.generic.id = ID_BACK
	s.back.generic.callback = PlayerSettings_MenuEvent
	s.back.generic.x = 0
	s.back.generic.y = 480 - 64
	s.back.width = 128
	s.back.height = 64
	s.back.focuspic = ART_BACK1

	s.item_null.generic.type = C.MTYPE_BITMAP
	s.item_null.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_MOUSEONLY, C.QMF_SILENT)
	s.item_null.generic.x = 0
	s.item_null.generic.y = 0
	s.item_null.width = 640
	s.item_null.height = 480

	U.Menu_AddItem(s.menu, s.banner)
	U.Menu_AddItem(s.menu, s.framel)
	U.Menu_AddItem(s.menu, s.framer)

	U.Menu_AddItem(s.menu, s.name)
	U.Menu_AddItem(s.menu, s.handicap)
	U.Menu_AddItem(s.menu, s.effects)
	U.Menu_AddItem(s.menu, s.effects2)
	U.Menu_AddItem(s.menu, s.model)
	U.Menu_AddItem(s.menu, s.back)

	U.Menu_AddItem(s.menu, s.player)

	U.Menu_AddItem(s.menu, s.item_null)

	PlayerSettings_SetMenuItems()
end

function U.PlayerSettings_Cache()
	PlayerSettings_Cache()
end

function U.UI_PlayerSettingsMenu()
	PlayerSettings_MenuInit()
	U.UI_PushMenu(s_playersettings.menu)
end

return U
