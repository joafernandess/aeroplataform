--[[
	DataService
	Owns every player's persisted profile.

	Data-loss protections:
	  - Session locking: a profile is locked to one server (JobId) while the player is in it. Another server
	    that tries to load a fresh lock waits/retries and finally kicks instead of loading stale data.
	  - Every write is an UpdateAsync that first checks we still own the lock.
	  - Loading retries with exponential backoff; if it still fails the player is kicked — we NEVER play on
	    default data, because saving it later would overwrite the real profile.
	  - Profiles are sanitised before saving (no NaN/negative currencies, valid unit references).
	  - Auto-save every GameConfig.Data.AutoSaveInterval, save + release on leave, save all on shutdown.
	  - Data versioning + migrations + reconcile against the template for forward-compatible updates.

	Public API:
	  DataService.ProfileLoaded      Signal(player, profile)
	  DataService.ProfileReleasing   Signal(player, profile)   (fires before the final save)
	  DataService:GetProfile(player) -> profile?   { Player, Data, IsNew, SessionStart, ... }
	  DataService:GetData(player)    -> data?
	  DataService:WaitForData(player, timeout?) -> data?
	  DataService:MarkDirty(player, key)          replicate one top-level key to the client
	  DataService:GetSnapshot(player) -> table    full client-safe copy
	  DataService:SaveProfile(player, release?) -> boolean
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Units = require(Shared.Config.Units)
local Items = require(Shared.Config.Items)
local Worlds = require(Shared.Config.Worlds)
local Signal = require(Shared.Modules.Signal)
local TableUtil = require(Shared.Modules.TableUtil)
local Clock = require(Shared.Modules.Clock)
local Net = require(Shared.Remotes.Net)

local DataFolder = script.Parent.Parent.Data
local DataTemplate = require(DataFolder.DataTemplate)
local Migrations = require(DataFolder.Migrations)
local DataStoreAdapter = require(DataFolder.DataStoreAdapter)

local CONFIG = GameConfig.Data

local DataService = {
	Name = "DataService",
	Priority = 1,
}

DataService.ProfileLoaded = Signal.new()
DataService.ProfileReleasing = Signal.new()

local profiles: { [any]: any } = {}
local loading: { [any]: boolean } = {}
local pendingReplication: { [any]: { [string]: boolean } } = {}
local store: any = nil
local isShuttingDown = false

local function jobId(): string
	local id = game.JobId
	return if id == nil or id == "" then "studio" else id
end

local function keyFor(player): string
	return CONFIG.KeyPrefix .. tostring(player.UserId)
end

local function retry<T>(attempts: number, fn: () -> T): (boolean, T | string)
	local lastErr = nil
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < attempts then
			task.wait(CONFIG.RetryBaseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, tostring(lastErr)
end

-- Sanitising -------------------------------------------------------------------------------

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Repairs impossible values. Returns the number of fixes applied (logged as a warning).
function DataService.Sanitize(data: { [string]: any }): number
	local fixes = 0
	for _, currency in GameConfig.Economy.Currencies do
		local value = data.Currencies[currency]
		if not isFiniteNumber(value) or value < 0 then
			data.Currencies[currency] = 0
			fixes += 1
		elseif value > GameConfig.Economy.MaxBalance then
			data.Currencies[currency] = GameConfig.Economy.MaxBalance
			fixes += 1
		end
	end
	if not isFiniteNumber(data.Level) or data.Level < 1 then
		data.Level = 1
		fixes += 1
	end
	if not isFiniteNumber(data.Experience) or data.Experience < 0 then
		data.Experience = 0
		fixes += 1
	end
	-- Units whose definition was removed are dropped (they would crash every system that reads them).
	for uid, unit in data.Inventory.Units do
		if type(unit) ~= "table" or not Units.IsValid(unit.UnitId) then
			data.Inventory.Units[uid] = nil
			fixes += 1
		else
			unit.Uid = uid
		end
	end
	for itemId, count in data.Inventory.Items do
		if not Items.IsValid(itemId) or not isFiniteNumber(count) or count <= 0 then
			data.Inventory.Items[itemId] = nil
			fixes += 1
		end
	end
	-- Equipped list must only contain owned, unique units.
	local seen = {}
	local cleaned = {}
	for _, uid in data.EquippedUnits do
		if type(uid) == "string" and data.Inventory.Units[uid] and not seen[uid] then
			seen[uid] = true
			table.insert(cleaned, uid)
		else
			fixes += 1
		end
	end
	data.EquippedUnits = cleaned
	if not Worlds.IsValid(data.CurrentWorld) or not data.UnlockedWorlds[data.CurrentWorld] then
		data.CurrentWorld = GameConfig.Start.World
		fixes += 1
	end
	data.Damage = data.Upgrades.Damage or 0
	return fixes
end

-- Store access -----------------------------------------------------------------------------

function DataService:_getStore()
	if not store then
		store = DataStoreAdapter.Get(CONFIG.StoreName)
	end
	return store
end

-- Exposed for tests: swap the backing store.
function DataService:SetStore(newStore)
	store = newStore
end

-- Loading ----------------------------------------------------------------------------------

local function buildProfile(player, record)
	local isNew = record == nil or record.Data == nil
	local data
	if isNew then
		data = DataTemplate.Create()
	else
		data = record.Data
		local ok, err = Migrations.Run(data, DataTemplate.CurrentVersion)
		if not ok then
			return nil, err
		end
		TableUtil.Reconcile(data, DataTemplate.Create())
	end
	local fixes = DataService.Sanitize(data)
	if fixes > 0 then
		warn(("[DataService] Repaired %d invalid field(s) in %s's profile"):format(fixes, player.Name))
	end
	local now = Clock.Now()
	if data.FirstJoin == 0 then
		data.FirstJoin = now
	end
	data.LastJoin = now
	return {
		Player = player,
		Data = data,
		IsNew = isNew,
		SessionStart = now,
		PlaytimeMark = now,
		Released = false,
	}, nil
end

function DataService:LoadProfile(player)
	if profiles[player] then
		return profiles[player]
	end
	if loading[player] then
		return nil
	end
	loading[player] = true
	local key = keyFor(player)
	local dataStore = self:_getStore()

	local record, failure = nil, nil
	for lockAttempt = 1, CONFIG.SessionLockWaitAttempts do
		local lockedByOther = false
		local loaded = nil
		local ok, err = retry(CONFIG.MaxLoadAttempts, function()
			lockedByOther = false
			return dataStore:UpdateAsync(key, function(current)
				current = current or {}
				local session = current.Session
				local now = Clock.Now()
				if session and session.JobId ~= jobId() and now - (session.LockedAt or 0) < CONFIG.SessionLockTimeout then
					lockedByOther = true
					return nil -- cancel: someone else owns the profile
				end
				current.Session = { JobId = jobId(), LockedAt = now }
				loaded = current
				return current
			end)
		end)
		if not ok then
			failure = "DataStore error: " .. tostring(err)
			break
		end
		if not lockedByOther then
			record = loaded
			failure = nil
			break
		end
		failure = "Profile is locked by another server"
		if lockAttempt < CONFIG.SessionLockWaitAttempts then
			task.wait(CONFIG.RetryBaseDelay * 2 ^ lockAttempt)
		end
	end

	if failure or player.Parent == nil then
		loading[player] = nil
		if failure then
			warn(("[DataService] Failed to load %s: %s"):format(player.Name, failure))
			player:Kick("We couldn't load your data safely. Your progress is NOT lost — please rejoin in a moment.")
		end
		return nil
	end

	local profile, buildErr = buildProfile(player, record)
	loading[player] = nil
	if not profile then
		warn(("[DataService] Refusing to load %s: %s"):format(player.Name, tostring(buildErr)))
		player:Kick("Your data was saved by a newer version of the game. Please rejoin.")
		return nil
	end

	profiles[player] = profile
	DataService.ProfileLoaded:Fire(player, profile)
	return profile
end

-- Saving -----------------------------------------------------------------------------------

local function flushPlaytime(profile)
	local now = Clock.Now()
	profile.Data.Playtime += math.max(0, now - profile.PlaytimeMark)
	profile.PlaytimeMark = now
end

function DataService:SaveProfile(player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile or profile.Released then
		return false
	end
	flushPlaytime(profile)
	DataService.Sanitize(profile.Data)
	local snapshot = TableUtil.DeepCopy(profile.Data)
	local dataStore = self:_getStore()
	local lockLost = false

	local ok, err = retry(CONFIG.MaxSaveAttempts, function()
		lockLost = false
		return dataStore:UpdateAsync(keyFor(player), function(current)
			current = current or {}
			local session = current.Session
			if session and session.JobId ~= jobId() then
				lockLost = true
				return nil
			end
			current.Data = snapshot
			current.Session = if release then nil else { JobId = jobId(), LockedAt = Clock.Now() }
			current.Meta = { SavedAt = Clock.Now(), DataVersion = snapshot.DataVersion }
			return current
		end)
	end)

	if lockLost then
		-- Another server took the profile (e.g. our lock went stale during an outage). Stop writing.
		warn(("[DataService] Lost session lock for %s; profile released without saving"):format(player.Name))
		profile.Released = true
		profiles[player] = nil
		if player.Parent ~= nil then
			player:Kick("Your data was opened on another server. Please rejoin.")
		end
		return false
	end
	if not ok then
		warn(("[DataService] Failed to save %s: %s"):format(player.Name, tostring(err)))
		return false
	end
	return true
end

function DataService:ReleaseProfile(player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	DataService.ProfileReleasing:Fire(player, profile)
	self:SaveProfile(player, true)
	profile.Released = true
	profiles[player] = nil
	pendingReplication[player] = nil
end

function DataService:SaveAll()
	local threads = {}
	for player in profiles do
		table.insert(threads, player)
	end
	local remaining = #threads
	for _, player in threads do
		task.spawn(function()
			self:ReleaseProfile(player)
			remaining -= 1
		end)
	end
	local deadline = Clock.Precise() + 25
	while remaining > 0 and Clock.Precise() < deadline do
		task.wait(0.1)
	end
end

-- Access -----------------------------------------------------------------------------------

function DataService:GetProfile(player)
	local profile = profiles[player]
	if profile and not profile.Released then
		return profile
	end
	return nil
end

function DataService:GetData(player)
	local profile = self:GetProfile(player)
	return profile and profile.Data
end

function DataService:WaitForData(player, timeout: number?)
	local deadline = Clock.Precise() + (timeout or 30)
	while player.Parent ~= nil and Clock.Precise() < deadline do
		local data = self:GetData(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return self:GetData(player)
end

function DataService:GetSnapshot(player)
	local data = self:GetData(player)
	if not data then
		return nil
	end
	local copy = {}
	for key, value in data do
		if not DataTemplate.PrivateKeys[key] then
			copy[key] = TableUtil.DeepCopy(value)
		end
	end
	return copy
end

-- Replication: batched per frame; only top-level keys are sent.
function DataService:MarkDirty(player, key: string)
	if DataTemplate.PrivateKeys[key] then
		return
	end
	local pending = pendingReplication[player]
	if pending then
		pending[key] = true
		return
	end
	pendingReplication[player] = { [key] = true }
	task.defer(function()
		local keys = pendingReplication[player]
		pendingReplication[player] = nil
		local data = self:GetData(player)
		if not keys or not data then
			return
		end
		for dirtyKey in keys do
			Net.Fire(player, "DataChanged", dirtyKey, data[dirtyKey])
		end
	end)
end

-- Lifecycle ----------------------------------------------------------------------------------

function DataService:Init(services)
	self.Services = services
	Net.Handle("GetProfile", function(player)
		local snapshot = self:GetSnapshot(player)
		if not snapshot then
			return false, "DataNotLoaded"
		end
		return true, snapshot
	end, { RateLimit = 1, Burst = 3 })
end

function DataService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:LoadProfile(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self.LoadProfile, self, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- If the player leaves while still loading, wait for the load to finish so the lock gets released.
		while loading[player] do
			task.wait(0.1)
		end
		self:ReleaseProfile(player)
		Net.CleanupPlayer(player)
	end)

	game:BindToClose(function()
		isShuttingDown = true
		self:SaveAll()
	end)

	while not isShuttingDown do
		task.wait(CONFIG.AutoSaveInterval)
		for player in profiles do
			task.spawn(self.SaveProfile, self, player, false)
		end
	end
end

return DataService
