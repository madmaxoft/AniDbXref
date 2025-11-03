-- test-updateDetails.lua

--[[ Tests updating AnimeDetails from an AniDb HTTP API
Consists of two individual tests - fetching and parsing.
The fetching can be disabled in order to test on locally cached data.
--]]

-- The anime's ID
local gAnimeIdToFetch = 7729  -- Steins;Gate
-- local gAnimeIdToFetch = 11167  -- Steins;Gate 0

local xmlFileName = string.format("%d.xml", gAnimeIdToFetch)


--- Should the data be fetched? If false, loads the data from a local file
local gShouldTestFetching = false





local db = require("db")
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
local xml
if (gShouldTestFetching) then
	xml = details.fetchXml(gAnimeIdToFetch)
	local f = assert(io.open(xmlFileName, "wb"))
	f:write(xml)
	f:close()
else
	local f = assert(io.open(xmlFileName, "rb"))
	xml = f:read("*all")
	f:close()
end

-- Parse the details:
local parsedLom = require("lxp.lom").parse(xml)
local parsedDetails = details.transformParsedIntoDetails(parsedLom)
assert(parsedDetails.aId == gAnimeIdToFetch)

-- Store into the DB:
db.storeAnimeDetails(parsedDetails)
