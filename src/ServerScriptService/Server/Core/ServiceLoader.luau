--[[
	ServiceLoader
	Two-phase lifecycle for server services:
	  1. Init(services)  — synchronous; resolve dependencies, register remotes, create signals.
	                        Must not yield and must not assume other services have started.
	  2. Start()          — runs in its own thread; connect Players events, start loops.

	Services are plain ModuleScripts returning a table with `Name`, optional `Priority` (lower = earlier),
	`Init` and `Start`. Services reach each other through the shared `services` table, which avoids
	require cycles between services that depend on each other.
]]

local ServiceLoader = {}

export type Service = {
	Name: string,
	Priority: number?,
	Init: ((self: any, services: { [string]: any }) -> ())?,
	Start: ((self: any) -> ())?,
}

function ServiceLoader.Load(modules: { Instance }): { [string]: any }
	local services = {}
	local ordered = {}
	for _, module in modules do
		if module:IsA("ModuleScript") then
			local service = require(module) :: any
			assert(type(service) == "table", module.Name .. " must return a table")
			service.Name = service.Name or module.Name
			assert(services[service.Name] == nil, "Duplicate service " .. service.Name)
			services[service.Name] = service
			table.insert(ordered, service)
		end
	end
	table.sort(ordered, function(a, b)
		local pa, pb = a.Priority or 100, b.Priority or 100
		if pa == pb then
			return a.Name < b.Name
		end
		return pa < pb
	end)
	return services, ordered
end

function ServiceLoader.InitAll(services: { [string]: any }, ordered: { any })
	for _, service in ordered do
		if service.Init then
			local ok, err = pcall(service.Init, service, services)
			if not ok then
				error(("[ServiceLoader] %s:Init failed: %s"):format(service.Name, tostring(err)), 0)
			end
		end
	end
end

function ServiceLoader.StartAll(ordered: { any })
	for _, service in ordered do
		if service.Start then
			task.spawn(function()
				local ok, err = pcall(service.Start, service)
				if not ok then
					warn(("[ServiceLoader] %s:Start failed: %s"):format(service.Name, tostring(err)))
				end
			end)
		end
	end
end

return ServiceLoader
