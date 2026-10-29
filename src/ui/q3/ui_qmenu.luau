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
-- Luau port of code/q3_ui/ui_qmenu.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- This part covers C lines 1-901 of the 0.8.8 source.

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local band = bit32.band
local bor = bit32.bor

U.menu_in_sound = 0
U.menu_move_sound = 0
U.menu_out_sound = 0
U.menu_buzz_sound = 0
U.menu_null_sound = 0
U.weaponChangeSound = 0

U.sliderBar = 0
U.sliderButton_0 = 0
U.sliderButton_1 = 0

-- NEW AND IMPLOVED colors
U.menu_text_color = Q.vec4(1.0, 1.0, 1.0, 1.0)
U.menu_dim_color = Q.vec4(0.0, 0.0, 0.0, 0.75)
U.color_black = Q.vec4(0.00, 0.00, 0.00, 1.00)
U.color_white = Q.vec4(1.00, 1.00, 1.00, 1.00)
U.color_yellow = Q.vec4(1.00, 1.00, 0.00, 1.00)
U.color_blue = Q.vec4(0.00, 0.00, 1.00, 1.00)
U.color_lightOrange = Q.vec4(0.30, 0.45, 0.58, 1.00)
U.color_orange = Q.vec4(0.30, 0.45, 0.58, 1.00)
U.color_red = Q.vec4(0.55, 0.65, 0.73, 1.00)
U.color_dim = Q.vec4(0.00, 0.00, 0.00, 0.25)

-- current color scheme
U.pulse_color = Q.vec4(1.00, 1.00, 1.00, 1.00)
U.text_color_disabled = Q.vec4(0.35, 0.24, 0.29, 1.00)
U.text_color_normal = Q.vec4(0.30, 0.45, 0.58, 1.00)
U.text_color_highlight = Q.vec4(0.76, 0.89, 0.93, 1.00)
U.listbar_color = Q.vec4(0.13, 0.26, 0.38, 0.30)
U.text_color_status = Q.vec4(1.00, 1.00, 1.00, 1.00)

function U.Text_Init(t)
	t.generic.flags = bor(t.generic.flags, C.QMF_INACTIVE)
end

function U.Text_Draw(t)
	local x = t.generic.x
	local y = t.generic.y

	local buff = ""

	-- possible label
	if t.generic.name ~= nil then
		buff = t.generic.name
	end

	-- possible value
	if t.string ~= nil then
		buff = buff .. t.string
	end

	local color
	if band(t.generic.flags, C.QMF_GRAYED) ~= 0 then
		color = U.text_color_disabled
	else
		color = t.color
	end

	U.UI_DrawString(x, y, buff, t.style, color)
end

function U.BText_Init(t)
	t.generic.flags = bor(t.generic.flags, C.QMF_INACTIVE)
end

function U.BText_Draw(t)
	local x = t.generic.x
	local y = t.generic.y

	local color
	if band(t.generic.flags, C.QMF_GRAYED) ~= 0 then
		color = U.text_color_disabled
	else
		color = t.color
	end

	U.UI_DrawBannerString(x, y, t.string, t.style, color)
end

function U.PText_Init(t)
	local sizeScale = U.UI_ProportionalSizeScale(t.style)

	local x = t.generic.x
	local y = t.generic.y
	local w = Q.int(U.UI_ProportionalStringWidth(t.string) * sizeScale)
	local h = Q.int(C.PROP_HEIGHT * sizeScale)

	if band(t.generic.flags, C.QMF_RIGHT_JUSTIFY) ~= 0 then
		x -= w
	elseif band(t.generic.flags, C.QMF_CENTER_JUSTIFY) ~= 0 then
		x -= Q.idiv(w, 2)
	end

	t.generic.left = Q.int(x - C.PROP_GAP_WIDTH * sizeScale)
	t.generic.right = Q.int(x + w + C.PROP_GAP_WIDTH * sizeScale)
	t.generic.top = y
	t.generic.bottom = y + h
end

function U.PText_Draw(t)
	local x = t.generic.x
	local y = t.generic.y

	local color
	if band(t.generic.flags, C.QMF_GRAYED) ~= 0 then
		color = U.text_color_disabled
	else
		color = t.color
	end

	local style = t.style
	if band(t.generic.flags, C.QMF_PULSEIFFOCUS) ~= 0 then
		if U.Menu_ItemAtCursor(t.generic.parent) == t then
			style = bor(style, C.UI_PULSE)
		else
			style = bor(style, C.UI_INVERSE)
		end
	end

	U.UI_DrawProportionalString(x, y, t.string, style, color)
end

