-- Replays the C oracle's pmove logs through the Luau port of bg_pmove /
-- bg_slidemove / bg_misc and diffs every logged playerState field.
--   lune run tests/oracle/replay_pmove.luau <map.bsp> <log>
--
-- Two passes over the same log:
--   resync   each frame starts from the oracle's input playerState (I line)
--            and must reproduce its output (O line) exactly;
--   freerun  each scenario starts from its first I line and then runs on the
--            Luau state only (with the Luau jump pad / teleporter emulation),
--            compared against O / A / R every frame. On a divergence the run
--            is resynced and the divergence counted.
local fs = require("@lune/fs")
local process = require("@lune/process")
local Cm = require("./common")
local Collision = require("../../src/shared/Collision")
local S = require("../../src/shared/structs")
local Q = require("../../src/shared/q_math")
local C = require("../../src/shared/consts")
local BG = require("../../src/shared/bg/bg_pmove")
local BGM = require("../../src/shared/bg/bg_misc")

local mapPath, logPath = process.args[1], process.args[2]
Cm.loadMap(mapPath)
local hf, fh = Cm.hf, Cm.fh

-- playerState fields in oracle.c log_ps() order: name, kind
local PS = {
	{ "commandTime", "i" }, { "pm_type", "i" }, { "bobCycle", "i" }, { "pm_flags", "i" }, { "pm_time", "i" },
	{ "origin", "v" }, { "velocity", "v" },
	{ "weaponTime", "i" }, { "gravity", "i" }, { "speed", "i" },
	{ "delta_angles", "a", 3 },
	{ "groundEntityNum", "i" }, { "legsTimer", "i" }, { "legsAnim", "i" }, { "torsoTimer", "i" }, { "torsoAnim", "i" },
	{ "movementDir", "i" }, { "grapplePoint", "v" }, { "eFlags", "i" }, { "eventSequence", "i" },
	{ "events", "e", C.MAX_PS_EVENTS },
	{ "externalEvent", "i" }, { "externalEventParm", "i" }, { "externalEventTime", "i" },
	{ "clientNum", "i" }, { "weapon", "i" }, { "weaponstate", "i" }, { "viewangles", "v" }, { "viewheight", "i" },
	{ "damageEvent", "i" }, { "damageYaw", "i" }, { "damagePitch", "i" }, { "damageCount", "i" },
	{ "stats", "a", C.MAX_STATS }, { "persistant", "a", C.MAX_PERSISTANT }, { "powerups", "a", C.MAX_POWERUPS },
	{ "ammo", "a", C.MAX_WEAPONS },
	{ "generic1", "i" }, { "loopSound", "i" }, { "jumppad_ent", "i" },
	{ "ping", "i" }, { "pmove_framecount", "i" }, { "jumppad_frame", "i" }, { "entityEventSequence", "i" },
}

-- read a playerState from tokens w starting at index i; returns next index
local function readPs(w, i, ps)
	for _, fd in PS do
		local name, kind, n = fd[1], fd[2], fd[3]
		if kind == "i" then
			ps[name] = tonumber(w[i])
			i += 1
		elseif kind == "v" then
			local v = ps[name]
			v[0], v[1], v[2] = hf(w[i]), hf(w[i + 1]), hf(w[i + 2])
			i += 3
		elseif kind == "a" then
			local a = ps[name]
			for k = 0, n - 1 do
				a[k] = tonumber(w[i])
				i += 1
			end
		else -- events / eventParms interleaved
			for k = 0, n - 1 do
				ps.events[k] = tonumber(w[i])
				ps.eventParms[k] = tonumber(w[i + 1])
				i += 2
			end
		end
	end
	return i
end

-- tokens of a playerState in log_ps order, with a parallel list of field labels
local function writePs(ps, out, labels)
	local function put(tok, label)
		table.insert(out, tok)
		table.insert(labels, label)
	end
	for _, fd in PS do
		local name, kind, n = fd[1], fd[2], fd[3]
		if kind == "i" then
			put(tostring(ps[name]), name)
		elseif kind == "v" then
			for k = 0, 2 do
				put(fh(ps[name][k]), name .. "[" .. k .. "]")
			end
		elseif kind == "a" then
			for k = 0, n - 1 do
				put(tostring(ps[name][k]), name .. "[" .. k .. "]")
			end
		else
			for k = 0, n - 1 do
				put(tostring(ps.events[k]), "events[" .. k .. "]")
				put(tostring(ps.eventParms[k]), "eventParms[" .. k .. "]")
			end
		end
	end
