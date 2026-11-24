--[[
	EventService
	Global time-limited modifiers (2x Yen weekends, launch luck...).

	  Event:GetActiveEvents() -> { { Id, Name, Description, Modifiers, EndsAt? } }
	  Event:GetModifier(stat) -> number (product of every active event's modifier for that stat)
	  Event:StartEvent(id, durationSeconds, definition?)   runtime/admin events
	  Event:StopEvent(id)

	Scheduled events come from Config/Events (StartsAt/EndsAt or WeeklyDays). Clients are notified via the
	EventsChanged remote whenever the active set changes, and can query GetServerInfo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Features = require(Shared.Config.Features)
local Events = require(Shared.Config.Events)
local Clock = require(Shared.Modules.Clock)
local Net = require(Shared.Remotes.Net)

local EventService = {
	Name = "EventService",
	Priority = 2,
}

local CHECK_INTERVAL = 30

local runtimeEvents: { [string]: any } = {}
local lastSignature = ""

local function isScheduledActive(def, now: number): boolean
	if def.WeeklyDays then
		return table.find(def.WeeklyDays, Clock.Weekday(now)) ~= nil
	end
	if def.StartsAt and def.EndsAt and def.EndsAt > def.StartsAt then
		return now >= def.StartsAt and now < def.EndsAt
	end
	return false
end

function EventService:GetActiveEvents(): { any }
	local now = Clock.Now()
	local active = {}
	for _, def in Events.List do
		if isScheduledActive(def, now) then
			table.insert(active, { Id = def.Id, Name = def.Name, Description = def.Description, Modifiers = def.Modifiers, EndsAt = def.EndsAt })
		end
	end
	for id, event in runtimeEvents do
		if event.EndsAt > now then
			table.insert(active, event)
		else
			runtimeEvents[id] = nil
		end
	end
	table.sort(active, function(a, b)
		return a.Id < b.Id
	end)
	return active
end

function EventService:GetModifier(stat: string): number
	if not Features.Events then
		return 1
	end
	local multiplier = 1
	for _, event in self:GetActiveEvents() do
		local value = event.Modifiers[stat]
		if type(value) == "number" and value > 0 then
			multiplier *= value
		end
	end
	return multiplier
end

function EventService:StartEvent(id: string, duration: number, definition: { Name: string?, Description: string?, Modifiers: { [string]: number } }?): (boolean, any)
	local base = Events.Get(id)
	local modifiers = (definition and definition.Modifiers) or (base and base.Modifiers)
	if type(modifiers) ~= "table" or type(duration) ~= "number" or duration <= 0 then
		return false, "InvalidArguments"
	end
	runtimeEvents[id] = {
		Id = id,
		Name = (definition and definition.Name) or (base and base.Name) or id,
		Description = (definition and definition.Description) or (base and base.Description) or "",
		Modifiers = modifiers,
		EndsAt = Clock.Now() + duration,
	}
	self:_broadcastIfChanged(true)
	return true, runtimeEvents[id]
end

function EventService:StopEvent(id: string)
	runtimeEvents[id] = nil
	self:_broadcastIfChanged(true)
end

function EventService:_broadcastIfChanged(force: boolean?)
	local active = self:GetActiveEvents()
	local ids = {}
	for _, event in active do
		table.insert(ids, event.Id)
	end
	local signature = table.concat(ids, ",")
	if force or signature ~= lastSignature then
		lastSignature = signature
		Net.FireAll("EventsChanged", active)
	end
end

function EventService:Init(services)
	self.Services = services
	Net.Handle("GetServerInfo", function()
		return true, { Events = self:GetActiveEvents(), ServerTime = Clock.Now() }
	end, { RateLimit = 1, Burst = 3 })
end

function EventService:Start()
	while true do
		self:_broadcastIfChanged(false)
		task.wait(CHECK_INTERVAL)
	end
end

return EventService
