-- voiceActors.lua

--[[ Handles the voice actors list page
--]]





local db = require("db")
local httpResponse = require("httpResponse")





return function (aClient, aPath, aParams, aHeaders)
	return httpResponse.sendTemplate(aClient, "voiceActors",
		{
			voiceActors = db.getVoiceActors(),
			hasAniDbData = db.hasBaseAniDbData()
		}
	)
end
