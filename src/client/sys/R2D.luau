-- 2D half of the renderer: RE_SetColor / RE_StretchPic onto a pool of
-- ImageLabels, rebuilt every frame in draw order (later draws on top).
--
-- Each shader stage becomes one label: the image's UV rectangle maps to
-- ImageRectOffset/ImageRectSize, the colour to ImageColor3/ImageTransparency.
-- UVs outside 0..1 (tiling, tcMod scroll) are split into one label per
-- texture repeat, so wrapping stays exact. What Roblox can't blend (GL_ONE
-- additive, filter) is listed in docs/client-notes.md.
local Assets = require(script.Parent.Assets)
local ShaderFx = require(script.Parent.ShaderFx)
local Clock = require(script.Parent.Clock)

local R2D = {}

-- Set by the client: the GuiObject/ScreenGui everything is drawn into, and
-- its size in pixels (glconfig.vidWidth/vidHeight).
R2D.root = nil :: Instance?
R2D.width = 640
R2D.height = 480
-- Layers above the 2D layer (ViewportFrames for RDF_NOWORLDMODEL scenes)
-- take ZIndex from the same counter, so they interleave with draws.
R2D.z = 0

local pool: { ImageLabel } = {}
local used = 0
local color = { 1, 1, 1, 1 }
local MAX_CELLS = 16

function R2D.SetColor(rgba)
	if rgba == nil then
		color = { 1, 1, 1, 1 }
	else
		color = { rgba[0], rgba[1], rgba[2], rgba[3] }
	end
end

function R2D.GetGlconfig(gl)
	gl.vidWidth = R2D.width
	gl.vidHeight = R2D.height
	gl.windowAspect = R2D.width / R2D.height
	gl.colorBits, gl.depthBits, gl.stencilBits = 32, 24, 8
	gl.maxTextureSize = 1024
	gl.isFullscreen = false
	gl.renderer_string = "Roblox"
	gl.vendor_string = "Roblox"
	gl.version_string = "rbx"
end

function R2D.NextZ(): number
	R2D.z += 1
	return R2D.z
end

local function label(): ImageLabel
	used += 1
	local l = pool[used]
	if l == nil then
		l = Instance.new("ImageLabel")
		l.Name = "Pic"
		l.BorderSizePixel = 0
		l.BackgroundTransparency = 1
		l.ScaleType = Enum.ScaleType.Stretch
		l.Parent = R2D.root
		pool[used] = l
	elseif l.Parent ~= R2D.root then
		l.Parent = R2D.root
	end
	l.Visible = true
	l.ZIndex = R2D.NextZ()
	return l
end

local function place(l: GuiObject, x: number, y: number, w: number, h: number)
	-- round edges, not origin and size separately, so abutting pics meet
	local x0, y0 = math.floor(x + 0.5), math.floor(y + 0.5)
	local x1, y1 = math.floor(x + w + 0.5), math.floor(y + h + 0.5)
	l.Position = UDim2.fromOffset(x0, y0)
	l.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
end

local function solid(x, y, w, h, r, g, b, a)
	local l = label()
	place(l, x, y, w, h)
	l.Image = ""
	l.BackgroundColor3 = Color3.new(r, g, b)
	l.BackgroundTransparency = 1 - a
	l.Rotation = 0
end

