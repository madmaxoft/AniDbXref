# Basic architecture

The app is written in Lua and runs a local webserver, so users interact with it through their browsers. The data is stored in a SQLite database.

The main program starts a LuaSocket-based server wrapped in Copas coroutines for handling multiple connections at the same time. The UI is provided in the Templates folder, Etlua is used to render data into HTML templates. A router pattern is used to distribute the HTTP requests to their appropriate handlers.


## Data sources

The data is primarily obtained from AniDB.net. The entire list of titles at [http://anidb.net/api/anime-titles.xml.gz] is used to populate the "known" anime titles and to provide searching capability. Since the list should be downloaded at most once per day, a limiter is placed on this update path.
The second source of data is the [AniDB HTTP API](https://wiki.anidb.net/HTTP_API_Definition), which is used to query the details of a title that the user wishes to add to their list.
The last source of data is an actual web scrape of AniDB webpages for the data that is not available in the API - that is mainly the xref data about voice actors.


## Database module

The database module provides access to the data in the SQLite database, wrapped into convenient function calls. It provides the means for backing up the DB and upgrading to newer DB schema version, by using a list of versioned upgrade scripts.


## Router

The router handles routing the individual HTTP requests to their respective handlers. Each route entry is identified by an HTTP method, URL patter and the handler function. The handler function takes as parameters the client socket, the URL path, the matches from the URL pattern and the request HTTP headers. The handler is expected to send the response to the client, possibly using the httpResponse module.

There is a special handler that handles serving static files from the Static folder.

When the handlers need to output HTML, they can do so using etlua templating and the templates in the Templates folder.
