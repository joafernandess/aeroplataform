--[[
	HUDController
	Always-visible player info, kept minimal and docked right above the left menu grid:
	  Yen counter box (Gems/Gold/Tokens boxes too when Features.PremiumCurrencies is on)
	  active boosts/events under it (only while there are any)
	  bottom-centre level badge + XP bar (only when Features.PlayerLevel is on)
	Side menus belong to UIController (UI/Navigation); the top-right corner belongs to UpdateLogController.
	Team power lives in the Stats window; auto-attack is a toggle in Settings.

	Reward feedback ("juice", docs/ui/UI_RESEARCH.md §2.5 / §5.3): when a currency goes up, its box pops (UIScale
	on the pill itself, not on the scaled column), its number counts up in ~0.4s and a floating "+X" ticker rises
	next to it and fades. Gains that arrive while a ticker is still showing merge into it.
	Decreases (spending) only count down: no pop, no ticker.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Features = require(Shared.Config.Features)
local Formulas = require(Shared.Modules.Formulas)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)
local Navigation = require(Client.UI.Navigation)

local HUDController = {
	Name = "HUDController",
	Priority = 10,
}

local COUNT_TIME = 0.4 -- number count-up
local BUMP_SCALE = 1.12
local TICKER_RISE_TIME = 0.6
local TICKER_HOLD = 0.75 -- a ticker stays fully visible this long after its last (merged) gain
local TICKER_FADE = 0.3

-- C.CurrencyBox (rounded-square counter): exactly as wide as the left menu grid it sits on.
local BOX_W = Navigation.PerRow * Navigation.ButtonSize + (Navigation.PerRow - 1) * Navigation.Gap
local BOX_H = 58
local PILL_HEIGHT = BOX_H + 4 -- row height (box + its shadow)
local BUFF_HEIGHT = 30

local function tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goals)
	t:Play()
	return t
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
	Wraps a C.CurrencyBox so it can count up, pop and show "+X" tickers.
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
	-- Placed by UIController:LayoutNav right above the left menu grid (same left edge, same scale).
	local currencies = C.Frame(root, { Name = "PlayerInfo", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(220, 260) })
	C.List(currencies, Enum.FillDirection.Vertical, 6)
	self.CurrencyPills = {}
	self.Animated = {}
	for i, currency in GameConfig.Economy.Currencies do
		if currency ~= "Yen" and not Features.PremiumCurrencies then
			continue -- base game: Yen only
		end
		local row = C.Frame(currencies, {
			Name = currency .. "Row",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(BOX_W, PILL_HEIGHT),
			LayoutOrder = i,
		})
		local pill = C.CurrencyBox(row, Theme.Icons[currency] or "?", BOX_W, {
			Height = BOX_H,
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
			TickerFrom = UDim2.fromOffset(BOX_W + 10, PILL_HEIGHT / 2 + 10),
			TickerTo = UDim2.fromOffset(BOX_W + 10, PILL_HEIGHT / 2 - 3),
			TickerAlign = Enum.TextXAlignment.Left,
		})
	end

	self.BuffList = C.Frame(currencies, { Name = "Boosts", BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 50, Visible = false })
	C.List(self.BuffList, Enum.FillDirection.Vertical, 6)

	self.InfoFrame = currencies
	ui:AttachAboveNav("Left", currencies, function()
		return self:InfoHeight()
	end)

	-- Level badge + XP bar (bottom centre)
	local levelFrame = C.Frame(root, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(460, 52), Visible = Features.PlayerLevel })
	self.XPBar = C.ProgressBar(levelFrame, nil, { Position = UDim2.fromOffset(34, 17), Size = UDim2.new(1, -34, 0, 20) })
	local badge = C.Frame(levelFrame, { Size = UDim2.fromOffset(52, 52), BackgroundColor3 = P.White, ZIndex = 4 })
	C.Corner(badge, UDim.new(0.5, 0))
	C.Stroke(badge, P.Ink, Theme.Stroke.Button)
	C.Gradient(badge, Theme.Gradients.Primary.Top, Theme.Gradients.Primary.Bottom)
	self.LevelLabel = C.Label(badge, "1", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Display, TextSize = 24, ZIndex = 5 })
	C.Outline(self.LevelLabel, 2.5)

	-- Responsive scaling (phones/tablets): every HUD block keeps its anchor and shrinks with the screen.
	-- (the player info is scaled together with the left menu by UIController:LayoutNav)
	ui:AddScaled(levelFrame, "Hud")
end

-- Unscaled height of the player-info stack (currency boxes + boosts).
function HUDController:InfoHeight(): number
	local frame = self.InfoFrame
	local height, count = 0, 0
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			count += 1
			if child == self.BuffList then
				height += (self.BuffCount or 0) * (BUFF_HEIGHT + 6) - 6
			else
				height += child.Size.Y.Offset
			end
		end
	end
	return height + math.max(count - 1, 0) * 6
end

-- Bottom edge of the player-info stack in root pixels.
function HUDController:InfoBottom(): number
	local frame = self.InfoFrame
	local scale = frame:FindFirstChildOfClass("UIScale")
	return frame.Position.Y.Offset + self:InfoHeight() * (if scale then scale.Scale else 1)
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
		local pill = C.Frame(self.BuffList, { Size = UDim2.fromOffset(220, BUFF_HEIGHT), BackgroundColor3 = P.Panel, BackgroundTransparency = 0.1, LayoutOrder = order })
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
	-- Collapse the empty list (it is the last block of the player-info column); the left menu follows its height.
	self.BuffList.Visible = order > 0
	if order ~= self.BuffCount then
		self.BuffCount = order
		self.Controllers.UIController:LayoutNav()
	end
end

function HUDController:Start()
	State.Observe({ "Currencies" }, function(data)
		for currency, entry in self.Animated do
			self:SetAnimated(entry, data.Currencies[currency] or 0)
		end
	end)
	State.Observe({ "Level", "Experience" }, function(data)
		local needed = Formulas.PlayerXPToNext(data.Level)
		self.LevelLabel.Text = tostring(data.Level)
		self.XPBar.Set(data.Experience / math.max(needed, 1), NumberFormat.Abbreviate(data.Experience) .. " / " .. NumberFormat.Abbreviate(needed) .. " XP")
	end)
	State.Observe({ "ActiveBoosts" }, function()
		self:RenderBuffs()
	end)
	State.EventsChanged:Connect(function()
		self:RenderBuffs()
	end)
	-- Refresh boost countdowns.
	task.spawn(function()
		while true do
			task.wait(1)
			self:RenderBuffs()
		end
	end)
end

return HUDController
