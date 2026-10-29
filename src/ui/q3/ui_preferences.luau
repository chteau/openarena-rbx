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
-- Luau port of code/q3_ui/ui_preferences.c (OpenArena gamecode).

--[[
=======================================================================

GAME OPTIONS MENU

=======================================================================
]]

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_FRAMEL = "menu/" .. C.MENU_ART_DIR .. "/frame2_l"
local ART_FRAMER = "menu/" .. C.MENU_ART_DIR .. "/frame1_r"
local ART_BACK0 = "menu/" .. C.MENU_ART_DIR .. "/back_0"
local ART_BACK1 = "menu/" .. C.MENU_ART_DIR .. "/back_1"

local PREFERENCES_X_POS = 360

local ID_CROSSHAIR = 127
local ID_SIMPLEITEMS = 128
local ID_HIGHQUALITYSKY = 129
local ID_EJECTINGBRASS = 130
local ID_WALLMARKS = 131
local ID_DYNAMICLIGHTS = 132
local ID_IDENTIFYTARGET = 133
local ID_SYNCEVERYFRAME = 134
local ID_FORCEMODEL = 135
local ID_DRAWTEAMOVERLAY = 136
local ID_ALLOWDOWNLOAD = 137
local ID_BACK = 138
local ID_WEAPONBAR = 139
local ID_DELAGHITSCAN = 140
local ID_COLORRED = 141
local ID_COLORGREEN = 142
local ID_COLORBLUE = 143
local ID_CROSSHAIRHEALTH = 144
local ID_CHATBEEP = 145
local ID_TEAMCHATBEEP = 146

local NUM_CROSSHAIRS = 99

local function newPreferences()
	return {
		menu = T.menuframework_s(),

		banner = T.menutext_s(),
		framel = T.menubitmap_s(),
		framer = T.menubitmap_s(),

		crosshair = T.menulist_s(),
		crosshairHealth = T.menuradiobutton_s(),

		crosshairColorRed = T.menuslider_s(),
		crosshairColorGreen = T.menuslider_s(),
		crosshairColorBlue = T.menuslider_s(),

		simpleitems = T.menuradiobutton_s(),
		alwaysweaponbar = T.menuradiobutton_s(),
		brass = T.menuradiobutton_s(),
		wallmarks = T.menuradiobutton_s(),
		dynamiclights = T.menuradiobutton_s(),
		identifytarget = T.menuradiobutton_s(),
		highqualitysky = T.menuradiobutton_s(),
		synceveryframe = T.menuradiobutton_s(),
		forcemodel = T.menuradiobutton_s(),
		drawteamoverlay = T.menulist_s(),
		delaghitscan = T.menuradiobutton_s(),
		allowdownload = T.menuradiobutton_s(),
		chatbeep = T.menuradiobutton_s(),
		teamchatbeep = T.menuradiobutton_s(),
		back = T.menubitmap_s(),

		crosshairShader = {},
	}
end

local s_preferences = newPreferences()
for n = 0, NUM_CROSSHAIRS - 1 do
	s_preferences.crosshairShader[n] = 0
end

local teamoverlay_names = {
	[0] = "off",
	[1] = "upper right",
	[2] = "lower right",
	[3] = "lower left",
}

local function cv(name)
	return trap.Cvar_VariableValue(name)
end

