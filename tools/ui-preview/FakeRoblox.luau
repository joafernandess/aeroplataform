--[[
	FakeRoblox (Lune)
	Minimal pure-Luau stand-ins for client-side Roblox Instances and services, good enough to run the real
	client controllers and capture the GUI tree they build. Properties are stored as set; events are fake
	signals that can be fired from the preview script (e.g. to "click" a button).
]]

local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Fake = {}

-- Signals -------------------------------------------------------------------------------------------
function Fake.Signal()
	local signal = { _handlers = {} }
	function signal:Connect(fn)
		local connection = { Connected = true }
		function connection:Disconnect()
			connection.Connected = false
		end
		table.insert(self._handlers, { fn = fn, c = connection })
		return connection
	end
	function signal:Once(fn)
		local connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end
	function signal:Fire(...)
		for _, h in table.clone(self._handlers) do
			if h.c.Connected then
				task.spawn(h.fn, ...)
			end
		end
	end
	function signal:Wait()
		return coroutine.yield()
	end
	return signal
end

-- Class hierarchy (only what the game uses) ------------------------------------------------------------
local PARENTS = {
	GuiObject = { "GuiBase2d" },
	Frame = { "GuiObject" },
	ScrollingFrame = { "GuiObject" },
	TextLabel = { "GuiObject" },
	TextButton = { "GuiButton", "GuiObject" },
	ImageLabel = { "GuiObject" },
	ImageButton = { "GuiButton", "GuiObject" },
	ScreenGui = { "LayerCollector", "GuiBase2d" },
	BillboardGui = { "LayerCollector", "GuiBase2d" },
	UIListLayout = { "UIGridStyleLayout", "UILayout", "UIComponent" },
	UIGridLayout = { "UIGridStyleLayout", "UILayout", "UIComponent" },
	UIPadding = { "UIComponent" },
	UICorner = { "UIComponent" },
	UIStroke = { "UIComponent" },
	UISizeConstraint = { "UIConstraint", "UIComponent" },
	UIScale = { "UIComponent" },
	UIGradient = { "UIComponent" },
	Part = { "BasePart", "PVInstance" },
	SpawnLocation = { "Part", "BasePart", "PVInstance" },
	Model = { "PVInstance" },
}

local GUI_DEFAULTS = {
	Visible = true,
	BackgroundTransparency = 0,
	BackgroundColor3 = roblox.Color3.fromRGB(163, 162, 165),
	BorderSizePixel = 1,
	Size = roblox.UDim2.new(),
	Position = roblox.UDim2.new(),
	AnchorPoint = roblox.Vector2.new(0, 0),
	ZIndex = 1,
	LayoutOrder = 0,
	ClipsDescendants = false,
	AutomaticSize = roblox.Enum.AutomaticSize.None,
}
local TEXT_DEFAULTS = {
	Text = "Label",
	TextColor3 = roblox.Color3.new(0, 0, 0),
	TextSize = 14,
	Font = roblox.Enum.Font.Legacy,
	TextXAlignment = roblox.Enum.TextXAlignment.Center,
	TextYAlignment = roblox.Enum.TextYAlignment.Center,
	TextWrapped = false,
	TextScaled = false,
	TextTransparency = 0,
	TextStrokeTransparency = 1,
}
local DEFAULTS = {
	ScreenGui = { Enabled = true },
	UIListLayout = { FillDirection = roblox.Enum.FillDirection.Vertical, Padding = roblox.UDim.new(0, 0), HorizontalAlignment = roblox.Enum.HorizontalAlignment.Left, VerticalAlignment = roblox.Enum.VerticalAlignment.Top },
	UIGridLayout = { CellSize = roblox.UDim2.fromOffset(100, 100), CellPadding = roblox.UDim2.fromOffset(5, 5) },
	UIPadding = { PaddingTop = roblox.UDim.new(), PaddingBottom = roblox.UDim.new(), PaddingLeft = roblox.UDim.new(), PaddingRight = roblox.UDim.new() },
	UICorner = { CornerRadius = roblox.UDim.new(0, 8) },
	UIStroke = { Thickness = 1, Color = roblox.Color3.new(0, 0, 0), Transparency = 0 },
	ScrollingFrame = { ScrollBarThickness = 12 },
	UIScale = { Scale = 1 },
	UIGradient = { Rotation = 0 },
}

