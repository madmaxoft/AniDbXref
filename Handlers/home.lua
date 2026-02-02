-- Handlers/home.lua

--[[ Handler for the "/" root URL path.
--]]

local db = require("db")




return function (aClient)
	return require("httpResponse").sendTemplate(aClient, "home", {
		hasAniDbData = db.hasBaseAniDbData(),
		seenAnime = db.getSeenAnimeForHomepage(),
	})
end
