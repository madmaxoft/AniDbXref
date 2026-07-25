-- Tests/test-search.lua

--[[
Tests the DB title search.
Runs without coroutines for easier debugging.
--]]





local queries = {
	"oshi no ko special",
	"steinsgate",
	"86",
	"girlfriend girlfriend",
	"atack on titan",
	"stein gate",
	"kimi no",
}





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

local perf = require("perf")
local utils = require("utils")

local timer = perf.newTimer("test-search")
local db = require("db")
timer("dbInit")

-- Print out the stats:
print("Stats:")
print(utils.serializeSimpleTable(db.titleSearch().mStats))

-- Measure the time for various queries:
local results = {}
for idx, query in ipairs(queries) do
	results[idx] = db.searchAnimeTitles(query)
	timer("search: " .. query)
end

-- Dump the results of the queries:
for idx, query in ipairs(queries) do
	print("\n\n\nQuery: " .. query)
	print("Found " .. results[idx].n .. " items:")
	local r = results[idx]
	for i = 1, r.n do
		print("  #" .. tostring(i))
		local item = r[i]
		print("    id = " .. item.aId .. ":")
		print("    score = " .. tostring(item.score))
		print("    enTitle = " .. tostring(item.details.enTitle))
		print("    jaTitle = " .. tostring(item.details.jatitle))
		print("    xjatTitle = " .. tostring(item.details.xjatTitle))
		print("    areTitlesEqual = " .. tostring(item.areTitlesEqual))
	end
	assert(r[r.n + 1] == nil)
end

print("All done.")
