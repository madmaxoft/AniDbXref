-- Handlers/updateStart.lua

--[[
Starts the AniDB dump update in background
--]]

local log = require("logger").log
local db = require("db")





local function updateThread()
	log("update", "Starting update from AniDB dump...")
	local httpClient = require("httpClient")
	local ltn12 = require("ltn12")
	local zlib = require("zlib")

	-- Download dump
	local tmpFile = "anime-titles.xml.gz"
	if not(isLocal) then
		log("update", "Downloading AniDB dump...")
		local f = assert(io.open(tmpFile, "wb"))
		local code, headers, body = httpClient.get("http://anidb.net/api/anime-titles.xml.gz")
		if (code ~= 200) then
			log("update", "Failed to download AniDB dump: %s / %s", tostring(code), tostring(headers))
			return
		end
	end

	-- Decompress
	log("update", "Decompressing AniDB dump...")
	local gzFile = assert(io.open(tmpFile, "rb"))
	local gzData = gzFile:read("*a")
	gzFile:close()

	local xmlString = zlib.inflate()(gzData)

	-- Update DB using module-local connection
	log("update", "Updating the AniDB data in the DB...")
	db.updateAniDbDataFromDump(xmlString)
	log("update", "Update finished.")
end





local function updateFromWeb(aRequest, aResponse)
	local lastUpdate = db.getLastAniDbUpdate()
	local now = os.time()
	local nextAllowed = lastUpdate + 24 * 3600

	if ((now - lastUpdate) < 24 * 3600) then
		local lastStr = os.date("%Y-%m-%d %H:%M:%S", lastUpdate)
		local nextStr = os.date("%Y-%m-%d %H:%M:%S", nextAllowed)
		return aResponse:sendError(403,
			string.format("Update blocked: last dump processed at %s, next allowed at %s", lastStr, nextStr)
		)
	end

	require("copas").addthread(updateThread)

	aResponse:sendSimpleMessage("Update started in background.")
end





--- Starts an update from the specified string data (uploaded file)
-- The file could be the XML data directly, or gzipped xml data
local function updateFromString(aRequest, aResponse, aData)
	assert(type(aRequest) == "table")
	assert(type(aResponse) == "table")
	assert(type(aData) == "string")

	-- Run in a separate thread in order not to block the entire server
	local threadFn = function()
		if (aData:sub(1, 2) == "\031\139") then
			log("update", "Decompressing AniDB dump...")
			aData = require("zlib").inflate()(aData)
		end
		log("update", "Updating the AniDB data in the DB...")
		db.updateAniDbDataFromDump(aData)
		log("update", "Update finished.")
	end
	require("copas").addthread(threadFn)

	aResponse:sendSimpleMessage("Update started in background.")
end





return function(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	local formData, msg = aRequest:formData()
	if not(formData) then
		return aResponse:sendError(400, "Failed to parse form data: " .. tostring(msg))
	end
	if (formData["dumpFile"]) then
		return updateFromString(aRequest, aResponse, formData["dumpFile"])
	else
		return updateFromWeb(aRequest, aResponse)
	end
end
