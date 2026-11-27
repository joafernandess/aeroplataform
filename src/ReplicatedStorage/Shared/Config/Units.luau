--[[
	Units
	Every collectible fighter. All names/series are ORIGINAL placeholders (do not use real anime IP —
	Roblox moderation and copyright). Swap names freely; Ids are what get saved, so never rename an Id
	that has shipped — add a migration instead.

	Fields:
	  Id, Name, Anime (series of origin), Rarity
	  BaseDamage      damage per hit at level 1, 0 stars, no traits
	  AttackSpeed     attacks per second
	  Range           studs from the player's character
	  CombatStyle     "Melee" | "Ranged" | "Magic" (cosmetic + default range)
	  CritChance      optional extra crit chance
	  Passive         Abilities.Passives id (optional)
	  Special         Abilities.Specials id (optional)
	  EvolvesTo       Id of the evolved form (optional)
	  EvolutionCost   { Yen = n, Items = { [itemId] = count } } required to evolve
	  Evolved         true for forms that can only be obtained by evolving
	  Model           path inside ServerStorage/Assets/Units (or ReplicatedStorage) — placeholder until art exists
]]

local Rarities = require(script.Parent.Rarities)
local Abilities = require(script.Parent.Abilities)

export type UnitDef = {
	Id: string,
	Name: string,
	Anime: string,
	Rarity: string,
	BaseDamage: number,
	AttackSpeed: number,
	Range: number,
	CombatStyle: string,
	CritChance: number,
	Passive: string?,
	Special: string?,
	EvolvesTo: string?,
	EvolutionCost: { Yen: number?, Gold: number?, Items: { [string]: number }? }?,
	Evolved: boolean,
	Model: string,
}

local STYLE_RANGE = { Melee = 14, Ranged = 32, Magic = 24 }

local Units = {}
Units.ById = {} :: { [string]: UnitDef }
Units.List = {} :: { UnitDef }

local function define(def)
	assert(type(def.Id) == "string" and def.Id ~= "", "Unit needs an Id")
	assert(Units.ById[def.Id] == nil, "Duplicate unit id " .. def.Id)
	assert(Rarities.IsValid(def.Rarity), "Invalid rarity on " .. def.Id)
	assert(type(def.BaseDamage) == "number" and def.BaseDamage > 0, "Invalid BaseDamage on " .. def.Id)
	if def.Passive then
		assert(Abilities.Passives[def.Passive], "Unknown passive " .. def.Passive .. " on " .. def.Id)
	end
	if def.Special then
		assert(Abilities.Specials[def.Special], "Unknown special " .. def.Special .. " on " .. def.Id)
	end
	def.CombatStyle = def.CombatStyle or "Melee"
	def.AttackSpeed = def.AttackSpeed or 1
	def.Range = def.Range or STYLE_RANGE[def.CombatStyle] or 14
	def.CritChance = def.CritChance or 0
	def.Evolved = def.Evolved == true
	def.Model = def.Model or ("Units/" .. def.Id)
	Units.ById[def.Id] = def
	table.insert(Units.List, def)
end

------------------------------------------------------------------------------------------
-- World 1: Shinobi Valley — series "Shadow Shinobi"
------------------------------------------------------------------------------------------
local SS = "Shadow Shinobi"
define({ Id = "SS_GeninRecruit", Name = "Genin Recruit", Anime = SS, Rarity = "Common", BaseDamage = 5, AttackSpeed = 1.0 })
define({ Id = "SS_Kenta", Name = "Kenta", Anime = SS, Rarity = "Common", BaseDamage = 6, AttackSpeed = 0.9, CombatStyle = "Ranged" })
define({ Id = "SS_Hikari", Name = "Hikari", Anime = SS, Rarity = "Rare", BaseDamage = 13, AttackSpeed = 1.1, Passive = "Discipline" })
define({ Id = "SS_Tetsuo", Name = "Tetsuo", Anime = SS, Rarity = "Epic", BaseDamage = 32, AttackSpeed = 1.0, Passive = "Focus", Special = "QuickSlash" })
define({
	Id = "SS_Raizen", Name = "Raizen", Anime = SS, Rarity = "Legendary", BaseDamage = 85, AttackSpeed = 1.2,
	Passive = "KeenEye", Special = "ShadowClone",
	EvolvesTo = "SS_RaizenStorm", EvolutionCost = { Yen = 50000, Items = { ShinobiScroll = 5, EvolutionStone = 1 } },
})
define({ Id = "SS_RaizenStorm", Name = "Raizen (Storm Sage)", Anime = SS, Rarity = "Legendary", BaseDamage = 210, AttackSpeed = 1.4, Passive = "Leader", Special = "ShadowClone", Evolved = true })
define({ Id = "SS_Kurogane", Name = "Kurogane", Anime = SS, Rarity = "Mythical", BaseDamage = 220, AttackSpeed = 1.1, CombatStyle = "Magic", Passive = "Commander", Special = "ShadowClone" })

