--!strict
-- Format (shared, mostly client UI). Number and time display helpers.
-- coins(n) (DESIGN §2.2, §9.13, §11.6): below 100,000 -> digit grouping ("12,345"); below 1,000,000 ->
-- one decimal K ("123.4K"); otherwise two decimals M ("1.23M", "1,000.00M"). Decimals are cut, never
-- rounded, so the text never shows more Coins than the true value (999,999 -> "999.9K", not "1.00M").
-- The K/M suffixes and the comma are number notation fixed by DESIGN §2.2, not translatable text.
-- clock(s): elapsed time "m:ss" (minutes are not capped). For remaining time use TimeUtil.formatCountdown.

-- Constants

local GROUPED_BELOW = 100000
local THOUSANDS_BELOW = 1000000
local THOUSANDS_SUFFIX = "K"
local MILLIONS_SUFFIX = "M"
local GROUP_SEPARATOR = ","
local SECONDS_PER_MINUTE = 60

-- Module table

local Format = {}

-- Private

local function isFinite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

-- Digit grouping for a whole number >= 0: 1234567 -> "1,234,567".
local function groupDigits(whole: number): string
	local digits = string.format("%d", whole)
	local head = #digits % 3
	if head == 0 then
		head = 3
	end
	local parts = { string.sub(digits, 1, head) }
	for i = head + 1, #digits, 3 do
		table.insert(parts, string.sub(digits, i, i + 2))
	end
	return table.concat(parts, GROUP_SEPARATOR)
end

-- Public

-- Coin amount text. Fractions are dropped (toward zero); negative values get a "-"; non-finite -> "0".
function Format.coins(n: number): string
	if not isFinite(n) then
		return "0"
	end
	local whole = math.floor(math.abs(n))
	local sign = if n < 0 and whole > 0 then "-" else ""
	if whole < GROUPED_BELOW then
		return sign .. groupDigits(whole)
	elseif whole < THOUSANDS_BELOW then
		local tenths = whole // 100
		return string.format("%s%d.%d%s", sign, tenths // 10, tenths % 10, THOUSANDS_SUFFIX)
	end
	local hundredths = whole // 10000
	return string.format("%s%s.%02d%s", sign, groupDigits(hundredths // 100), hundredths % 100, MILLIONS_SUFFIX)
end

-- Elapsed seconds as "m:ss" ("0:23", "12:05", "75:00"). Fractions are dropped; negative or non-finite -> "0:00".
function Format.clock(seconds: number): string
	local total = 0
	if isFinite(seconds) and seconds > 0 then
		total = math.floor(seconds)
	end
	return string.format("%d:%02d", total // SECONDS_PER_MINUTE, total % SECONDS_PER_MINUTE)
end

return Format
