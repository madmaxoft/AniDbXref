-- requestQueue.lua

--[[ Implements a queue for requesting details.
The queue runs in background and requests details through AniDB API; backing off if a rate-limit is reached.
--]]

local copas = require("copas")
local socket = require("socket")
local aniDbDetails = require("aniDbDetails")
local lomParser = require("lxp.lom")
local db = require("db")





--- The time to wait between requests if they are getting through:
local gTimeBetweenRequests = 3

--- The time to wait between requests once we hit an API rate limit
local gRateLimitBackoff = 3 * 60 * 60  -- 3 hours





local RQ = {queue = {}}





--- Adds the specified anime to the end of the queue to be downloaded in the background
function RQ.add(aAnimeId)
	-- If already in queue, move to front:
	for i = 1, #RQ.queue do
		if (RQ.queue[i] == aAnimeId) then
			table.remove(RQ.queue, i)
			table.insert(RQ.queue, 1, aAnimeId)
			return
		end
	end

	-- Not in the queue, append:
	table.insert(RQ.queue, aAnimeId)
end





--- Requests the anime details and stores it into the DB
-- Returns true on success, nil and error codes on failure
local gNumRequests = 0
function RQ.performRequest(aAnimeId)
	gNumRequests = gNumRequests + 1
	print(string.format("[RequestQueue] Requesting details for anime %d, request %d", aAnimeId, gNumRequests))
	local fileName = string.format("AniDB/%d.xml", aAnimeId)

	-- Fetch the details from the API:
	local apiResponse, err = aniDbDetails.fetchXml(aAnimeId)
	if not(apiResponse) then
		print("[RequestQueue] Failed to fetch AniDB APi XML: " .. tostring(err))
		return nil, err
	end

	local parsedLom = lomParser.parse(apiResponse)
	if not(parsedLom) then
		-- Store the response into a file:
		local f = assert(io.open(fileName), "wb")
		f:write(apiResponse)
		f:close()

		print(string.format(
			"[RequestQueue] FAILED to xml-parse response for anime %d. Response saved to file %s",
			aAnimeId, fileName
		))
		return nil, "xml-parse-failed"
	end

	-- If the API returned an <error> response, parse it and decide what kind of failure it is:
	for _, v in ipairs(parsedLom) do
		if (type(v) == "table") then
			if (v.tag == "error") then
				-- Store the response into a file:
				f = assert(io.open(fileName), "wb")
				f:write(apiResponse)
				f:close()

				local code = tostring((v.attr or {}).code)
				print(string.format(
					"[RequestQueue] ERROR code %s returned for anime %d. Response saved to file %s",
					code, aAnimeId, fileName
				))
				if (code == "500") then
					return nil, "rate-limit"
				else
					return nil, "api-error", code
				end
			end
		end
	end

	-- Transform the parsed LOM object into the details table:
	local parsedDetails = aniDbDetails.transformParsedIntoDetails(parsedLom)
	if not(parsedDetails.aId) then
		print("[RequestQueue] Failed to transform AniDB API XML to details.")
		return nil, "parse-details-failed"
	end

	db.storeAnimeDetails(parsedDetails)
	print("[RequestQueue] Updated anime details for " .. tostring(aAnimeId))
	return true
end





--- Runs the actual queue processing thread.
-- The client code is expected to add a call to this function as a copas thread
function RQ.run()
	-- Create the folder for storing suspicious API responses:
	require("lfs").mkdir("AniDB")

	while (true) do
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
end





return RQ
