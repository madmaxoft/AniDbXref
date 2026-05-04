-- aniDbDetails.lua

--[[
Handles fetching and parsing details for anime titles from AniDB.
--]]





local httpClient = require("httpClient")
local ltn12 = require("ltn12")
local lxp = require("lxp")
local lomParser = require("lxp.lom")
local db = require("db")
local lfs = require("lfs")
local log = require("logger").log
local rateLimiter = require("rateLimiter")





local M = {}





local gAniDbRateLimiter = rateLimiter.new(3 * 60 * 60)





--- Returns the body returned by sending an http request to the specified URL
-- Returns nil and error message on failure
local function fetchUrl(aUrl)
	-- Request:
	local code, headers, body = httpClient.request({
		url = aUrl,
		headers = {
			["User-Agent"] = "AniDbXref/1",
			["Accept-Encoding"] = "gzip",
		},
	})
	if (not(code) or (code ~= 200)) then
		return nil, "HTTP request failed: " .. tostring(code)
	end

	-- Unzip the body, if the server returns it zipped:
	if (
		(headers["content-encoding"] == "gzip") or
		(body:sub(1,2) == "\031\139")
	) then
		local zlib = require("zlib")
		return zlib.inflate()(body)
	end

	return body
end





--- Fetches the details from the specified URL, using the specified rate limiter instance
-- Checks the downloaded data for error responses
-- Returns the response, or nil and error message on failure
-- Specific error messages "rate-limit" and "rate-limit-ongoing" are used for rate limit failures.
-- If the API returns another error message, it is reportd as an error, too, but not counted towards rate limit
local function fetchUrlWithRateLimit(aUrl, aRateLimiter)
	assert(type(aUrl) == "string")
	aRateLimiter = aRateLimiter or rateLimiter.default
	assert(type(aRateLimiter) == "table")
	assert(type(aRateLimiter.canAttemptRequest) == "function")
	assert(type(aRateLimiter.rateLimitReached) == "function")
	assert(type(aRateLimiter.success) == "function")

	-- Ask the RateLimiter:
	if not(aRateLimiter:canAttemptRequest()) then
		return nil, "rate-limit-ongoing"
	end

	-- Fetch the URL:
	local resp, msg = fetchUrl(aUrl)
	if not(resp) then
		-- Request failed, but not due to rate limit. Propagate the failure without reporting to aRateLimiter:
		return nil, msg
	end

	-- If the response is too large, it cannot be a rate-limit error:
	if (#resp > 200) then
		aRateLimiter:success()
		return resp
	end

	-- Parse the response to see if it is a rate-limit error:
	local parsedLom = lomParser.parse(resp)
	if not(parsedLom) then
		-- Failed to parse, not an error:
		aRateLimiter:success()
		return resp
	end
	if (type(parsedLom) ~= "table") then
		-- Not a valid LOM response, not an error:
		aRateLimiter:success()
		return resp
	end
	if (parsedLom.tag == "error") then
		local code = tostring((parsedLom.attr or {}).code)
		log("aniDbDetails", "ERROR code %s returned.", code)
		if (code == "500") then
			aRateLimiter:ratLimitReached()
			return nil, "rate-limit"
		end
		return nil, string.format("API error %s", code)
	end

	-- Consider everything else a success:
	aRateLimiter:success();
	return resp
end





--- Returns the contents of the specified file
-- Returns nil and error message on failure
local function readFileContents(aFileName)
	local f = io.open(aFileName, "rb")
	if not(f) then
		return nil, "Cannot open file"
	end
	local res = f:read("*all")
	f:close()
	return res
end





--- Returns the contents of the specified LOM tag's child as a string
-- Assumes that the subtag only contains a string, no sub-tags.
-- Only the first child of the specified name is considered.
-- Returns nil if no such child
local function transformParsedIntoDetails_getSubtagString(aParsedLom, aTagName)
	assert(type(aParsedLom) == "table")

	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == aTagName) then
				return v[1]
			end
		end
	end
	return nil
