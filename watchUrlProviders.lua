-- watchUrlProviders.lua

--[[
Implements the entrypoints for WatchUrls providers and the mechanism to query them for URLs.

Individual providers are implemented in the WatchUrlProviders folder. The providers register themselves
using the watchUrlProviders.addProvider() API.
This module loads all the providers in the folder and executes them.
The providers expose a name and a function that queries the anime:
function query(aId, aTitleArray)
end
The function returns the URL as a string, an empty string if no match found, or nil and error message on
failure. Failures are silently dropped.
The function should run synchronously, blocking for network requests.

The main app calls watchUrlProviders.query(aId) or watchUrlProviders.enqueueQuery(aId) to query
all the providers (synchronously or asynchronously).

The providers may use helper functions from this module, such as useSingleTitleQuery() or
the ScoredCandidateList implementation.

ScoredCandidateList is a special table that stores candidates with their score and possibly other information.
It is a dict-table or url -> {url = "...", score = ..., ...} items.
There are specific functions to manipulate the table: wup.addScoredCandidateToList(),
wup.pickBestScoredCandidate() and wup.combineScoredCandidateLists().
--]]





local db = require("db")
local log = require("logger").log
local copas = require("copas")
local lfs = require("lfs")
local utils = require("utils")





--- The API returned from this module
local wup = {}

--- The providers that can resolve anime into a WatchUrl
-- Dict-table of name -> function(aId) ... end
-- Items are added via wup.addProvider()
local gProviders = {}





--- Initializes the providers, by walking through all .lua files in WatchUrlProviders folder and loading them
local function initialize()
	for fnam in lfs.dir("WatchUrlProviders") do
		local fullName = "WatchUrlProviders/" .. fnam
		if (fnam:match("%.lua$") and (lfs.attributes(fullName, "mode") == "file")) then
			local f, msg = io.open(fullName, "rb")
			if not(f) then
				log("watchUrlProviders", "Failed to open provider file %s: %s", fnam, tostring(msg))
			else
				local provider, msg = load(f:read("*all"), fullName)
				f:close()
				if not(provider) then
					log("watchUrlProviders", "Failed to load provider %s: %s", fnam, tostring(msg))
				else
					local isOK
					isOK, provider = pcall(provider, wup)
					if not(isOK) then
						log("watchUrlProviders", "Failed to initialize provider %s: %s", fnam, tostring(provider))
					end
				end
			end
		end
	end
end





function wup.addProvider(aName, aQueryFn)
	assert(type(aName) == "string")
	assert(type(aQueryFn) == "function")
	assert(not(gProviders[aName]))

	gProviders[aName] = aQueryFn
end





--- Adds the specified candidate to the specified scored candidate list table
-- If the candidate is already present and aCandidate contains more information, that information is copied
-- to the present candidate. But existing information is NOT overwritten
function wup.addScoredCandidateToList(aScoredCandidateList, aCandidate)
	assert(type(aScoredCandidateList) == "table")
	assert(type(aCandidate) == "table")
	assert(type(aCandidate.url) == "string")
	assert(type(aCandidate.score) == "number")

	local candidate = aScoredCandidateList[aCandidate.url]
	if not(candidate) then
		aScoredCandidateList[aCandidate.url] = aCandidate
	else
		candidate.score = candidate.score + aCandidate.score
		for k, v in pairs(aCandidate) do
			candidate[k] = candidate[k] or v  -- Copy missing fields from aCandidate to candidate
		end
	end
end





--- Combines the scored candidate lists into a single list with compound score for each candidate
-- aScoredCandidatesList is an array-table of scored candidate lists, possibly containing nil entries.
-- Returns a single candidate array combined from the list.
-- Note that the input candidate lists are clobbered by this function (esp. the score stored in them, since
-- the items are effectively shared into the result)
function wup.combineScoredCandidateLists(aScoredCandidatesLists)
	-- Note that we use pairs(aScoredCandidatesList) because some of the arrays may be nil, which would break ipairs()
	local res = {}
	for _, list in pairs(aScoredCandidatesLists) do
		for _, candidate in ipairs(list) do
			wup.addScoredCandidateToList(res, candidate)
		end  -- for candidate - list[]
	end  -- for list - aScoredCandidatesList[]
	return res
end





--- (Asynchronously) queries the specified anime using all providers
-- The resulting URLs are stored into the DB
function wup.enqueueQuery(aId)
	assert(type(aId) == "number")

	log("watchUrlProviders", "Enqueueing query for %d", aId)
	copas.addnamedthread(
		string.format("watchUrlProviders.enqueueQuery(%d)", aId),
		function()
			copas.pause(0.1)  -- Let the parent thread run first
			return wup.queryAndStore(aId)
		end
	)
end





