-- test-getVoiceActorDetails.lua

--[[ Tests getting voice actor details
Runs in a singlethreaded environment for easier debugging
--]]





--- The voice actor ID to query
local gVoiceActorId = 34626  -- Amamiya Sora





local db = require("db")

local charDetails = db.getVoiceActorDetails(gVoiceActorId)
for k, v in pairs(charDetails) do
	print(string.format("%s = %s", tostring(k), tostring(v)))
end
