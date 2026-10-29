--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / ioquake3 source code (botlib/be_ea.c).

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
-- Luau port of be_ea.c: elementary actions that set per-client bot inputs.

local B = require("./b_local")
local BC = require("./consts")
local SB = require("./structs")
local QS = require("../../../shared/q_shared")

local MAX_USERMOVE = 400

function B.EA_Say(client, str)
	B.botimport.BotClientCommand(client, QS.va("say %s", str))
end

function B.EA_SayTeam(client, str)
	B.botimport.BotClientCommand(client, QS.va("say_team %s", str))
end

function B.EA_Tell(client, clientto, str)
	B.botimport.BotClientCommand(client, QS.va("tell %d, %s", clientto, str))
end

function B.EA_UseItem(client, it)
	B.botimport.BotClientCommand(client, QS.va("use %s", it))
end

function B.EA_DropItem(client, it)
	B.botimport.BotClientCommand(client, QS.va("drop %s", it))
end

function B.EA_UseInv(client, inv)
	B.botimport.BotClientCommand(client, QS.va("invuse %s", inv))
end

function B.EA_DropInv(client, inv)
	B.botimport.BotClientCommand(client, QS.va("invdrop %s", inv))
end

function B.EA_Gesture(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_GESTURE)
end

function B.EA_Command(client, command)
	B.botimport.BotClientCommand(client, command)
end

function B.EA_SelectWeapon(client, weapon)
	local bi = B.botinputs[client]

	bi.weapon = weapon
end

function B.EA_Attack(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_ATTACK)
end

function B.EA_Talk(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_TALK)
end

function B.EA_Use(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_USE)
end

function B.EA_Respawn(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_RESPAWN)
end

function B.EA_Jump(client)
	local bi = B.botinputs[client]

	if bit32.band(bi.actionflags, BC.ACTION_JUMPEDLASTFRAME) ~= 0 then
		bi.actionflags = bit32.band(bi.actionflags, bit32.bnot(BC.ACTION_JUMP))
	else
		bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_JUMP)
	end
end

function B.EA_DelayedJump(client)
	local bi = B.botinputs[client]

	if bit32.band(bi.actionflags, BC.ACTION_JUMPEDLASTFRAME) ~= 0 then
		bi.actionflags = bit32.band(bi.actionflags, bit32.bnot(BC.ACTION_DELAYEDJUMP))
	else
		bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_DELAYEDJUMP)
	end
end

function B.EA_Crouch(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_CROUCH)
end

function B.EA_Walk(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_WALK)
end

function B.EA_Action(client, action)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, action)
end

function B.EA_MoveUp(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_MOVEUP)
end

function B.EA_MoveDown(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_MOVEDOWN)
end

function B.EA_MoveForward(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_MOVEFORWARD)
end

function B.EA_MoveBack(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_MOVEBACK)
end

function B.EA_MoveLeft(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_MOVELEFT)
end

function B.EA_MoveRight(client)
	local bi = B.botinputs[client]

	bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_MOVERIGHT)
end

function B.EA_Move(client, dir, speed)
	local bi = B.botinputs[client]

	bi.dir[0] = dir[0]
	bi.dir[1] = dir[1]
	bi.dir[2] = dir[2]
	if speed > MAX_USERMOVE then
		speed = MAX_USERMOVE
	elseif speed < -MAX_USERMOVE then
		speed = -MAX_USERMOVE
	end
	bi.speed = speed
end

function B.EA_View(client, viewangles)
	local bi = B.botinputs[client]

	bi.viewangles[0] = viewangles[0]
	bi.viewangles[1] = viewangles[1]
	bi.viewangles[2] = viewangles[2]
end

function B.EA_EndRegular(client, thinktime)
end

function B.EA_GetInput(client, thinktime, input)
	local bi = B.botinputs[client]

	bi.thinktime = thinktime
	SB.copy_bot_input_t(input, bi)
end

function B.EA_ResetInput(client)
	local bi = B.botinputs[client]

	bi.thinktime = 0
	bi.dir[0] = 0
	bi.dir[1] = 0
	bi.dir[2] = 0
	bi.speed = 0
	local jumped = bit32.band(bi.actionflags, BC.ACTION_JUMP)
	bi.actionflags = 0
	if jumped ~= 0 then
		bi.actionflags = bit32.bor(bi.actionflags, BC.ACTION_JUMPEDLASTFRAME)
	end
end

function B.EA_Setup()
	B.botinputs = {}
	for i = 0, B.botlibglobals.maxclients - 1 do
		B.botinputs[i] = SB.bot_input_t()
	end
	return BC.BLERR_NOERROR
end

function B.EA_Shutdown()
	B.botinputs = nil
end

return nil