function U.Bitmap_Init(b)
	local x = b.generic.x
	local y = b.generic.y
	local w = b.width
	local h = b.height
	if w < 0 then
		w = -w
	end
	if h < 0 then
		h = -h
	end

	if band(b.generic.flags, C.QMF_RIGHT_JUSTIFY) ~= 0 then
		x = x - w
	elseif band(b.generic.flags, C.QMF_CENTER_JUSTIFY) ~= 0 then
		x = x - Q.idiv(w, 2)
	end

	b.generic.left = x
	b.generic.right = x + w
	b.generic.top = y
	b.generic.bottom = y + h

	b.shader = 0
	b.focusshader = 0
end

function U.Bitmap_Draw(b)
	local x = b.generic.x
	local y = b.generic.y
	local w = b.width
	local h = b.height

	if band(b.generic.flags, C.QMF_RIGHT_JUSTIFY) ~= 0 then
		x = x - w
	elseif band(b.generic.flags, C.QMF_CENTER_JUSTIFY) ~= 0 then
		x = x - w / 2
	end

	-- used to refresh shader
	if b.generic.name ~= nil and b.shader == 0 then
		b.shader = trap.R_RegisterShaderNoMip(b.generic.name)
		if b.shader == 0 and b.errorpic ~= nil then
			b.shader = trap.R_RegisterShaderNoMip(b.errorpic)
		end
	end

	if b.focuspic ~= nil and b.focusshader == 0 then
		b.focusshader = trap.R_RegisterShaderNoMip(b.focuspic)
	end

	if band(b.generic.flags, C.QMF_GRAYED) ~= 0 then
		if b.shader ~= 0 then
			trap.R_SetColor(Q.colorMdGrey)
			U.UI_DrawHandlePic(x, y, w, h, b.shader)
			trap.R_SetColor(nil)
		end
	else
		if b.shader ~= 0 then
			U.UI_DrawHandlePic(x, y, w, h, b.shader)
		end

		if
			(band(b.generic.flags, C.QMF_PULSE) ~= 0 or band(b.generic.flags, C.QMF_PULSEIFFOCUS) ~= 0)
			and U.Menu_ItemAtCursor(b.generic.parent) == b
		then
			local color
			if b.focuscolor ~= nil then
				color = Q.vec4(b.focuscolor[0], b.focuscolor[1], b.focuscolor[2], 0)
			else
				color = U.pulse_color
			end
			color[3] = 0.5 + 0.5 * math.sin(U.uis.realtime / C.PULSE_DIVISOR)

			trap.R_SetColor(color)
			U.UI_DrawHandlePic(x, y, w, h, b.focusshader)
			trap.R_SetColor(nil)
		elseif
			band(b.generic.flags, C.QMF_HIGHLIGHT) ~= 0
			or (band(b.generic.flags, C.QMF_HIGHLIGHT_IF_FOCUS) ~= 0 and U.Menu_ItemAtCursor(b.generic.parent) == b)
		then
			if b.focuscolor ~= nil then
				trap.R_SetColor(b.focuscolor)
				U.UI_DrawHandlePic(x, y, w, h, b.focusshader)
				trap.R_SetColor(nil)
			else
				U.UI_DrawHandlePic(x, y, w, h, b.focusshader)
			end
		end
	end
end

function U.Action_Init(a)
	local len
	if a.generic.name ~= nil then
		len = #a.generic.name
	else
		len = 0
	end

	-- left justify text
	a.generic.left = a.generic.x
	a.generic.right = a.generic.x + len * C.BIGCHAR_WIDTH
	a.generic.top = a.generic.y
	a.generic.bottom = a.generic.y + C.BIGCHAR_HEIGHT
end

function U.Action_Draw(a)
	local style = 0
	local color = U.menu_text_color
	local flags = a.generic.flags
	local focus = a.generic.parent.cursor == a.generic.menuPosition
	if band(flags, C.QMF_GRAYED) ~= 0 then
		color = U.text_color_disabled
	elseif band(flags, C.QMF_PULSEIFFOCUS) ~= 0 and focus then
		color = U.text_color_highlight
		style = C.UI_PULSE
	elseif band(flags, C.QMF_HIGHLIGHT_IF_FOCUS) ~= 0 and focus then
		color = U.text_color_highlight
	elseif band(flags, C.QMF_BLINK) ~= 0 then
		style = C.UI_BLINK
		color = U.text_color_highlight
	end

	local x = a.generic.x
	local y = a.generic.y

	U.UI_DrawString(x, y, a.generic.name, bor(C.UI_LEFT, style), color)

	if focus then
		-- draw cursor
		U.UI_DrawChar(x - C.BIGCHAR_WIDTH, y, 13, bor(C.UI_LEFT, C.UI_BLINK), color)
	end
end

