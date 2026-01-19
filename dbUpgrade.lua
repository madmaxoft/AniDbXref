-- dbUpgrade.lua
-- Handles schema versioning and upgrades for the anime database

local sqlite3 = require("lsqlite3")
local lfs = require("lfs")
local log = require("logger").log

local dbUpgrade = {}




--- Executes an SQL command and throws if the command fails.
-- aConn is the DB connection on which to execute the command
-- aContext is a string description of where the check is happenning, for logging purposes
local function executeSql(aConn, aSql, aContext)
	assert(aConn)
	assert(type(aSql) == "string")
	assert(type(aContext) == "string")

	local resultCode = aConn:exec(aSql)
	if (
		(resultCode ~= sqlite3.OK) and
		(resultCode ~= sqlite3.DONE) and
		(resultCode ~= sqlite3.ROW)
	) then
		error(string.format("SQLite error in %s: %s (%s) (SQL: %s)",
			aContext or "unknown",
			tostring(resultCode),
			aConn:errmsg(),
			aSql
		))
	end
end





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
	local time = os.time()
	local timeStamp = os.date("%Y%m%d-%H%M%S", time)
	local year = os.date("%Y", time)
	local day = os.date("%Y-%m-%d", time)
	lfs.mkdir("Backups")
	lfs.mkdir("Backups/" .. year)
	lfs.mkdir("Backups/" .. year .. "/" .. day)
	local backupPath = "Backups/" .. year .. "/" .. day .. "/" .. aDbPath:gsub("%.sqlite$", "") .. "-" .. timeStamp .. ".sqlite"
	log("dbUpgrade", "Creating backup: %s", backupPath)
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
	if not(stmt) then error("Failed to prepare schema version update: " .. aConn:errmsg()) end
	stmt:bind_values(tostring(aVersion))
	stmt:step()
	stmt:finalize()
end




--- Upgrade scripts: each entry defines version and SQL to reach it
local upgrades = {
	-- Version 1:
	{
		scripts = {
			[[
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
	},

	-- Version 2:
	{
		scripts = {[[
			ALTER TABLE Picture ADD COLUMN dataThumb BLOB;
		]]},
	},

	-- Version 3:
	{
		scripts = {[[
			CREATE INDEX IF NOT EXISTS idx_AnimeEpisode_aId_id ON AnimeEpisode(aId, id);
			CREATE INDEX IF NOT EXISTS idx_AnimeEpisodeTitle_aId_episodeId ON AnimeEpisodeTitle(aId, episodeId);
		]]},
	},

	-- Version 4:
	{
		scripts = {[[
			CREATE INDEX idx_AnimeRelated_aId ON AnimeRelated(aId);
			CREATE INDEX idx_AnimeRelated_relatedAid ON AnimeRelated(relatedAid);
			CREATE INDEX idx_AnimeTitle_aId ON AnimeTitle(aId);
			CREATE INDEX idx_AnimeBaseDetails_aId ON AnimeBaseDetails(aId);
		]]},
	},

	-- Version 5:
	{
		scripts = {[[
			DROP TABLE AnimeCharacter;
			ALTER TABLE AnimeVoiceActor RENAME TO VoiceActor;
			ALTER TABLE VoiceActor ADD COLUMN gender TEXT;
			ALTER TABLE VoiceActor ADD COLUMN description TEXT;
			ALTER TABLE VoiceActor ADD COLUMN country TEXT;
			ALTER TABLE VoiceActor ADD COLUMN birthdate TEXT;
			CREATE TABLE Character (
				characterId INTEGER PRIMARY KEY,
				characterTypeId TEXT,
				name TEXT,
				gender TEXT,
				description TEXT,
				pictureId TEXT,
				ratingNumVotes INTEGER,
				ratingValue REAL
			);
			CREATE TABLE AnimeCharacter (
				acId INTEGER PRIMARY KEY AUTOINCREMENT,
				characterId INTEGER,
				aId INTEGER NOT NULL,
				notes TEXT,
				pictureId TEXT,
				FOREIGN KEY (characterId) REFERENCES Character(characterId),
				FOREIGN KEY (aId) REFERENCES Anime(aId)
			);
			CREATE TABLE AnimeCharacterVoiceActor (
				acId INTEGER,
				vaId INTEGER,
				language TEXT,
				episodes TEXT,
				notes TEXT,
				PRIMARY KEY (acId, vaId),
				FOREIGN KEY (acId) REFERENCES AnimeCharacter(acId),
				FOREIGN KEY (vaId) REFERENCES VoiceActor(vaId)
			);

			CREATE INDEX idx_AnimeCharacter_aId ON AnimeCharacter(aId);
			CREATE INDEX idx_AnimeCharacter_characterId ON AnimeCharacter(characterId);
			CREATE INDEX idx_AnimeCharacterVoiceActor_acId ON AnimeCharacterVoiceActor(acId);
			CREATE INDEX idx_AnimeCharacterVoiceActor_vaId ON AnimeCharacterVoiceActor(vaId);
		]]},
	},

	-- Version 6:
	{
		scripts =
		{
			[[
				CREATE TABLE UserData.Seen (
					aId INTEGER NOT NULL,
					seenDate TEXT NOT NULL,
					PRIMARY KEY (aId)
				);
			]],
			[[
				INSERT INTO UserData.Seen (aId, seenDate)
				SELECT aId, seenDate FROM main.Seen;
			]],
			[[ DROP TABLE main.Seen ]],
		},
	},
	-- Future upgrades can be added here
}




--- Runs all needed upgrades in order
function dbUpgrade.upgradeIfNeeded(aConn, aDbPath)
	local current = dbUpgrade.getSchemaVersion(aConn)
	local latest = #upgrades

	if (current >= latest) then
		log("dbUpgrade", "Schema up to date (v%d)", current)
		return
	end

	log("dbUpgrade", "Current schema v%d, latest v%d - upgrading...", current, latest)

	-- Ensure KeyValue table exists early for first-time DBs
	executeSql(aConn, "CREATE TABLE IF NOT EXISTS KeyValue (key TEXT PRIMARY KEY, value TEXT);", "CreateKeyValue")

	for version, upg in ipairs(upgrades) do
		if (version > current) then
			log("dbUpgrade", "Applying upgrade to v%d", version)
			executeSql(aConn, "BEGIN TRANSACTION", string.format("Upgrade.v%d", version))
			for idx, cmd in ipairs(upg.scripts) do
				executeSql(aConn, cmd, string.format("Upgrade.v%d.%d", version, idx))
			end
			dbUpgrade.setSchemaVersion(aConn, version)
			executeSql(aConn, "COMMIT", string.format("Upgrade.v%d", version))
			log("dbUpgrade", "Schema upgraded to v%d", version)
		end
	end
end

return dbUpgrade
