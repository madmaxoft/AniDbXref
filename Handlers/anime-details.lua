local db = require("db")
local httpResponse = require("httpResponse")
local requestQueue = require("requestQueue")





return function(aClient, aPath, aParams, aHeaders)
	local aId = tonumber(aPath:match("^/anime/(%d+)$"))
	if not(aId) then
		return httpResponse.write(aClient, 400, "text/plain", "Invalid aId")
	end

	local details = db.getAnimeDetails(aId)
	if not(details.description) then
		requestQueue.add(aId)
	end

	local template = require("Templates").animeDetails
	local html = template({ details = details, aId = aId })
	httpResponse.send(aClient, 200, nil, html)
end
