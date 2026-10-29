--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/ai_main.c and the botlib trap_AAS_* calls).

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
-- The bot AI (ai_*.c and botlib) is not ported: this file keeps the
-- entry points the game module calls (g_local.h's BotAI* prototypes and
-- the trap_AAS_* queries) so the hooks stay exactly where C has them.
-- With no AAS data loaded, G_BotConnect refuses bots ("bot_enable" or
-- missing AAS), which is what an engine without botlib does as well.

local G = require("./g_local")

-- int BotAISetup( int restart ): qtrue on success
function G.BotAISetup(restart: boolean): number
	return 1
end

function G.BotAIShutdown(restart: boolean): number
	return 1
end

function G.BotAILoadMap(restart: boolean): number
	return 1
end

-- 0 = the client could not be set up (no AAS)
function G.BotAISetupClient(client: number, settings, restart: boolean): number
	return 0
end

function G.BotAIShutdownClient(client: number, restart: boolean): number
	return 1
end

function G.BotAIStartFrame(time: number): number
	return 1
end

function G.BotTestAAS(origin) end

function G.BotInterbreedEndMatch() end

function G.trap_AAS_Initialized(): boolean
	return false
end

function G.trap_AAS_PointReachabilityAreaIndex(point): number
	return 0
end

return G
