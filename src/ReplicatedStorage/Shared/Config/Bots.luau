--!strict
-- Config.Duel.Bots: the 1v1 practice bot (owner 2026-10-16). Shared, data only. All [P]. Exposed through Config/Duel
-- (Config/init is near Roblox's 200,000-character Source limit), checked by Config/ValidateBots when BotService starts
-- (a bad value turns the bots off, it never breaks a duel). Logic/BotRules reads the numbers, BotService plays them.
-- The owner's decisions: a lone player in the 1v1 queue gets a bot within 8-10 s (a real player who queues first always
-- takes the spot), a random real-looking name (the word lists are Strings.bot), a random catalog squishy, the same
-- duel pay as a real duel, a plain Roblox character. The behaviour numbers below are a first tune: beatable, not a
-- pushover.

local Bots = {
	enabled = true, -- [P] false = no bot ever fills a duel (the off switch)

	-- Filling the queue. A player who is the only one Searching for fillDelay seconds (a new random value in
	-- [min, max] each time someone starts waiting alone) gets a bot; checked every checkSeconds.
	fillDelayMinSeconds = 8, -- [P] owner 2026-10-16: "within 8-10 seconds"
	fillDelayMaxSeconds = 10, -- [P]
	checkSeconds = 0.5, -- [P]

	-- The name: <start word><end word>[_]<number> (Logic/BotRules.name), always a valid-looking username.
	nameDigitsMin = 1, -- [P]
	nameDigitsMax = 999, -- [P] the longest words + "_" + this many digits must fit 20 characters
	nameUnderscoreChance = 0.5, -- [P] "SquishFan_23" vs "SquishFan23"

	-- The pilot: one decision step every thinkSeconds while the duel is Active / SuddenDeath.
	thinkSeconds = 0.1, -- [P]

	-- Throwing: once its throw is ready the bot waits a human reaction time, then throws at where the player will be
	-- (leadFraction of the player's flat velocity × the flight time) plus a random miss of up to
	-- min(aimErrorBaseStuds + aimErrorPerStud × distance, aimErrorMaxStuds) studs.
	throwReactionMinSeconds = 0.35, -- [P]
	throwReactionMaxSeconds = 0.8, -- [P]
	leadFraction = 0.5, -- [P] 0 = aims at the player, 1 = a perfect lead
	aimErrorBaseStuds = 1.5, -- [P]
	aimErrorPerStud = 0.06, -- [P] about 4 studs of miss at 40 studs
	aimErrorMaxStuds = 7, -- [P]

	-- Moving: a new random spot of its own half every moveMin..moveMax seconds, at least moveMinStuds away and
	-- edgeMarginStuds inside the half. With coverChance it prefers (among moveCandidates tries) a spot the player cannot
	-- see (a ray from the player is blocked by the arena's cover).
	moveMinSeconds = 0.8, -- [P]
	moveMaxSeconds = 2.2, -- [P]
	moveMinStuds = 6, -- [P]
	edgeMarginStuds = 3, -- [P]
	moveCandidates = 4, -- [P]
	coverChance = 0.35, -- [P]

	-- Dodging: when the player throws, with dodgeChance the bot dashes sideways after a reaction time (the dash's own
	-- rules and cooldown, Config.Duel.Rules.Dash, decide if it may).
	dodgeChance = 0.35, -- [P]
	dodgeReactionMinSeconds = 0.2, -- [P]
	dodgeReactionMaxSeconds = 0.45, -- [P]

	-- The ultimate: cast at the player (with the same aim error, no lead) a reaction time after it is ready.
	useUltimate = true, -- [P]
	ultReactionMinSeconds = 0.8, -- [P]
	ultReactionMaxSeconds = 2.5, -- [P]
}

return Bots
