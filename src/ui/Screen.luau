-- Quake III's 640x480 virtual screen, mapped onto the real viewport.
--
-- Every 2D draw in cgame (CG_AdjustFrom640) and q3_ui (UI_AdjustFrom640)
-- goes through here, so the whole HUD/menu layout follows one rule:
--
--   real_x = x * xscale + bias      real_y = y * yscale
--   real_w = w * xscale             real_h = h * yscale
--
-- q3_ui keeps 4:3 on a wider screen: xscale = yscale = vidHeight / 480 and
-- the 640-wide area is centred (bias = half the spare width), which is what
-- OpenArena 0.8.8's menus do. Full-screen backgrounds are drawn in real
-- pixels (UI_DrawBackgroundPic) and so still fill the screen.
--
-- The cgame HUD in OpenArena 0.8.8 stretches the 640 width over the whole
-- screen (xscale = vidWidth / 640, no bias); the reference shots in
-- docs/parity/ref show it. The gamecode this port follows later added a
-- centred 4:3 HUD ("leilei - widescreen adjust"); `cg_wideScreenHud 1`
-- selects that instead, 0 (default) matches 0.8.8.
local Screen = {}

Screen.WIDTH = 640
Screen.HEIGHT = 480

-- Fills cgs.screenXScale / screenYScale / screenXBias (and returns the
-- "wideAdjustX" the cgame keeps for the crosshair) from cgs.glconfig.
function Screen.cgSetup(cgs, wideHud: boolean?): number
	local w, h = cgs.glconfig.vidWidth, cgs.glconfig.vidHeight
	cgs.screenXScale = w / 640.0
	cgs.screenYScale = h / 480.0
	cgs.screenXBias = 0
	if wideHud and w * 480 > h * 640 then
		cgs.screenXBias = 0.5 * (w - (h * (640.0 / 480.0)))
		cgs.screenXScale = cgs.screenYScale
		-- leilei's resbias, in virtual units: 0.5 * (w * 480 / h - 640)
		return 0.5 * (w * (480.0 / h) - 640.0)
	end
	return 0
end

function Screen.cgAdjust(cgs, x: number, y: number, w: number, h: number): (number, number, number, number)
	return x * cgs.screenXScale + cgs.screenXBias, y * cgs.screenYScale, w * cgs.screenXScale, h * cgs.screenYScale
end

-- Fills uis.xscale / yscale / bias from uis.glconfig (UI_Init).
function Screen.uiSetup(uis)
	local w, h = uis.glconfig.vidWidth, uis.glconfig.vidHeight
	uis.xscale = w * (1.0 / 640.0)
	uis.yscale = h * (1.0 / 480.0)
	if w * 480 > h * 640 then
		uis.bias = 0.5 * (w - (h * (640.0 / 480.0)))
		uis.xscale = uis.yscale
	else
		uis.bias = 0
	end
end

function Screen.uiAdjust(uis, x: number, y: number, w: number, h: number): (number, number, number, number)
	return x * uis.xscale + uis.bias, y * uis.yscale, w * uis.xscale, h * uis.yscale
end

-- Real pixel -> virtual 640x480 (cursor), the inverse of uiAdjust.
function Screen.uiToVirtual(uis, px: number, py: number): (number, number)
	return (px - uis.bias) / uis.xscale, py / uis.yscale
end

return Screen
