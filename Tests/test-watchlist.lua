-- Tests/test-watchlist.lua

--[[
Implements the test for the watchlist functionality.
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;./?.lua;Tests/?.lua" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true

require("httpClient").noCopas()  -- Disable Copas in the underlying httpClient
local watchlistHandler = require("Handlers.watchlist")
local utils = require("utils")
local db = require("db")





local watchlistItem = db.watchlistItem(52)
print("Watchlist item 52:")
print(utils.serializeSimpleTable(watchlistItem))


local watchlist, seasonAnime = watchlistHandler.seasonData("2026-2")
-- The returned tables are not simple, they contain loops, so we need to manually massage them before printing:
print("Watchlist:")
for idx, w in ipairs(watchlist) do
	if (type(w.dayOfWeek) ~= "number") then
		print("DayOfWeek not a number")
	end
	local anime = w.anime
	w.anime = tostring(anime)
	print("-- " .. tostring(idx))
	print(utils.serializeSimpleTable(w))
	w.anime = anime
end
print("\n\n\n")
print("seasonAnime:")
for idx, a in ipairs(seasonAnime) do
	local watchlist = a.watchlist
	a.watchlist = tostring(watchlist)
	print("-- " .. tostring(idx))
	print(utils.serializeSimpleTable(a))
	a.watchlist = watchlist
end
