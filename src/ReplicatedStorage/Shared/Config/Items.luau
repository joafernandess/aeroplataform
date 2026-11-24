--[[
	Items
	Every stackable inventory item. Categories:
	  Potion        consumed on a unit (Effect.Type = "UnitXP")
	  Material      generic crafting/evolution material
	  Evolution     evolution-specific materials
	  Boost         timed player boost (Effect.Type = "Boost", Stat, Multiplier, Duration)
	  Consumable    misc single-use (Effect.Type = "TraitReroll", "Currency" ...)

	Item effects are executed by InventoryService:UseItem (server). Add a new Effect.Type there.
]]

export type ItemDef = {
	Id: string,
	Name: string,
	Category: string,
	Rarity: string,
	Description: string,
	MaxStack: number,
	Usable: boolean,
	TargetsUnit: boolean, -- true when using the item requires selecting a unit
	SellValue: number?,
	Effect: { [string]: any }?,
	Icon: string?, -- rbxassetid placeholder
}

local Items = {}

local list: { ItemDef } = {
	-- Potions
	{ Id = "XPPotionSmall", Name = "Small XP Potion", Category = "Potion", Rarity = "Common", Description = "Gives a unit 150 XP.", MaxStack = 999, Usable = true, TargetsUnit = true, SellValue = 5, Effect = { Type = "UnitXP", Amount = 150 } },
	{ Id = "XPPotionMedium", Name = "XP Potion", Category = "Potion", Rarity = "Rare", Description = "Gives a unit 1,000 XP.", MaxStack = 999, Usable = true, TargetsUnit = true, SellValue = 25, Effect = { Type = "UnitXP", Amount = 1000 } },
	{ Id = "XPPotionLarge", Name = "Large XP Potion", Category = "Potion", Rarity = "Epic", Description = "Gives a unit 8,000 XP.", MaxStack = 999, Usable = true, TargetsUnit = true, SellValue = 120, Effect = { Type = "UnitXP", Amount = 8000 } },

	-- Materials
	{ Id = "EvolutionStone", Name = "Evolution Stone", Category = "Material", Rarity = "Epic", Description = "Core ingredient of every evolution.", MaxStack = 999, Usable = false, TargetsUnit = false, SellValue = 200 },
	{ Id = "TraitCrystal", Name = "Trait Crystal", Category = "Consumable", Rarity = "Legendary", Description = "Rerolls the trait of a unit.", MaxStack = 999, Usable = true, TargetsUnit = true, SellValue = 500, Effect = { Type = "TraitReroll" } },

	-- Evolution items (one per world)
	{ Id = "ShinobiScroll", Name = "Shinobi Scroll", Category = "Evolution", Rarity = "Rare", Description = "Dropped in Shinobi Valley.", MaxStack = 999, Usable = false, TargetsUnit = false, SellValue = 30 },
	{ Id = "TideCompass", Name = "Tide Compass", Category = "Evolution", Rarity = "Rare", Description = "Dropped in Tidebreaker Isles.", MaxStack = 999, Usable = false, TargetsUnit = false, SellValue = 60 },
	{ Id = "SpiritShard", Name = "Spirit Shard", Category = "Evolution", Rarity = "Epic", Description = "Dropped in Spirit Academy.", MaxStack = 999, Usable = false, TargetsUnit = false, SellValue = 120 },
	{ Id = "HeroBadge", Name = "Hero Badge", Category = "Evolution", Rarity = "Epic", Description = "Dropped in Hero Metropolis.", MaxStack = 999, Usable = false, TargetsUnit = false, SellValue = 250 },
	{ Id = "CrimsonFang", Name = "Crimson Fang", Category = "Evolution", Rarity = "Legendary", Description = "Dropped in Crimson Forest.", MaxStack = 999, Usable = false, TargetsUnit = false, SellValue = 500 },

	-- Boosts
	{ Id = "DamageBoost2x", Name = "2x Damage (15m)", Category = "Boost", Rarity = "Epic", Description = "Doubles damage for 15 minutes.", MaxStack = 99, Usable = true, TargetsUnit = false, Effect = { Type = "Boost", Stat = "Damage", Multiplier = 2, Duration = 900 } },
	{ Id = "YenBoost2x", Name = "2x Yen (15m)", Category = "Boost", Rarity = "Epic", Description = "Doubles Yen for 15 minutes.", MaxStack = 99, Usable = true, TargetsUnit = false, Effect = { Type = "Boost", Stat = "Yen", Multiplier = 2, Duration = 900 } },
	{ Id = "LuckBoost2x", Name = "2x Luck (15m)", Category = "Boost", Rarity = "Legendary", Description = "Doubles summon luck for 15 minutes.", MaxStack = 99, Usable = true, TargetsUnit = false, Effect = { Type = "Boost", Stat = "Luck", Multiplier = 2, Duration = 900 } },
	{ Id = "XPBoost2x", Name = "2x XP (15m)", Category = "Boost", Rarity = "Rare", Description = "Doubles XP for 15 minutes.", MaxStack = 99, Usable = true, TargetsUnit = false, Effect = { Type = "Boost", Stat = "XP", Multiplier = 2, Duration = 900 } },

	-- Currency bundles
	{ Id = "GemPouch", Name = "Gem Pouch", Category = "Consumable", Rarity = "Rare", Description = "Open for 50 Gems.", MaxStack = 999, Usable = true, TargetsUnit = false, Effect = { Type = "Currency", Currency = "Gems", Amount = 50 } },
}

Items.List = list
Items.ById = {} :: { [string]: ItemDef }
for _, def in list do
	assert(Items.ById[def.Id] == nil, "Duplicate item id " .. def.Id)
	Items.ById[def.Id] = def
end

Items.Categories = { "Potion", "Material", "Evolution", "Boost", "Consumable" }

function Items.Get(id: string): ItemDef?
	return Items.ById[id]
end

function Items.IsValid(id: any): boolean
	return type(id) == "string" and Items.ById[id] ~= nil
end

return Items
