-- Templates/init.lua

--[[
Auto-reloads all .html templates from this directory
and exposes them by name (without extension).
--]]

local etlua = require("etlua")
local log = require("logger").log
local config = require("config")





--- The module API, returned from requiring this file
-- Behaves as a dict-table of TemplateName -> TemplateFunction, but lazy-evaluated
local templates = {}

--- Cache of the loaded templates (unless config option `hotreload.templates` is enabled)
-- TemplateName -> TemplateFunction
local gCache = {}






config.registerDefinitions({
	{
		identifier = "hotreload.templates",
		description = "Reload each HTML template before executing it",
		category = "Reload code",
		valueType = "bool",
		default = false,
	},
})





local function loadTemplate(aTemplateName)
	assert(type(aTemplateName) == "string")

	-- Load the template contents:
	local path = "Templates/" .. aTemplateName .. ".html"
	local f = assert(io.open(path, "rb"))
	local content = f:read("*a")
	f:close()

	-- Compile it using etlua, remember the lineMap (for error reporting):
	local parser = etlua.Parser()
	local luaCode, lineMap = parser:compile_to_lua(content)
	if not(luaCode) then
		error("Failed to compile template: " .. tostring(lineMap))
	end
	local compiled = assert(loadstring(luaCode, "@" .. path))

	-- Return a closure that executes the template on call and reports original template linenumbers on error:
	return function(aParams)
		local function errorHandler(aErr)
			local trace = debug.traceback(tostring(aErr), 2)

			-- Write compiled Lua for debugging:
			local dumpPath = path .. ".compiledLua"
			local out = io.open(dumpPath, "wb")
			if (out) then
				out:write(luaCode)
				out:close()
			end

			-- Rewrite stacktrace to point to the dumped file:
			trace = trace:gsub(
				path:gsub("([^%w])", "%%%1"),
				dumpPath
			)
			return trace
		end
		local isOK, result = xpcall(
			function()
				local buffer, i = parser:run(compiled, aParams)
				return table.concat(buffer, "", 1, i)
			end,
			errorHandler
		)
		if not(isOK) then
			log("template", "Template %s failed:\n%s", aTemplateName, result)
			return nil, result
		end

		return result
	end
end





--- Returns a function that reloads the template from disk each call
setmetatable(templates,
	{
		__index = function(t, aTemplateName)
		local isHotReload = config.get("hotreload.templates")

		-- Use cache only when hotreload disabled:
		if not(isHotReload) then
			local cached = gCache[aTemplateName]
			if (cached) then
				return cached
			end
		end

		-- Load from disk:
		local tmplFunc, msg = loadTemplate(aTemplateName)
		if not(tmplFunc) then
			log("templates", "Failed to load template %s: %s", aTemplateName, tostring(msg))
			return nil, msg
		end

		-- Store in cache only when hotreload disabled:
		if not(isHotReload) then
			gCache[aTemplateName] = tmplFunc
		end

		return tmplFunc, msg
	end
	}
)




return templates
