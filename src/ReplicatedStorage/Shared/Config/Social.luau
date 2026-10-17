--!strict
-- Config.Social: playing with friends (Batch 3, review #6 and #10, user decisions 2026-10-14: duel pads, Rematch,
-- Invite, the player list, a "Top Wins This Week" page and 12 badges). Shared, data only; Config.validate checks it.
-- Nothing here rewards inviting people or ranks spending, and no badge comes from box luck or Robux.
--   Pads     the 10 queue pads under the Duel tower (WorldLayout.QueuePads; Services/FriendDuelService with the pure
--            Logic/DuelPads): a player on a mint pad and one on the strawberry pad straight across the ring, for
--            holdSeconds (both are told "Duel with ... in holdSeconds seconds! Step off to cancel."), start a duel.
--            Checked checkHz times a second; a player stands on a pad within radiusStuds of its centre (horizontally)
--            and up to heightStuds above its top. Someone alone on a pad hears "get a friend on the ... pad" at most
--            once per waitingToastSeconds.
--   Rematch  after a finished duel (a win or a draw, nobody bailed, two players still in the server) both may press
--            Rematch for windowSeconds; both presses start a new duel. Validator: at least the Result phase, both
--            return fades, the result card's auto-close and the requeue cooldown, so the offer outlives the card.
--   Board    "Top Wins This Week" (Services/ShowOffService; the Quests screen shows it): an OrderedDataStore written by
--            the server only, one scope per week ("w" .. week, weeks start on Monday 00:00 UTC: 1970-01-01 was a
--            Thursday, so weekOffsetSeconds = 4 days), + 1 for each fully paid win over another player. Read every
--            refreshSeconds (one GetSortedAsync of readSize entries, at most 100): the top `size` and each player's own
--            place. Studio keeps it in memory unless Config.Data.studioMode is "datastore" (then studioStoreName).
--            Right to be forgotten: a player's wins sit in storeName, one scope "w<week>" per week from the first live
--            week on, keyed by tostring(userId); a deletion request means RemoveAsync(tostring(userId)) in each scope.
--   Badges   the free badges (BadgeService, server only), checked every checkSeconds; an award that errors is tried
--            again on a later check, at most maxTries times. `id` = the badge's id from the Creator Dashboard: none
--            yet (the owners make the badges and paste the ids here); a badge without an id is never awarded.
--            Rule kinds (Logic/BadgeRules): joined; stat {stat, atLeast} (profile.stats); gripLevel {atLeast};
--            ownRarityAll {rarity}; own {squishyId}; flag {flag} (a session flag: duelBuddies = finished a duel the
--            pads or Rematch started). Pens3 phase 2: the 3 capsule badges went with the capsules (none had an id).

export type BadgeRule = {
	kind: string,
	stat: string?,
	atLeast: number?,
	rarity: string?,
	squishyId: string?,
	flag: string?,
}
export type Badge = { key: string, id: number?, rule: BadgeRule }

local Social = {
	Pads = { checkHz = 5, holdSeconds = 3, radiusStuds = 1.8, heightStuds = 5, waitingToastSeconds = 30 },
	Rematch = { windowSeconds = 20 },
	Board = {
		size = 5,
		readSize = 100,
		refreshSeconds = 60,
		storeName = "WeeklyWins_v1",
		studioStoreName = "WeeklyWins_v1_STUDIO",
		weekOffsetSeconds = 4 * 86400,
	},
	Badges = {
		checkSeconds = 15,
		maxTries = 3,
		-- Paste each badge's id after `id =` (Creator Dashboard > the game > Badges), e.g. `id = 1234567890,`.
		list = {
			{ key = "welcome", id = nil, rule = { kind = "joined" } }, -- Welcome to Squishy Duels
			{ key = "first_duel", id = nil, rule = { kind = "stat", stat = "duelsPlayed", atLeast = 1 } }, -- First Duel
			{ key = "first_win", id = nil, rule = { kind = "stat", stat = "duelsWon", atLeast = 1 } }, -- First Victory
			{ key = "wins_10", id = nil, rule = { kind = "stat", stat = "duelsWon", atLeast = 10 } }, -- Duelist
			{ key = "wins_100", id = nil, rule = { kind = "stat", stat = "duelsWon", atLeast = 100 } }, -- Duel Champion
			{ key = "duel_buddies", id = nil, rule = { kind = "flag", flag = "duelBuddies" } }, -- Duel Buddies
			{ key = "grip_master", id = nil, rule = { kind = "gripLevel", atLeast = 50 } }, -- Grip Master
			{ key = "commons_all", id = nil, rule = { kind = "ownRarityAll", rarity = "Common" } }, -- Common Collector
			{ key = "dragon", id = nil, rule = { kind = "own", squishyId = "dragon" } }, -- Dragon Keeper
		} :: { Badge },
	},
}

return Social
