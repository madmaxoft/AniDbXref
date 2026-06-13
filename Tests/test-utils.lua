-- Tests/test-utils.lua

--[[
Implements tests for the utils module.
--]]





local utils = require("utils")





local function assertEqual(aVal1, aVal2)
	if (aVal1 == aVal2) then
		return
	end

	print("Values are not equal:")
	print("  val1: " .. tostring(aVal1))
	print("  val2: " .. tostring(aVal2))
	error("Values are not equal")
end





local function test_dayOfWeekAndTimeStrToSecondsSinceWeekStart()
	assertEqual(utils.dayOfWeekAndTimeStrToSecondsSinceWeekStart(1, "0:00"), 0)
	assertEqual(utils.dayOfWeekAndTimeStrToSecondsSinceWeekStart(1, "1:23"), 1 * 60 * 60 + 23 * 60)
	assertEqual(utils.dayOfWeekAndTimeStrToSecondsSinceWeekStart(1, "16:54"), 16 * 60 * 60 + 54 * 60)
	assertEqual(utils.dayOfWeekAndTimeStrToSecondsSinceWeekStart(2, "00:00"), 24 * 60 * 60)
	assertEqual(utils.dayOfWeekAndTimeStrToSecondsSinceWeekStart(3, "16:54"), 2 * 24 * 60 * 60 + 16 * 60 * 60 + 54 * 60)
	assertEqual(utils.dayOfWeekAndTimeStrToSecondsSinceWeekStart(7, "00:00"), 6 * 24 * 60 * 60)
end





local function test_localToUtcTimestamp()
	assertEqual(os.date("!%c", utils.localToUtcTimestamp(0)),          os.date("%c", 0))
	assertEqual(os.date("!%c", utils.localToUtcTimestamp(1778284800)), os.date("%c", 1778284800))  -- 2026-05-09

	-- Test the roundtrip UTC -> local -> UTC
	assertEqual(utils.localToUtcTimestamp(utils.utcToLocalTimestamp(0)), 0)
	assertEqual(utils.localToUtcTimestamp(utils.utcToLocalTimestamp(1778284800)), 1778284800)
end





local function test_parseIsoDateTime()
	assertEqual(utils.parseIsoDateTime("1970-01-01T00:00:00"), 0)
	assertEqual(utils.parseIsoDateTime("1970-01-02T00:00:00"), 24 * 60 * 60)
	assertEqual(utils.parseIsoDateTime("1970-02-01T00:00:00"), 31 * 24 * 60 * 60)
	assertEqual(utils.parseIsoDateTime("1970-05-09T14:00:00"), 11109600)
	assertEqual(utils.parseIsoDateTime("2026-05-09T00:00:00"), 1778284800)
	assertEqual(utils.parseIsoDateTime("2026-05-09T12:34:56"), 1778330096)
end





local function test_seasonsBetween()
	local seasons = {}

	-- Check forward iteration:
	for season in utils.seasonsBetween("2025-1", "2026-2") do
		table.insert(seasons, season)
	end
	assertEqual(6, #seasons)
	assertEqual("2025-1", seasons[1])
	assertEqual("2025-2", seasons[2])
	assertEqual("2025-3", seasons[3])
	assertEqual("2025-4", seasons[4])
	assertEqual("2026-1", seasons[5])
	assertEqual("2026-2", seasons[6])

	-- Check reverse iteration:
	seasons = {}
	for season in utils.seasonsBetween("2026-2", "2025-1") do
		table.insert(seasons, season)
	end
	assertEqual(6, #seasons)
	assertEqual("2026-2", seasons[1])
	assertEqual("2026-1", seasons[2])
	assertEqual("2025-4", seasons[3])
	assertEqual("2025-3", seasons[4])
	assertEqual("2025-2", seasons[5])
	assertEqual("2025-1", seasons[6])

	-- Check single season:
	seasons = {}
	for season in utils.seasonsBetween("2025-3", "2025-3") do
		table.insert(seasons, season)
	end
	assertEqual(1, #seasons)
	assertEqual("2025-3", seasons[1])

	-- Check current season:
	local currentSeason = utils.currentSeason()
	seasons = {}
	for season in utils.seasonsBetween(nil, nil) do
		table.insert(seasons, season)
	end
	assertEqual(1, #seasons)
	assertEqual(currentSeason, seasons[1])
end





local function test_utcToLocalTimestamp()
	assertEqual(os.date("%c", utils.utcToLocalTimestamp(0)), os.date("!%c", 0))
	assertEqual(os.date("%c", utils.utcToLocalTimestamp(1778284800)), os.date("!%c", 1778284800))  -- 2026-05-09
end





local function test_ymdAddOffset()
	-- Basic:
	assertEqual(utils.ymdAddOffset("1970-01-01",  3), "1970-01-04")
	assertEqual(utils.ymdAddOffset("1970-01-06", -2), "1970-01-04")

	-- Across month boundary:
	assertEqual(utils.ymdAddOffset("1970-01-29",  4), "1970-02-02")
	assertEqual(utils.ymdAddOffset("1970-02-03", -7), "1970-01-27")

	-- Across year boundary:
	assertEqual(utils.ymdAddOffset("1970-12-29",  4), "1971-01-02")
	assertEqual(utils.ymdAddOffset("1971-01-02", -4), "1970-12-29")

	-- Across DST boundary:
	assertEqual(utils.ymdAddOffset("1970-03-03",  60), "1970-05-02")
	assertEqual(utils.ymdAddOffset("1970-05-02", -60), "1970-03-03")
end





local function test_ymdDayOfWeek()
	assertEqual(utils.ymdDayOfWeek("1970-01-01"), 4)
	assertEqual(utils.ymdDayOfWeek("1970-01-02"), 5)
	assertEqual(utils.ymdDayOfWeek("1970-02-01"), 7)
	assertEqual(utils.ymdDayOfWeek("2026-05-09"), 6)
end





local function test_ymdToTimestamp()
	assertEqual(utils.ymdToTimestamp("1970-01-01"),  0)
	assertEqual(utils.ymdToTimestamp("1970-01-02"), 24 * 60 * 60)
	assertEqual(utils.ymdToTimestamp("1970-02-01"), 31 * 24 * 60 * 60)
	assertEqual(utils.ymdToTimestamp("1970-05-09"), 11059200)
	assertEqual(utils.ymdToTimestamp("2026-05-09"), 1778284800)
end





local function test_weekStartFromLocalTimestamp()
	assertEqual(utils.weekStartUtcFromLocalTimestamp(utils.utcToLocalTimestamp(utils.ymdToTimestamp("2026-05-04"))), 1777852800)
	assertEqual(utils.weekStartUtcFromLocalTimestamp(utils.utcToLocalTimestamp(utils.ymdToTimestamp("2026-05-09"))), 1777852800)
	assertEqual(utils.weekStartUtcFromLocalTimestamp(utils.utcToLocalTimestamp(utils.ymdToTimestamp("2026-05-10") + 24 * 60 * 60 - 1)), 1777852800)
	assertEqual(utils.weekStartUtcFromLocalTimestamp(utils.utcToLocalTimestamp(utils.ymdToTimestamp("2026-05-11"))), 1778457600)
end





test_dayOfWeekAndTimeStrToSecondsSinceWeekStart()
test_localToUtcTimestamp()
test_parseIsoDateTime()
test_seasonsBetween()
test_utcToLocalTimestamp()
test_ymdAddOffset()
test_ymdDayOfWeek()
test_ymdToTimestamp()
test_weekStartFromLocalTimestamp()