end





--- Returns the contents of the specified LOM tag as a string
-- Assumes that the tag only contains a string, no sub-tags
local function transformParsedIntoDetails_string(aParsedLom)
	assert(type(aParsedLom) == "table")

	return aParsedLom[1]
end





--- Returns the contents of the specified LOM tag as a date string
-- Assumes that the tag only contains a string, no sub-tags
local function transformParsedIntoDetails_date(aParsedLom)
	assert(type(aParsedLom) == "table")

	return aParsedLom[1]
end





--- Returns the contents of the specified LOM tag parsed as asingle title entry
local function transformParsedIntoDetails_title(aParsedLom)
	assert(type(aParsedLom) == "table")
	aParsedLom.attr = aParsedLom.attr or {}
	assert(type(aParsedLom.attr) == "table")

	return
	{
		language = aParsedLom.attr["xml:lang"],
		kind = aParsedLom.attr["type"],
		title = aParsedLom[1]
	}
end





--- Returns the contents of the specified LOM tag parsed as an array-table of title entries
local function transformParsedIntoDetails_titles(aParsedLom)
	assert(type(aParsedLom) == "table")

	local result = {}
	local n = 0
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == "title") then
				n = n + 1
				result[n] = transformParsedIntoDetails_title(v)
			end
		end
	end
	result.n = n
	return result
end





--- Returns the contents of the specified LOM tag parsed into a single dict-table representing an anime relation entry
-- Used for anime tags inside relatedAnime and similarAnime tags
local function transformParsedIntoDetails_anime(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)
	local attr = aParsedLom.attr or {}
	assert(type(attr) == "table")

	return
	{
		aId = attr.id,
		relation = attr.type,  -- Used only for relatedanime
	}
end





--- Returns the contents of the specified LOM tag parsed into an array-table of anime entries
-- Used for relatedAnime and similarAnime tags
local function transformParsedIntoDetails_animeArray(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)

	local result = {}
	local n = 0
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == "anime") then
				n = n + 1
				result[n] = transformParsedIntoDetails_anime(v)
			end
		end
	end
	result.n = n
	return result
end





--- Returns the contents of the specified LOM tag parsed into a single dict-table representing a recommendation entry
local function transformParsedIntoDetails_recommendation(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)
	local attr = aParsedLom.attr or {}
	assert(type(attr) == "table")
	assert(aParsedLom[2] == nil)  -- We expect only one string part

	return
	{
		uId = attr.uid,
		kind = attr.type,
		text = aParsedLom[1]
	}
end





--- Returns the contents of the specified LOM tag parsed into an array-table of recommendation entries
local function transformParsedIntoDetails_recommendations(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)

	local result = {}
	local n = 0
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == "recommendation") then
				n = n + 1
				result[n] = transformParsedIntoDetails_recommendation(v)
			end
		end
	end
	result.n = n
	return result
end





--- Returns the contents of the specified LOM tag parsed into a single dict-table representing a creator within a <name> tag
local function transformParsedIntoDetails_creatorname(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)
	local attr = aParsedLom.attr or {}
	assert(type(attr) == "table")
	assert(aParsedLom[2] == nil)  -- We expect only one string part

	return
	{
		id = attr.id,
		kind = attr.type,
		name = aParsedLom[1]
	}
end





--- Returns the contents of the specified LOM tag parsed into an array-table of creator entries
local function transformParsedIntoDetails_creators(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)

	local result = {}
	local n = 0
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == "name") then
				n = n + 1
				result[n] = transformParsedIntoDetails_creatorname(v)
			end
		end
	end
	result.n = n
	return result
end





--- Returns the contents of the specified LOM tag parsed into a single dict-table representing a rating
local function transformParsedIntoDetails_rating(aParsedLom)
	assert(type(aParsedLom) == "table")
	local attr = aParsedLom.attr or {}
	assert(type(attr) == "table")
	assert(aParsedLom[2] == nil)  -- We expect only one string part

	return
	{
		count = attr.count,
		value = tonumber(aParsedLom[1]),
	}
