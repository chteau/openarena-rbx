--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/cgame/cg_consolecmds.c (OpenArena 0.8.8, gamecode 9e0f0c0).
-- cg_consolecmds.c -- text commands typed in at the local console, or
-- executed by a key binding

local G = require(script.Parent.G)
local Q = require(script.Parent.Parent.q.Q)
local C = require(script.Parent.Parent.q.Consts)
local trap = require(script.Parent.Parent.sys.Trap)

local function atoi(s: string): number
	local m = string.match(s, "^%s*([-+]?%d+)")
	if m == nil then
		return 0
	end
	return tonumber(m) :: number
end

function G.CG_PrintClientNumbers()
	G.CG_Printf("slot score ping name\n")
	G.CG_Printf("---- ----- ---- ----\n")

	for i = 0, G.cg.numScores - 1 do
		G.CG_Printf(Q.va("%-4d", G.cg.scores[i].client))

		G.CG_Printf(Q.va(" %-5d", G.cg.scores[i].score))

		G.CG_Printf(Q.va(" %-4d", G.cg.scores[i].ping))

		G.CG_Printf(" " .. G.cgs.clientinfo[G.cg.scores[i].client].name .. "\n")
	end
end

function G.CG_TargetCommand_f()
	local targetNum = G.CG_CrosshairPlayer()
	if targetNum == 0 then
		return
	end

	local test = string.sub(trap.Argv(1), 1, 3)
	trap.SendConsoleCommand(Q.va("gc %i %i", targetNum, atoi(test)))
end

-- Keybinding command
local function CG_SizeUp_f()
	trap.Cvar_Set("cg_viewsize", Q.va("%i", Q.int(G.cg_viewsize.integer + 10)))
end

-- Keybinding command
local function CG_SizeDown_f()
	trap.Cvar_Set("cg_viewsize", Q.va("%i", Q.int(G.cg_viewsize.integer - 10)))
end

-- Debugging command to print the current position
local function CG_Viewpos_f()
	G.CG_Printf(Q.va("(%i %i %i) : %i\n", Q.int(G.cg.refdef.vieworg[0]),
		Q.int(G.cg.refdef.vieworg[1]), Q.int(G.cg.refdef.vieworg[2]),
		Q.int(G.cg.refdefViewAngles[C.YAW])))
end

local function CG_ScoresDown_f()
	local cg = G.cg
	if cg.scoresRequestTime + 2000 < cg.time then
		-- the scores are more than two seconds out of data,
		-- so request new ones
		cg.scoresRequestTime = cg.time
		trap.SendClientCommand("score")

		-- leave the current scores up if they were already
		-- displayed, but if this is the first hit, clear them out
		if not cg.showScores then
			cg.showScores = true
			cg.numScores = 0
		end
	else
		-- show the cached contents even if they just pressed if it
		-- is within two seconds
		cg.showScores = true
	end
end

local function CG_ScoresUp_f()
	local cg = G.cg
	if cg.showScores then
		cg.showScores = false
		cg.scoreFadeTime = cg.time
	end
end

local function CG_AccDown_f()
	local cg = G.cg
	if cg.accRequestTime + 2000 < cg.time then
		cg.accRequestTime = cg.time
		trap.SendClientCommand("acc")

		if not cg.showAcc then
			cg.showAcc = true
		end
	else
		cg.showAcc = true
	end
end

local function CG_AccUp_f()
	local cg = G.cg
	if cg.showAcc then
		cg.showAcc = false
		cg.accFadeTime = cg.time
	end
end

local function CG_TellTarget_f()
	local clientNum = G.CG_CrosshairPlayer()
	if clientNum == -1 then
		return
	end

	local message = string.sub(trap.Args(), 1, 127)
	trap.SendClientCommand(string.sub(Q.va("tell %i %s", clientNum, message), 1, 127))
end

local function CG_TellAttacker_f()
	local clientNum = G.CG_LastAttacker()
	if clientNum == -1 then
		return
	end

	local message = string.sub(trap.Args(), 1, 127)
	trap.SendClientCommand(string.sub(Q.va("tell %i %s", clientNum, message), 1, 127))
end

local function CG_VoiceTellTarget_f()
	local clientNum = G.CG_CrosshairPlayer()
	if clientNum == -1 then
		return
	end

	local message = string.sub(trap.Args(), 1, 127)
	trap.SendClientCommand(string.sub(Q.va("vtell %i %s", clientNum, message), 1, 127))
end

local function CG_VoiceTellAttacker_f()
	local clientNum = G.CG_LastAttacker()
	if clientNum == -1 then
		return
	end

	local message = string.sub(trap.Args(), 1, 127)
	trap.SendClientCommand(string.sub(Q.va("vtell %i %s", clientNum, message), 1, 127))
end

