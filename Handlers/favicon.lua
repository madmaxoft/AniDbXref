-- favicon.lua

-- Handles the requests for the favicon, sending the Static/favicon.ico file





local faviconData

local f = io.open("Static/favicon.ico", "rb")
if (f) then
	faviconData = f:read("*all")
	f:close()
end





return function(aRequest, aResponse)
	if (faviconData) then
		aResponse:sendRawDataWithLength(faviconData)
	else
		aResponse:sendError(404, "Not found")
	end
end
