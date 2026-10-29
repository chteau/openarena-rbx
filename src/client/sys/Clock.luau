-- Sys_Milliseconds: integer milliseconds since the client started.
local Clock = {}

local start = os.clock()
-- Tests and the parity driver pin time with Clock.fixed.
Clock.fixed = nil :: number?

function Clock.Milliseconds(): number
	if Clock.fixed then
		return Clock.fixed
	end
	return math.floor((os.clock() - start) * 1000)
end

return Clock
