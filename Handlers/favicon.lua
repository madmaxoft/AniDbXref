-- favicon.lua

-- Handles the requests for the favicon, sending the Static/favicon.ico file





local faviconData

local f = io.open("Static/favicon.ico", "rb")
if (f) then
	faviconData = f:read("*all")
	f:close()
end





return function(aClient)
	if (faviconData) then
		require("httpResponse").send(aClient, "200 OK", nil, faviconData)
	else
		require("httpResponse").send(aClient, "404 Not found")
	end
end
