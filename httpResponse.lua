-- httpResponse.lua
-- Simple helper to send HTTP responses over a socket

local templates = require("Templates")
local log = require("logger").log
local config = require("config")





--[[ HttpResponse class prototype.
Each instance has the following members:
	mSocket
	mStatusCode (number)
	mStatusText
	mHeaders  (dict-table of lowercased header name -> value)
	mHasSentHeaders
	mShouldClose
--]]
local M = {}
M.__index = M





config.registerDefinitions({
	{
		identifier = "hotreload.templateutils",
		description = "Reload template utils before executing each HTML template",
		category = "Reload code",
		valueType = "bool",
		default = false,
	},
})





function M.new(aSocket)
	local self =
	{
		mSocket = aSocket,
		mStatusCode = 200,
		mStatusText = "OK",
		mHeaders = {},
		mHasSentHeaders = false,
		mShouldClose = false,
	}
	setmetatable(self, M)
	return self
end





function M:setStatus(aCode, aText)
	assert(tonumber(aCode))

	if (self.mHasSentHeaders) then
		assert(false, "Headers have already been sent")
		return
	end

	self.mStatusCode = tonumber(aCode)
	self.mStatusText = aText or ""
end





function M:setHeader(aName, aValue)
	if (self.mHasSentHeaders) then
		assert(false, "Headers have already been sent")
		return
	end

	self.mHeaders[aName:lower()] = aValue
end





function M:header(aName)
	if not(aName) then
		return nil
	end

	return self.mHeaders[aName:lower()]
end





function M:setContentLength(aLength)
	assert(tonumber(aLength))

	self:setHeader("Content-Length", tostring(aLength))
end





function M:setContentType(aContentType)
	assert(type(aContentType) == "string")

	self:setHeader("Content-Type", aContentType)
end





function M:setConnectionClose()
	self.mShouldClose = true
	self:setHeader("Connection", "close")
end





function M:sendHeaders()
	assert(self)
	assert(self.mSocket)

	-- If headers were already sent, complain:
	if (self.mHasSentHeaders) then
		assert(false, "Headers have already been sent")
		return
	end

	-- Set the "Connection" header based on mShouldClose:
	if not(self:header("connection")) then
		if (self.mShouldClose) then
			self:setHeader("Connection", "close")
		else
			self:setHeader("Connection", "keep-alive")
		end
	end

	-- Send the HTTP status line:
	local statusLine = string.format(
		"HTTP/1.1 %d %s\r\n",
		self.mStatusCode,
		self.mStatusText
	)
	self.mSocket:send(statusLine)

	-- Send the HTTP headers:
	for key, value in pairs(self.mHeaders) do
		local line = string.format("%s: %s\r\n", key, value)
		self.mSocket:send(line)
	end
	self.mSocket:send("\r\n")
	self.mHasSentHeaders = true
end





function M:write(aData)
	assert(self)
	assert(self.mSocket)

	if not(self.mHasSentHeaders) then
		self:sendHeaders()
	end

	if not(aData) then
		return
	end

	self.mSocket:send(aData)
end





function M:finish()
	assert(self)
	assert(self.mSocket)

	if not(self.mHasSentHeaders) then
		self:setContentLength(0)
		self:sendHeaders()
	end
end





--- Sends an HTTP redirect (302) to the specified destination
function M:sendRedirect(aDestination)
	assert(self)
	assert(self.mSocket)
	assert(type(aDestination) == "string")

	self:setStatus(302, "Found")
	self:setHeader("Location", aDestination)
	self:setContentLength(0)
	self:sendHeaders()
end





--- Sends the specified raw data as the http response body
-- Sets the content-length header based on the data length
function M:sendRawDataWithLength(aData)
	assert(type(aData) == "string")

	self:setContentLength(#aData)
	self:write(aData)
end





--- Sends a plain text body with the currently set headers
function M:sendPlainText(aText)
	assert(self)
	assert(self.mSocket)
	assert(type(aText) == "string")

	self:setHeader("Content-Type", "text/plain; charset=utf-8")
	self:sendRawDataWithLength(aText)
end





--- Sends an html text body with the currently set headers.
function M:sendHtml(aHtml)
	assert(self)
	assert(self.mSocket)
	assert(type(aHtml) == "string")

	self:setHeader("Content-Type", "text/html; charset=utf-8")
	self:sendRawDataWithLength(aHtml)
end





--- Sends an HTTP error together with a nicely formatted error page containing the specified code and text
function M:sendError(aErrorCode, aErrorText)
	assert(self)
	assert(self.mSocket)
	assert(tonumber(aErrorCode))

	local template = templates["errorPage"]
	if not(template) then
		log("httpResponse", "errorPage template not present while responding with error %d / %s", aErrorCode, tostring(aErrorText))
		self:setStatus(500)
		return self:sendPlainText("Cannot load error page template")
	end
	local html, msg = template({errorText = aErrorText, errorCode = aErrorCode})
	if not(html) then
		log("httpResponse", "errorPage template execution failed: %s", tostring(msg))
		self:setStatus(500)
		return self:sendPlainText("Cannot render error page: " .. tostring(msg))
	end
	self:setStatus(aErrorCode)
	return self:sendHtml(html)
end





--- Executes the specified template using the specified params, then sends the result to the client as HTML
-- If the template fails, sends an error page
function M:sendTemplate(aTemplateName, aTemplateParams)
	assert(self)
	assert(self.mSocket)
	assert(type(aTemplateName) == "string")
	assert(type(aTemplateParams) == "table")

	local template = templates[aTemplateName]
	if not(template) then
		return self:sendError(500, string.format("Template %s failed, inspect log for details", aTemplateName))
	end

	-- If configured, reload the templateUtils on each call for fast development cycle of the utils:
	if (config.get("hotreload.templateutils")) then
		aTemplateParams.utils = dofile("templateUtils.lua")(aTemplateParams)
	else
		aTemplateParams.utils = require("templateUtils")(aTemplateParams)
	end

	-- Execute the template:
	local isOK, html, msg = pcall(template, aTemplateParams)
	if not(isOK) then
		log("httpResponse", "Template %s execution failed: %s %s", aTemplateName, tostring(html), tostring(msg))
		return self:sendError(500, string.format("Template %s execution failed: %s", aTemplateName, tostring(html)))
	end
	return self:sendHtml(html)
end





--- Sends a simple page with a message
-- If title is not given, "AniDbXref" is used
function M:sendSimpleMessage(aMessage, aTitle)
	return self:sendTemplate("simpleMessage", {title = aTitle or "AniDbXref", message = aMessage})
end





function M:sendUnauthorized(aRealm)
	assert(type(self) == "table")
	assert(self.sendUnauthorized)
	assert(self.setHeader)
	assert(type(aRealm) == "string")

	self:setHeader("WWW-Authenticate", "Basic realm = " .. aRealm)
	return self:sendError(401, "Unauthorized")
end





return M
