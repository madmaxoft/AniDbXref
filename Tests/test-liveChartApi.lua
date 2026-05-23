-- Tests/test-liveChartApi.lua

--[[
Implements a test harness for determining if the LiveChart.me API description
at https://github.com/infanf/livechart.me-rest-api works at all.
  -> We found out that the regular API always returns an empty result.

GraphQL queries have been observed from the LiveChart.me android app and reused here as well,
which was the basis for implementing the actual livechart.me integration in liveChartSchedule.lua.
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;./?.lua;Tests/?.lua" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true

local httpClient = require("httpClient").noCopas()  -- Disable Copas in the underlying httpClient
local credentials = require("liveChartLogin")  -- If this fails, check liveChartLogin-sample.lua for instructions
local json = require("dkjson")
local url = require("socket.url")
local utils = require("utils")






--- Performs authentication against LiveChart API
local function authenticate(aCredentials)
	assert(type(aCredentials) == "table")
	assert(type(aCredentials.email) == "string")
	assert(type(aCredentials.password) == "string")

	local requestBody =
		"email=" .. url.escape(aCredentials.email) ..
		"&password=" .. url.escape(aCredentials.password)
	local status, headers, body = httpClient.request({
		method = "POST",
		url = "https://www.livechart.me/api/v1/auth/authenticate",
		headers =
		{
			["content-type"] = "application/x-www-form-urlencoded",
			["accept"] = "application/json",
			["accept-encoding"] = "gzip",
			["user-agent"] = "me.livechart.android/6.4.8",
		},
		body = requestBody,
	})
	if ((status ~= 200) and (status ~= 201) and (status ~= 202)) then
		error(string.format(
			"Authentication failed, HTTP status %s, body = %s",
			tostring(status),
			tostring(body)
		))
	end

	local response = json.decode(body)
	if not(response) then
		error("Failed to decode authentication response JSON")
	end

	local accessToken =
		response.access_token or
		response.token or
		response.auth_token
	if (type(accessToken) ~= "string") then
		error(string.format(
			"Authentication response does not contain access token: %s",
			tostring(body)
		))
	end

	return accessToken
end





-- Authenticate, in case the API needs that for queries:
--  -> Found out that auth works but API doesn't, despite auth.
local accessToken = credentials.accessToken
if not(accessToken) then
	print("Access token not present in the liveChartLogin.lua credentials config file, requesting a new token.")
	accessToken = authenticate(credentials)
end
print(string.format("Access token = %s", accessToken))




--- Sends a regular API request for the schedule
local function getSimpleAPISchedule()
	local status, headers, body = httpClient.request({
		method = "GET",
		url =
			"https://www.livechart.me/api/v1/schedule" ..
			"?start_date=2026-04-10" ..
			"&end_date=2026-04-17" ..
			"&offset=0" ..
			"&limit=50" ..
			"&sort=title" ..
			"&titles=english",
		headers =
		{
			["accept"] = "application/json",
			["accept-encoding"] = "gzip",
			["user-agent"] = "me.livechart.android/6.4.8",
			["x-auth-token"] = accessToken,
			["authorization"] = "Bearer " .. accessToken,
		},
	})

	print(string.format("status = %s", tostring(status)))
	print(body)
end

-- getSimpleApiSchedule()
-- Returns an empty result with no error





--- Sends the specified GraphQL query and dumps the response to stdout
local function debugGraphQL(aQuery)
	assert(type(aQuery) == "table")

	local status, headers, body = httpClient.request({
		method = "POST",
		url = "https://www.livechart.me/graphql",
		headers =
		{
			["content-type"] = "application/json",
			["accept"] = "application/json",
			["user-agent"] = "desperate-person-testing-things-manually",
		},
		body = json.encode(aQuery),
	})
	print(status)
	if (type(body) ~= "string") then
		print("Body not a string: " .. type(body))
		print(tostring(body))
		return
	end
	local tbl, msg = json.decode(body)
	if not(tbl) then
		print("Body not a JSON: " .. tostring(msg))
		print(body)
		return
	end
	print("Body parsed as JSON:")
	print(utils.serializeSimpleTable(tbl))
end





--- Requests the GraphQL schema from the server
-- Doesn't work, the server responds with an error
local function getGraphQLSchema()
	print("GraphQL schema query:")
	debugGraphQL({
		query = [[
			query {
				__schema {
					queryType {
						name
					}
				}
			}
		]]
	})
end

-- getGraphQLSchema()   -- Returns an error, __schema doesn't exist




--- Requests schedule from the server
-- Doesn't work, needs parameters that are hidden, API docs incomplete.
local function getSimpleSchedule()
	print("Simple GraphQL schedule:")
	debugGraphQL({
		query = [[
			query {
				schedule(date: "2026-05-10") {
					*
				}
			}
		]]
	})
end

-- getSimpleSchedule()  -- Returns an error, needs a more specialized query with unknown parameters.





--- Returns the response for querying the schedule for the specified day, as requested by the Android app
local function getAppScheduleForDay(aDayYmd)
	assert(type(aDayYmd) == "string")
	assert(aDayYmd:match("%d%d%d%d%-%d%d%-%d%d"))

	print("getAppScheduleForDay")
	debugGraphQL({
		operationName = "Timetable",
		variables =
		{
			date = aDayYmd,
			timeZone = "Etc/UTC",
			dayCount = 1,
			titlePreference = "ENGLISH",
		},
		query = [[
			query Timetable(
				$date: ISO8601Date,
				$timeZone: TimeZoneName,
				$dayCount: Int,
				$titlePreference: TitleLanguage
			) {
				timetable(
					date: $date,
					timeZone: $timeZone,
					dayCount: $dayCount,
					titlePreference: $titlePreference
				) {
					days {
						date
						timeslots {
							time
							episodes {
								number
								airdate
								anime {
									databaseId
									romajiTitle
									englishTitle
									anidbUrl
									anilistUrl
									animePlanetUrl
									anisearchUrl
									annUrl
									kitsuUrl
									malUrl
								}
							}
						}
					}
				}
			}
		]]
	})
end

getAppScheduleForDay("2025-05-09")




