-- utils.lua

--[[
Implements various utility functions used throughout the project
--]]





local utils = {}





--- Returns the season-string for the current season
function utils.currentSeason()
	return utils.timestampToSeason(os.time())
end





--- Converts the (local) day of week and time string ("HH:MM") into the number of seconds since the start of week
-- Returns nil and error message on failure
function utils.dayOfWeekAndTimeStrToSecondsSinceWeekStart(aDayOfWeek, aTimeStr)
	assert(type(aDayOfWeek) == "number")
	assert(type(aTimeStr) == "string")

	local hh, mm = aTimeStr:match("(%d?%d):(%d%d)")
	hh = tonumber(hh)
	mm = tonumber(mm)
	if not(hh and mm) then
		return nil, "Failed to parse hours and minutes from timestamp"
	end

	local numSeconds = (aDayOfWeek - 1) * 24 * 60 * 60 + hh * 60 * 60 + mm * 60
	return numSeconds
end





--- Converts the local timestamp to UTC
function utils.localToUtcTimestamp(aLocalTimestamp)
	assert(type(aLocalTimestamp) == "number")

	return aLocalTimestamp + utils.timezoneOffset(aLocalTimestamp)
end





--- Returns an iterator over all seasons from aStartSeason up to aEndSeason (inclusive).
-- If either season is not specified, the current season is assumed.
-- Can generate a reversed sequence if aStartSeason is later than aEndSeason
-- This can be used to generate a list of all seasons from the specified start to end in a for loop:
-- for season in utils.seasonsBetween("2025-1", "2026-2") do print(season) end
function utils.seasonsBetween(aStartSeason, aEndSeason)
	assert(type(aStartSeason or "") == "string")
	assert(type(aEndSeason or "") == "string")

	local startYear, startQuarter = string.match(aStartSeason or utils.currentSeason(), "^(%d+)%-(%d+)$")
	assert(startYear ~= nil)
	assert(startQuarter ~= nil)
	startYear = tonumber(startYear)
	startQuarter = tonumber(startQuarter)
	assert((startQuarter >= 1) and (startQuarter <= 4))

	local endYear, endQuarter = string.match(aEndSeason or utils.currentSeason(), "^(%d+)%-(%d+)$")
	assert(endYear ~= nil)
	assert(endQuarter ~= nil)
	endYear = tonumber(endYear)
	endQuarter = tonumber(endQuarter)
	assert((endQuarter >= 1) and (endQuarter <= 4))

	local currentIndex = startYear * 4 + startQuarter - 1
	local endIndex = endYear * 4 + endQuarter - 1

	local step = 1
	if (currentIndex > endIndex) then
		step = -1
	end

	return function ()
		if (
			((step > 0) and (currentIndex > endIndex)) or
			((step < 0) and (currentIndex < endIndex))
		) then
			return nil
		end

		local year = math.floor(currentIndex / 4)
		local quarter = (currentIndex % 4) + 1
		currentIndex = currentIndex + step

		return string.format("%d-%d", year, quarter)
	end
end





--- Converts the season-string ("2026-1") into user-visible description ("2026 winter")
-- Returns nil and error message on failure
function utils.seasonToDescription(aSeason)
	assert(type(aSeason) == "string")

	local year, idx = aSeason:match("(%d+)%-(%d+)")
	if not(year and idx) then
		return nil, "Invalid season specification: " .. aSeason
	end

	if (idx == "1") then
		return year .. " winter"
	elseif (idx == "2") then
		return year .. " spring"
	elseif (idx == "3") then
		return year .. " summer"
	elseif (idx == "4") then
		return year .. " fall"
	end
	return nil, "Invalid season specification: " .. aSeason
end





--- Converts the season-string ("2026-1") into {startDateYmd = "2026-01-01", endDateYmd = "2026-03-31"}
-- Returns nil and error message on failure
function utils.seasonToYmdBounds(aSeason)
	assert(type(aSeason) == "string")

	-- Parse the season
	local year, idx = aSeason:match("(%d+)%-(%d)")
	if not(year and idx) then
		return nil, "Invalid season specification: " .. aSeason
	end

	local startDateYmd, endDateYmd
	if (idx == "1") then
		-- Winter season:
		startDateYmd = year .. "-01-01"
		endDateYmd = year .. "-03-31"
	elseif (idx == "2") then
		-- Spring season:
		startDateYmd = year .. "-04-01"
		endDateYmd = year .. "-06-30"
	elseif (idx == "3") then
		-- Summer season:
		startDateYmd = year .. "-07-01"
		endDateYmd = year .. "-09-30"
	elseif (idx == "4") then
		-- Autumn season:
		startDateYmd = year .. "-10-01"
		endDateYmd = year .. "-12-31"
	else
		return nil, "Invalid season specification: " .. aSeason
	end
	return {
		startDateYmd = startDateYmd,
		endDateYmd = endDateYmd,
	}
end





