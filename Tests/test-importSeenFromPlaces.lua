-- Tests/test-importSeenFromPlaces.lua

--[[
Tests the importSeenFromPlaces interface against a disk file
--]]




--- The filename to load for import:
local fileName = "Import/places.sqlite"





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

local import = require("importSeenFromPlaces")

print("Building session...")
local session = import.buildSession(fileName)

-- Dump to console:
for _, item in ipairs(session.items) do
	if (item.candidates.n == 1) then
		print(string.format(
			"FOUND a match: \"%s\" matches aid %d - \"%s\"",
			item.title, item.candidates[1].aId, item.candidates[1].details.enTitle
		))
	elseif (item.candidates.n == 0) then
		print(string.format("NOT FOUND a match for \"%s\"", item.title))
	else
		print(string.format("FOUND MULTIPLE matches for \"%s\":", item.title))
		for _, m in ipairs(item.candidates) do
			print(string.format("  aId %d - \"%s\"", m.aId, m.details.enTitle))
		end
	end
end

print("Done")
