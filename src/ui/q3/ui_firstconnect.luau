--[[
===========================================================================
Copyright (C) 2009 Poul Sander

This file is part of the Open Arena source code.

Open Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Open Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Open Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/q3_ui/ui_firstconnect.c (OpenArena gamecode).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_BACK0 = "menu/" .. C.MENU_ART_DIR .. "/back_0"
local ART_BACK1 = "menu/" .. C.MENU_ART_DIR .. "/back_1"
local ART_FRAMEL = "menu/" .. C.MENU_ART_DIR .. "/frame2_l"
local ART_FRAMER = "menu/" .. C.MENU_ART_DIR .. "/frame1_r"
local ART_FIGHT0 = "menu/" .. C.MENU_ART_DIR .. "/accept_0"
local ART_FIGHT1 = "menu/" .. C.MENU_ART_DIR .. "/accept_1"

local ID_NAME = 10
local ID_RATE = 11
local ID_DELAGHITSCAN = 12
local ID_ALLOWDOWNLOAD = 13

local ID_GO = 100
local ID_BACK = 101

local MAX_NAMELENGTH = 20

local art_artlist = {
	[0] = ART_FRAMEL,
	ART_FRAMER,
	ART_BACK0,
	ART_BACK1,
	ART_FIGHT0,
	ART_FIGHT1,
}

local function item()
	return { generic = {} }
end

local function newFirstConnect()
	local menu = if T.menuframework_s
		then T.menuframework_s()
		else { cursor = 0, cursor_prev = 0, nitems = 0, nslots = 0, items = {}, wrapAround = false, fullscreen = false }
	local name = item()
	name.field = { buffer = "", cursor = 0, scroll = 0, widthInChars = 0, maxchars = 0 }
	local rate = item()
	rate.curvalue = 0
	local delag = item()
	delag.curvalue = 0
	local download = item()
	download.curvalue = 0
	return {
		menu = menu,
		banner = item(),
		framel = item(),
		framer = item(),
		go = item(),
		back = item(),
		info = item(),
		info2 = item(),
		name = name,
		rate = rate,
		delaghitscan = delag,
		allowdownload = download,
	}
end

local s_firstconnect = newFirstConnect()

local function PlayerSettings_DrawName2(self)
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

	U.UI_DrawProportionalString(basex, y, "Name:", style, color)

	-- draw the actual name
	basex += 64 + 10
	y += 4
	local txt = f.field.buffer
	color = Q.g_color_table[Q.ColorIndex(C.COLOR_WHITE)]
	local x = basex
	local i = 1
	local len = #txt
	while i <= len do
		local c = string.byte(txt, i)
		local nextc = string.byte(txt, i + 1)
		if not focus and c == 94 and nextc ~= nil and nextc ~= 94 then
			local n = bit32.band(nextc - 48, 31)
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

	-- draw cursor if we have focus
	if focus then
		local o = trap.Key_GetOverstrikeMode()
		local c
		if o == true or (type(o) == "number" and o ~= 0) then
			c = 11
		else
			c = 10
		end

		style = bit32.band(style, bit32.bnot(C.UI_PULSE))
		style = bit32.bor(style, C.UI_BLINK)

		U.UI_DrawChar(basex + f.field.cursor * C.SMALLCHAR_WIDTH, y, c, style, U.color_white)
	end
end

local function FirstConnect_StatusBar_Name(ptr)
	U.UI_DrawString(320, 440, "Your nickname", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), Q.colorWhite)
end

local function FirstConnect_StatusBar_Rate(ptr)
	U.UI_DrawString(320, 440, "Your connection speed", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), Q.colorWhite)
end

local function FirstConnect_StatusBar_Delag(ptr)
	U.UI_DrawString(320, 440, "Reliable Instanthit weapons", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), Q.colorWhite)
end

local function FirstConnect_StatusBar_Download(ptr)
	U.UI_DrawString(
		320,
		440,
		"Auto download missing maps and mods",
		bit32.bor(C.UI_CENTER, C.UI_SMALLFONT),
		Q.colorWhite
	)
end

local function FirstConnect_SaveChanges()
	trap.Cvar_Set("name", s_firstconnect.name.field.buffer)
