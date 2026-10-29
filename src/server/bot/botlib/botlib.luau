--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib).

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
-- Loads every ported botlib file into the botlib namespace and returns
-- it. The engine side talks to botlib like ioquake3's does:
--
--   local B = require(path.to.botlib)
--   local botlib_export = B.GetBotLibAPI(BC.BOTLIB_API_VERSION, botimport)
--   botlib_export.BotLibSetup(), .BotLibLoadMap(name), .aas.AAS_PointAreaNum(p) ...
--
-- botimport is described in docs/bots-notes.md (sv_bot.luau builds it).

local B = require("./b_local")
require("./l_memory")
require("./l_libvar")
require("./l_log")
require("./l_struct")
require("./l_script_1")
require("./l_script_2")
require("./l_precomp_1")
require("./l_precomp_2")
require("./l_precomp_3")
require("./l_precomp_4")
require("./be_aas_main")
require("./be_aas_file")
require("./be_aas_bspq3")
require("./be_aas_sample_1")
require("./be_aas_sample_2")
require("./be_aas_route_1")
require("./be_aas_route_2")
require("./be_aas_route_3")
require("./be_aas_routealt")
require("./be_aas_move_1")
require("./be_aas_move_2")
require("./be_aas_entity")
require("./be_aas_reach")
require("./be_aas_debug")
require("./be_ai_weight_1")
require("./be_ai_weight_2")
require("./be_ai_char")
require("./be_ai_goal_1")
require("./be_ai_goal_2")
require("./be_ai_goal_3")
require("./be_ai_move_1")
require("./be_ai_move_2")
require("./be_ai_move_3")
require("./be_ai_move_4")
require("./be_ai_move_5")
require("./be_ai_weap")
require("./be_ai_chat_1")
require("./be_ai_chat_2")
require("./be_ai_chat_3")
require("./be_ai_chat_4")
require("./be_ai_gen")
require("./be_ea")
require("./be_interface_1")
require("./be_interface_2")
return B
