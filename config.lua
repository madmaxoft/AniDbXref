-- config.lua

--[[ Implements the backend for loading and storing configuration values.
Each config value has a string identifier and a simple Lua value (string or number)
Upon startup, the app registers known identifiers with their metadata, so that a config editor can use that
to display UI for editing.
Config values are stored in the user DB. The metadata is not stored.

Usage:
local config = require("config")
config.registerDefinitions(...)

...
config.get("some.value")

Config definitions specify the generic behavior of the config:
	- identifier [required] - the globally-unique config identifier
	- description [required] - the user-visible description of the config value
	- valueType [required] - one of "string", "number", "bool"
	- default [required] - the default value used when not present in the DB
	- validator - the function(aValue) that should return true if value is acceptable, nil and message if not
	- category - the UI category to put the setting in
	- orderInCategory - the UI order within the category
	- isRestartRequired - if true, the setting will not apply unti lapp restart
	- isSecret - if true, the editor UI will make the entry masked and will require entering twice for confirmation (string values only)
	- isMultiline - if true, the editor UI will use a multiline textarea instead of a single line input (string values only)

The main module must, beside requiring the config module and registering definitions, call loadAll() once all
the definitions are registered.
--]]





--- The API of the entire module
local config = {}

--- The metadata about known config values (see config.registerDefinitions() )
local gDefinitions = {}

--- The config values loaded from the DB
local gValues = {}





local db = require("db")





--- Returns the config value represented by the specified DB value
-- Inverse of configValueToDbValue()
-- (We need this because the DB can't store booleans directly)
local function dbValueToConfigValue(aValue, aDef)
	if (aValue == nil) then
		return nil
	end

	if (aDef.valueType == "bool") then
		return (aValue == "1")
	end

	if (aDef.valueType == "number") then
		return tonumber(aValue)
	end

	return aValue
end





--- Returns the DB representation of the specified config value
-- Inverse of dbValueToConfigValue()
-- (We need this because the DB can't store booleans directly)
local function configValueToDbValue(aValue, aDef)
	if (aValue == nil) then
		return nil
	end

	if (aDef.valueType == "bool") then
		return aValue and "1" or "0"
	end

	return tostring(aValue)
end





--- Registers config definitions
-- aDefinitions is an array of config definitions
function config.registerDefinitions(aDefinitions)
	for _, def in ipairs(aDefinitions) do
		assert(type(def.identifier) == "string")
		assert(type(def.description) == "string")
		assert(type(def.valueType) == "string")
		assert(not(gDefinitions[def.identifier]))  -- Duplicate definition

		-- Defaults for UI:
		def.category = def.category or "General"
		def.orderInCategory = def.orderInCategory or 1000

		-- Check the valueType:
		assert(
			(def.valueType == "string") or
			(def.valueType == "number") or
			(def.valueType == "bool"),
			string.format("Invalid valueType for %s", def.identifier)
		)

		-- Add the definition:
		gDefinitions[def.identifier] = def

		-- Validate the default value:
		local isOK, err = config.validate(def.identifier, def.default)
		assert(isOK, string.format(
			"Invalid default value for %s: %s",
			def.identifier,
			err or "validation failed"
		))
	end
end





--- Returns definition for identifier
function config.definition(aIdentifier)
	return gDefinitions[aIdentifier]
end





--- Returns the stored value (or default if not set)
-- Raises an error if value not stored and no definition known
function config.get(aIdentifier)
	local value = gValues[aIdentifier]
	if (value ~= nil) then
		return value
	end

	local def = gDefinitions[aIdentifier]
	if not(def) then
		error(string.format("Unknown config key: %s", aIdentifier))
	end

	return def.default
end





--- Returns the model of the current config suitable for an editor
-- Returns an array-table of {identifier = "", description = "", valueType = "", value = ..., default = ...,
-- category = "", orderInCategory = ..., isRestartRequired = ...}
-- The value member is only provided if explicitly set
-- The array is sorted by category and orderInCategory
function config.editorModel()
	local result = {}
	local n = 0
	for id, def in pairs(gDefinitions) do
		n = n + 1
		result[n] =
		{
			identifier = id,
			description = def.description,
			valueType = def.valueType,
			value = gValues[id],
			default = def.default,
			category = def.category,
			orderInCategory = def.orderInCategory,
			isRestartRequired = def.isRestartRequired,
			isSecret = def.isSecret,
			isMultiline = def.isMultiline,
		}
	end
	result.n = n

	-- Sort by category, then by order in category:
	table.sort(result,
		function(a, b)
			if (a.category ~= b.category) then
				return (a.category < b.category)
			end
			if (a.orderInCategory ~= b.orderInCategory) then
				return (a.orderInCategory < b.orderInCategory)
			end
			return (a.identifier < b.identifier)
		end
	)
	return result
end





--- Validates and stores the value
-- If the new value is nil, removes the setting
-- Returns true on success, nil and error message on error (no definition, validation error)
function config.set(aIdentifier, aValue)
	local def = gDefinitions[aIdentifier]
	if not(def) then
		return nil, string.format("Unknown config key: %s", aIdentifier)
	end

	-- Validate, unless nil ( = revert value to default, always possible)
	if (aValue) then
		local isOK, err = config.validate(aIdentifier, aValue)
		if not(isOK) then
			return nil, "Validation failed: " .. tostring(err)
		end
	end

	gValues[aIdentifier] = aValue
	db.setConfigValue(aIdentifier, configValueToDbValue(aValue, def))
	return true
end





--- Validates a value
-- Returns true on success, nil and error message on failure
function config.validate(aIdentifier, aValue)
	local def = gDefinitions[aIdentifier]
	if not(def) then
		return nil, "Unknown setting"
	end

	if (def.validator) then
		return def.validator(aValue)
	end

	return true
end





--- Returns all values (merged defaults + overrides)
function config.allValues()
	local result = {}

	for id, def in pairs(gDefinitions) do
		local value = gValues[id]
		if (value == nil) then
			value = def.default
		end
		result[id] = value
	end

	return result
end





--- Loads the values from the DB
function config.loadAll()
	local values = assert(db.allConfigValues())

	for _, v in ipairs(values) do
		local def = gDefinitions[v.identifier]
		if (def) then
			gValues[v.identifier] = dbValueToConfigValue(v.dbValue, def)
		end
	end
end





return config
