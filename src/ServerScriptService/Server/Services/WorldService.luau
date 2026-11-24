--[[
	WorldService
	World unlocking, teleporting and zone resolution.

	  World:Unlock(player, worldId) -> (ok, worldId | errorCode)
	      Requires the previous world unlocked, Requirements (level...) and the UnlockCost.
	  World:Teleport(player, worldId) -> (ok, worldId | errorCode)
	  World:GetZoneKey(player) -> "World:<id>" or the raid zone when the player is inside a raid
	  World:GetSpawnPosition(worldId) -> Vector3

	ClearReward: granted once (persisted OnceKey) the first time a player kills a world's final boss.
	Signals: WorldUnlocked(player, worldId), WorldChanged(player, worldId)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Worlds = require(Shared.Config.Worlds)
local Requirements = require(Shared.Modules.Requirements)
local Signal = require(Shared.Modules.Signal)
local Validate = require(Shared.Modules.Validate)
local Net = require(Shared.Remotes.Net)

local Server = script.Parent.Parent
local PlayerUtil = require(Server.Core.PlayerUtil)

local WorldService = {
	Name = "WorldService",
	Priority = 15,
}

WorldService.WorldUnlocked = Signal.new() -- (player, worldId)
WorldService.WorldChanged = Signal.new() -- (player, worldId)

local DataService, EconomyService

function WorldService:GetZoneKey(player): string
	local raid = self.Services.RaidService
	if raid then
		local zone = raid:GetPlayerZone(player)
		if zone then
			return zone
		end
	end
	local data = DataService:GetData(player)
	return "World:" .. (if data then data.CurrentWorld else "W1")
end

function WorldService:GetSpawnPosition(worldId: string): Vector3?
	local def = Worlds.Get(worldId)
	if not def then
		return nil
	end
	-- Map override: Workspace.Worlds.<id>.Spawn
	local worlds = Workspace:FindFirstChild("Worlds")
	local folder = worlds and worlds:FindFirstChild(worldId)
	local spawnPart = folder and folder:FindFirstChild("Spawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.Position + Vector3.new(0, 4, 0)
	end
	return Vector3.new(def.Spawn[1], def.Spawn[2], def.Spawn[3])
end

function WorldService:IsUnlocked(player, worldId: string): boolean
	local data = DataService:GetData(player)
	return data ~= nil and data.UnlockedWorlds[worldId] == true
end

-- Returns (canUnlock, errorCode?, reasonText?) without charging; used by the UI-facing checks too.
function WorldService:CanUnlock(player, worldId: string): (boolean, string?, string?)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded", nil
	end
	local def = Worlds.Get(worldId)
	if not def then
		return false, "WorldNotFound", nil
	end
	if data.UnlockedWorlds[worldId] then
		return false, "AlreadyUnlocked", nil
	end
	local previous = Worlds.GetPrevious(worldId)
	if previous and not data.UnlockedWorlds[previous.Id] then
		return false, "RequirementsNotMet", "Unlock " .. previous.Name .. " first"
	end
	local ok, reason = Requirements.Check(data, def.Requirements)
	if not ok then
		return false, "RequirementsNotMet", reason
	end
	return true, nil, nil
end

function WorldService:Unlock(player, worldId: string): (boolean, any)
	local can, err = self:CanUnlock(player, worldId)
	if not can then
		return false, err
	end
	local data = DataService:GetData(player)
	local def = Worlds.Get(worldId)
	return EconomyService:Purchase(player, def.UnlockCost, "UnlockWorld:" .. worldId, function()
		data.UnlockedWorlds[worldId] = true
		DataService:MarkDirty(player, "UnlockedWorlds")
		WorldService.WorldUnlocked:Fire(player, worldId)
		return true, worldId
	end)
end

function WorldService:Teleport(player, worldId: string): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	if not Worlds.Get(worldId) then
		return false, "WorldNotFound"
	end
	if not data.UnlockedWorlds[worldId] then
		return false, "WorldLocked"
	end
	local raid = self.Services.RaidService
	if raid and raid:GetPlayerZone(player) then
		return false, "AlreadyInRaid"
	end
	data.CurrentWorld = worldId
	DataService:MarkDirty(player, "CurrentWorld")
	local position = self:GetSpawnPosition(worldId)
	if position then
		PlayerUtil.Teleport(player, position)
	end
	WorldService.WorldChanged:Fire(player, worldId)
	return true, worldId
end

-- World clear reward: first kill of the world's last listed boss.
function WorldService:_onEnemyKilled(player, enemyDef)
	local world = Worlds.Get(enemyDef.World)
	if not world or not world.ClearReward or #world.Bosses == 0 then
		return
	end
	if world.Bosses[#world.Bosses].Enemy ~= enemyDef.Id then
		return
	end
	local data = DataService:GetData(player)
	if not data or data.ClearedWorlds[world.Id] then
		return
	end
	local ok = EconomyService:GrantRewards(player, world.ClearReward, { Reason = "WorldClear:" .. world.Id, OnceKey = "WorldClear:" .. world.Id })
	if ok then
		data.ClearedWorlds[world.Id] = true
		DataService:MarkDirty(player, "ClearedWorlds")
		Net.Fire(player, "Notify", { Text = world.Name .. " cleared! Bonus rewards granted.", Kind = "Success" })
	end
end

function WorldService:Init(services)
	self.Services = services
	DataService = services.DataService
	EconomyService = services.EconomyService

	if services.EnemyService then
		services.EnemyService.EnemyKilled:Connect(function(player, enemyDef)
			self:_onEnemyKilled(player, enemyDef)
		end)
	end

	Net.Handle("UnlockWorld", function(player, worldId)
		if not Validate.String(worldId, 16) then
			return false, "InvalidArguments"
		end
		return self:Unlock(player, worldId)
	end, { RateLimit = 2 })

	Net.Handle("TeleportWorld", function(player, worldId)
		if not Validate.String(worldId, 16) then
			return false, "InvalidArguments"
		end
		return self:Teleport(player, worldId)
	end, { RateLimit = 1, Burst = 2 })
end

function WorldService:Start()
	-- Spawn each character in the player's current world.
	local function onCharacter(player)
		local data = DataService:WaitForData(player, 30)
		if not data then
			return
		end
		task.wait(0.2)
		local raid = self.Services.RaidService
		if raid and raid:GetPlayerZone(player) then
			return
		end
		local position = self:GetSpawnPosition(data.CurrentWorld)
		if position then
			PlayerUtil.Teleport(player, position)
		end
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
		if player.Character then
			task.spawn(onCharacter, player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return WorldService
