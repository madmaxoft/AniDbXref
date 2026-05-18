-- caseInsensitiveDict.lua

--[[
Implements a case-insensitive dict-table of string -> any value that uses the standard Lua accessor style:
	local dict = caseInsensitiveDict.new()
	dict.someKey = "someValue"
	local v = dict.SomeKey
	assert(v == "someValue")

This is used for storing parsed HTTP form data, because some browsers seem to mangle the case of the form
fields when submitting the form.
--]]





--- The API, exported from this module:
local caseInsensitiveDict = {}





--- Converts a key to lowercase
local function normalizeKey(aKey)
	assert(type(aKey) == "string")

	return string.lower(aKey)
end





--- Reads a value from the map
local function index(aSelf, aKey)
	assert(type(aKey) == "string")
	assert(type(aSelf.mValues) == "table")

	local normalizedKey = normalizeKey(aKey)
	return aSelf.mValues[normalizedKey]
end





--- Writes a value to the map
local function newIndex(aSelf, aKey, aValue)
	assert(type(aKey) == "string")
	assert(type(aSelf.mValues) == "table")

	local normalizedKey = normalizeKey(aKey)
	aSelf.mValues[normalizedKey] = aValue
end





--- Creates a new caseInsensitiveMap instance
function caseInsensitiveDict.new()
	local self = {
		mValues = {},
	}
	setmetatable(self, {
		__index = index,
		__newindex = newIndex,
	})
	return self
end





return caseInsensitiveDict
