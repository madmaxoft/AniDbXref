-- Handlers/picture.lua

--[[
Implements the HTTP endpoint handler for requesting pictures.

Pictures are read from DB cache; if not present, they are requested from anidb.net and stored in the cache.
The request takes the picture's id and size as parameters:
	- "id" contains the pictureId
	- "size" is either "regular" or "thumb"
--]]

local db = require("db")
local httpResponse = require("httpResponse")
local httpRequest = require("httpRequest")
local log = require("logger").log
local socket = require("socket")
local ssl = require("ssl")





-- Keep a single persistent connection for AniDB HTTP requests
local aniDbConn = nil
local aniDbHost = "cdn.anidb.net"
local aniDbPort = 443

-- TLS parameters (default)
local sslParams = {
	mode = "client",
	protocol = "tlsv1_2",
	verify = "none",       -- skip certificate verification (for local app)
	options = "all",
}

--- Returns the persistent TCP connection to anidb.net (re-connects when needed)
local function getAniDbConnection()
	if aniDbConn then
		return aniDbConn
	end

	-- Plain TCP
	local tcp = assert(socket.tcp())
	tcp:settimeout(5)
	assert(tcp:connect(aniDbHost, aniDbPort))

	-- Wrap TLS
	local tlsConn, err = ssl.wrap(tcp, sslParams)
	if not tlsConn then error("SSL wrap failed: "..tostring(err)) end
	assert(tlsConn:dohandshake())

	aniDbConn = tlsConn
	return aniDbConn
end





--- Requests a picture from AniDB
local function requestFromAniDb(aPictureId, aSize)
	assert(type(aPictureId) == "string")
	assert(type(aSize) == "string")

	local conn = getAniDbConnection()
	local path
	if (aSize == "thumb") then
		path = string.format("/images/65/%s-thumb.jpg", aPictureId)
	else
		path = string.format("/images/main/%s", aPictureId)
	end

	-- Build and send the HTTP request
	local request = table.concat({
		string.format("GET %s HTTP/1.1", path),
		string.format("Host: %s", aniDbHost),
		"Connection: keep-alive",
		"User-Agent: AniDbXref/1.0",
		"", -- empty line to end headers
		""
	}, "\r\n")

	local isOK, msg = conn:send(request)
	if not(isOK) then
		log("picture", "Failed to send request for picture %s: %s. RETRYING", aPictureId, tostring(msg))
		-- Connection might be closed; reset and retry once
		aniDbConn:close()
		aniDbConn = nil
		conn = getAniDbConnection()
		isOK, msg = conn:send(request)
		if not(isOK) then
			log("picture", "Failed to send request for picture %s: %s", aPictureId, tostring(msg))
			aniDbConn:close()
			aniDbConn = nil
			return nil
		end
	end

	-- Read the HTTP response:
	local httpCode, httpResponse, headers, firstLine = httpRequest.readRequestHeaders(conn)
	if not(headers) then
		log("picture", "Failed to read http headers from AniDB response for picture %s. %s | %s | %s; firstLine \"%s\"",
			aPictureId,
			tostring(httpCode),
			tostring(httpResponse),
			tostring(headers),
			tostring(firstLine)
		)
		aniDbConn:close()
		aniDbConn = nil
		return nil

	end
	local body, msg = httpRequest.readBody(conn, headers)
	if not(body) then
		log("picture", "Failed to read http body for picture %s: %s", aPictureId, tostring(msg))
		aniDbConn:close()
		aniDbConn = nil
		return nil, msg
	end

	return body
end





return function(aClient, aRequestPath, aRequestHeaders)
	local path, params = httpRequest.parseRequestPath(aRequestPath)
	if not(params and params["id"]) then
		httpResponse.sendError(aClient, 404, "id parameter not found")
		return
	end
	local pictureId = params["id"]
	local pictureSize = params["size"] or "regular"

	-- Search the cache:
	local picData, msg = db.pictureData(pictureId, pictureSize)
	if (picData) then
		return httpResponse.send(aClient, 200, "image/jpeg", picData)
	end

	-- Not in the cache, request from anidb:
	picData = requestFromAniDb(pictureId, pictureSize)
	if not(picData) then
		-- Retry once - if the connection just timed out, it will be reconnected
		log("picture", "Failed to download picture %s / %s from AniDB, retrying...", pictureSize, pictureId)
		picData = requestFromAniDb(pictureId, pictureSize)
	end
	if (picData) then
		db.storePictureData(pictureId, pictureSize, picData)
		return httpResponse.send(aClient, 200, "image/jpeg", picData)
	end
	return httpResponse.sendError(aClient, 404, "Failed to download from AniDB.")
end