local function Preferences_SetMenuItems()
	local p = s_preferences
	p.crosshair.curvalue = math.fmod(Q.int(cv("cg_drawCrosshair")), NUM_CROSSHAIRS)
	p.crosshairHealth.curvalue = Q.b2i(cv("cg_crosshairHealth") ~= 0)
	p.crosshairColorRed.curvalue = cv("cg_crosshairColorRed") * 255.0
	p.crosshairColorGreen.curvalue = cv("cg_crosshairColorGreen") * 255.0
	p.crosshairColorBlue.curvalue = cv("cg_crosshairColorBlue") * 255.0
	p.simpleitems.curvalue = Q.b2i(cv("cg_simpleItems") ~= 0)
	p.alwaysweaponbar.curvalue = Q.b2i(cv("cg_alwaysWeaponBar") ~= 0)
	p.brass.curvalue = Q.b2i(cv("cg_brassTime") ~= 0)
	p.wallmarks.curvalue = Q.b2i(cv("cg_marks") ~= 0)
	p.identifytarget.curvalue = Q.b2i(cv("cg_drawCrosshairNames") ~= 0)
	p.dynamiclights.curvalue = Q.b2i(cv("r_dynamiclight") ~= 0)
	p.highqualitysky.curvalue = Q.b2i(cv("r_fastsky") == 0)
	p.synceveryframe.curvalue = Q.b2i(cv("r_finish") ~= 0)
	p.forcemodel.curvalue = Q.b2i(cv("cg_forcemodel") ~= 0)
	p.drawteamoverlay.curvalue = Q.int(Q.Com_Clamp(0, 3, cv("cg_drawTeamOverlay")))
	p.allowdownload.curvalue = Q.b2i(cv("cl_allowDownload") ~= 0)
	p.delaghitscan.curvalue = Q.b2i(cv("cg_delag") ~= 0)
	p.chatbeep.curvalue = Q.b2i(cv("cg_chatBeep") ~= 0)
	p.teamchatbeep.curvalue = Q.b2i(cv("cg_teamChatBeep") ~= 0)
end

