-- Static checks for ported game modules (run with lune):
--   lune run tools/check_port.luau <file.luau> [...] [--strict]
-- 1. the module loads (syntax and load-time errors);
-- 2. every C.NAME / QS.name / Q.name / BG.name / S.name it uses exists;
-- 3. every G.Name(...) it calls is defined by some src/server file
--    (`function G.Name` or `G.Name =`); a warning unless --strict.
-- Exit code 1 on any error.
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

local tables = {
	C = require("../src/server/g_defs"),
	QS = require("../src/shared/q_shared"),
	Q = require("../src/shared/q_math"),
	BG = require("../src/shared/BG"),
	S = require("../src/server/g_structs"),
}

-- which local name each file binds each module to
local modulePaths = {
	["g_defs"] = "C",
	["consts"] = "C",
	["g_consts"] = "C",
	["q_shared"] = "QS",
	["q_math"] = "Q",
	["BG"] = "BG",
	["g_structs"] = "S",
	["structs"] = "S",
}

-- every G.X defined anywhere under src/server (and where, to catch two
-- files defining the same function)
local defined = {}
local definedIn = {}
local duplicates = {}
local function scanDefs(dir)
	for _, name in fs.readDir(dir) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then
			scanDefs(p)
		elseif string.match(name, "%.luau$") then
			local src = fs.readFile(p)
			for n in string.gmatch(src, "\nfunction%s+G%.([%w_]+)") do
				defined[n] = true
				if definedIn[n] and definedIn[n] ~= p then
					duplicates[n] = definedIn[n] .. " and " .. p
				end
				definedIn[n] = p
			end
			for n in string.gmatch(src, "function%s+G%.([%w_]+)") do
				defined[n] = true
			end
			for n in string.gmatch(src, "\nG%.([%w_]+)%s*=") do
				defined[n] = true
			end
			for n in string.gmatch(src, "\n%s+G%.([%w_]+)%s*=") do
				defined[n] = true
			end
		end
	end
end
scanDefs("src/server")
-- fields of G set at load time (g_local.luau, and tables such as the
-- vmCvar_t globals that g_main builds in a loop): load every server
-- module and collect what ends up on G
local G = require("../src/server/g_local")
local function loadAll(dir)
	for _, name in fs.readDir(dir) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then
			loadAll(p)
		elseif string.match(name, "%.luau$") then
			pcall(function()
				return (require :: any)("../" .. string.gsub(p, "%.luau$", ""))
			end)
		end
	end
end
loadAll("src/server")
for k in G do
	defined[k] = true
end

local errors, warnings = 0, 0
if strict then
	for n, where in duplicates do
		print(string.format("G.%s is defined twice: %s", n, where))
		errors += 1
	end
end
for _, file in files do
	local src = fs.readFile(file)
	-- 1. load
	local ok, err = pcall(function()
		local rel = "../" .. string.gsub(file, "%.luau$", "")
		return (require :: any)(rel)
	end)
	if not ok then
		print(string.format("%s: load error: %s", file, tostring(err)))
		errors += 1
	end
	-- strip comments and strings so names inside them are ignored
	local code = string.gsub(src, "%-%-%[(=*)%[.-%]%1%]", "")
	code = string.gsub(code, "%-%-[^\n]*", "")
	code = string.gsub(code, '"[^"\n]*"', '""')
	code = string.gsub(code, "'[^'\n]*'", "''")
	-- 2. module members
	local bound = {}
	for lname, path in string.gmatch(src, "local%s+([%w_]+)%s*=%s*require%(%s*\"([^\"]+)\"%s*%)") do
		local base = string.match(path, "([^/]+)$")
		local t = modulePaths[base]
		if t then
			bound[lname] = t
		end
	end
	local seenMissing = {}
	for lname, t in bound do
		for name in string.gmatch(code, "%f[%w_]" .. lname .. "%.([%w_]+)") do
			if tables[t][name] == nil and not seenMissing[lname .. "." .. name] then
				seenMissing[lname .. "." .. name] = true
				-- G-side helpers sometimes live on S/BG lazily; only constants are fatal
				print(string.format("%s: unknown %s.%s", file, lname, name))
				errors += 1
			end
		end
	end
	-- 3. G calls
	local seenG = {}
	for name in string.gmatch(code, "%f[%w_]G%.([%w_]+)") do
		if not defined[name] and not seenG[name] then
			seenG[name] = true
			if strict then
				print(string.format("%s: G.%s is not defined in src/server", file, name))
				errors += 1
			else
				warnings += 1
			end
		end
	end
	if not strict and next(seenG) then
		local names = {}
		for n in seenG do
			table.insert(names, n)
		end
		table.sort(names)
		print(string.format("%s: note: G names not (yet) defined in src/server: %s", file, table.concat(names, ", ")))
	end
end
print(string.format("check_port: %d file(s), %d error(s)", #files, errors))
process.exit(if errors > 0 then 1 else 0)
