-- voiceActorDetails.lua

--[[ Handler for the voice actor details page
--]]





local db = require("db")





return function(aRequest, aResponse)
	local vaId = tonumber(aRequest:pathAndQuery():match("^/voiceActor/(%d+)$"))
	if not(vaId) then
		return aResponse:sendError(400, "Invalid vaId")
	end

	local details = db.getVoiceActorDetails(vaId)
	aResponse:sendTemplate("voiceActorDetails", { details = details, vaId = vaId })
end
