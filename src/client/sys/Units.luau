-- The Roblox boundary: Quake units/axes <-> studs/Roblox axes.
-- 1 stud = 8 Quake units; Quake (x, y, z) (Z up) -> Roblox (x, z, -y) / 8.
local Units = {}

Units.STUD = 8

function Units.toVector3(v): Vector3
	return Vector3.new(v[0] / 8, v[2] / 8, -v[1] / 8)
end

function Units.toVector3xyz(x: number, y: number, z: number): Vector3
	return Vector3.new(x / 8, z / 8, -y / 8)
end

-- A Quake direction (unit length, no scaling).
function Units.toDirection(v): Vector3
	return Vector3.new(v[0], v[2], -v[1])
end

function Units.fromVector3(p: Vector3, out)
	out[0], out[1], out[2] = p.X * 8, -p.Z * 8, p.Y * 8
	return out
end

-- Quake origin + axis[3] (forward, left, up) -> CFrame whose LookVector is
-- forward, RightVector is -left and UpVector is up.
function Units.toCFrame(origin, axis): CFrame
	local f, l, u = axis[0], axis[1], axis[2]
	local right = Vector3.new(-l[0], -l[2], l[1])
	local up = Vector3.new(u[0], u[2], -u[1])
	local back = Vector3.new(-f[0], -f[2], f[1])
	return CFrame.fromMatrix(Units.toVector3(origin), right, up, back)
end

-- Same, with the axis vectors possibly scaled (RF scaled models): returns
-- the CFrame from normalised vectors plus the per-axis scale.
function Units.toCFrameScaled(origin, axis): (CFrame, Vector3)
	local function len(v)
		return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
	end
	local sf, sl, su = len(axis[0]), len(axis[1]), len(axis[2])
	local function n(v, s)
		s = if s > 0 then s else 1
		return { [0] = v[0] / s, [1] = v[1] / s, [2] = v[2] / s }
	end
	local cf = Units.toCFrame(origin, { [0] = n(axis[0], sf), [1] = n(axis[1], sl), [2] = n(axis[2], su) })
	-- Roblox X is right (-left), Y is up, Z is back (-forward)
	return cf, Vector3.new(sl, su, sf)
end

return Units
