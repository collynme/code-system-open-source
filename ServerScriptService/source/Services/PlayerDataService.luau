local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage.shared.Packages
local ProfileStore = require(Packages.ProfileStore)
local Promise = require(Packages.Promise)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local BridgeNet2 = require(Packages.BridgeNet2)

local constants = ReplicatedStorage.shared.constants
local DataTemplate = require(constants.DataTemplate)

local serviceUtils = ReplicatedStorage.shared.serviceUtils
local MathUtils = require(serviceUtils.MathUtils)

local STORE_NAME = DataTemplate._STORE_NAME
local PROFILE_KEY_PREFIX = "Player_"
local RATE_LIMIT_INTERVAL = 0.5
local DATA_READY_TIMEOUT = 30

local SAFE_KEYS_FOR_CLIENT = {
	"currency",
}

export type Service = {
	onProfileLoaded: Signal.Signal<Player>,
	onProfileReleased: Signal.Signal<Player>,
	getProfile: (self: Service, player: Player) -> any?,
	getData: (self: Service, player: Player) -> {}?,
	getKey: (self: Service, player: Player, key: string) -> any,
	setKey: (self: Service, player: Player, key: string, value: any) -> boolean,
	incrementKey: (self: Service, player: Player, key: string, subKey: string, amount: number) -> boolean,
	getCoins: (self: Service, player: Player) -> number,
	addCoins: (self: Service, player: Player, amount: number) -> boolean,
	subtractCoins: (self: Service, player: Player, amount: number) -> boolean,
	syncLeaderstats: (self: Service, player: Player) -> (),
	replicate: (self: Service, player: Player, key: string) -> (),
	waitForProfile: (self: Service, player: Player) -> typeof(Promise.new(function() end)),
	init: (self: Service) -> (),
	destroy: (self: Service) -> (),
}

local _store = if RunService:IsStudio()
	then ProfileStore.New(STORE_NAME .. "_Studio", DataTemplate)
	else ProfileStore.New(STORE_NAME, DataTemplate)

local _profiles: { [Player]: any } = {}
local _playerTroves: { [Player]: any } = {}
local _trove = Trove.new()
local _rateLimits: { [Player]: number } = {}
local _dirty: { [Player]: { [string]: boolean } } = {}

local RemoteGetData = BridgeNet2.ServerBridge("Data.Get")
local RemoteDataChanged = BridgeNet2.ServerBridge("Data.Changed")

local PlayerDataService = {} :: Service
PlayerDataService.__index = PlayerDataService
PlayerDataService.onProfileLoaded = Signal.new() :: Signal.Signal<Player>
PlayerDataService.onProfileReleased = Signal.new() :: Signal.Signal<Player>

local function _buildSafeSnapshot(data: {}): {}
	local snapshot = {}
	for _, key in SAFE_KEYS_FOR_CLIENT do
		local value = (data :: any)[key]
		if value ~= nil then
			(snapshot :: any)[key] = value
		end
	end
	return snapshot
end

local function _isRateLimited(player: Player): boolean
	local now = os.clock()
	local last = _rateLimits[player] or 0
	if (now - last) < RATE_LIMIT_INTERVAL then
		return true
	end
	_rateLimits[player] = now
	return false
end

local function _markDirty(player: Player, key: string): ()
	local keys = _dirty[player]
	if not keys then
		keys = {}
		_dirty[player] = keys
	end
	keys[key] = true
end

local function _flush(): ()
	for player, keys in _dirty do
		local profile = _profiles[player]
		if profile and profile:IsActive() then
			local payload = {}
			for key in keys do
				(payload :: any)[key] = profile.Data[key]
			end
			RemoteDataChanged:Fire(player, payload)
		end
		_dirty[player] = nil
	end
end

local function _createLeaderstats(player: Player): ()
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local coins = Instance.new("StringValue")
	coins.Name = "Coins"
	coins.Value = "0"
	coins.Parent = leaderstats
end

local function _syncLeaderstats(player: Player): ()
	local profile = _profiles[player]
	if not profile or not profile:IsActive() then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	local coins = leaderstats:FindFirstChild("Coins") :: StringValue?
	if coins then
		coins.Value = MathUtils.format(profile.Data.currency.coins)
	end
end

