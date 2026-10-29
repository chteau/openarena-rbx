--!strict
-- Parity fixtures: boots the client without input hookups and puts it in the
-- states the reference shots in docs/parity/ref were taken in (see
-- scripts/oa-ref.sh calls in docs/client-notes.md). Used by tests/smoke.luau
-- under lune and by the rbx-native parity driver over MCP. Not part of the
-- game: the place build leaves the dev folder out.
local sys = script.Parent.Parent.sys
local C = require(script.Parent.Parent.q.Consts)
local T = require(script.Parent.Parent.q.Types)
local Client = require(sys.Client)
local Net = require(sys.Net)
local Clock = require(sys.Clock)
local Cmd = require(sys.Cmd)
local Cvar = require(sys.Cvar)
local Console = require(sys.Console)

local Scene = {}

local START = 100000 -- engine clock at boot (ms)
local LEVEL_START = 50000 -- server time of the level start

function Scene.boot(root: Instance, width: number, height: number)
	Clock.fixed = START
	Client.Boot({ root = root, width = width, height = height })
	Client.Frame(0)
end

-- the game in progress: a 20 Hz server sending `fill`ed snapshots
local game: { fill: (any) -> (), serverTime: number, nextSnap: number }? = nil
local snapshot: (number, (any) -> ()) -> ()

-- step the engine `ms` milliseconds, 16 ms a frame
function Scene.advance(ms: number)
	local stop = (Clock.fixed :: number) + ms
	while (Clock.fixed :: number) < stop do
		local step = math.min(16, stop - (Clock.fixed :: number))
		Clock.fixed = (Clock.fixed :: number) + step
		if game then
			game.serverTime += step
			if game.serverTime >= game.nextSnap then
				game.nextSnap += 50
				snapshot(game.serverTime, game.fill)
			end
		end
		Client.Frame(step / 1000)
	end
end

function Scene.census(root: Instance): (number, { [string]: number })
	local n, kinds = 0, {}
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d.Visible then
			n += 1
			kinds[d.ClassName] = (kinds[d.ClassName] or 0) + 1
		end
	end
	return n, kinds
end

-- main menu, as `openarena +set r_mode -1 ...` opens it
function Scene.menu()
	Scene.advance(1000)
end

local function playerInfo(name: string, model: string, bot: boolean?): string
	local s = "n\\" .. name .. "\\t\\0\\model\\" .. model .. "\\hmodel\\" .. model
		.. "\\c1\\4\\c2\\5\\hc\\100\\w\\0\\l\\0\\tt\\0\\tl\\0"
	if bot then
		s ..= "\\skill\\2"
	end
	return s
end

local seq = 0
local function serverCommand(text: string)
	seq += 1
	Net.ReceiveServerCommand(seq, text)
end

local snapNum = 0
function snapshot(serverTime: number, fill: (any) -> ())
	local snap = T.snapshot_t()
	snap.serverTime = serverTime
	local ps = snap.ps
	ps.commandTime = serverTime
	ps.pm_type = C.PM_NORMAL
	ps.clientNum = 0
	ps.origin[0], ps.origin[1], ps.origin[2] = 0, 0, 24
	ps.viewheight = C.DEFAULT_VIEWHEIGHT
	ps.weapon = C.WP_MACHINEGUN
	ps.weaponstate = C.WEAPON_READY
	ps.stats[C.STAT_HEALTH] = 100
	ps.stats[C.STAT_MAX_HEALTH] = 100
	ps.stats[C.STAT_ARMOR] = 0
	ps.stats[C.STAT_WEAPONS] = bit32.bor(bit32.lshift(1, C.WP_GAUNTLET), bit32.lshift(1, C.WP_MACHINEGUN))
	ps.ammo[C.WP_MACHINEGUN] = 100
	ps.groundEntityNum = C.ENTITYNUM_WORLD
	fill(snap)
	snapNum += 1
	Net.ReceiveSnapshot(snapNum, snap)
