--[[
	Clock
	Single source of time for gameplay code so tests can control it.
	  Clock.Now()      -> unix seconds (UTC), for persistence (daily resets, cooldowns, boosts)
	  Clock.Precise()  -> monotonic seconds with sub-second precision, for combat timers
]]

local Clock = {}

local nowOverride: (() -> number)? = nil
local preciseOverride: (() -> number)? = nil

local SECONDS_PER_DAY = 86400

function Clock.Now(): number
	if nowOverride then
		return nowOverride()
	end
	return os.time()
end

function Clock.Precise(): number
	if preciseOverride then
		return preciseOverride()
	end
	return os.clock()
end

-- Index of the UTC day (days since epoch), shifted by `offsetSeconds`.
function Clock.Day(timestamp: number?, offsetSeconds: number?): number
	local t = (timestamp or Clock.Now()) - (offsetSeconds or 0)
	return math.floor(t / SECONDS_PER_DAY)
end

-- 1 = Sunday ... 7 = Saturday (matches os.date("!*t").wday). 1970-01-01 was a Thursday (5).
function Clock.Weekday(timestamp: number?): number
	local day = Clock.Day(timestamp)
	return ((day + 4) % 7) + 1
end

function Clock.SecondsUntilNextDay(timestamp: number?, offsetSeconds: number?): number
	local t = (timestamp or Clock.Now()) - (offsetSeconds or 0)
	return SECONDS_PER_DAY - (t % SECONDS_PER_DAY)
end

-- Test hooks ------------------------------------------------------------------
function Clock.SetOverride(now: (() -> number)?, precise: (() -> number)?)
	nowOverride = now
	preciseOverride = precise
end

return Clock
