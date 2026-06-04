-- WatchUrlProviders/animegers.lua

--[[
Implements the WatchUrl provider for animegers.com
--]]





local httpClient = require("httpClient")
local url = require("socket.url")
local utils = require("utils")





--- Parses the response body, returns the url suffix, if found, or empty string if not found / unclear
-- Also returns, as second value, a bool whether the match was an exact match
-- aTitle is the expected title, for checking the match exactness
-- NOTE: Doesn't return the whole URL, only the suffix ("/details/9253")
local function parseBody(aBody, aTitle)
	assert(type(aBody) == "string")
	assert(type(aTitle) == "string")

	local foundUrl = nil
	local foundExactMatchUrl = nil
	local numFound = 0
	string.gsub(aBody, "<h3%s+class=\"film%-name\">(.-)</h3>",
		function(aMatch)
			local url, name = string.match(aMatch, "<a%s+href=\"([^\"]+)\".->(.+)</a>")
			if (url and name) then
				if (url:match("/details/%d+")) then
					url = url:gsub("/details/", "/watch/") .. "?ep=1"
				end
				foundUrl = url
				numFound = numFound + 1
				if (utils.areTitlesEqual(name, aTitle)) then
					foundExactMatchUrl = url
				end
			end
		end
	)
	if (foundExactMatchUrl) then
		return foundExactMatchUrl, true
	end
	if (foundUrl and (numFound == 1)) then
		return foundUrl, false
	end
	return "", false
end





--- Returns the url for the specified title, and whether it was an exact match
-- Returns an empty string if not found
-- Returns nil and error message on failure
local function querySingleTitle(aTitle)
	assert(type(aTitle) == "string")
	local url = "https://animegers.com/search?keyword=" .. url.escape(aTitle)
	local status, headers, body = httpClient.request({method = "GET", url = url})
	if not(status) then
		return nil, "Failed to query animegers.com: " .. tostring(headers)
	end
	if (status ~= 200) then
		return "", false
	end

	--[[
	-- DEBUG: Dump to file
	local f = assert(io.open(string.format("animegers.search.%s.html", aTitle), "wb"))
	f:write(body)
	f:close()
	--]]

	local urlSuffix, isExactMatch = parseBody(body, aTitle)
	if (not(urlSuffix) or (urlSuffix == "")) then
		return "", false
	end
	return "https://animegers.com" .. urlSuffix, isExactMatch
end





--- Queries animegers.com for the specified anime
-- Returns the url, if found, or empty string if not found / unclear
-- Returns nil and error message on failure
local function animegersQuery(aId, aTitleEn, aTitleXjat)
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

	local url, isExactMatch = querySingleTitle(aTitleEn)
	if (url and (url ~= "") and isExactMatch) then
		-- Valid exact match
		return url
	end
	local url2, isExactMatch2 = querySingleTitle(aTitleXjat)
	if (url2 and (url2 ~= "") and isExactMatch2) then
		-- Valid exact match
		return url2
	end
	if (url and (url == url2) and (url ~= "")) then
		-- Both URLs are the same, strong match
		return url
	end
	-- Different URLs, do not use either:
	return ""
end





--- Runs a simple self-test: queries a fixed ID anime and tries to parse the response
local function selfTest()
	print("Performing a quick self-test")
	--[[
	-- Full test:
	local url = animegersQuery(7729, "Steins;Gate", "Steins;Gate")
	print("SteinsGate URL: " .. tostring(url)
	--]]

	-- Parser test (the response has already been downloaded to animegers.search.html file, read from there):
	local f = assert(io.open("animegers.search.html", "rb"))
	local contents = f:read("*all")
	f:close()
	local url = parseBody(contents, "Steins;Gate", "Steins;Gate")
	print("Steins;Gate URL: " .. tostring(url))
end





local wup = {...}
if not(wup[1]) then
	selfTest()
	error("Provider must be load-called with WUP as first parameter")
end
wup[1].addProvider("animegers.com", animegersQuery)