end

-- the in-game state of hud_ffa.png: FFA on oa_dm1, `give all`, nothing else drawn
local function enterGame(players: { { name: string, model: string, bot: boolean? } }, fill: (any) -> ())
	if Client.cgameActive then
		Client.Disconnect()
	end
	game = nil
	local cs: { [number]: string } = {}
	cs[C.CS_SERVERINFO] = "\\g_gametype\\0\\mapname\\oa_dm1\\sv_hostname\\noname\\sv_maxclients\\8"
		.. "\\fraglimit\\20\\timelimit\\0\\capturelimit\\8\\dmflags\\0\\g_instantgib\\0\\g_rockets\\0"
		.. "\\elimflags\\0\\voteflags\\0\\g_obeliskRespawnDelay\\10\\g_altExcellent\\0"
	cs[C.CS_SYSTEMINFO] = "\\sv_serverid\\1\\sv_cheats\\1"
	cs[C.CS_GAME_VERSION] = C.GAME_VERSION
	cs[C.CS_LEVEL_START_TIME] = tostring(LEVEL_START)
	cs[C.CS_WARMUP] = ""
	cs[C.CS_SCORES1] = "0"
	-- g_main CalculateRanks: SCORE_NOT_PRESENT without a second player
	cs[C.CS_SCORES2] = if #players > 1 then "0" else "-9999"
	cs[C.CS_MOTD] = ""
	cs[C.CS_MODELS + 1] = "*1"
	cs[C.CS_ITEMS] = string.rep("0", C.MAX_ITEMS)
	for i, p in players do
		cs[C.CS_PLAYERS + i - 1] = playerInfo(p.name, p.model, p.bot)
	end
	Net.ReceiveGamestate(cs, 0, 0)
	seq = 0
	Client.connectRequested = true
	local serverTime = LEVEL_START + 20000
	game = { fill = fill, serverTime = serverTime, nextSnap = serverTime + 50 }
	snapshot(serverTime, fill)
	-- inits the cgame, goes CA_ACTIVE and lets the view settle
	Scene.advance(2000)
end

local function giveAll(snap)
	local ps = snap.ps
	local all = 0
	for w = C.WP_GAUNTLET, C.WP_NUM_WEAPONS - 1 do
		all = bit32.bor(all, bit32.lshift(1, w))
		ps.ammo[w] = 999
	end
	ps.stats[C.STAT_WEAPONS] = all
	ps.stats[C.STAT_ARMOR] = 198
end

function Scene.hud()
	Cvar.Set("cg_draw3dIcons", "0")
	Cvar.Set("cg_drawGun", "0")
	enterGame({ { name = "UnnamedPlayer", model = "sarge" } }, giveAll)
	serverCommand('print "UnnamedPlayer^7 entered the game\n"')
	-- commands run when the snapshot that carries them becomes cg.snap
	Scene.advance(400)
end

function Scene.scores()
	Cvar.Set("cg_draw3dIcons", "0")
	Cvar.Set("cg_drawGun", "0")
	Console.ClearNotify()
	enterGame({ { name = "UnnamedPlayer", model = "sarge" }, { name = "Sergei", model = "sergei", bot = true } }, function(snap)
		snap.ps.stats[C.STAT_HEALTH] = 125
		-- rank 0, tied with Sergei
		snap.ps.persistant[C.PERS_RANK] = C.RANK_TIED_FLAG
	end)
	Console.Print("loaded Sergei from bots/sergei_t.c\n")
	serverCommand('print "Sergei^7 connected\n"')
	serverCommand('print "Sergei^7 entered the game\n"')
	-- g_main sends this to everyone who has the board up (0.8.8 field order:
	-- client score ping time flags powerups accuracy impressive excellent
	-- gauntlet defend assist perfect captures isDead)
	serverCommand("scores 2 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0")
	Cmd.ExecuteText(C.EXEC_NOW, "+scores")
	Scene.advance(200)
end

return Scene
