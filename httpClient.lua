-- httpClient.lua

--[[
Implements a simple HTTP client singleton with keepalive pooling.
Usage:
local client = require("httpClient")
local status, headers, body = client.get("https://example.com", {header = "value"})
if not(status) then
	error(headers)
end

There's generic request() function that receives all params in a table, and shorthand get(), post() and
head() functions that call request() with the specified HTTP method.
--]]





local socket = require("socket")
local ssl = require("ssl")
local copas = require("copas")
local url = require("socket.url")
local httpUtils = require("httpUtils")
local requestTracker = require("requestTracker")
local log = require("logger").log





--- The module API returned from requiring this file
local httpClient = {}

--- Map of connectionKey -> connection (array-table of {socket = ..., isBusy = ..., lastUsed = ...} )
-- A busy connection cannot be reused yet (a request / response is pending on it)
local gConnectionPools = {}

local gConnectTimeout = 10
local gReadTimeout = 30
local gIdleTimeout = 30

--- If true, Copas is not used, falling back into synchronous single-request-at-a-time operation
-- See httpClient.noCopas()
local gDisableCopas = false

--- Max number of connections to a single host.
-- Further requests wait until an existing connection becomes available
local gMaxConnectionsPerHost = 4

--- Metrics, especially useful for tests. See httpClient.resetMetrics() for actually supported values
local gMetrics = {}





--- Returns the key used for the connection pool, based on the parsed URL table (see parseUrl())
local function connectionKey(aParsedUrl)
	assert(type(aParsedUrl) == "table")
	assert(type(aParsedUrl.host) == "string")

	return string.format(
		"%s:%s:%d",
		aParsedUrl.scheme,
		aParsedUrl.host,
		aParsedUrl.port
	)
end





--- Parses the URL into a dict-table of {scheme, host, port, path, isTls}
local function parseUrl(aUrl)
	assert(type(aUrl) == "string")

	local parsed, err = url.parse(aUrl)
	if not(parsed) then
		return nil, "Failed to parse URL: " .. tostring(err)
	end

	local scheme = parsed.scheme or "http"
	local host = parsed.host
	local port = parsed.port

	if not(host) then
		return nil, "URL is missing host"
	end

	local isTls
	if (scheme == "https") then
		isTls = true
		port = port or 443
	elseif (scheme == "http") then
		isTls = false
		port = port or 80
	else
		return nil, "Unsupported scheme: " .. tostring(scheme)
	end

	local path = parsed.path or "/"
	if (parsed.query) then
		path = path .. "?" .. parsed.query
	end

	return
	{
		scheme = scheme,
		host = host,
		port = port,
		path = path,
		isTls = isTls,
	}
end





--- Creates a connection to the host in the parsed Url table
-- aRequest is the originating request specification
-- Returns the connection usable in the pool
local function createConnection(aParsedUrl, aRequest)
	assert(type(aParsedUrl) == "table")
	assert(type(aParsedUrl.host) == "string")
	assert(type(aRequest) == "table")

	-- Create the socket:
	local sock, err = socket.tcp()
	if (sock == nil) then
		return nil, err
	end
	if not(gDisableCopas) then
		sock:settimeout(0)
	end

	-- Connect to the host:
	if not(aRequest.shouldSkipYields) then
		requestTracker.yieldUntilNoRequests()
	end
	log("httpClient", "Connecting to %s:%d...", aParsedUrl.host, aParsedUrl.port)
	local ok, err2 = sock:connect(aParsedUrl.host, aParsedUrl.port)
	if not(ok) and (err2 ~= "timeout") then
		return nil, err2
	end

	-- If TLS is needed, do the handshake:
	if (aParsedUrl.isTls) then
		local params =
		{
			mode = "client",
			protocol = "tlsv1_2",
			verify = "none",
			options = "all",
			server = aParsedUrl.host,
		}
		local tlsSock, err3 = ssl.wrap(sock, params)
		if not(tlsSock) then
			return nil, "Failed to initialize TLS: " .. tostring(err3)
		end
		sock = tlsSock
		if (sock.sni) then
			sock:sni(aParsedUrl.host)
		end

		local ok2, err4 = sock:dohandshake()
		if not(ok2) then
			return nil, "Failed to handshake TLS: " .. tostring(err4)
		end
	end

	-- Wrap only the final socket in Copas:
	if not(gDisableCopas) then
		sock = copas.wrap(sock)
	end

	gMetrics.numConnectionsCreated = gMetrics.numConnectionsCreated + 1
	gMetrics.numActiveConnections = gMetrics.numActiveConnections + 1

	return
	{
		socket = sock,
		isBusy = false,
		lastUsed = socket.gettime(),
	}
