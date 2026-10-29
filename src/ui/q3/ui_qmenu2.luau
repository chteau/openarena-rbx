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
-- This part covers C lines 902-1751 of the 0.8.8 source.

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot

local function isprint(c: number): boolean
	return c >= 32 and c <= 126
end

local function isupper(c: number): boolean
	return c >= 65 and c <= 90
end

function U.ScrollList_Init(l)
	l.oldvalue = 0
	l.curvalue = 0
	l.top = 0

	if l.columns == 0 then
		l.columns = 1
		l.seperation = 0
	elseif l.seperation == 0 then
		l.seperation = 3
	end

	local w = ((l.width + l.seperation) * l.columns - l.seperation) * C.SMALLCHAR_WIDTH

	local g = l.generic
	g.left = g.x
	g.top = g.y
	g.right = g.x + w
	g.bottom = g.y + l.height * C.SMALLCHAR_HEIGHT

	if band(g.flags, C.QMF_CENTER_JUSTIFY) ~= 0 then
		g.left -= Q.idiv(w, 2)
		g.right -= Q.idiv(w, 2)
	end
end

function U.ScrollList_Key(l, key)
	local g = l.generic

	if key == C.K_MOUSE1 then
		if band(g.flags, C.QMF_HASMOUSEFOCUS) ~= 0 then
			-- check scroll region
			local x = g.x
			local y = g.y
			local w = ((l.width + l.seperation) * l.columns - l.seperation) * C.SMALLCHAR_WIDTH
			if band(g.flags, C.QMF_CENTER_JUSTIFY) ~= 0 then
				x -= Q.idiv(w, 2)
			end
			if U.UI_CursorInRect(x, y, w, l.height * C.SMALLCHAR_HEIGHT) then
				local cursorx = Q.idiv(U.uis.cursorx - x, C.SMALLCHAR_WIDTH)
				local column = Q.idiv(cursorx, l.width + l.seperation)
				local cursory = Q.idiv(U.uis.cursory - y, C.SMALLCHAR_HEIGHT)
				local index = column * l.height + cursory
				if l.top + index < l.numitems then
					l.oldvalue = l.curvalue
					l.curvalue = l.top + index

					if l.oldvalue ~= l.curvalue and g.callback ~= nil then
						g.callback(l, C.QM_GOTFOCUS)
						return U.menu_move_sound
					end
				end

				-- absorbed, silent sound effect
				return U.menu_null_sound
			end
			return U.menu_null_sound
		end
	elseif key == C.K_HOME then
		l.oldvalue = l.curvalue
		l.curvalue = 0
		l.top = 0

		if l.oldvalue ~= l.curvalue and g.callback ~= nil then
			g.callback(l, C.QM_GOTFOCUS)
			return U.menu_move_sound
		end
		return U.menu_buzz_sound
	elseif key == C.K_END then
		l.oldvalue = l.curvalue
		l.curvalue = l.numitems - 1
		if l.columns > 1 then
			local c = (Q.idiv(l.curvalue, l.height) + 1) * l.height
			l.top = c - (l.columns * l.height)
		else
			l.top = l.curvalue - (l.height - 1)
		end
		if l.top < 0 then
			l.top = 0
		end

		if l.oldvalue ~= l.curvalue and g.callback ~= nil then
			g.callback(l, C.QM_GOTFOCUS)
			return U.menu_move_sound
		end
		return U.menu_buzz_sound
	elseif key == C.K_PGUP then
		if l.columns > 1 then
			return U.menu_null_sound
		end

		if l.curvalue > 0 then
			l.oldvalue = l.curvalue
			l.curvalue -= l.height - 1
			if l.curvalue < 0 then
				l.curvalue = 0
			end
			l.top = l.curvalue
			if l.top < 0 then
				l.top = 0
			end

			if g.callback ~= nil then
				g.callback(l, C.QM_GOTFOCUS)
			end

			return U.menu_move_sound
		end
		return U.menu_buzz_sound
	elseif key == C.K_PGDN then
		if l.columns > 1 then
			return U.menu_null_sound
		end

		if l.curvalue < l.numitems - 1 then
			l.oldvalue = l.curvalue
			l.curvalue += l.height - 1
			if l.curvalue > l.numitems - 1 then
				l.curvalue = l.numitems - 1
			end
			l.top = l.curvalue - (l.height - 1)
			if l.top < 0 then
				l.top = 0
			end

			if g.callback ~= nil then
				g.callback(l, C.QM_GOTFOCUS)
			end

			return U.menu_move_sound
		end
		return U.menu_buzz_sound
	elseif key == C.K_UPARROW then
		if l.curvalue == 0 then
			return U.menu_buzz_sound
		end

		l.oldvalue = l.curvalue
		l.curvalue -= 1

		if l.curvalue < l.top then
			if l.columns == 1 then
				l.top -= 1
			else
				l.top -= l.height
			end
		end

		if g.callback ~= nil then
			g.callback(l, C.QM_GOTFOCUS)
		end

		return U.menu_move_sound
	elseif key == C.K_DOWNARROW then
		if l.curvalue == l.numitems - 1 then
			return U.menu_buzz_sound
		end

		l.oldvalue = l.curvalue
		l.curvalue += 1

		if l.curvalue >= l.top + l.columns * l.height then
			if l.columns == 1 then
				l.top += 1
			else
				l.top += l.height
			end
		end

		if g.callback ~= nil then
			g.callback(l, C.QM_GOTFOCUS)
		end

		return U.menu_move_sound
	elseif key == C.K_LEFTARROW then
		if l.columns == 1 then
			return U.menu_null_sound
		end

		if l.curvalue < l.height then
			return U.menu_buzz_sound
		end

		l.oldvalue = l.curvalue
		l.curvalue -= l.height

		if l.curvalue < l.top then
			l.top -= l.height
		end

		if g.callback ~= nil then
			g.callback(l, C.QM_GOTFOCUS)
		end

		return U.menu_move_sound
	elseif key == C.K_RIGHTARROW then
		if l.columns == 1 then
			return U.menu_null_sound
		end

		local c = l.curvalue + l.height

		if c >= l.numitems then
			return U.menu_buzz_sound
		end

		l.oldvalue = l.curvalue
		l.curvalue = c

		if l.curvalue > l.top + l.columns * l.height - 1 then
			l.top += l.height
		end

		if g.callback ~= nil then
			g.callback(l, C.QM_GOTFOCUS)
		end

		return U.menu_move_sound
	end

	-- cycle look for ascii key inside list items
	if not isprint(key) then
		return 0
	end

	-- force to lower for case insensitive compare
	if isupper(key) then
		key -= 65 - 97
	end

	-- iterate list items
	for i = 1, l.numitems do
		local j = math.fmod(l.curvalue + i, l.numitems)
		local c = string.byte(l.itemnames[j], 1) or 0
		if isupper(c) then
			c -= 65 - 97
		end

		if c == key then
			-- set current item, mimic windows listbox scroll behavior
			if j < l.top then
				-- behind top most item, set this as new top
				l.top = j
			elseif j > l.top + l.height - 1 then
				-- past end of list box, do page down
				l.top = (j + 1) - l.height
			end

			if l.curvalue ~= j then
				l.oldvalue = l.curvalue
				l.curvalue = j
				if g.callback ~= nil then
					g.callback(l, C.QM_GOTFOCUS)
				end
				return U.menu_move_sound
			end

			return U.menu_buzz_sound
		end
	end

	return U.menu_buzz_sound