end





--- Returns the contents of the specified LOM tag parsed into a ratings entry
local function transformParsedIntoDetails_ratings(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)

	local result = {}
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == "permanent") then
				result.permanent = transformParsedIntoDetails_rating(v)
			elseif (v.tag == "temporary") then
				result.temporary = transformParsedIntoDetails_rating(v)
			elseif (v.tag == "review") then
				result.review = transformParsedIntoDetails_rating(v)
			end
		end
	end
	return result
end





--- Returns the contents of the specified LOM tag parsed into an array-table of resource entries
local function transformParsedIntoDetails_resources(aParsedLom)
	-- TODO
end





--- Returns the contents of the specified LOM tag parsed into a single dict-table representing a voice actor entry
local function transformParsedIntoDetails_seiyuu(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)
	local attr = aParsedLom.attr or {}
	assert(type(attr) == "table")

	return
	{
		vaId = attr.id,
		pictureId = attr.picture,
		name = aParsedLom[1],
		language = attr.language or "jp",
		episodes = attr.ep or attr.episodes,
	}
end





--- Returns the contents of the specified LOM tag parsed into a single dict-table representing a character entry
local function transformParsedIntoDetails_character(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)
	local attr = aParsedLom.attr or {}
	assert(type(attr) == "table")

	local result =
	{
		characterId = attr.id,
		kind = attr.type,
		voiceActors = {n = 0},
	}
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == "name") then
				result.name = transformParsedIntoDetails_string(v)
			elseif (v.tag == "description") then
				result.description = transformParsedIntoDetails_string(v)
			elseif (v.tag == "picture") then
				result.pictureId = transformParsedIntoDetails_string(v)
			elseif (v.tag == "seiyuu") then
				local voiceActor = transformParsedIntoDetails_seiyuu(v)
				if (voiceActor.vaId) then
					result.voiceActors.n = result.voiceActors.n + 1
					result.voiceActors[result.voiceActors.n] = voiceActor
				end
			elseif (v.tag == "charactertype") then
				result.characterTypeId = v.attr.id
			elseif (v.tag == "rating") then
				result.rating =
				{
					numVotes = v.attr.votes,
					value = tonumber(v[1]),
				}
			elseif (v.tag == "gender") then
				result.gender = transformParsedIntoDetails_string(v)
			end
		end
	end
	return result
end





--- Returns the contents of the specified LOM tag parsed into an array-table of character entries
local function transformParsedIntoDetails_characters(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)

	local result = {}
	local n = 0
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == "character") then
				n = n + 1
				result[n] = transformParsedIntoDetails_character(v)
			end
		end
	end
	result.n = n
	return result
end





--- Returns the contents of the specified LOM tag parsed into a single dict-table representing a tag entry
local function transformParsedIntoDetails_tag(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)
	local attr = aParsedLom.attr or {}
	assert(type(attr) == "table")

	return
	{
		tagId = attr.id,
		parentId = attr.parentid,
		weight = attr.weight,
		infobox = attr.infobox,  -- Whether the tag is shown in the main infobox
		name        = transformParsedIntoDetails_getSubtagString(aParsedLom, "name"),
		description = transformParsedIntoDetails_getSubtagString(aParsedLom, "description"),
		picUrl      = transformParsedIntoDetails_getSubtagString(aParsedLom, "picurl"),
	}
end





--- Returns the contents of the specified LOM tag parsed into an array-table of tag entries
local function transformParsedIntoDetails_tags(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)

	local result = {}
	local n = 0
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == "tag") then
				n = n + 1
				result[n] = transformParsedIntoDetails_tag(v)
			end
		end
	end
	result.n = n
	return result
end





