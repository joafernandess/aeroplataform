--[[
	IndexController
	"Fighter Index" window: every fighter the player can currently obtain (the pools of the visible summon banners,
	plus evolved forms when Features.Evolution is on), grouped by world and sorted by rarity.

	Layout (like the collection windows of the testplace):
	  top     rarity filter chips (All + each rarity present, colours from Config/Rarities)
	  left    grid of FighterIndexCards: 3D bust + name on a rarity-coloured bar when discovered; a dark
	          silhouette with "???" when not (the rarity colour stays visible as the only hint)
	  right   IndexWorldPanel: one banner per world (click to show that world; worlds not in this build are "???")
	          and the selected fighter's info (rarity, world, how to obtain it, chance, discovered or not)
	  bottom  "Fighters discovered X / Y" over the whole Index

	A fighter counts as discovered once the player has ever owned it — the server records it in data.Discovered
	(UnitService.MarkDiscovered: summons, auto-sold rolls and evolutions). New discoveries pop a toast, a badge on
	the Index menu button (cleared when the window opens) and their card pops the next time it is shown.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Banners = require(Shared.Config.Banners)
local Units = require(Shared.Config.Units)
local Rarities = require(Shared.Config.Rarities)
local Features = require(Shared.Config.Features)
local GameConfig = require(Shared.Config.GameConfig)
local Worlds = require(Shared.Config.Worlds)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Cards = require(Client.UI.Cards)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local IndexController = {
	Name = "IndexController",
	Priority = 33,
}

local CARD = UDim2.fromOffset(116, 150)
local GAP = 10
local PANEL_W = 262
local BAR_H = 40
local CHIPS_H = 44

local P = Theme.Colors

IndexController.SelectedWorld = nil :: string? -- world Id
IndexController.Filter = "All" -- rarity Id or "All"
IndexController.Selected = nil :: string? -- unit Id
IndexController.Fresh = {} :: { [string]: boolean } -- discovered since the window was last open (card pops)
IndexController.Unseen = 0

--[[
	Groups shown in the Index: { { Title, Banner, World, WorldName, Units = { unitDef } } }, one per visible banner.
	Pure function of the config (and feature switches) so tests can check it directly.
]]
function IndexController.Groups()
	local groups = {}
	for _, banner in Banners.List do
		if not (Features.MultipleWorlds or banner.World == GameConfig.Start.World) then
			continue
		end
		local seen, units = {}, {}
		local function add(unitId: string?)
			local def = unitId and Units.Get(unitId)
			if def and not seen[def.Id] then
				seen[def.Id] = true
				table.insert(units, def)
			end
		end
		for _, pool in banner.Pool do
			for _, unitId in pool do
				add(unitId)
				local def = Units.Get(unitId)
				if Features.Evolution and def and def.EvolvesTo then
					add(def.EvolvesTo)
				end
			end
		end
		table.sort(units, function(a, b)
			local ra, rb = Rarities.GetOrder(a.Rarity), Rarities.GetOrder(b.Rarity)
			if ra ~= rb then
				return ra < rb
			end
			if (a.Evolved == true) ~= (b.Evolved == true) then
				return not a.Evolved
			end
			return a.Name < b.Name
		end)
		local world = Worlds.Get(banner.World)
		table.insert(groups, {
			Title = banner.Name,
			Banner = banner,
			World = banner.World,
			WorldName = if world then world.Name else banner.World,
			Units = units,
		})
	end
	return groups
end

-- (discovered, total) over every group, or over one world's group.
function IndexController.Progress(data, worldId: string?): (number, number)
	local found, total = 0, 0
	for _, group in IndexController.Groups() do
		if worldId and group.World ~= worldId then
			continue
		end
		for _, def in group.Units do
			total += 1
			if data.Discovered and data.Discovered[def.Id] then
				found += 1
			end
		end
	end
	return found, total
end

-- Rarities present in the Index, in rarity order (for the filter chips).
function IndexController.RarityFilters(): { string }
	local present = {}
	for _, group in IndexController.Groups() do
		for _, def in group.Units do
			present[def.Rarity] = true
		end
	end
	local list = {}
	for _, rarity in Rarities.List do
		if present[rarity.Id] then
			table.insert(list, rarity.Id)
		end
	end
	return list
end

function IndexController:_group()
	local groups = IndexController.Groups()
	for _, group in groups do
		if group.World == self.SelectedWorld then
			return group
		end
	end
	return groups[1]
end

-- How the selected fighter is obtained: "Summon · Shinobi Star · 2.5%" or "Evolve Kazan".
function IndexController.ObtainText(def, group): string
	if def.Evolved then
		for _, other in Units.List or {} do
			if other.EvolvesTo == def.Id then
				return "Evolve " .. other.Name
			end
		end
		return "Evolution"
	end
	local banner = group.Banner
	local pool = banner.Pool[def.Rarity]
	local rate = Banners.GetDisplayRates(banner.Id)[def.Rarity]
	if pool and #pool > 0 and rate then
		local chance = rate / #pool
		local text = if chance >= 1 then ("%.1f%%"):format(chance) else ("%.2f%%"):format(chance)
		return ("Summon · %s · %s"):format(banner.Name, text)
	end
	return "Summon · " .. banner.Name
end

function IndexController:_info(data, group)
	local box = self.WorldPanel.Info
	C.Clear(box)
	C.List(box, Enum.FillDirection.Vertical, 4)
	local def = self.Selected and Units.Get(self.Selected)
	if not def then
		C.Label(box, "Select a fighter to see how to get it.", { Name = "Hint", Size = UDim2.new(1, 0, 0, 44), TextWrapped = true, TextColor3 = P.TextDim, TextSize = 15, LayoutOrder = 1, ZIndex = 3 })
		return
	end
	local discovered = data.Discovered[def.Id] == true
	local rarityColor = Theme.Rarity(def.Rarity)
	C.Title(box, if discovered then def.Name else "???", { Name = "FighterName", Size = UDim2.new(1, 0, 0, 30), TextSize = 26, TextScaled = true, TextColor3 = rarityColor, LayoutOrder = 1, ZIndex = 3 }, 2.5)
	C.Title(box, string.upper(def.Rarity), { Name = "Rarity", Size = UDim2.new(1, 0, 0, 18), TextSize = 15, TextColor3 = P.White, LayoutOrder = 2, ZIndex = 3 }, 1.5)
	-- caption (small, muted) over its value
	local function line(name: string, caption: string, value: string, order: number, color: Color3?)
		local row = C.Frame(box, { Name = name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = order, ZIndex = 3 })
		C.Label(row, caption, { Name = "Caption", Size = UDim2.new(1, 0, 0, 14), TextSize = 12, TextColor3 = P.TextMuted, Font = Theme.Fonts.Bold, ZIndex = 3 })
		C.Label(row, value, {
			Name = "Value",
			Position = UDim2.fromOffset(0, 15),
			Size = UDim2.new(1, 0, 0, 29),
			TextSize = 14,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = color or P.White,
			ZIndex = 3,
		})
	end
	line("World", "WORLD", group.WorldName, 3)
	line("Obtain", "OBTAIN", IndexController.ObtainText(def, group), 4, P.Yellow)
	line("Status", "STATUS", if discovered then "Discovered" else "Not discovered yet", 5, if discovered then P.Green else P.TextDim)
end

function IndexController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	local found, total = IndexController.Progress(data)
	self.Bar.Set(if total > 0 then found / total else 0, "Fighters discovered", ("%d / %d"):format(found, total))

	local groups = IndexController.Groups()
	self.Body.Visible = #groups > 0
	self.Empty.Visible = #groups == 0
	if #groups == 0 then
		return
	end
	local group = self:_group()
	self.SelectedWorld = group.World

	-- World banners (every world of the game; the ones without a collection in this build are "???")
	local worlds = {}
	for _, world in Worlds.List do
		local available = false
		for _, g in groups do
			available = available or g.World == world.Id
		end
		local worldFound, worldTotal = IndexController.Progress(data, world.Id)
		table.insert(worlds, {
			Id = world.Id,
			Name = world.Name,
			Color = if world.Theme then Color3.fromRGB(world.Theme[1], world.Theme[2], world.Theme[3]) else P.Yellow,
			Available = available,
			Selected = world.Id == group.World,
			Count = if available then ("%d / %d"):format(worldFound, worldTotal) else nil,
		})
	end
	self.WorldPanel.SetWorlds(worlds)

	-- Cards of the selected world, filtered by rarity
	C.Clear(self.Grid)
	local shown = 0
	for i, def in group.Units do
		if self.Filter ~= "All" and def.Rarity ~= self.Filter then
			continue
		end
		shown += 1
		local card = Cards.FighterIndexCard(self.Grid, {
			Def = def,
			Discovered = data.Discovered[def.Id] == true,
			Selected = def.Id == self.Selected,
		}, function()
			self.Selected = def.Id
			self:Render()
		end)
		card.LayoutOrder = i
		if self.Fresh[def.Id] then
			Cards.Pop(card)
		end
	end
	if shown == 0 then
		C.Label(self.Grid, "No fighters of this rarity here.", { Name = "NoMatch", Size = UDim2.fromOffset(CARD.X.Offset * 3, 40), TextColor3 = P.TextDim, ZIndex = 3 })
	end
	self.Fresh = {}
	self:_info(data, group)
end

function IndexController:SelectWorld(worldId: string)
	self.SelectedWorld = worldId
	self.Selected = nil
	self:Render()
end

function IndexController:SetFilter(rarity: string)
	self.Filter = rarity
	if self.Chips and self.Chips.Selected ~= rarity then
		self.Chips.Select(rarity)
	end
	self:Render()
end

-- Toast + badge for fighters discovered since the last update (not on the first load).
function IndexController:_track(data)
	local known = {}
	for id, value in data.Discovered or {} do
		known[id] = value == true
	end
	if self.Known then
		local fresh = {}
		for id in known do
			if not self.Known[id] and Units.Get(id) then
				table.insert(fresh, id)
				self.Fresh[id] = true
			end
		end
		if #fresh > 0 then
			local open = self.Controllers.UIController:IsOpen("Index")
			if not open then
				self.Unseen += #fresh
				self.Controllers.UIController:SetMenuBadge("Index", self.Unseen)
			end
			if State.Notify then
				local first = Units.Get(fresh[1])
				State.Notify(if #fresh == 1 then ("New fighter in the Index: %s!"):format(first.Name) else ("%d new fighters in the Index!"):format(#fresh), "Success")
			end
		end
	end
	self.Known = known
end

function IndexController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Index", "Fighter Index", UDim2.fromOffset(960, 560), function()
		self.Unseen = 0
		controllers.UIController:SetMenuBadge("Index", 0)
		self:Render()
	end)
	local content = self.Window.Content
	local body = C.Frame(content, { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	self.Body = body
	-- Rarity filter
	local items = { { Id = "All", Text = "ALL", Color = P.Yellow } }
	for _, rarity in IndexController.RarityFilters() do
		table.insert(items, { Id = rarity, Text = string.upper(rarity), Color = Theme.Rarity(rarity), Gradient = Theme.RarityGradient(rarity) })
	end
	self.Chips = Cards.Chips(body, items, function(id)
		self:SetFilter(id)
	end)
	self.Chips.Frame.Name = "RarityFilter"
	self.Chips.Frame.Position = UDim2.fromOffset(4, 2)
	self.Chips.Frame.Size = UDim2.new(1, -(PANEL_W + 18), 0, 34)
	self.Chips.Select(self.Filter)
	-- Card grid
	self.Grid = C.Scroll(body, { Name = "Cards", Position = UDim2.fromOffset(0, CHIPS_H), Size = UDim2.new(1, -(PANEL_W + 14), 1, -(CHIPS_H + BAR_H + 12)) })
	C.Grid(self.Grid, CARD, GAP)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), Parent = self.Grid })
	-- World banners + fighter info
	self.WorldPanel = Cards.IndexWorldPanel(body, function(worldId)
		self:SelectWorld(worldId)
	end)
	self.WorldPanel.Frame.AnchorPoint = Vector2.new(1, 0)
	self.WorldPanel.Frame.Position = UDim2.new(1, -2, 0, 0)
	self.WorldPanel.Frame.Size = UDim2.new(0, PANEL_W, 1, -(BAR_H + 14))
	-- Discovered count
	self.Bar = Cards.LabeledBar(body, { Name = "Discovered", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 2, 1, -2), Size = UDim2.new(1, -4, 0, BAR_H) })
	self.Empty = C.EmptyState(content, "index", "Nothing to collect yet", "Fighters will be listed here once a summon is available.")
	self.Empty.Visible = false
	local groups = IndexController.Groups()
	self.SelectedWorld = if groups[1] then groups[1].World else nil
end

function IndexController:Start()
	State.Observe({ "Discovered" }, function(data)
		self:_track(data)
		self:Render()
	end)
end

return IndexController
