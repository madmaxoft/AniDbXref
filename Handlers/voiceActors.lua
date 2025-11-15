-- voiceActors.lua

--[[ Handles the voice actors list page
--]]





local db = require("db")
local httpResponse = require("httpResponse")





return function (aClient, aPath, aParams, aHeaders)
	local template = require("Templates").voiceActors
	local html = template({
		voiceActors = db.getVoiceActors(),
		hasAniDbData = db.hasBaseAniDbData()
	})
	httpResponse.send(aClient, 200, nil, html)
end
