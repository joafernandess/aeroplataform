--[[
	CombatService
	Server-side combat simulation. Units are virtual attackers that orbit the player's character; the
	server decides every hit. The client only chooses a target (SetTarget) and renders effects.

	Per tick (GameConfig.Combat.TickRate):
	  for each player with a character:
	    for each equipped unit whose attack timer is ready:
	      target = manual target (if alive, same zone, in range)  or  nearest enemy in range (AutoAttack)
	      if the unit's special is off cooldown -> AbilityHandlers.Execute (Strike/Cleave/Execute/...)
	      else -> normal hit
	Damage = UnitStats.Damage x player Damage multiplier (upgrades/boosts/events/passes)
	         x (1 + team passives) x active Rally buff x boss bonus x crit
	Ranges are measured from the player's HumanoidRootPart.

	Damage numbers are batched per player and sent once per tick (DamageNumbers remote).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Units = require(Shared.Config.Units)
local Abilities = require(Shared.Config.Abilities)
local UnitStats = require(Shared.Modules.UnitStats)
local Clock = require(Shared.Modules.Clock)
local RNG = require(Shared.Modules.RNG)
local Net = require(Shared.Remotes.Net)

local Server = script.Parent.Parent
local AbilityHandlers = require(Server.Combat.AbilityHandlers)
local PlayerUtil = require(Server.Core.PlayerUtil)

local COMBAT = GameConfig.Combat
local IDLE_RECHECK = 0.25

local CombatService = {
	Name = "CombatService",
	Priority = 30,
}

CombatService.Random = nil :: any

local states: { [any]: any } = {}

local DataService, UnitService, EnemyService, BoostService, WorldService

local function getState(player)
	local state = states[player]
	if not state then
		state = { Target = nil, Units = {}, TeamBuff = nil, Numbers = {} }
		states[player] = state
	end
	return state
end

function CombatService:GetState(player)
	return getState(player)
end

function CombatService:ClearTarget(player)
	local state = states[player]
	if state then
		state.Target = nil
	end
end

-- Manual targeting -------------------------------------------------------------------------------------

function CombatService:SetTarget(player, runtimeId: string?): (boolean, string?)
	local state = getState(player)
	if runtimeId == nil then
		state.Target = nil
		return true, nil
	end
	local enemy = EnemyService:GetEnemy(runtimeId)
	if not enemy or not enemy.Alive then
		return false, "EnemyNotFound"
	end
	if enemy.ZoneKey ~= WorldService:GetZoneKey(player) then
		return false, "EnemyNotFound"
	end
	local position = PlayerUtil.GetPosition(player)
	if not position or (enemy.Position - position).Magnitude > COMBAT.MaxTargetSelectDistance then
		return false, "OutOfRange"
	end
	state.Target = runtimeId
	return true, nil
end

-- Damage -------------------------------------------------------------------------------------------------

local function pushNumber(state, enemy, amount, crit, special)
	if #state.Numbers < COMBAT.DamageNumberBatchLimit then
		table.insert(state.Numbers, { Enemy = enemy.Id, Amount = amount, Crit = crit, Special = special })
	end
end

-- Builds the per-tick multiplier shared by every unit of the player.
function CombatService:GetPlayerDamageMultiplier(player, state, now: number): number
	local multiplier = BoostService:GetMultiplier(player, "Damage")
	local bonuses = UnitService:GetEquippedBonuses(player)
	multiplier *= 1 + bonuses.TeamDamageBonus
	local buff = state.TeamBuff
	if buff then
		if buff.ExpiresAt > now then
			multiplier *= buff.Multiplier
		else
			state.TeamBuff = nil
		end
	end
	return multiplier
end

function CombatService:_dealDamage(player, state, stats, playerMultiplier: number, enemy, abilityMultiplier: number, isSpecial: boolean): number
	if not enemy.Alive then
		return 0
	end
	local damage = stats.Damage * playerMultiplier * abilityMultiplier
	if enemy.Def.IsBoss then
		damage *= stats.BossDamageMultiplier
	end
	local crit = RNG.Chance(self.Random, stats.CritChance)
	if crit then
		damage *= COMBAT.BaseCritMultiplier
	end
	local dealt = EnemyService:ApplyDamage(player, enemy, damage)
	if dealt > 0 then
		pushNumber(state, enemy, dealt, crit, isSpecial)
	end
	return dealt
end

function CombatService:_resolveTarget(_player, state, zoneKey: string, origin: Vector3, range: number, autoAttack: boolean, autoRange: number?)
	if state.Target then
		local enemy = EnemyService:GetEnemy(state.Target)
		if enemy and enemy.Alive and enemy.ZoneKey == zoneKey then
			if (enemy.Position - origin).Magnitude <= range then
				return enemy
			end
			-- Manual target alive but out of this unit's range: this unit waits (player must move closer).
			return nil
		end
		state.Target = nil
	end
	if autoAttack then
		return EnemyService:FindNearest(zoneKey, origin, autoRange or range)
	end
	return nil
end

function CombatService:StepPlayer(player, now: number)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local origin = PlayerUtil.GetPosition(player)
	if not origin then
		return
	end
	local state = getState(player)
	local zoneKey = WorldService:GetZoneKey(player)
	local autoAttack = data.Settings.AutoAttack ~= false
	local playerMultiplier = nil

	for _, unit in UnitService:GetEquippedUnits(player) do
		local unitState = state.Units[unit.Uid]
		if not unitState then
			unitState = { NextAttack = now, NextSpecial = now + 2, SpeedBuff = nil }
			state.Units[unit.Uid] = unitState
		end
		if now >= unitState.NextAttack then
			local stats = UnitStats.Compute(unit)
			local target = stats
				and self:_resolveTarget(
					player,
					state,
					zoneKey,
					origin,
					math.max(stats.Range, COMBAT.FighterReach),
					autoAttack,
					math.max(stats.Range, COMBAT.AutoTargetRange)
				)
			if not stats or not target then
				unitState.NextAttack = now + IDLE_RECHECK
			else
				playerMultiplier = playerMultiplier or self:GetPlayerDamageMultiplier(player, state, now)
				local speed = stats.AttackSpeed
				local buff = unitState.SpeedBuff
				if buff then
					if buff.ExpiresAt > now then
						speed *= buff.Multiplier
					else
						unitState.SpeedBuff = nil
					end
				end
				unitState.NextAttack = now + 1 / math.clamp(speed, COMBAT.MinAttackSpeed, COMBAT.MaxAttackSpeed * 2)

				local def = Units.Get(unit.UnitId)
				local special = Abilities.GetSpecial(def and def.Special)
				local multiplierForTick = playerMultiplier :: number
				if special and AbilityHandlers.Has(special.Type) and now >= unitState.NextSpecial then
					unitState.NextSpecial = now + special.Cooldown
					AbilityHandlers.Execute({
						Player = player,
						Unit = unit,
						Stats = stats,
						Special = special,
						Target = target,
						Now = now,
						ZoneKey = zoneKey,
						UnitState = unitState,
						PlayerState = state,
						DealDamage = function(enemy, multiplier, isSpecial)
							return self:_dealDamage(player, state, stats, multiplierForTick, enemy, multiplier, isSpecial ~= false)
						end,
						FindInRadius = function(center, radius)
							return EnemyService:FindInRadius(zoneKey, center, radius)
						end,
					})
					Net.Fire(player, "AbilityCast", { UnitUid = unit.Uid, Ability = special.Id, Enemy = target.Id })
				else
					self:_dealDamage(player, state, stats, multiplierForTick, target, 1, false)
				end
			end
		end
	end

	if #state.Numbers > 0 then
		if data.Settings.DamageNumbers ~= false then
			Net.Fire(player, "DamageNumbers", state.Numbers)
		end
		state.Numbers = {}
	end
end

function CombatService:Step(now: number?)
	local t = now or Clock.Precise()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(self.StepPlayer, self, player, t)
		if not ok then
			warn("[CombatService] Step error for " .. tostring(player.Name) .. ": " .. tostring(err))
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------------------------

function CombatService:Init(services)
	self.Services = services
	DataService = services.DataService
	UnitService = services.UnitService
	EnemyService = services.EnemyService
	BoostService = services.BoostService
	WorldService = services.WorldService
	if not CombatService.Random then
		CombatService.Random = RNG.new()
	end

	UnitService.UnitRemoved:Connect(function(player, uid)
		local state = states[player]
		if state then
			state.Units[uid] = nil
		end
	end)
	WorldService.WorldChanged:Connect(function(player)
		self:ClearTarget(player)
	end)

	Net.On("SetTarget", function(player, runtimeId)
		if runtimeId ~= nil and (type(runtimeId) ~= "string" or #runtimeId > 16) then
			return
		end
		self:SetTarget(player, runtimeId)
	end, { RateLimit = 8, Burst = 16 })
end

function CombatService:Start()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	while true do
		self:Step(Clock.Precise())
		task.wait(COMBAT.TickRate)
	end
end

return CombatService
