-- tool-queryWishlist.lua

--[[
Implements a simple query for the wishlist entry for a specified anime.
Used to debug the wishlist in a single-threaded app.
--]]




--- The anime to query
local animeId = 18854  -- Heavy Knight





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true

local db = require("db")




--- Prints the wishlist entry for the specified anime to the console
local function printEntry(aId)
	assert(type(aId) == "number")

	local entry, msg = db.wishlistEntry(aId)
	if not(entry) then
		if (entry == nil) then
			print(string.format("Failed to query wishlist entry for %d: %s", aId, tostring(msg)))
		else
			print(string.format("Anime %d doesn't have a wishlist entry", aId))
		end
		return
	end
	print(string.format("Wishlist entry for anime %d:", aId))
	print(string.format("addedOnYmd = %s", entry.addedOnYmd or "nil"))
	print(string.format("notes = %s", entry.notes or "nil"))
	print("")
end





printEntry(animeId)
printEntry(0)
