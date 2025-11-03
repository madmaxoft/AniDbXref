-- dbUpgrade.lua
-- Handles schema versioning and upgrades for the anime database

local sqlite3 = require("lsqlite3")

local dbUpgrade = {}




--- Copies a file in binary mode
function dbUpgrade.copyFile(aSrc, aDst)
	local inFile = assert(io.open(aSrc, "rb"))
	local data = inFile:read("*a")
	inFile:close()

	local outFile = assert(io.open(aDst, "wb"))
	outFile:write(data)
	outFile:close()
end




--- Creates a backup copy of the DB file before upgrade
function dbUpgrade.backupDbFile(aDbPath)
	local timeStamp = os.date("%y%m%d-%H%M%S")
	local backupPath = aDbPath:gsub("%.sqlite$", "") .. "-" .. timeStamp .. ".sqlite"
	print("[DB] Creating backup: " .. backupPath)
	dbUpgrade.copyFile(aDbPath, backupPath)
end




--- Gets current schema version from KeyValue (0 if missing)
function dbUpgrade.getSchemaVersion(aConn)
	local version = 0
	local stmt = aConn:prepare("SELECT value FROM KeyValue WHERE key = 'schema_version';")
	if (stmt) then
		for row in stmt:nrows() do
			version = tonumber(row.value) or 0
		end
		stmt:finalize()
	end
	return version
end




--- Updates schema version in KeyValue
function dbUpgrade.setSchemaVersion(aConn, aVersion)
	local stmt = aConn:prepare("INSERT OR REPLACE INTO KeyValue (key, value) VALUES ('schema_version', ?)")
	if (not stmt) then error("Failed to prepare schema version update: " .. aConn:errmsg()) end
	stmt:bind_values(tostring(aVersion))
	stmt:step()
	stmt:finalize()
end




--- Upgrade scripts: each entry defines version and SQL to reach it
local upgrades = {
	{
		version = 1,
		script = [[
			CREATE TABLE IF NOT EXISTS Anime (
				aId INTEGER PRIMARY KEY
			);

			CREATE TABLE IF NOT EXISTS AnimeTitle (
				aId INTEGER NOT NULL,
				language TEXT NOT NULL,
				kind TEXT NOT NULL,
				title TEXT NOT NULL,
				titleLower TEXT NOT NULL,
				FOREIGN KEY (aId) REFERENCES Anime(aId)
			);

			CREATE TABLE IF NOT EXISTS Seen (
				aId INTEGER PRIMARY KEY,
				seenDate TEXT NOT NULL,
				FOREIGN KEY (aId) REFERENCES Anime(aId)
			);

			CREATE TABLE IF NOT EXISTS AnimeBaseDetails (
				aId INTEGER NOT NULL,
				startDate TEXT,
				endDate TEXT,
				numEpisodes INTEGER,
				url TEXT,
				kind TEXT,
				description TEXT,
				pictureId TEXT,
				lastUpdated TEXT,
				PRIMARY KEY (aId),
				FOREIGN KEY (aId) REFERENCES Anime(aId)
			);

			CREATE TABLE IF NOT EXISTS AnimeEpisode (
				aId INTEGER NOT NULL,
				id INTEGER NOT NULL,
				kind INTEGER,
				episodeNumber TEXT NOT NULL,
				length REAL,
				airDate TEXT,
				PRIMARY KEY (id),
				FOREIGN KEY (aId) REFERENCES Anime(aId)
			);
			
			CREATE TABLE IF NOT EXISTS AnimeEpisodeTitle (
				aId INTEGER NOT NULL,
				episodeId INTEGER NOT NULL,
				language TEXT,
				title TEXT,
				FOREIGN KEY (aId) REFERENCES Anime(aId),
				FOREIGN KEY (episodeId) REFERENCES AnimeEpisode(id)
			)

			CREATE TABLE IF NOT EXISTS AnimeCharacter (
				aId INTEGER NOT NULL,
				characterTypeId TEXT,
				name TEXT,
				gender TEXT,
				description TEXT,
				voiceActorId INTEGER,
				pictureId TEXT,
				ratingNumVotes INTEGER,
				ratingValue REAL,
				FOREIGN KEY (aId) REFERENCES Anime(aId)
			);

			CREATE TABLE IF NOT EXISTS AnimeVoiceActor (
				vaId INTEGER PRIMARY KEY AUTOINCREMENT,
				name TEXT,
				pictureId INTEGER
			);
			
			CREATE TABLE IF NOT EXISTS AnimeRelated (
				aId INTEGER,
				relatedAid INTEGER,
				relation TEXT
				PRIMARY KEY (aId, relatedAid),
				FOREIGN KEY (aId) REFERENCES Anime(aId),
				FOREIGN KEY (relatedAid) REFERENCES Anime(aId)
			);

			CREATE TABLE IF NOT EXISTS AnimeSimilar (
				aId INTEGER,
				similarAid INTEGER,
				PRIMARY KEY (aId, similarAid),
				FOREIGN KEY (aId) REFERENCES Anime(aId),
				FOREIGN KEY (similarAid) REFERENCES Anime(aId)
			);

			CREATE TABLE IF NOT EXISTS AnimeRecommendation (
				aId INTEGER,
				uId INTEGER,
				kind TEXT,
				text TEXT,
				PRIMARY KEY (aId, uId),
				FOREIGN KEY (aId) REFERENCES Anime(aId)
			);
			
			CREATE TABLE IF NOT EXISTS AnimeCreator (
				aId INTEGER,
				id INTEGER,
				kind TEXT,
				name TEXT,
				PRIMARY KEY (aId, id),
				FOREIGN KEY (aId) REFERENCES Anime(aId)
			);
			
			CREATE TABLE IF NOT EXISTS AnimeTag (
				aId INTEGER,
				id INTEGER,
				weight REAL,
				PRIMARY KEY (aId, id)
				FOREIGN KEY (aId) REFERENCES Anime(aId)
			);
			
			CREATE TABLE IF NOT EXISTS Picture (
				pictureId INTEGER PRIMARY KEY AUTOINCREMENT,
				data BLOB
			);

			CREATE TABLE IF NOT EXISTS KeyValue (
				key TEXT PRIMARY KEY,
				value TEXT
			);

			INSERT OR IGNORE INTO KeyValue (key, value) VALUES ('schema_version', '1');
			
			CREATE INDEX IF NOT EXISTS idx_AnimeTitle_titleLower ON AnimeTitle(titleLower);
		]]
	},
	-- Future upgrades can be added here
}




--- Runs all needed upgrades in order
function dbUpgrade.upgradeIfNeeded(aConn, aDbPath)
	local current = dbUpgrade.getSchemaVersion(aConn)
	local latest = upgrades[#upgrades].version

	if (current >= latest) then
		print("[DB] Schema up to date (v" .. current .. ")")
		return
	end

	print("[DB] Current schema v" .. current .. ", latest v" .. latest .. " — upgrading...")

	-- Ensure KeyValue table exists early for first-time DBs
	aConn:exec("CREATE TABLE IF NOT EXISTS KeyValue (key TEXT PRIMARY KEY, value TEXT);")

	for i = 1, #upgrades do
		local u = upgrades[i]
		if (u.version > current) then
			print("[DB] Applying upgrade to v" .. u.version .. "...")
			local result = aConn:exec(u.script)
			if (result ~= sqlite3.OK) then
				error("DB upgrade to v" .. u.version .. " failed: " .. aConn:errmsg())
			end
			dbUpgrade.setSchemaVersion(aConn, u.version)
			print("[DB] Schema upgraded to v" .. u.version)
		end
	end
end

return dbUpgrade
