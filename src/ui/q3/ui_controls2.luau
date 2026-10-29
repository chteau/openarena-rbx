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
-- Luau port of code/q3_ui/ui_controls2.c (OpenArena 0.8.8, gamecode 9e0f0c0).

--[[
=======================================================================

CONTROLS MENU

=======================================================================
]]

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)
local BG = require(script.Parent.Parent.Parent.client.adapters.BG)

local ART_BACK0 = "menu/art_blueish/back_0"
local ART_BACK1 = "menu/art_blueish/back_1"
local ART_FRAMEL = "menu/art_blueish/frame2_l"
local ART_FRAMER = "menu/art_blueish/frame1_r"

-- control sections
local C_MOVEMENT = 0
local C_LOOKING = 1
local C_WEAPONS = 2
local C_MISC = 3
local C_MAX = 4

local ID_MOVEMENT = 100
local ID_LOOKING = 101
local ID_WEAPONS = 102
local ID_MISC = 103
local ID_DEFAULTS = 104
local ID_BACK = 105
local ID_SAVEANDEXIT = 106
local ID_EXIT = 107

-- bindable actions
local ID_SHOWSCORES = 0
local ID_USEITEM = 1
local ID_SPEED = 2
local ID_FORWARD = 3
local ID_BACKPEDAL = 4
local ID_MOVELEFT = 5
local ID_MOVERIGHT = 6
local ID_MOVEUP = 7
local ID_MOVEDOWN = 8
local ID_LEFT = 9
local ID_RIGHT = 10
local ID_STRAFE = 11
local ID_LOOKUP = 12
local ID_LOOKDOWN = 13
local ID_MOUSELOOK = 14
local ID_CENTERVIEW = 15
local ID_ZOOMVIEW = 16
local ID_WEAPON1 = 17
local ID_WEAPON2 = 18
local ID_WEAPON3 = 19
local ID_WEAPON4 = 20
local ID_WEAPON5 = 21
local ID_WEAPON6 = 22
local ID_WEAPON7 = 23
local ID_WEAPON8 = 24
local ID_WEAPON9 = 25
local ID_WEAPON10 = 26
local ID_WEAPON11 = 27
local ID_WEAPON12 = 28
local ID_WEAPON13 = 29
local ID_ATTACK = 30
local ID_WEAPPREV = 31
local ID_WEAPNEXT = 32
local ID_GESTURE = 33
local ID_CHAT = 34
local ID_CHAT2 = 35
local ID_CHAT3 = 36
local ID_CHAT4 = 37
local ID_VOIP_TALK = 38

-- all others
local ID_FREELOOK = 39
local ID_INVERTMOUSE = 40
local ID_ALWAYSRUN = 41
local ID_AUTOSWITCH = 42
local ID_MOUSESPEED = 43
local ID_JOYENABLE = 44
local ID_JOYTHRESHOLD = 45
local ID_SMOOTHMOUSE = 46
local ID_VOIP_TEAMONLY = 47

local ANIM_IDLE = 0
local ANIM_RUN = 1
local ANIM_WALK = 2
local ANIM_BACK = 3
local ANIM_JUMP = 4
local ANIM_CROUCH = 5
local ANIM_STEPLEFT = 6
local ANIM_STEPRIGHT = 7
local ANIM_TURNLEFT = 8
local ANIM_TURNRIGHT = 9
local ANIM_LOOKUP = 10
local ANIM_LOOKDOWN = 11
local ANIM_WEAPON1 = 12
local ANIM_WEAPON2 = 13
local ANIM_WEAPON3 = 14
local ANIM_WEAPON4 = 15
local ANIM_WEAPON5 = 16
local ANIM_WEAPON6 = 17
local ANIM_WEAPON7 = 18
local ANIM_WEAPON8 = 19
local ANIM_WEAPON9 = 20
local ANIM_WEAPON10 = 21
local ANIM_ATTACK = 22
local ANIM_GESTURE = 23
local ANIM_DIE = 24
local ANIM_CHAT = 25
local ANIM_WEAPON11 = 26
local ANIM_WEAPON12 = 27
local ANIM_WEAPON13 = 28

local function chr(s: string): number
	return string.byte(s, 1)
end

local s_controls: any = {}

-- constructors for every member of controls_t that is a menu item or struct
local itemFields = {
	{ "banner", "menutext_s" },
	{ "framel", "menubitmap_s" },
	{ "framer", "menubitmap_s" },
	{ "player", "menubitmap_s" },
	{ "movement", "menutext_s" },
	{ "looking", "menutext_s" },
	{ "weapons", "menutext_s" },
	{ "misc", "menutext_s" },
	{ "walkforward", "menuaction_s" },
	{ "backpedal", "menuaction_s" },
	{ "stepleft", "menuaction_s" },
	{ "stepright", "menuaction_s" },
	{ "moveup", "menuaction_s" },
	{ "movedown", "menuaction_s" },
	{ "turnleft", "menuaction_s" },
	{ "turnright", "menuaction_s" },
	{ "sidestep", "menuaction_s" },
	{ "run", "menuaction_s" },
	{ "machinegun", "menuaction_s" },
	{ "chainsaw", "menuaction_s" },
	{ "shotgun", "menuaction_s" },
	{ "grenadelauncher", "menuaction_s" },
	{ "rocketlauncher", "menuaction_s" },
	{ "lightning", "menuaction_s" },
	{ "railgun", "menuaction_s" },
	{ "plasma", "menuaction_s" },
	{ "bfg", "menuaction_s" },
	{ "grapple", "menuaction_s" },
	{ "nailgun", "menuaction_s" },
	{ "proxmine", "menuaction_s" },
	{ "chaingun", "menuaction_s" },
	{ "attack", "menuaction_s" },
	{ "prevweapon", "menuaction_s" },
	{ "nextweapon", "menuaction_s" },
	{ "lookup", "menuaction_s" },
	{ "lookdown", "menuaction_s" },
	{ "mouselook", "menuaction_s" },
	{ "freelook", "menuradiobutton_s" },
	{ "centerview", "menuaction_s" },
	{ "zoomview", "menuaction_s" },
	{ "gesture", "menuaction_s" },
	{ "invertmouse", "menuradiobutton_s" },
	{ "sensitivity", "menuslider_s" },
	{ "smoothmouse", "menuradiobutton_s" },
	{ "alwaysrun", "menuradiobutton_s" },
	{ "showscores", "menuaction_s" },
	{ "autoswitch", "menulist_s" },
	{ "useitem", "menuaction_s" },
	{ "chat", "menuaction_s" },
	{ "chat2", "menuaction_s" },
	{ "chat3", "menuaction_s" },
	{ "chat4", "menuaction_s" },
	{ "voip_talk", "menuaction_s" },
	{ "voip_teamonly", "menuradiobutton_s" },
	{ "joyenable", "menuradiobutton_s" },
	{ "joythreshold", "menuslider_s" },
	{ "back", "menubitmap_s" },
	{ "name", "menutext_s" },
}

