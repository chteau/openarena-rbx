-- Loads the repo's ModuleScripts under lune with a Roblox-like `script` tree,
-- so modules written for Roblox (`require(script.Parent.X)`) run unchanged.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local H = {}
H.roblox = roblox
H.root = process.cwd:gsub("/$", "") .. "/src"

-- The whole src/ tree is read up front: lune's fs calls yield, and lookups
-- happen inside __index metamethods, which can't yield.
local isDir: { [string]: boolean } = {}
local sources: { [string]: string } = {}
local function scan(dir: string)
	isDir[dir] = true
	for _, e in fs.readDir(dir) do
		local p = dir .. "/" .. e
		if fs.isDir(p) then
			scan(p)
		elseif e:match("%.luau?$") then
			sources[p] = fs.readFile(p)
		end
	end
end
scan(H.root)

-- `H.graft(diskDir, rel)` makes the modules in diskDir appear under src/<rel>
-- (e.g. the generated build/client/Files pack next to sys/FS).
function H.graft(diskDir: string, rel: string)
	local dst = H.root .. "/" .. rel
	isDir[dst] = true
	for _, e in fs.readDir(diskDir) do
		local p = diskDir .. "/" .. e
		if fs.isDir(p) then
			H.graft(p, rel .. "/" .. e)
		elseif e:match("%.luau?$") then
			sources[dst .. "/" .. e] = fs.readFile(p)
		end
	end
end

local nodes: { [string]: any } = {}
local loaded: { [string]: any } = {}
local loading: { [string]: boolean } = {}

local Node = {}

local function moduleFile(path: string): string?
	for _, ext in { ".luau", ".lua", "/init.luau", "/init.lua" } do
		if sources[path .. ext] then
			return path .. ext
		end
	end
	return nil
end

local function exists(path: string): boolean
	return isDir[path] == true or moduleFile(path) ~= nil
end

local function node(path: string)
	local n = nodes[path]
	if n == nil then
		n = setmetatable({ __path = path }, Node)
		nodes[path] = n
	end
	return n
end

local function parentPath(path: string): string
	return (path:match("^(.*)/[^/]+$")) or path
end

Node.__index = function(self, key)
	local path = rawget(self, "__path")
	if key == "Name" then
		return path:match("([^/]+)$")
	elseif key == "Parent" then
		return node(parentPath(path))
	elseif key == "FindFirstChild" then
		return function(_, name)
			local child = path .. "/" .. name
			return if exists(child) then node(child) else nil
		end
	elseif key == "WaitForChild" then
		return function(_, name)
			local child = path .. "/" .. name
			assert(exists(child), "WaitForChild: no " .. child)
			return node(child)
		end
	elseif key == "GetChildren" then
		return function()
			local out = {}
			local seen = {}
			local prefix = path .. "/"
			local function add(p)
				local name = p:sub(#prefix + 1):match("^([^/]+)")
				name = name and name:gsub("%.luau?$", "")
				if name and name ~= "init" and not seen[name] then
					seen[name] = true
					table.insert(out, node(prefix .. name))
				end
			end
			for p in sources do
				if p:sub(1, #prefix) == prefix then
					add(p)
				end
			end
			for p in isDir do
				if p:sub(1, #prefix) == prefix then
					add(p)
				end
			end
			table.sort(out, function(a, b)
				return rawget(a, "__path") < rawget(b, "__path")
			end)
			return out
		end
	elseif key == "IsA" then
		return function(_, class)
			return class == "ModuleScript" and moduleFile(path) ~= nil
		end
	end
	local child = path .. "/" .. key
	if exists(child) then
		return node(child)
	end
	error(("%s is not a valid member of %s"):format(tostring(key), path), 2)
end
Node.__tostring = function(self)
	return rawget(self, "__path")
end

H.game = roblox.Instance.new("DataModel")
H.globals = {
	game = H.game,
	workspace = H.game:GetService("Workspace"),
	task = task,
	tick = os.clock,
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Rect = roblox.Rect,
	Enum = roblox.Enum,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	Font = roblox.Font,
}

local function requireNode(n)
	local path = rawget(n, "__path")
	local file = moduleFile(path)
	assert(file, "require: no module at " .. path)
	if loaded[file] ~= nil then
		return loaded[file]
	end
	assert(not loading[file], "cyclic require of " .. file)
	loading[file] = true
	-- lune copies the environment's own fields (not its metatable), so the
	-- Roblox globals go in directly
	local env = table.clone(H.globals)
	env.script = node(path)
	env.require = function(m)
		if type(m) == "table" and rawget(m, "__path") then
			return requireNode(m)
		end
		if type(m) == "string" and (m:sub(1, 2) == "./" or m:sub(1, 3) == "../") then
			-- Luau require-by-string: relative to the requiring module's folder
			local dir = if file:match("/init%.luau?$") then parentPath(parentPath(file)) else parentPath(file)
			for part in m:gmatch("[^/]+") do
				if part == ".." then
					dir = parentPath(dir)
				elseif part ~= "." then
					dir ..= "/" .. part
				end
			end
			return requireNode(node(dir))
		end
		return require(m)
	end
	local fn = luau.load(sources[file], { debugName = file:sub(#H.root - 2), environment = env })
	local result = fn()
	-- Roblox: "Module code did not return exactly one value"
	assert(result ~= nil, "module returned nothing (or nil): " .. file)
	loaded[file] = if result == nil then true else result
	loading[file] = nil
	return result
end

-- `H.require("client/q/Q")` loads src/client/q/Q.luau.
function H.require(rel: string)
	return requireNode(node(H.root .. "/" .. rel))
end

function H.node(rel: string)
	return node(H.root .. "/" .. rel)
end

-- Minimal test registry used by tests/*.test.luau.
local results = { pass = 0, fail = 0, failures = {} }
H.results = results

function H.test(name: string, fn: () -> ())
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		results.pass += 1
	else
		results.fail += 1
		table.insert(results.failures, name .. ": " .. tostring(err))
	end
end

function H.eq(a, b, msg: string?)
	if a ~= b then
		error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", tostring(b), tostring(a)), 2)
	end
end

function H.near(a: number, b: number, eps: number?, msg: string?)
	if math.abs(a - b) > (eps or 1e-4) then
		error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", tostring(b), tostring(a)), 2)
	end
end

return H
