-- importSeenFromPlaces.lua

--[[ Handles importing into the Seen list from an uploaded "places.sqlite" file from a browser.
Handles, displaying the form (GET request), processing the uploaded file (POST request),
displaying the matched items for review (GET) and updating the matches based on user choices in the form (POST)
The handlers are returned in a table as named functions
--]]





local httpResponse = require("httpResponse")
local httpRequest = require("httpRequest")
local import = require("importSeenFromPlaces")
local multipart = require("multipart")
local db = require("db")





local I = {}





--- Handles the GET request for "/import", displaying a file-upload form
function I.get(aClient)
	local body = require("Templates").import()
	return httpResponse.send(aClient, "200 OK", nil, body)
end





--- Handles the POST request for "/import", parsing the uploaded file and processing it
function I.post(aClient, aPath, aPatternMatches, aRequestHeaders)
	-- Extract the uploaded file contents:
	local body = httpRequest.readBody(aClient, aRequestHeaders)
	local m = multipart(body, aRequestHeaders["content-type"])
	local placesFileContents = (m:get("placesFile") or {}).value
	if not(placesFileContents) then
		return httpResponse.send(aClient, "400 Bad upload", nil, "The upload contains no file")
	end

	-- Store to a temp disk file:
	require("lfs").mkdir("Import")
	local fileName = string.format("Import/%s.sqlite", os.date("%Y-%m-%d-%H-%M-%S"))
	local f = assert(io.open(fileName, "wb"))
	f:write(placesFileContents)
	f:close()

	-- Build a session out of the file:
	local session = import.buildSession(fileName)
	os.remove(fileName)
	if (session.items.n == 0) then
		return httpResponse.sendRedirect(aClient, "/")
	end
	return httpResponse.sendRedirect(aClient, "/import/review/" .. session.id)
end





--- Handles the GET request for "/import/test", a testing endpoint that builds a session
-- from an existing "Import/places.sqlite" file. Used for testing.
function I.importTest(aClient, aPath, aPatternMatches, aRequestHeaders)
	local session = import.buildSession("Import/places.sqlite")
	if (session.items.n == 0) then
		return httpResponse.sendRedirect(aClient, "/")
	end
	return httpResponse.sendRedirect(aClient, "/import/review/" .. session.id)
end





--- Handles the GET request for "/import/review/<id>"
-- Shows the form for the user to review the matches in the specified session
function I.reviewGet(aClient, aPath, aPatternMatches, aRequestHandlers)
	local id = tonumber(string.match(aPath, "^/import/review/(%d+)$"))
	local session = import.getSession(id)
	if not(session) then
		return httpResponse.send(aClient, "400 Bad session", nil, "No such session")
	end
	local body = require("Templates").importReview({sessionId = session.id, items = session.items})
	return httpResponse.send(aClient, "200 OK", nil, body)
end





--- Handles the POST request for "/import/review/<id>"
-- Updates the session based on the radio button selections:
--   - if a candidate is selected, marks the candidate as seen and removes it from the session
--   - if a search is selected, performs a new search and updates the candidates for the item
--   - if no radio is selected, doesn't do anything (keeps the item as-is)
-- If there are no items to process anymore, finishes the session and redirects back to home.
function I.reviewPost(aClient, aPath, aPatternMatches, aRequestHeaders)
	-- Find the correct session:
	local sessionId = tonumber(string.match(aPath, "^/import/review/(%d+)$"))
	local session = import.getSession(sessionId)
	if not(session) then
		return httpResponse.send(aClient, "400 Bad session", nil, "No such session")
	end

	local rawBody = httpRequest.readBody(aClient, aRequestHeaders)
	local form = multipart(rawBody, aRequestHeaders["content-type"])

	-- Process all items:
	for i = 1, session.items.n do
		local item = session.items[i]
		local choice = (form:get("candidate_" .. i) or {}).value
		if (choice == "search") then
			-- re-search this item
			local query = (form:get("custom_" .. i) or {}).value
			if (query) then
				item.candidates = import.searchCandidates(query)
			end
		elseif (choice == "ignore") then
			-- Ignore and do not show again
			session.items[i] = nil
		elseif (choice) then
			-- chosen candidate id
			local candidateId = tonumber(choice)
			if (candidateId) then
				db.markAnimeSeen(candidateId, item.lastVisitDate / 1000)
				-- Remove the item from the session:
				session.items[i] = nil
			end
		end
	end  -- for i - session.items[]

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
		return httpResponse.sendRedirect(aClient, "/")
	end

	-- Redirect to the session form again:
	return httpResponse.sendRedirect(aClient, "/import/review/" .. session.id)
end





return I
