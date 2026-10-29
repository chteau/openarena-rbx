--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (the game module and the dedicated server engine).

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
===========================================================================
]]
--!native
-- Entry point of the server side: loads every ported game file
-- (g_*.luau, bg_alloc), the engine (sv/*) and the bots (bot/*), wires the
-- shared modules' hooks to the engine, and exposes the API a host uses:
--
--   local Game = require(path.to.Game)
--   Game.Init({ loadMap = function(name) -> lumps, mapExists = ..., files = {...}, botfiles = blob })
--   Game.Command("map oa_dm1")          -- or any console command / cvar
--   Game.Frame(msec)                    -- call every host tick
--   SV.SV_DirectConnect / SV_PacketEvent / SV_Disconnect from a transport
--
-- See docs/formats/net.md for the messages and docs/game-notes.md for the
-- engine boundary.

local G = require("./g_local")

-- the game module, in g_*.c order
require("./bg_alloc")
require("./g_active_1")
require("./g_active_2")
require("./g_admin_1")
require("./g_admin_2")
require("./g_admin_3")
require("./g_admin_4")
require("./g_arenas")
require("./g_bot")
require("./g_client_1")
require("./g_client_2")
require("./g_cmds_1")
require("./g_cmds_2")
require("./g_cmds_3")
require("./g_cmds_ext")
require("./g_combat_1")
require("./g_combat_2")
require("./g_fileops")
require("./g_items")
require("./g_killspree")
require("./g_main_1")
require("./g_main_2")
require("./g_main_3")
require("./g_misc")
require("./g_missile")
require("./g_mover_1")
require("./g_mover_2")
require("./g_playerstore")
require("./g_session")
require("./g_spawn")
require("./g_svcmds")
require("./g_svcmds_ext")
require("./g_target")
require("./g_team_1")
require("./g_team_2")
require("./g_team_3")
require("./g_trigger")
require("./g_unlagged")
require("./g_utils")
require("./g_vote")
require("./g_weapon")

-- the engine
local SV = require("./sv/sv_main")
local Cvar = require("./sv/cvar")
local Cmd = require("./sv/cmd")
local Fs = require("./sv/fs")
local MSG = require("../shared/net/msg")
local QS = require("../shared/q_shared")
local C = require("./g_defs")
local Bots = require("./bot/Bots")

-- the bot AI and botlib (ai_*.c, g_syscalls' bot traps, sv_bot.c)
Bots.Install(require("./bot/BotGame").FromEngine({
	SV = SV,
	W = require("./sv/sv_world"),
	Cvar = Cvar,
	Fs = Fs,
	Collision = require("../shared/Collision"),
	G = G,
	C = C,
	structs = require("../shared/structs"),
}))
SV.Bots = Bots

local Game = {
	G = G,
	SV = SV,
	Cvar = Cvar,
	Cmd = Cmd,
	Fs = Fs,
	MSG = MSG,
	C = C,
	Bots = Bots,
}

-- q_shared's engine calls go to the game module's versions
-- (Com_Printf/Com_Error in g_main.c)
QS.Com_Printf = function(text: string)
	G.Com_Printf("%s", text)
end
QS.Com_Error = function(level: number, text: string)
	G.Com_Error(level, "%s", text)
end

export type InitOptions = {
	-- returns the parsed BSP lumps for maps/<name>.bsp (Collision.LoadMap
	-- input), with `checksum` = map.json's `checksum` (Com_BlockChecksum of
	-- the .bsp, sv_mapChecksum) and `aas` = the map's joined Aas blob, if any
	loadMap: (name: string) -> any,
	-- optional: whether maps/<name>.bsp exists (the "map" command checks it)
	mapExists: ((name: string) -> boolean)?,
	-- optional: files to mount, path -> contents (scripts/*.arena, ...)
	files: { [string]: string }?,
	-- optional: the joined Botfiles blob (tools/pack-botfiles.py), mounted
	-- as botfiles/*
	botfiles: buffer?,
	-- optional: the names of the maps the place carries; each shows up as
	-- an (empty) maps/<name>.bsp so the game's existence checks, map
	-- votes and rotation see it
	maps: { string }?,
	-- optional: console output (default: print)
	print: ((text: string) -> ())?,
	-- optional: millisecond clock (default: os.clock)
	milliseconds: (() -> number)?,
	-- optional: transport send (clientNum, buffer)
	send: ((clientNum: number, data: buffer) -> ())?,
}

function Game.Init(opts: InitOptions)
	if opts.print then
		SV.Com_Printf = opts.print
	end
	if opts.milliseconds then
		SV.Sys_Milliseconds = opts.milliseconds
	end
	if opts.send then
		SV.send = opts.send
	end
	SV.loadMap = opts.loadMap
	SV.mapExists = opts.mapExists
	if opts.files then
		for path, data in opts.files do
			Fs.Mount(path, data)
		end
	end
	if opts.botfiles then
		Bots.MountBotfiles(opts.botfiles, Fs.Mount)
	end
	if opts.maps then
		for _, name in opts.maps do
			Fs.Mount("maps/" .. name .. ".bsp", "")
		end
	end
	SV.SV_Init()
end

-- run console text now (like typing it at the server console)
function Game.Command(text: string)
	Cmd.Cbuf_AddText(text .. "\n")
	Cmd.Cbuf_Execute()
end

-- advance the server by msec of host time
function Game.Frame(msec: number)
	SV.SV_Frame(msec)
end

return Game