end

function U.ScrollList_Draw(l)
	local hasfocus = l.generic.parent.cursor == l.generic.menuPosition

	local x = l.generic.x
	for column = 0, l.columns - 1 do
		local y = l.generic.y
		local base = l.top + column * l.height
		for i = base, base + l.height - 1 do
			if i >= l.numitems then
				break
			end

			local color
			local style
			if i == l.curvalue then
				local u = x - 2
				if band(l.generic.flags, C.QMF_CENTER_JUSTIFY) ~= 0 then
					u -= Q.idiv(l.width * C.SMALLCHAR_WIDTH, 2) + 1
				end

				U.UI_FillRect(u, y, l.width * C.SMALLCHAR_WIDTH, C.SMALLCHAR_HEIGHT + 2, U.listbar_color)
				color = U.text_color_highlight

				if hasfocus then
					style = bor(C.UI_PULSE, C.UI_LEFT, C.UI_SMALLFONT)
				else
					style = bor(C.UI_LEFT, C.UI_SMALLFONT)
				end
			else
				color = U.text_color_normal
				style = bor(C.UI_LEFT, C.UI_SMALLFONT)
			end
			if band(l.generic.flags, C.QMF_CENTER_JUSTIFY) ~= 0 then
				style = bor(style, C.UI_CENTER)
			end

			U.UI_DrawString(x, y, l.itemnames[i], style, color)

			y += C.SMALLCHAR_HEIGHT
		end
		x += (l.width + l.seperation) * C.SMALLCHAR_WIDTH
	end
