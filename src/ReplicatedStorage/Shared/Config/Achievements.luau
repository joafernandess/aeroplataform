--[[
	Achievements
	Permanent, tiered goals computed from player Stats (or Level). Each tier is claimed once.
	`Stat` is a key in PlayerData.Stats, or "Level" for the player level.
]]

export type AchievementTier = { Goal: number, Rewards: { [string]: any } }
export type AchievementDef = { Id: string, Name: string, Description: string, Stat: string, Tiers: { AchievementTier } }

local Achievements = {}

Achievements.List = {
	{
		Id = "A_Kills", Name = "Exterminator", Description = "Defeat enemies.", Stat = "TotalKills",
		Tiers = {
			{ Goal = 100, Rewards = { Gems = 20 } },
			{ Goal = 1000, Rewards = { Gems = 50 } },
			{ Goal = 10000, Rewards = { Gems = 150, Items = { TraitCrystal = 1 } } },
			{ Goal = 100000, Rewards = { Gems = 500, Items = { TraitCrystal = 3 } } },
		},
	},
	{
		Id = "A_Bosses", Name = "Giant Slayer", Description = "Defeat bosses.", Stat = "BossKills",
		Tiers = {
			{ Goal = 1, Rewards = { Gems = 25 } },
			{ Goal = 25, Rewards = { Gems = 100 } },
			{ Goal = 250, Rewards = { Gems = 300, Items = { EvolutionStone = 2 } } },
		},
	},
	{
		Id = "A_Summons", Name = "Collector", Description = "Summon units.", Stat = "TotalSummons",
		Tiers = {
			{ Goal = 10, Rewards = { Gems = 30 } },
			{ Goal = 100, Rewards = { Gems = 100 } },
			{ Goal = 1000, Rewards = { Gems = 400, Items = { LuckBoost2x = 2 } } },
		},
	},
	{
		Id = "A_Level", Name = "Veteran", Description = "Reach player levels.", Stat = "Level",
		Tiers = {
			{ Goal = 10, Rewards = { Gems = 50 } },
			{ Goal = 50, Rewards = { Gems = 200 } },
			{ Goal = 100, Rewards = { Gems = 600 } },
		},
	},
	{
		Id = "A_Raids", Name = "Raider", Description = "Complete raids.", Stat = "RaidsCompleted",
		Tiers = {
			{ Goal = 1, Rewards = { Tokens = 20 } },
			{ Goal = 25, Rewards = { Tokens = 150 } },
			{ Goal = 100, Rewards = { Tokens = 500, Gems = 300 } },
		},
	},
	{
		Id = "A_Evolve", Name = "Evolutionist", Description = "Evolve units.", Stat = "UnitsEvolved",
		Tiers = {
			{ Goal = 1, Rewards = { Gems = 100 } },
			{ Goal = 10, Rewards = { Gems = 300, Items = { EvolutionStone = 3 } } },
		},
	},
} :: { AchievementDef }

Achievements.ById = {} :: { [string]: AchievementDef }
for _, def in Achievements.List do
	assert(Achievements.ById[def.Id] == nil, "Duplicate achievement " .. def.Id)
	for i = 2, #def.Tiers do
		assert(def.Tiers[i].Goal > def.Tiers[i - 1].Goal, "Achievement tiers must increase: " .. def.Id)
	end
	Achievements.ById[def.Id] = def
end

function Achievements.Get(id: string): AchievementDef?
	return Achievements.ById[id]
end

return Achievements