end

local function FirstConnect_Event(ptr, event)
	local id = ptr.generic.id
	if id == ID_GO then
		if event ~= C.QM_ACTIVATED then
			return
		end
		FirstConnect_SaveChanges()
		U.UI_PopMenu()
		trap.Cvar_SetValue("ui_setupchecked", 1)
		U.UI_ArenaServersMenu()
	elseif id == ID_BACK then
		if event ~= C.QM_ACTIVATED then
			return
		end
		U.UI_PopMenu()
	elseif id == ID_RATE then
		local cv = s_firstconnect.rate.curvalue
		if cv == 0 then
			trap.Cvar_SetValue("rate", 2500)
		elseif cv == 1 then
			trap.Cvar_SetValue("rate", 3000)
		elseif cv == 2 then
			trap.Cvar_SetValue("rate", 4000)
		elseif cv == 3 then
			trap.Cvar_SetValue("rate", 5000)
		elseif cv == 4 then
			trap.Cvar_SetValue("rate", 25000)
		end
	elseif id == ID_ALLOWDOWNLOAD then
		trap.Cvar_SetValue("cl_allowDownload", s_firstconnect.allowdownload.curvalue)
		trap.Cvar_SetValue("sv_allowDownload", s_firstconnect.allowdownload.curvalue)
	elseif id == ID_DELAGHITSCAN then
		trap.Cvar_SetValue("g_delagHitscan", s_firstconnect.delaghitscan.curvalue)
		trap.Cvar_SetValue("cg_delag", s_firstconnect.delaghitscan.curvalue)
	end
end

local function FirstConnect_SetMenuItems()
	s_firstconnect.name.field.buffer = string.sub(U.UI_Cvar_VariableString("name"), 1, 255)

	local rate = Q.int(trap.Cvar_VariableValue("rate"))
	if rate <= 2500 then
		s_firstconnect.rate.curvalue = 0
	elseif rate <= 3000 then
		s_firstconnect.rate.curvalue = 1
	elseif rate <= 4000 then
		s_firstconnect.rate.curvalue = 2
	elseif rate <= 5000 then
		s_firstconnect.rate.curvalue = 3
	else
		s_firstconnect.rate.curvalue = 4
	end

	s_firstconnect.allowdownload.curvalue = Q.b2i(trap.Cvar_VariableValue("cl_allowDownload") ~= 0)
	s_firstconnect.delaghitscan.curvalue = Q.b2i(trap.Cvar_VariableValue("cg_delag") ~= 0)
end

function U.FirstConnect_Cache()
	-- touch all our pics
	local i = 0
	while art_artlist[i] ~= nil do
		trap.R_RegisterShaderNoMip(art_artlist[i])
		i += 1
	end
end

