-- Tests/test-watchUrlProviders.lua

--[[
Implements a simple test harness for running a watchUrlProvider query in a single-threaded manner,
so that it can be investigated using an IDE debugger
--]]





--- The anime ID to query
local gId = 7729  -- Steins;Gate
-- local gId = 17001  -- Fuufu Ijou





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;./?.lua;Tests/?.lua" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true

require("httpClient").noCopas()  -- Disable Copas in the underlying httpClient
local utils = require("utils")
local wup = require("watchUrlProviders")




local res, msg = wup.queryAndStore(gId)
if not(res) then
	print("Failed to query WUP: " .. tostring(msg))
	return
end
print("WUP query finished:")
print(utils.serializeSimpleTable(res))
