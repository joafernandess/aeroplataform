--[[
	ShopController
	Currency shop (Config/Shop.Items) grouped by category, plus Robux products/passes when configured.
	While Features.Shop is off the window stays reachable from the Shop button but only says the shop is closed
	(the server answers FeatureDisabled to purchases anyway).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Shop = require(Shared.Config.Shop)
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

function ShopController:Buy(itemId: string, quantity: number)
	local response = State.Request("BuyShopItem", itemId, quantity)
	if response.ok and State.Notify then
		State.Notify("Purchased: " .. Rewards.Describe(response.data), "Success")
	end
end

function ShopController:Render()
	if not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	if not Features.Shop then
		C.EmptyState(self.List, "shop", "The shop is closed", "The shop isn't open yet. Defeat enemies for Yen and spend it on the summon orb.", { LayoutOrder = 0 })
		return
	end
	for i, item in Shop.Items do
		local row = C.Row(self.List, { Size = UDim2.new(1, -8, 0, 56), LayoutOrder = i })
		C.Label(row, ("[%s] %s"):format(item.Category, item.Name), { Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -260, 0, 24), Font = Theme.Fonts.Bold })
		C.Label(row, ("%s %s"):format(NumberFormat.Abbreviate(item.Price), item.Currency), { Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -260, 0, 20), TextSize = 14, TextColor3 = Theme.Currency(item.Currency) })
		local buttons = C.Frame(row, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(240, 38) })
		C.List(buttons, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
		C.Button(buttons, "Buy 1", function()
			self:Buy(item.Id, 1)
		end, { Kind = "Primary", Size = UDim2.fromOffset(110, 44), TextSize = 18, LayoutOrder = 1 })
		local bulk = math.min(10, item.MaxPerPurchase)
		if bulk > 1 then
			C.Button(buttons, "Buy " .. bulk, function()
				self:Buy(item.Id, bulk)
			end, { Size = UDim2.fromOffset(110, 36), LayoutOrder = 2 })
		end
	end
	local order = #Shop.Items
	for _, product in Shop.DevProducts do
		if product.ProductId ~= 0 then
			order += 1
			C.Button(self.List, ("R$ %s"):format(product.Name), function()
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.ProductId)
			end, { Kind = "Primary", Size = UDim2.new(1, -8, 0, 48), LayoutOrder = order })
		end
	end
	for _, pass in Shop.GamePasses do
		if pass.PassId ~= 0 then
			order += 1
			C.Button(self.List, ("Pass: %s — %s"):format(pass.Name, pass.Description), function()
				MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.PassId)
			end, { Kind = "Accent", Size = UDim2.new(1, -8, 0, 48), LayoutOrder = order, TextSize = 15 })
		end
	end
end

function ShopController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Shop", "Shop", nil, function()
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 6)
end

return ShopController
