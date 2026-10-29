-- Every constant and enum value of the OpenArena headers the client uses,
-- flat and keyed by C name (see consts/shared.luau and consts/cg.luau).
local C = table.clone(require(script.Parent.consts.shared))
for k, v in require(script.Parent.consts.cg) do
	C[k] = v
end
C.PITCH, C.YAW, C.ROLL = 0, 1, 2
return table.freeze(C)
