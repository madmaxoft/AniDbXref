-- Tests/test-caseInsensitiveDict.lua

--[[
Implements the test for the caseInsensitiveDict class.
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;./?.lua;Tests/?.lua" .. package.path

local cid = require("caseInsensitiveDict")





local function testSimpleStorage()
	local dict = cid.new()
	dict["someKey"] = "someValue"
	assert(dict.somekey == "someValue")
	dict.anotherKey = "anotherValue"
	assert(dict["AnotherKey"] == "anotherValue")
end





local function testEnumeration()
	local dict = cid.new()
	dict.someKey = "someValue"
	dict.anotherKey = "anotherValue"

	local collected = {}
	local n = 0
	for k, v in dict:pairs() do
		collected[k] = true
		n = n + 1
	end
	assert(n == 2)
	assert(collected.somekey)
	assert(collected.anotherkey)
	assert(not(collected.nonexistentkey))
end





testSimpleStorage()
testEnumeration()