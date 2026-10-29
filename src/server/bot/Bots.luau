--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (the bots: botlib, sv_bot.c and the game's ai_*.c).

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
-- Entry point of the bots. The server loads it after the game module
-- (Game.luau) and installs it with the BotGame adapter:
--
--   local Bots = require(path.to.bot.Bots)
--   Bots.Install(BotGame.FromEngine({ SV = SV, W = W, Cvar = Cvar, Fs = Fs,
--       Collision = Collision, G = G, C = C, structs = structs }))
--   Bots.MountBotfiles(botfilesBuffer, Fs.Mount)   -- botfiles/* for botlib
--
-- Install replaces the game's ai_stubs (BotAISetup, BotAIStartFrame, the
-- trap_AAS_* queries ...) with the ported AI and botlib traps, registers
-- the bot cvars and creates botlib (SV_BotInitCvars + SV_BotInitBotLib,
-- which ioquake3 runs in SV_Init). The engine then calls, like
-- ioquake3's server does:
--   Bots.InitGameProgs()   in SV_InitGameProgs, before the game is created
--   Bots.Frame(sv.time)    every server frame before GAME_RUN_FRAME, and
--                          after each GAME_RUN_FRAME of SV_SpawnServer's settle frames

local SVB = require("./sv_bot")

local Bots = {}
Bots.SVB = SVB

function Bots.Install(adapter)
	SVB.Bind(adapter)
	require("./g_botlib")
	require("./ai_main_1")
	require("./ai_main_2")
	require("./ai_main_3")
	require("./ai_dmq3_1")
	require("./ai_dmq3_2")
	require("./ai_dmq3_3")
	require("./ai_dmq3_4")
	require("./ai_dmq3_5")
	require("./ai_dmq3_6")
	require("./ai_dmq3_7")
	require("./ai_dmnet_1")
	require("./ai_dmnet_2")
	require("./ai_dmnet_3")
	require("./ai_dmnet_4")
	require("./ai_dmnet_5")
	require("./ai_team_1")
	require("./ai_team_2")
	require("./ai_team_3")
	require("./ai_chat_1")
	require("./ai_chat_2")
	require("./ai_cmd_1")
	require("./ai_cmd_2")
	require("./ai_cmd_3")
	require("./ai_vcmd")
	SVB.SV_BotInitCvars()
	SVB.SV_BotInitBotLib()
end

function Bots.InitGameProgs()
	SVB.SV_InitGameProgs()
end

function Bots.Frame(time: number)
	SVB.SV_BotFrame(time)
end

-- Joins a converter-style blob (index module + chunk modules, see the conv
-- branch's docs/formats/luau-blobs.md) given the index's table and a
-- function that returns a chunk's buffer by name.
function Bots.JoinBlob(info: { size: number, chunks: { string } }, chunk: (name: string) -> buffer): buffer
	local out = buffer.create(info.size)
	local o = 0
	for _, name in info.chunks do
		local b = chunk(name)
		buffer.copy(out, o, b)
		o += buffer.len(b)
	end
	assert(o == info.size, "blob size mismatch")
	return out
end

-- Mounts every file of the Botfiles blob (tools/pack-botfiles.py) with
-- mount(path, contents).
function Bots.MountBotfiles(blob: buffer, mount: (path: string, data: string) -> ())
	assert(buffer.readstring(blob, 0, 4) == "OABF", "not a botfiles blob")
	local count = buffer.readu32(blob, 4)
	local o = 8
	for _ = 1, count do
		local plen = buffer.readu16(blob, o)
		local path = buffer.readstring(blob, o + 2, plen)
		o += 2 + plen
		local len = buffer.readu32(blob, o)
		mount(path, buffer.readstring(blob, o + 4, len))
		o += 4 + len
	end
end

return Bots
