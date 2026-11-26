--[[
	InventoryController
	"Fighters" window: unit grid + embedded details panel (UnitDetailsController).
	(Items and currencies live in the Inventory window, ItemsController.)
	Also owns the NEW badge on the Fighters menu button: fighters obtained this session while the window was
	closed (summons, quest rewards...) are counted until the Fighters window is opened.
	Modes:
	  Browse  - click a card to inspect it
	  Fuse    - pick fodder for the selected target, then confirm (FuseUnits)
	  Delete  - multi-select units to sell (DeleteUnits)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Config.Units)
local Rarities = require(Shared.Config.Rarities)
local UnitStats = require(Shared.Modules.UnitStats)
local Formulas = require(Shared.Modules.Formulas)
local TableUtil = require(Shared.Modules.TableUtil)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local InventoryController = {
	Name = "InventoryController",
	Priority = 20,
}

InventoryController.Mode = "Browse"
InventoryController.SelectedUid = nil :: string?
InventoryController.MultiSelect = {} :: { [string]: boolean }
InventoryController.NewUids = {} :: { [string]: boolean }
InventoryController.KnownUids = nil :: { [string]: boolean }?

local SORTS = { "Power", "Rarity", "Level" }

local function sortedUnits(data, sortBy: string)
	local equipped = TableUtil.ToSet(data.EquippedUnits)
	local list = {}
	for uid, unit in data.Inventory.Units do
		local def = Units.Get(unit.UnitId)
		local stats = UnitStats.Compute(unit)
		if def and stats then
			table.insert(list, { Uid = uid, Unit = unit, Def = def, Power = stats.Power })
		end
	end
	table.sort(list, function(a, b)
		-- Equipped fighters always come first, then the chosen sort key.
		local ea, eb = equipped[a.Uid] == true, equipped[b.Uid] == true
		if ea ~= eb then
			return ea
		end
		local ka, kb
		if sortBy == "Rarity" then
			ka, kb = Rarities.GetOrder(a.Def.Rarity), Rarities.GetOrder(b.Def.Rarity)
		elseif sortBy == "Level" then
			ka, kb = a.Unit.Level, b.Unit.Level
		else
			ka, kb = a.Power, b.Power
		end
		if ka == kb then
			return a.Uid < b.Uid
		end
		return ka > kb
	end)
	return list
end

function InventoryController:SetMode(mode: string)
	self.Mode = mode
	self.MultiSelect = {}
	self:Render()
end

function InventoryController:Select(uid: string?)
	self.SelectedUid = uid
	self:Render()
end

function InventoryController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	local count = TableUtil.Count(data.Inventory.Units)
	local capacity = Formulas.UnitStorage(data.Upgrades.UnitStorage or 0)
	local slots = Formulas.EquipSlots(data.Upgrades.EquipSlots or 0, 0)
	self.UnitsCounter.Set(("%d/%d"):format(count, capacity), if count >= capacity then "Full" elseif count >= capacity * 0.9 then "Near" else "Normal")
	self.EquippedCounter.Set(("%d/%d"):format(#data.EquippedUnits, slots), if #data.EquippedUnits >= slots then "Near" else "Normal")
	self.SortLabel.Text = "Sort: " .. self.SortBy
	C.SetKind(self.SellModeButton, if self.Mode == "Delete" then "Primary" else "Danger")
	C.SetSelected(self.SellModeButton, self.Mode == "Delete")

	local modeText = {
		Browse = "",
		Fuse = "FUSE: select fodder units, then Confirm",
		Delete = "DELETE: select units to sell, then Confirm",
	}
	self.ModeLabel.Text = modeText[self.Mode]
	local selecting = self.Mode ~= "Browse"
	self.ModeBar.Visible = selecting
	self.Toolbar.Visible = not selecting
	self.ConfirmButton.Visible = self.Mode ~= "Browse"
	self.CancelButton.Visible = self.Mode ~= "Browse"

	C.Clear(self.Grid)
	local equipped = TableUtil.ToSet(data.EquippedUnits)
	for i, entry in sortedUnits(data, self.SortBy) do
		local unit = entry.Unit
		local card = C.UnitCard(self.Grid, {
			Name = entry.Def.Name,
			Rarity = entry.Def.Rarity,
			Level = unit.Level,
			Stars = unit.Stars or 0,
			Locked = unit.Locked,
			Equipped = equipped[entry.Uid] == true,
			Trait = unit.Trait,
		}, function()
			if self.Mode == "Browse" then
				self:Select(entry.Uid)
			elseif entry.Uid ~= self.SelectedUid then
				self.MultiSelect[entry.Uid] = if self.MultiSelect[entry.Uid] then nil else true
				self:Render()
			end
		end)
		card.LayoutOrder = i
		if self.MultiSelect[entry.Uid] then
			C.HighlightCard(card, "Marked")
		elseif entry.Uid == self.SelectedUid then
			C.HighlightCard(card, "Selected")
		end
	end

	self.Controllers.UnitDetailsController:Render(self.Details, self.SelectedUid)
end

function InventoryController:Confirm()
	local selected = {}
	for uid in self.MultiSelect do
		table.insert(selected, uid)
	end
	if #selected == 0 then
		return
	end
	if self.Mode == "Fuse" and self.SelectedUid then
		local response = State.Request("FuseUnits", self.SelectedUid, selected)
		if response.ok and State.Notify then
			State.Notify(("Fused! +%d XP, +%d stars"):format(response.data.XPGained, response.data.StarsGained), "Success")
		end
	elseif self.Mode == "Delete" then
		local response = State.Request("DeleteUnits", selected)
		if response.ok and State.Notify then
			State.Notify(("Sold %d units for %d Yen"):format(response.data.Deleted, response.data.Yen), "Success")
		end
		if self.SelectedUid and self.MultiSelect[self.SelectedUid] then
			self.SelectedUid = nil
		end
	end
	self:SetMode("Browse")
end

function InventoryController:Init(controllers)
	self.Controllers = controllers
	self.SortBy = SORTS[1]
	local window = controllers.UIController:CreateWindow("Fighters", "Fighters", UDim2.fromOffset(860, 560), function()
		self:Render()
	end)
	window.OnClose = function()
		self.Mode = "Browse"
		self.MultiSelect = {}
	end
	self.Window = window
	local content = window.Content

	local tabs = C.Tabs(content, { "Units" }, function()
		self:Render()
	end)
	-- Capacity counters (top-right of the content area)
	local counters = C.Frame(content, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 5), Size = UDim2.fromOffset(260, 34) })
	C.List(counters, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right)
	self.UnitsCounter = C.Counter(counters, Theme.Icons.Inventory, { LayoutOrder = 1 })
	self.EquippedCounter = C.Counter(counters, Theme.Icons.Equipped, { LayoutOrder = 2, Size = UDim2.fromOffset(96, 34) })

	-- Units page
	local unitsPage = C.Frame(content, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54) })
	self.UnitsPage = unitsPage

	-- Toolbar: sort (cycles) + sell mode
	local toolbar = C.Frame(unitsPage, { BackgroundTransparency = 1, Size = UDim2.new(0.58, 0, 0, 44) })
	C.List(toolbar, Enum.FillDirection.Horizontal, 8)
	self.Toolbar = toolbar
	C.ToolButton(toolbar, Theme.Icons.Sort, function()
		local index = table.find(SORTS, self.SortBy) or 1
		self.SortBy = SORTS[index % #SORTS + 1]
		self:Render()
	end, { LayoutOrder = 1 })
	self.SortLabel = C.Title(toolbar, "Sort: Power", { Size = UDim2.fromOffset(150, 44), TextSize = 16, TextColor3 = Theme.Colors.TextDim, LayoutOrder = 2 }, 2)
	self.SellModeButton = C.Button(toolbar, "SELL MODE", function()
		self:SetMode(if self.Mode == "Delete" then "Browse" else "Delete")
	end, { Kind = "Danger", Confirm = false, Size = UDim2.fromOffset(140, 44), TextSize = 16, LayoutOrder = 3 })

	local modeBar = C.Frame(unitsPage, { BackgroundTransparency = 1, Size = UDim2.new(0.58, 0, 0, 44), Visible = false })
	self.ModeBar = modeBar
	self.ModeLabel = C.Title(modeBar, "", { Size = UDim2.new(1, -210, 1, 0), TextSize = 14, TextColor3 = Theme.Colors.Cyan, TextWrapped = true }, 1.5)
	self.ConfirmButton = C.Button(modeBar, "CONFIRM", function()
		self:Confirm()
	end, { Kind = "Danger", Position = UDim2.new(1, -204, 0, 0), Size = UDim2.fromOffset(110, 44), TextSize = 16, Visible = false })
	self.CancelButton = C.Button(modeBar, "Cancel", function()
		self:SetMode("Browse")
	end, { Kind = "Secondary", Position = UDim2.new(1, -88, 0, 0), Size = UDim2.fromOffset(88, 44), TextSize = 16, Visible = false })

	local gridHolder = C.Scroll(unitsPage, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(0.58, 0, 1, -52 - 68) })
	C.Grid(gridHolder, UDim2.fromOffset(100, 124), 10)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 6), Parent = gridHolder })
	self.Grid = gridHolder

	-- Footer: big team actions on a darker band
	local footer = C.Frame(unitsPage, {
		BackgroundColor3 = Theme.Colors.Bg,
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.58, 0, 0, 64),
	})
	C.Corner(footer, Theme.Radius.Card)
	C.Frame(footer, { BackgroundColor3 = Theme.Colors.Line, Size = UDim2.new(1, 0, 0, 1.5) })
	local footerButtons = C.Frame(footer, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 52) })
	C.List(footerButtons, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center)
	C.Button(footerButtons, "Equip Best", function()
		State.Request("EquipBest")
	end, { Kind = "Primary", Size = UDim2.fromOffset(196, 52), TextSize = 22, LayoutOrder = 1 })
	C.Button(footerButtons, "Unequip All", function()
		State.Request("UnequipAll")
	end, { Kind = "Secondary", Size = UDim2.fromOffset(196, 52), TextSize = 22, LayoutOrder = 2 })

	self.Details = C.Frame(unitsPage, { Position = UDim2.new(0.6, 0, 0, 0), Size = UDim2.new(0.4, 0, 1, 0), BackgroundColor3 = Theme.Colors.Bg })
	C.Corner(self.Details, Theme.Radius.Card)
	C.Stroke(self.Details, Theme.Colors.Ink, Theme.Stroke.Card)
	C.Padding(self.Details, 14)
	tabs.Select("Units")
