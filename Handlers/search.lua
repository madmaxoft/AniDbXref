--- Handles Anime title search requests
local db = require("db")
local httpResponse = require("httpResponse")
local httpRequest = require("httpRequest")





return function(aClient, aRequestPath, aRequestHeaders)
	local path, params = httpRequest.parseRequestPath(aRequestPath)
	if (not(params) or not(params["q"])) then
		httpResponse.sendError(aClient, 404, "Query parameter not found")
		return
	end

	-- For an empty query, return empty results:
	if (params.q == "") then
		return httpResponse.sendTemplate(aClient, "searchResults", { query = params.q, results = { n = 0 } })
	end

	local results = db.searchAnimeTitles(params.q)
	return httpResponse.sendTemplate(aClient, "searchResults",
		{
			query = params.q,
			results = results
		}
	)
end