local autoswitch_items = {
	[0] = "NEVER",
	"ALWAYS",
	"NEW",
	"BETTER",
	"NEW&BETTER",
}

local controls_binding_color = Q.vec4(0.58, 0.70, 0.81, 1.00)

local function bind(command: string, label: string, id: number, anim: number, defaultbind1: number)
	return {
		command = command,
		label = label,
		id = id,
		anim = anim,
		defaultbind1 = defaultbind1,
		defaultbind2 = -1,
		bind1 = -1,
		bind2 = -1,
	}
end

local g_bindings = {
	[0] = bind("+scores", "show scores", ID_SHOWSCORES, ANIM_IDLE, C.K_TAB),
	bind("+button2", "use item", ID_USEITEM, ANIM_IDLE, C.K_ENTER),
	bind("+speed", "run / walk", ID_SPEED, ANIM_RUN, C.K_SHIFT),
	bind("+forward", "walk forward", ID_FORWARD, ANIM_WALK, C.K_UPARROW),
	bind("+back", "backpedal", ID_BACKPEDAL, ANIM_BACK, C.K_DOWNARROW),
	bind("+moveleft", "step left", ID_MOVELEFT, ANIM_STEPLEFT, chr(",")),
	bind("+moveright", "step right", ID_MOVERIGHT, ANIM_STEPRIGHT, chr(".")),
	bind("+moveup", "up / jump", ID_MOVEUP, ANIM_JUMP, C.K_SPACE),
	bind("+movedown", "down / crouch", ID_MOVEDOWN, ANIM_CROUCH, chr("c")),
	bind("+left", "turn left", ID_LEFT, ANIM_TURNLEFT, C.K_LEFTARROW),
	bind("+right", "turn right", ID_RIGHT, ANIM_TURNRIGHT, C.K_RIGHTARROW),
	bind("+strafe", "sidestep / turn", ID_STRAFE, ANIM_IDLE, C.K_ALT),
	bind("+lookup", "look up", ID_LOOKUP, ANIM_LOOKUP, C.K_PGDN),
	bind("+lookdown", "look down", ID_LOOKDOWN, ANIM_LOOKDOWN, C.K_DEL),
	bind("+mlook", "mouse look", ID_MOUSELOOK, ANIM_IDLE, chr("/")),
	bind("centerview", "center view", ID_CENTERVIEW, ANIM_IDLE, C.K_END),
	bind("+zoom", "zoom view", ID_ZOOMVIEW, ANIM_IDLE, -1),
	bind("weapon 1", "gauntlet", ID_WEAPON1, ANIM_WEAPON1, chr("1")),
	bind("weapon 2", "machinegun", ID_WEAPON2, ANIM_WEAPON2, chr("2")),
	bind("weapon 3", "shotgun", ID_WEAPON3, ANIM_WEAPON3, chr("3")),
	bind("weapon 4", "grenade launcher", ID_WEAPON4, ANIM_WEAPON4, chr("4")),
	bind("weapon 5", "rocket launcher", ID_WEAPON5, ANIM_WEAPON5, chr("5")),
	bind("weapon 6", "lightning", ID_WEAPON6, ANIM_WEAPON6, chr("6")),
	bind("weapon 7", "railgun", ID_WEAPON7, ANIM_WEAPON7, chr("7")),
	bind("weapon 8", "plasma gun", ID_WEAPON8, ANIM_WEAPON8, chr("8")),
	bind("weapon 9", "BFG", ID_WEAPON9, ANIM_WEAPON9, chr("9")),
	bind("weapon 10", "Grapple", ID_WEAPON10, ANIM_WEAPON10, -1),
	bind("weapon 11", "nailgun", ID_WEAPON11, ANIM_WEAPON11, -1),
	bind("weapon 12", "mine Launcher", ID_WEAPON12, ANIM_WEAPON12, -1),
	bind("weapon 13", "chaingun", ID_WEAPON13, ANIM_WEAPON13, -1),
	bind("+attack", "attack", ID_ATTACK, ANIM_ATTACK, C.K_CTRL),
	bind("weapprev", "prev weapon", ID_WEAPPREV, ANIM_IDLE, chr("[")),
	bind("weapnext", "next weapon", ID_WEAPNEXT, ANIM_IDLE, chr("]")),
	bind("+button3", "gesture", ID_GESTURE, ANIM_GESTURE, C.K_MOUSE3),
	bind("messagemode", "chat", ID_CHAT, ANIM_CHAT, chr("t")),
	bind("messagemode2", "chat - team", ID_CHAT2, ANIM_CHAT, -1),
	bind("messagemode3", "chat - target", ID_CHAT3, ANIM_CHAT, -1),
	bind("messagemode4", "chat - attacker", ID_CHAT4, ANIM_CHAT, -1),
	bind("+voiprecord", "voice chat", ID_VOIP_TALK, ANIM_CHAT, chr("q")),
}

local function cfg(name: string)
	return { name = name, defaultvalue = 0, value = 0 }
end

local g_configcvars = {
	[0] = cfg("cl_run"),
	cfg("m_pitch"),
	cfg("cg_autoswitch"),
	cfg("sensitivity"),
	cfg("in_joystick"),
	cfg("joy_threshold"),
	cfg("m_filter"),
	cfg("cl_freelook"),
	cfg("cg_voipTeamOnly"),
}

-- control groups, as 0-based arrays of s_controls member names
local g_movement_controls = {
	[0] = "alwaysrun",
	"run",
	"walkforward",
	"backpedal",
	"stepleft",
	"stepright",
	"moveup",
	"movedown",
	"turnleft",
	"turnright",
	"sidestep",
}

