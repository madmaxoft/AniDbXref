-- templateUtils.lua

--[[
Provides utility functions that are injected into each template call as the `utils` member.
--]]





local utils = {}





--- Returns the "best" title from those specified, limited to the specified language
-- Returns nil if none found.
-- Prefers main title, then official title, then synonyms and last shorts
function utils.pickBestTitle(aTitlesFromDb, aLanguage)
	assert(type(aTitlesFromDb) == "table")
	assert(type(aLanguage) == "string")

	-- Pick the best title in the specified language:
	local titles = {}
	local enTitles = {}
	local anyTitles = {}
	for _, row in ipairs(aTitlesFromDb) do
		if (row.language == aLanguage) then
			titles[row.kind or ""] = row.title
		elseif (row.language == "en") then
			enTitles[row.kind or ""] = row.title
		end
		anyTitles[row.kind or ""] = row.title
	end
	local res = titles["main"] or titles["official"] or titles["syn"] or titles["short"]
	if (res) then
		return res
	end

	-- No title in this language found, use "en":
	res = enTitles["main"] or enTitles["official"] or enTitles["syn"] or enTitles["short"]
	if (res) then
		return res
	end

	-- No title in this language or "en", use any:
	return anyTitles["main"] or anyTitles["official"] or anyTitles["syn"] or anyTitles["short"]
end





--- Converts a timestamp to an YYYY-MM-DD string, used by the <input type="date"> element.
function utils.toIsoDate(aTimeStamp)
	if not(aTimeStamp) then
		return ""
	end
	return os.date("!%Y-%m-%d", aTimeStamp)
end





return utils
