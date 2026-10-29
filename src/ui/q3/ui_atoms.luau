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
-- Luau port of code/q3_ui/ui_atoms.c (OpenArena gamecode).
-- Covers C lines 1-1293.

--[[
	UI_ATOMS.C

	User interface building blocks and support functions.
]]

local U = require(script.Parent.U)
local Screen = require(script.Parent.Parent.Screen)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot

U.m_entersound = false -- after a frame, so caching won't disrupt the sound

function U.Com_Error(level, error, ...)
	trap.Error(Q.va("%s", Q.va(error, ...)))
end

function U.Com_Printf(msg, ...)
	trap.Print(Q.va("%s", Q.va(msg, ...)))
end

function U.UI_ClampCvar(min, max, value)
	if value < min then
		return min
	end
	if value > max then
		return max
	end
	return value
end

function U.UI_StartDemoLoop()
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "d1\n")
end

function U.UI_PushMenu(menu)
	local uis = U.uis
	local i = 0

	-- avoid stacking menus invoked by hotkeys
	while i < uis.menusp do
		if uis.stack[i] == menu then
			uis.menusp = i
			break
		end
		i += 1
	end

	if i == uis.menusp then
		if uis.menusp >= C.MAX_MENUDEPTH then
			trap.Error("UI_PushMenu: menu stack overflow")
		end

		uis.stack[uis.menusp] = menu
		uis.menusp += 1
	end

	uis.activemenu = menu

	-- default cursor position
	menu.cursor = 0
	menu.cursor_prev = 0

	U.m_entersound = true

	trap.Key_SetCatcher(C.KEYCATCH_UI)

	-- force first available item to have focus
	for j = 0, menu.nitems - 1 do
		local item = menu.items[j].generic
		if band(item.flags, bor(C.QMF_GRAYED, C.QMF_MOUSEONLY, C.QMF_INACTIVE)) == 0 then
			menu.cursor_prev = -1
			U.Menu_SetCursor(menu, j)
			break
		end
	end

	uis.firstdraw = true
end

function U.UI_PopMenu()
	local uis = U.uis
	trap.S_StartLocalSound(U.menu_out_sound, C.CHAN_LOCAL_SOUND)

	uis.menusp -= 1

	if uis.menusp < 0 then
		trap.Error("UI_PopMenu: menu stack underflow")
	end

	if uis.menusp ~= 0 then
		uis.activemenu = uis.stack[uis.menusp - 1]
		uis.firstdraw = true
	else
		U.UI_ForceMenuOff()
	end
end

function U.UI_ForceMenuOff()
	local uis = U.uis
	uis.menusp = 0
	uis.activemenu = nil

	trap.Key_SetCatcher(band(trap.Key_GetCatcher(), bnot(C.KEYCATCH_UI)))
	trap.Key_ClearStates()
	trap.Cvar_Set("cl_paused", "0")
end

function U.UI_LerpColor(a, b, c, t)
	-- lerp and clamp each component
	for i = 0, 3 do
		c[i] = a[i] + t * (b[i] - a[i])
		if c[i] < 0 then
			c[i] = 0
		elseif c[i] > 1.0 then
			c[i] = 1.0
		end
	end
end

local function P(a, b, c)
	return { [0] = a, [1] = b, [2] = c }
end

local propMap = {}
for i = 0, 31 do
	propMap[i] = P(0, 0, -1)
