-- httpResponse.lua
-- Simple helper to send HTTP responses over a socket





local errorTemplate = require("Templates").errorPage





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





--- Sends an HTTP redirect (302) response
function httpResponse.sendRedirect(aClient, aDestination)
	aClient:send("HTTP/1.1 302 Moved\r\nLocation: " .. aDestination .. "\r\n\r\n")
end





--- Sends an HTTP error together with a nicely formatted error page containing the specified code and text
function httpResponse.sendError(aClient, aErrorCode, aErrorText)
	local html = errorTemplate({errorText = aErrorText, errorCode = aErrorCode})
	aClient:send(string.format("HTTP/1.1 %s\r\nContent-Type: text/html\r\nContent-Length: %d\r\n\r\n",
		tostring(aErrorCode),
		#html
	))
	aClient:send(html)
end





return httpResponse
