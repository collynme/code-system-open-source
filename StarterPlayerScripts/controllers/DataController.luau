local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.shared.Packages
local Signal = require(Packages.Signal)
local BridgeNet2 = require(Packages.BridgeNet2)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local RemoteGetData = BridgeNet2.ClientBridge("Data.Get")
local RemoteDataChanged = BridgeNet2.ClientBridge("Data.Changed")

export type DataController = {
	onDataReady: Signal.Signal<{}>,
	onDataChanged: Signal.Signal<{}>,
	data: {}?,
	isReady: boolean,
	requestData: (self: DataController) -> (),
	get: (self: DataController, key: string) -> any,
	init: (self: DataController) -> (),
}

local DataController = {} :: DataController
DataController.__index = DataController

local _trove = Trove.new()

DataController.data = nil
DataController.isReady = false
DataController.onDataReady = Signal.new() :: Signal.Signal<{}>
DataController.onDataChanged = Signal.new() :: Signal.Signal<{}>

function DataController:get(key: string): any
	if not self.data then return nil end
	return (self.data :: any)[key]
end

function DataController:requestData(): ()
	RemoteGetData:Fire()
end

local function _applySnapshot(self: DataController, snapshot: {})
	if not self.data then
		self.data = {}
	end

	for key, value in pairs(snapshot) do
		(self.data :: any)[key] = value
	end

	if not self.isReady then
		self.isReady = true
		self.onDataReady:Fire(self.data :: any)
	end

	self.onDataChanged:Fire(self.data :: any)
end

function DataController:init(): ()
	_trove:Add(RemoteDataChanged:Connect(function(snapshot: {})
		if type(snapshot) ~= "table" then return end
		_applySnapshot(self, snapshot)
	end))

	_trove:Add(RemoteGetData:Connect(function(snapshot: {})
		if type(snapshot) ~= "table" then return end
		_applySnapshot(self, snapshot)
	end))

	_trove:Add(LocalPlayer.AncestryChanged:Connect(function()
		if not LocalPlayer:IsDescendantOf(game) then
			_trove:Destroy()
		end
	end))

	task.defer(function()
		self:requestData()
	end)
end

return DataController