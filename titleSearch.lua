-- titleSearch.lua

--[[
Implements an object responsible for searching many text items for a best match. Produces possibly multiple
results, which are ranked by similarity. Used to search anime by its title, word by word.

Works by incrementally building an index of word -> ids containing the word, then queries are
split by words, each word adds score to each id, and the ids with the highest score are returned.

Supports initial batch load and incremental additions. Doesn't support removals.

Usage:
	local search = require("titleSearch").new()
	for id, title in pairs(anime) do
		search:insert(title, id)
	end
	...
	local found = search:query("some title text")
--]]





local fuzzyWordIndex = require("fuzzyWordIndex")





--- The API of this module
local titleSearch = {}
titleSearch.__index = titleSearch





--- Creates a new titleSearch instance
function titleSearch.new()
	local self =
	{
		--- Dict-table of word -> { id1 = true, id2 = true, ... }
		mIndex = {},

		--- Dict-table of id -> original title
		mTitles = {},

		--- word matcher fuzzy-search
		mFuzzyWordIndex = fuzzyWordIndex.new(),

		--- Statistics for debugging and tuning
		mStats =
		{
			numWords = 0,
			numTitles = 0,
		}
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
	for word in aTitle:lower():gmatch("[%w']+") do
		local bucket = self.mIndex[word]
		if not(bucket) then
			bucket = {n = 0}
			self.mIndex[word] = bucket
			self.mFuzzyWordIndex:insert(word)
			self.mStats.numWords = self.mStats.numWords + 1
		end
		if not(bucket[aId]) then
			bucket.n = bucket.n + 1
			bucket[aId] = true
		end
	end
	self.mStats.numTitles = self.mStats.numTitles + 1
end





--- Queries the search index
-- Returns array of: {aId = ..., title = ...}
function titleSearch:query(aQuery)
	assert(type(self) == "table")
	assert(type(aQuery) == "string")

	-- Collect the score for each relevant id:
	local scores = {}
	local maxScore = 0
	for queryWord in aQuery:lower():gmatch("[%w']+") do
		-- Search the fuzzyWordIndex, if word not found:
		local matchedWords
		if (self.mIndex[queryWord]) then
			matchedWords = {{word = queryWord, distance = 0}}
		else
			local maxDistance
			if (#queryWord <= 3) then
				-- For up-to-3-letter words we want an exact match, but there isn't one
				matchedWords = {}
			else
				if (#queryWord <= 6) then
					maxDistance = 1
				else
					maxDistance = 2
				end
				matchedWords = self.mFuzzyWordIndex:search(queryWord, maxDistance)
			end
		end

		-- Add the score for all fuzzy-matched words:
		for _, matchedWord in ipairs(matchedWords) do
			local bucket = self.mIndex[matchedWord.word]
			if (bucket) then
				local addition = 100 / bucket.n  -- Make less-common words more important
				addition = addition / (matchedWord.distance + 1)
				for id, _ in pairs(bucket) do
					local newScore = (scores[id] or 0) + addition
					scores[id] = newScore
					if (newScore > maxScore) then
						maxScore = newScore
					end
				end
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

	-- Return at most 50 results:
	for i = 50, n do
		results[i] = nil
	end
	results.n = math.min(50, n)

	-- collectgarbage()
	return results
end





return titleSearch
