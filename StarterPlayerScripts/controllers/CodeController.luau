local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.shared.Packages
local BridgeNet2 = require(Packages.BridgeNet2)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local TopbarPlus = require(Packages.Icon)

local serviceUtils = ReplicatedStorage.shared.serviceUtils
local CodeUtils = require(serviceUtils.CodeUtils)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local RESPONSE_TIMEOUT = 8
local MAX_REASON_LENGTH = 64
local UI_WAIT_TIMEOUT = 10
local FEEDBACK_DURATION = 2.5

local FEEDBACK_MESSAGES: { [string]: string } = {
	already_redeemed = "Already redeemed!",
	expired          = "Code expired!",
	sold_out         = "Code sold out!",
	group_required   = "Join the group!",
	account_too_new  = "Account too new!",
	rate_limited     = "Slow down!",
	locked_out       = "Too many tries!",
	data_unavailable = "Loading, try again!",
	timeout          = "No response!",
}

export type RedeemResult = {
	success: boolean,
	reason: string?,
	code: string?,
	rewards: { CodeUtils.Reward }?,
}

export type CodeController = {
	onRedeemResult: Signal.Signal<RedeemResult>,
	redeem: (self: CodeController, rawCode: string) -> (),
	init: (self: CodeController) -> (),
	destroy: (self: CodeController) -> (),
}

local RemoteRedeem = BridgeNet2.ClientBridge("Codes.Redeem")
local RemoteRedeemResponse = BridgeNet2.ClientBridge("Codes.RedeemResponse")

local CodeController = {} :: CodeController
CodeController.__index = CodeController
CodeController.onRedeemResult = Signal.new() :: Signal.Signal<RedeemResult>

local _trove = Trove.new()
local _pending = false
local _timeoutThread: thread? = nil
local _feedbackThread: thread? = nil
local _textBox: TextBox? = nil
local _defaultPlaceholder = ""
local _icon: any = nil

local function _cancelTimeout(): ()
	if _timeoutThread then
		task.cancel(_timeoutThread)
		_timeoutThread = nil
	end
end

local function _flashFeedback(result: RedeemResult): ()
	local textBox = _textBox
	if not textBox then
		return
	end

	local message = if result.success
		then "Code redeemed!"
		else FEEDBACK_MESSAGES[result.reason or ""] or "Wrong code!"

	if _feedbackThread then
		task.cancel(_feedbackThread)
		_feedbackThread = nil
	end

	textBox.Text = ""
	textBox.PlaceholderText = message

	_feedbackThread = task.delay(FEEDBACK_DURATION, function()
		_feedbackThread = nil
		if _textBox then
			_textBox.PlaceholderText = _defaultPlaceholder
		end
	end)
end

local function _sanitizeResponse(result: unknown): RedeemResult?
	if type(result) ~= "table" then
		return nil
	end

	local payload = result :: { [string]: any }
	if type(payload.success) ~= "boolean" then
		return nil
	end

	local reason: string? = nil
	if type(payload.reason) == "string" and #payload.reason <= MAX_REASON_LENGTH then
		reason = payload.reason
	end

	local code: string? = nil
	if type(payload.code) == "string" and #payload.code <= CodeUtils.MAX_LENGTH then
		code = payload.code
	end

	local rewards: { CodeUtils.Reward }? = nil
	if type(payload.rewards) == "table" and #payload.rewards <= 10 then
		rewards = payload.rewards
	end

	return { success = payload.success, reason = reason, code = code, rewards = rewards }
end

local function _handleResponse(result: unknown): ()
	if not _pending then
		return
	end

	local payload = _sanitizeResponse(result)
	if not payload then
		return
	end

	_cancelTimeout()
	_pending = false

	CodeController.onRedeemResult:Fire(payload)
end

function CodeController:redeem(rawCode: string): ()
	if _pending then
		return
	end

	local code = CodeUtils.normalize(rawCode)
	if not code then
		return
	end
	if not CodeUtils.isValidFormat(code).valid then
		CodeController.onRedeemResult:Fire({ success = false, reason = "invalid_code" })
		return
	end

	_pending = true
	RemoteRedeem:Fire(code)

	_timeoutThread = task.delay(RESPONSE_TIMEOUT, function()
		_timeoutThread = nil
		if not _pending then
			return
		end
		_pending = false
		CodeController.onRedeemResult:Fire({ success = false, reason = "timeout" })
	end)
end

local function _findCodeUi(): Instance?
	local existing = PlayerGui:FindFirstChild("Code", true)
	if existing then
		return existing
	end
	local deadline = os.clock() + UI_WAIT_TIMEOUT
	while os.clock() < deadline do
		existing = PlayerGui:FindFirstChild("Code", true)
		if existing then
			return existing
		end
		task.wait(0.1)
	end
	return nil
end

local function _enforceInputLimit(textBox: TextBox): ()
	local text = textBox.Text
	if #text > CodeUtils.MAX_LENGTH then
		textBox.Text = text:sub(1, CodeUtils.MAX_LENGTH)
	end
end

local function _setupUi(): ()
	local code = _findCodeUi()
	if not code then
		warn("Code UI not found in PlayerGui")
		return
	end

	local textBox = code:FindFirstChild("TextBox", true)
	if not textBox or not textBox:IsA("TextBox") then
		warn("TextBox not found inside the Code frame")
		return
	end
	_textBox = textBox
	_defaultPlaceholder = textBox.PlaceholderText

	local icon = TopbarPlus.new()
	icon:setName("Codes")
	icon:setLabel("Codes")
	icon:bindToggleItem(code)
	_icon = icon
	_trove:Add(function()
		icon:destroy()
	end)

	local closeButton = code:FindFirstChild("X", true)
	if closeButton and closeButton:IsA("GuiButton") then
		_trove:Add(closeButton.Activated:Connect(function()
			icon:deselect()
		end))
	end

	_trove:Add(textBox:GetPropertyChangedSignal("Text"):Connect(function()
		_enforceInputLimit(textBox)
	end))

	_trove:Add(textBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			CodeController:redeem(textBox.Text)
		end
	end))

	_trove:Add(CodeController.onRedeemResult:Connect(_flashFeedback))
end

function CodeController:init(): ()
	_trove:Add(RemoteRedeemResponse:Connect(_handleResponse))
	_setupUi()
end

function CodeController:destroy(): ()
	_cancelTimeout()
	if _feedbackThread then
		task.cancel(_feedbackThread)
		_feedbackThread = nil
	end
	_pending = false
	CodeController.onRedeemResult:DisconnectAll()
	_trove:Destroy()
end

return CodeController