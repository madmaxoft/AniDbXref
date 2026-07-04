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
	local details, msg = db.getAnimeDetails(aId)
	timer("Get details from DB")
	details = details or {}
	if not(details.description) then
		requestQueue.add(aId)
	end

	aResponse:sendTemplate("animeDetails",
	{
		details = details,
		idMap = db.mapId("aId", aId) or {},
		watchlist = db.watchlistSeasonsForAnime(aId),
		aId = aId
	})
	timer("Send response")
end





function AD.postAddToWatchlist(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	-- Only POST should reach here
	assert(aRequest:method() == "POST")

	local formData, msg = aRequest:formData()
	if not(formData) then
		return aResponse:sendError(400, "Failed to parse request body: " .. tostring(msg))
	end
	local aId = tonumber(formData.aid)
	if not(aId) then
		return aResponse:sendError(400, "Missing or invalid aid parameter")
	end
	local watchlistSeason = formData.watchlistSeason
	if (not(watchlistSeason) or (watchlistSeason == "")) then
		return aResponse:sendError(400, "Missing or invalid watchlistseason parameter")
	end

	local isOK, msg = db.addToWatchlist(aId, watchlistSeason)
	if not(isOK) then
		log("animeDetails", "Failed to add watchlist item into DB: %s", tostring(msg))
		return aResponse:sendError(400, "Failed to add watchlist item into DB")
	end

	return aResponse:sendRedirect("/anime/" .. tostring(aId))
end





function AD.postSetSeen(aRequest, aResponse)
	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	local formData, msg = aRequest:formData()
	if not(formData) then
		return aResponse:sendError(400, "Failed to parse form data: " .. tostring(msg))
	end

	local aId = tonumber(formData["aid"])
	if not(aId) then
		return aResponse:sendError(400, "Bad or missing aId")
	end

	if (formData["isseen"]) then
		local seenDateYmd = formData["seendateymd"]
		local seenDate = parseYmd(seenDateYmd)
		if not(seenDate) then
			return aResponse:sendError(400, "Bad or missing seenDateYmd")
		end
		local isOK, msg = db.markAnimeSeen(aId, seenDateYmd)
		if not(isOK) then
			log("animeDetails", "Failed to mark anime as seen: %s", tostring(msg))
		end
	else
		local isOK, msg = db.markAnimeNotSeen(aId)
		if not(isOK) then
			log("animeDetails", "Failed to mark anime as not seen: %s", tostring(msg))
		end
	end

	aResponse:sendRedirect("/anime/" .. aId)
end





return AD
