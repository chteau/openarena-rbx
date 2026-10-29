--[[
===========================================================================
Copyright (C) 2008-2009 Poul Sander

This file is part of the Open Arena source code.

Open Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Open Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Open Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
]]
-- Luau port of code/q3_ui/ui_challenges.c (OpenArena 0.8.8, gamecode 9e0f0c0).

local U = require(script.Parent.U)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local ID_BACK = 1

local ID_GENERAL = 100
local ID_GAMETYPES = 101
local ID_WEAPONS = 102
local ID_AWARDS = 103
local ID_POWERUPS = 104
local ID_FFA = 105

local ART_BACK0 = "menu/art_blueish/back_0"
local ART_BACK1 = "menu/art_blueish/back_1"
local ART_FRAMEL = "menu/art_blueish/frame2_l"
local ART_FRAMER = "menu/art_blueish/frame1_r"

local MAX_ENTRIES = 18
local MAX_INT_AS_STRING = 8

local function item()
	return { generic = {} }
end

local function newChallenges()
	local menu = if T.menuframework_s
		then T.menuframework_s()
		else { cursor = 0, cursor_prev = 0, nitems = 0, nslots = 0, items = {}, wrapAround = false, fullscreen = false }
	local ch = {
		menu = menu,
		banner = item(),
		framel = item(),
		framer = item(),
		general = item(),
		gametypes = item(),
		weapons = item(),
		awards = item(),
		powerups = item(),
		numberOfEntries = 0,
		entry = {},
		entryIntText = {},
		entryIntString = {},
		entryInt = {},
		notice = item(),
		notice2 = item(),
		back = item(),
	}
	for i = 0, MAX_ENTRIES - 1 do
		ch.entry[i] = item()
		ch.entryIntText[i] = item()
		ch.entryIntString[i] = ""
		ch.entryInt[i] = 0
	end
	return ch
end

local challenges = newChallenges()

local mainSelection = 0

