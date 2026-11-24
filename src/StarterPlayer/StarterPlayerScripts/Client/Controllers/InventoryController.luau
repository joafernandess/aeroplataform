--[[
	InventoryController
	"Units" window: unit grid + embedded details panel (UnitDetailsController) and an Items tab.
	Modes:
	  Browse  - click a card to inspect it
	  Fuse    - pick fodder for the selected target, then confirm (FuseUnits)
	  Delete  - multi-select units to sell (DeleteUnits)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Config.Units)
local Items = require(Shared.Config.Items)
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
InventoryController.Tab = "Units"

local SORTS = { "Power", "Rarity", "Level" }

local function sortedUnits(data, sortBy: string)
	local list = {}
	for uid, unit in data.Inventory.Units do
		local def = Units.Get(unit.UnitId)
		local stats = UnitStats.Compute(unit)
		if def and stats then
			table.insert(list, { Uid = uid, Unit = unit, Def = def, Power = stats.Power })
		end
	end
	table.sort(list, function(a, b)
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
	self.UnitsPage.Visible = self.Tab == "Units"
	self.ItemsPage.Visible = self.Tab == "Items"
	if self.Tab == "Items" then
		self:RenderItems(data)
		return
	end

	local count = TableUtil.Count(data.Inventory.Units)
	local capacity = Formulas.UnitStorage(data.Upgrades.UnitStorage or 0)
	self.CapacityLabel.Text = ("%d / %d units"):format(count, capacity)
	self.CapacityLabel.TextColor3 = if count >= capacity then Theme.Colors.Bad else Theme.Colors.TextDim
	self.SortButton.Text = "Sort: " .. self.SortBy

	local modeText = {
		Browse = "",
		Fuse = "FUSE: select fodder units, then Confirm",
		Delete = "DELETE: select units to sell, then Confirm",
	}
	self.ModeLabel.Text = modeText[self.Mode]
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
			card.BackgroundColor3 = Theme.Colors.Accent
		elseif entry.Uid == self.SelectedUid then
			card.BackgroundColor3 = Theme.Colors.Stroke
		end
	end

	self.Controllers.UnitDetailsController:Render(self.Details, self.SelectedUid)
end

function InventoryController:RenderItems(data)
	C.Clear(self.ItemList)
	local ids = {}
	for itemId in data.Inventory.Items do
		table.insert(ids, itemId)
	end
	table.sort(ids)
	if #ids == 0 then
		C.Label(self.ItemList, "No items yet. Defeat enemies and complete quests to find some!", { TextColor3 = Theme.Colors.TextDim })
	end
	for i, itemId in ids do
		local def = Items.Get(itemId)
		if def then
			local countValue = data.Inventory.Items[itemId]
			local row = C.Frame(self.ItemList, { Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = Theme.Colors.PanelLight, LayoutOrder = i })
			C.Corner(row, UDim.new(0, 8))
			C.Stroke(row, Theme.Rarity(def.Rarity), 1.5)
			C.Label(row, ("%s  x%d"):format(def.Name, countValue), { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -300, 0, 22), Font = Theme.Fonts.Bold, TextColor3 = Theme.Rarity(def.Rarity) })
			C.Label(row, def.Description, { Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -300, 0, 20), TextSize = 13, TextColor3 = Theme.Colors.TextDim })
			local buttons = C.Frame(row, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(280, 36) })
			C.List(buttons, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
			local locked = data.Inventory.LockedItems[itemId] == true
			C.Button(buttons, if locked then "Unlock" else "Lock", function()
				State.Request("LockItem", itemId, not locked)
			end, { Size = UDim2.fromOffset(80, 34), TextSize = 13, LayoutOrder = 1 })
			if def.SellValue then
				C.Button(buttons, "Sell 1", function()
					State.Request("SellItem", itemId, 1)
				end, { Size = UDim2.fromOffset(80, 34), TextSize = 13, LayoutOrder = 2 })
			end
			if def.Usable and not def.TargetsUnit then
				C.Button(buttons, "Use", function()
					local response = State.Request("UseItem", itemId)
					if response.ok and State.Notify then
						State.Notify("Used " .. def.Name, "Success")
					end
				end, { Size = UDim2.fromOffset(80, 34), TextSize = 13, LayoutOrder = 3, BackgroundColor3 = Theme.Colors.Good })
			elseif def.TargetsUnit then
				C.Label(buttons, "Use from unit", { Size = UDim2.fromOffset(100, 34), TextSize = 12, TextColor3 = Theme.Colors.TextDim, LayoutOrder = 3 })
			end
		end
	end
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
	local window = controllers.UIController:CreateWindow("Inventory", "Units", UDim2.fromOffset(820, 520), function()
		self:Render()
	end)
	window.OnClose = function()
		self.Mode = "Browse"
		self.MultiSelect = {}
	end
	self.Window = window
	local content = window.Content

	local tabs = C.Tabs(content, { "Units", "Items" }, function(name)
		self.Tab = name
		self:Render()
	end)
	tabs.Frame.Size = UDim2.new(1, 0, 0, 34)

	-- Units page
	local unitsPage = C.Frame(content, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40) })
	self.UnitsPage = unitsPage
	local toolbar = C.Frame(unitsPage, { BackgroundTransparency = 1, Size = UDim2.new(0.58, 0, 0, 36) })
	C.List(toolbar, Enum.FillDirection.Horizontal, 6)
	C.Button(toolbar, "Equip Best", function()
		State.Request("EquipBest")
	end, { Size = UDim2.fromOffset(100, 32), TextSize = 13, LayoutOrder = 1, BackgroundColor3 = Theme.Colors.Good })
	self.SortButton = C.Button(toolbar, "Sort", function()
		local index = table.find(SORTS, self.SortBy) or 1
		self.SortBy = SORTS[index % #SORTS + 1]
		self:Render()
	end, { Size = UDim2.fromOffset(100, 32), TextSize = 13, LayoutOrder = 2 })
	C.Button(toolbar, "Mass Sell", function()
		self:SetMode(if self.Mode == "Delete" then "Browse" else "Delete")
	end, { Size = UDim2.fromOffset(90, 32), TextSize = 13, LayoutOrder = 3, BackgroundColor3 = Theme.Colors.Bad })
	self.CapacityLabel = C.Label(toolbar, "", { Size = UDim2.fromOffset(120, 32), TextSize = 13, LayoutOrder = 4, TextColor3 = Theme.Colors.TextDim })

	local modeBar = C.Frame(unitsPage, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(0.58, 0, 0, 30) })
	self.ModeLabel = C.Label(modeBar, "", { Size = UDim2.new(1, -170, 1, 0), TextSize = 12, TextColor3 = Theme.Colors.Accent, Font = Theme.Fonts.Bold, TextWrapped = true })
	self.ConfirmButton = C.Button(modeBar, "Confirm", function()
		self:Confirm()
	end, { Position = UDim2.new(1, -164, 0, 0), Size = UDim2.fromOffset(80, 28), TextSize = 13, BackgroundColor3 = Theme.Colors.Good, Visible = false })
	self.CancelButton = C.Button(modeBar, "Cancel", function()
		self:SetMode("Browse")
	end, { Position = UDim2.new(1, -80, 0, 0), Size = UDim2.fromOffset(80, 28), TextSize = 13, Visible = false })

	local gridHolder = C.Scroll(unitsPage, { Position = UDim2.fromOffset(0, 72), Size = UDim2.new(0.58, 0, 1, -72) })
	C.Grid(gridHolder, UDim2.fromOffset(104, 104), 6)
	self.Grid = gridHolder

	self.Details = C.Frame(unitsPage, { Position = UDim2.new(0.6, 0, 0, 0), Size = UDim2.new(0.4, 0, 1, 0), BackgroundColor3 = Theme.Colors.Background })
	C.Corner(self.Details)
	C.Padding(self.Details, 10)

	-- Items page
	local itemsPage = C.Frame(content, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), Visible = false })
	self.ItemsPage = itemsPage
	self.ItemList = C.Scroll(itemsPage)
	C.List(self.ItemList, Enum.FillDirection.Vertical, 6)

	tabs.Select("Units")
end

function InventoryController:Start()
	State.Observe({ "Inventory", "EquippedUnits", "Upgrades" }, function(data)
		if self.SelectedUid and not data.Inventory.Units[self.SelectedUid] then
			self.SelectedUid = nil
		end
		self:Render()
	end)
end

return InventoryController
