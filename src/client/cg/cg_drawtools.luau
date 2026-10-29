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
-- Luau port of code/cgame/cg_drawtools.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local trap = require(script.Parent.Parent.sys.Trap)
local Screen = require(script.Parent.Parent.Parent.ui.Screen)

local COLOR_ESCAPE = 94

local function vec4(a: number, b: number, c: number, d: number): { [number]: number }
	return { [0] = a, [1] = b, [2] = c, [3] = d }
end

-- Q_IsColorString on the string s at 0-based offset i
local function isColorString(s: string, i: number): boolean
	if string.byte(s, i + 1) ~= COLOR_ESCAPE then
		return false
	end
	local n = string.byte(s, i + 2)
	return n ~= nil and n ~= COLOR_ESCAPE
end

function G.CG_AdjustFrom640(x, y, w, h)
	return Screen.cgAdjust(G.cgs, x, y, w, h)
end

function G.CG_FillRect(x, y, width, height, color)
	trap.R_SetColor(color)

	x, y, width, height = G.CG_AdjustFrom640(x, y, width, height)
	trap.R_DrawStretchPic(x, y, width, height, 0, 0, 0, 0, G.cgs.media.whiteShader)

	trap.R_SetColor(nil)
end

function G.CG_DrawSides(x, y, w, h, size)
	x, y, w, h = G.CG_AdjustFrom640(x, y, w, h)
	size *= G.cgs.screenXScale
	trap.R_DrawStretchPic(x, y, size, h, 0, 0, 0, 0, G.cgs.media.whiteShader)
	trap.R_DrawStretchPic(x + w - size, y, size, h, 0, 0, 0, 0, G.cgs.media.whiteShader)
end

function G.CG_DrawTopBottom(x, y, w, h, size)
	x, y, w, h = G.CG_AdjustFrom640(x, y, w, h)
	size *= G.cgs.screenYScale
	trap.R_DrawStretchPic(x, y, w, size, 0, 0, 0, 0, G.cgs.media.whiteShader)
	trap.R_DrawStretchPic(x, y + h - size, w, size, 0, 0, 0, 0, G.cgs.media.whiteShader)
end

function G.CG_DrawRect(x, y, width, height, size, color)
	trap.R_SetColor(color)

	G.CG_DrawTopBottom(x, y, width, height, size)
	G.CG_DrawSides(x, y, width, height, size)

	trap.R_SetColor(nil)
end

function G.CG_DrawPic(x, y, width, height, hShader)
	x, y, width, height = G.CG_AdjustFrom640(x, y, width, height)
	trap.R_DrawStretchPic(x, y, width, height, 0, 0, 1, 1, hShader)
end

function G.CG_DrawChar(x, y, width, height, ch)
	ch = bit32.band(ch, 255)

	if ch == 32 then
		return
	end

	local ax, ay, aw, ah = G.CG_AdjustFrom640(x, y, width, height)

	local row = bit32.rshift(ch, 4)
	local col = bit32.band(ch, 15)

	local frow = row * 0.0625
	local fcol = col * 0.0625
	local size = 0.0625

	trap.R_DrawStretchPic(ax, ay, aw, ah, fcol, frow, fcol + size, frow + size, G.cgs.media.charsetShader)
end

