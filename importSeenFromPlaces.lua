-- importSeenFromPlaces.lua

--[[ Implements importing Seen anime from a Places.sqlite file from Firefox.
Provides the Places.sqlite parser, matcher and session management
--]]





local db = require("db")
local perf = require("perf")
local utils = require("utils")





local I =
{
	sessions = {},  -- Dict table of id -> session
	nextSessionId = 0,  -- The id to be used for the next new session
}





--- Words that we don't want in the search query, since they most often break the search:
local gUnwantedWords =
{
	["the"] = true,
	["a"] = true,
	["an"] = true,
	["of"] = true,
	["and"] = true,
	["season"] = true,
	["part"] = true,
	["ova"] = true,
	["dub"] = true,
	["uncensored"] = true,
	["2nd"] = true,
	["3rd"] = true,
	["4th"] = true,
	["5th"] = true,
	["6th"] = true,
	["7th"] = true,
	["8th"] = true,
	["9th"] = true,
}





--- Replaces dashes in the title with spaces
-- Used to transform most titles found in URLs from "some-title" into "some title"
local function replaceDashesWithSpaces(aTitleWithDashes)
	assert(type(aTitleWithDashes) == "string")

	return string.gsub(aTitleWithDashes, "%-", " ")
end





--- Array-table of known servers
-- sqlPattern is used for matching the SQL rows in a SELECT ... LIKE query
-- titlePattern parses the full URL into a title
-- titleTransform transforms the matched title pattern into a real title that can be searched in the DBs
local knownAnimeServers =
{
	{ sqlPattern = "%animegers.com/watch/%", titleTransform = replaceDashesWithSpaces, titlePattern = "animegers%.com/watch/(.*)%-episode%-" },
	{ sqlPattern = "%9anime.pe/watch/%",     titleTransform = replaceDashesWithSpaces, titlePattern = "9anime%.pe/watch/(.*)%-%d+%?" },
	{ sqlPattern = "%9animetv.to/watch/%",   titleTransform = replaceDashesWithSpaces, titlePattern = "9animetv%.to/watch/(.*)%-%d+%?" },
	{ sqlPattern = "%hianime.to/watch/%",    titleTransform = replaceDashesWithSpaces, titlePattern = "hianime%.to/watch/(.*)%-%d+%?" },
	{ sqlPattern = "%hianimez.to/watch/%",   titleTransform = replaceDashesWithSpaces, titlePattern = "hianimez%.to/watch/(.*)%-%d+%?" },
	{ sqlPattern = "%hianime.ws/watch/%",    titleTransform = replaceDashesWithSpaces, titlePattern = "hianime%.ws/watch/(.*)%-...." },
	{ sqlPattern = "%animekai.to/watch/%",   titleTransform = replaceDashesWithSpaces, titlePattern = "animekai%.to/watch/(.*)%-...." },
}





--- Adds all titles matching the specified known server into aOutDict
-- aOutDict is a dict-table of title -> { url = ..., lastVisitDate = ... }
-- Existing items are replaced only if their lastVisitDate is lower than the existing one
local function addTitlesForSingleServer(aDb, aServerDef, aOutDict)
	assert(aDb)
	assert(aDb.prepare)
	assert(type(aServerDef) == "table")
	assert(type(aServerDef.sqlPattern) == "string")
	assert(aServerDef.titlePattern)

	local stmt = aDb:prepare("SELECT url, last_visit_date FROM moz_places WHERE url LIKE \"" .. aServerDef.sqlPattern .. "\"")
	if not(stmt) then
		error("Failed to prepare import statement for pattern " .. aServerDef.sqlPattern .. ": " .. aDb:errmsg())
	end
	for row in stmt:nrows() do
		local title = string.match(row.url, aServerDef.titlePattern)
		if (title) then
			if (aServerDef.titleTransform) then
				title = aServerDef.titleTransform(title)
			end
			local lastVisitDate = math.floor(row.last_visit_date / 1000000)
			if (not(aOutDict[title]) or (aOutDict[title].lastVisitDate < lastVisitDate)) then
				aOutDict[title] = { url = row.url, lastVisitDate = lastVisitDate }
			end
		end
	end
	stmt:finalize()
end





