--!strict
-- Config.Reminders (2026-10-30, owner: "Yes, build it"). Shared, data only. Come-back reminders: Roblox experience
-- notifications sent by Server/Services/ReminderService after a player leaves (the opt-in ask:
-- Client/Controllers/ReminderOptIn). The texts live in Creator Hub (the game > Engagement > Notifications), one string
-- each; paste its asset id here. An empty id switches that reminder off; with both empty nothing runs and nobody is
-- asked. Roblox only delivers them once the game has 100 visits, to opted-in players 13+, at most one a day.

local Reminders = {
	-- "Your squishies made {coins} Coins while you were away! Come collect them."
	penMessageId = "",
	-- "Your day {day} daily reward is ready! Come claim it."
	dailyMessageId = "",
	sendAfterSeconds = 20 * 3600, -- after leaving: about the time they played the day before
	minPenCoins = 1000, -- below this the pen reminder is not worth sending (the daily one goes out instead, if ready)
	pollSeconds = 30, -- how often each live server sends the due reminders
	askDelaySeconds = 1.5, -- client: the ask line shows this long before Roblox's opt-in box
}

return table.freeze(Reminders)
