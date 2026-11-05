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






--- Parses the response body, adds the scored candidates to the specified candidate list
-- The list is extended, existing items get their score increased
-- aTitle is the expected title, for calculating the score
local function parseBody(aScoredCandidateList, aBody, aTitle)
	assert(type(aScoredCandidateList) == "table")
	assert(type(aBody) == "string")
	assert(type(aTitle) == "string")

	for href, cardHtml in aBody:gmatch('<a href="(/info/[^"]+)"[^>]*>(.-)</a>') do
		local title = cardHtml:match('<img[^>]-alt="([^"]*)"')
		if (title) then
			local candidate = href:match("^/info/([^/]+)")
			if (candidate) then
				wup.addScoredCandidateToList(
					aScoredCandidateList,
					{
						url = "https://miruro.cx/watch/" .. candidate .."/w",  -- Miruro doesn't care about what's after the second slash, as long as there's something
						title = title,
						score = wup.scoreTitle(aTitle, title)
					}
				)
			end
		end
	end
end





--- Adds the candidates for the specified title into the specified scored candidate list
-- The list is extended, existing items get their score increased
-- Returns true on success, nil and error message on failure
local function addSingleTitleQuery(aScoredCandidatesList, aTitle)
	assert(type(aScoredCandidatesList) == "table")
	assert(type(aTitle) == "string")

	local url = "https://miruro.cx/search?q=" .. url.escape(aTitle)
	log("watchUrlProviders/miruro", "HTTP request for title %s", aTitle)
	local status, headers, body = httpClient.get(url)
	if not(status and body) then
		return nil, "Failed to query miruro.cx: " .. tostring(headers)
	end
	if (status ~= 200) then
		log("watchUrlProviders/miruro", "HTTP request FAILED (%s) for title %s: %s", tostring(status), aTitle, tostring(body):sub(1, 200))
		return nil, "HTTP query to miruro.cx failed: " .. tostring(status)
	end

	--[[
	-- DEBUG: Dump to file
	local f = assert(io.open(string.format("miruro.search.%s.raw", aTitle), "wb"))
	f:write(body)
	f:close()
	--]]

	parseBody(aScoredCandidatesList, body, aTitle)
	return true
end





--- Queries miruro.cx for the specified anime
-- Returns the url, if found, or empty string if not found / unclear
local function miruroQuery(aId, aTitleArray)
	assert(type(aId) == "number")
	assert(type(aTitleArray or "") == "table")

	local scoredCandidates = {}
	for _, title in ipairs(aTitleArray) do
		addSingleTitleQuery(scoredCandidates, title)
	end
	local numCandidates = 0
	for _, _ in pairs(scoredCandidates) do
		numCandidates = numCandidates + 1
	end
	log("watchUrlProviders/miruro", "There are %d candidates", numCandidates)
	local bestCandidate = wup.pickBestScoredCandidate(scoredCandidates)
	if (not(bestCandidate) or (bestCandidate.score < 500)) then
		return ""
	end
	return bestCandidate.url
end





if not(wup) then
	error("Provider must be load-called with watchUrlProviders module as first parameter")
end
wup.addProvider("miruro.cx", miruroQuery)
