--- Marks an anime as seen and returns to home
local httpRequest = require("httpRequest")
local httpResponse = require("httpResponse")
local db = require("db")
local requestQueue = require("requestQueue")
local log = require("logger").log





return function(aClient, aRequestPath, aRequestHeaders)
	-- Only POST should reach here
	local body = httpRequest.readBody(aClient, aRequestHeaders)
	local form = httpRequest.parseFormUrlEncoded(body)

	local aId = tonumber(form.aId)
	if not(aId) then
		return httpResponse.sendError(aClient, 400, "Missing or invalid aId parameter")
	end

	-- Mark as seen in the DB:
	local ok, err = pcall(function()
		db.markAnimeSeen(aId)
	end)
	if not(ok) then
		return httpResponse.sendError(aClient, 500, "Database error: " .. tostring(err))
	end

	-- Add to request queue so that the details are queried soon:
	requestQueue.add(aId)

	-- Redirect to home:
	log("seen-add", "Marked %d as seen. Redirecting to home.", aId)
	httpResponse.sendRedirect(aClient, "/")
end
