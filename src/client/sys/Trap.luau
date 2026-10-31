-- The engine side of every trap_* syscall cgame and q3_ui make, on top of
-- the sys/ modules. Names drop the `trap_` prefix; out-params and buffers
-- follow .forge/cheats/trap.md (also summarised in docs/client-notes.md).
-- Subsystems are required lazily so a ported module loads without them.
local C = require(script.Parent.Parent.q.Consts)
local LAN = require(script.Parent.LAN)

local sys = script.Parent
local cache = {}
local function mod(name: string)
	local m = cache[name]
	if m == nil then
		m = require(sys:FindFirstChild(name))
		cache[name] = m
	end
	return m
end
local function CM()
	local m = cache.CM
	if m == nil then
		m = require(script.Parent.Parent.adapters.CM)
		cache.CM = m
	end
	return m
end

local trap = {}

-- console / cvars / commands -------------------------------------------
function trap.Print(msg: string)
	mod("Console").Print(msg)
end
-- Roblox: the server's frame of a filtered chat line (cg_servercmds "rchat")
function trap.ChatFrame(id: string, cmd: string, prefix: string)
	mod("Chat").Frame(id, cmd, prefix)
end
function trap.Error(msg: string)
	error(msg, 2)
end
function trap.Milliseconds(): number
	return mod("Clock").Milliseconds()
end
function trap.RealTime(qtime)
	local t = os.date("*t")
	if qtime then
		qtime.tm_sec, qtime.tm_min, qtime.tm_hour = t.sec, t.min, t.hour
		qtime.tm_mday, qtime.tm_mon, qtime.tm_year = t.day, t.month - 1, t.year - 1900
		qtime.tm_wday, qtime.tm_yday, qtime.tm_isdst = t.wday - 1, t.yday - 1, if t.isdst then 1 else 0
	end
	return os.time()
end
function trap.MemoryRemaining(): number
	return 64 * 1024 * 1024
end

function trap.Cvar_Register(vm, name: string, default: string, flags: number)
	mod("Cvar").Register(vm, name, default, flags)
end
function trap.Cvar_Update(vm)
	mod("Cvar").Update(vm)
end
function trap.Cvar_Set(name: string, value: string)
	mod("Cvar").Set(name, value, true)
end
function trap.Cvar_SetValue(name: string, value: number)
	mod("Cvar").SetValue(name, value)
end
function trap.Cvar_Reset(name: string)
	mod("Cvar").Reset(name)
end
function trap.Cvar_Create(name: string, value: string, flags: number)
	mod("Cvar").Get(name, value, flags)
end
function trap.Cvar_VariableStringBuffer(name: string): string
	return mod("Cvar").VariableString(name)
end
function trap.Cvar_VariableValue(name: string): number
	return mod("Cvar").VariableValue(name)
end

function trap.Argc(): number
	return mod("Cmd").Argc()
end
function trap.Argv(n: number): string
	return mod("Cmd").Argv(n)
end
function trap.Args(): string
	return mod("Cmd").Args()
end
function trap.AddCommand(name: string)
	mod("Cmd").AddCommand(name, nil)
end
function trap.RemoveCommand(name: string)
	mod("Cmd").RemoveCommand(name)
end
function trap.SendConsoleCommand(text: string)
	mod("Cmd").AddText(text)
end
function trap.Cmd_ExecuteText(when: number, text: string)
	mod("Cmd").ExecuteText(when, text)
end
function trap.SendClientCommand(text: string)
	mod("Net").SendClientCommand(text)
end
function trap.UpdateScreen()
	mod("Client").UpdateScreen()
end

-- files -----------------------------------------------------------------
function trap.FS_FOpenFile(path: string, mode: number): (number, number)
	return mod("FS").FOpenFile(path, mode)
end
function trap.FS_Read(len: number, f: number): string
	return mod("FS").Read(len, f)
end
function trap.FS_Write(buffer: string, len: number, f: number)
	mod("FS").Write(buffer, len, f)
end
function trap.FS_FCloseFile(f: number)
	mod("FS").FCloseFile(f)
