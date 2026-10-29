-- trap_CM_* for the client. Uses src/shared's collision model (feat/game's
-- cm port) when present; without it the world is empty (traces never hit,
-- every point is empty space), which is enough for menus and the HUD.
--
-- MarkFragments is a renderer function in Q3 (tr_marks.c, clipping decals to
-- the BSP's draw surfaces). The client has no draw surfaces (the map is baked
-- meshes), so a mark is one fragment: the projected quad itself, on the
-- plane it was aimed at. Marks can overhang an edge; see docs/client-notes.md.
local src = script.Parent.Parent.Parent
local shared = src:FindFirstChild("shared")

local function find(...)
	if shared == nil then
		return nil
	end
	for _, path in { ... } do
		local node = shared
		for name in path:gmatch("[^.]+") do
			node = node and node:FindFirstChild(name)
		end
		if node then
			return require(node)
		end
	end
	return nil
end

local CM = {}
-- The BSP lumps for a map: the place's boot code sets this (the map's
-- collision data ships with the place, see docs/client-notes.md).
CM.loadLumps = nil :: ((name: string) -> any)?
CM.hasWorld = false

-- feat/game's src/shared/Collision.luau (cm_* without the CM_ prefix)
local api = find("Collision")
local cm: any = nil
if api then
	cm = {}
	for k, v in api do
		if type(v) == "function" then
			cm["CM_" .. k] = v
		end
	end
	cm.CM_LoadMap = function(name: string)
		local lumps = CM.loadLumps and CM.loadLumps(name)
		if lumps == nil then
			CM.hasWorld = false
			return
		end
		api.LoadMap(name, lumps)
		CM.hasWorld = true
	end
end

local function emptyTrace(results, start, endp)
	results.allsolid = false
	results.startsolid = false
	results.fraction = 1
	for i = 0, 2 do
		results.endpos[i] = endp[i]
		results.plane.normal[i] = 0
	end
	results.plane.dist = 0
	results.surfaceFlags = 0
	results.contents = 0
	results.entityNum = 1023 -- ENTITYNUM_NONE
end

function CM.LoadMap(name: string)
	if cm and cm.CM_LoadMap then
		cm.CM_LoadMap(name)
	end
end

function CM.NumInlineModels(): number
	return if cm and CM.hasWorld and cm.CM_NumInlineModels then cm.CM_NumInlineModels() else 0
end

function CM.InlineModel(index: number): number
	return if cm and CM.hasWorld and cm.CM_InlineModel then cm.CM_InlineModel(index) else 0
end

function CM.TempBoxModel(mins, maxs, capsule: boolean): number
	if cm and cm.CM_TempBoxModel then
		return cm.CM_TempBoxModel(mins, maxs, capsule)
	end
	return 0
end

function CM.PointContents(p, model: number): number
	return if cm and CM.hasWorld and cm.CM_PointContents then cm.CM_PointContents(p, model) else 0
end

function CM.TransformedPointContents(p, model: number, origin, angles): number
	if cm and CM.hasWorld and cm.CM_TransformedPointContents then
		return cm.CM_TransformedPointContents(p, model, origin, angles)
	end
	return 0
end

function CM.BoxTrace(results, start, endp, mins, maxs, model: number, mask: number, capsule: boolean)
	if cm and CM.hasWorld and cm.CM_BoxTrace then
		cm.CM_BoxTrace(results, start, endp, mins, maxs, model, mask, capsule)
	else
		emptyTrace(results, start, endp)
	end
end

function CM.TransformedBoxTrace(results, start, endp, mins, maxs, model: number, mask: number, origin, angles, capsule: boolean)
	if cm and CM.hasWorld and cm.CM_TransformedBoxTrace then
		cm.CM_TransformedBoxTrace(results, start, endp, mins, maxs, model, mask, origin, angles, capsule)
	else
		emptyTrace(results, start, endp)
	end
end

function CM.InPVS(p1, p2): boolean
	if cm and cm.CM_InPVS then
		return cm.CM_InPVS(p1, p2)
	end
	return true
end

function CM.MarkFragments(numPoints, points, projection, maxPoints, pointBuffer, maxFragments, fragmentBuffer): number
	if numPoints > maxPoints or maxFragments < 1 then
		return 0
	end
	for i = 0, numPoints - 1 do
		local p = pointBuffer[i]
		if p == nil then
			p = { [0] = 0, 0, 0 }
			pointBuffer[i] = p
		end
		p[0], p[1], p[2] = points[i][0], points[i][1], points[i][2]
	end
	fragmentBuffer[0].firstPoint = 0
	fragmentBuffer[0].numPoints = numPoints
	return 1
end

return CM
