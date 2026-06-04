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
	copas.newthread(M.queryAndStore)
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





initialize()

return M