local EVENTS = {
	Activated = true,
	MouseButton1Click = true,
	ChildAdded = true,
	ChildRemoved = true,
	AncestryChanged = true,
	Changed = true,
	CharacterAdded = true,
	Completed = true,
	Triggered = true,
}

local counter = 0
local Methods = {}
local Meta = {}

function Fake.IsGui(inst): boolean
	return Methods.IsA(inst, "GuiObject")
end

function Fake.new(className: string)
	counter += 1
	local obj = setmetatable({}, Meta)
	rawset(obj, "__data", {
		ClassName = className,
		Name = className,
		Parent = nil,
		Children = {},
		Props = {},
		Attributes = {},
		Signals = {},
		AttrSignals = {},
		Order = counter,
		Destroyed = false,
	})
	return obj
end

local function data(obj)
	return rawget(obj, "__data")
end

local function defaultFor(className: string, key: string)
	local own = DEFAULTS[className]
	if own and own[key] ~= nil then
		return own[key]
	end
	local isGui = className == "Frame" or className == "ScrollingFrame" or className == "TextLabel" or className == "TextButton" or className == "ImageLabel" or className == "ImageButton"
	if isGui and GUI_DEFAULTS[key] ~= nil then
		return GUI_DEFAULTS[key]
	end
	if (className == "TextLabel" or className == "TextButton") and TEXT_DEFAULTS[key] ~= nil then
		return TEXT_DEFAULTS[key]
	end
	return nil
end

function Meta.__index(self, key)
	local d = data(self)
	if key == "ClassName" or key == "Name" or key == "Parent" then
		return d[key]
	end
	if Methods[key] then
		return Methods[key]
	end
	if EVENTS[key] then
		local s = d.Signals[key]
		if not s then
			s = Fake.Signal()
			d.Signals[key] = s
		end
		return s
	end
	local value = d.Props[key]
	if value ~= nil then
		return value
	end
	local default = defaultFor(d.ClassName, key)
	if default ~= nil then
		return default
	end
	for _, child in d.Children do
		if data(child).Name == key then
			return child
		end
	end
	return nil
end

function Meta.__newindex(self, key, value)
	local d = data(self)
	if key == "Parent" then
		local old = d.Parent
		if old == value then
			return
		end
		if old then
			local siblings = data(old).Children
			local index = table.find(siblings, self)
			if index then
				table.remove(siblings, index)
			end
		end
		d.Parent = value
		if value then
			table.insert(data(value).Children, self)
			local added = data(value).Signals.ChildAdded
			if added then
				added:Fire(self)
			end
		end
		return
	end
	if key == "Name" then
		d.Name = value
		return
	end
	d.Props[key] = value
end

function Meta.__tostring(self)
	return data(self).Name
end

function Methods.IsA(self, className)
	local own = data(self).ClassName
	if own == className or className == "Instance" then
		return true
	end
	return table.find(PARENTS[own] or {}, className) ~= nil
end

function Methods.GetChildren(self)
	return table.clone(data(self).Children)
end

function Methods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, child in data(node).Children do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function Methods.FindFirstChild(self, name)
	for _, child in data(self).Children do
		if data(child).Name == name then
			return child
		end
	end
	return nil
end

function Methods.WaitForChild(self, name)
	return Methods.FindFirstChild(self, name)
end

function Methods.FindFirstChildOfClass(self, className)
	for _, child in data(self).Children do
		if data(child).ClassName == className then
			return child
		end
	end
	return nil
end

