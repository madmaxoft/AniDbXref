-- Handlers/importUI.lua

--[[
Handles importing:
	- into the Seen list from an uploaded "places.sqlite" file from a browser.
	- an XML file with single anime details
Handles, displaying the form (GET request), processing the uploaded file (POST request),
displaying the matched items for review (GET) and updating the matches based on user choices in the form (POST)
The handlers are returned in a table as named functions
--]]





local import = require("importSeenFromPlaces")
local db = require("db")
local lomParser = require("lxp.lom")
local aniDbDetails = require("aniDbDetails")
local httpClient = require("httpClient")
local ltn12 = require("ltn12")
local mime = require("mime")
local log = require("logger").log




local I = {}





--- Handles the POST request for "/import" for the places.sqlite file
local function handlePostPlacesFile(aRequest, aResponse, aFileContents)
	-- Store to a temp disk file:
	require("lfs").mkdir("Import")
	local fileName = string.format("Import/%s.sqlite", os.date("%Y-%m-%d-%H-%M-%S"))
	local f = assert(io.open(fileName, "wb"))
	f:write(aFileContents)
	f:close()

	-- Build a session out of the file:
	local session = import.buildSession(fileName)
	os.remove(fileName)
	if (session.items.n == 0) then
		return aResponse:sendRedirect("/")
	end
	return aResponse:sendRedirect("/import/review/" .. session.id)
end





--- Handles the POST request for "/import" for a details XML file
local function handlePostDetailsFile(aRequest, aResponse, aFileContents)
	-- XML-parse the contents:
	local parsedLom = lomParser.parse(aFileContents)
	if not(parsedLom) then
		return aResponse:sendError(400, "FAILED to xml-parse the file")
	end

	-- Transform the parsed LOM object into the details table:
	local parsedDetails = aniDbDetails.transformParsedIntoDetails(parsedLom)
	if not(parsedDetails.aId) then
		return aResponse:sendError(400, "FAILED to transform AniDB API XML to details.")
	end

	db.storeAnimeDetails(parsedDetails)
	return aResponse:sendRedirect("/")
end





