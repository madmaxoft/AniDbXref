-- Handlers/shutdown.lua

--[[
Implements the handler for the /shutdown HTTP endpoint
--]]

local copas = require("copas")





return function(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	aResponse:setConnectionClose()
	aResponse:sendSimpleMessage("Shutting down")
	copas.removeserver(copas.mainServerSocket)
	copas.exit()
end
