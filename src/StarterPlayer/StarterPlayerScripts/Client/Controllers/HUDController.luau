--[[
	HUDController
	Always-visible HUD: currencies, level/XP bar, current world, active boosts/events, auto-attack toggle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Worlds = require(Shared.Config.Worlds)
local Formulas = require(Shared.Modules.Formulas)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local HUDController = {
	Name = "HUDController",
	Priority = 10,
}

function HUDController:Init(controllers)
	local root = controllers.UIController:GetRoot()

	-- Currencies (top-left)
	local bar = C.Frame(root, { Name = "Currencies", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(560, 36) })
	C.List(bar, Enum.FillDirection.Horizontal, 8)
	self.CurrencyLabels = {}
	for i, currency in GameConfig.Economy.Currencies do
		local pill = C.Frame(bar, { Size = UDim2.fromOffset(130, 34), BackgroundColor3 = Theme.Colors.Panel, LayoutOrder = i })
		C.Corner(pill, UDim.new(0, 17))
		C.Stroke(pill, Theme.Currency(currency), 2)
		self.CurrencyLabels[currency] = C.Label(pill, currency .. ": 0", { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(10, 0), Font = Theme.Fonts.Bold, TextColor3 = Theme.Currency(currency), TextSize = 15 })
	end

	-- World name (top centre)
	self.WorldLabel = C.Label(root, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(320, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextStrokeTransparency = 0.5,
	})

	-- Level bar (bottom centre)
	local levelFrame = C.Frame(root, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(420, 40) })
	self.LevelLabel = C.Label(levelFrame, "Level 1", { Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Bold, TextStrokeTransparency = 0.5 })
	self.XPBar = C.ProgressBar(levelFrame, Theme.Colors.XP, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 16) })

	-- Boosts & events (top-right)
	self.BuffList = C.Frame(root, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 12), Size = UDim2.fromOffset(300, 80) })
	C.List(self.BuffList, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Right)

	-- Auto attack toggle (bottom right)
	self.AutoButton = C.Button(root, "Auto: ON", function()
		local data = State.Data
		if data then
			State.Request("UpdateSetting", "AutoAttack", not data.Settings.AutoAttack)
		end
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(130, 44) })
end

function HUDController:RenderBuffs()
	local data = State.Data
	if not data then
		return
	end
	C.Clear(self.BuffList)
	local now = os.time()
	for stat, boost in data.ActiveBoosts or {} do
		local remaining = boost.ExpiresAt - now
		if remaining > 0 then
			C.Label(self.BuffList, ("x%g %s  %s"):format(boost.Multiplier, stat, NumberFormat.Duration(remaining)), { TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Colors.Good, Font = Theme.Fonts.Bold, TextStrokeTransparency = 0.5, Size = UDim2.new(1, 0, 0, 18) })
		end
	end
	for _, event in State.ActiveEvents do
		C.Label(self.BuffList, "EVENT: " .. event.Name, { TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Colors.Accent, Font = Theme.Fonts.Bold, TextStrokeTransparency = 0.5, Size = UDim2.new(1, 0, 0, 18) })
	end
end

function HUDController:Start()
	State.Observe({ "Currencies" }, function(data)
		for currency, label in self.CurrencyLabels do
			label.Text = currency .. ": " .. NumberFormat.Abbreviate(data.Currencies[currency] or 0)
		end
	end)
	State.Observe({ "Level", "Experience" }, function(data)
		local needed = Formulas.PlayerXPToNext(data.Level)
		self.LevelLabel.Text = "Level " .. data.Level
		self.XPBar.Set(data.Experience / math.max(needed, 1), NumberFormat.Abbreviate(data.Experience) .. " / " .. NumberFormat.Abbreviate(needed))
	end)
	State.Observe({ "CurrentWorld" }, function(data)
		local world = Worlds.Get(data.CurrentWorld)
		self.WorldLabel.Text = if world then world.Name else ""
	end)
	State.Observe({ "Settings" }, function(data)
		local on = data.Settings.AutoAttack ~= false
		self.AutoButton.Text = if on then "Auto: ON" else "Auto: OFF"
		self.AutoButton.BackgroundColor3 = if on then Theme.Colors.Good else Theme.Colors.PanelLight
	end)
	State.Observe({ "ActiveBoosts" }, function()
		self:RenderBuffs()
	end)
	State.EventsChanged:Connect(function()
		self:RenderBuffs()
	end)
	-- Refresh countdowns
	task.spawn(function()
		while true do
			task.wait(1)
			self:RenderBuffs()
		end
	end)
end

return HUDController