function U.FirstConnect_MenuInit()
	-- zero set all our globals
	s_firstconnect = newFirstConnect()
	local s = s_firstconnect

	U.FirstConnect_Cache()

	s.menu.wrapAround = true
	s.menu.fullscreen = true

	s.banner.generic.type = C.MTYPE_BTEXT
	s.banner.generic.x = 320
	s.banner.generic.y = 16
	s.banner.string = "FIRST CONNECT"
	s.banner.color = U.color_white
	s.banner.style = C.UI_CENTER

	s.framel.generic.type = C.MTYPE_BITMAP
	s.framel.generic.name = ART_FRAMEL
	s.framel.generic.flags = C.QMF_INACTIVE
	s.framel.generic.x = 0
	s.framel.generic.y = 78
	s.framel.width = 256
	s.framel.height = 329

	s.framer.generic.type = C.MTYPE_BITMAP
	s.framer.generic.name = ART_FRAMER
	s.framer.generic.flags = C.QMF_INACTIVE
	s.framer.generic.x = 376
	s.framer.generic.y = 76
	s.framer.width = 256
	s.framer.height = 334

	s.go.generic.type = C.MTYPE_BITMAP
	s.go.generic.name = ART_FIGHT0
	s.go.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.go.generic.callback = FirstConnect_Event
	s.go.generic.id = ID_GO
	s.go.generic.x = 640
	s.go.generic.y = 480 - 64
	s.go.width = 128
	s.go.height = 64
	s.go.focuspic = ART_FIGHT1

	s.back.generic.type = C.MTYPE_BITMAP
	s.back.generic.name = ART_BACK0
	s.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s.back.generic.callback = FirstConnect_Event
	s.back.generic.id = ID_BACK
	s.back.generic.x = 0
	s.back.generic.y = 480 - 64
	s.back.width = 128
	s.back.height = 64
	s.back.focuspic = ART_BACK1

	local y = 144
	s.name.generic.type = C.MTYPE_FIELD
	s.name.generic.flags = C.QMF_NODEFAULTINIT
	s.name.generic.ownerdraw = PlayerSettings_DrawName2
	s.name.field.widthInChars = MAX_NAMELENGTH
	s.name.field.maxchars = MAX_NAMELENGTH
	s.name.generic.x = 192
	s.name.generic.y = y
	s.name.generic.left = 192 - 8
	s.name.generic.top = y - 8
	s.name.generic.right = 192 + 200
	s.name.generic.bottom = y + 2 * C.PROP_HEIGHT
	s.name.generic.statusbar = FirstConnect_StatusBar_Name

	y += 4 * C.PROP_HEIGHT
	s.rate.generic.type = C.MTYPE_SPINCONTROL
	s.rate.generic.name = "Data Rate:"
	s.rate.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	s.rate.generic.callback = FirstConnect_Event
	s.rate.generic.id = ID_RATE
	s.rate.generic.x = 320
	s.rate.generic.y = y
	s.rate.itemnames = U.rate_items
	s.rate.generic.statusbar = FirstConnect_StatusBar_Rate

	y += C.BIGCHAR_HEIGHT + 2
	s.delaghitscan.generic.type = C.MTYPE_RADIOBUTTON
	s.delaghitscan.generic.name = "Compensate latency:"
	s.delaghitscan.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	s.delaghitscan.generic.callback = FirstConnect_Event
	s.delaghitscan.generic.id = ID_DELAGHITSCAN
	s.delaghitscan.generic.x = 320
	s.delaghitscan.generic.y = y
	s.delaghitscan.generic.statusbar = FirstConnect_StatusBar_Delag

	y += C.BIGCHAR_HEIGHT + 2
	s.allowdownload.generic.type = C.MTYPE_RADIOBUTTON
	s.allowdownload.generic.name = "Automatic Downloading:"
	s.allowdownload.generic.flags = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	s.allowdownload.generic.callback = FirstConnect_Event
	s.allowdownload.generic.id = ID_ALLOWDOWNLOAD
	s.allowdownload.generic.x = 320
	s.allowdownload.generic.y = y
	s.allowdownload.generic.statusbar = FirstConnect_StatusBar_Download

	s.info.generic.type = C.MTYPE_TEXT
	s.info.generic.x = 320
	s.info.generic.y = 400
	s.info.color = U.color_white
	s.info.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
	s.info.string = "Note: All settings can be changed later in SETUP"

	s.info2.generic.type = C.MTYPE_TEXT
	s.info2.generic.x = 320
	s.info2.generic.y = 80
	s.info2.color = U.color_white
	s.info2.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
	s.info2.string = "Please verify these settings"

	U.Menu_AddItem(s.menu, s.banner)
	U.Menu_AddItem(s.menu, s.framel)
	U.Menu_AddItem(s.menu, s.framer)
	U.Menu_AddItem(s.menu, s.go)
	U.Menu_AddItem(s.menu, s.back)

	U.Menu_AddItem(s.menu, s.name)
	U.Menu_AddItem(s.menu, s.rate)

	U.Menu_AddItem(s.menu, s.delaghitscan)
	U.Menu_AddItem(s.menu, s.allowdownload)

	U.Menu_AddItem(s.menu, s.info)
	U.Menu_AddItem(s.menu, s.info2)

	FirstConnect_SetMenuItems()
end

function U.UI_FirstConnectMenu()
	U.FirstConnect_MenuInit()
	U.UI_PushMenu(s_firstconnect.menu)
end

return U
