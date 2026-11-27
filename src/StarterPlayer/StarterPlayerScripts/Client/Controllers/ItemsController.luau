--[[
	ItemsController
	"Items" window (the right menu's Inventory button; fighters have their own Fighters window; the Yen counter is
	always on the HUD):
	  grid of item cards (icon tinted by rarity, quantity, name, gold outline on the selected one) and a
	          details panel for the selected item: name, rarity, description, quantity and its actions —
	          Use / Sell 1 / Lock (server-validated: UseItem, SellItem, LockItem)
	While Features.Items is off the game has no items, so the section says so instead of showing an empty grid.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Features = require(Shared.Config.Features)
local Items = require(Shared.Config.Items)
local Rarities = require(Shared.Config.Rarities)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local ItemsController = {
	Name = "ItemsController",
	Priority = 34,
}

ItemsController.SelectedItem = nil :: string?

local CARD = UDim2.fromOffset(96, 112)

local P = Theme.Colors

-- Owned item ids (known to the config), sorted by rarity then name.
function ItemsController.OwnedItems(data): { string }
	local ids = {}
	for itemId, count in data.Inventory.Items do
		if Items.Get(itemId) and count > 0 then
			table.insert(ids, itemId)
		end
	end
	table.sort(ids, function(a, b)
		local da, db = Items.Get(a), Items.Get(b)
		local ra, rb = Rarities.GetOrder(da.Rarity), Rarities.GetOrder(db.Rarity)
		if ra ~= rb then
			return ra > rb
		end
		return da.Name < db.Name
	end)
	return ids
end

function ItemsController:_card(itemId: string, count: number, order: number)
	local def = Items.Get(itemId)
	local rarity = Theme.Rarity(def.Rarity)
	local card = C.Create("TextButton", { Name = itemId, Text = "", AutoButtonColor = false, BackgroundColor3 = P.PanelAlt, LayoutOrder = order, Parent = self.Grid })
	C.Corner(card, Theme.Radius.Card)
	C.Stroke(card, if itemId == self.SelectedItem then P.Select else P.Ink, if itemId == self.SelectedItem then 3 else 2.5)
	local well = C.Frame(card, { BackgroundColor3 = P.Bg, Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 66) })
	C.Corner(well, 10)
	C.Stroke(well, rarity, 2)
	C.Icon(well, "inventory", { Size = 42, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Color = rarity })
	C.Number(well, "x" .. NumberFormat.Abbreviate(count), {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -2),
		Size = UDim2.fromOffset(60, 18),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	C.Title(card, def.Name, {
		Font = Theme.Fonts.Body,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -8, 0, 28),
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, 1.5)
	card.Activated:Connect(function()
		self.SelectedItem = itemId
		self:Render()
	end)
end

function ItemsController:RenderDetails(data)
	C.Clear(self.Details)
	local itemId = self.SelectedItem
	local def = itemId and Items.Get(itemId)
	local count = itemId and data.Inventory.Items[itemId] or 0
	if not def or count <= 0 then
		C.Label(self.Details, "Select an item to see what it does.", { TextColor3 = P.TextDim, TextWrapped = true, Size = UDim2.new(1, 0, 0, 44) })
		return
	end
	C.Title(self.Details, def.Name, { Name = "ItemName", Size = UDim2.new(1, 0, 0, 28), TextSize = 22 }, 2.5)
	C.Title(self.Details, string.upper(def.Rarity), { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = Theme.Rarity(def.Rarity) }, 1.5)
	C.Label(self.Details, def.Description, { Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 60), TextSize = 15, TextColor3 = P.Ice, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	C.Label(self.Details, ("Owned: %s"):format(NumberFormat.Abbreviate(count)), { Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextColor3 = P.Cyan })
	local buttons = C.Frame(self.Details, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 152) })
	C.List(buttons, Enum.FillDirection.Vertical, 8)
	if def.Usable and not def.TargetsUnit then
		C.Button(buttons, "Use", function()
			task.spawn(function()
				local response = State.Request("UseItem", itemId)
				if response.ok and State.Notify then
					State.Notify("Used " .. def.Name, "Success")
				end
			end)
		end, { Name = "Use", Kind = "Primary", Size = UDim2.new(1, 0, 0, 44), TextSize = 18, LayoutOrder = 1, Confirm = false })
	elseif def.TargetsUnit then
		C.Label(buttons, "Use it on a fighter (Fighters menu).", { Size = UDim2.new(1, 0, 0, 22), TextSize = 13, TextColor3 = P.TextDim, LayoutOrder = 1 })
	end
	local locked = data.Inventory.LockedItems[itemId] == true
	if def.SellValue and not locked then
		C.Button(buttons, ("Sell 1 (+%s)"):format(NumberFormat.Abbreviate(def.SellValue)), function()
			task.spawn(State.Request, "SellItem", itemId, 1)
		end, { Name = "Sell", Kind = "Danger", Size = UDim2.new(1, 0, 0, 44), TextSize = 16, LayoutOrder = 2 })
	end
	C.Button(buttons, if locked then "Unlock" else "Lock", function()
		task.spawn(State.Request, "LockItem", itemId, not locked)
	end, { Name = "Lock", Kind = "Dark", Icon = "lock", IconSize = 16, Size = UDim2.new(1, 0, 0, 44), TextSize = 16, LayoutOrder = 3, Confirm = false })
end

function ItemsController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	if not Features.Items then
		self.ItemsPane.Visible = false
		self.List.Visible = true
		C.EmptyState(self.List, "inventory", "No items in this game yet", "Items are not part of the game yet. Fighters are in the Fighters menu.", { LayoutOrder = 1 })
		return
	end
	local ids = ItemsController.OwnedItems(data)
	if #ids == 0 then
		self.ItemsPane.Visible = false
		self.List.Visible = true
		C.EmptyState(self.List, "inventory", "No items yet", "Defeat enemies and complete quests to find some!", { LayoutOrder = 1 })
		return
	end
	self.List.Visible = false
	self.ItemsPane.Visible = true
	if not (self.SelectedItem and table.find(ids, self.SelectedItem)) then
		self.SelectedItem = ids[1]
	end
	C.Clear(self.Grid)
	for i, itemId in ids do
		self:_card(itemId, data.Inventory.Items[itemId], i)
	end
	self:RenderDetails(data)
end

function ItemsController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Items", "Inventory", UDim2.fromOffset(760, 520), function()
		self:Render()
	end)
	local content = self.Window.Content
	-- Empty / unavailable states
	self.List = C.Scroll(content, { Name = "ItemsList" })
	C.List(self.List, Enum.FillDirection.Vertical, 8)
	-- Grid + details
	local pane = C.Frame(content, { Name = "ItemsPane", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	self.ItemsPane = pane
	self.Grid = C.Scroll(pane, { Name = "Grid", Size = UDim2.new(0.64, 0, 1, 0) })
	C.Grid(self.Grid, CARD, 10)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = self.Grid })
	local details = C.Frame(pane, { Name = "Details", BackgroundColor3 = P.Bg, Position = UDim2.new(0.66, 0, 0, 0), Size = UDim2.new(0.34, 0, 1, 0) })
	C.Corner(details, Theme.Radius.Card)
	C.Stroke(details, P.Ink, Theme.Stroke.Card)
	C.Padding(details, 12)
	self.Details = details
end

function ItemsController:Start()
	State.Observe({ "Inventory" }, function()
		self:Render()
	end)
end

return ItemsController
