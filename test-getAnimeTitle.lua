-- test-getAnimeTitle.lua

-- Tests the db.getAnimeTitle() API
-- Works in a synchronous IDE-debugger-friendly environment

local db = require("db")





local aId = 15382





local details = db.getAnimeDetails(aId)
print("aid " .. tostring(aId) .. " en: " .. details.enTitle)
