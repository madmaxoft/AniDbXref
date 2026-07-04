-- WatchUrlProviders/miruro.lua

--[[
Implements the WatchUrl provider for miruro.tv
--]]





local db = require("db")





--- Queries miruro.tv for the specified anime
-- Returns the url, if found, or empty string if not found / unclear
-- Returns nil and error message on failure
local function miruroQuery(aId, aTitleEn, aTitleXjat)
	assert(type(aId) == "number")
	assert(type(aTitleEn or "") == "string")
	assert(type(aTitleXjat or "") == "string")

	-- Miruro uses anilist.co IDs in their URLs:
	local idMap = db.mapId("aId", aId)
	if not(idMap and idMap.aniListCoId) then
		return ""
	end
	return string.format("https://www.miruro.tv/watch/%d", idMap.aniListCoId)
end





local wup = {...}
if not(wup[1]) then
	error("Provider must be load-called with watchUrlProviders module as first parameter")
end
wup[1].addProvider("miruro.tv", miruroQuery)
