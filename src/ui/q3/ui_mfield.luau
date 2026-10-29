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
-- Luau port of code/q3_ui/ui_mfield.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot

local function isLower(c: number): boolean
	return c >= 97 and c <= 122
end

local function isUpper(c: number): boolean
	return c >= 65 and c <= 90
end

local function toLower(c: number): number
	if isUpper(c) then
		return c + 32
	end
	return c
end

--[[
===================
MField_Draw

Handles horizontal scrolling and cursor blinking
x, y, are in pixels
===================
]]
function U.MField_Draw(edit, x, y, style, color)
	local charw
	local prestep
	local cursorChar

	local drawLen = edit.widthInChars
	local len = #edit.buffer + 1

	-- guarantee that cursor will be visible
	if len <= drawLen then
		prestep = 0
	else
		if edit.scroll + drawLen > len then
			edit.scroll = len - drawLen
			if edit.scroll < 0 then
				edit.scroll = 0
			end
		end
		prestep = edit.scroll
	end

	if prestep + drawLen > len then
		drawLen = len - prestep
	end

	-- extract <drawLen> characters from the field at <prestep>
	if drawLen >= C.MAX_STRING_CHARS then
		trap.Error("drawLen >= MAX_STRING_CHARS")
	end
	local str = string.sub(edit.buffer, prestep + 1, prestep + drawLen)

	U.UI_DrawString(x, y, str, style, color)

	-- draw the cursor
	if band(style, C.UI_PULSE) == 0 then
		return
	end

	if trap.Key_GetOverstrikeMode() then
		cursorChar = 11
	else
		cursorChar = 10
	end

	style = band(style, bnot(C.UI_PULSE))
	style = bor(style, C.UI_BLINK)

	if band(style, C.UI_SMALLFONT) ~= 0 then
		charw = C.SMALLCHAR_WIDTH
	elseif band(style, C.UI_GIANTFONT) ~= 0 then
		charw = C.GIANTCHAR_WIDTH
	else
		charw = C.BIGCHAR_WIDTH
	end

	if band(style, C.UI_CENTER) ~= 0 then
		len = #str
		x = x - math.floor(len * charw / 2)
	elseif band(style, C.UI_RIGHT) ~= 0 then
		len = #str
		x = x - len * charw
	end

	U.UI_DrawChar(x + (edit.cursor - prestep) * charw, y, cursorChar, band(style, bnot(bor(C.UI_CENTER, C.UI_RIGHT))), color)
end

function U.MField_Paste(edit)
	local pasteBuffer = string.sub(trap.GetClipboardData(), 1, 63)

	-- send as if typed, so insert / overstrike works properly
	local pasteLen = #pasteBuffer
	for i = 0, pasteLen - 1 do
		U.MField_CharEvent(edit, string.byte(pasteBuffer, i + 1))
	end
end

--[[
=================
MField_KeyDownEvent

Performs the basic line editing functions for the console,
in-game talk, and menu fields

Key events are used for non-printable characters, others are gotten from char events.
=================
]]
function U.MField_KeyDownEvent(edit, key)
	-- shift-insert is paste
	if key == C.K_INS and trap.Key_IsDown(C.K_SHIFT) then
		U.MField_Paste(edit)
		return
	end

	local len = #edit.buffer

	if key == C.K_DEL then
		if edit.cursor < len then
			edit.buffer = string.sub(edit.buffer, 1, edit.cursor) .. string.sub(edit.buffer, edit.cursor + 2)
		end
		return
	end

	if key == C.K_RIGHTARROW then
		if edit.cursor < len then
			edit.cursor += 1
		end
		if edit.cursor >= edit.scroll + edit.widthInChars and edit.cursor <= len then
			edit.scroll += 1
		end
		return
	end

	if key == C.K_LEFTARROW then
		if edit.cursor > 0 then
			edit.cursor -= 1
		end
		if edit.cursor < edit.scroll then
			edit.scroll -= 1
		end
		return
	end

	if key == C.K_HOME or (toLower(key) == 97 and trap.Key_IsDown(C.K_CTRL)) then
		edit.cursor = 0
		edit.scroll = 0
		return
	end

	if key == C.K_END or (toLower(key) == 101 and trap.Key_IsDown(C.K_CTRL)) then
		edit.cursor = len
		edit.scroll = len - edit.widthInChars + 1
		if edit.scroll < 0 then
			edit.scroll = 0
		end
		return
	end

	if key == C.K_INS then
		trap.Key_SetOverstrikeMode(not trap.Key_GetOverstrikeMode())
		return
	end
end

