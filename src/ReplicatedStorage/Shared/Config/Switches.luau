--!strict
-- Config.Switches (2026-11-10, big job item 3; the owner: "add emergency switches so one broken feature can be turned
-- off without a publish"). Shared, data only. LihFolk vault "Global State and Live Config" (kill switches: a boolean
-- config checked at the entry points, default ON, flipped in seconds) and "Feature Flags and Staged Rollouts"
-- (defaults in code; every flag has an owner and a safe default).
-- A switch is one boolean in Roblox's experience configs (Creator Hub > the game > Configs, or Studio File > Open
-- Configs): key = keyPrefix .. the feature's name, e.g. `switch_boxes`. No key, or anything but `false` = ON (the
-- game runs as built when configs can't be read). `false` = that feature's requests are refused in every server
-- within about a minute, with the `reason` text; nothing else changes and nothing is lost. Turning it back to true
-- (or deleting the key) opens it again. Server/Services/SwitchService reads them; Services/NetService asks it before
-- every request of the remotes listed here.
-- A remote belongs to at most one feature; Switches_Test checks every name is a real client-to-server remote.

local Switches = {
	keyPrefix = "switch_",
	-- The reason code a refused request gets (Strings.reason.feature.off).
	reason = "feature.off",
	-- A RemoteEvent has no reply: the player gets the reason as a toast, at most once every this many seconds.
	notifyEverySeconds = 4,
	features = {
		-- Opening boxes (the paid random items: the first thing to close if odds or grants ever go wrong).
		boxes = { "BoxOpen" },
		-- Everything bought with Coins in the shop windows.
		shop = { "ShopBuy", "ShopRestockBuy", "GearBuy", "PenBuyIncome", "GripBuy", "BuyFood" },
		-- The Robux prompts (coin bundles and passes).
		robux = { "PromptCoinBundle", "PromptGamePass" },
		-- 1v1 duels: joining the queue and rematches (a duel in progress finishes).
		duels = { "QueueJoin", "RematchRequest" },
		-- Team Deathmatch and Free for All: joining a match queue.
		matches = { "MatchJoin" },
		-- The highway: going there and throwing.
		highway = { "GoHighway", "HighwayThrow" },
		-- The pen: buying spots and shelf spots, placing, selling, buying back, fusing, feeding.
		pen = { "PenBuySpot", "PenBuyShelf", "PenPlace", "SellItems", "SellAll", "BuyBack", "Fuse", "Feed", "FeedAll" },
		-- Quest and daily reward claims and quest swaps.
		rewards = { "QuestClaim", "QuestSwap", "DailyClaim" },
		-- Squeezing for Coins and Grip.
		squeeze = { "SqueezeRequest" },
	} :: { [string]: { string } },
}

return Switches
