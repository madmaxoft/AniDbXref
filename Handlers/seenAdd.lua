-- Handlers/seenAdd.lua

--[[
Marks an anime as seen and returns to home
--]]

local db = require("db")
local requestQueue = require("requestQueue")
local log = require("logger").log





return function(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	-- Only POST should reach here
	assert(aRequest:method() == "POST")

	local body = aRequest:readAll()
	local form = aRequest.parseFormUrlEncoded(body)
	if not(form) then
		return aResponse:sendError(400, "Failed to parse request body")
	end

	local aId = tonumber(form.aId)
	if not(aId) then
		return aResponse:sendError(400, "Missing or invalid aId parameter")
	end

	-- Mark as seen in the DB:
	local ok, err = pcall(function()
		db.markAnimeSeen(aId)
	end)
	if not(ok) then
		return aResponse:sendError(500, "Database error: " .. tostring(err))
	end

	-- Add to request queue so that the details are queried soon:
	requestQueue.add(aId)

	-- Redirect to home:
	log("seen-add", "Marked %d as seen. Redirecting to home.", aId)
	aResponse:sendRedirect("/")
end
