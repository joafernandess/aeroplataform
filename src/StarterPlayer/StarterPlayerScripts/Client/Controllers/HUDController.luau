--[[
	HUDController
	Always-visible HUD:
	  top-left      currency pills (Gems has a "+" shortcut to the shop)
	  top-centre    world banner (hidden while a window is open)
	  top-right     Team Power, active boosts and events
	  bottom-centre level badge + XP bar
	  bottom-right  big round AUTO toggle
	The menu buttons (bottom-left) belong to UIController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Features = require(Shared.Config.Features)
local Worlds = require(Shared.Config.Worlds)
local Formulas = require(Shared.Modules.Formulas)
local UnitStats = require(Shared.Modules.UnitStats)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local HUDController = {
	Name = "HUDController",
	Priority = 10,
}

-- Estimated damage per second of the equipped team (client-side estimate for display only).
local function teamPower(data): number
	local total = 0
	for _, uid in data.EquippedUnits do
		local unit = data.Inventory.Units[uid]
		local stats = unit and UnitStats.Compute(unit)
		if stats then
			total += stats.Power
		end
	end
	return total * Formulas.UpgradeMultiplier("Damage", data.Upgrades.Damage or 0)
end

function HUDController:Init(controllers)
	local ui = controllers.UIController
	local root = ui:GetRoot()

	-- Currencies (top-left)
	local currencies = C.Frame(root, { Name = "Currencies", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(240, 176) })
	C.List(currencies, Enum.FillDirection.Vertical, 4)
	self.CurrencyPills = {}
	for i, currency in GameConfig.Economy.Currencies do
		if currency ~= "Yen" and not Features.PremiumCurrencies then
			continue -- base game: Yen only
		end
		local row = C.Frame(currencies, { BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 40), LayoutOrder = i })
		local pill = C.CurrencyPill(row, Theme.Icons[currency] or "?", Theme.Currency(currency), 190)
		self.CurrencyPills[currency] = pill
		if currency == "Gems" and Features.Shop then
			local _, plus = C.IconButton(row, "+", nil, Theme.Colors.Good, function()
				ui:Open("Shop")
			end, 30)
			plus.Parent.Position = UDim2.fromOffset(196, 5)
			plus.TextSize = 20
		end
	end

	-- World banner (top centre)
	local banner = C.Frame(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(320, 42), BackgroundColor3 = Theme.Colors.Header })
	C.Corner(banner, UDim.new(0, 12))
	C.Stroke(banner, Theme.Colors.Stroke, 3)
	C.Gloss(banner)
	self.WorldLabel = C.Label(banner, "", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Display, TextSize = 24 })
	C.Outline(self.WorldLabel, 2.5)
	self.Banner = banner

	-- Team power + boosts/events (top-right)
	local right = C.Frame(root, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), Size = UDim2.fromOffset(260, 160) })
	C.List(right, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right)
	local powerRow = C.Frame(right, { BackgroundTransparency = 1, Size = UDim2.fromOffset(230, 40), LayoutOrder = 1 })
	self.PowerPill = C.CurrencyPill(powerRow, Theme.Icons.Power, Theme.Colors.Bad, 230)
	self.BuffList = C.Frame(right, { BackgroundTransparency = 1, Size = UDim2.fromOffset(260, 100), LayoutOrder = 2 })
	C.List(self.BuffList, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right)

	-- Level badge + XP bar (bottom centre)
	local levelFrame = C.Frame(root, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(460, 52), Visible = Features.PlayerLevel })
	self.XPBar = C.ProgressBar(levelFrame, Theme.Colors.XP, { Position = UDim2.fromOffset(34, 16), Size = UDim2.new(1, -34, 0, 22) })
	local badge = C.Frame(levelFrame, { Size = UDim2.fromOffset(52, 52), BackgroundColor3 = Theme.Colors.XP, ZIndex = 4 })
	C.Corner(badge, UDim.new(0.5, 0))
	C.Stroke(badge, Theme.Colors.Stroke, 3)
	C.Gloss(badge)
	self.LevelLabel = C.Label(badge, "1", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Display, TextSize = 24, ZIndex = 5 })
	C.Outline(self.LevelLabel, 2)

	-- Big round AUTO toggle (bottom right)
	local autoContainer, autoButton = C.IconButton(root, Theme.Icons.Auto, "AUTO", Theme.Colors.Good, function()
		local data = State.Data
		if data then
			State.Request("UpdateSetting", "AutoAttack", not data.Settings.AutoAttack)
		end
	end, 84)
	autoContainer.AnchorPoint = Vector2.new(1, 1)
	autoContainer.Position = UDim2.new(1, -14, 1, -12)
	self.AutoButton = autoButton
	self.AutoCaption = autoContainer:FindFirstChildOfClass("TextLabel")

	-- The world banner sits where window headers go; hide it while a window is open.
	ui.WindowChanged:Connect(function(current)
		banner.Visible = current == nil
	end)
	-- Responsive scaling (phones/tablets): every HUD block keeps its anchor and shrinks with the screen.
	for _, gui in { currencies, banner, right, levelFrame, autoContainer } do
		ui:AddScaled(gui, "Hud")
	end
end

function HUDController:RenderBuffs()
	local data = State.Data
	if not data then
		return
	end
	C.Clear(self.BuffList)
	local now = math.floor(workspace:GetServerTimeNow())
	local function badge(text: string, color: Color3, order: number)
		local pill = C.Frame(self.BuffList, { Size = UDim2.fromOffset(200, 26), BackgroundColor3 = color, LayoutOrder = order })
		C.Corner(pill, UDim.new(0.5, 0))
		C.Stroke(pill, Theme.Colors.Stroke, 2)
		C.Gloss(pill)
		C.Title(pill, text, { Size = UDim2.fromScale(1, 1), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center }, 1.5)
	end
	local order = 0
	for stat, boost in data.ActiveBoosts or {} do
		local remaining = boost.ExpiresAt - now
		if remaining > 0 then
			order += 1
			badge(("x%g %s • %s"):format(boost.Multiplier, stat, NumberFormat.Duration(remaining)), Theme.Colors.Good, order)
		end
	end
	for _, event in State.ActiveEvents do
		order += 1
		badge("EVENT: " .. event.Name, Theme.Colors.Cta, order)
	end
end

function HUDController:Start()
	State.Observe({ "Currencies" }, function(data)
		for currency, pill in self.CurrencyPills do
			pill.Set(NumberFormat.Abbreviate(data.Currencies[currency] or 0))
		end
	end)
	State.Observe({ "Level", "Experience" }, function(data)
		local needed = Formulas.PlayerXPToNext(data.Level)
		self.LevelLabel.Text = tostring(data.Level)
		self.XPBar.Set(data.Experience / math.max(needed, 1), NumberFormat.Abbreviate(data.Experience) .. " / " .. NumberFormat.Abbreviate(needed) .. " XP")
	end)
	State.Observe({ "CurrentWorld" }, function(data)
		local world = Worlds.Get(data.CurrentWorld)
		self.WorldLabel.Text = if world then world.Name else ""
	end)
	State.Observe({ "EquippedUnits", "Inventory", "Upgrades" }, function(data)
		self.PowerPill.Set(NumberFormat.Abbreviate(teamPower(data)) .. " Power")
	end)
	State.Observe({ "Settings" }, function(data)
		local on = data.Settings.AutoAttack ~= false
		self.AutoButton.BackgroundColor3 = if on then Theme.Colors.Good else Theme.Colors.Button
		if self.AutoCaption then
			self.AutoCaption.Text = if on then "AUTO ON" else "AUTO OFF"
		end
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
