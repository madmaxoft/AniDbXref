-- Handlers/watchlist.lua

--[[
Implements the HTTP endpoints for displaying and editing the watchlist, present and past
--]]





local utils = require("utils")
local db = require("db")
local liveChartSchedule = require("liveChartSchedule")
local log = require("logger").log
local copas = require("copas")
local wup = require("watchUrlProviders")





local M = {}

--- Dict-table of season -> timestamp for all season schedules that have been downloaded
-- Used to avoid re-downloading too soon
local gDownloadedSchedules = {}





--- Adds the local-time information to the specified schedule, based on the specified week start
-- The schedule may be unassigned, in which case the call is ignored
local function localizeSchedule(aSchedule, aWeekStartTimestampUtc)
	if not(aSchedule) then
		return
	end
	assert(type(aSchedule) == "table")
	if not(aSchedule.utcSecondsSinceWeekStart) then
		aSchedule.dayOfWeek = 8  -- No schedule -> Older column
		return
	end
	assert(type(aSchedule.utcSecondsSinceWeekStart) == "number")
	assert(type(aWeekStartTimestampUtc) == "number")

	local itemUtcTimestamp = aWeekStartTimestampUtc + aSchedule.utcSecondsSinceWeekStart
	local localDate = os.date("*t", itemUtcTimestamp)
	aSchedule.dayOfWeek = ((localDate.wday + 5) % 7) + 1
	aSchedule.timeStr = string.format("%02d:%02d", localDate.hour, localDate.min)
end





local function downloadScheduleInformationInBackground(aSeason)
	assert(type(aSeason) == "string")

	local lastDownloaded = gDownloadedSchedules[aSeason] or 0
	if (lastDownloaded < os.time() - 24 * 60 * 60) then
		log("watchlist", "Downloading schedule for season %s", aSeason)
		gDownloadedSchedules[aSeason] = os.time()
		copas.addthread(function()
			copas.pause(0)  -- Yield to other threads first, so that the current request can finish processing
			local seasonBounds = utils.seasonToYmdBounds(aSeason)
			local schedule, msg = liveChartSchedule.queryDate(utils.ymdAddOffset(seasonBounds.startDateYmd, 45))
			if not(schedule) then
				gDownloadedSchedules[aSeason] = nil  -- Re-download on next request
				log("watchlist", "Failed to download schedule for season %s: %s", aSeason, tostring(msg))
				return
			end
			log("watchlist", "Downloaded and stored schedule for season %s", aSeason)
		end)
	end
end





--- Returns the watchlist and season-anime tables for the specified season
-- Returns nil and error message on failure
function M.seasonData(aSeason)
	assert(type(aSeason) == "string")

	-- Process the season into useful information:
	local weekStartTimeStampUtc
	if (aSeason == utils.currentSeason()) then
		weekStartTimeStampUtc = utils.weekStartUtcFromLocalTimestamp(os.time())
	else
		local seasonBounds = utils.seasonToYmdBounds(aSeason)
		local dayTimeStamp = utils.ymdToTimestamp(utils.ymdAddOffset(seasonBounds.startDateYmd, 45))
		weekStartTimeStampUtc = utils.weekStartUtcFromLocalTimestamp(dayTimeStamp)
	end
	local seasonDescription = utils.seasonToDescription(aSeason)
	if not(seasonDescription) then
		return nil, "Invalid season specified"
	end

	-- Preprocess the anime and the watchlist:
	local seasonAnime = db.animeInSeason(aSeason)
	local watchlist = db.watchlistInSeason(aSeason)
	local watchlistById = {}
	local limitWatchUrlQueryTimestamp = os.time() - 7 * 24 * 60 * 60  -- Update links every 7 days
	for _, w in ipairs(watchlist) do
		if (w.aId) then
			watchlistById[w.aId] = w
			if ((w.lastWatchUrlQueryTimestamp or 0) < limitWatchUrlQueryTimestamp) then
				wup.enqueueQuery(w.aId)
			end
		end
		localizeSchedule(w, weekStartTimeStampUtc)
	end
	for _, a in ipairs(seasonAnime) do
		a.watchlist = watchlistById[a.aId]
		if (a.watchlist) then
			a.watchlist.anime = a
			a.watchlist.schedule = a.schedule
		end
		localizeSchedule(a.schedule, weekStartTimeStampUtc)
		if (a.watchlist and a.schedule) then
			a.watchlist.dayOfWeek = a.schedule.dayOfWeek  -- Overwrite any stored dayOfWeek with the schedule
		end
		-- Synthesize dayOfWeek from the start date if not present in the schedule:
		a.dayOfWeek = (a.schedule or {}).dayOfWeek or utils.ymdDayOfWeek(a.startDate)
	end

	return watchlist, seasonAnime
