-- voiceActors.lua

--[[ Handles the voice actors list page
--]]





local db = require("db")





return function (aRequest, aResponse)
	return aResponse:sendTemplate("voiceActors",
		{
			voiceActors = db.getVoiceActors(),
			hasAniDbData = db.hasBaseAniDbData()
		}
	)
end
