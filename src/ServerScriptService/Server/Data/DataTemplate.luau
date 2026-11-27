--[[
	DataTemplate
	Default profile for a brand-new player. Loaded profiles are reconciled against this template, so adding
	a new field here automatically back-fills it for existing players. Removing/renaming fields requires a
	migration (see Migrations.luau) and a DataVersion bump.

	All keys must be strings and arrays must be proper sequences — DataStores only accept JSON-compatible data.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DataTemplate = {}

DataTemplate.CurrentVersion = 1

function DataTemplate.Create()
	local start = GameConfig.Start
	return {
		DataVersion = DataTemplate.CurrentVersion,

		Level = 1,
		Experience = 0,
		Damage = 0, -- mirror of Upgrades.Damage

		Currencies = {
			Yen = start.Currencies.Yen or 0,
			Gems = start.Currencies.Gems or 0,
			Gold = start.Currencies.Gold or 0,
			Tokens = start.Currencies.Tokens or 0,
		},

		Upgrades = { Damage = 0, Yen = 0, Luck = 0, EquipSlots = 0, UnitStorage = 0, XP = 0 },

		Playtime = 0,
		CurrentWorld = start.World,
		UnlockedWorlds = { [start.World] = true },
		ClearedWorlds = {},

		Inventory = {
			Units = {},
			Items = {},
			LockedItems = {},
		},
		EquippedUnits = {},
		Discovered = {}, -- [unitId] = true for every fighter ever obtained (Index menu)
		NextUnitSerial = 1,

		Quests = {
			MainCurrent = "",
			MainCompleted = {},
			Active = {},
			DailyDay = 0,
		},
		Achievements = {},
		Milestones = {}, -- claimed milestone upgrades: [id] = true

		Settings = {
			MusicVolume = 0.5,
			SFXVolume = 0.5,
			DamageNumbers = true,
			LowGraphics = false,
			ShowOtherUnits = true,
			AutoDeleteCommon = false,
			AutoDeleteRare = false,
			LastSeenUpdate = "", -- UpdateLog entry id the player last opened
		},

		Stats = {
			TotalKills = 0,
			BossKills = 0,
			TotalSummons = 0,
			TotalDamage = 0,
			TotalYenEarned = 0,
			RaidsCompleted = 0,
			UnitsEvolved = 0,
			UnitsFused = 0,
			UnitsObtained = 0,
		},

		SummonPity = {},
		SummonHistory = {},
		TransactionLog = {},
		ClaimedRewards = {},
		ActiveBoosts = {},
		RaidCooldowns = {},
		ProcessedReceipts = {},

		FirstJoin = 0,
		LastJoin = 0,
	}
end

-- Keys that are never sent to the client.
DataTemplate.PrivateKeys = {
	ProcessedReceipts = true,
	ClaimedRewards = true,
}

return DataTemplate
