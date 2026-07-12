-- forceUpdateDetails.lua

--[[
Handles the request to force an update to details even when they are already in the DB
--]]

local requestQueue = require("requestQueue")
local wup = require("watchUrlProviders")
local utils = require("utils")
local lcs = require("liveChartSchedule")
local db = require("db")
local copas = require("copas")





return function(aRequest, aResponse)
	local aId = tonumber(aRequest:pathAndQuery():match("^/force%-update%-details/(%d+)$"))
	if not(aId) then
		return aResponse:sendError(400, "Invalid aId")
	end

	copas.addthread(
		function()
			requestQueue.addToFront(aId, true)
			wup.enqueueQuery(aId)

			-- If the start date is valid, query LiveChart.me for the schedule around that date, so that we get the ID map:
			local baseDetails = db.getAnimeDetails_base(aId)
			if (baseDetails) then
				local prevDay = utils.ymdAddOffset(baseDetails.startDate or "", -2)
				if (prevDay) then
					lcs.queryDate(prevDay)
				end
			end
		end
	)

	aResponse:sendRedirect("/anime/" .. tostring(aId))
end
