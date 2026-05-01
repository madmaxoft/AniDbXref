-- httpRequest.lua

--[[
Implements the HttpRequest class representing a single HTTP request from the client.
The object is created by reading all the headers from a connection: httpRequest.createFromSocket()
Also implements various helper functions, such as urlDecode(), readRequestHeaders() etc.
--]]




--[[ HttpRequest class prototype.
Each instance has the following members:
	mSocket: The LuaSocket that received the request; where to send the response
	mMethod: "GET", "POST", ...
	mPathAndQuery: The requested path, including the query parameters
	mHttpVersion: "1.1", "1.0" etc.
	mHeaders: Both dict- and array-table of headers; the dict-table is lowercase-keyed
	mContentLength: Total bytes in the request body
	mRemainingBodyBytes: Number of remaining bytes in the request body
	mHasBody: bool
--]]
local M = {}
M.__index = M





--- URL-decodes the input string
function M.urlDecode(aStr)
	aStr = aStr:gsub("+", " ")
	aStr = aStr:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
	return aStr
end





--- Parses the full path from the request into the path part and parameters
-- Returns the path as a string and a table of { paramName, paramValue } as well as [paramName] = paramValue
function M:parsePathAndQuery()
	local path, query = self:pathAndQuery():match("([^?]*)%??(.*)")
	local params = { n = 0 }

	if (query ~= "") then
		for key, val in query:gmatch("([^&=?]+)=?([^&]*)") do
			local decodedKey = M.urlDecode(key)
			local decodedVal = M.urlDecode(val)

			params[decodedKey] = decodedVal
			params.n = params.n + 1
			params[params.n] = { decodedKey, decodedVal }
		end
	end

	return path, params
end





--- Reads and parses an incoming HTTP request line and headers
-- Returns method (string), path (string) and headers (combined lowercase-dict- and array- table)
-- Also returns the whole first line, as a debugging help
function M.readRequestHeaders(aClient)
	local request, msg = aClient:receive("*l")
	if not(request) then
		return nil, msg
	end

	local method, path = request:match("^(%S+)%s+(%S+)")
	local headers = { n = 0 }

	while (true) do
		local line, msg = aClient:receive("*l")
		if (not(line) or (line == "")) then
			break
		end

		local key, value = line:match("^(.-):%s*(.*)")
		if (key and value) then
			headers[key:lower()] = value
			headers.n = headers.n + 1
			headers[headers.n] = { key = key, value = value }
		end
	end

	return method, path, headers, request
end





--- Returns the full request body up to Content-Length as a string
-- Returns nil and error message on failure
function M.readBody(aClient, aHeaders)
	local length = tonumber(aHeaders["content-length"] or 0)
	if (length <= 0) then
		return ""
	end

	local body, err = aClient:receive(length)
	if not(body) then
		return nil, string.format("Failed to read request body: %s", tostring(err))
	end

	return body
end





--- Parses x-www-form-urlencoded data into dict + array table
function M.parseFormUrlEncoded(aData)
	local t = { n = 0 }
	for key, val in aData:gmatch("([^&=]+)=([^&=]*)") do
		local k = M.urlDecode(key)
		local v = M.urlDecode(val)
		t.n = t.n + 1
		t[t.n] = { k, v }
		t[k] = v
	end
	return t
end





