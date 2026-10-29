-- lune run tests/names: every Q./C./T./trap./BG. member the ported cgame and
-- q3_ui code reads must exist, and every G./U. function it calls must be
-- defined by some module (catches misnamed helpers before they run).
local fs = require("@lune/fs")
local process = require("@lune/process")
local H = require("./harness")

local ns = {
	Q = H.require("client/q/Q"),
	C = H.require("client/q/Consts"),
	T = H.require("client/q/Types"),
	trap = H.require("client/sys/Trap"),
	BG = H.require("client/adapters/BG"),
}
local G = H.require("client/cg/G")
local U = H.require("ui/q3/U")
local files = {}
for _, dir in { "src/client/cg", "src/ui/q3" } do
	for _, f in fs.readDir(dir) do
		if f:match("%.luau$") then
			local rel = dir:sub(5) .. "/" .. f:gsub("%.luau$", "")
			H.require(rel)
			table.insert(files, dir .. "/" .. f)
		end
	end
end
local bad = 0
local seen = {}
for _, path in files do
	local src = fs.readFile(path)
	src = src:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
	for prefix, name in src:gmatch("%f[%w_]([%a_][%w_]*)%.([%a_][%w_]*)") do
		local t = ns[prefix]
		local missing = false
		if t then
			missing = t[name] == nil
		elseif prefix == "G" or prefix == "U" then
			local tbl = if prefix == "G" then G else U
			-- only calls: G.Foo( must resolve
			missing = tbl[name] == nil and src:find("%f[%w_]" .. prefix .. "%." .. name .. "%s*%(") ~= nil
		end
		-- optional hooks the code tests for first (`if G.X ~= nil`), and the
		-- pmove entry points BG only has once src/shared lands (BG.hasPmove)
		if missing and (src:find(prefix .. "%." .. name .. " ~= nil") or (prefix == "BG" and ns.BG.hasPmove == false
			and (name == "Pmove" or name == "PM_UpdateViewAngles")) or name == "Menu_Paint") then
			missing = false
		end
		local key = path .. prefix .. name
		if missing and not seen[key] then
			seen[key] = true
			bad += 1
			print(("%s: %s.%s"):format(path, prefix, name))
		end
	end
end
print(if bad == 0 then "names: ok" else ("names: %d missing"):format(bad))
process.exit(if bad == 0 then 0 else 1)