------------------------------------------------------------------------------------------
-- World 2: Tidebreaker Isles — series "Grand Tides"
------------------------------------------------------------------------------------------
local GT = "Grand Tides"
define({ Id = "GT_Deckhand", Name = "Deckhand", Anime = GT, Rarity = "Common", BaseDamage = 20, AttackSpeed = 1.0 })
define({ Id = "GT_Mira", Name = "Navigator Mira", Anime = GT, Rarity = "Rare", BaseDamage = 50, AttackSpeed = 1.1, CombatStyle = "Ranged", Passive = "Treasure" })
define({ Id = "GT_Sable", Name = "Sable", Anime = GT, Rarity = "Epic", BaseDamage = 125, AttackSpeed = 1.0, Passive = "Focus", Special = "QuickSlash" })
define({
	Id = "GT_CaptainRook", Name = "Captain Rook", Anime = GT, Rarity = "Legendary", BaseDamage = 340, AttackSpeed = 1.0, CombatStyle = "Ranged",
	Passive = "Leader", Special = "CannonBlast",
	EvolvesTo = "GT_RookTyrant", EvolutionCost = { Yen = 250000, Items = { TideCompass = 5, EvolutionStone = 2 } },
})
define({ Id = "GT_RookTyrant", Name = "Rook (Sea Tyrant)", Anime = GT, Rarity = "Legendary", BaseDamage = 820, AttackSpeed = 1.15, CombatStyle = "Ranged", Passive = "Commander", Special = "CannonBlast", Evolved = true })
define({ Id = "GT_Leviath", Name = "Leviath", Anime = GT, Rarity = "Mythical", BaseDamage = 880, AttackSpeed = 1.0, Passive = "Slayer", Special = "CannonBlast" })

------------------------------------------------------------------------------------------
-- World 3: Spirit Academy — series "Soul Requiem"
------------------------------------------------------------------------------------------
local SR = "Soul Requiem"
define({ Id = "SR_Initiate", Name = "Academy Initiate", Anime = SR, Rarity = "Common", BaseDamage = 80, AttackSpeed = 1.0 })
define({ Id = "SR_Yuki", Name = "Yuki", Anime = SR, Rarity = "Rare", BaseDamage = 200, AttackSpeed = 1.1, CombatStyle = "Magic", Passive = "Mentor" })
define({ Id = "SR_Ichigen", Name = "Ichigen", Anime = SR, Rarity = "Epic", BaseDamage = 500, AttackSpeed = 1.0, Passive = "KeenEye", Special = "SoulReap" })
define({
	Id = "SR_Byakuren", Name = "Byakuren", Anime = SR, Rarity = "Legendary", BaseDamage = 1350, AttackSpeed = 1.1,
	Passive = "Focus", Special = "SoulReap",
	EvolvesTo = "SR_ByakurenBankai", EvolutionCost = { Yen = 1200000, Items = { SpiritShard = 6, EvolutionStone = 3 } },
})
define({ Id = "SR_ByakurenBankai", Name = "Byakuren (Released)", Anime = SR, Rarity = "Legendary", BaseDamage = 3300, AttackSpeed = 1.25, Passive = "Awakened", Special = "SoulReap", Evolved = true })
define({ Id = "SR_Aizora", Name = "Aizora", Anime = SR, Rarity = "Mythical", BaseDamage = 3500, AttackSpeed = 1.0, CombatStyle = "Magic", Passive = "Commander", Special = "MoonCrescent" })
define({ Id = "SR_Hollowking", Name = "The Hollow King", Anime = SR, Rarity = "Secret", BaseDamage = 9000, AttackSpeed = 1.1, Passive = "Awakened", Special = "Judgement" })

