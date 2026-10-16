--!strict
-- Config.Match: the rules of Free for All (12 players) and Team Deathmatch (6 vs 6) on Diego's duel maps (jayyyyy's
-- answers 2026-10-15; plan scratch work/tdmffa/PLAN.md). Shared, data only. Read by Server/Logic/MatchRules (the match
-- state machine), Server/Logic/PowerUpRules and Shared/StormMath (also used by the client to draw the storm).
-- Values marked [P] are provisional (not given by the user; tune after the first live tests).
--
-- The rules in plain words:
--   * One hit = knocked out (K.O.) in both modes. Back in after respawnSeconds with spawnProtectSeconds of safety.
--   * FFA: unlimited respawns; the first to koTarget K.O.s wins; at time-up the most K.O.s wins. No storm.
--   * TDM: each team shares teamLives; every K.O. costs that team one life to respawn. At 0 lives nobody on that team
--     respawns: whoever still stands must carry. The last team with a player standing wins; at time-up the team with
--     more lives left wins. The storm (Storm below) closes in from stormStartSeconds.
--   * A tie at time-up goes to overtime: the next K.O. decides it (TDM: the team that scores it wins; FFA: the first
--     time one player alone leads). After overtimeMaxSeconds without a winner it is a draw [P] (a safety net).
--   * Power-up pads give one random power-up (PowerUps.kinds, equal chance; teamLife only in TDM); a pad refills
--     PowerUps.padRefillSeconds after a pickup.

export type Mode = {
	teams: boolean, -- TDM: Red vs Blue; FFA: everyone for themselves
	maxPlayers: number,
	matchSeconds: number, -- Active phase length before time-up
	koTarget: number?, -- FFA: K.O.s that win at once
	teamLives: number?, -- TDM: shared lives per team
	storm: boolean,
}

export type PowerUp = {
	seconds: number?, -- how long it lasts (nil = instant)
	ultFraction: number?, -- ultCharge: share of the full ult meter it adds
	teamsOnly: boolean?, -- only in a mode with teams (TDM)
}

local Match = {
	Modes = {
		ffa = {
			teams = false,
			maxPlayers = 12,
			matchSeconds = 480, -- 8 minutes
			koTarget = 25,
			storm = false,
		} :: Mode,
		tdm = {
			teams = true,
			maxPlayers = 12,
			matchSeconds = 600, -- 10 minutes
			teamLives = 40,
			storm = true,
		} :: Mode,
	},
	teamNames = { "Red", "Blue" }, -- Diego's queue bar: slots 1-6 red, 7-12 blue

	waitSeconds = 20, -- [P] the longest wait for every player to arrive before the countdown
	countdownSeconds = 3, -- [P] the in-arena 3-2-1 (Diego designs it)
	respawnSeconds = 3,
	spawnProtectSeconds = 2,
	overtimeMaxSeconds = 120, -- [P]
	resultSeconds = 8, -- [P] the end screen before players go back
	minPlayers = 2, -- fewer present at the countdown cancels the match

	-- The storm (TDM only), like Fortnite's: a circle around the map's centre that shrinks in steps; outside it a
	-- player's storm bar fills (barFillSeconds of time outside in total = K.O.) and inside it slowly drains.
	-- It starts as the circle around the whole map (StormMath.startRadius) and is shown from stormStartSeconds. Each
	-- step shrinks it to radiusFraction of that start radius over shrinkSeconds, beginning at shrinkAt (seconds of
	-- Active); warnSeconds before each shrink the HUD warns. With these numbers it reaches its smallest circle at 9:20.
	Storm = {
		stormStartSeconds = 300, -- 5:00, half of TDM's 10 minutes
		warnSeconds = 30, -- [P] "Storm is coming in 0:30"
		steps = {
			{ shrinkAt = 300, shrinkSeconds = 60, radiusFraction = 0.6 }, -- [P]
			{ shrinkAt = 400, shrinkSeconds = 60, radiusFraction = 0.3 }, -- [P]
			{ shrinkAt = 500, shrinkSeconds = 60, radiusFraction = 0.1 }, -- [P] a small circle in the middle
		},
		barFillSeconds = 3,
		barDrainSeconds = 9, -- [P] a full bar empties in 9 s back inside ("slowly")
	},

	PowerUps = {
		padRefillSeconds = 20,
		-- Pick order (also the random roll's order). Boosts last 6 s; dash boost 5 s (user).
		order = { "shield", "speed", "throwBoost", "ultCharge", "dashBoost", "rapidThrow", "superJump", "teamLife" },
		kinds = {
			shield = { seconds = 6 } :: PowerUp, -- blocks the next hit while it lasts
			speed = { seconds = 6 } :: PowerUp, -- run faster
			throwBoost = { seconds = 6 } :: PowerUp, -- throws hit harder
			ultCharge = { ultFraction = 0.5 } :: PowerUp, -- [P] instant: half the ult meter
			dashBoost = { seconds = 5 } :: PowerUp, -- no dash cooldown
			rapidThrow = { seconds = 6 } :: PowerUp, -- no wait between throws
			superJump = { seconds = 6 } :: PowerUp, -- jump much higher
			teamLife = { teamsOnly = true } :: PowerUp, -- +1 team life; at 0 lives a knocked-out teammate comes back
		},
	},
}

return Match
