--[[
	ShopService
	In-game currency shop, Robux developer products and game passes.

	  Shop:BuyItem(player, shopItemId, quantity) -> (ok, granted | errorCode)
	  Shop:GetPerkValue(player, perkName, default) -> number
	      "*Multiplier" perks multiply across owned passes; other perks (e.g. ExtraEquipSlots) add up.
	  Shop:OwnsPass(player, passKey) -> boolean

	Robux safety (ProcessReceipt):
	  - Grants only for known, configured ProductIds.
	  - Each PurchaseId is recorded in PlayerData.ProcessedReceipts; a repeated receipt returns
	    PurchaseGranted without granting again (Roblox retries receipts until it gets PurchaseGranted).
	  - If the player's data isn't loaded the receipt is deferred (NotProcessedYet), never dropped.
	  - The profile is saved right after granting.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Shop = require(Shared.Config.Shop)
local Requirements = require(Shared.Modules.Requirements)
local Rewards = require(Shared.Modules.Rewards)
local TableUtil = require(Shared.Modules.TableUtil)
local Validate = require(Shared.Modules.Validate)
local Net = require(Shared.Remotes.Net)

local ShopService = {
	Name = "ShopService",
	Priority = 8,
}

local ownedPasses: { [any]: { [string]: boolean } } = {}

local DataService, EconomyService

-- Currency shop -------------------------------------------------------------------------------------------

function ShopService:BuyItem(player, shopItemId: string, quantity: number): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local item = Shop.GetItem(shopItemId)
	if not item then
		return false, "ShopItemNotFound"
	end
	if not Validate.Integer(quantity, 1, item.MaxPerPurchase) then
		return false, "InvalidAmount"
	end
	local ok = Requirements.Check(data, item.Requirements)
	if not ok then
		return false, "RequirementsNotMet"
	end
	local grants = {}
	for _ = 1, quantity do
		Rewards.Merge(grants, item.Grants)
	end
	return EconomyService:Purchase(player, { Currency = item.Currency, Amount = item.Price * quantity }, "Shop:" .. shopItemId, function()
		local granted, result = EconomyService:GrantRewards(player, grants, { Reason = "Shop:" .. shopItemId })
		if not granted then
			return false, result
		end
		return true, result
	end)
end

-- Game passes ---------------------------------------------------------------------------------------------

function ShopService:OwnsPass(player, passKey: string): boolean
	local owned = ownedPasses[player]
	return owned ~= nil and owned[passKey] == true
end

function ShopService:GetPerkValue(player, perkName: string, default: number): number
	local owned = ownedPasses[player]
	if not owned then
		return default
	end
	local multiplicative = string.sub(perkName, -10) == "Multiplier"
	local value = if multiplicative then 1 else 0
	local found = false
	for _, pass in Shop.GamePasses do
		if owned[pass.Id] and pass.Perks[perkName] then
			found = true
			if multiplicative then
				value *= pass.Perks[perkName]
			else
				value += pass.Perks[perkName]
			end
		end
	end
	return if found then value else default
end

function ShopService:_refreshPasses(player)
	local owned = {}
	for _, pass in Shop.GamePasses do
		if pass.PassId ~= 0 then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.PassId)
			if ok and result then
				owned[pass.Id] = true
			end
		end
	end
	ownedPasses[player] = owned
end

-- Developer products --------------------------------------------------------------------------------------

function ShopService:ProcessReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return NOT_YET
	end
	local data = DataService:GetData(player)
	if not data then
		return NOT_YET
	end
	local purchaseId = tostring(receiptInfo.PurchaseId)
	if table.find(data.ProcessedReceipts, purchaseId) then
		return GRANTED
	end
	local product = Shop.ProductsByProductId[receiptInfo.ProductId]
	if not product then
		warn("[ShopService] Receipt for unknown product " .. tostring(receiptInfo.ProductId))
		return NOT_YET
	end
	local ok, err = EconomyService:GrantRewards(player, product.Grants, { Reason = "Robux:" .. product.Id })
	if not ok then
		warn("[ShopService] Failed to grant product " .. product.Id .. ": " .. tostring(err))
		return NOT_YET
	end
	TableUtil.PushBounded(data.ProcessedReceipts, purchaseId, GameConfig.Data.ProcessedReceiptLimit)
	DataService:SaveProfile(player, false)
	Net.Fire(player, "Notify", { Text = "Purchase complete: " .. product.Name, Kind = "Success" })
	return GRANTED
end

-- Lifecycle -----------------------------------------------------------------------------------------------

function ShopService:Init(services)
	self.Services = services
	DataService = services.DataService
	EconomyService = services.EconomyService

	Net.Handle("BuyShopItem", function(player, shopItemId, quantity)
		if not Validate.String(shopItemId, 32) then
			return false, "InvalidArguments"
		end
		return self:BuyItem(player, shopItemId, quantity or 1)
	end, { RateLimit = 4 })
end

function ShopService:Start()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local ok, decision = pcall(self.ProcessReceipt, self, receiptInfo)
		if ok then
			return decision
		end
		warn("[ShopService] ProcessReceipt error: " .. tostring(decision))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			for _, pass in Shop.GamePasses do
				if pass.PassId == passId then
					ownedPasses[player] = ownedPasses[player] or {}
					ownedPasses[player][pass.Id] = true
					DataService:MarkDirty(player, "EquippedUnits")
				end
			end
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		self:_refreshPasses(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self._refreshPasses, self, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ownedPasses[player] = nil
	end)
end

-- Test helper
function ShopService:_setOwnedPasses(player, passes: { [string]: boolean })
	ownedPasses[player] = passes
end

return ShopService
