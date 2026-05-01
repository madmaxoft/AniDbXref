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
local config = require("config")
local url = require("socket.url")





--- Validator for the URL template config value
local function validateUrlTemplate(aUrl)
	assert(type(aUrl) == "string")

	-- Must contain exactly one %s:
	local num = 0
	for _ in aUrl:gmatch("%%s") do
		num = num + 1
	end
	if (num ~= 1) then
		return nil, "URL template must contain exactly one %s placeholder"
	end

	-- reject any % not followed by s or escaped %%
	if (aUrl:match("%%[^s%%]")) then
		return nil, "Only %s placeholder is allowed"
	end

	-- Try formatting to ensure it's valid:
	local ok, result = pcall(string.format, aUrl, "test")
	if not(ok) then
		return nil, "Invalid format string: " .. tostring(result)
	end


	-- Basic URL sanity check:
	if not(result:match("^https?://")) then
		return nil, "Formatted URL must start with http:// or https://"
	end

	return true
end





config.registerDefinitions({
	{
		identifier = "picture.regular.url",
		description = "The URL template for downloading regular-size pictures. Must contain exactly one %s which will be replaced with picture ID.",
		valueType = "string",
		default = "https://cdn.anidb.net/images/main/%s",
		validator = validateUrlTemplate,
	},
	{
		identifier = "picture.regular.auth.username",
		description = "The username for HTTP basic auth used for downloading regular-size pictures. Empty means no auth.",
		valueType = "string",
		default = "",
	},
	{
		identifier = "picture.regular.auth.password",
		description = "The password for HTTP basic auth used for downloading regular-size pictures. Ignored when username is empty.",
		valueType = "string",
		default = "",
		isSecret = true,
	},

	{
		identifier = "picture.thumb.url",
		description = "The URL template for downloading thumbnail-size pictures. Must contain exactly one %s which will be replaced with picture ID.",
		valueType = "string",
		default = "https://cdn.anidb.net/images/65/%s-thumb.jpg",
		validator = validateUrlTemplate,
	},
	{
		identifier = "picture.thumb.auth.username",
		description = "The username for HTTP basic auth used for downloading regular-size pictures. Empty means no auth.",
		valueType = "string",
		default = "",
	},
	{
		identifier = "picture.thumb.auth.password",
		description = "The password for HTTP basic auth used for downloading regular-size pictures. Ignored when username is empty.",
		valueType = "string",
		default = "",
		isSecret = true,
	},
})





--- Cache of the persistent TCP connections, as connection objects
-- Dict-table of "scheme:host:port" -> {socket = ..., cacheKey = "scheme:host:port"}
local gConnCache = {}





local defaultPort =
{
	http = 80,
	https = 443,
}

--- Returns the port to use for the specified URL
-- If the port is not specified in the URL, uses the default port for the scheme
local function getPort(aParsedUrl)
	assert(type(aParsedUrl) == "table")
	assert(type(aParsedUrl.scheme) == "string")

	return aParsedUrl.port or defaultPort[aParsedUrl.scheme] or 80
end





--- Returns the key into the gConnCache table for the specified parsed URL
local function connectionKey(aParsedUrl)
	assert(type(aParsedUrl) == "table")
	assert(type(aParsedUrl.scheme) == "string")
	assert(type(aParsedUrl.host) == "string")

	return string.format("%s:%s:%d",
		aParsedUrl.scheme,
		aParsedUrl.host,
		getPort(aParsedUrl)
	)
end





-- TLS parameters (default)
local sslParams = {
	mode = "client",
	protocol = "tlsv1_2",
	verify = "none",
	options = "all",
}

--- Returns the persistent connection object for the host specified in the parsed URL
-- If no such connection is present yet, creates one.
local function getHttpConnection(aParsedUrl)
	assert(type(aParsedUrl) == "table")
	assert(type(aParsedUrl.host) == "string")

	-- Return the connection from the cache, if exists:
	local key = connectionKey(aParsedUrl)
	local conn = gConnCache[key]
	if (conn) then
		return conn
	end

	-- Not in cache, create, connect and add into cache:
	log("picture", "Opening HTTP connection to %s, path %s", aParsedUrl.host, aParsedUrl.path)
	local tcp = assert(socket.tcp())
	tcp:settimeout(5)
	assert(tcp:connect(aParsedUrl.host, getPort(aParsedUrl)))
	if (aParsedUrl.scheme == "https") then
		local tlsConn, err = ssl.wrap(tcp, sslParams)
		if not tlsConn then error("SSL wrap failed: "..tostring(err)) end
		assert(tlsConn:dohandshake())
		tcp = tlsConn
	end

	local connObj =
	{
		socket = tcp,
		cacheKey = key
	}
	gConnCache[key] = connObj
	return connObj
