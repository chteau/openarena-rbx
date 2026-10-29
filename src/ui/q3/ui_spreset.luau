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
-- Luau port of code/q3_ui/ui_spreset.c (OpenArena gamecode).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_FRAME = "menu/art/cut_frame"

local ID_NO = 100
local ID_YES = 101

local s_reset = {
	menu = T.menuframework_s(),
	no = T.menutext_s(),
	yes = T.menutext_s(),
	slashX = 0,
}

function U.Reset_MenuEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	U.UI_PopMenu()

	if ptr.generic.id == ID_NO then
		return
	end

	-- reset the game, pop the level menu and restart it so it updates
	U.UI_NewGame()
	trap.Cvar_SetValue("ui_spSelection", 0)
	U.UI_PopMenu()
	U.UI_SPLevelMenu()
end

local function Reset_MenuKey(key)
	if key == C.K_LEFTARROW or key == C.K_RIGHTARROW then
		key = C.K_TAB
	elseif key == 110 or key == 78 then
		U.Reset_MenuEvent(s_reset.no, C.QM_ACTIVATED)
	elseif key == 121 or key == 89 then
		U.Reset_MenuEvent(s_reset.yes, C.QM_ACTIVATED)
	end

	return U.Menu_DefaultKey(s_reset.menu, key)
end

local function Reset_MenuDraw()
	U.UI_DrawNamedPic(142, 118, 359, 256, ART_FRAME)
	U.UI_DrawProportionalString(320, 194 + 10, "RESET GAME?", bit32.bor(C.UI_CENTER, C.UI_INVERSE), Q.colorRed)
	U.UI_DrawProportionalString(s_reset.slashX, 265, "/", bit32.bor(C.UI_LEFT, C.UI_INVERSE), Q.colorRed)
	U.Menu_Draw(s_reset.menu)

	local small = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
	U.UI_DrawProportionalString(C.SCREEN_WIDTH / 2, 356 + C.PROP_HEIGHT * 0, "WARNING: This resets all of the", small, Q.colorYellow)
	U.UI_DrawProportionalString(C.SCREEN_WIDTH / 2, 356 + C.PROP_HEIGHT * 1, "single player game variables.", small, Q.colorYellow)
	U.UI_DrawProportionalString(C.SCREEN_WIDTH / 2, 356 + C.PROP_HEIGHT * 2, "Do this only if you want to", small, Q.colorYellow)
	U.UI_DrawProportionalString(C.SCREEN_WIDTH / 2, 356 + C.PROP_HEIGHT * 3, "start over from the beginning.", small, Q.colorYellow)
end

function U.Reset_Cache()
	trap.R_RegisterShaderNoMip(ART_FRAME)
end

function U.UI_ResetMenu()
	-- zero set all our globals
	s_reset.menu = T.menuframework_s()
	s_reset.no = T.menutext_s()
	s_reset.yes = T.menutext_s()
	s_reset.slashX = 0

	U.Reset_Cache()

	local n1 = U.UI_ProportionalStringWidth("YES/NO")
	local n2 = U.UI_ProportionalStringWidth("YES") + C.PROP_GAP_WIDTH
	local n3 = U.UI_ProportionalStringWidth("/") + C.PROP_GAP_WIDTH
	local l1 = 320 - Q.idiv(n1, 2)
	local l2 = l1 + n2
	local l3 = l2 + n3
	s_reset.slashX = l2

	s_reset.menu.draw = Reset_MenuDraw
	s_reset.menu.key = Reset_MenuKey
	s_reset.menu.wrapAround = true

	local cstate = T.uiClientState_t()
	trap.GetClientState(cstate)

	if cstate.connState >= C.CA_CONNECTED then
		-- float on top of running game
		s_reset.menu.fullscreen = false
	else
		-- game not running
		s_reset.menu.fullscreen = true
	end

	s_reset.yes.generic.type = C.MTYPE_PTEXT
	s_reset.yes.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_reset.yes.generic.callback = U.Reset_MenuEvent
	s_reset.yes.generic.id = ID_YES
	s_reset.yes.generic.x = l1
	s_reset.yes.generic.y = 264
	s_reset.yes.string = "YES"
	s_reset.yes.color = Q.colorRed
	s_reset.yes.style = C.UI_LEFT

	s_reset.no.generic.type = C.MTYPE_PTEXT
	s_reset.no.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_reset.no.generic.callback = U.Reset_MenuEvent
	s_reset.no.generic.id = ID_NO
	s_reset.no.generic.x = l3
	s_reset.no.generic.y = 264
	s_reset.no.string = "NO"
	s_reset.no.color = Q.colorRed
	s_reset.no.style = C.UI_LEFT

	U.Menu_AddItem(s_reset.menu, s_reset.yes)
	U.Menu_AddItem(s_reset.menu, s_reset.no)

	U.UI_PushMenu(s_reset.menu)

	U.Menu_SetCursorToItem(s_reset.menu, s_reset.no)
end

return U