end
function trap.FS_Seek(f: number, offset: number, origin: number): number
	return mod("FS").Seek(f, offset, origin)
end
function trap.FS_GetFileList(path: string, ext: string): (number, { [number]: string })
	return mod("FS").GetFileList(path, ext)
end

-- collision -------------------------------------------------------------
function trap.CM_LoadMap(name: string)
	CM().LoadMap(name)
end
function trap.CM_NumInlineModels(): number
	return CM().NumInlineModels()
end
function trap.CM_InlineModel(index: number): number
	return CM().InlineModel(index)
end
function trap.CM_TempBoxModel(mins, maxs): number
	return CM().TempBoxModel(mins, maxs, false)
end
function trap.CM_TempCapsuleModel(mins, maxs): number
	return CM().TempBoxModel(mins, maxs, true)
end
function trap.CM_PointContents(p, model: number): number
	return CM().PointContents(p, model)
end
function trap.CM_TransformedPointContents(p, model: number, origin, angles): number
	return CM().TransformedPointContents(p, model, origin, angles)
end
function trap.CM_BoxTrace(results, start, endp, mins, maxs, model: number, mask: number)
	CM().BoxTrace(results, start, endp, mins, maxs, model, mask, false)
end
function trap.CM_CapsuleTrace(results, start, endp, mins, maxs, model: number, mask: number)
	CM().BoxTrace(results, start, endp, mins, maxs, model, mask, true)
end
function trap.CM_TransformedBoxTrace(results, start, endp, mins, maxs, model: number, mask: number, origin, angles)
	CM().TransformedBoxTrace(results, start, endp, mins, maxs, model, mask, origin, angles, false)
end
function trap.CM_TransformedCapsuleTrace(results, start, endp, mins, maxs, model: number, mask: number, origin, angles)
	CM().TransformedBoxTrace(results, start, endp, mins, maxs, model, mask, origin, angles, true)
end
function trap.CM_MarkFragments(numPoints, points, projection, maxPoints, pointBuffer, maxFragments, fragmentBuffer): number
	return CM().MarkFragments(numPoints, points, projection, maxPoints, pointBuffer, maxFragments, fragmentBuffer)
end

-- sound -----------------------------------------------------------------
function trap.S_RegisterSound(name: string, compressed: boolean?): number
	return mod("Snd").RegisterSound(name)
end
function trap.S_StartSound(origin, entnum: number, channel: number, sfx: number)
	mod("Snd").StartSound(origin, entnum, channel, sfx)
end
function trap.S_StartLocalSound(sfx: number, channel: number)
	mod("Snd").StartLocalSound(sfx, channel)
end
function trap.S_ClearLoopingSounds(killall: boolean)
	mod("Snd").ClearLoopingSounds(killall)
end
function trap.S_AddLoopingSound(entnum: number, origin, velocity, sfx: number)
	mod("Snd").AddLoopingSound(entnum, origin, velocity, sfx, false)
end
function trap.S_AddRealLoopingSound(entnum: number, origin, velocity, sfx: number)
	mod("Snd").AddLoopingSound(entnum, origin, velocity, sfx, true)
end
function trap.S_StopLoopingSound(entnum: number)
	mod("Snd").StopLoopingSound(entnum)
end
function trap.S_UpdateEntityPosition(entnum: number, origin)
	mod("Snd").UpdateEntityPosition(entnum, origin)
end
function trap.S_Respatialize(entnum: number, origin, axis, inwater: number)
	mod("Snd").Respatialize(entnum, origin, axis, inwater)
end
function trap.S_StartBackgroundTrack(intro: string, loop: string)
	mod("Snd").StartBackgroundTrack(intro, loop)
end
function trap.S_StopBackgroundTrack()
	mod("Snd").StopBackgroundTrack()
end

-- renderer --------------------------------------------------------------
function trap.R_LoadWorldMap(name: string)
	mod("R3D").LoadWorldMap(name)
end
function trap.R_RegisterModel(name: string): number
	return mod("Assets").RegisterModel(name)
end
function trap.R_RegisterSkin(name: string): number
	return mod("Assets").RegisterSkin(name)
