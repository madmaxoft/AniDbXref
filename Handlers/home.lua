-- Handlers/home.lua

--[[ Handler for the "/" root URL path.
--]]

local db = require("db")




return function (aRequest, aResponse)
	return aResponse:sendTemplate("home", {
		hasAniDbData = db.hasBaseAniDbData(),
		seenAnime = db.getSeenAnimeForHomepage(),
	})
end
