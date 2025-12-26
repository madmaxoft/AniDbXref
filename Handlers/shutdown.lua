-- Handlers/shutdown.lua

--[[
Implements the handler for the /shutdown HTTP endpoint
--]]




local copas = require("copas")





return function()
	copas.removeserver(copas.mainServer)
	copas.exit()
end
