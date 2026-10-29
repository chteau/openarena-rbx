-- lune run tests/load <module...>: loads each module (path under src/, no
-- extension) in the harness, e.g. `client/cg/cg_view`. With `--names a,b`
-- after a module, also checks G (cgame) or U (q3_ui) got those functions.
local process = require("@lune/process")
local H = require("./harness")

local failed = false
local i = 1
local args = process.args
while i <= #args do
	local mod = args[i]
	local ok, err = pcall(H.require, mod)
	if not ok then
		print("FAIL load " .. mod .. ": " .. tostring(err))
		failed = true
	end
	if args[i + 1] == "--names" then
		local ns = if mod:find("^ui/") then H.require("ui/q3/U") else H.require("client/cg/G")
		for name in args[i + 2]:gmatch("[^,]+") do
			if type(ns[name]) ~= "function" then
				print("FAIL " .. mod .. ": " .. name .. " is not registered")
				failed = true
			end
		end
		i += 2
	end
	i += 1
end
print(if failed then "load: FAIL" else "load: ok")
process.exit(if failed then 1 else 0)
