-- routeTable.lua

--[[
Defines the static routing table, used by the HTTP router.
The matcher goes from top to bottom and uses the first substring match,
so the more generic URLs need to go at the bottom
Otherwise, the routes generally follow an alpha-sorted order
--]]





return {
	GET =
	{
		{ path = "/anime/",                handler = require("Handlers.animeDetails").get },
		{ path = "/api/v1/seen",           handler = require("Handlers.api").getSeen },
		{ path = "/api/v1/watchlist",      handler = require("Handlers.api").getWatchlist },
		{ path = "/config",                handler = require("Handlers.configEditor").get },
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
		{ path = "/watchlist/edit",        handler = require("Handlers.watchlist").getEdit },
		{ path = "/watchlist",             handler = require("Handlers.watchlist").get },
		{ path = "/",                      handler = require("Handlers.home") },
	},
	POST =
	{
		{ path = "/anime/setSeen",       handler = require("Handlers.animeDetails").postSetSeen },
		{ path = "/config",              handler = require("Handlers.configEditor").post },
		{ path = "/import/review/",      handler = require("Handlers.importUI").postReview },
		{ path = "/import",              handler = require("Handlers.importUI").post },
		{ path = "/seen/add",            handler = require("Handlers.seenAdd") },
		{ path = "/update-start",        handler = require("Handlers.updateStart") },
		{ path = "/watchlist/add/extra", handler = require("Handlers.watchlist").postAddExtra },
		{ path = "/watchlist/add",       handler = require("Handlers.watchlist").postAdd },
		{ path = "/watchlist/edit",      handler = require("Handlers.watchlist").postEdit },
		{ path = "/watchlist/remove",    handler = require("Handlers.watchlist").postRemove },
	},
}