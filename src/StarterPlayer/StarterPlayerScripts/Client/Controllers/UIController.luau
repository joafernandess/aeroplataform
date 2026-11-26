--[[
	UIController
	Owns the root ScreenGui, the two side menus (built from UI/Navigation) and the window registry.
	Only one window is open at a time; opening one pops it in (TweenService) over a dark scrim.

	  UI:CreateWindow(name, title, size?, onOpen?) -> window { Frame, Content, Title }
	  UI:Open(name, ...)  UI:Close(name?)  UI:Toggle(name)  UI:IsOpen(name)
	  UI:SetMenuBadge(name, count)           count badge on the menu button that opens window `name` (0 hides it)
	  UI:AddScaled(gui, "Window" | "Hud")   responsive UIScale (phones, tablets, small windows)

	Responsive scaling: the UI is designed for a 1280x720 screen. Every registered element gets a UIScale:
	  Window - shrinks just enough to fit the screen (never above 1)
	  Hud    - follows the screen size relative to 1280x720 (slightly boosted so text stays readable)
	UIScale keeps each element's anchor point fixed, so corner-anchored HUD blocks stay in their corners.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Signal = require(game:GetService("ReplicatedStorage").Shared.Modules.Signal)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local Navigation = require(Client.UI.Navigation)

local UIController = {
	Name = "UIController",
	Priority = 1,
}

UIController.Windows = {}
UIController.Current = nil :: string?
UIController.WindowChanged = Signal.new() -- (currentWindowName?)

local DESIGN_SIZE = Vector2.new(1280, 720)
local TOPBAR_INSET = 58 -- Roblox top bar height (ScreenGui.IgnoreGuiInset = false)
local HUD_BOOST = 1.2
local MIN_SCALE = 0.55 -- below this text becomes unreadable; windows scroll instead

UIController.Scaled = {} :: { { Gui: GuiObject, Kind: string, Scale: UIScale } }
UIController.MenuButtons = {} :: { [string]: GuiObject } -- window name -> nav tile (TextButton)
UIController.MenuBadges = {} :: { [string]: number } -- window name -> badge count (kept until its button exists)

local BADGE_SIZE = 24
local OPEN_TIME = 0.18

-- Icon shown in each window's header tile (icon names from UI/Icons).
local WINDOW_ICONS = {
	Fighters = "fighters",
	Summon = "summon",
	Worlds = "worlds",
	Quests = "quests",
	Shop = "shop",
	Upgrades = "upgrades",
	Raids = "raids",
	Settings = "settings",
	Items = "inventory",
	Codes = "codes",
	Teleport = "teleport",
	Mounts = "mounts",
	Achievements = "achievements",
	Stats = "stats",
	Index = "index",
	UpdateLog = "update",
}

function UIController:GetRoot(): ScreenGui
	return self.Root
end

function UIController:GetViewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else DESIGN_SIZE
end

function UIController:_scaleFor(gui: GuiObject, kind: string): number
	local viewport = self:GetViewportSize()
	local width, height = viewport.X, viewport.Y - TOPBAR_INSET
	if kind == "Window" then
		local size = gui.Size
		local w = size.X.Offset + size.X.Scale * width
		local h = size.Y.Offset + size.Y.Scale * height
		return math.clamp(math.min((width - 24) / math.max(w, 1), (height - 16) / math.max(h, 1)), MIN_SCALE, 1)
	end
	local ratio = math.min(width / DESIGN_SIZE.X, height / (DESIGN_SIZE.Y - TOPBAR_INSET))
	return math.clamp(ratio * HUD_BOOST, 0.55, 1)
end

function UIController:AddScaled(gui: GuiObject, kind: string)
	local scale = C.Create("UIScale", { Parent = gui })
	table.insert(self.Scaled, { Gui = gui, Kind = kind, Scale = scale })
	scale.Scale = self:_scaleFor(gui, kind)
	return scale
end

function UIController:RefreshScale()
	for _, entry in self.Scaled do
		if entry.Gui.Parent then
			entry.Scale.Scale = self:_scaleFor(entry.Gui, entry.Kind)
		end
	end
end

function UIController:CreateWindow(name: string, title: string, size: UDim2?, onOpen: ((...any) -> ())?)
	local window = C.Window(self.Root, title, size, WINDOW_ICONS[name])
	self:AddScaled(window.Frame, "Window")
	window.Name = name
	window.OnOpen = onOpen
	window.CloseButton.Activated:Connect(function()
		self:Close(name)
	end)
	self.Windows[name] = window
	return window
end

function UIController:IsOpen(name: string): boolean
	return self.Current == name
end

function UIController:Open(name: string, ...: any)
	local window = self.Windows[name]
	if not window then
		warn("[UIController] Unknown window " .. tostring(name))
		return
	end
	if self.Current and self.Current ~= name then
		self:Close(self.Current)
	end
	self.Current = name
	window.Frame.Visible = true
	self.Scrim.Visible = true
	self:_animateOpen(window)
	UIController.WindowChanged:Fire(name)
	if window.OnOpen then
		task.spawn(window.OnOpen, ...)
	end
end

-- Pop-in: the window's responsive UIScale grows from 86% to its target size and the scrim fades in.
function UIController:_animateOpen(window)
	for _, entry in self.Scaled do
		if entry.Gui == window.Frame then
			local target = self:_scaleFor(entry.Gui, entry.Kind)
			entry.Scale.Scale = target * 0.86
			TweenService:Create(entry.Scale, TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
			break
		end
	end
	self.Scrim.BackgroundTransparency = 1
	TweenService:Create(self.Scrim, TweenInfo.new(OPEN_TIME), { BackgroundTransparency = 0.55 }):Play()
end

function UIController:Close(name: string?)
	local target = name or self.Current
	if not target then
		return
	end
	local window = self.Windows[target]
	if window then
		window.Frame.Visible = false
		if window.OnClose then
			task.spawn(window.OnClose)
		end
	end
	if self.Current == target then
		self.Current = nil
		self.Scrim.Visible = false
		UIController.WindowChanged:Fire(nil)
	end
end

function UIController:Toggle(name: string, ...: any)
	if self:IsOpen(name) then
		self:Close(name)
	else
		self:Open(name, ...)
	end
end

-- Builds one side column from UI/Navigation entries. side = "Left" | "Right".
function UIController:_buildColumn(side: string, entries)
	local left = side == "Left"
	local count = #entries
	local height = count * Navigation.CellHeight + (count - 1) * Navigation.Gap
	local column = C.Frame(self.Root, {
		Name = side .. "Navigation",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(if left then 0 else 1, 0.5),
		Position = UDim2.new(if left then 0 else 1, if left then Navigation.Margin else -Navigation.Margin, Navigation.CenterY, 0),
		Size = UDim2.fromOffset(Navigation.ButtonSize + 22, height),
	})
	C.Create("UISizeConstraint", { MaxSize = Vector2.new(Navigation.ButtonSize + 22, height), Parent = column })
	local list = C.List(column, Enum.FillDirection.Vertical, Navigation.Gap, Enum.HorizontalAlignment.Center)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	for order, entry in entries do
		local container, button = C.NavButton(column, entry.Icon, entry.Label, entry.Accent, function()
			self:Toggle(entry.Window)
		end, Navigation.ButtonSize)
		container.Name = entry.Window
		container.Size = UDim2.fromOffset(Navigation.ButtonSize + 22, Navigation.CellHeight)
		container.LayoutOrder = order
		self.MenuButtons[entry.Window] = button
		self:_paintMenuBadge(entry.Window, false)
	end
	self:AddScaled(column, "Hud")
	return column
end

-- Notification badge (brief §5.2): cyan circle, ink border and ink count over the tile's top-right corner.
function UIController:_paintMenuBadge(name: string, pop: boolean)
	local button = self.MenuButtons[name]
	if not button then
		return
	end
	local count = self.MenuBadges[name] or 0
	local badge = button:FindFirstChild("Badge")
	if count <= 0 then
		if badge then
			badge.Visible = false
		end
		return
	end
	if not badge then
		local P = Theme.Colors
		badge = C.Frame(button, {
			Name = "Badge",
			BackgroundColor3 = P.Cyan,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE),
			ZIndex = 8,
		})
		C.Corner(badge, UDim.new(0.5, 0))
		C.Stroke(badge, P.Ink, Theme.Stroke.Badge)
		C.Create("UIScale", { Parent = badge })
		C.Label(badge, "", {
			Name = "Count",
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Bold,
			TextSize = 14,
			TextColor3 = P.Ink,
			ZIndex = 9,
		})
	end
	local text = if count > 99 then "99+" else tostring(count)
	badge.Count.Text = text
	badge.Size = UDim2.fromOffset(BADGE_SIZE + math.max(#text - 1, 0) * 7, BADGE_SIZE)
	badge.Visible = true
	if pop then
		-- Pop when the count goes up.
		local scale = badge:FindFirstChildOfClass("UIScale")
		scale.Scale = 1.4
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- Shows `count` on the menu button that opens `windowName` (0 hides the badge). Safe to call before the button
-- exists: the count is applied when the button is added.
function UIController:SetMenuBadge(windowName: string, count: number)
	count = math.max(0, math.floor(count))
	local previous = self.MenuBadges[windowName] or 0
	self.MenuBadges[windowName] = count
	self:_paintMenuBadge(windowName, count > previous)
end

function UIController:Init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Root = C.Create("ScreenGui", {
		Name = "AnimeFightersUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	-- Dark scrim behind the open window; clicking it closes the window.
	self.Scrim = C.Create("TextButton", {
		Name = "Scrim",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 5,
		Parent = self.Root,
	})
	self.Scrim.Activated:Connect(function()
		self:Close()
	end)
	-- Effects layer (popups that sit above windows, e.g. summon reveal)
	self.Overlay = C.Frame(self.Root, { Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50 })
	local _ = Theme
end

function UIController:Start()
	-- Side menus: main menus on the left, the player's management screens on the right (UI/Navigation).
	self.LeftNav = self:_buildColumn("Left", Navigation.Left)
	self.RightNav = self:_buildColumn("Right", Navigation.Right)
	-- Re-scale when the screen size changes (rotation, window resize, camera replaced).
	local cameraConnection = nil
	local function watchCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
		end
		local camera = Workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				self:RefreshScale()
			end)
		end
		self:RefreshScale()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local windowName = Navigation.Hotkeys[input.KeyCode]
		if windowName and self.Windows[windowName] then
			self:Toggle(windowName)
		end
	end)
end

return UIController