local function UI_Challenges_Event(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local id = ptr.generic.id
	if id == ID_GENERAL then
		mainSelection = 0
		U.UI_PopMenu()
		U.UI_ChallengesLocal()
	elseif id == ID_GAMETYPES then
		mainSelection = 1
		U.UI_PopMenu()
		U.UI_ChallengesLocal()
	elseif id == ID_WEAPONS then
		mainSelection = 2
		U.UI_PopMenu()
		U.UI_ChallengesLocal()
	elseif id == ID_AWARDS then
		mainSelection = 3
		U.UI_PopMenu()
		U.UI_ChallengesLocal()
	elseif id == ID_POWERUPS then
		mainSelection = 4
		U.UI_PopMenu()
		U.UI_ChallengesLocal()
	elseif id == ID_FFA then
		return
	elseif id == ID_BACK then
		U.UI_PopMenu()
	end
end

function U.UI_Challenges_Cache()
	trap.R_RegisterShaderNoMip(ART_FRAMEL)
	trap.R_RegisterShaderNoMip(ART_FRAMER)
	trap.R_RegisterShaderNoMip(ART_BACK0)
	trap.R_RegisterShaderNoMip(ART_BACK1)
end

local entryTables = {
	[0] = {
		{ "Total kills:", "GENERAL_TOTALKILLS" },
		{ "Total deaths:", "GENERAL_TOTALDEATHS" },
	},
	[1] = {},
	[2] = {
		{ "Gauntlet kills:", "WEAPON_GAUNTLET_KILLS" },
		{ "Machinegun kills:", "WEAPON_MACHINEGUN_KILLS" },
		{ "Shotgun kills:", "WEAPON_SHOTGUN_KILLS" },
		{ "Granade kills:", "WEAPON_GRANADE_KILLS" },
		{ "Rocket kills:", "WEAPON_ROCKET_KILLS" },
		{ "Lightning kills:", "WEAPON_LIGHTNING_KILLS" },
		{ "Plasmagun kills:", "WEAPON_PLASMA_KILLS" },
		{ "Railgun kills:", "WEAPON_RAIL_KILLS" },
		{ "Instant rail kills:", "WEAPON_INSTANT_RAIL_KILLS" },
		{ "BFG kills:", "WEAPON_BFG_KILLS" },
		{ "Grapple kills:", "WEAPON_GRAPPLE_KILLS" },
		{ "Chaingun kills:", "WEAPON_CHAINGUN_KILLS" },
		{ "Nailgun kills:", "WEAPON_NAILGUN_KILLS" },
		{ "Proxy mine kills:", "WEAPON_MINE_KILLS" },
		{ "Telefrags:", "WEAPON_TELEFRAG_KILLS" },
		{ "Push kills:", "WEAPON_PUSH_KILLS" },
		{ "Crush kills:", "WEAPON_CRUSH_KILLS" },
	},
	[3] = {
		{ "Gauntlet", "WEAPON_GAUNTLET_KILLS" },
		{ "Impressive", "AWARD_IMPRESSIVE" },
		{ "Excellent", "AWARD_EXCELLENT" },
		{ "Capture", "AWARD_CAPTURE" },
		{ "Assist", "AWARD_ASSIST" },
		{ "Defend", "AWARD_DEFENCE" },
	},
	[4] = {
		{ "Quad kills", "POWERUP_QUAD_KILL" },
		{ "2 fast 4 U", "POWERUP_SPEED_KILL" },
		{ "They didn't see me", "POWERUP_INVIS_KILL" },
		{ "I'm flying", "POWERUP_FLIGHT_KILL" },
		{ "Killing machine", "POWERUP_MULTI_KILL" },
		{ "Counter Quad", "POWERUP_COUNTER_QUAD" },
		{ "Not fast enough", "POWERUP_COUNTER_SPEED" },
		{ "You cannot hide", "POWERUP_COUNTER_INVIS" },
		{ "Fall deep", "POWERUP_COUNTER_FLIGHT" },
		{ "Counter battlesuit", "POWERUP_COUNTER_ENVIR" },
		{ "Counter regen", "POWERUP_COUNTER_REGEN" },
		{ "Counter multi", "POWERUP_COUNTER_MULTI" },
	},
}

local function UI_Challenges_Init()
	challenges = newChallenges()
	local ch = challenges

	U.UI_DisplayOptionsMenu_Cache()
	ch.menu.wrapAround = true
	ch.menu.fullscreen = true

	ch.banner.generic.type = C.MTYPE_BTEXT
	ch.banner.generic.flags = C.QMF_CENTER_JUSTIFY
	ch.banner.generic.x = 320
	ch.banner.generic.y = 16
	ch.banner.string = "STATISTICS"
	ch.banner.color = U.color_white
	ch.banner.style = C.UI_CENTER

	ch.framel.generic.type = C.MTYPE_BITMAP
	ch.framel.generic.name = ART_FRAMEL
	ch.framel.generic.flags = C.QMF_INACTIVE
	ch.framel.generic.x = 0
	ch.framel.generic.y = 78
	ch.framel.width = 256
	ch.framel.height = 329

	ch.framer.generic.type = C.MTYPE_BITMAP
	ch.framer.generic.name = ART_FRAMER
	ch.framer.generic.flags = C.QMF_INACTIVE
	ch.framer.generic.x = 376
	ch.framer.generic.y = 76
	ch.framer.width = 256
	ch.framer.height = 334

	local heads = {
		{ ch.general, ID_GENERAL, 240 - 1 * C.PROP_HEIGHT, "GENERAL" },
		{ ch.weapons, ID_WEAPONS, 240, "WEAPONS" },
		{ ch.awards, ID_AWARDS, 240 + C.PROP_HEIGHT, "AWARDS" },
		{ ch.powerups, ID_POWERUPS, 240 + C.PROP_HEIGHT * 2, "POWERUPS" },
	}
	for _, hd in heads do
		local h = hd[1]
		h.generic.type = C.MTYPE_PTEXT
		h.generic.flags = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_PULSEIFFOCUS)
		h.generic.id = hd[2]
		h.generic.callback = UI_Challenges_Event
		h.generic.x = 216
		h.generic.y = hd[3]
		h.string = hd[4]
		h.style = C.UI_RIGHT
		h.color = U.color_red
	end

	ch.notice.generic.type = C.MTYPE_TEXT
	ch.notice.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_INACTIVE, C.QMF_SMALLFONT)
	ch.notice.generic.x = 160
	ch.notice.generic.y = 430
	ch.notice.string = "Only results against"

	ch.notice2.generic.type = C.MTYPE_TEXT
	ch.notice2.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_INACTIVE, C.QMF_SMALLFONT)
	ch.notice2.generic.x = 160
	ch.notice2.generic.y = 430 + C.PROP_HEIGHT - 10
	ch.notice2.string = "humans are counted"

	ch.back.generic.type = C.MTYPE_BITMAP
	ch.back.generic.name = ART_BACK0
	ch.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	ch.back.generic.callback = UI_Challenges_Event
	ch.back.generic.id = ID_BACK
	ch.back.generic.x = 0
	ch.back.generic.y = 480 - 64
	ch.back.width = 128
	ch.back.height = 64
	ch.back.focuspic = ART_BACK1

	local inactive = bit32.bor(C.QMF_RIGHT_JUSTIFY, C.QMF_INACTIVE)
	local selected = ({ [0] = ch.general, [1] = ch.gametypes, [2] = ch.weapons, [3] = ch.awards, [4] = ch.powerups })[mainSelection]
	if selected ~= nil then
		selected.generic.flags = inactive
	end

	local list = entryTables[mainSelection]
	if list ~= nil then
		for i, e in list do
			local idx = i - 1
			ch.entry[idx].string = e[1]
			ch.entryInt[idx] = U.getChallenge(C[e[2]])
		end
		ch.numberOfEntries = #list
	else
		ch.numberOfEntries = 0
	end

	-- Now write the challenges
	local y = 240 - Q.int((ch.numberOfEntries / 2.0) * (C.BIGCHAR_HEIGHT + 2))
	local i = 0
	while i < MAX_ENTRIES and i < ch.numberOfEntries do
		ch.entry[i].color = U.color_white
		ch.entry[i].generic.type = C.MTYPE_TEXT
		ch.entry[i].generic.x = 230
		ch.entry[i].generic.y = y

		ch.entryIntText[i].color = U.color_white
		ch.entryIntText[i].generic.type = C.MTYPE_TEXT
		ch.entryIntText[i].generic.x = 630
		ch.entryIntText[i].generic.y = y
		ch.entryIntText[i].style = C.UI_RIGHT

		ch.entryIntString[i] = string.sub(string.format("%d", ch.entryInt[i]), 1, MAX_INT_AS_STRING)
		ch.entryIntText[i].string = ch.entryIntString[i]
		y += C.BIGCHAR_HEIGHT + 2
		i += 1
	end

	U.Menu_AddItem(ch.menu, ch.banner)
	U.Menu_AddItem(ch.menu, ch.framel)
	U.Menu_AddItem(ch.menu, ch.framer)

	U.Menu_AddItem(ch.menu, ch.general)
	U.Menu_AddItem(ch.menu, ch.weapons)
	U.Menu_AddItem(ch.menu, ch.awards)
	U.Menu_AddItem(ch.menu, ch.powerups)

	i = 0
	while i < MAX_ENTRIES and i < ch.numberOfEntries do
		U.Menu_AddItem(ch.menu, ch.entry[i])
		U.Menu_AddItem(ch.menu, ch.entryIntText[i])
		i += 1
	end
	U.Menu_AddItem(ch.menu, ch.notice)
	U.Menu_AddItem(ch.menu, ch.notice2)
	U.Menu_AddItem(ch.menu, ch.back)
end

function U.UI_Challenges()
	mainSelection = 0
	UI_Challenges_Init()
	U.UI_PushMenu(challenges.menu)
	U.Menu_SetCursorToItem(challenges.menu, challenges.back)
end

-- This is only used locally. Remembers selection
function U.UI_ChallengesLocal()
	UI_Challenges_Init()
	U.UI_PushMenu(challenges.menu)
	U.Menu_SetCursorToItem(challenges.menu, challenges.back)
end

return U