end
do
	local rows = {
		{ 0, 0, C.PROP_SPACE_WIDTH }, -- SPACE
		{ 11, 122, 7 }, -- !
		{ 154, 181, 14 }, -- "
		{ 55, 122, 17 }, -- #
		{ 79, 122, 18 }, -- $
		{ 101, 122, 23 }, -- %
		{ 153, 122, 18 }, -- &
		{ 9, 93, 7 }, -- '
		{ 207, 122, 8 }, -- (
		{ 230, 122, 9 }, -- )
		{ 177, 122, 18 }, -- *
		{ 30, 152, 18 }, -- +
		{ 85, 181, 7 }, -- ,
		{ 34, 93, 11 }, -- -
		{ 110, 181, 6 }, -- .
		{ 130, 152, 14 }, -- /
		{ 22, 64, 17 }, -- 0
		{ 41, 64, 12 }, -- 1
		{ 58, 64, 17 }, -- 2
		{ 78, 64, 18 }, -- 3
		{ 98, 64, 19 }, -- 4
		{ 120, 64, 18 }, -- 5
		{ 141, 64, 18 }, -- 6
		{ 204, 64, 16 }, -- 7
		{ 162, 64, 17 }, -- 8
		{ 182, 64, 18 }, -- 9
		{ 59, 181, 7 }, -- :
		{ 35, 181, 7 }, -- ;
		{ 203, 152, 14 }, -- <
		{ 56, 93, 14 }, -- =
		{ 228, 152, 14 }, -- >
		{ 177, 181, 18 }, -- ?
		{ 28, 122, 22 }, -- @
	}
	local letters = {
		{ 5, 4, 18 }, -- A
		{ 27, 4, 18 }, -- B
		{ 48, 4, 18 }, -- C
		{ 69, 4, 17 }, -- D
		{ 90, 4, 13 }, -- E
		{ 106, 4, 13 }, -- F
		{ 121, 4, 18 }, -- G
		{ 143, 4, 17 }, -- H
		{ 164, 4, 8 }, -- I
		{ 175, 4, 16 }, -- J
		{ 195, 4, 18 }, -- K
		{ 216, 4, 12 }, -- L
		{ 230, 4, 23 }, -- M
		{ 6, 34, 18 }, -- N
		{ 27, 34, 18 }, -- O
		{ 48, 34, 18 }, -- P
		{ 68, 34, 18 }, -- Q
		{ 90, 34, 17 }, -- R
		{ 110, 34, 18 }, -- S
		{ 130, 34, 14 }, -- T
		{ 146, 34, 18 }, -- U
		{ 166, 34, 19 }, -- V
		{ 185, 34, 29 }, -- W
		{ 215, 34, 18 }, -- X
		{ 234, 34, 18 }, -- Y
		{ 5, 64, 14 }, -- Z
	}
	for _, l in letters do
		table.insert(rows, l)
	end
	table.insert(rows, { 60, 152, 7 }) -- [
	table.insert(rows, { 106, 151, 13 }) -- backslash
	table.insert(rows, { 83, 152, 7 }) -- ]
	table.insert(rows, { 128, 122, 17 }) -- ^
	table.insert(rows, { 4, 152, 21 }) -- _
	table.insert(rows, { 134, 181, 5 }) -- '
	for _, l in letters do
		table.insert(rows, l)
	end
	table.insert(rows, { 153, 152, 13 }) -- {
	table.insert(rows, { 11, 181, 5 }) -- |
	table.insert(rows, { 180, 152, 13 }) -- }
	table.insert(rows, { 79, 93, 17 }) -- ~
	table.insert(rows, { 0, 0, -1 }) -- DEL
	for k, r in rows do
		propMap[31 + k] = P(r[1], r[2], r[3])
	end
end

local propMapB = {}
do
	local rows = {
		{ 11, 12, 33 },
		{ 49, 12, 31 },
		{ 85, 12, 31 },
		{ 120, 12, 30 },
		{ 156, 12, 21 },
		{ 183, 12, 21 },
		{ 207, 12, 32 },

		{ 13, 55, 30 },
		{ 49, 55, 13 },
		{ 66, 55, 29 },
		{ 101, 55, 31 },
		{ 135, 55, 21 },
		{ 158, 55, 40 },
		{ 204, 55, 32 },

		{ 12, 97, 31 },
		{ 48, 97, 31 },
		{ 82, 97, 30 },
		{ 118, 97, 30 },
		{ 153, 97, 30 },
		{ 185, 97, 25 },
		{ 213, 97, 30 },

		{ 11, 139, 32 },
		{ 42, 139, 51 },
		{ 93, 139, 32 },
		{ 126, 139, 31 },
		{ 158, 139, 25 },
	}
	for k, r in rows do
		propMapB[k - 1] = P(r[1], r[2], r[3])
	end
