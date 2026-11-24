--[[
	BoostService
	Single source of truth for player multipliers. Combines:
	  permanent upgrades (ProgressionService data) x timed boosts (items) x global events x game passes
	  + additive bonuses from equipped units (traits/passives such as "Golden" or "Treasure Hunter").

	  Boost:GetMultiplier(player, stat) -> number      stat: "Damage" | "Yen" | "XP" | "Luck" | "Gold"
	  Boost:Activate(player, stat, multiplier, duration) -> (ok, boost)
	  Boost:GetActive(player) -> { [stat] = { Multiplier, ExpiresAt } }

	Timed boosts store an absolute ExpiresAt (unix time), so they keep ticking while offline.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Modules.Formulas)
local Clock = require(Shared.Modules.Clock)

local BoostService = {
	Name = "BoostService",
	Priority = 3,
}

BoostService.Stats = { Damage = true, Yen = true, XP = true, Luck = true, Gold = true }

local UPGRADE_FOR_STAT = { Damage = "Damage", Yen = "Yen", XP = "XP", Luck = "Luck" }
local PASS_PERK_FOR_STAT = { Damage = "DamageMultiplier", Yen = "YenMultiplier", Luck = "LuckMultiplier" }

local DataService

local function pruneExpired(player, data): boolean
	local now = Clock.Now()
	local changed = false
	for stat, boost in data.ActiveBoosts do
		if type(boost) ~= "table" or (boost.ExpiresAt or 0) <= now then
			data.ActiveBoosts[stat] = nil
			changed = true
		end
	end
	if changed then
		DataService:MarkDirty(player, "ActiveBoosts")
	end
	return changed
end

function BoostService:GetActive(player)
	local data = DataService:GetData(player)
	if not data then
		return {}
	end
	pruneExpired(player, data)
	return data.ActiveBoosts
end

function BoostService:Activate(player, stat: string, multiplier: number, duration: number): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	if not BoostService.Stats[stat] or type(multiplier) ~= "number" or multiplier <= 1 or type(duration) ~= "number" or duration <= 0 then
		return false, "InvalidArguments"
	end
	pruneExpired(player, data)
	local now = Clock.Now()
	local current = data.ActiveBoosts[stat]
	if current then
		-- Same stat: keep the strongest multiplier and stack the remaining time.
		current.Multiplier = math.max(current.Multiplier, multiplier)
		current.ExpiresAt += duration
	else
		current = { Multiplier = multiplier, ExpiresAt = now + duration }
		data.ActiveBoosts[stat] = current
	end
	DataService:MarkDirty(player, "ActiveBoosts")
	return true, current
end

function BoostService:GetMultiplier(player, stat: string): number
	local data = DataService:GetData(player)
	if not data then
		return 1
	end
	local services = self.Services
	local multiplier = 1

	local upgradeId = UPGRADE_FOR_STAT[stat]
	if upgradeId then
		multiplier *= Formulas.UpgradeMultiplier(upgradeId, data.Upgrades[upgradeId] or 0)
	end

	local boost = data.ActiveBoosts[stat]
	if boost and (boost.ExpiresAt or 0) > Clock.Now() then
		multiplier *= boost.Multiplier
	end

	if services.EventService then
		multiplier *= services.EventService:GetModifier(stat)
	end

	local perk = PASS_PERK_FOR_STAT[stat]
	if perk and services.ShopService then
		multiplier *= services.ShopService:GetPerkValue(player, perk, 1)
	end

	-- Additive bonuses from equipped units (e.g. +20% Yen) applied as one extra factor.
	if (stat == "Yen" or stat == "XP") and services.UnitService then
		local bonuses = services.UnitService:GetEquippedBonuses(player)
		multiplier *= 1 + (if stat == "Yen" then bonuses.YenBonus else bonuses.XPBonus)
	end

	return multiplier
end

function BoostService:Init(services)
	self.Services = services
	DataService = services.DataService
end

return BoostService