local g_weapons_controls = {
	[0] = "attack",
	"nextweapon",
	"prevweapon",
	"autoswitch",
	"chainsaw",
	"machinegun",
	"shotgun",
	"grenadelauncher",
	"rocketlauncher",
	"lightning",
	"railgun",
	"plasma",
	"bfg",
	"grapple",
	"nailgun",
	"proxmine",
	"chaingun",
}

local g_looking_controls = {
	[0] = "sensitivity",
	"smoothmouse",
	"invertmouse",
	"lookup",
	"lookdown",
	"mouselook",
	"freelook",
	"centerview",
	"zoomview",
	"joyenable",
	"joythreshold",
}

local g_misc_controls = {
	[0] = "showscores",
	"useitem",
	"gesture",
	"chat",
	"chat2",
	"chat3",
	"chat4",
	"voip_talk",
	"voip_teamonly",
}

local g_controls = {
	[0] = g_movement_controls,
	g_looking_controls,
	g_weapons_controls,
	g_misc_controls,
}

local function groupSize(group: any): number
	local n = 0
	while group[n] ~= nil do
		n += 1
	end
	return n
end

local function setFlag(item: any, flags: number)
	item.flags = bit32.bor(item.flags, flags)
end

local function clearFlag(item: any, flags: number)
	item.flags = bit32.band(item.flags, bit32.bnot(flags))
end

local Controls_Update
local Controls_Cache

local function Controls_InitCvars()
	local i = 0
	while g_configcvars[i] ~= nil do
		local cvarptr = g_configcvars[i]
		-- get current value
		cvarptr.value = trap.Cvar_VariableValue(cvarptr.name)

		-- get default value
		trap.Cvar_Reset(cvarptr.name)
		cvarptr.defaultvalue = trap.Cvar_VariableValue(cvarptr.name)

		-- restore current value
		trap.Cvar_SetValue(cvarptr.name, cvarptr.value)
		i += 1
	end
end

local function Controls_GetCvarDefault(name: string): number
	local i = 0
	while g_configcvars[i] ~= nil do
		if g_configcvars[i].name == name then
			return g_configcvars[i].defaultvalue
		end
		i += 1
	end
	return 0
end

local function Controls_GetCvarValue(name: string): number
	local i = 0
	while g_configcvars[i] ~= nil do
		if g_configcvars[i].name == name then
			return g_configcvars[i].value
		end
		i += 1
	end
	return 0
end

local function Controls_UpdateModel(anim: number)
	Q.VectorClear(s_controls.playerViewangles)
	Q.VectorClear(s_controls.playerMoveangles)
	s_controls.playerViewangles[C.YAW] = 180 - 30
	s_controls.playerMoveangles[C.YAW] = s_controls.playerViewangles[C.YAW]
	s_controls.playerLegs = C.LEGS_IDLE
	s_controls.playerTorso = C.TORSO_STAND
	s_controls.playerWeapon = -1
	s_controls.playerChat = false

	if anim == ANIM_RUN then
		s_controls.playerLegs = C.LEGS_RUN
	elseif anim == ANIM_WALK then
		s_controls.playerLegs = C.LEGS_WALK
	elseif anim == ANIM_BACK then
		s_controls.playerLegs = C.LEGS_BACK
	elseif anim == ANIM_JUMP then
		s_controls.playerLegs = C.LEGS_JUMP
	elseif anim == ANIM_CROUCH then
		s_controls.playerLegs = C.LEGS_IDLECR
	elseif anim == ANIM_TURNLEFT then
		s_controls.playerViewangles[C.YAW] += 90
	elseif anim == ANIM_TURNRIGHT then
		s_controls.playerViewangles[C.YAW] -= 90
	elseif anim == ANIM_STEPLEFT then
		s_controls.playerLegs = C.LEGS_WALK
		s_controls.playerMoveangles[C.YAW] = s_controls.playerViewangles[C.YAW] + 90
	elseif anim == ANIM_STEPRIGHT then
		s_controls.playerLegs = C.LEGS_WALK
		s_controls.playerMoveangles[C.YAW] = s_controls.playerViewangles[C.YAW] - 90
	elseif anim == ANIM_LOOKUP then
		s_controls.playerViewangles[C.PITCH] = -45
	elseif anim == ANIM_LOOKDOWN then
		s_controls.playerViewangles[C.PITCH] = 45
	elseif anim == ANIM_WEAPON1 then
		s_controls.playerWeapon = C.WP_GAUNTLET
	elseif anim == ANIM_WEAPON2 then
		s_controls.playerWeapon = C.WP_MACHINEGUN
	elseif anim == ANIM_WEAPON3 then
		s_controls.playerWeapon = C.WP_SHOTGUN
	elseif anim == ANIM_WEAPON4 then
		s_controls.playerWeapon = C.WP_GRENADE_LAUNCHER
	elseif anim == ANIM_WEAPON5 then
		s_controls.playerWeapon = C.WP_ROCKET_LAUNCHER
	elseif anim == ANIM_WEAPON6 then
		s_controls.playerWeapon = C.WP_LIGHTNING
	elseif anim == ANIM_WEAPON7 then
		s_controls.playerWeapon = C.WP_RAILGUN
	elseif anim == ANIM_WEAPON8 then
		s_controls.playerWeapon = C.WP_PLASMAGUN
	elseif anim == ANIM_WEAPON9 then
		s_controls.playerWeapon = C.WP_BFG
	elseif anim == ANIM_WEAPON10 then
		s_controls.playerWeapon = C.WP_GRAPPLING_HOOK
	elseif anim == ANIM_WEAPON11 then
		s_controls.playerWeapon = C.WP_NAILGUN
	elseif anim == ANIM_WEAPON12 then
		s_controls.playerWeapon = C.WP_PROX_LAUNCHER
	elseif anim == ANIM_WEAPON13 then
		s_controls.playerWeapon = C.WP_CHAINGUN
	elseif anim == ANIM_ATTACK then
		s_controls.playerTorso = C.TORSO_ATTACK
	elseif anim == ANIM_GESTURE then
		s_controls.playerTorso = C.TORSO_GESTURE
	elseif anim == ANIM_DIE then
		s_controls.playerLegs = C.BOTH_DEATH1
		s_controls.playerTorso = C.BOTH_DEATH1
		s_controls.playerWeapon = C.WP_NONE
	elseif anim == ANIM_CHAT then
		s_controls.playerChat = true
	end

	U.UI_PlayerInfo_SetInfo(
		s_controls.playerinfo,
		s_controls.playerLegs,
		s_controls.playerTorso,
		s_controls.playerViewangles,
		s_controls.playerMoveangles,
		s_controls.playerWeapon,
		s_controls.playerChat
	)
