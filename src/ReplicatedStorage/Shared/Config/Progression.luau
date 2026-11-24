--[[
	Progression
	Player level curve, level-up rewards and purchasable permanent upgrades.
	Formulas that use these numbers live in Shared/Modules/Formulas so client UI and server agree.
]]

export type UpgradeDef = {
	Id: string,
	Name: string,
	Description: string,
	Currency: string,
	BaseCost: number,
	CostGrowth: number,
	MaxLevel: number,
	PerLevel: number, -- meaning depends on the upgrade (multiplier step, slots, storage...)
	Requirements: { [string]: any }?,
}

local Progression = {}

Progression.Player = {
	MaxLevel = 150,
	XPBase = 100,
	XPExponent = 1.5,
	-- Rewards granted every time the player reaches a multiple of `Every`.
	LevelRewards = {
		{ Every = 5, Rewards = { Gems = 25 } },
		{ Every = 25, Rewards = { Gems = 100, Items = { TraitCrystal = 1 } } },
	},
}

Progression.Unit = {
	XPBase = 50,
	XPExponent = 1.35,
}

-- Permanent upgrades bought in the Upgrade menu. The level is stored in PlayerData.Upgrades[Id].
-- PlayerData.Damage mirrors Upgrades.Damage for compatibility with the original data spec.
Progression.Upgrades = {
	Damage = { Id = "Damage", Name = "Damage", Description = "+5% damage per level", Currency = "Yen", BaseCost = 200, CostGrowth = 1.32, MaxLevel = 100, PerLevel = 0.05 },
	Yen = { Id = "Yen", Name = "Yen Gain", Description = "+5% Yen per level", Currency = "Yen", BaseCost = 300, CostGrowth = 1.35, MaxLevel = 100, PerLevel = 0.05 },
	Luck = { Id = "Luck", Name = "Summon Luck", Description = "+2% rare summon luck per level", Currency = "Gold", BaseCost = 20, CostGrowth = 1.25, MaxLevel = 50, PerLevel = 0.02 },
	EquipSlots = { Id = "EquipSlots", Name = "Equip Slots", Description = "+1 equipped unit", Currency = "Gems", BaseCost = 500, CostGrowth = 2, MaxLevel = 5, PerLevel = 1 },
	UnitStorage = { Id = "UnitStorage", Name = "Unit Storage", Description = "+25 unit storage", Currency = "Gems", BaseCost = 150, CostGrowth = 1.4, MaxLevel = 16, PerLevel = 25 },
	XP = { Id = "XP", Name = "Experience", Description = "+5% XP per level", Currency = "Gold", BaseCost = 15, CostGrowth = 1.3, MaxLevel = 50, PerLevel = 0.05 },
} :: { [string]: UpgradeDef }

Progression.UpgradeOrder = { "Damage", "Yen", "XP", "Luck", "EquipSlots", "UnitStorage" }

function Progression.GetUpgrade(id: string): UpgradeDef?
	return Progression.Upgrades[id]
end

return Progression
