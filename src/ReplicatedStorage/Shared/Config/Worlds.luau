--[[
	Worlds
	Each world is pure data: add a new table here (plus its enemies/units/banner) and every system picks it up.

	Coordinate convention: Y = 3 is "one stud above the ground" (greybox ground top is Y = 2).
	Positions are plain {x, y, z} arrays so the config is Roblox-free. If the map built in Studio contains
	Workspace.Worlds.<WorldId>.Spawn (a BasePart) or Workspace.Worlds.<WorldId>.SpawnAreas.<AreaId>, those parts
	override the coordinates below (see WorldService / EnemyService).

	Fields:
	  Id, Name, Order
	  UnlockCost      { Currency, Amount }
	  Requirements    shared Requirements table ({ Level = n, WorldUnlocked = id, ... })
	  Spawn           player teleport point
	  Banner          Banners id summoned from this world
	  SpawnAreas      { { Id, Center, Radius, MaxEnemies, Enemies = { [enemyId] = weight } } }
	  Bosses          { { Enemy, Position } }
	  NPCs            { { Id, Name, Role, Position } } Role: "Summon" | "Quest" | "Shop" | "Upgrade" | "Raid" | "Teleport"
	  ClearReward     optional rewards granted once when the world's boss is first killed
]]

export type Vec = { number }
export type SpawnArea = { Id: string, Name: string, Center: Vec, Radius: number, MaxEnemies: number, Enemies: { [string]: number } }
export type WorldDef = {
	Id: string,
	Name: string,
	Order: number,
	UnlockCost: { Currency: string, Amount: number },
	Requirements: { [string]: any },
	Spawn: Vec,
	Banner: string,
	SpawnAreas: { SpawnArea },
	Bosses: { { Enemy: string, Position: Vec } },
	NPCs: { { Id: string, Name: string, Role: string, Position: Vec } },
	ClearReward: { [string]: any }?,
	Theme: { number },
}

local Worlds = {}

local SPACING = 1000 -- studs between world origins on the X axis (greybox layout)

local function origin(order: number): number
	return (order - 1) * SPACING
end

local function makeWorld(def)
	local x = origin(def.Order)
	def.Spawn = def.Spawn or { x, 5, 0 }
	def.SpawnAreas = def.SpawnAreas
		or {
			{ Id = "Field", Name = def.FieldName or "Field", Center = { x + 60, 3, 0 }, Radius = 45, MaxEnemies = 12, Enemies = def.FieldEnemies },
			{ Id = "Camp", Name = def.CampName or "Camp", Center = { x + 150, 3, 60 }, Radius = 30, MaxEnemies = 5, Enemies = def.CampEnemies },
		}
	def.Bosses = def.Bosses or {}
	for _, boss in def.BossList or {} do
		table.insert(def.Bosses, { Enemy = boss[1], Position = { x + boss[2], 3, boss[3] } })
	end
	def.NPCs = def.NPCs
		or {
			{ Id = def.Id .. "_Summon", Name = "Summoner", Role = "Summon", Position = { x - 25, 3, -20 } },
			{ Id = def.Id .. "_Quest", Name = "Quest Master", Role = "Quest", Position = { x - 25, 3, 0 } },
			{ Id = def.Id .. "_Shop", Name = "Merchant", Role = "Shop", Position = { x - 25, 3, 20 } },
			{ Id = def.Id .. "_Upgrade", Name = "Trainer", Role = "Upgrade", Position = { x - 40, 3, 10 } },
			{ Id = def.Id .. "_Teleport", Name = "Portal", Role = "Teleport", Position = { x - 40, 3, -10 } },
		}
	def.Requirements = def.Requirements or {}
	def.FieldEnemies = nil
	def.CampEnemies = nil
	def.FieldName = nil
	def.CampName = nil
	def.BossList = nil
	return def
end

