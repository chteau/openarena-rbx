--[[
Copyright (C) 2026 openarena-rbx contributors

This file is part of openarena-rbx, a port of OpenArena to Roblox.

openarena-rbx is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version. See COPYING.
]]
-- Not a port: the live server list of the experience (ui_servers2's
-- "master server"), a MemoryStore SortedMap keyed by join code. Every
-- server heartbeats its entry with an expiry, so a crashed server drops out
-- by itself; BindToClose removes it at once.
--
-- Quotas: MemoryStore allows 1000 + 100 x concurrent users request units a
-- minute for the whole experience. A server writes 6 a minute, and a
-- listing is cached `listCache` seconds for every player of that server.
-- Any failed call (throttled or not) backs the registry off: 2 s, doubling
-- up to `backoffMax`, reset by the next success.
local Registry = {}
Registry.__index = Registry

export type Config = { heartbeat: number, expiry: number, listCache: number, listPages: number, backoffMax: number }

-- map: a MemoryStoreSortedMap (or a stub with the same methods);
-- ascending: Enum.SortDirection.Ascending; now: seconds
function Registry.new(map: any, ascending: any, now: () -> number, cfg: Config)
	return setmetatable({
		map = map,
		ascending = ascending,
		now = now,
		cfg = cfg,
		backoff = 0,
		blockedUntil = -math.huge,
		cache = nil :: { any }?,
		cacheAt = -math.huge,
	}, Registry)
end

function Registry:call(fn: () -> any): (boolean, any)
	if self.now() < self.blockedUntil then
		return false, "backing off"
	end
	local ok, result = pcall(fn)
	if ok then
		self.backoff = 0
	else
		self.backoff = math.min(math.max(2, self.backoff * 2), self.cfg.backoffMax)
		self.blockedUntil = self.now() + self.backoff
	end
	return ok, result
end

function Registry:heartbeat(entry: any): boolean
	entry.time = self.now()
	return (self:call(function()
		self.map:SetAsync(entry.code, entry, self.cfg.expiry)
	end))
end

function Registry:remove(code: string): boolean
	return (self:call(function()
		self.map:RemoveAsync(code)
	end))
end

-- every live entry (the server side's view: access codes included);
-- a cached copy while it's fresh, the last good one while backing off
function Registry:list(): { any }
	if self.cache and self.now() - self.cacheAt < self.cfg.listCache then
		return self.cache
	end
	local out = {}
	local ok = self:call(function()
		local after = nil
		for _ = 1, self.cfg.listPages do
			local page = self.map:GetRangeAsync(self.ascending, 200, after)
			for _, item in page do
				table.insert(out, item.value)
			end
			if #page < 200 then
				break
			end
			after = page[#page].key
		end
	end)
	if ok then
		self.cache, self.cacheAt = out, self.now()
	end
	return self.cache or {}
end

function Registry:lookup(code: string): any?
	if self.cache and self.now() - self.cacheAt < self.cfg.listCache then
		for _, e in self.cache do
			if e.code == code then
				return e
			end
		end
	end
	local ok, e = self:call(function()
		return self.map:GetAsync(code)
	end)
	return if ok then e else nil
end

return Registry