------------------------------------------------------------------------------------------
-- World 4: Hero Metropolis — series "Hero Rising"
------------------------------------------------------------------------------------------
local HR = "Hero Rising"
define({ Id = "HR_Sidekick", Name = "Sidekick", Anime = HR, Rarity = "Common", BaseDamage = 320, AttackSpeed = 1.0 })
define({ Id = "HR_Volt", Name = "Volt", Anime = HR, Rarity = "Rare", BaseDamage = 800, AttackSpeed = 1.3, CombatStyle = "Ranged", Passive = "Discipline" })
define({ Id = "HR_IronLady", Name = "Iron Lady", Anime = HR, Rarity = "Epic", BaseDamage = 2000, AttackSpeed = 0.9, Passive = "Slayer", Special = "DragonFist" })
define({
	Id = "HR_Smashman", Name = "Smash-Man", Anime = HR, Rarity = "Legendary", BaseDamage = 5400, AttackSpeed = 1.0,
	Passive = "Focus", Special = "DragonFist",
	EvolvesTo = "HR_SmashmanMax", EvolutionCost = { Yen = 6000000, Items = { HeroBadge = 6, EvolutionStone = 4 } },
})
define({ Id = "HR_SmashmanMax", Name = "Smash-Man (Full Power)", Anime = HR, Rarity = "Legendary", BaseDamage = 13000, AttackSpeed = 1.1, Passive = "Awakened", Special = "DragonFist", Evolved = true })
define({ Id = "HR_Omnipotent", Name = "Omnipotent One", Anime = HR, Rarity = "Mythical", BaseDamage = 14000, AttackSpeed = 1.0, Passive = "Commander", Special = "BattleCry" })

------------------------------------------------------------------------------------------
-- World 5: Crimson Forest — series "Crimson Moon"
------------------------------------------------------------------------------------------
local CM = "Crimson Moon"
define({ Id = "CM_Hunter", Name = "Demon Hunter", Anime = CM, Rarity = "Common", BaseDamage = 1300, AttackSpeed = 1.0 })
define({ Id = "CM_Nezumi", Name = "Nezumi", Anime = CM, Rarity = "Rare", BaseDamage = 3200, AttackSpeed = 1.2, Passive = "KeenEye" })
define({ Id = "CM_Tanjo", Name = "Tanjo", Anime = CM, Rarity = "Epic", BaseDamage = 8000, AttackSpeed = 1.0, Passive = "Focus", Special = "MoonCrescent" })
define({ Id = "CM_Rengar", Name = "Flame Pillar Rengar", Anime = CM, Rarity = "Legendary", BaseDamage = 21000, AttackSpeed = 1.1, Passive = "Leader", Special = "Overdrive" })
define({ Id = "CM_Muzan", Name = "Lord of Dusk", Anime = CM, Rarity = "Mythical", BaseDamage = 56000, AttackSpeed = 1.0, CombatStyle = "Magic", Passive = "Commander", Special = "MoonCrescent" })
define({ Id = "CM_Eclipse", Name = "Eclipse Sovereign", Anime = CM, Rarity = "Secret", BaseDamage = 150000, AttackSpeed = 1.1, Passive = "Awakened", Special = "Judgement" })

------------------------------------------------------------------------------------------
-- Special rarities
------------------------------------------------------------------------------------------
define({ Id = "DV_Celestia", Name = "Celestia", Anime = "Heavenly Accord", Rarity = "Divine", BaseDamage = 60000, AttackSpeed = 1.2, CombatStyle = "Magic", Passive = "Commander", Special = "Judgement" })
define({ Id = "EX_Founder", Name = "The Founder", Anime = "Origin", Rarity = "Exclusive", BaseDamage = 2500, AttackSpeed = 1.5, Passive = "Leader", Special = "BattleCry" })

-- Validate evolution links once everything is defined.
for _, def in Units.List do
	if def.EvolvesTo then
		local target = Units.ById[def.EvolvesTo]
		assert(target, ("Unit %s evolves into unknown unit %s"):format(def.Id, def.EvolvesTo))
		assert(target.Evolved, ("Evolution target %s must be flagged Evolved"):format(def.EvolvesTo))
		assert(def.EvolutionCost, ("Unit %s has EvolvesTo but no EvolutionCost"):format(def.Id))
	end
end

function Units.Get(id: string): UnitDef?
	return Units.ById[id]
end

function Units.IsValid(id: any): boolean
	return type(id) == "string" and Units.ById[id] ~= nil
end

return Units
