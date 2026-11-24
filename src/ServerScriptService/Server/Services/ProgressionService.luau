--[[
	ProgressionService
	Player level/XP and permanent upgrades.

	  Progression:AddPlayerXP(player, amount) -> (ok, { Level, Experience, LevelsGained })
	  Progression:BuyUpgrade(player, upgradeId) -> (ok, newLevel | errorCode)
	  Progression:GetUpgradeLevel(player, upgradeId) -> number

	Level rewards (Config/Progression.Player.LevelRewards) are granted with a persisted OnceKey per level,
	so they can never be granted twice even if a level is re-reached through data repair.
	Unit levels live in UnitService (AddUnitXP); evolution in UnitService:Evolve.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Features = require(Shared.Config.Features)
local Progression = require(Shared.Config.Progression)
local Formulas = require(Shared.Modules.Formulas)
local Requirements = require(Shared.Modules.Requirements)
local Signal = require(Shared.Modules.Signal)
local Validate = require(Shared.Modules.Validate)
local Net = require(Shared.Remotes.Net)

local ProgressionService = {
	Name = "ProgressionService",
	Priority = 6,
}

ProgressionService.LevelUp = Signal.new() -- (player, newLevel, levelsGained)
ProgressionService.UpgradePurchased = Signal.new() -- (player, upgradeId, newLevel)

local DataService, EconomyService

function ProgressionService:_grantLevelRewards(player, level: number)
	for index, rule in Progression.Player.LevelRewards do
		if level % rule.Every == 0 then
			EconomyService:GrantRewards(player, rule.Rewards, {
				Reason = "LevelReward",
				OnceKey = ("Level:%d:%d"):format(level, index),
			})
		end
	end
end

function ProgressionService:AddPlayerXP(player, amount: number): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	if not Validate.Number(amount, 0) then
		return false, "InvalidAmount"
	end
	local maxLevel = Progression.Player.MaxLevel
	if data.Level >= maxLevel then
		return true, { Level = data.Level, Experience = data.Experience, LevelsGained = 0 }
	end
	data.Experience += math.floor(amount)
	local gained = 0
	while data.Level < maxLevel do
		local needed = Formulas.PlayerXPToNext(data.Level)
		if data.Experience < needed then
			break
		end
		data.Experience -= needed
		data.Level += 1
		gained += 1
		self:_grantLevelRewards(player, data.Level)
	end
	if data.Level >= maxLevel then
		data.Experience = 0
	end
	DataService:MarkDirty(player, "Experience")
	if gained > 0 then
		DataService:MarkDirty(player, "Level")
		Net.Fire(player, "LevelUp", { Level = data.Level })
		ProgressionService.LevelUp:Fire(player, data.Level, gained)
	end
	return true, { Level = data.Level, Experience = data.Experience, LevelsGained = gained }
end

function ProgressionService:GetUpgradeLevel(player, upgradeId: string): number
	local data = DataService:GetData(player)
	return if data then data.Upgrades[upgradeId] or 0 else 0
end

function ProgressionService:BuyUpgrade(player, upgradeId: string): (boolean, any)
	if not Features.Upgrades then
		return false, "FeatureDisabled"
	end
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local def = Progression.GetUpgrade(upgradeId)
	if not def then
		return false, "InvalidArguments"
	end
	local ok = Requirements.Check(data, def.Requirements)
	if not ok then
		return false, "RequirementsNotMet"
	end
	local current = data.Upgrades[upgradeId] or 0
	local cost = Formulas.UpgradeCost(upgradeId, current)
	if not cost then
		return false, "MaxUpgrade"
	end
	return EconomyService:Purchase(player, { Currency = def.Currency, Amount = cost }, "Upgrade:" .. upgradeId, function()
		data.Upgrades[upgradeId] = current + 1
		if upgradeId == "Damage" then
			data.Damage = data.Upgrades.Damage
			DataService:MarkDirty(player, "Damage")
		end
		DataService:MarkDirty(player, "Upgrades")
		ProgressionService.UpgradePurchased:Fire(player, upgradeId, current + 1)
		return true, current + 1
	end)
end

function ProgressionService:Init(services)
	self.Services = services
	DataService = services.DataService
	EconomyService = services.EconomyService

	Net.Handle("BuyUpgrade", function(player, upgradeId)
		if not Validate.String(upgradeId, 32) then
			return false, "InvalidArguments"
		end
		return self:BuyUpgrade(player, upgradeId)
	end, { RateLimit = 5 })
end

return ProgressionService
