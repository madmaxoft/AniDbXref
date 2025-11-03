-- Templates/init.lua
-- Auto-reloads all .html templates from this directory
-- and exposes them by name (without extension).

local etlua = require("etlua")

local templates = {}

local function loadTemplate(aTemplateName)
	local path = "Templates/" .. aTemplateName .. ".html"
	local f = assert(io.open(path, "r"))
	local content = f:read("*a")
	f:close()
	return etlua.compile(content)
end

--- Returns a function that reloads the template from disk each call
setmetatable(templates, {
	__index = function(t, aTemplateName)
		local tplFunc = loadTemplate(aTemplateName)
		-- rawset(t, aTemplateName, tplFunc)
		return tplFunc
	end
})

return templates