function U.RadioButton_Init(rb)
	local len
	if rb.generic.name ~= nil then
		len = #rb.generic.name
	else
		len = 0
	end

	rb.generic.left = rb.generic.x - (len + 1) * C.SMALLCHAR_WIDTH
	rb.generic.right = rb.generic.x + 6 * C.SMALLCHAR_WIDTH
	rb.generic.top = rb.generic.y
	rb.generic.bottom = rb.generic.y + C.SMALLCHAR_HEIGHT
end

function U.RadioButton_Key(rb, key)
	local handled = false
	if key == C.K_MOUSE1 then
		if band(rb.generic.flags, C.QMF_HASMOUSEFOCUS) == 0 then
			return 0
		end
		handled = true
	elseif
		key == C.K_JOY1
		or key == C.K_JOY2
		or key == C.K_JOY3
		or key == C.K_JOY4
		or key == C.K_ENTER
		or key == C.K_LEFTARROW
		or key == C.K_RIGHTARROW
	then
		handled = true
	end

	if handled then
		rb.curvalue = if rb.curvalue ~= 0 then 0 else 1
		if rb.generic.callback ~= nil then
			rb.generic.callback(rb, C.QM_ACTIVATED)
		end

		return U.menu_move_sound
	end

	-- key not handled
	return 0
end

function U.RadioButton_Draw(rb)
	local x = rb.generic.x
	local y = rb.generic.y
	local color, style

	local focus = rb.generic.parent.cursor == rb.generic.menuPosition

	if band(rb.generic.flags, C.QMF_GRAYED) ~= 0 then
		color = U.text_color_disabled
		style = bor(C.UI_LEFT, C.UI_SMALLFONT)
	elseif focus then
		color = U.text_color_highlight
		style = bor(C.UI_LEFT, C.UI_PULSE, C.UI_SMALLFONT)
	else
		color = U.text_color_normal
		style = bor(C.UI_LEFT, C.UI_SMALLFONT)
	end

	if focus then
		-- draw cursor
		U.UI_FillRect(
			rb.generic.left,
			rb.generic.top,
			rb.generic.right - rb.generic.left + 1,
			rb.generic.bottom - rb.generic.top + 1,
			U.listbar_color
		)
		U.UI_DrawChar(x, y, 13, bor(C.UI_CENTER, C.UI_BLINK, C.UI_SMALLFONT), color)
	end

	if rb.generic.name ~= nil then
		U.UI_DrawString(x - C.SMALLCHAR_WIDTH, y, rb.generic.name, bor(C.UI_RIGHT, C.UI_SMALLFONT), color)
	end

	if rb.curvalue == 0 then
		U.UI_DrawHandlePic(x + C.SMALLCHAR_WIDTH, y + 2, 16, 16, U.uis.rb_off)
		U.UI_DrawString(x + C.SMALLCHAR_WIDTH + 16, y, "off", style, color)
	else
		U.UI_DrawHandlePic(x + C.SMALLCHAR_WIDTH, y + 2, 16, 16, U.uis.rb_on)
		U.UI_DrawString(x + C.SMALLCHAR_WIDTH + 16, y, "on", style, color)
	end
end

function U.Slider_Init(s)
	local len
	if s.generic.name ~= nil then
		len = #s.generic.name
	else
		len = 0
	end

	s.generic.left = s.generic.x - (len + 1) * C.SMALLCHAR_WIDTH
	s.generic.right = s.generic.x + (C.SLIDER_RANGE + 2 + 1) * C.SMALLCHAR_WIDTH
	s.generic.top = s.generic.y
	s.generic.bottom = s.generic.y + C.SMALLCHAR_HEIGHT
end

function U.Slider_Key(s, key)
	local sound

	if key == C.K_MOUSE1 then
		local x = U.uis.cursorx - s.generic.x - 2 * C.SMALLCHAR_WIDTH
		local oldvalue = Q.int(s.curvalue)
		s.curvalue = (x / (C.SLIDER_RANGE * C.SMALLCHAR_WIDTH)) * (s.maxvalue - s.minvalue) + s.minvalue

		if s.curvalue < s.minvalue then
			s.curvalue = s.minvalue
		elseif s.curvalue > s.maxvalue then
			s.curvalue = s.maxvalue
		end
		if s.curvalue ~= oldvalue then
			sound = U.menu_move_sound
		else
			sound = 0
		end
	elseif key == C.K_LEFTARROW then
		if s.curvalue > s.minvalue then
			s.curvalue -= 1
			sound = U.menu_move_sound
		else
			sound = U.menu_buzz_sound
		end
	elseif key == C.K_RIGHTARROW then
		if s.curvalue < s.maxvalue then
			s.curvalue += 1
			sound = U.menu_move_sound
		else
			sound = U.menu_buzz_sound
		end
	else
		-- key not handled
		sound = 0
	end

	if sound ~= 0 and s.generic.callback ~= nil then
		s.generic.callback(s, C.QM_ACTIVATED)
	end

	return sound