end

Controls_Update = function()
	local j

	-- disable all controls in all groups
	for i = 0, C_MAX - 1 do
		local group = g_controls[i]
		j = 0
		while group[j] ~= nil do
			setFlag(s_controls[group[j]].generic, bit32.bor(C.QMF_HIDDEN, C.QMF_INACTIVE))
			j += 1
		end
	end

	local group = g_controls[s_controls.section]

	-- enable controls in active group (and count number of items for vertical centering)
	j = 0
	while group[j] ~= nil do
		clearFlag(
			s_controls[group[j]].generic,
			bit32.bor(C.QMF_GRAYED, C.QMF_HIDDEN, C.QMF_INACTIVE)
		)
		j += 1
	end

	-- position controls
	local y = Q.idiv(C.SCREEN_HEIGHT - j * C.SMALLCHAR_HEIGHT, 2)
	j = 0
	while group[j] ~= nil do
		local control = s_controls[group[j]].generic
		control.x = 320
		control.y = y
		control.left = 320 - 19 * C.SMALLCHAR_WIDTH
		control.right = 320 + 21 * C.SMALLCHAR_WIDTH
		control.top = y
		control.bottom = y + C.SMALLCHAR_HEIGHT
		j += 1
		y += C.SMALLCHAR_HEIGHT
	end

	if s_controls.waitingforkey then
		-- disable everybody
		for i = 0, s_controls.menu.nitems - 1 do
			setFlag(s_controls.menu.items[i].generic, C.QMF_GRAYED)
		end

		-- enable action item
		clearFlag(s_controls.menu.items[s_controls.menu.cursor].generic, C.QMF_GRAYED)

		-- don't gray out player's name
		clearFlag(s_controls.name.generic, C.QMF_GRAYED)

		return
	end

	-- enable everybody
	for i = 0, s_controls.menu.nitems - 1 do
		clearFlag(s_controls.menu.items[i].generic, C.QMF_GRAYED)
	end

	-- makes sure flags are right on the group selection controls
	local hl = bit32.bor(C.QMF_GRAYED, C.QMF_HIGHLIGHT, C.QMF_HIGHLIGHT_IF_FOCUS)
	clearFlag(s_controls.looking.generic, hl)
	clearFlag(s_controls.movement.generic, hl)
	clearFlag(s_controls.weapons.generic, hl)
	clearFlag(s_controls.misc.generic, hl)

	setFlag(s_controls.looking.generic, C.QMF_PULSEIFFOCUS)
	setFlag(s_controls.movement.generic, C.QMF_PULSEIFFOCUS)
	setFlag(s_controls.weapons.generic, C.QMF_PULSEIFFOCUS)
	setFlag(s_controls.misc.generic, C.QMF_PULSEIFFOCUS)

	-- set buttons
	local active
	if s_controls.section == C_MOVEMENT then
		active = s_controls.movement
	elseif s_controls.section == C_LOOKING then
		active = s_controls.looking
	elseif s_controls.section == C_WEAPONS then
		active = s_controls.weapons
	elseif s_controls.section == C_MISC then
		active = s_controls.misc
	end
	if active ~= nil then
		clearFlag(active.generic, C.QMF_PULSEIFFOCUS)
		setFlag(active.generic, bit32.bor(C.QMF_HIGHLIGHT, C.QMF_HIGHLIGHT_IF_FOCUS))
	end
end

local function Controls_DrawKeyBinding(self: any)
	local a = self

	local x = a.generic.x
	local y = a.generic.y

	local c = (U.Menu_ItemAtCursor(a.generic.parent) == a)

	local name
	local b1 = g_bindings[a.generic.id].bind1
	if b1 == -1 then
		name = "???"
	else
		name = string.upper(trap.Key_KeynumToStringBuf(b1))

		local b2 = g_bindings[a.generic.id].bind2
		if b2 ~= -1 then
			local name2 = string.upper(trap.Key_KeynumToStringBuf(b2))
			name = name .. " or " .. name2
		end
	end

	local label = g_bindings[a.generic.id].label
	if c then
		U.UI_FillRect(
			a.generic.left,
			a.generic.top,
			a.generic.right - a.generic.left + 1,
			a.generic.bottom - a.generic.top + 1,
			U.listbar_color
		)

		U.UI_DrawString(x - C.SMALLCHAR_WIDTH, y, label, bit32.bor(C.UI_RIGHT, C.UI_SMALLFONT), U.text_color_highlight)
		U.UI_DrawString(
			x + C.SMALLCHAR_WIDTH,
			y,
			name,
			bit32.bor(C.UI_LEFT, C.UI_SMALLFONT, C.UI_PULSE),
			U.text_color_highlight
		)

		if s_controls.waitingforkey then
			U.UI_DrawChar(
				x,
				y,
				chr("="),
				bit32.bor(C.UI_CENTER, C.UI_BLINK, C.UI_SMALLFONT),
				U.text_color_highlight
			)
			U.UI_DrawString(
				C.SCREEN_WIDTH * 0.50,
				C.SCREEN_HEIGHT * 0.80,
				"Waiting for new key ... ESCAPE to cancel",
				bit32.bor(C.UI_SMALLFONT, C.UI_CENTER, C.UI_PULSE),
				Q.colorWhite
			)
		else
			U.UI_DrawChar(x, y, 13, bit32.bor(C.UI_CENTER, C.UI_BLINK, C.UI_SMALLFONT), U.text_color_highlight)
			U.UI_DrawString(
				C.SCREEN_WIDTH * 0.50,
				C.SCREEN_HEIGHT * 0.78,
				"Press ENTER or CLICK to change",
				bit32.bor(C.UI_SMALLFONT, C.UI_CENTER),
				Q.colorWhite
			)
			U.UI_DrawString(
				C.SCREEN_WIDTH * 0.50,
				C.SCREEN_HEIGHT * 0.82,
				"Press BACKSPACE to clear",
				bit32.bor(C.UI_SMALLFONT, C.UI_CENTER),
				Q.colorWhite
			)
		end
	else
		if bit32.band(a.generic.flags, C.QMF_GRAYED) ~= 0 then
			U.UI_DrawString(x - C.SMALLCHAR_WIDTH, y, label, bit32.bor(C.UI_RIGHT, C.UI_SMALLFONT), U.text_color_disabled)
			U.UI_DrawString(x + C.SMALLCHAR_WIDTH, y, name, bit32.bor(C.UI_LEFT, C.UI_SMALLFONT), U.text_color_disabled)
		else
			U.UI_DrawString(x - C.SMALLCHAR_WIDTH, y, label, bit32.bor(C.UI_RIGHT, C.UI_SMALLFONT), controls_binding_color)
			U.UI_DrawString(x + C.SMALLCHAR_WIDTH, y, name, bit32.bor(C.UI_LEFT, C.UI_SMALLFONT), controls_binding_color)
		end
	end
