--[[
	HUDController
	Always-visible HUD:
	  top-left      currency pills (Gems has a "+" shortcut to the shop) + "≈ X ¥/min" under the Yen pill
	  top-centre    kept clear (zone pill / target panel and toasts live there)
	  top-right     Team Power, active boosts and events, then the session stats panel (SessionStatsController)
	  bottom-centre level badge + XP bar
	  right-centre  big round AUTO toggle (icon spins while auto-attack is on, ON/OFF status pill under it)
	The menu buttons (bottom-left) belong to UIController.

	Reward feedback ("juice", docs/ui/UI_RESEARCH.md §2.5 / §5.3): when a currency or the team power goes up, the
	pill pops (UIScale on the pill itself, not on the scaled column), its number counts up in ~0.4s and a floating
	"+X" ticker rises next to it and fades. Gains that arrive while a ticker is still showing merge into it.
	Decreases (spending, unequipping) only count down: no pop, no ticker.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Features = require(Shared.Config.Features)
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

local COUNT_TIME = 0.4 -- number count-up
local BUMP_SCALE = 1.12
local TICKER_RISE_TIME = 0.6
local TICKER_HOLD = 0.75 -- a ticker stays fully visible this long after its last (merged) gain
local TICKER_FADE = 0.3
local AUTO_SPIN_SPEED = 90 -- degrees per second while auto-attack is on

local PILL_HEIGHT = 44 -- C.CurrencyPill container height (40px bar + 4)
local RATE_HEIGHT = 20
local TOOLS_WIDTH = 84 -- slot for small tool buttons left of the Power pill

local function tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goals)
	t:Play()
	return t
end

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
	return math.floor(total * Formulas.UpgradeMultiplier("Damage", data.Upgrades.Damage or 0))
end

local function whole(value: number): number
	return math.floor(value + 0.5)
end

-- Quick pop of a pill: scale up, then settle back (two tweens so a cancelled pop never leaves it enlarged).
local function bump(scale: UIScale)
	local up = TweenService:Create(scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = BUMP_SCALE })
	up.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			tween(scale, 0.14, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
	up:Play()
end

--[[
	Wraps a C.CurrencyPill so it can count up, pop and show "+X" tickers.
	options: { Holder, Format(n) -> text, TickerText(n) -> text, TickerAnchor, TickerFrom, TickerTo, TickerAlign }
]]
local function animated(pill, options)
	local entry = table.clone(options)
	entry.Pill = pill
	entry.Scale = C.Create("UIScale", { Name = "Bump", Parent = pill.Frame })
	entry.Value = C.Create("NumberValue", { Name = "Counter" }) -- tweened; Target / Ticker are filled in later
	entry.Value.Changed:Connect(function(value)
		pill.Set(entry.Format(value))
	end)
	return entry
end

function HUDController:Init(controllers)
	self.Controllers = controllers
	local ui = controllers.UIController
	local root = ui:GetRoot()
	local P = Theme.Colors

	-- Currencies (top-left column). Each pill sits in a fixed-size row so its pop never shifts the column.
	local currencies = C.Frame(root, { Name = "Currencies", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(220, 200) })
	C.List(currencies, Enum.FillDirection.Vertical, 8)
	self.CurrencyPills = {}
	self.Animated = {}
	for i, currency in GameConfig.Economy.Currencies do
		if currency ~= "Yen" and not Features.PremiumCurrencies then
			continue -- base game: Yen only
		end
		local isYen = currency == "Yen"
		local row = C.Frame(currencies, {
			Name = currency .. "Row",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(200, PILL_HEIGHT + (if isYen then RATE_HEIGHT + 2 else 0)),
			LayoutOrder = i,
		})
		local pill = C.CurrencyPill(row, Theme.Icons[currency] or "?", Theme.Currency(currency), 200, {
			GlyphColor = Theme.CurrencyGlyphColor[currency],
			Plus = if currency == "Gems" and Features.Shop
				then function()
					ui:Open("Shop")
				end
				else nil,
		})
		-- Pop from the badge side (UIScale keeps the AnchorPoint fixed).
		pill.Frame.AnchorPoint = Vector2.new(0, 0.5)
		pill.Frame.Position = UDim2.fromOffset(0, PILL_HEIGHT / 2)
		self.CurrencyPills[currency] = pill
		local glyph = Theme.Icons[currency] or ""
		self.Animated[currency] = animated(pill, {
			Holder = row,
			Format = function(value: number): string
				return NumberFormat.Abbreviate(whole(value))
			end,
			TickerText = function(amount: number): string
				return "+" .. NumberFormat.Abbreviate(amount) .. " " .. glyph
			end,
			TickerAnchor = Vector2.new(0, 0.5),
			TickerFrom = UDim2.fromOffset(208, PILL_HEIGHT / 2 + 10),
			TickerTo = UDim2.fromOffset(208, PILL_HEIGHT / 2 - 3),
			TickerAlign = Enum.TextXAlignment.Left,
		})
		if isYen then
			-- Income caption: small dark pill tucked under the Yen pill, aligned with its number.
			local ratePill = C.Frame(row, {
				Name = "YenPerMinute",
				BackgroundColor3 = P.Panel,
				BackgroundTransparency = 0.15,
				Position = UDim2.fromOffset(46, PILL_HEIGHT + 1),
				Size = UDim2.fromOffset(124, RATE_HEIGHT),
			})
			C.Corner(ratePill, UDim.new(0.5, 0))
			C.Stroke(ratePill, P.Ink, 2)
			self.RateLabel = C.Title(ratePill, "≈ 0 " .. glyph .. "/min", {
				Name = "Rate",
				Font = Theme.Fonts.Number,
				Size = UDim2.fromScale(1, 1),
				TextSize = 14,
				TextColor3 = P.Ice,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 2,
			}, 1.5)
		end
	end

	--[[
		Top-right column (LayoutOrder): 1 Power row = [tool slot][Power pill] · 2 boosts/events · 3 session stats panel.
		Small HUD tool buttons (the session stats toggle) go in `RightTools`, left of the Power pill, so they cost no
		vertical space: on a phone the column must stay clear of the AUTO button.
	]]
	local right = C.Frame(root, { Name = "RightColumn", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 10), Size = UDim2.fromOffset(TOOLS_WIDTH + 8 + 240, 360) })
	C.List(right, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
	self.RightColumn = right
	local powerRow = C.Frame(right, { Name = "PowerRow", BackgroundTransparency = 1, Size = UDim2.fromOffset(TOOLS_WIDTH + 8 + 240, PILL_HEIGHT), LayoutOrder = 1 })
	self.PowerPill = C.CurrencyPill(powerRow, Theme.Icons.Power, P.Ink, 240, { GlyphColor = P.Cyan, Height = 40 })
	self.PowerPill.Frame.AnchorPoint = Vector2.new(1, 0.5)
	self.PowerPill.Frame.Position = UDim2.new(1, 0, 0, PILL_HEIGHT / 2)
	self.RightTools = C.Frame(powerRow, { Name = "Tools", BackgroundTransparency = 1, Size = UDim2.fromOffset(TOOLS_WIDTH, PILL_HEIGHT) })
	C.List(self.RightTools, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
	self.Animated.Power = animated(self.PowerPill, {
		Holder = powerRow,
		Format = function(value: number): string
			return NumberFormat.Abbreviate(whole(value)) .. " Power"
		end,
		TickerText = function(amount: number): string
			return "+" .. NumberFormat.Abbreviate(amount)
		end,
		-- Left of the tool slot (outward from the screen edge, like the Yen ticker).
		TickerAnchor = Vector2.new(1, 0.5),
		TickerFrom = UDim2.fromOffset(-6, PILL_HEIGHT / 2 + 10),
		TickerTo = UDim2.fromOffset(-6, PILL_HEIGHT / 2 - 3),
		TickerAlign = Enum.TextXAlignment.Right,
	})
	self.BuffList = C.Frame(right, { Name = "Boosts", BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Visible = false })
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
	local autoContainer, autoButton = C.IconButton(root, Theme.Icons.Auto, nil, "Primary", function()
		local data = State.Data
		if data then
			State.Request("UpdateSetting", "AutoAttack", not data.Settings.AutoAttack)
		end
	end, 72)
	autoContainer.Name = "Auto"
	autoContainer.AnchorPoint = Vector2.new(1, 0.5)
	autoContainer.Position = UDim2.new(1, -16, 0.62, 0)
	autoContainer.Size = UDim2.fromOffset(88, 76 + 26)
	self.AutoButton = autoButton
	-- Status pill under the button: cyan "AUTO ON" / inverted black "AUTO OFF" (never colour alone: the text says it).
	local status = C.Frame(autoContainer, { Name = "AutoStatus", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(88, 22), BackgroundColor3 = P.Cyan, ZIndex = 4 })
	C.Corner(status, UDim.new(0.5, 0))
	self.AutoStatusStroke = C.Stroke(status, P.Ink, 2.5)
	self.AutoStatus = status
	self.AutoCaption = C.Label(status, "AUTO ON", { Name = "Caption", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Title, TextSize = 14, TextColor3 = P.Ink, ZIndex = 5 })

	-- Responsive scaling (phones/tablets): every HUD block keeps its anchor and shrinks with the screen.
	for _, gui in { currencies, right, levelFrame, autoContainer } do
		ui:AddScaled(gui, "Hud")
	end
end

-- Reward feedback ------------------------------------------------------------------------------------------------

-- Floating "+X" next to a pill; a gain that arrives while the ticker is still fully visible merges into it.
function HUDController:_ticker(entry, amount: number)
	local ticker = entry.Ticker
	if not (ticker and ticker.Label.Parent and not ticker.Fading) then
		local label = C.Number(entry.Holder, "", {
			Name = "Ticker",
			AnchorPoint = entry.TickerAnchor,
			Position = entry.TickerFrom,
			Size = UDim2.fromOffset(140, 26),
			TextSize = 22,
			TextColor3 = Theme.Colors.Cyan,
			TextXAlignment = entry.TickerAlign,
			ZIndex = 6,
		})
		ticker = {
			Label = label,
			Stroke = label:FindFirstChildOfClass("UIStroke"),
			Scale = C.Create("UIScale", { Parent = label }),
			Amount = 0,
			Version = 0,
			Fading = false,
		}
		entry.Ticker = ticker
	end
	ticker.Amount += amount
	ticker.Version += 1
	local version = ticker.Version
	local label = ticker.Label
	label.Text = entry.TickerText(ticker.Amount)
	-- (Re)start: pop in and rise from just below the pill's centre line.
	label.Position = entry.TickerFrom
	tween(label, TICKER_RISE_TIME, { Position = entry.TickerTo })
	ticker.Scale.Scale = 0.6
	tween(ticker.Scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(TICKER_HOLD, function()
		if ticker.Version ~= version or not label.Parent then
			return -- merged with a newer gain, which restarted the timer
		end
		ticker.Fading = true
		if ticker.Stroke then
			tween(ticker.Stroke, TICKER_FADE, { Transparency = 1 })
		end
		local fade = tween(label, TICKER_FADE, { TextTransparency = 1 })
		fade.Completed:Connect(function()
			label:Destroy()
		end)
	end)
	return ticker
end

-- Shows `target` on an animated pill. The first value (and `instant`) snaps; later ones count, and gains pop.
function HUDController:SetAnimated(entry, target: number, instant: boolean?)
	local previous = entry.Target
	entry.Target = target
	if previous == nil or instant then
		entry.Value.Value = target
		entry.Pill.Set(entry.Format(target))
		return
	end
	local delta = target - previous
	if delta == 0 then
		return
	end
	local count = tween(entry.Value, COUNT_TIME, { Value = target })
	count.Completed:Connect(function()
		if entry.Target == target then
			entry.Pill.Set(entry.Format(target)) -- exact final text
		end
	end)
	local gain = math.floor(delta)
	if gain >= 1 then
		bump(entry.Scale)
		self:_ticker(entry, gain)
	end
end

function HUDController:RefreshRate()
	local stats = self.Controllers and self.Controllers.SessionStatsController
	if not (self.RateLabel and stats and stats.YenPerMinute) then
		return
	end
	local rate = math.floor(stats:YenPerMinute())
	self.RateLabel.Text = "≈ " .. NumberFormat.Abbreviate(rate, 1) .. " " .. Theme.Icons.Yen .. "/min"
end

-- AUTO button ---------------------------------------------------------------------------------------------------

-- The object that holds the AUTO glyph: an explicit "Icon" holder or image if the button has one, else its label.
function HUDController:_autoIcon(): GuiObject?
	local cached = self.AutoIcon
	if cached and cached.Parent then
		return cached
	end
	local button = self.AutoButton
	if not button then
		return nil
	end
	local descendants = button:GetDescendants()
	local found = nil
	for _, d in descendants do
		if d.Name == "Icon" and d:IsA("GuiObject") then
			found = d
			break
		end
	end
	if not found then
		for _, d in descendants do
			if d:IsA("ImageLabel") then
				found = d
				break
			end
		end
	end
	if not found then
		for _, d in descendants do
			if d:IsA("TextLabel") and (d.Text == Theme.Icons.Auto or d.Name == "Label") then
				found = d
				break
			end
		end
	end
	self.AutoIcon = found
	return found
end

function HUDController:SetAutoState(on: boolean)
	local P = Theme.Colors
	self.AutoOn = on
	C.SetKind(self.AutoButton, if on then "Primary" else "Dark")
	C.SetSelected(self.AutoButton, on)
	self.AutoCaption.Text = if on then "AUTO ON" else "AUTO OFF"
	self.AutoCaption.TextColor3 = if on then P.Ink else P.White
	self.AutoStatus.BackgroundColor3 = if on then P.Cyan else P.Ink
	self.AutoStatusStroke.Color = if on then P.Ink else P.White
	self.AutoStatusStroke.Thickness = if on then 2.5 else 2
	if not on then
		local icon = self:_autoIcon()
		if icon then
			icon.Rotation = 0
		end
	end
end

-- Per frame: spin the AUTO icon while auto-attack is on.
function HUDController:Step(dt: number)
	if not self.AutoOn then
		return
	end
	local icon = self:_autoIcon()
	if icon then
		icon.Rotation = ((icon.Rotation or 0) + dt * AUTO_SPIN_SPEED) % 360
	end
end

-- Boosts / events --------------------------------------------------------------------------------------------------

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
	-- Collapse the empty list so the stats panel sits right under the Power pill.
	self.BuffList.Visible = order > 0
end

function HUDController:Start()
	State.Observe({ "Currencies" }, function(data)
		for currency, entry in self.Animated do
			if currency ~= "Power" then
				self:SetAnimated(entry, data.Currencies[currency] or 0)
			end
		end
	end)
	State.Observe({ "Level", "Experience" }, function(data)
		local needed = Formulas.PlayerXPToNext(data.Level)
		self.LevelLabel.Text = tostring(data.Level)
		self.XPBar.Set(data.Experience / math.max(needed, 1), NumberFormat.Abbreviate(data.Experience) .. " / " .. NumberFormat.Abbreviate(needed) .. " XP")
	end)
	State.Observe({ "EquippedUnits", "Inventory", "Upgrades" }, function(data)
		self:SetAnimated(self.Animated.Power, teamPower(data))
	end)
	State.Observe({ "Settings" }, function(data)
		self:SetAutoState(data.Settings.AutoAttack ~= false)
	end)
	State.Observe({ "ActiveBoosts" }, function()
		self:RenderBuffs()
	end)
	State.EventsChanged:Connect(function()
		self:RenderBuffs()
	end)
	local stats = self.Controllers.SessionStatsController
	if stats and stats.Changed then
		stats.Changed:Connect(function()
			self:RefreshRate()
		end)
	end
	RunService.RenderStepped:Connect(function(dt)
		self:Step(dt)
	end)
	-- Refresh countdowns and let the income rate decay as old gains leave the 60s window.
	task.spawn(function()
		while true do
			task.wait(1)
			self:RenderBuffs()
			self:RefreshRate()
		end
	end)
end

return HUDController
