--!strict
-- Timeline (client only). Keyframed values evaluated by time (DESIGN §9.2): Timeline.new(keys) with
-- { t_ms, value, style, dir } and :eval(ms) eased through TweenService:GetValue(alpha, style, dir).
-- Value kinds: number, Vector3, CFrame (and Color3, UDim2 for UI); every key must hold the same kind.
--
-- Semantics:
--   * keys are sorted by t_ms (non-decreasing; equal times make an instant jump to the later key);
--   * a key's style/dir shape the segment that ARRIVES at it (previous key → this key), so a phase table like
--     Config.Anim.squeeze.phases ("0-70 ms to c 1.06, Sine Out") maps to one key per phase end; the first key's
--     style/dir are unused. Defaults: Linear, Out;
--   * before the first key → the first value; at or after the last key → the last value (exactly);
--   * Back/Elastic styles may overshoot: values are extrapolated through Lerp, not clamped.
-- Pure apart from TweenService:GetValue: no instances, connections or clock reads; the caller supplies ms.

-- Services

local TweenService = game:GetService("TweenService")

-- Types

export type Key<T> = {
	t_ms: number,
	value: T,
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?,
}

export type Timeline<T> = {
	eval: (self: Timeline<T>, ms: number) -> T,
	duration: (self: Timeline<T>) -> number,
	isDone: (self: Timeline<T>, ms: number) -> boolean,
}

type InternalKey = {
	t: number,
	value: any,
	style: Enum.EasingStyle,
	dir: Enum.EasingDirection,
}

-- Constants

local DEFAULT_STYLE = Enum.EasingStyle.Linear
local DEFAULT_DIR = Enum.EasingDirection.Out
local LERP_KINDS = { Vector3 = true, CFrame = true, Color3 = true, UDim2 = true }

-- Module table

local TimelineClass = {}
TimelineClass.__index = TimelineClass

local Timeline = {}

-- Private

local function isFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function lerp(kind: string, a: any, b: any, alpha: number): any
	if kind == "number" then
		return a + (b - a) * alpha
	end
	return a:Lerp(b, alpha)
end

-- Public

-- keys: at least one { t_ms, value, style?, dir? }, sorted by t_ms. Errors on bad input (authoring mistake).
function Timeline.new<T>(keys: { Key<T> }): Timeline<T>
	assert(type(keys) == "table" and #keys > 0, "[SD][Timeline] needs at least one key")
	local kind = typeof(keys[1].value)
	assert(kind == "number" or LERP_KINDS[kind], `[SD][Timeline] unsupported value kind {kind}`)
	local list: { InternalKey } = table.create(#keys)
	local previous = -math.huge
	for index, key in keys do
		assert(isFinite(key.t_ms), `[SD][Timeline] key {index}: t_ms must be a finite number`)
		assert(key.t_ms >= previous, `[SD][Timeline] key {index}: keys must be sorted by t_ms`)
		assert(typeof(key.value) == kind, `[SD][Timeline] key {index}: every value must be a {kind}`)
		if kind == "number" then
			assert(isFinite(key.value), `[SD][Timeline] key {index}: value must be a finite number`)
		end
		previous = key.t_ms
		list[index] = {
			t = key.t_ms,
			value = key.value,
			style = key.style or DEFAULT_STYLE,
			dir = key.dir or DEFAULT_DIR,
		}
	end
	local self = { _keys = list, _kind = kind }
	return setmetatable(self, TimelineClass) :: any
end

-- Value at `ms` (milliseconds on the timeline's own clock).
function TimelineClass.eval(self: any, ms: number): any
	local keys: { InternalKey } = self._keys
	local count = #keys
	if ms >= keys[count].t then
		return keys[count].value
	end
	if not (ms >= keys[1].t) then -- before the first key, or NaN
		return keys[1].value
	end
	-- Last key with t <= ms; keys are few (≤ ~10), so a linear scan is enough.
	local index = 1
	while keys[index + 1].t <= ms do
		index += 1
	end
	local from, to = keys[index], keys[index + 1]
	local alpha = TweenService:GetValue((ms - from.t) / (to.t - from.t), to.style, to.dir)
	return lerp(self._kind, from.value, to.value, alpha)
end

-- Time of the last key (ms).
function TimelineClass.duration(self: any): number
	local keys: { InternalKey } = self._keys
	return keys[#keys].t
end

function TimelineClass.isDone(self: any, ms: number): boolean
	return ms >= TimelineClass.duration(self)
end

return Timeline