end

local PROPB_GAP_WIDTH = 4
local PROPB_SPACE_WIDTH = 12
local PROPB_HEIGHT = 36

local function UI_DrawBannerString2(x, y, str, color)
	local uis = U.uis

	-- draw the colored text
	trap.R_SetColor(color)

	local ax = x * uis.xscale + uis.bias
	local ay = y * uis.yscale

	for i = 1, #str do
		local ch = band(string.byte(str, i), 127)
		if ch == 32 then
			ax += (PROPB_SPACE_WIDTH + PROPB_GAP_WIDTH) * uis.xscale
		elseif ch >= 65 and ch <= 90 then
			ch -= 65
			local fcol = propMapB[ch][0] / 256.0
			local frow = propMapB[ch][1] / 256.0
			local fwidth = propMapB[ch][2] / 256.0
			local fheight = PROPB_HEIGHT / 256.0
			local aw = propMapB[ch][2] * uis.xscale
			local ah = PROPB_HEIGHT * uis.yscale
			trap.R_DrawStretchPic(ax, ay, aw, ah, fcol, frow, fcol + fwidth, frow + fheight, uis.charsetPropB)
			ax += (aw + PROPB_GAP_WIDTH * uis.xscale)
		end
	end

	trap.R_SetColor(nil)
end

function U.UI_DrawBannerString(x, y, str, style, color)
	-- find the width of the drawn text
	local width = 0
	for i = 1, #str do
		local ch = string.byte(str, i)
		if ch == 32 then
			width += PROPB_SPACE_WIDTH
		elseif ch >= 65 and ch <= 90 then
			width += propMapB[ch - 65][2] + PROPB_GAP_WIDTH
		end
	end
	width -= PROPB_GAP_WIDTH

	local fmt = band(style, C.UI_FORMATMASK)
	if fmt == C.UI_CENTER then
		x -= Q.idiv(width, 2)
	elseif fmt == C.UI_RIGHT then
		x -= width
	end

	if band(style, C.UI_DROPSHADOW) ~= 0 then
		local drawcolor = Q.vec4(0, 0, 0, color[3])
		UI_DrawBannerString2(x + 2, y + 2, str, drawcolor)
	end

	UI_DrawBannerString2(x, y, str, color)
end

function U.UI_ProportionalStringWidth(str)
	local width = 0
	for i = 1, #str do
		local ch = band(string.byte(str, i), 127)
		local charWidth = propMap[ch][2]
		if charWidth ~= -1 then
			width += charWidth
			width += C.PROP_GAP_WIDTH
		end
	end

	width -= C.PROP_GAP_WIDTH
	return width
end

local function UI_DrawProportionalString2(x, y, str, color, sizeScale, charset)
	local uis = U.uis
	local aw = 0

	-- draw the colored text
	trap.R_SetColor(color)

	local ax = x * uis.xscale + uis.bias
	local ay = y * uis.yscale

	for i = 1, #str do
		local ch = band(string.byte(str, i), 127)
		if ch == 32 then
			aw = C.PROP_SPACE_WIDTH * uis.xscale * sizeScale
		elseif propMap[ch][2] ~= -1 then
			local fcol = propMap[ch][0] / 256.0
			local frow = propMap[ch][1] / 256.0
			local fwidth = propMap[ch][2] / 256.0
			local fheight = C.PROP_HEIGHT / 256.0
			aw = propMap[ch][2] * uis.xscale * sizeScale
			local ah = C.PROP_HEIGHT * uis.yscale * sizeScale
			trap.R_DrawStretchPic(ax, ay, aw, ah, fcol, frow, fcol + fwidth, frow + fheight, charset)
		end

		ax += (aw + C.PROP_GAP_WIDTH * uis.xscale * sizeScale)
	end

	trap.R_SetColor(nil)
