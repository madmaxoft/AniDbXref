-- db.lua
-- Database access module

local sqlite3 = require("lsqlite3")
local perf = require("perf")
local log = require("logger").log
local utils = require("utils")
local titleSearch = require("titleSearch")

local db = {}
local gDB = nil  -- The actual DB connection object

--- The in-memory search engine for titles
local gTitleSearch

--- Gloal flag that TitleSearch initialization should be skipped (used for faster test startup):
local gDbSkipInitTitleSearch = gDbSkipInitTitleSearch or false

local unpack = unpack or table.unpack  -- Compatibility between Lua 5.1 and LuaJIT





--- Checks SQLite result codes and throws errors
-- aContext is a string description of where the check is happenning, for logging purposes
local function checkSql(aResultCode, aContext)
	assert(type(aContext) == "string")

	if (
		(aResultCode ~= sqlite3.OK) and
		(aResultCode ~= sqlite3.DONE) and
		(aResultCode ~= sqlite3.ROW)
	) then
		error(string.format("SQLite error in %s: %s (%s)",
			aContext or "unknown",
			tostring(aResultCode),
			gDB:errmsg()
		))
	end
end





--- Ensures DB schema exists and upgrades if needed
local function initialize()
	assert(gDB == nil)

	-- Backup userdata safely before opening
	local dbUpgrade = require("dbUpgrade")
	dbUpgrade.backupDbFile("userData.sqlite")

	-- Reopen fresh connection after backup
	gDB = sqlite3.open("anime.sqlite")
	gDB:busy_timeout(1000)
	checkSql(gDB:exec("PRAGMA foreign_keys = ON;"), "initialize.fkon")
	checkSql(gDB:exec([[ ATTACH 'userData.sqlite' AS UserData ]]), "initialize.attachUserData")
	checkSql(gDB:exec([[ ATTACH 'picture.sqlite' AS Pic ]]), "initialize.attachPic")

	-- Now safely run the upgrade
	dbUpgrade.upgradeIfNeeded(gDB, "anime.sqlite")

	gTitleSearch = titleSearch.new()
	if not(gDbSkipInitTitleSearch) then
		log("db", "Initializing titleSearch...")
		local allTitles = db.getArrayFromQuery("SELECT aId, language, title FROM AnimeTitle", {}, "allTitles")
		for _, title in ipairs(allTitles) do
			if ((title.language == "en") or (title.language == "x-jat")) then
				gTitleSearch:insert(title.title, title.aId)
			end
		end
	end
	log("db", "DB init done.")
end





--- Adds the specified tags to the global Tag table
-- aTags is an array-table of {tagId= ..., parentId = ..., name = ..., description = ..., pictureId = ..., ...}
function db.addGlobalTags(aTags)
	assert(type(aTags) == "table")
	assert(gDB ~= nil)

	local stmt = gDB:prepare([[
		INSERT INTO Tag
			(tagId, parentId, name, description, pictureId)
		VALUES
			(?, ?, ?, ?, ?)
		ON CONFLICT(tagId) DO UPDATE SET
			parentId = excluded.parentId,
			name = excluded.name,
			description = excluded.description,
			pictureId = excluded.pictureId
		]]
	)
	if not(stmt) then
		error(string.format("Failed to prepare statement for inserting Tags: %s", gDB:errmsg()))
	end

	for _, tag in ipairs(aTags) do
		checkSql(stmt:bind_values(tag.tagId, tag.parentId, tag.name, tag.description, tag.pictureId), "addGlobalTags.bind")
		checkSql(stmt:step(), "addGlobalTags.step")
		checkSql(stmt:reset(), "addGlobalTags.reset")
	end
	checkSql(stmt:finalize(), "addGlobalTags.finalize")
end





--- Adds the specified IDs into the Seen table
-- aRawSeen is an array-table of { aId = <id>, seen = <timestamp> }
-- See also rawSeenIdsFrom() that produces such a table
-- Used when importing via remote API
-- Returns true on success, nil and message on failure
function db.addRawSeenIds(aRawSeen)
	assert(type(aRawSeen) == "table")
	assert(gDB ~= nil)

	local stmt = gDB:prepare([[
		INSERT OR IGNORE INTO Seen
			(aId, seenDate)
		VALUES
			(?, ?)
		]]
	)
	if not(stmt) then
		return nil, string.format("Failed to prepare statement for inserting Seen: %s", gDB:errmsg())
	end

	local numIgnored = 0
	for _, s in ipairs(aRawSeen) do
		if (s.aId and s.seenDate) then
			checkSql(stmt:bind_values(s.aId, s.seenDate), "addRawSeenIds.bind")
			checkSql(stmt:step(), "addRawSeenIds.step")
			checkSql(stmt:reset(), "addRawSeenIds.reset")
		else
			numIgnored = numIgnored + 1
		end
	end
	if (numIgnored > 0) then
		log("db.addRawSeenIds", "Ignored %d records out of %s", numIgnored, tostring(aRawSeen.n or "<unknown>"))
	end
	checkSql(stmt:finalize(), "addRawSeenIds.finalize")
	return true
end





--- Adds the specified watchlist items into the Watchlist table
-- aRawWatchlist is an array-table of { aId = <id>, caption = ..., itemId = ..., ... }
-- See also rawWatchlist() that produces such a table
-- Used when importing via remote API
-- Returns true on success, nil and message on failure
function db.addRawWatchlist(aRawWatchlist)
	assert(type(aRawWatchlist) == "table")
	assert(gDB ~= nil)

	local stmt = gDB:prepare([[
		INSERT OR IGNORE INTO Watchlist
			(dayOfWeek, time, caption, aId, watchlistSeason)
		VALUES
			(?, ?, ?, ?, ?)
		ON CONFLICT(watchlistSeason, dayOfWeek, caption) DO NOTHING;
		]]
	)
	if not(stmt) then
		return nil, string.format("Failed to prepare statement for inserting Watchlist: %s", gDB:errmsg())
	end

	local numIgnored = 0
	for _, w in ipairs(aRawWatchlist) do
		if (w.watchlistSeason) then
			checkSql(stmt:bind_values(w.dayOfWeek, w.time, w.caption, w.aId, w.watchlistSeason), "addRawWatchlist.bind")
			checkSql(stmt:step(), "addRawWatchlist.step")
			checkSql(stmt:reset(), "addRawWatchlist.reset")
		else
			numIgnored = numIgnored + 1
		end
	end
	if (numIgnored > 0) then
		log("db.addRawWatchlist", "Ignored %d records out of %s", numIgnored, tostring(aRawWatchlist.n or "<unknown>"))
	end
	checkSql(stmt:finalize(), "addRawWatchlist.finalize")
	return true
end





--- Adds the specified anime to the user's watchlist
-- Queries the details to add them into the watchlist along the anime
function db.addToWatchlist(aId, aWatchlistSeason, aUtcSecondsSinceWeekStart)
	assert(type(aId) == "number")
	assert(type(aWatchlistSeason) == "string")
	assert(type(aUtcSecondsSinceWeekStart) == "number")

	-- Query the details:
	local details, msg = db.getAnimeDetails(aId)
	if not(details) then
		return nil, "Failed to query anime details: " .. tostring(msg)
	end

	local caption = utils.pickBestTitle(details.titles, "en") or tostring(aId)
	db.execBoundStatement([[
		INSERT INTO UserData.Watchlist
			(watchlistSeason, utcSecondsSinceWeekStart, aId, url, caption)
		VALUES
			(?, ?, ?, ?, ?)
		ON CONFLICT(watchlistSeason, utcSecondsSinceWeekStart, caption) DO NOTHING;
		]],
		{ aWatchlistSeason, aUtcSecondsSinceWeekStart, aId, url, caption },
		"addToWatchlist"
	)
	return true