end





--- Returns whether connection is stale (closed or too long since last use)
local function isConnectionStale(aConn, aNow)
	assert(type(aConn) == "table")

	if not(aConn.socket) then
		return true
	end

	if ((aNow - aConn.lastUsed) > gIdleTimeout) then
		return true
	end

	return false
end





--- Returns a connection that can handle the specified parsed Url table
local function getConnection(aParsedUrl, aRequest)
	assert(type(aParsedUrl) == "table")
	assert(type(aParsedUrl.host) == "string")
	assert(type(aRequest) == "table")

	-- Create a pool if not exists yet:
	local key = connectionKey(aParsedUrl)
	local pool = gConnectionPools[key]
	if not(pool) then
		pool = {}
		gConnectionPools[key] = pool
	end

	-- Half-busy-wait until a connection is available:
	while (true) do
		local now = socket.gettime()
		local numActive = 0

		-- Cleanup + reuse scan:
		for i = #pool, 1, -1 do
			local conn = pool[i]
			if not(conn.socket) or ((now - conn.lastUsed) > gIdleTimeout) then
				-- Connection no longer usable, close and drop it:
				if (conn.socket) then
					gMetrics.numConnectionsClosed = gMetrics.numConnectionsClosed + 1
					gMetrics.numActiveConnections = gMetrics.numActiveConnections - 1
					pcall(function()
						conn.socket:close()
					end)
				end
				table.remove(pool, i)
			else
				if (conn.isBusy) then
					numActive = numActive + 1
				else
					conn.isBusy = true
					gMetrics.numConnectionsReused = gMetrics.numConnectionsReused + 1
					return conn
				end
			end
		end

		-- Create a new connection, if allowed
		if (numActive < gMaxConnectionsPerHost) then
			local conn, err = createConnection(aParsedUrl, aRequest)
			if not(conn) then
				return nil, err
			end
			conn.isBusy = true
			table.insert(pool, conn)
			return conn
		end

		-- No connection available and cannot create a new one, half-busy-wait:
		if not(gDisableCopas) then
			copas.sleep(0.01)
		end
	end
end





--- Releases the connection from use. If not reusable, the connection will get closed, otherwise it will be
-- available in the pool for next request.
local function releaseConnection(aConn, aIsReusable)
	aConn.isBusy = false
	aConn.lastUsed = socket.gettime()
	if not(aIsReusable) then
		gMetrics.numConnectionsClosed = gMetrics.numConnectionsClosed + 1
		gMetrics.numActiveConnections = gMetrics.numActiveConnections - 1
		pcall(function()
			aConn.socket:close()
		end)
		aConn.socket = nil
	end
end





