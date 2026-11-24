--[[
	AdminService
	Debug/admin commands for testing in Studio and for whitelisted UserIds (GameConfig.Admin.UserIds).
	Every command goes through the normal services (EconomyService, UnitService...), so admin actions obey
	the same validation and are written to the transaction log with an "Admin:" reason.

	Client usage (Studio command bar on the client, or the debug UI):
	  Net.Request("AdminCommand", "give", { Currency = "Gems", Amount = 1000 })
	Commands: give, take, unit, item, xp, level, unlockall, event, spawn, resetquests
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Worlds = require(Shared.Config.Worlds)
local Validate = require(Shared.Modules.Validate)
local Net = require(Shared.Remotes.Net)

local Server = script.Parent.Parent
local PlayerUtil = require(Server.Core.PlayerUtil)

local AdminService = {
	Name = "AdminService",
	Priority = 90,
}

function AdminService:IsAdmin(player): boolean
	if RunService:IsStudio() then
		return true
	end
	return table.find(GameConfig.Admin.UserIds, player.UserId) ~= nil
end

AdminService.Commands = {
	give = function(self, player, args)
		return self.Services.EconomyService:Add(player, args.Currency, args.Amount, "Admin:give")
	end,
	take = function(self, player, args)
		return self.Services.EconomyService:Remove(player, args.Currency, args.Amount, "Admin:take")
	end,
	unit = function(self, player, args)
		return self.Services.UnitService:CreateUnit(player, args.UnitId, { Source = "Admin", IgnoreCapacity = true, Trait = args.Trait })
	end,
	item = function(self, player, args)
		return self.Services.InventoryService:AddItem(player, args.ItemId, args.Count or 1, "Admin")
	end,
	xp = function(self, player, args)
		return self.Services.ProgressionService:AddPlayerXP(player, args.Amount)
	end,
	level = function(self, player, args)
		local data = self.Services.DataService:GetData(player)
		if not Validate.Integer(args.Level, 1, 1000) then
			return false, "InvalidArguments"
		end
		data.Level = args.Level
		data.Experience = 0
		self.Services.DataService:MarkDirty(player, "Level")
		return true, data.Level
	end,
	unlockall = function(self, player)
		local data = self.Services.DataService:GetData(player)
		for _, world in Worlds.List do
			data.UnlockedWorlds[world.Id] = true
		end
		self.Services.DataService:MarkDirty(player, "UnlockedWorlds")
		return true, nil
	end,
	event = function(self, _player, args)
		return self.Services.EventService:StartEvent(args.Id or "AdminEvent", args.Duration or 600, { Name = args.Name, Modifiers = args.Modifiers })
	end,
	spawn = function(self, player, args)
		local position = PlayerUtil.GetPosition(player)
		if not position then
			return false, "InvalidArguments"
		end
		local zone = self.Services.WorldService:GetZoneKey(player)
		local ok, enemy = pcall(self.Services.EnemyService.Spawn, self.Services.EnemyService, args.EnemyId, position + Vector3.new(0, 0, 12), zone)
		if not ok then
			return false, "InvalidArguments"
		end
		return true, enemy.Id
	end,
	resetquests = function(self, player)
		local data = self.Services.DataService:GetData(player)
		data.Quests.DailyDay = 0
		self.Services.QuestService:RefreshDailies(player)
		return true, nil
	end,
}

function AdminService:Run(player, command: string, args: { [string]: any }?): (boolean, any)
	if not self:IsAdmin(player) then
		return false, "NotAdmin"
	end
	local handler = AdminService.Commands[command]
	if not handler then
		return false, "InvalidArguments"
	end
	if not self.Services.DataService:GetData(player) then
		return false, "DataNotLoaded"
	end
	print(("[Admin] %s ran %s"):format(player.Name, command))
	return handler(self, player, args or {})
end

function AdminService:Init(services)
	self.Services = services
	Net.Handle("AdminCommand", function(player, command, args)
		if not Validate.String(command, 24) or (args ~= nil and type(args) ~= "table") then
			return false, "InvalidArguments"
		end
		return self:Run(player, command, args)
	end, { RateLimit = 5 })
end

return AdminService
