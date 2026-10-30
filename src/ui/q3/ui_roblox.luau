--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Not a port: the q3_ui menus whose job doesn't exist on Roblox. A Roblox
-- place *is* the server, players don't record demos, switch mods,
-- play cinematics or enter CD keys. q3_ui still calls these names, so they
-- land here (docs/client-notes.md, "Walls"):
--   ui_demo2.c / ui_mods.c / ui_cinematics.c / ui_cdkey.c  a message box
local U = require(script.Parent.U)

local function unavailable(what: string)
	U.UI_Message({ [0] = what, [1] = "aren't available on Roblox" })
end

function U.UI_DemosMenu()
	unavailable("Demos")
end

function U.UI_ModsMenu()
	unavailable("Mods")
end

function U.UI_CinematicsMenu_f()
	unavailable("Cinematics")
end

function U.UI_CDKeyMenu_f()
	unavailable("CD keys")
end

function U.Demos_Cache() end
function U.UI_ModsMenu_Cache() end
function U.UI_CinematicsMenu_Cache() end
function U.UI_CDKeyMenu_Cache() end

return U
