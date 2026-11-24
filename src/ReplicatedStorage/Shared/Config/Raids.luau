--[[
	Raids
	Instanced wave fights. A raid instance is private: only its participants can see/damage its enemies
	(enemies spawn with a zone key "Raid:<instanceId>").

	Fields:
	  Id, Name, Requirements, EntryCost (optional { Currency, Amount }), Cooldown (seconds between entries)
	  TimeLimit      seconds before the raid fails
	  Waves          { { Enemies = { { Enemy, Count } } } } — the last wave usually holds the RaidBoss
	  Rewards        granted on completion (shared reward format), on top of per-kill rewards
	  ArenaOffset    {x,y,z} offset from Worlds.RaidArenaOrigin (one arena slot per running instance)
]]

export type RaidWave = { Enemies: { { Enemy: string, Count: number } } }
export type RaidDef = {
	Id: string,
	Name: string,
	Requirements: { [string]: any },
	EntryCost: { Currency: string, Amount: number }?,
	Cooldown: number,
	TimeLimit: number,
	Waves: { RaidWave },
	Rewards: { [string]: any },
	MaxPlayers: number,
}

local Enemies = require(script.Parent.Enemies)

local Raids = {}

Raids.List = {
	{
		Id = "RAID_Abyss", Name = "Abyssal Gate", Requirements = { WorldUnlocked = "W3", Level = 25 },
		Cooldown = 600, TimeLimit = 240, MaxPlayers = 4,
		Waves = {
			{ Enemies = { { Enemy = "R_Shade", Count = 6 } } },
			{ Enemies = { { Enemy = "R_Shade", Count = 6 }, { Enemy = "R_Revenant", Count = 2 } } },
			{ Enemies = { { Enemy = "R_Abyssal", Count = 1 } } },
		},
		Rewards = { Tokens = 40, Gems = 30, Items = { EvolutionStone = 1 } },
	},
	{
		Id = "RAID_Dread", Name = "Throne of Dread", Requirements = { WorldUnlocked = "W5", Level = 70 },
		EntryCost = { Currency = "Gold", Amount = 200 },
		Cooldown = 1800, TimeLimit = 300, MaxPlayers = 4,
		Waves = {
			{ Enemies = { { Enemy = "R_Revenant", Count = 8 } } },
			{ Enemies = { { Enemy = "R_Revenant", Count = 10 } } },
			{ Enemies = { { Enemy = "R_Dread", Count = 1 } } },
		},
		Rewards = { Tokens = 150, Gems = 100, Items = { TraitCrystal = 1, EvolutionStone = 2 } },
	},
} :: { RaidDef }

Raids.ById = {} :: { [string]: RaidDef }
for _, def in Raids.List do
	assert(Raids.ById[def.Id] == nil, "Duplicate raid " .. def.Id)
	assert(#def.Waves > 0, "Raid needs waves: " .. def.Id)
	for _, wave in def.Waves do
		for _, entry in wave.Enemies do
			assert(Enemies.Get(entry.Enemy), ("Raid %s references unknown enemy %s"):format(def.Id, entry.Enemy))
			assert(entry.Count > 0, "Raid wave count must be positive: " .. def.Id)
		end
	end
	Raids.ById[def.Id] = def
end

function Raids.Get(id: string): RaidDef?
	return Raids.ById[id]
end

return Raids
