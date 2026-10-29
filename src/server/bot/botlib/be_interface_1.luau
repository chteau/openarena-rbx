--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_interface.c, part 1 of 2).

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
-- Luau port of be_interface.c (botlib/be_interface.c, part 1 of 2): bot library interface.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local Q = require("../../../shared/q_math")
local QS = require("../../../shared/q_shared")

local SF = B.FileStatics("be_interface")

SF.BOTLIB_API_VERSION = 2

--library globals in a structure
B.botlibglobals = SB.botlib_globals_t()

B.be_botlib_export = nil
B.botimport = nil
B.botDeveloper = 0
--1 if the library is setup
B.botlibsetup = 0

-- the engine's Sys_MilliSeconds, which botlib calls directly in C
function B.Sys_MilliSeconds(): number
	return B.botimport.Sys_MilliSeconds()
end

function B.ValidClientNumber(num: number, str: string): boolean
	local botlibglobals = B.botlibglobals
	if num < 0 or num > botlibglobals.maxclients then
		B.botimport.Print(BC.PRT_ERROR, "%s: invalid client number %d, [0, %d]\n", str, num, botlibglobals.maxclients)
		return false
	end
	return true
end

function B.ValidEntityNumber(num: number, str: string): boolean
	local botlibglobals = B.botlibglobals
	if num < 0 or num > botlibglobals.maxentities then
		B.botimport.Print(BC.PRT_ERROR, "%s: invalid entity number %d, [0, %d]\n", str, num, botlibglobals.maxentities)
		return false
	end
	return true
end

function B.BotLibSetup(str: string): boolean
	if B.botlibglobals.botlibsetup == 0 then
		B.botimport.Print(BC.PRT_ERROR, "%s: bot library used before being setup\n", str)
		return false
	end
	return true
end

function B.Export_BotLibSetup(): number
	B.botDeveloper = B.LibVarGetValue("bot_developer")
	SB.copy_botlib_globals_t(B.botlibglobals, SB.botlib_globals_t())

	if B.botDeveloper ~= 0 then
		B.Log_Open("botlib.log")
	end

	B.botimport.Print(BC.PRT_MESSAGE, "------- BotLib Initialization -------\n")

	B.botlibglobals.maxclients = Q.trunc(B.LibVarValue("maxclients", "128"))
	B.botlibglobals.maxentities = Q.trunc(B.LibVarValue("maxentities", "1024"))

	local errnum = B.AAS_Setup() --be_aas_main.c
	if errnum ~= BC.BLERR_NOERROR then
		return errnum
	end
	errnum = B.EA_Setup() --be_ea.c
	if errnum ~= BC.BLERR_NOERROR then
		return errnum
	end
	errnum = B.BotSetupWeaponAI() --be_ai_weap.c
	if errnum ~= BC.BLERR_NOERROR then
		return errnum
	end
	errnum = B.BotSetupGoalAI() --be_ai_goal.c
	if errnum ~= BC.BLERR_NOERROR then
		return errnum
	end
	errnum = B.BotSetupChatAI() --be_ai_chat.c
	if errnum ~= BC.BLERR_NOERROR then
		return errnum
	end
	errnum = B.BotSetupMoveAI() --be_ai_move.c
	if errnum ~= BC.BLERR_NOERROR then
		return errnum
	end

	B.botlibsetup = 1
	B.botlibglobals.botlibsetup = 1

	return BC.BLERR_NOERROR
end

function B.Export_BotLibShutdown(): number
	if not B.BotLibSetup("BotLibShutdown") then
		return BC.BLERR_LIBRARYNOTSETUP
	end
	B.BotShutdownChatAI() --be_ai_chat.c
	B.BotShutdownMoveAI() --be_ai_move.c
	B.BotShutdownGoalAI() --be_ai_goal.c
	B.BotShutdownWeaponAI() --be_ai_weap.c
	B.BotShutdownWeights() --be_ai_weight.c
	B.BotShutdownCharacters() --be_ai_char.c
	--shut down aas
	B.AAS_Shutdown()
	--shut down bot elemantary actions
	B.EA_Shutdown()
	--free all libvars
	B.LibVarDeAllocAll()
	--remove all global defines from the pre compiler
	B.PC_RemoveAllGlobalDefines()

	--shut down library log file
	B.Log_Shutdown()
	B.botlibsetup = 0
	B.botlibglobals.botlibsetup = 0
	-- print any files still open
	B.PC_CheckOpenSourceHandles()
	return BC.BLERR_NOERROR
end

function B.Export_BotLibVarSet(var_name: string, value: string): number
	B.LibVarSet(var_name, value)
	return BC.BLERR_NOERROR
end

function B.Export_BotLibVarGet(var_name: string, size: number): (number, string)
	local varvalue = B.LibVarGetString(var_name)
	local value = QS.Q_strncpyz(varvalue, size)
	return BC.BLERR_NOERROR, value
end

function B.Export_BotLibStartFrame(time: number): number
	if not B.BotLibSetup("BotStartFrame") then
		return BC.BLERR_LIBRARYNOTSETUP
	end
	return B.AAS_StartFrame(time)
end

function B.Export_BotLibLoadMap(mapname: string): number
	if not B.BotLibSetup("BotLoadMap") then
		return BC.BLERR_LIBRARYNOTSETUP
	end
	B.botimport.Print(BC.PRT_MESSAGE, "------------ Map Loading ------------\n")
	--startup AAS for the current map, model and sound index
	local errnum = B.AAS_LoadMap(mapname)
	if errnum ~= BC.BLERR_NOERROR then
		return errnum
	end
	--initialize the items in the level
	B.BotInitLevelItems() --be_ai_goal.h
	B.BotSetBrushModelTypes() --be_ai_move.h
	B.botimport.Print(BC.PRT_MESSAGE, "-------------------------------------\n")
	return BC.BLERR_NOERROR
end

function B.Export_BotLibUpdateEntity(ent: number, state: any): number
	if not B.BotLibSetup("BotUpdateEntity") then
		return BC.BLERR_LIBRARYNOTSETUP
	end
	if not B.ValidEntityNumber(ent, "BotUpdateEntity") then
		return BC.BLERR_INVALIDENTITYNUMBER
	end

	return B.AAS_UpdateEntity(ent, state)
end

return nil
