-- Tests/fakeSocket.lua

--[[
Implements the fakeSocket class representing a mocked socket that is initialized with the data it should
return as input, and stores the data written to it for later inspection.
The class is API-compatible with LuaSocket's sockets, so it can be used as a test harness for code using LuaSocket.
Usage:
	local s = fakeSocket.new("Hello world\n")
	someTestedFunction(s)
	assert(s:sentData() == "Received: Hello world")
--]]




local fakeSocket = {}
fakeSocket.__index = fakeSocket





--- Creates a new fake socket instance that will return the specified data through its receive() function.
function fakeSocket.new(aReceiveData)
	assert(type(aReceiveData) == "string")

	local self = setmetatable(
		{
			mReceiveData = aReceiveData,
			mReceivePosition = 1,
			mSentData = "",
			mIsClosed = false,
		},
		fakeSocket
	)

	return self
end





--- Receives data from the fake socket.
function fakeSocket:receive(aPattern)
	assert(not(self.mIsClosed))

	if (type(aPattern) == "number") then
		return self:_receiveBytes(aPattern)
	end

	if (aPattern == "*l") then
		return self:_receiveLine()
	end

	error("Unsupported receive pattern")
end





--- Sends data to the fake socket.
function fakeSocket:send(aData)
	assert(not(self.mIsClosed))
	assert(type(aData) == "string")

	self.mSentData = self.mSentData .. aData

	return #aData
end





--- Returns all data sent to the fake socket and whether the socket has been closed
function fakeSocket:sentData()
	return self.mSentData, self.mIsClosed
end





--- Closes the fake socket.
function fakeSocket:close()
	self.mIsClosed = true
end





--- Receives a fixed number of bytes.
function fakeSocket:_receiveBytes(aNumBytes)
	assert(type(aNumBytes) == "number")
	assert(aNumBytes >= 0)

	if (self.mReceivePosition > #self.mReceiveData) then
		return nil, "closed"
	end

	local startPos = self.mReceivePosition
	local endPos = math.min(
		startPos + aNumBytes - 1,
		#self.mReceiveData
	)
	local data = self.mReceiveData:sub(startPos, endPos)
	self.mReceivePosition = endPos + 1
	return data
end





--- Receives a single line without the trailing newline.
function fakeSocket:_receiveLine()
	if (self.mReceivePosition > #self.mReceiveData) then
		return nil, "closed"
	end

	local newlinePos = self.mReceiveData:find(
		"\n",
		self.mReceivePosition,
		true
	)

	local line

	if not(newlinePos) then
		line = self.mReceiveData:sub(self.mReceivePosition)
		self.mReceivePosition = #self.mReceiveData + 1
	else
		local lineEnd = newlinePos - 1

		if (
			(lineEnd >= self.mReceivePosition)
			and
			(self.mReceiveData:sub(lineEnd, lineEnd) == "\r")
		) then
			lineEnd = lineEnd - 1
		end

		line = self.mReceiveData:sub(
			self.mReceivePosition,
			lineEnd
		)

		self.mReceivePosition = newlinePos + 1
	end

	return line
end





return fakeSocket