end
function trap.R_RegisterShader(name: string): number
	return mod("Assets").RegisterShader(name, true)
end
function trap.R_RegisterShaderNoMip(name: string): number
	return mod("Assets").RegisterShader(name, false)
end
function trap.R_RegisterFont(name: string, pointSize: number, font) end
function trap.R_RemapShader(old: string, new: string, timeOffset: string)
	mod("Assets").RemapShader(old, new, timeOffset)
end
function trap.R_ClearScene()
	mod("R3D").ClearScene()
end
function trap.R_AddRefEntityToScene(re)
	mod("R3D").AddRefEntity(re)
end
function trap.R_AddPolyToScene(shader: number, numVerts: number, verts)
	mod("R3D").AddPoly(shader, numVerts, verts)
end
function trap.R_AddPolysToScene(shader: number, numVerts: number, verts, num: number)
	-- verts holds `num` polys of numVerts each, back to back
	local R3D = mod("R3D")
	for p = 0, num - 1 do
		local one = {}
		for v = 0, numVerts - 1 do
			one[v] = verts[p * numVerts + v]
		end
		R3D.AddPoly(shader, numVerts, one)
	end
end
function trap.R_AddLightToScene(org, intensity: number, r: number, g: number, b: number)
	mod("R3D").AddLight(org, intensity, r, g, b, false)
end
function trap.R_AddAdditiveLightToScene(org, intensity: number, r: number, g: number, b: number)
	mod("R3D").AddLight(org, intensity, r, g, b, true)
end
function trap.R_RenderScene(refdef)
	mod("R3D").RenderScene(refdef)
end
function trap.R_LightForPoint(point, ambient, directed, dir): number
	return mod("R3D").LightForPoint(point, ambient, directed, dir)
end
function trap.R_SetColor(rgba)
	mod("R2D").SetColor(rgba)
end
function trap.R_DrawStretchPic(x, y, w, h, s1, t1, s2, t2, shader: number)
	mod("R2D").DrawStretchPic(x, y, w, h, s1, t1, s2, t2, shader)
end
function trap.R_ModelBounds(model: number, mins, maxs)
	mod("Assets").ModelBounds(model, mins, maxs)
end
-- Roblox avatars (sys/Avatar.luau): no C syscall has them
function trap.R_AvatarReady(clientNum: number): boolean
	return mod("Avatar").Ready(clientNum)
end
function trap.R_AddAvatarToScene(av): boolean
	local Avatar = mod("Avatar")
	Avatar.root = mod("R3D").worldRoot
	return Avatar.Draw(av)
end
function trap.R_AvatarTag(entNum: number, name: string, tag): boolean
	return mod("Avatar").Tag(entNum, name, tag)
end
function trap.R_AvatarHeadShader(clientNum: number): number
	return mod("Avatar").HeadShader(clientNum)
end
function trap.R_BotHeadShader(name: string): number
	return mod("Avatar").BotHeadShader(name)
end
function trap.R_LocalHeadShader(): number
	return mod("Avatar").LocalHeadShader()
end
function trap.R_LocalBodyShader(): number
	return mod("Avatar").LocalBodyShader()
end
-- friend-bots: the friend the next bot added to team ("", "red", "blue")
-- would wear, when the server knows (server/sv/avatars_roblox.luau)
function trap.FriendBotNext(team: string): string?
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("OAAvatars")
	local name = folder and folder:GetAttribute("NextFriendBot" .. team)
	return if type(name) == "string" then name else nil
end
function trap.R_AvatarAnimations()
	return require(script.Parent.Parent.avatar.AvatarAnim).animations()
end
function trap.R_LerpTag(tag, model: number, startFrame: number, endFrame: number, frac: number, name: string): boolean
	return mod("Assets").LerpTag(tag, model, startFrame, endFrame, frac, name)
end
function trap.CM_LerpTag(tag, model: number, startFrame: number, endFrame: number, frac: number, name: string): boolean
	return mod("Assets").LerpTag(tag, model, startFrame, endFrame, frac, name)
end
function trap.R_inPVS(p1, p2): boolean
	return CM().InPVS(p1, p2)
