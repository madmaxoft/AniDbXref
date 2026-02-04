-- templateUtils.lua

--[[
Provides utility functions that are injected into each template call as the `utils` member.
--]]





local utils = {}





local gHtmlEscapeEntities = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
  ["'"] = '&#039;'
}




--- Escapes all characters that have special meaning in HTML with their respective HTML entities
function utils.htmlEscape(aStr)
	assert(type(aStr) == "string")

	return (aStr:gsub([=[["><'&]]=], gHtmlEscapeEntities))
end





--- Rewrites the specified description, parsing links and changing anidb.net links into our own.
-- Also changes linebreaks into <br />
function utils.htmlizeDescription(aDesc)
	assert(type(aDesc) == "string")

	-- Format commonly used sequences:
	local res = "<p>" .. utils.htmlEscape(aDesc) .. "</p>"
	res = res:gsub("\r\n", "</p><p>"):gsub("\n", "</p><p>"):gsub("\r", "</p><p>")
	res = res:gsub("<p>%s*Note:(.-)</p>", "<p><i>Note: %1</i></p>")
	res = res:gsub("<p>%s*%*(.-)</p>", "<p><i>%1</i></p>")
	res = res:gsub("%[i%](.-)%[/i%]", "<i>%1</i>")
	res = res:gsub("(https*://%S*) %[(.-)%]", "<a href=\"%1\">%2</a>")

	-- Replace anidb.net links with our own:
	res = res:gsub("http://anidb.net/([a-zA-Z0-9]+)",
		function(aUrlPath)
			local prefix, number = aUrlPath:match("([a-zA-Z]+)([0-9]+)")
			if (prefix == "a") then
				return "/anime/" .. tostring(number)
			end
			return "http://anidb.net/" .. aUrlPath
		end
	)

	return res
end





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
	local res = titles["main"] or titles["official"] or titles["syn"] or titles["short"] or titles[""]
	if (res) then
		return res
	end

	-- No title in this language found, use "en":
	res = enTitles["main"] or enTitles["official"] or enTitles["syn"] or enTitles["short"] or enTitles[""]
	if (res) then
		return res
	end

	-- No title in this language or "en", use any:
	return anyTitles["main"] or anyTitles["official"] or anyTitles["syn"] or anyTitles["short"] or anyTitles[""]
end





--- Converts a timestamp to an YYYY-MM-DD string, used by the <input type="date"> element.
function utils.toIsoDate(aTimeStamp)
	if not(aTimeStamp) then
		return ""
	end
	return os.date("!%Y-%m-%d", aTimeStamp)
end





return utils
