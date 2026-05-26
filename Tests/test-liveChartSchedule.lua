-- Tests/test-liveChartSchedule.lua

--[[
Tests the LiveChart integration interface
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;./?.lua;Tests/?.lua" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true

require("httpClient").noCopas()  -- Disable Copas in the underlying httpClient
local liveChartSchedule = require("liveChartSchedule")
local utils = require("utils")




local bounds = utils.seasonToYmdBounds("2026-2")
local schedule, msg = liveChartSchedule.queryDate(utils.ymdAddOffset(bounds.startDateYmd, 50))
if not(schedule) then
	print("Failed to query day schedule: " .. tostring(msg))
	return
end
print("Schedule:")
print(utils.serializeSimpleTable(schedule))
