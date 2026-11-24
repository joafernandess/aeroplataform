--[[
	Enemies
	Enemy definitions + tier rules. Tiers control reward sharing, visuals and default respawn times.

	Fields:
	  Id, Name, World, Tier ("Normal" | "Elite" | "MiniBoss" | "WorldBoss" | "RaidBoss")
	  MaxHP, Damage (dealt to players when Aggressive), Defense (flat damage reduction curve)
	  RespawnTime   seconds after death before a new one spawns (nil = tier default)
	  Rewards       { Yen, Gold, Gems, Tokens, XP (player), UnitXP (each equipped unit), Drops = { {Item, Chance, Min, Max} } }
	  Model         path in ServerStorage/Assets/Enemies; a placeholder rig is generated when missing
]]

export type Drop = { Item: string, Chance: number, Min: number, Max: number }
export type EnemyRewards = {
	Yen: number?,
	Gold: number?,
	Gems: number?,
	Tokens: number?,
	XP: number?,
	UnitXP: number?,
	Drops: { Drop }?,
}
export type EnemyDef = {
	Id: string,
	Name: string,
	World: string,
	Tier: string,
	MaxHP: number,
	Damage: number,
	Defense: number,
	RespawnTime: number,
	Rewards: EnemyRewards,
	Model: string,
	IsBoss: boolean,
}
export type TierDef = {
	Id: string,
	IsBoss: boolean,
	SharedRewards: boolean, -- every contributor above the threshold receives full rewards
	DefaultRespawn: number,
	Scale: number, -- placeholder model scale
	Aggressive: boolean, -- attacks nearby players with its Damage stat
	AttackInterval: number,
	AttackRange: number,
	Color: { number },
}

local Enemies = {}

Enemies.Tiers = {
	Normal = { Id = "Normal", IsBoss = false, SharedRewards = false, DefaultRespawn = 4, Scale = 1, Aggressive = false, AttackInterval = 2, AttackRange = 10, Color = { 200, 200, 200 } },
	Elite = { Id = "Elite", IsBoss = false, SharedRewards = false, DefaultRespawn = 10, Scale = 1.4, Aggressive = false, AttackInterval = 2, AttackRange = 12, Color = { 90, 160, 255 } },
	MiniBoss = { Id = "MiniBoss", IsBoss = true, SharedRewards = true, DefaultRespawn = 60, Scale = 2.2, Aggressive = true, AttackInterval = 2.5, AttackRange = 16, Color = { 255, 160, 40 } },
	WorldBoss = { Id = "WorldBoss", IsBoss = true, SharedRewards = true, DefaultRespawn = 300, Scale = 3.5, Aggressive = true, AttackInterval = 3, AttackRange = 22, Color = { 255, 60, 60 } },
	RaidBoss = { Id = "RaidBoss", IsBoss = true, SharedRewards = true, DefaultRespawn = 0, Scale = 4, Aggressive = true, AttackInterval = 2.5, AttackRange = 24, Color = { 170, 40, 255 } },
} :: { [string]: TierDef }

Enemies.ById = {} :: { [string]: EnemyDef }
Enemies.List = {} :: { EnemyDef }

local function define(def)
	assert(type(def.Id) == "string", "Enemy needs an Id")
	assert(Enemies.ById[def.Id] == nil, "Duplicate enemy id " .. def.Id)
	local tier = Enemies.Tiers[def.Tier or "Normal"]
	assert(tier, "Invalid tier on enemy " .. def.Id)
	assert(type(def.MaxHP) == "number" and def.MaxHP > 0, "Invalid MaxHP on " .. def.Id)
	def.Tier = tier.Id
	def.IsBoss = tier.IsBoss
	def.Damage = def.Damage or 0
	def.Defense = def.Defense or 0
	def.RespawnTime = def.RespawnTime or tier.DefaultRespawn
	def.Rewards = def.Rewards or {}
	def.Model = def.Model or ("Enemies/" .. def.Id)
	Enemies.ById[def.Id] = def
	table.insert(Enemies.List, def)
end

-- World 1 -------------------------------------------------------------------------
define({ Id = "W1_Bandit", Name = "Bandit", World = "W1", MaxHP = 60, Defense = 0, Rewards = { Yen = 6, XP = 4, UnitXP = 3, Drops = { { Item = "XPPotionSmall", Chance = 0.02, Min = 1, Max = 1 } } } })
define({ Id = "W1_RogueNinja", Name = "Rogue Ninja", World = "W1", MaxHP = 180, Defense = 2, Rewards = { Yen = 15, XP = 9, UnitXP = 7, Drops = { { Item = "ShinobiScroll", Chance = 0.03, Min = 1, Max = 1 } } } })
define({ Id = "W1_MaskedElite", Name = "Masked Elite", World = "W1", Tier = "Elite", MaxHP = 900, Defense = 5, Rewards = { Yen = 70, XP = 35, UnitXP = 25, Drops = { { Item = "ShinobiScroll", Chance = 0.15, Min = 1, Max = 2 } } } })
define({ Id = "W1_SnakeSage", Name = "Snake Sage", World = "W1", Tier = "MiniBoss", MaxHP = 8000, Damage = 10, Defense = 10, Rewards = { Yen = 600, Gold = 5, XP = 200, UnitXP = 150, Drops = { { Item = "ShinobiScroll", Chance = 0.6, Min = 1, Max = 3 }, { Item = "EvolutionStone", Chance = 0.05, Min = 1, Max = 1 } } } })
define({ Id = "W1_NineTails", Name = "Nine-Tailed Beast", World = "W1", Tier = "WorldBoss", MaxHP = 60000, Damage = 25, Defense = 20, Rewards = { Yen = 4000, Gold = 25, Gems = 10, XP = 1000, UnitXP = 600, Drops = { { Item = "EvolutionStone", Chance = 0.35, Min = 1, Max = 1 }, { Item = "DamageBoost2x", Chance = 0.1, Min = 1, Max = 1 } } } })

