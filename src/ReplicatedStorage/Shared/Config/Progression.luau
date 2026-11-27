--[[
	Progression
	Player level curve, level-up rewards, purchasable permanent upgrades and milestone upgrades (the "Upgrades"
	window: permanent bonuses unlocked by playing — see Progression.Milestones below).
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

-- Milestone upgrades ----------------------------------------------------------------------------------------------
--[[
	The Upgrades window. Each milestone is a permanent bonus unlocked by playing, in tiers per category:
	  Locked      the previous tier of its category hasn't been claimed yet
	  InProgress  unlocked, requirement not reached
	  Claimable   requirement reached: the player claims it (ClaimMilestone, server-validated)
	  Completed   claimed: its bonus is active for good (PlayerData.Milestones[Id] = true)
	Bonuses are additive per stat (Yen / Luck / Damage) and applied by BoostService:GetMultiplier.
	To add a milestone: add an entry (Category + Tier + Bonus + Requirement). Names ("Yen VI") and requirement texts
	are generated, nothing is hard-coded in the UI.
]]

export type MilestoneDef = {
	Id: string,
	Category: string,
	Tier: number,
	Bonus: number, -- e.g. 0.10 = +10%
	Requirement: { Type: string, Goal: number },
}

Progression.MilestoneCategories = {
	{ Id = "Yen", Name = "Yen", Stat = "Yen", Icon = "yen", Color = { 255, 194, 26 } },
	{ Id = "Luck", Name = "Luck", Stat = "Luck", Icon = "luck", Color = { 62, 212, 94 } },
	{ Id = "Damage", Name = "Damage", Stat = "Damage", Icon = "kills", Color = { 255, 69, 69 } },
}

Progression.Milestones = {
	{ Id = "YEN_1", Category = "Yen", Tier = 1, Bonus = 0.05, Requirement = { Type = "Kills", Goal = 50 } },
	{ Id = "YEN_2", Category = "Yen", Tier = 2, Bonus = 0.05, Requirement = { Type = "YenEarned", Goal = 10000 } },
	{ Id = "YEN_3", Category = "Yen", Tier = 3, Bonus = 0.05, Requirement = { Type = "MainQuests", Goal = 3 } },
	{ Id = "YEN_4", Category = "Yen", Tier = 4, Bonus = 0.10, Requirement = { Type = "BossKills", Goal = 3 } },
	{ Id = "YEN_5", Category = "Yen", Tier = 5, Bonus = 0.10, Requirement = { Type = "YenEarned", Goal = 250000 } },
	{ Id = "YEN_6", Category = "Yen", Tier = 6, Bonus = 0.10, Requirement = { Type = "MainQuests", Goal = 5 } },
	{ Id = "LUCK_1", Category = "Luck", Tier = 1, Bonus = 0.05, Requirement = { Type = "Playtime", Goal = 2 * 3600 } },
	{ Id = "LUCK_2", Category = "Luck", Tier = 2, Bonus = 0.10, Requirement = { Type = "Playtime", Goal = 10 * 3600 } },
	{ Id = "LUCK_3", Category = "Luck", Tier = 3, Bonus = 0.15, Requirement = { Type = "Playtime", Goal = 25 * 3600 } },
	{ Id = "DMG_1", Category = "Damage", Tier = 1, Bonus = 0.05, Requirement = { Type = "Kills", Goal = 500 } },
	{ Id = "DMG_2", Category = "Damage", Tier = 2, Bonus = 0.10, Requirement = { Type = "Summons", Goal = 50 } },
	{ Id = "DMG_3", Category = "Damage", Tier = 3, Bonus = 0.15, Requirement = { Type = "BossKills", Goal = 25 } },
} :: { MilestoneDef }

local function count(map): number
	local n = 0
	for _, v in map or {} do
		if v then
			n += 1
		end
	end
	return n
end

-- Requirement types: how progress is read from PlayerData and how the requirement is described.
Progression.MilestoneRequirements = {
	Kills = { Text = "Defeat %s enemies.", Get = function(data)
		return data.Stats.TotalKills or 0
	end },
	BossKills = { Text = "Defeat %s bosses.", Get = function(data)
		return data.Stats.BossKills or 0
	end },
	YenEarned = { Text = "Earn %s Yen in total.", Get = function(data)
		return data.Stats.TotalYenEarned or 0
	end },
	Summons = { Text = "Summon %s fighters.", Get = function(data)
		return data.Stats.TotalSummons or 0
	end },
	MainQuests = { Text = "Complete %s main quests.", Get = function(data)
		return count(data.Quests and data.Quests.MainCompleted)
	end },
	Discovered = { Text = "Discover %s fighters.", Get = function(data)
		return count(data.Discovered)
	end },
	Playtime = { Text = "Play for %s.", Hours = true, Get = function(data)
		return data.Playtime or 0
	end },
}

Progression.MilestonesById = {} :: { [string]: MilestoneDef }
local categoryIds = {}
for _, category in Progression.MilestoneCategories do
	categoryIds[category.Id] = category
end
for _, def in Progression.Milestones do
	assert(not Progression.MilestonesById[def.Id], "Duplicate milestone " .. def.Id)
	assert(categoryIds[def.Category], "Milestone " .. def.Id .. " has an unknown category")
	assert(Progression.MilestoneRequirements[def.Requirement.Type], "Milestone " .. def.Id .. " has an unknown requirement type")
	assert(def.Requirement.Goal > 0 and def.Bonus > 0, "Milestone " .. def.Id .. " needs a positive goal and bonus")
	Progression.MilestonesById[def.Id] = def
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

function Progression.GetMilestone(id: string): MilestoneDef?
	return Progression.MilestonesById[id]
end

function Progression.GetMilestoneCategory(id: string)
	return categoryIds[id]
end

-- "Yen VI"
function Progression.MilestoneName(def: MilestoneDef): string
	return categoryIds[def.Category].Name .. " " .. (ROMAN[def.Tier] or tostring(def.Tier))
end

-- The milestone of the same category one tier below (nil for tier 1).
function Progression.PreviousMilestone(def: MilestoneDef): MilestoneDef?
	for _, other in Progression.Milestones do
		if other.Category == def.Category and other.Tier == def.Tier - 1 then
			return other
		end
	end
	return nil
end

-- Current progress value (`playtime` overrides data.Playtime with the live value on the server).
function Progression.MilestoneProgress(data, def: MilestoneDef, playtime: number?): number
	if def.Requirement.Type == "Playtime" and playtime then
		return playtime
	end
	return Progression.MilestoneRequirements[def.Requirement.Type].Get(data)
end

-- "Locked" | "InProgress" | "Claimable" | "Completed"
function Progression.MilestoneState(data, def: MilestoneDef, playtime: number?): string
	local claimed = data.Milestones or {}
	if claimed[def.Id] then
		return "Completed"
	end
	local previous = Progression.PreviousMilestone(def)
	if previous and not claimed[previous.Id] then
		return "Locked"
	end
	if Progression.MilestoneProgress(data, def, playtime) >= def.Requirement.Goal then
		return "Claimable"
	end
	return "InProgress"
end

-- Total additive bonus of the claimed milestones for a stat ("Yen" / "Luck" / "Damage").
function Progression.MilestoneBonus(data, stat: string): number
	local total = 0
	for id in data.Milestones or {} do
		local def = Progression.MilestonesById[id]
		if def and categoryIds[def.Category].Stat == stat then
			total += def.Bonus
		end
	end
	return total
end

return Progression