--- Sends the specified request over the specified connection
-- Returns true on success, nil and error message on failure
local function sendRequest(aConn, aRequest, aParsedUrl)
	local sock = aConn.socket
	local method = aRequest.method or "GET"
	local headers = aRequest.headers or {}
	local body = aRequest.body
	local lines = {}
	table.insert(
		lines,
		string.format("%s %s HTTP/1.1", method, aParsedUrl.path)
	)
	headers["Host"] = headers["Host"] or aParsedUrl.host
	headers["Connection"] = headers["Connection"] or "keep-alive"
	headers["User-Agent"] = headers["User-Agent"] or "AniDbXref/1"
	if (body) then
		headers["Content-Length"] = tostring(#body)
	end
	for k, v in pairs(headers) do
		table.insert(
			lines,
			string.format("%s: %s", k, v)
		)
	end
	table.insert(lines, "")
	table.insert(lines, "")
	local requestData = table.concat(lines, "\r\n")
	--[[
	-- DEBUG:
	print(string.format("Request data for URL %s://%s/%s:", aParsedUrl.scheme, aParsedUrl.host, aParsedUrl.path))
	print(requestData)
	print("\n")
	--]]

	local ok, err = sock:send(requestData)
	if not(ok) then
		return nil, "Failed to send request headers: " .. tostring(err)
	end

	if (body) then
		local ok2, err2 = sock:send(body)
		if not(ok2) then
			return nil, "Failed to send request body: " .. tostring(err2)
		end
	end

	return true
end





--- Parses the status line text into a dict-table of {version, statusCode, reasonPhrase}
-- Returns nil and error message on error
local function parseStatusLine(aLine)
	assert(type(aLine) == "string")

	local version, status, reason = aLine:match("^(HTTP/%d%.%d)%s+(%d+)%s*(.*)$")
	if not(version) then
		return nil, "Invalid status line"
	end
	return
	{
		version = version,
		statusCode = tonumber(status),
		reasonPhrase = reason or "",
	}
end





--- Reads the response on the connection and returns the status code, headers, body and isConnectionReusable flag
-- Returns nil and error message on failure
local function readResponse(aConn)
	assert(type(aConn) == "table")
	assert(aConn.socket)

	-- Read the status line:
	local sock = aConn.socket
	local statusLine, err = sock:receive("*l")
	if not(statusLine) then
		return nil, err
	end
	local status = parseStatusLine(statusLine)
	if not(status) then
		return nil, "Failed to parse status line"
	end

	-- Read the headers:
	local headers, err2 = httpUtils.readHeaders(sock)
	if not(headers) then
		return nil, err2
	end

	-- body
	local body = httpUtils.readBody(sock, headers["content-length"], headers["transfer-encoding"])

	-- Keepalive decision:
	local isReusable = true
	local connectionHeader = headers["connection"]
	if (connectionHeader and (connectionHeader:lower() == "close")) then
		isReusable = false
	end

	return status.statusCode, headers, body, isReusable
end





--- API: Send a generic request (with retry-once)
--[[
Returns HTTP status (number), headers (dict-table), and body
Returns nil and error message on failure
The aRequest is a table containing the following members:
	- method: HTTP verb to use (default: "GET")
	- url: The URL to request. Required.
	- headers: dict-table of request headers
	- body: The body of the request to send
	- shouldSkipYields: if true, the connection is made without yielding until all incoming requests
		are processed (used for foreground downloads)
--]]
function httpClient.request(aRequest)
	assert(type(aRequest) == "table")
	assert(type(aRequest.url) == "string")

	gMetrics.numRequests = gMetrics.numRequests + 1
	local parsed, err = parseUrl(aRequest.url)
	if not(parsed) then
		gMetrics.numFailedRequests = gMetrics.numFailedRequests + 1
		return nil, err
	end

	local shouldRetry = true
	for attempt = 1, 2 do
		local conn, err2 = getConnection(parsed, aRequest)
		if not(conn) then
			gMetrics.numFailedRequests = gMetrics.numFailedRequests + 1
			return nil, err2
		end

		-- Send request:
		local isOK, err3 = sendRequest(conn, aRequest, parsed)
		if not(isOK) then
			releaseConnection(conn, false)
			if (shouldRetry) then
				shouldRetry = false
			else
				gMetrics.numFailedRequests = gMetrics.numFailedRequests + 1
				return nil, err3
			end
		else
			-- Read response:
			local status, headers, body, isReusable = readResponse(conn)
			if not(status) then
				releaseConnection(conn, false)
				if (shouldRetry) then
					shouldRetry = false
				else
					gMetrics.numFailedRequests = gMetrics.numFailedRequests + 1
					return nil, headers
				end
			else
				releaseConnection(conn, isReusable)
				gMetrics.numSuccessfulRequests = gMetrics.numSuccessfulRequests + 1
				return status, headers, body
			end
		end
	end

	-- Should be unreachable - either we succeed -> return, or we fail either the first attempt ( -> retry)
	-- or the second attempt (-> return)
	assert(nil, "This shouldn't have been reached")
end





--- API: Send a GET request
function httpClient.get(aUrl, aHeaders)
	return httpClient.request
	{
		url = aUrl,
		method = "GET",
		headers = aHeaders,
	}
end





--- API: Send a POST request
function httpClient.post(aUrl, aHeaders, aBody)
	return httpClient.request
	{
		url = aUrl,
		method = "POST",
		headers = aHeaders,
		body = aBody,
	}
end





--- API: Send a HEAD request
function httpClient.head(aUrl, aHeaders)
	return httpClient.request
	{
		url = aUrl,
		method = "HEAD",
		headers = aHeaders,
	}
end





--- API: Returns a snapshot of the current metrics
function httpClient.metrics()
	local snapshot = {}
	for k, v in pairs(gMetrics) do
		snapshot[k] = v
	end
	return snapshot
end





--- Resets the metrics to the default initial values
function httpClient.resetMetrics()
	gMetrics = {
		numRequests = 0,
		numSuccessfulRequests = 0,
		numFailedRequests = 0,

		numConnectionsCreated = 0,
		numConnectionsReused = 0,
		numConnectionsClosed = 0,

		numActiveConnections = 0,
		numQueuedWaits = 0,
	}
end





--- Disables the use of Copas in the library, turning it into a simple single-request-at-a-time processor
-- Must be called first thing after loading
-- Returns self, expected usage is local httpClient = require("httpClient").noCopas()
function httpClient.noCopas()
	gDisableCopas = true
	return httpClient
end





httpClient.resetMetrics()

return httpClient
