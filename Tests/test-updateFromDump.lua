-- Tests/test-updateFromDump.lua

--[[
Implements a test that updates the list of anime from an AniDB dump in 'anime-titles.xml.gz' file.
If the file doesn't exist, downloads a fresh new one.

The test runs in a single threaded environment for easier debugging.
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

local db = require("db")
local httpClient = require("httpClient").noCopas()
local ltn12 = require("ltn12")
local zlib = require("zlib")





-- Download dump, if not present already:
local fnam = "anime-titles.xml.gz"
local f = io.open(fnam, "rb")
if not(f) then
	print("Downloading AniDB dump...")
	local statusCode, headers, body = httpClient.get("http://anidb.net/api/anime-titles.xml.gz")
	if (statusCode ~= 200) then
		error(string.format("Failed to download the dump from AniDB, status %s, err %s", tostring(statusCode), tostring(headers)))
	end
	local f2 = assert(io.open(fnam, "wb"))
	f2:write(body)
	f2:close()
	f2 = nil
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
