-- lune run tests/lint <file.luau...>: flags free names that look like C
-- globals a port forgot to prefix (CG_Foo instead of G.CG_Foo, MAX_CLIENTS
-- instead of C.MAX_CLIENTS, trap_X instead of trap.X, a bare `cg`).
local fs = require("@lune/fs")
local process = require("@lune/process")

local KEYWORDS = {}
for w in ("and break do else elseif end false for function if in local nil not or repeat return then true until while continue type export"):gmatch("%a+") do
	KEYWORDS[w] = true
end
local LUAU_GLOBALS = {}
for w in ("math string table bit32 buffer coroutine debug os utf8 print error assert pcall xpcall select type typeof tostring tonumber pairs ipairs next rawget rawset rawequal rawlen setmetatable getmetatable unpack require script game workspace task tick Instance Vector3 Vector2 CFrame Color3 UDim UDim2 Enum Rect NumberRange NumberSequence NumberSequenceKeypoint ColorSequence ColorSequenceKeypoint Font RaycastParams TweenInfo BrickColor Ray Region3 PhysicalProperties Axes Faces DateTime _G _VERSION self"):gmatch("[%w_]+") do
	LUAU_GLOBALS[w] = true
end

local function strip(src: string): string
	-- blanks comments and string literals (keeping newlines) so only code is scanned
	local out = table.create(#src)
	local i, n = 1, #src
	while i <= n do
		local c = src:sub(i, i)
		local long = src:match("^%[(=*)%[", i)
		if c == "-" and src:sub(i + 1, i + 1) == "-" then
			local eq = src:match("^%-%-%[(=*)%[", i)
			local j
			if eq then
				local _, e = src:find("]" .. eq .. "]", i, true)
				j = e or n
			else
				j = (src:find("\n", i, true) or (n + 1)) - 1
			end
			table.insert(out, (src:sub(i, j):gsub("[^\n]", " ")))
			i = j + 1
		elseif long then
			local _, e = src:find("]" .. long .. "]", i, true)
			local j = e or n
			table.insert(out, '""' .. (src:sub(i, j):gsub("[^\n]", "")))
			i = j + 1
		elseif c == '"' or c == "'" or c == "`" then
			local j = i + 1
			while j <= n do
				local d = src:sub(j, j)
				if d == "\\" then
					j += 2
				elseif d == c or d == "\n" then
					break
				else
					j += 1
				end
			end
			table.insert(out, '""')
			i = j + 1
		else
			table.insert(out, c)
			i += 1
		end
	end
	return table.concat(out)
end

local failed = false
for _, file in process.args do
	local src = strip(fs.readFile(file))
	local declared = {}
	for name in src:gmatch("local%s+function%s+([%w_]+)") do
		declared[name] = true
	end
	for list in src:gmatch("local%s+([%w_,%s]+)") do
		for name in list:gmatch("[%w_]+") do
			declared[name] = true
		end
	end
	for params in src:gmatch("function[%w_%.:%s]*%(([^)]*)%)") do
		for name in params:gmatch("[%w_]+") do
			declared[name] = true
		end
	end
	for vars in src:gmatch("for%s+([%w_,%s]+)%s+[=i]") do
		for name in vars:gmatch("[%w_]+") do
			declared[name] = true
		end
	end
	local seen = {}
	local line = 1
	local pos = 1
	for prev, name, p in src:gmatch("()([%a_][%w_]*)()") do
		local before = src:sub(prev - 1, prev - 1)
		local isMember = before == "." or before == ":"
		local nextChar = src:match("^%s*(.)", p)
		local isKey = nextChar == "=" and src:sub(p):match("^%s*=[^=]") ~= nil and (src:sub(1, prev - 1):match("[{,]%s*$") ~= nil)
		if not isMember and not isKey and not KEYWORDS[name] and not LUAU_GLOBALS[name] and not declared[name] and not seen[name] then
			local suspicious = name:match("^CG_") or name:match("^BG_") or name:match("^UI_") or name:match("^trap_")
				or name:match("^Q_") or name:match("^Com_") or name:match("^Vector") or name:match("^Menu")
				or name:match("^Info_") or name:match("^Angle") or (name:match("^%u[%u%d_]+$") and #name >= 3)
				or name == "cg" or name == "cgs" or name == "uis" or name:match("^cg_") or name:match("^ui_")
				or name == "qtrue" or name == "qfalse" or name == "NULL"
			if suspicious then
				seen[name] = true
				local _, n = src:sub(1, prev):gsub("\n", "")
				print(("%s:%d: free name %s (missing G./U./C./Q./trap. prefix or local?)"):format(file, n + 1, name))
				failed = true
			end
		end
	end
	local _ = line + pos
end
print(if failed then "lint: FAIL" else "lint: ok")
process.exit(if failed then 1 else 0)
