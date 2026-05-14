-- Tools/tool-updateAllDetailsFromLocal.lua

--[[
Updates details for all anime in the DB from the local files in AniDB subfolder.
Can be used after dumping all data from an AniDbMirror using its downloader script.
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true

local db = require("db")
local details = require("aniDbDetails")
local perf = require("perf")




--- The minimum ID to update
-- Used for resuming after a break / error
local gMinId = 0





--- Updates a single anime in the DB from the details xml file in the AniDB subfolder
local function updateAnime(aId)
	assert(type(aId) == "number")

	-- Read file contents:
	local timer = perf.newTimer("updateAnime")
	local prefix = string.format("AniDB/%d", math.floor(aId / 100))
	local fileName = string.format("%s/%d.xml", prefix, aId)
	local f = io.open(fileName, "rb")
	if not(f) then
		return nil, "Cannot open file"
	end
	local xml = f:read("*all")
	timer("Read XML")
	f:close()

	-- Parse the XML:
	local parsedLom, msg = require("lxp.lom").parse(xml)
	timer("Parse XML")
	if not(parsedLom) then
		return nil, string.format("Failed to parse XML: %s", tostring(msg))
	end
	if (parsedLom.tag ~= "anime") then
		-- Silently skip these - there are a few animes that return an <error> response in their API call, such as 14738
		return true
	end
	local parsedDetails, msg = details.transformParsedIntoDetails(parsedLom)
	timer("Transform into details")
	if not(parsedDetails) then
		return nil, string.format("Failed to parse details from XML: %s", tostring(msg))
	end
	if (parsedDetails.aId ~= aId) then
		return nil, string.format("Wrong ID found in XML file %s, exp %d, got %s", fileName, aId, tostring(parsedDetails.aId))
	end

	-- Store into the DB:
	local isOK, msg1, msg2 = pcall(db.storeAnimeDetails, parsedDetails)
	timer("Store in DB")
	return isOK, msg1, msg2
end





-- Config:
perf.silenceTimer("db.storeAnimeCharacters")
perf.silenceTimer("db.storeAnimeDetails")
perf.silenceTimer("db.storeAnimeEpisodes")
perf.silenceTimer("updateAnime")

print("Reading all IDs...")
local allIDs = db.allAnimeIDs()
local numAll = #allIDs
local numSkipped = 0
print("Processing " .. numAll .. " items...")
local timeStarted = os.time()
db.execBoundStatement("PRAGMA foreign_keys = off", {}, "fk.off")
db.beginTransaction()
for idx, id in ipairs(allIDs) do
	print("id: " .. tostring(id))
	if (idx % 10 == 0) then
		local timeElapsed = os.time() - timeStarted
		local estMinutesLeft = (timeElapsed / (idx - numSkipped) * (numAll - idx + 1)) / 60
		print(string.format("%d / %d, %d %%, estimated %.1f minutes left", idx, numAll, 100 * idx / numAll, estMinutesLeft))
	end
	if ((idx % 100 == 0) and (id >= gMinId)) then
		print("Committing the batch...")
		db.commitTransaction()
		db.beginTransaction()
		print("Committed.")
	end
	if (id >= gMinId) then
		local isOK, msg = updateAnime(id)
		if not(isOK) then
			if (msg ~= "Cannot open file") then
				error("Failed to update anime " .. id .. ": " .. tostring(msg))
			else
				print(string.format("Cannot open file for ID %d, skipping", id))
			end
		end
	else
		numSkipped = numSkipped + 1
	end
end
print("Committing the last batch.")
db.commitTransaction()
db.execBoundStatement("PRAGMA foreign_keys = on", {}, "fk.on")
print("Done.")
