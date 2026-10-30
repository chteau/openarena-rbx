-- Sound (snd_dma.c semantics on Roblox Sounds). Effects come from the sound
-- atlas: Assets.Sound(h).clip = { id, start, len } is played through
-- Sound.PlaybackRegion. Positional sounds sit on an Attachment at the
-- entity (moved by S_UpdateEntityPosition), with Q3's linear falloff
-- (full volume to 80 u, silent at 80 + 1/0.0008 u) as Linear RollOff.
-- The listener follows S_Respatialize. Music tracks are whole assets.
local Assets = require(script.Parent.Assets)
local Units = require(script.Parent.Units)
local Cvar = require(script.Parent.Cvar)
local Cmd = require(script.Parent.Cmd)
local C = require(script.Parent.Parent.q.Consts)

local Snd = {}

local SOUND_FULLVOLUME = 80
local SOUND_MAXDIST = SOUND_FULLVOLUME + 1 / 0.0008

local s_volume = Cvar.Get("s_volume", "0.8", C.CVAR_ARCHIVE)
local s_musicvolume = Cvar.Get("s_musicvolume", "0.25", C.CVAR_ARCHIVE)

-- set by the client
Snd.worldRoot = nil :: Instance? -- holds the emitter part
Snd.localRoot = nil :: Instance? -- holds 2D sounds (SoundService)
Snd.listenerEntity = -1

local emitter: BasePart? = nil
local entityOrigins: { [number]: Vector3 } = {}
-- (entnum, channel) -> playing voice
local voices: { [string]: any } = {}
local free: { any } = {}
local loops: { [number]: any } = {}
local music: Sound? = nil

local function getEmitter(): BasePart?
	if emitter == nil and Snd.worldRoot then
		local p = Instance.new("Part")
		p.Name = "SoundEmitter"
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.Transparency = 1
		p.Size = Vector3.one
		p.CFrame = CFrame.identity
		p.Parent = Snd.worldRoot
		emitter = p
	end
	return emitter
end

local function newVoice()
	local v = table.remove(free)
	if v then
		return v
	end
	local s = Instance.new("Sound")
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = SOUND_FULLVOLUME / Units.STUD
	s.RollOffMaxDistance = SOUND_MAXDIST / Units.STUD
	local att = Instance.new("Attachment")
	att.Name = "Voice"
	return { sound = s, att = att }
end

local function release(key: string, v)
	v.sound:Stop()
	voices[key] = nil
	table.insert(free, v)
end

local function setClip(s: Sound, clip)
	s.SoundId = clip.id
	if clip.len then
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = NumberRange.new(clip.start, clip.start + clip.len)
		s.TimePosition = clip.start
	else
		s.PlaybackRegionsEnabled = false
		s.TimePosition = 0
	end
end

function Snd.RegisterSound(name: string): number
	return Assets.RegisterSound(name)
end

local autoCount = 0

-- S_StartSound: origin nil = follow the entity.
function Snd.StartSound(origin, entnum: number, channel: number, sfx: number)
	local info = Assets.Sound(sfx)
	if info == nil or info.clip == nil then
		return
	end
	local key
	if channel == C.CHAN_AUTO then
		autoCount += 1
		key = "auto" .. autoCount
	else
		key = entnum .. ":" .. channel
		local old = voices[key]
		if old then
			release(key, old)
		end
	end
	local v = newVoice()
	local s: Sound = v.sound
	setClip(s, info.clip)
	s.Volume = s_volume.value
	local local2D = entnum == Snd.listenerEntity and origin == nil
	if local2D or getEmitter() == nil then
		v.att.Parent = nil
		s.Parent = Snd.localRoot
	else
		v.att.Parent = emitter
		v.att.WorldPosition = if origin then Units.toVector3(origin) else (entityOrigins[entnum] or Vector3.zero)
		s.Parent = v.att
	end
	v.entnum = if origin then nil else entnum
	voices[key] = v
	s:Play()
	v.conn = s.Ended:Once(function()
		if voices[key] == v then
			release(key, v)
		end
	end)
end

function Snd.StartLocalSound(sfx: number, channel: number)
	Snd.StartSound(nil, Snd.listenerEntity, channel, sfx)
