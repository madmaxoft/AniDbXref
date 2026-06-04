-- WatchUrlProviders/miruro.lua

--[[
Implements the WatchUrl provider for miruro.tv
--]]





local httpClient = require("httpClient")
local url = require("socket.url")





--- Queries miruro.tv for the specified anime
local function miruroQuery(aId, aTitleEn, aTitleXjat)
	assert(type(aId) == "number")
	assert(type(aTitleEn or "") == "string")
	assert(type(aTitleXjat or "") == "string")

	if (
		not(aTitleEn or aTitleXjat) or  -- Both are nil
		((aTitleEn == "") and (aTitleXjat == ""))  -- Both are empty
	) then
		-- No idea what to search for, there's no title
		return ""
	end

	--[[
	-- NOTE: The search body doesn't provide the link data, it requires JS to actually build the results,
	and all APIs we've seen so far seem encrypted as well.
	In the future, we'll rather use the Anilist ID to build the URL ourselves:
	"https://www.miruro.tv/watch/{$anilistID}" seems to work just fine

	local url = "https://www.miruro.tv/search?query=" .. url.escape((aTitleEn or "") .. " " .. (aTitleXjat or ""))
	local status, headers, body = httpClient.request({method = "GET", url = url})
	if not(status) then
		return nil, "Failed to query miruro.tv: " .. tostring(headers)
	end
	if (status ~= 200) then
		return ""
	end

	-- DEBUG: Dump to file:
	local f = assert(io.open("miruro.search.html", "wb"))
	f:write(body)
	f:close()

	-- TODO: Parse
	--]]

	return ""
end





local wup = {...}
if not(wup[1]) then
	error("Provider must be load-called with WUP as first parameter")
end
wup[1].addProvider("miruro.tv", miruroQuery)
