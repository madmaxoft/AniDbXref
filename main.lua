-- main.lua

-- Implements the main app entrypoint





--- Same as Lua's built-in require, but on failure reports to the user a help string
-- containing the specified LuaRocks' rock name to install
local function requireWithHelp(aModuleName, aLuaRocksRockName)
	assert(type(aModuleName) == "string")

	-- Attempt to load the module:
	local isSuccess, m = pcall(require, aModuleName)
	if (isSuccess) then
		return m
	end

	-- Module not found, instruct the user to use LuaRocks to install it:
	if not(aLuaRocksRockName) then
		-- No LuaRocks rock name given, output a generic error message:
		error("Cannot load module " .. aModuleName .. ": " .. tostring(m))
	end
	error(string.format(
		"Cannot load module %s: %s\n\n" ..
		"You can install it using the following LuaRocks command:\n" ..
		"sudo luarocks install %s",
		aModuleName, tostring(m),
		aLuaRocksRockName
	))
end





-- Load all the required rocks, in their dependency order:
local lfs       = requireWithHelp("lfs",       "luafilesystem")
local socket    = requireWithHelp("socket",    "luasocket")
local copas     = requireWithHelp("copas",     "copas")
local sqlite    = requireWithHelp("lsqlite3",  "lsqlite3")
local lxp       = requireWithHelp("lxp",       "luaexpat")
local etlua     = requireWithHelp("etlua",     "etlua")
local lzlib     = requireWithHelp("zlib",      "lzlib")
local multipart = requireWithHelp("multipart", "multipart")

-- Load the templates and utils:
local log = require("logger").log
require("Templates")
require("httpResponse")
require("httpRequest")
local db = require("db")
db.createSchema()
require("aniDbDetails")
local requestQueue = require("requestQueue")
local router = require("router")





--- Starts the Copas HTTP server on port 8080
local function startServer()
	local serverSocket = assert(socket.bind("*", 8080))
	log("main", "Server running on http://localhost:8080/")

	copas.mainServer = serverSocket
	copas.addserver(serverSocket, function(aSocket)
		router.handleRequest(copas.wrap(aSocket))
	end)

	copas.loop()
	log("main", "Server loop terminated.")
end





--- Queues requesting details through AniDB API
local function startRequestingDetails()
	-- Start the background requester thread:
	copas.addthread(function()
		requestQueue.run()
	end)

	-- Add those that are marked as seen but have no details stored:
	local seenWithoutDetails = db.getSeenWithoutDetails()
	log("RequestQueue", "Queueing API calls for %d items.", seenWithoutDetails.n)
	for _, aid in ipairs(seenWithoutDetails) do
		requestQueue.add(aid)
	end
end





--- Entry point
startRequestingDetails()
startServer()
log("main", "Finished.")