end

function U.Slider_Draw(s)
	local x = s.generic.x
	local y = s.generic.y
	local color, style
	local focus = s.generic.parent.cursor == s.generic.menuPosition

	if band(s.generic.flags, C.QMF_GRAYED) ~= 0 then
		color = U.text_color_disabled
		style = C.UI_SMALLFONT
	elseif focus then
		color = U.text_color_highlight
		style = bor(C.UI_SMALLFONT, C.UI_PULSE)
	else
		color = U.text_color_normal
		style = C.UI_SMALLFONT
	end

	-- draw label
	U.UI_DrawString(x - C.SMALLCHAR_WIDTH, y, s.generic.name, bor(C.UI_RIGHT, style), color)

	-- draw slider
	U.UI_SetColor(color)
	U.UI_DrawHandlePic(x + C.SMALLCHAR_WIDTH, y, 96, 16, U.sliderBar)
	U.UI_SetColor(nil)

	-- clamp thumb
	if s.maxvalue > s.minvalue then
		s.range = (s.curvalue - s.minvalue) / (s.maxvalue - s.minvalue)
		if s.range < 0 then
			s.range = 0
		elseif s.range > 1 then
			s.range = 1
		end
	else
		s.range = 0
	end

	-- draw thumb
	local button
	if band(style, C.UI_PULSE) ~= 0 then
		button = U.sliderButton_1
	else
		button = U.sliderButton_0
	end

	U.UI_DrawHandlePic(
		Q.int(x + 2 * C.SMALLCHAR_WIDTH + (C.SLIDER_RANGE - 1) * C.SMALLCHAR_WIDTH * s.range) - 2,
		y - 2,
		12,
		20,
		button
	)
end

function U.SpinControl_Init(s)
	local len
	if s.generic.name ~= nil then
		len = #s.generic.name * C.SMALLCHAR_WIDTH
	else
		len = 0
	end

	s.generic.left = s.generic.x - C.SMALLCHAR_WIDTH - len

	len = 0
	s.numitems = 0
	while true do
		local str = s.itemnames[s.numitems]
		if str == nil then
			break
		end
		local l = #str
		if l > len then
			len = l
		end

		s.numitems += 1
	end

	s.generic.top = s.generic.y
	s.generic.right = s.generic.x + (len + 1) * C.SMALLCHAR_WIDTH
	s.generic.bottom = s.generic.y + C.SMALLCHAR_HEIGHT
end

function U.SpinControl_Key(s, key)
	local sound = 0

	if key == C.K_MOUSE1 then
		s.curvalue += 1
		if s.curvalue >= s.numitems then
			s.curvalue = 0
		end
		sound = U.menu_move_sound
	elseif key == C.K_LEFTARROW then
		if s.curvalue > 0 then
			s.curvalue -= 1
			sound = U.menu_move_sound
		else
			sound = U.menu_buzz_sound
		end
	elseif key == C.K_RIGHTARROW then
		if s.curvalue < s.numitems - 1 then
			s.curvalue += 1
			sound = U.menu_move_sound
		else
			sound = U.menu_buzz_sound
		end
	end

	if sound ~= 0 and s.generic.callback ~= nil then
		s.generic.callback(s, C.QM_ACTIVATED)
	end

	return sound
end

function U.SpinControl_Draw(s)
	local x = s.generic.x
	local y = s.generic.y
	local color

	local style = C.UI_SMALLFONT
	local focus = s.generic.parent.cursor == s.generic.menuPosition

	if band(s.generic.flags, C.QMF_GRAYED) ~= 0 then
		color = U.text_color_disabled
	elseif focus then
		color = U.text_color_highlight
		style = bor(style, C.UI_PULSE)
	elseif band(s.generic.flags, C.QMF_BLINK) ~= 0 then
		color = U.text_color_highlight
		style = bor(style, C.UI_BLINK)
	else
		color = U.text_color_normal
	end

	if focus then
		-- draw cursor
		U.UI_FillRect(
			s.generic.left,
			s.generic.top,
			s.generic.right - s.generic.left + 1,
			s.generic.bottom - s.generic.top + 1,
			U.listbar_color
		)
		U.UI_DrawChar(x, y, 13, bor(C.UI_CENTER, C.UI_BLINK, C.UI_SMALLFONT), color)
	end

	U.UI_DrawString(x - C.SMALLCHAR_WIDTH, y, s.generic.name, bor(style, C.UI_RIGHT), color)
	U.UI_DrawString(x + C.SMALLCHAR_WIDTH, y, s.itemnames[s.curvalue], bor(style, C.UI_LEFT), color)
end

return U
