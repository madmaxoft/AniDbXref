-- Handlers/api.lua

--[[
Implements the API http endpoints
--]]

local config = require("config")
local db = require("db")





--- The API module, returned from requiring this file
local api = {}





config.registerDefinitions({
	{
		identifier = "api.enable",
		description = "Enables the API endpoints exporting data in a machine-readable format.",
		valueType = "bool",
		default = false,
	}
})





function api.getSeen(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aRequest.parsedPathAndQuery)
	assert(type(aResponse) == "table")
	assert(aResponse.sendLuaTable)

	if not(config.get("api.enable")) then
		return aResponse:sendError(400, "API disabled")
	end

	local path, params = aRequest:parsedPathAndQuery()
	local from = (params or {}).from or "0"
	local seenIds = db.rawSeenIdsFrom(from)
	aResponse:sendLuaTable(seenIds)
end





function api.getWatchlist(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aRequest.parsedPathAndQuery)
	assert(type(aResponse) == "table")
	assert(aResponse.sendLuaTable)

	if not(config.get("api.enable")) then
		return aResponse:sendError(400, "API disabled")
	end

	local watchlist = db.rawWatchlist()
	aResponse:sendLuaTable(watchlist)
end





return api