--- Returns the contents of the specified LOM tag parsed into a single dict-table representing an episode entry
local function transformParsedIntoDetails_episode(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)
	local attr = aParsedLom.attr
	assert(type(attr) == "table")
	assert(tonumber(attr.id))

	local result = {id = attr.id, titles = {}}
	local n = 0  -- Counter for result.titles[]
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == "epno") then
				result.episodeNumber = v[1]
				result.kind = (v.attr or {}).type
			elseif (v.tag == "length") then
				result.length = tonumber(v[1])
			elseif (v.tag == "title") then
				n = n + 1
				result.titles[n] =
				{
					language = v.attr["xml:lang"],
					title = v[1]
				}
			elseif (v.tag == "summary") then
				result.summary = v[1]
			elseif (v.tag == "rating") then
				result.rating =
				{
					numVotes = (v.attr or {}).votes,
					value = tonumber(v[1]),
				}
			elseif (v.tag == "airdate") then
				result.airDate = v[1]
			end
		end
	end
	return result
end





--- Returns the contents of the specified LOM tag parsed into an array-table of episode entries
local function transformParsedIntoDetails_episodes(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(aParsedLom.tag)

	local result = {}
	local n = 0
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			if (v.tag == "episode") then
				n = n + 1
				result[n] = transformParsedIntoDetails_episode(v)
			end
		end
	end
	result.n = n
	return result
end





--- Fetches AniDB XML for the specified aId
-- Tries the following sources in order (examples for aId = 1234):
--   1. Local file "AniDB/12/1234.xml"  (canonical format)
--   2. Local file "AniDB/012/1234.xml" (used by earlier versions of our requestQueue downloader)
--   3. Local file "AniDB/1234.xml"     (used by earliest versions)
--   4. https://xoft.cz/AniDbMirror/api/get...
--   5. http://api.anidb.net:9001/httpapi...
-- Auto-inflates the result if the server used gzip encoding
-- If the file was requested through API, saves it locally under "AniDB/aIdHundreds/aId.xml"
-- If aShouldSkipCaches is true, only AniDB.net is queried, not the other caches
function M.fetchXml(aId, aShouldSkipCaches)
	assert(tonumber(aId))
	assert(type(aShouldSkipCaches) == "boolean")

	-- Check each source:
	local isReadFromFile = true
	local canonicalFolder = string.format("AniDB/%d", math.floor(aId / 100))
	local canonicalFileName = string.format("%s/%d.xml", canonicalFolder, aId)
	local response
	if not(aShouldSkipCaches) then
		response = readFileContents(canonicalFileName)
		if not(response) then
			response = readFileContents(string.format("AniDB/%d.xml", aId))
		end
		if not(response) then
			response = readFileContents(string.format("AniDB/%.03d/%d.xml", math.floor(aId / 100), aId))
		end
		if not(response) then
			isReadFromFile = false
			response = fetchUrl("https://xoft.cz/AniDbMirror/api/get?id=" .. aId)
		end
	end
	if not(response) then
		response = fetchUrlWithRateLimit(
			"http://api.anidb.net:9001/httpapi?client=anidbxref&clientver=1&protover=1&request=anime&aid=" .. aId,
			gAniDbRateLimiter
		)
	end
	if not(response) then
		return nil, "Cannot fetch details from any source."
	end

	-- Store locally, if requested via API:
	if (response and not(isReadFromFile)) then
		lfs.mkdir("AniDB")
		lfs.mkdir(canonicalFolder)
		local f = io.open(canonicalFileName, "wb")
		if (f) then
			f:write(response)
			f:close()
		end
	end

	return response
end





--- Transforms the LOM-parsed XML API data into our anime details format table
-- Raises an error if the LOM data contains an <error> tag
function M.transformParsedIntoDetails(aParsedLom)
	assert(type(aParsedLom) == "table")
	assert(type(aParsedLom.tag) == "string")
	assert(type(aParsedLom.attr) == "table")
	assert(tonumber(aParsedLom.attr.id))

	-- Check failures:
	if (aParsedLom.tag == "error") then
		error("Error querying the AniDB API: " .. aParsedLom.attr.code .. ": " .. tostring(aParsedLom[1]))
	end
	if (aParsedLom.tag ~= "anime") then
		error("Error parsing the AniDB API: The top level tag is not 'anime', but instead '" .. tostring(aParsedLom.tag) .. "'.")
	end

	local details = {aId = tonumber(aParsedLom.attr.id)}
	for _, v in ipairs(aParsedLom) do
		if (type(v) == "table") then
			local tag = v.tag
			if (tag == "type") then
				details.kind = transformParsedIntoDetails_string(v)
			elseif (tag == "startdate") then
				details.startDate = transformParsedIntoDetails_date(v)
			elseif (tag == "enddate") then
				details.endDate = transformParsedIntoDetails_date(v)
			elseif (tag == "titles") then
				details.titles = transformParsedIntoDetails_titles(v)
			elseif (tag == "relatedanime") then
				details.relatedAnime = transformParsedIntoDetails_animeArray(v)
			elseif (tag == "similaranime") then
				details.similarAnime = transformParsedIntoDetails_animeArray(v)
			elseif (tag == "recommendations") then
				details.recommendations = transformParsedIntoDetails_recommendations(v)
			elseif (tag == "url") then
				details.url = transformParsedIntoDetails_string(v)
			elseif (tag == "creators") then
				details.creators = transformParsedIntoDetails_creators(v)
			elseif (tag == "description") then
				details.description = transformParsedIntoDetails_string(v)
			elseif (tag == "ratings") then
				details.ratings = transformParsedIntoDetails_ratings(v)
			elseif (tag == "picture") then
				details.pictureId = transformParsedIntoDetails_string(v)
			elseif (tag == "resources") then
				details.resources = transformParsedIntoDetails_resources(v)
			elseif (tag == "tags") then
				details.tags = transformParsedIntoDetails_tags(v)
			elseif (tag == "characters") then
				details.characters = transformParsedIntoDetails_characters(v)
			elseif (tag == "episodes") then
				details.episodes = transformParsedIntoDetails_episodes(v)
			end
		end
	end
	return details
end





--- Synchronously downloads the details for the specified anime and updates the DB with the data
-- If aShouldSkipCaches is true, only AniDB.net is queried, not the other caches (local, xoft.cz)
-- Returns true if successful, nil and error message on failure
function M.updateDetailsInDb(aAnimeId, aShouldSkipCaches)
	local xml, msg = M.fetchXml(aAnimeId, aShouldSkipCaches)
	if not(xml) then
		return nil, msg
	end

	local parsedLom, msg = lomParser.parse(xml)
	if not(parsedLom) then
		log("aniDbDetails",
			"FAILED to xml-parse response for anime %d.",
			aAnimeId
		)
		return nil, string.format("Xml parse failed: %s", tostring(msg))
	end

	-- If the API returned an <error> response, parse it and decide what kind of failure it is:
	if (type(parsedLom) ~= "table") then
		log("aniDbDetails",
			"Unknown API response received for anime %d.",
			aAnimeId
		)
		return nil, "Unknown xml format"
	end
	if (parsedLom.tag == "error") then
		local code = tostring((parsedLom.attr or {}).code)
		log("aniDbDetails",
			"ERROR code %s returned for anime %d",
			code, aAnimeId
		)
		return nil, string.format("API error %s", code)
	end

	-- Transform the parsed LOM object into the details table:
	local parsedDetails = M.transformParsedIntoDetails(parsedLom)
	if not(parsedDetails.aId) then
		log("aniDbDetails", "Failed to transform AniDB API XML to details.")
		return nil, "Parsing the details failed"
	end

	-- Store into DB:
	db.storeAnimeDetails(parsedDetails)
	log("aniDbDetails", "Updated anime details for %d", aAnimeId)
	return true
end





return M
