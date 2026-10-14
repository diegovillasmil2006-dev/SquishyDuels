--!strict
-- Config.Squeeze: squeeze stations, server bucket and flood guard (DESIGN §6.3). Shared, data only. All [P].
-- Coins per squeeze: the squeeze value (CapsuleMath.squeezeValue); the earnings limit is Config.Economy.SqueezeLimit;
-- squeeze animation timings are Config.Anim.squeeze; the pads (only the Foam Mats' row since build plan Phase 6), Grip
-- and hold-to-squeeze (its repeat rhythm, Grip.Hold.repeatSeconds) are in Config.Grip.
-- The server model is Logic/SqueezeRules: a squeeze works anywhere in the lobby (spec 2026-10-11 §5); the pad that
-- sets its tier is the one under the HumanoidRootPart (WorldLayout.stationUnder with padMargin / heightAbove below).
-- Every click pays (user decision, 2026-10-06): there is no squeeze timer. The bucket below is only a hidden
-- anti-autoclicker cap that a human never meets: 12 at once and 12 per second on average (after a rest a macro can get
-- up to 20 in one second, the flood guard's limit; over any t seconds at most 12 + 12 × t). The client stays under it
-- (at most 12 sends in any second) and shows nothing for squeeze.tooFast. Config.validate: bucketCapacity >= 1,
-- floodPerSecond >= the cap (capacity and 1 / cycleSeconds), Config.Net.Remotes.SqueezeRequest.rate = floodPerSecond
-- (its burst holds 5 s of the cap), floodLogDrops >= that burst - floodPerSecond, Grip.Hold.repeatSeconds >= the
-- release pop end of every rarity (Config.Anim.squeeze), padMargin in [0, 2] and heightAbove in (0, 8].

local Squeeze = {
	-- Other players' mat pulse only (SqueezeController): a root within stationRadius + radiusTolerance studs of a mat
	-- centre is on that mat. The squeeze itself needs no mat (spec 2026-10-11 §5).
	stationRadius = 8,
	radiusTolerance = 2,
	-- "Standing on a pad" (server SqueezeRules.padUnder sets a squeeze's tier; the client pulses the mat under the
	-- player with the same test). Build plan Phase 6: moved here from Config.Grip.Afk when slow training went.
	padMargin = 1, -- studs beyond a pad's footprint that still count as "on it"
	heightAbove = 6, -- root part height window above the pad top
	bucketCapacity = 12, -- anti-autoclicker token bucket (os.clock()): at most 12 paid squeezes at once ...
	cycleSeconds = 1 / 12, -- ... refilled 1 per cycle (12 a second on average); over it: squeeze.tooFast, no Coins/Grip
	floodPerSecond = 20, -- requests above this are dropped silently (= Config.Net.Remotes.SqueezeRequest.rate)
	-- More than this many drops ... (40: a network stall delivers an honest clicker's queued presses at once; 5 s of
	-- them, the SqueezeRequest remote burst of 60, drop 40 here and are not logged as abuse.)
	floodLogDrops = 40,
	floodLogWindowSeconds = 10, -- ... inside this window is logged once
	othersCullStuds = 60, -- clients ignore other players' SD_SqueezeAt beyond this distance
}

return Squeeze
