--!strict
-- Validate (shared; used by server remote handlers on unknown client input, DESIGN §2.7, §2.8).
-- Every narrowing helper takes `unknown` and returns the typed value, or nil when the input is invalid.
-- Numbers are valid only when finite: `x == x` and `|x| < Config.Net.maxAbsNumber` (1e6). Server timestamps
-- (`clientTime` = workspace:GetServerTimeNow(), Unix seconds) use `serverTime`, bounded by Config.Net.maxAbsServerTime.
-- Coin amounts (a price the client only repeats, ShopBuy's expectedPrice) use `coins`: a whole number in
-- [0, Config.Economy.maxCoins], since prices reach the trillions (spec 2026-10-12 §6).
-- Game-state checks (ownership, catalog membership, phases) are not done here.
-- Bounds come from Config (the single source); Config never requires Util modules, so there is no cycle.

-- Requires

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

-- Types

-- A validated SetSettings payload: only keys that were sent, volumes already clamped.
export type SettingsPatch = Types.SettingsPatch

-- Constants

local MAX_ABS = Config.Net.maxAbsNumber
local MAX_ABS_SERVER_TIME = Config.Net.maxAbsServerTime

local SIMPLE_ID_MAX_LENGTH = 24 -- squishyId, boxId, bundleKey, passKey
local SIMPLE_ID_PATTERN = "^[a-z_]+$"

local REQUEST_ID_LENGTH = 36
local REQUEST_ID_PATTERN = "^(%x+)%-(%x+)%-(%x+)%-(%x+)%-(%x+)$"
local REQUEST_ID_GROUPS = { 8, 4, 4, 4, 12 }

-- AckReveal also accepts the free Treat Box key "daily:<dayIndex>". DESIGN gives no length limit for it;
-- the GUID length (36) is used so the accepted length is the same for both forms.
local DAILY_REVEAL_PATTERN = "^daily:%d+$"
local DAILY_REVEAL_MAX_LENGTH = 36

local QUEST_ID_MAX_LENGTH = 24
local QUEST_DAILY_PATTERN = "^q%d+_%d$"
local QUEST_STARTER_PATTERN = "^starter_[a-z]+$"

local STATION_ID_LENGTH = 10
local STATION_ID_PATTERN = "^squeeze_%d%d$"

local SETTINGS_MAX_KEYS = 4
local SETTINGS_VOLUME_MIN = Config.Data.settingsMin
local SETTINGS_VOLUME_MAX = Config.Data.settingsMax
local SETTINGS_VOLUME_KEYS = { music = true, sfx = true }
local SETTINGS_TOGGLE_KEYS = { cameraShake = true, showTips = true }

-- Module table

local Validate = {}

-- Public: numbers and vectors

function Validate.isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < MAX_ABS
end

-- Finite number, optionally inside [min, max].
function Validate.number(value: unknown, min: number?, max: number?): number?
	if not Validate.isFiniteNumber(value) then
		return nil
	end
	local n = value :: number
	if (min and n < min) or (max and n > max) then
		return nil
	end
	return n
end

-- A workspace:GetServerTimeNow() timestamp (ThrowRequest/UltimateRequest `clientTime`, §5.6): a finite number with
-- `|x| < Config.Net.maxAbsServerTime`. Only shape is checked; how far it may be from `now` is ThrowRules' job (§5.6 #7).
function Validate.serverTime(value: unknown): number?
	if type(value) ~= "number" then
		return nil
	end
	local t = value :: number
	if t ~= t or math.abs(t) >= MAX_ABS_SERVER_TIME then
		return nil
	end
	return t
end

-- Finite whole number, optionally inside [min, max].
function Validate.integer(value: unknown, min: number?, max: number?): number?
	local n = Validate.number(value, min, max)
	if n == nil or math.floor(n) ~= n then
		return nil
	end
	return n
end

-- A Coin amount: a whole number in [0, Config.Economy.maxCoins] (not bounded by maxAbsNumber).
function Validate.coins(value: unknown): number?
	if type(value) ~= "number" then
		return nil
	end
	local n = value :: number
	if n ~= n or n < 0 or n > Config.Economy.maxCoins or math.floor(n) ~= n then
		return nil
	end
	return n
end

-- Vector3 whose three components are finite.
function Validate.vector3(value: unknown): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local v = value :: Vector3
	if Validate.isFiniteNumber(v.X) and Validate.isFiniteNumber(v.Y) and Validate.isFiniteNumber(v.Z) then
		return v
	end
	return nil
end

-- Finite Vector3 with `|1 - magnitude| <= tolerance`; returns it normalized.
-- The tolerance is a Config value (e.g. throw aim 0.05, DESIGN §5.6), so it is always passed in.
function Validate.unitVector(value: unknown, tolerance: number): Vector3?
	local v = Validate.vector3(value)
	if v == nil then
		return nil
	end
	local magnitude = v.Magnitude
	if magnitude <= 0 or math.abs(magnitude - 1) > tolerance then
		return nil
	end
	return v / magnitude
end

-- Public: strings and ids

-- String of at most maxLength bytes that matches pattern (when given; patterns should be anchored).
function Validate.string(value: unknown, maxLength: number, pattern: string?): string?
	if type(value) ~= "string" then
		return nil
	end
	local s = value :: string
	if #s > maxLength or (pattern and string.match(s, pattern) == nil) then
		return nil
	end
	return s
end

-- `^[a-z_]+$`, at most 24 characters. Shared by squishyId, boxId, bundleKey and passKey.
local function simpleId(value: unknown): string?
	return Validate.string(value, SIMPLE_ID_MAX_LENGTH, SIMPLE_ID_PATTERN)
end

Validate.squishyId = simpleId
Validate.boxId = simpleId
Validate.bundleKey = simpleId
Validate.passKey = simpleId

-- GUID from HttpService:GenerateGUID(false): 36 characters, hex groups 8-4-4-4-12.
function Validate.requestId(value: unknown): string?
	if type(value) ~= "string" or #value ~= REQUEST_ID_LENGTH then
		return nil
	end
	local s = value :: string
	local groups = { string.match(s, REQUEST_ID_PATTERN) }
	if #groups ~= #REQUEST_ID_GROUPS then
		return nil
	end
	for i, expected in REQUEST_ID_GROUPS do
		if #groups[i] ~= expected then
			return nil
		end
	end
	return s
end

-- AckReveal key: a requestId GUID or "daily:<dayIndex>".
function Validate.ackRevealId(value: unknown): string?
	return Validate.requestId(value) or Validate.string(value, DAILY_REVEAL_MAX_LENGTH, DAILY_REVEAL_PATTERN)
end

-- "q<dayIndex>_<slot>" or "starter_<name>", at most 24 characters.
function Validate.questId(value: unknown): string?
	return Validate.string(value, QUEST_ID_MAX_LENGTH, QUEST_DAILY_PATTERN)
		or Validate.string(value, QUEST_ID_MAX_LENGTH, QUEST_STARTER_PATTERN)
end

-- "squeeze_<two digits>".
function Validate.stationId(value: unknown): string?
	return Validate.string(value, STATION_ID_LENGTH, STATION_ID_PATTERN)
end

-- One of the allowed strings (e.g. OnboardingStep ids {"welcome", "inspect"}).
function Validate.oneOf(value: unknown, allowed: { string }): string?
	if type(value) ~= "string" then
		return nil
	end
	local s = value :: string
	if table.find(allowed, s) == nil then
		return nil
	end
	return s
end

-- Public: payload shapes

-- SetSettings payload (DESIGN §2.8): a table with at most 4 keys from {music, sfx, cameraShake, showTips};
-- music and sfx are whole numbers (then clamped to 0-100), cameraShake and showTips are booleans.
-- Any other key or value type rejects the whole payload. An empty table is valid (nothing to change).
function Validate.settings(value: unknown): SettingsPatch?
	if type(value) ~= "table" then
		return nil
	end
	local patch: SettingsPatch = {}
	local count = 0
	for key, item in value :: { [unknown]: unknown } do
		count += 1
		if count > SETTINGS_MAX_KEYS or type(key) ~= "string" then
			return nil
		end
		if SETTINGS_VOLUME_KEYS[key] then
			local volume = Validate.integer(item)
			if volume == nil then
				return nil
			end
			local clamped = math.clamp(volume, SETTINGS_VOLUME_MIN, SETTINGS_VOLUME_MAX)
			if key == "music" then
				patch.music = clamped
			else
				patch.sfx = clamped
			end
		elseif SETTINGS_TOGGLE_KEYS[key] then
			if type(item) ~= "boolean" then
				return nil
			end
			if key == "cameraShake" then
				patch.cameraShake = item
			else
				patch.showTips = item
			end
		else
			return nil
		end
	end
	return patch
end

return Validate