end

function U.UI_ProportionalSizeScale(style)
	if band(style, C.UI_SMALLFONT) ~= 0 then
		return C.PROP_SMALL_SIZE_SCALE
	end

	return 1.00
end

function U.UI_DrawProportionalString(x, y, str, style, color)
	local uis = U.uis
	local sizeScale = U.UI_ProportionalSizeScale(style)

	local fmt = band(style, C.UI_FORMATMASK)
	if fmt == C.UI_CENTER then
		local width = Q.int(U.UI_ProportionalStringWidth(str) * sizeScale)
		x -= Q.idiv(width, 2)
	elseif fmt == C.UI_RIGHT then
		local width = Q.int(U.UI_ProportionalStringWidth(str) * sizeScale)
		x -= width
	end

	if band(style, C.UI_DROPSHADOW) ~= 0 then
		local drawcolor = Q.vec4(0, 0, 0, color[3])
		UI_DrawProportionalString2(x + 2, y + 2, str, drawcolor, sizeScale, uis.charsetProp)
	end

	if band(style, C.UI_INVERSE) ~= 0 then
		local drawcolor = Q.vec4(color[0] * 0.7, color[1] * 0.7, color[2] * 0.7, color[3])
		UI_DrawProportionalString2(x, y, str, drawcolor, sizeScale, uis.charsetProp)
		return
	end

	if band(style, C.UI_PULSE) ~= 0 then
		UI_DrawProportionalString2(x, y, str, color, sizeScale, uis.charsetProp)

		local drawcolor =
			Q.vec4(color[0], color[1], color[2], 0.5 + 0.5 * math.sin(uis.realtime / C.PULSE_DIVISOR))
		UI_DrawProportionalString2(x, y, str, drawcolor, sizeScale, uis.charsetPropGlow)
		return
	end

	UI_DrawProportionalString2(x, y, str, color, sizeScale, uis.charsetProp)
end

