-- Tools/tool-updateDetailsForAllSeen.lua

--[[
Forces an update of details for all seen titles.
Since there may be more seen titles than the AniDB API capacity, sorts the seen titles by aid and starts from the lowest,
excluding those below gIgnoreBelowAid threshold (defined below) - this way the script can be updated and called
again the next day.
The details are queried using the standard aniDbDetails.updateDetailsInDb() function that uses the local cache.
--]]





--- Aid-s below this number will not be updated.
-- Use to call the script again the next day after AniDB API rate-limit reached
local gIgnoreBelowAid = 15695





local db = require("db")
local aniDbDetails = require("aniDbDetails")
local socket = require("socket")




local seen = db.getSeenAnime()
table.sort(seen, function (aSeen1, aSeen2)
	return (aSeen1.aId < aSeen2.aId)
end)
for _, s in ipairs(seen) do
	if (s.aId >= gIgnoreBelowAid) then
		local isSuccess, msg = aniDbDetails.updateDetailsInDb(s.aId, false)
		if not(isSuccess) then
			if (msg == "rate-limit") then
				print("Rate limit reached with aId " .. s.aId .. ". Terminating now; re-run the script after setting gIgnoreBelowAid to " .. s.aId)
				return
			end
		end
		socket.sleep(3)
	end
end
print("All items updated.")