end





--- Returns an array-table of all anime IDs in the DB.
-- Returns an empty array on empty DB.
-- Returns nil and error message on error.
function db.allAnimeIDs()
	-- Query the DB:
	local dictArray, msg = db.getArrayFromQuery("SELECT aId FROM Anime", {}, "allAnimeIDs")
	if not(dictArray) then
		return nil, "Failed to query DB: " .. tostring(msg)
	end

	-- dictArray is { {aId = ...}, {aId = ...}, ... }
	-- Convert the array of dict-tables into a plain array of numbers:
	local res = {}
	for idx, idRec in ipairs(dictArray) do
		res[idx] = idRec.aId
	end
	res.n = dictArray.n
	return res
end





--- Returns an array-table of all config values, as {identifier = "", dbValue = ""} items
-- Returns an empty array on empty DB.
-- Returns nil and error message on error.
function db.allConfigValues()
	return db.getArrayFromQuery("SELECT * FROM UserData.Config", {}, "allConfigValues")
end





--- Returns an array-table of all the anime in the specified season
-- Each item contains the base details and an array of titles
-- aSeason is a season specification, such as "2026-1" for winter 2026
function db.animeInSeason(aSeason)
	assert(type(aSeason) == "string")

	local seasonBounds, msg = utils.seasonToYmdBounds(aSeason)
	if not(seasonBounds) then
		return nil, string.format("Unknown season bounds: %s", tostring(msg))
	end

	-- Query base details:
	local res = db.getArrayFromQuery([[
		SELECT
			AnimeBaseDetails.*,
			CASE WHEN Seen.aId IS NOT NULL THEN 1 ELSE 0 END AS isSeen,
			Seen.seenDate AS seenDate
		FROM AnimeBaseDetails
		LEFT JOIN Seen ON (AnimeBaseDetails.aId = Seen.aId)
		WHERE length(startDate) = 10 AND startDate >= ? AND startDate <= ?
	]], {seasonBounds.startDateYmd, seasonBounds.endDateYmd}, "animeInSeason.baseDetails")
	local byId = {}  -- dict of aId -> anime
	for _, anime in ipairs(res) do
		byId[anime.aId] = anime
		anime.isSeen = (anime.isSeen == "1") or (anime.isSeen == 1)
	end

	-- Query titles:
	local titles = db.getArrayFromQuery([[
		SELECT
			AnimeTitle.aId AS aId,
			AnimeTitle.title AS title,
			AnimeTitle.kind AS kind,
			AnimeTitle.language AS language
		FROM AnimeTitle
		LEFT JOIN AnimeBaseDetails ON AnimeTitle.aId = AnimeBaseDetails.aId
		WHERE length(AnimeBaseDetails.startDate) = 10 AND AnimeBaseDetails.startDate >= ? AND AnimeBaseDetails.startDate <= ?
	]], {seasonBounds.startDateYmd, seasonBounds.endDateYmd}, "animeInSeason.titles")
	for _, title in ipairs(titles) do
		local titles = byId[title.aId].titles or {n = 0}
		titles.n = titles.n + 1
		titles[titles.n] = title
		byId[title.aId].titles = titles
	end

	-- Enrich with schedule information, if available:
	local n = res.n
	db.forEachRowInStatement("SELECT * FROM WeeklySchedule WHERE watchlistSeason = ?",
		{aSeason}, "animeInSeason.schedule",
		function(sch)
			local ani = byId[sch.aId]
			if not(ani) then
				ani, msg = db.getAnimeDetails_base(sch.aId)
				if not(ani) then
					log("db", "animeInSeason: Failed to query base details for watchlist item %s: %s",
						tostring(sch.aId), tostring(msg)
					)
					return
				end
				ani.titles = db.getAnimeDetails_titles(sch.aId)
				n = n + 1
				res[n] = ani
				byId[sch.aId] = ani
			end
			assert(type(ani) == "table")
			ani.schedule = sch
		end
	)
	res.n = n

	return res
end





--- Begins a DB transaction
-- Should not be normally used, only meant as optimization for offline tools for doing bulk data modifications
-- After calling this, the code is expected to eventually call commitTransaction()
-- aOptionalName is only for logging purposes
function db.beginTransaction(aOptionalName)
	assert(gDB ~= nil)

	checkSql(gDB:exec("BEGIN TRANSACTION"), "beginTransaction." .. tostring(aOptionalName))
end





--- Collects CREATE INDEX statements for the whole DB.
--  Drops them, and returns their definitions as an array-table of { name = <indexName>, sql = <createIndexSql> }
-- Recreate the indices later by calling db.recreateIndices(returned)
function db.collectAndDropIndices()
	assert(gDB ~= nil)

	-- Query all indices:
	local result = db.getArrayFromQuery([[
		SELECT name, sql
		FROM sqlite_master
		WHERE type = 'index'
		  AND tbl_name IS NOT NULL
		  AND sql IS NOT NULL;
	]])

	-- Drop the actual indices:
	for _, row in ipairs (result) do
		assert(type(row.name) == "string")
		checkSql(gDB:exec(string.format("DROP INDEX IF EXISTS \"%s\";", row.name)), "dropIndex." .. row.name or "<nil>")
	end

	return result
end





--- Commits a DB transaction, previously started with beginTransaction()
-- Should not be normally used, only meant as optimization for offline tools for doing bulk data modifications
-- aOptionalName is only for logging purposes
function db.commitTransaction(aOptionalName)
	assert(gDB ~= nil)

	checkSql(gDB:exec("COMMIT"), "commitTransaction." .. tostring(aOptionalName))
end





--- Executes the specified statement, binding the specified values to it.
-- aDescription is used for error logging.
function db.execBoundStatement(aSql, aValuesToBind, aDescription)
	assert(type(aSql) == "string")
	assert(type(aValuesToBind) == "table")
	assert(type(aDescription) == "string")
	assert(gDB ~= nil)

	local stmt = gDB:prepare(aSql)
	if not(stmt) then
		error("Failed to prepare statement (" .. aDescription .. "): " .. gDB:errmsg())
	end
	checkSql(stmt:bind_values(unpack(aValuesToBind)), aDescription .. ".bind")
	checkSql(stmt:step(), aDescription .. ".step")
	checkSql(stmt:finalize(), aDescription .. ".finalize")
end




--- Calls the specified callback for each row of the executed DB statement
-- Binds the values before executing the statement
-- If the callback returns true, the execution is aborted
function db.forEachRowInStatement(aSql, aValuesToBind, aDescription, aCallback)
	assert(type(aSql) == "string")
	assert(type(aValuesToBind) == "table")
	assert(type(aDescription) == "string")
	assert(aCallback)
	assert(gDB ~= nil)

	local stmt = gDB:prepare(aSql)
	if not(stmt) then
		error("Failed to prepare statement (" .. aDescription .. "): " .. gDB:errmsg())
	end
	if ((aValuesToBind) and (aValuesToBind[1])) then
		checkSql(stmt:bind_values(unpack(aValuesToBind)), aDescription .. ".bind")
	end
	for row in stmt:nrows() do
		if (aCallback(row)) then
			break
		end
	end
	checkSql(stmt:finalize(), aDescription .. ".finalize")
end