end

local function readCmd(w, i, cmd)
	cmd.serverTime = tonumber(w[i])
	cmd.angles[0], cmd.angles[1], cmd.angles[2] = tonumber(w[i + 1]), tonumber(w[i + 2]), tonumber(w[i + 3])
	cmd.buttons = tonumber(w[i + 4])
	cmd.weapon = tonumber(w[i + 5])
	cmd.forwardmove = tonumber(w[i + 6])
	cmd.rightmove = tonumber(w[i + 7])
	cmd.upmove = tonumber(w[i + 8])
	return i + 9
end

-- engine glue, as in oracle.c pm_trace / pm_pointcontents
local function pm_trace(results, start, mins, maxs, endp, passEntityNum, contentMask)
	Collision.BoxTrace(results, start, endp, mins, maxs, 0, contentMask, false)
	results.entityNum = if results.fraction ~= 1.0 then C.ENTITYNUM_WORLD else C.ENTITYNUM_NONE
end
local function pm_pointcontents(p, passEntityNum)
	return Collision.PointContents(p, 0)
end

-- trigger_push / trigger_teleport stand-ins (oracle.c apply_triggers)
local triggers = {}
local tmins, tmaxs = Q.vec3(), Q.vec3()
local ttr = S.trace_t()
local es = S.entityState_t()
local function applyTriggers(ps, pm, cmd)
	for _, t in triggers do
		Q.VectorAdd(ps.origin, pm.mins, tmins)
		Q.VectorAdd(ps.origin, pm.maxs, tmaxs)
		Collision.TransformedBoxTrace(ttr, Q.vec3_origin, Q.vec3_origin, tmins, tmaxs, t.model, -1, Q.vec3_origin, Q.vec3_origin, false)
		if not ttr.startsolid then
			continue
		end
		if t.type == 0 then
			S.copy_entityState_t(es, S.entityState_t())
			es.number = t.entnum
			Q.VectorCopy(t.vec, es.origin2)
			BGM.BG_TouchJumpPad(ps, es)
		else
			Q.VectorCopy(t.vec, ps.origin)
			ps.origin[2] = Q.f(ps.origin[2] + 1)
			Q.AngleVectors(t.angles, ps.velocity, nil, nil)
			Q.VectorScale(ps.velocity, 400, ps.velocity)
			ps.pm_time = 160
			ps.pm_flags = bit32.bor(ps.pm_flags, C.PMF_TIME_KNOCKBACK)
			for j = 0, 2 do
				ps.delta_angles[j] = Q.ANGLE2SHORT(t.angles[j]) - cmd.angles[j]
			end
			Q.VectorCopy(t.angles, ps.viewangles)
			ps.eFlags = bit32.bxor(ps.eFlags, C.EF_TELEPORT_BIT)
		end
	end
end

local function newPm(ps, cmd, w, i)
	local pm = S.pmove_t()
	pm.ps = ps
	S.copy_usercmd_t(pm.cmd, cmd)
	pm.tracemask = tonumber(w[i]) :: number
	pm.pmove_fixed = tonumber(w[i + 1]) :: number
	pm.pmove_msec = tonumber(w[i + 2]) :: number
	pm.pmove_float = tonumber(w[i + 3]) :: number
	pm.pmove_flags = tonumber(w[i + 4]) :: number
	pm.trace = pm_trace
	pm.pointcontents = pm_pointcontents
	pm.debugLevel = 0
	pm.noFootsteps = false
	return pm
end

