-- Headless host for the server tests (lune): loads BSPs from build/maps,
-- mounts OA's scripts from the 0.8.8 pk3s, and gives the tests a Game.
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local BSP = require("../../src/shared/cm/bsp")

local M = {}

local PK3_DIR = "vendor/oa088/openarena-0.8.8/baseoa"
-- later pk3s override earlier ones, like the search path
local PK3S = { "pak0.pk3", "pak6-misc.pk3", "pak6-patch085.pk3", "pak6-patch088.pk3" }
local SCRIPTS = { "scripts/arenas.txt", "scripts/085p.arena", "scripts/bots.txt" }

local function pk3Files(): { [string]: string }
	local files = {}
	for _, pk3 in PK3S do
		local p = PK3_DIR .. "/" .. pk3
		if not fs.isFile(p) then
			continue
		end
		for _, path in SCRIPTS do
			local r = process.exec("unzip", { "-p", p, path })
			if r.ok and #r.stdout > 0 then
				files[path] = r.stdout
			end
		end
	end
	return files
end

-- opts.patchEntities(mapname, entityString) -> entityString lets a test
-- add entities (e.g. domination points) to a real map
function M.newGame(opts: { quiet: boolean?, log: { string }?, patchEntities: ((string, string) -> string)? }?)
	local Game = require("../../src/server/Game")
	local o = opts or {}
	-- the modules are singletons: a new world starts from a dead server
	-- with no cvars and no files
	if M.initialized then
		Game.SV.SV_Shutdown("test world reset")
		Game.Cvar.ResetAll()
		Game.Fs.Clear()
	end
	M.initialized = true
	local clock = 0
	M.clock = function(ms: number)
		clock += ms
	end
	Game.Init({
		loadMap = function(name: string)
			local path = "build/maps/" .. name .. ".bsp"
			if not fs.isFile(path) then
				return nil
			end
			local lumps = BSP.parse(buffer.fromstring(fs.readFile(path)))
			if o.patchEntities then
				lumps.entities = o.patchEntities(name, lumps.entities)
			end
			return lumps
		end,
		mapExists = function(name: string): boolean
			return fs.isFile("build/maps/" .. name .. ".bsp")
		end,
		files = pk3Files(),
		maps = (function()
			local names = {}
			for _, f in fs.readDir("build/maps") do
				local n = string.match(f, "^(.+)%.bsp$")
				if n then
					table.insert(names, n)
				end
			end
			return names
		end)(),
		print = function(text: string)
			if o.log then
				table.insert(o.log, text)
			end
			if not o.quiet then
				stdio.write(text)
			end
		end,
		milliseconds = function(): number
			return clock
		end,
	})
	return Game
end

return M
