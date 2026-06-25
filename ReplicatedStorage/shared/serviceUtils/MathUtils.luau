

local MathUtils = {}

export type WeightedOption = {
	item: any,
	weight: number,
}

local SUFFIXES = {
	"K", "M", "B", "T",
	"Qa", "Qi", "Sx", "Sp", "Oc", "No",
	"Dc",
	"UDc", "DDc", "TDc", "QaDc", "QiDc", "SxDc", "SpDc", "OcDc", "NoDc",
	"Vg",
	"UVg", "DVg", "TVg", "QaVg", "QiVg", "SxVg", "SpVg", "OcVg", "NoVg",
	"Tg",
	"UTg", "DTg", "TTg", "QaTg", "QiTg", "SxTg", "SpTg", "OcTg", "NoTg",
	"Qag",
	"UQag", "DQag", "TQag", "QaQag", "QiQag", "SxQag", "SpQag", "OcQag", "NoQag",
	"Qig",
	"UQig", "DQig", "TQig", "QaQig", "QiQig", "SxQig", "SpQig", "OcQig", "NoQig",
	"Sxg",
	"USxg", "DSxg", "TSxg", "QaSxg", "QiSxg", "SxSxg", "SpSxg", "OcSxg", "NoSxg",
	"Spg",
	"USpg", "DSpg", "TSpg", "QaSpg", "QiSpg", "SxSpg", "SpSpg", "OcSpg", "NoSpg",
	"Ocg",
	"UOcg", "DOcg", "TOcg", "QaOcg", "QiOcg", "SxOcg", "SpOcg", "OcOcg", "NoOcg",
	"Nog",
	"UNog", "DNog", "TNog", "QaNog", "QiNog", "SxNog", "SpNog", "OcNog", "NoNog",
	"Cg",
}

local function _getScale(n: number): (number, number)
	local abs = math.abs(n)
	if abs < 1000 then
		return 0, n
	end
	local index = 0
	local value = abs
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	return index, if n < 0 then -value else value
end

function MathUtils.format(n: number): string
	assert(type(n) == "number", "n must be a number")
	if n ~= n then return "NaN" end
	if n == math.huge then return "∞" end
	if n == -math.huge then return "-∞" end

	local index, value = _getScale(n)
	if index == 0 then
		if n == math.floor(n) then
			return tostring(math.floor(n))
		end
		return string.format("%.1f", n)
	end

	local abs = math.abs(value)
	local formatted = if abs >= 100
		then string.format("%d", math.floor(value))
		elseif abs >= 10
		then string.format("%.1f", value)
		else string.format("%.2f", value)

	return formatted .. SUFFIXES[index]
end

function MathUtils.formatComma(n: number): string
	assert(type(n) == "number", "n must be a number")
	local s = tostring(math.floor(math.abs(n)))
	local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end
	return if n < 0 then "-" .. result else result
end

function MathUtils.formatMultiplier(n: number): string
	assert(type(n) == "number", "n must be a number")
	if n >= 1000 then
		return MathUtils.format(n) .. "x"
	end
	local text = string.format("%.2f", n)
	text = text:gsub("%.?0+$", "")
	return text .. "x"
end

function MathUtils.formatTime(seconds: number): string
	assert(type(seconds) == "number" and seconds >= 0, "seconds must be a non-negative number")
	local s = math.floor(seconds)
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then
		return string.format("%dh %dm %ds", h, m, sec)
	elseif m > 0 then
		return string.format("%dm %ds", m, sec)
	else
		return string.format("%ds", sec)
	end
end

function MathUtils.formatPercent(ratio: number, decimals: number?): string
	assert(type(ratio) == "number", "ratio must be a number")
	local d = decimals or 1
	return string.format("%." .. d .. "f%%", ratio * 100)
end

function MathUtils.formatSign(n: number): string
	assert(type(n) == "number", "n must be a number")
	return if n >= 0 then "+" .. MathUtils.format(n) else MathUtils.format(n)
end

function MathUtils.clamp(n: number, min: number, max: number): number
	assert(min <= max, "min must be <= max")
	return math.max(min, math.min(max, n))
end

function MathUtils.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MathUtils.inverseLerp(a: number, b: number, value: number): number
	assert(b ~= a, "a and b must differ")
	return (value - a) / (b - a)
end