end

local function Controls_StatusBar(self: any)
	U.UI_DrawString(
		C.SCREEN_WIDTH * 0.50,
		C.SCREEN_HEIGHT * 0.80,
		"Use Arrow Keys or CLICK to change",
		bit32.bor(C.UI_SMALLFONT, C.UI_CENTER),
		Q.colorWhite
	)
end

local function Controls_DrawPlayer(self: any)
	local buf = trap.Cvar_VariableStringBuffer("model")
	if buf ~= s_controls.playerModel then
		U.UI_PlayerInfo_SetModel(s_controls.playerinfo, buf)
		s_controls.playerModel = buf
		Controls_UpdateModel(ANIM_IDLE)
	end

	local b = self
	U.UI_DrawPlayer(b.generic.x, b.generic.y, b.width, b.height, s_controls.playerinfo, Q.idiv(U.uis.realtime, 2))
end

local function Controls_GetKeyAssignment(command: string, twokeys: any)
	twokeys[0] = -1
	twokeys[1] = -1
	local count = 0

	for j = 0, 255 do
		local b = trap.Key_GetBindingBuf(j)
		if b ~= "" and Q.stricmp(b, command) == 0 then
			twokeys[count] = j
			count += 1
			if count == 2 then
				break
			end
		end
	end
end

local function Controls_GetConfig()
	local twokeys = { [0] = -1, -1 }

	-- put the bindings into a local store
	-- iterate each command, get its numeric binding
	local i = 0
	while g_bindings[i] ~= nil do
		local bindptr = g_bindings[i]
		Controls_GetKeyAssignment(bindptr.command, twokeys)

		bindptr.bind1 = twokeys[0]
		bindptr.bind2 = twokeys[1]
		i += 1
	end

	s_controls.invertmouse.curvalue = Q.b2i(Controls_GetCvarValue("m_pitch") < 0)
	s_controls.smoothmouse.curvalue = U.UI_ClampCvar(0, 1, Controls_GetCvarValue("m_filter"))
	s_controls.alwaysrun.curvalue = U.UI_ClampCvar(0, 1, Controls_GetCvarValue("cl_run"))
	s_controls.autoswitch.curvalue = U.UI_ClampCvar(0, 4, Controls_GetCvarValue("cg_autoswitch"))
	s_controls.sensitivity.curvalue = U.UI_ClampCvar(2, 30, Controls_GetCvarValue("sensitivity"))
	s_controls.joyenable.curvalue = U.UI_ClampCvar(0, 1, Controls_GetCvarValue("in_joystick"))
	s_controls.joythreshold.curvalue = U.UI_ClampCvar(0.05, 0.75, Controls_GetCvarValue("joy_threshold"))
	s_controls.freelook.curvalue = U.UI_ClampCvar(0, 1, Controls_GetCvarValue("cl_freelook"))
	s_controls.voip_teamonly.curvalue = U.UI_ClampCvar(0, 1, Controls_GetCvarValue("cg_voipTeamOnly"))
end

local function Controls_SetConfig()
	-- set the bindings from the local store
	local i = 0
	while g_bindings[i] ~= nil do
		local bindptr = g_bindings[i]
		if bindptr.bind1 ~= -1 then
			trap.Key_SetBinding(bindptr.bind1, bindptr.command)

			if bindptr.bind2 ~= -1 then
				trap.Key_SetBinding(bindptr.bind2, bindptr.command)
			end
		end
		i += 1
	end

	if s_controls.invertmouse.curvalue ~= 0 then
		trap.Cvar_SetValue("m_pitch", -math.abs(trap.Cvar_VariableValue("m_pitch")))
	else
		trap.Cvar_SetValue("m_pitch", math.abs(trap.Cvar_VariableValue("m_pitch")))
	end

	trap.Cvar_SetValue("m_filter", s_controls.smoothmouse.curvalue)
	trap.Cvar_SetValue("cl_run", s_controls.alwaysrun.curvalue)
	trap.Cvar_SetValue("cg_autoswitch", s_controls.autoswitch.curvalue)
	trap.Cvar_SetValue("sensitivity", s_controls.sensitivity.curvalue)
	trap.Cvar_SetValue("in_joystick", s_controls.joyenable.curvalue)
	trap.Cvar_SetValue("joy_threshold", s_controls.joythreshold.curvalue)
	trap.Cvar_SetValue("cl_freelook", s_controls.freelook.curvalue)
	trap.Cvar_SetValue("cg_voipTeamOnly", s_controls.voip_teamonly.curvalue)
	trap.Cmd_ExecuteText(C.EXEC_APPEND, "in_restart\n")
end

