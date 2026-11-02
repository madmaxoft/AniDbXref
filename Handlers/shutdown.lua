-- Handlers/shutdown.lua

--[[
Implements the handler for the /shutdown HTTP endpoint
--]]

local copas = require("copas")
local utils = require("utils")
local httpClient = require("httpClient")





return function(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	aResponse:setConnectionClose()
	aResponse:sendSimpleMessage("Shutting down")

	-- Close all sockets currently opened in the server
	httpClient.closeAllConnections()
	copas.removeserver(copas.mainServerSocket)
	for sock, _ in pairs(copas.mainServerClients or {}) do
		if (sock.close) then
			sock:close()
		end
	end

	copas.exit()
end
