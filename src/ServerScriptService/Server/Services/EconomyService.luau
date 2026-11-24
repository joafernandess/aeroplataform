--[[
	EconomyService
	The ONLY place allowed to change a player's currencies. Every other service calls this API.

	  Economy:GetBalance(player, currency) -> number
	  Economy:CanAfford(player, currency, amount) -> boolean
	  Economy:Add(player, currency, amount, reason) -> (ok, newBalance | errorCode)
	  Economy:Remove(player, currency, amount, reason) -> (ok, newBalance | errorCode)
	  Economy:Purchase(player, cost, reason, onPaid) -> (ok, result | errorCode)
	      Charges `cost` ({ Currency, Amount }), runs onPaid(); if onPaid errors or returns false the
	      payment is refunded automatically. This keeps "pay then grant" atomic from the player's view.
	  Economy:GrantRewards(player, rewards, options) -> (ok, granted | errorCode)
	      Grants the shared reward format. options.OnceKey makes the grant idempotent (persisted), which
	      protects quests/achievements/receipts from being claimed twice. options.ApplyMultipliers applies
	      Yen/XP/Gold multipliers from BoostService.

	Signals:
	  Economy.CurrencyChanged (player, currency, delta, newBalance, reason)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Modules.Signal)
local TableUtil = require(Shared.Modules.TableUtil)
local Clock = require(Shared.Modules.Clock)
local Rewards = require(Shared.Modules.Rewards)
local Validate = require(Shared.Modules.Validate)

local ECONOMY = GameConfig.Economy

local EconomyService = {
	Name = "EconomyService",
	Priority = 2,
}

EconomyService.CurrencyChanged = Signal.new()

local DataService

local function isCurrency(currency: any): boolean
	return type(currency) == "string" and table.find(ECONOMY.Currencies, currency) ~= nil
end

local function normaliseAmount(amount: any): number?
	if not Validate.Number(amount, 0, ECONOMY.MaxSingleTransaction) then
		return nil
	end
	local whole = math.floor(amount)
	if whole <= 0 then
		return nil
	end
	return whole
end

local function log(data, currency: string, delta: number, balance: number, reason: string)
	if ECONOMY.UnloggedReasons[reason] then
		return
	end
	TableUtil.PushBounded(data.TransactionLog, {
		Time = Clock.Now(),
		Currency = currency,
		Delta = delta,
		Balance = balance,
		Reason = reason,
	}, GameConfig.Data.TransactionLogLimit)
end

function EconomyService:GetBalance(player, currency: string): number
	local data = DataService:GetData(player)
	if not data or not isCurrency(currency) then
		return 0
	end
	return data.Currencies[currency] or 0
end

function EconomyService:CanAfford(player, currency: string, amount: number): boolean
	local whole = normaliseAmount(amount)
	if not whole then
		return amount == 0
	end
	return self:GetBalance(player, currency) >= whole
end

function EconomyService:Add(player, currency: string, amount: number, reason: string): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	if not isCurrency(currency) then
		return false, "InvalidCurrency"
	end
	local whole = normaliseAmount(amount)
	if not whole then
		return false, "InvalidAmount"
	end
	local before = data.Currencies[currency] or 0
	local after = math.min(before + whole, ECONOMY.MaxBalance)
	local delta = after - before
	data.Currencies[currency] = after
	if currency == "Yen" then
		data.Stats.TotalYenEarned += delta
	end
	log(data, currency, delta, after, reason or "Unknown")
	DataService:MarkDirty(player, "Currencies")
	EconomyService.CurrencyChanged:Fire(player, currency, delta, after, reason)
	return true, after
end

function EconomyService:Remove(player, currency: string, amount: number, reason: string): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	if not isCurrency(currency) then
		return false, "InvalidCurrency"
	end
	local whole = normaliseAmount(amount)
	if not whole then
		return false, "InvalidAmount"
	end
	local before = data.Currencies[currency] or 0
	if before < whole then
		return false, "NotEnoughCurrency"
	end
	local after = before - whole
	data.Currencies[currency] = after
	log(data, currency, -whole, after, reason or "Unknown")
	DataService:MarkDirty(player, "Currencies")
	EconomyService.CurrencyChanged:Fire(player, currency, -whole, after, reason)
	return true, after
end

function EconomyService:Purchase(player, cost: { Currency: string, Amount: number }, reason: string, onPaid: () -> (boolean, any)): (boolean, any)
	if type(cost) ~= "table" then
		return false, "InvalidArguments"
	end
	local free = cost.Amount == 0
	if not free then
		local ok, err = self:Remove(player, cost.Currency, cost.Amount, reason)
		if not ok then
			return false, err
		end
	end
	local success, granted, result = pcall(onPaid)
	if success and granted then
		return true, result
	end
	if not free then
		self:Add(player, cost.Currency, cost.Amount, "Refund:" .. reason)
	end
	if not success then
		warn(("[EconomyService] Purchase '%s' failed for %s and was refunded: %s"):format(reason, player.Name, tostring(granted)))
		return false, "InternalError"
	end
	return false, if type(result) == "string" then result else "InternalError"
end

--[[
	Multi-currency variant of Purchase: costs = { [currency] = amount }. Every balance is checked before
	anything is charged, so a failure never leaves the player half-charged.
]]
function EconomyService:PurchaseBundle(player, costs: { [string]: number }, reason: string, onPaid: () -> (boolean, any)): (boolean, any)
	if type(costs) ~= "table" then
		return false, "InvalidArguments"
	end
	local charges = {}
	for currency, amount in costs do
		if amount and amount > 0 then
			if not isCurrency(currency) or not normaliseAmount(amount) then
				return false, "InvalidArguments"
			end
			if not self:CanAfford(player, currency, amount) then
				return false, "NotEnoughCurrency"
			end
			charges[currency] = math.floor(amount)
		end
	end
	local charged = {}
	for currency, amount in charges do
		local ok, err = self:Remove(player, currency, amount, reason)
		if not ok then
			for refundCurrency, refundAmount in charged do
				self:Add(player, refundCurrency, refundAmount, "Refund:" .. reason)
			end
			return false, err
		end
		charged[currency] = amount
	end
	local success, granted, result = pcall(onPaid)
	if success and granted then
		return true, result
	end
	for currency, amount in charged do
		self:Add(player, currency, amount, "Refund:" .. reason)
	end
	if not success then
		warn(("[EconomyService] Purchase '%s' failed for %s and was refunded: %s"):format(reason, player.Name, tostring(granted)))
		return false, "InternalError"
	end
	return false, if type(result) == "string" then result else "InternalError"
end

--[[
	Grants a reward bundle. Order matters for safety: everything is validated first, the once-key is
	written before granting (so a crash mid-grant can never be replayed into a double claim), then each
	part is granted.
]]
function EconomyService:GrantRewards(player, rewards: { [string]: any }, options: { Reason: string, OnceKey: string?, ApplyMultipliers: boolean? }): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local valid, why = Rewards.IsValid(rewards)
	if not valid then
		warn(("[EconomyService] Invalid rewards for '%s': %s"):format(options.Reason, tostring(why)))
		return false, "InternalError"
	end
	if options.OnceKey then
		if data.ClaimedRewards[options.OnceKey] then
			return false, "AlreadyClaimed"
		end
		data.ClaimedRewards[options.OnceKey] = true
	end

	local services = self.Services
	local granted = rewards
	if options.ApplyMultipliers and services.BoostService then
		granted = Rewards.Scale(rewards, {
			Yen = services.BoostService:GetMultiplier(player, "Yen"),
			Gold = services.BoostService:GetMultiplier(player, "Gold"),
			XP = services.BoostService:GetMultiplier(player, "XP"),
		})
	end

	for _, currency in ECONOMY.Currencies do
		local amount = granted[currency]
		if amount and amount >= 1 then
			self:Add(player, currency, amount, options.Reason)
		end
	end
	if granted.XP and granted.XP >= 1 and services.ProgressionService then
		services.ProgressionService:AddPlayerXP(player, granted.XP)
	end
	if granted.Items and services.InventoryService then
		for itemId, count in granted.Items do
			services.InventoryService:AddItem(player, itemId, count, options.Reason)
		end
	end
	if granted.Units and services.UnitService then
		for _, unitId in granted.Units do
			-- Reward units may exceed storage: the player paid/earned them, we never discard them.
			services.UnitService:CreateUnit(player, unitId, { Source = options.Reason, IgnoreCapacity = true })
		end
	end
	return true, granted
end

function EconomyService:Init(services)
	self.Services = services
	DataService = services.DataService
end

return EconomyService
