-- forceUpdateDetails.lua

--[[
Handles the request to force an update to details even when they are already in the DB
--]]

local requestQueue = require("requestQueue")




return function(aRequest, aResponse)
	local aId = tonumber(aRequest:pathAndQuery():match("^/force%-update%-details/(%d+)$"))
	if not(aId) then
		return aResponse:sendError(400, "Invalid aId")
	end

	requestQueue.addToFront(aId, true)

	aResponse:sendRedirect("/anime/" .. tostring(aId))
end
