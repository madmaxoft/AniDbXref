-- lowLevelDB.lua

--[[
Implements low-level DB access functions for executing sql statements
--]]





local sqlite3 = require("lsqlite3")




--- Compatibility between Lua 5.1 and LuaJIT
local unpack = unpack or table.unpack

--- The API returned by this module
local lldb = {}





--- Runs the specified SQL query, binding the specified values to it, and returns the results as an array-table of dict-tables
-- aDescription is used for error logging.
function lldb.arrayFromQuery(aDB, aSql, aValuesToBind, aDescription)
	assert(aDB ~= nil)
	assert(type(aSql) == "string")
	assert(type(aValuesToBind) == "table" or not(aValuesToBind))
	if not(aDescription) then
		aDescription = debug.getinfo(1, 'S').source
	end

	local stmt = aDB:prepare(aSql)
	if not(stmt) then
		error("Failed to prepare statement (" .. aDescription .. "): " .. aDB:errmsg())
	end
	if ((aValuesToBind) and (aValuesToBind[1])) then
		lldb.checkSql(aDB, stmt:bind_values(unpack(aValuesToBind)), aDescription .. ".bind")
	end
	local result = {}
	local n = 0
	for row in stmt:nrows() do
		n = n + 1
		result[n] = row
	end
	result.n = n
	lldb.checkSql(aDB, stmt:finalize(), aDescription .. ".finalize")

	return result
end





--- Checks SQLite result codes and raises errors if not success
-- aContext is a string description of where the check is happenning, for logging purposes
function lldb.checkSql(aDB, aResultCode, aContext)
	assert(type(aDB) == "userdata")
	assert(type(aResultCode) == "number")
	assert(type(aContext) == "string")

	if (
		(aResultCode ~= sqlite3.OK) and
		(aResultCode ~= sqlite3.DONE) and
		(aResultCode ~= sqlite3.ROW)
	) then
		error(string.format("SQLite error in %s: %s (%s)",
			aContext or "unknown",
			tostring(aResultCode),
			aDB:errmsg()
		))
	end
end





--- Executes an SQL command and raises an error if the command fails.
-- aConn is the DB connection on which to execute the command
-- aContext is a string description of where the check is happenning, for logging purposes
function lldb.executeSql(aDB, aSql, aContext)
	assert(aDB ~= nil)
	assert(type(aSql) == "string")
	assert(type(aContext) == "string")

	lldb.checkSql(aDB, aDB:exec(aSql), "executeSql." .. tostring(aContext) .. "; SQL: " .. tostring(aSql))
end





--- Executes an SQL command bound to the specified values and raises an error if the command fails.
-- aDB is the DB connection on which to execute the command
-- aContext is a string description of where the check is happenning, for logging purposes
function lldb.executeBoundSql(aDB, aSql, aValuesToBind, aContext)
	assert(aDB ~= nil)
	assert(type(aSql) == "string")
	assert(type(aContext) == "string")

	local stmt = aDB:prepare(aSql)
	if not(stmt) then
		error("Failed to prepare statement (" .. aContext .. "): " .. aConn:errmsg())
	end
	lldb.checkSql(aDB, stmt:bind_values(unpack(aValuesToBind)), aContext .. ".bind")
	lldb.checkSql(aDB, stmt:step(), aContext .. ".step")
	lldb.checkSql(aDB, stmt:finalize(), aContext .. ".finalize")
end





--- Calls the specified callback for each row of the executed DB statement
-- Binds the values before executing the statement
-- If the callback returns true, the execution is aborted
-- Raises an error on failure
function lldb.forEachRowInStatement(aDB, aSql, aValuesToBind, aDescription, aCallback)
	assert(aDB ~= nil)
	assert(type(aSql) == "string")
	assert(type(aValuesToBind) == "table")
	assert(type(aDescription) == "string")
	assert(aCallback)

	local stmt = aDB:prepare(aSql)
	if not(stmt) then
		error("Failed to prepare statement (" .. aDescription .. "): " .. gDB:errmsg())
	end
	if ((aValuesToBind) and (aValuesToBind[1])) then
		lldb.checkSql(aDB, stmt:bind_values(unpack(aValuesToBind)), aDescription .. ".bind")
	end
	for row in stmt:nrows() do
		if (aCallback(row)) then
			break
		end
	end
	lldb.checkSql(aDB, stmt:finalize(), aDescription .. ".finalize")
end





--- Converts the specified value from DB representation to a boolean
function lldb.toBool(aValue)
	return (aValue == "1") or (aValue == 1) or (aValue == true)
end





return lldb
