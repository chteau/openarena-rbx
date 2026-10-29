--[[
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.
Copyright (C) 2005-2012 The OpenArena team

This file is part of the OpenArena Roblox port, a Luau port of the
Quake III Arena / OpenArena source code (ioquake3 code/qcommon/files.c).

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
===========================================================================
]]
--!native
-- A virtual file system behind trap_FS_* (the subset of ioquake3's
-- qcommon/files.c the game module uses). There is no disk on a Roblox
-- server: read-only files (scripts/*.arena, scripts/bots.txt, maps/*.bsp
-- names, admin config seeds ...) are mounted by the host from converted
-- data, and files the game writes (games.log, admin.dat, ...) live in
-- memory, where the host can read them back or persist them.
--
-- Paths are case-insensitive and use '/', like the pk3 search path.

local C = require("../g_defs")

local Fs = {}

-- lower-case path -> { name = original path, data = string }
local files: { [string]: { name: string, data: string } } = {}

-- open handles: handle -> { path, mode, pos }
local handles: { [number]: { key: string, mode: number, pos: number } } = {}
local MAX_FILE_HANDLES = 64

-- called after every write to a file (host persistence hook)
Fs.onWrite = nil :: ((path: string, data: string) -> ())?

local function norm(path: string): string
	path = string.gsub(path, "\\", "/")
	path = string.gsub(path, "^/+", "")
	return string.lower(path)
end

function Fs.Mount(path: string, data: string)
	files[norm(path)] = { name = path, data = data }
end

function Fs.Unmount(path: string)
	files[norm(path)] = nil
end

function Fs.Clear()
	table.clear(files)
	table.clear(handles)
end

-- whole-file read; nil if missing
function Fs.ReadFile(path: string): string?
	local f = files[norm(path)]
	return f and f.data
end

function Fs.WriteFile(path: string, data: string)
	Fs.Mount(path, data)
	if Fs.onWrite then
		Fs.onWrite(path, data)
	end
end

function Fs.Exists(path: string): boolean
	return files[norm(path)] ~= nil
end

-- trap_FS_FOpenFile: returns (length, handle); (-1, 0) when a read finds nothing
function Fs.FOpenFile(path: string, mode: number): (number, number)
	local h = 0
	for i = 1, MAX_FILE_HANDLES - 1 do
		if not handles[i] then
			h = i
			break
		end
	end
	if h == 0 then
		return -1, 0
	end
	local key = norm(path)
	if mode == C.FS_READ then
		local f = files[key]
		if not f then
			return -1, 0
		end
		handles[h] = { key = key, mode = mode, pos = 0 }
		return #f.data, h
	elseif mode == C.FS_WRITE then
		files[key] = { name = path, data = "" }
		handles[h] = { key = key, mode = mode, pos = 0 }
		return 0, h
	elseif mode == C.FS_APPEND or mode == C.FS_APPEND_SYNC then
		local f = files[key]
		if not f then
			f = { name = path, data = "" }
			files[key] = f
		end
		handles[h] = { key = key, mode = mode, pos = #f.data }
		return #f.data, h
	end
	error("FS_FOpenFileByMode: bad mode")
end

-- trap_FS_Read: returns up to len bytes from the current position
function Fs.Read(len: number, h: number): string
	local hd = handles[h]
	if not hd then
		return ""
	end
	local f = files[hd.key]
	if not f then
		return ""
	end
	local s = string.sub(f.data, hd.pos + 1, hd.pos + len)
	hd.pos += #s
	return s
end

-- trap_FS_Write: writes the first len bytes of text
function Fs.Write(text: string, len: number, h: number)
	local hd = handles[h]
	if not hd or hd.mode == C.FS_READ then
		return
	end
	local f = files[hd.key]
	if not f then
		return
	end
	local chunk = string.sub(text, 1, len)
	local d = f.data
	f.data = string.sub(d, 1, hd.pos) .. chunk .. string.sub(d, hd.pos + #chunk + 1)
	hd.pos += #chunk
	if Fs.onWrite then
		Fs.onWrite(f.name, f.data)
	end
end

function Fs.FCloseFile(h: number)
	handles[h] = nil
end

-- trap_FS_Seek: returns 0 on success, -1 on failure
function Fs.Seek(h: number, offset: number, origin: number): number
	local hd = handles[h]
	if not hd then
		return -1
	end
	local size = #(files[hd.key] and files[hd.key].data or "")
	local base
	if origin == C.FS_SEEK_CUR then
		base = hd.pos
	elseif origin == C.FS_SEEK_END then
		base = size
	elseif origin == C.FS_SEEK_SET then
		base = 0
	else
		error("Bad origin in FS_Seek")
	end
	local p = base + offset
	if p < 0 or p > size then
		return -1
	end
	hd.pos = p
	return 0
end

-- trap_FS_GetFileList: names under `path` (relative to it, without the
-- directory) ending in `extension` (case-insensitive); extension "/"
-- lists subdirectories. Returns (count, 0-based names), sorted the way
-- FS_SortFileList orders pk3 listings.
function Fs.GetFileList(path: string, extension: string): (number, { [number]: string })
	local dir = norm(path)
	if dir ~= "" and string.sub(dir, -1) ~= "/" then
		dir ..= "/"
	end
	local ext = string.lower(extension or "")
	if ext ~= "" and ext ~= "/" and string.sub(ext, 1, 1) ~= "." then
		ext = "." .. ext
	end
	local seen = {}
	local list = {}
	for key, f in files do
		if string.sub(key, 1, #dir) == dir then
			local rest = string.sub(f.name, #dir + 1)
			rest = string.gsub(rest, "\\", "/")
			local slash = string.find(rest, "/", 1, true)
			if ext == "/" then
				if slash then
					local sub = string.sub(rest, 1, slash - 1)
					if not seen[string.lower(sub)] then
						seen[string.lower(sub)] = true
						table.insert(list, sub)
					end
				end
			elseif not slash then
				if ext == "" or string.lower(string.sub(rest, -#ext)) == ext then
					table.insert(list, rest)
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return string.lower(a) < string.lower(b)
	end)
	local out = {}
	for i, n in list do
		out[i - 1] = n
	end
	return #list, out
end

return Fs
