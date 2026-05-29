-- Handlers/watchlist.lua

--[[
Implements the HTTP endpoints for displaying and editing the watchlist, present and past
--]]





local utils = require("utils")
local db = require("db")
local liveChartSchedule = require("liveChartSchedule")
local log = require("logger").log
local copas = require("copas")





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
	for _, w in ipairs(watchlist) do
		watchlistById[w.aId] = w
	end
	for _, a in ipairs(seasonAnime) do
		a.watchlist = watchlistById[a.aId]
		if (a.watchlist) then
			a.watchlist.anime = a
			a.watchlist.schedule = a.schedule
		end
		localizeSchedule(a.schedule, weekStartTimeStampUtc)
		if (a.watchlist and a.schedule) then
			a.watchlist.dayOfWeek = a.schedule.dayOfWeek  -- Overwrite any storen dayOfWeek with the schedule
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
	local isOK, err = pcall(function()
		db.addToWatchlist(aId, watchlistSeason, numSeconds - tzOffset)
	end)
	if not(isOK) then
		return aResponse:sendError(500, "Database error: " .. tostring(err))
	end

	return aResponse:sendRedirect("/watchlist/" .. watchlistSeason)
end





return M
