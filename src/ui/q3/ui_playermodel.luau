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
-- Luau port of code/q3_ui/ui_playermodel.c (OpenArena gamecode).

local U = require(script.Parent.U)
local C = require(script.Parent.Parent.Parent.client.q.Consts)
local Q = require(script.Parent.Parent.Parent.client.q.Q)
local T = require(script.Parent.Parent.Parent.client.q.Types)
local trap = require(script.Parent.Parent.Parent.client.sys.Trap)

local MODEL_BACK0 = "menu/" .. C.MENU_ART_DIR .. "/back_0"
local MODEL_BACK1 = "menu/" .. C.MENU_ART_DIR .. "/back_1"
local MODEL_SELECT = "menu/art/opponents_select"
local MODEL_SELECTED = "menu/art/opponents_selected"
local MODEL_FRAMEL = "menu/" .. C.MENU_ART_DIR .. "/frame1_l"
local MODEL_FRAMER = "menu/" .. C.MENU_ART_DIR .. "/frame1_r"
local MODEL_PORTS = "menu/" .. C.MENU_ART_DIR .. "/player_models_ports"
local MODEL_ARROWS = "menu/" .. C.MENU_ART_DIR .. "/gs_arrows_0"
local MODEL_ARROWSL = "menu/" .. C.MENU_ART_DIR .. "/gs_arrows_l"
local MODEL_ARROWSR = "menu/" .. C.MENU_ART_DIR .. "/gs_arrows_r"

local LOW_MEMORY = 5 * 1024 * 1024

local playermodel_artlist = {
	[0] = MODEL_BACK0,
	MODEL_BACK1,
	MODEL_SELECT,
	MODEL_SELECTED,
	MODEL_FRAMEL,
	MODEL_FRAMER,
	MODEL_PORTS,
	MODEL_ARROWS,
	MODEL_ARROWSL,
	MODEL_ARROWSR,
}
local ARTLIST_COUNT = 10

local PLAYERGRID_COLS = 4
local PLAYERGRID_ROWS = 4
local MAX_MODELSPERPAGE = PLAYERGRID_ROWS * PLAYERGRID_COLS

local MAX_PLAYERMODELS = 256

local ID_PLAYERPIC0 = 0
local ID_PREVPAGE = 100
local ID_NEXTPAGE = 101
local ID_BACK = 102

local function newItem()
	return {
		generic = {
			type = 0,
			name = nil,
			id = 0,
			x = 0,
			y = 0,
			left = 0,
			top = 0,
			right = 0,
			bottom = 0,
			flags = 0,
			callback = nil,
			ownerdraw = nil,
		},
		width = 0,
		height = 0,
		shader = 0,
		focuspic = nil,
		focuscolor = nil,
		string = "",
		style = 0,
		color = nil,
	}
end

local function newState()
	local s = {
		menu = {
			cursor = 0,
			cursor_prev = 0,
			nitems = 0,
			items = {},
			key = nil,
			wrapAround = false,
			fullscreen = false,
			showlogo = false,
		},
		pics = {},
		picbuttons = {},
		framel = newItem(),
		framer = newItem(),
		ports = newItem(),
		banner = newItem(),
		back = newItem(),
		player = newItem(),
		arrows = newItem(),
		left = newItem(),
		right = newItem(),
		modelname = newItem(),
		skinname = newItem(),
		playername = newItem(),
		playerinfo = T.playerInfo_t(),
		nummodels = 0,
		modelnames = {},
		modelpage = 0,
		numpages = 0,
		modelskin = "",
		selectedmodel = 0,
	}
	for i = 0, MAX_MODELSPERPAGE - 1 do
		s.pics[i] = newItem()
		s.picbuttons[i] = newItem()
	end
	return s
end

local s_playermodel = newState()

local function setFlag(item, f)
	item.generic.flags = bit32.bor(item.generic.flags, f)
end

local function clearFlag(item, f)
	item.generic.flags = bit32.band(item.generic.flags, bit32.bnot(f))
end

