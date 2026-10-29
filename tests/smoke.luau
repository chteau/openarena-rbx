-- lune run tests/smoke [hud|scores|menu|all] (OA_SHARED=dir optional): runs the real cgame and q3_ui
-- code end to end against the engine layer, with the dev asset pack
-- (scripts/client-dev-assets.py) grafted next to sys/FS, and reports what
-- each frame drew. Needs build/client/{Files,AssetIndex}.
local fs = require("@lune/fs")
local process = require("@lune/process")
local H = require("./harness")

local build = process.cwd:gsub("/$", "") .. "/build/client"
assert(fs.isDir(build .. "/Files"), "run scripts/client-dev-assets.py first")
H.graft(build .. "/Files", "client/sys/Files")
H.graft(build .. "/AssetIndex", "client/sys/AssetIndex")

-- OA_SHARED=<feat/game's src/shared>: run against the real bg/cm ports
local shared = process.env.OA_SHARED
if shared and shared ~= "" then
	H.graft(shared, "shared")
end

local Scene = H.require("client/dev/Scene")
print("pmove: " .. tostring(H.require("client/adapters/BG").hasPmove))
local which = process.args[1] or "all"

local root = H.roblox.Instance.new("ScreenGui")
Scene.boot(root, 1280, 720)

local function report(name)
	local n, kinds = Scene.census(root)
	local parts = {}
	for k, c in kinds do
		table.insert(parts, k .. "=" .. c)
	end
	table.sort(parts)
	print(("%-8s %4d labels  %s"):format(name, n, table.concat(parts, " ")))
	return n
end

local failed = false
local function run(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		print("FAIL " .. name .. ": " .. tostring(err))
		failed = true
		return
	end
	if report(name) == 0 then
		print("FAIL " .. name .. ": nothing drawn")
		failed = true
	end
end

if which == "menu" or which == "all" then
	run("menu", function()
		Scene.menu()
	end)
end
if which == "hud" or which == "all" then
	run("hud", function()
		Scene.hud()
	end)
end
if which == "scores" or which == "all" then
	run("scores", function()
		Scene.scores()
	end)
end
print(if failed then "smoke: FAIL" else "smoke: ok")
process.exit(if failed then 1 else 0)
