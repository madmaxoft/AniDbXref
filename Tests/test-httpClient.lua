-- Tests/test-httpClient.lua

--[[
Implements tests for the httpClient library
--]]




-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

local copas = require("copas")
local socket = require("socket")
local httpClient = require("httpClient")



-- Test framework:

local gTests = {}

local function assertTrue(aValue, aMessage)
	if not(aValue) then
		error("ASSERT TRUE FAILED: " .. (aMessage or ""))
	end
end

local function assertEqual(aExpected, aActual, aMessage)
	if (aExpected ~= aActual) then
		error(
			"ASSERT EQUAL FAILED: "
			.. (aMessage or "")
			.. " expected="
			.. tostring(aExpected)
			.. " actual="
			.. tostring(aActual)
		)
	end
end

local function test(aName, aFn)
	assert(type(aName) == "string")
	assert(type(aFn) == "function")

	table.insert(gTests,
	{
		name = aName,
		fn = aFn,
	})
end





-- Tests:

test("GET basic response", function()
	local status, headers, body = assert(httpClient.get("https://httpbin.org/get"))

	assertEqual(200, status)
	assertTrue(type(body) == "string")
	assertTrue(body:len() > 0)
end)





test("POST JSON body", function()
	local status, headers, body, err = httpClient.post(
		"https://httpbin.org/post",
		{
			["Content-Type"] = "application/json",
		},
		"{\"test\":123}"
	)

	assertEqual(200, status)
	assertTrue(body:find("test") ~= nil)
end)





test("Custom headers roundtrip", function()
	local status, headers, body = httpClient.request(
		{
			url = "https://httpbin.org/headers",
			headers =
			{
				["X-Test-Header"] = "abc123",
			},
		}
	)

	assertEqual(200, status)
	assertTrue(body:find("X%-Test%-Header") ~= nil)
end)





test("Keepalive multiple requests", function()
	local url = "https://httpbin.org/get"

	local s1 = httpClient.get(url)
	local s2 = httpClient.get(url)
	local s3 = httpClient.get(url)

	assertEqual(200, s1)
	assertEqual(200, s2)
	assertEqual(200, s3)
end)





test("Retry-once logic (simulated via invalid host)", function()
	local status, err = httpClient.get("http://invalid.localhost.test")

	assertTrue(status == nil)
	assertTrue(err ~= nil)
end)





test("Chunked response handling", function()
	-- httpbin always uses chunked for some endpoints depending on headers
	local status, headers, body = httpClient.get("https://httpbin.org/stream/5")

	assertEqual(200, status)
	assertTrue(body ~= nil)
	assertTrue(#body > 0)
end)





test("Connection pool limit behavior", function()
	local numTotal = 10
	local numCompleted = 0
	httpClient.resetMetrics()

	-- Start concurrent threads:
	for i = 1, numTotal do
		copas.addthread(function()
			local status = httpClient.get("https://httpbin.org/delay/1")
			assertEqual(200, status)
			numCompleted = numCompleted + 1
		end)
	end

	-- Wait for completion, with a timeout:
	local startTime = socket.gettime()
	while (numCompleted < numTotal) do
		if ((socket.gettime() - startTime) > 10) then
			assert(false, "test timeout: requests did not complete")
		end
		copas.sleep(0)
	end

	assertEqual(numTotal, numCompleted)
	local metrics = httpClient.metrics()
	print("Num connections created: " .. tostring(metrics.numConnectionsCreated))
	assert(metrics.numConnectionsCreated <= 4)
end)





--- Runner
local function runNextTest(i)
	local t = gTests[i]
	if not(t) then
		print("ALL TESTS DONE")
		copas.exit()
		return
	end

	print("Running test: " .. t.name)
	local isOK, err = pcall(t.fn)
	if not(isOK) then
		print("FAIL: " .. t.name)
		print(err)
	else
		print("OK  : " .. t.name)
	end

	copas.sleep(0)
	copas.addthread(function()
		runNextTest(i + 1)
	end)
end




-- Start the tests:
copas.addthread(function()
	runNextTest(1)
end)

-- Run the main copas loop containing the tests:
copas.loop()
