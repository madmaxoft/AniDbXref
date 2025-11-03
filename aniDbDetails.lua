local socket = require("socket.http")
local ltn12 = require("ltn12")
local lxp = require("lxp")
local db = require("db")





local M = {}





--- Fetches AniDB XML for the specified aId
-- Inflates the result if the server used gzip encoding
function M.fetchXml(aId)
	assert(tonumber(aId))

	local url = "http://api.anidb.net:9001/httpapi?client=anidbxref&clientver=1&protover=1&request=anime&aid=" .. aId
	local response = {}
	local ok, code, headers = socket.request{
		url = url,
		sink = ltn12.sink.table(response),
		headers = {
			["User-Agent"] = "AniDbXref/1",
		},
	}
	if (not(ok) or (code ~= 200)) then
		return nil, "HTTP request failed: " .. tostring(code)
	end
	local body = table.concat(response)

	-- Unzip the body, if the server returns it zipped
	if (
		(headers["content-encoding"] == "gzip") or
		(body:sub(1,2) == "\031\139")
	) then
		local zlib = require("zlib")
		return zlib.inflate()(body)
	end

	return body
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
		id = attr.id,
		picture = attr.picture,
		name = aParsedLom[1]
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
		id = attr.id,
		kind = attr.type,
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
				result.voiceActor = transformParsedIntoDetails_seiyuu(v)
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
		id = attr.id,
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





--- Fetches, parses, and stores details for the specified aId
-- Returns the parsed details
function M.updateAnimeDetails(aId)
	assert(tonumber(aId))

	local xml, err = M.fetchXml(aId)
	if not(xml) then
		return nil, err
	end

	local parsedLom = require("lxp.lom").parse(xml)
	local details = M.transformParsedIntoDetails(parsedLom)
	db.storeAnimeDetails(aId, details)
	return details
end





return M
