--[[
	SessionStatsController
	Client-only counters for the current play session (never saved): play time, kills, bosses defeated, Yen earned
	and the best fighter owned (highest Power). Shown in a compact panel in the HUD's right column, under the boosts,
	opened by a small "STATS" button in the HUD's tool slot left of the Power pill. Collapsed by default; the
	expanded state is remembered for this session only.

	Also the Yen income tracker behind the HUD's "≈ X ¥/min" caption (HUDController:RefreshRate):
	  gains = EnemyDefeated payloads (they arrive first) + any Currencies.Yen increase those kills don't explain
	          (quests, sells, codes...). Decreases (spending) are ignored.
	  rate  = gains of the last 60s, per minute (the window is at least 15s so the first kill doesn't spike it).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Config.Units)
local UnitStats = require(Shared.Modules.UnitStats)
local NumberFormat = require(Shared.Modules.NumberFormat)
local Signal = require(Shared.Modules.Signal)
local Net = require(Shared.Remotes.Net)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local SessionStatsController = {
	Name = "SessionStatsController",
	Priority = 11, -- after HUDController, whose right column hosts the panel
}

local RATE_WINDOW = 60
local MIN_RATE_SPAN = 15
-- Panel layout: 2x2 stat tiles + a best-fighter tile (kept short so a phone's right column clears the AUTO button).
local PANEL_WIDTH = 240
local PAD = 8
local TILE_GAP = 6
local TILE_WIDTH = (PANEL_WIDTH - 2 * PAD - TILE_GAP) / 2
local TILE_HEIGHT = 34
local BEST_HEIGHT = 46
local BODY_HEIGHT = PAD * 2 + 2 * (TILE_HEIGHT + TILE_GAP) + BEST_HEIGHT

SessionStatsController.Changed = Signal.new() -- fired whenever a counter changes
SessionStatsController.Clock = os.clock -- overridable in tests
SessionStatsController.Expanded = false
SessionStatsController.Kills = 0
SessionStatsController.Bosses = 0
SessionStatsController.YenEarned = 0
SessionStatsController.Best = nil :: { Name: string, Rarity: string, Level: number, Power: number }?

-- Counters -------------------------------------------------------------------------------------------------------

function SessionStatsController:SessionTime(): number
	return self.Clock() - (self.StartedAt or self.Clock())
end

function SessionStatsController:RecordYen(amount: number)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return
	end
	self.YenEarned += amount
	table.insert(self.Gains, { Time = self.Clock(), Amount = amount })
	self.Changed:Fire()
end

-- Yen per minute over the last 60s of gains.
function SessionStatsController:YenPerMinute(): number
	local now = self.Clock()
	local gains = self.Gains
	local cutoff = now - RATE_WINDOW
	while gains[1] and gains[1].Time < cutoff do
		table.remove(gains, 1)
	end
	local total = 0
	for _, gain in gains do
		total += gain.Amount
	end
	if total <= 0 then
		return 0
	end
	local span = math.clamp(now - self.StartedAt, MIN_RATE_SPAN, RATE_WINDOW)
	return total * 60 / span
end

function SessionStatsController:_onEnemyDefeated(payload)
	if type(payload) ~= "table" then
		return
	end
	self.Kills += 1
	if payload.Boss == true then
		self.Bosses += 1
	end
	local yen = tonumber(payload.Yen) or 0
	if yen > 0 then
		-- Already credited on the server; the matching Currencies update must not count it twice.
		self.PendingKillYen += yen
		self:RecordYen(yen)
	else
		self.Changed:Fire()
	end
end

function SessionStatsController:_onCurrencies(data)
	local yen = data.Currencies and data.Currencies.Yen or 0
	if self.LastYen ~= nil then
		local unexplained = (yen - self.LastYen) - self.PendingKillYen
		if unexplained > 0 then
			self:RecordYen(unexplained)
		end
	end
	-- Each Currencies update already includes every kill reported before it.
	self.PendingKillYen = 0
	self.LastYen = yen
end

-- Highest-Power fighter in the inventory.
function SessionStatsController:_findBest(data)
	local best = nil
	for _, unit in (data.Inventory and data.Inventory.Units) or {} do
		local def = Units.Get(unit.UnitId)
		local stats = def and UnitStats.Compute(unit)
		if def and stats and (best == nil or stats.Power > best.Power) then
			best = { Name = def.Name, Rarity = def.Rarity, Level = unit.Level or 1, Power = stats.Power }
		end
	end
	return best
end

-- Panel ------------------------------------------------------------------------------------------------------------

-- Dark inset tile (PanelAlt well) inside the panel body.
local function tile(parent: Instance, x: number, y: number, w: number, h: number)
	local frame = C.Frame(parent, { BackgroundColor3 = Theme.Colors.PanelAlt, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), ZIndex = 3 })
	C.Corner(frame, 8)
	return frame
end

-- Stat tile: small caption on top, big number below. Returns the value label.
local function statTile(parent: Instance, caption: string, column: number, row: number)
	local frame = tile(parent, PAD + column * (TILE_WIDTH + TILE_GAP), PAD + row * (TILE_HEIGHT + TILE_GAP), TILE_WIDTH, TILE_HEIGHT)
	C.Title(frame, caption, { Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -12, 0, 13), TextSize = 11, TextColor3 = Theme.Colors.TextDim, ZIndex = 4 }, 1.5)
	return C.Number(frame, "0", { Position = UDim2.fromOffset(8, 14), Size = UDim2.new(1, -12, 0, 20), TextSize = 18, ZIndex = 4 })
end

function SessionStatsController:_build(toolParent: Instance, bodyParent: Instance)
	local P = Theme.Colors
	self.ToggleButton = C.Button(toolParent, "STATS ▼", function()
		self:Toggle()
	end, {
		Name = "StatsToggle",
		Kind = "Dark",
		TextSize = 15,
		Radius = Theme.Radius.Tool,
		Size = UDim2.fromOffset(84, 44), -- 40px face + lip: full touch target
		StrokeThickness = Theme.Stroke.Tool,
		Confirm = false,
		LayoutOrder = 1,
	})

	local body = C.Frame(bodyParent, {
		Name = "SessionStats",
		BackgroundColor3 = P.Panel,
		BackgroundTransparency = 0.08,
		Size = UDim2.fromOffset(PANEL_WIDTH, BODY_HEIGHT),
		LayoutOrder = 3,
		Visible = false,
	})
	C.Corner(body, Theme.Radius.Card)
	C.Stroke(body, P.Ink, Theme.Stroke.Card)
	local rim = C.Frame(body, { BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), ZIndex = 2 })
	C.Corner(rim, Theme.Radius.Card - 3)
	C.Stroke(rim, P.Line, Theme.Stroke.Rim)
	self.Body = body

	self.TimeValue = statTile(body, "SESSION", 0, 0)
	self.KillsValue = statTile(body, "KILLS", 1, 0)
	self.BossesValue = statTile(body, "BOSSES", 0, 1)
	self.YenValue = statTile(body, "YEN EARNED", 1, 1)
	self.YenValue.TextColor3 = P.Cyan

	-- Best fighter: rarity strip + name, rarity name and level (never colour alone), Power on the right.
	local best = tile(body, PAD, PAD + 2 * (TILE_HEIGHT + TILE_GAP), PANEL_WIDTH - 2 * PAD, BEST_HEIGHT)
	self.BestStrip = C.Frame(best, { Name = "RarityStrip", BackgroundColor3 = P.TextMuted, Position = UDim2.fromOffset(7, 6), Size = UDim2.fromOffset(5, BEST_HEIGHT - 12), ZIndex = 4 })
	C.Corner(self.BestStrip, UDim.new(0.5, 0))
	C.Title(best, "BEST FIGHTER", { Position = UDim2.fromOffset(18, 2), Size = UDim2.fromOffset(120, 13), TextSize = 11, TextColor3 = P.TextDim, ZIndex = 4 }, 1.5)
	self.BestName = C.Title(best, "—", {
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.new(1, -96, 0, 18),
		TextSize = 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	}, 2)
	self.BestInfo = C.Title(best, "", {
		Font = Theme.Fonts.Body,
		Position = UDim2.fromOffset(18, 31),
		Size = UDim2.new(1, -96, 0, 14),
		TextSize = 12,
		TextColor3 = P.TextDim,
		ZIndex = 4,
	}, 1.5)
	self.BestPower = C.Number(best, "", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(84, 22),
		TextSize = 17,
		TextColor3 = P.Cyan,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
end

function SessionStatsController:Refresh()
	if not self.Body then
		return
	end
	C.SetText(self.ToggleButton, if self.Expanded then "STATS ▲" else "STATS ▼")
	C.SetToolActive(self.ToggleButton, self.Expanded)
	self.Body.Visible = self.Expanded
	if not self.Expanded then
		return
	end
	self.TimeValue.Text = NumberFormat.Duration(self:SessionTime())
	self.KillsValue.Text = NumberFormat.Abbreviate(self.Kills)
	self.BossesValue.Text = NumberFormat.Abbreviate(self.Bosses)
	self.YenValue.Text = "+" .. NumberFormat.Abbreviate(math.floor(self.YenEarned)) .. " " .. Theme.Icons.Yen
	local best = self.Best
	if best then
		self.BestStrip.BackgroundColor3 = Theme.Rarity(best.Rarity)
		self.BestName.Text = best.Name
		self.BestInfo.Text = best.Rarity .. " · Lv " .. best.Level
		self.BestPower.Text = NumberFormat.Abbreviate(best.Power) .. " " .. Theme.Icons.Power
	else
		self.BestStrip.BackgroundColor3 = Theme.Colors.TextMuted
		self.BestName.Text = "—"
		self.BestInfo.Text = ""
		self.BestPower.Text = ""
	end
end

function SessionStatsController:SetExpanded(expanded: boolean)
	self.Expanded = expanded
	self:Refresh()
end

function SessionStatsController:Toggle()
	self:SetExpanded(not self.Expanded)
end

-- Lifecycle --------------------------------------------------------------------------------------------------------

function SessionStatsController:Init(controllers)
	self.StartedAt = self.Clock()
	self.Gains = {}
	self.PendingKillYen = 0
	self.LastYen = nil
	-- Toggle in the HUD's tool slot (left of the Power pill), panel under the boosts in the right column.
	local hud = controllers.HUDController
	local column = hud and hud.RightColumn
	local tools = hud and hud.RightTools
	if not column then
		-- Fallback: own top-right column (HUD missing or reorganised).
		local ui = controllers.UIController
		column = C.Frame(ui:GetRoot(), { Name = "SessionStatsColumn", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 64), Size = UDim2.fromOffset(PANEL_WIDTH, 260) })
		C.List(column, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
		ui:AddScaled(column, "Hud")
	end
	self:_build(tools or column, column)
	self:Refresh()
end

function SessionStatsController:Start()
	Net.Connect("EnemyDefeated", function(payload)
		self:_onEnemyDefeated(payload)
	end)
	State.Observe({ "Currencies" }, function(data)
		self:_onCurrencies(data)
	end)
	State.Observe({ "Inventory" }, function(data)
		self.Best = self:_findBest(data)
		self:Refresh()
	end)
	self.Changed:Connect(function()
		if self.Expanded then
			self:Refresh()
		end
	end)
	-- Session clock
	task.spawn(function()
		while true do
			task.wait(1)
			if self.Expanded then
				self:Refresh()
			end
		end
	end)
end

return SessionStatsController