end

function U.Menu_AddItem(menu, item)
	if menu.nitems >= C.MAX_MENUITEMS then
		trap.Error("Menu_AddItem: excessive items")
	end

	menu.items[menu.nitems] = item
	local g = item.generic
	g.parent = menu
	g.menuPosition = menu.nitems
	g.flags = band(g.flags, bnot(C.QMF_HASMOUSEFOCUS))

	-- perform any item specific initializations
	if band(g.flags, C.QMF_NODEFAULTINIT) == 0 then
		local t = g.type
		if t == C.MTYPE_ACTION then
			U.Action_Init(item)
		elseif t == C.MTYPE_FIELD then
			U.MenuField_Init(item)
		elseif t == C.MTYPE_SPINCONTROL then
			U.SpinControl_Init(item)
		elseif t == C.MTYPE_RADIOBUTTON then
			U.RadioButton_Init(item)
		elseif t == C.MTYPE_SLIDER then
			U.Slider_Init(item)
		elseif t == C.MTYPE_BITMAP then
			U.Bitmap_Init(item)
		elseif t == C.MTYPE_TEXT then
			U.Text_Init(item)
		elseif t == C.MTYPE_SCROLLLIST then
			U.ScrollList_Init(item)
		elseif t == C.MTYPE_PTEXT then
			U.PText_Init(item)
		elseif t == C.MTYPE_BTEXT then
			U.BText_Init(item)
		else
			trap.Error(Q.va("Menu_Init: unknown type %d", t))
		end
	end

	menu.nitems += 1
end

function U.Menu_CursorMoved(m)
	if m.cursor_prev == m.cursor then
		return
	end

	if m.cursor_prev >= 0 and m.cursor_prev < m.nitems then
		local callback = m.items[m.cursor_prev].generic.callback
		if callback ~= nil then
			callback(m.items[m.cursor_prev], C.QM_LOSTFOCUS)
		end
	end

	if m.cursor >= 0 and m.cursor < m.nitems then
		local callback = m.items[m.cursor].generic.callback
		if callback ~= nil then
			callback(m.items[m.cursor], C.QM_GOTFOCUS)
		end
	end
end

function U.Menu_SetCursor(m, cursor)
	if band(m.items[cursor].generic.flags, bor(C.QMF_GRAYED, C.QMF_INACTIVE)) ~= 0 then
		-- cursor can't go there
		return
	end

	m.cursor_prev = m.cursor
	m.cursor = cursor

	U.Menu_CursorMoved(m)
end

function U.Menu_SetCursorToItem(m, ptr)
	for i = 0, m.nitems - 1 do
		if m.items[i] == ptr then
			U.Menu_SetCursor(m, i)
			return
		end
	end
end

--[[
** Menu_AdjustCursor
**
** This function takes the given menu, the direction, and attempts
** to adjust the menu's cursor so that it's at the next available
** slot.
]]
function U.Menu_AdjustCursor(m, dir)
	local wrapped = false
	local skip = bor(C.QMF_GRAYED, C.QMF_MOUSEONLY, C.QMF_INACTIVE)

	while true do
		while m.cursor >= 0 and m.cursor < m.nitems do
			local item = m.items[m.cursor]
			if band(item.generic.flags, skip) ~= 0 then
				m.cursor += dir
			else
				break
			end
		end

		if dir == 1 then
			if m.cursor >= m.nitems then
				if m.wrapAround then
					if wrapped then
						m.cursor = m.cursor_prev
						return
					end
					m.cursor = 0
					wrapped = true
					continue
				end
				m.cursor = m.cursor_prev
			end
		else
			if m.cursor < 0 then
				if m.wrapAround then
					if wrapped then
						m.cursor = m.cursor_prev
						return
					end
					m.cursor = m.nitems - 1
					wrapped = true
					continue
				end
				m.cursor = m.cursor_prev
			end
		end
		return
	end
