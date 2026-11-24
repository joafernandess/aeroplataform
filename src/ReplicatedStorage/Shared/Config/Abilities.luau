--[[
	Abilities
	Passive and Special ability definitions. Units reference these by Id.

	Passive `Type` values understood by UnitStats (shared):
	  SelfDamage      - multiplies this unit's damage by (1 + Value)
	  SelfSpeed       - multiplies this unit's attack speed by (1 + Value)
	  SelfCrit        - adds Value to this unit's crit chance
	  TeamDamage      - multiplies damage of every equipped unit by (1 + Value) (applied by CombatService)
	  YenBonus        - adds Value to the player's Yen multiplier while equipped
	  XPBonus         - adds Value to the player's XP multiplier while equipped
	  BossDamage      - multiplies this unit's damage against bosses by (1 + Value)

	Special `Type` values are resolved by the server ability registry (ServerScriptService/Server/Combat/AbilityHandlers).
	New types can be registered there without touching CombatService:
	  Strike   - single target hit for Multiplier x damage
	  Cleave   - hits every enemy within Radius of the target for Multiplier x damage
	  Execute  - Multiplier x damage, doubled when the target is under ExecuteThreshold HP
	  Frenzy   - temporarily multiplies this unit's attack speed by Multiplier for Duration seconds
	  Rally    - temporarily multiplies the whole team's damage by Multiplier for Duration seconds
]]

export type PassiveDef = {
	Id: string,
	Name: string,
	Type: string,
	Value: number,
	Description: string,
}

export type SpecialDef = {
	Id: string,
	Name: string,
	Type: string,
	Cooldown: number,
	Multiplier: number,
	Radius: number?,
	Duration: number?,
	ExecuteThreshold: number?,
	Description: string,
	VFX: string?, -- client-side effect id, resolved by the client (placeholder until assets exist)
}

local Abilities = {}

Abilities.Passives = {
	Focus = { Id = "Focus", Name = "Focus", Type = "SelfDamage", Value = 0.10, Description = "+10% damage" },
	Discipline = { Id = "Discipline", Name = "Discipline", Type = "SelfSpeed", Value = 0.10, Description = "+10% attack speed" },
	KeenEye = { Id = "KeenEye", Name = "Keen Eye", Type = "SelfCrit", Value = 0.08, Description = "+8% critical chance" },
	Leader = { Id = "Leader", Name = "Leader", Type = "TeamDamage", Value = 0.08, Description = "+8% damage for the whole team" },
	Commander = { Id = "Commander", Name = "Commander", Type = "TeamDamage", Value = 0.15, Description = "+15% damage for the whole team" },
	Treasure = { Id = "Treasure", Name = "Treasure Hunter", Type = "YenBonus", Value = 0.20, Description = "+20% Yen" },
	Mentor = { Id = "Mentor", Name = "Mentor", Type = "XPBonus", Value = 0.20, Description = "+20% XP" },
	Slayer = { Id = "Slayer", Name = "Boss Slayer", Type = "BossDamage", Value = 0.30, Description = "+30% damage against bosses" },
	Awakened = { Id = "Awakened", Name = "Awakened", Type = "SelfDamage", Value = 0.35, Description = "+35% damage" },
} :: { [string]: PassiveDef }

Abilities.Specials = {
	QuickSlash = { Id = "QuickSlash", Name = "Quick Slash", Type = "Strike", Cooldown = 6, Multiplier = 3, Description = "Deals 3x damage to the target", VFX = "Slash" },
	ShadowClone = { Id = "ShadowClone", Name = "Shadow Barrage", Type = "Cleave", Cooldown = 10, Multiplier = 2, Radius = 14, Description = "Deals 2x damage to all enemies near the target", VFX = "Burst" },
	CannonBlast = { Id = "CannonBlast", Name = "Cannon Blast", Type = "Cleave", Cooldown = 12, Multiplier = 2.5, Radius = 18, Description = "Deals 2.5x damage in a large area", VFX = "Explosion" },
	SoulReap = { Id = "SoulReap", Name = "Soul Reap", Type = "Execute", Cooldown = 9, Multiplier = 3, ExecuteThreshold = 0.3, Description = "3x damage, doubled against enemies under 30% HP", VFX = "Slash" },
	Overdrive = { Id = "Overdrive", Name = "Overdrive", Type = "Frenzy", Cooldown = 20, Multiplier = 2, Duration = 5, Description = "Doubles attack speed for 5s", VFX = "Aura" },
	BattleCry = { Id = "BattleCry", Name = "Battle Cry", Type = "Rally", Cooldown = 25, Multiplier = 1.5, Duration = 6, Description = "+50% team damage for 6s", VFX = "Aura" },
	DragonFist = { Id = "DragonFist", Name = "Dragon Fist", Type = "Strike", Cooldown = 8, Multiplier = 5, Description = "Deals 5x damage to the target", VFX = "Burst" },
	MoonCrescent = { Id = "MoonCrescent", Name = "Crescent Moon", Type = "Cleave", Cooldown = 9, Multiplier = 3.5, Radius = 16, Description = "Deals 3.5x damage to all enemies near the target", VFX = "Slash" },
	Judgement = { Id = "Judgement", Name = "Divine Judgement", Type = "Execute", Cooldown = 12, Multiplier = 6, ExecuteThreshold = 0.5, Description = "6x damage, doubled against enemies under 50% HP", VFX = "Explosion" },
} :: { [string]: SpecialDef }

function Abilities.GetPassive(id: string?): PassiveDef?
	return if id then Abilities.Passives[id] else nil
end

function Abilities.GetSpecial(id: string?): SpecialDef?
	return if id then Abilities.Specials[id] else nil
end

return Abilities
