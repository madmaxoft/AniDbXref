-- Tests/test-getVoiceActorDetails.lua

--[[
Tests getting voice actor details
Runs in a singlethreaded environment for easier debugging
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

-- Do not initialize DB's titleSearch
gDbSkipInitTitleSearch = true





--- The voice actor ID to query
local gVoiceActorId = 34626  -- Amamiya Sora





local db = require("db")
local utils = require("utils")

local vaDetails = db.getVoiceActorDetails(gVoiceActorId)
print("VoiceActor details:")
print(utils.serializeSimpleTable(vaDetails))
