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
print = require("logger")
require("Templates")
require("httpResponse")
require("httpRequest")
local db = require("db")
db.createSchema()
require("aniDbDetails")
local requestQueue = require("requestQueue").new()
local router = require("router")





--- Reads and parses an incoming HTTP request line and headers
-- Returns method (string), path (string) and headers (combined lowercase-dict- and array- table)
local function parseRequest(aClient)
	local request = aClient:receive("*l")
	if not(request) then
		return nil, nil, nil
	end

	local method, path = request:match("^(%S+)%s+(%S+)")
	local headers = { n = 0 }

	while (true) do
		local line = aClient:receive("*l")
		if (not(line) or line == "") then
			break
		end

		local key, value = line:match("^(.-):%s*(.*)")
		if (key and value) then
			headers[key:lower()] = value
			headers.n = headers.n + 1
			headers[headers.n] = { key = key, value = value }
		end
	end

	return method, path, headers
end




--- Handles a single HTTP client connection
local function handleRequest(aClient)
	local method, path, headers = parseRequest(aClient)
	if (not(method) or not(path)) then
		return
	end

	local handler, params = router.match(method, path)
	if (handler) then
		print(string.format("[main] %s Request for path \"%s\".", method, path))
		handler(aClient, path, params, headers)
	else
		print(string.format("[main] UNHANDLED: %s Request for path \"%s\".", method, path))
		aClient:send("HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\nNot Found")
	end
end





--- Starts the Copas HTTP server on port 8080
local function startServer()
	local serverSocket = assert(socket.bind("*", 8080))
	print("[main] Server running on http://localhost:8080/")

	copas.addserver(serverSocket, function(aSocket)
		handleRequest(copas.wrap(aSocket))
	end)

	copas.loop()
end





--- Queues requesting details through AniDB API
local function startRequestingDetails()
	-- Start the background requester thread:
	copas.addthread(function()
		requestQueue:run()
	end)

	-- Add those that are marked as seen but have no details stored:
	local seenWithoutDetails = db.getSeenWithoutDetails()
	for _, aid in ipairs(seenWithoutDetails) do
		requestQueue:add(aid)
	end
end





--- Entry point
startRequestingDetails()
startServer()
