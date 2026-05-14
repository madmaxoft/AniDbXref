-- Tests/test-config.lua

--[[
Defines unit-tests for the config.lua module.
Includes testcases for weird values that may break the underlying storage (false, "", 0)
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true





-- Simple test framework:
local gTestsRun = 0
local gTestsFailed = 0





local function assertEquals(aExpected, aActual, aMessage)
	if (aExpected ~= aActual) then
		gTestsFailed = gTestsFailed + 1
		print("[FAIL] " .. (aMessage or ""))
		print("	expected:", aExpected)
		print("	actual  :", aActual)
		print(debug.traceback())
	else
		print("[OK] " .. (aMessage or ""))
	end

	gTestsRun = gTestsRun + 1
end





local function assertTrue(aValue, aMessage)
	assertEquals(true, aValue, aMessage)
end





local function assertFalse(aValue, aMessage)
	assertEquals(false, aValue, aMessage)
end





-- Mock DB layer:
local gMockDb = {}

local gStored = {}

function gMockDb.allConfigValues()
	local result = {}

	for k, v in pairs(gStored) do
		table.insert(result, {
			identifier = k,
			dbValue = v
		})
	end

	return result
end





function gMockDb.setConfigValue(aIdentifier, aDbValue)
	if (aDbValue == nil) then
		gStored[aIdentifier] = nil
	else
		gStored[aIdentifier] = aDbValue
	end
end





-- Inject mock DB into config module:
package.loaded["db"] = gMockDb





local config = require("config")





-- Define test config schema:
config.registerDefinitions(
{
	{
		identifier = "test.bool",
		description = "Boolean test",
		valueType = "bool",
		default = false
	},

	{
		identifier = "test.number",
		description = "Number test",
		valueType = "number",
		default = 10
	},

	{
		identifier = "test.string",
		description = "String test",
		valueType = "string",
		default = "abc"
	},

	{
		identifier = "test.validated",
		description = "Validated test",
		valueType = "number",
		default = 1,

		validator = function(aValue)
			if (aValue < 0) then
				return nil, "must be >= 0"
			end

			return true
		end
	}
})





print("\n--- CONFIG TESTS ---\n")

-- Basic get default
assertEquals(false, config.get("test.bool"), "default bool")
assertEquals(10, config.get("test.number"), "default number")
assertEquals("abc", config.get("test.string"), "default string")

-- Set and get
config.set("test.number", 42)
assertEquals(42, config.get("test.number"), "set/get number")

config.set("test.bool", true)
assertTrue(config.get("test.bool"), "set/get bool true")

config.set("test.bool", false)
assertFalse(config.get("test.bool"), "set/get bool false (CRITICAL CASE)")

-- Edge cases: false must NOT behave like nil
config.set("test.string", "")
assertEquals("", config.get("test.string"), "empty string must be valid")

-- Validation success
local ok1, err1 = config.set("test.validated", 5)
assertTrue(ok1, "validation success")

-- Validation failure
local ok2, err2 = config.set("test.validated", -1)
assertEquals(nil, ok2, "validation failure returns nil")
assertEquals("Validation failed: must be >= 0", err2, "validation error message")

-- Load/save roundtrip test via mock DB
config.set("test.number", 123)

-- simulate reload
gStored = {
	["test.number"] = "123",
	["test.bool"] = "1"
}
config.loadAll()

assertEquals(123, config.get("test.number"), "load number from DB")
assertTrue(config.get("test.bool"), "load bool true from DB")

-- Unknown key safety
local ok3, err3 = pcall(function()
	config.get("does.not.exist")
end)
assertTrue(ok3 == false, "unknown key should error")





print("\n--- TEST SUMMARY ---")
print("Run:   ", gTestsRun)
print("Failed:", gTestsFailed)

if (gTestsFailed > 0) then
	error("CONFIG TESTS FAILED")
end
