-- httpRequest.lua

--[[
Implements the HttpRequest class representing a single HTTP request incoming from the client.
The object is created by reading all the headers from a connection: httpRequest.createFromSocket()
--]]




local httpUtils = require("httpUtils")
local multipart = require("multipart")
local caseInsensitiveDict = require("caseInsensitiveDict")





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
	mHasStartedReadingBody: true if any part of the body has already been read.
	mFormData: dict- and array-table of submitted form data. nil if not present, false if failed to parse.
		See httpRequest:formData() for details.
--]]
local httpRequest = {}
httpRequest.__index = httpRequest





function httpRequest.createFromSocket(aSocket)
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
	setmetatable(self, httpRequest)

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
	local msg
	self.mHeaders, msg = httpUtils.readHeaders(aSocket)
	if not(self.mHeaders) then
		return nil, "Failed to read headers: " .. tostring(msg)
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





--- If the request's body hasn't been fully read yet, reads the remainder and discards the data.
function httpRequest:discardUnreadBody()
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





--- Returns the parsed form data from this request
-- Parses forms in both "application/x-www-form-urlencoded" and "multipart/form-data" formats
-- NOTE: Doesn't parse the form data in GET request parameters, use parsedPathAndQuery() for that
-- NOTE: Stores both the body and the form data in memory, not suitable for large file uploads
-- Returns a case-insensitive dict-table of the form data elements
-- Returns nil and error message on failure
function httpRequest:formData()
	assert(type(self) == "table")
	assert(self.method)

	-- If the data has already been parsed, return that:
	if (self.mFormData) then
		return self.mFormData
	end

	-- If the form data parsing has been attempted previously with a failure, fail now as well:
	if (self.mFormData == false) then
		return nil, "Parsing the form data has failed previously"
	end

	-- Fail if the request isn't supposed to have a body (use parsedPathAndQuery() to process GET-targeted forms)
	if not(self.mHasBody) then
		return nil, "The request has no body, no form data could be sent"
	end

	-- Fail if any part of the body has already been read:
	if (self.mHasStartedReadingBody) then
		return nil, "Reading the body has already started before"
	end

	local body = self:readAll()
	self.mFormData = false  -- Mark attempted parsing
	local contentType = self:header("content-type")
	if not(type(contentType) == "string") then
		return nil, "Content-Type not present or specified multiple times"
	end
	if (contentType:find("multipart/form%-data")) then
		local m, msg = multipart(body, contentType)
		if not(m) then
			return nil, "Failed to parse form multipart data: " .. tostring(msg)
		end
		self.mFormData = m:get_all()
	elseif (contentType:find("application/x%-www%-form%-urlencoded")) then
		local fd, msg = httpUtils.parseFormUrlEncoded(body)
		if not(fd) then
			return nil, "Failed to parse form data: " .. tostring(msg)
		end
		self.mFormData = fd
	else
		return nil, "Unhandled content type: " .. contentType
	end

	-- Normalize form field names to lowercase:
	local fd = caseInsensitiveDict.new()
	for k, v in pairs(self.mFormData) do
		fd[k:lower()] = v
	end
	self.mFormData = fd

	return self.mFormData
end





--- Returns whether the request has a body or not
function httpRequest:hasBody()
	return self.mHasBody
end





--- Returns the value of the specified http header, nil if not provided
-- The header name in parameter is case-insensitive
-- If there are multiple headers of the same name, returns an array-table of the values
function httpRequest:header(aName)
	assert(type(aName) == "string")

	return self.mHeaders[aName:lower()]
end





--- Returns the http version used in the request, such as "1.1"
function httpRequest:httpVersion()
	return self.mHttpVersion
end





--- Returns the HTTP method used in the request
function httpRequest:method()
	return self.mMethod
end





--- Parses the full path from the request into the path part and parameters
-- Returns the path as a string and a table of { paramName, paramValue } as well as [paramName] = paramValue
function httpRequest:parsedPathAndQuery()
	local path, query = self:pathAndQuery():match("([^?]*)%??(.*)")
	local params = { n = 0 }

	if (query ~= "") then
		for key, val in query:gmatch("([^&=?]+)=?([^&]*)") do
			local decodedKey = httpUtils.urlDecode(key)
			local decodedVal = httpUtils.urlDecode(val)

			params[decodedKey] = decodedVal
			params.n = params.n + 1
			params[params.n] = { decodedKey, decodedVal }
		end
	end

	return path, params
end





--- Returns the request path (including the query part)
function httpRequest:pathAndQuery()
	return self.mPathAndQuery
end





function httpRequest:read(aNumBytes)
	if not(self.mHasBody) then
		return nil
	end

	if (self.mRemainingBodyBytes <= 0) then
		return nil
	end

	self.mHasStartedReadingBody = true
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
function httpRequest:readAll()
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





--- Returns the number of remaining bytes of the body to still be read
function httpRequest:remainingBodyBytes()
	return self.mRemainingBodyBytes
end





--- Returns whether the connection should be kept alive after sending the specified response to this request
-- Implements the default rules for the two http versions, with the possibility to override
-- keepalive using response's "Connection: Close" header
-- If aResponse is nil, the response override is not taken into account
function httpRequest:shouldKeepAlive(aResponse)
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





return httpRequest
