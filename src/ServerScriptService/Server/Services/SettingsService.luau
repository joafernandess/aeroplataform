--[[
	SettingsService
	Validated player settings. Each setting has a type and (for numbers) a range; anything else is rejected.
	Settings that affect the server (DamageNumbers, AutoDelete*) are read directly from
	PlayerData.Settings by the relevant service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Remotes.Net)

local SettingsService = {
	Name = "SettingsService",
	Priority = 50,
}

SettingsService.Schema = {
	MusicVolume = { Type = "number", Min = 0, Max = 1 },
	SFXVolume = { Type = "number", Min = 0, Max = 1 },
	DamageNumbers = { Type = "boolean" },
	LowGraphics = { Type = "boolean" },
	ShowOtherUnits = { Type = "boolean" },
	AutoDeleteCommon = { Type = "boolean" },
	AutoDeleteRare = { Type = "boolean" },
	LastSeenUpdate = { Type = "string", MaxLength = 32 },
}

local DataService

function SettingsService:Set(player, key: any, value: any): (boolean, any)
	local data = DataService:GetData(player)
	if not data then
		return false, "DataNotLoaded"
	end
	local rule = type(key) == "string" and SettingsService.Schema[key]
	if not rule or type(value) ~= rule.Type then
		return false, "InvalidArguments"
	end
	if rule.Type == "string" and #value > (rule.MaxLength or 32) then
		return false, "InvalidArguments"
	end
	if rule.Type == "number" then
		if value ~= value or value < rule.Min or value > rule.Max then
			return false, "InvalidArguments"
		end
	end
	data.Settings[key] = value
	DataService:MarkDirty(player, "Settings")
	return true, value
end

function SettingsService:Init(services)
	self.Services = services
	DataService = services.DataService
	Net.Handle("UpdateSetting", function(player, key, value)
		return self:Set(player, key, value)
	end, { RateLimit = 6 })
end

return SettingsService
