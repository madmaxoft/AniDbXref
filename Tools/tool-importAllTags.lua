-- Tools/tool-importAllTAgs.lua

--[[
Imports the tags from all local AniDB/.../<id>.xml files into the global Tag table
--]]





-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;" .. package.path

local db = require("db")
local lomParser = require("lxp.lom")
local perf = require("perf")
local lfs = require("lfs")





--- Parses a single <tag> element into the tag definition
-- Returns the dict-table tag definition
-- Returns nil and error message on failure
local function parseTag(aTag)
	assert(type(aTag) == "table")

	local res =
	{
		tagId = tonumber(aTag.attr["id"]),
		parentId = tonumber(aTag.attr["parentid"]),
	}
	if not(res.tagId) then
		return nil, "No id attribute found"
	end
	for idx, v in ipairs(aTag) do
		if (type(v) == "table") then
			if (v.tag == "name") then
				res.name = v[1]
			elseif (v.tag == "description") then
				res.description = v[1]
			elseif (v.tag == "picurl") then
				res.pictureId = v[1]
			end
		end
	end
	return res
end





--- Parses all the tags in aTags into an array-table
-- aTags if the LOM subtree of the <tags> element
-- Returns an array table of the tag definitions
-- Returns nil and error message on failure
local function parseTags(aTags)
	assert(type(aTags) == "table")

	local tags = {}
	local n = 0
	for idx, v in ipairs(aTags) do
		if (type(v) == "table") then
			if (v.tag == "tag") then
				-- New <tag> encountered
				local tag, msg = parseTag(v)
				if not(tag) then
					return nil, string.format("Failed to parse tag %d: %s", idx, tostring(msg))
				end
				n = n + 1
				tags[n] = tag
			end
		end
	end
	tags.n = n
	return tags
end





--- Processes the tags in the specified XML file
local function processFile(aFileName)
	print("  Processing file " .. aFileName)

	-- Parse the XML into LOM:
	local f = assert(io.open(aFileName, "rb"))
	local contents = f:read("*all")
	f:close()
	local lom, msg = lomParser.parse(contents)
	if not(lom) then
		error(string.format("Failed to LOM-parse file %s: %s", aFileName, tostring(msg)))
	end

	-- Parse all the tags:
	for _, v in ipairs(lom) do
		if (type(v) == "table") then
			if (v.tag == "tags") then
				local tags, msg = parseTags(v)
				if not(tags) then
					error(string.format("Failed to parse tags from file %s: %s", aFileName, tostring(msg)))
				end
				db.addGlobalTags(tags)
			end
		end
	end
end





--- Processes all XML files in the specified folder and, recursively, subfolders
local function processFolder(aFolder)
	print("Processing folder " .. aFolder)
	for fnam in lfs.dir(aFolder) do
		if ((fnam ~= ".") and (fnam ~= "..")) then
			local fullName = aFolder .. "/" .. fnam
			local mode = lfs.attributes(fullName, "mode")
			if (mode == "directory") then
				processFolder(fullName)
			elseif (mode == "file") then
				if (fnam:match("%.xml$")) then
					processFile(fullName)
				end
			end
		end
	end
end





db.beginTransaction()
processFolder("AniDB")
db.commitTransaction()
