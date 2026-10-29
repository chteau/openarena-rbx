-- lune run tests/run [filter]: runs tests/*.test.luau (matching filter).
local fs = require("@lune/fs")
local process = require("@lune/process")
local luau = require("@lune/luau")
local H = require("./harness")

local filter = process.args[1]
local files = {}
for _, f in fs.readDir("tests") do
	if f:match("%.test%.luau$") and (filter == nil or f:find(filter, 1, true)) then
		table.insert(files, f)
	end
end
table.sort(files)
for _, f in files do
	local before = H.results.fail
	local ok, err = pcall(function()
		local chunk = luau.load(fs.readFile("tests/" .. f), { debugName = f, environment = { H = H } })
		chunk()
	end)
	if not ok then
		H.results.fail += 1
		table.insert(H.results.failures, f .. " (load): " .. tostring(err))
	end
	print(("%-40s %s"):format(f, H.results.fail == before and "ok" or "FAIL"))
end
for _, line in H.results.failures do
	print("  " .. line)
end
print(("passed %d, failed %d"):format(H.results.pass, H.results.fail))
process.exit(if H.results.fail == 0 then 0 else 1)
