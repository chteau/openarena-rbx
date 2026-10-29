-- The cgame's global namespace: every non-static C global of cgame (state
-- and functions) lives here under its C name. Modules register their
-- functions into it and call each other through it at call time.
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)

local G = {}

G.cg = T.cg_t()
G.cgs = T.cgs_t()
G.cg_entities = table.create(0)
for i = 0, C.MAX_GENTITIES - 1 do
	G.cg_entities[i] = T.centity_t()
end
G.cg_weapons = {}
for i = 0, C.MAX_WEAPONS - 1 do
	G.cg_weapons[i] = T.weaponInfo_t()
end
G.cg_items = {}
for i = 0, C.MAX_ITEMS - 1 do
	G.cg_items[i] = T.itemInfo_t()
end

return G
