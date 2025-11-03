--- Handles Anime title search requests
local db = require("db")
local httpResponse = require("httpResponse")
local httpRequest = require("httpRequest")





return function(aClient, aRequestPath, aRequestParameters, aRequestHeaders)
	local path, params = httpRequest.parseRequestPath(aRequestPath)
	if (not(params) or not(params["q"])) then
		httpResponse.send(aClient, "404 Not Found")
		return
	end

	if (params.q == "") then
		local template = require("Templates").searchResults
		local html = template({ query = params.q, results = { n = 0 } })
		return httpResponse.send(aClient, 200, nil, html)
	end

	local results = db.searchAnimeTitles(params.q)
	local template = require("Templates").searchResults
	local html = template({
		query = params.q,
		results = results
	})

	httpResponse.send(aClient, 200, nil, html)
end
