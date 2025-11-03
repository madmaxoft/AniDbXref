--- Starts the AniDB dump update in background
return function(aClient, aRequestPath, aRequestParameters, aRequestHeaders)
	local db = require("db")
	local httpResponse = require("httpResponse")
	local lastUpdate = db.getLastAniDbUpdate()
	local now = os.time()
	local nextAllowed = lastUpdate + 24*3600
	
	-- DEBUG:
	local isLocal = true

	if (not(isLocal) and ((now - lastUpdate) < 24*3600)) then
		local lastStr = os.date("%Y-%m-%d %H:%M:%S", lastUpdate)
		local nextStr = os.date("%Y-%m-%d %H:%M:%S", nextAllowed)
		return httpResponse.send(aClient, 403, {["Content-Type"] = "text/plain"},
			string.format("Update blocked: last dump processed at %s, next allowed at %s", lastStr, nextStr))
	end

	require("copas").addthread(function()
		print("[update] Starting update from AniDB dump...")
		local http = require("socket.http")
		local ltn12 = require("ltn12")
		local zlib = require("zlib")

		-- Download dump
		local tmpFile = "anime-titles.xml.gz"
		if not(isLocal) then
			print("[update] Downloading AniDB dump...")
			local f = assert(io.open(tmpFile, "wb"))
			http.request{ url = "http://anidb.net/api/anime-titles.xml.gz", sink = ltn12.sink.file(f) }
		end

		-- Decompress
		print("[update] Decompressing AniDB dump...")
		local gzFile = assert(io.open(tmpFile, "rb"))
		local gzData = gzFile:read("*a")
		gzFile:close()
		local xmlString = zlib.inflate()(gzData)

		-- Update DB using module-local connection
		print("[update] Updating the AniDB data in the DB...")
		db.updateAniDbDataFromDump(xmlString)
		print("[update] Update finished.")
	end)

	httpResponse.send(aClient, 200, {["Content-Type"] = "text/plain"}, "Update started in background.")
end
