-- 3D half of the renderer (RE_ClearScene / RE_AddRefEntityToScene /
-- RE_AddPolyToScene / RE_AddLightToScene / RE_RenderScene) on Roblox
-- instances. The cgame rebuilds its scene every frame, so every kind of
-- refEntity draws from a pool that is reused in submission order and hidden
-- when a frame doesn't use it.
--
--   RT_MODEL      vertex-animated MD3 -> one EditableMesh-backed MeshPart per
--                 surface (positions lerped between oldframe and frame), or
--                 a baked MeshPart for a static model the converter uploaded
--   RT_SPRITE     BillboardGui + ImageLabel (radius, rotation, colour)
--   RT_BEAM, RT_RAIL_CORE, RT_RAIL_RINGS, RT_LIGHTNING
--                 Beam between two Attachments, textured with the shader
--   polys         (marks, particles) a thin Part with a Decal per quad
--   dlights       PointLight
--   RenderScene   the main view drives workspace.CurrentCamera (Scriptable);
--                 an RDF_NOWORLDMODEL scene (HUD heads, menu models) renders
--                 into a ViewportFrame at refdef's rectangle in the 2D layer
-- Blend modes Roblox lacks are approximated; see docs/client-notes.md.
local C = require(script.Parent.Parent.q.Consts)
local Assets = require(script.Parent.Assets)
local ShaderFx = require(script.Parent.ShaderFx)
local Units = require(script.Parent.Units)
local Md3 = require(script.Parent.Md3)
local LightGrid = require(script.Parent.LightGrid)
local R2D = require(script.Parent.R2D)

local R3D = {}

R3D.worldRoot = nil :: Instance? -- folder in workspace for the main scene
R3D.camera = nil :: Camera? -- workspace.CurrentCamera
R3D.noEditableMesh = false
R3D.mapName = ""

local AssetService = game:GetService("AssetService")
local ContentProvider = game:GetService("ContentProvider")

-- scene being built since the last ClearScene/RenderScene ----------------
local entities: { any } = {}
local polys: { any } = {}
local lights: { any } = {}

function R3D.ClearScene()
	table.clear(entities)
	table.clear(polys)
	table.clear(lights)
end

local function copyVec(v)
	return { [0] = v[0], [1] = v[1], [2] = v[2] }
end

function R3D.AddRefEntity(re)
	-- the cgame reuses its refEntity_t, so keep what the renderer needs now
	table.insert(entities, {
		reType = re.reType,
		renderfx = re.renderfx,
		hModel = re.hModel,
		origin = copyVec(re.origin),
		oldorigin = copyVec(re.oldorigin),
		axis = { [0] = copyVec(re.axis[0]), [1] = copyVec(re.axis[1]), [2] = copyVec(re.axis[2]) },
		nonNormalizedAxes = re.nonNormalizedAxes,
		frame = re.frame,
		oldframe = re.oldframe,
		backlerp = re.backlerp,
		skinNum = re.skinNum,
		customSkin = re.customSkin,
		customShader = re.customShader,
		shaderRGBA = { re.shaderRGBA[0], re.shaderRGBA[1], re.shaderRGBA[2], re.shaderRGBA[3] },
		shaderTime = re.shaderTime,
		radius = re.radius,
		rotation = re.rotation,
	})
end

function R3D.AddPoly(shader: number, numVerts: number, verts)
	local p = { shader = shader, verts = {} }
	for i = 0, numVerts - 1 do
		local v = verts[i]
		p.verts[i + 1] = {
			xyz = copyVec(v.xyz),
			st = { v.st[0], v.st[1] },
			rgba = { v.modulate[0], v.modulate[1], v.modulate[2], v.modulate[3] },
		}
	end
	table.insert(polys, p)
end

function R3D.AddLight(org, intensity: number, r: number, g: number, b: number, additive: boolean)
	table.insert(lights, { origin = copyVec(org), intensity = intensity, r = r, g = g, b = b })
end

