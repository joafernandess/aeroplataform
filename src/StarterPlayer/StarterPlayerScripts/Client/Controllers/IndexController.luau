--[[
	IndexController
	"Index" window: the collection of every fighter the player can currently obtain (the pools of the visible
	summon banners, plus evolved forms when Features.Evolution is on), grouped by banner and sorted by rarity.

	A fighter counts as discovered once the player has ever owned it — the server records it in data.Discovered
	(UnitService.MarkDiscovered: summons, auto-sold rolls and evolutions). Undiscovered fighters show as dark
	"???" silhouettes with only their rarity visible. The header shows the overall progress.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Banners = require(Shared.Config.Banners)
local Units = require(Shared.Config.Units)
local Rarities = require(Shared.Config.Rarities)
local Features = require(Shared.Config.Features)
local GameConfig = require(Shared.Config.GameConfig)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local IndexController = {
	Name = "IndexController",
	Priority = 33,
}

local CARD = UDim2.fromOffset(104, 132)
local CARD_GAP = 10
local WINDOW_W = 820
-- Cards per grid row: the window is scaled with a UIScale (its layout width never changes), so this is fixed.
local PER_ROW = math.floor((WINDOW_W - 32 - 4 - 8 - 6 + CARD_GAP) / (CARD.X.Offset + CARD_GAP))

local P = Theme.Colors

--[[
	Groups shown in the Index: { { Title, Units = { unitDef } } }, one per visible banner.
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
		table.insert(groups, { Title = banner.Name, Units = units })
	end
	return groups
end

-- (discovered, total) over every group.
function IndexController.Progress(data): (number, number)
	local found, total = 0, 0
	for _, group in IndexController.Groups() do
		for _, def in group.Units do
			total += 1
			if data.Discovered and data.Discovered[def.Id] then
				found += 1
			end
		end
	end
	return found, total
end

-- Dark silhouette card for a fighter not discovered yet (rarity is the only hint).
local function hiddenCard(parent: Instance, def, order: number)
	local rarityColor = Theme.Rarity(def.Rarity)
	local card = C.Frame(parent, { Name = "Hidden_" .. def.Rarity, BackgroundColor3 = P.Bg, LayoutOrder = order })
	C.Corner(card, Theme.Radius.Card)
	C.Stroke(card, P.Line, 2)
	local portrait = C.Frame(card, { Name = "Silhouette", BackgroundColor3 = P.Ink, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 76) })
	C.Corner(portrait, 10)
	C.Title(portrait, "?", { Size = UDim2.fromScale(1, 1), Font = Theme.Fonts.Display, TextSize = 40, TextColor3 = P.PanelLight, TextXAlignment = Enum.TextXAlignment.Center }, 0.01)
	local strip = C.Frame(card, { BackgroundColor3 = rarityColor, BackgroundTransparency = 0.45, Position = UDim2.fromOffset(8, 87), Size = UDim2.new(1, -16, 0, 5) })
	C.Corner(strip, UDim.new(0.5, 0))
	C.Title(card, "???", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.new(1, -8, 0, 18), TextSize = 15, TextColor3 = P.TextMuted, TextXAlignment = Enum.TextXAlignment.Center }, 1.5)
	C.Title(card, string.upper(def.Rarity), {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -8, 0, 16),
		TextSize = 11,
		TextColor3 = Theme.Darken(rarityColor, 0.25),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, 1.5)
	return card
end

function IndexController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	local found, total = IndexController.Progress(data)
	self.ProgressBar.Set(if total > 0 then found / total else 0, ("%d / %d discovered"):format(found, total))
	self.Percent.Text = ("%d%%"):format(if total > 0 then math.floor(found / total * 100) else 0)

	C.Clear(self.List)
	local groups = IndexController.Groups()
	if #groups == 0 then
		C.EmptyState(self.List, "index", "Nothing to collect yet", "Fighters will be listed here once a summon is available.")
		return
	end
	local order = 0
	for _, group in groups do
		order += 1
		local groupFound = 0
		for _, def in group.Units do
			if data.Discovered[def.Id] then
				groupFound += 1
			end
		end
		C.Section(self.List, ("%s  ·  %d/%d"):format(group.Title, groupFound, #group.Units), order)
		local rows = math.ceil(#group.Units / PER_ROW)
		order += 1
		local grid = C.Frame(self.List, {
			Name = "Grid",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, rows * CARD.Y.Offset + math.max(rows - 1, 0) * CARD_GAP + 4),
			LayoutOrder = order,
		})
		C.Grid(grid, CARD, CARD_GAP)
		for i, def in group.Units do
			if data.Discovered[def.Id] then
				local card = C.UnitCard(grid, {
					Name = def.Name,
					Rarity = def.Rarity,
					Level = 1,
					Stars = 0,
					Locked = false,
					Equipped = false,
					HideLevel = true,
					Footer = string.upper(def.Rarity),
					FooterColor = Theme.Rarity(def.Rarity),
					FooterFont = Theme.Fonts.Title,
				})
				card.Name = def.Id
				card.LayoutOrder = i
			else
				hiddenCard(grid, def, i)
			end
		end
	end
end

function IndexController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Index", "Index", UDim2.fromOffset(WINDOW_W, 560), function()
		self:Render()
	end)
	local content = self.Window.Content
	local header = C.Frame(content, { Name = "Progress", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) })
	self.ProgressBar = C.ProgressBar(header, nil, { Position = UDim2.fromOffset(4, 8), Size = UDim2.new(1, -96, 0, 24) })
	self.Percent = C.Number(header, "0%", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(80, 30),
		TextSize = 26,
		TextColor3 = P.Cyan,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	self.List = C.Scroll(content, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 1, -48) })
	C.List(self.List, Enum.FillDirection.Vertical, 6)
	C.Create("UIPadding", { PaddingLeft = UDim.new(0, 4), Parent = self.List })
end

function IndexController:Start()
	State.Observe({ "Discovered" }, function()
		self:Render()
	end)
end

return IndexController
