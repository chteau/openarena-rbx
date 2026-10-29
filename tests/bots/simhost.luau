-- Headless server with bots for the lune tests: the game branch's server
-- (src/server/Game, its engine and pmove) with the bot port installed the
-- way docs/bots-notes.md describes, BSPs from build/maps (game branch),
-- the .aas files from the converter's Aas blob modules (conv branch
-- build/maps/<map>/luau), botfiles from tools/pack-botfiles.py's blob, and
-- OA's scripts from the pk3s.
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local BSP = require("../../src/shared/cm/bsp")
local checksum = require("./md4")

local M = {}

local PK3_DIR = "vendor/oa088/openarena-0.8.8/baseoa"
local PK3S = { "pak0.pk3", "pak6-misc.pk3", "pak6-patch085.pk3", "pak6-patch088.pk3" }
local SCRIPTS = { "scripts/arenas.txt", "scripts/085p.arena", "scripts/bots.txt" }

local function pk3Files(): { [string]: string }
	local files = {}
	for _, pk3 in PK3S do
		for _, path in SCRIPTS do
			local r = process.exec("unzip", { "-p", PK3_DIR .. "/" .. pk3, path })
			if r.ok and #r.stdout > 0 then
				files[path] = r.stdout
			end
		end
	end
	return files
end

-- joins a converter blob through its index and chunk modules, as the
-- Roblox side does with ModuleScripts
local function blob(dir: string, name: string): buffer?
	if not fs.isFile(dir .. "/" .. name .. ".luau") then
		return nil
	end
	local Bots = require("../../src/server/bot/Bots")
	local info = (require :: any)("../../" .. dir .. "/" .. name)
	return Bots.JoinBlob(info, function(chunk)
		return (require :: any)("../../" .. dir .. "/" .. chunk)
	end)
end

function M.new(opts: { maps: { string }, quiet: boolean?, log: { string }? })
	local Game = require("../../src/server/Game")
	local W = require("../../src/server/sv/sv_world")
	local Collision = require("../../src/shared/Collision")
	local structs = require("../../src/shared/structs")
	local Bots = require("../../src/server/bot/Bots")
	local BotGame = require("../../src/server/bot/BotGame")
	local clock = 0
	local files = pk3Files()
	local botfiles = assert(blob("build/botfiles/luau", "Botfiles"), "run tools/pack-botfiles.py first")
	Bots.MountBotfiles(botfiles, function(path, data)
		files[path] = data
	end)
	for _, map in opts.maps do
		local aas = blob("build/conv-maps/" .. map .. "/luau", "Aas")
		if aas then
			files["maps/" .. map .. ".aas"] = buffer.tostring(aas)
		end
	end
	Game.Init({
		loadMap = function(name: string)
			local path = "build/maps/" .. name .. ".bsp"
			if not fs.isFile(path) then
				return nil
			end
			local data = buffer.fromstring(fs.readFile(path))
			local lumps = BSP.parse(data)
			lumps.checksum = checksum(data)
			return lumps
		end,
		mapExists = function(name: string): boolean
			return fs.isFile("build/maps/" .. name .. ".bsp")
		end,
		files = files,
		print = function(text: string)
			if opts.log then
				table.insert(opts.log, text)
			end
			if not opts.quiet then
				stdio.write(text)
			end
		end,
		milliseconds = function(): number
			return clock
		end,
	})
	Bots.Install(BotGame.FromEngine({
		SV = Game.SV, W = W, Cvar = Game.Cvar, Fs = Game.Fs, Collision = Collision,
		G = Game.G, C = Game.C, structs = structs,
	}))
	Bots.InitGameProgs()
	local host = { Game = Game, Bots = Bots, G = Game.G, SV = Game.SV, botMs = 0, gameMs = 0, frames = 0 }
	-- one server tick: the bots think (SV_BotFrame) then the game runs, as
	-- ioquake3's dedicated SV_Frame does
	function host.frame(msec: number)
		clock += msec
		local t = os.clock()
		Bots.Frame(Game.SV.sv.time)
		host.botMs += (os.clock() - t) * 1000
		t = os.clock()
		Game.Frame(msec)
		host.gameMs += (os.clock() - t) * 1000
		host.frames += 1
	end
	return host
end

return M
