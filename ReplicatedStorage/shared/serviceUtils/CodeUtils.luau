local CodeUtils = {}

export type ValidationResult = {
	valid: boolean,
	reason: string?,
}

export type Reward = {
	key: string,
	subKey: string,
	amount: number,
}

export type Condition = {
	groupId: number?,
	minAccountAgeDays: number?,
	expiresAt: number?,
}

export type ConditionContext = {
	now: number,
	accountAgeDays: number,
	isInGroup: boolean?,
}

local MIN_LENGTH = 3
local MAX_LENGTH = 32
local MAX_RAW_LENGTH = 64
local MAX_REWARDS_PER_CODE = 10
local MAX_REWARD_AMOUNT = 1_000_000_000

CodeUtils.MIN_LENGTH = MIN_LENGTH
CodeUtils.MAX_LENGTH = MAX_LENGTH
CodeUtils.MAX_RAW_LENGTH = MAX_RAW_LENGTH

function CodeUtils.normalize(raw: unknown): string?
	if type(raw) ~= "string" then
		return nil
	end
	if #raw == 0 or #raw > MAX_RAW_LENGTH then
		return nil
	end
	local trimmed = raw:match("^%s*(.-)%s*$")
	if not trimmed or #trimmed == 0 then
		return nil
	end
	return trimmed:upper()
end

function CodeUtils.isValidFormat(code: unknown): ValidationResult
	if type(code) ~= "string" then
		return { valid = false, reason = "invalid_type" }
	end
	local len = #code
	if len < MIN_LENGTH or len > MAX_LENGTH then
		return { valid = false, reason = "invalid_length" }
	end
	if not code:match("^[A-Z0-9_%-]+$") then
		return { valid = false, reason = "invalid_characters" }
	end
	return { valid = true }
end

function CodeUtils.isExpired(expiresAt: number?, now: number): boolean
	assert(type(now) == "number", "now must be a number")
	if expiresAt == nil then
		return false
	end
	return now > expiresAt
end

function CodeUtils.hasPlayerRedeemed(redeemedCodes: { [string]: any }, code: string): boolean
	return redeemedCodes[code] ~= nil
end

function CodeUtils.validateRewards(rewards: unknown, rewardTargets: { [string]: { [string]: boolean } }): ValidationResult
	if type(rewards) ~= "table" then
		return { valid = false, reason = "rewards_missing" }
	end

	local list = rewards :: { any }
	local count = 0
	for _ in list do
		count += 1
	end

	if count == 0 then
		return { valid = false, reason = "rewards_empty" }
	end
	if count > MAX_REWARDS_PER_CODE or count ~= #list then
		return { valid = false, reason = "rewards_malformed" }
	end

	for _, reward in list do
		if type(reward) ~= "table" then
			return { valid = false, reason = "reward_malformed" }
		end
		if type(reward.key) ~= "string" or type(reward.subKey) ~= "string" then
			return { valid = false, reason = "reward_target_malformed" }
		end

		local section = rewardTargets[reward.key]
		if not section or section[reward.subKey] ~= true then
			return { valid = false, reason = "reward_target_unknown" }
		end

		local amount = reward.amount
		if type(amount) ~= "number"
			or amount ~= amount
			or amount <= 0
			or amount > MAX_REWARD_AMOUNT
			or amount ~= math.floor(amount)
		then
			return { valid = false, reason = "reward_amount_invalid" }
		end
	end

	return { valid = true }
end

function CodeUtils.evaluateCondition(condition: Condition?, context: ConditionContext): (boolean, string?)
	if not condition then
		return true, nil
	end

	if CodeUtils.isExpired(condition.expiresAt, context.now) then
		return false, "expired"
	end

	if condition.groupId and context.isInGroup ~= true then
		return false, "group_required"
	end

	if condition.minAccountAgeDays and context.accountAgeDays < condition.minAccountAgeDays then
		return false, "account_too_new"
	end

	return true, nil
end

function CodeUtils.summarizeRewards(rewards: { Reward }): string
	local parts = {}
	for _, reward in rewards do
		local label = reward.subKey:sub(1, 1):upper() .. reward.subKey:sub(2)
		table.insert(parts, `+{reward.amount} {label}`)
	end
	return table.concat(parts, ", ")
end

return CodeUtils