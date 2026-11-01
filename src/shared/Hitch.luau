-- Frame-time profiler behind a cvar (cl_hitchlog on the client, sv_hitchlog
-- on the server): its value is a threshold in ms, 0 is off. A frame over it
-- prints its time split into the buckets the caller laps; every 30 s a
-- histogram of frame times, the slowest frame and the Luau heap are printed.
local Hitch = {}
Hitch.__index = Hitch

local EDGES = { 4, 8, 16, 33, 50, 100, 250, 500 }

export type Hitch = typeof(setmetatable(
	{} :: {
		label: string,
		order: { string },
		cur: { [string]: number },
		hist: { number },
		t0: number,
		last: number,
		since: number,
		worst: number,
		frames: number,
		heapMax: number,
	},
	Hitch
))

function Hitch.new(label: string): Hitch
	return setmetatable({
		label = label,
		order = {},
		cur = {},
		hist = table.create(#EDGES + 1, 0),
		t0 = 0,
		last = 0,
		since = os.clock(),
		worst = 0,
		frames = 0,
		heapMax = 0,
	}, Hitch)
end

function Hitch.start(self: Hitch)
	self.t0 = os.clock()
	self.last = self.t0
	for k in self.cur do
		self.cur[k] = 0
	end
end

-- the time since the last lap (or start) goes to bucket `name`
function Hitch.lap(self: Hitch, name: string)
	local t = os.clock()
	if self.cur[name] == nil then
		table.insert(self.order, name)
	end
	self.cur[name] = (self.cur[name] or 0) + (t - self.last)
	self.last = t
end

-- ends the frame; `ms` overrides the measured time (a frame interval),
-- `note` is printed with a slow frame
function Hitch.stop(self: Hitch, threshold: number, ms: number?, note: string?)
	local now = os.clock()
	local total = ms or (now - self.t0) * 1000
	local k = #EDGES + 1
	for i, e in EDGES do
		if total < e then
			k = i
			break
		end
	end
	self.hist[k] += 1
	self.frames += 1
	self.worst = math.max(self.worst, total)
	local heap = gcinfo()
	self.heapMax = math.max(self.heapMax, heap)
	if total >= threshold then
		local parts = {}
		for _, name in self.order do
			local v = self.cur[name] * 1000
			if v >= 0.05 then
				table.insert(parts, string.format("%s %.1f", name, v))
			end
		end
		print(string.format("%s hitch %.1f ms: %s%s", self.label, total, table.concat(parts, ", "),
			if note then " " .. note else ""))
	end
	if now - self.since >= 30 then
		local parts = {}
		local lo = 0
		for i, n in self.hist do
			local e = EDGES[i]
			table.insert(parts, string.format("%s-%s:%d", tostring(lo), if e then tostring(e) else "", n))
			lo = e
		end
		print(string.format("%s frames %d in %.0f s, worst %.1f ms, heap %d KB (max %d) [%s]", self.label,
			self.frames, now - self.since, self.worst, heap, self.heapMax, table.concat(parts, " ")))
		table.clear(self.hist)
		for i = 1, #EDGES + 1 do
			self.hist[i] = 0
		end
		self.since, self.worst, self.frames, self.heapMax = now, 0, 0, 0
	end
end

return Hitch