function R3D.LightForPoint(point, ambient, directed, dir): number
	if LightGrid.LightForPoint(point, ambient, directed, dir) then
		return 1
	end
	-- no grid (map not converted yet, or edit mode): a neutral light
	for i = 0, 2 do
		ambient[i], directed[i], dir[i] = 64, 128, 0
	end
	dir[2] = 1
	return 0
end

-- pools -----------------------------------------------------------------------
-- A "target" is where a scene renders: the world folder or a ViewportFrame.
-- Each target keeps per-kind pools; `cursor` counts what this frame used.
local targets: { [Instance]: any } = {}
local viewports: { ViewportFrame } = {}
local viewportsUsed = 0

local function target(root: Instance)
	local t = targets[root]
	if t == nil then
		t = { root = root, models = {}, sprites = {}, beams = {}, polys = {}, lights = {}, cursor = {} }
		targets[root] = t
	end
	return t
end

local function white(): Vector3
	return Vector3.one
end

local function color01(rgba): Color3
	return Color3.new(rgba[1] / 255, rgba[2] / 255, rgba[3] / 255)
end

-- shader -> (image id or nil, blend mode, colour/alpha from the first stage,
-- whether the image is an alpha-blended stand-in for the blend mode)
local function shaderLook(h: number, rgba, timeSec: number, light: { number }?)
	local sh = Assets.Shader(h)
	if sh == nil then
		return nil, "opaque", 1, 1, 1, 1
	end
	local stages = ShaderFx.drawStages(sh)
	local st = stages[1]
	if st == nil then
		return nil, "opaque", 1, 1, 1, 1
	end
	local vert = { rgba[1] / 255, rgba[2] / 255, rgba[3] / 255, rgba[4] / 255 }
	local r, g, b, a = ShaderFx.stageColor(st, timeSec, vert, light)
	local img, standIn = Assets.StageImage(st, ShaderFx.stageImage(st, timeSec))
	if standIn then
		r, g, b, a = ShaderFx.foldBrightness(r, g, b, a)
	end
	return img and img.id, ShaderFx.blendMode(st), r, g, b, a, standIn
end

-- A MeshPart draws untextured, a plain white shape, until its TextureID has
-- downloaded: the first use of an effect (a bullet impact) flashed white.
-- Its surfaces stay hidden until the image is in.
local textures: { [string]: boolean } = {}
local function textureReady(id: string): boolean
	local state = textures[id]
	if state then
		return true
	end
	local ok, status = pcall(ContentProvider.GetAssetFetchStatus, ContentProvider, id)
	if not ok or (status ~= Enum.AssetFetchStatus.None and status ~= Enum.AssetFetchStatus.Loading) then
		-- loaded, failed for good, or no way to tell: draw as it is
		textures[id] = true
		return true
	end
	if state == nil then
		textures[id] = false
		task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, { id })
	end
	return false
end

local function applyBlend(part: BasePart, mode: string, a: number)
	if mode == "add" then
		-- no additive blending on Roblox: glow + see-through stands in
		part.Material = Enum.Material.Neon
		part.Transparency = math.clamp(1 - a * 0.6, 0, 1)
	elseif mode == "alpha" or mode == "filter" then
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = math.clamp(1 - a, 0, 1)
	else
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 0
	end
end