end





--- Closes the specified connection and removes it from the cache
local function releaseHttpConnection(aConnObj)
	assert(type(aConnObj) == "table")
	assert(type(aConnObj.cacheKey) == "string")

	aConnObj.socket:close()
	gConnCache[aConnObj.cacheKey] = nil
end





--- Returns the string that is to be sent in the GET request for the specified parsed URL
-- This consists of the path, and if present, the query
local function getRequest(aParsedUrl)
	assert(type(aParsedUrl) == "table")

	local res = aParsedUrl.path
	if (aParsedUrl.query) then
		res = res .. "?" .. aParsedUrl.query
	end

	return res
end





--- Requests a picture from AniDB
local function requestFromAniDb(aPictureId, aSize)
	assert(type(aPictureId) == "string")
	assert(type(aSize) == "string")

	-- Parse the picture URL:
	local picUrl, msg
	if (aSize == "thumb") then
		picUrl, msg = url.parse(string.format(config.get("picture.thumb.url"), aPictureId))
	else
		picUrl, msg = url.parse(string.format(config.get("picture.regular.url"), aPictureId))
	end
	if not(picUrl) then
		log("picture", "FAILED to parse picture URL %s : %s", picUrl, tostring(msg))
		return
	end

	-- Build the HTTP request:
	local request = table.concat({
		string.format("GET %s HTTP/1.1", getRequest(picUrl)),
		string.format("Host: %s", picUrl.host),
		"Connection: keep-alive",
		"User-Agent: AniDbXref/1.0",
		"", -- empty line to end headers
		""
	}, "\r\n")

	-- Send the HTTP request:
	local conn, msg = getHttpConnection(picUrl)
	if not(conn) then
		log("picture", "Failed to connect for picture %s: %s", aPictureId, tostring(msg))
		return
	end
	local isOK, msg = conn.socket:send(request)
	if not(isOK) then
		log("picture", "Failed to send request for picture %s: %s. RETRYING", aPictureId, tostring(msg))
		-- Connection might have gotten closed; release and retry once:
		releaseHttpConnection( conn)
		conn = getHttpConnection(picUrl)
		isOK, msg = conn.socket:send(request)
		if not(isOK) then
			log("picture", "Failed to send second request for picture %s: %s", aPictureId, tostring(msg))
			releaseHttpConnection(conn)
			return nil
		end
	end

	-- Read the HTTP response:
	local httpCode, httpResponse, headers, firstLine = httpRequest.readRequestHeaders(conn.socket)
	if not(headers) then
		log("picture", "Failed to read http headers from AniDB response for picture %s. %s | %s | %s; firstLine \"%s\"",
			aPictureId,
			tostring(httpCode),
			tostring(httpResponse),
			tostring(headers),
			tostring(firstLine)
		)
		releaseHttpConnection(conn)
		return nil, httpResponse

	end
	local body, msg = httpRequest.readBody(conn.socket, headers)
	if not(body) then
		log("picture", "Failed to read http body for picture %s: %s", aPictureId, tostring(msg))
		releaseHttpConnection(conn)
		return nil, msg
	end

	return body
end





return function(aRequest, aResponse)
	local path, params = aRequest:parsePathAndQuery()
	if not(params and params["id"]) then
		aResponse:sendError(404, "id parameter not found")
		return
	end
	local pictureId = params["id"]
	local pictureSize = params["size"] or "regular"

	-- Search the cache:
	local picData, msg = db.pictureData(pictureId, pictureSize)
	if (picData) then
		aResponse:setContentType("image/jpeg")
		return aResponse:sendRawDataWithLength(picData)
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
		aResponse:setContentType("image/jpeg")
		return aResponse:sendRawDataWithLength(picData)
	end
	return aResponse:sendError(404, "Failed to download from AniDB.")
end
