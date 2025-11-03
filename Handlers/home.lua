-- Handlers/home.lua

--[[ Handler for the "/" root URL path.
--]]

local db = require("db")




return function (aClient)
	local seen = db.getSeenAnime("en")
	for _, s in ipairs(seen) do
		if (s.aId) then
			s.details = db.getAnimeDetails(s.aId)
		end
	end
	local body = require("Templates").home({
		hasAniDbData = db.hasBaseAniDbData(),
		seenAnime = seen,
	})
	require("httpResponse").send(aClient, "200 OK", nil, body)
end
