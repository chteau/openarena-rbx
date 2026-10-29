-- Static checks for ported bot modules, run by tools/check_bots.sh:
-- 1. the module loads;
-- 2. every BC./SB. (botlib) or C./S. (bot AI) / Q./QS./BG. member it uses exists;
-- 3. every B.Name it uses is defined by some botlib file and every G.Name
--    by some src/server file (a note unless --strict, then an error).
local fs = require("@lune/fs")
local process = require("@lune/process")

local files, strict = {}, false
for _, a in process.args do
	if a == "--strict" then
		strict = true
	else
		table.insert(files, a)
	end
end

local mods = {
	consts = "src/server/bot/botlib/consts",
	structs = "src/server/bot/botlib/structs",
	ai_defs = "src/server/bot/ai_defs",
	ai_structs = "src/server/bot/ai_structs",
	q_math = "src/shared/q_math",
	q_shared = "src/shared/q_shared",
	BG = "src/shared/BG",
}
local loaded = {}
local function mod(base)
	if loaded[base] == nil then
		loaded[base] = (require :: any)("../" .. mods[base])
	end
	return loaded[base]
end

-- names defined on B (botlib) and G (game + bot AI) by any file
local definedB, definedG = {}, {}
local where = { B = {}, G = {} }
local duplicates = {}
local function scan(dir, ns, out)
	for _, name in fs.readDir(dir) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then
			scan(p, ns, out)
		elseif string.match(name, "%.luau$") then
			local src = "\n" .. fs.readFile(p)
			for n in string.gmatch(src, "\nfunction " .. ns .. "%.([%w_]+)") do
				out[n] = true
				-- one definition per name across the bot port (ai_stubs.luau is what it replaces)
				if string.find(p, "/bot/") then
					local prev = where[ns][n]
					if prev and prev ~= p then
						duplicates[ns .. "." .. n] = prev .. " and " .. p
					end
					where[ns][n] = p
				end
			end
			for n in string.gmatch(src, "\n%s*" .. ns .. "%.([%w_]+)%s*=") do
				out[n] = true
			end
		end
	end
end
scan("src/server/bot/botlib", "B", definedB)
scan("src/server", "G", definedG)
for k in require("../src/server/bot/botlib/b_local") do
	definedB[k] = true
end
local okG, G = pcall(require, "../src/server/g_local")
if okG then
	-- names the game module creates at load time (the cvar table loop in g_main ...)
	for _, name in fs.readDir("src/server") do
		if string.match(name, "^g_.*%.luau$") then
			pcall(function()
				return (require :: any)("../src/server/" .. string.gsub(name, "%.luau$", ""))
			end)
		end
	end
	for k in G do
		definedG[k] = true
	end
end

local errors = 0
if strict then
	for n, w in duplicates do
		print(string.format("%s is defined twice: %s", n, w))
		errors += 1
	end
end
for _, file in files do
	local src = fs.readFile(file)
	local ok, err = pcall(function()
		return (require :: any)("../" .. string.gsub(file, "%.luau$", ""))
	end)
	if not ok then
		print(string.format("%s: load error: %s", file, tostring(err)))
		errors += 1
	end
	local code = string.gsub(src, "%-%-%[(=*)%[.-%]%1%]", "")
	code = string.gsub(code, "%-%-[^\n]*", "")
	code = string.gsub(code, '"[^"\n]*"', '""')
	code = string.gsub(code, "'[^'\n]*'", "''")
	local seen = {}
	for lname, path in string.gmatch(src, "local%s+([%w_]+)%s*=%s*require%(%s*\"([^\"]+)\"%s*%)") do
		local base = string.match(path, "([^/]+)$")
		if mods[base] then
			local t = mod(base)
			for name in string.gmatch(code, "%f[%w_]" .. lname .. "%.([%w_]+)") do
				if t[name] == nil and not seen[lname .. "." .. name] then
					seen[lname .. "." .. name] = true
					print(string.format("%s: unknown %s.%s", file, lname, name))
					errors += 1
				end
			end
		end
	end
	for _, ns in { { "B", definedB }, { "G", definedG } } do
		local missing = {}
		for name in string.gmatch(code, "%f[%w_]" .. ns[1] .. "%.([%w_]+)") do
			if not ns[2][name] and not missing[name] then
				missing[name] = true
			end
		end
		local names = {}
		for n in missing do
			table.insert(names, n)
		end
		if #names > 0 then
			table.sort(names)
			print(string.format("%s: %s %s names not defined anywhere: %s", file, if strict then "error:" else "note:",
				ns[1], table.concat(names, ", ")))
			if strict then
				errors += #names
			end
		end
	end
end
print(string.format("check_bots: %d file(s), %d error(s)", #files, errors))
process.exit(if errors > 0 then 1 else 0)
