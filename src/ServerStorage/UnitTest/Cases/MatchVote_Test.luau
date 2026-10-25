--!strict
-- MatchVote_Test: unit tests for ServerScriptService.Server.Logic.MatchVote (round 3 of the match flow, 2026-10-25;
-- L = Diego's "Squishy Duels LOBBY HUD.dc.html"). Contract: a vote moves (never counts twice) and lands last; the most
-- voted choice wins at once; a tie or no vote at all is decided among the tied after a roulette that ends on the winner
-- with steps 80 + n² x 1.3 ms apart from 320 ms (L:1122-1126); bots follow the leader at botFollowShare, and some never
-- vote; their times sit inside the vote.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local MatchVote = t.requireServer("Logic/MatchVote")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local VOTE = Config.Match.Vote

	t.test("cast: a vote moves, lands last, and the same vote changes nothing", function()
		local order = { {}, {}, {} }
		expect.truthy(MatchVote.cast(order, 1, 2))
		expect.truthy(MatchVote.cast(order, 2, 2))
		expect.falsy(MatchVote.cast(order, 1, 2))
		expect.truthy(MatchVote.cast(order, 1, 3))
		expect.deepEqual(order, { {}, { 2 }, { 1 } })
		expect.deepEqual(MatchVote.tally(order, 3), { 0, 1, 1 })
	end)

	t.test("result: the most voted wins at once (L:1120)", function()
		local result = MatchVote.result({ { 1 }, { 2, 3 }, {} }, 3, Random.new(1), VOTE)
		expect.equal(result.winner, 2)
		expect.equal(result.kind, "chosen")
		expect.equal(#result.roulette, 0)
		expect.equal(result.revealMs, VOTE.chosenRevealMs)
	end)

	t.test("result: a tie rolls over the tied choices and ends on the winner (L:1121-1126)", function()
		for seed = 1, 30 do
			local result = MatchVote.result({ { 1 }, {}, { 2 } }, 3, Random.new(seed), VOTE)
			expect.equal(result.kind, "tie")
			expect.truthy(result.winner == 1 or result.winner == 3)
			expect.truthy(#result.roulette >= VOTE.rouletteExtra + 2)
			expect.equal(result.roulette[#result.roulette].choice, result.winner)
			local last = VOTE.rouletteFirstMs
			for n, step in result.roulette do
				expect.truthy(step.choice == 1 or step.choice == 3)
				local gap = VOTE.rouletteStepMs + (n - 1) ^ 2 * VOTE.rouletteGrowMs
				expect.near(step.atMs - last, gap, 1e-6)
				last = step.atMs
			end
			expect.near(result.revealMs, last + VOTE.rouletteRevealMs, 1e-6)
		end
		local none = MatchVote.result({ {}, {}, {} }, 3, Random.new(4), VOTE)
		expect.equal(none.kind, "random")
	end)

	t.test("bots: follow the leader at botFollowShare, else any choice; some never vote", function()
		local order = { {}, { 5 }, {} }
		local follow, n = 0, 400
		for seed = 1, n do
			local pick = MatchVote.botPick(order, 3, Random.new(seed), VOTE)
			expect.truthy(pick >= 1 and pick <= 3)
			if pick == 2 then
				follow += 1
			end
		end
		-- The leader is picked when following (botFollowShare) or by chance (1/3 of the rest).
		local expected = VOTE.botFollowShare + (1 - VOTE.botFollowShare) / 3
		expect.truthy(math.abs(follow / n - expected) < 0.1)
		local times = MatchVote.botTimes(200, 10000, Random.new(9), VOTE)
		local skipped = 0
		for _, at in times do
			if at == false then
				skipped += 1
			else
				expect.truthy(at >= VOTE.botFirstMs and at <= VOTE.botFirstMs + 10000 - VOTE.botSpanMarginMs)
			end
		end
		expect.truthy(skipped > 0 and skipped < 50)
	end)
end
