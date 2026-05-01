-- Handlers/configEditor.lua

--[[
Implements the handler responsible for providing the config editor
--]]

local config = require("config")





--- The API of this module, returned from this file
local CE = {}





--- The base GET handler, sends the editor form page
function CE.get(aRequest, aResponse)
	assert(aRequest)
	assert(aRequest.header)
	assert(aResponse)
	assert(aResponse.sendTemplate)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	return aResponse:sendTemplate("configEditor", {config = config.editorModel() or {} })
end





--- Handles updating a single config value via a POST request
function CE.post(aRequest, aResponse)
	assert(aRequest)
	assert(aRequest.header)
	assert(aResponse)
	assert(aResponse.sendTemplate)
	assert(aRequest:method() == "POST")

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	-- Read the form fields:
	local body = aRequest:readAll()
	local form = aRequest.parseFormUrlEncoded(body)
	if not(form) then
		return aResponse:sendError(400, "Failed to parse request body")
	end
	if not(form.id) then
		return aResponse:sendError(400, "No id in the form data")
	end
	if not(form.value) then
		return aResponse:sendError(400, "No value in the form data")
	end
	if not(form.action) then
		return aResponse:sendError(400, "No action in the form data")
	end

	if (form.action == "revert") then
		local isOK, msg = config.set(form.id, nil)
		if not(isOK) then
			return aResponse:sendError(400, "Failed to revert config value: " .. tostring(msg))
		end
		return aResponse:sendRedirect("/config")
	end

	-- Normalize the value according to config type:
	local def = config.definition(form.id)
	if not(def) then
		return aResponse:sendError(400, "Unknown config id")
	end
	if (def.valueType == "bool") then
		form.value = (form.value == "1")
	elseif (def.valueType == "number") then
		form.value = tonumber(form.value)
		if not(form.value) then
			return aResponse:sendError(400, "Cannot parse as number")
		end
	end

	-- Store the value:
	local isOK, msg = config.set(form.id, form.value)
	if not(isOK) then
		return aResponse:sendError(400, "Failed to store config value: " .. tostring(msg))
	end

	return aResponse:sendRedirect("/config")
end





return CE
