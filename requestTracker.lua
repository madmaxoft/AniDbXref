-- requestTracker.lua

--[[
Keeps track of whether there is currently any request being processed, via its beginRequest() and
endRequest() calls. While a request is being processed, it is ill-advised to make any outgoing requests
(name lookup may block for seconds) or heavy calculations. Use the yieldUntilNoRequests() function before
starting those operations, it keeps yielding until there is no request being currently processed.
There's an upper limit on the yielding, gMaxDelaySec, after which the yielding is aborted and the operation
continues, despite there being a request.
--]]





--- Keeps track of the number of requests currently being processed
local gNumCurrentRequests = 0

--- Timestamp of when the last request has finished processing
local gLastRequestTimestamp = 0

--- The maximum delay to be made. Reaching this will abort the yielding and continue the operation anyway
local gMaxDelaySec = 30

--- The delay for half-busy-waiting, between checking the request status
local gDelayDurationSec = 0.2




local copas = require("copas")
local log = require("logger").log





--- The API returned from this module
local requestTracker = {}




--- Called by main when a new request from the client has started processing
function requestTracker.beginRequest()
	gNumCurrentRequests = gNumCurrentRequests + 1
end





--- Called by main to indicate a request has finished processing
function requestTracker.endRequest()
	assert(gNumCurrentRequests > 0)

	gNumCurrentRequests = gNumCurrentRequests - 1
	if (gNumCurrentRequests == 0) then
		gLastRequestTimestamp = os.time()
	end
end






--- Keeps yielding until there is no request currently being processed
-- Should be called before starting a potentially-blocking or CPU-heavy operation, so that the operation
-- doesn't block the server.
function requestTracker.yieldUntilNoRequests()
	local numCycles = gMaxDelaySec / gDelayDurationSec
	for i = 1, numCycles do
		if (
			(gNumCurrentRequests == 0) and           -- No requests in flight
			(os.time() - gLastRequestTimestamp > 1)  -- Wait at least one second after the last request has finished
		) then
			return
		end
		copas.pause(0.2)
	end
	log("requestTracker", "Reached max delay while waiting for no incoming requests.")
end





return requestTracker
