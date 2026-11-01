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
--   deformVertexes wave/move/bulge/autosprite/autosprite2 -> vertex
--       positions on the EditableMesh (sprites turned to the view every frame)
--   blendFunc add -> Neon material + transparency (no additive blend on Roblox)
--   blendFunc add/filter/... with the converter's alpha stand-in for the
--       stage's image (Assets.StageImage) -> that image, so the black (or
--       white) background is see-through
-- An overlay (drawn over its baked copy) whose stage would draw opaque, or
-- is an environment map, is hidden: the baked layer already has the static
-- look, and the overlay would cover it with the raw image (flat gray for
-- the env maps). Roblox has no polygonOffset: overlays and polygonOffset
-- decals sit on the very plane of the wall under them, so every frame they
-- are scaled about the view by OFFSET, which keeps them where they are on
-- screen and puts them a hair in front.
-- Brush models (map parts named model<N>_...) are drawn where their entity
-- is (R3D -> WorldFx.PlaceInline, as tr_world.c R_AddBrushModelSurfaces):
-- doors, plats and trains move, a mover built around an origin brush sits
-- at its entity instead of the map origin, and a model no entity drew this
-- frame (triggers, out of view) is not drawn at all.
-- Sky: the map's sky shader (Map attribute OASky, or index.maps[name].sky)
-- feeds a Lighting.Sky from its skyparms box (env/<name>_rt/_lf/...).
-- Fog: index.maps[name].fogs = { {mins={x,y,z}, maxs=..., shader=""} };
-- with the view inside one, Lighting fog takes its colour and opaque depth.
local Assets = require(script.Parent.Assets)
local ShaderFx = require(script.Parent.ShaderFx)
local Units = require(script.Parent.Units)

local WorldFx = {}

local AssetService = game:GetService("AssetService")
local Lighting = game:GetService("Lighting")

-- Set by the client: where the loaded map lives.
WorldFx.mapRoot = nil :: Instance?

local animated: { any } = {}
local OFFSET = 0.002
local fogs: { any } = {}
-- submodel number -> its parts' records ({ part, base, baseCF, seen })
local movers: { [number]: { any } } = {}
local IDENTITY = Units.toCFrame({ [0] = 0, 0, 0 }, { [0] = { [0] = 1, 0, 0 }, { [0] = 0, 1, 0 }, { [0] = 0, 0, 1 } })
local savedFog: { any }? = nil

-- feat/conv's map.json lists every mesh it exports with the shader the
-- client must draw (glb.meshes[i] = { name, shader, class, overlay }); the
-- index carries it as maps[name].meshes = { [meshName] = that record }.
local meshInfo: { [string]: any } = {}

-- tools/oaconv shader/classify.rs stage_animated: a stage the converter
-- leaves to the client (an overlay carries only those)
local ANIMATED_RGB = { wave = true, entity = true, oneminusentity = true, lightingdiffuse = true }
local ANIMATED_ALPHA = { wave = true, entity = true, oneminusentity = true, lightingspecular = true, portal = true }
local function stageAnimated(st): boolean
	if st.animMap or st.videoMap or st.tcGen == "environment" then
		return true
	end
	for _, m in st.tcMod do
		if m.type ~= "scale" and m.type ~= "transform" then
			return true
		end
	end
	local rgb, alpha = st.rgbGen and st.rgbGen.type, st.alphaGen and st.alphaGen.type
	return (rgb ~= nil and ANIMATED_RGB[rgb] == true) or (alpha ~= nil and ANIMATED_ALPHA[alpha] == true)
end

local function stageOf(part: Instance)
	local name = part:GetAttribute("OAShader")
	local overlay = false
	if name == nil then
		local m = meshInfo[part.Name]
		if m and (m.overlay or (m.class ~= nil and m.class ~= "opaque")) and m.shader ~= "atlas" then
			name = m.shader
			overlay = m.overlay == true
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
	if type(idx) == "number" then
		return def, def.stages[idx]
	end
	-- the stage whose image the part wears: the converter textures a mesh
	-- with the shader's first image, an overlay with its first animated one
	-- (the baked stages may wear the same image: never those)
	if part:IsA("MeshPart") then
		for _, st in def.stages do
			if overlay and not stageAnimated(st) then
				continue
			end
			local path = st.map or (st.animMap and st.animMap.images[1])
			local img, alt = Assets.Image(path), Assets.StageImage(st, path)
			if (img and img.id == part.TextureID) or (alt and alt.id == part.TextureID) then
				return def, st
			end
		end
	end
	if overlay then
		for _, st in def.stages do
			if stageAnimated(st) then
				return def, st
			end
		end
	end
	return def, def.stages[1]
end