function G.CG_DrawStringExt(x, y, str, setColor, forceColor, shadow, charWidth, charHeight, maxChars)
	local color = vec4(0, 0, 0, 0)
	local len = #str

	if maxChars <= 0 then
		maxChars = 32767
	end

	if shadow then
		color[0] = 0
		color[1] = 0
		color[2] = 0
		color[3] = setColor[3]
		trap.R_SetColor(color)
		local i = 0
		local xx = x
		local cnt = 0
		while i < len and cnt < maxChars do
			if isColorString(str, i) then
				i += 2
				continue
			end
			G.CG_DrawChar(xx + 2, y + 2, charWidth, charHeight, string.byte(str, i + 1))
			cnt += 1
			xx += charWidth
			i += 1
		end
	end

	local i = 0
	local xx = x
	local cnt = 0
	trap.R_SetColor(setColor)
	while i < len and cnt < maxChars do
		if isColorString(str, i) then
			if not forceColor then
				local idx = bit32.band(string.byte(str, i + 2) - 48, 7)
				local src = Q.g_color_table[idx]
				color[0] = src[0]
				color[1] = src[1]
				color[2] = src[2]
				color[3] = setColor[3]
				trap.R_SetColor(color)
			end
			i += 2
			continue
		end
		G.CG_DrawChar(xx, y, charWidth, charHeight, string.byte(str, i + 1))
		xx += charWidth
		cnt += 1
		i += 1
	end
	trap.R_SetColor(nil)
end

function G.CG_DrawBigString(x, y, s, alpha)
	local color = vec4(1, 1, 1, alpha)
	G.CG_DrawStringExt(x, y, s, color, false, true, C.BIGCHAR_WIDTH, C.BIGCHAR_HEIGHT, 0)
end

function G.CG_DrawBigStringColor(x, y, s, color)
	G.CG_DrawStringExt(x, y, s, color, true, true, C.BIGCHAR_WIDTH, C.BIGCHAR_HEIGHT, 0)
end

function G.CG_DrawSmallString(x, y, s, alpha)
	local color = vec4(1, 1, 1, alpha)
	G.CG_DrawStringExt(x, y, s, color, false, false, C.SMALLCHAR_WIDTH, C.SMALLCHAR_HEIGHT, 0)
end

function G.CG_DrawSmallStringColor(x, y, s, color)
	G.CG_DrawStringExt(x, y, s, color, true, false, C.SMALLCHAR_WIDTH, C.SMALLCHAR_HEIGHT, 0)
end

-- Returns character count, skiping color escape codes
function G.CG_DrawStrlen(str)
	local len = #str
	local i = 0
	local count = 0

	while i < len do
		if isColorString(str, i) then
			i += 2
		else
			count += 1
			i += 1
		end
	end

	return count
end

local function CG_TileClearBox(x, y, w, h, hShader)
	local s1 = x / 64.0
	local t1 = y / 64.0
	local s2 = (x + w) / 64.0
	local t2 = (y + h) / 64.0
	trap.R_DrawStretchPic(x, y, w, h, s1, t1, s2, t2, hShader)
end

-- Clear around a sized down screen
function G.CG_TileClear()
	local w = G.cgs.glconfig.vidWidth
	local h = G.cgs.glconfig.vidHeight
	local refdef = G.cg.refdef

	if refdef.x == 0 and refdef.y == 0 and refdef.width == w and refdef.height == h then
		return
	end

	local top = refdef.y
	local bottom = top + refdef.height - 1
	local left = refdef.x
	local right = left + refdef.width - 1

	CG_TileClearBox(0, 0, w, top, G.cgs.media.backTileShader)
	CG_TileClearBox(0, bottom, w, h - bottom, G.cgs.media.backTileShader)
	CG_TileClearBox(0, top, left, bottom - top + 1, G.cgs.media.backTileShader)
	CG_TileClearBox(right, top, w - right, bottom - top + 1, G.cgs.media.backTileShader)
end

local fadeColor = vec4(0, 0, 0, 0)

function G.CG_FadeColor(startMsec, totalMsec)
	if startMsec == 0 then
		return nil
	end

	local t = G.cg.time - startMsec

	if t >= totalMsec then
		return nil
	end

	if totalMsec - t < C.FADE_TIME then
		fadeColor[3] = (totalMsec - t) * 1.0 / C.FADE_TIME
	else
		fadeColor[3] = 1.0
	end
	fadeColor[0] = 1
	fadeColor[1] = 1
	fadeColor[2] = 1

	return fadeColor
end

local teamRed = vec4(1, 0.2, 0.2, 1)
local teamBlue = vec4(0.2, 0.2, 1, 1)
local teamOther = vec4(1, 1, 1, 1)
local teamSpectator = vec4(0.7, 0.7, 0.7, 1)

