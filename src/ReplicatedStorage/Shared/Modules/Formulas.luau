--[[
	Formulas
	Every balance formula in one place, shared by server (authoritative) and client (display only).
]]

local Config = script.Parent.Parent.Config
local GameConfig = require(Config.GameConfig)
local Progression = require(Config.Progression)
local Rarities = require(Config.Rarities)

local Formulas = {}

-- Player ------------------------------------------------------------------------------
function Formulas.PlayerXPToNext(level: number): number
	local p = Progression.Player
	return math.floor(p.XPBase * level ^ p.XPExponent)
end

-- Units --------------------------------------------------------------------------------
function Formulas.UnitXPToNext(level: number, rarityId: string): number
	local rarity = Rarities.Get(rarityId)
	local mult = if rarity then rarity.XPCurveMultiplier else 1
	local u = Progression.Unit
	return math.floor(u.XPBase * level ^ u.XPExponent * mult)
end

function Formulas.UnitMaxLevel(rarityId: string): number
	local rarity = Rarities.Get(rarityId)
	return if rarity then rarity.MaxLevel else 1
end

function Formulas.LevelDamageMultiplier(level: number): number
	return 1 + (math.max(level, 1) - 1) * GameConfig.Units.LevelDamageBonus
end

function Formulas.StarDamageMultiplier(stars: number): number
	return 1 + math.clamp(stars, 0, GameConfig.Units.MaxStars) * GameConfig.Units.StarDamageBonus
end

function Formulas.UnitSellValue(rarityId: string, level: number, stars: number): number
	local rarity = Rarities.Get(rarityId)
	local base = if rarity then rarity.SellValue else 1
	return math.floor(base * (1 + (level - 1) * 0.05) * (1 + stars * 0.5))
end

function Formulas.UnitFeedXP(rarityId: string, level: number): number
	local rarity = Rarities.Get(rarityId)
	local base = if rarity then rarity.FeedXP else 10
	return math.floor(base * (1 + (level - 1) * 0.1))
end

-- Combat -------------------------------------------------------------------------------
-- Defense reduces damage by defense / (defense + 1000), capped at 75%. Every hit deals at least 1.
function Formulas.DamageAfterDefense(damage: number, defense: number): number
	local reduction = math.min(0.75, math.max(defense, 0) / (math.max(defense, 0) + 1000))
	return math.max(1, math.floor(damage * (1 - reduction)))
end

-- Upgrades -----------------------------------------------------------------------------
function Formulas.UpgradeCost(upgradeId: string, currentLevel: number): number?
	local def = Progression.GetUpgrade(upgradeId)
	if not def or currentLevel >= def.MaxLevel then
		return nil
	end
	return math.floor(def.BaseCost * def.CostGrowth ^ currentLevel)
end

-- Multiplier granted by a "percentage" upgrade at the given level (Damage, Yen, Luck, XP).
function Formulas.UpgradeMultiplier(upgradeId: string, level: number): number
	local def = Progression.GetUpgrade(upgradeId)
	if not def then
		return 1
	end
	return 1 + math.clamp(level, 0, def.MaxLevel) * def.PerLevel
end

function Formulas.EquipSlots(upgradeLevel: number, bonusSlots: number?): number
	local def = Progression.Upgrades.EquipSlots
	local slots = GameConfig.Units.BaseEquipSlots + math.clamp(upgradeLevel, 0, def.MaxLevel) * def.PerLevel + (bonusSlots or 0)
	return math.min(slots, GameConfig.Units.MaxEquipSlots)
end

function Formulas.UnitStorage(upgradeLevel: number): number
	local def = Progression.Upgrades.UnitStorage
	local storage = GameConfig.Units.BaseUnitStorage + math.clamp(upgradeLevel, 0, def.MaxLevel) * def.PerLevel
	return math.min(storage, GameConfig.Units.MaxUnitStorage)
end

return Formulas
