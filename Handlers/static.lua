-- Handlers/static.lua

--[[ Handler for the "/static/" URL path.
Servers static files from the Static subfolder
--]]





--- Serves static files from Static folder
return function (aRequest, aResponse)
	local relativePath = aRequest:path():match("^/[Ss]tatic/(.*)")
	if (not relativePath) then
		return aResponse:sendError(404, "Not Found")
	end

	-- Read the local file:
	local filePath = "Static/" .. relativePath
	local f = io.open(filePath, "rb")
	if not(f) then
		return aResponse:sendError(404, "Not Found")
	end
	local content = f:read("*a")
	f:close()

	-- Simple content type detection
	local contentType = "application/octet-stream"
	if (filePath:match("%.html$")) then contentType = "text/html"
	elseif (filePath:match("%.css$")) then contentType = "text/css"
	elseif (filePath:match("%.js$")) then contentType = "application/javascript"
	elseif (filePath:match("%.png$")) then contentType = "image/png"
	elseif (filePath:match("%.jpg$")) then contentType = "image/jpeg"
	elseif (filePath:match("%.gif$")) then contentType = "image/gif" end
	aResponse:setContentType(contentType)
	aResponse:sendRawDataWithLength(content)
end
