--!strict
-- Config.Match.Bots: the MATCH BOTS of Free for All / Team Deathmatch (owner 2026-10-17). Shared, data only. All [P].
-- Exposed through Config/Match (Config/init is near Roblox's 200,000-character Source limit), checked by
-- Config/ValidateMatchBots when MatchBotService starts (a bad value turns the match bots off, it never breaks a match).
-- Logic/MatchBotRules reads the numbers, MatchBotService plays them.
-- The owner's decisions: bots fill a match up to its maxPlayers (12; TDM 6 vs 6) when it starts from the queue (matches
-- run inside the lobby server, so bots are how a match gets full); a random real-looking name (the practice bot's
-- generator), a plain Roblox character; bots never block the real players' pay (the same match pay rules and switch);
-- bots never count in saves, leaderboards or win streaks. They are smarter than the 1v1 practice bot: they pick targets, move
-- around the map, use cover a bit, take power-up pads, stay out of the TDM storm, dodge and cast their ultimate.
-- Their aim, throw / dodge / ultimate reaction times and the name come from the practice bot (Config.Duel.Bots).

local MatchBots = {
	enabled = true, -- [P] false = matches never get bots (the off switch)

	-- The pilot: one decision step for every match bot every thinkSeconds while the match is live.
	thinkSeconds = 0.15, -- [P] about 7 steps a second for all 11 bots together
	-- A bot that could not be built (the avatar service failed) is tried again after this long.
	rigRetrySeconds = 15, -- [P]

	-- Targets: every targetSeconds the nearest enemy (never a teammate in TDM, never one under spawn protection) the
	-- bot can see (a ray from its head is not blocked by the map) within reach = rangeFraction × the longest throw of
	-- its squishy (ProjectileMath.maxRange), at most targetMaxStuds.
	targetSeconds = 0.4, -- [P]
	rangeFraction = 0.85, -- [P]
	targetMaxStuds = 90, -- [P]

	-- Moving: a new goal every moveMin..moveMax seconds (sooner when stuck), at least moveMinStuds away,
	-- edgeMarginStuds inside the map's Bounds, on a straight path that is clear at waist height and has ground under
	-- every pathStepStuds (no hole to the void), never onto ground more than climbStuds above its feet. Within
	-- arrivedStuds of its goal it has arrived (it waits there for the next goal).
	moveMinSeconds = 1, -- [P]
	moveMaxSeconds = 2.5, -- [P]
	moveMinStuds = 6, -- [P]
	arrivedStuds = 2, -- [P]
	moveCandidates = 6, -- [P] random tries per decision
	edgeMarginStuds = 8, -- [P]
	pathStepStuds = 6, -- [P]
	climbStuds = 3, -- [P]
	-- With a target: a spot within strafeStuds that keeps it keepMinStuds..keepMaxStuds from the target (never past its
	-- reach); with coverChance it prefers a spot the target cannot see.
	strafeStuds = 16, -- [P]
	keepMinStuds = 18, -- [P]
	keepMaxStuds = 45, -- [P]
	coverChance = 0.3, -- [P]
	-- Without a target: with huntChance it walks up to roamStuds toward the nearest enemy (up to huntJitterDegrees off
	-- the straight line), else to a random spot up to roamStuds away.
	huntChance = 0.6, -- [P]
	huntJitterDegrees = 30, -- [P]
	roamStuds = 40, -- [P]
	-- Power-up pads: with padChance a ready pad within padSeekStuds is the next goal.
	padChance = 0.35, -- [P]
	padSeekStuds = 50, -- [P]
	-- Stuck: moved less than stuckStuds in stuckSeconds while walking: it jumps once and picks a new goal.
	stuckSeconds = 1.2, -- [P]
	stuckStuds = 2, -- [P]

	-- The TDM storm: goals stay stormMarginStuds inside the safe circle as it will be stormLookaheadSeconds from now;
	-- a bot outside it walks back in first.
	stormLookaheadSeconds = 12, -- [P]
	stormMarginStuds = 10, -- [P]

	-- Dodging: an enemy's throw that heads at the bot (its flat direction within dodgeAngleDegrees of the bot, from at
	-- most dodgeRangeStuds away) is dodged with dodgeChance by a sideways dash (the practice bot's reaction time).
	dodgeChance = 0.3, -- [P]
	dodgeRangeStuds = 60, -- [P]
	dodgeAngleDegrees = 15, -- [P]
}

return MatchBots