function U.MField_CharEvent(edit, ch)
	if ch == 22 then -- ctrl-v is paste
		U.MField_Paste(edit)
		return
	end

	if ch == 3 then -- ctrl-c clears the field
		U.MField_Clear(edit)
		return
	end

	local len = #edit.buffer

	if ch == 8 then -- ctrl-h is backspace
		if edit.cursor > 0 then
			edit.buffer = string.sub(edit.buffer, 1, edit.cursor - 1) .. string.sub(edit.buffer, edit.cursor + 1)
			edit.cursor -= 1
			if edit.cursor < edit.scroll then
				edit.scroll -= 1
			end
		end
		return
	end

	if ch == 1 then -- ctrl-a is home
		edit.cursor = 0
		edit.scroll = 0
		return
	end

	if ch == 5 then -- ctrl-e is end
		edit.cursor = len
		edit.scroll = edit.cursor - edit.widthInChars + 1
		if edit.scroll < 0 then
			edit.scroll = 0
		end
		return
	end

	-- ignore any other non printable chars
	if ch < 32 then
		return
	end

	local chStr = string.char(band(ch, 255))
	if not trap.Key_GetOverstrikeMode() then
		if edit.cursor == C.MAX_EDIT_LINE - 1 or (edit.maxchars ~= 0 and edit.cursor >= edit.maxchars) then
			return
		end
		edit.buffer = string.sub(edit.buffer, 1, edit.cursor) .. chStr .. string.sub(edit.buffer, edit.cursor + 2)
	else
		-- insert mode
		if len == C.MAX_EDIT_LINE - 1 or (edit.maxchars ~= 0 and len >= edit.maxchars) then
			return
		end
		edit.buffer = string.sub(edit.buffer, 1, edit.cursor) .. chStr .. string.sub(edit.buffer, edit.cursor + 1)
	end

	if edit.maxchars == 0 or edit.cursor < edit.maxchars - 1 then
		edit.cursor += 1
	end

	if edit.cursor >= edit.widthInChars then
		edit.scroll += 1
	end

	if edit.cursor == len + 1 then
		edit.buffer = string.sub(edit.buffer, 1, edit.cursor)
	end
end

function U.MField_Clear(edit)
	edit.buffer = ""
	edit.cursor = 0
	edit.scroll = 0
end

function U.MenuField_Init(m)
	local l, w, h

	U.MField_Clear(m.field)

	if band(m.generic.flags, C.QMF_SMALLFONT) ~= 0 then
		w = C.SMALLCHAR_WIDTH
		h = C.SMALLCHAR_HEIGHT
	else
		w = C.BIGCHAR_WIDTH
		h = C.BIGCHAR_HEIGHT
	end

	if m.generic.name ~= nil then
		l = (#m.generic.name + 1) * w
	else
		l = 0
	end

	m.generic.left = m.generic.x - l
	m.generic.top = m.generic.y
	m.generic.right = m.generic.x + w + m.field.widthInChars * w
	m.generic.bottom = m.generic.y + h
end

function U.MenuField_Draw(f)
	local w, style, focus, color

	local x = f.generic.x
	local y = f.generic.y

	if band(f.generic.flags, C.QMF_SMALLFONT) ~= 0 then
		w = C.SMALLCHAR_WIDTH
		style = C.UI_SMALLFONT
	else
		w = C.BIGCHAR_WIDTH
		style = C.UI_BIGFONT
	end

	if U.Menu_ItemAtCursor(f.generic.parent) == f then
		focus = true
		style = bor(style, C.UI_PULSE)
	else
		focus = false
	end

	if band(f.generic.flags, C.QMF_GRAYED) ~= 0 then
		color = U.text_color_disabled
	elseif focus then
		color = U.text_color_highlight
	else
		color = U.text_color_normal
	end

	if focus then
		-- draw cursor
		U.UI_FillRect(f.generic.left, f.generic.top, f.generic.right - f.generic.left + 1, f.generic.bottom - f.generic.top + 1, U.listbar_color)
		U.UI_DrawChar(x, y, 13, bor(C.UI_CENTER, C.UI_BLINK, style), color)
	end

	if f.generic.name ~= nil then
		U.UI_DrawString(x - w, y, f.generic.name, bor(style, C.UI_RIGHT), color)
	end

	U.MField_Draw(f.field, x + w, y, style, color)
end

-- key is passed by value; the (possibly replaced) key is returned as a second value
function U.MenuField_Key(m, key)
	local keycode = key

	if
		keycode == C.K_KP_ENTER
		or keycode == C.K_ENTER
		or keycode == C.K_JOY1
		or keycode == C.K_JOY2
		or keycode == C.K_JOY3
		or keycode == C.K_JOY4
	then
		-- have enter go to next cursor point
		key = C.K_TAB
	elseif keycode == C.K_TAB or keycode == C.K_DOWNARROW or keycode == C.K_UPARROW then
	else
		if band(keycode, C.K_CHAR_FLAG) ~= 0 then
			keycode = band(keycode, bnot(C.K_CHAR_FLAG))

			if band(m.generic.flags, C.QMF_UPPERCASE) ~= 0 and isLower(keycode) then
				keycode -= 32
			elseif band(m.generic.flags, C.QMF_LOWERCASE) ~= 0 and isUpper(keycode) then
				keycode += 32
			elseif band(m.generic.flags, C.QMF_NUMBERSONLY) ~= 0 and (isLower(keycode) or isUpper(keycode)) then
				return U.menu_buzz_sound, key
			end

			U.MField_CharEvent(m.field, keycode)
		else
			U.MField_KeyDownEvent(m.field, keycode)
		end
	end

	return 0, key
end

return U
