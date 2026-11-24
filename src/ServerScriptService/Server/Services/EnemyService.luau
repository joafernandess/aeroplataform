--[[
	EnemyService
	Authoritative enemy state, spawning, damage intake, death and reward distribution.

	Enemies live in "zones": "World:<WorldId>" for world spawns, "Raid:<instanceId>" for raid instances.
	Players only see/target/damage enemies of their current zone (see WorldService:GetZoneKey).

	Runtime enemy (plain table):
	  { Id, Def, ZoneKey, WorldId?, AreaId?, Position: Vector3, Health, MaxHealth, Alive,
	    Contributors = { [player] = damage }, NextAttackAt, Handle (visual), OnDeath? }

	Spawning:
	  - Spawn areas from Config/Worlds keep MaxEnemies alive; each death schedules a respawn after the
	    enemy's RespawnTime.
	  - Boss points spawn one boss each and respawn it after its RespawnTime.
	  - RaidService spawns its own enemies with EnemyService:Spawn(...).

	Rewards on death:
	  - Normal/Elite: the killer receives the rewards.
	  - Boss tiers (SharedRewards): every player who dealt >= RewardContributionThreshold of max HP
	    receives the full rewards (so groups can farm bosses together).
	  Rewards go through EconomyService:GrantRewards (multipliers applied); unit XP goes to equipped units;
	  drops roll independently per player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Enemies = require(Shared.Config.Enemies)
local Worlds = require(Shared.Config.Worlds)
local Formulas = require(Shared.Modules.Formulas)
local Signal = require(Shared.Modules.Signal)
local Clock = require(Shared.Modules.Clock)
local RNG = require(Shared.Modules.RNG)

local Server = script.Parent.Parent
local EnemyVisuals = require(Server.Combat.EnemyVisuals)
local PlayerUtil = require(Server.Core.PlayerUtil)

local EnemyService = {
	Name = "EnemyService",
	Priority = 20,
}

EnemyService.EnemySpawned = Signal.new() -- (enemy)
EnemyService.EnemyKilled = Signal.new() -- (player, enemyDef, enemy) fired once per rewarded player
EnemyService.EnemyDied = Signal.new() -- (enemy, killer)
EnemyService.Random = nil :: any

local STEP_INTERVAL = 0.25

local enemiesById: { [string]: any } = {}
local enemiesByZone: { [string]: { [string]: any } } = {}
local areas: { any } = {}
local bossPoints: { any } = {}
local nextId = 0

local DataService, EconomyService, UnitService, InventoryService, BoostService

local function toVector(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

local function zoneOf(worldId: string): string
	return "World:" .. worldId
end
EnemyService.WorldZone = zoneOf

-- Spawning ----------------------------------------------------------------------------------------

function EnemyService:Spawn(enemyId: string, position: Vector3, zoneKey: string, options: { AreaId: string?, WorldId: string?, OnDeath: ((any, any) -> ())?, HealthMultiplier: number? }?)
	local def = Enemies.Get(enemyId)
	assert(def, "Unknown enemy " .. tostring(enemyId))
	options = options or {}
	nextId += 1
	local maxHealth = math.floor(def.MaxHP * ((options :: any).HealthMultiplier or 1))
	local enemy = {
		Id = "E" .. nextId,
		Def = def,
		ZoneKey = zoneKey,
		WorldId = (options :: any).WorldId,
		AreaId = (options :: any).AreaId,
		Position = position,
		Health = maxHealth,
		MaxHealth = maxHealth,
		Alive = true,
		Contributors = {},
		NextAttackAt = Clock.Precise() + Enemies.Tiers[def.Tier].AttackInterval,
		OnDeath = (options :: any).OnDeath,
		Handle = nil,
	}
	enemiesById[enemy.Id] = enemy
	local zone = enemiesByZone[zoneKey]
	if not zone then
		zone = {}
		enemiesByZone[zoneKey] = zone
	end
	zone[enemy.Id] = enemy
	local ok, handle = pcall(EnemyVisuals.Create, enemy)
	if ok then
		enemy.Handle = handle
	else
		warn("[EnemyService] Failed to create visual for " .. enemyId .. ": " .. tostring(handle))
	end
	EnemyService.EnemySpawned:Fire(enemy)
	return enemy
end

local function unregister(enemy)
	enemiesById[enemy.Id] = nil
	local zone = enemiesByZone[enemy.ZoneKey]
	if zone then
		zone[enemy.Id] = nil
		if next(zone) == nil then
			enemiesByZone[enemy.ZoneKey] = nil
		end
	end
	pcall(EnemyVisuals.Destroy, enemy)
end

-- Removes an enemy without rewards (raid cleanup, admin).
function EnemyService:Despawn(enemy)
	if not enemy or not enemy.Alive then
		return
	end
	enemy.Alive = false
	unregister(enemy)
end

function EnemyService:DespawnZone(zoneKey: string)
	local zone = enemiesByZone[zoneKey]
	if not zone then
		return
	end
	for _, enemy in table.clone(zone) do
		self:Despawn(enemy)
	end
end

-- Queries ---------------------------------------------------------------------------------------------

function EnemyService:GetEnemy(runtimeId: string)
	return enemiesById[runtimeId]
end

function EnemyService:GetEnemiesInZone(zoneKey: string): { any }
	local out = {}
	for _, enemy in enemiesByZone[zoneKey] or {} do
		if enemy.Alive then
			table.insert(out, enemy)
		end
	end
	return out
end

function EnemyService:CountInZone(zoneKey: string): number
	local n = 0
	for _, enemy in enemiesByZone[zoneKey] or {} do
		if enemy.Alive then
			n += 1
		end
	end
	return n
end

function EnemyService:FindNearest(zoneKey: string, origin: Vector3, maxRange: number)
	local best, bestDistance = nil, maxRange
	for _, enemy in enemiesByZone[zoneKey] or {} do
		if enemy.Alive then
			local distance = (enemy.Position - origin).Magnitude
			if distance <= bestDistance then
				best, bestDistance = enemy, distance
			end
		end
	end
	return best
end

function EnemyService:FindInRadius(zoneKey: string, center: Vector3, radius: number): { any }
	local out = {}
	for _, enemy in enemiesByZone[zoneKey] or {} do
		if enemy.Alive and (enemy.Position - center).Magnitude <= radius then
			table.insert(out, enemy)
		end
	end
	return out
end

-- Damage & death ---------------------------------------------------------------------------------------

-- Applies raw damage from `player`. Returns (damageDealt, killed).
function EnemyService:ApplyDamage(player, enemy, rawDamage: number): (number, boolean)
	if not enemy or not enemy.Alive or type(rawDamage) ~= "number" or rawDamage ~= rawDamage or rawDamage <= 0 then
		return 0, false
	end
	local dealt = math.min(Formulas.DamageAfterDefense(rawDamage, enemy.Def.Defense), enemy.Health)
	enemy.Health -= dealt
	enemy.Contributors[player] = (enemy.Contributors[player] or 0) + dealt
	local data = DataService:GetData(player)
	if data then
		data.Stats.TotalDamage += dealt
	end
	if enemy.Health <= 0 then
		self:_kill(enemy, player)
		return dealt, true
	end
	EnemyVisuals.Update(enemy)
	return dealt, false
end

function EnemyService:_rollDrops(player, drops)
	if not drops then
		return {}
	end
	local granted = {}
	for _, drop in drops do
		if RNG.Chance(self.Random, drop.Chance) then
			local count = self.Random:NextInteger(drop.Min, drop.Max)
			local ok = InventoryService:AddItem(player, drop.Item, count, "Drop")
			if ok then
				granted[drop.Item] = (granted[drop.Item] or 0) + count
			end
		end
	end
	return granted
end

function EnemyService:_rewardPlayer(player, enemy)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local def = enemy.Def
	local rewards = def.Rewards
	local bundle = {}
	for _, key in { "Yen", "Gold", "Gems", "Tokens", "XP" } do
		if rewards[key] then
			bundle[key] = rewards[key]
		end
	end
	EconomyService:GrantRewards(player, bundle, { Reason = "EnemyKill", ApplyMultipliers = true })
	if rewards.UnitXP then
		UnitService:AddXPToEquipped(player, math.floor(rewards.UnitXP * BoostService:GetMultiplier(player, "XP")))
	end
	self:_rollDrops(player, rewards.Drops)
	data.Stats.TotalKills += 1
	if def.IsBoss then
		data.Stats.BossKills += 1
	end
	DataService:MarkDirty(player, "Stats")
	EnemyService.EnemyKilled:Fire(player, def, enemy)
end

function EnemyService:_kill(enemy, killer)
	enemy.Alive = false
	enemy.Health = 0
	unregister(enemy)

	local tier = Enemies.Tiers[enemy.Def.Tier]
	local rewarded = {}
	if tier.SharedRewards then
		local threshold = enemy.MaxHealth * GameConfig.Combat.RewardContributionThreshold
		for player, damage in enemy.Contributors do
			if damage >= threshold and player.Parent ~= nil then
				table.insert(rewarded, player)
			end
		end
		if killer and not table.find(rewarded, killer) and #rewarded == 0 then
			table.insert(rewarded, killer)
		end
	elseif killer then
		table.insert(rewarded, killer)
	end
	for _, player in rewarded do
		local ok, err = pcall(self._rewardPlayer, self, player, enemy)
		if not ok then
			warn("[EnemyService] Reward error: " .. tostring(err))
		end
	end

	if enemy.AreaId then
		local area = areas[enemy.AreaIndex]
		if area then
			table.insert(area.Respawns, Clock.Precise() + enemy.Def.RespawnTime)
		end
	end
	if enemy.BossPoint then
		enemy.BossPoint.Enemy = nil
		enemy.BossPoint.RespawnAt = Clock.Precise() + enemy.Def.RespawnTime
	end
	if enemy.OnDeath then
		task.spawn(enemy.OnDeath, enemy, killer)
	end
	EnemyService.EnemyDied:Fire(enemy, killer)
end

-- World spawner ----------------------------------------------------------------------------------------

function EnemyService:_randomPointInArea(area): Vector3
	local angle = self.Random:NextNumber() * math.pi * 2
	local distance = math.sqrt(self.Random:NextNumber()) * area.Radius
	return area.Center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

function EnemyService:_buildSpawners()
	areas = {}
	bossPoints = {}
	for _, world in Worlds.List do
		for _, areaDef in world.SpawnAreas do
			local center = EnemyVisuals.GetAreaCenter and EnemyVisuals.GetAreaCenter(world.Id, areaDef.Id) or nil
			table.insert(areas, {
				WorldId = world.Id,
				Def = areaDef,
				Center = center or toVector(areaDef.Center),
				Radius = areaDef.Radius,
				Respawns = {},
				Alive = {},
			})
		end
		for _, boss in world.Bosses do
			table.insert(bossPoints, { WorldId = world.Id, EnemyId = boss.Enemy, Position = toVector(boss.Position), Enemy = nil, RespawnAt = 0 })
		end
	end
end

function EnemyService:StepSpawners(now: number)
	for index, area in areas do
		-- Count living enemies of this area.
		local alive = 0
		for id, enemy in area.Alive do
			if enemy.Alive then
				alive += 1
			else
				area.Alive[id] = nil
			end
		end
		local pending = 0
		for i = #area.Respawns, 1, -1 do
			if area.Respawns[i] <= now then
				table.remove(area.Respawns, i)
			else
				pending += 1
			end
		end
		local toSpawn = area.Def.MaxEnemies - alive - pending
		for _ = 1, toSpawn do
			local enemyId = RNG.WeightedPick(self.Random, area.Def.Enemies)
			if enemyId then
				local enemy = self:Spawn(enemyId, self:_randomPointInArea(area), zoneOf(area.WorldId), { AreaId = area.Def.Id, WorldId = area.WorldId })
				enemy.AreaIndex = index
				area.Alive[enemy.Id] = enemy
			end
		end
	end
	for _, point in bossPoints do
		if not point.Enemy and now >= point.RespawnAt then
			local enemy = self:Spawn(point.EnemyId, point.Position, zoneOf(point.WorldId), { WorldId = point.WorldId })
			enemy.BossPoint = point
			point.Enemy = enemy
		end
	end
end

-- Aggressive enemies (bosses) hit players of their zone within range.
function EnemyService:StepAggression(now: number)
	local zoneResolver = self.Services.WorldService
	if not zoneResolver then
		return
	end
	for _, player in Players:GetPlayers() do
		local position = PlayerUtil.GetPosition(player)
		local humanoid = PlayerUtil.GetHumanoid(player)
		if position and humanoid and humanoid.Health > 0 then
			local zoneKey = zoneResolver:GetZoneKey(player)
			for _, enemy in enemiesByZone[zoneKey] or {} do
				local tier = Enemies.Tiers[enemy.Def.Tier]
				if enemy.Alive and tier.Aggressive and enemy.Def.Damage > 0 and now >= enemy.NextAttackAt then
					if (enemy.Position - position).Magnitude <= tier.AttackRange then
						humanoid:TakeDamage(enemy.Def.Damage)
						enemy.NextAttackAt = now + tier.AttackInterval
					end
				end
			end
		end
	end
end

-- Lifecycle ----------------------------------------------------------------------------------------------

function EnemyService:Init(services)
	self.Services = services
	DataService = services.DataService
	EconomyService = services.EconomyService
	UnitService = services.UnitService
	InventoryService = services.InventoryService
	BoostService = services.BoostService
	if not EnemyService.Random then
		EnemyService.Random = RNG.new()
	end
	self:_buildSpawners()
end

function EnemyService:Start()
	while true do
		local now = Clock.Precise()
		local ok, err = pcall(function()
			self:StepSpawners(now)
			self:StepAggression(now)
		end)
		if not ok then
			warn("[EnemyService] Step error: " .. tostring(err))
		end
		task.wait(STEP_INTERVAL)
	end
end

-- Test helper: forget every enemy (no visuals touched beyond Destroy).
function EnemyService:_resetForTests()
	for _, enemy in table.clone(enemiesById) do
		self:Despawn(enemy)
	end
	self:_buildSpawners()
end

return EnemyService