end

-- S_Play_f: each file named plays as a local sound
function Snd.Play(name: string)
	Snd.StartLocalSound(Snd.RegisterSound(name), C.CHAN_LOCAL_SOUND)
end
Cmd.AddCommand("play", function()
	local c = Cmd.Argc()
	if c < 2 then
		Cmd.print("Usage: play <sound filename> [sound filename] [sound filename] ...")
		return
	end
	for i = 1, c - 1 do
		Snd.Play(Cmd.Argv(i))
	end
end)

function Snd.UpdateEntityPosition(entnum: number, origin)
	local p = Units.toVector3(origin)
	entityOrigins[entnum] = p
	for _, v in voices do
		if v.entnum == entnum and v.att.Parent then
			v.att.WorldPosition = p
		end
	end
	local l = loops[entnum]
	if l and l.att.Parent then
		l.att.WorldPosition = p
	end
end

function Snd.Respatialize(entnum: number, origin, axis, inwater: number)
	Snd.listenerEntity = entnum
	local SoundService = game:GetService("SoundService")
	pcall(function()
		SoundService:SetListener(Enum.ListenerType.CFrame, Units.toCFrame(origin, axis))
	end)
end

-- Looping sounds: re-added every frame; loops not re-added by the next
-- Update() stop (S_ClearLoopingSounds(false) + S_Update semantics).
function Snd.ClearLoopingSounds(killall: boolean)
	for entnum, l in loops do
		l.active = false
		if killall then
			l.sound:Stop()
			l.att:Destroy()
			loops[entnum] = nil
		end
	end
end

function Snd.AddLoopingSound(entnum: number, origin, velocity, sfx: number, real: boolean)
	local info = Assets.Sound(sfx)
	if info == nil or info.clip == nil then
		return
	end
	local l = loops[entnum]
	if l == nil or l.sfx ~= sfx then
		if l then
			l.sound:Stop()
			l.att:Destroy()
		end
		local e = getEmitter()
		if e == nil then
			return
		end
		local att = Instance.new("Attachment")
		att.Name = "Loop" .. entnum
		att.Parent = e
		local s = Instance.new("Sound")
		s.Looped = true
		s.RollOffMode = Enum.RollOffMode.Linear
		s.RollOffMinDistance = SOUND_FULLVOLUME / Units.STUD
		s.RollOffMaxDistance = SOUND_MAXDIST / Units.STUD
		setClip(s, info.clip)
		s.Parent = att
		l = { sound = s, att = att, sfx = sfx }
		loops[entnum] = l
		s:Play()
	end
	l.active = true
	l.att.WorldPosition = Units.toVector3(origin)
	l.sound.Volume = s_volume.value
end

function Snd.StopLoopingSound(entnum: number)
	local l = loops[entnum]
	if l then
		l.sound:Stop()
		l.att:Destroy()
		loops[entnum] = nil
	end
end

-- After each frame: drop loops nobody re-added.
function Snd.Update()
	for entnum, l in loops do
		if not l.active then
			l.sound:Stop()
			l.att:Destroy()
			loops[entnum] = nil
		end
	end
	if music then
		music.Volume = s_musicvolume.value
	end
end

-- Music: index.music[path] = asset id (whole tracks, not in the atlas).
function Snd.StartBackgroundTrack(intro: string, loop: string)
	Snd.StopBackgroundTrack()
	local tracks = Assets.index.music or {}
	local function id(path)
		return path ~= "" and tracks[Assets.stripExt(path)] or nil
	end
	local introId, loopId = id(intro), id(loop)
	if introId == nil and loopId == nil then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "Music"
	s.Volume = s_musicvolume.value
	s.SoundId = introId or loopId
	s.Looped = introId == nil
	s.Parent = Snd.localRoot
	music = s
	if introId and loopId then
		s.Ended:Once(function()
			if music == s then
				s.SoundId = loopId
				s.Looped = true
				s:Play()
			end
		end)
	end
	s:Play()
end

function Snd.StopBackgroundTrack()
	if music then
		music:Stop()
		music:Destroy()
		music = nil
	end
end

return Snd