function G.CG_TeamColor(team)
	if team == C.TEAM_RED then
		return teamRed
	elseif team == C.TEAM_BLUE then
		return teamBlue
	elseif team == C.TEAM_SPECTATOR then
		return teamSpectator
	end
	return teamOther
end

function G.CG_GetColorForHealth(health, armor, hcolor)
	-- calculate the total points of damage that can
	-- be sustained at the current health / armor level
	if health <= 0 then
		hcolor[0] = 0
		hcolor[1] = 0
		hcolor[2] = 0
		hcolor[3] = 1
		return
	end
	local count = armor
	local max = Q.int(health * C.ARMOR_PROTECTION / (1.0 - C.ARMOR_PROTECTION))
	if max < count then
		count = max
	end
	health += count

	-- set the color based on health
	hcolor[0] = 1.0
	hcolor[3] = 1.0
	if health >= 100 then
		hcolor[2] = 1.0
	elseif health < 66 then
		hcolor[2] = 0
	else
		hcolor[2] = (health - 66) / 33.0
	end

	if health > 60 then
		hcolor[1] = 1.0
	elseif health < 30 then
		hcolor[1] = 0
	else
		hcolor[1] = (health - 30) / 30.0
	end
end

function G.CG_ColorForHealth(hcolor)
	local stats = G.cg.snap.ps.stats
	G.CG_GetColorForHealth(stats[C.STAT_HEALTH], stats[C.STAT_ARMOR], hcolor)
end

-- code below duplicated in q3_ui/ui-atoms.c
local propMap: { [number]: { number } } = {}
for i = 0, 127 do
	propMap[i] = { 0, 0, -1 }
end

local propUpper = {
	{ 5, 4, 18 }, { 27, 4, 18 }, { 48, 4, 18 }, { 69, 4, 17 }, { 90, 4, 13 }, { 106, 4, 13 }, { 121, 4, 18 },
	{ 143, 4, 17 }, { 164, 4, 8 }, { 175, 4, 16 }, { 195, 4, 18 }, { 216, 4, 12 }, { 230, 4, 23 },
	{ 6, 34, 18 }, { 27, 34, 18 }, { 48, 34, 18 }, { 68, 34, 18 }, { 90, 34, 17 }, { 110, 34, 18 },
	{ 130, 34, 14 }, { 146, 34, 18 }, { 166, 34, 19 }, { 185, 34, 29 }, { 215, 34, 18 }, { 234, 34, 18 },
	{ 5, 64, 14 },
}

local propSymbols = {
	[32] = { 0, 0, C.PROP_SPACE_WIDTH },
	[33] = { 11, 122, 7 },
	[34] = { 154, 181, 14 },
	[35] = { 55, 122, 17 },
	[36] = { 79, 122, 18 },
	[37] = { 101, 122, 23 },
	[38] = { 153, 122, 18 },
	[39] = { 9, 93, 7 },
	[40] = { 207, 122, 8 },
	[41] = { 230, 122, 9 },
	[42] = { 177, 122, 18 },
	[43] = { 30, 152, 18 },
	[44] = { 85, 181, 7 },
	[45] = { 34, 93, 11 },
	[46] = { 110, 181, 6 },
	[47] = { 130, 152, 14 },
	[48] = { 22, 64, 17 },
	[49] = { 41, 64, 12 },
	[50] = { 58, 64, 17 },
	[51] = { 78, 64, 18 },
	[52] = { 98, 64, 19 },
	[53] = { 120, 64, 18 },
	[54] = { 141, 64, 18 },
	[55] = { 204, 64, 16 },
	[56] = { 162, 64, 17 },
	[57] = { 182, 64, 18 },
	[58] = { 59, 181, 7 },
	[59] = { 35, 181, 7 },
	[60] = { 203, 152, 14 },
	[61] = { 56, 93, 14 },
	[62] = { 228, 152, 14 },
	[63] = { 177, 181, 18 },
	[64] = { 28, 122, 22 },
	[91] = { 60, 152, 7 },
	[92] = { 106, 151, 13 },
	[93] = { 83, 152, 7 },
	[94] = { 128, 122, 17 },
	[95] = { 4, 152, 21 },
	[96] = { 134, 181, 5 },
	[123] = { 153, 152, 13 },
	[124] = { 11, 181, 5 },
	[125] = { 180, 152, 13 },
	[126] = { 79, 93, 17 },
}

