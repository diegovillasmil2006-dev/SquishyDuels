--!strict
-- Config.Match: the rules of Free for All (12 players) and Team Deathmatch (6 vs 6) on Diego's duel maps (jayyyyy's
-- answers 2026-10-15; plan scratch work/tdmffa/PLAN.md). Shared, data only. Read by Server/Logic/MatchRules (the match
-- state machine), Server/Logic/PowerUpRules and Shared/StormMath (also used by the client to draw the storm).
-- Values marked [P] are provisional (not given by the user; tune after the first live tests).
-- FFA/TDM v1 (2026-10-15, played inside the lobby server): the in-server queue (gatherSeconds), no rewards yet
-- (rewardCoins), out of bounds = a K.O. (outOfBoundsIsKo), the maps' footprints, Bounds height and ground
-- probe (Maps), the spawn spots (Spawns), the storm's sampling, safe respawn and test wall (Storm.sampleHz,
-- respawnInsetStuds, wall), the client's test readout (readoutHz) and the spread at the lobby return points
-- (returnSpreadStuds). Read by Server/Services/MatchService, MatchMapService, Logic/MatchSpawns, CombatService
-- (Maps.groundProbeStuds) and the client's MatchController.
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

	-- FFA/TDM v1 (2026-10-15): the in-server queue (/ffa, /tdm). Once minPlayers are queued for a mode this many
	-- seconds pass before the match starts (at once when the queue reaches maxPlayers or everyone in the server).
	gatherSeconds = 10, -- [P]
	rewardCoins = 0, -- [P] v1 pays nothing yet (no Coins, quests, weekly wins or badges)
	-- jayyyyy 2026-10-15: falling off or leaving the map "counts as a knockout" (TDM: costs a team life; FFA: you wait
	-- respawnSeconds like any K.O.). false would only put the player back at a spawn.
	outOfBoundsIsKo = true,
	readoutHz = 4, -- [P] the client's test readout chip refreshes this many times a second
	returnSpreadStuds = 4, -- [P] players sent back to the same lobby return point stand this far apart (rings of 6)

	-- Diego's maps in Workspace.DuelMaps (MatchMapService). footprint = the floor size (X x Z) by the map's Mode
	-- attribute. The Bounds box the combat code reads spans the footprint from floorY + boundsBottomOffset (the kill
	-- line: Config.Duel OutOfBounds.KillYOffset) to floorY + boundsTop (throw arcs, platforms up to 29 studs, the super
	-- jump). Studio scan 2026-10-15: walls 20 tall at the footprint edge.
	Maps = {
		footprint = {
			TDM = Vector3.new(160, 0, 240), -- [P]
			FFA = Vector3.new(200, 0, 200), -- [P]
		},
		boundsBottomOffset = -15, -- [P]
		boundsTop = 100, -- [P]
		-- [P] how far below a server HRP the ground probe looks (CombatService.groundUnder: the dash's ground check and
		-- the ultimates' floor on these maps); more than the highest standable top (29 studs)
		groundProbeStuds = 30,
	},

	-- Spawn spots on the maps' spawn pads (Logic/MatchSpawns): spotsPerPad points per pad (by mode), each at least
	-- edgeStuds from the pad's edges; a respawn avoids spots with a standing player within occupiedStuds; a respawn
	-- moved into the storm's safe circle is raised onto geometry by a downward raycast from raycastUpStuds above.
	Spawns = {
		spotsPerPad = { tdm = 6, ffa = 2 }, -- [P] TDM: one pad per team for 6 players; FFA: 8 pads for 12
		edgeStuds = 4, -- [P]
		occupiedStuds = 4, -- [P]
		raycastUpStuds = 40, -- [P]
	},

	-- The storm (TDM only), like Fortnite's: a circle around the map's centre that shrinks in steps; outside it a
	-- player's storm bar fills (barFillSeconds of time outside in total = K.O.) and inside it slowly drains.
	-- It starts as the circle around the whole map (StormMath.startRadius) and is shown from stormStartSeconds. Each
	-- step shrinks it to radiusFraction of that start radius over shrinkSeconds, beginning at shrinkAt (seconds of
	-- Active); warnSeconds before each shrink the HUD warns. With these numbers it reaches its smallest circle at 9:20.
	-- FFA/TDM v1: the server samples every standing player sampleHz times a second; a respawn that would land in the
	-- storm moves onto the safe circle, respawnInsetStuds inside its edge. `wall` is the client's test placeholder
	-- (one see-through cylinder, until Diego's storm design): its transparency, height and Art/Palette colour token.
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
		sampleHz = 5, -- [P]
		respawnInsetStuds = 6, -- [P]
		wall = {
			transparency = 0.6, -- [P]
			heightStuds = 120, -- [P]
			color = "Sky", -- [P] an Art/Palette token (a "...Key" name would be read as a Strings key by Config.validate)
		},
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
