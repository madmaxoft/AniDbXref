-- Handlers/updateConfirm.lua

--[[
Displays confirmation page for starting AniDB dump update
--]]





return function(aClient, aRequestPath, aRequestHeaders)
	local lastUpdate = require("db").getLastAniDbUpdate() or 0
	local now = os.time()
	local nextAllowed = lastUpdate + 24 * 3600

	return require("httpResponse").sendTemplates(aClient, "updateConfirm",
		{
			lastUpdate = os.date("%Y-%m-%d %H:%M:%S", lastUpdate),
			nextUpdate = os.date("%Y-%m-%d %H:%M:%S", nextAllowed),
			canUpdate = ((now - lastUpdate) >= 24 * 3600)
		}
	)
end
