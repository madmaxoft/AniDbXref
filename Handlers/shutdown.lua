-- Handlers/shutdown.lua

--[[
Implements the handler for the /shutdown HTTP endpoint
--]]

local copas = require("copas")
local httpResponse = require("httpResponse")





return function(aClient)
	httpResponse.sendSimpleMessage(aClient, "Shutting down")
	copas.removeserver(copas.mainServer)
	copas.exit()
end
