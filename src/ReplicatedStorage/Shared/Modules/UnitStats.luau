--[[
	UnitStats
	Computes the effective stats of a unit instance (definition + level + stars + trait + passive).
	Shared so the UI shows exactly what the server uses. Player-wide multipliers (upgrades, boosts,
	events, team passives) are applied on top by CombatService.
]]

local Config = script.Parent.Parent.Config
local GameConfig = require(Config.GameConfig)
local Units = require(Config.Units)
local Traits = require(Config.Traits)
local Abilities = require(Config.Abilities)
local Formulas = require(script.Parent.Formulas)

export type Stats = {
	Damage: number,
	AttackSpeed: number,
	Range: number,
	CritChance: number,
	BossDamageMultiplier: number,
	TeamDamageBonus: number,
	YenBonus: number,
	XPBonus: number,
	Power: number,
}

local UnitStats = {}

function UnitStats.Compute(instance: { UnitId: string, Level: number?, Stars: number?, Trait: string? }): Stats?
	local def = Units.Get(instance.UnitId)
	if not def then
		return nil
	end
	local level = instance.Level or 1
	local stars = instance.Stars or 0

	local damage = def.BaseDamage * Formulas.LevelDamageMultiplier(level) * Formulas.StarDamageMultiplier(stars)
	local attackSpeed = def.AttackSpeed
	local range = def.Range
	local crit = GameConfig.Combat.BaseCritChance + def.CritChance
	local bossMult, teamBonus, yenBonus, xpBonus = 1, 0, 0, 0

	local trait = if instance.Trait then Traits.Get(instance.Trait) else nil
	if trait then
		local m = trait.Modifiers
		damage *= m.DamageMultiplier or 1
		attackSpeed *= m.AttackSpeedMultiplier or 1
		range *= m.RangeMultiplier or 1
		crit += m.CritChance or 0
		yenBonus += m.YenBonus or 0
		xpBonus += m.XPBonus or 0
	end

	local passive = Abilities.GetPassive(def.Passive)
	if passive then
		if passive.Type == "SelfDamage" then
			damage *= 1 + passive.Value
		elseif passive.Type == "SelfSpeed" then
			attackSpeed *= 1 + passive.Value
		elseif passive.Type == "SelfCrit" then
			crit += passive.Value
		elseif passive.Type == "TeamDamage" then
			teamBonus += passive.Value
		elseif passive.Type == "YenBonus" then
			yenBonus += passive.Value
		elseif passive.Type == "XPBonus" then
			xpBonus += passive.Value
		elseif passive.Type == "BossDamage" then
			bossMult += passive.Value
		end
	end

	local combat = GameConfig.Combat
	attackSpeed = math.clamp(attackSpeed, combat.MinAttackSpeed, combat.MaxAttackSpeed)
	crit = math.clamp(crit, 0, combat.MaxCritChance)

	local expectedCrit = 1 + crit * (combat.BaseCritMultiplier - 1)
	return {
		Damage = damage,
		AttackSpeed = attackSpeed,
		Range = range,
		CritChance = crit,
		BossDamageMultiplier = bossMult,
		TeamDamageBonus = teamBonus,
		YenBonus = yenBonus,
		XPBonus = xpBonus,
		-- Single comparable number (expected damage per second, ignoring specials). Used by "Equip Best".
		Power = math.floor(damage * attackSpeed * expectedCrit * (1 + teamBonus)),
	}
end

export type StatDiff = { Stat: string, A: number, B: number, Difference: number, Better: string }

local COMPARED = { "Power", "Damage", "AttackSpeed", "Range", "CritChance" }

-- Returns per-stat differences between two unit instances. `Better` is "A", "B" or "Equal".
function UnitStats.Compare(a, b): { StatDiff }?
	local sa, sb = UnitStats.Compute(a), UnitStats.Compute(b)
	if not sa or not sb then
		return nil
	end
	local out = {}
	for _, stat in COMPARED do
		local va, vb = (sa :: any)[stat], (sb :: any)[stat]
		table.insert(out, {
			Stat = stat,
			A = va,
			B = vb,
			Difference = vb - va,
			Better = if va > vb then "A" elseif vb > va then "B" else "Equal",
		})
	end
	return out
end

return UnitStats
