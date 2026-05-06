-- templateUtils.lua

--[[
Provides utility functions that are injected into each template call as the `utils` member.
All the utils in the utils.lua package are inserted.

Since the utils are bound to the template, they need to be initialized with the template environment,
so the module returns a function that needs to be called with the template environment as its parameter:

	aTemplateParams.utils = require("templateUtils")(aTemplateParams)
--]]





local utils = require("utils")





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





--- Converts a timestamp to an YYYY-MM-DD string, used by the <input type="date"> element.
function utils.toIsoDate(aTimeStamp)
	if not(aTimeStamp) then
		return ""
	end
	return os.date("!%Y-%m-%d", aTimeStamp)
end






--- Returns a new table that has members from both environments
-- If a value is in both environments, the main environment takes precedence
local function mergeEnv(aMainEnv, aSecondaryEnv)
	local merged = {}
	for k, v in pairs(aSecondaryEnv or {}) do
		merged[k] = v
	end
	for k, v in pairs(aMainEnv or {}) do
		merged[k] = v
	end
	return merged
end





-- Wrap the module in a function that generates a new context for each template environment:
return function(aEnv)
	local res = {__index = utils}
	setmetatable(res, res)
	res.include = function(aTemplateName, aSubEnv)
		local templates = require("Templates")
		return templates[aTemplateName](mergeEnv(aSubEnv, aEnv))
	end
	return res
end
