-- test-getAnimeTitle.lua

-- Tests the db.getAnimeTitle() API
-- Works in a synchronous IDE-debugger-friendly environment




local db = require("db")
db.createSchema()





print("aid 11167 en: " .. tostring(db.getAnimeTitle(11167, "en")))
