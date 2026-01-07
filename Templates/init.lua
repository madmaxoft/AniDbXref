-- Templates/init.lua

--[[
Auto-reloads all .html templates from this directory
and exposes them by name (without extension).
--]]

local etlua = require("etlua")
local log = require("logger").log





local templates = {}





local function loadTemplate(aTemplateName)
	local path = "Templates/" .. aTemplateName .. ".html"
	local f = assert(io.open(path, "rb"))
	local content = f:read("*a")
	f:close()
	return etlua.compile(content)
end





--- Returns a function that reloads the template from disk each call
setmetatable(templates,
	{
		__index = function(t, aTemplateName)
			local tmplFunc, msg = loadTemplate(aTemplateName)
			if not(tmplFunc) then
				log("templates", "Failed to load template %s: %s", aTemplateName, tostring(msg))
			end
			-- rawset(t, aTemplateName, tmplFunc)  -- Uncomment to not-reload
			return tmplFunc, msg
		end
	}
)

return templates
