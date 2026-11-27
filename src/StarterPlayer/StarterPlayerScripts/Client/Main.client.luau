--[[
	Client entry point.
	Loads every controller under Client/Controllers, runs Init (Priority order), starts the State mirror,
	then Start on every controller. Controllers never decide game outcomes; they render state and send
	requests to the server.
]]

local Client = script.Parent
local State = require(Client.State)

local controllers = {}
local ordered = {}
for _, module in Client.Controllers:GetChildren() do
	if module:IsA("ModuleScript") then
		local controller = require(module)
		controller.Name = controller.Name or module.Name
		controllers[controller.Name] = controller
		table.insert(ordered, controller)
	end
end
table.sort(ordered, function(a, b)
	local pa, pb = a.Priority or 100, b.Priority or 100
	if pa == pb then
		return a.Name < b.Name
	end
	return pa < pb
end)

for _, controller in ordered do
	if controller.Init then
		local ok, err = pcall(controller.Init, controller, controllers)
		if not ok then
			warn(("[Client] %s:Init failed: %s"):format(controller.Name, tostring(err)))
		end
	end
end

State.Init()

for _, controller in ordered do
	if controller.Start then
		task.spawn(function()
			local ok, err = pcall(controller.Start, controller)
			if not ok then
				warn(("[Client] %s:Start failed: %s"):format(controller.Name, tostring(err)))
			end
		end)
	end
end