-- outputs after Pmove: playerState + pmove_t results (oracle O line)
local function outTokens(ps, pm)
	local out, labels = {}, {}
	writePs(ps, out, labels)
	table.insert(out, tostring(pm.numtouch))
	table.insert(labels, "numtouch")
	for k = 0, pm.numtouch - 1 do
		table.insert(out, tostring(pm.touchents[k]))
		table.insert(labels, "touchents[" .. k .. "]")
	end
	for _, nm in { "mins", "maxs" } do
		for k = 0, 2 do
			table.insert(out, fh(pm[nm][k]))
			table.insert(labels, nm .. "[" .. k .. "]")
		end
	end
	table.insert(out, tostring(pm.watertype))
	table.insert(labels, "watertype")
	table.insert(out, tostring(pm.waterlevel))
	table.insert(labels, "waterlevel")
	table.insert(out, fh(pm.xyspeed))
	table.insert(labels, "xyspeed")
	return out, labels
end

-- compare our tokens with the logged ones (w from index 2); returns the
-- number of differing fields, the max float ulps and the first difference
local function diff(out, labels, w)
	local nd, maxu, first = 0, 0, nil
	if #w - 1 ~= #out then
		return 1, math.huge, string.format("token count %d vs %d", #out, #w - 1)
	end
	for k, tok in out do
		local ref = w[k + 1]
		if tok ~= ref then
			nd += 1
			local u = 0
			if #tok == 8 and #ref == 8 and string.match(tok, "^%x+$") and string.match(ref, "^%x+$") then
				u = Cm.ulps(hf(tok), hf(ref))
			else
				u = math.huge
			end
			if u > maxu then
				maxu = u
			end
			if not first then
				first = string.format("%s: luau %s oracle %s", labels[k], tok, ref)
			end
		end
	end
	return nd, maxu, first
end

local lines = string.split(fs.readFile(logPath), "\n")
for _, line in lines do
	local w = Cm.words(line)
	if w[1] == "G" then
		table.insert(triggers, {
			type = tonumber(w[2]),
			model = tonumber(w[3]),
			entnum = tonumber(w[4]),
			vec = Q.vec3(hf(w[5]), hf(w[6]), hf(w[7])),
			angles = Q.vec3(hf(w[8]), hf(w[9]), hf(w[10])),
		})
	end
end

local cover = {}
local stats = { frames = 0, resyncBad = 0, resyncMaxUlps = 0, kinds = {} }
local t0 = os.clock()

------------------------------------------------------------------ resync pass
do
	local ps, cmd = S.playerState_t(), S.usercmd_t()
	local pm
	local reported = 0
	for idx, line in lines do
		local w = Cm.words(line)
		local tag = w[1]
		if tag == "I" then
			ps = S.playerState_t()
			local i = readPs(w, 3, ps)
			i = readCmd(w, i, cmd)
			pm = newPm(ps, cmd, w, i)
			local seq0 = ps.eventSequence
			BG.Pmove(pm)
			stats.frames += 1
			-- coverage: which movement situations the log exercised
			for q = seq0, ps.eventSequence - 1 do
				local ev = ps.events[bit32.band(q, C.MAX_PS_EVENTS - 1)]
				local nm = BGM.eventnames[ev] or tostring(ev)
				cover[nm] = (cover[nm] or 0) + 1
			end
			if pm.waterlevel > 0 then
				cover["waterlevel>0"] = (cover["waterlevel>0"] or 0) + 1
			end
			if ps.groundEntityNum == C.ENTITYNUM_NONE and BG.pml.groundPlane then
				cover["steep slope slide"] = (cover["steep slope slide"] or 0) + 1
			end
		elseif tag == "A" then
			local o = S.playerState_t()
			readPs(w, 2, o)
			if bit32.band(bit32.bxor(o.eFlags, ps.eFlags), C.EF_TELEPORT_BIT) ~= 0 then
				cover["teleport"] = (cover["teleport"] or 0) + 1
			end
			if o.jumppad_frame == o.pmove_framecount and o.jumppad_ent ~= 0 and (o.velocity[0] ~= ps.velocity[0] or o.velocity[2] ~= ps.velocity[2] or o.eventSequence ~= ps.eventSequence) then
				cover["jumppad launch"] = (cover["jumppad launch"] or 0) + 1
			end
		elseif tag == "O" then
			local out, labels = outTokens(ps, pm)
			local nd, maxu, first = diff(out, labels, w)
			if nd > 0 then
				stats.resyncBad += 1
				if maxu > stats.resyncMaxUlps then
					stats.resyncMaxUlps = maxu
				end
				reported += 1
				if reported <= 8 then
					print(string.format("resync mismatch at log line %d (%d fields): %s", idx, nd, first))
				end
			end
		end
	end
end
local resyncTime = os.clock() - t0

----------------------------------------------------------------- freerun pass
local fr = { divergences = 0, frames = 0, maxUlps = 0, scenarios = 0, cleanScenarios = 0, longest = 0 }
do
	local ps, cmd = nil :: any, S.usercmd_t()
	local pm
	local sincePrevDiv = 0
	local scenarioClean = true
	local reported = 0
	local function check(w, out, labels, idx, what)
		local nd, maxu, first = diff(out, labels, w)
		if nd > 0 then
			fr.divergences += 1
			scenarioClean = false
			if maxu > fr.maxUlps then
				fr.maxUlps = maxu
			end
			reported += 1
			if reported <= 8 then
				print(string.format("freerun divergence (%s) at log line %d after %d frames: %s", what, idx, sincePrevDiv, first))
			end
			sincePrevDiv = 0
			-- resync to the oracle's state
			ps = S.playerState_t()
			readPs(w, 2, ps)
			if pm then
				pm.ps = ps
			end
			return false
		end
		return true
	end
	for idx, line in lines do
		local w = Cm.words(line)
		local tag = w[1]
		if tag == "S" then
			if fr.scenarios > 0 and scenarioClean then
				fr.cleanScenarios += 1
			end
			fr.scenarios += 1
			scenarioClean = true
			ps = nil
			sincePrevDiv = 0
		elseif tag == "I" then
			if ps == nil then
				ps = S.playerState_t()
				readPs(w, 3, ps)
			end
			-- the input cmd and pmove settings come from the log; the state is ours
			local i = 3
			local tmp = S.playerState_t()
			i = readPs(w, i, tmp)
			i = readCmd(w, i, cmd)
			pm = newPm(ps, cmd, w, i)
			BG.Pmove(pm)
			fr.frames += 1
		elseif tag == "O" then
			local out, labels = outTokens(ps, pm)
			check(w, out, labels, idx, "pmove")
		elseif tag == "A" then
			applyTriggers(ps, pm, cmd)
			local out, labels = {}, {}
			writePs(ps, out, labels)
			if check(w, out, labels, idx, "triggers") then
				sincePrevDiv += 1
				if sincePrevDiv > fr.longest then
					fr.longest = sincePrevDiv
				end
			end
		elseif tag == "R" then
			-- respawn: the oracle moved the player to a spawn point
			local ref = S.playerState_t()
			readPs(w, 2, ref)
			Q.VectorCopy(ref.origin, ps.origin)
			Q.VectorClear(ps.velocity)
			ps.eFlags = bit32.bxor(ps.eFlags, C.EF_TELEPORT_BIT)
			local out, labels = {}, {}
			writePs(ps, out, labels)
			check(w, out, labels, idx, "respawn")
		end
	end
	if fr.scenarios > 0 and scenarioClean then
		fr.cleanScenarios += 1
	end
end

print(string.format(
	"%s: %d frames, %d triggers | resync: %d mismatching frames, max %s ulps (%.2fs, %.1f us/frame) | freerun: %d/%d scenarios bit-exact end to end, %d divergences, max %s ulps",
	string.match(mapPath, "([^/]+)%.bsp$") or mapPath,
	stats.frames,
	#triggers,
	stats.resyncBad,
	tostring(stats.resyncMaxUlps),
	resyncTime,
	resyncTime / math.max(stats.frames, 1) * 1e6,
	fr.cleanScenarios,
	fr.scenarios,
	fr.divergences,
	tostring(fr.maxUlps)
))
local cv = {}
for _, k in { "EV_JUMP", "jumppad launch", "teleport", "EV_STEP_4", "EV_STEP_8", "EV_STEP_12", "EV_STEP_16", "steep slope slide", "waterlevel>0", "EV_WATER_UNDER", "EV_FALL_FAR", "EV_FIRE_WEAPON", "EV_CHANGE_WEAPON" } do
	table.insert(cv, k .. "=" .. tostring(cover[k] or 0))
end
print("  coverage: " .. table.concat(cv, " "))
if stats.resyncBad > 0 or fr.divergences > 0 then
	process.exit(1)
end
