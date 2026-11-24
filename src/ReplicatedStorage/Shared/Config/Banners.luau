--[[
	Banners (summon tables)
	All probabilities live here and are evaluated ONLY on the server (SummonService). The client may read
	this module to display rates, but never decides results.

	Fields:
	  Id, Name, World (nil for global/event banners)
	  Currency, CostSingle, CostMulti (price of one multi-open of MultiCount units)
	  MultiCount     size of the multi-open (default 10; the world-1 star opens x3)
	  Rates          { [rarity] = weight } — weights, normalised at runtime (they do not need to sum to 100)
	  Pool           { [rarity] = { unitId, ... } } — units obtainable per rarity (uniform pick)
	  Pity           { { Rarity, Threshold } } — after Threshold-1 pulls without >= Rarity, the next pull is forced
	  MultiGuarantee rarity guaranteed at least once in every x10 (nil to disable)
	  Requirements   shared Requirements table checked before summoning
	  StartsAt/EndsAt optional unix times for limited banners
	  LuckAffects    rarities whose weight is multiplied by the player's Luck multiplier
]]

export type PityRule = { Rarity: string, Threshold: number }
export type BannerDef = {
	Id: string,
	Name: string,
	World: string?,
	Currency: string,
	CostSingle: number,
	CostMulti: number,
	Rates: { [string]: number },
	Pool: { [string]: { string } },
	Pity: { PityRule },
	MultiGuarantee: string?,
	Requirements: { [string]: any },
	StartsAt: number?,
	EndsAt: number?,
	LuckAffects: { [string]: boolean },
}

local Rarities = require(script.Parent.Rarities)
local Units = require(script.Parent.Units)

local Banners = {}

local STANDARD_RATES = { Common = 60, Rare = 28, Epic = 9, Legendary = 2.5, Mythical = 0.5 }
local SECRET_RATES = { Common = 59.95, Rare = 28, Epic = 9, Legendary = 2.5, Mythical = 0.5, Secret = 0.05 }
local STANDARD_PITY = { { Rarity = "Legendary", Threshold = 75 }, { Rarity = "Mythical", Threshold = 400 } }
local LUCK = { Epic = true, Legendary = true, Mythical = true, Secret = true, Divine = true }

local list: { BannerDef } = {
	{
		-- World 1 star: paid with Yen dropped by enemies, opens x1 or x3 (core loop of the base game).
		Id = "B_W1", Name = "Shinobi Star", World = "W1", Currency = "Yen", CostSingle = 100, CostMulti = 280, MultiCount = 3,
		Rates = STANDARD_RATES,
		Pool = {
			Common = { "SS_GeninRecruit", "SS_Kenta" },
			Rare = { "SS_Hikari" },
			Epic = { "SS_Tetsuo" },
			Legendary = { "SS_Raizen" },
			Mythical = { "SS_Kurogane" },
		},
		Pity = STANDARD_PITY, Requirements = { WorldUnlocked = "W1" }, LuckAffects = LUCK,
	},
	{
		Id = "B_W2", Name = "Tidebreaker Banner", World = "W2", Currency = "Gems", CostSingle = 60, CostMulti = 540,
		Rates = STANDARD_RATES,
		Pool = {
			Common = { "GT_Deckhand" },
			Rare = { "GT_Mira" },
			Epic = { "GT_Sable" },
			Legendary = { "GT_CaptainRook" },
			Mythical = { "GT_Leviath" },
		},
		Pity = STANDARD_PITY, MultiGuarantee = "Rare", Requirements = { WorldUnlocked = "W2" }, LuckAffects = LUCK,
	},
	{
		Id = "B_W3", Name = "Spirit Academy Banner", World = "W3", Currency = "Gems", CostSingle = 75, CostMulti = 675,
		Rates = SECRET_RATES,
		Pool = {
			Common = { "SR_Initiate" },
			Rare = { "SR_Yuki" },
			Epic = { "SR_Ichigen" },
			Legendary = { "SR_Byakuren" },
			Mythical = { "SR_Aizora" },
			Secret = { "SR_Hollowking" },
		},
		Pity = STANDARD_PITY, MultiGuarantee = "Rare", Requirements = { WorldUnlocked = "W3" }, LuckAffects = LUCK,
	},
	{
		Id = "B_W4", Name = "Hero Metropolis Banner", World = "W4", Currency = "Gems", CostSingle = 90, CostMulti = 810,
		Rates = STANDARD_RATES,
		Pool = {
			Common = { "HR_Sidekick" },
			Rare = { "HR_Volt" },
			Epic = { "HR_IronLady" },
			Legendary = { "HR_Smashman" },
			Mythical = { "HR_Omnipotent" },
		},
		Pity = STANDARD_PITY, MultiGuarantee = "Rare", Requirements = { WorldUnlocked = "W4" }, LuckAffects = LUCK,
	},
	{
		Id = "B_W5", Name = "Crimson Forest Banner", World = "W5", Currency = "Gems", CostSingle = 110, CostMulti = 990,
		Rates = SECRET_RATES,
		Pool = {
			Common = { "CM_Hunter" },
			Rare = { "CM_Nezumi" },
			Epic = { "CM_Tanjo" },
			Legendary = { "CM_Rengar" },
			Mythical = { "CM_Muzan" },
			Secret = { "CM_Eclipse" },
		},
		Pity = STANDARD_PITY, MultiGuarantee = "Rare", Requirements = { WorldUnlocked = "W5" }, LuckAffects = LUCK,
	},
	{
		-- Token banner fed by raids. Divine units only come from here.
		Id = "B_Raid", Name = "Abyss Banner", Currency = "Tokens", CostSingle = 40, CostMulti = 360,
		Rates = { Epic = 70, Legendary = 25, Mythical = 4.9, Divine = 0.1 },
		Pool = {
			Epic = { "SR_Ichigen", "HR_IronLady" },
			Legendary = { "SR_Byakuren", "HR_Smashman" },
			Mythical = { "SR_Aizora", "HR_Omnipotent" },
			Divine = { "DV_Celestia" },
		},
		Pity = { { Rarity = "Mythical", Threshold = 100 }, { Rarity = "Divine", Threshold = 1500 } },
		MultiGuarantee = "Legendary", Requirements = { WorldUnlocked = "W3" }, LuckAffects = LUCK,
	},
}

