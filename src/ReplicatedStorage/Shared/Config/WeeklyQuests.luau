--!strict
-- Config.Economy.WeeklyQuests: the weekly quests (owner YES 2026-10-17, review page idea 6; Diego's Weekly tab,
-- "Squishy Duels HUD.dc.html" H:959, its reset pill H:1027). Shared, data only. All [P]. A child module, so Config/init
-- does not grow (it is near Roblox's 200,000-character Source limit): exposed through Config/Economy and checked by
-- Config/ValidateWeeklyQuests when QuestService starts (any problem keeps the weekly quests off; the daily quests and
-- starter tasks never depend on them). The quests themselves (goals, rewards counted in squeezes like the daily ones)
-- are QuestDefs.weekly().

local WeeklyQuests = {
	enabled = true, -- false = no new weeks and no weekly progress (quests already done stay claimable)
	-- A week starts on Monday 00:00 UTC, the same week as the "Top Wins This Week" board's
	-- (Config.Social.Board.weekOffsetSeconds): 1970-01-01 was a Thursday, so weeks start 4 days after the epoch.
	weekOffsetSeconds = 4 * 86400,
}

return WeeklyQuests
