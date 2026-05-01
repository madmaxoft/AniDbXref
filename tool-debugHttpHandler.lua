-- tool-debugHttpHandler.lua

--[[
A test harness to debug a selected HTTP handler in a synchronous environment, in order to avoid
asynchronous pitfalls with the ZBS debugger.
Calls the router on the specified mocked HTTP request.
--]]




local theRequest =
{
	method = function()
		return "GET"
	end,
	path = function()
		return "/picture?id=313313.jpg"
	end,
	httpVersion = function()
		return "1.1"
	end,
}
theRequest.__index = require("httpRequest")  -- inherit httpRequest's functions
setmetatable(theRequest, theRequest)

local theResponse1 = require("httpResponse").new({send = function(...) end, })
local theResponse2 = require("httpResponse").new({send = function(...) end, })
local router = require("router")

-- This should fail only in mSocket.send() not being defined:
print("Requesting 1st request")
router.handleRequest(theRequest, theResponse1)
theRequest.path = function() return "/picture?id=313310.jpg" end

print("Requesting 2nd request")
router.handleRequest(theRequest, theResponse2)