local function CG_StartOrbit_f()
	local var = trap.Cvar_VariableStringBuffer("developer")
	if atoi(var) == 0 then
		return
	end
	if G.cg_cameraOrbit.value ~= 0 then
		trap.Cvar_Set("cg_cameraOrbit", "0")
		trap.Cvar_Set("cg_thirdPerson", "0")
	else
		trap.Cvar_Set("cg_cameraOrbit", "5")
		trap.Cvar_Set("cg_thirdPerson", "1")
		trap.Cvar_Set("cg_thirdPersonAngle", "0")
		trap.Cvar_Set("cg_thirdPersonRange", "100")
	end
end

local function viaG(name: string): () -> ()
	return function()
		G[name]()
	end
end

local commands = {
	{ cmd = "testgun", ["function"] = viaG("CG_TestGun_f") },
	{ cmd = "testmodel", ["function"] = viaG("CG_TestModel_f") },
	{ cmd = "nextframe", ["function"] = viaG("CG_TestModelNextFrame_f") },
	{ cmd = "prevframe", ["function"] = viaG("CG_TestModelPrevFrame_f") },
	{ cmd = "nextskin", ["function"] = viaG("CG_TestModelNextSkin_f") },
	{ cmd = "prevskin", ["function"] = viaG("CG_TestModelPrevSkin_f") },
	{ cmd = "viewpos", ["function"] = CG_Viewpos_f },
	{ cmd = "+scores", ["function"] = CG_ScoresDown_f },
	{ cmd = "-scores", ["function"] = CG_ScoresUp_f },
	{ cmd = "+zoom", ["function"] = viaG("CG_ZoomDown_f") },
	{ cmd = "-zoom", ["function"] = viaG("CG_ZoomUp_f") },
	{ cmd = "sizeup", ["function"] = CG_SizeUp_f },
	{ cmd = "sizedown", ["function"] = CG_SizeDown_f },
	{ cmd = "weapnext", ["function"] = viaG("CG_NextWeapon_f") },
	{ cmd = "weapprev", ["function"] = viaG("CG_PrevWeapon_f") },
	{ cmd = "weapon", ["function"] = viaG("CG_Weapon_f") },
	{ cmd = "tell_target", ["function"] = CG_TellTarget_f },
	{ cmd = "tell_attacker", ["function"] = CG_TellAttacker_f },
	{ cmd = "vtell_target", ["function"] = CG_VoiceTellTarget_f },
	{ cmd = "vtell_attacker", ["function"] = CG_VoiceTellAttacker_f },
	{ cmd = "tcmd", ["function"] = viaG("CG_TargetCommand_f") },
	{ cmd = "startOrbit", ["function"] = CG_StartOrbit_f },
	{ cmd = "loaddeferred", ["function"] = viaG("CG_LoadDeferredPlayers") },
	{ cmd = "+acc", ["function"] = CG_AccDown_f },
	{ cmd = "-acc", ["function"] = CG_AccUp_f },
	{ cmd = "clients", ["function"] = viaG("CG_PrintClientNumbers") },
}

-- The string has been tokenized and can be retrieved with
-- Cmd_Argc() / Cmd_Argv()
function G.CG_ConsoleCommand(): boolean
	local cmd = G.CG_Argv(0)

	for i = 1, #commands do
		if Q.stricmp(cmd, commands[i].cmd) == 0 then
			commands[i]["function"]()
			return true
		end
	end

	return false
end

-- Let the client system know about all of our commands
-- so it can perform tab completion
function G.CG_InitConsoleCommands()
	for i = 1, #commands do
		trap.AddCommand(commands[i].cmd)
	end

	-- the game server will interpret these commands, which will be automatically
	-- forwarded to the server after they are not recognized locally
	trap.AddCommand("kill")
	trap.AddCommand("say")
	trap.AddCommand("say_team")
	trap.AddCommand("tell")
	trap.AddCommand("vsay")
	trap.AddCommand("vsay_team")
	trap.AddCommand("vtell")
	trap.AddCommand("vtaunt")
	trap.AddCommand("vosay")
	trap.AddCommand("vosay_team")
	trap.AddCommand("votell")
	trap.AddCommand("give")
	trap.AddCommand("god")
	trap.AddCommand("notarget")
	trap.AddCommand("noclip")
	trap.AddCommand("team")
	trap.AddCommand("follow")
	trap.AddCommand("levelshot")
	trap.AddCommand("addbot")
	trap.AddCommand("setviewpos")
	trap.AddCommand("callvote")
	trap.AddCommand("getmappage")
	trap.AddCommand("vote")
	trap.AddCommand("callteamvote")
	trap.AddCommand("teamvote")
	trap.AddCommand("stats")
	trap.AddCommand("teamtask")
	trap.AddCommand("loaddefered") -- spelled wrong, but not changing for demo
end

return G
