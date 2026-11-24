--[[
	ServerHarness (Lune)
	Boots the real server services (Init phase only) against mocks:
	  - Net is replaced by a FakeNet so tests can invoke remotes like a client
	  - time is controlled through Clock overrides (h:Advance(seconds))
	  - visual adapters that need real Instances are replaced with no-op fakes
	Start() loops are NOT run; tests drive services directly (e.g. CombatService:Step()).
]]

local Runtime = require("./Runtime")
local Mocks = require("./Mocks")
local roblox = require("@lune/roblox")

local ServerHarness = {}
ServerHarness.__index = ServerHarness

local function fakeVisuals()
	return {
		Init = function() end,
		Create = function()
			return nil
		end,
		Update = function() end,
		Destroy = function() end,
		GetAreaCenter = function()
			return nil
		end,
	}
end

function ServerHarness.new(options: { Services: { string }? }?)
	local self = setmetatable({}, ServerHarness)
	local rt = Runtime.new({ IsServer = true })
	self.Runtime = rt
	self.Net = Mocks.FakeNet()
	rt:Mock("ReplicatedStorage/Shared/Remotes/Net", self.Net)

	local okVis = pcall(function()
		rt:Mock("ServerScriptService/Server/Combat/EnemyVisuals", fakeVisuals())
	end)
	local _ = okVis

	local GameConfig = rt:Require("ReplicatedStorage/Shared/Config/GameConfig")
	GameConfig.Data.RetryBaseDelay = 0
	self.GameConfig = GameConfig

	self.Now = 1_700_000_000 -- a Tuesday
	self.PreciseNow = 1000
	self.Clock = rt:Require("ReplicatedStorage/Shared/Modules/Clock")
	self.Clock.SetOverride(function()
		return self.Now
	end, function()
		return self.PreciseNow
	end)

	local ServiceLoader = rt:Require("ServerScriptService/Server/Core/ServiceLoader")
	local folder = rt:Find("ServerScriptService/Server/Services")
	local modules = {}
	local only = options and options.Services
	for _, child in folder:GetChildren() do
		if not only or table.find(only, child.Name) then
			table.insert(modules, child)
		end
	end
	local requireFn = function(m)
		return rt:Require(m)
	end
	-- ServiceLoader uses the global `require`; emulate it by loading modules ourselves.
	local services, ordered = {}, {}
	for _, module in modules do
		local service = requireFn(module)
		service.Name = service.Name or module.Name
		services[service.Name] = service
		table.insert(ordered, service)
	end
	table.sort(ordered, function(a, b)
		local pa, pb = a.Priority or 100, b.Priority or 100
		if pa == pb then
			return a.Name < b.Name
		end
		return pa < pb
	end)
	ServiceLoader.InitAll(services, ordered)
	self.Services = services
	self.Ordered = ordered
	self.Players = rt:GetService("Players")
	self.DataStores = rt.Mocks.Stores
	self.Mocks = Mocks
	self.Vector3 = roblox.Vector3
	return self
end

function ServerHarness:Advance(seconds: number)
	self.Now += seconds
	self.PreciseNow += seconds
end

-- Adds a fake player and loads its profile synchronously.
function ServerHarness:AddPlayer(userId: number?, name: string?, position: any?)
	local player = Mocks.FakePlayer(userId or math.random(1, 1e9), name)
	if position then
		player.Character = Mocks.FakeCharacter(position)
	end
	table.insert(self.Players._list, player)
	local profile = self.Services.DataService:LoadProfile(player)
	assert(profile, "profile failed to load in harness: " .. tostring(player.Kicked))
	return player, profile.Data
end

function ServerHarness:Invoke(player, name: string, ...)
	return self.Net.Invoke(player, name, ...)
end

function ServerHarness:Data(player)
	return self.Services.DataService:GetData(player)
end

return ServerHarness