local function _loadProfile(player: Player): ()
	local key = PROFILE_KEY_PREFIX .. tostring(player.UserId)

	local profile = _store:StartSessionAsync(key, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if not profile then
		player:Kick("Failed to load data. Please rejoin.")
		return
	end

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profile:Reconcile()
	profile:AddUserId(player.UserId)

	local playerTrove = Trove.new()
	_playerTroves[player] = playerTrove

	_profiles[player] = profile

	local sessionReleasedNormally = false

	playerTrove:Add(profile.OnSessionEnd:Connect(function()
		_profiles[player] = nil
		if not sessionReleasedNormally then
			player:Kick("Your session was ended by another server.")
		end
	end))

	_createLeaderstats(player)
	_syncLeaderstats(player)

	PlayerDataService.onProfileLoaded:Fire(player)
	RemoteDataChanged:Fire(player, _buildSafeSnapshot(profile.Data))

	playerTrove:Add(function()
		sessionReleasedNormally = true
	end)
end

local function _releaseProfile(player: Player): ()
	local playerTrove = _playerTroves[player]
	if playerTrove then
		playerTrove:Destroy()
		_playerTroves[player] = nil
	end

	local profile = _profiles[player]
	if profile and profile:IsActive() then
		profile:EndSession()
	end

	_profiles[player] = nil
	_rateLimits[player] = nil
	_dirty[player] = nil

	PlayerDataService.onProfileReleased:Fire(player)
end

local function _handleGetData(player: Player): ()
	if _isRateLimited(player) then
		return
	end

	local profile = _profiles[player]
	if not profile or not profile:IsActive() then
		PlayerDataService:waitForProfile(player)
			:andThen(function(loadedProfile)
				RemoteGetData:Fire(player, _buildSafeSnapshot(loadedProfile.Data))
			end)
			:catch(function(err)
				warn(`Failed to wait for profile for {player.Name}: {err}`)
			end)
		return
	end

	RemoteGetData:Fire(player, _buildSafeSnapshot(profile.Data))
end

function PlayerDataService:getProfile(player: Player): any?
	return _profiles[player]
end

function PlayerDataService:getData(player: Player): {}?
	local profile = _profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	return profile.Data
end

function PlayerDataService:getKey(player: Player, key: string): any
	local data = self:getData(player)
	if not data then
		return nil
	end
	return (data :: any)[key]
end

function PlayerDataService:setKey(player: Player, key: string, value: any): boolean
	assert(type(key) == "string" and #key > 0, "invalid key")

	local profile = _profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end

	if DataTemplate[key] == nil then
		return false
	end

	profile.Data[key] = value

	if key == "currency" then
		_syncLeaderstats(player)
		_markDirty(player, key)
	end

	return true
end

function PlayerDataService:incrementKey(player: Player, key: string, subKey: string, amount: number): boolean
	assert(type(key) == "string" and #key > 0, "invalid key")
	assert(type(subKey) == "string" and #subKey > 0, "invalid subKey")
	assert(type(amount) == "number", "amount must be a number")

	local profile = _profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end

	local section = (profile.Data :: any)[key]
	if type(section) ~= "table" then
		return false
	end

	if type(section[subKey]) ~= "number" then
		return false
	end

	section[subKey] = math.max(0, section[subKey] + amount)

	if key == "currency" then
		_syncLeaderstats(player)
		_markDirty(player, key)
	end

	return true
end

function PlayerDataService:getCoins(player: Player): number
	local data = self:getData(player)
	if not data then
		return 0
	end
	return (data :: any).currency.coins or 0
end

function PlayerDataService:addCoins(player: Player, amount: number): boolean
	assert(type(amount) == "number", "amount must be a number")
	assert(amount > 0, "amount must be positive")
	return self:incrementKey(player, "currency", "coins", amount)
end

function PlayerDataService:subtractCoins(player: Player, amount: number): boolean
	assert(type(amount) == "number", "amount must be a number")
	assert(amount > 0, "amount must be positive")

	local profile = _profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end

	if profile.Data.currency.coins < amount then
		return false
	end

	profile.Data.currency.coins -= amount
	_syncLeaderstats(player)
	_markDirty(player, "currency")

	return true
end

function PlayerDataService:syncLeaderstats(player: Player): ()
	_syncLeaderstats(player)
end

function PlayerDataService:replicate(player: Player, key: string): ()
	if type(key) ~= "string" or #key == 0 then
		return
	end
	local profile = _profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	_markDirty(player, key)
end

function PlayerDataService:waitForProfile(player: Player): typeof(Promise.new(function() end))
	return Promise.new(function(resolve, reject)
		if _profiles[player] then
			return resolve(_profiles[player])
		end

		local resolved = false
		local conn
		conn = self.onProfileLoaded:Connect(function(loadedPlayer: Player)
			if loadedPlayer ~= player then
				return
			end
			resolved = true
			conn:Disconnect()
			resolve(_profiles[player])
		end)

		task.delay(DATA_READY_TIMEOUT, function()
			if not resolved then
				resolved = true
				conn:Disconnect()
				reject(`Profile timeout for {player.Name}`)
			end
		end)
		return
	end)
end

function PlayerDataService:init(): ()
	self.onProfileLoaded = Signal.new()
	self.onProfileReleased = Signal.new()

	_trove:Add(RemoteGetData:Connect(_handleGetData))
	_trove:Add(RunService.Heartbeat:Connect(_flush))

	_trove:Add(Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(_loadProfile, player)
	end))

	_trove:Add(Players.PlayerRemoving:Connect(_releaseProfile))

	for _, player in Players:GetPlayers() do
		task.spawn(_loadProfile, player)
	end
end

function PlayerDataService:destroy(): ()
	_trove:Destroy()
	self.onProfileLoaded:DisconnectAll()
	self.onProfileReleased:DisconnectAll()
end

return PlayerDataService