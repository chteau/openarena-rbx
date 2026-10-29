-- bg_misc / bg_pmove for the client. Uses src/shared's port (feat/game) when
-- it is present in the tree, otherwise the client's own bg_misc port in
-- fallback/. Both expose the C names (BG_EvaluateTrajectory, bg_itemlist, ...).
-- Without src/shared there is no Pmove: BG.Pmove is nil and cg_predict falls
-- back to interpolating the server's playerState.
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

local BG = {}
-- feat/game's src/shared/BG.luau is the whole both-games API in one module
local api = find("BG")
if api == nil then
	api = find("bg_misc", "bg.bg_misc") or require(script.Parent.fallback.bg_misc)
	local pmove = find("bg_pmove", "bg.bg_pmove")
	if pmove then
		api.Pmove = pmove.Pmove
		api.PM_UpdateViewAngles = pmove.PM_UpdateViewAngles
	end
end
for k, v in api do
	BG[k] = v
end
BG.hasPmove = BG.Pmove ~= nil

if BG.PM_UpdateViewAngles == nil then
	-- bg_pmove.c PM_UpdateViewAngles, for the no-pmove fallback (cg_predict
	-- still applies local view angles while it interpolates)
	local C = require(script.Parent.Parent.q.Consts)
	local function short(n: number): number
		n = bit32.band(n, 0xffff)
		return if n >= 0x8000 then n - 0x10000 else n
	end
	function BG.PM_UpdateViewAngles(ps, cmd)
		if ps.pm_type == C.PM_INTERMISSION or ps.pm_type == C.PM_SPINTERMISSION then
			return -- no view changes at all
		end
		if ps.pm_type ~= C.PM_SPECTATOR and ps.stats[C.STAT_HEALTH] <= 0 then
			return -- no view changes at all
		end
		-- circularly clamp the angles with deltas
		for i = 0, 2 do
			local temp = short(cmd.angles[i] + ps.delta_angles[i])
			if i == C.PITCH then
				-- don't let the player look up or down more than 90 degrees
				if temp > 16000 then
					ps.delta_angles[i] = 16000 - cmd.angles[i]
					temp = 16000
				elseif temp < -16000 then
					ps.delta_angles[i] = -16000 - cmd.angles[i]
					temp = -16000
				end
			end
			ps.viewangles[i] = temp * (360.0 / 65536)
		end
	end
end
return BG
