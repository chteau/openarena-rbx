-- Shader effects on the map's non-baked surfaces, the sky box and fog.
--
-- The converter bakes plain surfaces into the map's atlas meshes; what it
-- can't bake (scrolling/animated/additive/deforming shaders) becomes
-- MeshParts tagged with attributes (contract, see docs/client-notes.md):
--   OAShader = "<shader name>"   OAStage = <1-based stage index, default 1>
-- or, untagged, a part named after a map.json mesh whose class isn't opaque
-- WorldFx animates each tagged part every frame from the parsed shader:
--   tcMod scroll/rotate/scale/stretch/turb/transform -> UVs rewritten on an
--       EditableMesh copy of the part's mesh (base UVs x the stage matrix)
--   animMap -> TextureID swapped per frame
--   rgbGen/alphaGen wave/const -> vertex colour (EditableMesh) or
--       Transparency (additive stages, where brightness is opacity)
--   deformVertexes wave/move/bulge -> vertex positions on the EditableMesh
--   blendFunc add -> Neon material + transparency (no additive blend on Roblox)
-- Sky: the map's sky shader (Map attribute OASky, or index.maps[name].sky)
-- feeds a Lighting.Sky from its skyparms box (env/<name>_rt/_lf/...).
-- Fog: index.maps[name].fogs = { {mins={x,y,z}, maxs=..., shader=""} };
-- with the view inside one, Lighting fog takes its colour and opaque depth.
local Assets = require(script.Parent.Assets)
local ShaderFx = require(script.Parent.ShaderFx)

local WorldFx = {}

local AssetService = game:GetService("AssetService")
local Lighting = game:GetService("Lighting")

-- Set by the client: where the loaded map lives.
WorldFx.mapRoot = nil :: Instance?

local animated: { any } = {}
local fogs: { any } = {}
local savedFog: { any }? = nil

-- feat/conv's map.json lists every mesh it exports with the shader the
-- client must draw (glb.meshes[i] = { name, shader, class, overlay }); the
-- index carries it as maps[name].meshes = { [meshName] = that record }.
local meshInfo: { [string]: any } = {}

local function stageOf(part: Instance)
	local name = part:GetAttribute("OAShader")
	if name == nil then
		local m = meshInfo[part.Name]
		if m and (m.overlay or (m.class ~= nil and m.class ~= "opaque")) and m.shader ~= "atlas" then
			name = m.shader
		end
	end
	if type(name) ~= "string" then
		return nil, nil
	end
	local def = Assets.ShaderDef(name)
	if def == nil then
		return nil, nil
	end
	local idx = part:GetAttribute("OAStage")
	local st = def.stages[if type(idx) == "number" then idx else 1]
	return def, st
end

local function needsMesh(def, st): boolean
	if #def.deforms > 0 or (st.tcMod and #st.tcMod > 0) then
		return true
	end
	local ty = st.rgbGen and st.rgbGen.type
	return (ty == "wave" or ty == "const") and ShaderFx.blendMode(st) ~= "add"
end