function U.UI_DrawProportionalString_AutoWrapped(x, y, xmax, ystep, str, style, color)
	if str == nil or str == "" then
		return
	end

	local sizeScale = U.UI_ProportionalSizeScale(style)

	local buf = string.sub(str, 1, 1023)

	local function at(p)
		return string.byte(buf, p + 1) or 0
	end
	local function cstr(p)
		local nul = string.find(buf, "\0", p + 1, true)
		return string.sub(buf, p + 1, nul and nul - 1 or #buf)
	end

	local s1, s2, s3 = 0, 0, 0

	while true do
		repeat
			s3 += 1
		until at(s3) == 32 or at(s3) == 0
		local c_bcp = at(s3)
		local width = Q.int(U.UI_ProportionalStringWidth(string.sub(buf, s1 + 1, s3)) * sizeScale)
		if width > xmax then
			if s1 == s2 then
				-- don't have a clean cut, we'll overflow
				s2 = s3
			end
			buf = string.sub(buf, 1, s2) .. "\0" .. string.sub(buf, s2 + 2)
			U.UI_DrawProportionalString(x, y, cstr(s1), style, color)
			y += ystep
			if c_bcp == 0 then
				-- that was the last word; print it now if needed
				s2 += 1
				if at(s2) ~= 0 then
					U.UI_DrawProportionalString(x, y, cstr(s2), style, color)
				end
				break
			end
			s2 += 1
			s1 = s2
			s3 = s2
		else
			s2 = s3
			if c_bcp == 0 then -- we reached the end
				U.UI_DrawProportionalString(x, y, cstr(s1), style, color)
				break
			end
		end
	end
end

local function UI_DrawString2(x, y, str, color, charw, charh)
	local uis = U.uis
	local forceColor = false

	if y < -charh then
		-- offscreen
		return
	end

	-- draw the colored text
	trap.R_SetColor(color)

	local ax = x * uis.xscale + uis.bias
	local ay = y * uis.yscale
	local aw = charw * uis.xscale
	local ah = charh * uis.yscale

	local i = 1
	local n = #str
	while i <= n do
		local b = string.byte(str, i)
		local nb = string.byte(str, i + 1)
		if b == 94 and nb ~= nil and nb ~= 94 then
			if not forceColor then
				local src = Q.g_color_table[Q.ColorIndex(nb)]
				local tempcolor = Q.vec4(src[0], src[1], src[2], color[3])
				trap.R_SetColor(tempcolor)
			end
			i += 2
			continue
		end

		local ch = band(b, 255)
		if ch ~= 32 then
			local frow = bit32.rshift(ch, 4) * 0.0625
			local fcol = band(ch, 15) * 0.0625
			trap.R_DrawStretchPic(ax, ay, aw, ah, fcol, frow, fcol + 0.0625, frow + 0.0625, uis.charset)
		end

		ax += aw
		i += 1
	end

	trap.R_SetColor(nil)
end

function U.UI_DrawString(x, y, str, style, color)
	local uis = U.uis

	if str == nil then
		return
	end

	if band(style, C.UI_BLINK) ~= 0 and band(Q.idiv(uis.realtime, C.BLINK_DIVISOR), 1) ~= 0 then
		return
	end

	local charw, charh
	if band(style, C.UI_SMALLFONT) ~= 0 then
		charw = C.SMALLCHAR_WIDTH
		charh = C.SMALLCHAR_HEIGHT
	elseif band(style, C.UI_GIANTFONT) ~= 0 then
		charw = C.GIANTCHAR_WIDTH
		charh = C.GIANTCHAR_HEIGHT
	else
		charw = C.BIGCHAR_WIDTH
		charh = C.BIGCHAR_HEIGHT
	end

	local drawcolor
	if band(style, C.UI_PULSE) ~= 0 then
		local lowlight = Q.vec4(0.8 * color[0], 0.8 * color[1], 0.8 * color[2], 0.8 * color[3])
		local newcolor = Q.vec4(0, 0, 0, 0)
		U.UI_LerpColor(color, lowlight, newcolor, 0.5 + 0.5 * math.sin(uis.realtime / C.PULSE_DIVISOR))
		drawcolor = newcolor
	else
		drawcolor = color
	end

	local fmt = band(style, C.UI_FORMATMASK)
	if fmt == C.UI_CENTER then
		-- center justify at x
		x = x - Q.idiv(#str * charw, 2)
	elseif fmt == C.UI_RIGHT then
		-- right justify at x
		x = x - #str * charw
	end

	if band(style, C.UI_DROPSHADOW) ~= 0 then
		local dropcolor = Q.vec4(0, 0, 0, drawcolor[3])
		UI_DrawString2(x + 2, y + 2, str, dropcolor, charw, charh)
	end

	UI_DrawString2(x, y, str, drawcolor, charw, charh)
end

function U.UI_DrawChar(x, y, ch, style, color)
	U.UI_DrawString(x, y, string.char(band(ch, 255)), style, color)
end

function U.UI_IsFullscreen()
	local uis = U.uis
	if uis.activemenu ~= nil and band(trap.Key_GetCatcher(), C.KEYCATCH_UI) ~= 0 then
		return uis.activemenu.fullscreen
	end

	return false
end

local function NeedCDAction(result)
	if not result then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "quit\n")
	end
end

local function NeedCDKeyAction(result)
	if not result then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "quit\n")
	end
end

