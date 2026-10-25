--!strict
-- MatchVoteBoard_Test: unit tests for StarterPlayerScripts.Client.UI.MatchVoteBoard (round 3 of the match flow,
-- 2026-10-25; L = Diego's "Squishy Duels LOBBY HUD.dc.html"). Contract: the timer shows the whole seconds left, full
-- before the vote opens, its ring a second behind the number (L:684), urgent from urgentAt until the result; a card's
-- look follows L:1394-1398 (the winner to the middle, the others down and faded; the roulette's card raised and the
-- others dimmed; your pick lifted, glowing until the result); the gold count is the single leader's; each voter's
-- landing note rises; the board builds the head, the line and a card per map, and every view's votes land on their
-- cards (at once here: ReducedMotion, no tiles), moving a voter off their old card, the counts and leader following.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local MatchVoteBoard = t.requireClient("UI/MatchVoteBoard")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local V = Config.UI.MatchFound.vote

	local function view(votes: { { number } }, result: any?): any
		return {
			id = "match:test",
			mode = "ffa",
			maps = { "JellyArcade", "SundaePlaza", "PillowFortPark" },
			opensAt = 100,
			closesAt = 110,
			votes = votes,
			result = result,
		}
	end

	t.test(
		"the timer: whole seconds left, full before the open, the ring a second behind, urgent at the end",
		function()
			local v = view({ {}, {}, {} })
			local function at(now: number): { any }
				return { MatchVoteBoard.clock(v, now) }
			end
			expect.deepEqual(at(99), { 10, 1, false })
			expect.deepEqual(at(100.5), { 10, 1, false })
			expect.deepEqual(at(101), { 9, 1, false })
			local shown, share = MatchVoteBoard.clock(v, 101.5)
			expect.equal(shown, 9)
			expect.near(share, 0.95, 1e-9)
			expect.deepEqual(at(110 - V.timer.urgentAt), { V.timer.urgentAt, (V.timer.urgentAt + 1) / 10, true })
			expect.equal(select(1, MatchVoteBoard.clock(v, 110)), 0)
			expect.equal(select(2, MatchVoteBoard.clock(v, 111)), 0)
			local decided = view(
				{ {}, {}, {} },
				{ winner = 1, kind = "chosen", roulette = {}, at = 110.3, revealAt = 110.7, startsAt = 114 }
			)
			expect.equal(select(3, MatchVoteBoard.clock(decided, 108)), false) -- no red once the result is out
		end
	)

	t.test("a card's look: the winner to the middle, the roulette's card raised, your pick lifted", function()
		local cards = V.cards
		local won = { count = 3, won = 1, result = true }
		local first = MatchVoteBoard.cardPose(1, won)
		expect.equal(first.x, cards.won.stepX) -- L:1395 translateX((1 - i) * 402): the left card moves right
		expect.equal(first.scale, cards.won.scale)
		expect.equal(first.z, 3)
		expect.equal(MatchVoteBoard.cardPose(3, { count = 3, won = 3, result = true }).x, -cards.won.stepX)
		expect.equal(MatchVoteBoard.cardPose(2, { count = 3, won = 2, result = true }).x, 0)
		local lost = MatchVoteBoard.cardPose(2, won)
		expect.equal(lost.y, cards.lost.y)
		expect.equal(lost.alpha, cards.lost.alpha)
		expect.equal(lost.glow, 0)
		local lit = MatchVoteBoard.cardPose(2, { count = 3, lit = 2, result = true })
		expect.equal(lit.y, cards.roulette.y)
		expect.equal(lit.glow, 1)
		expect.equal(MatchVoteBoard.cardPose(1, { count = 3, lit = 2, result = true }).tint, cards.roulette.others)
		local mine = MatchVoteBoard.cardPose(3, { count = 3, mine = 3, result = false })
		expect.equal(mine.y, cards.mine.y)
		expect.equal(mine.glow, 1)
		expect.equal(MatchVoteBoard.cardPose(3, { count = 3, mine = 3, result = true }).glow, 0) -- L:1398 mine && !res
		expect.deepEqual(MatchVoteBoard.cardPose(1, { count = 3, mine = 3, result = false }), {
			x = 0,
			y = 0,
			scale = 1,
			tint = 1,
			alpha = 1,
			glow = 0,
			z = 1,
		})
	end)

	t.test("the gold count is the single leader's; each voter's landing note rises", function()
		expect.equal(MatchVoteBoard.leader({ 0, 0, 0 }), nil)
		expect.equal(MatchVoteBoard.leader({ 2, 1, 0 }), 1)
		expect.equal(MatchVoteBoard.leader({ 2, 2, 0 }), nil)
		expect.equal(MatchVoteBoard.leader({ 0, 1, 0 }), 2)
		expect.near(MatchVoteBoard.landPitch(1), 1, 1e-9)
		expect.near(MatchVoteBoard.landPitch(4), 2 ^ (7 / 12), 1e-9)
		expect.near(MatchVoteBoard.landPitch(99), 2 ^ (26 / 12), 1e-9)
	end)

	t.test("the board builds its parts and every view's votes land on their cards", function()
		local stage = Instance.new("Frame")
		stage.Size = UDim2.fromOffset(1440, 810)
		local played: { string } = {}
		local board = MatchVoteBoard.new({
			stage = stage,
			mode = "ffa",
			view = view({ {}, {}, {} }),
			you = 1,
			voters = {},
			now = function(): number
				return 105
			end,
			play = function(key: string)
				table.insert(played, key)
			end,
			vote = function() end,
			reduced = true,
			k = 1,
			fxK = 1,
			track = function() end,
			add = function() end,
			loop = function() end,
			onReveal = function() end,
		})
		expect.truthy(stage:FindFirstChild("VoteHead") ~= nil)
		expect.truthy(stage:FindFirstChild("VoteLine") ~= nil)
		local function chips(index: number): number
			local card = stage:FindFirstChild("Card" .. index) :: Frame
			local strip = card:FindFirstChild("Strip", true) :: Frame
			local n = 0
			for _, child in strip:GetChildren() do
				if child:IsA("Frame") then
					n += 1
				end
			end
			return n
		end
		local function leaderFace(index: number): boolean
			local card = stage:FindFirstChild("Card" .. index) :: Frame
			return (card:FindFirstChild("LeaderFace", true) :: Frame).Visible
		end
		expect.equal(chips(1) + chips(2) + chips(3), 0)
		board:setView(view({ { 1, 2 }, { 3 }, {} }))
		expect.equal(chips(1), 2)
		expect.equal(chips(2), 1)
		expect.truthy(leaderFace(1))
		expect.truthy(table.find(played, V.sounds.landMine.key) ~= nil) -- your vote's own note
		board:setView(view({ { 1 }, { 3, 2 }, {} })) -- voter 2 moved
		expect.equal(chips(1), 1)
		expect.equal(chips(2), 2)
		expect.falsy(leaderFace(1))
		expect.truthy(leaderFace(2))
		expect.equal(board:endsAt(), nil)
		local result = { winner = 2, kind = "chosen", roulette = {}, at = 110.3, revealAt = 110.7, startsAt = 114.2 }
		board:setView(view({ { 1 }, { 3, 2 }, {} }, result))
		expect.near(board:endsAt() :: number, 110.7 + V.reveal.endAfterMs / 1000, 1e-9)
		expect.equal(board:winnerName(), "Sundae Plaza")
		board:destroy()
		expect.equal(stage:FindFirstChild("VoteHead"), nil)
		expect.equal(stage:FindFirstChild("Card1"), nil)
		stage:Destroy()
	end)
end
