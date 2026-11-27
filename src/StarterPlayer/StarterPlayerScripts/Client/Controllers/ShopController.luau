--[[
	ShopController
	"Shop" window: the currency shop (Config/Shop.Items) as item cards grouped by category tabs, plus Robux
	products/passes when configured. Each card: icon, name, what it gives, price with the currency icon, Buy 1 and
	Buy 10. The wallet bar at the top shows the currencies the shop uses. Purchases go through BuyShopItem
	(server-validated: price, requirements, stack limits).

	While Features.Shop is off the window stays reachable from the Shop button but only says the shop is closed
	(the server answers FeatureDisabled to purchases anyway).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Shop = require(Shared.Config.Shop)
local Items = require(Shared.Config.Items)
local Features = require(Shared.Config.Features)
local Rewards = require(Shared.Modules.Rewards)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local ShopController = {
	Name = "ShopController",
	Priority = 25,
}

local CARD = UDim2.fromOffset(166, 214)
local ROBUX = "Robux"

local P = Theme.Colors

-- Category names in config order (+ "Robux" when a product or pass has a real id).
function ShopController.Categories(): { string }
	local list, seen = {}, {}
	for _, item in Shop.Items do
		if not seen[item.Category] then
			seen[item.Category] = true
			table.insert(list, item.Category)
		end
	end
	for _, product in Shop.DevProducts do
		if product.ProductId ~= 0 and not seen[ROBUX] then
			seen[ROBUX] = true
			table.insert(list, ROBUX)
		end
	end
	for _, pass in Shop.GamePasses do
		if pass.PassId ~= 0 and not seen[ROBUX] then
			seen[ROBUX] = true
			table.insert(list, ROBUX)
		end
	end
	return list
end

-- Currencies used by the shop's items (wallet bar).
local function shopCurrencies(): { string }
	local list, seen = {}, {}
	for _, item in Shop.Items do
		if not seen[item.Currency] then
			seen[item.Currency] = true
			table.insert(list, item.Currency)
		end
	end
	return list
end

-- The item a shop entry grants (for its rarity colour), if any.
local function grantedItem(item)
	for itemId in (item.Grants and item.Grants.Items) or {} do
		return Items.Get(itemId)
	end
	return nil
end

function ShopController:Buy(itemId: string, quantity: number)
	local response = State.Request("BuyShopItem", itemId, quantity)
	if response.ok and State.Notify then
		State.Notify("Purchased: " .. Rewards.Describe(response.data), "Success")
	end
end

function ShopController:_card(item, order: number)
	local def = grantedItem(item)
	local accent = if def then Theme.Rarity(def.Rarity) else P.Gold
	local card = C.Frame(self.Grid, { Name = item.Id, BackgroundColor3 = P.PanelAlt, LayoutOrder = order })
	C.Corner(card, Theme.Radius.Card)
	C.Stroke(card, P.Ink, Theme.Stroke.Card)
	local well = C.Frame(card, { Name = "IconWell", BackgroundColor3 = P.Bg, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 78) })
	C.Corner(well, 10)
	C.Stroke(well, accent, 2)
	C.Icon(well, if item.Category == "Materials" then "upgrades" else "inventory", {
		Size = 52,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = accent,
	})
	C.Title(card, item.Name, { Name = "ItemName", Position = UDim2.fromOffset(10, 92), Size = UDim2.new(1, -20, 0, 22), TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd }, 2)
	C.Label(card, Rewards.Describe(item.Grants), { Position = UDim2.fromOffset(10, 113), Size = UDim2.new(1, -20, 0, 18), TextSize = 13, TextColor3 = P.TextDim, TextTruncate = Enum.TextTruncate.AtEnd })
	-- Price: currency icon + amount (gold = currency)
	local price = C.Frame(card, { Name = "Price", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 132), Size = UDim2.new(1, -20, 0, 26) })
	C.Icon(price, Theme.Icons[item.Currency] or item.Currency, { Size = 22, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Color = Theme.Currency(item.Currency) })
	C.Number(price, NumberFormat.Abbreviate(item.Price), { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 20, TextColor3 = P.Gold })
	local buttons = C.Frame(card, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, 44) })
	C.List(buttons, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	local bulk = math.min(10, item.MaxPerPurchase)
	C.Button(buttons, "Buy", function()
		task.spawn(self.Buy, self, item.Id, 1)
	end, { Name = "Buy1", Kind = "Primary", Size = UDim2.fromOffset(if bulk > 1 then 72 else 150, 44), TextSize = 17, LayoutOrder = 1, Confirm = false })
	if bulk > 1 then
		C.Button(buttons, "x" .. bulk, function()
			task.spawn(self.Buy, self, item.Id, bulk)
		end, { Name = "BuyBulk", Kind = "Dark", Size = UDim2.fromOffset(72, 44), TextSize = 17, LayoutOrder = 2, Confirm = false })
	end
end

function ShopController:_robux(order: number)
	for _, product in Shop.DevProducts do
		if product.ProductId ~= 0 then
			order += 1
			C.Button(self.Grid, ("R$ %s"):format(product.Name), function()
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.ProductId)
			end, { Kind = "Primary", LayoutOrder = order, TextSize = 16 })
		end
	end
	for _, pass in Shop.GamePasses do
		if pass.PassId ~= 0 then
			order += 1
			C.Button(self.Grid, ("Pass: %s"):format(pass.Name), function()
				MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.PassId)
			end, { Kind = "Accent", LayoutOrder = order, TextSize = 15 })
		end
	end
