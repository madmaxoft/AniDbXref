-- utils.lua

--[[
Implements various utility functions used throughout the project
--]]





local utils = {}





--- Returns the season-string for the current season
function utils.currentSeason()
	return utils.timestampToSeason(os.time())
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
		return year .. " autumn"
	end
	return nil, "Invalid season specification: " .. aSeason
end





--- Converts the season-string ("2026-1") into {startDateYmd = "2025-12-01", endDateYmd = "2026-02-29"}
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
		-- Winter season, starts at previous year:
		startDateYmd = tostring(tonumber(year) - 1) .. "-12-01"
		endDateYmd = year .. "-02-29"
	elseif (idx == "2") then
		-- Spring season:
		startDateYmd = year .. "-03-01"
		endDateYmd = year .. "-05-31"
	elseif (idx == "3") then
		-- Summer season:
		startDateYmd = year .. "-06-01"
		endDateYmd = year .. "-08-31"
	elseif (idx == "4") then
		-- Autumn season:
		startDateYmd = year .. "-09-01"
		endDateYmd = year .. "-11-30"
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
		if (type(v) == "table") then
			res[n + 1] = aIndent .. tostring(k) .. " = {"
			res[n + 2] = utils.serializeSimpleTable(v, aIndent .. "\t")
			res[n + 3] = aIndent .. "}  -- " .. tostring(k)
			n = n + 3
		else
			n = n + 1
			res[n] = aIndent .. tostring(k) .. " = " .. tostring(v)
		end
	end
	return table.concat(res, "\n")
end





--- Converts the specified timestamp into the season to which it belongs
function utils.timestampToSeason(aTimestamp)
	assert(type(aTimestamp) == "number")

	return utils.ymdToSeason(os.date("!%Y-%m-%d", aTimestamp))
end





--- Returns the day-of-week index of the specified YMD date (1 = Mon, 7 = Sun)
-- Returns nil and error message on failure
function utils.ymdDayOfWeek(aDateYmd)
	assert(type(aDateYmd) == "string")

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
	local dt = os.date("*t", os.time({year = y, month = m, day = d}))
	if (dt.wday == 0) then
		return 7
	end
	return dt.wday
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

	-- Decide the season, breaking at the start of months 3, 6, 9, 12:
	m = tonumber(m)
	if (m < 3) then
		-- Winter season of this year
		return y .. "-1"
	elseif (m < 6) then
		-- Spring season of this year
		return y .. "-2"
	elseif (m < 9) then
		-- Summer season of this year
		return y .. "-3"
	elseif (m < 12) then
		-- Autumn season of this year
		return y .. "-4"
	elseif (m == 12) then
		-- Winter season of the next year
		return tostring(tonumber(y) + 1) .. "-1"
	end
	return nil, "Invalid month: " .. aDateYmd
end





return utils
