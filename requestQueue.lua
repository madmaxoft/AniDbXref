-- requestQueue.lua

--[[
Implements a queue for requesting details from AniDB.
The queue runs in background and requests details through AniDB API; backing off if a rate-limit is reached.
--]]

local copas = require("copas")
local socket = require("socket")
local aniDbDetails = require("aniDbDetails")
local lomParser = require("lxp.lom")
local db = require("db")
local lfs = require("lfs")
local log = require("logger").log





--- The time to wait between requests if they are getting through:
local gTimeBetweenRequests = 3

--- The time to wait between requests once we hit an API rate limit
local gRateLimitBackoff = 3 * 60 * 60  -- 3 hours





local RQ = {queue = {}}





--- Adds the specified anime to the end of the queue to be downloaded in the background
function RQ.add(aAnimeId)
	-- If already in queue, bail out:
	for i = 1, #RQ.queue do
		if (RQ.queue[i] == aAnimeId) then
			return
		end
	end

	-- Not in the queue, append:
	table.insert(RQ.queue, aAnimeId)
end





--- Adds the specified anime to the end of the queue to be downloaded in the background
function RQ.addToFront(aAnimeId)
	-- If already in queue, move to front:
	for i = 1, #RQ.queue do
		if (RQ.queue[i] == aAnimeId) then
			table.remove(RQ.queue, i)
			table.insert(RQ.queue, 1, aAnimeId)
			return
		end
	end

	-- Not in the queue, insert to front:
	table.insert(RQ.queue, 1, aAnimeId)
end





--- Requests the anime details and stores it into the DB
-- Returns true on success, nil and error codes on failure
local gNumRequests = 0
function RQ.performRequest(aAnimeId)
	gNumRequests = gNumRequests + 1
	log("RequestQueue", "Requesting details for anime %d, request %d", aAnimeId, gNumRequests)

	-- Fetch the details from the API:
	local apiResponse, err = aniDbDetails.fetchXml(aAnimeId)
	if not(apiResponse) then
		log("RequestQueue", "Failed to fetch AniDB APi XML: %s", tostring(err))
		return nil, err
	end

	local parsedLom = lomParser.parse(apiResponse)
	if not(parsedLom) then
		log("RequestQueue",
			"FAILED to xml-parse response for anime %d. Response saved to file %s",
			aAnimeId, fileName
		)
		return nil, "xml-parse-failed"
	end

	-- If the API returned an <error> response, parse it and decide what kind of failure it is:
	if (type(parsedLom) ~= "table") then
		log("RequestQueue",
			"Unknown API response received for anime %d. Response saved to file %s",
			aAnimeId, fileName
		)
		return nil, "unknown-xml-format"
	end
	if (parsedLom.tag == "error") then
		local code = tostring((parsedLom.attr or {}).code)
		log("RequestQueue",
			"ERROR code %s returned for anime %d. Response saved to file %s",
			code, aAnimeId, fileName
		)
		if (code == "500") then
			return nil, "rate-limit"
		else
			return nil, "api-error", code
		end
	end

	-- Transform the parsed LOM object into the details table:
	local parsedDetails = aniDbDetails.transformParsedIntoDetails(parsedLom)
	if not(parsedDetails.aId) then
		log("RequestQueue", "Failed to transform AniDB API XML to details.")
		return nil, "parse-details-failed"
	end

	db.storeAnimeDetails(parsedDetails)
	log("RequestQueue", "Updated anime details for %d", aAnimeId)
	return true
end





--- Runs the actual queue processing thread.
-- The client code is expected to add a call to this function as a copas thread
function RQ.run()
	-- Create the folder for storing suspicious API responses:
	require("lfs").mkdir("AniDB")

	while not(copas.exiting()) do
		if (#RQ.queue > 0) then
			local animeId = table.remove(RQ.queue, 1)
			local isOk, err = RQ.performRequest(animeId)
			if not(isOk) then
				table.insert(RQ.queue, 1, animeId)  -- Return the aId to the queue for later
				if (err == "rate-limit") then
					print("[RequestQueue] AniDB API returned rate-limit, backing off")
					copas.sleep(gRateLimitBackoff)
				end
				-- Other errors do not trigger long cooldown or requeue.
			end
			copas.sleep(gTimeBetweenRequests)
		else
			copas.sleep(gTimeBetweenRequests)
		end
	end
	print("[RequestQueue] Finished.")
end





return RQ
