-- Headless server with bots for the lune tests: the game branch's server
-- (src/server/Game, its engine and pmove) with the bot port installed the
-- way Game.luau installs it, BSPs from build/maps (or, without them, the
-- converter's Collision and Entities blobs, as the place loads), each map's checksum and
-- .aas from the converter's output (build/conv/maps/<map>/map.json and its
-- Aas blob modules), botfiles from tools/pack-botfiles.py's blob, and OA's
-- scripts from the pk3s.
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local BSP = require("../../src/shared/cm/bsp")
local serde = require("@lune/serde")

-- oaconv convert --only maps --out build/conv, or a full convert's build/
local CONV = if fs.isDir("build/conv/maps") then "build/conv/maps" else "build/maps"
local Blob = require("../../src/shared/cm/blob")

local M = {}

-- OA's scripts and player skins as the place ships them: the 0.8.8 pk3s
-- with the roster applied (tools/roster.py, tools/oaconv/roster.json)
local SHIPPED = { "scripts/arenas.txt", "scripts/085p.arena", "scripts/bots.txt", "models/players/" }

local shipped
local function pk3Files(): { [string]: string }
	if shipped == nil then
		local r = process.exec("python3", { "tools/roster.py", "files", table.unpack(SHIPPED) })
		assert(r.ok, r.stderr)
		shipped = serde.decode("json", r.stdout)
	end
	return shipped
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
	local Bots = Game.Bots
	local clock = 0
	local botfiles = assert(blob("build/botfiles/luau", "Botfiles"), "run tools/pack-botfiles.py first")
	Game.Init({
		-- the BSP for the clip map; the checksum and the .aas come from the
		-- converter's map.json and Aas blob, as on Roblox
		loadMap = function(name: string)
			local path = "build/maps/" .. name .. ".bsp"
			local conv = CONV .. "/" .. name
			local lumps
			if fs.isFile(path) then
				lumps = BSP.parse(buffer.fromstring(fs.readFile(path)))
			else
				-- no BSP: the Collision and Entities blobs the place carries
				local collision = blob(conv .. "/luau", "Collision")
				if collision == nil then
					return nil
				end
				local entities = blob(conv .. "/luau", "Entities") :: buffer
				lumps = Blob.lumps(collision, serde.decode("json", buffer.tostring(entities)))
			end
			local info = serde.decode("json", fs.readFile(conv .. "/map.json"))
			lumps.checksum = info.checksum
			lumps.aas = blob(conv .. "/luau", "Aas")
			return lumps
		end,
		mapExists = function(name: string): boolean
			return fs.isFile("build/maps/" .. name .. ".bsp") or fs.isFile(CONV .. "/" .. name .. "/luau/Collision.luau")
		end,
		files = pk3Files(),
		botfiles = botfiles,
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
	local host = { Game = Game, Bots = Bots, G = Game.G, SV = Game.SV, botMs = 0, gameMs = 0, frames = 0 }
	-- SV_Frame runs SV_BotFrame itself; time it apart from the rest
	local botFrame = Bots.Frame
	Bots.Frame = function(time: number)
		local t = os.clock()
		botFrame(time)
		host.botMs += (os.clock() - t) * 1000
	end
	-- one host tick of the server (gameMs includes the bots)
	function host.frame(msec: number)
		clock += msec
		local t = os.clock()
		Game.Frame(msec)
		host.gameMs += (os.clock() - t) * 1000
		host.frames += 1
	end
	return host
end

return M
