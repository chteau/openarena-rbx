--[[
Collision model API (Luau port of ioquake3's qcommon/cm_*.c, GPL-2.0).

	Collision.LoadMap(name, lumps)           -- lumps from cm/bsp.luau or a blob adapter
	Collision.BoxTrace(results, start, end, mins, maxs, model, brushmask, capsule?)
	Collision.TransformedBoxTrace(results, start, end, mins, maxs, model, brushmask, origin, angles, capsule?)
	Collision.PointContents(p, model) / TransformedPointContents(p, model, origin, angles)
	Collision.TempBoxModel(mins, maxs, capsule?) -> handle
	Collision.InlineModel(i), ModelBounds(h, mins, maxs), NumInlineModels(), EntityString()
	Collision.PointLeafnum(p), LeafCluster(l), LeafArea(l), BoxLeafnums(mins, maxs, list, max)
	Collision.ClusterPVS(cluster) -> (buffer, offset), AreasConnected(a1, a2),
	Collision.AdjustAreaPortalState(a1, a2, open), WriteAreaBits(buf, area)

Vectors are 0-based {[0]=x, y, z} in Quake units; results is a trace_t from
structs.luau (filled in place, like the C out parameter).
]]

local L = require("./cm/cm_local")
require("./cm/cm_test")
require("./cm/cm_patch")
require("./cm/cm_trace")
require("./cm/cm_load")

local C = {
	state = L,
	cvars = L.cvars,
	counters = L.counters,
	BOX_MODEL_HANDLE = L.BOX_MODEL_HANDLE,
	CAPSULE_MODEL_HANDLE = L.CAPSULE_MODEL_HANDLE,
}

for k, v in L do
	if type(v) == "function" and string.sub(k, 1, 3) == "CM_" then
		C[string.sub(k, 4)] = v
	end
end

return C
