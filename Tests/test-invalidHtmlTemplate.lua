-- Tests/test-invalidHtmlTemplate.lua

--[[
This tests how etlua handles invalid templates.
--]]

local etlua = require("etlua")




-- A bad template to compile
-- (Notice the <%= in front of the "end")
local badTemplate =
[[
<html>
<input type="checkbox" name="isEnabled" value="1" <% if (details.isSeen) then %> checked="true" <%= end %> >
</html>
]]

print("Attempting to compile a bad template:")
print(etlua.compile(badTemplate))  -- Should print "nil" and an error message