--- (Synchronously) queries the specified anime using all providers
-- Returns an array of {providerName = ..., url = ...} items
function wup.query(aId)
	assert(type(aId) == "number")

	-- Resolve the titles from the DB:
	local titlesFromDB, msg = db.getAnimeDetails_titles(aId)
	if not(titlesFromDB) then
		return nil, "Failed to query titles from the DB: " .. tostring(msg)
	end
	local titlesArr = {}
	local n = 0
	for _, title in ipairs(titlesFromDB) do
		if ((title.language == "en") or (title.language == "ja") or (title.language == "x-jat")) then
			n = n + 1
			titlesArr[n] = title.title
		end
	end

	local res = {}
	n = 0
	for name, queryFn in pairs(gProviders) do
		local url = queryFn(aId, titlesArr)
		if (url and (url ~= "")) then
			n = n + 1
			res[n] = {providerName = name, url = url}
		end
	end
	res.n = n
	return res
end





--- Queries the specified anime and stores the resulting urls into the DB
-- Returns the array of {provider = ..., url = ...} on success.
-- Returns nil and error message on failure.
function wup.queryAndStore(aId)
	assert(type(aId) == "number")

	-- Query all providers:
	local urls, msg = wup.query(aId)
	if not(urls) then
		log("watchUrlProviders", "Failed to query URLs for anime %d: %s", aId, tostring(msg))
		return nil, "Failed to query URLs for anime: " .. tostring(msg)
	end

	-- Store into the DB:
	db.storeWatchUrls(aId, urls)

	return urls
end





--- Picks the best candidate (max score) out of the scored candidates array
-- Returns nil if there are no candidates
function wup.pickBestScoredCandidate(aScoredCandidates)
	assert(type(aScoredCandidates) == "table")

	local bestCandidate = nil
	local bestScore = -1
	for _, candidate in pairs(aScoredCandidates) do
		if (candidate.score > bestScore) then
			bestCandidate = candidate
			bestScore = candidate.score
		end
	end
	return bestCandidate
end





local MAX_TITLE_SCORE = 1000

--- Returns the score of the aReceivedTitle as the representant of aWantedTitle
function wup.scoreTitle(aWantedTitle, aReceivedTitle)
	assert(type(aWantedTitle) == "string")
	assert(type(aReceivedTitle) == "string")

	if (utils.areTitlesEqual(aWantedTitle, aReceivedTitle)) then
		return MAX_TITLE_SCORE
	end

	-- Normalize titles:
	local wanted = string.lower(aWantedTitle):gsub("[%p%s]", "")
	local received = string.lower(aReceivedTitle):gsub("[%p%s]", "")

	if (wanted == received) then
		return MAX_TITLE_SCORE - 1
	end

	local wantedLen = #wanted
	local receivedLen = #received
	if (wantedLen == 0) or (receivedLen == 0) then
		return 0
	end

	-- Calculate Levenshtein distance:
	local prev = {}
	local curr = {}
	for i = 0, receivedLen do
		prev[i] = i
	end
	for i = 1, wantedLen do
		curr[0] = i
		for j = 1, receivedLen do
			local cost = (wanted:sub(i, i) == received:sub(j, j)) and 0 or 1

			curr[j] = math.min(
				curr[j - 1] + 1,
				prev[j] + 1,
				prev[j - 1] + cost
			)
		end
		prev, curr = curr, prev
	end
	local distance = prev[receivedLen]
	local maxLen = math.max(wantedLen, receivedLen)

	return MAX_TITLE_SCORE * (1 - distance / maxLen)
end





--- Uses a function that queries a single title to return the final URL for the two specified titles
-- Calls the function with each of the given titles, and decides the resulting URL based on
-- what the function returns.
-- The SingleTitleQuery function takes a single title as a parameter and returns the URL string (empty if
-- not found) and a bool specifying if the result was an exact match.
-- aProviderName is only for logging purposes
-- See the animegers and miruro WUPs for usage
function wup.useSingleTitleQuery(aProviderName, aTitles, aSingleTitleQueryFn)
	assert(type(aProviderName) == "string")
	assert(aProviderName ~= "")
	assert(type(aTitles) == "table")
	assert(type(aTitles[1] or "") == "string")

	local bestUrl = ""
	for _, title in ipairs(aTitles) do
		assert(type(title) == "string")
		if (title ~= "") then
			local url, isExactMatch = aSingleTitleQueryFn(title)
			if (url) then
				if ((url ~= "") and isExactMatch) then
					-- Valid exact match
					log("watchUrlProviders/" .. aProviderName, "Found an exact match for %s: %s", title, url)
					return url
				end
				if (bestUrl ~= "") then
					if (url ~= bestUrl) then
						-- Got different URLs
						log("watchUrlProviders/" .. aProviderName, "Found varying matches for %s, NOT using any of them", aTitles[1])
						return ""
					end
					-- Got the same URL twice, consider this a valid result
					log("watchUrlProviders/" .. aProviderName, "Found a multi-match for %s: %s", title, url)
					return bestUrl
				else
					bestUrl = url
				end
			end  -- if (url)
		end  -- if (title ~= "")
	end  -- for title: aTitles[]

	-- Didn't find anything
	log("watchUrlProviders/" .. aProviderName, "Found nothing for %s", aTitles[1])
	return ""
end





initialize()

return wup
