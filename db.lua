-- db.lua
-- Database access module

local sqlite3 = require("lsqlite3")

local db = {}
local dbFile = "anime.sqlite"
local conn = nil





--- Ensures an open DB connection
local function ensureDb()
	if (not conn) then
		conn = sqlite3.open(dbFile)
		conn:busy_timeout(1000)
		conn:exec("PRAGMA foreign_keys = ON;")
	end
	return conn
end





--- Checks SQLite result codes and throws errors
local function checkSql(aConn, aResult, aContext)
	if (aResult ~= sqlite3.OK and aResult ~= sqlite3.DONE and aResult ~= sqlite3.ROW) then
		error(string.format("SQLite error in %s: %s", aContext or "unknown", aConn:errmsg()))
	end
end





--- Closes the DB connection
function db.close()
	if (conn) then
		conn:close()
		conn = nil
	end
end





--- Ensures DB schema exists and upgrades if needed
function db.createSchema()
	-- If connection is already open, close before backup
	if (conn) then
		conn:close()
		conn = nil
	end

	-- Open new connection (not yet upgraded)
	local tempConn = sqlite3.open(dbFile)
	tempConn:busy_timeout(1000)
	tempConn:exec("PRAGMA foreign_keys = ON;")

	-- Backup safely before upgrade
	local dbUpgrade = require("dbUpgrade")
	dbUpgrade.backupDbFile(dbFile)  -- expose backup as public

	-- Reopen fresh connection after backup
	tempConn:close()
	conn = sqlite3.open(dbFile)
	conn:busy_timeout(1000)
	conn:exec("PRAGMA foreign_keys = ON;")

	-- Now safely run the upgrade
	dbUpgrade.upgradeIfNeeded(conn, dbFile)
end





--- Executes the specified statement, binding the specified values to it.
-- aDescription is used for error logging.
function db.execBoundStatement(aSql, aValuesToBind, aDescription)
	local c = ensureDb()
	local stmt = c:prepare(aSql)
	if not(stmt) then
		error("Failed to prepare statement (" .. aDescription .. "): " .. c:errmsg())
	end
	checkSql(c, stmt:bind_values(table.unpack(aValuesToBind)), aDescription .. ".bind")
	checkSql(c, stmt:step(), aDescription .. ".step")
	checkSql(c, stmt:finalize(), aDescription .. ".finalize")
end





--- Runs the specified SQL query, binding the specified values to it, and returns the results as an array-table of dict-tables
-- aDescription is used for error logging.
function db.getArrayFromQuery(aSql, aValuesToBind, aDescription)
	assert(type(aSql) == "string")
	assert(type(aValuesToBind) == "table" or not(aValuesToBind))
	if not(aDescription) then
		aDescription = debug.getinfo(1, 'S').source
	end

	local c = ensureDb()
	local stmt = c:prepare(aSql)
	if not(stmt) then
		error("Failed to prepare statement (" .. aDescription .. "): " .. c:errmsg())
	end
	if ((aValuesToBind) and (aValuesToBind[1])) then
		checkSql(c, stmt:bind_values(table.unpack(aValuesToBind)), aDescription .. ".bind")
	end
	local result = {}
	local n = 0
	for row in stmt:nrows() do
		n = n + 1
		result[n] = row
	end
	result.n = n
	checkSql(c, stmt:finalize(), aDescription .. ".finalize")

	return result
end





--- Returns an array-table of all seen Anime
-- Each item is a table {aId = ..., seenDate = ...}
function db.getSeenAnime()
	local c = ensureDb()

	return db.getArrayFromQuery("SELECT aId, seenDate FROM Seen")
end





--- Returns an array-table of anime aIds that have been marked as seen but have no details stored in the DB
function db.getSeenWithoutDetails()
	local c = ensureDb()

	local stmt = c:prepare([[
		SELECT s.aId
		FROM Seen AS s
		WHERE NOT EXISTS (
			SELECT 1
			FROM AnimeBaseDetails AS b
			WHERE b.aId = s.aId
		);
	]])
	if not(stmt) then
		error("SQL prepare failed (getSeenWithoutDetails): " .. c:errmsg())
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