end

function ShopController:RenderWallet()
	local data = State.Data
	C.Clear(self.Wallet)
	for i, currency in shopCurrencies() do
		local chip = C.Frame(self.Wallet, { Name = currency, BackgroundColor3 = P.Bg, Size = UDim2.fromOffset(132, 34), LayoutOrder = i })
		C.Corner(chip, UDim.new(0.5, 0))
		C.Stroke(chip, P.Gold, 2)
		C.Icon(chip, Theme.Icons[currency] or currency, { Size = 24, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Color = Theme.Currency(currency) })
		C.Number(chip, NumberFormat.Abbreviate(math.floor(data and data.Currencies[currency] or 0)), {
			Position = UDim2.fromOffset(36, 0),
			Size = UDim2.new(1, -44, 1, 0),
			TextSize = 18,
		})
	end
end

function ShopController:Render()
	if not self.Window.Frame.Visible then
		return
	end
	if not Features.Shop then
		self.Body.Visible = false
		C.Clear(self.Closed)
		C.EmptyState(self.Closed, "shop", "The shop is closed", "The shop isn't open yet. Defeat enemies for Yen and spend it on the summon orb.", { LayoutOrder = 0 })
		return
	end
	self.Body.Visible = true
	self:RenderWallet()
	C.Clear(self.Grid)
	local order = 0
	if self.Category == ROBUX then
		self:_robux(order)
		return
	end
	for _, item in Shop.Items do
		if item.Category == self.Category then
			order += 1
			self:_card(item, order)
		end
	end
end

function ShopController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Shop", "Shop", UDim2.fromOffset(800, 540), function()
		self:Render()
	end)
	local content = self.Window.Content
	-- Closed state (Features.Shop off)
	self.Closed = C.Scroll(content, { Name = "Closed" })
	C.List(self.Closed, Enum.FillDirection.Vertical, 8)
	self.List = self.Closed -- (tests / tools look for the window's list)
	-- Open shop: wallet bar, category tabs, card grid
	local body = C.Frame(content, { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	self.Body = body
	self.Wallet = C.Frame(body, { Name = "Wallet", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 0), Size = UDim2.new(1, -8, 0, 36) })
	C.List(self.Wallet, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right)
	local categories = ShopController.Categories()
	self.Category = categories[1]
	self.Grid = C.Scroll(body, { Name = "Grid", Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 1, -100) })
	C.Grid(self.Grid, CARD, 12)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = self.Grid })
	if #categories > 0 then
		local tabs = C.Tabs(body, categories, function(name)
			self.Category = name
			self:Render()
		end)
		tabs.Frame.Name = "Categories"
		tabs.Frame.Position = UDim2.fromOffset(4, 46)
		self.Tabs = tabs
		tabs.Select(self.Category)
	end
end

function ShopController:Start()
	State.Observe({ "Currencies" }, function()
		if self.Window.Frame.Visible and Features.Shop then
			self:RenderWallet()
		end
	end)
end

return ShopController
