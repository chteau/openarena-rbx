-- Evaluates Quake III shader stages at a given time (tr_shade_calc.c
-- semantics): waveforms, rgbGen/alphaGen, tcMod chains (as a 2D affine
-- transform of the texture coordinates), animMap frames and the blend mode
-- a stage needs. R2D and R3D both draw from what this returns; the mapping
-- of each feature onto Roblox is in docs/client-notes.md.
local ShaderFx = {}

local TWO_PI = math.pi * 2

local function frac(x: number): number
	return x - math.floor(x)
end

-- Deterministic noise in [-1, 1] standing in for R_NoiseGet4f.
local function noise(t: number): number
	local i = math.floor(t)
	local f = t - i
	local function h(n)
		n = bit32.bxor(n * 1103515245 + 12345, bit32.rshift(n, 16)) % 65536
		return n / 32768 - 1
	end
	local a, b = h(i), h(i + 1)
	return a + (b - a) * (f * f * (3 - 2 * f))
end

-- EvalWaveForm: base + table[phase + time * freq] * amp
function ShaderFx.wave(w, timeSec: number): number
	if w == nil then
		return 1
	end
	local x = w.phase + timeSec * w.freq
	local v
	local fn = w.func
	if fn == "sin" then
		v = math.sin(frac(x) * TWO_PI)
	elseif fn == "square" then
		v = if frac(x) < 0.5 then 1 else -1
	elseif fn == "triangle" then
		local f = frac(x)
		v = if f < 0.25 then f * 4 elseif f < 0.75 then 2 - f * 4 else f * 4 - 4
	elseif fn == "sawtooth" then
		v = frac(x)
	elseif fn == "inversesawtooth" then
		v = 1 - frac(x)
	elseif fn == "noise" then
		v = noise(x)
	else
		v = 0
	end
	return w.base + v * w.amp
end

local function clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

-- How a stage blends: "opaque", "alpha", "add" or "filter" (multiply).
function ShaderFx.blendMode(st): string
	local bf = st.blendFunc
	if bf == nil then
		return if st.alphaFunc then "alpha" else "opaque"
	end
	local src, dst = bf[1], bf[2]
	if dst == "gl_one" then
		return "add"
	elseif src == "gl_dst_color" or dst == "gl_src_color" or (src == "gl_zero" and dst ~= "gl_zero") then
		return "filter"
	elseif dst == "gl_zero" then
		return "opaque"
	end
	return "alpha"
end

-- For an alpha-blended stand-in of an additive or filter stage (Assets.
-- StageImage): OA fades those by darkening the colour, which over a stand-in
-- means fading the opacity, so the colour's brightness moves into alpha.
function ShaderFx.foldBrightness(r: number, g: number, b: number, a: number): (number, number, number, number)
	local k = math.max(r, g, b)
	if k <= 0 then
		return 1, 1, 1, 0
	end
	return r / k, g / k, b / k, a * k
end

-- The image path a stage shows at `timeSec` (animMap picks a frame).
function ShaderFx.stageImage(st, timeSec: number): string?
	if st.animMap then
		local imgs = st.animMap.images
		local i = math.floor(timeSec * st.animMap.freq) % #imgs
		return imgs[i + 1]
	end
	return st.map
end

