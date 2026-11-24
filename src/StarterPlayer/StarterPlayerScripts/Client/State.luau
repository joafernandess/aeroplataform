--[[
	State (client)
	Read-only mirror of the player's profile. The server is the source of truth:
	  - full snapshot via GetProfile on start
	  - incremental top-level updates via the DataChanged remote
	Controllers subscribe with State.Observe(keys, callback) and never mutate State.Data themselves.
	State.Request wraps Net.Request and shows an error toast when a request fails.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Modules.Signal)
local Errors = require(Shared.Modules.Errors)
local Net = require(Shared.Remotes.Net)

local State = {}

State.Data = nil :: { [string]: any }?
State.Loaded = Signal.new()
State.Changed = Signal.new() -- (key, value)
State.ActiveEvents = {}
State.EventsChanged = Signal.new()
State.Notify = nil :: ((text: string, kind: string?) -> ())? -- set by NotificationController

function State.Init()
	Net.Connect("DataChanged", function(key, value)
		if State.Data then
			State.Data[key] = value
			State.Changed:Fire(key, value)
		end
	end)
	Net.Connect("EventsChanged", function(events)
		State.ActiveEvents = events or {}
		State.EventsChanged:Fire(State.ActiveEvents)
	end)
	task.spawn(function()
		while not State.Data do
			local response = Net.Request("GetProfile")
			if response.ok then
				State.Data = response.data
				State.Loaded:Fire(State.Data)
				break
			end
			task.wait(1)
		end
		local info = Net.Request("GetServerInfo")
		if info.ok and info.data then
			State.ActiveEvents = info.data.Events or {}
			State.EventsChanged:Fire(State.ActiveEvents)
		end
	end)
end

function State.IsLoaded(): boolean
	return State.Data ~= nil
end

-- Calls `callback(data)` now (if loaded) and whenever any of `keys` changes.
function State.Observe(keys: { string }, callback: (data: { [string]: any }) -> ())
	local set = {}
	for _, key in keys do
		set[key] = true
	end
	if State.Data then
		task.spawn(callback, State.Data)
	end
	State.Loaded:Connect(function(data)
		callback(data)
	end)
	State.Changed:Connect(function(key)
		if set[key] and State.Data then
			callback(State.Data)
		end
	end)
end

-- Server request with automatic error toast. Returns the response envelope.
function State.Request(name: string, ...: any)
	local response = Net.Request(name, ...)
	if not response.ok and State.Notify then
		State.Notify(Errors.Message(response.error), "Error")
	end
	return response
end

return State
