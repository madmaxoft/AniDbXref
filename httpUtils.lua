-- httpUtils.lua

--[[
Implements various utilities used by the HTTP protocol classes
--]]





local httpUtils = {}





--- Returns the body from socket that is being transferred using chunked encoding
-- Returns nil and error message on error
local function readChunkedBody(aSock)
	assert(aSock)
	assert(aSock.receive)

	local chunks = {}
	while (true) do
		local sizeLine, err = aSock:receive("*l")
		if not(sizeLine) then
			return nil, err
		end
		local chunkSize = tonumber(sizeLine, 16)
		if not(chunkSize) then
			return nil, "Chunked reader: Invalid chunk size"
		end

		-- Last chunk
		if (chunkSize == 0) then
			-- Consume trailing CRLF
			aSock:receive("*l")
			break
		end

		local chunk, err2 = aSock:receive(chunkSize)
		if not(chunk) then
			return nil, err2
		end
		table.insert(chunks, chunk)

		-- Consume trailing CRLF after chunk
		local crlf, err3 = aSock:receive(2)
		if not(crlf) then
			return nil, err3
		end
	end

	return table.concat(chunks)
end





--- Appends the specified value into the dict-table
-- If the key doesn't exist, a string value is created in the dict
-- If the key already exists, its current string value is converted into a table (if needed) and the new value is appended
function httpUtils.appendValue(aDict, aKey, aValue)
	assert(type(aDict) == "table")
	assert(type(aKey) == "string")
	assert(type(aValue) == "string")

	local key = aKey:lower()
	local existing = aDict[key]
	if not(existing) then
		aDict[key] = aValue
		return
	end

	if (type(existing) == "table") then
		table.insert(existing, aValue)
	else
		aDict[key] = { existing, aValue }
	end
end





--- Parses x-www-form-urlencoded data into dict + array table
function httpUtils.parseFormUrlEncoded(aData)
	local t = {}
	for key, val in aData:gmatch("([^&=]+)=([^&=]*)") do
		local k = httpUtils.urlDecode(key)
		local v = httpUtils.urlDecode(val)
		httpUtils.appendValue(t, k, v)
	end
	return t
end





--- Returns the body of an HTTP message read from the specified socket.
-- The socket is expected to have just finished reading the empty line after headers.
-- Returns nil and error message on failure
-- Supports reading body with content-length, with chunked transfer-encoding or with neither (reading until
-- socket closed then)
-- aHdrContentLength is the value of the Content-Length header (possibly nil)
-- aHdrTransferEncoding is the value of the Transfer-Encoding header (possibly nil)
function httpUtils.readBody(aSocket, aHdrContentLength, aHdrTransferEncoding)
	local body = ""
	local contentLength = tonumber(aHdrContentLength)
	if (aHdrTransferEncoding and aHdrTransferEncoding:lower():find("chunked")) then
		local data, err3 = readChunkedBody(aSocket)
		if not(data) then
			return nil, err3
		end
		body = data
	elseif (contentLength) then
		local data, err3 = aSocket:receive(contentLength)
		if not(data) then
			return nil, err3
		end
		body = data
	else
		-- Read until close:
		while (true) do
			local chunk, err4, partial = aSocket:receive(1024)
			if (chunk) then
				body = body .. chunk
			elseif (partial and (#partial > 0)) then
				body = body .. partial
				break
			else
				break
			end
		end
	end
	return body
end





--- Returns a dict-table of lowercased header name -> value, or name -> {value1, value2, ...} for multi-header,
-- read from the specified socket.
-- Supports legacy line-folded headers
-- Reading stops when an empty line is encountered.
-- Returns nil and error message on error
function httpUtils.readHeaders(aSock)
	assert(aSock)
	assert(aSock.receive)

	local headers = {}
	local lastKey = nil
	while (true) do
		local line, err = aSock:receive("*l")
		if not(line) then
			return nil, err
		end

		if (line == "") then
			break
		end

		if (line:match("^%s") and lastKey) then
			-- Legacy support: line folding
			local existing = headers[lastKey]
			if (type(existing) == "table") then
				local lastIndex = #existing
				existing[lastIndex] = existing[lastIndex] .. " " .. line:match("^%s*(.*)$")
			else
				headers[lastKey] = existing .. " " .. line:match("^%s*(.*)$")
			end
		else
			local key, value = line:match("^(.-):%s*(.*)$")
			if (key and value) then
				local normKey = key:lower()
				httpUtils.appendValue(headers, normKey, value)
				lastKey = normKey
			end
		end
	end
	return headers
end





--- URL-decodes the input string
function httpUtils.urlDecode(aStr)
	aStr = aStr:gsub("+", " ")
	aStr = aStr:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
	return aStr
end





return httpUtils