end

-- NEW badge -------------------------------------------------------------------------------------------------------

function InventoryController:TrackNew(data)
	local units = data.Inventory.Units
	if self.KnownUids == nil then
		-- First snapshot: everything owned before this session is "old".
		local known = {}
		for uid in units do
			known[uid] = true
		end
		self.KnownUids = known
		return
	end
	local known = self.KnownUids :: { [string]: boolean }
	local open = self.Controllers.UIController:IsOpen("Fighters")
	for uid in units do
		if not known[uid] then
			known[uid] = true
			if not open then
				self.NewUids[uid] = true
			end
		end
	end
	-- Sold / fused away before being seen: stop counting them.
	for uid in self.NewUids do
		if not units[uid] then
			self.NewUids[uid] = nil
		end
	end
	self:_publishBadge()
end

function InventoryController:NewCount(): number
	local count = 0
	for _ in self.NewUids do
		count += 1
	end
	return count
end

function InventoryController:ClearNew()
	self.NewUids = {}
	self:_publishBadge()
end

function InventoryController:_publishBadge()
	self.Controllers.UIController:SetMenuBadge("Fighters", self:NewCount())
end

function InventoryController:Start()
	self.Controllers.UIController.WindowChanged:Connect(function(name)
		if name == "Fighters" then
			self:ClearNew()
		end
	end)
	State.Observe({ "Inventory", "EquippedUnits", "Upgrades" }, function(data)
		self:TrackNew(data)
		if self.SelectedUid and not data.Inventory.Units[self.SelectedUid] then
			self.SelectedUid = nil
		end
		self:Render()
	end)
end

return InventoryController
