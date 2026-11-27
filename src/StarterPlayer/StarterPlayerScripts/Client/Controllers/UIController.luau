--[[
	UIController
	Owns the root ScreenGui, the two side menu grids (built from UI/Navigation) and the window registry.
	Only one window is open at a time (no duplicates: each window is created once by its controller). Opening one
	scales it up and fades it in over a dark scrim; closing scales it down and fades it out. Windows can be dragged
	by their title bar (kept on screen), Escape or the red X closes them, and the open window's menu button stays
	highlighted.

	  UI:CreateWindow(name, title, size?, onOpen?) -> window { Frame, Content, Title }
	  UI:Open(name, ...)  UI:Close(name?)  UI:Toggle(name)  UI:IsOpen(name)
	  UI:SetMenuBadge(name, count)           count badge on the menu button that opens window `name` (0 hides it)
	  UI:AddScaled(gui, "Window" | "Hud")   responsive UIScale (phones, tablets, small windows)

	Responsive scaling: the UI is designed for a 1280x720 screen. Every registered element gets a UIScale:
	  Window - shrinks just enough to fit the screen (never above 1)
	  Hud    - follows the screen size relative to 1280x720 (slightly boosted so text stays readable)
	UIScale keeps each element's anchor point fixed, so corner-anchored HUD blocks stay in their corners.

	Side menus (UI:LayoutNav) are laid out separately: each grid, together with the block docked above it
	(UI:AttachAboveNav — the player's Yen counter on the left), is centred at Navigation.CenterY but kept below the
	HUD blocks registered with UI:AvoidForNav(side, bottomFn) (the Update Log card on the right) and above the
	bottom edge; on short screens it shrinks further so it always fits. LayoutChanged fires
	after every re-layout.
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
UIController.LayoutChanged = Signal.new() -- side menus were re-laid out (screen size or HUD blocks changed)
UIController.NavAvoid = { Left = {}, Right = {} } :: { [string]: { () -> number } }
UIController.NavAttach = {} :: { [string]: { Gui: GuiObject, Height: () -> number } }

local DESIGN_SIZE = Vector2.new(1280, 720)
local TOPBAR_INSET = 58 -- Roblox top bar height (ScreenGui.IgnoreGuiInset = false)
local HUD_BOOST = 1.2
local MIN_SCALE = 0.55 -- below this text becomes unreadable; windows scroll instead
local NAV_EDGE = 10 -- gap between a side menu and whatever it must stay clear of
local NAV_MIN_SCALE = 0.42
local NAV_ATTACH_GAP = 12 -- between a block docked above a grid (player info) and the grid

UIController.Scaled = {} :: { { Gui: GuiObject, Kind: string, Scale: UIScale } }
UIController.MenuButtons = {} :: { [string]: GuiObject } -- window name -> nav tile (TextButton)
UIController.MenuBadges = {} :: { [string]: number } -- window name -> badge count (kept until its button exists)

local BADGE_SIZE = 24
local OPEN_TIME = 0.18
local CLOSE_TIME = 0.12
local DRAG_KEEP = 60 -- px of a dragged window that must stay on screen

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
	if self.LeftNav or self.RightNav then
		self:LayoutNav()
	end
end

-- Size of the root ScreenGui's area (the viewport below the Roblox top bar).
function UIController:GetRootSize(): Vector2
	local viewport = self:GetViewportSize()
	return Vector2.new(viewport.X, viewport.Y - TOPBAR_INSET)
end

-- Registers a HUD block a side menu must stay below; `bottom()` returns its bottom edge in root pixels.
function UIController:AvoidForNav(side: string, bottom: () -> number)
	table.insert(self.NavAvoid[side], bottom)
	if self.LeftNav or self.RightNav then
		self:LayoutNav()
	end
end

--[[
	Docks `gui` right above a side menu grid: same edge, same scale, moved with the grid as one block (the block is
	what LayoutNav centres and fits). `height()` returns the block's unscaled height (it may change, e.g. boosts).
]]
function UIController:AttachAboveNav(side: string, gui: GuiObject, height: () -> number)
	if not gui:FindFirstChild("NavScale") then
		C.Create("UIScale", { Name = "NavScale", Parent = gui })
	end
	self.NavAttach[side] = { Gui = gui, Height = height }
	if self.LeftNav or self.RightNav then
		self:LayoutNav()
	end
end

-- Places and scales both side menus (see the header).
function UIController:LayoutNav()
	local root = self:GetRootSize()
	for side, column in { Left = self.LeftNav, Right = self.RightNav } do
		local scale = column:FindFirstChild("NavScale")
		local height = column.Size.Y.Offset
		local minTop = NAV_EDGE
		for _, bottom in self.NavAvoid[side] do
			local ok, value = pcall(bottom)
			if ok and type(value) == "number" then
				minTop = math.max(minTop, value + NAV_EDGE)
			end
		end
		local maxBottom = root.Y - NAV_EDGE
		local attach = self.NavAttach[side]
		local extra = 0
		if attach then
			local ok, value = pcall(attach.Height)
			extra = (if ok and type(value) == "number" then value else 0) + NAV_ATTACH_GAP
		end
		local total = height + extra
		local s = math.max(math.min(self:_scaleFor(column, "Hud"), (maxBottom - minTop) / total), NAV_MIN_SCALE)
		local h = total * s
		local top = math.clamp(root.Y * Navigation.CenterY - h / 2, minTop, math.max(minTop, maxBottom - h))
		if attach then
			attach.Gui.AnchorPoint = Vector2.new(column.AnchorPoint.X, 0)
			attach.Gui.Position = UDim2.new(column.Position.X.Scale, column.Position.X.Offset, 0, top)
			attach.Gui.NavScale.Scale = s
			top += extra * s
		end
		scale.Scale = s
		column.Position = UDim2.new(column.Position.X.Scale, column.Position.X.Offset, 0, top + height * s / 2)
	end
	self.LayoutChanged:Fire()
end

function UIController:CreateWindow(name: string, title: string, size: UDim2?, onOpen: ((...any) -> ())?)
	local window = C.Window(self.Root, title, size, WINDOW_ICONS[name])
	self:AddScaled(window.Frame, "Window")
	self:_makeDraggable(window)
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
	window.Closing = nil -- cancels a close animation still running
	window.Frame.Visible = true
	window.Frame.Position = self:_clampWindow(window.Frame, window.Frame.Position)
	self.Scrim.Visible = true
	self:_animateOpen(window)
	local button = self.MenuButtons[name]
	if button then
		C.SetNavSelected(button, true)
	end
	UIController.WindowChanged:Fire(name)
	if window.OnOpen then
		task.spawn(window.OnOpen, ...)
	end
end

-- Pop-in: the window's responsive UIScale grows from 86% to its target size and the scrim fades in.
-- The window's responsive UIScale entry (and the scale it should rest at).
function UIController:_scaleEntry(window): (any, number)
	for _, entry in self.Scaled do
		if entry.Gui == window.Frame then
			return entry, self:_scaleFor(entry.Gui, entry.Kind)
		end
	end
	return nil, 1
end

-- Open: slight scale-up from 88% with a fade-in of the whole window (CanvasGroup) and the dark scrim.
function UIController:_animateOpen(window)
	local entry, target = self:_scaleEntry(window)
	if entry then
		entry.Scale.Scale = target * 0.88
		TweenService:Create(entry.Scale, TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
	local outline = window.Frame:FindFirstChildOfClass("UIStroke")
	if window.Group then
		window.Group.GroupTransparency = 1
		TweenService:Create(window.Group, TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
	end
	if outline then
		outline.Transparency = 1
		TweenService:Create(outline, TweenInfo.new(OPEN_TIME), { Transparency = 0 }):Play()
	end
	self.Scrim.BackgroundTransparency = 1
	TweenService:Create(self.Scrim, TweenInfo.new(OPEN_TIME), { BackgroundTransparency = 0.55 }):Play()
end

-- Close: slight scale-down with a fade-out, then hide (unless it was reopened meanwhile).
function UIController:_animateClose(window, hideScrim: boolean)
	local token = {}
	window.Closing = token
	local entry, target = self:_scaleEntry(window)
	local info = TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if entry then
		TweenService:Create(entry.Scale, info, { Scale = target * 0.92 }):Play()
	end
	local outline = window.Frame:FindFirstChildOfClass("UIStroke")
	if outline then
		TweenService:Create(outline, info, { Transparency = 1 }):Play()
	end
	if hideScrim then
		TweenService:Create(self.Scrim, info, { BackgroundTransparency = 1 }):Play()
	end
	local function finish()
		if window.Closing ~= token then
			return -- reopened while closing
		end
		window.Closing = nil
		window.Frame.Visible = false
		if entry then
			entry.Scale.Scale = target
		end
		if hideScrim and self.Current == nil then
			self.Scrim.Visible = false
		end
	end
	if window.Group then
		local fade = TweenService:Create(window.Group, info, { GroupTransparency = 1 })
		fade.Completed:Connect(finish)
		fade:Play()
	else
		finish()
	end
end

-- Keeps a (dragged) window reachable: its header stays on screen and at least DRAG_KEEP px of it are visible.
function UIController:_clampWindow(frame: GuiObject, position: UDim2): UDim2
	local root = self:GetRootSize()
	local scale = frame:FindFirstChildOfClass("UIScale")
	local s = if scale then scale.Scale else 1
	local w, h = frame.Size.X.Offset * s, frame.Size.Y.Offset * s
	local cx = root.X * position.X.Scale + position.X.Offset
	local cy = root.Y * position.Y.Scale + position.Y.Offset
	cx = math.clamp(cx, DRAG_KEEP - w / 2, root.X - DRAG_KEEP + w / 2)
	cy = math.clamp(cy, h / 2, math.max(h / 2, root.Y - DRAG_KEEP + h / 2))
	return UDim2.new(position.X.Scale, cx - root.X * position.X.Scale, position.Y.Scale, cy - root.Y * position.Y.Scale)
end

-- Drag a window by its title bar (mouse or touch).
function UIController:_makeDraggable(window)
	local frame = window.Frame
	local dragging, startPoint, startPosition = nil, nil, nil
	window.Header.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = input
			startPoint = input.Position
			startPosition = frame.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement or (kind == Enum.UserInputType.Touch and input == dragging) then
			local delta = input.Position - startPoint
			frame.Position = self:_clampWindow(frame, startPosition + UDim2.fromOffset(delta.X, delta.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = nil
		end
	end)
end

function UIController:Close(name: string?)
	local target = name or self.Current
	if not target then
		return
	end
	local window = self.Windows[target]
	local wasCurrent = self.Current == target
	if wasCurrent then
		self.Current = nil
	end
	if window then
		self:_animateClose(window, wasCurrent)
		if window.OnClose then
			task.spawn(window.OnClose)
		end
	end
	local button = self.MenuButtons[target]
	if button then
		C.SetNavSelected(button, false)
	end
	if wasCurrent then
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
-- One side menu: square buttons in rows of Navigation.PerRow, Wide buttons on a row of their own; pushed against
-- its screen edge (a short row hugs the edge).
function UIController:_buildColumn(side: string, entries)
	local left = side == "Left"
	local perRow, d, gap = Navigation.PerRow, Navigation.ButtonSize, Navigation.Gap
	local width = perRow * d + (perRow - 1) * gap
	local rows, current = {}, nil
	for _, entry in entries do
		if entry.Wide then
			table.insert(rows, { entry })
			current = nil
		else
			if not current or #current >= perRow then
				current = {}
				table.insert(rows, current)
			end
			table.insert(current, entry)
		end
	end
	local height = 0
	for r, row in rows do
		height += (if row[1].Wide then Navigation.WideHeight else d) + (if r > 1 then gap else 0)
	end
	local grid = C.Frame(self.Root, {
		Name = side .. "Navigation",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(if left then 0 else 1, 0.5),
		Position = UDim2.new(if left then 0 else 1, if left then Navigation.Margin else -Navigation.Margin, Navigation.CenterY, 0),
		Size = UDim2.fromOffset(width, height),
	})
	C.Create("UISizeConstraint", { MaxSize = Vector2.new(width, height), Parent = grid })
	C.List(grid, Enum.FillDirection.Vertical, gap)
	local showKeys = Navigation.ShowKeys and UserInputService.KeyboardEnabled == true
	local order = 0
	for r, rowEntries in rows do
		local wide = rowEntries[1].Wide == true
		local rowHeight = if wide then Navigation.WideHeight else d
		local row = C.Frame(grid, { Name = "Row" .. r, BackgroundTransparency = 1, Size = UDim2.fromOffset(width, rowHeight), LayoutOrder = r })
		C.List(row, Enum.FillDirection.Horizontal, gap, if left then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right)
		for _, entry in rowEntries do
			order += 1
			local container, button = C.NavButton(row, {
				Icon = entry.Icon,
				Label = entry.Label,
				Key = entry.Key and entry.Key.Name,
				Wide = wide,
				Width = if wide then width else d,
				Height = rowHeight,
				ShowLabel = Navigation.ShowLabels,
				ShowKey = showKeys,
			}, function()
				self:Toggle(entry.Window)
			end)
			container.Name = entry.Window
			container.LayoutOrder = order
			self.MenuButtons[entry.Window] = button
			self:_paintMenuBadge(entry.Window, false)
		end
	end
	C.Create("UIScale", { Name = "NavScale", Parent = grid }) -- driven by LayoutNav
	return grid
end

-- Notification badge: red circle, ink border and white count over the tile's top-right corner; pulses gently.
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
			BackgroundColor3 = Theme.Colors.Alert, -- red count badge with an ink rim
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 4, 0, 2), -- top-right corner, clear of the next button's key badge
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
			TextColor3 = P.White,
			ZIndex = 9,
		})
		C.Outline(badge.Count, 1.5)
		-- Gentle colour pulse while it is shown.
		TweenService:Create(badge, TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			BackgroundColor3 = Theme.Colors.Alert:Lerp(P.White, 0.3),
		}):Play()
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
		-- Escape closes the open window (checked first: Roblox may also mark it as processed).
		if input.KeyCode == Enum.KeyCode.Escape and self.Current then
			self:Close()
			return
		end
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
