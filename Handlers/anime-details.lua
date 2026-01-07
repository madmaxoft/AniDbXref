-- Handlers/anime-details.lua

--[[
Handles displaying the anime details page.
--]]

local db = require("db")
local httpResponse = require("httpResponse")
local requestQueue = require("requestQueue")





return function(aClient, aPath, aHeaders)
	local aId = tonumber(aPath:match("^/anime/(%d+)$"))
	if not(aId) then
		return httpResponse.sendError(aClient, "Invalid aId")
	end

	local details = db.getAnimeDetails(aId)
	if not(details.description) then
		requestQueue.add(aId)
	end

	httpResponse.sendTemplate(aClient, "animeDetails", { details = details, aId = aId })
end
