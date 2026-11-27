--[[
	ShopController
	"Shop" window: the game's Game Passes (Config/Shop.GamePasses). One card per pass with a real PassId: its image
	(from Roblox), name, what it gives, the Robux price and a BUY button (MarketplaceService prompt) — or OWNED.
	The perks themselves are applied by the server (ShopService checks UserOwnsGamePassAsync and the purchase
	event). Passes whose PassId is still 0 (not created on the Roblox website yet) are not shown; with none
	configured the window says so instead of showing fake offers.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)

local ShopController = {
	Name = "ShopController",
	Priority = 25,
}

local CARD = UDim2.fromOffset(222, 262)
local P = Theme.Colors

ShopController.Owned = {} :: { [number]: boolean } -- passId -> owned (checked with Roblox)
ShopController.Info = {} :: { [number]: any } -- passId -> MarketplaceService product info (price, image)

-- Passes that exist on Roblox (PassId set).
function ShopController.Passes()
	local list = {}
	for _, pass in Shop.GamePasses do
		if pass.PassId ~= 0 then
			table.insert(list, pass)
		end
	end
	return list
end

-- Asks Roblox for prices / images and ownership (yields; failures just leave the defaults).
function ShopController:Refresh()
	local player = Players.LocalPlayer
	for _, pass in ShopController.Passes() do
		local okInfo, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass.PassId, Enum.InfoType.GamePass)
		if okInfo and type(info) == "table" then
			self.Info[pass.PassId] = info
		end
		local okOwned, owned = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.PassId)
		if okOwned then
			self.Owned[pass.PassId] = owned == true
		end
	end
	self:Render()
end

function ShopController:_card(pass, order: number)
	local info = self.Info[pass.PassId]
	local owned = self.Owned[pass.PassId] == true
	local card = C.Frame(self.List, { Name = pass.Id, BackgroundColor3 = P.PanelAlt, LayoutOrder = order })
	C.Corner(card, Theme.Radius.Card)
	C.Stroke(card, if owned then P.Yellow else P.Ink, if owned then 3 else Theme.Stroke.Card)
	-- The pass's own image (uploaded with the pass on Roblox), on a dark well with a gold rim.
	local well = C.Frame(card, { Name = "Art", BackgroundColor3 = P.Bg, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 104) })
	C.Corner(well, 10)
	C.Stroke(well, P.Yellow, 2)
	if info and info.IconImageAssetId and info.IconImageAssetId ~= 0 then
		C.Create("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Image = "rbxassetid://" .. tostring(info.IconImageAssetId),
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(92, 92),
			Parent = well,
		})
	end
	C.Title(card, pass.Name, { Name = "PassName", Position = UDim2.fromOffset(12, 120), Size = UDim2.new(1, -24, 0, 26), TextSize = 21, TextTruncate = Enum.TextTruncate.AtEnd }, 2.5)
	C.Label(card, pass.Description, {
		Name = "Description",
		Position = UDim2.fromOffset(12, 148),
		Size = UDim2.new(1, -24, 0, 40),
		TextSize = 14,
		TextColor3 = P.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local price = if info and info.PriceInRobux then "R$ " .. NumberFormat.Abbreviate(info.PriceInRobux) else "BUY"
	local button = C.Button(card, if owned then "OWNED" else price, if owned
		then nil
		else function()
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.PassId)
		end, {
		Name = "Buy",
		Kind = if owned then "Dark" else "Gold",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 48),
		TextSize = 20,
		Confirm = false,
	})
	if owned then
		C.SetDisabled(button, true)
	end
end

function ShopController:Render()
	if not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	local passes = ShopController.Passes()
	self.List.Visible = #passes > 0
	self.Empty.Visible = #passes == 0
	for i, pass in passes do
		self:_card(pass, i)
	end
end

function ShopController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Shop", "Shop", UDim2.fromOffset(760, 520), function()
		self:Render()
		task.spawn(self.Refresh, self)
	end)
	self.List = C.Scroll(self.Window.Content, { Name = "Passes" })
	C.Grid(self.List, CARD, 14)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = self.List })
	-- Shown while no pass has been created on Roblox yet (honest empty state, no fake offers).
	self.Empty = C.EmptyState(self.Window.Content, "shop", "Game passes coming soon", "Game passes will be sold here once they are released.")
	self.Empty.Visible = false
end

function ShopController:Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and player == Players.LocalPlayer then
			self.Owned[passId] = true
			self:Render()
		end
	end)
end

return ShopController
