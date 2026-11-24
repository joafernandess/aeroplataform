--[[
	Server entry point.
	Loads every ModuleScript under Server/Services, runs Init on all of them (in Priority order), then Start.
	Adding a service = adding a ModuleScript to the Services folder; nothing else to wire here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent
local ServiceLoader = require(Server.Core.ServiceLoader)
local Net = require(ReplicatedStorage.Shared.Remotes.Net)

-- Remotes must exist before any client asks for them.
Net.Init()

local services, ordered = ServiceLoader.Load(Server.Services:GetChildren())
ServiceLoader.InitAll(services, ordered)
ServiceLoader.StartAll(ordered)

local names = {}
for _, service in ordered do
	table.insert(names, service.Name)
end
print(("[Server] %d services running: %s"):format(#ordered, table.concat(names, ", ")))
