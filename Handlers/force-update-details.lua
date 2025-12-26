-- force-update-details.lua

--[[ Handles the request to force an update to details even when they are already in the DB
--]]





local httpResponse = require("httpResponse")
local requestQueue = require("requestQueue")





return function(aClient, aPath, aHeaders)
	local aId = tonumber(aPath:match("^/force%-update%-details/(%d+)$"))
	if not(aId) then
		return httpResponse.send(aClient, 400, "text/plain", "Invalid aId")
	end

	requestQueue.addToFront(aId)

	httpResponse.sendRedirect(aClient, "/anime/" .. tostring(aId))
end