local function Controls_SetDefaults()
	-- set the bindings from the local store
	local i = 0
	while g_bindings[i] ~= nil do
		local bindptr = g_bindings[i]
		bindptr.bind1 = bindptr.defaultbind1
		bindptr.bind2 = bindptr.defaultbind2
		i += 1
	end

	s_controls.invertmouse.curvalue = Q.b2i(Controls_GetCvarDefault("m_pitch") < 0)
	s_controls.smoothmouse.curvalue = Controls_GetCvarDefault("m_filter")
	s_controls.alwaysrun.curvalue = Controls_GetCvarDefault("cl_run")
	s_controls.autoswitch.curvalue = Controls_GetCvarDefault("cg_autoswitch")
	s_controls.sensitivity.curvalue = Controls_GetCvarDefault("sensitivity")
	s_controls.joyenable.curvalue = Controls_GetCvarDefault("in_joystick")
	s_controls.joythreshold.curvalue = Controls_GetCvarDefault("joy_threshold")
	s_controls.freelook.curvalue = Controls_GetCvarDefault("cl_freelook")
	s_controls.voip_teamonly.curvalue = Controls_GetCvarDefault("cg_voipTeamOnly")
end

local function Controls_MenuKey(key: number)
	local found = false

	local ignore = false
	if not s_controls.waitingforkey then
		if key == C.K_BACKSPACE or key == C.K_DEL or key == C.K_KP_DEL then
			key = -1
		elseif key == C.K_MOUSE2 or key == C.K_ESCAPE then
			if s_controls.changesmade then
				Controls_SetConfig()
			end
			ignore = true
		else
			ignore = true
		end
	else
		if bit32.band(key, C.K_CHAR_FLAG) ~= 0 then
			ignore = true
		elseif key == C.K_ESCAPE then
			s_controls.waitingforkey = false
			Controls_Update()
			return U.menu_out_sound
		elseif key == chr("`") then
			ignore = true
		end
	end

	if ignore then
		return U.Menu_DefaultKey(s_controls.menu, key)
	end

	s_controls.changesmade = true

	if key ~= -1 then
		-- remove from any other bind
		local i = 0
		while g_bindings[i] ~= nil do
			local bindptr = g_bindings[i]
			if bindptr.bind2 == key then
				bindptr.bind2 = -1
			end

			if bindptr.bind1 == key then
				bindptr.bind1 = bindptr.bind2
				bindptr.bind2 = -1
			end
			i += 1
		end
	end

	-- assign key to local store
	local id = s_controls.menu.items[s_controls.menu.cursor].generic.id
	local i = 0
	while g_bindings[i] ~= nil do
		local bindptr = g_bindings[i]
		if bindptr.id == id then
			found = true
			if key == -1 then
				if bindptr.bind1 ~= -1 then
					trap.Key_SetBinding(bindptr.bind1, "")
					bindptr.bind1 = -1
				end
				if bindptr.bind2 ~= -1 then
					trap.Key_SetBinding(bindptr.bind2, "")
					bindptr.bind2 = -1
				end
			elseif bindptr.bind1 == -1 then
				bindptr.bind1 = key
			elseif bindptr.bind1 ~= key and bindptr.bind2 == -1 then
				bindptr.bind2 = key
			else
				trap.Key_SetBinding(bindptr.bind1, "")
				trap.Key_SetBinding(bindptr.bind2, "")
				bindptr.bind1 = key
				bindptr.bind2 = -1
			end
			break
		end
		i += 1
	end

	s_controls.waitingforkey = false

	if found then
		Controls_Update()
		return U.menu_out_sound
	end

	return U.Menu_DefaultKey(s_controls.menu, key)
end

local function Controls_ResetDefaults_Action(result: boolean)
	if not result then
		return
	end

	s_controls.changesmade = true
	Controls_SetDefaults()
	Controls_Update()
end

local function Controls_ResetDefaults_Draw()
	U.UI_DrawProportionalString(
		C.SCREEN_WIDTH / 2,
		356 + C.PROP_HEIGHT * 0,
		"WARNING: This will reset all",
		bit32.bor(C.UI_CENTER, C.UI_SMALLFONT),
		U.color_yellow
	)
	U.UI_DrawProportionalString(
		C.SCREEN_WIDTH / 2,
		356 + C.PROP_HEIGHT * 1,
		"controls to their default values.",
		bit32.bor(C.UI_CENTER, C.UI_SMALLFONT),
		U.color_yellow
	)
end

local function Controls_MenuEvent(ptr: any, event: number)
	local id = ptr.generic.id
	if id == ID_MOVEMENT then
		if event == C.QM_ACTIVATED then
			s_controls.section = C_MOVEMENT
			Controls_Update()
		end
	elseif id == ID_LOOKING then
		if event == C.QM_ACTIVATED then
			s_controls.section = C_LOOKING
			Controls_Update()
		end
	elseif id == ID_WEAPONS then
		if event == C.QM_ACTIVATED then
			s_controls.section = C_WEAPONS
			Controls_Update()
		end
	elseif id == ID_MISC then
		if event == C.QM_ACTIVATED then
			s_controls.section = C_MISC
			Controls_Update()
		end
	elseif id == ID_DEFAULTS then
		if event == C.QM_ACTIVATED then
			U.UI_ConfirmMenu("SET TO DEFAULTS?", Controls_ResetDefaults_Draw, Controls_ResetDefaults_Action)
		end
	elseif id == ID_BACK then
		if event == C.QM_ACTIVATED then
			if s_controls.changesmade then
				Controls_SetConfig()
			end
			U.UI_PopMenu()
		end
	elseif id == ID_SAVEANDEXIT then
		if event == C.QM_ACTIVATED then
			Controls_SetConfig()
			U.UI_PopMenu()
		end
	elseif id == ID_EXIT then
		if event == C.QM_ACTIVATED then
			U.UI_PopMenu()
		end
	elseif
		id == ID_FREELOOK
		or id == ID_MOUSESPEED
		or id == ID_INVERTMOUSE
		or id == ID_SMOOTHMOUSE
		or id == ID_ALWAYSRUN
		or id == ID_AUTOSWITCH
		or id == ID_VOIP_TEAMONLY
		or id == ID_JOYENABLE
		or id == ID_JOYTHRESHOLD
	then
		if event == C.QM_ACTIVATED then
			s_controls.changesmade = true
		end
	end
end

local function Controls_ActionEvent(ptr: any, event: number)
	if event == C.QM_LOSTFOCUS then
		Controls_UpdateModel(ANIM_IDLE)
	elseif event == C.QM_GOTFOCUS then
		Controls_UpdateModel(g_bindings[ptr.generic.id].anim)
	elseif event == C.QM_ACTIVATED and not s_controls.waitingforkey then
		s_controls.waitingforkey = true
		Controls_Update()
	end
