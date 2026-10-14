--!strict
-- Config.Squeeze: squeeze stations, server bucket and flood guard (DESIGN §6.3). Shared, data only. All [P].
-- Coins per squeeze: the squeeze value (CapsuleMath.squeezeValue); the earnings limit is Config.Economy.SqueezeLimit;
-- squeeze animation timings are Config.Anim.squeeze; the pads (only the Foam Mats' row since build plan Phase 6), Grip
-- and hold-to-squeeze (its repeat rhythm, Grip.Hold.repeatSeconds) are in Config.Grip.
-- The server model is Logic/SqueezeRules: a squeeze works anywhere in the lobby (spec 2026-10-11 §5); the pad that
-- sets its tier is the one under the HumanoidRootPart (WorldLayout.stationUnder with padMargin / heightAbove below).
-- Batch 1 #2 (replaces "every click pays", 2026-10-06): squeezes pay up to the hold-to-squeeze rhythm and no faster.
-- The bucket below is the paid-squeeze cap: 2 at once, then 1 every cycleSeconds (= Grip.Hold.repeatSeconds, 0.45 s),
-- so over any t seconds at most 2 + t / 0.45 squeezes pay (8,000 an hour, G3), whether held, clicked or sent by a
-- macro. A request over it is squeeze.tooFast: no Coins, no Grip, no capsule push, and the client shows nothing for
-- it. The client sends at most bucketCapacity requests inside bucketCapacity × cycleSeconds; a click over that still
-- squishes on screen but is not sent. Config.validate: bucketCapacity >= 1, floodPerSecond >= the cap (capacity and
-- 1 / cycleSeconds), Config.Net.Remotes.SqueezeRequest.rate = floodPerSecond (its burst holds 5 s of the cap),
-- floodLogDrops >= that burst - floodPerSecond, Grip.Hold.repeatSeconds >= the release pop end of every rarity
-- (Config.Anim.squeeze) and = cycleSeconds, padMargin in [0, 2] and heightAbove in (0, 8].

local Squeeze = {
	-- Other players' mat pulse only (SqueezeController): a root within stationRadius + radiusTolerance studs of a mat
	-- centre is on that mat. The squeeze itself needs no mat (spec 2026-10-11 §5).
	stationRadius = 8,
	radiusTolerance = 2,
	-- "Standing on a pad" (server SqueezeRules.padUnder sets a squeeze's tier; the client pulses the mat under the
	-- player with the same test). Build plan Phase 6: moved here from Config.Grip.Afk when slow training went.
	padMargin = 1, -- studs beyond a pad's footprint that still count as "on it"
	heightAbove = 6, -- root part height window above the pad top
	bucketCapacity = 2, -- paid-squeeze token bucket (os.clock()): 2 at once (absorbs network jitter on a hold) ...
	cycleSeconds = 0.45, -- ... refilled 1 per cycle = Grip.Hold.repeatSeconds; over it: squeeze.tooFast, nothing paid
	floodPerSecond = 20, -- requests above this are dropped silently (= Config.Net.Remotes.SqueezeRequest.rate)
	-- More than this many drops ... (40: a network stall delivers queued presses at once; the SqueezeRequest remote's
	-- whole burst of 60 drops 40 here and is not logged as abuse.)
	floodLogDrops = 40,
	floodLogWindowSeconds = 10, -- ... inside this window is logged once
	othersCullStuds = 60, -- clients ignore other players' SD_SqueezeAt beyond this distance
}

return Squeeze
