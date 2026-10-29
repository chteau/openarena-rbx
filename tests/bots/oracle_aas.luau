-- Replays the C oracle's AAS queries (tools/oracle-bots) through the Luau
-- botlib and diffs every output bit for bit.
--   lune run tests/bots/oracle_aas.luau [maps...] [--n N]
local process = require("@lune/process")
local B = require("../../src/server/bot/botlib/botlib")
local BC = require("../../src/server/bot/botlib/consts")
local SB = require("../../src/server/bot/botlib/structs")
local BI = require("./botimport")
local Qm = require("../../src/shared/q_math")

local maps, N = {}, 2000
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--n" then
		N = tonumber(process.args[i + 1]) :: number
		i += 1
	else
		table.insert(maps, a)
	end
	i += 1
end
if #maps == 0 then
	maps = { "oa_dm1", "oa_ctf2", "am_thornish", "oa_bases7" }
end

local fb = buffer.create(4)
local function hf(h: string): number
	buffer.writeu32(fb, 0, tonumber(h, 16) :: number)
	return buffer.readf32(fb, 0)
end
local function fh(v: number): string
	buffer.writef32(fb, 0, v)
	return string.format("%08x", buffer.readu32(fb, 0))
end
local function vh(t, k)
	return { [0] = hf(t[k]), hf(t[k + 1]), hf(t[k + 2]) }
end
local function vs(v): string
	return fh(v[0]) .. " " .. fh(v[1]) .. " " .. fh(v[2])
end
local function words(line: string)
	local t = {}
	for w in string.gmatch(line, "%S+") do
		table.insert(t, w)
	end
	return t
end
local function oracle(map: string, ...): { string }
	local r = process.exec(process.cwd .. "/build/oracle-bots/oracle-bots",
		{ "maps/" .. map .. ".bsp", "maps/" .. map .. ".aas", ... },
		{ cwd = process.cwd .. "/build/oracle-bots" })
	assert(r.ok, r.stderr)
	local lines = {}
	for l in string.gmatch(r.stdout, "[^\n]+") do
		table.insert(lines, l)
	end
	return lines
end

local failures = 0
local function report(map, kind, total, bad, first)
	print(string.format("%-12s %-8s %6d checked, %d mismatch%s", map, kind, total, bad, if bad == 1 then "" else "es"))
	if first then
		print("  first mismatch: " .. first)
	end
	failures += bad
end

