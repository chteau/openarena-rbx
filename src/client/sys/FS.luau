-- The read-only virtual filesystem cgame/ui see (trap_FS_*): text files
-- the game reads at runtime (animation.cfg, *.skin, default.cfg, arena and
-- bot scripts, shader scripts) plus the list of every path in the OA data,
-- so directory scans (player models, icons, levelshots) work.
--
-- The data comes from a `Files` ModuleScript: { files = {[path] = text},
-- paths = { path, ... } }, built from the pk3s (scripts/client-dev-assets.py
-- writes build/client/Files/; the place assembly puts it next to this
-- module). Paths are compared case-insensitively, as in Q3.
local FS = {}

local files: { [string]: string } = {}
local paths: { string } = {}
local handles: { [number]: { data: string, pos: number, write: boolean, path: string } } = {}
local nextHandle = 1
-- files written by the game (q3config-like saves) stay in memory
local written: { [string]: string } = {}

function FS.Mount(pack)
	table.clear(files)
	for p, text in pack.files or {} do
		files[string.lower(p)] = text
	end
	paths = {}
	for _, p in pack.paths or {} do
		table.insert(paths, string.lower(p))
	end
	for p in files do
		table.insert(paths, p)
	end
	table.sort(paths)
end

do
	local ok, pack = pcall(function()
		local m = script.Parent:FindFirstChild("Files")
		return m and require(m)
	end)
	if ok and pack then
		FS.Mount(pack)
	end
end

function FS.ReadFile(path: string): string?
	local p = string.lower(path)
	return written[p] or files[p]
end

-- trap_FS_FOpenFile: returns (length, handle); (-1, 0) when missing.
function FS.FOpenFile(path: string, mode: number): (number, number)
	local p = string.lower(path)
	local h = nextHandle
	nextHandle += 1
	if mode == 0 then -- FS_READ
		local data = written[p] or files[p]
		if data == nil then
			if not FS.Exists(p) then
				return -1, 0
			end
			-- a binary file (image, model, sound): it exists, its bytes live in
			-- the asset index, not here. Callers only use this to test for it.
			handles[h] = { data = "", pos = 1, write = false, path = p }
			return 1, h
		end
		handles[h] = { data = data, pos = 1, write = false, path = p }
		return #data, h
	end
	handles[h] = { data = if mode == 2 then (written[p] or "") else "", pos = 1, write = true, path = p }
	return 0, h
end

function FS.Read(len: number, f: number): string
	local h = handles[f]
	if h == nil then
		return ""
	end
	local s = h.data:sub(h.pos, h.pos + len - 1)
	h.pos += #s
	return s
end

function FS.Write(buffer: string, len: number, f: number)
	local h = handles[f]
	if h and h.write then
		h.data ..= buffer:sub(1, len)
	end
end

function FS.FCloseFile(f: number)
	local h = handles[f]
	if h and h.write then
		written[h.path] = h.data
	end
	handles[f] = nil
end

function FS.Seek(f: number, offset: number, origin: number): number
	local h = handles[f]
	if h == nil then
		return -1
	end
	if origin == 0 then -- FS_SEEK_CUR
		h.pos += offset
	elseif origin == 1 then -- FS_SEEK_END
		h.pos = #h.data + 1 + offset
	else -- FS_SEEK_SET
		h.pos = 1 + offset
	end
	return 0
end

-- FS_GetFileList: names (relative to `path`) of the files in it with
-- extension `ext`, or of its subdirectories when ext is "/".
function FS.GetFileList(path: string, ext: string): (number, { [number]: string })
	local dir = string.lower(path):gsub("/$", "") .. "/"
	local wantDirs = ext == "/"
	local e = string.lower(ext):gsub("^%.", "")
	local out, seen = {}, {}
	local n = 0
	for _, p in paths do
		if p:sub(1, #dir) == dir then
			local rest = p:sub(#dir + 1)
			local name
			if wantDirs then
				name = rest:match("^([^/]+)/")
			elseif not rest:find("/", 1, true) and (e == "" or rest:match("%.([^.]+)$") == e) then
				name = rest
			end
			if name and not seen[name] then
				seen[name] = true
				out[n] = name
				n += 1
			end
		end
	end
	return n, out
end

function FS.Exists(path: string): boolean
	local p = string.lower(path)
	if files[p] or written[p] then
		return true
	end
	-- binary files (images, models) are listed in paths only
	local lo, hi = 1, #paths
	while lo <= hi do
		local mid = (lo + hi) // 2
		if paths[mid] == p then
			return true
		elseif paths[mid] < p then
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return false
end

return FS
