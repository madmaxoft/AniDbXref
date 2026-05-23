-- Tests/liveChartLogin.sample.lua

--[[
This is an example config file for LiveChart.me login, used by the tests.

In order to use LiveChart.me API, make a copy of this file as liveChartLogin.lua and change it to contain
your credentials.
Do NOT commit the new credentials file to git!
--]]




return
{
	email = "renge@livechart.me",
	password = "secret",

	-- Once the token is retrieved, you can store it here to avoid re-sending auth all the time:
	accessToken = "token",
}
