-- Test/test-updateDetails.lua

--[[
Tests updating AnimeDetails from an AniDb HTTP API
Consists of two individual tests - fetching and parsing.
The fetching can be disabled in order to test on locally cached data.
--]]

-- The anime's ID
-- local gAnimeIdToFetch = 1543  -- Samurai Champloo
-- local gAnimeIdToFetch = 7729  -- Steins;Gate
-- local gAnimeIdToFetch = 11167  -- Steins;Gate 0
-- local gAnimeIdToFetch = 17001  -- Fuufu Ijou
-- local gAnimeIdToFetch = 19548  -- Ganglion
local gAnimeIdToFetch = 12661  -- Boruto NNG, API returns an incomplete XML





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true

local db = require("db")
require("httpClient").noCopas()
local details = require("aniDbDetails")





--- Dumps the keys and values in the specified table, using the specified indent
local function dumpTable(aTable, aIndent)
	assert(type(aTable) == "table")
	aIndent = aIndent or ""

	for k, v in pairs(aTable) do
		if (type(v) == "table") then
			print(aIndent .. tostring(k) .. " = {")
			dumpTable(v, aIndent .. "\t")
			print(aIndent .. "}  -- " .. tostring(k))
		else
			print(aIndent .. tostring(k) .. " = " .. tostring(v))
		end
	end
end





-- Read the XML data, either from remote or from local cache:
local xml, msg = details.fetchXml(gAnimeIdToFetch, false)
if not(xml) then
	error("Failed to fetch XML: " .. tostring(msg))
end

-- Parse the details:
local parsedLom, msg = require("lxp.lom").parse(xml)
if not(parsedLom) then
	error("Failed to parse XML: " .. tostring(msg))
end
local parsedDetails = details.transformParsedIntoDetails(parsedLom)
assert(parsedDetails.aId == gAnimeIdToFetch)
--[[
print("Characters:")
dumpTable(parsedDetails.characters)
--]]

-- Store into the DB:
db.storeAnimeDetails(parsedDetails)
