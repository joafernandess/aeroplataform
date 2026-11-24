--[[
	AbilityHandlers
	Registry of special-ability behaviours keyed by Abilities.Specials[*].Type.

	A handler receives a context and returns true when the ability was cast:
	  ctx.Player, ctx.Unit, ctx.Stats (UnitStats), ctx.Special (definition), ctx.Target (enemy), ctx.Now
	  ctx.ZoneKey, ctx.UnitState, ctx.PlayerState
	  ctx.DealDamage(enemy, multiplier, isSpecial?) -> damageDealt
	  ctx.FindInRadius(center, radius) -> { enemy }

	Adding a new ability style = AbilityHandlers.Register("MyType", function(ctx) ... end); no change to
	CombatService is required.
]]

local AbilityHandlers = {}

local handlers: { [string]: (ctx: any) -> boolean } = {}

function AbilityHandlers.Register(abilityType: string, handler: (ctx: any) -> boolean)
	assert(type(abilityType) == "string" and type(handler) == "function", "Invalid ability handler")
	handlers[abilityType] = handler
end

function AbilityHandlers.Has(abilityType: string): boolean
	return handlers[abilityType] ~= nil
end

function AbilityHandlers.Execute(ctx): boolean
	local handler = handlers[ctx.Special.Type]
	if not handler then
		warn("[AbilityHandlers] No handler for ability type " .. tostring(ctx.Special.Type))
		return false
	end
	return handler(ctx)
end

-- Built-in types ---------------------------------------------------------------------------------------

AbilityHandlers.Register("Strike", function(ctx)
	ctx.DealDamage(ctx.Target, ctx.Special.Multiplier, true)
	return true
end)

AbilityHandlers.Register("Cleave", function(ctx)
	local center = ctx.Target.Position
	for _, enemy in ctx.FindInRadius(center, ctx.Special.Radius or 10) do
		ctx.DealDamage(enemy, ctx.Special.Multiplier, true)
	end
	return true
end)

AbilityHandlers.Register("Execute", function(ctx)
	local target = ctx.Target
	local multiplier = ctx.Special.Multiplier
	if target.Health / target.MaxHealth <= (ctx.Special.ExecuteThreshold or 0.25) then
		multiplier *= 2
	end
	ctx.DealDamage(target, multiplier, true)
	return true
end)

AbilityHandlers.Register("Frenzy", function(ctx)
	ctx.UnitState.SpeedBuff = { Multiplier = ctx.Special.Multiplier, ExpiresAt = ctx.Now + (ctx.Special.Duration or 5) }
	ctx.DealDamage(ctx.Target, 1, false)
	return true
end)

AbilityHandlers.Register("Rally", function(ctx)
	ctx.PlayerState.TeamBuff = { Multiplier = ctx.Special.Multiplier, ExpiresAt = ctx.Now + (ctx.Special.Duration or 5) }
	ctx.DealDamage(ctx.Target, 1, false)
	return true
end)

return AbilityHandlers
