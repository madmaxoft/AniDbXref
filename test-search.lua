-- test-search.lua

--[[ Tests the DB title search.
Runs without coroutines for easier debugging.
--]]





local query = "hajimete no gal"

local db = require("db")

local results = db.searchAnimeTitles(query)
print("Found " .. results.n .. " items:")
for _, item in ipairs(results) do
	print("  id = " .. item.aId .. ":")
	print("    enTitle = " .. tostring(item.details.enTitle))
	print("    jpTitle = " .. tostring(item.details.jptitle))
	print("    xjpTitle = " .. tostring(item.details.xjpTitle))
	print("    areTitlesEqual = " .. tostring(item.areTitlesEqual))
end
print("Done.")