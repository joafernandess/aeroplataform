--[[
	Traits
	Random modifiers rolled when a unit is created. A trait may modify any unit stat multiplicatively
	(Damage, AttackSpeed, Range) or additively (CritChance), or add a player-level reward bonus (YenBonus, XPBonus).
	`Weight` is relative; `NoTraitWeight` is the chance weight of rolling no trait at all.
]]

export type TraitDef = {
	Id: string,
	Name: string,
	Weight: number,
	Description: string,
	Modifiers: {
		DamageMultiplier: number?,
		AttackSpeedMultiplier: number?,
		RangeMultiplier: number?,
		CritChance: number?,
		YenBonus: number?,
		XPBonus: number?,
	},
}

local Traits = {}

Traits.NoTraitWeight = 600

Traits.List = {
	{ Id = "Strong", Name = "Strong", Weight = 180, Description = "+10% damage", Modifiers = { DamageMultiplier = 1.10 } },
	{ Id = "Swift", Name = "Swift", Weight = 150, Description = "+15% attack speed", Modifiers = { AttackSpeedMultiplier = 1.15 } },
	{ Id = "Sharp", Name = "Sharp", Weight = 120, Description = "+5% critical chance", Modifiers = { CritChance = 0.05 } },
	{ Id = "Far", Name = "Far-Sighted", Weight = 90, Description = "+25% attack range", Modifiers = { RangeMultiplier = 1.25 } },
	{ Id = "Golden", Name = "Golden", Weight = 60, Description = "+15% Yen from kills", Modifiers = { YenBonus = 0.15 } },
	{ Id = "Scholar", Name = "Scholar", Weight = 60, Description = "+15% XP from kills", Modifiers = { XPBonus = 0.15 } },
	{ Id = "Mighty", Name = "Mighty", Weight = 25, Description = "+35% damage", Modifiers = { DamageMultiplier = 1.35 } },
	{ Id = "Godspeed", Name = "Godspeed", Weight = 10, Description = "+30% attack speed, +10% damage", Modifiers = { AttackSpeedMultiplier = 1.30, DamageMultiplier = 1.10 } },
	{ Id = "Overlord", Name = "Overlord", Weight = 2, Description = "+75% damage, +10% critical chance", Modifiers = { DamageMultiplier = 1.75, CritChance = 0.10 } },
} :: { TraitDef }

Traits.ById = {} :: { [string]: TraitDef }
for _, def in Traits.List do
	Traits.ById[def.Id] = def
end

function Traits.Get(id: string): TraitDef?
	return Traits.ById[id]
end

function Traits.IsValid(id: any): boolean
	return type(id) == "string" and Traits.ById[id] ~= nil
end

return Traits