end





function M.get(aRequest, aResponse)
	-- Parse the season from the URL, if present:
	local season = aRequest:pathAndQuery():match("/watchlist/(.+)")
	if not(season) then
		season = utils.currentSeason()
	end
	downloadScheduleInformationInBackground(season)  -- for the next request to this endpoint

	local watchlist, seasonAnime = M.seasonData(season)
	if not(watchlist) then
		return aResponse:sendError(404, tostring(seasonAnime))
	end

	return aResponse:sendTemplate("watchlist",
		{
			season = season,
			seasonAnime = seasonAnime,
			seasonYear = tonumber(season:match("(%d+)%-")),
			seasonDescription = utils.seasonToDescription(season),
			watchlist = watchlist,
		}
	)
end





function M.getAddSearch(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	-- Only GET should reach here
	assert(aRequest:method() == "GET")

	local formData, msg = aRequest:formData()
	if not(formData) then
		return aResponse:sendError(400, "Failed to parse request body: " .. tostring(msg))
	end
	local query = formData.query
	if not(query) then
		return aResponse:sendError(400, "Missing query parameter")
	end
	local watchlistSeason = formData.watchlistseason
	if not(watchlistSeason) then
		return aResponse:sendError(400, "Missing watchlistseason parameter")
	end

	-- Search for the candidates:
	local candidates = db.searchAnimeTitles(query)

	-- If there are no candidates, report failure:
	if (candidates.n == 0) then
		return aResponse:sendMessage("No candidates found")
	end

	-- If there's only one candidate, add it:
	if (candidates.n == 1) then
		local isOK, err = db.addToWatchlist(candidates[1].aId, watchlistSeason, nil)
		if not(isOK) then
			return aResponse:sendError(500, "Database error: " .. tostring(err))
		end
		return aResponse:sendRedirect("/watchlist/" .. watchlistSeason)
	end

	-- Multiple candidates, let the user pick:
	return aResponse:sendTemplate("watchlistAddCandidates",
		{
			candidates = candidates,
			season = watchlistSeason,
			seasonYear = tonumber(watchlistSeason:match("(%d+)%-")),
			seasonDescription = utils.seasonToDescription(watchlistSeason),
		}
	)
end





function M.getEdit(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	local _, query = aRequest:parsedPathAndQuery()
	local itemId = tonumber(query.itemid)
	if not(itemId) then
		return aResponse:sendError(400, "Missing itemid parameter")
	end

	-- Query the DB:
	local watchlistItem, msg = db.watchlistItem(itemId)
	if not(watchlistItem) then
		log("watchlistEdit", "Failed to load wachlist item %d from DB: %s", itemId, tostring(msg))
		return aResponse:sendError(400, "Failed to load item from DB")
	end
	if (watchlistItem.aId) then
		watchlistItem.anime = db.getAnimeDetails(watchlistItem.aId)
	end

	-- Convert utcSecondsSinceWeekStart into dayOfWeek and timeStr:
	local weekStartTimeStampUtc
	if (watchlistItem.watchlistSeason == utils.currentSeason()) then
		weekStartTimeStampUtc = utils.weekStartUtcFromLocalTimestamp(os.time())
	else
		local seasonBounds = utils.seasonToYmdBounds(watchlistItem.watchlistSeason)
		local dayTimeStamp = utils.ymdToTimestamp(utils.ymdAddOffset(seasonBounds.startDateYmd, 45))
		weekStartTimeStampUtc = utils.weekStartUtcFromLocalTimestamp(dayTimeStamp)
	end
	localizeSchedule(watchlistItem, weekStartTimeStampUtc)

	local season = watchlistItem.watchlistSeason
	return aResponse:sendTemplate("watchlistEditor",
		{
			watchlistItem = watchlistItem,
			season = season,
			seasonYear = tonumber(season:match("(%d+)%-")),
			seasonDescription = utils.seasonToDescription(season),
		}
	)
end





function M.postAdd(aRequest, aResponse)
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
		return aResponse:sendError(400, "Missing or invalid aId parameter")
	end
	local watchlistSeason = formData.watchlistseason
	if not(watchlistSeason) then
		return aResponse:sendError(400, "Missing or invalid watchlistSeason parameter")
	end
	local dayOfWeek = tonumber(formData.dayofweek)
	if not(dayOfWeek) then
		return aResponse:sendError(400, "Missing or invalid dayofweek parameter")
	end
	local timeStr = formData.timestr
	if (not(timeStr) or (timeStr == "")) then
		timeStr = "0:00"
	end

	-- Add to the DB:
	local numSeconds, msg = utils.dayOfWeekAndTimeStrToSecondsSinceWeekStart(dayOfWeek, timeStr)
	if not(numSeconds) then
		log("watchlist", "Failed to convert schedule [%d, %s] to numSeconds: %s", dayOfWeek, timeStr, tostring(msg))
		return aResponse:sendError(400, "Failed to convert schedule to numSeconds")
	end
	local refTimestamp = utils.ymdToTimestamp(assert(utils.seasonToYmdBounds(watchlistSeason)).startDateYmd)
	local tzOffset = utils.timezoneOffset(refTimestamp)
	log("watchlist", "Adding aId %d into watchlist season %s, dow %d, timeStr %s", aId, watchlistSeason, dayOfWeek, timeStr)
	local isOK, err = db.addToWatchlist(aId, watchlistSeason, numSeconds - tzOffset)
	if not(isOK) then
		return aResponse:sendError(500, "Database error: " .. tostring(err))
	end

	return aResponse:sendRedirect("/watchlist/" .. watchlistSeason)
end





function M.postAddExtra(aRequest, aResponse)
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

	local watchlistSeason = formData.watchlistseason
	if not(watchlistSeason) then
		return aResponse:sendError(400, "Missing or invalid watchlistSeason parameter")
	end
	local dayOfWeek = formData.dayofweek
	if not(dayOfWeek and (tonumber(dayOfWeek) or (dayOfWeek == "older"))) then
		return aResponse:sendError(400, "Missing or invalid dayofweek parameter")
	end
	local timeStr = formData.timestr
	if (not(timeStr) or (timeStr == "")) then
		timeStr = "0:00"
	end
	local caption = formData.caption
	if not(caption) then
		return aResponse:sendError(400, "Missing caption parameter")
	end
	if (caption == "") then
		return aResponse:sendError(400, "Caption cannot be empty")
	end
	local url = formData.url or ""

	-- Add to the DB:
	local utcSecondsSinceWeekStart = nil
	if (tonumber(dayOfWeek)) then
		dayOfWeek = tonumber(dayOfWeek)
		local numSeconds, msg = utils.dayOfWeekAndTimeStrToSecondsSinceWeekStart(dayOfWeek, timeStr)
		if not(numSeconds) then
			log("watchlist", "Failed to convert schedule [%d, %s] to numSeconds: %s", dayOfWeek, timeStr, tostring(msg))
			return aResponse:sendError(400, "Failed to convert schedule to numSeconds")
		end
		local refTimestamp = utils.ymdToTimestamp(assert(utils.seasonToYmdBounds(watchlistSeason)).startDateYmd)
		local tzOffset = utils.timezoneOffset(refTimestamp)
		utcSecondsSinceWeekStart = numSeconds - tzOffset
	end
	log("watchlist", "Adding an extra item %s into watchlist season %s, dow %s, timeStr %s",
		caption, watchlistSeason, tostring(dayOfWeek), timeStr
	)
	local isOK, err = db.addExtraToWatchlist(caption, watchlistSeason, utcSecondsSinceWeekStart, url)
	if not(isOK) then
		return aResponse:sendError(500, "Database error: " .. tostring(err))
	end

	return aResponse:sendRedirect("/watchlist/" .. watchlistSeason)
end





function M.postAddOlder(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	-- Only POST should reach here
	assert(aRequest:method() == "POST")

	-- Parse the form data:
	local formData, msg = aRequest:formData()
	if not(formData) then
		return aResponse:sendError(400, "Failed to parse request body: " .. tostring(msg))
	end
	local watchlistSeason = formData.watchlistseason
	if not(watchlistSeason) then
		return aResponse:sendError(400, "Missing the watchlistseason parameter")
	end
	local ids = {}
	local n = 0
	for k, v in formData:pairs() do
		local aId = tonumber(string.match(tostring(k), "^chb_(%d+)$"))
		if (aId) then
			n = n + 1
			ids[n] = aId
		end
	end

	-- Add to DB:
	for _, aId in ipairs(ids) do
		local isOK, msg = db.addToWatchlist(aId, watchlistSeason, nil)
		if not(isOK) then
			log("watchlist", "Failed to add to watchlist season %s: anime %d", watchlistSeason, aId)
		end
	end

	return aResponse:sendRedirect("/watchlist/" .. watchlistSeason)
end





function M.postEdit(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	-- Extract and check form parameters:
	local formData, msg = aRequest:formData()
	if not(formData) then
		return aResponse:sendError(400, "Failed to parse request body: " .. tostring(msg))
	end
	local watchlistSeason = formData.watchlistseason or ""
	local itemId = tonumber(formData.itemid)
	if not(itemId) then
		return aResponse:sendError(400, "Missing itemid parameter")
	end
	local dayOfWeek = tonumber(formData.dayofweek)
	if not(dayOfWeek) then
		return aResponse:sendError(400, "Missing dayofweek parameter")
	end
	local timeStr = formData.timeStr
	if not(timeStr) then
		return aResponse:sendError(400, "Missing timestr parameter")
	end
	local numSeconds, msg = utils.dayOfWeekAndTimeStrToSecondsSinceWeekStart(dayOfWeek, timeStr)
	if not(numSeconds) then
		log("watchlist", "Failed to convert schedule [%d, %s] to numSeconds: %s", dayOfWeek, timeStr, tostring(msg))
		return aResponse:sendError(400, "Failed to convert schedule to numSeconds")
	end
	local refTimestamp = utils.ymdToTimestamp(assert(utils.seasonToYmdBounds(watchlistSeason)).startDateYmd)
	local tzOffset = utils.timezoneOffset(refTimestamp)
	local caption = formData.caption
	if (not(caption) or (caption == "")) then
		return aResponse:sendError(400, "Missing or empty caption")
	end
	local url = formData.url or ""

	-- Save to DB:
	log("watchlist", "Updating watchlist item %d (%s) in season %s, dow %d, timeStr %s", itemId, caption, watchlistSeason, dayOfWeek, timeStr)
	db.updateWatchlistItem(itemId, numSeconds - tzOffset, caption, url)

	aResponse:sendRedirect("/watchlist/" .. watchlistSeason)
end





function M.postRemove(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	local formData, msg = aRequest:formData()
	if not(formData) then
		return aResponse:sendError(400, "Failed to parse request body: " .. tostring(msg))
	end
	local itemId = tonumber(formData.itemid)
	if not(itemId) then
		return aResponse:sendError(400, "Missing itemid parameter")
	end
	local watchlistSeason = formData.watchlistseason

	local isOK, msg = db.removeWatchlistItem(itemId)
	if not(isOK) then
		return aResponse:sendError(400, "Failed to remove watchlist item: " .. tostring(msg))
	end

	return aResponse:sendRedirect("/watchlist/" .. (watchlistSeason or ""))
end





return M