local function cleanStr(s)
	return (string.gsub(s, "%^[^%^]", ""))
end

local function stripIcon(name)
	local buffptr = string.sub(name, #"models/players/" + 1)
	local p = string.find(buffptr, "icon_", 1, true)
	return buffptr, p
end

local function PlayerModel_UpdateGrid()
	local j = s_playermodel.modelpage * MAX_MODELSPERPAGE
	for i = 0, PLAYERGRID_ROWS * PLAYERGRID_COLS - 1 do
		if j < s_playermodel.nummodels then
			-- model/skin portrait
			s_playermodel.pics[i].generic.name = s_playermodel.modelnames[j]
			clearFlag(s_playermodel.picbuttons[i], C.QMF_INACTIVE)
		else
			-- dead slot
			s_playermodel.pics[i].generic.name = nil
			setFlag(s_playermodel.picbuttons[i], C.QMF_INACTIVE)
		end

		clearFlag(s_playermodel.pics[i], C.QMF_HIGHLIGHT)
		s_playermodel.pics[i].shader = 0
		setFlag(s_playermodel.picbuttons[i], C.QMF_PULSEIFFOCUS)
		j += 1
	end

	if Q.idiv(s_playermodel.selectedmodel, MAX_MODELSPERPAGE) == s_playermodel.modelpage then
		-- set selected model
		local i = s_playermodel.selectedmodel % MAX_MODELSPERPAGE

		setFlag(s_playermodel.pics[i], C.QMF_HIGHLIGHT)
		clearFlag(s_playermodel.picbuttons[i], C.QMF_PULSEIFFOCUS)
	end

	if s_playermodel.numpages > 1 then
		if s_playermodel.modelpage > 0 then
			clearFlag(s_playermodel.left, C.QMF_INACTIVE)
		else
			setFlag(s_playermodel.left, C.QMF_INACTIVE)
		end

		if s_playermodel.modelpage < s_playermodel.numpages - 1 then
			clearFlag(s_playermodel.right, C.QMF_INACTIVE)
		else
			setFlag(s_playermodel.right, C.QMF_INACTIVE)
		end
	else
		-- hide left/right markers
		setFlag(s_playermodel.left, C.QMF_INACTIVE)
		setFlag(s_playermodel.right, C.QMF_INACTIVE)
	end
end

local function PlayerModel_UpdateModel()
	local viewangles = Q.vec3(0, 0, 0)
	local moveangles = Q.vec3(0, 0, 0)

	s_playermodel.playerinfo = T.playerInfo_t()

	viewangles[C.YAW] = 180 - 30
	viewangles[C.PITCH] = 0
	viewangles[C.ROLL] = 0

	U.UI_PlayerInfo_SetModel(s_playermodel.playerinfo, s_playermodel.modelskin)
	U.UI_PlayerInfo_SetInfo(
		s_playermodel.playerinfo,
		C.LEGS_IDLE,
		C.TORSO_STAND,
		viewangles,
		moveangles,
		C.WP_MACHINEGUN,
		false
	)
end

local function PlayerModel_SaveChanges()
	trap.Cvar_Set("model", s_playermodel.modelskin)
	trap.Cvar_Set("headmodel", s_playermodel.modelskin)
	trap.Cvar_Set("team_model", s_playermodel.modelskin)
	trap.Cvar_Set("team_headmodel", s_playermodel.modelskin)
end

local function PlayerModel_MenuEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	local id = ptr.generic.id
	if id == ID_PREVPAGE then
		if s_playermodel.modelpage > 0 then
			s_playermodel.modelpage -= 1
			PlayerModel_UpdateGrid()
		end
	elseif id == ID_NEXTPAGE then
		if s_playermodel.modelpage < s_playermodel.numpages - 1 then
			s_playermodel.modelpage += 1
			PlayerModel_UpdateGrid()
		end
	elseif id == ID_BACK then
		PlayerModel_SaveChanges()
		U.UI_PopMenu()
	end
end

local function PlayerModel_MenuKey(key)
	if key == C.K_KP_LEFTARROW or key == C.K_LEFTARROW then
		local m = U.Menu_ItemAtCursor(s_playermodel.menu)
		local picnum = m.generic.id - ID_PLAYERPIC0
		if picnum >= 0 and picnum <= 15 then
			if picnum > 0 then
				U.Menu_SetCursor(s_playermodel.menu, s_playermodel.menu.cursor - 1)
				return U.menu_move_sound
			elseif s_playermodel.modelpage > 0 then
				s_playermodel.modelpage -= 1
				U.Menu_SetCursor(s_playermodel.menu, s_playermodel.menu.cursor + 15)
				PlayerModel_UpdateGrid()
				return U.menu_move_sound
			else
				return U.menu_buzz_sound
			end
		end
	elseif key == C.K_KP_RIGHTARROW or key == C.K_RIGHTARROW then
		local m = U.Menu_ItemAtCursor(s_playermodel.menu)
		local picnum = m.generic.id - ID_PLAYERPIC0
		if picnum >= 0 and picnum <= 15 then
			if picnum < 15 and s_playermodel.modelpage * MAX_MODELSPERPAGE + picnum + 1 < s_playermodel.nummodels then
				U.Menu_SetCursor(s_playermodel.menu, s_playermodel.menu.cursor + 1)
				return U.menu_move_sound
			elseif picnum == 15 and s_playermodel.modelpage < s_playermodel.numpages - 1 then
				s_playermodel.modelpage += 1
				U.Menu_SetCursor(s_playermodel.menu, s_playermodel.menu.cursor - 15)
				PlayerModel_UpdateGrid()
				return U.menu_move_sound
			else
				return U.menu_buzz_sound
			end
		end
	elseif key == C.K_MOUSE2 or key == C.K_ESCAPE then
		PlayerModel_SaveChanges()
	end

	return U.Menu_DefaultKey(s_playermodel.menu, key)
end

local function splitNames(buffptr, p)
	local modelmax = p - 1
	if modelmax > 16 then
		modelmax = 16
	end
	local modelname = string.upper(string.sub(buffptr, 1, modelmax - 1))

	local skin = string.sub(buffptr, p + 5)
	local skinmax = #skin + 1
	if skinmax > 16 then
		skinmax = 16
	end
	local skinname = string.upper(string.sub(skin, 1, skinmax - 1))
	return modelname, skinname
end

local function PlayerModel_PicEvent(ptr, event)
	if event ~= C.QM_ACTIVATED then
		return
	end

	for i = 0, PLAYERGRID_ROWS * PLAYERGRID_COLS - 1 do
		-- reset
		clearFlag(s_playermodel.pics[i], C.QMF_HIGHLIGHT)
		setFlag(s_playermodel.picbuttons[i], C.QMF_PULSEIFFOCUS)
	end

	-- set selected
	local i = ptr.generic.id - ID_PLAYERPIC0
	setFlag(s_playermodel.pics[i], C.QMF_HIGHLIGHT)
	clearFlag(s_playermodel.picbuttons[i], C.QMF_PULSEIFFOCUS)

	-- get model and strip icon_
	local modelnum = s_playermodel.modelpage * MAX_MODELSPERPAGE + i
	local buffptr, p = stripIcon(s_playermodel.modelnames[modelnum])
	if p ~= nil then
		-- track the whole model/skin name
		s_playermodel.modelskin = string.sub(buffptr, 1, p - 1) .. string.sub(buffptr, p + 5)

		local mn, sn = splitNames(buffptr, p)
		s_playermodel.modelname.string = mn
		s_playermodel.skinname.string = sn

		s_playermodel.selectedmodel = modelnum

		if trap.MemoryRemaining() > LOW_MEMORY then
			PlayerModel_UpdateModel()
		end
	end
end

local function PlayerModel_DrawPlayer(self)
	local b = self

	if trap.MemoryRemaining() <= LOW_MEMORY then
		U.UI_DrawProportionalString(b.generic.x, b.generic.y + b.height / 2, "LOW MEMORY", C.UI_LEFT, U.color_red)
		return
	end

	U.UI_DrawPlayer(
		b.generic.x,
		b.generic.y,
		b.width,
		b.height,
		s_playermodel.playerinfo,
		Q.idiv(U.uis.realtime, 2)
	)
end

local function PlayerModel_BuildList()
	local precache = trap.Cvar_VariableValue("com_buildscript") ~= 0

	s_playermodel.modelpage = 0
	s_playermodel.nummodels = 0

	-- iterate directory of all player models
	local numdirs, dirlist = trap.FS_GetFileList("models/players", "/")
	local i = 0
	while i < numdirs and s_playermodel.nummodels < MAX_PLAYERMODELS do
		local dirptr = dirlist[i]
		local dirlen = #dirptr

		if dirlen ~= 0 and string.sub(dirptr, dirlen, dirlen) == "/" then
			dirptr = string.sub(dirptr, 1, dirlen - 1)
		end

		if dirptr ~= "." and dirptr ~= ".." then
			-- iterate all skin files in directory
			local numfiles, filelist = trap.FS_GetFileList(Q.va("models/players/%s", dirptr), "tga")
			local j = 0
			while j < numfiles and s_playermodel.nummodels < MAX_PLAYERMODELS do
				local skinname = (string.gsub(filelist[j], "%.[^%.]*$", ""))

				-- look for icon_????
				if string.sub(skinname, 1, 5) == "icon_" then
					s_playermodel.modelnames[s_playermodel.nummodels] =
						Q.va("models/players/%s/%s", dirptr, skinname)
					s_playermodel.nummodels += 1
				end

				if precache then
					trap.S_RegisterSound(Q.va("sound/player/announce/%s_wins.wav", skinname), false)
				end
				j += 1
			end
		end
		i += 1
	end

	s_playermodel.numpages = Q.idiv(s_playermodel.nummodels, MAX_MODELSPERPAGE)
	if s_playermodel.nummodels % MAX_MODELSPERPAGE ~= 0 then
		s_playermodel.numpages += 1
	end
end

local function PlayerModel_SetMenuItems()
	-- name
	s_playermodel.playername.string = cleanStr(string.sub(trap.Cvar_VariableStringBuffer("name"), 1, 15))

	-- model
	s_playermodel.modelskin = string.sub(trap.Cvar_VariableStringBuffer("model"), 1, 63)

	-- use default skin if none is set
	if string.find(s_playermodel.modelskin, "/", 1, true) == nil then
		s_playermodel.modelskin = string.sub(s_playermodel.modelskin .. "/default", 1, 63)
	end

	-- find model in our list
	for i = 0, s_playermodel.nummodels - 1 do
		-- strip icon_
		local buffptr, p = stripIcon(s_playermodel.modelnames[i])
		if p ~= nil then
			local modelskin = string.sub(buffptr, 1, p - 1) .. string.sub(buffptr, p + 5)

			if string.lower(s_playermodel.modelskin) == string.lower(modelskin) then
				-- found pic, set selection here
				s_playermodel.selectedmodel = i
				s_playermodel.modelpage = Q.idiv(i, MAX_MODELSPERPAGE)

				local mn, sn = splitNames(buffptr, p)
				s_playermodel.modelname.string = mn
				s_playermodel.skinname.string = sn
				break
			end
		end
	end
end

local function PlayerModel_MenuInit()
	-- zero set all our globals
	s_playermodel = newState()

	U.PlayerModel_Cache()

	s_playermodel.menu.key = PlayerModel_MenuKey
	s_playermodel.menu.wrapAround = true
	s_playermodel.menu.fullscreen = true

	s_playermodel.banner.generic.type = C.MTYPE_BTEXT
	s_playermodel.banner.generic.x = 320
	s_playermodel.banner.generic.y = 16
	s_playermodel.banner.string = "PLAYER MODEL"
	s_playermodel.banner.color = U.color_white
	s_playermodel.banner.style = C.UI_CENTER

	s_playermodel.framel.generic.type = C.MTYPE_BITMAP
	s_playermodel.framel.generic.name = MODEL_FRAMEL
	s_playermodel.framel.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	s_playermodel.framel.generic.x = 0
	s_playermodel.framel.generic.y = 78
	s_playermodel.framel.width = 256
	s_playermodel.framel.height = 329

	s_playermodel.framer.generic.type = C.MTYPE_BITMAP
	s_playermodel.framer.generic.name = MODEL_FRAMER
	s_playermodel.framer.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	s_playermodel.framer.generic.x = 376
	s_playermodel.framer.generic.y = 76
	s_playermodel.framer.width = 256
	s_playermodel.framer.height = 334

	s_playermodel.ports.generic.type = C.MTYPE_BITMAP
	s_playermodel.ports.generic.name = MODEL_PORTS
	s_playermodel.ports.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
	s_playermodel.ports.generic.x = 50
	s_playermodel.ports.generic.y = 59
	s_playermodel.ports.width = 274
	s_playermodel.ports.height = 274

	local y = 59
	local k = 0
	for _ = 0, PLAYERGRID_ROWS - 1 do
		local x = 50
		for _ = 0, PLAYERGRID_COLS - 1 do
			local pic = s_playermodel.pics[k]
			pic.generic.type = C.MTYPE_BITMAP
			pic.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_INACTIVE)
			pic.generic.x = x
			pic.generic.y = y
			pic.width = 64
			pic.height = 64
			pic.focuspic = MODEL_SELECTED
			pic.focuscolor = Q.colorRed

			local pb = s_playermodel.picbuttons[k]
			pb.generic.type = C.MTYPE_BITMAP
			pb.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_NODEFAULTINIT, C.QMF_PULSEIFFOCUS)
			pb.generic.id = ID_PLAYERPIC0 + k
			pb.generic.callback = PlayerModel_PicEvent
			pb.generic.x = x - 16
			pb.generic.y = y - 16
			pb.generic.left = x
			pb.generic.top = y
			pb.generic.right = x + 64
			pb.generic.bottom = y + 64
			pb.width = 128
			pb.height = 128
			pb.focuspic = MODEL_SELECT
			pb.focuscolor = Q.colorRed

			x += 64 + 6
			k += 1
		end
		y += 64 + 6
	end

	s_playermodel.playername.generic.type = C.MTYPE_PTEXT
	s_playermodel.playername.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_INACTIVE)
	s_playermodel.playername.generic.x = 320
	s_playermodel.playername.generic.y = 440
	s_playermodel.playername.style = C.UI_CENTER
	s_playermodel.playername.color = U.text_color_normal

	s_playermodel.modelname.generic.type = C.MTYPE_PTEXT
	s_playermodel.modelname.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_INACTIVE)
	s_playermodel.modelname.generic.x = 497
	s_playermodel.modelname.generic.y = 54
	s_playermodel.modelname.style = C.UI_CENTER
	s_playermodel.modelname.color = U.text_color_normal

	s_playermodel.skinname.generic.type = C.MTYPE_PTEXT
	s_playermodel.skinname.generic.flags = bit32.bor(C.QMF_CENTER_JUSTIFY, C.QMF_INACTIVE)
	s_playermodel.skinname.generic.x = 497
	s_playermodel.skinname.generic.y = 394
	s_playermodel.skinname.style = C.UI_CENTER
	s_playermodel.skinname.color = U.text_color_normal

	s_playermodel.player.generic.type = C.MTYPE_BITMAP
	s_playermodel.player.generic.flags = C.QMF_INACTIVE
	s_playermodel.player.generic.ownerdraw = PlayerModel_DrawPlayer
	s_playermodel.player.generic.x = 400
	s_playermodel.player.generic.y = -40
	s_playermodel.player.width = 32 * 10
	s_playermodel.player.height = 56 * 10

	s_playermodel.arrows.generic.type = C.MTYPE_BITMAP
	s_playermodel.arrows.generic.name = MODEL_ARROWS
	s_playermodel.arrows.generic.flags = C.QMF_INACTIVE
	s_playermodel.arrows.generic.x = 125
	s_playermodel.arrows.generic.y = 340
	s_playermodel.arrows.width = 128
	s_playermodel.arrows.height = 32

	s_playermodel.left.generic.type = C.MTYPE_BITMAP
	s_playermodel.left.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_playermodel.left.generic.callback = PlayerModel_MenuEvent
	s_playermodel.left.generic.id = ID_PREVPAGE
	s_playermodel.left.generic.x = 125
	s_playermodel.left.generic.y = 340
	s_playermodel.left.width = 64
	s_playermodel.left.height = 32
	s_playermodel.left.focuspic = MODEL_ARROWSL

	s_playermodel.right.generic.type = C.MTYPE_BITMAP
	s_playermodel.right.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_playermodel.right.generic.callback = PlayerModel_MenuEvent
	s_playermodel.right.generic.id = ID_NEXTPAGE
	s_playermodel.right.generic.x = 125 + 61
	s_playermodel.right.generic.y = 340
	s_playermodel.right.width = 64
	s_playermodel.right.height = 32
	s_playermodel.right.focuspic = MODEL_ARROWSR

	s_playermodel.back.generic.type = C.MTYPE_BITMAP
	s_playermodel.back.generic.name = MODEL_BACK0
	s_playermodel.back.generic.flags = bit32.bor(C.QMF_LEFT_JUSTIFY, C.QMF_PULSEIFFOCUS)
	s_playermodel.back.generic.callback = PlayerModel_MenuEvent
	s_playermodel.back.generic.id = ID_BACK
	s_playermodel.back.generic.x = 0
	s_playermodel.back.generic.y = 480 - 64
	s_playermodel.back.width = 128
	s_playermodel.back.height = 64
	s_playermodel.back.focuspic = MODEL_BACK1

	U.Menu_AddItem(s_playermodel.menu, s_playermodel.banner)
	U.Menu_AddItem(s_playermodel.menu, s_playermodel.framel)
	U.Menu_AddItem(s_playermodel.menu, s_playermodel.framer)
	U.Menu_AddItem(s_playermodel.menu, s_playermodel.ports)
	U.Menu_AddItem(s_playermodel.menu, s_playermodel.playername)
	U.Menu_AddItem(s_playermodel.menu, s_playermodel.modelname)
	U.Menu_AddItem(s_playermodel.menu, s_playermodel.skinname)

	for i = 0, MAX_MODELSPERPAGE - 1 do
		U.Menu_AddItem(s_playermodel.menu, s_playermodel.pics[i])
		U.Menu_AddItem(s_playermodel.menu, s_playermodel.picbuttons[i])
	end

	U.Menu_AddItem(s_playermodel.menu, s_playermodel.player)
	U.Menu_AddItem(s_playermodel.menu, s_playermodel.arrows)
	U.Menu_AddItem(s_playermodel.menu, s_playermodel.left)
	U.Menu_AddItem(s_playermodel.menu, s_playermodel.right)
	U.Menu_AddItem(s_playermodel.menu, s_playermodel.back)

	-- set initial states
	PlayerModel_SetMenuItems()

	-- update user interface
	PlayerModel_UpdateGrid()
	PlayerModel_UpdateModel()
end

function U.PlayerModel_Cache()
	for i = 0, ARTLIST_COUNT - 1 do
		trap.R_RegisterShaderNoMip(playermodel_artlist[i])
	end

	PlayerModel_BuildList()
	for i = 0, s_playermodel.nummodels - 1 do
		trap.R_RegisterShaderNoMip(s_playermodel.modelnames[i])
	end
end

function U.UI_PlayerModelMenu()
	PlayerModel_MenuInit()

	U.UI_PushMenu(s_playermodel.menu)

	U.Menu_SetCursorToItem(s_playermodel.menu, s_playermodel.pics[s_playermodel.selectedmodel % MAX_MODELSPERPAGE])
end

return U