for _, map in maps do
	-- the oracle runs from build/oracle-bots, so its relative paths match ours
	local info = words(oracle(map, "info")[1])
	BI.loadMap(map)
	local export = B.GetBotLibAPI(BC.BOTLIB_API_VERSION, BI.new({ quiet = process.env.BOTS_VERBOSE == nil }))
	export.BotLibVarSet("sv_mapChecksum", info[2])
	export.BotLibVarSet("maxclients", "64")
	export.BotLibVarSet("maxentities", "1024")
	assert(export.BotLibSetup() == BC.BLERR_NOERROR, "BotLibSetup failed")
	assert(export.BotLibLoadMap(map) == BC.BLERR_NOERROR, "BotLibLoadMap failed")
	local f = 0
	while export.aas.AAS_Initialized() == 0 and f < 10 do
		export.BotLibStartFrame(Qm.f(f * 0.1))
		f += 1
	end
	local aasworld = B.aasworld
	local mine = string.format("I %s %d %d %d %d %d", info[2], aasworld.numareas, aasworld.reachabilitysize,
		aasworld.numclusters, aasworld.numportals, aasworld.numreachabilityareas)
	report(map, "info", 1, if mine == table.concat(info, " ") then 0 else 1, if mine ~= table.concat(info, " ") then mine else nil)

	-- reachability list
	do
		local bad, first, lines = 0, nil, oracle(map, "reach")
		for _, l in lines do
			local w = words(l)
			local r = aasworld.reachability[tonumber(w[2]) :: number]
			local m = string.format("R %s %d %d %d %s %s %d %d", w[2], r.areanum, r.facenum, r.edgenum, vs(r.start), vs(r.end_),
				r.traveltype, r.traveltime)
			if m ~= l then
				bad += 1
				first = first or (l .. "  <>  " .. m)
			end
		end
		report(map, "reach", #lines, bad, first)
	end
	-- point -> area
	do
		local bad, first, lines = 0, nil, oracle(map, "areas", tostring(N), "1")
		for _, l in lines do
			local w = words(l)
			local a = B.AAS_PointAreaNum(vh(w, 2))
			if a ~= tonumber(w[5]) then
				bad += 1
				first = first or (l .. "  <>  " .. a)
			end
		end
		report(map, "areas", #lines, bad, first)
	end
	-- travel times
	do
		local bad, first, lines = 0, nil, oracle(map, "travel", tostring(N), "2")
		for _, l in lines do
			local w = words(l)
			local a, g, tfl = tonumber(w[2]) :: number, tonumber(w[3]) :: number, tonumber(w[4]) :: number
			local org = vh(w, 5)
			local ok, tt, rn = B.AAS_AreaRouteToGoalArea(a, org, g, tfl)
			local t2 = B.AAS_AreaTravelTimeToGoalArea(a, org, g, tfl)
			local m = string.format("T %d %d %d %s %d %d %d %d", a, g, tfl, vs(org), if ok == true then 1 elseif ok == false then 0 else ok, tt or 0, rn or 0, t2)
			if m ~= l then
				bad += 1
				first = first or (l .. "  <>  " .. m)
			end
		end
		report(map, "travel", #lines, bad, first)
	end
	-- client bbox traces through the AAS tree
	do
		local bad, first, lines = 0, nil, oracle(map, "trace", tostring(N), "3")
		for _, l in lines do
			local w = words(l)
			local pres = tonumber(w[2]) :: number
			local s, e = vh(w, 3), vh(w, 6)
			local t = B.AAS_TraceClientBBox(s, e, pres, -1)
			local m = string.format("C %d %s %s %d %s %s %d %d %d %d", pres, vs(s), vs(e), if t.startsolid then 1 else 0,
				fh(t.fraction), vs(t.endpos), t.ent, t.lastarea, t.area, t.planenum)
			if m ~= l then
				bad += 1
				first = first or (l .. "  <>  " .. m)
			end
		end
		report(map, "trace", #lines, bad, first)
	end
	-- movement prediction
	do
		local bad, first, lines = 0, nil, oracle(map, "predict", tostring(N // 4), "4")
		for _, l in lines do
			local w = words(l)
			local org, vel, cmd = vh(w, 2), vh(w, 5), vh(w, 8)
			local onground, cmdframes, frames, stop = tonumber(w[11]), tonumber(w[12]), tonumber(w[13]), tonumber(w[14])
			local mv = SB.aas_clientmove_t()
			B.AAS_PredictClientMovement(mv, -1, org, BC.PRESENCE_NORMAL, onground, vh(w, 5), vh(w, 8), cmdframes, frames,
				Qm.f(0.1), stop, 0, 0)
			local m = string.format("P %s %s %s %d %d %d %d %s %d %s %d %d %d %s %d", vs(org), vs(vel), vs(cmd), onground,
				cmdframes, frames, stop, vs(mv.endpos), mv.endarea, vs(mv.velocity), mv.presencetype, mv.stopevent,
				mv.endcontents, fh(mv.time), mv.frames)
			if m ~= l then
				bad += 1
				first = first or (l .. "  <>  " .. m)
			end
		end
		report(map, "predict", #lines, bad, first)
	end
	export.BotLibShutdown()
end
print(if failures == 0 then "oracle_aas: all match" else string.format("oracle_aas: %d mismatch(es)", failures))
process.exit(if failures == 0 then 0 else 1)
