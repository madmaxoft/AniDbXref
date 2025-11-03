-- httpRequest.lua

-- Implements helper utilities for parsing http requests





local M = {}





--- URL-decodes the input string
function M.urlDecode(aStr)
	aStr = aStr:gsub("+", " ")
	aStr = aStr:gsub("%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
	return aStr
end





--- Parses a full path from the request into the path part and parameters
-- Returns the path as a string and a table of { paramName, paramValue } as well as [paramName] = paramValue
function M.parseRequestPath(aRequestPath)
	local path, query = aRequestPath:match("([^?]*)%??(.*)")
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





--- Returns the full request body up to Content-Length as a string
function M.readBody(aClient, aHeaders)
	local length = tonumber(aHeaders["content-length"] or 0)
	if (length <= 0) then
		return ""
	end

	local body, err = aClient:receive(length)
	if (not body) then
		error("Failed to read request body: " .. tostring(err))
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





return M
