--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (game/bg_local.h, game/bg_pmove.c).

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
-- Shared state of the player movement code (bg_local.h): the current pmove_t
-- and the pml_t locals, plus the movement tunables of bg_pmove.c. Both
-- bg_slidemove and bg_pmove register their functions into this table, the
-- way the C files share one global namespace.

local S = require("../structs")
local Q = require("../q_math")

local B = {}

B.pm = nil :: any -- pmove_t currently being run
B.pml = S.pml_t()
B.c_pmove = 0

local f = Q.f
-- movement parameters (floats in C)
B.pm_stopspeed = 100
B.pm_duckScale = 0.25
B.pm_swimScale = 0.5
B.pm_wadeScale = f(0.7)
B.pm_swimFastScale = 5
B.pm_accelerate = 10
B.pm_airaccelerate = 1
B.pm_wateraccelerate = 4
B.pm_flyaccelerate = 8
B.pm_friction = 6
B.pm_waterfriction = 1
B.pm_flightfriction = 3
B.pm_spectatorfriction = 5

-- leilei: cg_enableQ (map scales the player for Q1 adaptations). Registered
-- by the game / cgame module; bg only reads .value.
B.cg_enableQ = S.vmCvar_t()

-- memset(&pml, 0, sizeof(pml))
local zeroTrace = S.trace_t()
function B.clearPml()
	local pml = B.pml
	local v = pml.forward
	v[0], v[1], v[2] = 0, 0, 0
	v = pml.right
	v[0], v[1], v[2] = 0, 0, 0
	v = pml.up
	v[0], v[1], v[2] = 0, 0, 0
	pml.frametime = 0
	pml.msec = 0
	pml.walking = false
	pml.groundPlane = false
	S.copy_trace_t(pml.groundTrace, zeroTrace)
	pml.impactSpeed = 0
	v = pml.previous_origin
	v[0], v[1], v[2] = 0, 0, 0
	v = pml.previous_velocity
	v[0], v[1], v[2] = 0, 0, 0
	pml.previous_waterlevel = 0
end

return B