end

function U.Menu_Draw(menu)
	-- draw menu
	for i = 0, menu.nitems - 1 do
		local itemptr = menu.items[i]
		local g = itemptr.generic

		if band(g.flags, C.QMF_HIDDEN) == 0 then
			if g.ownerdraw ~= nil then
				-- total subclassing, owner draws everything
				g.ownerdraw(itemptr)
			else
				local t = g.type
				if t == C.MTYPE_RADIOBUTTON then
					U.RadioButton_Draw(itemptr)
				elseif t == C.MTYPE_FIELD then
					U.MenuField_Draw(itemptr)
				elseif t == C.MTYPE_SLIDER then
					U.Slider_Draw(itemptr)
				elseif t == C.MTYPE_SPINCONTROL then
					U.SpinControl_Draw(itemptr)
				elseif t == C.MTYPE_ACTION then
					U.Action_Draw(itemptr)
				elseif t == C.MTYPE_BITMAP then
					U.Bitmap_Draw(itemptr)
				elseif t == C.MTYPE_TEXT then
					U.Text_Draw(itemptr)
				elseif t == C.MTYPE_SCROLLLIST then
					U.ScrollList_Draw(itemptr)
				elseif t == C.MTYPE_PTEXT then
					U.PText_Draw(itemptr)
				elseif t == C.MTYPE_BTEXT then
					U.BText_Draw(itemptr)
				else
					trap.Error(Q.va("Menu_Draw: unknown type %d", t))
				end
			end
			local dbg = U.uis.debug
			if dbg == true or (type(dbg) == "number" and dbg ~= 0) then
				if band(g.flags, C.QMF_INACTIVE) == 0 then
					local x = g.left
					local y = g.top
					local w = g.right - g.left + 1
					local h = g.bottom - g.top + 1

					if band(g.flags, C.QMF_HASMOUSEFOCUS) ~= 0 then
						U.UI_DrawRect(x, y, w, h, Q.colorYellow)
					else
						U.UI_DrawRect(x, y, w, h, Q.colorWhite)
					end
				end
			end
		end
	end

	local itemptr = U.Menu_ItemAtCursor(menu)
	if itemptr ~= nil and itemptr.generic.statusbar ~= nil then
		itemptr.generic.statusbar(itemptr)
	end
end

function U.Menu_ItemAtCursor(m)
	if m.cursor < 0 or m.cursor >= m.nitems then
		return nil
	end

	return m.items[m.cursor]
end

function U.Menu_ActivateItem(s, item)
	local g = item.generic
	if g.callback ~= nil then
		g.callback(item, C.QM_ACTIVATED)
		if band(g.flags, C.QMF_SILENT) == 0 then
			return U.menu_move_sound
		end
	end

	return 0
end

