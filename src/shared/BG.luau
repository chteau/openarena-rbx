--[[
Both-games API (Luau port of OpenArena 0.8.8's bg_pmove.c, bg_slidemove.c and
bg_misc.c at gamecode 9e0f0c0, GPL-2.0). Used by the server for authoritative movement and by
the client for prediction; both must run it on identical inputs.

	BG.Pmove(pm)                         -- pm = structs.pmove_t(); pm.ps, pm.cmd, pm.trace, pm.pointcontents
	BG.PM_UpdateViewAngles(ps, cmd)
	BG.bg_itemlist[i], BG.bg_numItems     -- 0-based item table; it.index == ITEM_INDEX(it)
	BG.BG_FindItem / ForWeapon / ForPowerup / ForHoldable
	BG.BG_CanItemBeGrabbed(gametype, es, ps), BG.BG_PlayerTouchesItem(ps, es, atTime)
	BG.BG_EvaluateTrajectory(tr, atTime, out), BG.BG_EvaluateTrajectoryDelta(tr, atTime, out)
	BG.BG_AddPredictableEventToPlayerstate(ev, parm, ps), BG.BG_TouchJumpPad(ps, es)
	BG.BG_PlayerStateToEntityState(ps, es, snap), BG.BG_PlayerStateToEntityStateExtraPolate(ps, es, time, snap)
	BG.eventnames, BG.BG_TeamName(team)

pm.trace(results, start, mins, maxs, end, passEntityNum, contentmask) fills a
trace_t; pm.pointcontents(point, passEntityNum) returns contents. Vectors are
0-based {[0]=x, y, z} in Quake units and axes (Z up).
]]

local P = require("./bg/bg_pmove")
local M = require("./bg/bg_misc")

local BG = {}
for k, v in M do
	BG[k] = v
end
BG.Pmove = P.Pmove
BG.PmoveSingle = P.PmoveSingle
BG.PM_UpdateViewAngles = P.PM_UpdateViewAngles
BG.state = P -- pm / pml / tunables (pm_accelerate, ...), as bg_local.h

return BG