local function Preferences_Event(ptr, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end

	local p = s_preferences
	local id = ptr.generic.id

	if id == ID_CROSSHAIR then
		p.crosshair.curvalue = p.crosshair.curvalue + 1
		if p.crosshair.curvalue == NUM_CROSSHAIRS or p.crosshairShader[p.crosshair.curvalue] == 0 then
			p.crosshair.curvalue = 0
		end
		trap.Cvar_SetValue("cg_drawCrosshair", p.crosshair.curvalue)
	elseif id == ID_CROSSHAIRHEALTH then
		trap.Cvar_SetValue("cg_crosshairHealth", p.crosshairHealth.curvalue)
		if p.crosshairHealth.curvalue ~= 0 then
			-- If crosshairHealth is on: Don't allow color selection
			p.crosshairColorRed.generic.flags = bit32.bor(p.crosshairColorRed.generic.flags, C.QMF_INACTIVE)
			p.crosshairColorGreen.generic.flags = bit32.bor(p.crosshairColorGreen.generic.flags, C.QMF_INACTIVE)
			p.crosshairColorBlue.generic.flags = bit32.bor(p.crosshairColorBlue.generic.flags, C.QMF_INACTIVE)
		else
			-- If crosshairHealth is off: Allow color selection
			p.crosshairColorRed.generic.flags = bit32.band(p.crosshairColorRed.generic.flags, bit32.bnot(C.QMF_INACTIVE))
			p.crosshairColorGreen.generic.flags = bit32.band(p.crosshairColorGreen.generic.flags, bit32.bnot(C.QMF_INACTIVE))
			p.crosshairColorBlue.generic.flags = bit32.band(p.crosshairColorBlue.generic.flags, bit32.bnot(C.QMF_INACTIVE))
		end
	elseif id == ID_COLORRED then
		trap.Cvar_SetValue("cg_crosshairColorRed", p.crosshairColorRed.curvalue / 255.0)
	elseif id == ID_COLORGREEN then
		trap.Cvar_SetValue("cg_crosshairColorGreen", p.crosshairColorGreen.curvalue / 255.0)
	elseif id == ID_COLORBLUE then
		trap.Cvar_SetValue("cg_crosshairColorBlue", p.crosshairColorBlue.curvalue / 255.0)
	elseif id == ID_SIMPLEITEMS then
		trap.Cvar_SetValue("cg_simpleItems", p.simpleitems.curvalue)
	elseif id == ID_WEAPONBAR then
		trap.Cvar_SetValue("cg_alwaysWeaponBar", p.alwaysweaponbar.curvalue)
	elseif id == ID_HIGHQUALITYSKY then
		trap.Cvar_SetValue("r_fastsky", Q.b2i(p.highqualitysky.curvalue == 0))
	elseif id == ID_EJECTINGBRASS then
		if p.brass.curvalue ~= 0 then
			trap.Cvar_Reset("cg_brassTime")
		else
			trap.Cvar_SetValue("cg_brassTime", 0)
		end
	elseif id == ID_WALLMARKS then
		trap.Cvar_SetValue("cg_marks", p.wallmarks.curvalue)
	elseif id == ID_DYNAMICLIGHTS then
		trap.Cvar_SetValue("r_dynamiclight", p.dynamiclights.curvalue)
	elseif id == ID_IDENTIFYTARGET then
		trap.Cvar_SetValue("cg_drawCrosshairNames", p.identifytarget.curvalue)
	elseif id == ID_SYNCEVERYFRAME then
		trap.Cvar_SetValue("r_finish", p.synceveryframe.curvalue)
	elseif id == ID_FORCEMODEL then
		trap.Cvar_SetValue("cg_forcemodel", p.forcemodel.curvalue)
	elseif id == ID_DRAWTEAMOVERLAY then
		trap.Cvar_SetValue("cg_drawTeamOverlay", p.drawteamoverlay.curvalue)
	elseif id == ID_ALLOWDOWNLOAD then
		trap.Cvar_SetValue("cl_allowDownload", p.allowdownload.curvalue)
		trap.Cvar_SetValue("sv_allowDownload", p.allowdownload.curvalue)
	elseif id == ID_DELAGHITSCAN then
		trap.Cvar_SetValue("g_delagHitscan", p.delaghitscan.curvalue)
		trap.Cvar_SetValue("cg_delag", p.delaghitscan.curvalue)
	elseif id == ID_CHATBEEP then
		trap.Cvar_SetValue("cg_chatBeep", p.chatbeep.curvalue)
	elseif id == ID_TEAMCHATBEEP then
		trap.Cvar_SetValue("cg_teamChatBeep", p.teamchatbeep.curvalue)
	elseif id == ID_BACK then
		U.UI_PopMenu()
	end
end

--[[
=================
Crosshair_Draw
=================
]]
local function Crosshair_Draw(self)
	local s = self
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
		U.UI_FillRect(s.generic.left, s.generic.top, s.generic.right - s.generic.left + 1, s.generic.bottom - s.generic.top + 1, U.listbar_color)
		U.UI_DrawChar(x, y, 13, bit32.bor(C.UI_CENTER, C.UI_BLINK, C.UI_SMALLFONT), color)
	end

	U.UI_DrawString(x - C.SMALLCHAR_WIDTH, y, s.generic.name, bit32.bor(style, C.UI_RIGHT), color)
	if s.curvalue == 0 then
		return
	end
	local color4 = Q.vec4(
		s_preferences.crosshairColorRed.curvalue / 255.0,
		s_preferences.crosshairColorGreen.curvalue / 255.0,
		s_preferences.crosshairColorBlue.curvalue / 255.0,
		1.0
	)
	trap.R_SetColor(color4)
	U.UI_DrawHandlePic(x + C.SMALLCHAR_WIDTH, y - 4, 24, 24, s_preferences.crosshairShader[s.curvalue])
end

local function Preferences_Menu_AddBoolean(menutext, y, id, text)
	menutext.generic.type = C.MTYPE_RADIOBUTTON
	menutext.generic.name = text
	menutext.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	menutext.generic.callback = Preferences_Event
	menutext.generic.id = id
	menutext.generic.x = PREFERENCES_X_POS
	menutext.generic.y = y
	return y + C.BIGCHAR_HEIGHT
end

local function sliderInit(item, name, id, y)
	item.generic.type = C.MTYPE_SLIDER
	item.generic.name = name
	item.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	item.generic.callback = Preferences_Event
	item.generic.id = id
	item.generic.x = PREFERENCES_X_POS
	item.generic.y = y
	item.minvalue = 0.0
	item.maxvalue = 255.0
end

local function Preferences_MenuInit()
	U.UI_SetDefaultCvar("cg_crosshairHealth", "1")
	U.UI_SetDefaultCvar("cg_crosshairColorRed", "1")
	U.UI_SetDefaultCvar("cg_crosshairColorBlue", "1")
	U.UI_SetDefaultCvar("cg_crosshairColorGreen", "1")

	s_preferences = newPreferences()
	local p = s_preferences

	U.Preferences_Cache()

	p.menu.wrapAround = true
	p.menu.fullscreen = true

	p.banner.generic.type = C.MTYPE_BTEXT
	p.banner.generic.x = 320
	p.banner.generic.y = 16
	p.banner.string = "GAME OPTIONS"
	p.banner.color = Q.colorWhite
	p.banner.style = C.UI_CENTER

	p.framel.generic.type = C.MTYPE_BITMAP
	p.framel.generic.name = ART_FRAMEL
	p.framel.generic.flags = C.QMF_INACTIVE
	p.framel.generic.x = 0
	p.framel.generic.y = 78
	p.framel.width = 256
	p.framel.height = 329

	p.framer.generic.type = C.MTYPE_BITMAP
	p.framer.generic.name = ART_FRAMER
	p.framer.generic.flags = C.QMF_INACTIVE
	p.framer.generic.x = 376
	p.framer.generic.y = 76
	p.framer.width = 256
	p.framer.height = 334

	local y = 82
	p.crosshair.generic.type = C.MTYPE_TEXT
	p.crosshair.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT, C.QMF_NODEFAULTINIT, C.QMF_OWNERDRAW)
	p.crosshair.generic.x = PREFERENCES_X_POS
	p.crosshair.generic.y = y
	p.crosshair.generic.name = "Crosshair:"
	p.crosshair.generic.callback = Preferences_Event
	p.crosshair.generic.ownerdraw = Crosshair_Draw
	p.crosshair.generic.id = ID_CROSSHAIR
	p.crosshair.generic.top = y - 4
	p.crosshair.generic.bottom = y + 20
	p.crosshair.generic.left = PREFERENCES_X_POS - ((#p.crosshair.generic.name + 1) * C.SMALLCHAR_WIDTH)
	p.crosshair.generic.right = PREFERENCES_X_POS + 48

	y = y + C.BIGCHAR_HEIGHT + 2
	p.crosshairHealth.generic.type = C.MTYPE_RADIOBUTTON
	p.crosshairHealth.generic.name = "Crosshair shows health:"
	p.crosshairHealth.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	p.crosshairHealth.generic.callback = Preferences_Event
	p.crosshairHealth.generic.id = ID_CROSSHAIRHEALTH
	p.crosshairHealth.generic.x = PREFERENCES_X_POS
	p.crosshairHealth.generic.y = y

	y = y + C.BIGCHAR_HEIGHT
	sliderInit(p.crosshairColorRed, "Crosshair red:", ID_COLORRED, y)

	y = y + C.BIGCHAR_HEIGHT + 2
	sliderInit(p.crosshairColorGreen, "Crosshair green:", ID_COLORGREEN, y)

	y = y + C.BIGCHAR_HEIGHT + 2
	sliderInit(p.crosshairColorBlue, "Crosshair blue:", ID_COLORBLUE, y)

	if p.crosshairHealth.curvalue ~= 0 then
		p.crosshairColorRed.generic.flags = bit32.bor(p.crosshairColorRed.generic.flags, C.QMF_INACTIVE)
		p.crosshairColorGreen.generic.flags = bit32.bor(p.crosshairColorGreen.generic.flags, C.QMF_INACTIVE)
		p.crosshairColorBlue.generic.flags = bit32.bor(p.crosshairColorBlue.generic.flags, C.QMF_INACTIVE)
	end

	y = y + C.BIGCHAR_HEIGHT + 2 + 4
	y = Preferences_Menu_AddBoolean(p.simpleitems, y, ID_SIMPLEITEMS, "Simple Items:")
	y = Preferences_Menu_AddBoolean(p.alwaysweaponbar, y, ID_WEAPONBAR, "Always show weapons:")
	y = Preferences_Menu_AddBoolean(p.wallmarks, y, ID_WALLMARKS, "Marks on Walls:")
	y = Preferences_Menu_AddBoolean(p.brass, y, ID_EJECTINGBRASS, "Ejecting Brass:")
	y = Preferences_Menu_AddBoolean(p.dynamiclights, y, ID_DYNAMICLIGHTS, "Dynamic Lights:")
	y = Preferences_Menu_AddBoolean(p.identifytarget, y, ID_IDENTIFYTARGET, "Identify Target:")
	y = Preferences_Menu_AddBoolean(p.highqualitysky, y, ID_HIGHQUALITYSKY, "High Quality Sky:")
	y = Preferences_Menu_AddBoolean(p.synceveryframe, y, ID_SYNCEVERYFRAME, "Sync Every Frame:")
	y = Preferences_Menu_AddBoolean(p.forcemodel, y, ID_FORCEMODEL, "Force Player Models:")

	p.drawteamoverlay.generic.type = C.MTYPE_SPINCONTROL
	p.drawteamoverlay.generic.name = "Draw Team Overlay:"
	p.drawteamoverlay.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	p.drawteamoverlay.generic.callback = Preferences_Event
	p.drawteamoverlay.generic.id = ID_DRAWTEAMOVERLAY
	p.drawteamoverlay.generic.x = PREFERENCES_X_POS
	p.drawteamoverlay.generic.y = y
	p.drawteamoverlay.itemnames = teamoverlay_names

	y = y + C.BIGCHAR_HEIGHT + 2

	y = Preferences_Menu_AddBoolean(p.delaghitscan, y, ID_DELAGHITSCAN, "Unlag hitscan:")
	y = Preferences_Menu_AddBoolean(p.allowdownload, y, ID_ALLOWDOWNLOAD, "Automatic Downloading:")
	y = Preferences_Menu_AddBoolean(p.chatbeep, y, ID_CHATBEEP, "Beep on chat:")
	y = Preferences_Menu_AddBoolean(p.teamchatbeep, y, ID_TEAMCHATBEEP, "Beep on team chat:")

	p.back.generic.type = C.MTYPE_BITMAP
	p.back.generic.name = ART_BACK0
	p.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	p.back.generic.callback = Preferences_Event
	p.back.generic.id = ID_BACK
	p.back.generic.x = 0
	p.back.generic.y = 480 - 64
	p.back.width = 128
	p.back.height = 64
	p.back.focuspic = ART_BACK1

	U.Menu_AddItem(p.menu, p.banner)
	U.Menu_AddItem(p.menu, p.framel)
	U.Menu_AddItem(p.menu, p.framer)

	U.Menu_AddItem(p.menu, p.crosshair)
	U.Menu_AddItem(p.menu, p.crosshairHealth)
	U.Menu_AddItem(p.menu, p.crosshairColorRed)
	U.Menu_AddItem(p.menu, p.crosshairColorGreen)
	U.Menu_AddItem(p.menu, p.crosshairColorBlue)
	U.Menu_AddItem(p.menu, p.simpleitems)
	U.Menu_AddItem(p.menu, p.alwaysweaponbar)
	U.Menu_AddItem(p.menu, p.wallmarks)
	U.Menu_AddItem(p.menu, p.brass)
	U.Menu_AddItem(p.menu, p.dynamiclights)
	U.Menu_AddItem(p.menu, p.identifytarget)
	U.Menu_AddItem(p.menu, p.highqualitysky)
	U.Menu_AddItem(p.menu, p.synceveryframe)
	U.Menu_AddItem(p.menu, p.forcemodel)
	U.Menu_AddItem(p.menu, p.drawteamoverlay)
	U.Menu_AddItem(p.menu, p.delaghitscan)
	U.Menu_AddItem(p.menu, p.allowdownload)
	U.Menu_AddItem(p.menu, p.chatbeep)
	U.Menu_AddItem(p.menu, p.teamchatbeep)

	U.Menu_AddItem(p.menu, p.back)

	Preferences_SetMenuItems()
end

--[[
===============
Preferences_Cache
===============
]]
function U.Preferences_Cache()
	trap.R_RegisterShaderNoMip(ART_FRAMEL)
	trap.R_RegisterShaderNoMip(ART_FRAMER)
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
	for n = 0, NUM_CROSSHAIRS - 1 do
		if n < 10 then
			s_preferences.crosshairShader[n] = trap.R_RegisterShaderNoMip("gfx/2d/crosshair" .. string.char(97 + n))
		else
			s_preferences.crosshairShader[n] = trap.R_RegisterShaderNoMip(Q.va("gfx/2d/crosshair%02d", n - 10))
		end
	end
end

--[[
===============
UI_PreferencesMenu
===============
]]
function U.UI_PreferencesMenu()
	Preferences_MenuInit()
	U.UI_PushMenu(s_preferences.menu)
end

return U
