--[[
	Quests
	Categories:
	  Main   - a linear chain; completing one activates `Next`
	  Daily  - a random subset (GameConfig.Quests.DailyQuestCount) is assigned every UTC day

	Objective types (QuestService maps gameplay events to these):
	  KillEnemies   Filter: { Enemy?, World?, Tier? }     progress += kills
	  KillBoss      Filter: { Enemy?, World? }             progress += boss kills (any boss tier)
	  Summon        Filter: { Banner? }                     progress += units summoned
	  EarnYen                                               progress += Yen earned
	  UnlockWorld   Filter: { World? }                      progress += worlds unlocked
	  ReachLevel                                            progress = player level (max semantics)
	  LevelUpUnits                                          progress += unit level ups
	  EvolveUnit                                            progress += evolutions
	  FuseUnits                                             progress += fusions
	  CompleteRaid  Filter: { Raid? }                       progress += raids cleared

	Rewards use the shared reward format: { Yen, Gems, Gold, Tokens, XP, Items = { [id] = n }, Units = { unitId, ... } }
]]

export type QuestDef = {
	Id: string,
	Category: string,
	Title: string,
	Description: string,
	Type: string,
	Target: number,
	Filter: { [string]: any }?,
	Rewards: { [string]: any },
	Next: string?,
	Requirements: { [string]: any }?,
}

local Quests = {}

Quests.ObjectiveTypes = {
	KillEnemies = true,
	KillBoss = true,
	Summon = true,
	EarnYen = true,
	UnlockWorld = true,
	ReachLevel = true,
	LevelUpUnits = true,
	EvolveUnit = true,
	FuseUnits = true,
	CompleteRaid = true,
}

-- Objective types whose progress is "the current value" instead of an accumulator.
Quests.AbsoluteTypes = { ReachLevel = true }

local main: { QuestDef } = {
	{ Id = "M01", Category = "Main", Title = "First Steps", Description = "Defeat 10 Bandits.", Type = "KillEnemies", Target = 10, Filter = { Enemy = "W1_Bandit" }, Rewards = { Yen = 150, XP = 50 }, Next = "M02" },
	{ Id = "M02", Category = "Main", Title = "Call for Help", Description = "Summon 3 units.", Type = "Summon", Target = 3, Rewards = { Gems = 50 }, Next = "M03" },
	{ Id = "M03", Category = "Main", Title = "Ninja Trouble", Description = "Defeat 25 enemies in Shinobi Valley.", Type = "KillEnemies", Target = 25, Filter = { World = "W1" }, Rewards = { Yen = 500, XP = 150, Items = { XPPotionSmall = 5 } }, Next = "M04" },
	{ Id = "M04", Category = "Main", Title = "Growing Stronger", Description = "Reach player level 5.", Type = "ReachLevel", Target = 5, Rewards = { Gems = 75 }, Next = "M05" },
	{ Id = "M05", Category = "Main", Title = "The King", Description = "Defeat the Bandit King.", Type = "KillBoss", Target = 1, Filter = { Enemy = "W1_SnakeSage" }, Rewards = { Yen = 3000, Gold = 10, XP = 400 }, Next = "M06" },
	{ Id = "M06", Category = "Main", Title = "Set Sail", Description = "Unlock Tidebreaker Isles.", Type = "UnlockWorld", Target = 1, Filter = { World = "W2" }, Rewards = { Gems = 150, Items = { XPPotionMedium = 3 } }, Next = "M07" },
	{ Id = "M07", Category = "Main", Title = "High Seas", Description = "Defeat 100 enemies in Tidebreaker Isles.", Type = "KillEnemies", Target = 100, Filter = { World = "W2" }, Rewards = { Yen = 15000, XP = 3000 }, Next = "M08" },
	{ Id = "M08", Category = "Main", Title = "Beast of the Deep", Description = "Defeat the Abyssal Kraken.", Type = "KillBoss", Target = 1, Filter = { Enemy = "W2_Kraken" }, Rewards = { Gems = 200, Items = { EvolutionStone = 1 } }, Next = "M09" },
	{ Id = "M09", Category = "Main", Title = "Academy Entrance", Description = "Unlock Spirit Academy.", Type = "UnlockWorld", Target = 1, Filter = { World = "W3" }, Rewards = { Gems = 250, Items = { TraitCrystal = 1 } }, Next = "M10" },
	{ Id = "M10", Category = "Main", Title = "Into the Abyss", Description = "Complete any raid.", Type = "CompleteRaid", Target = 1, Rewards = { Tokens = 50, Gems = 150 }, Next = "M11" },
	{ Id = "M11", Category = "Main", Title = "Hero Licence", Description = "Unlock Hero Metropolis.", Type = "UnlockWorld", Target = 1, Filter = { World = "W4" }, Rewards = { Gems = 300 }, Next = "M12" },
	{ Id = "M12", Category = "Main", Title = "Crimson Night", Description = "Unlock Crimson Forest.", Type = "UnlockWorld", Target = 1, Filter = { World = "W5" }, Rewards = { Gems = 500, Items = { TraitCrystal = 2 } } },
}

