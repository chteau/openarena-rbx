-- The engine's cvar store (qcommon/cvar.c semantics, trimmed to what the
-- client uses): creation with flags, set/reset, vmCvar_t mirroring for
-- cgame/ui, and change tracking for userinfo and archived cvars.
local C = require(script.Parent.Parent.q.Consts)

local Cvar = {}

export type cvar = {
	name: string,
	string: string,
	resetString: string,
	flags: number,
	modified: boolean,
	modificationCount: number,
	value: number,
	integer: number,
}

local vars: { [string]: cvar } = {}
Cvar.vars = vars
-- Bits of CVAR_* that changed since the engine last looked (cvar_modifiedFlags).
Cvar.modifiedFlags = 0
-- Called with (cvar) after any change; the client hooks userinfo/archiving here.
Cvar.onChange = nil :: ((cvar) -> ())?

local function key(name: string): string
	return string.lower(name)
end

local function toNumber(s: string): number
	-- atof: leading numeric prefix, 0 otherwise
	local n = tonumber((s:match("^%s*([%+%-]?%d*%.?%d*[eE]?[%+%-]?%d*)")))
	return n or 0
end

local function setValue(v: cvar, s: string)
	v.string = s
	v.value = toNumber(s)
	local i = v.value
	v.integer = if i >= 0 then math.floor(i) else math.ceil(i)
	v.modified = true
	v.modificationCount += 1
	Cvar.modifiedFlags = bit32.bor(Cvar.modifiedFlags, v.flags)
	if Cvar.onChange then
		Cvar.onChange(v)
	end
end

function Cvar.Find(name: string): cvar?
	return vars[key(name)]
end

-- Cvar_Get: creates the cvar or merges flags/default into an existing one.
function Cvar.Get(name: string, default: string, flags: number): cvar
	local v = vars[key(name)]
	if v then
		if bit32.band(v.flags, C.CVAR_USER_CREATED) ~= 0 then
			v.flags = bit32.band(v.flags, bit32.bnot(C.CVAR_USER_CREATED))
			v.resetString = default
		elseif default ~= "" and v.resetString == "" then
			v.resetString = default
		end
		v.flags = bit32.bor(v.flags, flags)
		Cvar.modifiedFlags = bit32.bor(Cvar.modifiedFlags, flags)
		return v
	end
	v = {
		name = name,
		string = "",
		resetString = default,
		flags = flags,
		modified = true,
		modificationCount = 0,
		value = 0,
		integer = 0,
	}
	vars[key(name)] = v
	setValue(v, default)
	v.modificationCount = 1
	return v
end

-- Cvar_Set2: `force` bypasses ROM/INIT (engine-side sets).
function Cvar.Set(name: string, value: string?, force: boolean?): cvar?
	local v = vars[key(name)]
	if v == nil then
		if value == nil then
			return nil
		end
		return Cvar.Get(name, value, if force then 0 else C.CVAR_USER_CREATED)
	end
	local s = value or v.resetString
	if not force then
		if bit32.band(v.flags, bit32.bor(C.CVAR_ROM, C.CVAR_INIT)) ~= 0 then
			print(("%s is read only."):format(name))
			return v
		end
	end
	if s == v.string then
		return v
	end
	setValue(v, s)
	return v
end

function Cvar.SetValue(name: string, value: number)
	local s
	if value == math.floor(value) and math.abs(value) < 2 ^ 31 then
		s = string.format("%d", value)
	else
		s = tostring(value)
	end
	Cvar.Set(name, s, false)
end

function Cvar.Reset(name: string)
	Cvar.Set(name, nil, false)
end

function Cvar.VariableString(name: string): string
	local v = vars[key(name)]
	return if v then v.string else ""
end

function Cvar.VariableValue(name: string): number
	local v = vars[key(name)]
	return if v then v.value else 0
end

function Cvar.VariableIntegerValue(name: string): number
	local v = vars[key(name)]
	return if v then v.integer else 0
end

-- vmCvar_t mirror: handle is the cvar name.
function Cvar.Register(vm, name: string, default: string, flags: number)
	local v = Cvar.Get(name, default, flags)
	if vm then
		vm.handle = v.name
		Cvar.Update(vm)
	end
end

function Cvar.Update(vm)
	local v = vars[key(vm.handle or "")]
	if v == nil or vm.modificationCount == v.modificationCount then
		return
	end
	vm.modificationCount = v.modificationCount
	vm.string = v.string
	vm.value = v.value
	vm.integer = v.integer
end

-- Info string of every cvar with `flag` (CVAR_USERINFO, CVAR_SERVERINFO).
function Cvar.InfoString(flag: number): string
	local names = {}
	for _, v in vars do
		if bit32.band(v.flags, flag) ~= 0 then
			table.insert(names, v.name)
		end
	end
	table.sort(names)
	local out = {}
	for _, n in names do
		table.insert(out, "\\" .. n .. "\\" .. vars[key(n)].string)
	end
	return table.concat(out)
end

-- All CVAR_ARCHIVE cvars as {name = value}, for saving a player's config.
function Cvar.Archived(): { [string]: string }
	local out = {}
	for _, v in vars do
		if bit32.band(v.flags, C.CVAR_ARCHIVE) ~= 0 then
			out[v.name] = v.string
		end
	end
	return out
end

return Cvar