function U.Menu_DefaultKey(m, key)
	local sound = 0

	-- menu system keys
	if key == C.K_MOUSE2 or key == C.K_ESCAPE then
		U.UI_PopMenu()
		return U.menu_out_sound
	end

	if m == nil or m.nitems == 0 then
		return 0
	end

	-- route key stimulus to widget
	local item = U.Menu_ItemAtCursor(m)
	if item ~= nil and band(item.generic.flags, bor(C.QMF_GRAYED, C.QMF_INACTIVE)) == 0 then
		local t = item.generic.type
		if t == C.MTYPE_SPINCONTROL then
			sound = U.SpinControl_Key(item, key)
		elseif t == C.MTYPE_RADIOBUTTON then
			sound = U.RadioButton_Key(item, key)
		elseif t == C.MTYPE_SLIDER then
			sound = U.Slider_Key(item, key)
		elseif t == C.MTYPE_SCROLLLIST then
			sound = U.ScrollList_Key(item, key)
		elseif t == C.MTYPE_FIELD then
			local s, k = U.MenuField_Key(item, key)
			sound = s
			if k ~= nil then
				key = k
			end
		end

		if sound ~= 0 then
			-- key was handled
			return sound
		end
	end

	-- default handling
	if key == C.K_F11 then
		local dbg = U.uis.debug
		if type(dbg) == "boolean" then
			U.uis.debug = not dbg
		else
			U.uis.debug = bit32.bxor(dbg, 1)
		end
	elseif key == C.K_F12 then
		trap.Cmd_ExecuteText(C.EXEC_APPEND, "screenshot\n")
	elseif key == C.K_UPARROW then
		local cursor_prev = m.cursor
		m.cursor_prev = m.cursor
		m.cursor -= 1
		U.Menu_AdjustCursor(m, -1)
		if cursor_prev ~= m.cursor then
			U.Menu_CursorMoved(m)
			sound = U.menu_move_sound
		end
	elseif key == C.K_TAB or key == C.K_DOWNARROW then
		local cursor_prev = m.cursor
		m.cursor_prev = m.cursor
		m.cursor += 1
		U.Menu_AdjustCursor(m, 1)
		if cursor_prev ~= m.cursor then
			U.Menu_CursorMoved(m)
			sound = U.menu_move_sound
		end
	elseif key == C.K_MOUSE1 or key == C.K_MOUSE3 then
		if item ~= nil then
			local f = item.generic.flags
			if band(f, C.QMF_HASMOUSEFOCUS) ~= 0 and band(f, bor(C.QMF_GRAYED, C.QMF_INACTIVE)) == 0 then
				return U.Menu_ActivateItem(m, item)
			end
		end
	elseif
		key == C.K_JOY1
		or key == C.K_JOY2
		or key == C.K_JOY3
		or key == C.K_JOY4
		or (key >= C.K_AUX1 and key <= C.K_AUX16)
		or key == C.K_KP_ENTER
		or key == C.K_ENTER
	then
		if item ~= nil then
			if band(item.generic.flags, bor(C.QMF_MOUSEONLY, C.QMF_GRAYED, C.QMF_INACTIVE)) == 0 then
				return U.Menu_ActivateItem(m, item)
			end
		end
	end

	return sound
end

function U.Menu_Cache()
	local uis = U.uis
	uis.charset = trap.R_RegisterShaderNoMip("gfx/2d/bigchars")
	uis.charsetProp = trap.R_RegisterShaderNoMip("menu/art/font1_prop.tga")
	uis.charsetPropGlow = trap.R_RegisterShaderNoMip("menu/art/font1_prop_glo.tga")
	uis.charsetPropB = trap.R_RegisterShaderNoMip("menu/art/font2_prop.tga")
	uis.cursor = trap.R_RegisterShaderNoMip("menu/art/3_cursor2")
	uis.rb_on = trap.R_RegisterShaderNoMip("menu/art/switch_on")
	uis.rb_off = trap.R_RegisterShaderNoMip("menu/art/switch_off")

	uis.whiteShader = trap.R_RegisterShaderNoMip("white")
	if uis.glconfig.hardwareType == C.GLHW_RAGEPRO then
		-- the blend effect turns to shit with the normal
		uis.menuBackShader = trap.R_RegisterShaderNoMip("menubackRagePro")
	else
		uis.menuBackShader = trap.R_RegisterShaderNoMip("menuback_blueish")
	end
	uis.menuBackNoLogoShader = trap.R_RegisterShaderNoMip("menubacknologo_blueish")

	U.menu_in_sound = trap.S_RegisterSound("sound/misc/menu1.wav", false)
	U.menu_move_sound = trap.S_RegisterSound("sound/misc/menu2.wav", false)
	U.menu_out_sound = trap.S_RegisterSound("sound/misc/menu3.wav", false)
	U.menu_buzz_sound = trap.S_RegisterSound("sound/misc/menu4.wav", false)
	U.weaponChangeSound = trap.S_RegisterSound("sound/weapons/change.wav", false)

	-- need a nonzero sound, make an empty sound for this
	U.menu_null_sound = -1

	U.sliderBar = trap.R_RegisterShaderNoMip("menu/art/slider2")
	U.sliderButton_0 = trap.R_RegisterShaderNoMip("menu/art/sliderbutt_0")
	U.sliderButton_1 = trap.R_RegisterShaderNoMip("menu/art/sliderbutt_1")
end

return U
