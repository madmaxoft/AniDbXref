-- Handlers/animeDetails.lua

--[[
Implements handlers for displaying the anime details page and handling the forms in it.
--]]

local db = require("db")
local requestQueue = require("requestQueue")
local log = require("logger").log
local perf = require("perf")





local AD = {}




--- Parses an YYYY-MM-DD date into a timestamp
-- Returns nil if aDateStr is nil
-- Returns nil and error message on failure
-- Doesn't validate that the date is valid
local function parseYmd(aDateStr)
	if not(aDateStr) then
		return nil
	end
	assert(type(aDateStr) == "string")
	local y, m, d = string.match(aDateStr, "(%d+)%-(%d+)%-(%d+)")
	if not(y and m and d) then
		return nil, "Cannot parse the YMD string"
	end
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not(y and m and d) then
		return nil, "Cannot convert YMD to numbers"
	end
	return os.time({year = y, month = m, day = d})
end





function AD.get(aRequest, aResponse)
	local aId = tonumber(aRequest:pathAndQuery():match("^/anime/(%d+)$"))
	if not(aId) then
		return aResponse:sendError(400, "Invalid aId")
	end

	local timer = perf.newTimer("animeDetails.get")
	local details = db.getAnimeDetails(aId)
	timer("Get details from DB")
	if not(details.description) then
		requestQueue.add(aId)
	end

	aResponse:sendTemplate("animeDetails", { details = details, aId = aId })
	timer("Send response")
end





function AD.postSetSeen(aRequest, aResponse)
	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	local formData, msg = aRequest:formData()
	if not(formData) then
		return aResponse:sendError(400, "Failed to parse form data: " .. tostring(msg))
	end

	local aId = tonumber(formData["aId"])
	if not(aId) then
		return aResponse:sendError(400, "Bad or missing aId")
	end

	if ((form:get("isSeen") or {}).value) then
		local seenDateYmd = formData["seenDateYmd"]
		local seenDate = parseYmd(seenDateYmd)
		if not(seenDate) then
			return aResponse:sendError(400, "Bad or missing seenDateYmd")
		end
		db.markAnimeSeen(aId, seenDate)
	else
		db.markAnimeNotSeen(aId)
	end

	aResponse:sendRedirect("/anime/" .. aId)
end





return AD
