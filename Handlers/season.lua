-- Handlers/season.lua

--[[
Implements the HTTP endpoint handler for displaying per-season lists of anime.
--]]





local utils = require("utils")
local db = require("db")





return function(aRequest, aResponse)
	local season = aRequest:pathAndQuery():match("/season/(.+)")
	if not(season) then
		season = utils.currentSeason()
	end
	local seasonDescription = utils.seasonToDescription(season)
	if not(seasonDescription) then
		return aResponse:sendError(404, "Invalid season specified")
	end
	return aResponse:sendTemplate("season",
		{
			season = season,
			seasonYear = tonumber(season:match("(%d+)%-")),
			seasonDescription = seasonDescription,
			anime = db.animeInSeason(season),
		}
	)
end
