--[[
	UIController
	Owns the root ScreenGui, the left menu and the window registry. Only one window is open at a time.

	  UI:CreateWindow(name, title, size?, onOpen?) -> window { Frame, Content, Title }
	  UI:Open(name, ...)  UI:Close(name?)  UI:Toggle(name)  UI:IsOpen(name)
	  UI:AddMenuButton(name, label, order)
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
local Features = require(game:GetService("ReplicatedStorage").Shared.Config.Features)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)

local UIController = {
	Name = "UIController",
	Priority = 1,
}

UIController.Windows = {}
UIController.Current = nil :: string?
UIController.WindowChanged = Signal.new() -- (currentWindowName?)

local HOTKEY_FEATURE = { Quests = "Quests", Worlds = "MultipleWorlds", Shop = "Shop" }
local DESIGN_SIZE = Vector2.new(1280, 720)
local TOPBAR_INSET = 58 -- Roblox top bar height (ScreenGui.IgnoreGuiInset = false)
local HUD_BOOST = 1.2
local MIN_SCALE = 0.55 -- below this text becomes unreadable; windows scroll instead

UIController.Scaled = {} :: { { Gui: GuiObject, Kind: string, Scale: UIScale } }
UIController.MenuButtons = {} :: { [string]: GuiObject } -- window name -> menu button container
UIController.MenuBadges = {} :: { [string]: number } -- window name -> badge count (kept until its button exists)

local MENU_ICON_SIZE = 68
local BADGE_SIZE = 24

-- Glyph shown in each window's header tile.
local WINDOW_ICONS = {
	Inventory = Theme.Icons.Inventory,
	Summon = Theme.Icons.Summon,
	Worlds = Theme.Icons.Worlds,
	Quests = Theme.Icons.Quests,
	Shop = Theme.Icons.Shop,
	Upgrades = Theme.Icons.Upgrades,
	Raids = Theme.Icons.Raids,
	Settings = Theme.Icons.Settings,
}

local HOTKEYS = {
	[Enum.KeyCode.I] = "Inventory",
	[Enum.KeyCode.Q] = "Quests",
	[Enum.KeyCode.M] = "Worlds",
	[Enum.KeyCode.B] = "Shop",
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
	UIController.WindowChanged:Fire(name)
	if window.OnOpen then
		task.spawn(window.OnOpen, ...)
	end
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

function UIController:AddMenuButton(name: string, label: string, order: number)
	local container = C.IconButton(self.Menu, Theme.Icons[name] or "?", label, Theme.MenuKinds[name] or "Primary", function()
		self:Toggle(name)
	end, MENU_ICON_SIZE)
	container.LayoutOrder = order
	self.MenuButtons[name] = container
	self:_paintMenuBadge(name, false)
end

-- Notification badge (brief §5.2): cyan circle, ink border and ink count over the button's top-right corner.
function UIController:_paintMenuBadge(name: string, pop: boolean)
	local container = self.MenuButtons[name]
	if not container then
		return
	end
	local count = self.MenuBadges[name] or 0
	local badge = container:FindFirstChild("Badge")
	if count <= 0 then
		if badge then
			badge.Visible = false
		end
		return
	end
	if not badge then
		local P = Theme.Colors
		badge = C.Frame(container, {
			Name = "Badge",
			BackgroundColor3 = P.Cyan,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(0.5, MENU_ICON_SIZE / 2 + 6, 0, -6),
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
	self.Menu = C.Frame(self.Root, {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(178, 404),
	})
	C.Grid(self.Menu, UDim2.fromOffset(84, 94), 10)
	self:AddScaled(self.Menu, "Hud")
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
	-- { window, caption, feature switch (nil = always) }. In the base game the star is opened in the world.
	local order = {
		{ "Inventory", "Fighters", nil },
		{ "Summon", "Summon", "MultipleWorlds" },
		{ "Worlds", "Worlds", "MultipleWorlds" },
		{ "Quests", "Quests", "Quests" },
		{ "Shop", "Shop", "Shop" },
		{ "Upgrades", "Upgrades", "Upgrades" },
		{ "Raids", "Raids", "Raids" },
		{ "Settings", "Settings", nil },
	}
	local count = 0
	for i, entry in order do
		if self.Windows[entry[1]] and (entry[3] == nil or Features[entry[3]]) then
			self:AddMenuButton(entry[1], entry[2], i)
			count += 1
		end
	end
	-- Fit the menu to its rows so the 2-column grid grows upward from the bottom-left corner.
	local rows = math.max(1, math.ceil(count / 2))
	self.Menu.Size = UDim2.fromOffset(178, rows * 94 + (rows - 1) * 10)
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
		local windowName = HOTKEYS[input.KeyCode]
		local feature = windowName and HOTKEY_FEATURE[windowName]
		if windowName and self.Windows[windowName] and (feature == nil or Features[feature]) then
			self:Toggle(windowName)
		end
	end)
end

return UIController