function U.UI_SetActiveMenu(menu)
	-- this should be the ONLY way the menu system is brought up
	-- enusure minumum menu data is cached
	U.Menu_Cache()

	if menu == C.UIMENU_NONE then
		U.UI_ForceMenuOff()
		return
	elseif menu == C.UIMENU_MAIN then
		U.UI_MainMenu()
		return
	elseif menu == C.UIMENU_NEED_CD then
		U.UI_ConfirmMenu("Insert the CD", nil, NeedCDAction)
		return
	elseif menu == C.UIMENU_BAD_CD_KEY then
		U.UI_ConfirmMenu("Bad CD Key", nil, NeedCDKeyAction)
		return
	elseif menu == C.UIMENU_INGAME then
		trap.Cvar_Set("cl_paused", "1")
		U.UI_InGameMenu()
		return
	else
		U.Com_Printf("UI_SetActiveMenu: bad enum %d\n", menu)
	end
end

function U.UI_KeyEvent(key, down)
	local uis = U.uis

	if uis.activemenu == nil then
		return
	end

	if not down then
		return
	end

	local s
	if uis.activemenu.key ~= nil then
		s = uis.activemenu.key(key)
	else
		s = U.Menu_DefaultKey(uis.activemenu, key)
	end

	if s > 0 and s ~= U.menu_null_sound then
		trap.S_StartLocalSound(s, C.CHAN_LOCAL_SOUND)
	end
end

function U.UI_MouseEvent(dx, dy)
	local uis = U.uis

	if uis.activemenu == nil then
		return
	end

	-- update mouse screen position
	uis.cursorx += dx
	if uis.cursorx < -uis.bias then
		uis.cursorx = -uis.bias
	elseif uis.cursorx > C.SCREEN_WIDTH + uis.bias then
		uis.cursorx = C.SCREEN_WIDTH + uis.bias
	end

	uis.cursory += dy
	if uis.cursory < 0 then
		uis.cursory = 0
	elseif uis.cursory > C.SCREEN_HEIGHT then
		uis.cursory = C.SCREEN_HEIGHT
	end

	local menu = uis.activemenu

	-- region test the active menu items
	for i = 0, menu.nitems - 1 do
		local m = menu.items[i].generic

		if band(m.flags, bor(C.QMF_GRAYED, C.QMF_INACTIVE)) ~= 0 then
			continue
		end

		if uis.cursorx < m.left or uis.cursorx > m.right or uis.cursory < m.top or uis.cursory > m.bottom then
			-- cursor out of item bounds
			continue
		end

		-- set focus to item at cursor
		if menu.cursor ~= i then
			U.Menu_SetCursor(menu, i)
			local prev = menu.items[menu.cursor_prev].generic
			prev.flags = band(prev.flags, bnot(C.QMF_HASMOUSEFOCUS))

			if band(menu.items[menu.cursor].generic.flags, C.QMF_SILENT) == 0 then
				trap.S_StartLocalSound(U.menu_move_sound, C.CHAN_LOCAL_SOUND)
			end
		end

		local cur = menu.items[menu.cursor].generic
		cur.flags = bor(cur.flags, C.QMF_HASMOUSEFOCUS)
		return
	end

	if menu.nitems > 0 then
		-- out of any region
		local cur = menu.items[menu.cursor].generic
		cur.flags = band(cur.flags, bnot(C.QMF_HASMOUSEFOCUS))
	end
end

function U.UI_Argv(arg)
	return trap.Argv(arg)
end

function U.UI_Cvar_VariableString(var_name)
	return trap.Cvar_VariableStringBuffer(var_name)
end

function U.UI_Cache_f()
	U.MainMenu_Cache()
	U.InGame_Cache()
	U.ConfirmMenu_Cache()
	U.PlayerModel_Cache()
	U.PlayerSettings_Cache()
	U.Controls_Cache()
	U.Demos_Cache()
	U.UI_CinematicsMenu_Cache()
	U.Preferences_Cache()
	U.ServerInfo_Cache()
	U.SpecifyServer_Cache()
	U.ArenaServers_Cache()
	U.StartServer_Cache()
	U.ServerOptions_Cache()
	U.DriverInfo_Cache()
	U.GraphicsOptions_Cache()
	U.UI_DisplayOptionsMenu_Cache()
	U.UI_SoundOptionsMenu_Cache()
	U.UI_NetworkOptionsMenu_Cache()
	U.UI_SPLevelMenu_Cache()
	U.UI_SPSkillMenu_Cache()
	U.UI_SPPostgameMenu_Cache()
	U.TeamMain_Cache()
	U.UI_AddBots_Cache()
	U.UI_RemoveBots_Cache()
	U.UI_SetupMenu_Cache()
	U.UI_BotSelectMenu_Cache()
	U.UI_CDKeyMenu_Cache()
	U.UI_ModsMenu_Cache()
