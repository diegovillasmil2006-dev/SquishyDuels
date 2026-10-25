--!strict
-- MatchFoundRoster_Test: unit tests for ServerScriptService.Server.Logic.MatchFoundRoster (round 2 of the match flow,
-- 2026-10-25). Contract: the players keep their order and fields; a player's Grip level is a whole number of at least 1;
-- a bot (no level) gets one from 1 to the highest player's level.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local MatchFoundRoster = t.requireServer("Logic/MatchFoundRoster")
	local expect = t.expect

	t.test("the players keep their order; levels are whole; a bot's level is at most the top player's", function()
		local view = MatchFoundRoster.build("tdm", {
			{ userId = 1, name = "A", squishy = "toast", level = 7.6, team = 1 },
			{ userId = -5, name = "Bot", squishy = "donut", team = 2 },
			{ userId = 2, name = "B", squishy = "mochi_fox", level = 0, team = 2 },
		}, Random.new(3))
		expect.equal(view.mode, "tdm")
		expect.equal(#view.players, 3)
		expect.deepEqual(view.players[1], { userId = 1, name = "A", squishy = "toast", level = 7, team = 1 })
		expect.equal(view.players[3].level, 1)
		local bot = view.players[2]
		expect.equal(bot.userId, -5)
		expect.equal(bot.team, 2)
		for seed = 1, 40 do
			local level = MatchFoundRoster.build("ffa", {
				{ userId = 1, name = "A", squishy = "toast", level = 7 },
				{ userId = -1, name = "Bot", squishy = "toast" },
			}, Random.new(seed)).players[2].level
			expect.truthy(level >= 1 and level <= 7 and level == math.floor(level))
		end
		-- Bots alone (never sent, but safe): level 1.
		local alone = MatchFoundRoster.build("1v1", { { userId = -1, name = "Bot", squishy = "toast" } }, Random.new(1))
		expect.equal(alone.players[1].level, 1)
	end)
end