function Methods.FindFirstChildWhichIsA(self, className)
	for _, child in data(self).Children do
		if Methods.IsA(child, className) then
			return child
		end
	end
	return nil
end

function Methods.Destroy(self)
	data(self).Destroyed = true
	self.Parent = nil
	for _, child in table.clone(data(self).Children) do
		Methods.Destroy(child)
	end
end

function Methods.ClearAllChildren(self)
	for _, child in table.clone(data(self).Children) do
		Methods.Destroy(child)
	end
end

function Methods.SetAttribute(self, name, value)
	data(self).Attributes[name] = value
end

function Methods.GetAttribute(self, name)
	return data(self).Attributes[name]
end

function Methods.GetAttributeChangedSignal(self, name)
	local d = data(self)
	d.AttrSignals[name] = d.AttrSignals[name] or Fake.Signal()
	return d.AttrSignals[name]
end

function Methods.GetPropertyChangedSignal(self, name)
	return Methods.GetAttributeChangedSignal(self, "__prop_" .. name)
end

-- Preview helper: set a property and fire its changed signal.
function Fake.SetProperty(inst, name, value)
	inst[name] = value
	local signal = data(inst).AttrSignals["__prop_" .. name]
	if signal then
		signal:Fire()
	end
end

function Methods.PivotTo(self, cframe)
	data(self).Props.__Pivot = cframe
end

function Methods.GetPivot(self)
	return data(self).Props.__Pivot or roblox.CFrame.new()
end

function Methods.Clone(self)
	local copy = Fake.new(data(self).ClassName)
	for k, v in data(self).Props do
		data(copy).Props[k] = v
	end
	data(copy).Name = data(self).Name
	return copy
end

function Fake.Data(obj)
	return data(obj)
end

-- Services ------------------------------------------------------------------------------------------------
function Fake.CreateClientServices(serverTime: () -> number)
	local playerGui = Fake.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	local localPlayer = Fake.new("Player")
	localPlayer.Name = "PreviewPlayer"
	localPlayer.UserId = 4242
	playerGui.Parent = localPlayer

	local workspace = Fake.new("Workspace")
	workspace.Name = "Workspace"
	local enemies = Fake.new("Folder")
	enemies.Name = "Enemies"
	enemies.Parent = workspace
	local camera = Fake.new("Camera")
	camera.Name = "Camera"
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
	camera.Parent = workspace
	workspace.CurrentCamera = camera
	rawset(workspace, "GetServerTimeNow", function()
		return serverTime()
	end)
	rawset(workspace, "Raycast", function()
		return nil
	end)

	local tweenService = {}
	function tweenService:Create(instance, _info, goals)
		local tween = { Completed = Fake.Signal() }
		function tween:Play()
			for k, v in goals do
				instance[k] = v
			end
			task.defer(function()
				tween.Completed:Fire(roblox.Enum.PlaybackState.Completed)
			end)
		end
		return tween
	end

	local services = {
		Players = { LocalPlayer = localPlayer, PlayerAdded = Fake.Signal(), PlayerRemoving = Fake.Signal(), GetPlayers = function()
			return { localPlayer }
		end },
		UserInputService = { InputBegan = Fake.Signal(), InputEnded = Fake.Signal(), TouchEnabled = false },
		TweenService = tweenService,
		RunService = {
			RenderStepped = Fake.Signal(),
			Heartbeat = Fake.Signal(),
			IsServer = function()
				return false
			end,
			IsClient = function()
				return true
			end,
			IsStudio = function()
				return true
			end,
		},
		Workspace = workspace,
		SoundService = Fake.new("SoundService"),
		ProximityPromptService = { PromptTriggered = Fake.Signal() },
		MarketplaceService = {
			PromptProductPurchase = function() end,
			PromptGamePassPurchase = function() end,
		},
	}
	return services, localPlayer, playerGui
end

Fake.TweenInfo = {
	new = function(...)
		return { ... }
	end,
}
Fake.RaycastParams = {
	new = function()
		return {}
	end,
}

return Fake
