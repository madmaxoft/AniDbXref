-- voiceActorDetails.lua

--[[ Handler for the voice actor details page
--]]





local db = require("db")
local httpResponse = require("httpResponse")
local requestQueue = require("requestQueue")





return function(aClient, aPath, aHeaders)
	local vaId = tonumber(aPath:match("^/voiceActor/(%d+)$"))
	if not(vaId) then
		return httpResponse.sendError(aClient, 400, "Invalid vaId")
	end

	local details = db.getVoiceActorDetails(vaId)
	local template = require("Templates").voiceActorDetails
	local html = template({ details = details, vaId = vaId })
	httpResponse.send(aClient, 200, nil, html)
end
