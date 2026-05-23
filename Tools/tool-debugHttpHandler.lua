-- Tools/tool-debugHttpHandler.lua

--[[
A test harness to debug a selected HTTP handler in a synchronous environment, in order to avoid
asynchronous pitfalls with the ZBS debugger.
Calls the router on the specified mocked HTTP request.
--]]




-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true





local theRequest =
{
	mMethod = "GET",
	mPathAndQuery = "/watchlist",
	mHttpVersion = "1.1",
	mHeaders = {},

	-- Add a dummy socket implementation:
	mSocket =
	{
		send = function() end,
	}
}
theRequest.__index = require("httpRequest")  -- inherit httpRequest's functions
setmetatable(theRequest, theRequest)

local theResponse1 = require("httpResponse").new(theRequest)
local router = require("router")

print("Requesting 1st request")
router.handleRequest(theRequest, theResponse1)

print("Requesting 2nd request")
theRequest.path = function() return "/picture?id=313310.jpg" end
local theResponse2 = require("httpResponse").new(theRequest)
router.handleRequest(theRequest, theResponse2)
