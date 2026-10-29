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
-- Luau port of code/q3_ui/ui_confirm.c (OpenArena gamecode).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ART_CONFIRM_FRAME = "menu/" .. C.MENU_ART_DIR .. "/cut_frame"

local ID_CONFIRM_NO = 10
local ID_CONFIRM_YES = 11

local s_confirm

local function newConfirm()
	return {
		menu = T.menuframework_s(),
		no = T.menutext_s(),
		yes = T.menutext_s(),
		slashX = 0,
		question = nil,
		draw = nil,
		action = nil,
		style = 0,
		lines = nil,
	}
end

s_confirm = newConfirm()

local function ConfirmMenu_Event(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	U.UI_PopMenu()

	local result
	if ptr.generic.id == ID_CONFIRM_NO then
		result = false
	else
		result = true
	end

	if s_confirm.action ~= nil then
		s_confirm.action(result)
	end
end

local function ConfirmMenu_Key(key)
	if key == C.K_KP_LEFTARROW or key == C.K_LEFTARROW or key == C.K_KP_RIGHTARROW or key == C.K_RIGHTARROW then
		key = C.K_TAB
	elseif key == 110 or key == 78 then -- 'n', 'N'
		ConfirmMenu_Event(s_confirm.no, C.QM_ACTIVATED)
	elseif key == 121 or key == 89 then -- 'y', 'Y'
		ConfirmMenu_Event(s_confirm.yes, C.QM_ACTIVATED)
	end

	return U.Menu_DefaultKey(s_confirm.menu, key)
end

local function MessageMenu_Draw()
	U.UI_DrawNamedPic(142, 118, 359, 256, ART_CONFIRM_FRAME)

	local y = 188
	local i = 0
	while s_confirm.lines[i] ~= nil do
		U.UI_DrawProportionalString(320, y, s_confirm.lines[i], s_confirm.style, U.color_red)
		y += 18
		i += 1
	end

	U.Menu_Draw(s_confirm.menu)

	if s_confirm.draw ~= nil then
		s_confirm.draw()
	end
end

local function ConfirmMenu_Draw()
	U.UI_DrawNamedPic(142, 118, 359, 256, ART_CONFIRM_FRAME)
	U.UI_DrawProportionalString(320, 204, s_confirm.question, s_confirm.style, U.color_red)
	U.UI_DrawProportionalString(s_confirm.slashX, 265, "/", bit32.bor(C.UI_LEFT, C.UI_INVERSE), U.color_red)

	U.Menu_Draw(s_confirm.menu)

	if s_confirm.draw ~= nil then
		s_confirm.draw()
	end
end

function U.ConfirmMenu_Cache()
	trap.R_RegisterShaderNoMip(ART_CONFIRM_FRAME)
end

function U.UI_ConfirmMenu_Style(question, style, draw, action)
	-- zero set all our globals
	s_confirm = newConfirm()

	U.ConfirmMenu_Cache()

	local n1 = U.UI_ProportionalStringWidth("YES/NO")
	local n2 = U.UI_ProportionalStringWidth("YES") + C.PROP_GAP_WIDTH
	local n3 = U.UI_ProportionalStringWidth("/") + C.PROP_GAP_WIDTH
	local l1 = 320 - Q.idiv(n1, 2)
	local l2 = l1 + n2
	local l3 = l2 + n3
	s_confirm.slashX = l2

	s_confirm.question = question
	s_confirm.draw = draw
	s_confirm.action = action
	s_confirm.style = style

	s_confirm.menu.draw = ConfirmMenu_Draw
	s_confirm.menu.key = ConfirmMenu_Key
	s_confirm.menu.wrapAround = true

	local cstate = T.uiClientState_t()
	trap.GetClientState(cstate)
	if cstate.connState >= C.CA_CONNECTED then
		s_confirm.menu.fullscreen = false
	else
		s_confirm.menu.fullscreen = true
	end

	s_confirm.yes.generic.type = C.MTYPE_PTEXT
	s_confirm.yes.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_confirm.yes.generic.callback = ConfirmMenu_Event
	s_confirm.yes.generic.id = ID_CONFIRM_YES
	s_confirm.yes.generic.x = l1
	s_confirm.yes.generic.y = 264
	s_confirm.yes.string = "YES"
	s_confirm.yes.color = U.color_red
	s_confirm.yes.style = C.UI_LEFT

	s_confirm.no.generic.type = C.MTYPE_PTEXT
	s_confirm.no.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_confirm.no.generic.callback = ConfirmMenu_Event
	s_confirm.no.generic.id = ID_CONFIRM_NO
	s_confirm.no.generic.x = l3
	s_confirm.no.generic.y = 264
	s_confirm.no.string = "NO"
	s_confirm.no.color = U.color_red
	s_confirm.no.style = C.UI_LEFT

	U.Menu_AddItem(s_confirm.menu, s_confirm.yes)
	U.Menu_AddItem(s_confirm.menu, s_confirm.no)

	U.UI_PushMenu(s_confirm.menu)

	U.Menu_SetCursorToItem(s_confirm.menu, s_confirm.no)
end

function U.UI_ConfirmMenu(question, draw, action)
	U.UI_ConfirmMenu_Style(question, bit32.bor(C.UI_CENTER, C.UI_INVERSE), draw, action)
end

-- hacked over from Confirm stuff
function U.UI_Message(lines)
	-- zero set all our globals
	s_confirm = newConfirm()

	U.ConfirmMenu_Cache()

	local n1 = U.UI_ProportionalStringWidth("OK")
	local l1 = 320 - Q.idiv(n1, 2)

	s_confirm.lines = lines
	s_confirm.style = bit32.bor(C.UI_CENTER, C.UI_INVERSE, C.UI_SMALLFONT)

	s_confirm.menu.draw = MessageMenu_Draw
	s_confirm.menu.key = ConfirmMenu_Key
	s_confirm.menu.wrapAround = true

	local cstate = T.uiClientState_t()
	trap.GetClientState(cstate)
	if cstate.connState >= C.CA_CONNECTED then
		s_confirm.menu.fullscreen = false
	else
		s_confirm.menu.fullscreen = true
	end

	s_confirm.yes.generic.type = C.MTYPE_PTEXT
	s_confirm.yes.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_confirm.yes.generic.callback = ConfirmMenu_Event
	s_confirm.yes.generic.id = ID_CONFIRM_YES
	s_confirm.yes.generic.x = l1
	s_confirm.yes.generic.y = 280
	s_confirm.yes.string = "OK"
	s_confirm.yes.color = U.color_red
	s_confirm.yes.style = C.UI_LEFT

	U.Menu_AddItem(s_confirm.menu, s_confirm.yes)

	U.UI_PushMenu(s_confirm.menu)

	U.Menu_SetCursorToItem(s_confirm.menu, s_confirm.yes)
end

return U
