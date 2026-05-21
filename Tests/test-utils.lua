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





local function test_parseIsoDateTime()
	assertEqual(utils.parseIsoDateTime("1970-01-01T00:00:00"), 0)
	assertEqual(utils.parseIsoDateTime("1970-01-02T00:00:00"), 24 * 60 * 60)
	assertEqual(utils.parseIsoDateTime("1970-02-01T00:00:00"), 31 * 24 * 60 * 60)
	assertEqual(utils.parseIsoDateTime("1970-05-09T14:00:00"), 11109600)
	assertEqual(utils.parseIsoDateTime("2026-05-09T00:00:00"), 1778284800)
	assertEqual(utils.parseIsoDateTime("2026-05-09T12:34:56"), 1778330096)
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





test_parseIsoDateTime()
test_ymdAddOffset()
test_ymdDayOfWeek()
test_ymdToTimestamp()
