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
	local P = Theme.Colors

	-- Currencies (top-left column)
	local currencies = C.Frame(root, { Name = "Currencies", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(220, 200) })
	C.List(currencies, Enum.FillDirection.Vertical, 8)
	self.CurrencyPills = {}
	for i, currency in GameConfig.Economy.Currencies do
		if currency ~= "Yen" and not Features.PremiumCurrencies then
			continue -- base game: Yen only
		end
		local pill = C.CurrencyPill(currencies, Theme.Icons[currency] or "?", Theme.Currency(currency), 200, {
			GlyphColor = Theme.CurrencyGlyphColor[currency],
			Plus = if currency == "Gems" and Features.Shop
				then function()
					ui:Open("Shop")
				end
				else nil,
		})
		pill.Frame.LayoutOrder = i
		self.CurrencyPills[currency] = pill
	end

	-- World banner (top centre): straight blue plate with speed-lines and the cyan energy line.
	local banner = C.Frame(root, {
		Name = "WorldBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(340, 48),
		BackgroundColor3 = P.White,
		ClipsDescendants = true,
	})
	C.Corner(banner, Theme.Radius.Header)
	C.Stroke(banner, P.Ink, Theme.Stroke.Button)
	C.Gradient(banner, Theme.Gradients.WindowHeader.Top, Theme.Gradients.WindowHeader.Bottom)
	C.SpeedLines(banner, 5, { Start = 0.72, Spacing = 24, Length = 90 })
	C.Frame(banner, { BackgroundColor3 = P.Cyan, Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3), ZIndex = 3 })
	self.WorldLabel = C.Label(banner, "", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Display, TextSize = 26, ZIndex = 4 })
	C.Outline(self.WorldLabel, 3)
	self.Banner = banner

	-- Team power + boosts/events (top-right)
	local right = C.Frame(root, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 10), Size = UDim2.fromOffset(260, 170) })
	C.List(right, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
	self.PowerPill = C.CurrencyPill(right, Theme.Icons.Power, P.Ink, 240, { GlyphColor = P.Cyan, Height = 40 })
	self.PowerPill.Frame.LayoutOrder = 1
	self.BuffList = C.Frame(right, { BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 100), LayoutOrder = 2 })
	C.List(self.BuffList, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right)

	-- Level badge + XP bar (bottom centre)
	local levelFrame = C.Frame(root, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(460, 52), Visible = Features.PlayerLevel })
	self.XPBar = C.ProgressBar(levelFrame, nil, { Position = UDim2.fromOffset(34, 17), Size = UDim2.new(1, -34, 0, 20) })
	local badge = C.Frame(levelFrame, { Size = UDim2.fromOffset(52, 52), BackgroundColor3 = P.White, ZIndex = 4 })
	C.Corner(badge, UDim.new(0.5, 0))
	C.Stroke(badge, P.Ink, Theme.Stroke.Button)
	C.Gradient(badge, Theme.Gradients.Primary.Top, Theme.Gradients.Primary.Bottom)
	self.LevelLabel = C.Label(badge, "1", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Display, TextSize = 24, ZIndex = 5 })
	C.Outline(self.LevelLabel, 2.5)

	-- AUTO toggle (right side, kept clear of the mobile jump button in the bottom-right corner)
	local autoContainer, autoButton = C.IconButton(root, Theme.Icons.Auto, "AUTO", "Primary", function()
		local data = State.Data
		if data then
			State.Request("UpdateSetting", "AutoAttack", not data.Settings.AutoAttack)
		end
	end, 72)
	autoContainer.AnchorPoint = Vector2.new(1, 0.5)
	autoContainer.Position = UDim2.new(1, -16, 0.62, 0)
	self.AutoButton = autoButton
	self.AutoCaption = autoContainer:FindFirstChild("Caption")

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
	local P = Theme.Colors
	local now = math.floor(workspace:GetServerTimeNow())
	local function badge(text: string, accent: Color3, order: number)
		local pill = C.Frame(self.BuffList, { Size = UDim2.fromOffset(220, 30), BackgroundColor3 = P.Panel, BackgroundTransparency = 0.1, LayoutOrder = order })
		C.Corner(pill, UDim.new(0.5, 0))
		C.Stroke(pill, P.Ink, 2.5)
		local bar = C.Frame(pill, { BackgroundColor3 = accent, Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(6, 16), ZIndex = 2 })
		C.Corner(bar, UDim.new(0.5, 0))
		C.Title(pill, text, { Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 15, ZIndex = 2 }, 2)
	end
	local order = 0
	for stat, boost in data.ActiveBoosts or {} do
		local remaining = boost.ExpiresAt - now
		if remaining > 0 then
			order += 1
			badge(("x%g %s • %s"):format(boost.Multiplier, stat, NumberFormat.Duration(remaining)), P.Cyan, order)
		end
	end
	for _, event in State.ActiveEvents do
		order += 1
		badge("EVENT: " .. event.Name, P.Blue500, order)
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
		C.SetKind(self.AutoButton, if on then "Primary" else "Dark")
		C.SetSelected(self.AutoButton, on)
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