-- World 2 -------------------------------------------------------------------------
define({ Id = "W2_Pirate", Name = "Pirate Grunt", World = "W2", MaxHP = 900, Defense = 5, Rewards = { Yen = 40, XP = 20, UnitXP = 15 } })
define({ Id = "W2_Marine", Name = "Marine Soldier", World = "W2", MaxHP = 2400, Defense = 10, Rewards = { Yen = 95, XP = 40, UnitXP = 30, Drops = { { Item = "TideCompass", Chance = 0.03, Min = 1, Max = 1 } } } })
define({ Id = "W2_Commodore", Name = "Commodore", World = "W2", Tier = "Elite", MaxHP = 12000, Defense = 25, Rewards = { Yen = 450, XP = 160, UnitXP = 110, Drops = { { Item = "TideCompass", Chance = 0.15, Min = 1, Max = 2 } } } })
define({ Id = "W2_Warlord", Name = "Sea Warlord", World = "W2", Tier = "MiniBoss", MaxHP = 110000, Damage = 40, Defense = 40, Rewards = { Yen = 3800, Gold = 15, XP = 900, UnitXP = 650, Drops = { { Item = "TideCompass", Chance = 0.6, Min = 1, Max = 3 }, { Item = "EvolutionStone", Chance = 0.08, Min = 1, Max = 1 } } } })
define({ Id = "W2_Kraken", Name = "Abyssal Kraken", World = "W2", Tier = "WorldBoss", MaxHP = 800000, Damage = 90, Defense = 60, Rewards = { Yen = 26000, Gold = 70, Gems = 15, XP = 4500, UnitXP = 2800, Drops = { { Item = "EvolutionStone", Chance = 0.4, Min = 1, Max = 2 } } } })

-- World 3 -------------------------------------------------------------------------
define({ Id = "W3_Hollow", Name = "Lesser Hollow", World = "W3", MaxHP = 14000, Defense = 20, Rewards = { Yen = 260, XP = 90, UnitXP = 70 } })
define({ Id = "W3_Arrancar", Name = "Masked Spirit", World = "W3", MaxHP = 36000, Defense = 35, Rewards = { Yen = 600, XP = 180, UnitXP = 140, Drops = { { Item = "SpiritShard", Chance = 0.03, Min = 1, Max = 1 } } } })
define({ Id = "W3_Captain", Name = "Rogue Captain", World = "W3", Tier = "Elite", MaxHP = 180000, Defense = 70, Rewards = { Yen = 2800, XP = 700, UnitXP = 500, Drops = { { Item = "SpiritShard", Chance = 0.15, Min = 1, Max = 2 } } } })
define({ Id = "W3_Espada", Name = "Fallen Espada", World = "W3", Tier = "MiniBoss", MaxHP = 1600000, Damage = 150, Defense = 120, Rewards = { Yen = 24000, Gold = 40, XP = 4000, UnitXP = 3000, Drops = { { Item = "SpiritShard", Chance = 0.6, Min = 1, Max = 3 }, { Item = "EvolutionStone", Chance = 0.1, Min = 1, Max = 1 } } } })
define({ Id = "W3_SoulKing", Name = "Soul Tyrant", World = "W3", Tier = "WorldBoss", MaxHP = 12000000, Damage = 300, Defense = 200, Rewards = { Yen = 160000, Gold = 180, Gems = 25, XP = 20000, UnitXP = 12000, Drops = { { Item = "EvolutionStone", Chance = 0.5, Min = 1, Max = 2 }, { Item = "TraitCrystal", Chance = 0.05, Min = 1, Max = 1 } } } })

