-- voiceActorDetails.lua

--[[ Handler for the voice actor details page
--]]





local db = require("db")
local httpResponse = require("httpResponse")





return function(aClient, aPath, aHeaders)
	local vaId = tonumber(aPath:match("^/voiceActor/(%d+)$"))
	if not(vaId) then
		return httpResponse.sendError(aClient, 400, "Invalid vaId")
	end

	local details = db.getVoiceActorDetails(vaId)
	httpResponse.sendTemplate(aClient, "voiceActorDetails", { details = details, vaId = vaId })
end
