--[[
	Events
	Time-limited global modifiers. Scheduled events activate automatically between StartsAt and EndsAt
	(unix seconds, UTC). Admins can also start an event at runtime through EventService.

	Modifiers: { Damage?, Yen?, XP?, Luck?, Gold? } — multiplicative, stacked across active events.
]]

export type EventDef = {
	Id: string,
	Name: string,
	Description: string,
	StartsAt: number?,
	EndsAt: number?,
	Modifiers: { [string]: number },
	-- Weekly recurrence: active on these UTC weekdays (1 = Sunday ... 7 = Saturday). Optional.
	WeeklyDays: { number }?,
}

local Events = {}

Events.List = {
	{
		Id = "EV_WeekendYen", Name = "Weekend Fortune", Description = "2x Yen every Saturday and Sunday (UTC).",
		WeeklyDays = { 1, 7 }, Modifiers = { Yen = 2 },
	},
	{
		Id = "EV_LaunchLuck", Name = "Launch Celebration", Description = "1.5x luck and XP during the launch window.",
		-- Placeholder window: set real launch timestamps before publishing.
		StartsAt = 0, EndsAt = 0, Modifiers = { Luck = 1.5, XP = 1.5 },
	},
} :: { EventDef }

Events.ById = {} :: { [string]: EventDef }
for _, def in Events.List do
	Events.ById[def.Id] = def
end

function Events.Get(id: string): EventDef?
	return Events.ById[id]
end

return Events
