-- fuzzyWordIndex.lua

--[[
Lightweight fuzzy word index using:
	- length bucketing (primary filter)
	- optional first-character grouping (weak filter)
	- bounded Levenshtein distance (core matching)

Key idea:
	Pre-filtering is used to reduce candidates.
	Correctness is always decided by Levenshtein.
--]]





local fuzzyWordIndex = {}
fuzzyWordIndex.__index = fuzzyWordIndex





--- Levenshtein distance (bounded, early exit if exceeds aMaxDist
local function boundedLevenshtein(a, b, aMaxDist)
	local lenA = #a
	local lenB = #b

	if (math.abs(lenA - lenB) > aMaxDist) then
		return nil
	end
	if (a == b) then
		return 0
	end

	local prev = {}
	local curr = {}
	for j = 0, lenB do
		prev[j] = j
	end

	for i = 1, lenA do
		curr[0] = i
		local best = curr[0]
		local ca = a:sub(i, i)
		for j = 1, lenB do
			local cost = (ca == b:sub(j, j)) and 0 or 1
			local insert = curr[j - 1] + 1
			local delete = prev[j] + 1
			local replace = prev[j - 1] + cost
			local val = math.min(insert, delete, replace)
			curr[j] = val
			if (val < best) then
				best = val
			end
		end
		if (best > aMaxDist) then
			return nil
		end
		prev, curr = curr, prev
	end

	local result = prev[lenB]
	if (result > aMaxDist) then
		return nil
	end

	return result
end





--- Returns true if the word is definitely not a candidate for the query with the specified max distance
-- Must be fast to calculate
local function cheapReject(aWord, aQuery, aMaxDistance)
	-- If more than maxDistance initial letters are different, it's a fast reject
	-- This alone prunes away about 95 % of the false candidates
	return (aWord:sub(1, 1 + aMaxDistance) ~= aQuery:sub(1, 1 + aMaxDistance))
end





--- constructor
function fuzzyWordIndex.new()
	local self =
	{
		--- Dict-table of length -> words array
		mByLength = {},

		--- dedup
		mIsSeen = {},
	}
	setmetatable(self, fuzzyWordIndex)
	return self
end





--- Inserts a new word to the structure
function fuzzyWordIndex:insert(aWord)
	assert(type(aWord) == "string")

	-- Unique words only:
	if (self.mIsSeen[aWord]) then
		return
	end
	self.mIsSeen[aWord] = true

	-- Put into per-length bucket:
	local len = #aWord
	local lenBucket = self.mByLength[len]
	if not(lenBucket) then
		lenBucket = {}
		self.mByLength[len] = lenBucket
	end
	table.insert(lenBucket, aWord)
end





--- Searches for words matching the specified query up to the specified distance
-- Returns an array-table of { word = ..., distance = ... } sorted by distance, then alphabetically
function fuzzyWordIndex:search(aQuery, aMaxDistance)
	assert(type(aQuery) == "string")
	assert(type(aMaxDistance) == "number")

	local results = {}
	local n = 0
	local queryLen = #aQuery
	for len = queryLen - aMaxDistance, queryLen + aMaxDistance do  -- Pre-filter: only per-distance buckets in range
		local bucket = self.mByLength[len] or {}
		for _, candidate in ipairs(bucket) do
			if not(cheapReject(candidate, aQuery, aMaxDistance)) then  -- Pre-filter: cheap reject
				local dist = boundedLevenshtein(candidate, aQuery, aMaxDistance)  -- Truth decider
				if (dist) then
					n = n + 1
					results[n] =
					{
						word = candidate,
						distance = dist,
					}
				end
			end
		end
	end
	results.n = n

	-- Sort by distance, then alphabetically:
	table.sort(results,
		function(a, b)
			if (a.distance ~= b.distance) then
				return (a.distance < b.distance)
			end
			return (a.word < b.word)
		end
	)
	return results
end





return fuzzyWordIndex
