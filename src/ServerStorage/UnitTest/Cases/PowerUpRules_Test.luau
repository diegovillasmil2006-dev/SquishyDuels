--!strict
-- PowerUpRules_Test: unit tests for ServerScriptService.Server.Logic.PowerUpRules (Config.Match.PowerUps).
-- Contract: FFA offers every kind but the TDM-only team life, TDM offers all of them, in Config's order; a roll in
-- [0, 1) picks each kind with an equal share; a pad is ready at first, refills padRefillSeconds after a pickup, can't be
-- taken while refilling, and the given pad is never modified.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local PowerUpRules = t.requireServer("Logic/PowerUpRules")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local MATCH = Config.Match -- the fresh copy under test (the place's Config can be a cached older copy)
	local P = MATCH.PowerUps

	t.test("kindsFor: FFA has no team life; TDM has every kind; both in Config's order", function()
		local ffa = PowerUpRules.kindsFor("ffa", MATCH)
		local tdm = PowerUpRules.kindsFor("tdm", MATCH)
		expect.equal(#tdm, #P.order)
		expect.equal(#ffa, #P.order - 1)
		expect.falsy(table.find(ffa, "teamLife"))
		expect.truthy(table.find(tdm, "teamLife"))
		for index, kind in ffa do
			expect.equal(kind, P.order[index])
		end
		expect.throws(function()
			PowerUpRules.kindsFor("nope", MATCH)
		end, "unknown mode")
	end)

	t.test("roll: each kind gets an equal share of [0, 1)", function()
		for _, modeId in { "ffa", "tdm" } do
			local kinds = PowerUpRules.kindsFor(modeId, MATCH)
			local n = #kinds
			for i = 1, n do
				expect.equal(PowerUpRules.roll(modeId, (i - 0.5) / n, MATCH), kinds[i])
			end
			expect.equal(PowerUpRules.roll(modeId, 0, MATCH), kinds[1])
			expect.equal(PowerUpRules.roll(modeId, 0.999999, MATCH), kinds[n])
		end
	end)

	t.test("pads: ready at first, refill padRefillSeconds after a pickup, the given pad unchanged", function()
		local pad = PowerUpRules.newPad()
		expect.truthy(PowerUpRules.isReady(pad, 0))
		local ok, taken = PowerUpRules.take(pad, 50, MATCH)
		expect.truthy(ok)
		expect.equal(taken.readyAt, 50 + P.padRefillSeconds)
		expect.equal(pad.readyAt, -math.huge)
		local again, same = PowerUpRules.take(taken, 50 + P.padRefillSeconds - 0.1, MATCH)
		expect.falsy(again)
		expect.equal(same, taken)
		expect.truthy((PowerUpRules.take(taken, 50 + P.padRefillSeconds, MATCH)))
	end)

	t.test("Config: every kind in the order has a row; timed kinds last a positive time", function()
		for _, kind in P.order do
			local row = P.kinds[kind]
			expect.truthy(row)
			if row.seconds then
				expect.truthy(row.seconds > 0)
			end
		end
		expect.equal(P.kinds.dashBoost.seconds, 5)
		expect.equal(P.kinds.shield.seconds, 6)
		expect.truthy(P.kinds.teamLife.teamsOnly)
	end)
end
