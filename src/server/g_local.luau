--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
OpenArena 0.8.8 source code (gamecode 9e0f0c0, game/g_local.h).

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
-- The game module's global namespace (g_local.h). Every ported g_*.c file
-- does `local G = require("./g_local")` and registers its non-static
-- functions as G.Name; calls between files go through G.Name(...) so the
-- files load in any order. Globals declared in g_local.h (level, g_entities,
-- the vmCvar_t cvars, ...) live here too.

local S = require("./g_structs")
local C = require("./g_defs")

local G = {} :: any

G.MAX_GENTITIES = C.MAX_GENTITIES
G.MAX_CLIENTS = C.MAX_CLIENTS

-- gentity_t g_entities[MAX_GENTITIES] and gclient_t g_clients[MAX_CLIENTS]
-- (the latter is static in g_main.c; level.clients points at it). Each
-- table carries its array index in `.index`, the Luau stand-in for the
-- pointer arithmetic `ent - g_entities` / `client - level.clients`.
G.g_entities = {}
for i = 0, C.MAX_GENTITIES - 1 do
	local e = S.gentity_t()
	e.index = i
	G.g_entities[i] = e
end
G.g_clients = {}
for i = 0, C.MAX_CLIENTS - 1 do
	local c = S.gclient_t()
	c.index = i
	G.g_clients[i] = c
end

G.level = S.level_locals_t()

-- memset(ent, 0, sizeof(*ent)) keeping the table identity and its index
function G.G_ClearEntity(e)
	local index = e.index
	S.copy_gentity_t(e, S.gentity_t())
	e.index = index
end

-- memset(client, 0, sizeof(*client)), same idea
function G.G_ClearClient(c)
	local index = c.index
	S.copy_gclient_t(c, S.gclient_t())
	c.index = index
end

-- ent - g_entities, client - level.clients
function G.ENTNUM(ent): number
	return ent.index
end
function G.CLIENTNUM(client): number
	return client.index
end

-- A C file split across several Luau part files keeps its static functions
-- and variables in one shared per-file table: local SF = G.FileStatics("g_admin")
local fileStatics = {}
function G.FileStatics(cfile: string)
	local t = fileStatics[cfile]
	if not t then
		t = {}
		fileStatics[cfile] = t
	end
	return t
end

return G
