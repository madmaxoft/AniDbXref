-- cmd-updateAllDetailsFromLocal.lua

--[[
Updates details for all anime in the DB from the local files in AniDB subfolder.
Can be used after dumping all data from an AniDbMirror using its downloader script.
--]]





local db = require("db")
local details = require("aniDbDetails")
local perf = require("perf")




--- The minimum ID to update
-- Used for resuming after a break / error
local gMinId = 19672





--- Updates a single anime in the DB from the details xml file in the AniDB subfolder
local function updateAnime(aId)
	assert(type(aId) == "number")

	-- Read file contents:
	-- local timer = perf.newTimer()
	local prefix = string.format("AniDB/%d", math.floor(aId / 100))
	local fileName = string.format("%s/%d.xml", prefix, aId)
	local f = io.open(fileName, "rb")
	if not(f) then
		return nil, "Cannot open file"
	end
	local xml = f:read("*all")
	-- timer("Read XML")
	f:close()

	-- Parse the XML:
	local parsedLom, msg = require("lxp.lom").parse(xml)
	-- timer("Parse XML")
	if not(parsedLom) then
		return nil, string.format("Failed to parse XML: %s", tostring(msg))
	end
	if (parsedLom.tag ~= "anime") then
		-- Silently skip these - there are a few animes that return an <error> response in their API call, such as 14738
		return true
	end
	local parsedDetails, msg = details.transformParsedIntoDetails(parsedLom)
	-- timer("Transform into details")
	if not(parsedDetails) then
		return nil, string.format("Failed to parse details from XML: %s", tostring(msg))
	end
	if (parsedDetails.aId ~= aId) then
		return nil, string.format("Wrong ID found in XML file %s, exp %d, got %s", fileName, aId, tostring(parsedDetails.aId))
	end

	-- Store into the DB:
	local isOK, msg1, msg2 = pcall(db.storeAnimeDetails, parsedDetails)
	-- timer("Store in DB")
	return isOK, msg1, msg2
end





print("Reading all IDs...")
db.createSchema()
local allIDs = db.allAnimeIDs()
local numAll = #allIDs
local numSkipped = 0
print("Processing " .. numAll .. " items...")
local timeStarted = os.time()
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
			error("Failed to update anime " .. id .. ": " .. tostring(msg))
		end
	else
		numSkipped = numSkipped + 1
	end
end
db.commitTransaction()
print("Done.")
