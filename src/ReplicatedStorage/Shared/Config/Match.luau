--!strict
-- Config.Match: the rules of Free for All (12 players) and Team Deathmatch (6 vs 6) on Diego's duel maps (jayyyyy's
-- answers 2026-10-15; plan scratch work/tdmffa/PLAN.md). Shared, data only. Read by Server/Logic/MatchRules (the match
-- state machine), Server/Logic/PowerUpRules and Shared/StormMath (also used by the client to draw the storm).
-- Values marked [P] are provisional (not given by the user; tune after the first live tests).
-- FFA/TDM v1 (2026-10-15, played inside the lobby server): the in-server queue (gatherSeconds), no rewards yet
-- (rewardCoins; Rewards since Match HUD M2), out of bounds = a K.O. (outOfBoundsIsKo), the maps' footprints, Bounds
-- height and ground probe (Maps), the spawn spots (Spawns), the storm's sampling, safe respawn and test wall
-- (Storm.sampleHz, respawnInsetStuds, wall), the client's test readout (readoutHz) and the spread at the lobby return
-- points (returnSpreadStuds). Read by Server/Services/MatchService, MatchMapService, Logic/MatchSpawns, CombatService
-- (Maps.groundProbeStuds) and the client's MatchController.
-- Power-ups v1.1 (2026-10-16, jayyyyy's pads): who takes a pad (PowerUps.pickupRadiusStuds / pickupHeightStuds,
-- sampled at Storm.sampleHz in both modes) and what each timed power-up does (kinds.*: speed walkMultiplier, superJump
-- jumpMultiplier, rapidThrow cooldownMultiplier, throwBoost speedMultiplier). Read by Server/Services/MatchService (the
-- pads, the movement and the port callbacks CombatService and DashService ask) and the client's Throw / Dash
-- controllers (their predictions mirror the same numbers). Review fixes (2026-10-16): rapid throw's 0 means the
-- shortest cooldown (CooldownClamp.Min), not none; the dash boost is one dash after the other.
-- Match HUD M2 (2026-10-16, owner Q3 / Q4): Rewards (it replaces rewardCoins = 0): the switch of the match pay and the
-- win streak, read by Server/Services/MatchService; the amounts and rules are Config.Economy.DuelRewards'
-- (Server/Logic/MatchRewards).
-- Match bots (2026-10-17, owner): Bots = the Config/MatchBots module (Config.Match.Bots; every value and why; checked by
-- Config/ValidateMatchBots), read by Server/Services/MatchBotService and Logic/MatchBotRules.
--
-- The rules in plain words:
--   * One hit = knocked out (K.O.) in both modes. Back in after respawnSeconds with spawnProtectSeconds of safety.
--   * FFA: unlimited respawns; the first to koTarget K.O.s wins; at time-up the most K.O.s wins. No storm.
--   * TDM (owner 2026-10-26: Diego's match page, "diego 30 in 3 mins, but still have to have the storm"): unlimited
--     respawns; every K.O. scores one for the other team (a storm or out-of-bounds K.O. too); the first team to
--     koTarget wins; at time-up the higher score wins. The storm (Storm below) closes in from stormStartSeconds.
--   * A tie at time-up goes to overtime: the next K.O. decides it (TDM: the team that scores it wins; FFA: the first
--     time one player alone leads). After overtimeMaxSeconds without a winner it is a draw [P] (a safety net).
--   * Power-up pads give one random power-up (PowerUps.kinds, equal chance); a pad refills
--     PowerUps.padRefillSeconds after a pickup. A standing player takes a ready pad by standing on it (within
--     pickupRadiusStuds of its centre, pickupHeightStuds of standing height on it).

export type Mode = {
	teams: boolean, -- TDM: Red vs Blue; FFA: everyone for themselves
	maxPlayers: number,
	matchSeconds: number, -- Active phase length before time-up
	koTarget: number, -- K.O.s that win at once (TDM: the team's score)
	storm: boolean,
}

export type PowerUp = {
	seconds: number?, -- how long it lasts (nil = instant)
	ultFraction: number?, -- ultCharge: share of the full ult meter it adds
	teamsOnly: boolean?, -- only in a mode with teams (TDM)
	-- Power-ups v1.1 (2026-10-16): what a timed kind changes while it lasts.
	walkMultiplier: number?, -- speed: × Config.Duel.Rules.Movement.WalkSpeed
	jumpMultiplier: number?, -- superJump: × Config.Duel.Rules.Movement.JumpHeight
	-- rapidThrow: × the throw cooldown, never below Config.Duel.Rules.CooldownClamp.Min (0 = that shortest cooldown)
	cooldownMultiplier: number?,
	speedMultiplier: number?, -- throwBoost: × the throw's launch speed
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
			matchSeconds = 180, -- 3 minutes (Diego's MATCH.clock, uploads/tdm-hud.js)
			koTarget = 30, -- FIRST TO 30 (Diego's MATCH.target)
			storm = true,
		} :: Mode,
	},
	-- Diego's queue bar: slots 1-6 red, 7-12 blue. Owner 2026-10-16: the teams are STRAWBERRY vs BLUEBERRY.
	teamNames = { "Strawberry", "Blueberry" },

	waitSeconds = 20, -- [P] the longest wait for every player to arrive before the countdown
	-- Round 1 of the match screens (2026-10-26): the intro's cards play at least this long before the countdown, even
	-- when everyone is in at once (Diego's introExit waits until 1.7 s, LOADING SCREEN Y MATCH HUD.dc.html L:630).
	introMinSeconds = 1.7,
	countdownSeconds = 3, -- [P] the in-arena 3-2-1 (Diego's: beats 0.8 s apart, GO at Active)
	respawnSeconds = 3,
	spawnProtectSeconds = 2,
	overtimeMaxSeconds = 120, -- [P]
	resultSeconds = 8, -- [P] the end screen before players go back
	minPlayers = 2, -- fewer present at the countdown cancels the match

	-- FFA/TDM v1 (2026-10-15): the in-server queue (/ffa, /tdm). Once minPlayers are queued for a mode this many
	-- seconds pass before the match starts (at once when the queue reaches maxPlayers or everyone in the server).
	gatherSeconds = 10, -- [P]
	-- Round 3 of the match flow (2026-10-25, owner: Diego's map vote for Team and Free for All; LOBBY HUD L:1024-1147,
	-- Server/Logic/MatchVote): a match from the queue first holds its players (SD_MatchId set: no other queue takes them)
	-- and the free maps of its mode (up to maxChoices) through the MATCH FOUND show and the vote, then starts on the
	-- winner. Seconds unless named ms; [P] = not the design's.
	Vote = {
		enabled = true, -- [P] false: a queue match starts at once (the tests' setting)
		maxChoices = 3, -- L:1035: the mode's 3 maps
		-- The cards' order (Workspace.DuelMaps model names; L:1035 toybox, sprinkle, bath / arcade, sundae, park); a map
		-- not listed comes after, by name.
		mapOrder = { "ToyBoxClash", "SprinkleFactory", "BubbleBathBay", "JellyArcade", "SundaePlaza", "PillowFortPark" },
		-- found -> the vote opens: the waiting bar's fill-up (up to 12 x 70 ms + 350 ms), the show (3 s) and the swap to
		-- the vote (.64 s, L:1048-1066).
		introSeconds = 4.83,
		seconds = 10, -- L:1033 voteSeconds
		earlySeconds = 0.5, -- [P] a vote this early is taken (the cards are up, the timer not yet)
		minIntervalSeconds = 0.2, -- [P] one player's votes at least this far apart
		endDelaySeconds = 0.28, -- L:1083: the result this long after the timer's 0
		chosenRevealMs = 420, -- L:1120
		rouletteFirstMs = 320, -- L:1124-1126: the tie's roulette steps (80 + n² x 1.3 ms), then the winner
		rouletteStepMs = 80,
		rouletteGrowMs = 1.3,
		rouletteExtra = 8,
		rouletteRevealMs = 450,
		startAfterRevealSeconds = 3.52, -- L:1141: 3.1 s, then the show fades (.42 s, L:1147)
		botSkipShare = 0.08, -- L:1070: bots that never vote
		botFollowShare = 0.45, -- L:1076: a bot votes for the leader this often
		botFirstMs = 700, -- L:1070: bot votes from 700 ms into the vote, spread over the time left but the last 2.2 s
		botMinSpanMs = 800,
		botSpanMarginMs = 2200,
	},
	-- Match HUD M2 (2026-10-16, owner): a match pays like a 1v1 duel (Config.Economy.DuelRewards: the win / loss / draw
	-- squeezes, at least minOwnThrows own throws and the min Active seconds), as Coins AND Grip, with no hourly cap. A
	-- win (a team win or FFA 1st, paid or not) is +1 win streak; a loss, a draw or leaving a live match resets it
	-- (cancelled / void and 1v1 duels never touch it). Still no quests, weekly wins or badges.
	Rewards = {
		-- owner 2026-10-16 "Same as a duel, no limit" (bot matches too): on; a toast shows the pay until M9's
		-- results bar
		enabled = true,
	},
	-- jayyyyy 2026-10-15: falling off or leaving the map "counts as a knockout" (TDM: the other team scores; FFA: you wait
	-- respawnSeconds like any K.O.). false would only put the player back at a spawn.
	outOfBoundsIsKo = true,
	readoutHz = 4, -- [P] the client's test readout chip refreshes this many times a second
	returnSpreadStuds = 4, -- [P] players sent back to the same lobby return point stand this far apart (rings of 6)
	-- UI FINAL R4 (the user, 2026-10-15: "testers get the new picker", work/tdmffa/PLAN.md D3 / D5): the HUD's DUEL
	-- button shows Diego's TEAM DEATHMATCH / FREE FOR ALL picker under it (N:144-162) and joins this in-server queue
	-- (MatchJoin) for these userIds (the co-owners jayyyyy2806 and VillasmilGaming), or for everyone with
	-- pickerForEveryone; everyone else keeps the 1v1 DUEL button. A display gate only (the server's MatchJoin checks
	-- stay as they are); the chat commands /ffa /tdm /leave work for everyone as before. The user, 2026-10-16: the
	-- picker is for EVERYONE.
	pickerTesters = { 8963996639, 136002404 },
	pickerForEveryone = true, -- [P]

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
	-- Active); warnSeconds before each shrink the HUD warns. With these numbers it reaches its smallest circle at 2:50
	-- (2026-10-26: TDM is 3 minutes; still from half time, steps 30 s apart).
	-- FFA/TDM v1: the server samples every standing player sampleHz times a second; a respawn that would land in the
	-- storm moves onto the safe circle, respawnInsetStuds inside its edge. `wall` is the client's test placeholder
	-- (one see-through cylinder, until Diego's storm design): its transparency, height and Art/Palette colour token.
	Storm = {
		stormStartSeconds = 90, -- 1:30, half of TDM's 3 minutes
		warnSeconds = 15, -- [P] "Storm is coming in 0:15"
		steps = {
			{ shrinkAt = 90, shrinkSeconds = 20, radiusFraction = 0.6 }, -- [P]
			{ shrinkAt = 120, shrinkSeconds = 20, radiusFraction = 0.3 }, -- [P]
			{ shrinkAt = 150, shrinkSeconds = 20, radiusFraction = 0.1 }, -- [P] a small circle in the middle
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
		-- Power-ups v1.1 (2026-10-16): a standing player whose HumanoidRootPart is within pickupRadiusStuds of a ready
		-- pad's centre (horizontally) and within pickupHeightStuds of standing height on the pad's top takes it.
		pickupRadiusStuds = 4, -- [P]
		pickupHeightStuds = 6, -- [P]
		-- Pick order (also the random roll's order). Boosts last 6 s; dash boost 5 s (user).
		-- 2026-10-26: teamLife went with the team lives (TDM scores K.O.s now).
		order = { "shield", "speed", "throwBoost", "ultCharge", "dashBoost", "rapidThrow", "superJump" },
		kinds = {
			shield = { seconds = 6 } :: PowerUp, -- blocks the next hit while it lasts
			speed = { seconds = 6, walkMultiplier = 1.6 } :: PowerUp, -- run faster (user: x1.6)
			throwBoost = { seconds = 6, speedMultiplier = 1.4 } :: PowerUp, -- throws fly 40% faster (user)
			ultCharge = { ultFraction = 0.5 } :: PowerUp, -- [P] instant: half the ult meter
			-- no dash cooldown: one dash after the other (the next once the last one's pose has played, 0.4 s;
			-- DashService), under Config.Net's DashRequest bucket
			dashBoost = { seconds = 5 } :: PowerUp,
			-- no wait between throws: the shortest cooldown, Config.Duel.Rules.CooldownClamp.Min (0.6 s; MatchService)
			rapidThrow = { seconds = 6, cooldownMultiplier = 0 } :: PowerUp,
			superJump = { seconds = 6, jumpMultiplier = 2 } :: PowerUp, -- jump 2x as high (user)
		},
	},

	-- Match bots (2026-10-17): Config/MatchBots (every value and why; a child module, so Config/init does not grow).
	Bots = require(script.Parent.MatchBots),
}

return Match