-- Colour and alpha of a stage. `vertex` is the incoming vertex/entity colour
-- {r, g, b, a} in 0..1 (R_SetColor in 2D, shaderRGBA for entities).
-- `light`: the entity's lighting (lightingDiffuse) where the caller has one
function ShaderFx.stageColor(st, timeSec: number, vertex: { number }, light: { number }?): (number, number, number, number)
	local r, g, b = 1, 1, 1
	local rg = st.rgbGen
	local ty = rg and rg.type or nil
	if ty == nil then
		-- default: identity, except vertex-coloured when the stage blends
		-- nothing in (implicit 2D/image shaders use vertex colour)
		if st.implicit then
			r, g, b = vertex[1], vertex[2], vertex[3]
		end
	elseif ty == "lightingdiffuse" and light then
		r, g, b = light[1], light[2], light[3]
	elseif ty == "vertex" or ty == "exactvertex" or ty == "entity" or ty == "lightingdiffuse" then
		r, g, b = vertex[1], vertex[2], vertex[3]
	elseif ty == "oneminusvertex" or ty == "oneminusentity" then
		r, g, b = 1 - vertex[1], 1 - vertex[2], 1 - vertex[3]
	elseif ty == "wave" then
		local v = clamp01(ShaderFx.wave(rg.wave, timeSec))
		r, g, b = v, v, v
	elseif ty == "const" and rg.color then
		r, g, b = rg.color[1] or 1, rg.color[2] or 1, rg.color[3] or 1
	end
	local a = 1
	local ag = st.alphaGen
	local aty = ag and ag.type or nil
	if aty == nil then
		if st.implicit or ty == "vertex" or ty == "exactvertex" or ty == "entity" then
			a = vertex[4]
		end
	elseif aty == "vertex" or aty == "entity" then
		a = vertex[4]
	elseif aty == "oneminusvertex" or aty == "oneminusentity" then
		a = 1 - vertex[4]
	elseif aty == "wave" then
		a = clamp01(ShaderFx.wave(ag.wave, timeSec))
	elseif aty == "const" then
		a = ag.value
	end
	return clamp01(r), clamp01(g), clamp01(b), clamp01(a)
end

-- tcMod chain as an affine map of (s, t): s' = a*s + b*t + c, t' = d*s + e*t + f.
-- Returned as {a, b, c, d, e, f}; turb and stretch use their current value.
function ShaderFx.texMatrix(st, timeSec: number): { number }
	local m = { 1, 0, 0, 0, 1, 0 }
	local function mul(n)
		-- m = n applied after m
		local a = n[1] * m[1] + n[2] * m[4]
		local b = n[1] * m[2] + n[2] * m[5]
		local c = n[1] * m[3] + n[2] * m[6] + n[3]
		local d = n[4] * m[1] + n[5] * m[4]
		local e = n[4] * m[2] + n[5] * m[5]
		local f = n[4] * m[3] + n[5] * m[6] + n[6]
		m = { a, b, c, d, e, f }
	end
	for _, tm in st.tcMod or {} do
		local ty = tm.type
		if ty == "scroll" then
			mul({ 1, 0, frac(tm.s * timeSec), 0, 1, frac(tm.t * timeSec) })
		elseif ty == "scale" then
			mul({ tm.s, 0, 0, 0, tm.t, 0 })
		elseif ty == "rotate" then
			local deg = -tm.degPerSec * timeSec
			local s, c = math.sin(math.rad(deg)), math.cos(math.rad(deg))
			-- rotate about (0.5, 0.5)
			mul({ c, -s, 0.5 - 0.5 * c + 0.5 * s, s, c, 0.5 - 0.5 * s - 0.5 * c })
		elseif ty == "stretch" then
			local p = ShaderFx.wave(tm.wave, timeSec)
			local inv = if p ~= 0 then 1 / p else 1
			mul({ inv, 0, 0.5 - 0.5 * inv, 0, inv, 0.5 - 0.5 * inv })
		elseif ty == "turb" then
			-- a whole-surface wobble; per-vertex turbulence can't be expressed
			-- as one transform, so the texture drifts by the wave instead
			local w = tm.wave
			local x = math.sin((w.phase + timeSec * w.freq) * TWO_PI) * w.amp
			mul({ 1, 0, x, 0, 1, x })
		elseif ty == "transform" then
			local t = tm.m
			mul({ t[1], t[3], t[5], t[2], t[4], t[6] })
		end
	end
	return m
end

-- The stages worth drawing (no lightmap-only stages), with `implicit` set for
-- an image with no script (vertex-coloured, alpha blended in 2D).
function ShaderFx.drawStages(shader): { any }
	local def = shader and shader.def
	if def == nil then
		if shader and shader.image then
			if shader.model then
				return { { map = shader.key, rgbGen = { type = "lightingdiffuse" } } }
			end
			return { { map = shader.key, implicit = true, blendFunc = { "gl_src_alpha", "gl_one_minus_src_alpha" } } }
		end
		return {}
	end
	local out = {}
	for _, st in def.stages do
		local img = st.map or (st.animMap and st.animMap.images[1])
		if img and img ~= "$lightmap" then
			table.insert(out, st)
		end
	end
	return out
end

return ShaderFx