--- Recursively serializes the specified simple table into a string
function utils.serializeSimpleTable(aTable, aIndent)
	assert(type(aTable) == "table")
	aIndent = aIndent or ""

	local res = {}
	local n = 0
	for k, v in pairs(aTable) do
		local kstring
		if (type(k) == "number") then
			kstring = "[" .. tostring(k) .. "]"
		else
			kstring = string.format("[%q]", k)
		end

		if (type(v) == "table") then
			res[n + 1] = kstring .. " ="
			res[n + 2] = utils.serializeSimpleTable(v, aIndent .. "\t") .. ",  -- " .. kstring
			n = n + 2
		elseif (type(v) == "string") then
			n = n + 1
			res[n] = string.format("%s = %q,", kstring, v)
		else
			n = n + 1
			res[n] = kstring .. " = " .. tostring(v) .. ","
		end
	end
	return "{\n" .. aIndent .. table.concat(res, "\n" .. aIndent) .. "\n" .. aIndent:sub(2, -1) .. "}"
end





--- Converts the specified timestamp into the season to which it belongs
function utils.timestampToSeason(aTimestamp)
	assert(type(aTimestamp) == "number")

	return utils.ymdToSeason(utils.timestampToYmd(aTimestamp))
end





--- Converts a timestamp to its YMD representation
function utils.timestampToYmd(aTimestamp)
	assert(type(aTimestamp) == "number")

	return os.date("!%Y-%m-%d", aTimestamp)
end





--- Returns the timezone offset from UTC for the specified timestamp, taking DST into account
function utils.timezoneOffset(aTimestamp)
	local localDate = os.date("*t", aTimestamp)
	local utcDate = os.date("!*t", aTimestamp)

	-- Manually calculate the offset, os.timediff() would do timezone conversion, which we don't want.
	local offset = (localDate.hour - utcDate.hour) * 3600 + (localDate.min  - utcDate.min) * 60 + localDate.sec  - utcDate.sec

	-- Correct day wraparound:
	local dayDiff = localDate.yday - utcDate.yday
	if (dayDiff > 1) then  -- Wrap-around the new year
		dayDiff = -1
	elseif (dayDiff < -1) then
		dayDiff = 1
	end

	return offset + dayDiff * 86400
end





--- Converts the UTC timestamp to a local timestamp
function utils.utcToLocalTimestamp(aUtcTimestamp)
	assert(type(aUtcTimestamp) == "number")

	return aUtcTimestamp - utils.timezoneOffset(aUtcTimestamp)
end





--- Returns the YMD representation of a day that is the specified offset of days from the specified date
-- Eg. "2026-01-02" + (-3) = "2025-12-30"
-- Returns nil and error message on failure
function utils.ymdAddOffset(aDateYmd, aOffsetDays)
	assert(type(aDateYmd) == "string")
	assert(type(aOffsetDays) == "number")

	local timestamp, msg = utils.ymdToTimestamp(aDateYmd)
	if not(timestamp) then
		return nil, "Failed to parse date: " .. tostring(msg)
	end
	return utils.timestampToYmd(timestamp + aOffsetDays * 24 * 60 * 60)
end





--- Returns the day-of-week index of the specified YMD date (1 = Mon, 7 = Sun)
-- Returns nil and error message on failure
function utils.ymdDayOfWeek(aDateYmd)
	assert(type(aDateYmd) == "string")

	local timestamp, msg = utils.ymdToTimestamp(aDateYmd)
	if not(timestamp) then
		return nil, "Failed to convert date: " .. tostring(msg)
	end
	local dt = os.date("!*t", timestamp)
	if (dt.wday == 1) then
		return 7
	end
	return dt.wday - 1
end





--- Returns whether the specified YMD date string is within the specified season
function utils.ymdInSeason(aDateYmd, aSeason)
	local bounds = utils.seasonToYmdBounds(aSeason)
	return ((aDateYmd >= bounds.startDateYmd) and (aDateYmd <= bounds.endDateYmd))
end





--- Returns the season to which the specified date belongs
-- Returns nil and error message on failure
function utils.ymdToSeason(aDateYmd)
	assert(type(aDateYmd) == "string")

	-- Parse the date:
	local y, m, d = aDateYmd:match("(%d+)%-(%d+)%-(%d+)")
	if not(y and m and d) then
		return nil, "Invalid YMD date: " .. aDateYmd
	end

	-- Decide the season, breaking at the end of months 3, 6, 9, 12:
	m = tonumber(m)
	if (m <= 3) then
		-- Winter season of this year
		return y .. "-1"
	elseif (m <= 6) then
		-- Spring season of this year
		return y .. "-2"
	elseif (m <= 9) then
		-- Summer season of this year
		return y .. "-3"
	elseif (m <= 12) then
		-- Autumn season of this year
		return y .. "-4"
	end
	return nil, "Invalid month: " .. aDateYmd
end