-- Swaps `part` for an EditableMesh-backed copy so UVs/colours/positions can
-- change at runtime; returns the record or nil when the platform says no
-- (EditableMesh is off unless the experience enables it in its Security
-- settings: creating one works, reading it then errors). The first refusal
-- turns the effect off for the session; the part keeps its static look.
local editableRefused = false
local loadWarned = false
local function editable(part: MeshPart)
	if editableRefused then
		return nil
	end
	local ok, rec = pcall(function()
		local em = AssetService:CreateEditableMeshAsync(Content.fromUri(part.MeshId), { FixedSize = true })
		local rec: any = { em = em }
		rec.uvIds = em:GetUVs()
		rec.baseUV = table.create(#rec.uvIds)
		for i, id in rec.uvIds do
			rec.baseUV[i] = em:GetUV(id)
		end
		rec.vertIds = em:GetVertices()
		rec.basePos = table.create(#rec.vertIds)
		for i, id in rec.vertIds do
			rec.basePos[i] = em:GetPosition(id)
		end
		rec.colorIds = em:GetColors()
		rec.part = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		return rec
	end)
	if not ok or rec == nil then
		-- only the Security setting turns the effect off for the session; a
		-- mesh that fails to load leaves just that part static
		if string.find(tostring(rec), "not accessible", 1, true) then
			editableRefused = true
			warn("WorldFx: no EditableMesh here, animated map shaders stay static: " .. tostring(rec))
		elseif not loadWarned then
			loadWarned = true
			warn("WorldFx: " .. part.Name .. " stays static (and any other part that fails the same way): " .. tostring(rec))
		end
		return nil
	end
	local copy = rec.part
	copy.CFrame, copy.Size = part.CFrame, part.Size
	copy.TextureID, copy.Material, copy.Color, copy.Transparency = part.TextureID, part.Material, part.Color, part.Transparency
	copy.Anchored, copy.CanCollide, copy.CanQuery, copy.CanTouch = true, false, false, false
	copy.CastShadow = part.CastShadow
	for k, v in part:GetAttributes() do
		copy:SetAttribute(k, v)
	end
	copy.Name = part.Name
	copy.Parent = part.Parent
	part.Parent = nil
	return rec
end

function WorldFx.Load(mapName: string)
	table.clear(animated)
	local root = WorldFx.mapRoot or workspace:FindFirstChild("Map")
	local maps = Assets.index.maps or {}
	-- R_LoadWorldMap gets the BSP path ("maps/oa_dm1.bsp")
	local key = string.lower(mapName or ""):gsub("^maps/", ""):gsub("%.bsp$", "")
	local info = maps[key] or {}
	fogs = info.fogs or {}
	table.clear(meshInfo)
	for _, m in info.meshes or {} do
		meshInfo[m.name] = m
	end
	if root then
		for _, part in root:GetDescendants() do
			if part:IsA("MeshPart") then
				local def, st = stageOf(part)
				if def and st then
					local rec = if needsMesh(def, st) then editable(part) else nil
					rec = rec or { part = part }
					rec.def, rec.st = def, st
					rec.mode = ShaderFx.blendMode(st)
					rec.baseTransparency = rec.part.Transparency
					if rec.mode == "add" then
						rec.part.Material = Enum.Material.Neon
					end
					table.insert(animated, rec)
				end
			end
		end
	end
	local sky = (root and root:GetAttribute("OASky")) or info.sky
	if type(sky) == "string" then
		WorldFx.SetSky(sky)
	end
end

-- Q3 sky box faces -> Roblox Sky faces. tr_sky.c draws suffix i of
-- {rt, bk, lf, ft, up, dn} on the side st_to_vec[i] points at: rt +X,
-- bk -X, lf +Y, ft -Y. With Quake (x, y, z) -> Roblox (x, z, -y) that is
-- Rt +X, Lf -X, Ft -Z, Bk +Z. The in-face rotation of each image is not
-- checked against the real game yet (no converted map to look at).
function WorldFx.SetSky(shaderName: string)
	local def = Assets.ShaderDef(shaderName)
	if def == nil or def.sky == nil or def.sky.outer == nil or def.sky.outer == "-" then
		return
	end
	local box = def.sky.outer
	local function face(suffix)
		local img = Assets.Image(box .. "_" .. suffix)
		return img and img.id or ""
	end
	local skyObj = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	skyObj.SkyboxRt = face("rt")
	skyObj.SkyboxLf = face("bk")
	skyObj.SkyboxFt = face("lf")
	skyObj.SkyboxBk = face("ft")
	skyObj.SkyboxUp = face("up")
	skyObj.SkyboxDn = face("dn")
	skyObj.CelestialBodiesShown = false
	skyObj.StarCount = 0
	skyObj.Parent = Lighting
end

local function inside(p, f): boolean
	return p[0] >= f.mins[1] and p[0] <= f.maxs[1] and p[1] >= f.mins[2] and p[1] <= f.maxs[2]
		and p[2] >= f.mins[3] and p[2] <= f.maxs[3]
end

local function updateFog(vieworg)
	local hit = nil
	for _, f in fogs do
		if inside(vieworg, f) then
			hit = f
			break
		end
	end
	if hit then
		local def = Assets.ShaderDef(hit.shader)
		local fp = def and def.fogParms
		if fp then
			if savedFog == nil then
				savedFog = { Lighting.FogColor, Lighting.FogStart, Lighting.FogEnd }
			end
			Lighting.FogColor = Color3.new(fp.color[1], fp.color[2], fp.color[3])
			Lighting.FogStart = 0
			Lighting.FogEnd = math.max(fp.depthForOpaque / 8, 1)
		end
	elseif savedFog then
		Lighting.FogColor, Lighting.FogStart, Lighting.FogEnd = savedFog[1], savedFog[2], savedFog[3]
		savedFog = nil
	end
end

local function deform(rec, timeSec: number)
	local pos = table.create(#rec.basePos)
	for i, p in rec.basePos do
		local q = p
		for _, d in rec.def.deforms do
			if d.type == "wave" and d.wave then
				-- offset along the vertex's height (no per-vertex normal here:
				-- Quake's vertical waves on water/flags), phase spread by position
				local off = (p.X + p.Y + p.Z) * 8 * (d.div ~= 0 and (1 / d.div) or 0)
				local w = d.wave
				local v = ShaderFx.wave({ func = w.func, base = w.base, amp = w.amp, phase = w.phase + off, freq = w.freq }, timeSec)
				q += Vector3.new(0, v / 8, 0)
			elseif d.type == "move" and d.wave then
				local v = ShaderFx.wave(d.wave, timeSec)
				q += Vector3.new(d.vec[1], d.vec[3], -d.vec[2]) * (v / 8)
			elseif d.type == "bulge" then
				local s = math.sin(timeSec * d.speed + (p.X + p.Z) * 8 * d.width) * d.height / 8
				q += Vector3.new(0, s, 0)
			end
		end
		pos[i] = q
	end
	rec.em:BatchSetValues(rec.vertIds, pos)
end

function WorldFx.Update(refdef, timeSec: number)
	updateFog(refdef.vieworg)
	for _, rec in animated do
		local st = rec.st
		local part = rec.part
		if st.animMap then
			local img = Assets.Image(ShaderFx.stageImage(st, timeSec))
			if img and img.id and part.TextureID ~= img.id then
				part.TextureID = img.id
			end
		end
		local r, g, b, a = ShaderFx.stageColor(st, timeSec, { 1, 1, 1, 1 })
		if rec.mode == "add" then
			-- additive: darker means more see-through
			local lum = math.max(r, g, b) * a
			part.Transparency = math.clamp(1 - lum, 0, 0.95)
		elseif rec.mode == "alpha" then
			part.Transparency = math.clamp(1 - a, 0, 1)
		end
		if rec.em then
			if st.tcMod and #st.tcMod > 0 then
				local m = ShaderFx.texMatrix(st, timeSec)
				local uvs = table.create(#rec.baseUV)
				for i, uv in rec.baseUV do
					uvs[i] = Vector2.new(m[1] * uv.X + m[2] * uv.Y + m[3], m[4] * uv.X + m[5] * uv.Y + m[6])
				end
				rec.em:BatchSetValues(rec.uvIds, uvs)
			end
			if #rec.def.deforms > 0 then
				deform(rec, timeSec)
			end
			if rec.mode ~= "add" and #rec.colorIds > 0 and st.rgbGen then
				rec.em:BatchSetValues(rec.colorIds, table.create(#rec.colorIds, Color3.new(r, g, b)))
			end
		end
	end
end

return WorldFx
