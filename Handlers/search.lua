--- Handles Anime title search requests
local db = require("db")





return function(aRequest, aResponse)
	local path, params = aRequest:parsePathAndQuery()
	if (not(params) or not(params["q"])) then
		return aResponse:sendError(404, "Query parameter not found")
	end

	-- For an empty query, return empty results:
	if (params.q == "") then
		return aResponse:sendTemplate("searchResults", { query = params.q, results = { n = 0 } })
	end

	local results = db.searchAnimeTitles(params.q)
	return aResponse:sendTemplate("searchResults",
		{
			query = params.q,
			results = results
		}
	)
end
