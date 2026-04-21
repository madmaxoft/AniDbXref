-- router.lua

--[[
Implements the HTTP server's routing table.
The routes are listed statically in the table below
Route handlers live in the Handlers subfolder.
--]]




local copas = require("copas")
local httpRequest = require("httpRequest")
local httpResponse = require("httpResponse")
local socket = require("socket")
local log = require("logger").log





local router = {}





-- Define static routes:
router.routes = require("routeTable")





--- Calls the specified handler safely - if an error is raised, an error page is served
function router.dispatchHandler(aHandler, aRequest, aResponse)
	assert(type(aHandler) == "function")
	assert(aRequest)
	assert(aRequest.httpVersion)
	assert(aResponse)
	assert(aResponse.setHeader)

	-- error handler that adds traceback
	local function onError(aErr)
		return debug.traceback(aErr, 2)
	end

	-- run handler safely
	local ok, result = xpcall(function()
		return aHandler(aRequest, aResponse)
	end, onError)

	-- If an exception occurred, log and send it to the client:
	if not(ok) then
		local errText = result or "Unknown error"
		log("router", "ERROR during request: %s", errText)
		aResponse:sendError(500, errText)
	end
end





--- Handles a single HTTP client connection
function router.handleRequest(aRequest, aResponse)
	assert(aRequest)
	assert(aRequest.httpVersion)  -- Is it an HttpRequest object?
	assert(aResponse)
	assert(aResponse.setHeader)  -- Is it an HttpResponse object?

	local handler = router.match(aRequest)
	if (handler) then
		local beginTime = socket.gettime()
		log("router", "%s Request for path \"%s\".", aRequest:method(), aRequest:path())
		router.dispatchHandler(handler, aRequest, aResponse)
		local endTime = socket.gettime()
		if (endTime - beginTime >= 0.5) then
			log("router", "  ^^ Request took %f seconds.", (endTime - beginTime))
		end
	else
		log("router", "UNHANDLED: %s Request for path \"%s\".", aRequest:method(), aRequest:path())
		aResponse:sendError(404, "Not Found")
	end
end





--- Returns the handler function matching the specified request
-- Returns nil if no match found
function router.match(aRequest)
	assert(aRequest)
	assert(aRequest.httpVersion)

	local method = aRequest:method()
	local path = aRequest:path()
	for _, route in ipairs(router.routes[method] or {}) do
		if (route.path == string.sub(path, 1, #route.path)) then
			if not(route.handler) then
				log("router", "ERROR: Route entry found, but no handler present for request %s %s", aRequest:method(), aRequest:path())
			end
			return route.handler
		end
	end
end





return router