local list: { WorldDef } = {
	makeWorld({
		Id = "W1", Name = "Shinobi Valley", Order = 1, Banner = "B_W1", Theme = { 120, 200, 110 },
		FieldName = "Bandit Fields", CampName = "Ninja Camp",
		UnlockCost = { Currency = "Yen", Amount = 0 },
		FieldEnemies = { W1_Bandit = 70, W1_RogueNinja = 30 },
		CampEnemies = { W1_RogueNinja = 70, W1_MaskedElite = 30 },
		BossList = { { "W1_SnakeSage", 220, -80 }, { "W1_NineTails", 300, 0 } },
		ClearReward = { Gems = 50 },
	}),
	makeWorld({
		Id = "W2", Name = "Tidebreaker Isles", Order = 2, Banner = "B_W2", Theme = { 80, 170, 230 },
		UnlockCost = { Currency = "Yen", Amount = 25000 },
		Requirements = { Level = 10, WorldUnlocked = "W1" },
		FieldEnemies = { W2_Pirate = 70, W2_Marine = 30 },
		CampEnemies = { W2_Marine = 70, W2_Commodore = 30 },
		BossList = { { "W2_Warlord", 220, -80 }, { "W2_Kraken", 300, 0 } },
		ClearReward = { Gems = 75 },
	}),
	makeWorld({
		Id = "W3", Name = "Spirit Academy", Order = 3, Banner = "B_W3", Theme = { 230, 230, 240 },
		UnlockCost = { Currency = "Yen", Amount = 400000 },
		Requirements = { Level = 25, WorldUnlocked = "W2" },
		FieldEnemies = { W3_Hollow = 70, W3_Arrancar = 30 },
		CampEnemies = { W3_Arrancar = 70, W3_Captain = 30 },
		BossList = { { "W3_Espada", 220, -80 }, { "W3_SoulKing", 300, 0 } },
		ClearReward = { Gems = 100 },
	}),
	makeWorld({
		Id = "W4", Name = "Hero Metropolis", Order = 4, Banner = "B_W4", Theme = { 240, 190, 70 },
		UnlockCost = { Currency = "Yen", Amount = 6000000 },
		Requirements = { Level = 45, WorldUnlocked = "W3" },
		FieldEnemies = { W4_Thug = 70, W4_Villain = 30 },
		CampEnemies = { W4_Villain = 70, W4_Nomu = 30 },
		BossList = { { "W4_Overseer", 220, -80 }, { "W4_AllEater", 300, 0 } },
		ClearReward = { Gems = 150 },
	}),
	makeWorld({
		Id = "W5", Name = "Crimson Forest", Order = 5, Banner = "B_W5", Theme = { 170, 30, 50 },
		UnlockCost = { Currency = "Yen", Amount = 90000000 },
		Requirements = { Level = 70, WorldUnlocked = "W4" },
		FieldEnemies = { W5_LesserDemon = 70, W5_Demon = 30 },
		CampEnemies = { W5_Demon = 70, W5_LowerMoon = 30 },
		BossList = { { "W5_UpperMoon", 220, -80 }, { "W5_DemonKing", 300, 0 } },
		ClearReward = { Gems = 250 },
	}),
}

table.sort(list, function(a, b)
	return a.Order < b.Order
end)

Worlds.List = list
Worlds.ById = {} :: { [string]: WorldDef }
for _, def in list do
	assert(Worlds.ById[def.Id] == nil, "Duplicate world id " .. def.Id)
	Worlds.ById[def.Id] = def
end

-- Raid arenas live far away from the worlds so they never overlap.
Worlds.RaidArenaOrigin = { 0, 3, 3000 }

function Worlds.Get(id: string): WorldDef?
	return Worlds.ById[id]
end

function Worlds.IsValid(id: any): boolean
	return type(id) == "string" and Worlds.ById[id] ~= nil
end

function Worlds.GetPrevious(id: string): WorldDef?
	local def = Worlds.ById[id]
	if not def then
		return nil
	end
	local best = nil
	for _, other in list do
		if other.Order < def.Order and (best == nil or other.Order > best.Order) then
			best = other
		end
	end
	return best
end

return Worlds