-- The client's EditableMesh budget is small and charges every growable mesh
-- heavily: an empty CreateEditableMesh starts failing ("memory budget") after
-- a few dozen. Each md3 surface is built growable once, copied into a
-- fixed-size template (charged by its size), and every instance draws a
-- fixed-size copy of that; copies keep the vertex and colour ids.
local templates: { [string]: { em: EditableMesh, ids: { number }, colors: { number } } } = {}
local function surfaceTemplate(model, s)
	local key = model.name .. "#" .. s.name
	local tpl = templates[key]
	if tpl then
		return tpl
	end
	local em = AssetService:CreateEditableMesh({})
	if em == nil then
		error("EditableMesh memory budget reached")
	end
	local ids, colors = table.create(s.numVerts), table.create(s.numVerts)
	for v = 0, s.numVerts - 1 do
		local x, y, z = Md3.Vertex(s, 0, v)
		ids[v + 1] = em:AddVertex(Vector3.new(-y / 8, z / 8, -x / 8))
	end
	local uvs = table.create(s.numVerts)
	for v = 0, s.numVerts - 1 do
		local u, t = Md3.TexCoord(s, v)
		uvs[v + 1] = em:AddUV(Vector2.new(u, t))
		colors[v + 1] = em:AddColor(Color3.new(1, 1, 1), 1)
	end
	for t = 0, s.numTriangles - 1 do
		local a, b, c = Md3.Triangle(s, t)
		-- Q3 front faces wind clockwise, Roblox's counter-clockwise
		local f = em:AddTriangle(ids[a + 1], ids[c + 1], ids[b + 1])
		em:SetFaceUVs(f, { uvs[a + 1], uvs[c + 1], uvs[b + 1] })
		em:SetFaceColors(f, { colors[a + 1], colors[c + 1], colors[b + 1] })
	end
	local ok, fixed = pcall(function()
		return AssetService:CreateEditableMeshAsync(Content.fromObject(em), { FixedSize = true })
	end)
	em:Destroy()
	if not ok then
		error(fixed, 0)
	end
	tpl = { em = fixed, ids = ids, colors = colors }
	templates[key] = tpl
	return tpl
end

