local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local _bootHost = LocalPlayer:WaitForChild("PlayerScripts")
if _bootHost:GetAttribute("__clientBooted") then return end
_bootHost:SetAttribute("__clientBooted", true)

local Packages = ReplicatedStorage.shared.Packages
local Promise = require(Packages.Promise)
local Trove = require(Packages.Trove)

local ControllersFolder = script.Parent:WaitForChild("controllers") :: Instance

local DATA_CONTROLLER_NAME = "DataController"
local DATA_READY_TIMEOUT = 30
local CLIENT_READY_ATTRIBUTE = "ClientReady"
local BOOT_TOTAL_ATTRIBUTE = "BootTotal"
local BOOT_DONE_ATTRIBUTE = "BootDone"
local BOOT_STEP_ATTRIBUTE = "BootStep"

local _globalTrove = Trove.new()

local function loadController(module: ModuleScript): any?
	local ok, result = pcall(require, module)
	if not ok then
		warn(`Failed to load {module.Name}: {result}`)
		return nil
	end
	if type(result) ~= "table" then
		return nil
	end
	return result
end

local function initController(controller: any, name: string): typeof(Promise.new(function() end))
	if type(controller.init) ~= "function" then
		return Promise.resolve()
	end
	return Promise.try(function()
		controller:init()
	end):catch(function(err)
		warn(`{name} failed to initialize: {err}`)
	end)
end

local function waitForDataReady(DataController: any): typeof(Promise.new(function() end))
	return Promise.new(function(resolve, reject)
		if DataController.isReady then
			return resolve()
		end

		local conn
		conn = DataController.onDataReady:Connect(function()
			conn:Disconnect()
			resolve()
		end)

		task.delay(DATA_READY_TIMEOUT, function()
			if conn._connected then
				conn:Disconnect()
				reject(`Data ready timeout after {DATA_READY_TIMEOUT}s`)
			end
		end)
		return
	end)
end

local function boot()
	local dataModule = ControllersFolder:FindFirstChild(DATA_CONTROLLER_NAME)
	if not dataModule then
		warn(`{DATA_CONTROLLER_NAME} not found. Boot aborted.`)
		return
	end

	local DataController = loadController(dataModule)
	if not DataController then
		return
	end

	local remaining: { { name: string, controller: any } } = {}
	local seen: { [string]: boolean } = { [DATA_CONTROLLER_NAME] = true }

	for _, child in ControllersFolder:GetChildren() do
		if child:IsA("ModuleScript") and not seen[child.Name] then
			seen[child.Name] = true
			local controller = loadController(child)
			if controller then
				table.insert(remaining, { name = child.Name, controller = controller })
			end
		end
	end

	_bootHost:SetAttribute(BOOT_TOTAL_ATTRIBUTE, #remaining + 1)
	_bootHost:SetAttribute(BOOT_DONE_ATTRIBUTE, 0)
	_bootHost:SetAttribute(BOOT_STEP_ATTRIBUTE, DATA_CONTROLLER_NAME)

	initController(DataController, DATA_CONTROLLER_NAME)
		:andThen(function()
			return waitForDataReady(DataController)
		end)
		:andThen(function()
			_bootHost:SetAttribute(BOOT_DONE_ATTRIBUTE, 1)

			return Promise.each(remaining, function(entry, index)
				_bootHost:SetAttribute(BOOT_STEP_ATTRIBUTE, entry.name)
				return initController(entry.controller, entry.name):andThen(function()
					_bootHost:SetAttribute(BOOT_DONE_ATTRIBUTE, index + 1)
				end)
			end)
		end)
		:andThen(function()
			_bootHost:SetAttribute(CLIENT_READY_ATTRIBUTE, true)
		end)
		:catch(function(err)
			_bootHost:SetAttribute(CLIENT_READY_ATTRIBUTE, true)
			warn(`Boot critical failure: {err}`)
		end)
end

_globalTrove:Add(LocalPlayer.AncestryChanged:Connect(function()
	if not LocalPlayer:IsDescendantOf(game) then
		_globalTrove:Destroy()
	end
end))

boot()