--- Returns true if the base AniDB data (Anime, AnimeTitle tables) have been populated
function db.hasBaseAniDbData()
	local c = ensureDb()
	local stmt = c:prepare("SELECT COUNT(aId) as cnt FROM Anime")
	if not(stmt) then error("SQL prepare failed (hasBaseAniDbData): " .. c:errmsg()) end
	for row in stmt:nrows() do
		if (row.cnt > 0) then
			return true
		end
	end
	checkSql(c, stmt:finalize(), "hasBaseAniDbData.finalize")
	return false
end





--- Returns true if the specified Anime has an entry in the AnimeDetails table (and so is supposed
-- to have had its details queried from AniDB previously)
function db.hasDetails(aId)
	assert(type(aId) == "number")
	local c = ensureDb()
	local stmt = c:prepare("SELECT COUNT(aId) as cnt FROM AnimeDetails WHERE aId = ?")
	if not(stmt) then error("SQL prepare failed (hasBaseAniDbData): " .. c:errmsg()) end
	checkSql(c, stmt:bind_values(aId), "hasDetails.bind")
	for row in stmt:nrows() do
		if (row.cnt > 0) then
			return true
		end
	end
	checkSql(c, stmt:finalize(), "hasDetails.finalize")
	return false
end





--- Marks an anime as seen
function db.markAnimeSeen(aId)
	db.execBoundStatement(
		"INSERT OR REPLACE INTO Seen (aId, seenDate) VALUES (?, datetime('now'))",
		{aId},
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





--- Gets full details for a single anime
function db.getAnimeDetails(aId)
	assert(tonumber(aId))

	local c = ensureDb()
	local result =
	{
		aId = aId,
		characters = db.getAnimeDetails_characters(aId),
		creators = db.getAnimeDetails_creators(aId),
		episodes = db.getAnimeDetails_episodes(aId),
		recommendations = db.getAnimeDetails_recommendations(aId),
		relatedAnime = db.getAnimeDetails_relatedAnime(aId),
		similarAnime = db.getAnimeDetails_similarAnime(aId),
		tags = db.getAnimeDetails_tags(aId),
		titles = db.getAnimeDetails_titles(aId),
	}

	-- Get the base details:
	local stmt = c:prepare([[
		SELECT startDate, endDate, numEpisodes, pictureId, lastUpdated
		FROM AnimeBaseDetails
		WHERE aId = ? LIMIT 1;
	]])
	if not(stmt) then
		error("SQL prepare failed (getAnimeDetails): " .. c:errmsg())
	end
	checkSql(c, stmt:bind_values(aId), "getAnimeDetails.bind")
	for row in stmt:nrows() do
		result.startDate = row.startDate
		result.endDate = row.endDate
		result.episodes = {n = 0}
		result.pictureId = row.pictureId
		result.lastUpdated = row.lastUpdated
	end
	checkSql(c, stmt:finalize(), "getAnimeDetails.finalize")

	-- Get the most useful titles:
	result.enTitle = db.pickBestTitle(result.titles, "en")
	result.jpTitle = db.pickBestTitle(result.titles, "ja")
	result.xjpTitle = db.pickBestTitle(result.titles, "x-jat")

	return result
end





--- Returns the characters for the specified anime, as the details-table
function db.getAnimeDetails_characters(aId)
	assert(tonumber(aId))

	return db.getArrayFromQuery("SELECT * FROM AnimeCharacter WHERE aId = ?", {aId}, "getAnimeDetails_characters")
end





--- Returns the creators for the specified anime, as the details-table
function db.getAnimeDetails_creators(aId)
	assert(tonumber(aId))

	return db.getArrayFromQuery("SELECT * FROM AnimeCreator WHERE aId = ?", {aId}, "getAnimeDetails_creators")
end





--- Returns the episodes for the specified anime, as the details-table
function db.getAnimeDetails_episodes(aId)
	assert(tonumber(aId))

	local result = db.getArrayFromQuery("SELECT * FROM AnimeEpisode WHERE aId = ?", {aId}, "getAnimeDetails_episodes")
	for _, epi in ipairs(result) do
		epi.titles = db.getArrayFromQuery("SELECT * FROM AnimeEpisodeTitle WHERE aId = ? AND episodeId = ?", {aId, epi.id}, "getAnimeDetails_episodesT")
	end
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

	return db.getArrayFromQuery("SELECT * FROM AnimeRelated WHERE aId = ?", {aId}, "getAnimeDetails_related")
end





--- Returns the X for the specified anime, as the details-table
function db.getAnimeDetails_similarAnime(aId)
	assert(tonumber(aId))

	return db.getArrayFromQuery("SELECT * FROM AnimeSimilar WHERE aId = ?", {aId}, "getAnimeDetails_similar")
end





--- Returns the X for the specified anime, as the details-table
function db.getAnimeDetails_tags(aId)
	assert(tonumber(aId))

	return db.getArrayFromQuery("SELECT * FROM AnimeTag WHERE aId = ?", {aId}, "getAnimeDetails_tags")
end





--- Returns the X for the specified anime, as the details-table
function db.getAnimeDetails_titles(aId)
	assert(tonumber(aId))

	return db.getArrayFromQuery("SELECT * FROM AnimeTitle WHERE aId = ?", {aId}, "getAnimeDetails_title")
end





--- Updates Anime and AnimeTitle tables from a dump
function db.updateAniDbDataFromDump(aDumpFunction)
	local c = ensureDb()

	checkSql(c, c:exec("BEGIN;"), "updateAniDbDataFromDump.begin")
	checkSql(c, c:exec("PRAGMA foreign_keys = OFF;"), "updateAniDbDataFromDump.fkoff")

	checkSql(c, c:exec("DELETE FROM AnimeTitle;"), "updateAniDbDataFromDump.clearTitle")
	checkSql(c, c:exec("DELETE FROM Anime;"), "updateAniDbDataFromDump.clearAnime")

	if (aDumpFunction) then
		aDumpFunction(c)
	end

	checkSql(c, c:exec("PRAGMA foreign_keys = ON;"), "updateAniDbDataFromDump.fkon")
	checkSql(c, c:exec("COMMIT;"), "updateAniDbDataFromDump.commit")
end





--- Stores or updates details retrieved from AniDB
-- The details are a full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeDetails(aDetails)
	assert(type(aDetails) == "table")

	local c = ensureDb()
	checkSql(c, c:exec("BEGIN TRANSACTION"), "storeAnimeDetails.begin")
	db.storeAnimeBaseDetails(aDetails)
	db.storeAnimeRelated(aDetails)
	db.storeAnimeSimilar(aDetails)
	db.storeAnimeRecommendations(aDetails)
	db.storeAnimeCreators(aDetails)
	db.storeAnimeCharacters(aDetails)
	db.storeAnimeTags(aDetails)
	db.storeAnimeEpisodes(aDetails)
	checkSql(c, c:exec("COMMIT TRANSACTION"), "storeAnimeDetails.commit")
end





--- Stores or updates the base details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeBaseDetails(aDetails)
	assert(type(aDetails) == "table")
	if not(aDetails.episodes) then
		aDetails.episodes = { n = 0 }
	end

	local c = ensureDb()
	local stmt = c:prepare([[
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
		error("Failed to prepare statement for storeAnimeBaseDetails: " .. c:errmsg())
	end
	checkSql(c, stmt:bind_values(
		aDetails.aId,
		aDetails.startDate,
		aDetails.endDate,
		aDetails.episodes.n,
		aDetails.url,
		aDetails.kind,
		aDetails.description,
		aDetails.pictureId
	), "storeAnimeBaseDetails.bind")
	checkSql(c, stmt:step(), "storeAnimeBaseDetails.step")
	checkSql(c, stmt:finalize(), "storeAnimeBaseDetails.finalize")
end





--- Stores or updates the relatedAnime details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeRelated(aDetails)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.relatedAnime) then
		return
	end

	local c = ensureDb()
	db.execBoundStatement("DELETE FROM AnimeRelated WHERE aId = ?", {aDetails.aId}, "storeAnimeRelated")
	local stmt = c:prepare([[
		INSERT OR IGNORE INTO AnimeRelated(aId, relatedAid, relation)
		VALUES (?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeRelated: " .. c:errmsg())
	end
	for _, rel in ipairs(aDetails.relatedAnime) do
		assert(tonumber(rel.aId))
		checkSql(c, stmt:bind_values(aDetails.aId, rel.aId, rel.relation), "storeAnimeRelated.bind")
		checkSql(c, stmt:step(), "storeAnimeRelated.step")
		checkSql(c, stmt:reset(), "storeAnimeRelated.reset")
	end
	checkSql(c, stmt:finalize(), "storeAnimeRelated.finalize")
end





--- Stores or updates the similarAnime details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeSimilar(aDetails)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.similarAnime) then
		return
	end

	local c = ensureDb()
	db.execBoundStatement("DELETE FROM AnimeSimilar WHERE aId = ?", {aDetails.aId}, "storeAnimeSimilar")
	local stmt = c:prepare([[
		INSERT OR IGNORE INTO AnimeSimilar(aId, similarAid)
		VALUES (?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeSimilar: " .. c:errmsg())
	end
	for _, rel in ipairs(aDetails.similarAnime) do
		assert(tonumber(rel.aId))
		checkSql(c, stmt:bind_values(aDetails.aId, rel.aId), "storeAnimeSimilar.bind")
		checkSql(c, stmt:step(), "storeAnimeSimilar.step")
		checkSql(c, stmt:reset(), "storeAnimeSimilar.reset")
	end
	checkSql(c, stmt:finalize(), "storeAnimeSimilar.finalize")
end





--- Stores or updates the recommendations details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeRecommendations(aDetails)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.recommendations) then
		return
	end

	local c = ensureDb()
	db.execBoundStatement("DELETE FROM AnimeRecommendation WHERE aId = ?", {aDetails.aId}, "storeAnimeRecommendations")
	local stmt = c:prepare([[
		INSERT OR IGNORE INTO AnimeRecommendation(aId, uId, kind, text)
		VALUES (?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeRecommendations: " .. c:errmsg())
	end
	for _, rec in ipairs(aDetails.recommendations) do
		assert(tonumber(rec.uId))
		checkSql(c, stmt:bind_values(aDetails.aId, rec.uId, rec.kind, rec.text), "storeAnimeRecommendations.bind")
		checkSql(c, stmt:step(), "storeAnimeRecommendations.step")
		checkSql(c, stmt:reset(), "storeAnimeRecommendations.reset")
	end
	checkSql(c, stmt:finalize(), "storeAnimeRecommendations.finalize")
end





--- Stores or updates the creators details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeCreators(aDetails)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.creators) then
		return
	end

	local c = ensureDb()
	db.execBoundStatement("DELETE FROM AnimeCreator WHERE aId = ?", {aDetails.aId}, "storeAnimeCreators")
	local stmt = c:prepare([[
		INSERT OR IGNORE INTO AnimeCreator(aId, id, kind, name)
		VALUES (?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeCreators: " .. c:errmsg())
	end
	for _, c in ipairs(aDetails.creators) do
		assert(tonumber(c.id))
		checkSql(c, stmt:bind_values(aDetails.aId, c.id, c.kind, c.name), "storeAnimeCreators.bind")
		checkSql(c, stmt:step(), "storeAnimeCreators.step")
		checkSql(c, stmt:reset(), "storeAnimeCreators.reset")
	end
	checkSql(c, stmt:finalize(), "storeAnimeCreators.finalize")
end





--- Stores or updates the characters details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeCharacters(aDetails)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.characters) then
		return
	end

	local c = ensureDb()
	db.execBoundStatement("DELETE FROM AnimeCharacter WHERE aId = ?", {aDetails.aId}, "storeAnimeCharacters")
	local stmt = c:prepare([[
		INSERT OR IGNORE INTO AnimeCharacter(aId, characterTypeId, name, gender, description, voiceActorId, pictureId, ratingNumVotes, ratingValue)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeCharacters: " .. c:errmsg())
	end
	for _, ch in ipairs(aDetails.characters) do
		assert(ch.name)
		checkSql(c, stmt:bind_values(
			aDetails.aId,
			ch.characterTypeId,
			ch.name,
			ch.gender,
			ch.description,
			(ch.voiceActor or {}).id,
			ch.pictureId,
			(ch.rating or {}).numVotes,
			(ch.rating or {}).value
		), "storeAnimeCharacters.bind")
		checkSql(c, stmt:step(), "storeAnimeCharacters.step")
		checkSql(c, stmt:reset(), "storeAnimeCharacters.reset")
	end
	checkSql(c, stmt:finalize(), "storeAnimeCharacters.finalize")
end





--- Stores or updates the tags details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeTags(aDetails)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.tags) then
		return
	end

	local c = ensureDb()
	db.execBoundStatement("DELETE FROM AnimeTag WHERE aId = ?", {aDetails.aId}, "storeAnimeTags")
	local stmt = c:prepare([[
		INSERT OR IGNORE INTO AnimeTag(aId, id, weight)
		VALUES (?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeTags: " .. c:errmsg())
	end
	for _, tag in ipairs(aDetails.tags) do
		assert(tonumber(tag.id))
		local weight = tonumber(tag.weight) or 0
		if (weight > 0) then
			checkSql(c, stmt:bind_values(aDetails.aId, tag.id, weight), "storeAnimeTags.bind")
			checkSql(c, stmt:step(), "storeAnimeTags.step")
			checkSql(c, stmt:reset(), "storeAnimeTags.reset")
		end
	end
	checkSql(c, stmt:finalize(), "storeAnimeTags.finalize")

	-- TODO: Store the tags in the global tags table, for the parentId information
end





--- Stores or updates the episodes details from AniDB API
-- aDetails is the full details table parsed out of AniDB's HTTP API XML response
function db.storeAnimeEpisodes(aDetails)
	assert(type(aDetails) == "table")
	assert(tonumber(aDetails.aId))
	if not(aDetails.episodes) then
		return
	end

	local c = ensureDb()
	db.execBoundStatement("DELETE FROM AnimeEpisodeTitle WHERE aId = ?", {aDetails.aId}, "storeAnimeEpisodes.title")
	db.execBoundStatement("DELETE FROM AnimeEpisode WHERE aId = ?", {aDetails.aId}, "storeAnimeEpisodes.episode")
	local stmt = c:prepare([[
		INSERT OR IGNORE INTO AnimeEpisode(aId, id, kind, episodeNumber, length, airDate)
		VALUES (?, ?, ?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement for storeAnimeEpisodes: " .. c:errmsg())
	end
	local stmtTitles = c:prepare([[
		INSERT OR IGNORE INTO AnimeEpisodeTitle(aId, episodeId, language, title)
		VALUES (?, ?, ?, ?)
	]])
	if not(stmtTitles) then
		error("Failed to prepare titles statement for storeAnimeEpisodes: " .. c:errmsg())
	end
	for _, epi in ipairs(aDetails.episodes) do
		assert(tonumber(epi.id))
		checkSql(c, stmt:bind_values(aDetails.aId, epi.id, epi.kind, epi.episodeNumber, epi.length, epi.airDate), "storeAnimeEpisodes.bind")
		checkSql(c, stmt:step(), "storeAnimeEpisodes.step")
		checkSql(c, stmt:reset(), "storeAnimeEpisodes.reset")
		for _, title in ipairs(epi.titles) do
			checkSql(c, stmtTitles:bind_values(aDetails.aId, epi.id, title.language, title.title), "storeAnimeEpisodesT.bind")
			checkSql(c, stmtTitles:step(), "storeAnimeEpisodesT.step")
			checkSql(c, stmtTitles:reset(), "storeAnimeEpisodesT.reset")
		end
	end
	checkSql(c, stmtTitles:finalize(), "storeAnimeEpisodesT.finalize")
	checkSql(c, stmt:finalize(), "storeAnimeEpisodes.finalize")
end





--- Returns the last DB update timestamp, or 0 if none
function db.getLastAniDbUpdate()
	local c = ensureDb()
	local stmt = c:prepare("SELECT value FROM KeyValue WHERE key = 'lastAniDbUpdate';")
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




--- Sets the last DB update timestamp
function db.setLastAniDbUpdate(aTimestamp)
	local c = ensureDb()
	local stmt = c:prepare("INSERT OR REPLACE INTO KeyValue (key, value) VALUES ('lastAniDbUpdate', ?);")
	checkSql(c, stmt:bind_values(tostring(aTimestamp)), "setLastAniDbUpdate.bind")
	checkSql(c, stmt:step(), "setLastAniDbUpdate.step")
	checkSql(c, stmt:finalize(), "setLastAniDbUpdate.finalize")
end




--- Updates the Anime and AnimeTitle tables from an AniDB dump
function db.updateAniDbDataFromDump(aXmlString)
	-- Disable foreign keys during replacement
	local c = ensureDb()
	checkSql(c, c:exec("BEGIN TRANSACTION"),          "updateAniDb.begin")
	checkSql(c, c:exec("PRAGMA foreign_keys = OFF;"), "updateAniDb.fkoff")
	checkSql(c, c:exec("DELETE FROM AnimeTitle;"),    "updateAniDb.delTitle")
	checkSql(c, c:exec("DELETE FROM Anime;"),         "updateAniDb.delAnime")

	local lxp = require("lxp")
	local stmtInsertAnime = assert(c:prepare("INSERT INTO Anime(aId) VALUES(?);"))
	local stmtInsertTitle = assert(c:prepare([[
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
				checkSql(c, stmtInsertAnime:bind_values(curAnimeId), "updateAniDb.insertAnime.bind")
				checkSql(c, stmtInsertAnime:step(),  "updateAniDb.insertAnime.step")
				checkSql(c, stmtInsertAnime:reset(), "updateAniDb.insertAnime.reset")
			elseif (aName == "title") then
				curTitleLang = aAttr["xml:lang"]
				curTitleKind = aAttr.type
				curTitleText = ""
				insideTitle = true
			end
		end,

		EndElement = function(_, aName)
			if (aName == "title" and insideTitle and curAnimeId) then
				checkSql(c, stmtInsertTitle:bind_values(
					curAnimeId, curTitleLang, curTitleKind,
					curTitleText, curTitleText:lower()
				), "updateAniDb.insertTitle.bind")
				checkSql(c, stmtInsertTitle:step(), "updateAniDb.insertTitle.step")
				checkSql(c, stmtInsertTitle:reset(), "updateAniDb.insertTitle.reset")
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
	checkSql(c, c:exec("PRAGMA foreign_keys = ON;"), "updateAniDb.fkon")
	db.setLastAniDbUpdate(os.time())
	checkSql(c, c:exec("COMMIT TRANSACTION"), "updateAniDb.commit")
end





--- Searches Anime titles containing all given words of length >= 3
-- Returns an array-table with {aId, title, language} items
-- Up to 50 items are returned
function db.searchAnimeTitles(aQuery)
	local results = { n = 0 }
	local words = {}

	for word in aQuery:gmatch("%S+") do
		if (#word >= 3) then
			words[#words + 1] = "%" .. word:lower() .. "%"
		end
	end

	if (#words == 0) then
		return results
	end

	local sql = [[
		SELECT DISTINCT aId
		FROM AnimeTitle
		WHERE 1 = 1
	]]

	for _ = 1, #words do
		sql = sql .. " AND titleLower LIKE ?"
	end

	sql = sql .. " LIMIT 50;"

	local stmt = conn:prepare(sql)
	if (not stmt) then
		error("Failed to prepare search query: " .. (conn:errmsg() or "unknown error"))
	end

	stmt:bind_values(table.unpack(words))

	for row in stmt:nrows() do
		results.n = results.n + 1
		results[results.n] = { aId = row.aId, details = db.getAnimeDetails(row.aId) }
	end

	stmt:finalize()
	return results
end





return db
