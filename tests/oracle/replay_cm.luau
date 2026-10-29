-- Replays the C oracle's patch dumps and trace logs through the Luau
-- collision model and reports every mismatch.
--   lune run tests/oracle/replay_cm.luau <map.bsp> <patches|traces> <log>
local fs = require("@lune/fs")
local process = require("@lune/process")
local C = require("./common")
local Collision = require("../../src/shared/Collision")
local S = require("../../src/shared/structs")
local Q = require("../../src/shared/q_math")

local mapPath, mode, logPath = process.args[1], process.args[2], process.args[3]
local t0 = os.clock()
C.loadMap(mapPath)
local loadTime = os.clock() - t0
local lines = string.split(fs.readFile(logPath), "\n")
local hf, fh = C.hf, C.fh

local mismatches, total, maxUlps = 0, 0, 0
local function report(msg)
	mismatches += 1
	if mismatches <= 10 then
		print(msg)
	end
end

if mode == "patches" then
	local cm = Collision.state.cm
	local pc, pi = nil, 0
	local fi = 0
	for _, line in lines do
		local w = C.words(line)
		if w[1] == "P" then
			local surf = tonumber(w[2])
			local p = cm.surfaces[surf]
			total += 1
			if not p then
				report("missing patch " .. surf)
				pc = nil
				continue
			end
			pc = p.pc
			pi, fi = 0, 0
			if pc.numPlanes ~= tonumber(w[3]) or pc.numFacets ~= tonumber(w[4]) then
				report(string.format("patch %d: planes %d/%s facets %d/%s", surf, pc.numPlanes, w[3], pc.numFacets, w[4]))
				pc = nil
				continue
			end
			local k = 5
			for j = 0, 1 do
				for i = 0, 2 do
					if fh(pc.bounds[j][i]) ~= w[k] then
						report(string.format("patch %d bounds[%d][%d] %s vs %s", surf, j, i, fh(pc.bounds[j][i]), w[k]))
					end
					k += 1
				end
			end
		elseif w[1] == "p" and pc then
			local pl = pc.planes[pi]
			for i = 0, 3 do
				local d = C.ulps(pl.plane[i], hf(w[2 + i]))
				if d > maxUlps then
					maxUlps = d
				end
				if d ~= 0 then
					report(string.format("plane %d[%d] %s vs %s", pi, i, fh(pl.plane[i]), w[2 + i]))
				end
			end
			if pl.signbits ~= tonumber(w[6]) then
				report("plane signbits " .. pi)
			end
			pi += 1
		elseif w[1] == "f" and pc then
			local fc = pc.facets[fi]
			local s = string.format("f %d %d", fc.surfacePlane, fc.numBorders)
			for k = 0, fc.numBorders - 1 do
				s ..= string.format(" %d:%d:%d", fc.borderPlanes[k], if fc.borderInward[k] then 1 else 0, if fc.borderNoAdjust[k] then 1 else 0)
			end
			if s ~= line then
				report("facet " .. fi .. "\n  lua: " .. s .. "\n  c:   " .. line)
			end
			fi += 1
		end
	end
	print(string.format("%s patches: %d patches, %d mismatches, max plane ulps %d, load %.3fs", mapPath, total, mismatches, maxUlps, loadTime))
elseif mode == "traces" then
	local tr = S.trace_t()
	local maxFrac = 0
	local emins, emaxs = Q.vec3(-15, -15, -24), Q.vec3(15, 15, 32)
	for _, line in lines do
		local w = C.words(line)
		if w[1] ~= "T" then
			continue
		end
		total += 1
		local function v(i)
			return Q.vec3(hf(w[i]), hf(w[i + 1]), hf(w[i + 2]))
		end
		local kind = tonumber(w[2])
		local start, endp, mins, maxs = v(3), v(6), v(9), v(12)
		local model, mask, capsule = tonumber(w[15]) :: number, tonumber(w[16]) :: number, w[17] == "1"
		local origin, angles = v(18), v(21)
		if kind == 8 then
			model = Collision.TempBoxModel(emins, emaxs, false)
		end
		if model ~= 0 then
			Collision.TransformedBoxTrace(tr, start, endp, mins, maxs, model, mask, origin, angles, capsule)
		else
			Collision.BoxTrace(tr, start, endp, mins, maxs, 0, mask, capsule)
		end
		local pc1 = if model ~= 0
			then Collision.TransformedPointContents(start, model, origin, angles)
			else Collision.PointContents(start, 0)
		local pc2 = Collision.PointContents(endp, 0)
		local got = string.format(
			"| %d %d %s %s %s %s %s %s %s %s %d %d %d %d %d %d",
			if tr.allsolid then 1 else 0, if tr.startsolid then 1 else 0, fh(tr.fraction),
			fh(tr.endpos[0]), fh(tr.endpos[1]), fh(tr.endpos[2]),
			fh(tr.plane.normal[0]), fh(tr.plane.normal[1]), fh(tr.plane.normal[2]), fh(tr.plane.dist),
			tr.plane.type, tr.plane.signbits, tr.surfaceFlags, tr.contents, pc1, pc2
		)
		local want = string.match(line, "(|.*)$")
		if got ~= want then
			local wf = C.words(want)
			local d = math.abs(tr.fraction - hf(wf[4]))
			if d > maxFrac then
				maxFrac = d
			end
			report(string.format("trace %d kind %d\n  lua %s\n  c   %s", total, kind, got, want))
		end
	end
	print(string.format("%s traces: %d traces, %d mismatches, max fraction diff %g", mapPath, total, mismatches, maxFrac))
end
process.exit(if mismatches == 0 then 0 else 1)
