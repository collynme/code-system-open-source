local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.shared.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Promise = require(Packages.Promise)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)

local constants = ReplicatedStorage.shared.constants
local CodesConfig = require(constants.CodesConfig)
local DataTemplate = require(constants.DataTemplate)

local serviceUtils = ReplicatedStorage.shared.serviceUtils
local CodeUtils = require(serviceUtils.CodeUtils)

local PlayerDataService = require(script.Parent.PlayerDataService)

local ATTEMPT_INTERVAL = 2
local MAX_FAILED_ATTEMPTS = 8
local FAILURE_WINDOW = 60
local LOCKOUT_DURATION = 120
local CALL_WINDOW = 10
local MAX_CALLS_PER_WINDOW = 10
local RELEASE_RETRY_ATTEMPTS = 3
local REDEMPTIONS_STORE_NAME = "CodeRedemptions_v1"
local REWARD_SECTIONS = { "currency" }

local FAILURE_REASONS: { [string]: boolean } = {
	invalid_code = true,
	expired = true,
	already_redeemed = true,
	group_required = true,
	account_too_new = true,
	sold_out = true,
}

export type RedeemSuccess = {
	code: string,
	rewards: { CodeUtils.Reward },
}

export type CodeService = {
	onCodeRedeemed: Signal.Signal<Player, string>,
	redeem: (self: CodeService, player: Player, rawCode: unknown) -> typeof(Promise.new(function() end)),
	init: (self: CodeService) -> (),
	destroy: (self: CodeService) -> (),
}

type AttemptState = {
	last: number,
	calls: number,
	callsWindowStart: number,
	failures: number,
	windowStart: number,
	lockedUntil: number,
}

local _trove = Trove.new()
local _attempts: { [Player]: AttemptState } = {}
local _inFlight: { [Player]: boolean } = {}
local _registry: { [string]: CodesConfig.CodeEntry } = {}
local _rewardTargets: { [string]: { [string]: boolean } } = {}
local _redemptionsStore: GlobalDataStore? = nil

local RemoteRedeem = BridgeNet2.ServerBridge("Codes.Redeem")
local RemoteRedeemResponse = BridgeNet2.ServerBridge("Codes.RedeemResponse")

local CodeService = {} :: CodeService
CodeService.__index = CodeService

local function _buildRewardTargets(): ()
	for _, sectionName in REWARD_SECTIONS do
		local section = (DataTemplate :: any)[sectionName]
		if type(section) ~= "table" then
			continue
		end
		local targets: { [string]: boolean } = {}
		for subKey, value in section do
			if type(value) == "number" then
				targets[subKey] = true
			end
		end
		_rewardTargets[sectionName] = targets
	end
end

local function _buildRegistry(): ()
	for rawCode, entry in CodesConfig do
		local code = CodeUtils.normalize(rawCode)
		if not code or not CodeUtils.isValidFormat(code).valid then
			warn(`Code config key "{tostring(rawCode)}" has an invalid format and was skipped`)
			continue
		end

		if type(entry) ~= "table" or entry.enabled ~= true then
			continue
		end

		if _registry[code] then
			warn(`Code config key "{code}" is duplicated after normalization and was skipped`)
			continue
		end

		local rewardsResult = CodeUtils.validateRewards(entry.rewards, _rewardTargets)
		if not rewardsResult.valid then
			warn(`Code config key "{code}" has invalid rewards ({rewardsResult.reason}) and was skipped`)
			continue
		end

		local maxRedemptions = entry.maxRedemptions
		if maxRedemptions ~= nil
			and (type(maxRedemptions) ~= "number" or maxRedemptions < 1 or maxRedemptions ~= math.floor(maxRedemptions))
		then
			warn(`Code config key "{code}" has an invalid maxRedemptions and was skipped`)
			continue
		end

		_registry[code] = entry
	end
end

local function _getAttemptState(player: Player): AttemptState
	local state = _attempts[player]
	if not state then
		state = { last = 0, calls = 0, callsWindowStart = 0, failures = 0, windowStart = 0, lockedUntil = 0 }
		_attempts[player] = state
	end
	return state
end

local function _checkThrottle(player: Player): string?
	local state = _getAttemptState(player)
	local now = os.clock()

	if now < state.lockedUntil then
		return "locked_out"
	end

	if (now - state.callsWindowStart) > CALL_WINDOW then
		state.callsWindowStart = now
		state.calls = 0
	end
	state.calls += 1
	if state.calls > MAX_CALLS_PER_WINDOW then
		state.lockedUntil = now + LOCKOUT_DURATION
		return "locked_out"
	end

	if (now - state.last) < ATTEMPT_INTERVAL then
		return "rate_limited"
	end

	state.last = now
	return nil
end

local function _registerFailure(player: Player): ()
	local state = _attempts[player]
	if not state then
		return
	end

	local now = os.clock()
	if (now - state.windowStart) > FAILURE_WINDOW then
		state.windowStart = now
		state.failures = 0
	end

	state.failures += 1
	if state.failures >= MAX_FAILED_ATTEMPTS then
		state.lockedUntil = now + LOCKOUT_DURATION
		state.failures = 0
	end
end

local function _registerSuccess(player: Player): ()
	local state = _attempts[player]
	if state then
		state.failures = 0
	end
end