end

function U.UI_ConsoleCommand(realTime)
	local uis = U.uis

	uis.frametime = realTime - uis.realtime
	uis.realtime = realTime

	local cmd = U.UI_Argv(0)

	-- ensure minimum menu data is available
	U.Menu_Cache()

	if cmd == "levelselect" then
		U.UI_SPLevelMenu_f()
		return true
	end

	if cmd == "postgame" then
		U.UI_SPPostgameMenu_f()
		return true
	end

	if cmd == "ui_cache" then
		U.UI_Cache_f()
		return true
	end

	if cmd == "ui_cinematics" then
		U.UI_CinematicsMenu_f()
		return true
	end

	if cmd == "ui_teamOrders" then
		U.UI_TeamOrdersMenu_f()
		return true
	end

	if cmd == "iamacheater" then
		U.UI_SPUnlock_f()
		return true
	end

	if cmd == "iamamonkey" then
		U.UI_SPUnlockMedals_f()
		return true
	end

	if cmd == "ui_cdkey" then
		U.UI_CDKeyMenu_f()
		return true
	end

	if cmd == "ui_mappage" then
		local mappage = U.mappage
		mappage.pagenumber = Q.int(tonumber(U.UI_Argv(1)) or 0)
		for k = 0, 9 do
			mappage.mapname[k] = string.sub(U.UI_Argv(k + 2), 1, 31)
		end

		U.UI_VoteMapMenuInternal()
		return true
	end

	if cmd == "ui_writemappools" then
		U.WriteMapList()
		return true
	end

	return false
end

function U.UI_Shutdown() end

function U.UI_Init()
	local uis = U.uis

	U.UI_RegisterCvars()

	U.UI_InitGameinfo()

	-- cache redundant calulations
	trap.GetGlconfig(uis.glconfig)

	-- for 640x480 virtualized screen
	Screen.uiSetup(uis)

	-- initialize the menu system
	U.Menu_Cache()

	uis.activemenu = nil
	uis.menusp = 0
end

-- Adjusted for resolution and screen aspect ratio
function U.UI_AdjustFrom640(x, y, w, h)
	return Screen.uiAdjust(U.uis, x, y, w, h)
end

function U.UI_DrawNamedPic(x, y, width, height, picname)
	local hShader = trap.R_RegisterShaderNoMip(picname)
	x, y, width, height = U.UI_AdjustFrom640(x, y, width, height)
	trap.R_DrawStretchPic(x, y, width, height, 0, 0, 1, 1, hShader)
end

function U.UI_DrawHandlePic(x, y, w, h, hShader)
	local s0, s1, t0, t1

	if w < 0 then -- flip about vertical
		w = -w
		s0 = 1
		s1 = 0
	else
		s0 = 0
		s1 = 1
	end

	if h < 0 then -- flip about horizontal
		h = -h
		t0 = 1
		t1 = 0
	else
		t0 = 0
		t1 = 1
	end

	x, y, w, h = U.UI_AdjustFrom640(x, y, w, h)
	trap.R_DrawStretchPic(x, y, w, h, s0, t0, s1, t1, hShader)
end

function U.UI_DrawBackgroundPic(hShader)
	local uis = U.uis
	trap.R_DrawStretchPic(0.0, 0.0, uis.glconfig.vidWidth, uis.glconfig.vidHeight, 0, 0, 1, 1, hShader)