function M.createFromSocket(aSocket)
	local self =
	{
		mSocket = aSocket,
		mMethod = nil,
		mPathAndQuery = nil,
		mHttpVersion = nil,
		mHeaders = {n = 0},
		mContentLength = 0,
		mRemainingBodyBytes = 0,
		mHasBody = false,
	}
	setmetatable(self, M)

	-- Read the request line:
	local requestLine, err = aSocket:receive("*l")
	if (not(requestLine) or (requestLine == "")) then
		return nil, "Failed to read HTTP request line: " .. tostring(err)
	end
	local method, pathAndQuery, version = requestLine:match("^(%S+)%s+(%S+)%s+HTTP/(%d+%.%d+)$")
	if not(method) then
		return nil, "Invalid HTTP request line"
	end
	self.mMethod = method
	self.mPathAndQuery = pathAndQuery
	self.mHttpVersion = version

	-- Read the http headers:
	while (true) do
		local line, lineErr = aSocket:receive("*l")
		if not(line) then
			return nil, "Failed to receive header: " .. tostring(lineErr)
		end
		if (line == "") then
			break
		end
		local key, value = line:match("^([^:]+):%s*(.*)$")
		if (key) then
			self.mHeaders.n = self.mHeaders.n + 1
			self.mHeaders[self.mHeaders.n] = value
			key = key:lower()
			self.mHeaders[key] = value
		end
	end

	-- Determine the body length:
	local contentLength = self.mHeaders["content-length"]
	if (contentLength) then
		local num = tonumber(contentLength)
		if ((num) and (num > 0)) then
			self.mContentLength = num
			self.mRemainingBodyBytes = num
			self.mHasBody = true
		end
	end

	return self
end





--- Returns the HTTP method used in the request
function M:method()
	return self.mMethod
end





--- Returns the request path (including the query part)
function M:pathAndQuery()
	return self.mPathAndQuery
end





--- Returns the http version used in the request, such as "1.1"
function M:httpVersion()
	return self.mHttpVersion
end





--- Returns the value of the specified http header, nil if not provided
-- aName can either be the header name, such as "Content-Type", or the (1-based) index
function M:header(aName)
	if not(aName) then
		return nil
	end
	if (type(aName) == "string") then
		aName = aName:lower()
	end
	return self.mHeaders[aName]
end





--- Returns whether the request has a body or not
function M:hasBody()
	return self.mHasBody
end





--- Returns the number of remaining bytes of the body to still be read
function M:remainingBodyBytes()
	return self.mRemainingBodyBytes
end





function M:read(aNumBytes)
	if (not self.mHasBody) then
		return nil
	end

	if (self.mRemainingBodyBytes <= 0) then
		return nil
	end

	local toRead = aNumBytes
	if ((not toRead) or (toRead > self.mRemainingBodyBytes)) then
		toRead = self.mRemainingBodyBytes
	end

	local data, err, partial = self.mSocket:receive(toRead)
	local received = data or partial

	if ((not received) or (received == "")) then
		return nil, err
	end

	local numReceived = #received
	self.mRemainingBodyBytes = self.mRemainingBodyBytes - numReceived

	return received
end





--- Reads and returns the remainder of the request body
function M:readAll()
	if not(self.mHasBody) then
		return nil
	end
	if (self.mRemainingBodyBytes <= 0) then
		return ""
	end

	local chunks = {}
	local numChunks = 0
	while (self.mRemainingBodyBytes > 0) do
		local chunk, err = self:read(8192)
		if not(chunk) then
			return nil, err
		end
		numChunks = numChunks + 1
		chunks[numChunks] = chunk
	end

	return table.concat(chunks)
end





function M:discardUnreadBody()
	if not(self.mHasBody) then
		return
	end

	while (self.mRemainingBodyBytes > 0) do
		local chunk, err = self:read(8192)
		if (not chunk) then
			break
		end
	end
end





--- Returns whether the connection should be kept alive after sending the specified response to this request
-- Implements the default rules for the two http versions, with the possibility to override
-- keepalive using response's "Connection: Close" header
-- If aResponse is nil, the response override is not taken into account
function M:shouldKeepAlive(aResponse)
	-- Check if the "Connection: Close" request header is present:
	local connectionHeader = self:header("connection")
	if (connectionHeader) then
		connectionHeader = connectionHeader:lower()
		if (connectionHeader == "close") then
			return false
		end
	end

	-- Check if there's a response override:
	if (aResponse) then
		local responseConnection = aResponse:header("connection")
		if (responseConnection) then
			responseConnection = responseConnection:lower()
			if (responseConnection == "close") then
				return false
			end
		end
	end

	-- HTTP 1.1 defaults to keepalive:
	if (self.mHttpVersion == "1.1") then
		return true
	end

	-- HTTP 1.0 defaults to close, unless "Connection: Keep-alive" is specified:
	if (connectionHeader == "keep-alive") then
		return true
	end

	return false
end





return M
