-- Handlers/watchlist.lua

--[[
Implements the HTTP endpoints for displaying and editing the watchlist, present and past
--]]





local utils = require("utils")
local db = require("db")





local M = {}





function M.get(aRequest, aResponse)
	-- Parse the season from the URL, if present:
	local season = aRequest:pathAndQuery():match("/watchlist/(.+)")
	if not(season) then
		season = utils.currentSeason()
	end
	local seasonDescription = utils.seasonToDescription(season)
	if not(seasonDescription) then
		return aResponse:sendError(404, "Invalid season specified")
	end

	-- Preprocess the anime and the watchlist:
	local seasonAnime = db.animeInSeason(season)
	local watchlist = db.watchlistInSeason(season)
	for _, w in ipairs(watchlist) do
		watchlist[w.aId] = w
	end
	for _, a in ipairs(seasonAnime) do
		a.watchlist = watchlist[a.aId]
		a.dayOfWeek = utils.ymdDayOfWeek(a.startDate)
	end
	return aResponse:sendTemplate("watchlist",
		{
			season = season,
			seasonAnime = seasonAnime,
			seasonYear = tonumber(season:match("(%d+)%-")),
			seasonDescription = utils.seasonToDescription(season),
			watchlist = watchlist,
		}
	)
end





function M.postAdd(aRequest, aResponse)
	-- Only POST should reach here
	assert(aRequest:method() == "POST")

	local body = aRequest:readAll()
	local form = aRequest.parseFormUrlEncoded(body)
	if not(form) then
		return aResponse:sendError(400, "Failed to parse request body")
	end

	local aId = tonumber(form.aId)
	if not(aId) then
		return aResponse:sendError(400, "Missing or invalid aId parameter")
	end
	local watchlistSeason = form.watchlistSeason
	if not(watchlistSeason) then
		return aResponse:sendError(400, "Missing or invalid watchlistSeason parameter")
	end

	-- Add to the DB:
	local isOK, err = pcall(function()
		db.addToWatchlist(aId, watchlistSeason)
	end)
	if not(isOK) then
		return aResponse:sendError(500, "Database error: " .. tostring(err))
	end

	return aResponse:sendRedirect("/watchlist/" .. watchlistSeason)
end





return M
