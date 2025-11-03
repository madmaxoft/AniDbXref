-- test-localAniDbUpdate.lua

--[[ Runs the AniDB update on the local file anime-titles.xml.gz.

Runs without any coroutines, so it's easy to debug using an IDE.
--]]




local zlib = require("zlib")





-- Initialize the DB:
local db = require("db")
db.createSchema()

-- Decompress
local tmpFile = "anime-titles.xml.gz"
print("[update] Decompressing AniDB dump...")
local gzFile = assert(io.open(tmpFile, "rb"))
local gzData = gzFile:read("*a")
gzFile:close()
local xmlString = zlib.inflate()(gzData)

-- Update DB using module-local connection
print("[update] Updating the AniDB data in the DB...")
db.updateAniDbDataFromDump(xmlString)
print("[update] Update finished.")
