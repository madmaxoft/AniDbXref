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
local json      = requireWithHelp("dkjson",    "dkjson")

-- Load the templates and utils:
package.path = "?/init.lua;" .. package.path  -- Load packages from a subfolder of the current folder
local log = require("logger").log
require("Templates")
local httpResponse = require("httpResponse")
local httpRequest  = require("httpRequest")
local requestTracker = require("requestTracker")
local db = require("db")
require("aniDbDetails")
local requestQueue = require("requestQueue")
local router = require("router")
local utils = require("utils")
local config = require("config")





config.registerDefinitions(
{
	{
		identifier = "http.port",
		description = "The port on which the main app HTTP server listens on. Must be free on the local system.",
		category = "HTTP",
		valueType = "number",
		default = 8080,
		validator = function(aValue)
			aValue = tonumber(aValue)
			if not(aValue) then
				return nil, "Not a number"
			end
			if ((aValue < 0) or (aValue > 65535)) then
				return nil, "Out of range; valid range is 0 - 65536."
			end
			return true
		end,
		isRestartRequired = true,
	},
})
config.loadAll()





--- Handles a single connected client, possibly with keep-alive:
local function clientLoop(aSocket)
	while true do
		local req, err = httpRequest.createFromSocket(aSocket)
		if not req then
			break
		end
		requestTracker.beginRequest()
		local resp = httpResponse.new(req)
		router.handleRequest(req, resp)
		resp:finish()
		req:discardUnreadBody()
		requestTracker.endRequest()
		if not(req:shouldKeepAlive(resp)) then
			break
		end
	end
	aSocket:close()
end





--- Starts the Copas HTTP server on port 8080
local function startServer()
	local port = config.get("http.port")
	local serverSocket = assert(socket.bind("*", port))
	log("main", "Server running on http://localhost:" .. port .. "/")

	copas.mainServerSocket = serverSocket
	copas.addserver(serverSocket, function(aSocket)
		clientLoop(copas.wrap(aSocket))
	end)

	copas.loop()
	log("main", "Server loop terminated.")
end





--- Queues requesting details through AniDB API
local function startRequestingDetails()
	-- Start the background requester thread:
	requestQueue.start()

	-- Add those that are marked as seen but have no details stored:
	local seenWithoutDetails = db.getSeenWithoutDetails()
	log("main", "Queueing API calls for details for %d items.", seenWithoutDetails.n)
	for _, aid in ipairs(seenWithoutDetails) do
		requestQueue.add(aid)
	end
end





--- Entry point
startRequestingDetails()
startServer()
log("main", "Finished.")
