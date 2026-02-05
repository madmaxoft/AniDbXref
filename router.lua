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
-- NOTE: The matcher goes from top to bottom and uses the first substring match,
-- so the more generic URLs need to go at the bottom
-- Otherwise, the routes generally follow an alpha-sorted order
router.routes =
{
	GET =
	{
		{ path = "/anime/",                handler = require("Handlers.animeDetails").get },
		{ path = "/favicon.ico",           handler = require("Handlers.favicon") },
		{ path = "/import/review/",        handler = require("Handlers.importUI").getReview },
		{ path = "/import/test",           handler = require("Handlers.importUI").getImportTest },
		{ path = "/import",                handler = require("Handlers.importUI").get },
		{ path = "/force-update-details/", handler = require("Handlers.forceUpdateDetails") },
		{ path = "/picture",               handler = require("Handlers.picture") },
		{ path = "/search?",               handler = require("Handlers.search") },
		{ path = "/season",                handler = require("Handlers.season") },
		{ path = "/shutdown",              handler = require("Handlers.shutdown") },
		{ path = "/static/",               handler = require("Handlers.static") },
		{ path = "/Static/",               handler = require("Handlers.static") },
		{ path = "/update-confirm",        handler = require("Handlers.updateConfirm") },
		{ path = "/voiceActor/",           handler = require("Handlers.voiceActorDetails") },
		{ path = "/voiceActors",           handler = require("Handlers.voiceActors") },
		{ path = "/",                      handler = require("Handlers.home") },
	},
	POST =
	{
		{ path = "/anime/setSeen",  handler = require("Handlers.animeDetails").postSetSeen },
		{ path = "/import/review/", handler = require("Handlers.importUI").postReview },
		{ path = "/import",         handler = require("Handlers.importUI").post },
		{ path = "/seen/add",       handler = require("Handlers.seenAdd") },
		{ path = "/update-start",   handler = require("Handlers.updateStart") },
	},
}





--- Calls the specified handler safely - if an error is raised, an error page is served
function router.dispatchHandler(aClient, aPath, aHeaders, aHandler)
	-- error handler that adds traceback
	local function onError(aErr)
		return debug.traceback(aErr, 2)
	end

	-- run handler safely
	local ok, result = xpcall(function()
		return aHandler(aClient, aPath, aHeaders)
	end, onError)

	-- If an exception occurred, log and send it to the client:
	if not(ok) then
		local errText = result or "Unknown error"
		log("router", "ERROR during request:\n" .. errText)
		httpResponse.sendError(aClient, 500, errText)
	end
end





--- Handles a single HTTP client connection
function router.handleRequest(aClient)
	local method, path, headers = httpRequest.readRequestHeaders(aClient)
	if (not(method) or not(path)) then
		return
	end

	local handler = router.match(method, path)
	if (handler) then
		local beginTime = socket.gettime()
		log("router", "%s Request for path \"%s\".", method, path)
		router.dispatchHandler(aClient, path, headers, handler)
		local endTime = socket.gettime()
		if (endTime - beginTime >= 0.5) then
			log("router", "  ^^ Request took %f seconds.", (endTime - beginTime))
		end
	else
		log("router", "UNHANDLED: %s Request for path \"%s\".", method, path)
		httpResponse.sendError(aClient, "404 Not Found")
	end
end





--- Returns the function matching the specified method and path, and optionally captures from the route's pattern
-- Returns nil if no match found
function router.match(aMethod, aPath)
	assert(type(aMethod) == "string")
	assert(type(aPath) == "string")

	for _, route in ipairs(router.routes[aMethod] or {}) do
		if (route.path == string.sub(aPath, 1, #route.path)) then
			return route.handler
		end
	end
end





return router