--- Parses the Places.sqlite file into an array-table of {title = ..., url = ..., lastVisitDate = ...}
local function parsePlacesFile(aFileName)
	-- Open the DB:
	local sqlite = require("lsqlite3")
	local dbPlaces, errCode, errMsg = sqlite.open(
		string.format("file:%s?immutable=1", aFileName),  -- Disable WAL, SHM, locking etc.
		sqlite.OPEN_READONLY + sqlite.OPEN_URI
	)
	if not(dbPlaces) then
		error(string.format("Failed to open file %s: %s / %s", aFileName, tostring(errCode), tostring(errMsg)))
	end
	dbPlaces:busy_timeout(1000)

	-- Load all seen titles:
	local titles = {}  -- dict-table of all found titles, title = { url = ..., lastVisitDate = ... }
	for _, server in ipairs(knownAnimeServers) do
		addTitlesForSingleServer(dbPlaces, server, titles)
	end
	dbPlaces:close()

	-- Convert dict-table to array-table:
	local result = {}
	local n = 0
	for title, v in pairs(titles) do
		n = n + 1
		result[n] = v
		v.title = title
	end
	result.n = n
	table.sort(result,
		function(aItem1, aItem2)
			return (aItem1.title < aItem2.title)
		end
	)

	return result
end





--- Strips unwanted words from a title string.
-- aFilterSet is a dict table of "word" -> true for the unwanted words
local function stripFilteredWords(aTitle, aFilterSet)
	assert(type(aTitle) == "string")
	assert(type(aFilterSet) == "table")

	-- Break into list of words:
	local words = {}
	for word in string.gmatch(aTitle, "%S+") do
		table.insert(words, word)
	end

	-- Filter unwanted words:
	local filteredWords = {}
	for _, word in ipairs(words) do
		if not(aFilterSet[word]) then
			table.insert(filteredWords, word)
		end
	end

	return table.concat(filteredWords, " ")
end





--- Builds a new session for the specified Places.sqlite file
-- Parses the file, matches it up to the DB and adds it into I.currentSessions[]
function I.buildSession(aFileName)
	-- Parse the items and search for candidates:
	local parsed = parsePlacesFile(aFileName)
	local numParsed = parsed.n
	for idx = 1, numParsed do
		local seen = parsed[idx]
		seen.query = stripFilteredWords(seen.title, gUnwantedWords):gsub("(%d+)(%a+)", "%1 %2")
		seen.candidates = I.searchCandidates(seen.title, seen.query)
		if (seen.candidates.n == 1) then
			local candidate = seen.candidates[1]
			if (candidate.details.isSeen == 1) then
				if (tonumber(candidate.details.seenDateYmd) <= tonumber(seen.lastVisitDate)) then
					parsed[idx] = nil  -- Discard, remove later
				end
			end
		end
	end

	-- Remove items that have been discarded:
	local parsed2 = {}
	local n = 0
	for idx = 1, numParsed do
		if (parsed[idx]) then
			n = n + 1
			parsed2[n] = parsed[idx]
		end
	end
	parsed = parsed2
	parsed.n = n
	numParsed = n

	--[[
	-- Sort the items by their last visit date:
	table.sort(parsed,
		function(aItem1, aItem2)
			return (aItem1.lastVisitDate < aItem2.lastVisitDate)
		end
	)
	--]]

	-- Add it as a session
	local session =
	{
		id = I.nextSessionId,
		items = parsed,
	}
	I.nextSessionId = I.nextSessionId + 1
	I.sessions[session.id] = session

	return session
end





--- Returns the candidates found for the specified query
-- The candidates are sorted by their enTitle
function I.searchCandidates(aTitle, aQuery)
	assert(type(aTitle) == "string")
	assert(type(aQuery) == "string")

	local timer = perf.newTimer("searchCandidates")
	-- Use raw search for speed:
	local result = db.searchAnimeTitlesRaw(aQuery)
	timer("dbSearch")

	-- Only add titles and base details:
	for _, res in ipairs(result) do
		res.details = db.getAnimeDetails_base(res.aId) or {}
	end
	timer("dbDetails")
	for _, res in ipairs(result) do
		res.details.titles = db.getAnimeDetails_titles(res.aId)
		res.bestTitle = utils.pickBestTitle(res.details.titles or {}, "en")
		res.areTitlesEqual = utils.areMultiTitlesEqual(aTitle, res.details.titles or {})
	end
	timer("dbTitles")
	table.sort(result, function(aItem1, aItem2)
		return ((aItem1.bestTitle or "") < (aItem2.bestTitle or ""))
	end)
	return result
end





--- Returns the session identified by the specified id
function I.getSession(aId)
	return I.sessions[aId]
end





--- Removes the session from the global registry
function I.removeSession(aId)
	I.sessions[aId] = nil
end





return I
