--!strict
-- SqueezeRhythm (client only, pure). DESIGN §18.5.1 A2: the ASMR cadence of the local player's own squeezes, held or
-- clicked. Never affects sending (SqueezeController's sendDue / holdStopReason ignore it); other players' squeezes
-- have no rhythm.
--
-- * Streak: own squeezes at most rhythm.streakSeconds (2.1 s, its own value: it no longer depends on
--   Config.Squeeze.cycleSeconds, the paid-squeeze cap since Batch 1 #2) apart continue it, so fast clicking
--   keeps one streak; a longer gap starts a new streak at 1. Any rejection other than squeeze.tooFast resets it
--   (tooFast is the cap saying "not yet", not a stop).
-- * Pitch: sfx.squish and sfx.squeezeRelease follow rhythm.pitchPattern {1.00, 1.03, 1.06, 1.03}, repeating from the
--   streak's first squeeze; the random variance is cut to ±rhythm.pitchVariance (1%) once the streak is >= 2 (the
--   first squeeze keeps the key's own variance: nil).
-- * Pops: the release pop is rhythm.popSparkles (2) sparkles; every rhythm.popEvery-th (8th) squeeze of a streak is a
--   big pop instead (rhythm.bigPopSparkles = 4 sparkles plus sfx.pop): the big pop REPLACES the release pop, so a
--   squeeze never emits more than max(popSparkles, bigPopSparkles) sparkles (§18.9).
-- No instances, connections or clock reads: the caller passes `now` (os.clock()).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

-- Types

-- The streak so far (new() gives an empty one).
export type State = {
	streak: number, -- squeezes in the current streak (0 = none yet)
	lastAt: number?, -- os.clock() of the last own squeeze
}

-- What one own squeeze plays.
export type Beat = {
	streak: number, -- its place in the streak (1 = the first)
	pitch: number, -- pitchPattern value (a multiplier on the random pitch)
	variance: number?, -- nil = the key's own pitch variance; rhythm.pitchVariance once the streak is >= 2
	bigPop: boolean, -- every popEvery-th squeeze: bigPopSparkles + sfx.pop instead of the release pop
	sparkles: number, -- sparkles at the start of foam recovery
}

export type Rhythm = typeof(Config.Anim.squeeze.rhythm)

-- Constants

local RHYTHM: Rhythm = Config.Anim.squeeze.rhythm
local REASON_TOO_FAST = "squeeze.tooFast"
local GAP_EPSILON = 1e-9 -- a gap of exactly streakSeconds still continues the streak

-- Module table

local SqueezeRhythm = {}

-- Public

-- An empty streak.
function SqueezeRhythm.new(): State
	return { streak = 0, lastAt = nil }
end

-- True when two own squeezes `gap` seconds apart belong to one streak (gap <= rhythm.streakSeconds).
function SqueezeRhythm.continues(gap: number, rhythm: Rhythm?): boolean
	local r = rhythm or RHYTHM
	return gap >= 0 and gap <= r.streakSeconds + GAP_EPSILON
end

-- The pattern pitch of the `streak`-th squeeze (1-based, repeating).
function SqueezeRhythm.pitchAt(streak: number, rhythm: Rhythm?): number
	local pattern = (rhythm or RHYTHM).pitchPattern
	if #pattern == 0 then
		return 1
	end
	local index = (math.max(1, math.floor(streak)) - 1) % #pattern + 1
	return pattern[index]
end

-- Counts one own squeeze at `now` and returns what it plays. Mutates `state`.
function SqueezeRhythm.beat(state: State, now: number, rhythm: Rhythm?): Beat
	local r = rhythm or RHYTHM
	local last = state.lastAt
	if last ~= nil and state.streak > 0 and SqueezeRhythm.continues(now - last, r) then
		state.streak += 1
	else
		state.streak = 1
	end
	state.lastAt = now
	local streak = state.streak
	local bigPop = r.popEvery > 0 and streak % r.popEvery == 0
	return {
		streak = streak,
		pitch = SqueezeRhythm.pitchAt(streak, r),
		variance = if streak >= 2 then r.pitchVariance else nil,
		bigPop = bigPop,
		sparkles = if bigPop then r.bigPopSparkles else r.popSparkles,
	}
end

-- A SqueezeResult rejection: any reason but squeeze.tooFast resets the streak. Returns true when it reset.
function SqueezeRhythm.reject(state: State, reason: string?): boolean
	if reason == REASON_TOO_FAST then
		return false
	end
	SqueezeRhythm.reset(state)
	return true
end

-- Ends the streak (the next squeeze starts at 1).
function SqueezeRhythm.reset(state: State)
	state.streak = 0
	state.lastAt = nil
end

return SqueezeRhythm
