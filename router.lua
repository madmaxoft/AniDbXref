-- router.lua

--[[
Implements the HTTP server's routing table.
The routes are listed statically in the table below
Route handlers live in the Handlers subfolder.
--]]




local router = {}





-- Define static routes:
router.routes = {
	{ method = "GET",  pattern = "^/$",                    handler = require("Handlers.home") },
	{ method = "GET",  pattern = "^/[Ss]tatic/.*",         handler = require("Handlers.static") },
	{ method = "POST", pattern = "^/update%-start$",       handler = require("Handlers.update-start") },
	{ method = "GET",  pattern = "^/update%-confirm$",     handler = require("Handlers.update-confirm") },
	{ method = "GET",  pattern = "^/search?.*",            handler = require("Handlers.search") },
	{ method = "POST", pattern = "^/seen/add$",            handler = require("Handlers.seen-add") },
	{ method = "GET",  pattern = "^/anime/%d+$",           handler = require("Handlers.anime-details") },
	{ method = "GET",  pattern = "^/favicon.ico$",         handler = require("Handlers.favicon") },
	{ method = "GET",  pattern = "^/import$",              handler = require("Handlers.import").get },
	{ method = "POST", pattern = "^/import$",              handler = require("Handlers.import").post },
	{ method = "GET",  pattern = "^/import/test$",         handler = require("Handlers.import").importTest },
	{ method = "GET",  pattern = "^/import/review/",       handler = require("Handlers.import").reviewGet },
	{ method = "POST", pattern = "^/import/review/",       handler = require("Handlers.import").reviewPost },
}





--- Returns the function matching the specified method and path, and optionally captures from the route's pattern
-- Returns nil if no match found
function router.match(aMethod, aPath)
	for _, route in ipairs(router.routes) do
		local captures = { aPath:match(route.pattern) }
		if ((route.method == aMethod) and (#captures > 0 or aPath:match(route.pattern))) then
			return route.handler, captures
		end
	end
end





return router
