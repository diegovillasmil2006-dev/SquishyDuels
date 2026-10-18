--!strict
-- Format (shared, mostly client UI). Number and time display helpers.
-- coins(n) (DESIGN §2.2, §9.13, §11.6; spec 2026-10-12 §12): below 100,000 -> digit grouping ("12,345"); below
-- 1,000,000 -> one decimal K ("123.4K"); below 1,000,000,000 -> two decimals M ("1.23M", "999.99M"); from there 3
-- significant digits with B (1e9), T (1e12) or Qa (1e15): "1.23B", "12.3B", "123B", "45.6T", "2.85Qa"; from 1,000Qa
-- the whole Qa, grouped ("1,234Qa"). Decimals are cut, never rounded, so the text never shows more Coins than the true
-- value (999,999 -> "999.9K", not "1.00M"; 999,999,999 -> "999.99M", not "1.00B"). Integer math only.
-- The K/M/B/T/Qa suffixes and the comma are number notation fixed by DESIGN §2.2 and the spec, not translatable text.
-- clock(s): elapsed time "m:ss" (minutes are not capped). For remaining time use TimeUtil.formatCountdown.
-- Pens3 phase 13 (the throw): power(x), a float that grows far past the Coin cap (work/econ4/out5_grip110.txt's
-- style: "4.7", "12", "1.4K", "25K", "330M", "1.6Oc", "24No"): under 10 one decimal (none on a whole number), under
-- 1,000 whole, then the units of POWER_UNITS (K .. Ud) with one decimal under 10 of the unit and whole above, the whole
-- Ud grouped past 1,000Ud; cut like coins (a float a hair under a whole number of its unit, 2.4e31 / 1e30 =
-- 23.999..., still shows the whole number: CUT_SLACK). distance(studs): whole studs, cut and grouped ("8,500"); the
-- word "studs" is Strings' (highway.studs).

-- Constants

local GROUPED_BELOW = 100000
local THOUSANDS_BELOW = 1000000
local MILLIONS_BELOW = 1000000000
local THOUSANDS_SUFFIX = "K"
local MILLIONS_SUFFIX = "M"
-- From 1B: each unit with its suffix, smallest first (spec 2026-10-12 §12).
local BIG_UNITS: { { unit: number, suffix: string } } = {
	{ unit = 1e9, suffix = "B" },
	{ unit = 1e12, suffix = "T" },
	{ unit = 1e15, suffix = "Qa" },
}
local GROUP_SEPARATOR = ","
-- Pens3 phase 13: the power units, smallest first (G110; the short scale's names, as Coins' B / T / Qa).
local POWER_UNITS: { { unit: number, suffix: string } } = {
	{ unit = 1e3, suffix = "K" },
	{ unit = 1e6, suffix = "M" },
	{ unit = 1e9, suffix = "B" },
	{ unit = 1e12, suffix = "T" },
	{ unit = 1e15, suffix = "Qa" },
	{ unit = 1e18, suffix = "Qi" },
	{ unit = 1e21, suffix = "Sx" },
	{ unit = 1e24, suffix = "Sp" },
	{ unit = 1e27, suffix = "Oc" },
	{ unit = 1e30, suffix = "No" },
	{ unit = 1e33, suffix = "Dc" },
	{ unit = 1e36, suffix = "Ud" },
}
local CUT_SLACK = 1e-9 -- relative: a float this close under a cut step counts as on it (never a whole unit more)
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

-- A whole number >= 1e9 with 3 significant digits of its unit, cut: "1.23B", "12.3B", "123B"; the whole Qa, grouped,
-- from 1,000Qa.
local function bigText(whole: number): string
	local unit, suffix = BIG_UNITS[1].unit, BIG_UNITS[1].suffix
	for _, big in BIG_UNITS do
		if whole >= big.unit then
			unit, suffix = big.unit, big.suffix
		end
	end
	local hundredths = whole // (unit // 100) -- hundredths of the unit, cut
	if hundredths >= 100000 then
		return groupDigits(whole // unit) .. suffix -- 1,000 units or more: only after the last suffix (Qa)
	elseif hundredths >= 10000 then
		return string.format("%d%s", hundredths // 100, suffix)
	elseif hundredths >= 1000 then
		local tenths = hundredths // 10
		return string.format("%d.%d%s", tenths // 10, tenths % 10, suffix)
	end
	return string.format("%d.%02d%s", hundredths // 100, hundredths % 100, suffix)
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
	elseif whole < MILLIONS_BELOW then
		local hundredths = whole // 10000
		return string.format("%s%d.%02d%s", sign, hundredths // 100, hundredths % 100, MILLIONS_SUFFIX)
	end
	return sign .. bigText(whole)
end

-- Pens3 phase 13: a power (see the header). 0 or below and non-finite -> "0".
function Format.power(x: number): string
	if not isFinite(x) or x <= 0 then
		return "0"
	end
	local value, suffix = x, ""
	for _, big in POWER_UNITS do
		if x * (1 + CUT_SLACK) >= big.unit then
			value, suffix = x / big.unit, big.suffix
		end
	end
	value *= 1 + CUT_SLACK
	if value >= 1000 then
		return groupDigits(math.floor(value)) .. suffix -- past the last unit (Ud)
	elseif value >= 10 then
		return string.format("%d%s", math.floor(value), suffix)
	end
	local tenths = math.floor(value * 10)
	if suffix == "" and tenths % 10 == 0 then
		return string.format("%d", tenths // 10)
	end
	return string.format("%d.%d%s", tenths // 10, tenths % 10, suffix)
end

-- Pens3 phase 13: whole studs, cut and grouped ("8,500"). Below 0 and non-finite -> "0".
function Format.distance(studs: number): string
	if not isFinite(studs) or studs <= 0 then
		return "0"
	end
	return groupDigits(math.floor(studs))
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