function MathUtils.map(n: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	return outMin + (outMax - outMin) * MathUtils.inverseLerp(inMin, inMax, n)
end

function MathUtils.round(n: number, decimals: number?): number
	local factor = 10 ^ (decimals or 0)
	return math.floor(n * factor + 0.5) / factor
end

function MathUtils.floorTo(n: number, decimals: number?): number
	local factor = 10 ^ (decimals or 0)
	return math.floor(n * factor) / factor
end

function MathUtils.ceilTo(n: number, decimals: number?): number
	local factor = 10 ^ (decimals or 0)
	return math.ceil(n * factor) / factor
end

function MathUtils.roundToNearest(n: number, multiple: number): number
	assert(multiple ~= 0, "multiple must not be 0")
	return math.floor(n / multiple + 0.5) * multiple
end

function MathUtils.sign(n: number): number
	if n > 0 then
		return 1
	elseif n < 0 then
		return -1
	end
	return 0
end

function MathUtils.average(t: { number }): number
	assert(#t > 0, "table must not be empty")
	local total = 0
	for _, v in t do
		total += v
	end
	return total / #t
end

function MathUtils.sum(t: { number }): number
	local total = 0
	for _, v in t do
		total += v
	end
	return total
end

function MathUtils.minInTable(t: { number }): number
	assert(#t > 0, "table must not be empty")
	local m = t[1]
	for i = 2, #t do
		if t[i] < m then m = t[i] end
	end
	return m
end

function MathUtils.maxInTable(t: { number }): number
	assert(#t > 0, "table must not be empty")
	local m = t[1]
	for i = 2, #t do
		if t[i] > m then m = t[i] end
	end
	return m
end

function MathUtils.chance(percent: number): boolean
	assert(percent >= 0 and percent <= 100, "percent must be between 0 and 100")
	return math.random() * 100 < percent
end

function MathUtils.randomRange(min: number, max: number): number
	assert(min <= max, "min must be <= max")
	return min + math.random() * (max - min)
end

function MathUtils.randomInt(min: number, max: number): number
	assert(min <= max, "min must be <= max")
	return math.random(min, max)
end

function MathUtils.weightedRandom(options: { WeightedOption }): any
	assert(#options > 0, "options must not be empty")
	local total = 0
	for _, opt in options do
		assert(type(opt.weight) == "number" and opt.weight > 0, "each option must have a positive weight")
		total += opt.weight
	end
	local roll = math.random() * total
	local cumulative = 0
	for _, opt in options do
		cumulative += opt.weight
		if roll <= cumulative then
			return opt.item
		end
	end
	return options[#options].item
end

function MathUtils.percentage(part: number, total: number): number
	assert(total ~= 0, "total must not be 0")
	return part / total
end

function MathUtils.easeIn(t: number, power: number?): number
	return t ^ (power or 2)
end

function MathUtils.easeOut(t: number, power: number?): number
	return 1 - (1 - t) ^ (power or 2)
end

function MathUtils.easeInOut(t: number, power: number?): number
	local p = power or 2
	if t < 0.5 then
		return 0.5 * (2 * t) ^ p
	else
		return 1 - 0.5 * (2 * (1 - t)) ^ p
	end
end

function MathUtils.easeInElastic(t: number): number
	if t == 0 then return 0 end
	if t == 1 then return 1 end
	return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * (2 * math.pi / 3))
end

function MathUtils.easeOutElastic(t: number): number
	if t == 0 then return 0 end
	if t == 1 then return 1 end
	return (2 ^ (-10 * t)) * math.sin((t * 10 - 0.75) * (2 * math.pi / 3)) + 1
end

function MathUtils.easeOutBounce(t: number): number
	local n1 = 7.5625
	local d1 = 2.75
	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elseif t < 2.5 / d1 then
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	else
		t -= 2.625 / d1
		return n1 * t * t + 0.984375
	end
end

function MathUtils.easeInBounce(t: number): number
	return 1 - MathUtils.easeOutBounce(1 - t)
end

function MathUtils.easeInOutBounce(t: number): number
	if t < 0.5 then
		return (1 - MathUtils.easeOutBounce(1 - 2 * t)) / 2
	else
		return (1 + MathUtils.easeOutBounce(2 * t - 1)) / 2
	end
end

function MathUtils.sigmoid(x: number): number
	return 1 / (1 + math.exp(-x))
end

function MathUtils.gcd(a: number, b: number): number
	a = math.abs(math.floor(a))
	b = math.abs(math.floor(b))
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

function MathUtils.lcm(a: number, b: number): number
	return math.abs(a * b) / MathUtils.gcd(a, b)
end

function MathUtils.factorial(n: number): number
	assert(n >= 0 and math.floor(n) == n, "n must be a non-negative integer")
	if n <= 1 then return 1 end
	local result = 1
	for i = 2, n do
		result *= i
	end
	return result
end

function MathUtils.fibonacci(n: number): number
	assert(n >= 0 and math.floor(n) == n, "n must be a non-negative integer")
	if n == 0 then return 0 end
	if n == 1 then return 1 end
	local a, b = 0, 1
	for _ = 2, n do
		a, b = b, a + b
	end
	return b
end

function MathUtils.isPrime(n: number): boolean
	assert(n >= 0 and math.floor(n) == n, "n must be a non-negative integer")
	if n < 2 then return false end
	if n == 2 then return true end
	if n % 2 == 0 then return false end
	local limit = math.floor(math.sqrt(n))
	for i = 3, limit, 2 do
		if n % i == 0 then return false end
	end
	return true
end

return MathUtils
