-- liveChartSchedule.lua

--[[
Implements the interface for querying the schedule from LiveChart.me
--]]





local httpClient = require("httpClient")
local url = require("socket.url")
local utils = require("utils")
local db = require("db")
local json = require("dkjson")
local log = require("logger").log

local strmatch = string.match





--- The API returned from this module
local liveChartSchedule = {}





--- Sends the specified GraphQL query (Lua table representing the JSON) to livechart.me.
-- Returns the response, parsed into a Lua table
-- Returns nil and error message on failure
local function sendLiveChartGraphQL(aQuery)
	assert(type(aQuery) == "table")

	local status, headers, body = httpClient.request({
		method = "POST",
		url = "https://www.livechart.me/graphql",
		headers =
		{
			["content-type"] = "application/json",
			["accept"] = "application/json",
		},
		body = json.encode(aQuery),
	})
	if not(status) then
		return nil, "Failed to send GraphQL request: " .. tostring(headers)
	end
	if (
		(type(status) ~= "number") or
		((status <= 199) or (status >= 300))
	) then
		return nil, "Bad http status: " .. tostring(status) .. " / " .. tostring(headers)
	end
	if (type(body) ~= "string") then
		return nil, "Body not a string: " .. type(body)
	end
	local tbl, msg = json.decode(body)
	if not(tbl) then
		return nil, "Body not a JSON: " .. tostring(msg)
	end
	return tbl
end





--- Converts the DayOfWeek and TimeStr into the number of seconds since the start of Monday
-- This is the number that is actually stored in the DB to support changing timezones
local function secondsSinceWeekStart(aDayOfWeek, aTimeStr)
	assert(type(aDayOfWeek) == "number")
	assert(type(aTimeStr) == "string")

	local hh, mm, ss = aTimeStr:match("(%d%d):(%d%d):(%d%d)")
	if not(hh and mm and ss) then
		return nil, "Failed to extract hours and minutes"
	end
	hh = tonumber(hh)
	mm = tonumber(mm)
	ss = tonumber(ss)
	assert(hh and mm and ss)  -- Both are digits from the string matching, so they should have parsed
	return (aDayOfWeek - 1) * 24 * 60 * 60 + hh * 60 * 60 + mm * 60 + ss
end





--- Returns the LiveChart.me schedule for the specified YMD date ("2024-01-23" etc.)
-- Returns the response parsed into a schedule table, with IDs mapped from LiveChart to AniDB
-- Returns nil and error message on failure
-- We cover +1 day in each direction in order to be safe even against timezone shifts
-- Items that don't have an AniDB ID are silently dropped from the response.
-- Stores the resulting schedule into the DB
function liveChartSchedule.queryDate(aDateYmd)
	assert(type(aDateYmd) == "string")
	assert(aDateYmd:match("%d%d%d%d%-%d%d%-%d%d"))

	local resp, msg = sendLiveChartGraphQL({
		operationName = "Timetable",
		variables =
		{
			date = utils.ymdAddOffset(aDateYmd, -1),
			timeZone = "Etc/UTC",
			dayCount = 3,  -- Doesn't seem to matter, we always get 7 days, or empty response if too large
			titlePreference = "ENGLISH",
		},
		query = [[
			query Timetable(
				$date: ISO8601Date,
				$timeZone: TimeZoneName,
				$dayCount: Int,
				$titlePreference: TitleLanguage
			) {
				timetable(
					date: $date,
					timeZone: $timeZone,
					dayCount: $dayCount,
					titlePreference: $titlePreference
				) {
					days {
						date
						timeslots {
							time
							episodes {
								number
								airdate
								anime {
									databaseId
									anidbUrl
								}
							}
						}
					}
				}
			}
		]]
	})
	if not(resp) then
		return nil, "Failed to query schedule: " .. tostring(msg)
	end

	-- TODO: Handle pagination, if we ever get any
	-- TODO: Feed the ID mappings to a general ID map, pull any possible missing candidates from there

	-- Process the response into the resulting schedule array:
	local days = ((resp.data or {}).timetable or {}).days or {}
	local res = {}
	local n = 0
	for _, day in ipairs(days) do
		local dayOfWeek = utils.ymdDayOfWeek(day.date)
		for _, timeslot in ipairs(day.timeslots or {}) do
			for _, episode in ipairs(timeslot.episodes or {}) do
				local aniDbUrl = (episode.anime or {}).anidbUrl
				if (aniDbUrl) then
					local idStr = strmatch(aniDbUrl, "https?://anidb.net/a(%d+)")
					if (idStr) then
						local id = tonumber(idStr)
						if (id) then
							local timeStr = strmatch(episode.airdate or "", "%d%d%d%d%-%d%d%-%d%dT(%d%d:%d%d:%d%d)")
							if (timeStr) then
								n = n + 1
								res[n] =
								{
									dateYmd = day.date,
									dayOfWeek = dayOfWeek,
									timeStr = timeStr,
									utcSecondsSinceWeekStart = secondsSinceWeekStart(dayOfWeek, timeStr),
									aId = id,
								}
							end
						end
					end
				end
			end
		end
	end
	res.n = n
	log("liveChartSchedule", "Downloaded schedule for %s, got %d items", aDateYmd, n)

	-- Store in the DB:
	local season = assert(utils.ymdToSeason(aDateYmd))
	db.storeWeeklySchedule(season, res)

	return res
end





return liveChartSchedule
