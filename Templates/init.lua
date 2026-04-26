-- Templates/init.lua

--[[
Auto-reloads all .html templates from this directory
and exposes them by name (without extension).
--]]

local etlua = require("etlua")
local log = require("logger").log





local templates = {}





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
			local tmplFunc, msg = loadTemplate(aTemplateName)
			if not(tmplFunc) then
				log("templates", "Failed to load template %s: %s", aTemplateName, tostring(msg))
			end
			-- rawset(t, aTemplateName, tmplFunc)  -- Uncomment to not-reload
			return tmplFunc, msg
		end
	}
)




--- Dumps the Lua code for the specified template to a file "${aTemplateName}.compiledLua"
function templates.dump(aTemplateName)
	assert(type(aTemplateName) == "string")

	local path = "Templates/" .. aTemplateName .. ".html"
	local f = assert(io.open(path, "rb"))
	local content = f:read("*a")
	f:close()
	local parser = etlua.Parser()
	local luaCode = parser:compile_to_lua(content)
	f = assert(io.open("Templates/" .. aTemplateName .. ".compiledLua", "wb"))
	f:write(luaCode)
	f:close()
end





return templates
