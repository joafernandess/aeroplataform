--[[
	RaidService
	Instanced wave raids (Config/Raids).

	Flow:
	  StartRaid(player, raidId)
	    -> checks requirements, cooldown, entry cost (EconomyService:Purchase)
	    -> allocates an arena slot, creates zone "Raid:<instanceId>", teleports the player there
	    -> spawns wave 1 (enemies only exist in the raid zone, so nobody else can hit them)
	  Each enemy death checks whether the wave is cleared -> next wave -> ... -> completion rewards
	  Fails on timeout, death of every participant, or LeaveRaid. Cleanup despawns the zone and returns
	  participants to their world.

	Instances are currently solo (one player). The data model already keeps a Players list and
	Config.MaxPlayers so party raids only need a lobby/invite flow on top (see docs/TODO.md).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Raids = require(Shared.Config.Raids)
local Worlds = require(Shared.Config.Worlds)
local Requirements = require(Shared.Modules.Requirements)
local Clock = require(Shared.Modules.Clock)
local Signal = require(Shared.Modules.Signal)
local Validate = require(Shared.Modules.Validate)
local Net = require(Shared.Remotes.Net)

local Server = script.Parent.Parent
local PlayerUtil = require(Server.Core.PlayerUtil)

local RaidService = {
	Name = "RaidService",
	Priority = 35,
}

RaidService.RaidCompleted = Signal.new() -- (player, raidId)
RaidService.RaidFailed = Signal.new() -- (player, raidId, reason)

local ARENA_SPACING = 400
local WAVE_SPAWN_RADIUS = 25
local END_DELAY = 5
local STEP_INTERVAL = 1

local instances: { [string]: any } = {}
local playerInstance: { [any]: any } = {}
local usedSlots: { [number]: boolean } = {}
local nextInstanceId = 0

local DataService, EconomyService, EnemyService, WorldService

local function allocateSlot(): number
	local slot = 0
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	return slot
end

local function arenaOrigin(slot: number): Vector3
	local o = Worlds.RaidArenaOrigin
	return Vector3.new(o[1] + slot * ARENA_SPACING, o[2], o[3])
end

local function broadcast(instance, payload)
	for _, player in instance.Players do
		Net.Fire(player, "RaidUpdate", payload)
	end
end

local function statePayload(instance, state: string, extra: { [string]: any }?)
	local payload = {
		State = state,
		Raid = instance.Def.Id,
		Wave = instance.Wave,
		Waves = #instance.Def.Waves,
		EndsAt = instance.EndsAt,
		Remaining = EnemyService:CountInZone(instance.ZoneKey),
	}
	for k, v in extra or {} do
		payload[k] = v
	end
	return payload
end

function RaidService:GetPlayerZone(player): string?
	local instance = playerInstance[player]
	return instance and instance.ZoneKey
end

function RaidService:GetInstance(player)
	return playerInstance[player]
end

-- Waves ------------------------------------------------------------------------------------------------------

function RaidService:_spawnWave(instance)
	instance.Wave += 1
	local wave = instance.Def.Waves[instance.Wave]
	local total = 0
	for _, entry in wave.Enemies do
		total += entry.Count
	end
	local index = 0
	for _, entry in wave.Enemies do
		for _ = 1, entry.Count do
			index += 1
			local angle = (index / total) * math.pi * 2
			local radius = if total == 1 then 0 else WAVE_SPAWN_RADIUS
			local position = instance.Origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius + 30)
			EnemyService:Spawn(entry.Enemy, position, instance.ZoneKey, {
				OnDeath = function()
					self:_onEnemyDeath(instance)
				end,
			})
		end
	end
	broadcast(instance, statePayload(instance, "Wave"))
end

function RaidService:_onEnemyDeath(instance)
	if instance.State ~= "Active" then
		return
	end
	if EnemyService:CountInZone(instance.ZoneKey) > 0 then
		broadcast(instance, statePayload(instance, "Progress"))
		return
	end
	if instance.Wave < #instance.Def.Waves then
		self:_spawnWave(instance)
	else
		self:_complete(instance)
	end
end

function RaidService:_complete(instance)
	instance.State = "Completed"
	for _, player in instance.Players do
		local data = DataService:GetData(player)
		if data then
			EconomyService:GrantRewards(player, instance.Def.Rewards, { Reason = "Raid:" .. instance.Def.Id })
			data.Stats.RaidsCompleted += 1
			DataService:MarkDirty(player, "Stats")
			RaidService.RaidCompleted:Fire(player, instance.Def.Id)
		end
	end
	broadcast(instance, statePayload(instance, "Completed", { Rewards = instance.Def.Rewards }))
	task.delay(self.EndDelay, function()
		self:_cleanup(instance)
	end)
end

function RaidService:_fail(instance, reason: string)
	if instance.State ~= "Active" then
		return
	end
	instance.State = "Failed"
	broadcast(instance, statePayload(instance, "Failed", { Reason = reason }))
	for _, player in instance.Players do
		RaidService.RaidFailed:Fire(player, instance.Def.Id, reason)
	end
	self:_cleanup(instance)
end

function RaidService:_cleanup(instance)
	if instance.CleanedUp then
		return
	end
	instance.CleanedUp = true
	EnemyService:DespawnZone(instance.ZoneKey)
	for _, player in instance.Players do
		if playerInstance[player] == instance then
			playerInstance[player] = nil
			if self.Services.CombatService then
				self.Services.CombatService:ClearTarget(player)
			end
			local data = DataService:GetData(player)
			if data and player.Parent ~= nil then
				local position = WorldService:GetSpawnPosition(data.CurrentWorld)
				if position then
					PlayerUtil.Teleport(player, position)
				end
				Net.Fire(player, "RaidUpdate", { State = "Ended", Raid = instance.Def.Id })
			end
		end
	end
	usedSlots[instance.Slot] = nil
	instances[instance.Id] = nil
end

-- Public API ------------------------------------------------------------------------------------------------------

function RaidService:StartRaid(player, raidId: string): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local def = Raids.Get(raidId)
	if not def then
		return false, "RaidNotFound"
	end
	if playerInstance[player] then
		return false, "AlreadyInRaid"
	end
	local ok = Requirements.Check(data, def.Requirements)
	if not ok then
		return false, "RequirementsNotMet"
	end
	local now = Clock.Now()
	if (data.RaidCooldowns[raidId] or 0) > now then
		return false, "RaidOnCooldown"
	end
	local cost = def.EntryCost or { Currency = "Yen", Amount = 0 }
	return EconomyService:Purchase(player, cost, "RaidEntry:" .. raidId, function()
		nextInstanceId += 1
		local slot = allocateSlot()
		local instance = {
			Id = tostring(nextInstanceId),
			Def = def,
			Players = { player },
			Wave = 0,
			Slot = slot,
			Origin = arenaOrigin(slot),
			ZoneKey = "Raid:" .. nextInstanceId,
			StartedAt = now,
			EndsAt = now + def.TimeLimit,
			State = "Active",
		}
		instances[instance.Id] = instance
		playerInstance[player] = instance
		data.RaidCooldowns[raidId] = now + def.Cooldown
		DataService:MarkDirty(player, "RaidCooldowns")
		if self.Services.CombatService then
			self.Services.CombatService:ClearTarget(player)
		end
		PlayerUtil.Teleport(player, instance.Origin)
		self:_spawnWave(instance)
		return true, { Instance = instance.Id, Raid = raidId, EndsAt = instance.EndsAt, Waves = #def.Waves }
	end)
end

function RaidService:LeaveRaid(player): (boolean, any)
	local instance = playerInstance[player]
	if not instance then
		return false, "NotInRaid"
	end
	if instance.State == "Active" then
		self:_fail(instance, "Left")
	else
		self:_cleanup(instance)
	end
	return true, nil
end

function RaidService:Step()
	local now = Clock.Now()
	for _, instance in table.clone(instances) do
		if instance.State == "Active" then
			if now >= instance.EndsAt then
				self:_fail(instance, "TimeUp")
			else
				local anyAlive = false
				for _, player in instance.Players do
					if player.Parent ~= nil and (player.Character == nil or PlayerUtil.IsAlive(player)) then
						anyAlive = true
					end
				end
				if not anyAlive then
					self:_fail(instance, "Defeated")
				end
			end
		end
	end
end

function RaidService:Init(services)
	self.Services = services
	self.EndDelay = END_DELAY
	DataService = services.DataService
	EconomyService = services.EconomyService
	EnemyService = services.EnemyService
	WorldService = services.WorldService

	Net.Handle("StartRaid", function(player, raidId)
		if not Validate.String(raidId, 32) then
			return false, "InvalidArguments"
		end
		return self:StartRaid(player, raidId)
	end, { RateLimit = 1, Burst = 2 })
	Net.Handle("LeaveRaid", function(player)
		return self:LeaveRaid(player)
	end, { RateLimit = 1, Burst = 2 })

	DataService.ProfileReleasing:Connect(function(player)
		local instance = playerInstance[player]
		if instance then
			local index = table.find(instance.Players, player)
			if index then
				table.remove(instance.Players, index)
			end
			playerInstance[player] = nil
			if #instance.Players == 0 then
				instance.State = "Failed"
				self:_cleanup(instance)
			end
		end
	end)
end

function RaidService:Start()
	while true do
		local ok, err = pcall(self.Step, self)
		if not ok then
			warn("[RaidService] Step error: " .. tostring(err))
		end
		task.wait(STEP_INTERVAL)
	end
end

local _ = Players

return RaidService
