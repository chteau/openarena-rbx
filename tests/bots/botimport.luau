-- A headless botimport for the lune tests: traces and point contents from
-- the game branch's collision model (src/shared/Collision), files from
-- build/oracle-bots (the maps and botfiles tools/oracle-bots/build.sh
-- extracts). It is what sv_bot.luau builds in the real server, minus the
-- entities.
local fs = require("@lune/fs")
local stdio = require("@lune/stdio")
local Collision = require("../../src/shared/Collision")
local BSP = require("../../src/shared/cm/bsp")
local SS = require("../../src/shared/structs")
local Q = require("../../src/shared/q_math")
local QS = require("../../src/shared/q_shared")

local M = {}
local DATA = "build/oracle-bots"

function M.loadMap(name: string)
	local lumps = BSP.parse(buffer.fromstring(fs.readFile(DATA .. "/maps/" .. name .. ".bsp")))
	Collision.LoadMap("maps/" .. name .. ".bsp", lumps)
end

function M.new(opts: { quiet: boolean? }?)
	local quiet = opts and opts.quiet
	local tr = SS.trace_t()
	local imp = {}
	function imp.Print(t: number, fmt: string, ...)
		if not quiet then
			stdio.ewrite(QS.va(fmt, ...))
		end
	end
	function imp.Trace(bt, start, mins, maxs, endp, passent, contentmask)
		Collision.BoxTrace(tr, start, endp, mins, maxs, 0, contentmask)
		bt.allsolid = tr.allsolid
		bt.startsolid = tr.startsolid
		bt.fraction = tr.fraction
		Q.VectorCopy(tr.endpos, bt.endpos)
		bt.plane.dist = tr.plane.dist
		Q.VectorCopy(tr.plane.normal, bt.plane.normal)
		bt.plane.signbits = tr.plane.signbits
		bt.plane.type = tr.plane.type
		bt.surface.value = 0
		bt.surface.flags = tr.surfaceFlags
		bt.ent = if tr.fraction < 1 then 1022 else 1023
		bt.exp_dist = 0
		bt.sidenum = 0
		bt.contents = 0
	end
	function imp.EntityTrace(bt, start, mins, maxs, endp, entnum, contentmask)
		bt.allsolid, bt.startsolid, bt.fraction = false, false, 1
		Q.VectorCopy(endp, bt.endpos)
		bt.ent = 1023
	end
	function imp.PointContents(p)
		return Collision.PointContents(p, 0)
	end
	function imp.inPVS(p1, p2)
		return true
	end
	function imp.BSPEntityData()
		return Collision.EntityString()
	end
	function imp.BSPModelMinsMaxsOrigin(modelnum, angles, outmins, outmaxs, origin)
		local mins, maxs = Q.vec3(), Q.vec3()
		Collision.ModelBounds(Collision.InlineModel(modelnum), mins, maxs)
		if angles[0] ~= 0 or angles[1] ~= 0 or angles[2] ~= 0 then
			local max = Q.RadiusFromBounds(mins, maxs)
			for i = 0, 2 do
				mins[i] = -max
				maxs[i] = max
			end
		end
		if outmins then
			Q.VectorCopy(mins, outmins)
		end
		if outmaxs then
			Q.VectorCopy(maxs, outmaxs)
		end
		if origin then
			Q.VectorClear(origin)
		end
	end
	function imp.BotClientCommand(client, command) end
	function imp.FS_ReadFile(path: string): buffer?
		local p = DATA .. "/" .. path
		if fs.isFile(p) then
			return buffer.fromstring(fs.readFile(p))
		end
		return nil
	end
	function imp.AvailableMemory()
		return 256 * 1024 * 1024
	end
	function imp.Sys_MilliSeconds()
		return math.floor(os.clock() * 1000)
	end
	function imp.DebugLineCreate()
		return 0
	end
	function imp.DebugLineDelete(id) end
	function imp.DebugLineShow(id, s, e, c) end
	function imp.DebugPolygonCreate(color, n, points)
		return 0
	end
	function imp.DebugPolygonDelete(id) end
	return imp
end

return M
