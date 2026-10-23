-- WatchUrlProviders/miruro.lua

--[[
Implements the WatchUrl provider for miruro.tv
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






--- Decode an "encrypted" Miruro API response into a JSON string.
-- Returns the decoded API response
-- Returns nil and error message on failure
local function decodeMiruroResponse(aResponse)
	assert(type(aResponse) == "string")

	--- XOR the response with the repeating key:
	local key = "miruro/catalog"
	local numKeyBytes = #key
	local numByte = 0
	local xoredResponse = aResponse:gsub(".", function(aChar)
		numByte = numByte + 1
		local keyByte = string.byte(key, ((numByte - 1) % numKeyBytes) + 1)
		return string.char(bit.bxor(string.byte(aChar), keyByte))
	end)

	--- Decompress the XOR-decoded GZIP data:
	local inflate = zlib.inflate(31)
	local result, isEof = inflate(xoredResponse)
	if not(isEof) then
		return nil, "Incomplete Miruro GZIP response"
	end
	return result
end





--- Parses the response body, returns the url suffix, if found, or empty string if not found / unclear
-- Also returns, as second value, a bool whether the match was an exact match
-- aTitle is the expected title, for checking the match exactness
-- NOTE: Doesn't return the whole URL, only the suffix ("/watch/{slug}/{anything}")
local function parseBody(aBody, aTitle)
	assert(type(aBody) == "string")
	assert(type(aTitle) == "string")

	local parsed, msg = json.decode(aBody)
	if not(parsed) then
		log("watchUrlProviders/miruro", "Failed to decode JSON: %s", tostring(msg))
		return nil, false
	end
	for _, d in ipairs(parsed.data) do
		if (d.id and d.title) then
			for _, title in pairs(d.title) do
				if (utils.areTitlesEqual(title, aTitle)) then
					return "/watch/" .. d.id .. "/watch", true  -- Miruro doesn't care about what's after the second slash
				end
			end
		end
	end
	return "", false
end





--- Returns the url for the specified title, and whether it was an exact match
-- Returns an empty string if not found
-- Returns nil and error message on failure
local function querySingleTitle(aTitle)
	assert(type(aTitle) == "string")
	-- local url = "https://www.miruro.tv/search?query=" .. url.escape(aTitle)
	local url = "https://www.miruro.tv/api/v1/anime?limit=5&sort=-popularity&q=" .. url.escape(aTitle)
	log("watchUrlProviders/miruro", "HTTP request for title %s", aTitle)
	local status, headers, body = httpClient.request({method = "GET", url = url})
	if not(status and body) then
		return nil, "Failed to query www.miruro.tv: " .. tostring(headers)
	end
	if (status ~= 200) then
		return "", false
	end

	--[[
	-- DEBUG: Dump to file
	local f = assert(io.open(string.format("miruro.api.search.%s.raw", aTitle), "wb"))
	f:write(body)
	f:close()
	--]]

	body = decodeMiruroResponse(body)

	--[[
	-- DEBUG: Dump to file
	local f = assert(io.open(string.format("miruro.api.search.%s.decoded", aTitle), "wb"))
	f:write(body)
	f:close()
	--]]

	local urlSuffix, isExactMatch = parseBody(body, aTitle)
	if (not(urlSuffix) or (urlSuffix == "")) then
		return "", false
	end
	return "https://www.miruro.tv" .. urlSuffix, isExactMatch
end





--- Queries miruro.tv for the specified anime
-- Returns the url, if found, or empty string if not found / unclear
-- Returns nil and error message on failure
local function miruroQuery(aId, aTitleEn, aTitleXjat)
	assert(type(aId) == "number")
	assert(type(aTitleEn or "") == "string")
	assert(type(aTitleXjat or "") == "string")

	return wup.useSingleTitleQuery({aTitleEn, aTitleXjat}, querySingleTitle)
end





if not(wup) then
	-- DEBUG: Self-test when run as the main file:
	httpClient.noCopas()
	log("", "Miruro self-test: querying a single one")
	local foundUrl, msg = querySingleTitle("My Ribdiculous Reincarnation")
	log("", "foundUrl = %s, msg = %s", foundUrl, msg or "nil")

	-- In normal usage, we want WUP valid
	error("Provider must be load-called with watchUrlProviders module as first parameter")
end
wup.addProvider("miruro.tv", miruroQuery)
