--- Displays confirmation page for starting AniDB dump update
return function(aClient, aRequestPath, aRequestParameters, aRequestHeaders)
	local lastUpdate = require("db").getLastAniDbUpdate() or 0
	local now = os.time()
	local nextAllowed = lastUpdate + 24 * 3600

	local template = require("Templates").updateConfirm

	local renderedHtml = template({
		lastUpdate = os.date("%Y-%m-%d %H:%M:%S", lastUpdate),
		nextUpdate = os.date("%Y-%m-%d %H:%M:%S", nextAllowed),
		canUpdate = ((now - lastUpdate) >= 24*3600)
	})

	require("httpResponse").send(aClient, 200, {["Content-type"] = "text/html"}, renderedHtml)
end
