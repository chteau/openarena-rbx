-- Quake III's 640x480 virtual screen, mapped onto a viewport of any aspect.
--
-- Every 2D draw in cgame (CG_AdjustFrom640) and q3_ui (UI_AdjustFrom640)
-- goes through here:
--
--   real_x = x * xscale + xbias     real_y = y * yscale + ybias
--   real_w = w * xscale             real_h = h * yscale
--
-- The 640x480 area is scaled uniformly, s = min(safe width / 640, h / 480),
-- so nothing is stretched and a screen narrower than 4:3 shrinks the layout
-- to fit its width instead of cropping it. Where the scaled area sits
-- depends on the placement of what is drawn: each axis is pinned to an edge
-- (left/top, right/bottom), centred, or stretched over the whole screen.
-- An edge placement keeps OA's 4:3 offset from that edge and stays inside
-- the safe area (Screen.insets: notches, the Roblox topbar); centred and
-- stretched ones use the whole screen. At 4:3 with no insets every
-- placement gives x * w/640, y * h/480, OpenArena 0.8.8's own mapping.
--
-- q3_ui is drawn centred; its decorative full-screen backgrounds cover the
-- screen (Screen.cover) so a wide screen has no pillarbox bars.
local Screen = {}

Screen.WIDTH = 640
Screen.HEIGHT = 480

-- placements (horizontal: LEFT/CENTER/RIGHT, vertical: TOP/CENTER/BOTTOM)
Screen.LEFT = 0
Screen.TOP = 0
Screen.CENTER = 1
Screen.RIGHT = 2
Screen.BOTTOM = 2
Screen.STRETCH = 3

-- Safe-area insets in real pixels, kept up to date by the client.
Screen.insets = { left = 0, top = 0, right = 0, bottom = 0 }

export type Insets = { left: number, top: number, right: number, bottom: number }
export type Layout = {
	scale: number,
	sx: number,
	sy: number,
	x: { [number]: number },
	y: { [number]: number },
}

local NO_INSETS: Insets = { left = 0, top = 0, right = 0, bottom = 0 }

function Screen.layout(w: number, h: number, insets: Insets?): Layout
	local ins = insets or Screen.insets
	local s = math.min((w - ins.left - ins.right) / 640, h / 480)
	local vw, vh = 640 * s, 480 * s
	return {
		scale = s,
		sx = w / 640,
		sy = h / 480,
		x = { [0] = ins.left, 0.5 * (w - vw), w - vw - ins.right },
		y = { [0] = ins.top, 0.5 * (h - vh), h - vh - ins.bottom },
	}
end

-- Hor+: cg_fov is the horizontal FOV of a 4:3 view. A wider view keeps that
-- view's vertical FOV and sees more at the sides; a narrower one keeps the
-- horizontal FOV and sees more above and below (never less than 4:3):
--
--   fov_y = 2 * atan(tan(fov / 2) * max(3/4, h / w))
--   fov_x = 2 * atan(tan(fov_y / 2) * w / h)
--
-- At 4:3 this is CG_CalcFov's own fov_y = atan2(h, w / tan(fov_x / 2)).
function Screen.fov(fov: number, w: number, h: number): (number, number)
	local t = math.tan(math.rad(fov) * 0.5) * math.max(0.75, h / w)
	return math.deg(2 * math.atan(t * w / h)), math.deg(2 * math.atan(t))
end

-- UVs that cover a w x h screen with a 4:3 picture, cropping the overflow
-- evenly (s1, t1, s2, t2 for R_DrawStretchPic over the whole screen).
function Screen.cover(w: number, h: number): (number, number, number, number)
	if w * 480 > h * 640 then
		local f = 0.5 * (1 - h * 640 / (w * 480))
		return 0, f, 1, 1 - f
	end
	local f = 0.5 * (1 - w * 480 / (h * 640))
	return f, 0, 1 - f, 1
end

-- cgame (cgs) ------------------------------------------------------------------------

-- Fills cgs.screenLayout from cgs.glconfig (CG_Init, and on every resize)
-- and resets the placement to centred.
function Screen.cgSetup(cgs)
	cgs.screenLayout = Screen.layout(cgs.glconfig.vidWidth, cgs.glconfig.vidHeight)
	Screen.cgPlace(cgs, Screen.CENTER, Screen.CENTER)
end

-- CG_SetScreenPlacement: what the following draws are anchored to.
function Screen.cgPlace(cgs, horizontal: number, vertical: number)
	local l = cgs.screenLayout
	if horizontal == Screen.STRETCH then
		cgs.screenXScale, cgs.screenXBias = l.sx, 0
	else
		cgs.screenXScale, cgs.screenXBias = l.scale, l.x[horizontal]
	end
	if vertical == Screen.STRETCH then
		cgs.screenYScale, cgs.screenYBias = l.sy, 0
	else
		cgs.screenYScale, cgs.screenYBias = l.scale, l.y[vertical]
	end
end

function Screen.cgAdjust(cgs, x: number, y: number, w: number, h: number): (number, number, number, number)
	return x * cgs.screenXScale + cgs.screenXBias,
		y * cgs.screenYScale + cgs.screenYBias,
		w * cgs.screenXScale,
		h * cgs.screenYScale
end

-- q3_ui (uis) ------------------------------------------------------------------------

-- Fills uis.xscale / yscale / bias / ybias from uis.glconfig (UI_Init, and
-- on every resize): the menus are centred on the whole screen.
function Screen.uiSetup(uis)
	local l = Screen.layout(uis.glconfig.vidWidth, uis.glconfig.vidHeight, NO_INSETS)
	uis.xscale, uis.yscale = l.scale, l.scale
	uis.bias, uis.ybias = l.x[Screen.CENTER], l.y[Screen.CENTER]
end

function Screen.uiAdjust(uis, x: number, y: number, w: number, h: number): (number, number, number, number)
	return x * uis.xscale + uis.bias, y * uis.yscale + uis.ybias, w * uis.xscale, h * uis.yscale
end

-- Real pixel -> virtual 640x480 (cursor), the inverse of uiAdjust.
function Screen.uiToVirtual(uis, px: number, py: number): (number, number)
	return (px - uis.bias) / uis.xscale, (py - uis.ybias) / uis.yscale
end

return Screen
