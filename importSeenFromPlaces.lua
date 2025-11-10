-- importSeenFromPlaces.lua

--[[ Implements importing Seen anime from a Places.sqlite file from Firefox.
Provides the Places.sqlite parser, matcher and session management
--]]





local db = require("db")





local I =
{
	sessions = {},  -- Dict table of id -> session
	nextSessionId = 0,  -- The id to be used for the next new session
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
}





--- Adds all titles matching the specified known server into aOutDict
-- aOutDict is a dict-table of title -> { lastVisitDate = ... }
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
			if (not(aOutDict[title]) or (aOutDict[title].lastVisitDate > lastVisitDate)) then
				aOutDict[title] = { lastVisitDate = lastVisitDate }
			end
		end
	end
	stmt:finalize()
end





--- Parses the Places.sqlite file into an array-table of {title = ..., lastVisitDate = ...}
local function parsePlacesFile(aFileName)
	-- Open the DB:
	local sqlite = require("lsqlite3")
	local dbPlaces = assert(sqlite.open(aFileName, sqlite.OPEN_READONLY))
	dbPlaces:busy_timeout(1000)

	-- Load all seen titles:
	local titles = {}  -- dict-table of all found titles, title = { lastVisitDate = ... }
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

	return result
end





--- Builds a new session for the specified Places.sqlite file
-- Parses the file, matches it up to the DB and adds it into I.currentSessions[]
function I.buildSession(aFileName)
	-- Parse the items and search for candidates:
	local parsed = parsePlacesFile(aFileName)
	for _, seen in ipairs(parsed) do
		seen.candidates = I.searchCandidates(seen.title)
	end

	-- Sort the items by their last visit date:
	table.sort(parsed,
		function(aItem1, aItem2)
			return (aItem1.lastVisitDate < aItem2.lastVisitDate)
		end
	)

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





--- Returns the candidates found using the specified search query
-- The candidates are sorted by their enTitle
function I.searchCandidates(aQuery)
	local result = db.searchAnimeTitles(aQuery)
	table.sort(result, function(aItem1, aItem2)
		return ((aItem1.details.enTitle or "") < (aItem2.details.enTitle or ""))
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
