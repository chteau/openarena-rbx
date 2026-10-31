-- The loading screen a teleport carries (ReplicatedFirst.OALoadingScreen):
-- built before the teleport (TeleportService:SetTeleportGui), rebuilt on
-- arrival when the carried one is missing, and faded out once the map is up.
-- It depends on nothing but Roblox, since ReplicatedFirst runs before
-- ReplicatedStorage has replicated.
--
-- Layout: the levelshot crops to cover the whole screen (insets ignored, so
-- no bar shows on a notched phone); the text sits on a 4:3 stage (OA's 640x480
-- virtual screen) that fits and centres in any aspect ratio, so it stays
-- clear of the screen edges and safe areas whatever the shape.
local LoadingScreen = {}

LoadingScreen.name = "OALoadingScreen"
LoadingScreen.ready = "OAReady" -- LocalPlayer attribute, set once the map is up

local FADE = 0.4

local function text(parent: Instance, str: string, y: number, h: number, font: Enum.Font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.fromScale(0.5, y / 480)
	l.Size = UDim2.fromScale(0.9, h / 480)
	l.Font = font
	l.Text = str
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	-- OA's drop shadow
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = l
	l.Parent = parent
end

-- map: the level's name ("oa_dm1"), shot: its levelshot ("rbxassetid://123");
-- either may be nil
function LoadingScreen.build(map: string?, shot: string?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = LoadingScreen.name
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000

	local root = Instance.new("CanvasGroup")
	root.Name = "Root"
	root.BackgroundColor3 = Color3.new(0, 0, 0)
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	if shot then
		local img = Instance.new("ImageLabel")
		img.Name = "Levelshot"
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = shot
		img.ScaleType = Enum.ScaleType.Crop
		img.Parent = root
	end

	-- OA lays a detail texture over the levelshot; a dim veil keeps the text legible
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = 0.6
	veil.BorderSizePixel = 0
	veil.Size = UDim2.fromScale(1, 1)
	veil.Parent = root

	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromScale(0.92, 0.92)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 4 / 3
	ratio.AspectType = Enum.AspectType.FitWithinMaxSize
	ratio.DominantAxis = Enum.DominantAxis.Width
	ratio.Parent = stage
	stage.Parent = root

	text(stage, "Loading...", 80, 44, Enum.Font.Michroma)
	if map and map ~= "" then
		text(stage, map, 136, 28, Enum.Font.Michroma)
	end
	return gui
end

-- Fades the screen out and removes it.
function LoadingScreen.dismiss(gui: ScreenGui)
	local root = gui:FindFirstChild("Root")
	if root and root:IsA("CanvasGroup") then
		local TweenService = game:GetService("TweenService")
		local tween = TweenService:Create(root, TweenInfo.new(FADE), { GroupTransparency = 1 })
		tween.Completed:Once(function()
			gui:Destroy()
		end)
		tween:Play()
	else
		gui:Destroy()
	end
end

-- Whether teleport data is ours, and the map and levelshot it names
-- (checked again here: the arrival script can't reach the servers' check).
function LoadingScreen.fromData(data: any): (boolean, string?, string?)
	if type(data) ~= "table" or data.oa ~= 1 then
		return false, nil, nil
	end
	local map, shot = data.map, data.shot
	if type(map) ~= "string" or #map > 64 or not string.match(map, "^[%w_%-]+$") then
		map = nil
	end
	if type(shot) ~= "string" or #shot > 40 or not string.match(shot, "^rbxassetid://%d+$") then
		shot = nil
	end
	return true, map, shot
end

return LoadingScreen
