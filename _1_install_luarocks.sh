#!/bin/sh

# This script installs the LuaRocks' rocks that are required to run the app
# NOTE: Running this script requires the current user to be able to use `sudo`, as it installs the rocks globally





# Abort on error:
set -e

sudo luarocks install copas
sudo luarocks install luasocket
sudo luarocks install lsqlite3
sudo luarocks install etlua
sudo luarocks install luaexpat
sudo luarocks install lua-zlib