end

local function Controls_InitModel()
	s_controls.playerinfo = T.playerInfo_t()

	U.UI_PlayerInfo_SetModel(s_controls.playerinfo, U.UI_Cvar_VariableString("model"))

	Controls_UpdateModel(ANIM_IDLE)
end

local function Controls_InitWeapons()
	local i = 1
	while true do
		local item = BG.bg_itemlist[i]
		if item == nil or item.classname == nil or item.classname == "" then
			break
		end
		if item.giType == C.IT_WEAPON then
			trap.R_RegisterModel(item.world_model[0])
		end
		i += 1
	end
end

local function Controls_Menu_AddPText(menutext: any, y: number, id: number, text: string): number
	menutext.generic.type = C.MTYPE_PTEXT
	menutext.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	menutext.generic.callback = Controls_MenuEvent
	menutext.generic.id = id
	menutext.generic.x = 152
	menutext.generic.y = y
	menutext.string = text
	menutext.color = U.color_red
	menutext.style = C.UI_RIGHT

	return y + C.PROP_HEIGHT
end

local ACTION_FLAGS = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS, C.QMF_GRAYED, C.QMF_HIDDEN)

local function initAction(item: any, id: number, flags: number?)
	item.generic.type = C.MTYPE_ACTION
	item.generic.flags = flags or ACTION_FLAGS
	item.generic.callback = Controls_ActionEvent
	item.generic.ownerdraw = Controls_DrawKeyBinding
	item.generic.id = id
end

local function initRadio(item: any, name: string, id: number)
	item.generic.type = C.MTYPE_RADIOBUTTON
	item.generic.flags = C.QMF_SMALLFONT
	item.generic.x = C.SCREEN_WIDTH / 2
	item.generic.name = name
	item.generic.id = id
	item.generic.callback = Controls_MenuEvent
	item.generic.statusbar = Controls_StatusBar
end

