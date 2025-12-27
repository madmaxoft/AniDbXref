--- Marks an anime as seen and returns to home
local httpRequest = require("httpRequest")
local httpResponse = require("httpResponse")
local db = require("db")
local log = require("logger").log





return function(aClient, aRequestPath, aRequestHeaders)
	-- Only POST should reach here
	local body = httpRequest.readBody(aClient, aRequestHeaders)
	local form = httpRequest.parseFormUrlEncoded(body)

	local aId = tonumber(form.aId)
	if not(aId) then
		return httpResponse.send(aClient, 400, "text/plain", "Missing or invalid aId parameter")
	end

	local ok, err = pcall(function()
		db.markAnimeSeen(aId)
	end)

	if not(ok) then
		return httpResponse.send(aClient, 500, "text/plain", "Database error: " .. tostring(err))
	end

	-- Redirect to home
	log("seen-add", "Marked %d as seen. Redirecting to home.", aId)
	httpResponse.send(aClient, 302, { ["Location"] = "/" }, "Redirecting to home...")
end
