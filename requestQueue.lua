-- requestQueue.lua

--[[
Implements a queue for requesting details from AniDB.
The queue runs in background and requests details through any source in aniDbDetails.lua:
	- local files
	- cache at xoft.cz
	- AniDB API servers
The queue handles failures and retries, although it doesn't persist them across app restarts.
--]]

local copas = require("copas")
local aniDbDetails = require("aniDbDetails")
local db = require("db")
local log = require("logger").log





--- The time to wait between requests if the queue is not empty:
local gTimeBetweenRequestsBusy = 0.2

--- The time to wait between requests if the queue is empty:
local gTimeBetweenRequestsIdle = 1





local RQ =
{
	thread = nil,  -- The background thread in which the processing takes place. Initialized by RQ.start()
	queue = {}     -- The queue to process. Array-table of { animeId = ..., shouldSkipCaches = ... }
}





--- Adds the specified anime to the end of the queue to be downloaded in the background
-- If aShouldSkipCaches is true, only AniDB.net is queried, not the other caches (local, xoft.cz)
function RQ.add(aAnimeId, aShouldSkipCaches)
	aShouldSkipCaches = (aShouldSkipCaches == true)  -- Explicitly convert to a boolean

	-- If already in queue, merge flags and bail out:
	for i = 1, #RQ.queue do
		local item = RQ.queue[i]
		if (item.animeId == aAnimeId) then
			item.shouldSkipCaches = item.shouldSkipCaches or aShouldSkipCaches
			return
		end
	end

	-- Not in the queue, append:
	table.insert(RQ.queue,
	{
		animeId = aAnimeId,
		shouldSkipCaches = aShouldSkipCaches
	})
	copas.wakeup(RQ.thread)
end





--- Adds the specified anime to the front of the queue
-- If aShouldSkipCaches is true, only AniDB.net is queried, not the other caches (local, xoft.cz)
function RQ.addToFront(aAnimeId, aShouldSkipCaches)
	aShouldSkipCaches = (aShouldSkipCaches == true)

	-- If already in queue, move to front and merge flags:
	for i = 1, #RQ.queue do
		local item = RQ.queue[i]
		if (item.animeId == aAnimeId) then
			item.shouldSkipCaches = item.shouldSkipCaches or aShouldSkipCaches
			table.remove(RQ.queue, i)
			table.insert(RQ.queue, 1, item)
			return
		end
	end

	-- Not in the queue, insert to front:
	table.insert(RQ.queue, 1,
	{
		animeId = aAnimeId,
		shouldSkipCaches = aShouldSkipCaches
	})
	copas.wakeup(RQ.thread)
end





--- Runs the actual queue processing thread.
-- The client code is expected to add a call to this function as a copas thread
function RQ.run()
	while not(copas.exiting()) do
		if (#RQ.queue > 0) then
			local item = table.remove(RQ.queue, 1)
			local isOk, err = aniDbDetails.updateDetailsInDb(item.animeId, item.shouldSkipCaches)
			if not(isOk) then
				-- TODO: Add a timeout value to the queue so that the ID is not retried immediately
				table.insert(RQ.queue, item)  -- Return the item to the queue for later
			end
		end
		if (#RQ.queue > 0) then
			copas.sleep(gTimeBetweenRequestsBusy)
		else
			copas.sleep(gTimeBetweenRequestsIdle)
		end
	end
	log("requestQueue", "Finished.")
end





--- Starts the background processing thread
function RQ.start()
	assert(not(RQ.thread), "Only one start is allowed")

	RQ.thread = copas.addthread(RQ.run)
end





return RQ
