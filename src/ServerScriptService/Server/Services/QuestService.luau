--[[
	QuestService
	Main quest chain + daily quests, driven by gameplay signals from other services.

	Data (PlayerData.Quests):
	  MainCurrent   id of the active main quest ("" when the chain is finished)
	  MainCompleted { [id] = true }
	  Active        { [id] = { Progress, Completed, Claimed } }  — current main quest + today's dailies
	  DailyDay      UTC day index the dailies were rolled for

	  Quest:Track(player, objectiveType, amount, context)   context = { Enemy?, World?, Tier?, Banner?, Raid? }
	  Quest:Claim(player, questId) -> (ok, rewards | errorCode)
	  Quest:RefreshDailies(player)

	Daily quests are picked with a seed of (day, userId) so the same player always gets the same dailies for
	a given day, even across servers. Claims use persisted once-keys (per day for dailies).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Features = require(Shared.Config.Features)
local GameConfig = require(Shared.Config.GameConfig)
local Quests = require(Shared.Config.Quests)
local Clock = require(Shared.Modules.Clock)
local Signal = require(Shared.Modules.Signal)
local Validate = require(Shared.Modules.Validate)
local Net = require(Shared.Remotes.Net)

local QuestService = {
	Name = "QuestService",
	Priority = 40,
}

QuestService.QuestCompleted = Signal.new() -- (player, questId)
QuestService.QuestClaimed = Signal.new() -- (player, questId)

local DAILY_CHECK_INTERVAL = 60

local DataService, EconomyService

local function currentDay(): number
	return Clock.Day(Clock.Now(), GameConfig.Quests.DailyResetOffsetSeconds)
end

local function matchesFilter(filter: { [string]: any }?, context: { [string]: any }?): boolean
	if not filter then
		return true
	end
	context = context or {}
	for key, expected in filter do
		if (context :: any)[key] ~= expected then
			return false
		end
	end
	return true
end

-- Value used for "absolute" objectives at activation time (e.g. ReachLevel -> current level).
local function absoluteValue(data, objectiveType: string): number
	if objectiveType == "ReachLevel" then
		return data.Level
	end
	return 0
end

function QuestService:_activate(data, questId: string)
	local def = Quests.Get(questId)
	if not def then
		return
	end
	local entry = { Progress = 0, Completed = false, Claimed = false }
	if Quests.AbsoluteTypes[def.Type] then
		entry.Progress = math.min(absoluteValue(data, def.Type), def.Target)
		entry.Completed = entry.Progress >= def.Target
	end
	data.Quests.Active[questId] = entry
end

function QuestService:EnsureMainQuest(player)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local quests = data.Quests
	if quests.MainCurrent == "" and not quests.MainCompleted[Quests.FirstMain] then
		quests.MainCurrent = Quests.FirstMain
	end
	if quests.MainCurrent ~= "" and not Quests.Get(quests.MainCurrent) then
		-- Quest removed from config: skip to nothing rather than soft-locking.
		quests.MainCurrent = ""
	end
	if quests.MainCurrent ~= "" and not quests.Active[quests.MainCurrent] then
		self:_activate(data, quests.MainCurrent)
	end
	DataService:MarkDirty(player, "Quests")
end

function QuestService:RefreshDailies(player): boolean
	local data = DataService:GetData(player)
	if not data then
		return false
	end
	local day = currentDay()
	if data.Quests.DailyDay == day then
		return false
	end
	for questId in table.clone(data.Quests.Active) do
		local def = Quests.Get(questId)
		if not def or def.Category == "Daily" then
			data.Quests.Active[questId] = nil
		end
	end
	local pool = table.clone(Quests.Daily)
	local generator = Random.new(day * 100003 + (player.UserId % 100003))
	local count = math.min(GameConfig.Quests.DailyQuestCount, #pool)
	for _ = 1, count do
		local index = generator:NextInteger(1, #pool)
		local def = table.remove(pool, index)
		self:_activate(data, def.Id)
	end
	data.Quests.DailyDay = day
	DataService:MarkDirty(player, "Quests")
	return true
end

function QuestService:Track(player, objectiveType: string, amount: number, context: { [string]: any }?)
	local data = DataService:GetData(player)
	if not data or type(amount) ~= "number" or amount <= 0 then
		return
	end
	local changed = false
	for questId, entry in data.Quests.Active do
		local def = Quests.Get(questId)
		if def and def.Type == objectiveType and not entry.Completed and matchesFilter(def.Filter, context) then
			if Quests.AbsoluteTypes[objectiveType] then
				entry.Progress = math.max(entry.Progress, math.min(amount, def.Target))
			else
				entry.Progress = math.min(entry.Progress + amount, def.Target)
			end
			if entry.Progress >= def.Target then
				entry.Completed = true
				Net.Fire(player, "Notify", { Text = "Quest complete: " .. def.Title, Kind = "Quest" })
				QuestService.QuestCompleted:Fire(player, questId)
			end
			changed = true
		end
	end
	if changed then
		DataService:MarkDirty(player, "Quests")
	end
end

function QuestService:Claim(player, questId: string): (boolean, any)
	if not Features.Quests then
		return false, "FeatureDisabled"
	end
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local def = Quests.Get(questId)
	local entry = data.Quests.Active[questId]
	if not def or not entry then
		return false, "QuestNotFound"
	end
	if entry.Claimed then
		return false, "AlreadyClaimed"
	end
	if not entry.Completed then
		return false, "QuestNotComplete"
	end
	local onceKey = if def.Category == "Daily" then ("Daily:%d:%s"):format(data.Quests.DailyDay, questId) else "Quest:" .. questId
	local ok, result = EconomyService:GrantRewards(player, def.Rewards, { Reason = "Quest:" .. questId, OnceKey = onceKey })
	if not ok then
		if result == "AlreadyClaimed" then
			entry.Claimed = true
		end
		return false, result
	end
	entry.Claimed = true
	if def.Category == "Main" then
		data.Quests.MainCompleted[questId] = true
		data.Quests.Active[questId] = nil
		data.Quests.MainCurrent = def.Next or ""
		if def.Next then
			self:_activate(data, def.Next)
		end
	end
	DataService:MarkDirty(player, "Quests")
	QuestService.QuestClaimed:Fire(player, questId)
	return true, result
end

-- Lifecycle ----------------------------------------------------------------------------------------------

function QuestService:Init(services)
	self.Services = services
	DataService = services.DataService
	EconomyService = services.EconomyService

	DataService.ProfileLoaded:Connect(function(player)
		self:EnsureMainQuest(player)
		self:RefreshDailies(player)
	end)

	-- Gameplay hooks -> objectives
	if services.EnemyService then
		services.EnemyService.EnemyKilled:Connect(function(player, def)
			local context = { Enemy = def.Id, World = def.World, Tier = def.Tier }
			self:Track(player, "KillEnemies", 1, context)
			if def.IsBoss then
				self:Track(player, "KillBoss", 1, context)
			end
		end)
	end
	if services.SummonService then
		services.SummonService.Summoned:Connect(function(player, bannerId, count)
			self:Track(player, "Summon", count, { Banner = bannerId })
		end)
	end
	services.EconomyService.CurrencyChanged:Connect(function(player, currency, delta, _, reason)
		if currency == "Yen" and delta > 0 and type(reason) == "string" and string.sub(reason, 1, 7) ~= "Refund:" and string.sub(reason, 1, 6) ~= "Admin:" then
			self:Track(player, "EarnYen", delta)
		end
	end)
	if services.WorldService then
		services.WorldService.WorldUnlocked:Connect(function(player, worldId)
			self:Track(player, "UnlockWorld", 1, { World = worldId })
		end)
	end
	if services.ProgressionService then
		services.ProgressionService.LevelUp:Connect(function(player, level)
			self:Track(player, "ReachLevel", level)
		end)
	end
	if services.UnitService then
		services.UnitService.UnitLeveled:Connect(function(player, _, levels)
			self:Track(player, "LevelUpUnits", levels)
		end)
		services.UnitService.UnitEvolved:Connect(function(player)
			self:Track(player, "EvolveUnit", 1)
		end)
		services.UnitService.UnitsFused:Connect(function(player)
			self:Track(player, "FuseUnits", 1)
		end)
	end
	if services.RaidService then
		services.RaidService.RaidCompleted:Connect(function(player, raidId)
			self:Track(player, "CompleteRaid", 1, { Raid = raidId })
		end)
	end

	Net.Handle("ClaimQuest", function(player, questId)
		if not Validate.String(questId, 32) then
			return false, "InvalidArguments"
		end
		return self:Claim(player, questId)
	end, { RateLimit = 4 })
end

function QuestService:Start()
	while true do
		task.wait(DAILY_CHECK_INTERVAL)
		for _, player in Players:GetPlayers() do
			if self:RefreshDailies(player) then
				Net.Fire(player, "Notify", { Text = "New daily quests are available!", Kind = "Quest" })
			end
		end
	end
end

return QuestService
