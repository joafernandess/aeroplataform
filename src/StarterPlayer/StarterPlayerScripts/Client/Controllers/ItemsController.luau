--[[
	ItemsController
	"Items" window (the right menu's Inventory button; fighters have their own Fighters window):
	  Wallet  every currency the game currently uses, abbreviated (live)
	  Items   potions, boosts and materials with Lock / Sell / Use (server-validated: LockItem, SellItem, UseItem)
	While Features.Items is off the game has no items, so the section says so instead of showing an empty list.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Features = require(Shared.Config.Features)
local Items = require(Shared.Config.Items)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local ItemsController = {
	Name = "ItemsController",
	Priority = 34,
}

local P = Theme.Colors

-- Currencies shown in the wallet (Yen only in the base game).
function ItemsController.WalletCurrencies(): { string }
	local list = {}
	for _, currency in GameConfig.Economy.Currencies do
		if currency == "Yen" or Features.PremiumCurrencies then
			table.insert(list, currency)
		end
	end
	return list
end

function ItemsController:RenderWallet(data, order: number): number
	C.Section(self.List, "Wallet", order)
	local wallet = C.Frame(self.List, { Name = "Wallet", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 64), LayoutOrder = order + 1 })
	C.List(wallet, Enum.FillDirection.Horizontal, 10)
	for i, currency in ItemsController.WalletCurrencies() do
		local tile, value = C.StatTile(wallet, currency, NumberFormat.Abbreviate(math.floor(data.Currencies[currency] or 0)), {
			Name = currency,
			Size = UDim2.fromOffset(160, 64),
			LayoutOrder = i,
		})
		value.Position = UDim2.fromOffset(44, 22)
		value.Size = UDim2.new(1, -50, 0, 32)
		C.Icon(tile, Theme.Icons[currency] or currency, { Size = 28, Position = UDim2.fromOffset(10, 24), Color = Theme.Currency(currency) })
	end
	return order + 2
end

function ItemsController:RenderItems(data, order: number)
	C.Section(self.List, "Items", order)
	order += 1
	if not Features.Items then
		C.EmptyState(self.List, "inventory", "No items in this game yet", "Items are not part of the game yet. Fighters are in the Fighters menu.", { LayoutOrder = order })
		return
	end
	local ids = {}
	for itemId in data.Inventory.Items do
		if Items.Get(itemId) then
			table.insert(ids, itemId)
		end
	end
	table.sort(ids)
	if #ids == 0 then
		C.EmptyState(self.List, "inventory", "No items yet", "Defeat enemies and complete quests to find some!", { LayoutOrder = order })
		return
	end
	for i, itemId in ids do
		local def = Items.Get(itemId)
		local countValue = data.Inventory.Items[itemId]
		local row = C.Row(self.List, { Name = itemId, Size = UDim2.new(1, -8, 0, 62), LayoutOrder = order + i })
		local strip = C.Frame(row, { BackgroundColor3 = Theme.Rarity(def.Rarity), Position = UDim2.fromOffset(8, 10), Size = UDim2.fromOffset(5, 42) })
		C.Corner(strip, UDim.new(0.5, 0))
		C.Title(row, ("%s  x%s"):format(def.Name, NumberFormat.Abbreviate(countValue)), { Position = UDim2.fromOffset(22, 6), Size = UDim2.new(1, -330, 0, 26), TextSize = 18 })
		C.Label(row, def.Description, { Position = UDim2.fromOffset(22, 32), Size = UDim2.new(1, -330, 0, 22), TextSize = 15, TextColor3 = P.TextDim })
		local buttons = C.Frame(row, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(300, 44) })
		C.List(buttons, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right)
		local locked = data.Inventory.LockedItems[itemId] == true
		C.Button(buttons, if locked then "Unlock" else "Lock", function()
			State.Request("LockItem", itemId, not locked)
		end, { Kind = "Dark", Size = UDim2.fromOffset(88, 44), TextSize = 16, LayoutOrder = 1 })
		if def.SellValue then
			C.Button(buttons, "Sell 1", function()
				State.Request("SellItem", itemId, 1)
			end, { Kind = "Danger", Size = UDim2.fromOffset(88, 44), TextSize = 16, LayoutOrder = 2 })
		end
		if def.Usable and not def.TargetsUnit then
			C.Button(buttons, "Use", function()
				local response = State.Request("UseItem", itemId)
				if response.ok and State.Notify then
					State.Notify("Used " .. def.Name, "Success")
				end
			end, { Kind = "Primary", Size = UDim2.fromOffset(88, 44), TextSize = 16, LayoutOrder = 3 })
		elseif def.TargetsUnit then
			C.Label(buttons, "Use on a fighter", { Size = UDim2.fromOffset(104, 44), TextSize = 13, TextColor3 = P.TextDim, LayoutOrder = 3 })
		end
	end
end

function ItemsController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	local order = self:RenderWallet(data, 1)
	self:RenderItems(data, order)
end

function ItemsController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Items", "Inventory", UDim2.fromOffset(700, 500), function()
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 8)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 4), Parent = self.List })
end

function ItemsController:Start()
	State.Observe({ "Currencies", "Inventory" }, function()
		self:Render()
	end)
end

return ItemsController
