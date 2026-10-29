-- Zero-initialising constructors for the C structs (types/shared.luau,
-- types/cg.luau) plus T.copy / T.assign / T.reset.
local T = table.clone(require(script.Parent.types.shared))
local ok, cg = pcall(require, script.Parent.types.cg)
if ok then
	for k, v in cg do
		T[k] = v
	end
end
-- The C gameState_t (offsets into one char buffer) is a plain array of
-- configstrings here; see docs/client-notes.md.
T.gameState_t = function()
	return { configstrings = {}, dataCount = 0 }
end
-- ui_public.h (the q3_ui side of the engine interface)
T.uiClientState_t = function()
	return { connState = 0, connectPacketCount = 0, clientNum = 0, servername = "", updateInfoString = "", messageString = "" }
end
return T
