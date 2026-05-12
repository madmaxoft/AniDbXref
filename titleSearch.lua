-- titleSearch.lua

--[[
Implements an object responsible for searching many text items for a best match. Produces possibly multiple
results, which are ranked by similarity. Used to search anime by its title, word by word.

Works by incrementally building an index of word -> array of ids containing the word, then queries are
split by words, each word produces a set of ids, those are then intersected to give the results.

Supports initial batch load and incremental additions. Doesn't support removals.

Usage:
	local search = require("titleSearch").new()
	for id, title in pairs(anime) do
		search:insert(title, id)
	end
	...
	local found = search:query("some title text")
--]]





--- The API of this module
local titleSearch = {}
titleSearch.__index = titleSearch





--- Splits text into normalized searchable words
local function tokenize(aText)
	assert(type(aText) == "string")

	local words = {}
	for word in aText:lower():gmatch("[%w']+") do
		table.insert(words, word)
	end
	return words
end





--- Removes items from aSetToChange that are not in aArrayToKeep
local function removeFromSet(aSetToChange, aArrayToKeep)
	assert(type(aSetToChange) == "table")
	assert(aSetToChange.currentMarker)
	assert(type(aArrayToKeep) == "table")

	local currentMarker = aSetToChange.currentMarker
	local newMarker = currentMarker + 1
	for _, value in ipairs(aArrayToKeep) do
		if (aSetToChange[value] == currentMarker) then
			aSetToChange[value] = newMarker
		end
	end
	aSetToChange.currentMarker = newMarker
end





--- Creates a new titleSearch instance
function titleSearch.new()
	local self =
	{
		--- Dict-table of word -> { id1, id2, ... }
		mIndex = {},

		--- Dict-table of id -> original title
		mTitles = {},
	}
	setmetatable(self, titleSearch)
	return self
end





--- Inserts a title with associated ID into the search index
function titleSearch:insert(aTitle, aId)
	assert(type(aTitle) == "string")
	assert(aId ~= nil)

	-- Insert mapping of the original title from the id:
	self.mTitles[aId] = aTitle

	-- Insert each word into the index:
	local alreadyInserted = {}  -- Dict of word -> true for already-inserted words, to avoid duplicate insertions
	for _, word in ipairs(tokenize(aTitle)) do
		if not(alreadyInserted[word]) then
			alreadyInserted[word] = true
			local bucket = self.mIndex[word]
			if not(bucket) then
				bucket = {n = 0}
				self.mIndex[word] = bucket
			end
			if not(bucket[aId]) then
				bucket.n = bucket.n + 1
				bucket[aId] = true
			end
		end
	end
end





--- Queries the search index
-- Returns array of: {aId = ..., title = ...}
function titleSearch:query(aQuery)
	assert(type(self) == "table")
	assert(type(aQuery) == "string")

	local queryWords = tokenize(aQuery)
	if (#queryWords == 0) then
		return {n = 0}
	end

	-- Collect the score for each relevant id:
	local scores = {}
	local maxScore = 0
	for _, word in ipairs(queryWords) do
		local bucket = self.mIndex[word]
		if not(bucket) then
			return {n = 0}
		end
		local addition = 100 / bucket.n
		for id, _ in pairs(bucket) do
			local newScore = (scores[id] or 0) + addition
			scores[id] = newScore
			if (newScore > maxScore) then
				maxScore = newScore
			end
		end
	end
	scores.n = nil  -- Remove the extra member created from bucket.n for each word bucket

	-- Convert from per-id scores into an array of top score ids
	local results = {}
	local n = 0
	maxScore = maxScore / 4
	for id, score in pairs(scores) do
		if (score >= maxScore) then
			n = n + 1
			results[n] = {aId = id, score = score}
		end
	end
	table.sort(results,
		function (aItem1, aItem2)
			-- Compare by score; sort same-score by title:
			if (math.abs(aItem1.score - aItem2.score) > 0.00001) then
				return (aItem1.score > aItem2.score)
			end
			return (self.mTitles[aItem1.aId] < self.mTitles[aItem2.aId])
		end
	)
	for i = 50, n do
		results[i] = nil
	end
	results.n = math.min(50, n)

	-- collectgarbage()
	return results
end





return titleSearch