--- Converts the string YMD date representation into the UTC timestamp of the day's start
-- Returns the timestamp (UTC)
-- Returns nil and error message on error
function utils.ymdToTimestamp(aDateYmd)
	assert(type(aDateYmd) == "string")

	-- Parse the date, use noon to work around DST edge cases:
	local y, m, d = aDateYmd:match("(%d+)%-(%d+)%-(%d+)")
	if not(y and m and d) then
		return nil, "Failed to parse YMD"
	end
	y = tonumber(y)
	m = tonumber(m)
	d = tonumber(d)
	if not(y and m and d) then
		return nil, "Non-numeric year, month or day"
	end
	local localTimeStamp = os.time({year = y, month = m, day = d, hour = 0})
	local offset = utils.timezoneOffset(localTimeStamp)
	return localTimeStamp + offset
end





--- Normalizes the title for comparison purposes
-- Lowercases, replaces all punctuation with spaces, collapses whitespace, trims whitespace from ends
function utils.normalizeTitle(aTitle)
	-- lowercase
	local s = aTitle:lower()
	-- replace any non-alphanumeric character with space
	s = s:gsub("[%W_]+", " ")
	-- collapse multiple spaces to one
	s = s:gsub("%s+", " ")
	-- trim spaces at start and end
	s = s:match("^%s*(.-)%s*$")
	return s
end





--- Returns true if the two titles are equal up to punctuation, compressed whitespace and trimmed space from ends
-- Returns nil if not (so that assigning it to a table member will not allocate the member for inequal titles)
function utils.areTitlesEqual(aTitle1, aTitle2)
	if (utils.normalizeTitle(aTitle1) == utils.normalizeTitle(aTitle2)) then
		return true
	else
		return nil
	end
end





--- Returns true if the title matches at least one of the multiple titles, up to normalization
-- Returns nil if not (so that assigning it to a table member will not allocate the member for inequal titles)
-- aMultiTitles is the assumed to be the structure returned by db.getAnimeDetails_titles
function utils.areMultiTitlesEqual(aTitle, aMultiTitles)
	assert(type(aTitle) == "string")
	assert(type(aMultiTitles) == "table")

	local normalizedTitle = utils.normalizeTitle(aTitle)
	for _, title in ipairs(aMultiTitles) do
		if (normalizedTitle == utils.normalizeTitle(title.title)) then
			return true
		end
	end
	return nil
end





--- Parses an ISO DateTime string ("2025-05-09T00:00:00.000000000Z") into timestamp
-- The fractional seconds are ignored and needn't be present
-- Returns nil and error message on failure
function utils.parseIsoDateTime(aStr)
	assert(type(aStr) == "string")

	local y, m, d, hh, mm, ss = string.match(aStr, "(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
	if not(y and m and d and hh and mm and ss) then
		return nil, "Bad ISO DateTime string"
	end
	y = tonumber(y)
	m = tonumber(m)
	d = tonumber(d)
	hh = tonumber(hh)
	mm = tonumber(mm)
	ss = tonumber(ss)
	assert(y and m and d and hh and mm and ss)
	local localTimeStamp = os.time({year = y, month = m, day = d, hour = hh, min = mm, sec = ss})
	local offset = utils.timezoneOffset(localTimeStamp)
	return localTimeStamp + offset
end





--- Returns the "best" title from those specified, limited to the specified language
-- Returns nil if none found.
-- Prefers main title, then official title, then synonyms and last shorts
function utils.pickBestTitle(aTitlesFromDb, aLanguage)
	assert(type(aTitlesFromDb or {}) == "table")
	assert(type(aLanguage) == "string")

	if not(aTitlesFromDb) then
		return nil
	end

	-- Pick the best title in the specified language:
	local titles = {}
	local enTitles = {}
	local anyTitles = {}
	for _, row in ipairs(aTitlesFromDb) do
		if (row.language == aLanguage) then
			titles[row.kind or ""] = row.title
		elseif (row.language == "en") then
			enTitles[row.kind or ""] = row.title
		end
		anyTitles[row.kind or ""] = row.title
	end
	local res = titles["main"] or titles["official"] or titles["syn"] or titles["short"] or titles[""]
	if (res) then
		return res
	end

	-- No title in this language found, use "en":
	res = enTitles["main"] or enTitles["official"] or enTitles["syn"] or enTitles["short"] or enTitles[""]
	if (res) then
		return res
	end

	-- No title in this language or "en", use any:
	return anyTitles["main"] or anyTitles["official"] or anyTitles["syn"] or anyTitles["short"] or anyTitles[""]
end





--- Returns the UTC timestamp of the start of the week containing the specified (local) timestamp
function utils.weekStartUtcFromLocalTimestamp(aLocalTimestamp)
	assert(type(aLocalTimestamp) == "number")

	local utcDate = os.date("*t", aLocalTimestamp)
	local dayOfWeek = ((utcDate.wday + 5) % 7) + 1
	local weekStartLocal =
		aLocalTimestamp
		- ((dayOfWeek - 1) * 86400)
		- (utcDate.hour * 3600)
		- (utcDate.min * 60)
		- utcDate.sec

	return utils.localToUtcTimestamp(weekStartLocal)
end





return utils
