-- Tests/test-getAnimeTitle.lua

--[[
Tests the db.getAnimeTitle() API
Works in a synchronous IDE-debugger-friendly environment
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true





local db = require("db")
local utils = require("utils")





local aId = 15382

local details = db.getAnimeDetails(aId)
print("aid " .. tostring(aId) .. " en: " .. details.enTitle)
print("details:")
print(utils.serializeSimpleTable(details))