--- Gets full details for a single anime
function db.getAnimeDetails(aId)
	assert(tonumber(aId))

	-- Get the base details:
	local result, msg = db.getAnimeDetails_base(aId)
	if not(result) then
		return nil, "Failed to query base details: " .. tostring(msg)
	end

	-- Get the domain-specific details:
	result.characters = db.getAnimeDetails_characters(aId)
	result.creators = db.getAnimeDetails_creators(aId)
	result.episodes = db.getAnimeDetails_episodes(aId)
	result.recommendations = db.getAnimeDetails_recommendations(aId)
	result.relatedAnime = db.getAnimeDetails_relatedAnime(aId)
	result.similarAnime = db.getAnimeDetails_similarAnime(aId)
	result.tags = db.getAnimeDetails_tags(aId)
	result.titles = db.getAnimeDetails_titles(aId)

	-- Get the most useful titles:
	result.enTitle = db.pickBestTitle(result.titles, "en")
	result.jaTitle = db.pickBestTitle(result.titles, "ja")
	result.xjatTitle = db.pickBestTitle(result.titles, "x-jat")

	return result
end





--- Returns the base details about the anime (AnimeBaseDetails table) combined with the Seen table
-- Returns nil and error message on failure
function db.getAnimeDetails_base(aId)
	assert(tonumber(aId))

	local result, msg = db.getArrayFromQuery([[
		SELECT
			abd.aId AS aId,
			abd.startDate AS startDate,
			abd.endDate AS endDate,
			abd.kind AS kind,
			abd.numEpisodes AS numEpisodes,
			abd.url AS url,
			abd.description AS description,
			abd.pictureId AS pictureId,
			abd.lastUpdated AS lastUpdated,
			CASE WHEN s.aId IS NOT NULL THEN 1 ELSE 0 END AS isSeen,
			s.seenDate AS seenDateYmd
		FROM AnimeBaseDetails AS abd
		LEFT JOIN Seen AS s ON (abd.aId = s.aId)
		WHERE abd.aId = ? LIMIT 1;
	]], {aId}, "getAnimeDetails.BaseDetails")
	if (not(result) or not(result[1])) then
		log("db", "Failed to query base details for aId %s: %s", tostring(aId), tostring(msg))
		return nil, "Base details query failed: " .. tostring(msg)
	end
	return result[1]
end





--- Returns the characters for the specified anime, as the details-table
function db.getAnimeDetails_characters(aId)
	assert(tonumber(aId))

	-- Query bare characers:
	local characters = db.getArrayFromQuery([[
		SELECT
			ac.acId,
			ac.characterId,
			ac.notes,
			ac.pictureId,
			c.name,
			c.gender,
			c.description,
			c.pictureId AS characterPictureId
		FROM AnimeCharacter AS ac
		JOIN Character AS c ON c.characterId = ac.characterId
		WHERE ac.aId = ?
	]], {aId}, "getAnimeDetails_characters.ch")

	-- Add key-based lookup, coallesce pictureId:
	local acIds = {}
	local byAcId = {}
	local n = 0
	for _, ch in ipairs(characters) do
		byAcId[ch.acId] = ch
		ch.pictureId = ch.characterPictureId or ch.pictureId
		n = n + 1
		acIds[n] = ch.acId
	end

	-- Query VoiceActors:
	local voiceActors = db.getArrayFromQuery([[
		SELECT
			acva.vaId,
			va.name,
			va.pictureId,
			acva.language,
			acva.episodes,
			acva.notes,
			acva.acId
		FROM AnimeCharacterVoiceActor AS acva
		JOIN VoiceActor AS va ON va.vaId = acva.vaId
		WHERE acva.acId IN (
			SELECT ac.acId
			FROM AnimeCharacter ac
			WHERE ac.aId = ?
		)
	]], {aId}, "getAnimeDetails_characters.va")

	-- Extend characters with data from voiceActors:
	for _, va in ipairs(voiceActors) do
		local ch = byAcId[va.acId]
		if (ch) then
			ch.voiceActors = ch.voiceActors or {n = 0}
			ch.voiceActors.n = ch.voiceActors.n + 1
			ch.voiceActors[ch.voiceActors.n] = va
		else
			log("db", "VA not found in characters: %s (name %s)", tostring(va.acId), tostring(va.name))
		end
	end
	return characters
end





--- Returns the creators for the specified anime, as the details-table
function db.getAnimeDetails_creators(aId)
	assert(tonumber(aId))

	return db.getArrayFromQuery("SELECT * FROM AnimeCreator WHERE aId = ?", {aId}, "getAnimeDetails_creators")
end





--- Returns the episodes for the specified anime, as the details-table
function db.getAnimeDetails_episodes(aId)
	assert(tonumber(aId))

	local rows = db.getArrayFromQuery([[
		SELECT
			epi.*,
			title.title    AS title,
			title.language AS language
		FROM AnimeEpisode AS epi
		LEFT JOIN AnimeEpisodeTitle AS title
			ON title.aId = epi.aId
			AND title.episodeId = epi.id
		WHERE epi.aId = ?
		ORDER BY epi.id
	]], {aId}, "getAnimeDetails_episodes")

	local result = {}
	local lastId
	local cur

	for _, row in ipairs(rows) do
		if (row.id ~= lastId) then
			cur = {
				id = row.id,
				episodeNumber = row.episodeNumber,
				kind = row.kind,
				length = row.length,
				airDate = row.airDate,
				titles = {n = 0}
			}
			table.insert(result, cur)
			lastId = row.id
		end

		-- Only add title if present (LEFT JOIN can produce nulls):
		if (row.title) then
			cur.titles.n = cur.titles.n + 1
			cur.titles[cur.titles.n] =
			{
				title = row.title,
				language = row.language,
			}
		end
	end
	result.n = #result

	return result
end





--- Returns the recommendations for the specified anime, as the details-table
function db.getAnimeDetails_recommendations(aId)
	assert(tonumber(aId))

	return db.getArrayFromQuery("SELECT * FROM AnimeRecommendation WHERE aId = ?", {aId}, "getAnimeDetails_recommendations")
end





--- Returns the relatedAnime for the specified anime, as the details-table
function db.getAnimeDetails_relatedAnime(aId)
	assert(tonumber(aId))

	local related, msg = db.getArrayFromQuery(
		[[
			SELECT
				r.relatedAid AS relatedAid,
				r.relation AS relation,
				a.*,
				t.title AS title,
				t.kind AS titleKind,
				t.language AS titleLanguage,
				CASE WHEN s.aId IS NOT NULL THEN 1 ELSE 0 END AS isSeen,
				s.seenDate AS seenDate
			FROM AnimeRelated AS r
			JOIN AnimeBaseDetails AS a ON a.aId = r.relatedAid
			LEFT JOIN AnimeTitle AS t ON t.aId = a.aId
			LEFT JOIN Seen AS s
				ON s.aId = r.relatedAid
			WHERE r.aId = ?
		]],
		{aId}, "getAnimeDetails_related"
	)
	if not(related) then
		log("db", "Failed to query related anime: %s", tostring(msg))
		return nil
	end

	local result = {n = 0}
	local byId = {}
	for _, row in ipairs(related) do
		local item = byId[row.relatedAid]
		if not(item) then
			item = row
			item.titles = {n = 0}
			byId[row.relatedAid] = item
			result.n = result.n + 1
			result[result.n] = item
		end

		if (row.title) then
			item.titles.n = item.titles.n + 1
			item.titles[item.titles.n] =
			{
				title = row.title,
				language = row.titleLanguage,
				kind = row.titleKind,
			}
		end
	end

	return result
end





