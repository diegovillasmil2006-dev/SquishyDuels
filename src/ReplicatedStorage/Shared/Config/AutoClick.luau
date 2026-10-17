--!strict
-- Config.Net.AutoClick: the auto-clicker check on squeezes (owner 2026-10-16: no earning limits for normal players;
-- robot-fast clicking is handled step by step). Shared, data only. All [P]. Exposed through Config/Net (Config/init
-- is near Roblox's 200,000-character Source limit), checked by Config/ValidateAutoClick when AutoClickService starts.
-- Auto-clicker check (2026-10-16). The numbers come from a timing study of what the server sees (simulated kids,
-- drummers and auto-clickers through 30 to 240 FPS clients, four network qualities and 60 Hz server frames).
-- Review fixes (2026-10-16, job autoclick): no "too fast" rule any more (speed alone never strikes: a kid mashing
-- F + E + a click, or a worn mouse, sends 17-25 presses a second, and anything over the paid cap pays nothing anyway);
-- the machine-regular rule skips the client ceiling's own rhythm (maxPerSecond); `enforce` sets how far a catch goes.

local AutoClick = {
	enabled = true, -- false = no check and no strikes at all (the off switch if something looks wrong live)

	-- Review fix (2026-10-16): how far a catch goes. "log": only logged ([SD][abuse] ... would warn / kick / ban, with
	-- the numbers); nobody is warned, slowed, kicked or banned and nothing is saved. "warn": every catch is the first
	-- step (one warning, penaltySeconds of squeezes that pay nothing; saved as step 1), never a kick or a ban. "full":
	-- the owner's steps (warn, kick, 1-day ban, then longer bans). Shipped as "log" (watch only) on 2026-10-16; owner
	-- 2026-10-17: "turn on warn -> kick -> ban now" (only robot-steady clicking counts, rule B below).
	enforce = "full",

	-- Client (SqueezeController): a fresh press over the paid-squeeze cap is still sent (it pays nothing,
	-- squeeze.tooFast), at most this many inside any rolling second, so the server sees the real press rhythm. With the
	-- paid cap's own sends (Config.Squeeze.bucketCapacity) on top it stays within Config.Squeeze.floodPerSecond and the
	-- SqueezeRequest bucket (both 20 a second): the client is never dropped or counted as abuse. Anything faster (an
	-- auto-clicker, or a kid mashing several keys) is held at it. No extra press is sent while the check is off.
	clientPressesPerSecond = 18,

	-- A burst at maxPerSecond or faster is the client ceiling's own rhythm, not the presses' (past the ceiling the client
	-- sends at the first press after a slot frees, so a 25-a-second kid and a 1000-a-second macro look alike): rule B
	-- never judges a window whose mean gap is at or under 1 / maxPerSecond. Such a stream earns only the hold rhythm.
	-- People at 16.5-25 a second (one finger, or F + E + a click: the world click counts one finger at a time,
	-- ControlsController worldPointerPresses `touchDown`) were never caught in the study (sim/fast.txt, fast20.txt).
	maxPerSecond = 17,

	-- Rule B, machine-regular: windowIntervals gaps between requests of one burst (a pause over burstGapSeconds starts
	-- the window again) are judged once, then a new window starts. Only a window whose mean gap is at most
	-- maxMeanGapSeconds is judged (4 or more a second: a held squeeze repeats every 0.45 s or slower, so a hold is never
	-- judged). It is cut into blocks of blockIntervals gaps; a block's mean gap hardly moves with frame timing (only its
	-- first and last press count), and a standard deviation of the block means of at most maxBlockSpreadSeconds is a
	-- machine. People drift: in the study (sim/margins.txt, 20 minutes non-stop) the steadiest player (a drummer's
	-- timing, 3% spread, at 16 a second) never went under 0.88 ms and kids (8%+) not under 1.08 ms; auto-clickers sit at
	-- about 0.5 ms on a normal connection. One that adds random timing, or a very bad connection, hides it (it still pays
	-- only the hold rhythm).
	windowIntervals = 400,
	blockIntervals = 20,
	maxMeanGapSeconds = 0.25,
	maxBlockSpreadSeconds = 0.0007,
	burstGapSeconds = 1,

	-- The steps (owner 2026-10-16; with enforce = "full"): the 1st catch = squeezes pay nothing for penaltySeconds,
	-- with one short warning; the 2nd catch within memorySeconds of the last one (the same visit or after a rejoin) =
	-- kicked; the 3rd = banned for banSeconds (Players:BanAsync, only when Players.BanningEnabled is on; else a kick).
	-- Nothing is judged during the penalty (time to switch the auto-clicker off), and every catch needs new proof.
	-- Owner 2026-10-17: a ban is never forgotten (memorySeconds is for the warning and the kick only): after it ends,
	-- the next catch (whenever it comes) is a longer ban, laterBanSeconds in turn (7 days, then 30 days), the last one
	-- again after that. Each is a whole number of days, longer than the one before. [P]
	penaltySeconds = 30,
	memorySeconds = 86400,
	banSeconds = 86400,
	laterBanSeconds = { 604800, 2592000 },
	-- true: the ban does not spread to accounts Roblox thinks belong to the same person (brothers and sisters often
	-- share one tablet).
	banExcludeAltAccounts = true,
}

return AutoClick
