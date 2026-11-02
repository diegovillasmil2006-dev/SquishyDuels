--!strict
-- DuelVote_Test: unit tests for ServerScriptService.Server.Logic.DuelVote, the 1v1 map vote (2026-11-01, owner: "1v1
-- vote and if both vote it should be random between the 2 maps"; a 5 s vote; every duel). Pure, Edit mode.
-- Contract: the Team / Free for All vote's rules (Logic/MatchVote): both on one map -> that map; two different maps ->
-- one of those two at random (never the third); nobody -> any map; a vote is taken only while open, for a whole card
-- number, not faster than minIntervalSeconds; bots vote at their drawn times; endDelaySeconds after the close the
-- result comes with its times, and holdSeconds covers the longest one.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local T0 = 1000
local A, B = 101, 202
local MAPS = { "PencilCase", "PianoKeys", "Lunchbox" }
local ARENAS = { "D1", "D2", "D3" }

return function(t: Context)
	local DuelVote = t.requireServer("Logic/DuelVote")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local CFG = table.clone(Config.Match.Vote)
	CFG.seconds = Config.Duel.Vote.seconds

	local function newVote(seed: number, bots: { number }?): any
		return DuelVote.new("duel:test", MAPS, ARENAS, bots or {}, T0, Random.new(seed), CFG)
	end

	-- Runs the vote to its result (the cards close, then endDelaySeconds) and returns it.
	local function finish(vote: any, seed: number): any
		DuelVote.step(vote, vote.closesAt + CFG.endDelaySeconds, Random.new(seed), CFG)
		return vote
	end

	t.test("a 5 s vote that opens after the MATCH FOUND show", function()
		local vote = newVote(1)
		expect.equal(Config.Duel.Vote.seconds, 5)
		expect.equal(vote.opensAt, T0 + CFG.introSeconds)
		expect.equal(vote.closesAt, vote.opensAt + 5)
		local view = DuelVote.view(vote)
		expect.equal(view.mode, "1v1")
		expect.deepEqual(view.maps, MAPS)
		expect.equal(view.result, nil)
	end)

	t.test("both players on one map: that map", function()
		for seed = 1, 20 do
			local vote = newVote(seed)
			expect.truthy(DuelVote.cast(vote, A, 2, vote.opensAt + 1, CFG))
			expect.truthy(DuelVote.cast(vote, B, 2, vote.opensAt + 2, CFG))
			finish(vote, seed)
			expect.equal(vote.result.winner, 2)
			expect.equal(vote.result.kind, "chosen")
			expect.equal(DuelVote.winner(vote), "D2")
		end
	end)

	t.test("two different maps: one of those two at random, never the third", function()
		local seen: { [number]: boolean } = {}
		for seed = 1, 60 do
			local vote = newVote(seed)
			DuelVote.cast(vote, A, 1, vote.opensAt + 1, CFG)
			DuelVote.cast(vote, B, 3, vote.opensAt + 1, CFG)
			finish(vote, seed)
			expect.truthy(vote.result.winner == 1 or vote.result.winner == 3)
			expect.equal(vote.result.kind, "tie")
			seen[vote.result.winner] = true
		end
		expect.truthy(seen[1] and seen[3]) -- both happen
	end)

	t.test("one vote wins; nobody voting is any map at random", function()
		local vote = newVote(3)
		DuelVote.cast(vote, A, 3, vote.opensAt + 1, CFG)
		expect.equal(finish(vote, 3).result.winner, 3)
		local seen: { [number]: boolean } = {}
		for seed = 1, 60 do
			local quiet = finish(newVote(seed), seed)
			expect.equal(quiet.result.kind, "random")
			seen[quiet.result.winner] = true
		end
		expect.truthy(seen[1] and seen[2] and seen[3])
	end)

	t.test("a vote is taken only while open, for a whole card number, not too fast", function()
		local vote = newVote(4)
		expect.falsy(DuelVote.cast(vote, A, 1, vote.opensAt - CFG.earlySeconds - 0.1, CFG)) -- not open yet
		expect.truthy(DuelVote.cast(vote, A, 1, vote.opensAt - CFG.earlySeconds, CFG))
		expect.falsy(DuelVote.cast(vote, A, 2, vote.opensAt - CFG.earlySeconds + CFG.minIntervalSeconds / 2, CFG)) -- too fast
		expect.truthy(DuelVote.cast(vote, A, 2, vote.opensAt + 1, CFG)) -- moved
		expect.falsy(DuelVote.cast(vote, A, 2, vote.opensAt + 2, CFG)) -- same card: no change
		for _, bad in { 0, 4, 1.5, 0 / 0, math.huge, "1" :: any, nil :: any } do
			expect.falsy(DuelVote.cast(vote, B, bad, vote.opensAt + 1, CFG))
		end
		expect.falsy(DuelVote.cast(vote, B, 1, vote.closesAt, CFG)) -- closed
		finish(vote, 4)
		expect.falsy(DuelVote.cast(vote, B, 1, vote.closesAt - 0.1, CFG)) -- decided
	end)

	t.test("the practice bot votes at its drawn time; the result comes with its times", function()
		for seed = 1, 20 do
			local vote = newVote(seed, { -1 })
			local rng = Random.new(seed)
			local at = vote.botAt[1] -- (false once it voted)
			DuelVote.step(vote, vote.closesAt - 0.01, rng, CFG)
			local voted = 0
			for _, list in vote.votes do
				voted += #list
			end
			expect.equal(voted, if at == false then 0 else 1)
			expect.equal(vote.result, nil)
			DuelVote.step(vote, vote.closesAt + CFG.endDelaySeconds, rng, CFG)
			local r = vote.result
			expect.equal(r.at, vote.closesAt + CFG.endDelaySeconds)
			expect.truthy(r.revealAt >= r.at)
			expect.equal(r.startsAt, r.revealAt + CFG.startAfterRevealSeconds)
		end
	end)

	t.test("holdSeconds covers the longest vote (a three-way roulette)", function()
		local hold = DuelVote.holdSeconds(#MAPS, CFG)
		for seed = 1, 200 do
			local vote = finish(newVote(seed), seed)
			expect.truthy(vote.result.startsAt - T0 <= hold)
		end
	end)
end
