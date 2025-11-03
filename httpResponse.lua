-- httpResponse.lua
-- Simple helper to send HTTP responses over a socket





local httpResponse = {}





--- Sends a complete HTTP response
function httpResponse.send(aClient, aStatus, aHeaders, aBody)
	aStatus = aStatus or "200 OK"
	aHeaders = aHeaders or {}
	aBody = aBody or ""
	
	-- We can use simple shortcut: string means the content type we want to send:
	if (type(aHeaders) == "string") then
		aHeaders = { ["Content-Type"] = aHeaders }
	end

	-- Ensure Content-Length is set
	if (not aHeaders["Content-Length"]) then
		aHeaders["Content-Length"] = tostring(#aBody)
	end

	-- Default Content-Type
	if (not aHeaders["Content-Type"]) then
		aHeaders["Content-Type"] = "text/html; charset=utf-8"
	end

	-- Build response string
	local response = "HTTP/1.1 " .. aStatus .. "\r\n"
	for k, v in pairs(aHeaders) do
		response = response .. k .. ": " .. v .. "\r\n"
	end
	response = response .. "\r\n" .. aBody

	-- Send over socket
	aClient:send(response)
end





-- Add a "write" synonym to "send":
httpResponse.write = httpResponse.send





return httpResponse
