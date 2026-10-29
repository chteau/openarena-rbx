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
-- Luau port of code/q3_ui/ui_credits.c (OpenArena gamecode).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local s_credits = {
	menu = { items = {}, nitems = 0, cursor = 0, cursor_prev = 0, wrapAround = false, fullscreen = false },
}

local function UI_CreditMenu_Key(key)
	if bit32.band(key, C.K_CHAR_FLAG) ~= 0 then
		return 0
	end

	-- Sago: I no longer show credits on close.
	return 0
end

local function UI_CreditMenu_Draw()
	local y = 12
	U.UI_DrawProportionalString(320, y, "Thank you for playing", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_white)
	y += C.PROP_HEIGHT * C.PROP_SMALL_SIZE_SCALE
	U.UI_DrawProportionalString(320, y, "Open Arena", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_white)

	y += 228
	U.UI_DrawString(320, y, "Terminating...", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_red)

	y = 480 - C.PROP_HEIGHT * C.PROP_SMALL_SIZE_SCALE
	U.UI_DrawProportionalString(320, y, "www.openarena.ws", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_white)
end

function U.UI_CreditMenu()
	s_credits.menu = { items = {}, nitems = 0, cursor = 0, cursor_prev = 0, wrapAround = false, fullscreen = false }

	s_credits.menu.draw = UI_CreditMenu_Draw
	s_credits.menu.key = UI_CreditMenu_Key
	s_credits.menu.fullscreen = true
	U.UI_PushMenu(s_credits.menu)
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "wait 2; quit\n")
end

return U
