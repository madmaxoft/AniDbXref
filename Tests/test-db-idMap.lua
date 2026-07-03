-- Tests/test-db-idMap.lua

--[[
Implements the tests for IdMap within the DB.
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;./?.lua;Tests/?.lua" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true





local db = require("db")
local utils = require("utils")





--- Tests the basic roundtrip through db.storeIdMap() + db.mapId()
-- Stores a single entry into the DB, using real data for the test not to break the DB if run in production
local function testBasicRoundtrip()
	local aId = 7729  -- Steins;Gate
	local idMap = {aniListCoId = 9253}

	-- Store the mapping:
	local isOK, msg = db.storeIdMap(aId, idMap)
	assert(isOK)

	-- Retrieve the mapping by aId:
	local receivedMapping1 = db.mapId("aId", aId)
	assert(type(receivedMapping1) == "table")
	assert(receivedMapping1.aId == aId)
	assert(receivedMapping1.aniListCoId == idMap.aniListCoId)

	-- Retrieve the mapping by aniListCoId:
	local receivedMapping2 = db.mapId("aniListCoId", idMap.aniListCoId)
	assert(type(receivedMapping2) == "table")
	assert(receivedMapping2.aId == aId)
	assert(receivedMapping2.aniListCoId == idMap.aniListCoId)
end





testBasicRoundtrip()