--- Returns the X for the specified anime, as the details-table
function db.getAnimeDetails_similarAnime(aId)
	assert(tonumber(aId))

	local similar, msg = db.getArrayFromQuery(
		[[
			SELECT
				sim.similarAid AS similarAid,
				a.*,
				t.title AS title,
				t.kind AS titleKind,
				t.language AS titleLanguage,
				CASE WHEN s.aId IS NOT NULL THEN 1 ELSE 0 END AS isSeen,
				s.seenDate AS seenDate
			FROM AnimeSimilar AS sim
			JOIN AnimeBaseDetails AS a ON a.aId = sim.similarAid
			LEFT JOIN AnimeTitle AS t ON t.aId = a.aId
			LEFT JOIN Seen AS s
				ON s.aId = sim.similarAid
			WHERE sim.aId = ?
		]],
		{aId}, "getAnimeDetails_similar"
	)
	if not(similar) then
		log("db", "Failed to query similar anime: %s", tostring(msg))
		return nil
	end

	local result = {n = 0}
	local byId = {}
	for _, row in ipairs(similar) do
		local item = byId[row.similarAid]
		if not(item) then
			item = row
			item.titles = {n = 0}
			byId[row.similarAid] = item
			result.n = result.n + 1
			result[result.n] = item
		end

		if (row.title) then
			item.titles.n = item.titles.n + 1
			item.titles[item.titles.n] =
			{
				title = row.title,
				language = row.titleLanguage,
				kind = row.titleKind,
			}
		end
	end

	return result
end





--- Returns the X for the specified anime, as the details-table
function db.getAnimeDetails_tags(aId)
	assert(tonumber(aId))

	return db.getArrayFromQuery([[
		SELECT
			AnimeTag.tagId AS tagId,
			AnimeTag.weight AS weight,
			Tag.name AS name,
			Tag.description AS description
		FROM AnimeTag
		LEFT JOIN Tag ON Tag.tagId = AnimeTag.tagId
		WHERE aId = ?
	]], {aId}, "getAnimeDetails_tags")
end





--- Returns the X for the specified anime, as the details-table
function db.getAnimeDetails_titles(aId)
	assert(tonumber(aId))

	return db.getArrayFromQuery("SELECT * FROM AnimeTitle WHERE aId = ?", {aId}, "getAnimeDetails_title")
end





--- Runs the specified SQL query, binding the specified values to it, and returns the results as an array-table of dict-tables
-- aDescription is used for error logging.
function db.getArrayFromQuery(aSql, aValuesToBind, aDescription)
	assert(gDB ~= nil)
	assert(type(aSql) == "string")
	assert(type(aValuesToBind) == "table" or not(aValuesToBind))
	if not(aDescription) then
		aDescription = debug.getinfo(1, 'S').source
	end

	local stmt = gDB:prepare(aSql)
	if not(stmt) then
		error("Failed to prepare statement (" .. aDescription .. "): " .. gDB:errmsg())
	end
	if ((aValuesToBind) and (aValuesToBind[1])) then
		checkSql(stmt:bind_values(unpack(aValuesToBind)), aDescription .. ".bind")
	end
	local result = {}
	local n = 0
	for row in stmt:nrows() do
		n = n + 1
		result[n] = row
	end
	result.n = n
	checkSql(stmt:finalize(), aDescription .. ".finalize")

	return result
end





--- Returns the last DB update timestamp, or 0 if none
function db.getLastAniDbUpdate()
	assert(gDB ~= nil)

	local stmt = gDB:prepare("SELECT value FROM KeyValue WHERE key = 'lastAniDbUpdate';")
	if (not stmt) then
		return 0
	end
	local ts = 0
	for row in stmt:nrows() do
		ts = tonumber(row.value) or 0
	end
	stmt:finalize()
	return ts
end




--- Returns an array-table of all seen Anime
-- Each item is a table {aId = ..., seenDate = ...}
function db.getSeenAnime()
	assert(gDB ~= nil)

	return db.getArrayFromQuery("SELECT aId, seenDate FROM Seen", {}, "getSeenAnime")
end





--- Returns an array-table of all seen anime, together with basic details, suitable for display on the homepage
function db.getSeenAnimeForHomepage()
	assert(gDB ~= nil)

	local rows = db.getArrayFromQuery([[
		SELECT
			s.aId AS aId,
			s.seenDate AS seenDate,
			d.startDate AS startDate,
			d.endDate AS endDate,
			d.numEpisodes AS numEpisodes,
			d.pictureId AS pictureId,
			t.language AS language,
			t.kind AS kind,
			t.title AS title
		FROM Seen s
		LEFT JOIN AnimeBaseDetails d ON d.aId = s.aId
		LEFT JOIN AnimeTitle t ON t.aId = s.aId
		ORDER BY s.seenDate DESC, t.language, t.kind
	]])

	-- Process the returned data - collapse multiple titles for a single anime:
	local animeById = {}
	for _, row in ipairs(rows) do
		local a = animeById[row.aId]
		if not(a) then
			a =
			{
				aId = row.aId,
				seenDate = row.seenDate,
				startDate = row.startDate,
				endDate = row.endDate,
				numEpisodes = row.numEpisodes,
				pictureId = row.pictureId,
				titles = { n = 0 }
			}
			animeById[row.aId] = a
		end

		if (row.title) then
			local titles = a.titles
			titles.n = titles.n + 1
			titles[titles.n] =
			{
				language = row.language,
				kind = row.kind,
				title = row.title
			}
		end
	end

	-- Convert dictionary to array-table, pick best titles:
	local result = {}
	local n = 0
	for _, a in pairs(animeById) do
		a.enTitle = db.pickBestTitle(a.titles, "en")
		a.jaTitle = db.pickBestTitle(a.titles, "ja")
		a.xjatTitle = db.pickBestTitle(a.titles, "x-jat")
		n = n + 1
		result[n] = a
	end
	result.n = n

	return result
end





--- Returns an array-table of anime aIds that have been marked as seen but have no details stored in the DB
function db.getSeenWithoutDetails()
	assert(gDB ~= nil)

	local stmt = gDB:prepare([[
		SELECT s.aId
		FROM Seen AS s
		WHERE NOT EXISTS (
			SELECT 1
			FROM AnimeBaseDetails AS b
			WHERE b.aId = s.aId
		);
	]])
	if not(stmt) then
		error("SQL prepare failed (getSeenWithoutDetails): " .. gDB:errmsg())
	end
	local result = {}
	local n = 0
	for row in stmt:nrows() do
		n = n + 1
		result[n] = row.aId
	end
	result.n = n
	return result
end





--- Returns the details on the specified voice actor, as needed for the details page
-- Return nil if not found
function db.getVoiceActorDetails(aVoiceActorId)
	assert(gDB ~= nil)
	assert(tonumber(aVoiceActorId))

	local baseDetails = db.getArrayFromQuery("SELECT * FROM VoiceActor WHERE vaId = ?", {aVoiceActorId}, "getVoiceActorDetails")
	if (not(baseDetails) or (baseDetails.n ~= 1)) then
		return nil
	end
	local result = baseDetails[1]

	-- Load all the characters:
	result.characters = db.getArrayFromQuery([[
		SELECT
			acva.language,
			acva.episodes,
			acva.notes AS vaNotes,

			c.characterId,
			c.name,
			c.description,
			c.pictureId,

			ac.aId,
			abd.startDate AS animeStartDate,
			abd.endDate AS animeEndDate,
			CASE WHEN s.aId IS NOT NULL THEN 1 ELSE 0 END AS isSeen,
			s.seenDate AS seenDate

		FROM AnimeCharacterVoiceActor acva
		JOIN AnimeCharacter ac    ON ac.acId = acva.acId
		JOIN Character c          ON c.characterId = ac.characterId
		JOIN AnimeBaseDetails abd ON abd.aId = ac.aId
		LEFT JOIN Seen s          ON s.aId = ac.aId
		WHERE acva.vaId = ?
	]], {aVoiceActorId}, "getVoiceActorDetails.characters")

	-- Add titles for the anime through a subquery:
	local titles = db.getArrayFromQuery([[
		SELECT *
		FROM AnimeTitle
		WHERE aId IN (
			SELECT DISTINCT ac.aId
			FROM AnimeCharacterVoiceActor acva
			JOIN AnimeCharacter ac ON ac.acId = acva.acId
			WHERE acva.vaId = ?
		)
	]], {aVoiceActorId}, "getVoiceActorDetails.animeTitles")
	local titleByAnime = {}
	for _, title in ipairs(titles) do
		titleByAnime[title.aId] = titleByAnime[title.aId] or {n = 0}
		titleByAnime[title.aId].n = titleByAnime[title.aId].n + 1
		titleByAnime[title.aId][titleByAnime[title.aId].n] = title
	end
	for _, ch in ipairs(result.characters) do
		ch.isSeen = (ch.isSeen == "1") or (ch.isSeen == 1)
		ch.animeTitles = titleByAnime[ch.aId]
		ch.enTitle = db.pickBestTitle(titleByAnime[ch.aId], "en")
		ch.jpTitle = db.pickBestTitle(titleByAnime[ch.aId], "jp")
		ch.xjatTitle = db.pickBestTitle(titleByAnime[ch.aId], "x-jat")
	end

	return result