-- Validate configuration on load: a broken banner should fail loudly in Studio, not at summon time.
for _, banner in list do
	assert(banner.CostSingle > 0 and banner.CostMulti > 0, "Banner costs must be positive: " .. banner.Id)
	for rarity, weight in banner.Rates do
		assert(Rarities.IsValid(rarity), ("Banner %s has invalid rarity %s"):format(banner.Id, rarity))
		assert(type(weight) == "number" and weight >= 0, ("Banner %s has invalid weight for %s"):format(banner.Id, rarity))
		if weight > 0 then
			local pool = banner.Pool[rarity]
			assert(pool and #pool > 0, ("Banner %s has rate for %s but an empty pool"):format(banner.Id, rarity))
		end
	end
	for rarity, pool in banner.Pool do
		for _, unitId in pool do
			local unit = Units.Get(unitId)
			assert(unit, ("Banner %s references unknown unit %s"):format(banner.Id, unitId))
			assert(unit.Rarity == rarity, ("Banner %s lists %s under %s but it is %s"):format(banner.Id, unitId, rarity, unit.Rarity))
		end
	end
	for _, rule in banner.Pity do
		assert(banner.Rates[rule.Rarity], ("Banner %s pity rarity %s has no rate"):format(banner.Id, rule.Rarity))
	end
end

Banners.List = list
Banners.ById = {} :: { [string]: BannerDef }
for _, def in list do
	Banners.ById[def.Id] = def
end

-- A banner can be opened x1 or x MultiCount (default 10).
function Banners.GetMultiCount(banner): number
	return banner.MultiCount or 10
end

function Banners.IsAllowedCount(banner, count: number): boolean
	return count == 1 or count == Banners.GetMultiCount(banner)
end

function Banners.Get(id: string): BannerDef?
	return Banners.ById[id]
end

function Banners.IsValid(id: any): boolean
	return type(id) == "string" and Banners.ById[id] ~= nil
end

-- Returns normalised percentages for UI display ({ [rarity] = percent }).
function Banners.GetDisplayRates(id: string): { [string]: number }
	local def = Banners.ById[id]
	local out = {}
	if not def then
		return out
	end
	local total = 0
	for _, weight in def.Rates do
		total += weight
	end
	for rarity, weight in def.Rates do
		out[rarity] = if total > 0 then weight / total * 100 else 0
	end
	return out
end

return Banners
