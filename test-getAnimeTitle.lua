-- test-getAnimeTitle.lua

-- Tests the db.getAnimeTitle() API
-- Works in a synchronous IDE-debugger-friendly environment




local aId = 15382

local db = require("db")
db.createSchema()





local details = db.getAnimeDetails(aId)
print("aid " .. tostring(aId) .. " en: " .. details.enTitle)
