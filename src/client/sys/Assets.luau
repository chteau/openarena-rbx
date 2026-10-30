-- Name -> handle registries for shaders, models, skins and sounds
-- (RE_RegisterShader, RE_RegisterModel, RE_RegisterSkin, S_RegisterSound),
-- resolved against the asset index the pipeline produces.
--
-- AssetIndex (ModuleScript next to this one, optional):
--   images  = { ["gfx/2d/bigchars"] = { id = "rbxassetid://..", w = 256, h = 256 } }
--             keyed by lower-case path without extension
--   shaders = { [name] = shader table (ShaderParse shape) }   (from shaders.json)
--   models  = { ["models/weapons2/rocketl/rocketl"] = { ... see Md3.luau } }
--   baked2d = { [shader] = image path }  2D multi-stage shaders composited offline
--   atlases = { ["sfx_00.ogg"] = "rbxassetid://.." }  sound atlas uploads
--   sounds  = { ["sound/weapons/rocket/rocklf1a"] = { id, start, len } }   (SoundAtlas)
-- Shader scripts in the FS pack (scripts/*.shader) are parsed on first use
-- when `shaders` is missing.
local ShaderParse = require(script.Parent.ShaderParse)

local Assets = {}

local index = { images = {}, shaders = nil :: any, models = {}, sounds = {}, meshes = {} }
do
	local m = script.Parent:FindFirstChild("AssetIndex")
	if m then
		local ok, data = pcall(require, m)
		if ok and type(data) == "table" then
			for k, v in data do
				index[k] = v
			end
		end
	end
end
Assets.index = index

-- feat/conv's sound_index.json shape ({ ["sound/x.wav"] = { atlas, start,
-- length } }) -> { id, start, len } keyed without extension. `atlases` maps
-- an atlas file to its uploaded asset id (from the upload lock).
do
	local norm = {}
	for k, v in index.sounds do
		local key = string.lower(k):gsub("\\", "/"):gsub("%.%w%w%w?$", "")
		if v.atlas then
			local id = index.atlases and index.atlases[v.atlas]
			norm[key] = { id = id, start = v.start, len = v.length }
		else
			norm[key] = v
		end
	end
	index.sounds = norm
end

local function stripExt(name: string): string
	return (string.lower(name):gsub("\\", "/"):gsub("%.%w%w%w?$", ""))
end
Assets.stripExt = stripExt

local function shaderScripts()
	if index.shaders == nil then
		index.shaders = {}
		local FS = require(script.Parent.FS)
		local n, list = FS.GetFileList("scripts", "shader")
		for i = 0, n - 1 do
			local text = FS.ReadFile("scripts/" .. list[i])
			if text then
				ShaderParse.parse(text, index.shaders)
			end
		end
	end
	return index.shaders
end

function Assets.Image(path: string?)
	if path == nil then
		return nil
	end
	return index.images[stripExt(path)]
end

-- shaders ------------------------------------------------------------------
-- handle -> { name, def (shader table or nil for an implicit image shader),
--             image (first image entry or nil), remap (handle) }
local shaders = { [0] = { name = "<default>" } }
local shaderByName: { [string]: number } = {}

function Assets.RegisterShader(name: string, mip: boolean?): number
	local key = stripExt(name)
	local h = shaderByName[key]
	if h then
		return h
	end
	local def = shaderScripts()[key]
	if index.baked2d and index.baked2d[key] then
		-- a 2D shader whose stages multiply (blendfunc filter and friends),
		-- which GUI images can't: the pack ships it composited (docs/client-notes.md)
		def = ShaderParse.parse(key .. "\n{\n\tnopicmip\n\t{\n\t\tmap " .. index.baked2d[key] .. "\n\t}\n}\n")[key]
	end
	local image = nil
	if def then
		for _, st in def.stages do
			local p = st.map or (st.animMap and st.animMap.images[1])
			if p and p:sub(1, 1) ~= "$" then
				image = Assets.Image(p)
				if image then
					break
				end
			end
		end
	else
		image = Assets.Image(key)
		if image == nil then
			-- R_FindShader: a missing shader is the default shader, handle 0
			return 0
		end
	end
	h = #shaders + 1
	shaders[h] = { name = name, key = key, def = def, image = image }
	shaderByName[key] = h
	return h
end

-- An image the engine got at run time (an avatar headshot) as an implicit
-- 2D shader.
function Assets.RegisterImage(key: string, id: string, w: number, h: number): number
	index.images[key] = { id = id, w = w, h = h }
	return Assets.RegisterShader(key, false)
end

function Assets.Shader(h: number)
	local s = shaders[h]
	if s and s.remap then
		return shaders[s.remap] or s
	end
	return s
end

function Assets.ShaderDef(name: string)
	return shaderScripts()[stripExt(name)]
end

function Assets.RemapShader(old: string, new: string, timeOffset: string)
	local from = Assets.RegisterShader(old)
	local to = Assets.RegisterShader(new)
	if from ~= 0 then
		shaders[from].remap = if to ~= 0 and to ~= from then to else nil
		shaders[from].timeOffset = tonumber(timeOffset) or 0
	end
end

-- skins --------------------------------------------------------------------
-- handle -> { [surface name] = shader handle }
local skins = { [0] = {} }
local skinByName: { [string]: number } = {}

function Assets.RegisterSkin(name: string): number
	local key = string.lower(name)
	if skinByName[key] then
		return skinByName[key]
	end
	local FS = require(script.Parent.FS)
	local text = FS.ReadFile(name)
	if text == nil then
		return 0
	end
	local skin = {}
	for line in text:gmatch("[^\r\n]+") do
		local surf, shader = line:match("^%s*([^,]+),%s*(%S*)")
		if surf and not surf:match("^tag_") then
			skin[string.lower(surf)] = if shader and shader ~= "" then Assets.RegisterShader(shader) else 0
		end
	end
	local h = #skins + 1
	skins[h] = skin
	skinByName[key] = h
	return h
end

function Assets.Skin(h: number)
	return skins[h]
end

-- models -------------------------------------------------------------------
-- handle -> model (Md3.luau shape) ; 0 = none
local models = { [0] = false :: any }
local modelByName: { [string]: number } = {}

function Assets.RegisterModel(name: string): number
	local key = stripExt(name)
	if modelByName[key] then
		return modelByName[key]
	end
	local Md3 = require(script.Parent.Md3)
	local model = Md3.Load(key, index.models[key])
	if model == nil then
		return 0
	end
	local h = #models + 1
	models[h] = model
	modelByName[key] = h
	return h
end

function Assets.Model(h: number)
	return models[h] or nil
end

function Assets.ModelBounds(h: number, mins, maxs)
	local m = models[h]
	local f = m and m.frames and m.frames[0]
	for i = 0, 2 do
		mins[i] = if f then f.mins[i] else 0
		maxs[i] = if f then f.maxs[i] else 0
	end
end

function Assets.LerpTag(tag, h: number, startFrame: number, endFrame: number, frac: number, name: string): boolean
	local m = models[h]
	local Md3 = require(script.Parent.Md3)
	if not m or not Md3.LerpTag(tag, m, startFrame, endFrame, frac, name) then
		for i = 0, 2 do
			tag.origin[i] = 0
			for j = 0, 2 do
				tag.axis[i][j] = if i == j then 1 else 0
			end
		end
		return false
	end
	return true
end

-- sounds -------------------------------------------------------------------
local sounds = { [0] = false :: any }
local soundByName: { [string]: number } = {}

-- S_RegisterSound never fails in Q3 (a missing file plays nothing), so a
-- handle is always returned; Sound(h).clip is nil when the atlas lacks it.
function Assets.RegisterSound(name: string): number
	local key = stripExt(name)
	local h = soundByName[key]
	if h then
		return h
	end
	h = #sounds + 1
	local clip = index.sounds[key]
	sounds[h] = { name = key, clip = if clip and clip.id then clip else nil }
	soundByName[key] = h
	return h
end

function Assets.Sound(h: number)
	return sounds[h] or nil
end

return Assets
