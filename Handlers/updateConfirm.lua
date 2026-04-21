-- Handlers/updateConfirm.lua

--[[
Displays confirmation page for starting AniDB dump update
--]]





return function(aRequest, aResponse)
	local lastUpdate = require("db").getLastAniDbUpdate() or 0
	local now = os.time()
	local nextAllowed = lastUpdate + 24 * 3600

	return aResponse:sendTemplate("updateConfirm",
		{
			lastUpdate = os.date("%Y-%m-%d %H:%M:%S", lastUpdate),
			nextUpdate = os.date("%Y-%m-%d %H:%M:%S", nextAllowed),
			canUpdate = ((now - lastUpdate) >= 24 * 3600)
		}
	)
end
