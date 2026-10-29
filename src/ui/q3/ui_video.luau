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
-- Luau port of code/q3_ui/ui_video.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local function newGeneric()
	return { type = 0, id = 0, flags = 0, x = 0, y = 0, left = 0, top = 0, right = 0, bottom = 0 }
end

local function newText()
	return { generic = newGeneric(), string = "", style = 0, color = nil }
end

local function newBitmap()
	return { generic = newGeneric(), width = 0, height = 0, focuspic = nil }
end

local function newList()
	return { generic = newGeneric(), oldvalue = 0, curvalue = 0, numitems = 0, itemnames = nil }
end

local function newSlider()
	return { generic = newGeneric(), minvalue = 0, maxvalue = 0, curvalue = 0 }
end

local function newFramework()
	return { cursor = 0, cursor_prev = 0, nitems = 0, items = {}, wrapAround = false, fullscreen = false, showlogo = false }
end

local MAX_RESOLUTIONS = 32

--[[ DRIVER INFORMATION MENU ]]

local DRIVERINFO_FRAMEL = "menu/art_blueish/frame2_l"
local DRIVERINFO_FRAMER = "menu/art_blueish/frame1_r"
local DRIVERINFO_BACK0 = "menu/art_blueish/back_0"
local DRIVERINFO_BACK1 = "menu/art_blueish/back_1"

local driverinfo_artlist = {
	[0] = DRIVERINFO_FRAMEL,
	DRIVERINFO_FRAMER,
	DRIVERINFO_BACK0,
	DRIVERINFO_BACK1,
}

local ID_DRIVERINFOBACK = 100

local s_driverinfo = {}

