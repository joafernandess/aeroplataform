--[[
	Rarities
	Ordered rarity tiers. `Order` is used for comparisons ("Rare or better"), so it must be unique and increasing.
	Color is stored as RGB numbers so this module stays free of Roblox datatypes (testable outside Roblox).
]]

export type RarityDef = {
	Id: string,
	Order: number,
	Color: { number },
	MaxLevel: number,
	XPCurveMultiplier: number,
	FeedXP: number, -- XP given when this unit is used as fusion fodder
	SellValue: number, -- Yen given when deleted
	Summonable: boolean,
}

local list: { RarityDef } = {
	{ Id = "Common", Order = 1, Color = { 190, 190, 190 }, MaxLevel = 25, XPCurveMultiplier = 1.0, FeedXP = 40, SellValue = 10, Summonable = true },
	{ Id = "Rare", Order = 2, Color = { 70, 150, 255 }, MaxLevel = 35, XPCurveMultiplier = 1.15, FeedXP = 120, SellValue = 35, Summonable = true },
	{ Id = "Epic", Order = 3, Color = { 170, 80, 255 }, MaxLevel = 45, XPCurveMultiplier = 1.3, FeedXP = 400, SellValue = 120, Summonable = true },
	{ Id = "Legendary", Order = 4, Color = { 255, 190, 40 }, MaxLevel = 60, XPCurveMultiplier = 1.5, FeedXP = 1500, SellValue = 500, Summonable = true },
	{ Id = "Mythical", Order = 5, Color = { 255, 70, 90 }, MaxLevel = 75, XPCurveMultiplier = 1.75, FeedXP = 5000, SellValue = 2000, Summonable = true },
	{ Id = "Secret", Order = 6, Color = { 20, 20, 20 }, MaxLevel = 90, XPCurveMultiplier = 2.0, FeedXP = 15000, SellValue = 8000, Summonable = true },
	{ Id = "Divine", Order = 7, Color = { 255, 255, 160 }, MaxLevel = 100, XPCurveMultiplier = 2.3, FeedXP = 40000, SellValue = 20000, Summonable = true },
	{ Id = "Exclusive", Order = 8, Color = { 0, 255, 200 }, MaxLevel = 100, XPCurveMultiplier = 2.3, FeedXP = 40000, SellValue = 20000, Summonable = false },
}

local Rarities = {}
Rarities.List = list
Rarities.ById = {} :: { [string]: RarityDef }

for _, def in list do
	Rarities.ById[def.Id] = def
end

function Rarities.Get(id: string): RarityDef?
	return Rarities.ById[id]
end

function Rarities.IsValid(id: any): boolean
	return type(id) == "string" and Rarities.ById[id] ~= nil
end

function Rarities.GetOrder(id: string): number
	local def = Rarities.ById[id]
	return if def then def.Order else 0
end

-- True when `a` is the same tier as or better than `b`.
function Rarities.AtLeast(a: string, b: string): boolean
	return Rarities.GetOrder(a) >= Rarities.GetOrder(b)
end

return Rarities
