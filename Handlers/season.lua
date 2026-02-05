-- Handlers/season.lua

--[[
Implements the HTTP endpoint handler for displaying per-season lists of anime.
--]]





local httpResponse = require("httpResponse")
local utils = require("utils")
local db = require("db")





return function(aClient, aRequestPath, aRequestHeaders)
	local season = aRequestPath:match("/season/(.+)")
	if not(season) then
		season = utils.currentSeason()
	end
	local seasonDescription = utils.seasonToDescription(season)
	if not(seasonDescription) then
		return httpResponse.sendError(aClient, "404", "Invalid season specified")
	end
	return httpResponse.sendTemplate(aClient, "season",
		{
			season = season,
			seasonYear = tonumber(season:match("(%d+)%-")),
			seasonDescription = seasonDescription,
			anime = db.animeInSeason(season),
		}
	)
end
