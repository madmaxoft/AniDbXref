-- Tests/test-db-reads.lua

--[[
Implements tests for reading from the DB.
These tests can be executed at any time, as they do not affect any data in the DB
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;./?.lua;Tests/?.lua" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true





local db = require("db")
local utils = require("utils")

local strFormat = string.format





--- Checks that the specified table is a properly-numbered array of specified type,
-- that is, it has the "n" member and exactly n items and type(aArray[idx]) == aItemType for each idx.
local function verifyArray(aArray, aItemType)
	assert(type(aItemType) == "string")

	assert(type(aArray) == "table")
	assert(type(aArray.n) == "number")
	for i = 1, aArray.n do
		assert(type(aArray[i]) == aItemType)
	end
	assert(aArray[aArray.n + 1] == nil)

	if (aArray.n == 0) then
		print("WARNING: An empty array detected, no members will get checked")
		print(debug.traceback())
	end
end





--- Checks that the value is a string representing a maybe-date - "2026", "2026-01", "2026-01-23" or nil
local function verifyMaybeDate(aValue)
	if not(aValue) then
		return
	end
	assert(type(aValue) == "string")
	local len = string.len(aValue)
	assert((len == 4) or (len == 7) or (len == 10))
	if (len == 4) then
		assert(tonumber(aValue))
	elseif (len == 7) then
		assert(tonumber(aValue:sub(1, 4)))
		assert(aValue:sub(5, 5) == "-")
		assert(tonumber(aValue:sub(6, 7)))
	else
		assert(utils.ymdToTimestamp(aValue))
	end
end





--- Checks that the specified table is a properly-numbered array of {title = ..., language = ...}
local function verifyTitles(aTitles)
	verifyArray(aTitles, "table")
	for j = 1, aTitles.n do
		local title = aTitles[j]
		assert(type(title.title) == "string")
		assert(type(title.language) == "string")
	end
end





--- Verifies that the specified value is an YMD date string
local function verifyYmd(aValue)
	if not(aValue) then
		return
	end
	assert(type(aValue) == "string")
	assert(utils.ymdToTimestamp(aValue))
end





local function testAllAnimeIDs()
	print("Testing db.allAnimeIDs()")

	local allIDs = db.allAnimeIDs()
	verifyArray(allIDs, "number")
end





local function testAllConfigValues()
	print("Testing db.allConfigValues()")

	local allValues = db.allConfigValues()
	verifyArray(allValues, "table")
	for i = 1, allValues.n do
		local v = allValues[i]
		assert(type(v.identifier) == "string")
		assert(type(v.dbValue) == "string")
	end
end





local function testAnimeInSeason(aSeason)
	assert(type(aSeason) == "string")
	print("Testing db.animeInSeason(" .. aSeason .. ")")

	local anime = db.animeInSeason(aSeason)
	verifyArray(anime, "table")
	print(strFormat("  got %d items", anime.n))
	for i = 1, anime.n do
		local a = anime[i]
		assert(type(a.aId) == "number")
		assert(type(a.isSeen) == "boolean")
		assert(type(a.startDate) == "string")
		assert(type(a.endDate or "") == "string")
		verifyTitles(a.titles)
		-- Also check titles' "kind" member
		for j = 1, a.titles.n do
			local t = a.titles[j]
			assert(type(t.kind) == "string")
		end
	end
end





local function testGetAnimeDetails_base(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.getAnimeDetails_base(%d)", aId))

	local details = db.getAnimeDetails_base(aId)
	assert(type(details) == "table")
	assert(type(details.aId) == "number")
	assert(type(details.startDate or "") == "string")
	assert(type(details.endDate or "") == "string")
	assert(type(details.kind) == "string")
	assert(type(details.numEpisodes) == "number")
	assert(type(details.url or "") == "string")
	assert(type(details.description) == "string")
	assert(type(details.pictureId) == "string")
	assert(type(details.lastUpdated) == "string")
	assert(type(details.isSeen) == "boolean")
	if (details.isSeen) then
		assert(type(details.seenDateYmd) == "string")
	end
end





local function testGetAnimeDetails_characters(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.getAnimeDetails_characters(%d)", aId))

	local chars = db.getAnimeDetails_characters(aId)
	verifyArray(chars, "table")
	for i = 1, chars.n do
		local char = chars[i]
		assert(type(char.name) == "string")
		assert(type(char.gender) == "string")
		assert(type(char.description or "") == "string")
		assert(type(char.pictureId or "") == "string")
		assert(type(char.notes or "") == "string")
		if (char.voiceActors) then
			verifyArray(char.voiceActors, "table")
			for j = 1, char.voiceActors.n do
				local va = char.voiceActors[j]
				assert(type(va.name) == "string")
				assert(type(va.pictureId) == "string")
				assert(type(va.language) == "string")
				assert(type(va.episodes or "") == "string")
				assert(type(va.notes or "") == "string")
			end
		end
	end
end





local function testGetAnimeDetails_creators(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.getAnimeDetails_creators(%d)", aId))

	local creators = db.getAnimeDetails_creators(aId)
	verifyArray(creators, "table")
	for i = 1, creators.n do
		local creator = creators[i]
		assert(creator.aId == aId)
		assert(type(creator.name) == "string")
		assert(type(creator.kind) == "string")
	end
end





local function testGetAnimeDetails_episodes(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.getAnimeDetails_episodes(%d)", aId))

	local episodes = db.getAnimeDetails_episodes(aId)
	verifyArray(episodes, "table")
	for i = 1, episodes.n do
		local episode = episodes[i]
		assert(episode.aId == aId)
		assert(type(episode.episodeNumber) == "string")
		assert(type(episode.length) == "number")
		verifyYmd(episode.airDateYmd)
		verifyTitles(episode.titles)
		for j = 1, episode.titles.n do  -- Also check that each item has the corresponding aId:
			local title = episode.titles[j]
			assert(title.aId == aId)
		end
	end
end





local function testGetAnimeDetails_recommendations(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.getAnimeDetails_recommendations(%d)", aId))

	local recommendations = db.getAnimeDetails_recommendations(aId)
	verifyArray(recommendations, "table")
	for i = 1, recommendations.n do
		local rec = recommendations[i]
		assert(type(rec.kind) == "string")
		assert(type(rec.text) == "string")
	end
end





local function testGetAnimeDetails_relatedAnime(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.getAnimeDetails_relatedAnime(%d)", aId))

	local relations = db.getAnimeDetails_relatedAnime(aId)
	verifyArray(relations, "table")
	for i = 1, relations.n do
		local rel = relations[i]
		assert(type(rel.relatedAid) == "number")
		assert(type(rel.relation) == "string")
		assert(type(rel.isSeen) == "boolean")
		if (rel.isSeen) then
			assert(type(rel.seenDateYmd) == "string")
		end
		verifyTitles(rel.titles)
	end
end





local function testGetAnimeDetails_similarAnime(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.getAnimeDetails_similarAnime(%d)", aId))

	local similars = db.getAnimeDetails_similarAnime(aId)
	verifyArray(similars, "table")
	for i = 1, similars.n do
		local sim = similars[i]
		assert(type(sim.similarAid) == "number")
		assert(type(sim.isSeen) == "boolean")
		if (sim.isSeen) then
			assert(type(sim.seenDateYmd) == "string")
		end
		verifyTitles(sim.titles)
	end
end





local function testGetAnimeDetails_tags(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.getAnimeDetails_tags(%d)", aId))

	local tags = db.getAnimeDetails_tags(aId)
	verifyArray(tags, "table")
	for i = 1, tags.n do
		local tag = tags[i]
		assert(type(tag.tagId) == "number")
		assert(type(tag.weight) == "number")
		assert(type(tag.name or "") == "string")
		assert(type(tag.description or "") == "string")
	end
end





local function testGetAnimeDetails_titles(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.getAnimeDetails_titles(%d)", aId))

	local titles = db.getAnimeDetails_titles(aId)
	verifyTitles(titles)
end





local function testGetAnimeDetails(aId)
	assert(type(aId) == "number")

	-- Test values set specifically by db.getAnimeDetails():
	print(strFormat("Testing db.getAnimeDetails(%d)", aId))
	local details = db.getAnimeDetails(aId)
	assert(type(details) == "table")
	assert(type(details.enTitle or "") == "string")
	assert(type(details.jaTitle or "") == "string")
	assert(type(details.xjatTitle or "") == "string")

	-- Test the individual sub-tables:
	testGetAnimeDetails_base(aId)
	testGetAnimeDetails_characters(aId)
	testGetAnimeDetails_creators(aId)
	testGetAnimeDetails_episodes(aId)
	testGetAnimeDetails_recommendations(aId)
	testGetAnimeDetails_relatedAnime(aId)
	testGetAnimeDetails_similarAnime(aId)
	testGetAnimeDetails_tags(aId)
	testGetAnimeDetails_titles(aId)
end





local function testGetLastAniDbUpdate()
	print("Testing db.getLastAniDbUpdate")
	local lastUpdate = db.getLastAniDbUpdate()
	assert(type(lastUpdate) == "number")
end





local function testGetSeenAnime()
	print("Testing db.getSeenAnime()")
	local seen = db.getSeenAnime()
	verifyArray(seen, "table")
	for i = 1, seen.n do
		local s = seen[i]
		assert(type(s.aId) == "number")
		verifyYmd(s.seenDateYmd)
	end
end





local function testGetSeenAnimeForHomepage()
	print("Testing db.getSeenAnimeForHomepage()")
	local seen = db.getSeenAnimeForHomepage()
	verifyArray(seen, "table")
	for i = 1, seen.n do
		local s = seen[i]
		assert(type(s.aId) == "number")
		verifyYmd(s.seenDateYmd)
		assert(type(s.startDate or "") == "string")
		assert(type(s.endDate or "") == "string")
		assert(type(s.numEpisodes or 0) == "number")
		assert(type(s.pictureId or "") == "string")
		verifyTitles(s.titles)
	end
end





local function testGetSeenWithoutDetails()
	print("Testing db.getSeenWithoutDetails()")
	local seen = db.getSeenWithoutDetails()
	verifyArray(seen, "number")
end





local function testGetVoiceActorDetails(aVoiceActorID)
	assert(type(aVoiceActorID) == "number")
	print(strFormat("Testing db.getVoiceActorDetails(%d)", aVoiceActorID))
	local details = db.getVoiceActorDetails(aVoiceActorID)
	assert(type(details) == "table")
	assert(type(details.name) == "string")
	verifyArray(details.characters, "table")
	for i = 1, details.characters.n do
		local ch = details.characters[i]
		assert(type(ch.language or "") == "string")
		assert(type(ch.episodes or "") == "string")
		assert(type(ch.vaNotes or "") == "string")
		assert(type(ch.characterId) == "number")
		assert(type(ch.name) == "string")
		assert(type(ch.description or "") == "string")
		assert(type(ch.pictureId or "") == "string")
		assert(type(ch.aId) == "number")
		verifyMaybeDate(ch.animeStartDate)
		verifyMaybeDate(ch.animeEndDate)
		assert(type(ch.isSeen) == "boolean")
		verifyYmd(ch.seenDateYmd)
	end
end





local function testGetVoiceActors()
	print("Testing db.getVoiceActors()")
	local vas = db.getVoiceActors()
	verifyArray(vas, "table")
	for i = 1, vas.n do
		local va = vas[i]
		assert(type(va.name) == "string")
		assert(type(va.gender or "") == "string")
		assert(type(va.pictureId or "") == "string")
		assert(type(va.description or "") == "string")
		assert(type(va.country or "") == "string")
		assert(type(va.birthdate or "") == "string")
	end
end





local function testRawSeenIdsFrom(aFrom)
	assert(aFrom ~= nil)
	print(strFormat("Testing db.rawSeenIdsFrom(%q)", tostring(aFrom)))
	local ids = db.rawSeenIdsFrom(aFrom)
	verifyArray(ids, "table")
	for i = 1, ids.n do
		local id = ids[i]
		assert(type(id.aId) == "number")
		verifyYmd(id.seenDateYmd)
	end
end





local function testRawWatchlist()
	print("Testing db.rawWatchlist()")
	local watchlist = db.rawWatchlist()
	verifyArray(watchlist, "table")
	for i = 1, watchlist.n do
		local item = watchlist[i]
		assert(type(item.watchlistSeason) == "string")
		assert(type(item.caption) == "string")
		assert(type(item.utcSecondsSinceWeekStart or 0) == "number")
		if (item.utcSecondsSinceWeekStart) then
			assert(item.utcSecondsSinceWeekStart >= 0)
			assert(item.utcSecondsSinceWeekStart <= 7 * 24 * 60 * 60)
		end
		assert(type(item.aId or 0) == "number")
		assert(type(item.url or "") == "string")
	end
end





local function testWatchlistInSeason(aSeason)
	assert(type(aSeason) == "string")
	print(strFormat("Testing db.watchlistInSeason(%q)", aSeason))
	local watchlist = db.watchlistInSeason(aSeason)
	verifyArray(watchlist, "table")
	for i = 1, watchlist.n do
		local item = watchlist[i]
		-- Raw watchlist DB table:
		assert(type(item.watchlistSeason) == "string")
		assert(type(item.caption) == "string")
		assert(type(item.utcSecondsSinceWeekStart or 0) == "number")
		if (item.utcSecondsSinceWeekStart) then
			assert(item.utcSecondsSinceWeekStart >= 0)
			assert(item.utcSecondsSinceWeekStart <= 7 * 24 * 60 * 60)
		end
		assert(type(item.aId or 0) == "number")
		assert(type(item.url or "") == "string")

		-- WatchUrls:
		assert(type(item.lastWatchUrlQueryTimestamp or 0) == "number")
		if (item.watchUrls) then
			verifyArray(item.watchUrls, "table")
			for j = 1, item.watchUrls.n do
				local wu = item.watchUrls[j]
				assert(type(wu.providerName) == "string")
				assert(type(wu.createdOnYmd) == "string")
				assert(utils.ymdToTimestamp(wu.createdOnYmd))
				assert(type(wu.watchUrl) == "string")
			end
		end
	end
end





local function testWatchlistItem(aItemId)
	assert(type(aItemId) == "number")
	print(strFormat("Testing db.watchlistItem(%d)", aItemId))

	local item = db.watchlistItem(aItemId)
	assert(type(item) == "table")
	assert(type(item.watchlistSeason) == "string")
	assert(type(item.caption) == "string")
	assert(type(item.utcSecondsSinceWeekStart or 0) == "number")
	if (item.utcSecondsSinceWeekStart) then
		assert(item.utcSecondsSinceWeekStart >= 0)
		assert(item.utcSecondsSinceWeekStart <= 7 * 24 * 60 * 60)
	end
	assert(type(item.aId or 0) == "number")
	assert(type(item.url or "") == "string")
end





local function testWatchlistSeasonsForAnime(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.watchlistSeasonsForAnime(%d)", aId))
	local seasons = db.watchlistSeasonsForAnime(aId)
	verifyArray(seasons, "string")
end





local function testWatchUrlsForAnime(aId)
	assert(type(aId) == "number")
	print(strFormat("Testing db.watchUrlsForAnime(%d)", aId))
	local wurls = db.watchUrlsForAnime(aId)
	verifyArray(wurls, "table")
	for i = 1, wurls.n do
		local item = wurls[i]
		assert(type(item.providerName) == "string")
		assert(type(item.createdOnYmd) == "string")
		assert(utils.ymdToTimestamp(item.createdOnYmd))
		assert(type(item.url) == "string")
	end
end





testAllAnimeIDs()
testAllConfigValues()
testAnimeInSeason("2025-1")
testAnimeInSeason("2026-2")
testGetAnimeDetails(1)
testGetAnimeDetails(7729)  -- Steins'Gate
testGetAnimeDetails(19628)  -- OtaGal
testGetLastAniDbUpdate()
testGetSeenAnime()
testGetSeenAnimeForHomepage()
testGetSeenWithoutDetails()
testGetVoiceActorDetails(2296)   -- Hayami Saori
testGetVoiceActorDetails(53526)  -- Hasegawa Ikumi
testGetVoiceActorDetails(139)    -- Koyasu Takehito
testGetVoiceActors()
testRawSeenIdsFrom("2026-01-01")
testRawSeenIdsFrom("0")
testRawSeenIdsFrom("a")
testRawWatchlist()
testWatchlistInSeason("2025-4")
testWatchlistInSeason("2026-2")
testWatchlistItem(1)
testWatchlistItem(10)
testWatchlistSeasonsForAnime(7729)  -- Steins;Gate
testWatchlistSeasonsForAnime(19628)  -- OtaGal
testWatchUrlsForAnime(7729)  -- Steins;Gate
testWatchUrlsForAnime(19628)  -- OtaGal