local function _claimGlobalSlot(code: string, maxRedemptions: number): string?
	local store = _redemptionsStore
	if not store then
		return "try_again"
	end

	local ok, count = pcall(store.IncrementAsync, store, code, 1)
	if not ok or type(count) ~= "number" then
		return "try_again"
	end

	if count > maxRedemptions then
		pcall(store.IncrementAsync, store, code, -1)
		return "sold_out"
	end

	return nil
end

local function _releaseGlobalSlot(code: string): ()
	local store = _redemptionsStore
	if not store then
		return
	end
	task.spawn(function()
		for attempt = 1, RELEASE_RETRY_ATTEMPTS do
			local ok = pcall(store.IncrementAsync, store, code, -1)
			if ok then
				return
			end
			if attempt < RELEASE_RETRY_ATTEMPTS then
				task.wait(2 ^ attempt)
			end
		end
		warn(`Failed to release a redemption slot for code {code}, the global counter is now inflated by one`)
	end)
end

local function _applyRewards(player: Player, rewards: { CodeUtils.Reward }): boolean
	local applied: { CodeUtils.Reward } = {}

	for _, reward in rewards do
		local ok = PlayerDataService:incrementKey(player, reward.key, reward.subKey, reward.amount)
		if not ok then
			for _, granted in applied do
				PlayerDataService:incrementKey(player, granted.key, granted.subKey, -granted.amount)
			end
			return false
		end
		table.insert(applied, reward)
	end

	return true
end

function CodeService:redeem(player: Player, rawCode: unknown): typeof(Promise.new(function() end))
	if _inFlight[player] then
		return Promise.reject("busy")
	end
	_inFlight[player] = true

	return Promise.new(function(resolve, reject)
		local throttleReason = _checkThrottle(player)
		if throttleReason then
			return reject(throttleReason)
		end

		local code = CodeUtils.normalize(rawCode)
		if not code or not CodeUtils.isValidFormat(code).valid then
			return reject("invalid_code")
		end

		local entry = _registry[code]
		if not entry then
			return reject("invalid_code")
		end

		local profile = PlayerDataService:getProfile(player)
		if not profile or not profile:IsActive() then
			return reject("data_unavailable")
		end

		local redeemedCodes = profile.Data.meta.redeemedCodes
		if CodeUtils.hasPlayerRedeemed(redeemedCodes, code) then
			return reject("already_redeemed")
		end

		local condition = entry.condition
		local isInGroup: boolean? = nil
		if condition and condition.groupId then
			local ok, inGroup = pcall(player.IsInGroup, player, condition.groupId)
			isInGroup = ok and inGroup == true
		end

		local conditionOk, conditionReason = CodeUtils.evaluateCondition(condition, {
			now = os.time(),
			accountAgeDays = player.AccountAge,
			isInGroup = isInGroup,
		})
		if not conditionOk then
			return reject(conditionReason)
		end

		local claimedSlot = false
		if entry.maxRedemptions then
			local claimReason = _claimGlobalSlot(code, entry.maxRedemptions)
			if claimReason then
				return reject(claimReason)
			end
			claimedSlot = true
		end

		if not profile:IsActive() or not player.Parent then
			if claimedSlot then
				_releaseGlobalSlot(code)
			end
			return reject("data_unavailable")
		end

		if CodeUtils.hasPlayerRedeemed(redeemedCodes, code) then
			if claimedSlot then
				_releaseGlobalSlot(code)
			end
			return reject("already_redeemed")
		end

		redeemedCodes[code] = os.time()

		if not _applyRewards(player, entry.rewards) then
			redeemedCodes[code] = nil
			if claimedSlot then
				_releaseGlobalSlot(code)
			end
			return reject("reward_failed")
		end

		CodeService.onCodeRedeemed:Fire(player, code)

		resolve({ code = code, rewards = entry.rewards })
	end):finally(function()
		_inFlight[player] = nil
	end)
end

local function _handleRedeem(player: Player, payload: unknown): ()
	if type(payload) ~= "string" or #payload == 0 or #payload > CodeUtils.MAX_RAW_LENGTH then
		RemoteRedeemResponse:Fire(player, { success = false, reason = "invalid_code" })
		return
	end

	CodeService:redeem(player, payload)
		:andThen(function(result: RedeemSuccess)
			_registerSuccess(player)
			RemoteRedeemResponse:Fire(player, { success = true, code = result.code, rewards = result.rewards })
		end)
		:catch(function(reason)
			local reasonText = tostring(reason)
			if FAILURE_REASONS[reasonText] then
				_registerFailure(player)
			end
			RemoteRedeemResponse:Fire(player, { success = false, reason = reasonText })
		end)
end

function CodeService:init(): ()
	self.onCodeRedeemed = Signal.new()

	_buildRewardTargets()
	_buildRegistry()

	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, REDEMPTIONS_STORE_NAME)
	if ok then
		_redemptionsStore = store
	else
		warn(`Code redemptions datastore is unavailable: {store}`)
	end

	_trove:Add(RemoteRedeem:Connect(_handleRedeem))

	_trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
		_attempts[player] = nil
		_inFlight[player] = nil
	end))
end

function CodeService:destroy(): ()
	_trove:Destroy()
	self.onCodeRedeemed:DisconnectAll()
	table.clear(_attempts)
	table.clear(_inFlight)
end

return CodeService