end

-- Coordinates are 640*480 virtual values
function U.UI_FillRect(x, y, width, height, color)
	trap.R_SetColor(color)

	x, y, width, height = U.UI_AdjustFrom640(x, y, width, height)
	trap.R_DrawStretchPic(x, y, width, height, 0, 0, 0, 0, U.uis.whiteShader)

	trap.R_SetColor(nil)
end

-- Coordinates are 640*480 virtual values
function U.UI_DrawRect(x, y, width, height, color)
	local white = U.uis.whiteShader
	trap.R_SetColor(color)

	x, y, width, height = U.UI_AdjustFrom640(x, y, width, height)

	trap.R_DrawStretchPic(x, y, width, 1, 0, 0, 0, 0, white)
	trap.R_DrawStretchPic(x, y, 1, height, 0, 0, 0, 0, white)
	trap.R_DrawStretchPic(x, y + height - 1, width, 1, 0, 0, 0, 0, white)
	trap.R_DrawStretchPic(x + width - 1, y, 1, height, 0, 0, 0, 0, white)

	trap.R_SetColor(nil)
end

function U.UI_SetColor(rgba)
	trap.R_SetColor(rgba)
end

function U.UI_UpdateScreen()
	trap.UpdateScreen()
end

function U.UI_Refresh(realtime)
	local uis = U.uis

	uis.frametime = realtime - uis.realtime
	uis.realtime = realtime

	if band(trap.Key_GetCatcher(), C.KEYCATCH_UI) == 0 then
		return
	end

	U.UI_UpdateCvars()

	if uis.activemenu ~= nil then
		if uis.activemenu.fullscreen then
			-- draw the background
			if uis.activemenu.showlogo then
				U.UI_DrawBackgroundPic(uis.menuBackShader)
			else
				U.UI_DrawBackgroundPic(uis.menuBackNoLogoShader)
			end
		end

		if uis.activemenu.draw ~= nil then
			uis.activemenu.draw()
		else
			U.Menu_Draw(uis.activemenu)
		end

		if uis.firstdraw then
			U.UI_MouseEvent(0, 0)
			uis.firstdraw = false
		end
	end

	-- draw cursor
	U.UI_SetColor(nil)
	U.UI_DrawHandlePic(uis.cursorx - 16, uis.cursory - 16, 32, 32, uis.cursor)

	if uis.debug then
		-- cursor coordinates
		U.UI_DrawString(
			0,
			0,
			Q.va("(%d,%d)", uis.cursorx, uis.cursory),
			bor(C.UI_LEFT, C.UI_SMALLFONT),
			Q.colorRed
		)
	end

	-- delay playing the enter sound until after the
	-- menu has been drawn, to avoid delay while
	-- caching images
	if U.m_entersound then
		trap.S_StartLocalSound(U.menu_in_sound, C.CHAN_LOCAL_SOUND)
		U.m_entersound = false
	end
end

function U.UI_DrawTextBox(x, y, width, lines)
	U.UI_FillRect(
		x + Q.idiv(C.BIGCHAR_WIDTH, 2),
		y + Q.idiv(C.BIGCHAR_HEIGHT, 2),
		(width + 1) * C.BIGCHAR_WIDTH,
		(lines + 1) * C.BIGCHAR_HEIGHT,
		Q.colorBlack
	)
	U.UI_DrawRect(
		x + Q.idiv(C.BIGCHAR_WIDTH, 2),
		y + Q.idiv(C.BIGCHAR_HEIGHT, 2),
		(width + 1) * C.BIGCHAR_WIDTH,
		(lines + 1) * C.BIGCHAR_HEIGHT,
		Q.colorWhite
	)
end

function U.UI_CursorInRect(x, y, width, height)
	local uis = U.uis
	if uis.cursorx < x or uis.cursory < y or uis.cursorx > x + width or uis.cursory > y + height then
		return false
	end

	return true
end

return U
