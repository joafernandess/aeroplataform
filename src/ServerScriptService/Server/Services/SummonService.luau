--[[
	SummonService
	Server-authoritative gacha. The client only sends (bannerId, count); every roll happens here.

	Algorithm per pull:
	  1. Start from the banner's rarity weights (Config/Banners).
	  2. Multiply weights of rarities listed in LuckAffects by the player's Luck multiplier
	     (upgrades x boosts x events x game passes — see BoostService).
	  3. Pity: for every pity rule, if this pull would be the Threshold-th pull without reaching that rarity,
	     the pull is restricted to that rarity or better. Counters reset when the rarity (or better) is hit.
	  4. x10 guarantee: if the first 9 pulls of a x10 produced nothing >= MultiGuarantee, the 10th is
	     restricted to MultiGuarantee or better.
	  5. A unit is picked uniformly from the banner pool of the chosen rarity.

	Auto-delete settings (AutoDeleteCommon/AutoDeleteRare) convert those pulls straight into Yen.
	The client receives the full result list, ready for a reveal animation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Banners = require(Shared.Config.Banners)
local Features = require(Shared.Config.Features)
local Rarities = require(Shared.Config.Rarities)
local Units = require(Shared.Config.Units)
local Formulas = require(Shared.Modules.Formulas)
local Requirements = require(Shared.Modules.Requirements)
local TableUtil = require(Shared.Modules.TableUtil)
local Signal = require(Shared.Modules.Signal)
local Clock = require(Shared.Modules.Clock)
local RNG = require(Shared.Modules.RNG)
local Validate = require(Shared.Modules.Validate)
local Net = require(Shared.Remotes.Net)

local SummonService = {
	Name = "SummonService",
	Priority = 10,
}

SummonService.Summoned = Signal.new() -- (player, bannerId, count, results)
SummonService.Random = nil :: any

local AUTO_DELETE_SETTINGS = { Common = "AutoDeleteCommon", Rare = "AutoDeleteRare" }

local DataService, EconomyService, UnitService, InventoryService, BoostService

-- Pure roll helpers (exposed for tests) ------------------------------------------------------------

-- Returns the rarity weights after luck, optionally restricted to rarities >= minRarity.
function SummonService.BuildWeights(banner, luck: number, minRarity: string?): { [string]: number }
	local weights = {}
	for rarity, weight in banner.Rates do
		if weight > 0 and (minRarity == nil or Rarities.AtLeast(rarity, minRarity)) then
			local w = weight
			if banner.LuckAffects and banner.LuckAffects[rarity] then
				w *= math.max(luck, 0)
			end
			weights[rarity] = w
		end
	end
	if next(weights) == nil and minRarity then
		-- Banner has nothing at/above minRarity: fall back to its best rarity.
		local best, bestOrder = nil, -1
		for rarity, weight in banner.Rates do
			if weight > 0 and Rarities.GetOrder(rarity) > bestOrder then
				best, bestOrder = rarity, Rarities.GetOrder(rarity)
			end
		end
		if best then
			weights[best] = 1
		end
	end
	return weights
end

-- Rolls one rarity, applying and updating pity counters in place.
function SummonService.RollRarity(generator, banner, pity: { [string]: number }, luck: number, minRarity: string?): string
	local floor = minRarity
	for _, rule in banner.Pity do
		local counter = pity[rule.Rarity] or 0
		if counter + 1 >= rule.Threshold then
			if floor == nil or Rarities.GetOrder(rule.Rarity) > Rarities.GetOrder(floor) then
				floor = rule.Rarity
			end
		end
	end
	local rarity = RNG.WeightedPick(generator, SummonService.BuildWeights(banner, luck, floor)) :: string
	for _, rule in banner.Pity do
		if Rarities.AtLeast(rarity, rule.Rarity) then
			pity[rule.Rarity] = 0
		else
			pity[rule.Rarity] = (pity[rule.Rarity] or 0) + 1
		end
	end
	return rarity
end

-- Rolls `count` units. Returns { { UnitId, Rarity } } and mutates `pity`.
function SummonService.RollMany(generator, banner, pity: { [string]: number }, luck: number, count: number)
	local results = {}
	local guaranteeMet = banner.MultiGuarantee == nil or count < Banners.GetMultiCount(banner)
	for i = 1, count do
		local minRarity = nil
		if not guaranteeMet and i == count then
			minRarity = banner.MultiGuarantee
		end
		local rarity = SummonService.RollRarity(generator, banner, pity, luck, minRarity)
		if banner.MultiGuarantee and Rarities.AtLeast(rarity, banner.MultiGuarantee) then
			guaranteeMet = true
		end
		local unitId = RNG.PickFromList(generator, banner.Pool[rarity]) :: string
		table.insert(results, { UnitId = unitId, Rarity = rarity })
	end
	return results
end

-- Availability ------------------------------------------------------------------------------------------

function SummonService:CanUseBanner(player, banner): (boolean, string?)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	if not Features.MultipleWorlds and banner.World ~= GameConfig.Start.World then
		return false, "BannerUnavailable"
	end
	local now = Clock.Now()
	if (banner.StartsAt and now < banner.StartsAt) or (banner.EndsAt and now > banner.EndsAt) then
		return false, "BannerUnavailable"
	end
	local ok = Requirements.Check(data, banner.Requirements)
	if not ok then
		return false, "RequirementsNotMet"
	end
	return true, nil
end

function SummonService:GetCost(banner, count: number): number
	return if count == Banners.GetMultiCount(banner) and count > 1 then banner.CostMulti else banner.CostSingle * count
end

-- Summon ---------------------------------------------------------------------------------------------------

function SummonService:Summon(player, bannerId: string, count: number): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local banner = Banners.Get(bannerId)
	if not banner then
		return false, "BannerNotFound"
	end
	if not Banners.IsAllowedCount(banner, count) then
		return false, "InvalidAmount"
	end
	local usable, why = self:CanUseBanner(player, banner)
	if not usable then
		return false, why
	end
	-- Conservative capacity check: assume every pull is kept.
	if not InventoryService:HasUnitSpace(player, count) then
		return false, "InventoryFull"
	end

	local cost = self:GetCost(banner, count)
	return EconomyService:Purchase(player, { Currency = banner.Currency, Amount = cost }, "Summon:" .. bannerId, function()
		local pity = data.SummonPity[bannerId]
		if not pity then
			pity = {}
			data.SummonPity[bannerId] = pity
		end
		local luck = BoostService:GetMultiplier(player, "Luck")
		local rolls = SummonService.RollMany(self.Random, banner, pity, luck, count)

		local results = {}
		local autoDeleteYen = 0
		local now = Clock.Now()
		for _, roll in rolls do
			local settingKey = AUTO_DELETE_SETTINGS[roll.Rarity]
			local entry = { UnitId = roll.UnitId, Rarity = roll.Rarity, AutoDeleted = false }
			if settingKey and data.Settings[settingKey] == true then
				-- Auto-sold pulls still count as discovered for the Index.
				UnitService.MarkDiscovered(player, data, roll.UnitId)
				entry.AutoDeleted = true
				autoDeleteYen += Formulas.UnitSellValue(roll.Rarity, 1, 0)
			else
				local ok, unit = UnitService:CreateUnit(player, roll.UnitId, { Source = "Summon:" .. bannerId, IgnoreCapacity = true })
				if ok then
					entry.Uid = unit.Uid
					entry.Trait = unit.Trait
				end
			end
			table.insert(results, entry)
			TableUtil.PushBounded(data.SummonHistory, { Time = now, Banner = bannerId, UnitId = roll.UnitId, Rarity = roll.Rarity }, GameConfig.Data.SummonHistoryLimit)
		end
		if autoDeleteYen > 0 then
			EconomyService:Add(player, "Yen", autoDeleteYen, "AutoDelete")
		end
		data.Stats.TotalSummons += count
		DataService:MarkDirty(player, "SummonPity")
		DataService:MarkDirty(player, "SummonHistory")
		DataService:MarkDirty(player, "Stats")
		SummonService.Summoned:Fire(player, bannerId, count, results)
		return true, { Banner = bannerId, Cost = cost, Currency = banner.Currency, Results = results, Pity = table.clone(pity) }
	end)
end

function SummonService:Init(services)
	self.Services = services
	DataService = services.DataService
	EconomyService = services.EconomyService
	UnitService = services.UnitService
	InventoryService = services.InventoryService
	BoostService = services.BoostService
	if not SummonService.Random then
		SummonService.Random = RNG.new()
	end

	Net.Handle("Summon", function(player, bannerId, count)
		if not Validate.String(bannerId, 32) or not Validate.Integer(count, 1, 10) then
			return false, "InvalidArguments"
		end
		return self:Summon(player, bannerId, count)
	end, { RateLimit = 2, Burst = 4 })
end

-- Keep Units referenced so config validation errors surface when this service loads.
local _ = Units

return SummonService