end
function trap.GetGlconfig(glconfig)
	mod("R2D").GetGlconfig(glconfig)
end

-- client state / net ------------------------------------------------------
function trap.GetGameState(gs)
	mod("Net").GetGameState(gs)
end
function trap.GetConfigString(index: number): string
	return mod("Net").ConfigString(index)
end
function trap.GetClientState(cs)
	mod("Net").GetClientState(cs)
end
function trap.GetCurrentSnapshotNumber(): (number, number)
	return mod("Net").GetCurrentSnapshotNumber()
end
function trap.GetSnapshot(n: number, snap): boolean
	return mod("Net").GetSnapshot(n, snap)
end
function trap.GetServerCommand(n: number): boolean
	return mod("Net").GetServerCommand(n)
end
function trap.GetCurrentCmdNumber(): number
	return mod("Input").GetCurrentCmdNumber()
end
function trap.GetUserCmd(n: number, cmd): boolean
	return mod("Input").GetUserCmd(n, cmd)
end
function trap.SetUserCmdValue(weapon: number, sensitivityScale: number)
	mod("Input").SetUserCmdValue(weapon, sensitivityScale)
end
function trap.SnapVector(v)
	for i = 0, 2 do
		v[i] = math.floor(v[i] + 0.5)
	end
end

-- keys --------------------------------------------------------------------
function trap.Key_IsDown(k: number): boolean
	return mod("Keys").IsDown(k)
end
function trap.Key_GetCatcher(): number
	return mod("Keys").GetCatcher()
end
function trap.Key_SetCatcher(c: number)
	mod("Keys").SetCatcher(c)
end
function trap.Key_GetKey(binding: string): number
	return mod("Keys").GetKey(binding)
end
function trap.Key_KeynumToStringBuf(k: number): string
	return mod("Keys").KeynumToString(k)
end
function trap.Key_GetBindingBuf(k: number): string
	return mod("Keys").GetBinding(k)
end
function trap.Key_SetBinding(k: number, cmd: string)
	mod("Keys").SetBinding(k, cmd)
end
function trap.Key_GetOverstrikeMode(): boolean
	return mod("Keys").overstrike == true
end
function trap.Key_SetOverstrikeMode(on: boolean)
	mod("Keys").overstrike = on
end
function trap.Key_ClearStates()
	mod("Keys").ClearStates()
end
function trap.GetClipboardData(): string
	return ""
end

-- not available on Roblox (see docs/client-notes.md) ----------------------
function trap.CIN_PlayCinematic(): number
	return -1
end
function trap.CIN_StopCinematic(): number
	return C.FMV_EOF or 0
end
function trap.CIN_RunCinematic(): number
	return C.FMV_EOF or 0
end
function trap.CIN_DrawCinematic() end
function trap.CIN_SetExtents() end
function trap.loadCamera(): boolean
	return false
end
function trap.startCamera() end
function trap.getCameraInfo(): boolean
	return false
end
function trap.GetEntityToken(): (boolean, string)
	return false, ""
end
function trap.PC_AddGlobalDefine(): number
	return 0
end
function trap.PC_LoadSource(): number
	return 0
end
function trap.PC_FreeSource(): number
	return 0
end
function trap.PC_ReadToken(): number
	return 0
end
function trap.PC_SourceFileAndLine(): number
	return 0
end
-- the server browser (sys/LAN.luau, cl_ui.c's LAN_*)
trap.LAN_GetServerCount = LAN.GetServerCount
trap.LAN_GetPingQueueCount = LAN.GetPingQueueCount
trap.LAN_ClearPing = LAN.ClearPing
trap.LAN_GetPing = LAN.GetPing
trap.LAN_GetPingInfo = LAN.GetPingInfo
trap.LAN_GetServerAddressString = LAN.GetServerAddressString
function trap.GetCDKey(): string
	return ""
end
function trap.SetCDKey() end
function trap.VerifyCDKey(): boolean
	return true
end
function trap.CL_UI_RankUserRequestLogout() end
function trap.CL_UI_RankUserLogin() end
function trap.CL_UI_RankUserCreate() end
function trap.CL_UI_RankGetLeauges() end

return trap
