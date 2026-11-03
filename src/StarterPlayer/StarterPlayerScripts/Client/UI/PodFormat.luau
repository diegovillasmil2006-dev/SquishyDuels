--!strict
-- PodFormat (client only, pure). Squish Pods HUD (owner 2026-11-01 "implement the in game hud exactly as shown in the
-- claude design", "Yes, start part 2" 2026-11-03; `H:n` = Downloads "Squishy Duels In-Game HUD.dc.html" line n): the
-- pod dial's numbers, unit-tested in Edit mode. The views are UI/PodDial (the dial, in AbilityBarController) and
-- UI/Match/PodHud (the toast and the screen edge).
--   rollSchedule(totalMs)           the spin's icon changes, ms after the grab, slowing down (H:130)
--   remember(memory, rolling, alive, now)  the dial's memory of the last grab ({power, landsAt}, server time): a new
--                                   roll replaces it; a roll still spinning goes with a K.O.; a landing view that comes
--                                   a hair early lands now
--   state(memory, buffs, now, powerUps)  "rolling" until landsAt (since = seconds since the grab), "landed" for
--                                   LAND_HOLD (fraction 1), "active" while a timed power-up lasts (left, fraction of its
--                                   seconds; read from buffs, so a late HUD still drains), else "idle"
--   tagText(state)                  "POD", or the whole seconds left while active (H:183)
--   chipText(power, powerUps)       "Shield!" / "+50% Ult!" (H:184)
--   look(kind)                      {color, top, bottom, icon} (H:53-59; img.pod.<kind>)
--   edgeColor(kind)                 the screen edge of Shield, Speed and Super Jump (H:188)
--   glowButton(kind)                "dash" (Dash Boost rings E, H:195) or "throw" (Throw / Rapid: H rings Q; the owner
--                                   2026-11-01: Q is Catch here, so the touch Throw button glows and PC shows none)
--   keyed(frames, u, ease)          a CSS keyframe value at u (0..1) of {{at, value}}, each segment eased (CSS runs
--                                   the timing function per segment)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

-- Types

export type Roll = { power: string, landsAt: number }
export type Memory = { power: string?, landsAt: number? }
export type Phase = "idle" | "rolling" | "landed" | "active"
export type State = { phase: Phase, power: string?, since: number?, left: number?, fraction: number? }
export type Look = { color: Color3, top: Color3, bottom: Color3, icon: string }

-- Constants

local LAND_HOLD = 0.7 -- H:160 landed, then the timer
local TEXT = Strings.match.pod
-- Palette names of each kind (Pod<Name>, Pod<Name>Top, Pod<Name>End)
local NAMES: { [string]: string } = {
	shield = "Shield",
	speed = "Speed",
	throwBoost = "ThrowBoost",
	ultCharge = "UltCharge",
	dashBoost = "DashBoost",
	rapidThrow = "RapidThrow",
	superJump = "SuperJump",
}
local EDGE: { [string]: boolean } = { shield = true, speed = true, superJump = true } -- H:188
local GLOW: { [string]: string } = { dashBoost = "dash", throwBoost = "throw", rapidThrow = "throw" }

-- Module table

local PodFormat = {}
PodFormat.LAND_HOLD = LAND_HOLD

-- Private

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Public

function PodFormat.rollSchedule(totalMs: number): { number }
	local out: { number } = {}
	local t = 0
	while t < totalMs do
		local p = t / totalMs
		t += 42 + p * p * 150
		if t < totalMs - 30 then
			table.insert(out, t)
		end
	end
	return out
end

function PodFormat.remember(memory: Memory, rolling: Roll?, alive: boolean, now: number): Memory
	if rolling then
		if memory.power == rolling.power and memory.landsAt == rolling.landsAt then
			return memory
		end
		return { power = rolling.power, landsAt = rolling.landsAt }
	end
	local landsAt = memory.landsAt
	if landsAt and now < landsAt then
		if not alive then
			return {} -- lost with the K.O.
		end
		return { power = memory.power, landsAt = now }
	end
	return memory
end

function PodFormat.state(memory: Memory, buffs: { [string]: number }, now: number, powerUps: any): State
	local power, landsAt = memory.power, memory.landsAt
	if power and landsAt then
		if now < landsAt then
			return { phase = "rolling", power = power, since = now - (landsAt - (powerUps.rollSeconds or 0)) }
		elseif now < landsAt + LAND_HOLD then
			return { phase = "landed", power = power, since = now - landsAt, fraction = 1 }
		end
	end
	for _, kind in powerUps.order do
		local untilAt = buffs[kind]
		local seconds = powerUps.kinds[kind] and powerUps.kinds[kind].seconds
		if finite(untilAt) and untilAt > now and finite(seconds) and seconds > 0 then
			local left = untilAt - now
			return { phase = "active", power = kind, left = left, fraction = math.clamp(left / seconds, 0, 1) }
		end
	end
	return { phase = "idle" }
end

function PodFormat.tagText(state: State): string
	if state.phase == "active" and state.left then
		return Strings.format(TEXT.seconds, { seconds = math.ceil(state.left) })
	end
	return TEXT.tag
end

function PodFormat.chipText(power: string, powerUps: any): string
	local kind = powerUps.kinds[power]
	if kind and kind.ultFraction then
		return Strings.format(TEXT.chipUlt, { pct = math.round(kind.ultFraction * 100) })
	end
	return Strings.format(TEXT.chip, { name = TEXT.name[power] or power })
end

function PodFormat.look(kind: string): Look?
	local name = NAMES[kind]
	if name == nil then
		return nil
	end
	local p = Palette :: any
	return { color = p["Pod" .. name], top = p["Pod" .. name .. "Top"], bottom = p["Pod" .. name .. "End"], icon = "img.pod." .. kind }
end

function PodFormat.edgeColor(kind: string): Color3?
	local look = PodFormat.look(kind)
	return if EDGE[kind] and look then look.bottom else nil
end

function PodFormat.glowButton(kind: string): string?
	return GLOW[kind]
end

function PodFormat.keyed(frames: { { number } }, u: number, ease: (number) -> number): number
	if u <= frames[1][1] then
		return frames[1][2]
	end
	for i = 2, #frames do
		local a, b = frames[i - 1], frames[i]
		if u <= b[1] then
			return a[2] + (b[2] - a[2]) * ease((u - a[1]) / (b[1] - a[1]))
		end
	end
	return frames[#frames][2]
end

return PodFormat