-- RT_MODEL ---------------------------------------------------------------------
-- One pooled instance per (model, nth use this frame): a Model with a part per
-- surface; vertex-animated surfaces own an EditableMesh.
local function buildSurface(model, s, parent: Instance)
	local surf = { s = s }
	local baked = Assets.index.meshes and Assets.index.meshes[model.name .. "#" .. s.name]
	if baked then
		-- { id, c }: the place's index (place/assemble.py). The converter bakes
		-- a static MD3 in world axes, (x, z, -y) / 8, centred on its box
		-- centre `c`; Roblox's importer turns the scene 180 degrees about Y.
		-- The part's frame relative to the model's (EditableMesh axes,
		-- (-y, z, -x) / 8) is then Ry(90) c, turned 270 degrees about Y.
		local id = baked
		if type(baked) == "table" then
			id = baked.id
			local c = baked.c
			surf.offset = CFrame.new(c[3], c[2], -c[1]) * CFrame.Angles(0, 1.5 * math.pi, 0)
		end
		local mp = AssetService:CreateMeshPartAsync(Content.fromUri(id))
		mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch = true, false, false, false
		mp.CastShadow = false
		mp.Parent = parent
		surf.part = mp
		surf.static = true
		return surf
	end
	-- EditableMesh exists only in a running client (not in rbx-native's edit
	-- runtime, not under lune), and only when the experience enables it in its
	-- Security settings (creating one works there, using it errors "not
	-- accessible"): without it no surface is drawn. Any other error is this
	-- surface's own ("Invalid mesh."), and only it is left out
	-- a surface with no triangles can't be a MeshPart ("Mesh has no faces",
	-- models/misc/telep's tube)
	if R3D.noEditableMesh or s.numTriangles == 0 then
		return nil
	end
	local ok, err = pcall(function()
		local tpl = surfaceTemplate(model, s)
		local em = AssetService:CreateEditableMeshAsync(Content.fromObject(tpl.em), { FixedSize = true })
		local ids, colors = tpl.ids, tpl.colors
		local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch = true, false, false, false
		mp.CastShadow = false
		-- vertices are in the part's object space: keep the part at 1:1 scale
		mp.Size = mp.MeshSize
		mp.Parent = parent
		surf.part, surf.em, surf.ids, surf.colorIds = mp, em, ids, colors
	end)
	if not ok then
		if string.find(tostring(err), "not accessible", 1, true) then
			R3D.noEditableMesh = true
			warn("R3D: no EditableMesh here, MD3 surfaces won't draw: " .. tostring(err))
		else
			warn(("R3D: %s#%s not drawn: %s"):format(model.name, s.name, tostring(err)))
		end
		return nil
	end
	surf.colorKey = ""
	return surf
end

local function modelInstance(t, hModel: number)
	local list = t.models[hModel]
	if list == nil then
		list = {}
		t.models[hModel] = list
	end
	local n = (t.cursor["m" .. hModel] or 0) + 1
	t.cursor["m" .. hModel] = n
	local inst = list[n]
	if inst == nil then
		local model = Assets.Model(hModel)
		if model == nil then
			return nil
		end
		-- parented by hideUnused once drawn: building yields, and its parts
		-- would show untextured at the origin meanwhile
		local folder = Instance.new("Model")
		folder.Name = model.name:match("[^/]+$") or "md3"
		inst = { model = model, folder = folder, surfaces = {} }
		for i, s in model.surfaces do
			inst.surfaces[i] = buildSurface(model, s, folder)
		end
		list[n] = inst
	end
	inst.used = true
	return inst
end

local function surfaceShader(e, s): number
	if e.customShader ~= 0 then
		return e.customShader
	end
	if e.customSkin ~= 0 then
		local skin = Assets.Skin(e.customSkin)
		if skin and skin[s.name] then
			return skin[s.name]
		end
	end
	return if s.shaders[1] then Assets.RegisterShader(s.shaders[1], true, true) else 0
end

-- rgbGen lightingDiffuse's light for a whole entity (R_SetupEntityLighting):
-- the light grid at its origin, the directed part taken at half strength
-- (an average facing) instead of per vertex, doubled for the map's
-- overbright bits as the lightmaps baked into the atlas are
local function entityLight(e): { number }
	local amb, dir, ldir = { [0] = 0, 0, 0 }, { [0] = 0, 0, 0 }, { [0] = 0, 0, 0 }
	R3D.LightForPoint(e.origin, amb, dir, ldir)
	local min = if bit32.band(e.renderfx, C.RF_MINLIGHT) ~= 0 then 32 else 0
	local out = table.create(3)
	for i = 0, 2 do
		out[i + 1] = math.clamp(2 * (amb[i] + min + 0.5 * dir[i]) / 255, 0, 1)
	end
	return out
end

local function drawModel(t, e, timeSec: number, firstPerson: boolean)
	local inst = modelInstance(t, e.hModel)
	if inst == nil then
		return
	end
	local model = inst.model
	local cf, scale = Units.toCFrameScaled(e.origin, e.axis)
	if not e.nonNormalizedAxes then
		scale = Vector3.one
	end
	local nf = model.numFrames
	local frame = if nf > 0 then math.clamp(e.frame, 0, nf - 1) else 0
	local oldframe = if nf > 0 then math.clamp(e.oldframe, 0, nf - 1) else 0
	local back = e.backlerp
	local light = nil
	for _, surf in inst.surfaces do
		local part: MeshPart = surf.part
		part.CFrame = if surf.offset then cf * surf.offset else cf
		part.Parent = inst.folder
		local sh = surfaceShader(e, surf.s)
		light = light or entityLight(e)
		local img, mode, r, g, b, a, standIn = shaderLook(sh, e.shaderRGBA, timeSec - (e.shaderTime or 0), light)
		if img and part.TextureID ~= img then
			part.TextureID = img
		end
		applyBlend(part, if standIn then "alpha" else mode, a)
		if img and not textureReady(img) then
			part.Transparency = 1
		end
		-- RF_DEPTHHACK (view weapon) and first-person-only parts can't skip the
		-- depth test on Roblox; they're drawn normally
		part.LocalTransparencyModifier = 0
		if surf.em then
			-- re-lerp the vertices only when the pose changed
			local key = frame .. "/" .. oldframe .. "/" .. back .. "/" .. tostring(scale)
			if surf.poseKey ~= key then
				surf.poseKey = key
				local s = surf.s
				local pos = table.create(s.numVerts)
				local sx, sy, sz = scale.X / 8, scale.Y / 8, scale.Z / 8
				for v = 0, s.numVerts - 1 do
					local x1, y1, z1 = Md3.Vertex(s, frame, v)
					if back ~= 0 then
						local x0, y0, z0 = Md3.Vertex(s, oldframe, v)
						x1 = x1 + (x0 - x1) * back
						y1 = y1 + (y0 - y1) * back
						z1 = z1 + (z0 - z1) * back
					end
					pos[v + 1] = Vector3.new(-y1 * sx, z1 * sy, -x1 * sz)
				end
				surf.em:BatchSetValues(surf.ids, pos)
			end
			local ck = string.format("%.3f,%.3f,%.3f", r, g, b)
			if surf.colorKey ~= ck then
				surf.colorKey = ck
				local cols = table.create(#surf.colorIds, Color3.new(r, g, b))
				surf.em:BatchSetValues(surf.colorIds, cols)
			end
		else
			part.Color = Color3.new(r, g, b)
		end
	end
end

-- RT_SPRITE --------------------------------------------------------------------
local function drawSprite(t, e, timeSec: number)
	local n = (t.cursor.sprite or 0) + 1
	t.cursor.sprite = n
	local sp = t.sprites[n]
	if sp == nil then
		local att = Instance.new("Attachment")
		local bb = Instance.new("BillboardGui")
		bb.LightInfluence = 0
		bb.ResetOnSpawn = false
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Parent = bb
		sp = { att = att, bb = bb, img = img }
		t.sprites[n] = sp
	end
	local anchor = t.anchor
	sp.att.Parent = anchor
	sp.att.WorldPosition = Units.toVector3(e.origin)
	sp.bb.Adornee = sp.att
	sp.bb.Parent = t.guiRoot
	sp.bb.Enabled = true
	local d = e.radius * 2 / 8
	sp.bb.Size = UDim2.fromScale(d, d)
	local id, mode, r, g, b, a = shaderLook(e.customShader, e.shaderRGBA, timeSec - (e.shaderTime or 0))
	sp.img.Image = id or ""
	sp.img.ImageColor3 = Color3.new(r, g, b)
	sp.img.ImageTransparency = 1 - a
	sp.img.Rotation = e.rotation
	sp.bb.AlwaysOnTop = false
end

-- beams ------------------------------------------------------------------------
local function drawBeam(t, e, timeSec: number)
	local n = (t.cursor.beam or 0) + 1
	t.cursor.beam = n
	local bm = t.beams[n]
	if bm == nil then
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.FaceCamera = true
		beam.Segments = 1
		bm = { a0 = a0, a1 = a1, beam = beam }
		t.beams[n] = bm
	end
	bm.a0.Parent, bm.a1.Parent = t.anchor, t.anchor
	bm.a0.WorldPosition = Units.toVector3(e.origin)
	bm.a1.WorldPosition = Units.toVector3(e.oldorigin)
	bm.beam.Parent = t.anchor
	bm.beam.Enabled = true
	local id, mode, r, g, b, a = shaderLook(e.customShader, e.shaderRGBA, timeSec - (e.shaderTime or 0))
	bm.beam.Texture = id or ""
	bm.beam.Color = ColorSequence.new(Color3.new(r, g, b))
	bm.beam.Transparency = NumberSequence.new(1 - a)
	bm.beam.LightEmission = if mode == "add" then 1 else 0
	bm.beam.LightInfluence = 0
	-- rail core / lightning: width is in units (cg_railCoreWidth, ...)
	local width = (if e.reType == C.RT_RAIL_CORE or e.reType == C.RT_RAIL_RINGS then 6 else (e.radius ~= 0 and e.radius or 8)) / 8
	bm.beam.Width0, bm.beam.Width1 = width, width
	local len = (bm.a1.WorldPosition - bm.a0.WorldPosition).Magnitude
	bm.beam.TextureMode = Enum.TextureMode.Wrap
	bm.beam.TextureLength = math.max(len / 4, 0.1)
	bm.beam.TextureSpeed = if e.reType == C.RT_LIGHTNING then 2 else 0
end

-- polys (marks, particles) -------------------------------------------------------
local function drawPoly(t, p, timeSec: number)
	local v = p.verts
	if #v < 3 then
		return
	end
	local n = (t.cursor.poly or 0) + 1
	t.cursor.poly = n
	local pp = t.polys[n]
	if pp == nil then
		local part = Instance.new("Part")
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		part.Transparency = 1
		part.CastShadow = false
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Front
		decal.Parent = part
		pp = { part = part, decal = decal }
		t.polys[n] = pp
	end
	-- the quad's frame: centre, edge directions from vertex 1 -> 2 and 1 -> n
	local p1, p2, pn = Units.toVector3(v[1].xyz), Units.toVector3(v[2].xyz), Units.toVector3(v[#v].xyz)
	local centre = Vector3.zero
	for i = 1, #v do
		centre += Units.toVector3(v[i].xyz)
	end
	centre /= #v
	local ex, ey = p2 - p1, pn - p1
	local normal = ex:Cross(ey)
	if normal.Magnitude < 1e-6 then
		return
	end
	normal = normal.Unit
	local right = ex.Unit
	local up = normal:Cross(right).Unit
	-- Front face = -Z: look along -normal so the decal faces out of the surface
	pp.part.CFrame = CFrame.fromMatrix(centre + normal * 0.02, right, up, normal)
	pp.part.Size = Vector3.new(math.max(ex.Magnitude, 0.05), math.max(ey.Magnitude, 0.05), 0.01)
	pp.part.Parent = t.root
	local rgba = { v[1].rgba[1], v[1].rgba[2], v[1].rgba[3], v[1].rgba[4] }
	local id, mode, r, g, b, a = shaderLook(p.shader, rgba, timeSec)
	pp.decal.Texture = id or ""
	pp.decal.Color3 = Color3.new(r, g, b)
	pp.decal.Transparency = 1 - a
end

-- dlights -------------------------------------------------------------------------
local function drawLight(t, l)
	local n = (t.cursor.light or 0) + 1
	t.cursor.light = n
	local pl = t.lights[n]
	if pl == nil then
		local att = Instance.new("Attachment")
		local light = Instance.new("PointLight")
		light.Shadows = false
		light.Parent = att
		pl = { att = att, light = light }
		t.lights[n] = pl
	end
	pl.att.Parent = t.anchor
	pl.att.WorldPosition = Units.toVector3(l.origin)
	pl.light.Enabled = true
	pl.light.Color = Color3.new(math.clamp(l.r, 0, 1), math.clamp(l.g, 0, 1), math.clamp(l.b, 0, 1))
	pl.light.Range = math.clamp(l.intensity / 8, 0, 60)
	pl.light.Brightness = 2
end

-- frame lifecycle -------------------------------------------------------------------
local function resetTarget(t)
	table.clear(t.cursor)
	for _, list in t.models do
		for _, inst in list do
			inst.used = false
		end
	end
end

local function hideUnused(t)
	for _, list in t.models do
		for _, inst in list do
			if not inst.used and inst.folder.Parent then
				inst.folder.Parent = nil
			elseif inst.used and inst.folder.Parent ~= t.root then
				inst.folder.Parent = t.root
			end
		end
	end
	for i = (t.cursor.sprite or 0) + 1, #t.sprites do
		t.sprites[i].bb.Enabled = false
	end
	for i = (t.cursor.beam or 0) + 1, #t.beams do
		t.beams[i].beam.Enabled = false
	end
	for i = (t.cursor.poly or 0) + 1, #t.polys do
		t.polys[i].part.Parent = nil
	end
	for i = (t.cursor.light or 0) + 1, #t.lights do
		t.lights[i].light.Enabled = false
	end
end

local frameTargets: { any } = {}

function R3D.BeginFrame()
	require(script.Parent.Avatar).BeginFrame()
	for _, t in targets do
		resetTarget(t)
	end
	viewportsUsed = 0
	table.clear(frameTargets)
end

function R3D.EndFrame()
	for _, t in targets do
		hideUnused(t)
	end
	require(script.Parent.Avatar).EndFrame()
	for i = viewportsUsed + 1, #viewports do
		viewports[i].Visible = false
	end
end

local function anchorFor(t)
	if t.anchor == nil then
		local p = Instance.new("Part")
		p.Name = "Anchor"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Transparency = 1
		p.Size = Vector3.one
		p.CFrame = CFrame.identity
		p.Parent = t.root
		t.anchor = p
	end
	return t.anchor
end

local function fillTarget(t, refdef, timeSec: number)
	anchorFor(t)
	local firstPerson = true
	for _, e in entities do
		local ty = e.reType
		local fx = e.renderfx
		-- RF_THIRD_PERSON: only in mirrors/portals, never the main view
		if bit32.band(fx, C.RF_THIRD_PERSON) == 0 or bit32.band(refdef.rdflags, C.RDF_NOWORLDMODEL) ~= 0 then
			if ty == C.RT_MODEL then
				drawModel(t, e, timeSec, firstPerson)
			elseif ty == C.RT_SPRITE then
				drawSprite(t, e, timeSec)
			elseif ty == C.RT_BEAM or ty == C.RT_RAIL_CORE or ty == C.RT_RAIL_RINGS or ty == C.RT_LIGHTNING then
				drawBeam(t, e, timeSec)
			end
		end
	end
	for _, p in polys do
		drawPoly(t, p, timeSec)
	end
	for _, l in lights do
		drawLight(t, l)
	end
end

local viewportCams: { [Instance]: Camera } = {}
local function viewportFor(refdef)
	viewportsUsed += 1
	local vf = viewports[viewportsUsed]
	if vf == nil then
		vf = Instance.new("ViewportFrame")
		vf.Name = "Scene" .. viewportsUsed
		vf.BackgroundTransparency = 1
		vf.BorderSizePixel = 0
		vf.Ambient = Color3.fromRGB(160, 160, 160)
		vf.LightColor = Color3.fromRGB(255, 255, 255)
		local cam = Instance.new("Camera")
		cam.Parent = vf
		vf.CurrentCamera = cam
		viewportCams[vf] = cam
		local world = Instance.new("WorldModel")
		world.Parent = vf
		viewports[viewportsUsed] = vf
	end
	vf.Parent = R2D.root
	vf.Visible = true
	vf.ZIndex = R2D.NextZ()
	vf.Position = UDim2.fromOffset(refdef.x, refdef.y)
	vf.Size = UDim2.fromOffset(refdef.width, refdef.height)
	return vf
end

-- RE_RenderScene
function R3D.RenderScene(refdef)
	local timeSec = refdef.time * 0.001
	local cf = Units.toCFrame(refdef.vieworg, refdef.viewaxis)
	if bit32.band(refdef.rdflags, C.RDF_NOWORLDMODEL) ~= 0 then
		local vf = viewportFor(refdef)
		local cam = viewportCams[vf]
		cam.CFrame = cf
		cam.FieldOfView = refdef.fov_y
		local t = target(vf:FindFirstChildOfClass("WorldModel") :: Instance)
		t.guiRoot = vf
		fillTarget(t, refdef, timeSec)
	else
		local cam = R3D.camera or workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = cf
			cam.FieldOfView = refdef.fov_y
		end
		if R3D.worldRoot then
			local t = target(R3D.worldRoot)
			t.guiRoot = R3D.worldRoot
			fillTarget(t, refdef, timeSec)
			local WorldFx = require(script.Parent.WorldFx)
			WorldFx.Update(refdef, timeSec)
		end
	end
	R3D.ClearScene()
end

function R3D.LoadWorldMap(name: string)
	R3D.mapName = name
	LightGrid.Load(name)
	local WorldFx = require(script.Parent.WorldFx)
	WorldFx.Load(name)
end

return R3D
