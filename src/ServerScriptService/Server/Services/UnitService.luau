--[[
	UnitService
	Owns unit instances: creation, equip/unequip, lock, delete (sell), XP/levels, fusion, evolution, traits.

	Unit instance (persisted in Inventory.Units[uid]):
	  { Uid, UnitId, Level, XP, Stars, Trait?, Locked, ObtainedAt, Source }

	Rules:
	  - Fusion: fodder units are consumed and give XP to the target. Fodder with the same UnitId as the
	    target also grants +1 Star each (up to GameConfig.Units.MaxStars). Locked/equipped units are never
	    consumed.
	  - Evolution: a max-level unit with an `EvolvesTo` definition can evolve by paying its EvolutionCost.
	    The unit keeps its uid, stars, trait and lock; level/XP reset to 1/0 in its evolved form.
	  - Units above storage capacity can only come from rewards/purchases (IgnoreCapacity); summoning
	    checks capacity up-front.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Features = require(Shared.Config.Features)
local GameConfig = require(Shared.Config.GameConfig)
local Units = require(Shared.Config.Units)
local Traits = require(Shared.Config.Traits)
local Formulas = require(Shared.Modules.Formulas)
local UnitStats = require(Shared.Modules.UnitStats)
local Signal = require(Shared.Modules.Signal)
local Clock = require(Shared.Modules.Clock)
local RNG = require(Shared.Modules.RNG)
local Validate = require(Shared.Modules.Validate)
local Net = require(Shared.Remotes.Net)

local UNITS = GameConfig.Units

local UnitService = {
	Name = "UnitService",
	Priority = 5,
}

UnitService.UnitAdded = Signal.new() -- (player, unit)
UnitService.UnitRemoved = Signal.new() -- (player, uid)
UnitService.UnitLeveled = Signal.new() -- (player, unit, levelsGained)
UnitService.UnitEvolved = Signal.new() -- (player, unit, fromUnitId)
UnitService.UnitsFused = Signal.new() -- (player, unit, fodderCount)
UnitService.EquippedChanged = Signal.new() -- (player, equippedUids)

-- Server-side RNG; tests may replace it with a seeded generator.
UnitService.Random = nil :: any

local DataService, EconomyService, InventoryService

local function getUnit(player, uid: string)
	local data = DataService:GetData(player)
	if not data then
		return nil, nil
	end
	return data.Inventory.Units[uid], data
end

local function isEquipped(data, uid: string): boolean
	return table.find(data.EquippedUnits, uid) ~= nil
end

function UnitService:RollTrait(): string?
	if not Features.Traits then
		return nil
	end
	local weights = { [""] = Traits.NoTraitWeight }
	for _, def in Traits.List do
		weights[def.Id] = def.Weight
	end
	local pick = RNG.WeightedPick(self.Random, weights)
	if pick == nil or pick == "" then
		return nil
	end
	return pick
end

-- Creation ---------------------------------------------------------------------------------------

function UnitService:CreateUnit(player, unitId: string, options: { Source: string?, IgnoreCapacity: boolean?, Trait: string?, Level: number? }?): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local def = Units.Get(unitId)
	if not def then
		return false, "UnitNotFound"
	end
	options = options or {}
	if not options.IgnoreCapacity and not InventoryService:HasUnitSpace(player, 1) then
		return false, "InventoryFull"
	end
	local uid = "U" .. tostring(data.NextUnitSerial)
	data.NextUnitSerial += 1
	local trait = options.Trait
	if trait == nil then
		trait = self:RollTrait()
	elseif not Traits.IsValid(trait) then
		trait = nil
	end
	local unit = {
		Uid = uid,
		UnitId = unitId,
		Level = math.clamp(options.Level or 1, 1, Formulas.UnitMaxLevel(def.Rarity)),
		XP = 0,
		Stars = 0,
		Trait = trait,
		Locked = false,
		ObtainedAt = Clock.Now(),
		Source = options.Source or "Unknown",
	}
	data.Inventory.Units[uid] = unit
	data.Stats.UnitsObtained += 1
	DataService:MarkDirty(player, "Inventory")
	UnitService.UnitAdded:Fire(player, unit)
	return true, unit
end

-- Queries -------------------------------------------------------------------------------------------

function UnitService:GetUnit(player, uid: string)
	return (getUnit(player, uid))
end

function UnitService:GetEquippedUnits(player): { any }
	local data = DataService:GetData(player)
	if not data then
		return {}
	end
	-- Only the first GetEquipSlots() units count: if slots shrink (e.g. a game pass is refunded) the extra
	-- equipped units stay in the list but don't fight until the player re-arranges them.
	local slots = self:GetEquipSlots(player)
	local out = {}
	for _, uid in data.EquippedUnits do
		local unit = data.Inventory.Units[uid]
		if unit then
			table.insert(out, unit)
			if #out >= slots then
				break
			end
		end
	end
	return out
end

function UnitService:GetEquipSlots(player): number
	local data = DataService:GetData(player)
	if not data then
		return 0
	end
	local bonus = 0
	if self.Services.ShopService then
		bonus = self.Services.ShopService:GetPerkValue(player, "ExtraEquipSlots", 0)
	end
	return Formulas.EquipSlots(data.Upgrades.EquipSlots or 0, bonus)
end

-- Sum of the player-wide bonuses granted by equipped units (traits + passives).
function UnitService:GetEquippedBonuses(player): { YenBonus: number, XPBonus: number, TeamDamageBonus: number }
	local totals = { YenBonus = 0, XPBonus = 0, TeamDamageBonus = 0 }
	for _, unit in self:GetEquippedUnits(player) do
		local stats = UnitStats.Compute(unit)
		if stats then
			totals.YenBonus += stats.YenBonus
			totals.XPBonus += stats.XPBonus
			totals.TeamDamageBonus += stats.TeamDamageBonus
		end
	end
	return totals
end

-- Equip ------------------------------------------------------------------------------------------------

local function equippedChanged(player, data)
	DataService:MarkDirty(player, "EquippedUnits")
	UnitService.EquippedChanged:Fire(player, data.EquippedUnits)
end

function UnitService:Equip(player, uid: string): (boolean, any)
	local unit, data = getUnit(player, uid)
	if not data then
		return false, "DataNotLoaded"
	end
	if not unit then
		return false, "UnitNotFound"
	end
	if isEquipped(data, uid) then
		return false, "AlreadyEquipped"
	end
	if #data.EquippedUnits >= self:GetEquipSlots(player) then
		return false, "EquipLimit"
	end
	table.insert(data.EquippedUnits, uid)
	equippedChanged(player, data)
	return true, data.EquippedUnits
end

function UnitService:Unequip(player, uid: string): (boolean, any)
	local _, data = getUnit(player, uid)
	if not data then
		return false, "DataNotLoaded"
	end
	local index = table.find(data.EquippedUnits, uid)
	if not index then
		return false, "NotEquipped"
	end
	table.remove(data.EquippedUnits, index)
	equippedChanged(player, data)
	return true, data.EquippedUnits
end

function UnitService:EquipBest(player): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local ranked = {}
	for uid, unit in data.Inventory.Units do
		local stats = UnitStats.Compute(unit)
		if stats then
			table.insert(ranked, { Uid = uid, Power = stats.Power })
		end
	end
	table.sort(ranked, function(a, b)
		if a.Power == b.Power then
			return a.Uid < b.Uid
		end
		return a.Power > b.Power
	end)
	local slots = self:GetEquipSlots(player)
	local equipped = {}
	for i = 1, math.min(slots, #ranked) do
		table.insert(equipped, ranked[i].Uid)
	end
	data.EquippedUnits = equipped
	equippedChanged(player, data)
	return true, equipped
end

function UnitService:UnequipAll(player): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	data.EquippedUnits = {}
	equippedChanged(player, data)
	return true, data.EquippedUnits
end

function UnitService:SetLocked(player, uid: string, locked: boolean): (boolean, any)
	local unit, data = getUnit(player, uid)
	if not data then
		return false, "DataNotLoaded"
	end
	if not unit then
		return false, "UnitNotFound"
	end
	unit.Locked = locked == true
	DataService:MarkDirty(player, "Inventory")
	return true, unit.Locked
end

-- Removal -----------------------------------------------------------------------------------------------

-- Internal: removes a unit without any checks or payouts.
function UnitService:_removeUnit(player, data, uid: string)
	data.Inventory.Units[uid] = nil
	local index = table.find(data.EquippedUnits, uid)
	if index then
		table.remove(data.EquippedUnits, index)
		equippedChanged(player, data)
	end
	UnitService.UnitRemoved:Fire(player, uid)
end

-- Deletes (sells) units. Locked/equipped/missing units are skipped and reported.
function UnitService:DeleteUnits(player, uids: { string }): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local deleted, skipped, yen = 0, {}, 0
	for _, uid in uids do
		local unit = data.Inventory.Units[uid]
		if not unit then
			skipped[uid] = "UnitNotFound"
		elseif unit.Locked then
			skipped[uid] = "UnitLocked"
		elseif isEquipped(data, uid) then
			skipped[uid] = "UnitEquipped"
		else
			local def = Units.Get(unit.UnitId)
			yen += Formulas.UnitSellValue(def.Rarity, unit.Level, unit.Stars or 0)
			self:_removeUnit(player, data, uid)
			deleted += 1
		end
	end
	if deleted > 0 then
		DataService:MarkDirty(player, "Inventory")
		if yen > 0 then
			EconomyService:Add(player, "Yen", yen, "SellUnit")
		end
	end
	return true, { Deleted = deleted, Yen = yen, Skipped = skipped }
end

-- Progression ---------------------------------------------------------------------------------------------

function UnitService:AddUnitXP(player, uid: string, amount: number): (boolean, any)
	local unit, data = getUnit(player, uid)
	if not data then
		return false, "DataNotLoaded"
	end
	if not unit then
		return false, "UnitNotFound"
	end
	if type(amount) ~= "number" or amount <= 0 or amount ~= amount then
		return false, "InvalidAmount"
	end
	local def = Units.Get(unit.UnitId)
	local maxLevel = Formulas.UnitMaxLevel(def.Rarity)
	if unit.Level >= maxLevel then
		return false, "MaxLevel"
	end
	unit.XP += math.floor(amount)
	local gained = 0
	while unit.Level < maxLevel do
		local needed = Formulas.UnitXPToNext(unit.Level, def.Rarity)
		if unit.XP < needed then
			break
		end
		unit.XP -= needed
		unit.Level += 1
		gained += 1
	end
	if unit.Level >= maxLevel then
		unit.XP = 0
	end
	DataService:MarkDirty(player, "Inventory")
	if gained > 0 then
		UnitService.UnitLeveled:Fire(player, unit, gained)
	end
	return true, { Level = unit.Level, XP = unit.XP, LevelsGained = gained }
end

-- Gives XP to every equipped unit (used by combat kill rewards). Max-level units are skipped silently.
function UnitService:AddXPToEquipped(player, amount: number)
	for _, unit in self:GetEquippedUnits(player) do
		self:AddUnitXP(player, unit.Uid, amount)
	end
end

function UnitService:Fuse(player, targetUid: string, fodderUids: { string }): (boolean, any)
	if not Features.Fusion then
		return false, "FeatureDisabled"
	end
	local target, data = getUnit(player, targetUid)
	if not data then
		return false, "DataNotLoaded"
	end
	if not target then
		return false, "UnitNotFound"
	end
	if #fodderUids == 0 or #fodderUids > UNITS.MaxFodderPerFuse then
		return false, "InvalidArguments"
	end
	-- Validate everything before consuming anything.
	local fodder = {}
	for _, uid in fodderUids do
		if uid == targetUid then
			return false, "CannotFuse"
		end
		local unit = data.Inventory.Units[uid]
		if not unit then
			return false, "UnitNotFound"
		end
		if unit.Locked then
			return false, "UnitLocked"
		end
		if isEquipped(data, uid) then
			return false, "UnitEquipped"
		end
		table.insert(fodder, unit)
	end

	local def = Units.Get(target.UnitId)
	local maxLevel = Formulas.UnitMaxLevel(def.Rarity)
	local xp, starsGained = 0, 0
	for _, unit in fodder do
		local fodderDef = Units.Get(unit.UnitId)
		if unit.UnitId == target.UnitId and (target.Stars or 0) + starsGained < UNITS.MaxStars then
			starsGained += 1
		end
		xp += Formulas.UnitFeedXP(fodderDef.Rarity, unit.Level)
	end
	if starsGained == 0 and target.Level >= maxLevel then
		return false, "MaxLevel"
	end

	for _, unit in fodder do
		self:_removeUnit(player, data, unit.Uid)
	end
	target.Stars = (target.Stars or 0) + starsGained
	local levelsGained = 0
	if target.Level < maxLevel then
		local _, result = self:AddUnitXP(player, targetUid, xp)
		levelsGained = if type(result) == "table" then result.LevelsGained else 0
	end
	data.Stats.UnitsFused += 1
	DataService:MarkDirty(player, "Inventory")
	UnitService.UnitsFused:Fire(player, target, #fodder)
	return true, { Unit = target, XPGained = xp, StarsGained = starsGained, LevelsGained = levelsGained }
end

function UnitService:Evolve(player, uid: string): (boolean, any)
	if not Features.Evolution then
		return false, "FeatureDisabled"
	end
	local unit, data = getUnit(player, uid)
	if not data then
		return false, "DataNotLoaded"
	end
	if not unit then
		return false, "UnitNotFound"
	end
	local def = Units.Get(unit.UnitId)
	if not def.EvolvesTo or not def.EvolutionCost then
		return false, "CannotEvolve"
	end
	if unit.Level < Formulas.UnitMaxLevel(def.Rarity) then
		return false, "NotMaxLevel"
	end
	local cost = def.EvolutionCost
	if not InventoryService:HasItems(player, cost.Items) then
		return false, "MissingMaterials"
	end
	local fromId = unit.UnitId
	return EconomyService:PurchaseBundle(player, { Yen = cost.Yen or 0, Gold = cost.Gold or 0 }, "Evolve:" .. fromId, function()
		local removed, err = InventoryService:RemoveItems(player, cost.Items)
		if not removed then
			return false, err
		end
		unit.UnitId = def.EvolvesTo
		unit.Level = 1
		unit.XP = 0
		data.Stats.UnitsEvolved += 1
		DataService:MarkDirty(player, "Inventory")
		UnitService.UnitEvolved:Fire(player, unit, fromId)
		return true, unit
	end)
end

function UnitService:RerollTrait(player, uid: string): (boolean, any)
	if not Features.Traits then
		return false, "FeatureDisabled"
	end
	local unit, data = getUnit(player, uid)
	if not data then
		return false, "DataNotLoaded"
	end
	if not unit then
		return false, "UnitNotFound"
	end
	-- Rerolling never yields "no trait": keep rolling until a trait comes up (bounded).
	local trait = nil
	for _ = 1, 50 do
		trait = self:RollTrait()
		if trait then
			break
		end
	end
	unit.Trait = trait or Traits.List[1].Id
	DataService:MarkDirty(player, "Inventory")
	return true, unit.Trait
end

-- Lifecycle --------------------------------------------------------------------------------------------------

function UnitService:Init(services)
	self.Services = services
	DataService = services.DataService
	EconomyService = services.EconomyService
	InventoryService = services.InventoryService
	if not UnitService.Random then
		UnitService.Random = RNG.new()
	end

	DataService.ProfileLoaded:Connect(function(player, profile)
		if profile.IsNew then
			for _, unitId in GameConfig.Start.StarterUnits do
				local ok, unit = self:CreateUnit(player, unitId, { Source = "Starter", IgnoreCapacity = true })
				if ok then
					self:Equip(player, unit.Uid)
				end
			end
		end
	end)

	Net.Handle("EquipUnit", function(player, uid)
		if not Validate.UnitUid(uid) then
			return false, "InvalidArguments"
		end
		return self:Equip(player, uid)
	end)
	Net.Handle("UnequipUnit", function(player, uid)
		if not Validate.UnitUid(uid) then
			return false, "InvalidArguments"
		end
		return self:Unequip(player, uid)
	end)
	Net.Handle("EquipBest", function(player)
		return self:EquipBest(player)
	end, { RateLimit = 2 })
	Net.Handle("UnequipAll", function(player)
		return self:UnequipAll(player)
	end, { RateLimit = 2 })
	Net.Handle("LockUnit", function(player, uid, locked)
		if not Validate.UnitUid(uid) or not Validate.Boolean(locked) then
			return false, "InvalidArguments"
		end
		return self:SetLocked(player, uid, locked)
	end)
	Net.Handle("DeleteUnits", function(player, uids)
		if not Validate.UnitUidList(uids, UNITS.MaxDeletePerRequest) then
			return false, "InvalidArguments"
		end
		return self:DeleteUnits(player, uids)
	end, { RateLimit = 3 })
	Net.Handle("FuseUnits", function(player, targetUid, fodderUids)
		if not Validate.UnitUid(targetUid) or not Validate.UnitUidList(fodderUids, UNITS.MaxFodderPerFuse) then
			return false, "InvalidArguments"
		end
		return self:Fuse(player, targetUid, fodderUids)
	end, { RateLimit = 3 })
	Net.Handle("EvolveUnit", function(player, uid)
		if not Validate.UnitUid(uid) then
			return false, "InvalidArguments"
		end
		return self:Evolve(player, uid)
	end, { RateLimit = 2 })
end

return UnitService
