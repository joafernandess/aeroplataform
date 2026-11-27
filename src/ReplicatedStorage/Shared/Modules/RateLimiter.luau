--[[
	RateLimiter
	Token bucket keyed by any value (usually player). Used by the network layer to throttle remotes.
]]

local Clock = require(script.Parent.Clock)

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(ratePerSecond: number, burst: number?)
	return setmetatable({
		_rate = ratePerSecond,
		_burst = burst or ratePerSecond,
		_buckets = {},
	}, RateLimiter)
end

function RateLimiter:Check(key: any): boolean
	local now = Clock.Precise()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { Tokens = self._burst, Last = now }
		self._buckets[key] = bucket
	end
	bucket.Tokens = math.min(self._burst, bucket.Tokens + (now - bucket.Last) * self._rate)
	bucket.Last = now
	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end
	return false
end

function RateLimiter:Remove(key: any)
	self._buckets[key] = nil
end

return RateLimiter
