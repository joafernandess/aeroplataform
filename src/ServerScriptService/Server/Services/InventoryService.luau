--[[
	InventoryService
	Stackable items (potions, materials, evolution items, boosts, consumables) and unit storage capacity.
	Units themselves are managed by UnitService; this service answers "is there room?".

	  Inventory:AddItem(player, itemId, count, reason) -> (ok, newCount | errorCode)
	  Inventory:RemoveItem(player, itemId, count) -> (ok, newCount | errorCode)
	  Inventory:GetItemCount(player, itemId) -> number
	  Inventory:HasItems(player, { [itemId] = count }) -> boolean
	  Inventory:RemoveItems(player, { [itemId] = count }) -> (ok, errorCode?)   all-or-nothing
	  Inventory:UseItem(player, itemId, targetUid?, count?) -> (ok, result | errorCode)
	  Inventory:SellItem(player, itemId, count) -> (ok, yen | errorCode)
	  Inventory:SetItemLocked(player, itemId, locked)
	  Inventory:GetUnitCapacity(player) / GetUnitCount(player) / HasUnitSpace(player, n)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Features = require(Shared.Config.Features)
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Config.Items)
local Formulas = require(Shared.Modules.Formulas)
local Signal = require(Shared.Modules.Signal)
local TableUtil = require(Shared.Modules.TableUtil)
local Validate = require(Shared.Modules.Validate)
local Net = require(Shared.Remotes.Net)

local InventoryService = {
	Name = "InventoryService",
	Priority = 4,
}

InventoryService.ItemAdded = Signal.new() -- (player, itemId, count, reason)
InventoryService.ItemUsed = Signal.new() -- (player, itemId, count)

local MAX_USE_PER_REQUEST = 100

local DataService, EconomyService

local function validCount(count: any): boolean
	return Validate.Integer(count, 1, 1e6)
end

function InventoryService:GetItemCount(player, itemId: string): number
	local data = DataService:GetData(player)
	return if data then data.Inventory.Items[itemId] or 0 else 0
end

function InventoryService:AddItem(player, itemId: string, count: number, reason: string?): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local def = Items.Get(itemId)
	if not def then
		return false, "ItemNotFound"
	end
	if not validCount(count) then
		return false, "InvalidAmount"
	end
	local current = data.Inventory.Items[itemId] or 0
	if current >= def.MaxStack then
		return false, "StackLimit"
	end
	local added = math.min(count, def.MaxStack - current)
	data.Inventory.Items[itemId] = current + added
	DataService:MarkDirty(player, "Inventory")
	InventoryService.ItemAdded:Fire(player, itemId, added, reason)
	return true, current + added
end

function InventoryService:RemoveItem(player, itemId: string, count: number): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	if not validCount(count) then
		return false, "InvalidAmount"
	end
	local current = data.Inventory.Items[itemId] or 0
	if current < count then
		return false, "ItemNotFound"
	end
	local remaining = current - count
	data.Inventory.Items[itemId] = if remaining > 0 then remaining else nil
	DataService:MarkDirty(player, "Inventory")
	return true, remaining
end

function InventoryService:HasItems(player, required: { [string]: number }?): boolean
	if not required then
		return true
	end
	for itemId, count in required do
		if self:GetItemCount(player, itemId) < count then
			return false
		end
	end
	return true
end

function InventoryService:RemoveItems(player, required: { [string]: number }?): (boolean, string?)
	if not required then
		return true, nil
	end
	if not self:HasItems(player, required) then
		return false, "MissingMaterials"
	end
	for itemId, count in required do
		self:RemoveItem(player, itemId, count)
	end
	return true, nil
end

function InventoryService:SetItemLocked(player, itemId: string, locked: boolean): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	if not Items.IsValid(itemId) then
		return false, "ItemNotFound"
	end
	data.Inventory.LockedItems[itemId] = if locked then true else nil
	DataService:MarkDirty(player, "Inventory")
	return true, locked
end

function InventoryService:SellItem(player, itemId: string, count: number): (boolean, any)
	if not Features.Items then
		return false, "FeatureDisabled"
	end
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local def = Items.Get(itemId)
	if not def or not def.SellValue then
		return false, "ItemNotFound"
	end
	if data.Inventory.LockedItems[itemId] then
		return false, "ItemLocked"
	end
	local ok, err = self:RemoveItem(player, itemId, count)
	if not ok then
		return false, err
	end
	local yen = def.SellValue * count
	EconomyService:Add(player, "Yen", yen, "SellItem")
	return true, yen
end

-- Item effects ------------------------------------------------------------------------------
-- Each handler validates, applies the effect for `count` items and returns (ok, result|errorCode).
-- The item is only consumed when the handler succeeds.
InventoryService.EffectHandlers = {
	UnitXP = function(self, player, def, targetUid, count)
		if not Validate.UnitUid(targetUid) then
			return false, "InvalidArguments"
		end
		return self.Services.UnitService:AddUnitXP(player, targetUid, def.Effect.Amount * count)
	end,
	TraitReroll = function(self, player, _def, targetUid, count)
		if count ~= 1 then
			return false, "InvalidAmount"
		end
		if not Validate.UnitUid(targetUid) then
			return false, "InvalidArguments"
		end
		return self.Services.UnitService:RerollTrait(player, targetUid)
	end,
	Boost = function(self, player, def, _targetUid, count)
		local effect = def.Effect
		return self.Services.BoostService:Activate(player, effect.Stat, effect.Multiplier, effect.Duration * count)
	end,
	Currency = function(_self, player, def, _targetUid, count)
		local effect = def.Effect
		return EconomyService:Add(player, effect.Currency, effect.Amount * count, "UseItem:" .. def.Id)
	end,
}

function InventoryService:UseItem(player, itemId: string, targetUid: string?, count: number?): (boolean, any)
	if not Features.Items then
		return false, "FeatureDisabled"
	end
	local amount = count or 1
	if not Validate.Integer(amount, 1, MAX_USE_PER_REQUEST) then
		return false, "InvalidAmount"
	end
	local def = Items.Get(itemId)
	if not def then
		return false, "ItemNotFound"
	end
	if not def.Usable or not def.Effect then
		return false, "ItemNotUsable"
	end
	if self:GetItemCount(player, itemId) < amount then
		return false, "ItemNotFound"
	end
	local handler = InventoryService.EffectHandlers[def.Effect.Type]
	if not handler then
		warn("[InventoryService] No effect handler for " .. tostring(def.Effect.Type))
		return false, "ItemNotUsable"
	end
	local ok, result = handler(self, player, def, targetUid, amount)
	if not ok then
		return false, result
	end
	self:RemoveItem(player, itemId, amount)
	InventoryService.ItemUsed:Fire(player, itemId, amount)
	return true, result
end

-- Unit capacity -------------------------------------------------------------------------------

function InventoryService:GetUnitCapacity(player): number
	local data = DataService:GetData(player)
	if not data then
		return 0
	end
	return Formulas.UnitStorage(data.Upgrades.UnitStorage or 0)
end

function InventoryService:GetUnitCount(player): number
	local data = DataService:GetData(player)
	return if data then TableUtil.Count(data.Inventory.Units) else 0
end

function InventoryService:HasUnitSpace(player, count: number?): boolean
	return self:GetUnitCount(player) + (count or 1) <= self:GetUnitCapacity(player)
end

-- Lifecycle -------------------------------------------------------------------------------------

function InventoryService:Init(services)
	self.Services = services
	DataService = services.DataService
	EconomyService = services.EconomyService

	DataService.ProfileLoaded:Connect(function(player, profile)
		if profile.IsNew and Features.Items then
			for itemId, count in GameConfig.Start.StarterItems do
				self:AddItem(player, itemId, count, "Starter")
			end
		end
	end)

	Net.Handle("UseItem", function(player, itemId, targetUid, count)
		if not Validate.String(itemId, 64) or (targetUid ~= nil and not Validate.UnitUid(targetUid)) then
			return false, "InvalidArguments"
		end
		if count ~= nil and not Validate.Integer(count, 1, MAX_USE_PER_REQUEST) then
			return false, "InvalidAmount"
		end
		return self:UseItem(player, itemId, targetUid, count)
	end)

	Net.Handle("SellItem", function(player, itemId, count)
		if not Validate.String(itemId, 64) or not Validate.Integer(count, 1, 1e6) then
			return false, "InvalidArguments"
		end
		return self:SellItem(player, itemId, count)
	end)

	Net.Handle("LockItem", function(player, itemId, locked)
		if not Validate.String(itemId, 64) or not Validate.Boolean(locked) then
			return false, "InvalidArguments"
		end
		return self:SetItemLocked(player, itemId, locked)
	end)
end

return InventoryService
