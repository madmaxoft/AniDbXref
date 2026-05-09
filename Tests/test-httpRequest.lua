-- Tests/test-httpRequest.lua

--[[
Implements tests for the thtpRequest class.
A fake socket implementation is used to feed in test data to the parser.
--]]




-- Adjust the package load path so that the local modules can be loaded:
package.path = "../?.lua;./?.lua;Tests/?.lua" .. package.path

local httpRequest = require("httpRequest")
local fakeSocket = require("fakeSocket")




--- Tests the form data "application/x-www-form-urlencoded" parser
local function testFormDataFormUrlEncoded()
	local body = "name=John+Doe&age=42&city=New+York"
	local socket = fakeSocket.new(table.concat({
		"POST /submit HTTP/1.1\r\n",
		"Host: example.com\r\n",
		"Content-Type: application/x-www-form-urlencoded\r\n",
		"Content-Length: " .. tostring(#body) .. "\r\n",
		"\r\n",
		body,
	}))

	local request = httpRequest.createFromSocket(socket)
	local formData = request:formData()

	assert(type(formData) == "table")
	assert(formData.name == "John Doe")
	assert(formData.age == "42")
	assert(formData.city == "New York")

	local formData2 = request:formData()
	assert(formData2 == formData)
end





--- Tests the form data "multipart/form-data" parser
local function testFormDataMultipart()
	local boundary = "---------------------------123456789"

	local body = table.concat({
		"--" .. boundary .. "\r\n",
		"Content-Disposition: form-data; name=\"username\"\r\n",
		"\r\n",
		"alice\r\n",

		"--" .. boundary .. "\r\n",
		"Content-Disposition: form-data; name=\"password\"\r\n",
		"\r\n",
		"secret123\r\n",

		"--" .. boundary .. "--\r\n",
	})

	local socket = fakeSocket.new(table.concat({
		"POST /login HTTP/1.1\r\n",
		"Host: example.com\r\n",
		"Content-Type: multipart/form-data; boundary=" .. boundary .. "\r\n",
		"Content-Length: " .. tostring(#body) .. "\r\n",
		"\r\n",
		body,
	}))

	local request = httpRequest.createFromSocket(socket)
	local formData = request:formData()

	assert(type(formData) == "table")
	assert(formData.username == "alice")
	assert(formData.password == "secret123")
end





testFormDataFormUrlEncoded()
testFormDataMultipart()