-- One image, uv rectangle (u0,v0)-(u1,v1) in texture space (may leave 0..1
-- or be reversed for a flip), onto the screen rectangle.
local function textured(img, x, y, w, h, u0, v0, u1, v1, r, g, b, a)
	local W, H = img.w, img.h
	local ua, ub = math.min(u0, u1), math.max(u0, u1)
	local va, vb = math.min(v0, v1), math.max(v0, v1)
	local flipU, flipV = u1 < u0, v1 < v0
	local cu0, cu1 = math.floor(ua), math.max(math.ceil(ub) - 1, math.floor(ua))
	local cv0, cv1 = math.floor(va), math.max(math.ceil(vb) - 1, math.floor(va))
	local cells = (cu1 - cu0 + 1) * (cv1 - cv0 + 1)
	local function emit(sx, sy, sw, sh, ra, rb, rc, rd, fu, fv, tile)
		local l = label()
		place(l, sx, sy, sw, sh)
		l.Image = img.id
		l.BackgroundTransparency = 1
		l.ImageColor3 = Color3.new(r, g, b)
		l.ImageTransparency = 1 - a
		l.Rotation = 0
		if tile then
			l.ScaleType = Enum.ScaleType.Tile
			l.TileSize = UDim2.fromOffset(tile.X, tile.Y)
			l.ImageRectOffset = Vector2.zero
			l.ImageRectSize = Vector2.zero
			return
		end
		l.ScaleType = Enum.ScaleType.Stretch
		if ra == 0 and rb == 0 and rc == W and rd == H and not fu and not fv then
			l.ImageRectOffset = Vector2.zero
			l.ImageRectSize = Vector2.zero
			return
		end
		-- a flipped axis is a negative rect size starting from the far edge
		local ox, sxz = ra, rc
		local oy, syz = rb, rd
		if fu then
			ox, sxz = ra + rc, -rc
		end
		if fv then
			oy, syz = rb + rd, -rd
		end
		l.ImageRectOffset = Vector2.new(ox, oy)
		l.ImageRectSize = Vector2.new(sxz, syz)
	end
	if ub - ua <= 0 or vb - va <= 0 then
		return
	end
	if cells > MAX_CELLS then
		emit(x, y, w, h, 0, 0, W, H, false, false, Vector2.new(w / (ub - ua), h / (vb - va)))
		return
	end
	for cu = cu0, cu1 do
		for cv = cv0, cv1 do
			local su0, su1 = math.max(ua, cu), math.min(ub, cu + 1)
			local sv0, sv1 = math.max(va, cv), math.min(vb, cv + 1)
			if su1 > su0 and sv1 > sv0 then
				-- where this piece sits on screen (mirrored when flipped)
				local fx0 = (su0 - ua) / (ub - ua)
				local fx1 = (su1 - ua) / (ub - ua)
				local fy0 = (sv0 - va) / (vb - va)
				local fy1 = (sv1 - va) / (vb - va)
				if flipU then
					fx0, fx1 = 1 - fx1, 1 - fx0
				end
				if flipV then
					fy0, fy1 = 1 - fy1, 1 - fy0
				end
				emit(
					x + fx0 * w,
					y + fy0 * h,
					(fx1 - fx0) * w,
					(fy1 - fy0) * h,
					(su0 - cu) * W,
					(sv0 - cv) * H,
					(su1 - su0) * W,
					(sv1 - sv0) * H,
					flipU,
					flipV
				)
			end
		end
	end
end

-- RE_StretchPic
function R2D.DrawStretchPic(x, y, w, h, s1, t1, s2, t2, hShader: number)
	if R2D.root == nil or w == 0 or h == 0 then
		return
	end
	local shader = Assets.Shader(hShader)
	if shader == nil or hShader == 0 then
		return
	end
	local timeSec = Clock.Milliseconds() * 0.001 - (shader.timeOffset or 0)
	for _, st in ShaderFx.drawStages(shader) do
		local r, g, b, a = ShaderFx.stageColor(st, timeSec, color)
		local path = ShaderFx.stageImage(st, timeSec)
		if path == "*white" or path == "$whiteimage" then
			solid(x, y, w, h, r, g, b, a)
		else
			local img = Assets.Image(path)
			if img then
				local m = ShaderFx.texMatrix(st, timeSec)
				if m[2] == 0 and m[4] == 0 then
					textured(img, x, y, w, h,
						m[1] * s1 + m[3], m[5] * t1 + m[6],
						m[1] * s2 + m[3], m[5] * t2 + m[6], r, g, b, a)
				else
					-- rotation: draw the untransformed quad turned by the angle
					textured(img, x, y, w, h, s1, t1, s2, t2, r, g, b, a)
					pool[used].Rotation = -math.deg(math.atan2(m[4], m[1]))
				end
			end
		end
	end
end

function R2D.BeginFrame()
	used = 0
	R2D.z = 0
end

function R2D.EndFrame()
	for i = used + 1, #pool do
		if pool[i].Visible then
			pool[i].Visible = false
		end
	end
end

function R2D.Count(): number
	return used
end

return R2D
