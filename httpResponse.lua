-- httpResponse.lua
-- Simple helper to send HTTP responses over a socket

local templates = require("Templates")
local log = require("logger").log




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
	local html = require("Templates").errorPage({errorText = aErrorText, errorCode = aErrorCode})
	return httpResponse.send(aClient, aErrorCode, nil, html)
end





--- Sends a simple page with a message
-- If title is not given, "AniDbXref" is used
function httpResponse.sendSimpleMessage(aClient, aMessage, aTitle)
	assert(type(aMessage) == "string")

	local html = templates.simpleMessage({title = aTitle, message = aMessage})
	return httpResponse.send(aClient, 200, nil, html)
end





--- Executes the specified template using the specified params, then sends the result to the client as HTML
-- If the template fails, sends an error page
function httpResponse.sendTemplate(aClient, aTemplateName, aTemplateParams)
	assert(type(aTemplateName) == "string")
	assert(type(aTemplateParams) == "table")

	local template = templates[aTemplateName]
	if not(template) then
		return httpResponse.sendError(aClient, string.format("Template %s failed, inspect log for details", aTemplateName))
	end
	local html, msg = template(aTemplateParams)
	if not(html) then
		log("httpResponse", "Template %s execution failed: %s", aTemplateName, tostring(msg))
		return httpResponse.sendError(aClient, string.format("Template %s execution failed: %s", aTemplateName, tostring(msg)))
	end
	return httpResponse.send(aClient, 200, nil, html)
end





return httpResponse
