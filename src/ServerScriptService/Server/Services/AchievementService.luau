--[[
	AchievementService
	Tiered permanent achievements computed from PlayerData.Stats (or Level).
	PlayerData.Achievements[id] = highest tier claimed (0/nil = none).

	  Achievement:GetProgress(player, id) -> (value, nextTierIndex?, nextTier?)
	  Achievement:Claim(player, id) -> (ok, rewards | errorCode)     claims the next tier if reached
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Features = require(Shared.Config.Features)
local Achievements = require(Shared.Config.Achievements)
local Validate = require(Shared.Modules.Validate)
local Net = require(Shared.Remotes.Net)

local AchievementService = {
	Name = "AchievementService",
	Priority = 41,
}

local DataService, EconomyService

local function statValue(data, stat: string): number
	if stat == "Level" then
		return data.Level
	end
	return data.Stats[stat] or 0
end

function AchievementService:GetProgress(player, achievementId: string)
	local data = DataService:GetData(player)
	local def = Achievements.Get(achievementId)
	if not data or not def then
		return 0, nil, nil
	end
	local nextIndex = (data.Achievements[achievementId] or 0) + 1
	return statValue(data, def.Stat), nextIndex, def.Tiers[nextIndex]
end

function AchievementService:Claim(player, achievementId: string): (boolean, any)
	if not Features.Achievements then
		return false, "FeatureDisabled"
	end
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local def = Achievements.Get(achievementId)
	if not def then
		return false, "QuestNotFound"
	end
	local value, nextIndex, tier = self:GetProgress(player, achievementId)
	if not tier then
		return false, "AlreadyClaimed"
	end
	if value < tier.Goal then
		return false, "QuestNotComplete"
	end
	local ok, result = EconomyService:GrantRewards(player, tier.Rewards, {
		Reason = "Achievement:" .. achievementId,
		OnceKey = ("Ach:%s:%d"):format(achievementId, nextIndex),
	})
	if not ok and result ~= "AlreadyClaimed" then
		return false, result
	end
	data.Achievements[achievementId] = nextIndex
	DataService:MarkDirty(player, "Achievements")
	if not ok then
		return false, result
	end
	return true, result
end

function AchievementService:Init(services)
	self.Services = services
	DataService = services.DataService
	EconomyService = services.EconomyService

	Net.Handle("ClaimAchievement", function(player, achievementId)
		if not Validate.String(achievementId, 32) then
			return false, "InvalidArguments"
		end
		return self:Claim(player, achievementId)
	end, { RateLimit = 4 })
end

return AchievementService
