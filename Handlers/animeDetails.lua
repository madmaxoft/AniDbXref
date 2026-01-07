-- Handlers/animeDetails.lua

--[[
Implements handlers for displaying the anime details page and handling the forms in it.
--]]

local db = require("db")
local httpResponse = require("httpResponse")
local requestQueue = require("requestQueue")
local httpRequest = require("httpRequest")
local multipart = require("multipart")
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





function AD.get(aClient, aPath, aRequestHeaders)
	local aId = tonumber(aPath:match("^/anime/(%d+)$"))
	if not(aId) then
		return httpResponse.sendError(aClient, 400, "Invalid aId")
	end

	local timer = perf.newTimer("animeDetails.get")
	local details = db.getAnimeDetails(aId)
	timer("Get details from DB")
	if not(details.description) then
		requestQueue.add(aId)
	end

	httpResponse.sendTemplate(aClient, "animeDetails", { details = details, aId = aId })
	timer("Send response")
end





function AD.postSetSeen(aClient, aPath, aRequestHeaders)
	local rawBody = httpRequest.readBody(aClient, aRequestHeaders)
	local form = multipart(rawBody, aRequestHeaders["content-type"])

	local aId = tonumber((form:get("aId") or {}).value)
	if not(aId) then
		return httpResponse.sendError(aClient, 400, "Bad or missing aId")
	end

	if ((form:get("isSeen") or {}).value) then
		local seenDateYmd = (form:get("seenDateYmd") or {}).value
		local seenDate = parseYmd(seenDateYmd)
		if not(seenDate) then
			return httpResponse.sendError(aClient, "Bad or missing seenDateYmd")
		end
		db.markAnimeSeen(aId, seenDate)
	else
		db.markAnimeNotSeen(aId)
	end

	httpResponse.sendRedirect(aClient, "/anime/" .. aId)
end





return AD