--- Sends a HTTP GET request to the specified URL, returns the response parsed as a Lua data
-- Returns nil and error message on failure
local function callLuaApi(aUrl, aUsername, aPassword)
	assert(type(aUrl) == "string")
	assert(type(aUsername) == "string")
	assert(type(aPassword) == "string")

	-- Send the request:
	local authHeaderValue = "Basic " .. mime.b64(aUsername .. ":" .. aPassword)
	local responseBody = {}
	local statusCode, headers, body = httpClient.request({
		url = aUrl,
		headers =
		{
			["Authorization"] = authHeaderValue,
		},
	})
	if (statusCode ~= 200) then
		return nil, string.format("Failed to receive API response, status code %s, err %s", tostring(statusCode), tostring(headers))
	end
	log("import.api", "API call received successfully: " .. #body .. " bytes")

	-- Parse the returned body:
	local fn, msg = loadstring("return " .. body, "api")
	if not(fn) then
		return nil, "Failed to load API response: " .. tostring(msg)
	end
	setfenv(fn, {})
	local isOK, res, msg = pcall(fn)
	if not(isOK) then
		return nil, "Failed to parse API response: " .. tostring(res) .. "/" .. tostring(msg)
	end
	if not(res) then
		return nil, "API response is invalid: " .. tostring(msg)
	end
	log("import.api", "API call parsed successfully, " .. type(res))
	return res
end





--- Imports the Seen data from a remote API endpoint
local function importSeen(aRequest, aResponse, aUrl, aUsername, aPassword)
	assert(type(aRequest) == "table")
	assert(aRequest.header)
	assert(type(aResponse) == "table")
	assert(aResponse.sendError)
	assert(type(aUrl) == "string")
	assert(type(aUsername) == "string")
	assert(type(aPassword) == "string")

	local resp, msg = callLuaApi(aUrl, aUsername, aPassword)
	if (type(resp) ~= "table") then
		return aResponse:sendError(400, "Failed to call API: " .. tostring(msg))
	end

	local isOK, msg = db.addRawSeenIds(resp)
	if not(isOK) then
		return aResponse:sendError(400, "Failed to store the Seen in the DB: " .. tostring(msg))
	end
	log("import", "Successfully imported %d seen IDs from %s", resp.n or 0, aUrl)
	return aResponse:sendRedirect("/")
end





--- Imports the Watchlist data from a remote API endpoint
local function importWatchlist(aRequest, aResponse, aUrl, aUsername, aPassword)
	assert(type(aRequest) == "table")
	assert(aRequest.header)
	assert(type(aResponse) == "table")
	assert(aResponse.sendError)
	assert(type(aUrl) == "string")
	assert(type(aUsername) == "string")
	assert(type(aPassword) == "string")

	local resp, msg = callLuaApi(aUrl, aUsername, aPassword)
	if (type(resp) ~= "table") then
		return aResponse:sendError(400, "Failed to call API: " .. tostring(msg))
	end

	local isOK, msg = db.addRawWatchlist(resp)
	if not(isOK) then
		return aResponse:sendError(400, "Failed to store the Watchlist in the DB: " .. tostring(msg))
	end
	log("import", "Successfully imported %d watchlist items from %s", resp.n or 0, aUrl)
	return aResponse:sendRedirect("/watchlist")
end





--- Handles the GET request for "/import", displaying a file-upload form
function I.get(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	return aResponse:sendTemplate("import", {})
end





--- Handles the GET request for "/import/test", a testing endpoint that builds a session
-- from an existing "Import/places.sqlite" file. Used for testing.
function I.getImportTest(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	local session = import.buildSession("Import/places.sqlite")
	if (session.items.n == 0) then
		return aResponse:sendRedirect("/import")
	end
	return aResponse:sendRedirect("/import/review/" .. session.id)
end





--- Handles the GET request for "/import/review/<id>"
-- Shows the form for the user to review the matches in the specified session
function I.getReview(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	local id = tonumber(string.match(aRequest:pathAndQuery(), "^/import/review/(%d+)$"))
	local session = import.getSession(id)
	if not(session) then
		return aResponse:sendError(400, "Bad session")
	end
	return aResponse:sendTemplate("importReview", {sessionId = session.id, items = session.items})
end





--- Handles the POST request for "/import", parsing the uploaded file and processing it
-- Bases the processing on the name of the form element that the browser sends
function I.post(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	-- Extract the uploaded form contents:
	local formData, msg = aRequest:formData()
	if not(formData) then
		return aResponse:sendError(400, "Failed to parse form data: " .. tostring(msg))
	end

	local placesFileContents = formData["placesfile"]
	if (placesFileContents) then
		return handlePostPlacesFile(aRequest, aResponse, placesFileContents)
	end

	local detailsFileContents = formData["detailsfile"]
	if (detailsFileContents) then
		return handlePostDetailsFile(aRequest, aResponse, detailsFileContents)
	end

	local seenUrl = formData["seenurl"]
	if (seenUrl) then
		return importSeen(aRequest, aResponse,
			seenUrl,
			formData["username"],
			formData["password"]
		)
	end

	local watchlistUrl = formData["watchlisturl"]
	if (watchlistUrl) then
		return importWatchlist(aRequest, aResponse,
			watchlistUrl,
			formData["username"],
			formData["password"]
		)
	end

	return aResponse:sendError(400, "Bad upload")
end





--- Handles the POST request for "/import/review/<sessionid>"
-- Updates the session based on the radio button selections:
--   - if a candidate is selected, marks the candidate as seen and removes it from the session
--   - if a search is selected, performs a new search and updates the candidates for the item
--   - if no radio is selected, doesn't do anything (keeps the item as-is)
-- If there are no items to process anymore, finishes the session and redirects back to home.
function I.postReview(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	-- Find the correct session:
	local sessionId = tonumber(string.match(aRequest:pathAndQuery(), "^/import/review/(%d+)$"))
	local session = import.getSession(sessionId)
	if not(session) then
		return aResponse:sendError(400, "No such session")
	end

	local formData, msg = aRequest:formData()
	if not(formData) then
		return aResponse:sendError(400, "Failed to parse form data: %s", tostring(msg))
	end

	-- Process all items:
	local toMark = {}  -- Dict of aId -> lastVisitDate for all items to be marked
	for i = 1, session.items.n do
		local item = session.items[i]
		local choice = formData["candidate_" .. i]
		if (choice == "search") then
			-- Re-search this item:
			local query = formData["custom_" .. i]
			if (query) then
				item.candidates = import.searchCandidates(item.title, query)
			end
		elseif (choice == "ignore") then
			-- Ignore and do not show again
			session.items[i] = nil
		elseif (choice) then
			-- chosen candidate id
			local candidateId = tonumber(choice)
			if (candidateId) then
				-- De-duplicate requests for marking the same show multiple times - use the earliest time:
				local tm = toMark[candidateId]
				if (not(tm) or (tm > item.lastVisitDate)) then
					toMark[candidateId] = item.lastVisitDate
				end
				-- Remove the item from the session:
				session.items[i] = nil
			end
		end
	end  -- for i - session.items[]
	for aId, timeStamp in pairs(toMark) do
		db.markAnimeSeen(aId, timeStamp)
	end

	-- Compact the item array-table:
	local newItems = {}
	local n = 0
	for i = 1, session.items.n do
		local item = session.items[i]
		if (item ~= nil) then
			n = n + 1
			newItems[n] = item
		end
	end
	newItems.n = n
	session.items = newItems

	-- If complete, redirect to home:
	if (session.items.n == 0) then
		import.removeSession(sessionId)
		return aResponse:sendRedirect("/")
	end

	-- Redirect to the session form again:
	return aResponse:sendRedirect("/import/review/" .. session.id)
end





return I
