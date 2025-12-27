-- logger.lua

--[[
Implements the logging function that prefixes all messages with a timestamp and subsystem name.
It will be easy to extend in the future tu suppress specified subsystems from logging on demand.
Usage:
	local log = require("logger").log

	log("subsystem", "message %s", "supports formatting")
--]]





local L = {}





function L.log(aSubsystemName, aMessageFmt, ...)
	local msg = string.format(aMessageFmt, ...)
	local timeStamp = os.date("[%Y-%m-%d %H:%M:%S]")
	print(string.format("%s [%s] %s", timeStamp, aSubsystemName, msg))
end





return L
