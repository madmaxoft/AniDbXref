-- watchUrlProviders.lua

--[[
Implements the entrypoints for WatchUrls providers and the mechanism to query them for URLs.

Individual providers are implemented in the WatchUrlProviders folder. The providers register themselves
using the watchUrlProviders.addProvider() API.
This module loads all the providers in the folder and executes them.
The providers expose a name and a function that queries the anime:
function query(aId, aTitleEn, aTitleXjat)
end
The function returns the URL as a string, an empty string if no match found, or nil and error message on
failure. Failures are silently dropped.
The function should run synchronously, blocking for network requests.

The main app calls watchUrlProviders.query(aId) or watchUrlProviders.enqueueQuery(aId) to query
all the providers (synchronously or asynchronously).

The providers may use helper functions from this module, such as useSingleTitleQuery().
--]]





local db = require("db")
local log = require("logger").log
local copas = require("copas")
local lfs = require("lfs")
local utils = require("utils")





--- The API returned from this module
local M = {}

--- The providers that can resolve anime into a WatchUrl
-- Dict-table of name -> function(aId) ... end
-- Items are added via M.addProvider()
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
					isOK, provider = pcall(provider, M)
					if not(isOK) then
						log("watchUrlProviders", "Failed to initialize provider %s: %s", fnam, tostring(provider))
					end
				end
			end
		end
	end
end





function M.addProvider(aName, aQueryFn)
	assert(type(aName) == "string")
	assert(type(aQueryFn) == "function")
	assert(not(gProviders[aName]))

	gProviders[aName] = aQueryFn
end





--- (Asynchronously) queries the specified anime using all providers
-- The resulting URLs are stored into the DB
function M.enqueueQuery(aId)
	assert(type(aId) == "number")

	log("watchUrlProviders", "Enqueueing query for %d", aId)
	copas.addnamedthread(
		string.format("watchUrlProviders.enqueueQuery(%d)", aId),
		function()
			copas.pause(0.1)  -- Let the parent thread run first
			return M.queryAndStore(aId)
		end
	)
end





--- (Synchronously) queries the specified anime using all providers
-- Returns an array of {providerName = ..., url = ...} items
function M.query(aId)
	assert(type(aId) == "number")

	-- Resolve the titles from the DB:
	local titles, msg = db.getAnimeDetails_titles(aId)
	if not(titles) then
		return nil, "Failed to query titles from the DB: " .. tostring(msg)
	end
	local enTitle = utils.pickBestTitle(titles, "en")
	local xjatTitle = utils.pickBestTitle(titles, "x-jat")

	local res = {}
	local n = 0
	for name, queryFn in pairs(gProviders) do
		local url = queryFn(aId, enTitle, xjatTitle)
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
function M.queryAndStore(aId)
	assert(type(aId) == "number")

	-- Query all providers:
	local urls, msg = M.query(aId)
	if not(urls) then
		log("watchUrlProviders", "Failed to query URLs for anime %d: %s", aId, tostring(msg))
		return nil, "Failed to query URLs for anime: " .. tostring(msg)
	end

	-- Store into the DB:
	db.storeWatchUrls(aId, urls)

	return urls
end





--- Uses a function that queries a single title to return the final URL for the two specified titles
-- Calls the function with each of the given titles, and decides the resulting URL based on
-- what the function returns.
-- The SingleTitleQuery function takes a single title as a parameter and returns the URL string (empty if
-- not found) and a bool specifying if the result was an exact match.
-- aProviderName is only for logging purposes
-- See the animegers and miruro WUPs for usage
function M.useSingleTitleQuery(aProviderName, aTitles, aSingleTitleQueryFn)
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

return M
