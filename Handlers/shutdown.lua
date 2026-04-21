-- Handlers/shutdown.lua

--[[
Implements the handler for the /shutdown HTTP endpoint
--]]

local copas = require("copas")





return function(aRequest, aResponse)
	aResponse:setConnectionClose()
	aResponse:sendSimpleMessage("Shutting down")
	copas.removeserver(copas.mainServerSocket)
	copas.exit()
end