local function Controls_MenuInit()
	local playername

	-- zero set all our globals
	s_controls = {}
	s_controls.menu = T.menuframework_s()
	for _, f in itemFields do
		s_controls[f[1]] = T[f[2]]()
	end
	s_controls.playerinfo = T.playerInfo_t()
	s_controls.changesmade = false
	s_controls.section = 0
	s_controls.waitingforkey = false
	s_controls.playerModel = ""
	s_controls.playerViewangles = Q.vec3(0, 0, 0)
	s_controls.playerMoveangles = Q.vec3(0, 0, 0)
	s_controls.playerLegs = 0
	s_controls.playerTorso = 0
	s_controls.playerWeapon = 0
	s_controls.playerChat = false

	Controls_Cache()

	s_controls.menu.key = Controls_MenuKey
	s_controls.menu.wrapAround = true
	s_controls.menu.fullscreen = true

	s_controls.banner.generic.type = C.MTYPE_BTEXT
	s_controls.banner.generic.flags = C.QMF_CENTER_JUSTIFY
	s_controls.banner.generic.x = 320
	s_controls.banner.generic.y = 16
	s_controls.banner.string = "CONTROLS"
	s_controls.banner.color = U.color_white
	s_controls.banner.style = C.UI_CENTER

	s_controls.framel.generic.type = C.MTYPE_BITMAP
	s_controls.framel.generic.name = ART_FRAMEL
	s_controls.framel.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	s_controls.framel.generic.x = 0
	s_controls.framel.generic.y = 78
	s_controls.framel.width = 256
	s_controls.framel.height = 329

	s_controls.framer.generic.type = C.MTYPE_BITMAP
	s_controls.framer.generic.name = ART_FRAMER
	s_controls.framer.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	s_controls.framer.generic.x = 376
	s_controls.framer.generic.y = 76
	s_controls.framer.width = 256
	s_controls.framer.height = 334

	local y = 240 - 2 * C.PROP_HEIGHT

	y = Controls_Menu_AddPText(s_controls.looking, y, ID_LOOKING, "LOOK")
	y = Controls_Menu_AddPText(s_controls.movement, y, ID_MOVEMENT, "MOVE")
	y = Controls_Menu_AddPText(s_controls.weapons, y, ID_WEAPONS, "SHOOT")
	y = Controls_Menu_AddPText(s_controls.misc, y, ID_MISC, "MISC")

	s_controls.back.generic.type = C.MTYPE_BITMAP
	s_controls.back.generic.name = ART_BACK0
	s_controls.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_controls.back.generic.x = 0
	s_controls.back.generic.y = 480 - 64
	s_controls.back.generic.id = ID_BACK
	s_controls.back.generic.callback = Controls_MenuEvent
	s_controls.back.width = 128
	s_controls.back.height = 64
	s_controls.back.focuspic = ART_BACK1

	s_controls.player.generic.type = C.MTYPE_BITMAP
	s_controls.player.generic.flags = C.QMF_INACTIVE
	s_controls.player.generic.ownerdraw = Controls_DrawPlayer
	s_controls.player.generic.x = 400
	s_controls.player.generic.y = -40
	s_controls.player.width = 32 * 10
	s_controls.player.height = 56 * 10

	initAction(s_controls.walkforward, ID_FORWARD)
	initAction(s_controls.backpedal, ID_BACKPEDAL)
	initAction(s_controls.stepleft, ID_MOVELEFT)
	initAction(s_controls.stepright, ID_MOVERIGHT)
	initAction(s_controls.moveup, ID_MOVEUP)
	initAction(s_controls.movedown, ID_MOVEDOWN)
	initAction(s_controls.turnleft, ID_LEFT)
	initAction(s_controls.turnright, ID_RIGHT)
	initAction(s_controls.sidestep, ID_STRAFE)
	initAction(s_controls.run, ID_SPEED)
	initAction(s_controls.chainsaw, ID_WEAPON1)
	initAction(s_controls.machinegun, ID_WEAPON2)
	initAction(s_controls.shotgun, ID_WEAPON3)
	initAction(s_controls.grenadelauncher, ID_WEAPON4)
	initAction(s_controls.rocketlauncher, ID_WEAPON5)
	initAction(s_controls.lightning, ID_WEAPON6)
	initAction(s_controls.railgun, ID_WEAPON7)
	initAction(s_controls.plasma, ID_WEAPON8)
	initAction(s_controls.bfg, ID_WEAPON9)
	initAction(s_controls.grapple, ID_WEAPON10)
	initAction(s_controls.nailgun, ID_WEAPON11)
	initAction(s_controls.proxmine, ID_WEAPON12)
	initAction(s_controls.chaingun, ID_WEAPON13)
	initAction(s_controls.attack, ID_ATTACK)
	initAction(s_controls.prevweapon, ID_WEAPPREV)
	initAction(s_controls.nextweapon, ID_WEAPNEXT)
	initAction(s_controls.lookup, ID_LOOKUP)
	initAction(s_controls.lookdown, ID_LOOKDOWN)
	initAction(
		s_controls.mouselook,
		ID_MOUSELOOK,
		bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_HIGHLIGHT_IF_FOCUS, C.QMF_GRAYED, C.QMF_HIDDEN)
	)

	initRadio(s_controls.freelook, "free look", ID_FREELOOK)

	initAction(s_controls.centerview, ID_CENTERVIEW)
	initAction(s_controls.zoomview, ID_ZOOMVIEW)
	initAction(s_controls.useitem, ID_USEITEM)
	initAction(s_controls.showscores, ID_SHOWSCORES)

	initRadio(s_controls.invertmouse, "invert mouse", ID_INVERTMOUSE)
	initRadio(s_controls.smoothmouse, "smooth mouse", ID_SMOOTHMOUSE)
	initRadio(s_controls.alwaysrun, "always run", ID_ALWAYSRUN)

	s_controls.autoswitch.generic.type = C.MTYPE_SPINCONTROL
	s_controls.autoswitch.generic.flags = C.QMF_SMALLFONT
	s_controls.autoswitch.generic.x = C.SCREEN_WIDTH / 2
	s_controls.autoswitch.generic.name = "autoswitch weapons"
	s_controls.autoswitch.generic.id = ID_AUTOSWITCH
	s_controls.autoswitch.generic.callback = Controls_MenuEvent
	s_controls.autoswitch.generic.statusbar = Controls_StatusBar
	s_controls.autoswitch.itemnames = autoswitch_items

	s_controls.sensitivity.generic.type = C.MTYPE_SLIDER
	s_controls.sensitivity.generic.x = C.SCREEN_WIDTH / 2
	s_controls.sensitivity.generic.flags = C.QMF_SMALLFONT
	s_controls.sensitivity.generic.name = "mouse speed"
	s_controls.sensitivity.generic.id = ID_MOUSESPEED
	s_controls.sensitivity.generic.callback = Controls_MenuEvent
	s_controls.sensitivity.minvalue = 2
	s_controls.sensitivity.maxvalue = 30
	s_controls.sensitivity.generic.statusbar = Controls_StatusBar

	initAction(s_controls.gesture, ID_GESTURE)
	initAction(s_controls.chat, ID_CHAT)
	initAction(s_controls.chat2, ID_CHAT2)
	initAction(s_controls.chat3, ID_CHAT3)
	initAction(s_controls.chat4, ID_CHAT4)
	initAction(s_controls.voip_talk, ID_VOIP_TALK)

	initRadio(s_controls.voip_teamonly, "teamonly voicechat", ID_VOIP_TEAMONLY)
	initRadio(s_controls.joyenable, "joystick", ID_JOYENABLE)

	s_controls.joythreshold.generic.type = C.MTYPE_SLIDER
	s_controls.joythreshold.generic.x = C.SCREEN_WIDTH / 2
	s_controls.joythreshold.generic.flags = C.QMF_SMALLFONT
	s_controls.joythreshold.generic.name = "joystick threshold"
	s_controls.joythreshold.generic.id = ID_JOYTHRESHOLD
	s_controls.joythreshold.generic.callback = Controls_MenuEvent
	s_controls.joythreshold.minvalue = 0.05
	s_controls.joythreshold.maxvalue = 0.75
	s_controls.joythreshold.generic.statusbar = Controls_StatusBar

	playername = Q.CleanStr(string.sub(trap.Cvar_VariableStringBuffer("name"), 1, 15))

	s_controls.name.generic.type = C.MTYPE_PTEXT
	s_controls.name.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_INACTIVE)
	s_controls.name.generic.x = 320
	s_controls.name.generic.y = 440
	s_controls.name.string = playername
	s_controls.name.style = C.UI_CENTER
	s_controls.name.color = U.text_color_normal

	local order = {
		"banner", "framel", "framer", "player", "name",
		"looking", "movement", "weapons", "misc",
		"sensitivity", "smoothmouse", "invertmouse", "lookup", "lookdown", "mouselook",
		"freelook", "centerview", "zoomview", "joyenable", "joythreshold",
		"alwaysrun", "run", "walkforward", "backpedal", "stepleft", "stepright",
		"moveup", "movedown", "turnleft", "turnright", "sidestep",
		"attack", "nextweapon", "prevweapon", "autoswitch", "chainsaw",
		"machinegun", "shotgun", "grenadelauncher", "rocketlauncher", "lightning",
		"railgun", "plasma", "bfg", "grapple", "nailgun", "proxmine", "chaingun",
		"showscores", "useitem", "gesture", "chat", "chat2", "chat3", "chat4",
		"voip_talk", "voip_teamonly",
		"back",
	}
	for _, n in order do
		U.Menu_AddItem(s_controls.menu, s_controls[n])
	end

	-- initialize the configurable cvars
	Controls_InitCvars()

	-- initialize the current config
	Controls_GetConfig()

	-- intialize the model
	Controls_InitModel()

	-- intialize the weapons
	Controls_InitWeapons()

	-- initial default section
	s_controls.section = C_LOOKING

	-- update the ui
	Controls_Update()
end

Controls_Cache = function()
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
	trap.R_RegisterShaderNoMip(ART_FRAMEL)
	trap.R_RegisterShaderNoMip(ART_FRAMER)
end

function U.Controls_Cache()
	Controls_Cache()
end

function U.UI_ControlsMenu()
	Controls_MenuInit()
	U.UI_PushMenu(s_controls.menu)
end

return U
