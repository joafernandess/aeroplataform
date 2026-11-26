--[[
	CodesService
	Redeems codes from Config/Codes. The rewards go through EconomyService:GrantRewards with a persisted
	OnceKey ("Code:<CODE>"), so each player can claim each code exactly once, even across servers.

	  Codes:Redeem(player, text) -> (ok, rewards | errorCode)
	  errors: InvalidArguments, InvalidCode, CodeExpired, RequirementsNotMet, CodeAlreadyUsed
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Codes = require(Shared.Config.Codes)
local Rewards = require(Shared.Modules.Rewards)
local Clock = require(Shared.Modules.Clock)
local Net = require(Shared.Remotes.Net)

local CodesService = {
	Name = "CodesService",
	Priority = 45,
}

local MAX_LENGTH = 32

local DataService, EconomyService

function CodesService:Redeem(player, text: any): (boolean, any)
	if type(text) ~= "string" or #text == 0 or #text > MAX_LENGTH * 2 then
		return false, "InvalidArguments"
	end
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local code = Codes.Normalize(text)
	local def = Codes.ByCode[code]
	if not def then
		return false, "InvalidCode"
	end
	if def.ExpiresAt and Clock.Now() >= def.ExpiresAt then
		return false, "CodeExpired"
	end
	if def.Level and data.Level < def.Level then
		return false, "RequirementsNotMet"
	end
	local ok, result = EconomyService:GrantRewards(player, def.Rewards, { Reason = "Code:" .. code, OnceKey = "Code:" .. code })
	if not ok then
		return false, if result == "AlreadyClaimed" then "CodeAlreadyUsed" else result
	end
	return true, result
end

function CodesService:Init(services)
	self.Services = services
	DataService = services.DataService
	EconomyService = services.EconomyService
	-- Fail loudly in Studio if a code was configured with invalid rewards.
	for code, def in Codes.ByCode do
		local valid, why = Rewards.IsValid(def.Rewards)
		assert(valid, ("Code %s has invalid rewards: %s"):format(code, tostring(why)))
	end
	Net.Handle("RedeemCode", function(player, text)
		return self:Redeem(player, text)
	end, { RateLimit = 1, Burst = 3 })
end

return CodesService
