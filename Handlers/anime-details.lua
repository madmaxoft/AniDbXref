local db = require("db")
local httpResponse = require("httpResponse")
local aniDbDetails = require("aniDbDetails")





return function(aClient, aPath, aParams, aHeaders)
	local aId = tonumber(aPath:match("^/anime/(%d+)$"))
	if not(aId) then
		return httpResponse.write(aClient, 400, "text/plain", "Invalid aId")
	end

	local cached = db.getAnimeDetails(aId)
	local needFetch = true

	if (cached and cached.lastUpdated) then
		local y, m, d = cached.lastUpdated:match("(%d+)%-(%d+)%-(%d+)")
		local last = os.time({year=y, month=m, day=d})
		if (os.difftime(os.time(), last) < 7 * 24 * 3600) then
			needFetch = false
		end
	end

	if (needFetch) then
		local parsed, err = aniDbDetails.updateAnimeDetails(aId)
		if (parsed) then
			cached = parsed
		else
			print("[anime-details] Fetch failed:", err)
		end
	end

	local template = require("Templates").animeDetails
	local html = template({ details = cached, aId = aId })
	httpResponse.send(aClient, 200, nil, html)
end