end





--- Returns the voice actors currently stored in the DB, together with the number of characters they voiced
function db.getVoiceActors()
	return db.getArrayFromQuery([[
		SELECT
			va.*,
			COUNT(acva.acId) AS numCharacters,
			COUNT(DISTINCT s.aId) AS numSeenAnime
		FROM VoiceActor AS va
		LEFT JOIN AnimeCharacterVoiceActor AS acva
			ON acva.vaId = va.vaId
		LEFT JOIN AnimeCharacter AS ac
			ON ac.acId = acva.acId
		LEFT JOIN Seen AS s
			ON s.aId = ac.aId
		GROUP BY va.vaId
	]], {}, "getVoiceActors")
end





--- Returns true if the base AniDB data (Anime, AnimeTitle tables) have been populated
function db.hasBaseAniDbData()
	local stmt = gDB:prepare("SELECT COUNT(aId) as cnt FROM Anime")
	if not(stmt) then
		error("SQL prepare failed (hasBaseAniDbData): " .. gDB:errmsg())
	end
	for row in stmt:nrows() do
		if (row.cnt > 0) then
			return true
		end
	end
	checkSql(stmt:finalize(), "hasBaseAniDbData.finalize")
	return false
end





--- Returns true if the specified Anime has an entry in the AnimeDetails table (and so is supposed
-- to have had its details queried from AniDB previously)
function db.hasDetails(aId)
	assert(gDB ~= nil)
	assert(type(aId) == "number")

	local stmt = gDB:prepare("SELECT COUNT(aId) as cnt FROM AnimeDetails WHERE aId = ?")
	if not(stmt) then
		error("SQL prepare failed (hasBaseAniDbData): " .. gDB:errmsg())
	end
	checkSql(stmt:bind_values(aId), "hasDetails.bind")
	for row in stmt:nrows() do
		if (row.cnt > 0) then
			return true
		end
	end
	checkSql(stmt:finalize(), "hasDetails.finalize")
	return false
end





--- Removes the anime from the Seen table
function db.markAnimeNotSeen(aId)
	assert(type(aId) == "number")

	db.execBoundStatement(
		"DELETE FROM Seen WHERE aId = ?",
		{aId},
		"markAnimeNotSeen"
	)
end





--- Marks an anime as seen
function db.markAnimeSeen(aId, aDateTime)
	assert(type(aId) == "number")
	if not(aDateTime) then
		aDateTime = os.time()
	end
	assert(type(aDateTime) == "number")
	db.execBoundStatement(
		"INSERT OR REPLACE INTO Seen (aId, seenDate) VALUES (?, ?)",
		{aId, aDateTime},
		"markAnimeSeen"
	)
end





--- Returns the "best" title from those specified, limited to the specified language
-- Returns nil if none found.
-- Prefers main title, then official title, then synonyms and last shorts
function db.pickBestTitle(aTitlesFromDb, aLanguage)
	assert(type(aTitlesFromDb) == "table")
	assert(type(aLanguage) == "string")

	local titles = {}
	for _, row in ipairs(aTitlesFromDb) do
		if (row.language == aLanguage) then
			titles[row.kind] = row.title
		end
	end
	return titles["main"] or titles["official"] or titles["syn"] or titles["short"]
end





--- Returns the data stored for the specified picture and size in the DB
-- Returns nil if no data.
-- aSize is either "regular" or "thumb"
function db.pictureData(aPictureId, aSize)
	assert(type(aPictureId) == "string")
	assert(type(aSize) == "string")

	local row, msg = db.getArrayFromQuery([[
		SELECT data FROM Picture
		WHERE pictureId = ? AND size = ?
	]], {aPictureId, aSize}, "pictureData")
	-- log("db", "pic: row = %s, row[1] = %s, row[1].data = %s", tostring(row), tostring((row or {})[1]), tostring(((row or {})[1] or {}).data))
	if not(row and row[1] and row[1].data) then
		return nil, msg
	end
	return row[1].data
end





--- Returns an array-table of the seen IDs that are seen after the specified From string (string-compared by SQL)
function db.rawSeenIdsFrom(aFrom)
	return db.getArrayFromQuery([[
		SELECT * FROM Seen
		WHERE seenDate >= ?
		ORDER BY seenDate ASC
	]], {aFrom}, "rawSeenIdsFrom")
end





--- Returns an array-table of the watchlist data
function db.rawWatchlist()
	return db.getArrayFromQuery([[
		SELECT * FROM Watchlist
	]])
end





--- Re-creates indices previously dropped by collectAndDropIndices()
-- aIndexDefs is an array-table of {name = "", sql = ""}
function db.recreateIndices(aIndexDefs)
	assert(type(aIndexDefs) == "table")

	for _, def in ipairs(aIndexDefs) do
		assert(type(def.sql) == "string")
		checkSql(db:exec(def.sql), "recreateIndices." .. tostring(def.name))
	end
end





--- Searches Anime titles containing all given words of length >= 3
-- Returns an array-table with {aId, details} items
-- If the query matches the title perfectly (sans punctuation), areTitlesEqual = true is added into the item
-- Up to 50 items are returned
function db.searchAnimeTitles(aQuery)
	assert(gDB ~= nil)
	assert(type(aQuery) == "string")

	-- Raw ID search:
	local results, msg = db.searchAnimeTitlesRaw(aQuery)

	-- Insert the details:
	if not(results) then
		return nil, msg
	end
	for _, res in ipairs(results) do
		res.details = db.getAnimeDetails(res.aId) or {episodes = {n = 0}, titles = {n = 0}, characters = {n = 0}, tags = {n = 0}}
		res.areTitlesEqual = utils.areMultiTitlesEqual(aQuery, res.details.titles or {})
	end

	return results
end





--- Searches Anime titles containing all given words of length >= 3
-- Returns an array-table with {aId = ...} items
-- Up to 50 items are returned
function db.searchAnimeTitlesRaw(aQuery)
	assert(gDB ~= nil)
	assert(type(aQuery) == "string")

	return gTitleSearch:query(aQuery)
end





--- Stores the specified config value
-- NOTE: the config module does conversion between ConfigValue and the DbValue
function db.setConfigValue(aIdentifier, aDbValue)
	if (aDbValue) then
		local stmt = gDB:prepare([[
			INSERT INTO Config(identifier, dbValue)
			VALUES(?, ?)
			ON CONFLICT(identifier)
			DO UPDATE SET dbValue = excluded.dbValue
		]])
		stmt:bind_values(aIdentifier, aDbValue)
		stmt:step()
		stmt:reset()
		stmt:finalize()
	else
		db.execBoundStatement([[DELETE FROM Config WHERE identifier = ?]], {aIdentifier}, "setConfigValue")
	end