-- World 4 -------------------------------------------------------------------------
define({ Id = "W4_Thug", Name = "Street Thug", World = "W4", MaxHP = 200000, Defense = 60, Rewards = { Yen = 1700, XP = 400, UnitXP = 300 } })
define({ Id = "W4_Villain", Name = "Villain Recruit", World = "W4", MaxHP = 520000, Defense = 100, Rewards = { Yen = 3900, XP = 800, UnitXP = 600, Drops = { { Item = "HeroBadge", Chance = 0.03, Min = 1, Max = 1 } } } })
define({ Id = "W4_Nomu", Name = "Bio-Engineered Brute", World = "W4", Tier = "Elite", MaxHP = 2600000, Defense = 180, Rewards = { Yen = 18000, XP = 3000, UnitXP = 2200, Drops = { { Item = "HeroBadge", Chance = 0.15, Min = 1, Max = 2 } } } })
define({ Id = "W4_Overseer", Name = "League Overseer", World = "W4", Tier = "MiniBoss", MaxHP = 24000000, Damage = 500, Defense = 300, Rewards = { Yen = 150000, Gold = 100, XP = 18000, UnitXP = 13000, Drops = { { Item = "HeroBadge", Chance = 0.6, Min = 1, Max = 3 }, { Item = "EvolutionStone", Chance = 0.12, Min = 1, Max = 1 } } } })
define({ Id = "W4_AllEater", Name = "The All-Eater", World = "W4", Tier = "WorldBoss", MaxHP = 180000000, Damage = 1000, Defense = 500, Rewards = { Yen = 1000000, Gold = 450, Gems = 40, XP = 90000, UnitXP = 55000, Drops = { { Item = "EvolutionStone", Chance = 0.6, Min = 1, Max = 3 }, { Item = "TraitCrystal", Chance = 0.08, Min = 1, Max = 1 } } } })

-- World 5 -------------------------------------------------------------------------
define({ Id = "W5_LesserDemon", Name = "Lesser Demon", World = "W5", MaxHP = 3000000, Defense = 150, Rewards = { Yen = 11000, XP = 1800, UnitXP = 1300 } })
define({ Id = "W5_Demon", Name = "Blood Demon", World = "W5", MaxHP = 7800000, Defense = 250, Rewards = { Yen = 25000, XP = 3500, UnitXP = 2600, Drops = { { Item = "CrimsonFang", Chance = 0.03, Min = 1, Max = 1 } } } })
define({ Id = "W5_LowerMoon", Name = "Lower Moon", World = "W5", Tier = "Elite", MaxHP = 40000000, Defense = 450, Rewards = { Yen = 120000, XP = 13000, UnitXP = 9500, Drops = { { Item = "CrimsonFang", Chance = 0.15, Min = 1, Max = 2 } } } })
define({ Id = "W5_UpperMoon", Name = "Upper Moon", World = "W5", Tier = "MiniBoss", MaxHP = 360000000, Damage = 1800, Defense = 800, Rewards = { Yen = 950000, Gold = 250, XP = 80000, UnitXP = 60000, Drops = { { Item = "CrimsonFang", Chance = 0.6, Min = 1, Max = 3 }, { Item = "EvolutionStone", Chance = 0.15, Min = 1, Max = 1 } } } })
define({ Id = "W5_DemonKing", Name = "Demon King", World = "W5", Tier = "WorldBoss", MaxHP = 2700000000, Damage = 4000, Defense = 1300, Rewards = { Yen = 6500000, Gold = 1100, Gems = 60, XP = 400000, UnitXP = 250000, Drops = { { Item = "EvolutionStone", Chance = 0.7, Min = 2, Max = 4 }, { Item = "TraitCrystal", Chance = 0.12, Min = 1, Max = 1 } } } })

-- Raid enemies (World = "Raid": never spawned by the world spawner) -----------------
define({ Id = "R_Shade", Name = "Shade", World = "Raid", MaxHP = 400000, Defense = 80, Rewards = { Tokens = 1, XP = 500, UnitXP = 400 } })
define({ Id = "R_Revenant", Name = "Revenant", World = "Raid", Tier = "Elite", MaxHP = 2500000, Defense = 160, Rewards = { Tokens = 3, XP = 2000, UnitXP = 1500 } })
define({ Id = "R_Abyssal", Name = "Abyssal Warden", World = "Raid", Tier = "RaidBoss", MaxHP = 30000000, Damage = 400, Defense = 300, Rewards = { Tokens = 25, Gold = 150, Gems = 20, XP = 20000, UnitXP = 15000, Drops = { { Item = "TraitCrystal", Chance = 0.25, Min = 1, Max = 1 }, { Item = "EvolutionStone", Chance = 0.5, Min = 1, Max = 2 } } } })
define({ Id = "R_Dread", Name = "Dread Monarch", World = "Raid", Tier = "RaidBoss", MaxHP = 900000000, Damage = 2500, Defense = 900, Rewards = { Tokens = 80, Gold = 800, Gems = 50, XP = 250000, UnitXP = 180000, Drops = { { Item = "TraitCrystal", Chance = 0.5, Min = 1, Max = 2 }, { Item = "EvolutionStone", Chance = 0.8, Min = 2, Max = 4 } } } })

function Enemies.Get(id: string): EnemyDef?
	return Enemies.ById[id]
end

function Enemies.GetTier(id: string): TierDef?
	return Enemies.Tiers[id]
end

function Enemies.IsValid(id: any): boolean
	return type(id) == "string" and Enemies.ById[id] ~= nil
end

return Enemies