local function DriverInfo_Event(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	if ptr.generic.id == ID_DRIVERINFOBACK then
		U.UI_PopMenu()
	end
end

local function DriverInfo_MenuDraw()
	U.Menu_Draw(s_driverinfo.menu)

	U.UI_DrawString(320, 80, "VENDOR", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_red)
	U.UI_DrawString(320, 152, "PIXELFORMAT", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_red)
	U.UI_DrawString(320, 192, "EXTENSIONS", bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.color_red)

	local gl = U.uis.glconfig
	U.UI_DrawString(320, 80 + 16, gl.vendor_string, bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.text_color_normal)
	U.UI_DrawString(320, 96 + 16, gl.version_string, bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.text_color_normal)
	U.UI_DrawString(320, 112 + 16, gl.renderer_string, bit32.bor(C.UI_CENTER, C.UI_SMALLFONT), U.text_color_normal)
	U.UI_DrawString(
		320,
		152 + 16,
		Q.va("color(%d-bits) Z(%d-bits) stencil(%d-bits)", gl.colorBits, gl.depthBits, gl.stencilBits),
		bit32.bor(C.UI_CENTER, C.UI_SMALLFONT),
		U.text_color_normal
	)

	-- double column
	local y = 192 + 16
	for i = 0, Q.idiv(s_driverinfo.numstrings, 2) - 1 do
		U.UI_DrawString(320 - 4, y, s_driverinfo.strings[i * 2], bit32.bor(C.UI_RIGHT, C.UI_SMALLFONT), U.text_color_normal)
		U.UI_DrawString(320 + 4, y, s_driverinfo.strings[i * 2 + 1], bit32.bor(C.UI_LEFT, C.UI_SMALLFONT), U.text_color_normal)
		y += C.SMALLCHAR_HEIGHT
	end

	if bit32.band(s_driverinfo.numstrings, 1) ~= 0 then
		U.UI_DrawString(
			320,
			y,
			s_driverinfo.strings[s_driverinfo.numstrings - 1],
			bit32.bor(C.UI_CENTER, C.UI_SMALLFONT),
			U.text_color_normal
		)
	end
end

function U.DriverInfo_Cache()
	-- touch all our pics
	local i = 0
	while driverinfo_artlist[i] ~= nil do
		trap.R_RegisterShaderNoMip(driverinfo_artlist[i])
		i += 1
	end
end

local function UI_DriverInfo_Menu()
	s_driverinfo = {
		menu = newFramework(),
		banner = newText(),
		back = newBitmap(),
		framel = newBitmap(),
		framer = newBitmap(),
		strings = {},
		numstrings = 0,
	}
	local d = s_driverinfo

	U.DriverInfo_Cache()

	d.menu.fullscreen = true
	d.menu.draw = DriverInfo_MenuDraw

	d.banner.generic.type = C.MTYPE_BTEXT
	d.banner.generic.x = 320
	d.banner.generic.y = 16
	d.banner.string = "DRIVER INFO"
	d.banner.color = U.color_white
	d.banner.style = C.UI_CENTER

	d.framel.generic.type = C.MTYPE_BITMAP
	d.framel.generic.name = DRIVERINFO_FRAMEL
	d.framel.generic.flags = C.QMF_INACTIVE
	d.framel.generic.x = 0
	d.framel.generic.y = 78
	d.framel.width = 256
	d.framel.height = 329

	d.framer.generic.type = C.MTYPE_BITMAP
	d.framer.generic.name = DRIVERINFO_FRAMER
	d.framer.generic.flags = C.QMF_INACTIVE
	d.framer.generic.x = 376
	d.framer.generic.y = 76
	d.framer.width = 256
	d.framer.height = 334

	d.back.generic.type = C.MTYPE_BITMAP
	d.back.generic.name = DRIVERINFO_BACK0
	d.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	d.back.generic.callback = DriverInfo_Event
	d.back.generic.id = ID_DRIVERINFOBACK
	d.back.generic.x = 0
	d.back.generic.y = 480 - 64
	d.back.width = 128
	d.back.height = 64
	d.back.focuspic = DRIVERINFO_BACK1

	-- overflow with particularly long GL extensions
	local ext = string.sub(U.uis.glconfig.extensions_string, 1, 1023)

	-- build extension strings
	for word in string.gmatch(ext, "[^ ]+") do
		if d.numstrings >= 40 then
			break
		end
		d.strings[d.numstrings] = word
		d.numstrings += 1
	end

	-- safety length strings for display
	for i = 0, d.numstrings - 1 do
		local s = d.strings[i]
		local len = #s
		if len > 32 then
			d.strings[i] = string.sub(s, 1, len - 1) .. ">"
		end
	end

	U.Menu_AddItem(d.menu, d.banner)
	U.Menu_AddItem(d.menu, d.framel)
	U.Menu_AddItem(d.menu, d.framer)
	U.Menu_AddItem(d.menu, d.back)

	U.UI_PushMenu(d.menu)
end

--[[ GRAPHICS OPTIONS MENU ]]

local GRAPHICSOPTIONS_FRAMEL = "menu/art_blueish/frame2_l"
local GRAPHICSOPTIONS_FRAMER = "menu/art_blueish/frame1_r"
local GRAPHICSOPTIONS_BACK0 = "menu/art_blueish/back_0"
local GRAPHICSOPTIONS_BACK1 = "menu/art_blueish/back_1"
local GRAPHICSOPTIONS_ACCEPT0 = "menu/art_blueish/accept_0"
local GRAPHICSOPTIONS_ACCEPT1 = "menu/art_blueish/accept_1"

local ID_BACK2 = 101
local ID_FULLSCREEN = 102
local ID_LIST = 103
local ID_MODE = 104
local ID_DRIVERINFO = 105
local ID_GRAPHICS = 106
local ID_DISPLAY = 107
local ID_SOUND = 108
local ID_NETWORK = 109
local ID_RATIO = 110

local function newGraphicsOptions()
	return {
		menu = newFramework(),
		banner = newText(),
		framel = newBitmap(),
		framer = newBitmap(),
		graphics = newText(),
		display = newText(),
		sound = newText(),
		network = newText(),
		list = newList(),
		ratio = newList(),
		mode = newList(),
		driver = newList(),
		tq = newSlider(),
		fs = newList(),
		lighting = newList(),
		flares = newList(),
		bloom = newList(),
		allow_extensions = newList(),
		texturebits = newList(),
		geometry = newList(),
		filter = newList(),
		aniso = newList(),
		driverinfo = newText(),
		apply = newBitmap(),
		back = newBitmap(),
	}
end

local s_ivo = {
	mode = 0,
	fullscreen = 0,
	tq = 0,
	lighting = 0,
	flares = 0,
	bloom = 0,
	texturebits = 0,
	geometry = 0,
	filter = 0,
	aniso = 0,
	driver = 0,
	extensions = 0,
}
local s_graphicsoptions = newGraphicsOptions()

local function ivo(mode, fullscreen, tq, lighting, flares, bloom, texturebits, geometry, filter, aniso, driver, extensions)
	return {
		mode = mode,
		fullscreen = fullscreen,
		tq = tq,
		lighting = lighting,
		flares = flares,
		bloom = bloom,
		texturebits = texturebits,
		geometry = geometry,
		filter = filter,
		aniso = aniso,
		driver = driver,
		extensions = extensions,
	}
end

local s_ivo_templates = {
	[0] = ivo(6, 1, 3, 0, 0, 0, 2, 2, 1, 0, 0, 1),
	ivo(4, 1, 2, 0, 0, 0, 2, 1, 1, 0, 0, 1),
	ivo(3, 1, 2, 0, 0, 0, 0, 1, 0, 0, 0, 1),
	ivo(2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1),
	ivo(2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1),
	ivo(3, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1),
}

local NUM_IVO_TEMPLATES = 6

local builtinResolutions = {
	[0] = "320x240",
	"400x300",
	"512x384",
	"640x480",
	"800x600",
	"960x720",
	"1024x768",
	"1152x864",
	"1280x1024",
	"1600x1200",
	"2048x1536",
	"856x480",
}

local knownRatios = {
	[0] = { [0] = "1.25:1", "5:4" },
	{ [0] = "1.33:1", "4:3" },
	{ [0] = "1.50:1", "3:2" },
	{ [0] = "1.56:1", "14:9" },
	{ [0] = "1.60:1", "16:10" },
	{ [0] = "1.67:1", "5:3" },
	{ [0] = "1.78:1", "16:9" },
}

local ratios = {}
local ratioBuf = {}
local ratioToRes = {}
local resToRatio = {}
for i = 0, MAX_RESOLUTIONS - 1 do
	ratioBuf[i] = ""
	ratioToRes[i] = 0
	resToRatio[i] = 0
end

local detectedResolutions = {}

local resolutions = builtinResolutions
local resolutionsDetected = false

local function atoi(s)
	local n = string.match(s, "^%s*([+-]?%d+)")
	return n and tonumber(n) or 0
end

local function b2n(b)
	if b then
		return 1
	end
	return 0
end

local function GraphicsOptions_FindBuiltinResolution(mode)
	if not resolutionsDetected then
		return mode
	end

	if mode < 0 then
		return -1
	end

	local i = 0
	while builtinResolutions[i] ~= nil do
		if Q.stricmp(builtinResolutions[i], detectedResolutions[mode]) == 0 then
			return i
		end
		i += 1
	end

	return -1
end

local function GraphicsOptions_FindDetectedResolution(mode)
	if not resolutionsDetected then
		return mode
	end

	if mode < 0 then
		return -1
	end

	local i = 0
	while detectedResolutions[i] ~= nil do
		if Q.stricmp(builtinResolutions[mode], detectedResolutions[i]) == 0 then
			return i
		end
		i += 1
	end

	return -1
end

local function GraphicsOptions_GetAspectRatios()
	-- build ratio list from resolutions
	local r = 0
	while resolutions[r] ~= nil do
		local res = resolutions[r]
		local xpos = string.find(res, "x", 1, true)
		local w = atoi(string.sub(res, 1, xpos - 1))
		local h = atoi(string.sub(res, xpos + 1))
		local str = string.format("%.2f:1", w / h)

		-- rename common ratios ("1.33:1" -> "4:3")
		local i = 0
		while knownRatios[i] ~= nil do
			if Q.stricmp(str, knownRatios[i][0]) == 0 then
				str = knownRatios[i][1]
				break
			end
			i += 1
		end

		-- add ratio to list if it is new
		-- establish res/ratio relationship
		i = 0
		while ratioBuf[i] ~= nil and ratioBuf[i] ~= "" do
			if Q.stricmp(str, ratioBuf[i]) == 0 then
				break
			end
			i += 1
		end
		if ratioBuf[i] == nil or ratioBuf[i] == "" then
			ratioBuf[i] = string.sub(str, 1, 7)
			ratioToRes[i] = r
		end
		ratios[r] = ratioBuf[r]
		resToRatio[r] = i
		r += 1
	end
	ratios[r] = nil
end

local function GraphicsOptions_GetInitialVideo()
	local g = s_graphicsoptions
	s_ivo.driver = g.driver.curvalue
	s_ivo.mode = g.mode.curvalue
	s_ivo.fullscreen = g.fs.curvalue
	s_ivo.extensions = g.allow_extensions.curvalue
	s_ivo.tq = g.tq.curvalue
	s_ivo.lighting = g.lighting.curvalue
	s_ivo.flares = g.flares.curvalue
	s_ivo.bloom = g.bloom.curvalue
	s_ivo.geometry = g.geometry.curvalue
	s_ivo.filter = g.filter.curvalue
	s_ivo.aniso = g.aniso.curvalue
	s_ivo.texturebits = g.texturebits.curvalue
end

local function GraphicsOptions_GetResolutions()
	local resbuf = U.UI_Cvar_VariableString("r_availableModes")
	if resbuf ~= "" then
		local pos = 1
		local i = 0
		while pos ~= nil and i < MAX_RESOLUTIONS - 1 do
			local sp = string.find(resbuf, " ", pos, true)
			if sp then
				detectedResolutions[i] = string.sub(resbuf, pos, sp - 1)
				pos = sp + 1
			else
				detectedResolutions[i] = string.sub(resbuf, pos)
				pos = nil
			end
			i += 1
		end
		detectedResolutions[i] = nil

		if i > 0 then
			resolutions = detectedResolutions
			resolutionsDetected = true
		end
	end
end

local function GraphicsOptions_CheckConfig()
	local g = s_graphicsoptions
	for i = 0, NUM_IVO_TEMPLATES - 2 do
		local t = s_ivo_templates[i]
		if
			t.driver == g.driver.curvalue
			and GraphicsOptions_FindDetectedResolution(t.mode) == g.mode.curvalue
			and t.fullscreen == g.fs.curvalue
			and t.tq == g.tq.curvalue
			and t.lighting == g.lighting.curvalue
			and t.flares == g.flares.curvalue
			and t.bloom == g.bloom.curvalue
			and t.geometry == g.geometry.curvalue
			and t.filter == g.filter.curvalue
			and t.aniso == g.aniso.curvalue
		then
			g.list.curvalue = i
			return
		end
	end

	-- return 'Custom' ivo template
	g.list.curvalue = NUM_IVO_TEMPLATES - 1
end

local function GraphicsOptions_UpdateMenuItems()
	local g = s_graphicsoptions
	local hide = bit32.bor(C.QMF_HIDDEN, C.QMF_INACTIVE)

	if g.driver.curvalue == 1 then
		g.fs.curvalue = 1
		g.fs.generic.flags = bit32.bor(g.fs.generic.flags, C.QMF_GRAYED)
	else
		g.fs.generic.flags = bit32.band(g.fs.generic.flags, bit32.bnot(C.QMF_GRAYED))
	end

	if g.allow_extensions.curvalue == 0 then
		if g.texturebits.curvalue == 0 then
			g.texturebits.curvalue = 1
		end
	end

	g.apply.generic.flags = bit32.bor(g.apply.generic.flags, hide)

	if
		s_ivo.mode ~= g.mode.curvalue
		or s_ivo.fullscreen ~= g.fs.curvalue
		or s_ivo.extensions ~= g.allow_extensions.curvalue
		or s_ivo.tq ~= g.tq.curvalue
		or s_ivo.lighting ~= g.lighting.curvalue
		or s_ivo.flares ~= g.flares.curvalue
		or s_ivo.bloom ~= g.bloom.curvalue
		or s_ivo.driver ~= g.driver.curvalue
		or s_ivo.texturebits ~= g.texturebits.curvalue
		or s_ivo.geometry ~= g.geometry.curvalue
		or s_ivo.filter ~= g.filter.curvalue
		or s_ivo.aniso ~= g.aniso.curvalue
	then
		g.apply.generic.flags = bit32.band(g.apply.generic.flags, bit32.bnot(hide))
	end

	GraphicsOptions_CheckConfig()
end

local function GraphicsOptions_ApplyChanges(unused, notification)
	if notification ~= C.QM_ACTIVATED then
		return
	end
	local g = s_graphicsoptions

	local tb = g.texturebits.curvalue
	if tb == 0 then
		trap.Cvar_SetValue("r_texturebits", 0)
	elseif tb == 1 then
		trap.Cvar_SetValue("r_texturebits", 16)
	elseif tb == 2 then
		trap.Cvar_SetValue("r_texturebits", 32)
	end
	trap.Cvar_SetValue("r_picmip", 3 - g.tq.curvalue)
	trap.Cvar_SetValue("r_allowExtensions", g.allow_extensions.curvalue)

	if resolutionsDetected then
		-- search for builtin mode that matches the detected mode
		if g.mode.curvalue == -1 or g.mode.curvalue >= MAX_RESOLUTIONS then
			g.mode.curvalue = 0
		end
		local mode = GraphicsOptions_FindBuiltinResolution(g.mode.curvalue)
		if mode == -1 then
			local res = detectedResolutions[g.mode.curvalue]
			local xpos = string.find(res, "x", 1, true)
			local w = string.sub(string.sub(res, 1, xpos - 1), 1, 15)
			local h = string.sub(string.sub(res, xpos + 1), 1, 15)
			trap.Cvar_Set("r_customwidth", w)
			trap.Cvar_Set("r_customheight", h)
		end

		trap.Cvar_SetValue("r_mode", mode)
	else
		trap.Cvar_SetValue("r_mode", g.mode.curvalue)
	end

	trap.Cvar_SetValue("r_fullscreen", g.fs.curvalue)
	trap.Cvar_SetValue("r_colorbits", 0)
	trap.Cvar_SetValue("r_depthbits", 0)
	trap.Cvar_SetValue("r_stencilbits", 0)
	trap.Cvar_SetValue("r_vertexLight", g.lighting.curvalue)
	trap.Cvar_SetValue("cg_autovertex", g.lighting.curvalue)
	trap.Cvar_SetValue("r_flares", g.flares.curvalue)
	trap.Cvar_SetValue("r_bloom", g.bloom.curvalue)

	--r_ext_texture_filter_anisotropic is special
	if g.aniso.curvalue ~= 0 then
		trap.Cvar_SetValue("r_ext_max_anisotropy", g.aniso.curvalue * 2)
		trap.Cvar_SetValue("r_ext_texture_filter_anisotropic", 1)
	else
		trap.Cvar_SetValue("r_ext_texture_filter_anisotropic", 0)
	end

	trap.Cvar_SetValue("com_hunkmegs", 128)

	if g.geometry.curvalue == 2 then
		trap.Cvar_SetValue("r_lodBias", 0)
		trap.Cvar_SetValue("r_subdivisions", 4)
	elseif g.geometry.curvalue == 1 then
		trap.Cvar_SetValue("r_lodBias", 1)
		trap.Cvar_SetValue("r_subdivisions", 12)
	else
		trap.Cvar_SetValue("r_lodBias", 1)
		trap.Cvar_SetValue("r_subdivisions", 20)
	end

	if g.filter.curvalue ~= 0 then
		trap.Cvar_Set("r_textureMode", "GL_LINEAR_MIPMAP_LINEAR")
	else
		trap.Cvar_Set("r_textureMode", "GL_LINEAR_MIPMAP_NEAREST")
	end

	trap.Cmd_ExecuteText(C.EXEC_APPEND, "vid_restart\n")
end

local function applyModeConstraints()
	local g = s_graphicsoptions
	-- clamp 3dfx video modes
	if g.driver.curvalue == 1 then
		if g.mode.curvalue < 2 then
			g.mode.curvalue = 2
		elseif g.mode.curvalue > 6 then
			g.mode.curvalue = 6
		end
	end
	g.ratio.curvalue = resToRatio[g.mode.curvalue]
end

local function GraphicsOptions_Event(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	local g = s_graphicsoptions
	local id = ptr.generic.id

	if id == ID_RATIO then
		g.mode.curvalue = ratioToRes[g.ratio.curvalue]
		applyModeConstraints()
	elseif id == ID_MODE then
		applyModeConstraints()
	elseif id == ID_LIST then
		local t = s_ivo_templates[g.list.curvalue]

		g.mode.curvalue = GraphicsOptions_FindDetectedResolution(t.mode)
		g.ratio.curvalue = resToRatio[g.mode.curvalue]
		g.tq.curvalue = t.tq
		g.lighting.curvalue = t.lighting
		g.texturebits.curvalue = t.texturebits
		g.geometry.curvalue = t.geometry
		g.filter.curvalue = t.filter
		g.aniso.curvalue = t.aniso
		g.fs.curvalue = t.fullscreen
		g.flares.curvalue = t.flares
		g.bloom.curvalue = t.bloom
	elseif id == ID_DRIVERINFO then
		UI_DriverInfo_Menu()
	elseif id == ID_BACK2 then
		U.UI_PopMenu()
	elseif id == ID_GRAPHICS then
		return
	elseif id == ID_DISPLAY then
		U.UI_PopMenu()
		U.UI_DisplayOptionsMenu()
	elseif id == ID_SOUND then
		U.UI_PopMenu()
		U.UI_SoundOptionsMenu()
	elseif id == ID_NETWORK then
		U.UI_PopMenu()
		U.UI_NetworkOptionsMenu()
	end
end

local function GraphicsOptions_TQEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end
	s_graphicsoptions.tq.curvalue = Q.int(s_graphicsoptions.tq.curvalue + 0.5)
end

function U.GraphicsOptions_MenuDraw()
	GraphicsOptions_UpdateMenuItems()

	U.Menu_Draw(s_graphicsoptions.menu)
end

local function GraphicsOptions_SetMenuItems()
	local g = s_graphicsoptions
	g.mode.curvalue = GraphicsOptions_FindDetectedResolution(Q.int(trap.Cvar_VariableValue("r_mode")))

	if g.mode.curvalue < 0 then
		if resolutionsDetected then
			local buf = trap.Cvar_VariableStringBuffer("r_customwidth")
				.. "x"
				.. trap.Cvar_VariableStringBuffer("r_customheight")

			local i = 0
			while detectedResolutions[i] ~= nil do
				if Q.stricmp(buf, detectedResolutions[i]) == 0 then
					g.mode.curvalue = i
					break
				end
				i += 1
			end
			if g.mode.curvalue < 0 then
				g.mode.curvalue = 0
			end
		else
			g.mode.curvalue = 3
		end
	end
	g.fs.curvalue = Q.int(trap.Cvar_VariableValue("r_fullscreen"))
	g.allow_extensions.curvalue = Q.int(trap.Cvar_VariableValue("r_allowExtensions"))
	g.flares.curvalue = Q.int(trap.Cvar_VariableValue("r_flares"))
	g.bloom.curvalue = Q.int(trap.Cvar_VariableValue("r_bloom"))
	if trap.Cvar_VariableValue("r_ext_texture_filter_anisotropic") ~= 0 then
		g.aniso.curvalue = Q.int(trap.Cvar_VariableValue("r_ext_max_anisotropy") / 2)
	end
	g.tq.curvalue = 3 - trap.Cvar_VariableValue("r_picmip")
	if g.tq.curvalue < 0 then
		g.tq.curvalue = 0
	elseif g.tq.curvalue > 3 then
		g.tq.curvalue = 3
	end

	g.lighting.curvalue = b2n(trap.Cvar_VariableValue("r_vertexLight") ~= 0)
	local tbits = Q.int(trap.Cvar_VariableValue("r_texturebits"))
	if tbits == 16 then
		g.texturebits.curvalue = 1
	elseif tbits == 32 then
		g.texturebits.curvalue = 2
	else
		g.texturebits.curvalue = 0
	end

	if Q.stricmp(U.UI_Cvar_VariableString("r_textureMode"), "GL_LINEAR_MIPMAP_NEAREST") == 0 then
		g.filter.curvalue = 0
	else
		g.filter.curvalue = 1
	end

	if trap.Cvar_VariableValue("r_lodBias") > 0 then
		if trap.Cvar_VariableValue("r_subdivisions") >= 20 then
			g.geometry.curvalue = 0
		else
			g.geometry.curvalue = 1
		end
	else
		g.geometry.curvalue = 2
	end
end

function U.GraphicsOptions_Cache()
	trap.R_RegisterShaderNoMip(GRAPHICSOPTIONS_FRAMEL)
	trap.R_RegisterShaderNoMip(GRAPHICSOPTIONS_FRAMER)
	trap.R_RegisterShaderNoMip(GRAPHICSOPTIONS_BACK0)
	trap.R_RegisterShaderNoMip(GRAPHICSOPTIONS_BACK1)
	trap.R_RegisterShaderNoMip(GRAPHICSOPTIONS_ACCEPT0)
	trap.R_RegisterShaderNoMip(GRAPHICSOPTIONS_ACCEPT1)
end

local s_driver_names = { [0] = "Default", "Voodoo" }
local tq_names = { [0] = "Default", "16 bit", "32 bit" }
local s_graphics_options_names = {
	[0] = "Very High Quality",
	"High Quality",
	"Normal",
	"Fast",
	"Fastest",
	"Custom",
}
local lighting_names = { [0] = "Lightmap (Normal)", "Vertex (Low)" }
local filter_names = { [0] = "Bilinear", "Trilinear" }
local aniso_names = { [0] = "Off", "2x", "4x", "6x", "8x" }
local quality_names = { [0] = "Low", "Medium", "High" }
local enabled_names = { [0] = "Off", "On" }

function U.GraphicsOptions_MenuInit()
	-- zero set all our globals
	s_graphicsoptions = newGraphicsOptions()
	local g = s_graphicsoptions
	local SPIN_FLAGS = bit32.bor(C.QMF_PULSEIFFOCUS, C.QMF_SMALLFONT)
	local TAB_FLAGS = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)

	GraphicsOptions_GetResolutions()
	GraphicsOptions_GetAspectRatios()

	U.GraphicsOptions_Cache()

	g.menu.wrapAround = true
	g.menu.fullscreen = true
	g.menu.draw = U.GraphicsOptions_MenuDraw

	g.banner.generic.type = C.MTYPE_BTEXT
	g.banner.generic.x = 320
	g.banner.generic.y = 16
	g.banner.string = "SYSTEM SETUP"
	g.banner.color = U.color_white
	g.banner.style = C.UI_CENTER

	g.framel.generic.type = C.MTYPE_BITMAP
	g.framel.generic.name = GRAPHICSOPTIONS_FRAMEL
	g.framel.generic.flags = C.QMF_INACTIVE
	g.framel.generic.x = 0
	g.framel.generic.y = 78
	g.framel.width = 256
	g.framel.height = 329

	g.framer.generic.type = C.MTYPE_BITMAP
	g.framer.generic.name = GRAPHICSOPTIONS_FRAMER
	g.framer.generic.flags = C.QMF_INACTIVE
	g.framer.generic.x = 376
	g.framer.generic.y = 76
	g.framer.width = 256
	g.framer.height = 334

	g.graphics.generic.type = C.MTYPE_PTEXT
	g.graphics.generic.flags = C.QMF_RIGHT_JUSTIFY
	g.graphics.generic.id = ID_GRAPHICS
	g.graphics.generic.callback = GraphicsOptions_Event
	g.graphics.generic.x = 216
	g.graphics.generic.y = 240 - 2 * C.PROP_HEIGHT
	g.graphics.string = "GRAPHICS"
	g.graphics.style = C.UI_RIGHT
	g.graphics.color = U.color_red

	g.display.generic.type = C.MTYPE_PTEXT
	g.display.generic.flags = TAB_FLAGS
	g.display.generic.id = ID_DISPLAY
	g.display.generic.callback = GraphicsOptions_Event
	g.display.generic.x = 216
	g.display.generic.y = 240 - C.PROP_HEIGHT
	g.display.string = "DISPLAY"
	g.display.style = C.UI_RIGHT
	g.display.color = U.color_red

	g.sound.generic.type = C.MTYPE_PTEXT
	g.sound.generic.flags = TAB_FLAGS
	g.sound.generic.id = ID_SOUND
	g.sound.generic.callback = GraphicsOptions_Event
	g.sound.generic.x = 216
	g.sound.generic.y = 240
	g.sound.string = "SOUND"
	g.sound.style = C.UI_RIGHT
	g.sound.color = U.color_red

	g.network.generic.type = C.MTYPE_PTEXT
	g.network.generic.flags = TAB_FLAGS
	g.network.generic.id = ID_NETWORK
	g.network.generic.callback = GraphicsOptions_Event
	g.network.generic.x = 216
	g.network.generic.y = 240 + C.PROP_HEIGHT
	g.network.string = "NETWORK"
	g.network.style = C.UI_RIGHT
	g.network.color = U.color_red

	local step = C.BIGCHAR_HEIGHT + 2
	local y = 240 - 7 * step
	g.list.generic.type = C.MTYPE_SPINCONTROL
	g.list.generic.name = "Graphics Settings:"
	g.list.generic.flags = SPIN_FLAGS
	g.list.generic.x = 400
	g.list.generic.y = y
	g.list.generic.callback = GraphicsOptions_Event
	g.list.generic.id = ID_LIST
	g.list.itemnames = s_graphics_options_names
	y += 2 * step

	g.driver.generic.type = C.MTYPE_SPINCONTROL
	g.driver.generic.name = "GL Driver:"
	g.driver.generic.flags = SPIN_FLAGS
	g.driver.generic.x = 400
	g.driver.generic.y = y
	g.driver.itemnames = s_driver_names
	g.driver.curvalue = b2n(U.uis.glconfig.driverType == C.GLDRV_VOODOO)
	y += step

	-- references/modifies "r_allowExtensions"
	g.allow_extensions.generic.type = C.MTYPE_SPINCONTROL
	g.allow_extensions.generic.name = "GL Extensions:"
	g.allow_extensions.generic.flags = SPIN_FLAGS
	g.allow_extensions.generic.x = 400
	g.allow_extensions.generic.y = y
	g.allow_extensions.itemnames = enabled_names
	y += step

	g.ratio.generic.type = C.MTYPE_SPINCONTROL
	g.ratio.generic.name = "Aspect Ratio:"
	g.ratio.generic.flags = SPIN_FLAGS
	g.ratio.generic.x = 400
	g.ratio.generic.y = y
	g.ratio.itemnames = ratios
	g.ratio.generic.callback = GraphicsOptions_Event
	g.ratio.generic.id = ID_RATIO
	y += step

	-- references/modifies "r_mode"
	g.mode.generic.type = C.MTYPE_SPINCONTROL
	g.mode.generic.name = "Resolution:"
	g.mode.generic.flags = SPIN_FLAGS
	g.mode.generic.x = 400
	g.mode.generic.y = y
	g.mode.itemnames = resolutions
	g.mode.generic.callback = GraphicsOptions_Event
	g.mode.generic.id = ID_MODE
	y += step

	-- references/modifies "r_fullscreen"
	g.fs.generic.type = C.MTYPE_SPINCONTROL
	g.fs.generic.name = "Fullscreen:"
	g.fs.generic.flags = SPIN_FLAGS
	g.fs.generic.x = 400
	g.fs.generic.y = y
	g.fs.itemnames = enabled_names
	y += step

	-- references/modifies "r_vertexLight"
	g.lighting.generic.type = C.MTYPE_SPINCONTROL
	g.lighting.generic.name = "Lighting:"
	g.lighting.generic.flags = SPIN_FLAGS
	g.lighting.generic.x = 400
	g.lighting.generic.y = y
	g.lighting.itemnames = lighting_names
	y += step

	-- references/modifies "r_flares"
	g.flares.generic.type = C.MTYPE_SPINCONTROL
	g.flares.generic.name = "Flares:"
	g.flares.generic.flags = SPIN_FLAGS
	g.flares.generic.x = 400
	g.flares.generic.y = y
	g.flares.itemnames = enabled_names
	y += step

	-- references/modifies "r_bloom"
	g.bloom.generic.type = C.MTYPE_SPINCONTROL
	g.bloom.generic.name = "Bloom:"
	g.bloom.generic.flags = SPIN_FLAGS
	g.bloom.generic.x = 400
	g.bloom.generic.y = y
	g.bloom.itemnames = enabled_names
	y += step

	-- references/modifies "r_lodBias" & "subdivisions"
	g.geometry.generic.type = C.MTYPE_SPINCONTROL
	g.geometry.generic.name = "Geometric Detail:"
	g.geometry.generic.flags = SPIN_FLAGS
	g.geometry.generic.x = 400
	g.geometry.generic.y = y
	g.geometry.itemnames = quality_names
	y += step

	-- references/modifies "r_picmip"
	g.tq.generic.type = C.MTYPE_SLIDER
	g.tq.generic.name = "Texture Detail:"
	g.tq.generic.flags = SPIN_FLAGS
	g.tq.generic.x = 400
	g.tq.generic.y = y
	g.tq.minvalue = 0
	g.tq.maxvalue = 3
	g.tq.generic.callback = GraphicsOptions_TQEvent
	y += step

	-- references/modifies "r_textureBits"
	g.texturebits.generic.type = C.MTYPE_SPINCONTROL
	g.texturebits.generic.name = "Texture Quality:"
	g.texturebits.generic.flags = SPIN_FLAGS
	g.texturebits.generic.x = 400
	g.texturebits.generic.y = y
	g.texturebits.itemnames = tq_names
	y += step

	-- references/modifies "r_textureMode"
	g.filter.generic.type = C.MTYPE_SPINCONTROL
	g.filter.generic.name = "Texture Filter:"
	g.filter.generic.flags = SPIN_FLAGS
	g.filter.generic.x = 400
	g.filter.generic.y = y
	g.filter.itemnames = filter_names
	y += 2 + C.BIGCHAR_HEIGHT

	g.aniso.generic.type = C.MTYPE_SPINCONTROL
	g.aniso.generic.name = "Anisotropy:"
	g.aniso.generic.flags = SPIN_FLAGS
	g.aniso.generic.x = 400
	g.aniso.generic.y = y
	g.aniso.itemnames = aniso_names
	y += 2 * C.BIGCHAR_HEIGHT

	g.driverinfo.generic.type = C.MTYPE_PTEXT
	g.driverinfo.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_PULSEIFFOCUS)
	g.driverinfo.generic.callback = GraphicsOptions_Event
	g.driverinfo.generic.id = ID_DRIVERINFO
	g.driverinfo.generic.x = 320
	g.driverinfo.generic.y = y
	g.driverinfo.string = "Driver Info"
	g.driverinfo.style = bit32.bor(C.UI_CENTER, C.UI_SMALLFONT)
	g.driverinfo.color = U.color_red
	y += step

	g.back.generic.type = C.MTYPE_BITMAP
	g.back.generic.name = GRAPHICSOPTIONS_BACK0
	g.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	g.back.generic.callback = GraphicsOptions_Event
	g.back.generic.id = ID_BACK2
	g.back.generic.x = 0
	g.back.generic.y = 480 - 64
	g.back.width = 128
	g.back.height = 64
	g.back.focuspic = GRAPHICSOPTIONS_BACK1

	g.apply.generic.type = C.MTYPE_BITMAP
	g.apply.generic.name = GRAPHICSOPTIONS_ACCEPT0
	g.apply.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS, C.QMF_HIDDEN, C.QMF_INACTIVE)
	g.apply.generic.callback = GraphicsOptions_ApplyChanges
	g.apply.generic.x = 640
	g.apply.generic.y = 480 - 64
	g.apply.width = 128
	g.apply.height = 64
	g.apply.focuspic = GRAPHICSOPTIONS_ACCEPT1

	U.Menu_AddItem(g.menu, g.banner)
	U.Menu_AddItem(g.menu, g.framel)
	U.Menu_AddItem(g.menu, g.framer)

	U.Menu_AddItem(g.menu, g.graphics)
	U.Menu_AddItem(g.menu, g.display)
	U.Menu_AddItem(g.menu, g.sound)
	U.Menu_AddItem(g.menu, g.network)

	U.Menu_AddItem(g.menu, g.list)
	U.Menu_AddItem(g.menu, g.driver)
	U.Menu_AddItem(g.menu, g.allow_extensions)
	U.Menu_AddItem(g.menu, g.ratio)
	U.Menu_AddItem(g.menu, g.mode)
	U.Menu_AddItem(g.menu, g.fs)
	U.Menu_AddItem(g.menu, g.lighting)
	U.Menu_AddItem(g.menu, g.flares)
	U.Menu_AddItem(g.menu, g.bloom)
	U.Menu_AddItem(g.menu, g.geometry)
	U.Menu_AddItem(g.menu, g.tq)
	U.Menu_AddItem(g.menu, g.texturebits)
	U.Menu_AddItem(g.menu, g.filter)
	U.Menu_AddItem(g.menu, g.aniso)
	U.Menu_AddItem(g.menu, g.driverinfo)

	U.Menu_AddItem(g.menu, g.back)
	U.Menu_AddItem(g.menu, g.apply)

	GraphicsOptions_SetMenuItems()
	GraphicsOptions_GetInitialVideo()

	if U.uis.glconfig.driverType == C.GLDRV_ICD and U.uis.glconfig.hardwareType == C.GLHW_3DFX_2D3D then
		g.driver.generic.flags = bit32.bor(g.driver.generic.flags, C.QMF_HIDDEN, C.QMF_INACTIVE)
	end
end

function U.UI_GraphicsOptionsMenu()
	U.GraphicsOptions_MenuInit()
	U.UI_PushMenu(s_graphicsoptions.menu)
	U.Menu_SetCursorToItem(s_graphicsoptions.menu, s_graphicsoptions.graphics)
end

return U
