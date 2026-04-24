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
		return "/watchlist"
	end,
	httpVersion = function()
		return "1.1"
	end,
}

local theResponse = require("httpResponse").new({})
local router = require("router")
router.handleRequest(theRequest, theResponse)