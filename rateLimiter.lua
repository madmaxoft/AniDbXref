-- rateLimiter.lua

--[[
Implements the RateLimiter class handling rate-limiting for URLs.
Multiple independent instances can be created.
Clients first ask the rate limiter if the rate limit was hit recently; if not, they attempt the URL request.
Once the request succeeds or fails, they report this to the rate limiter. The rate limiter only disallows
requests once a rate-limit is reported, and only for a pre-hard-coded amount of time.
The RateLimiter API consists of:
	- canAttemptRequest(): Returns true if a request can be made
	- rateLimitReached(): Notifies the instance that a rate limit has just been reached
	- success(): Notifies the instance that a successful request was made
There's also a RateLimiter.default that always allows requests
--]]





local RateLimiter =
{
	-- The default rate limiter always allows any request:
	default =
	{
		canAttemptRequest = function() return true end,
		rateLimitReached = function() end,
		success = function() end,
	}
}





--- Creates a new RatLimiter object
-- aRateLimitDelay is the delay (in seconds) to disallow requests after a rate limit is hit
function RateLimiter.new(aRateLimitDelay)
	local res = {}
	setmetatable(res, RateLimiter)
	RateLimiter.__index = RateLimiter
	res.rateLimitUntil = os.clock() - 1
	res.rateLimitDelay = aRateLimitDelay
	return res
end





function RateLimiter:canAttemptRequest()
	return (self.rateLimitUntil < os.clock())
end





function RateLimiter:rateLimitReached()
	self.rateLimitUntil = os.clock() + self.rateLimitDelay
end





function RateLimiter:success()
	-- Not exactly needed, but let's allow further requests:
	self.rateLimitUntil = os.clock() - 1
end





return RateLimiter
