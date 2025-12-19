-- test-update.lua

--[[
Implements a test that updates the list of anime from an AniDB dump in 'anime-titles.xml.gz' file

The test runs in a single threaded environment for easier debugging.
--]]





local db = require("db")
local http = require("socket.http")
local ltn12 = require("ltn12")
local zlib = require("zlib")





-- Download dump, if not present already:
local fnam = "anime-titles.xml.gz"
local f = io.open(fnam, "rb")
if not(f) then
	print("Downloading AniDB dump...")
	local f2 = assert(io.open(fnam, "wb"))
	http.request{ url = "http://anidb.net/api/anime-titles.xml.gz", sink = ltn12.sink.file(f2) }
	f2:close()
	f = assert(io.open(fnam, "rb"))
end

-- Decompress:
print("Decompressing AniDB dump...")
local gzFile = assert(io.open(fnam, "rb"))
local gzData = gzFile:read("*a")
gzFile:close()
local xmlString = zlib.inflate()(gzData)

-- Update DB using module-local connection:
print("Updating the AniDB data in the DB...")
db.updateAniDbDataFromDump(xmlString)
print("Update finished.")
