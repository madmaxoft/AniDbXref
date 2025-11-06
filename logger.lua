-- logger.lua

--[[ Implements the logging function.
The main uses that to replace the default print function
--]]





local print = print
local tostring = tostring
local select = select
local osdate = os.date
local tblconcat = table.concat




return function (...)
    local timestamp = osdate("[%Y-%m-%d %H:%M:%S]")
    local message = {}
    for i = 1, select("#", ...) do
        message[i] = tostring(select(i, ...))
    end
    print(timestamp, tblconcat(message, "\t"))
end