for code, entry in propSymbols do
	propMap[code] = entry
end
for i = 0, 25 do
	propMap[65 + i] = propUpper[i + 1]
	propMap[97 + i] = propUpper[i + 1]
end

local propMapB = {
	[0] = { 11, 12, 33 }, { 49, 12, 31 }, { 85, 12, 31 }, { 120, 12, 30 }, { 156, 12, 21 }, { 183, 12, 21 },
	{ 207, 12, 32 },
	{ 13, 55, 30 }, { 49, 55, 13 }, { 66, 55, 29 }, { 101, 55, 31 }, { 135, 55, 21 }, { 158, 55, 40 },
	{ 204, 55, 32 },
	{ 12, 97, 31 }, { 48, 97, 31 }, { 82, 97, 30 }, { 118, 97, 30 }, { 153, 97, 30 }, { 185, 97, 25 },
	{ 213, 97, 30 },
	{ 11, 139, 32 }, { 42, 139, 51 }, { 93, 139, 32 }, { 126, 139, 31 }, { 158, 139, 25 },
}

local PROPB_GAP_WIDTH = 4
local PROPB_SPACE_WIDTH = 12
local PROPB_HEIGHT = 36

local function UI_DrawBannerString2(x, y, str, color)
	trap.R_SetColor(color)

	local media = G.cgs.media
	local ax = x * G.cgs.screenXScale + G.cgs.screenXBias
	local ay = y * G.cgs.screenYScale

	for i = 1, #str do
		local ch = bit32.band(string.byte(str, i), 127)
		if ch == 32 then
			ax += (PROPB_SPACE_WIDTH + PROPB_GAP_WIDTH) * G.cgs.screenXScale
		elseif ch >= 65 and ch <= 90 then
			ch -= 65
			local fcol = propMapB[ch][1] / 256.0
			local frow = propMapB[ch][2] / 256.0
			local fwidth = propMapB[ch][3] / 256.0
			local fheight = PROPB_HEIGHT / 256.0
			local aw = propMapB[ch][3] * G.cgs.screenXScale
			local ah = PROPB_HEIGHT * G.cgs.screenXScale
			trap.R_DrawStretchPic(ax, ay, aw, ah, fcol, frow, fcol + fwidth, frow + fheight, media.charsetPropB)
			ax += aw + PROPB_GAP_WIDTH * G.cgs.screenXScale
		end
	end

	trap.R_SetColor(nil)
end

function G.UI_DrawBannerString(x, y, str, style, color)
	-- find the width of the drawn text
	local width = 0
	for i = 1, #str do
		local ch = string.byte(str, i)
		if ch == 32 then
			width += PROPB_SPACE_WIDTH
		elseif ch >= 65 and ch <= 90 then
			width += propMapB[ch - 65][3] + PROPB_GAP_WIDTH
		end
	end
	width -= PROPB_GAP_WIDTH

	local fmt = bit32.band(style, C.UI_FORMATMASK)
	if fmt == C.UI_CENTER then
		x -= Q.idiv(width, 2)
	elseif fmt == C.UI_RIGHT then
		x -= width
	end

	if bit32.band(style, C.UI_DROPSHADOW) ~= 0 then
		local drawcolor = vec4(0, 0, 0, color[3])
		UI_DrawBannerString2(x + 2, y + 2, str, drawcolor)
	end

	UI_DrawBannerString2(x, y, str, color)
end

