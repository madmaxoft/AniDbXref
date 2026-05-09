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
local httpClient = require("httpClient")
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





--- Requests a picture from AniDB
-- Returns the picture data on success
-- Returns nil and error message on failure
local function requestFromAniDb(aPictureId, aSize)
	assert(type(aPictureId) == "string")
	assert(type(aSize) == "string")

	-- Parse the picture URL:
	local picUrl, msg
	if (aSize == "thumb") then
		picUrl = string.format(config.get("picture.thumb.url"), aPictureId)
	else
		picUrl = string.format(config.get("picture.regular.url"), aPictureId)
	end

	-- Request the picture from the URL:
	local statusCode, headers, body = httpClient.get(picUrl)
	if not(statusCode) then
		-- DEBUG:
		log("picture", "Failed to read picture %s from AniDB. statusCode = %s, err = %s",
			aPictureId,
			tostring(statusCode),
			tostring(headers)
		)
		return nil, headers
	end
	if ((statusCode ~= "200") and (statusCode ~= 200)) then
		-- DEBUG:
		log("picture", "Failed to read picture %s from AniDB. statusCode = %s",
			aPictureId,
			tostring(statusCode)
		)
		return nil, "HTTP status " .. tostring(statusCode)
	end

	return body
end





return function(aRequest, aResponse)
	local path, params = aRequest:parsedPathAndQuery()
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
	picData, msg = requestFromAniDb(pictureId, pictureSize)
	if not(picData) then
		-- Retry once - if the connection just timed out, it will be reconnected
		log("picture", "Failed to download picture %s / %s from AniDB (%s), retrying...", pictureSize, pictureId, tostring(msg))
		picData, msg = requestFromAniDb(pictureId, pictureSize)
		if not(picData) then
			log("picture", "Failed to retry-download picture %s / %s from AniDB (%s), failing.", pictureSize, pictureId, tostring(msg))
		end
	end
	if (picData) then
		db.storePictureData(pictureId, pictureSize, picData)
		aResponse:setContentType("image/jpeg")
		return aResponse:sendRawDataWithLength(picData)
	end
	return aResponse:sendError(404, "Failed to download from AniDB.")
end
