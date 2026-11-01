-- WatchUrlProviders/miruro.lua

--[[
Implements the WatchUrl provider for miruro.cx
--]]





local httpClient = require("httpClient")
local url = require("socket.url")
local utils = require("utils")
local log = require("logger").log
local zlib = require("zlib")
local bit = bit32 or require("bit")
local json = require("dkjson")

local params = {...}
local wup = params[1]






--- Parses the response body, returns the url suffix, if found, or empty string if not found / unclear
-- Also returns, as second value, a bool whether the match was an exact match
-- aTitle is the expected title, for checking the match exactness
-- NOTE: Doesn't return the whole URL, only the suffix ("/watch/{slug}/{anything}")
local function parseBody(aBody, aTitle)
	assert(type(aBody) == "string")
	assert(type(aTitle) == "string")

	local lastCandidate = ""
	for href, cardHtml in aBody:gmatch('<a href="(/info/[^"]+)"[^>]*>(.-)</a>') do
		local title = cardHtml:match('<img[^>]-alt="([^"]*)"')
		if (title) then
			local candidate = href:match("^/info/([^/]+)")
			if (candidate) then
				if (utils.areTitlesEqual(title, aTitle)) then
					return "/watch/" .. candidate .. "/watch", true  -- Miruro doesn't care about what's after the second slash
				end
				lastCandidate = candidate
			end
		end
	end
	return "/watch/" .. lastCandidate .. "/watch", false
end





--- Returns the url for the specified title, and whether it was an exact match
-- Returns an empty string if not found
-- Returns nil and error message on failure
local function querySingleTitle(aTitle)
	assert(type(aTitle) == "string")

	local url = "https://miruro.cx/search?q=" .. url.escape(aTitle)
	log("watchUrlProviders/miruro", "HTTP request for title %s", aTitle)
	local status, headers, body = httpClient.get(url)
	if not(status and body) then
		return nil, "Failed to query miruro.cx: " .. tostring(headers)
	end
	if (status ~= 200) then
		log("watchUrlProviders/miruro", "HTTP request FAILED (%s) for title %s: %s", tostring(status), aTitle, tostring(body):sub(1, 200))
		return "", false
	end

	--[[
	-- DEBUG: Dump to file
	local f = assert(io.open(string.format("miruro.search.%s.raw", aTitle), "wb"))
	f:write(body)
	f:close()
	--]]

	local urlSuffix, isExactMatch = parseBody(body, aTitle)
	if (not(urlSuffix) or (urlSuffix == "")) then
		return "", false
	end
	return "https://miruro.cx" .. urlSuffix, isExactMatch
end





--- Queries miruro.cx for the specified anime
-- Returns the url, if found, or empty string if not found / unclear
-- Returns nil and error message on failure
local function miruroQuery(aId, aTitleEn, aTitleXjat)
	assert(type(aId) == "number")
	assert(type(aTitleEn or "") == "string")
	assert(type(aTitleXjat or "") == "string")

	return wup.useSingleTitleQuery("miruro", {aTitleEn, aTitleXjat}, querySingleTitle)
end





if not(wup) then
	-- DEBUG: Self-test when run as the main file:
	httpClient.noCopas()
	log("", "Miruro self-test: querying a single one")
	local foundUrl, msg = querySingleTitle("The Exiled Heavy Knight Knows How to Game the System")
	log("", "foundUrl = %s, msg = %s", foundUrl, msg or "nil")

	-- In normal usage, we want WUP valid
	error("Provider must be load-called with watchUrlProviders module as first parameter")
end
wup.addProvider("miruro.cx", miruroQuery)