function G.UI_ProportionalStringWidth(str)
	local width = 0
	for i = 1, #str do
		local ch = bit32.band(string.byte(str, i), 127)
		local charWidth = propMap[ch][3]
		if charWidth ~= -1 then
			width += charWidth
			width += C.PROP_GAP_WIDTH
		end
	end

	width -= C.PROP_GAP_WIDTH
	return width
end

local function UI_DrawProportionalString2(x, y, str, color, sizeScale, charset)
	trap.R_SetColor(color)

	local ax = x * G.cgs.screenXScale + G.cgs.screenXBias
	local ay = y * G.cgs.screenXScale

	for i = 1, #str do
		local ch = bit32.band(string.byte(str, i), 127)
		local aw
		if ch == 32 then
			aw = C.PROP_SPACE_WIDTH * G.cgs.screenXScale * sizeScale
		elseif propMap[ch][3] ~= -1 then
			local fcol = propMap[ch][1] / 256.0
			local frow = propMap[ch][2] / 256.0
			local fwidth = propMap[ch][3] / 256.0
			local fheight = C.PROP_HEIGHT / 256.0
			aw = propMap[ch][3] * G.cgs.screenXScale * sizeScale
			local ah = C.PROP_HEIGHT * G.cgs.screenXScale * sizeScale
			trap.R_DrawStretchPic(ax, ay, aw, ah, fcol, frow, fcol + fwidth, frow + fheight, charset)
		else
			aw = 0
		end

		ax += aw + C.PROP_GAP_WIDTH * G.cgs.screenXScale * sizeScale
	end

	trap.R_SetColor(nil)
end

function G.UI_ProportionalSizeScale(style)
	if bit32.band(style, C.UI_SMALLFONT) ~= 0 then
		return 0.75
	end

	return 1.00
end

function G.UI_DrawProportionalString(x, y, str, style, color)
	local sizeScale = G.UI_ProportionalSizeScale(style)

	local fmt = bit32.band(style, C.UI_FORMATMASK)
	if fmt == C.UI_CENTER then
		local width = Q.int(G.UI_ProportionalStringWidth(str) * sizeScale)
		x -= Q.idiv(width, 2)
	elseif fmt == C.UI_RIGHT then
		local width = Q.int(G.UI_ProportionalStringWidth(str) * sizeScale)
		x -= width
	end

	local media = G.cgs.media
	local drawcolor = vec4(0, 0, 0, 0)

	if bit32.band(style, C.UI_DROPSHADOW) ~= 0 then
		drawcolor[0] = 0
		drawcolor[1] = 0
		drawcolor[2] = 0
		drawcolor[3] = color[3]
		UI_DrawProportionalString2(x + 2, y + 2, str, drawcolor, sizeScale, media.charsetProp)
	end

	if bit32.band(style, C.UI_INVERSE) ~= 0 then
		drawcolor[0] = color[0] * 0.8
		drawcolor[1] = color[1] * 0.8
		drawcolor[2] = color[2] * 0.8
		drawcolor[3] = color[3]
		UI_DrawProportionalString2(x, y, str, drawcolor, sizeScale, media.charsetProp)
		return
	end

	if bit32.band(style, C.UI_PULSE) ~= 0 then
		drawcolor[0] = color[0] * 0.8
		drawcolor[1] = color[1] * 0.8
		drawcolor[2] = color[2] * 0.8
		drawcolor[3] = color[3]
		UI_DrawProportionalString2(x, y, str, color, sizeScale, media.charsetProp)

		drawcolor[0] = color[0]
		drawcolor[1] = color[1]
		drawcolor[2] = color[2]
		drawcolor[3] = 0.5 + 0.5 * math.sin(G.cg.time / C.PULSE_DIVISOR)
		UI_DrawProportionalString2(x, y, str, drawcolor, sizeScale, media.charsetPropGlow)
		return
	end

	UI_DrawProportionalString2(x, y, str, color, sizeScale, media.charsetProp)
end

return G
