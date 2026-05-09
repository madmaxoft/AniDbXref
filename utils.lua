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

	return utils.ymdToSeason(os.date("!%Y-%m-%d", aTimestamp))
end





--- Converts a timestamp to its YMD representation
function utils.timestampToYmd(aTimestamp)
	assert(type(aTimestamp) == "number")

	return os.date("!%Y-%m-%d", aTimestamp)
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





--- Returns the "best" title from those specified, limited to the specified language
-- Returns nil if none found.
-- Prefers main title, then official title, then synonyms and last shorts
function utils.pickBestTitle(aTitlesFromDb, aLanguage)
	assert(type(aTitlesFromDb) == "table")
	assert(type(aLanguage) == "string")

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





return utils