end





--- Sets the last DB update timestamp
function db.setLastAniDbUpdate(aTimestamp)
	assert(gDB ~= nil)

	local stmt = gDB:prepare("INSERT OR REPLACE INTO KeyValue (key, value) VALUES ('lastAniDbUpdate', ?);")
	checkSql(stmt:bind_values(tostring(aTimestamp)), "setLastAniDbUpdate.bind")
	checkSql(stmt:step(), "setLastAniDbUpdate.step")
	checkSql(stmt:finalize(), "setLastAniDbUpdate.finalize")
end




--- Stores or updates the base details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeBaseDetails(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")

	if not(aDetails.episodes) then
		aDetails.episodes = { n = 0 }
	end

	local stmt = gDB:prepare([[
		INSERT INTO AnimeBaseDetails(aId, startDate, endDate, numEpisodes, url, kind, description, pictureId, lastUpdated)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
		ON CONFLICT(aId) DO UPDATE SET
			startDate = excluded.startDate,
			endDate = excluded.endDate,
			numEpisodes = excluded.numEpisodes,
			url = excluded.url,
			description = excluded.description,
			pictureId = excluded.pictureId,
			lastUpdated = datetime('now');
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeBaseDetails: " .. gDB:errmsg())
	end
	checkSql(stmt:bind_values(
		aDetails.aId,
		aDetails.startDate,
		aDetails.endDate,
		aDetails.episodes.n,
		aDetails.url,
		aDetails.kind,
		aDetails.description,
		aDetails.pictureId
	), "storeAnimeBaseDetails.bind")
	checkSql(stmt:step(), "storeAnimeBaseDetails.step")
	checkSql(stmt:finalize(), "storeAnimeBaseDetails.finalize")
end





--- Stores or updates the characters details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeCharacters(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.characters) then
		return
	end
	local timer = perf.newTimer("db.storeAnimeCharacters")

	-- First insert the global objects from the details:
	db.storeAnimeCharacters_Characters(aDetails)
	timer("Characters")
	db.storeAnimeCharacters_VoiceActors(aDetails)
	timer("VoiceActors")

	-- Delete any existing relations:
	db.execBoundStatement([[
		DELETE FROM AnimeCharacterVoiceActor
		WHERE acId IN (
			SELECT acId FROM AnimeCharacter WHERE aId = ?
		)]],
		{aDetails.aId}, "storeAnimeCharacters.delACVA"
	)
	timer("delACVA")
	db.execBoundStatement("DELETE FROM AnimeCharacter WHERE aId = ?", {aDetails.aId}, "storeAnimeCharacters.delAC")
	timer("delAC")

	-- Insert Anime characters:
	local stmtInsertAnimeCharacters = gDB:prepare([[
		INSERT INTO AnimeCharacter(characterId, aId, notes, pictureId)
		VALUES (?, ?, ?, ?)
	]])
	if not(stmtInsertAnimeCharacters) then
		error("Failed to prepare statement for AnimeCharacter insertion: " .. gDB:errmsg())
	end
	for _, ch in ipairs(aDetails.characters) do
		assert(ch.characterId)
		checkSql(stmtInsertAnimeCharacters:bind_values(
			ch.characterId,
			aDetails.aId,
			ch.notes,
			ch.pictureId
		), "storeAnimeCharacters.AC.bind")
		checkSql(stmtInsertAnimeCharacters:step(), "storeAnimeCharacters.AC.step")
		checkSql(stmtInsertAnimeCharacters:reset(), "storeAnimeCharacters.AC.reset")
		ch.acId = gDB:last_insert_rowid()
	end
	checkSql(stmtInsertAnimeCharacters:finalize(), "storeAnimeCharacters.AC.finalize")
	timer("storeAC")

	-- Insert Anime characters' voice actors:
	local stmtInsertACVA = gDB:prepare([[
		INSERT INTO AnimeCharacterVoiceActor (acId, vaId, language, episodes, notes)
		VALUES (?, ?, ?, ?, ?)
	]])
	if not(stmtInsertACVA) then
		error("Failed to prepare statement for ACVA insertion: " .. gDB:errmsg())
	end
	for _, ch in ipairs(aDetails.characters) do
		for _, va in ipairs(ch.voiceActors) do
			checkSql(stmtInsertACVA:bind_values(
				ch.acId,
				va.vaId,
				va.language,
				va.episodes,
				va.notes
			), "storeAnimeCharacters.ACVA.bind")
			checkSql(stmtInsertACVA:step(), "storeAnimeCharacters.ACVA.step")
			checkSql(stmtInsertACVA:reset(), "storeAnimeCharacters.ACVA.reset")
		end
	end
	checkSql(stmtInsertACVA:finalize(), "storeAnimeCharacters.ACVA.finalize")
	timer("storeACVA")
end





--- Stores the characters in the specified anime details table into the global Characters table
function db.storeAnimeCharacters_Characters(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")
	if not(aDetails.characters) then
		return
	end

	local stmtInsertGlobalCharacter = gDB:prepare([[
		INSERT INTO Character(
			characterId,
			characterTypeId,
			name,
			gender,
			description,
			pictureId,
			ratingNumVotes,
			ratingValue
		)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(characterId) DO UPDATE SET
			characterTypeId = COALESCE(NULLIF(excluded.characterTypeId, ''), Character.characterTypeId),
			name            = COALESCE(NULLIF(excluded.name, ''), Character.name),
			gender          = COALESCE(NULLIF(excluded.gender, ''), Character.gender),
			description     = COALESCE(NULLIF(excluded.description, ''), Character.description),
			pictureId       = COALESCE(NULLIF(excluded.pictureId, ''), Character.pictureId),
			ratingNumVotes  = CASE
				WHEN excluded.ratingNumVotes IS NOT NULL THEN excluded.ratingNumVotes
				ELSE Character.ratingNumVotes
			END,
			ratingValue     = CASE
				WHEN excluded.ratingValue IS NOT NULL THEN excluded.ratingValue
				ELSE Character.ratingValue
			END;
	]])
	if not(stmtInsertGlobalCharacter) then
		error("Failed to prepare statement for global character insertion: " .. gDB:errmsg())
	end
	for _, ch in ipairs(aDetails.characters) do
		checkSql(stmtInsertGlobalCharacter:bind_values(
			ch.characterId,
			ch.characterTypeId,
			ch.name,
			ch.gender,
			ch.description,
			ch.pictureId,
			ch.ratingNumVotes,
			ch.ratingValue
		), "storeAnimeCharacters_globalCharacters.step")
		checkSql(stmtInsertGlobalCharacter:step(), "storeAnimeCharacters_Characters.step")
		checkSql(stmtInsertGlobalCharacter:reset(), "storeAnimeCharacters_Characters.reset")
	end
	checkSql(stmtInsertGlobalCharacter:finalize(), "storeAnimeCharacters_Characters.finalize")
end





--- Stores the voice actors in the specified anime details table into the global VoiceActor table
function db.storeAnimeCharacters_VoiceActors(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")
	if not(aDetails.characters) then
		return
	end

	-- Prepare statement for inserting / updating global voice actors
	local stmtInsertGlobalVoiceActor = gDB:prepare([[
		INSERT INTO VoiceActor(
			vaId,
			name,
			gender,
			description,
			pictureId,
			country,
			birthdate
		)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (vaId) DO UPDATE SET
			name        = COALESCE(NULLIF(excluded.name, ''), VoiceActor.name),
			gender      = COALESCE(NULLIF(excluded.gender, ''), VoiceActor.gender),
			description = COALESCE(NULLIF(excluded.description, ''), VoiceActor.description),
			pictureId   = COALESCE(NULLIF(excluded.pictureId, ''), VoiceActor.pictureId),
			country     = COALESCE(NULLIF(excluded.country, ''), VoiceActor.country),
			birthdate   = COALESCE(NULLIF(excluded.birthdate, ''), VoiceActor.birthdate);
	]])
	if not(stmtInsertGlobalVoiceActor) then
		error("Failed to prepare statement for global voice actor insertion: " .. gDB:errmsg())
	end

	for _, ch in ipairs(aDetails.characters) do
		if ch.voiceActors then
			for _, va in ipairs(ch.voiceActors) do
				checkSql(stmtInsertGlobalVoiceActor:bind_values(
					va.vaId,
					va.name,
					va.gender,
					va.description,
					va.pictureId,
					va.country,
					va.birthdate
				), "storeAnimeCharacters_VoiceActors.bind")

				checkSql(stmtInsertGlobalVoiceActor:step(), "storeAnimeCharacters_VoiceActors.step")
				checkSql(stmtInsertGlobalVoiceActor:reset(), "storeAnimeCharacters_VoiceActors.reset")
			end
		end
	end

	checkSql(stmtInsertGlobalVoiceActor:finalize(), "storeAnimeCharacters_VoiceActors.finalize")
end





--- Stores or updates the creators details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeCreators(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.creators) then
		return
	end

	db.execBoundStatement("DELETE FROM AnimeCreator WHERE aId = ?", {aDetails.aId}, "storeAnimeCreators")
	local stmt = gDB:prepare([[
		INSERT OR IGNORE INTO AnimeCreator(aId, id, kind, name)
		VALUES (?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeCreators: " .. gDB:errmsg())
	end
	for _, c in ipairs(aDetails.creators) do
		assert(tonumber(c.id))
		checkSql(stmt:bind_values(aDetails.aId, c.id, c.kind, c.name), "storeAnimeCreators.bind")
		checkSql(stmt:step(), "storeAnimeCreators.step")
		checkSql(stmt:reset(), "storeAnimeCreators.reset")
	end
	checkSql(stmt:finalize(), "storeAnimeCreators.finalize")
end





--- Stores or updates details retrieved from AniDB
-- The details are a full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeDetails(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")
	local timer = perf.newTimer("db.storeAnimeDetails")

	checkSql(gDB:exec("SAVEPOINT anime_details"), "storeAnimeDetails.savepoint")
	db.storeAnimeBaseDetails(aDetails)
	timer("BaseDetails")
	db.storeAnimeRelated(aDetails)
	timer("Related")
	db.storeAnimeSimilar(aDetails)
	timer("Similar")
	db.storeAnimeRecommendations(aDetails)
	timer("Recommendations")
	db.storeAnimeCreators(aDetails)
	timer("Creators")
	db.storeAnimeCharacters(aDetails)
	timer("Characters")
	db.storeAnimeTags(aDetails)
	timer("Tags")
	db.storeAnimeEpisodes(aDetails)
	timer("Episodes")
	checkSql(gDB:exec("RELEASE SAVEPOINT anime_details"), "storeAnimeDetails.release")
end





--- Stores or updates the episodes details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeEpisodes(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.episodes) then
		return
	end

	local timer = perf.newTimer("db.storeAnimeEpisodes")

	db.execBoundStatement("DELETE FROM AnimeEpisodeTitle WHERE aId = ?", {aDetails.aId}, "storeAnimeEpisodes.title")
	timer("delEpisodeTitles")
	db.execBoundStatement("DELETE FROM AnimeEpisode WHERE aId = ?", {aDetails.aId}, "storeAnimeEpisodes.episode")
	timer("delEpisodes")
	local stmt = gDB:prepare([[
		INSERT INTO AnimeEpisode(aId, id, kind, episodeNumber, length, airDate)
		VALUES (?, ?, ?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeEpisodes: " .. gDB:errmsg())
	end
	local stmtTitles = gDB:prepare([[
		INSERT INTO AnimeEpisodeTitle(aId, episodeId, language, title)
		VALUES (?, ?, ?, ?)
	]])
	if not(stmtTitles) then
		error("Failed to prepare titles statement for storeAnimeEpisodes: " .. gDB:errmsg())
	end
	for _, epi in ipairs(aDetails.episodes) do
		assert(tonumber(epi.id))
		checkSql(stmt:bind_values(aDetails.aId, epi.id, epi.kind, epi.episodeNumber, epi.length, epi.airDate), "storeAnimeEpisodes.bind")
		checkSql(stmt:step(), "storeAnimeEpisodes.step")
		checkSql(stmt:reset(), "storeAnimeEpisodes.reset")
		for _, title in ipairs(epi.titles) do
			checkSql(stmtTitles:bind_values(aDetails.aId, epi.id, title.language, title.title), "storeAnimeEpisodesT.bind")
			checkSql(stmtTitles:step(), "storeAnimeEpisodesT.step")
			checkSql(stmtTitles:reset(), "storeAnimeEpisodesT.reset")
		end
	end
	checkSql(stmtTitles:finalize(), "storeAnimeEpisodesT.finalize")
	checkSql(stmt:finalize(), "storeAnimeEpisodes.finalize")
	timer("inserted")
end





--- Stores or updates the recommendations details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeRecommendations(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.recommendations) then
		return
	end

	db.execBoundStatement("DELETE FROM AnimeRecommendation WHERE aId = ?", {aDetails.aId}, "storeAnimeRecommendations")
	local stmt = gDB:prepare([[
		INSERT OR IGNORE INTO AnimeRecommendation(aId, uId, kind, text)
		VALUES (?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeRecommendations: " .. gDB:errmsg())
	end
	for _, rec in ipairs(aDetails.recommendations) do
		assert(tonumber(rec.uId))
		checkSql(stmt:bind_values(aDetails.aId, rec.uId, rec.kind, rec.text), "storeAnimeRecommendations.bind")
		checkSql(stmt:step(), "storeAnimeRecommendations.step")
		checkSql(stmt:reset(), "storeAnimeRecommendations.reset")
	end
	checkSql(stmt:finalize(), "storeAnimeRecommendations.finalize")
end





--- Stores or updates the relatedAnime details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeRelated(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.relatedAnime) then
		return
	end

	db.execBoundStatement("DELETE FROM AnimeRelated WHERE aId = ?", {aDetails.aId}, "storeAnimeRelated")
	local stmt = gDB:prepare([[
		INSERT OR IGNORE INTO AnimeRelated(aId, relatedAid, relation)
		VALUES (?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeRelated: " .. gDB:errmsg())
	end
	for _, rel in ipairs(aDetails.relatedAnime) do
		assert(tonumber(rel.aId))
		checkSql(stmt:bind_values(aDetails.aId, rel.aId, rel.relation), "storeAnimeRelated.bind")
		checkSql(stmt:step(), "storeAnimeRelated.step")
		checkSql(stmt:reset(), "storeAnimeRelated.reset")
	end
	checkSql(stmt:finalize(), "storeAnimeRelated.finalize")
end





--- Stores or updates the similarAnime details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeSimilar(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.similarAnime) then
		return
	end

	db.execBoundStatement("DELETE FROM AnimeSimilar WHERE aId = ?", {aDetails.aId}, "storeAnimeSimilar")
	local stmt = gDB:prepare([[
		INSERT OR IGNORE INTO AnimeSimilar(aId, similarAid)
		VALUES (?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeSimilar: " .. gDB:errmsg())
	end
	for _, rel in ipairs(aDetails.similarAnime) do
		assert(tonumber(rel.aId))
		checkSql(stmt:bind_values(aDetails.aId, rel.aId), "storeAnimeSimilar.bind")
		checkSql(stmt:step(), "storeAnimeSimilar.step")
		checkSql(stmt:reset(), "storeAnimeSimilar.reset")
	end
	checkSql(stmt:finalize(), "storeAnimeSimilar.finalize")
end





--- Stores or updates the tags details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeTags(aDetails)
	assert(gDB ~= nil)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.tags) then
		return
	end

	-- First add the tags to the global table, if not already there:
	db.addGlobalTags(aDetails.tags)

	-- Then add the per-anime tags:
	db.execBoundStatement("DELETE FROM AnimeTag WHERE aId = ?", {aDetails.aId}, "storeAnimeTags")
	local stmt = gDB:prepare([[
		INSERT OR IGNORE INTO AnimeTag(aId, tagId, weight)
		VALUES (?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeTags: " .. gDB:errmsg())
	end
	for _, tag in ipairs(aDetails.tags) do
		assert(tonumber(tag.tagId))
		local weight = tonumber(tag.weight) or 0
		if (weight >= 0) then
			checkSql(stmt:bind_values(aDetails.aId, tag.tagId, weight), "storeAnimeTags.bind")
			checkSql(stmt:step(), "storeAnimeTags.step")
			checkSql(stmt:reset(), "storeAnimeTags.reset")
		end
	end
	checkSql(stmt:finalize(), "storeAnimeTags.finalize")

	-- Based on the tags, update the 18+ restriction detail:
	db.updateAnimeBaseDetailsIsAdultRestricted(aDetails.aId)
end





--- Stores the data for the specified picture
function db.storePictureData(aPictureId, aPictureSize, aPictureData)
	assert(gDB ~= nil)
	assert(type(aPictureId) == "string")
	assert(type(aPictureSize) == "string")
	assert(type(aPictureData) == "string")

	local stmt = gDB:prepare([[
		INSERT INTO Picture(pictureId, size, data)
		VALUES (?, ?, ?)
		ON CONFLICT(pictureId, size) DO UPDATE SET
			data = excluded.data;
	]])
	if not(stmt) then
		error("Failed to prepare statement for storePictureData: " .. gDB:errmsg())
	end
	checkSql(stmt:bind_values(aPictureId, aPictureSize, aPictureData), "storePictureData.bind")
	checkSql(stmt:step(), "storePictureData.step")
	checkSql(stmt:reset(), "storePictureData.reset")
	checkSql(stmt:finalize(), "storePictureData.finalize")
end





--- Stores the specified schedule into the DB, overwriting any existing items for the
-- unique (aId, watchlistSeason) combination
-- aSchedule is an array-table of at least {aId = ..., utcSecondsSinceWeekStart = ...}
function db.storeWeeklySchedule(aWatchlistSeason, aSchedule)
	assert(gDB ~= nil)
	assert(type(aWatchlistSeason) == "string")
	assert(type(aSchedule) == "table")

	local stmt = gDB:prepare([[
		INSERT OR REPLACE INTO WeeklySchedule(aId, utcSecondsSinceWeekStart, watchlistSeason)
		VALUES (?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeWeeklySchedule: " .. gDB:errmsg())
	end
	for _, sch in ipairs(aSchedule) do
		checkSql(stmt:bind_values(sch.aId, sch.utcSecondsSinceWeekStart, aWatchlistSeason), "storeWeeklySchedule.bind")
		checkSql(stmt:step(), "storeWeeklySchedule.step")
		checkSql(stmt:reset(), "storeWeeklySchedule.reset")
	end
	checkSql(stmt:finalize(), "storeWeeklySchedule.finalize")
end





--- Returns the titleSearch instance
function db.titleSearch()
	return gTitleSearch
end





--- Updates the Anime and AnimeTitle tables from an AniDB dump
function db.updateAniDbDataFromDump(aXmlString)
	assert(gDB ~= nil)

	-- Disable foreign keys during replacement
	checkSql(gDB:exec("PRAGMA foreign_keys = OFF;"), "updateAniDbDataFromDump.fkoff")
	checkSql(gDB:exec("BEGIN TRANSACTION"),          "updateAniDbDataFromDump.begin")
	checkSql(gDB:exec("DELETE FROM AnimeTitle;"),    "updateAniDbDataFromDump.delTitle")
	checkSql(gDB:exec("DELETE FROM Anime;"),         "updateAniDbDataFromDump.delAnime")

	local lxp = require("lxp")
	local stmtInsertAnime = assert(gDB:prepare("INSERT INTO Anime(aId) VALUES(?);"))
	local stmtInsertTitle = assert(gDB:prepare([[
		INSERT INTO AnimeTitle(aId, language, kind, title, titleLower)
		VALUES(?, ?, ?, ?, ?);
	]]))

	local curAnimeId
	local curTitleLang, curTitleKind, curTitleText
	local insideTitle = false

	local parser = lxp.new({
		StartElement = function(_, aName, aAttr)
			if (aName == "anime") then
				curAnimeId = tonumber(aAttr.aid)
				checkSql(stmtInsertAnime:bind_values(curAnimeId), "updateAniDbDataFromDump.insertAnime.bind")
				checkSql(stmtInsertAnime:step(),  "updateAniDbDataFromDump.insertAnime.step")
				checkSql(stmtInsertAnime:reset(), "updateAniDbDataFromDump.insertAnime.reset")
			elseif (aName == "title") then
				curTitleLang = aAttr["xml:lang"]
				curTitleKind = aAttr.type
				curTitleText = ""
				insideTitle = true
			end
		end,

		EndElement = function(_, aName)
			if (aName == "title" and insideTitle and curAnimeId) then
				checkSql(stmtInsertTitle:bind_values(
					curAnimeId, curTitleLang, curTitleKind,
					curTitleText, curTitleText:lower()
				), "updateAniDb.insertTitle.bind")
				checkSql(stmtInsertTitle:step(), "updateAniDbDataFromDump.insertTitle.step")
				checkSql(stmtInsertTitle:reset(), "updateAniDbDataFromDump.insertTitle.reset")
				insideTitle = false
			end
		end,

		CharacterData = function(_, aData)
			if (insideTitle) then
				curTitleText = curTitleText .. aData
			end
		end
	})

	parser:parse(aXmlString)
	parser:close()

	stmtInsertAnime:finalize()
	stmtInsertTitle:finalize()

	-- Re-enable foreign keys
	db.setLastAniDbUpdate(os.time())
	checkSql(gDB:exec("COMMIT TRANSACTION"), "updateAniDbDataFromDump.commit")
	checkSql(gDB:exec("PRAGMA foreign_keys = ON;"), "updateAniDbDataFromDump.fkon")
end





--- Updates the specified anime's isAdultRestricted flag based on the anime's tags
function db.updateAnimeBaseDetailsIsAdultRestricted(aId)
	assert(gDB ~= nil)
	assert(tonumber(aId))

	db.execBoundStatement([[
		UPDATE AnimeBaseDetails
		SET isAdultRestricted =
			EXISTS (
				SELECT 1
				FROM AnimeTag at
				JOIN Tag t ON t.tagId = at.tagId
				WHERE at.aId = AnimeBaseDetails.aId
				AND t.name = '18 restricted'
			)
		WHERE aId = ?
	]], {aId}, "updateAnimeBaseDetailsIsAdultRestricted")
end





--- Returns the watchlist for the specified season
-- Only the base data for the watchlist is returned. Callers are expected to enrich the watchlist with
-- anime data based on the aId items; use animeInSeason() to query the relevant anime
function db.watchlistInSeason(aSeason)
	-- Query the base watchlist:
	return db.getArrayFromQuery(
	[[
		SELECT * FROM Watchlist
		WHERE watchlistSeason = ?
	]], {aSeason}, "watchlistInSeason")
end





initialize()
return db