-- The groups of vertices (indices into rec.basePos) that make one sprite
-- quad each, with each vertex's base UV.
local function spriteQuads(rec)
	local em = rec.em
	local at = {}
	for i, id in rec.vertIds do
		at[id] = i
	end
	local uvAt = {}
	for i, id in rec.uvIds do
		uvAt[id] = i
	end
	local parent = {}
	local function find(i)
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	local uvOf, normalOf = {}, {}
	for _, f in em:GetFaces() do
		local vs, uvs = em:GetFaceVertices(f), em:GetFaceUVs(f)
		local p0 = rec.basePos[at[vs[1]]]
		normalOf[at[vs[1]]] = (rec.basePos[at[vs[2]]] - p0):Cross(rec.basePos[at[vs[3]]] - p0)
		for k, v in vs do
			local i = at[v]
			parent[i] = parent[i] or i
			uvOf[i] = rec.baseUV[uvAt[uvs[k]]]
		end
		for k = 2, #vs do
			local a, b = find(at[vs[1]]), find(at[vs[k]])
			parent[b] = a
		end
	end
	local groups = {}
	for i in parent do
		local r = find(i)
		groups[r] = groups[r] or {}
		table.insert(groups[r], i)
	end
	local quads = {}
	for _, verts in groups do
		if #verts >= 3 then
			local q = { verts = verts, uv = table.create(#verts), normal = Vector3.zero }
			for k, i in verts do
				q.uv[k] = uvOf[i] or Vector2.zero
				q.normal = if normalOf[i] then normalOf[i] else q.normal
			end
			table.insert(quads, q)
		end
	end
	return quads
end

-- tr_shade_calc.c AutospriteDeform / Autosprite2Deform: each quad turned to
-- the view (autosprite: into the view plane; autosprite2: about its long
-- axis), in the part's space. The texture's U runs along the view's right,
-- V down, as RB_AddQuadStamp lays it; a quad whose winding would then face
-- away (Roblox culls back faces) is mirrored instead.
local function autosprite(rec, view: CFrame, two: boolean, pos: { Vector3 })
	local scale = rec.scale
	local eye = rec.baseCF:PointToObjectSpace(view.Position)
	local right = rec.baseCF:VectorToObjectSpace(view.RightVector)
	local up = rec.baseCF:VectorToObjectSpace(view.UpVector)
	for _, q in rec.quads do
		local verts, uv = q.verts, q.uv
		local n = #verts
		local mid, uvMid = Vector3.zero, Vector2.zero
		for k, i in verts do
			mid += rec.basePos[i] * scale
			uvMid += uv[k]
		end
		mid /= n
		uvMid /= n
		-- dP/du and dP/dv from the first three corners
		local p0, p1, p2 = rec.basePos[verts[1]] * scale, rec.basePos[verts[2]] * scale, rec.basePos[verts[3]] * scale
		local d1, d2 = uv[2] - uv[1], uv[3] - uv[1]
		local det = d1.X * d2.Y - d2.X * d1.Y
		if math.abs(det) < 1e-9 then
			continue
		end
		local e1, e2 = p1 - p0, p2 - p0
		local pu = (e1 * d2.Y - e2 * d1.Y) / det
		local pv = (e2 * d1.X - e1 * d2.X) / det
		local du, dv
		if two then
			-- keep the long axis, turn the short one to face the eye
			local uLong = pu.Magnitude >= pv.Magnitude
			local axis = (if uLong then pu else pv).Unit
			local side = axis:Cross(eye - mid)
			if side.Magnitude < 1e-6 then
				continue
			end
			side = side.Unit
			du, dv = if uLong then axis else side, if uLong then side else axis
		else
			du, dv = right, -up
		end
		-- the winding keeps its sense through the map pu -> du, pv -> dv:
		-- front faces (counter-clockwise) must end up facing the eye
		if q.normal:Dot(pu:Cross(pv)) * du:Cross(dv):Dot(eye - mid) < 0 then
			if two and pu.Magnitude < pv.Magnitude then
				du = -du
			else
				dv = -dv
			end
		end
		du, dv = du * pu.Magnitude, dv * pv.Magnitude
		for k, i in verts do
			local d = uv[k] - uvMid
			pos[i] = (mid + du * d.X + dv * d.Y) / scale
		end
	end
end

-- The stage's image at `timeSec`, and whether it's an alpha stand-in.
local function stageTexture(st, timeSec: number)
	return Assets.StageImage(st, ShaderFx.stageImage(st, timeSec))
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
				local info = meshInfo[part.Name]
				if def and st and info and info.overlay and part:GetAttribute("OAShader") == nil then
					local _, standIn = stageTexture(st, 0)
					local mode = ShaderFx.blendMode(st)
					if st.tcGen == "environment" or (not standIn and (mode == "opaque" or mode == "filter")) then
						part.Transparency = 1
						continue
					end
				end
				if def and st then
					local rec = if needsMesh(def, st) then editable(part) else nil
					rec = rec or { part = part }
					rec.def, rec.st = def, st
					rec.mode = ShaderFx.blendMode(st)
					rec.baseTransparency = rec.part.Transparency
					local img, standIn = stageTexture(st, 0)
					if standIn then
						-- the blend is in the image's alpha now, like an effect's
						-- (R3D): drawn as a plain alpha-blended texture
						rec.part.TextureID = img.id
						rec.mode = "standin"
					end
					if rec.mode == "add" then
						rec.part.Material = Enum.Material.Neon
					end
					rec.baseCF, rec.baseSize = rec.part.CFrame, rec.part.Size
					rec.offset = def.polygonoffset == true or (info ~= nil and info.overlay == true)
					if rec.em then
						for _, d in def.deforms do
							if d.type == "autosprite" or d.type == "autosprite2" then
								rec.sprite2 = d.type == "autosprite2"
								rec.quads = spriteQuads(rec)
								-- mesh space -> the part's studs (per axis; flat axes kept)
								local lo, hi = rec.basePos[1] or Vector3.zero, rec.basePos[1] or Vector3.zero
								for _, p in rec.basePos do
									lo, hi = lo:Min(p), hi:Max(p)
								end
								local ext = hi - lo
								local s = rec.baseSize
								rec.scale = Vector3.new(
									if ext.X > 1e-4 then s.X / ext.X else 1,
									if ext.Y > 1e-4 then s.Y / ext.Y else 1,
									if ext.Z > 1e-4 then s.Z / ext.Z else 1
								)
								break
							end
						end
					end
					table.insert(animated, rec)
				end
			end
		end
	end
	table.clear(movers)
	if root then
		local recOf = {}
		for _, rec in animated do
			recOf[rec.part] = rec
		end
		for _, part in root:GetDescendants() do
			local n = part:IsA("MeshPart") and tonumber(string.match(part.Name, "^model(%d+)_"))
			if n then
				local rec = recOf[part] or { part = part, baseCF = part.CFrame }
				rec.base, rec.root, rec.seen = rec.baseCF, part.Parent, false
				part.Parent = nil
				movers[n] = movers[n] or {}
				table.insert(movers[n], rec)
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

local function deform(rec, timeSec: number, view: CFrame?)
	local turned = table.clone(rec.basePos)
	if rec.quads and view then
		autosprite(rec, view, rec.sprite2, turned)
	end
	local pos = table.create(#rec.basePos)
	for i, p in rec.basePos do
		local q = turned[i]
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

-- Brush model `n` drawn this frame at the entity's origin and axis.
function WorldFx.PlaceInline(n: number, origin, axis)
	local list = movers[n]
	if list == nil then
		return
	end
	local frame = Units.toCFrame(origin, axis) * IDENTITY:Inverse()
	for _, rec in list do
		rec.baseCF = frame * rec.base
		rec.part.CFrame = rec.baseCF
		rec.seen = true
	end
end

function WorldFx.Update(refdef, timeSec: number)
	updateFog(refdef.vieworg)
	for _, list in movers do
		for _, rec in list do
			rec.part.Parent = if rec.seen then rec.root else nil
			rec.seen = false
		end
	end
	local eye = Units.toVector3(refdef.vieworg)
	local view = if refdef.viewaxis then Units.toCFrame(refdef.vieworg, refdef.viewaxis) else nil
	for _, rec in animated do
		local st = rec.st
		local part = rec.part
		if rec.offset then
			local k = 1 - OFFSET
			local s = rec.baseSize
			part.Size = Vector3.new(
				if s.X > 0.01 then s.X * k else s.X,
				if s.Y > 0.01 then s.Y * k else s.Y,
				if s.Z > 0.01 then s.Z * k else s.Z
			)
			part.CFrame = rec.baseCF.Rotation + eye + (rec.baseCF.Position - eye) * k
		end
		if st.animMap then
			local img = stageTexture(st, timeSec)
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
			part.Transparency = math.clamp(1 - a, ShaderFx.MESH_ALPHA_MIN, 1)
		elseif rec.mode == "standin" then
			r, g, b, a = ShaderFx.foldBrightness(r, g, b, a)
			part.Transparency = math.clamp(1 - a, ShaderFx.MESH_ALPHA_MIN, 1)
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
				deform(rec, timeSec, view)
			end
			if rec.mode ~= "add" and #rec.colorIds > 0 and st.rgbGen then
				rec.em:BatchSetValues(rec.colorIds, table.create(#rec.colorIds, Color3.new(r, g, b)))
			end
		end
	end
end

return WorldFx