local daily: { QuestDef } = {
	{ Id = "D_Kill100", Category = "Daily", Title = "Daily Hunt", Description = "Defeat 100 enemies.", Type = "KillEnemies", Target = 100, Rewards = { Gems = 30, Yen = 1000 } },
	{ Id = "D_Kill300", Category = "Daily", Title = "Daily Massacre", Description = "Defeat 300 enemies.", Type = "KillEnemies", Target = 300, Rewards = { Gems = 60 } },
	{ Id = "D_Elite", Category = "Daily", Title = "Elite Hunter", Description = "Defeat 15 elite enemies.", Type = "KillEnemies", Target = 15, Filter = { Tier = "Elite" }, Rewards = { Gems = 40, Items = { XPPotionMedium = 2 } } },
	{ Id = "D_Boss", Category = "Daily", Title = "Boss Slayer", Description = "Defeat 2 bosses.", Type = "KillBoss", Target = 2, Rewards = { Gems = 50, Gold = 10 } },
	{ Id = "D_Summon10", Category = "Daily", Title = "Summoner", Description = "Summon 10 units.", Type = "Summon", Target = 10, Rewards = { Gems = 45 } },
	{ Id = "D_Yen", Category = "Daily", Title = "Money Maker", Description = "Earn 10,000 Yen.", Type = "EarnYen", Target = 10000, Rewards = { Gems = 35, Items = { YenBoost2x = 1 } } },
	{ Id = "D_Fuse", Category = "Daily", Title = "Fusion Practice", Description = "Fuse units 3 times.", Type = "FuseUnits", Target = 3, Rewards = { Gems = 30, Items = { XPPotionSmall = 5 } } },
	{ Id = "D_LevelUp", Category = "Daily", Title = "Training Day", Description = "Level up units 10 times.", Type = "LevelUpUnits", Target = 10, Rewards = { Gems = 35 } },
}

Quests.Main = main
Quests.Daily = daily
Quests.FirstMain = "M01"

Quests.ById = {} :: { [string]: QuestDef }
for _, group in { main, daily } do
	for _, def in group do
		assert(Quests.ById[def.Id] == nil, "Duplicate quest id " .. def.Id)
		assert(Quests.ObjectiveTypes[def.Type], ("Quest %s has unknown type %s"):format(def.Id, tostring(def.Type)))
		assert(type(def.Target) == "number" and def.Target > 0, "Quest target must be positive: " .. def.Id)
		Quests.ById[def.Id] = def
	end
end
for _, def in main do
	if def.Next then
		assert(Quests.ById[def.Next], ("Quest %s points to unknown Next %s"):format(def.Id, def.Next))
	end
end

function Quests.Get(id: string): QuestDef?
	return Quests.ById[id]
end

return Quests
