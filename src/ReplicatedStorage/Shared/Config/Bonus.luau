--!strict
-- Config.Bonus (2026-11-10, big job item 4; the owner: "A bonus for joining my Roblox group (DIJAY Studios), and redeem
-- codes"). Shared, data only; required directly (Config/init is near Roblox's source size limit); Bonus_Test checks it.
-- LihFolk vault "Roblox Communities as Your On-Platform Hub" (a modest perk for members is fine; never reward likes or
-- favourites; membership is checked on the server and can be checked again; no join prompt on join or in the tutorial)
-- and "Codes Redemption System End to End" (rewards sized as if every player redeems every code; typing forgiven; one
-- use per player; guessers slowed down).
--   Group  the game's owner group. A member's pen pays penBoost more while they are in the group (Services/PerkService;
--          pen coins only, like the Friend Boost and on top of it; the "Group +10%" pill) and gets one gift per account:
--          giftSqueezes squeezes' worth of Coins (counted in squeezes like the daily reward, so it fits every stage of
--          the game; Coin reason "group"). recheckSeconds = the least time between two membership checks a player can
--          ask for (the Settings row's button).
--   Plus   big job item 5 (the owner: "Perks for Roblox Premium players"). Roblox Plus replaced Premium on 2026-04-30
--          (LihFolk vault "Subscriptions and Premium Payouts"; Roblox's Plus page): a subscriber is a player with
--          Player.HasRobloxSubscription, or one of the members Premium still has (Player.MembershipType, marked
--          deprecated). The same kind of perk as the group's, and on top of it: the pen pays penBoost more while the
--          subscription lasts (the "Plus +10%" pill) and one gift per account of giftSqueezes squeezes' worth of Coins
--          (Coin reason "plus"). Honest, the same on every device, no paywall, nothing that helps in a fight.
--   Codes  the rules of the redeem codes (the list itself is server only: Server/Logic/Codes). What a player types is
--          cut to maxTyped characters, put in capitals and keeps only letters and digits; a code is minLength..maxLength
--          long. maxSqueezes is the most a code can pay (a live code above it is skipped: a typo never floods the
--          economy). missLimit wrong codes within missWindowSeconds lock the player's redeeming for lockSeconds.

local Bonus = {
	Group = {
		id = 706867720, -- DIJAY Studios (game.CreatorId: the group that owns the game)
		penBoost = 0.10,
		giftSqueezes = 500, -- a daily reward's day 7
		recheckSeconds = 10,
	},
	Plus = {
		penBoost = 0.10,
		giftSqueezes = 500,
	},
	Codes = {
		minLength = 3,
		maxLength = 20,
		maxTyped = 40, -- under NetService's 64-character limit for a text argument
		maxSqueezes = 5000,
		missLimit = 5,
		missWindowSeconds = 60,
		lockSeconds = 60,
	},
}

return Bonus
