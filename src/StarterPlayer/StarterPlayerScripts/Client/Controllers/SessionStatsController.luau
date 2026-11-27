--[[
	SessionStatsController
	The "Stats" window (right menu) and the session counters behind it:
	  Team power    total (equipped fighters' Power with the Damage upgrade) and each fighter's share
	  This session  play time, kills, bosses, Yen earned, Yen spent, Yen per minute (client-only, never saved)
	  All time      saved lifetime stats from the profile (kills, bosses, damage, Yen, summons) and fighters discovered
	  Best fighter  highest-Power fighter owned

	Yen income tracker (the "Yen / min" tile):
	  gains = EnemyDefeated payloads (they arrive first) + any Currencies.Yen increase those kills don't explain
	          (quests, sells, codes...). Decreases (spending) are ignored.
	  rate  = gains of the last 60s, per minute (the window is at least 15s so the first kill doesn't spike it).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Config.Units)
local UnitStats = require(Shared.Modules.UnitStats)
local Formulas = require(Shared.Modules.Formulas)
local NumberFormat = require(Shared.Modules.NumberFormat)
local Signal = require(Shared.Modules.Signal)
local Net = require(Shared.Remotes.Net)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local SessionStatsController = {
	Name = "SessionStatsController",
	Priority = 36,
}

local RATE_WINDOW = 60
local MIN_RATE_SPAN = 15
local TILE_H, TILE_GAP = 62, 8
local CONTENT_W = 720 - 32 - 4 - 14 -- window width minus padding and scrollbar

SessionStatsController.Changed = Signal.new() -- fired whenever a counter changes
SessionStatsController.Clock = os.clock -- overridable in tests
SessionStatsController.Kills = 0
SessionStatsController.Bosses = 0
SessionStatsController.YenEarned = 0
SessionStatsController.YenSpent = 0
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
		elseif unexplained < 0 then
			-- Spent (summons, upgrades...): kill Yen already counted above can't make this negative.
			self.YenSpent += -unexplained
			self.Changed:Fire()
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

-- Window -----------------------------------------------------------------------------------------------------------

-- Equipped fighters with their Power, strongest first, and the team total (with the Damage upgrade, like the HUD).
function SessionStatsController.TeamBreakdown(data): ({ { Name: string, Rarity: string, Level: number, Power: number } }, number)
	local members, sum = {}, 0
	for _, uid in data.EquippedUnits do
		local unit = data.Inventory.Units[uid]
		local def = unit and Units.Get(unit.UnitId)
		local stats = def and UnitStats.Compute(unit)
		if def and stats then
			sum += stats.Power
			table.insert(members, { Name = def.Name, Rarity = def.Rarity, Level = unit.Level or 1, Power = stats.Power })
		end
	end
	table.sort(members, function(a, b)
		return a.Power > b.Power
	end)
	local total = math.floor(sum * Formulas.UpgradeMultiplier("Damage", data.Upgrades.Damage or 0))
	return members, total
end

local function count(map): number
	local n = 0
	for _ in map or {} do
		n += 1
	end
	return n
end

-- Row of stat tiles: { { Caption, Value, Color? } }.
function SessionStatsController:_tiles(order: number, tiles)
	local row = C.Frame(self.List, { Name = "Tiles", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, TILE_H), LayoutOrder = order })
	C.List(row, Enum.FillDirection.Horizontal, TILE_GAP)
	local labels = {}
	local tileW = math.floor((CONTENT_W - (#tiles - 1) * TILE_GAP) / #tiles)
	for i, tile in tiles do
		local _, value = C.StatTile(row, tile[1], tile[2], { Name = tile[1], Size = UDim2.fromOffset(tileW, TILE_H), LayoutOrder = i })
		if tile[3] then
			value.TextColor3 = tile[3]
		end
		labels[tile[1]] = value
	end
	return labels
end

-- Fighter row: rarity strip, name, "Rarity · Lv", Power and a bar with its share of the team.
function SessionStatsController:_fighterRow(order: number, member, share: number?)
	local P = Theme.Colors
	local row = C.Row(self.List, { Name = "Fighter", Size = UDim2.new(1, -8, 0, 54), LayoutOrder = order })
	local strip = C.Frame(row, { BackgroundColor3 = Theme.Rarity(member.Rarity), Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(6, 36) })
	C.Corner(strip, UDim.new(0.5, 0))
	C.Title(row, member.Name, { Position = UDim2.fromOffset(26, 5), Size = UDim2.new(0.5, -30, 0, 24), TextSize = 18, TextTruncate = Enum.TextTruncate.AtEnd }, 2)
	C.Label(row, ("%s · Lv %d"):format(member.Rarity, member.Level), { Position = UDim2.fromOffset(26, 28), Size = UDim2.new(0.5, -30, 0, 20), TextSize = 14, TextColor3 = P.TextDim })
	if share then
		local bar = C.ProgressBar(row, nil, { Position = UDim2.new(0.5, 0, 0.5, -8), Size = UDim2.new(0.3, 0, 0, 16) })
		bar.Set(share, ("%d%%"):format(math.floor(share * 100 + 0.5)))
	end
	local power = C.Frame(row, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0.2, -16, 0, 28) })
	C.Icon(power, "power", { Size = 20, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Color = P.Cyan })
	C.Number(power, NumberFormat.Abbreviate(member.Power), { Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right })
end

function SessionStatsController:Render()
	local data = State.Data
	if not (self.Window and self.Window.Frame.Visible and data) then
		return
	end
	local P = Theme.Colors
	C.Clear(self.List)

	local members, total = SessionStatsController.TeamBreakdown(data)
	C.Section(self.List, ("Team power  ·  %s"):format(NumberFormat.Abbreviate(total)), 1)
	if #members == 0 then
		C.Label(self.List, "No fighters equipped.", { TextColor3 = P.TextDim, LayoutOrder = 2 })
	end
	local sum = 0
	for _, member in members do
		sum += member.Power
	end
	for i, member in members do
		self:_fighterRow(1 + i, member, if sum > 0 then member.Power / sum else 0)
	end

	C.Section(self.List, "This session", 20)
	self.SessionLabels = self:_tiles(21, {
		{ "Time", NumberFormat.Duration(self:SessionTime()) },
		{ "Kills", NumberFormat.Abbreviate(self.Kills) },
		{ "Bosses", NumberFormat.Abbreviate(self.Bosses) },
		{ "Yen earned", NumberFormat.Abbreviate(math.floor(self.YenEarned)), P.Yen },
		{ "Yen spent", NumberFormat.Abbreviate(math.floor(self.YenSpent)), P.Yen },
		{ "Yen / min", NumberFormat.Abbreviate(math.floor(self:YenPerMinute())), P.Yen },
	})

	local stats = data.Stats
	C.Section(self.List, "All time", 30)
	self:_tiles(31, {
		{ "Kills", NumberFormat.Abbreviate(stats.TotalKills or 0) },
		{ "Bosses", NumberFormat.Abbreviate(stats.BossKills or 0) },
		{ "Damage", NumberFormat.Abbreviate(math.floor(stats.TotalDamage or 0)) },
		{ "Yen earned", NumberFormat.Abbreviate(math.floor(stats.TotalYenEarned or 0)), P.Yen },
		{ "Summons", NumberFormat.Abbreviate(stats.TotalSummons or 0) },
		{ "Discovered", tostring(count(data.Discovered)) },
	})

	C.Section(self.List, "Best fighter", 40)
	local best = self.Best
	if best then
		self:_fighterRow(41, best, nil)
	else
		C.Label(self.List, "No fighters yet.", { TextColor3 = P.TextDim, LayoutOrder = 41 })
	end
end

-- Live session tiles (cheap: only text, no rebuild).
function SessionStatsController:RefreshSession()
	local labels = self.SessionLabels
	if not (labels and self.Window and self.Window.Frame.Visible) then
		return
	end
	labels["Time"].Text = NumberFormat.Duration(self:SessionTime())
	labels["Kills"].Text = NumberFormat.Abbreviate(self.Kills)
	labels["Bosses"].Text = NumberFormat.Abbreviate(self.Bosses)
	labels["Yen earned"].Text = NumberFormat.Abbreviate(math.floor(self.YenEarned))
	labels["Yen spent"].Text = NumberFormat.Abbreviate(math.floor(self.YenSpent))
	labels["Yen / min"].Text = NumberFormat.Abbreviate(math.floor(self:YenPerMinute()))
end

-- Lifecycle --------------------------------------------------------------------------------------------------------

function SessionStatsController:Init(controllers)
	self.Controllers = controllers
	self.StartedAt = self.Clock()
	self.Gains = {}
	self.PendingKillYen = 0
	self.LastYen = nil
	local ui = controllers.UIController
	if ui then
		self.Window = ui:CreateWindow("Stats", "Stats", UDim2.fromOffset(720, 540), function()
			self:Render()
		end)
		self.List = C.Scroll(self.Window.Content)
		C.List(self.List, Enum.FillDirection.Vertical, 8)
		C.Create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 4), Parent = self.List })
	end
end

function SessionStatsController:Start()
	Net.Connect("EnemyDefeated", function(payload)
		self:_onEnemyDefeated(payload)
	end)
	State.Observe({ "Currencies" }, function(data)
		self:_onCurrencies(data)
	end)
	State.Observe({ "Inventory", "EquippedUnits", "Upgrades", "Stats", "Discovered" }, function(data)
		self.Best = self:_findBest(data)
		self:Render()
	end)
	self.Changed:Connect(function()
		self:RefreshSession()
	end)
	-- Session clock
	task.spawn(function()
		while true do
			task.wait(1)
			self:RefreshSession()
		end
	end)
end

return SessionStatsController
