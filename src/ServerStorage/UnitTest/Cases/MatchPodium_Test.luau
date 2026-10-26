--!strict
-- MatchPodium_Test: unit tests for StarterPlayerScripts.Client.UI.Match.MatchPodium (end screens round B1,
-- 2026-10-26; E = Diego's uploads/sd/tdm-end.js). Contract: Team: your team, the MVP first then most squishes then
-- fewest times squished, on the cake when it won, else (a loss, a draw) in the line; Free for All: the standings' top 6
-- on the cake (the line on a draw); at most 6; the cake's ranks and the line centred; the clips timed so each HIT lands
-- at its rank's time; the camera's orbit, push, hero shot, ticks and kick, and the line's push-in (Diego's numbers);
-- the crown drops, lands, wobbles and bobs; the least blocked turn; the cake's pieces and its seeded sprinkles (the
-- design's first ones), fewer on phones.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-3

return function(t: Context)
	local expect = t.expect
	local MatchPodium = t.requireClient("UI/Match/MatchPodium")
	local PodiumPoses = t.requireClient("Anim/PodiumPoses")

	local function standing(userId: number, kos: number, knockedOut: number): any
		return { userId = userId, kos = kos, knockedOut = knockedOut, bestStreak = 0 }
	end

	local TEAMS = { [1] = "Red", [2] = "Red", [3] = "Red", [4] = "Blue", [5] = "Blue", [9] = "Red" }
	local function teamOf(userId: number): string?
		return TEAMS[userId]
	end

	local function tdm(kind: string, winner: string?, yourTeam: string): any
		return {
			mode = "tdm",
			you = { userId = 1, team = yourTeam },
			outcome = {
				kind = kind,
				winnerTeam = winner,
				standings = {
					standing(4, 9, 1),
					standing(2, 5, 2),
					standing(1, 5, 1),
					standing(5, 3, 3),
					standing(3, 7, 4),
					standing(9, 1, 0),
				},
			},
		}
	end

	t.test("Team: the winners on the cake, the MVP first, then squishes, then fewest times squished", function()
		local lineup = MatchPodium.lineup(tdm("win", "Red", "Red"), teamOf, 2)
		expect.truthy(lineup.cake)
		expect.equal(lineup.mvp, 2)
		expect.deepEqual(lineup.ids, { 2, 3, 1, 9 })
	end)

	t.test("Team: a loss or a draw is your team in the line, by squishes", function()
		local lost = MatchPodium.lineup(tdm("win", "Blue", "Red"), teamOf, 4)
		expect.falsy(lost.cake)
		expect.equal(lost.mvp, nil)
		expect.deepEqual(lost.ids, { 3, 1, 2, 9 })
		local draw = MatchPodium.lineup(tdm("draw", nil, "Blue"), teamOf, nil)
		expect.falsy(draw.cake)
		expect.deepEqual(draw.ids, { 4, 5 })
	end)

	t.test("Free for All: the top 6 on the cake for everyone; a draw in the line", function()
		local standings = {}
		for i = 1, 9 do
			table.insert(standings, standing(100 + i, 10 - i, i))
		end
		local view = {
			mode = "ffa",
			you = { userId = 109 },
			outcome = { kind = "win", winnerUserId = 101, standings = standings },
		}
		local lineup = MatchPodium.lineup(view, teamOf, 101)
		expect.truthy(lineup.cake)
		expect.equal(lineup.mvp, 101)
		expect.deepEqual(lineup.ids, { 101, 102, 103, 104, 105, 106 })
		view.outcome.kind = "draw"
		local draw = MatchPodium.lineup(view, teamOf, nil)
		expect.falsy(draw.cake)
		expect.equal(#draw.ids, 6)
		expect.equal(MatchPodium.lineup({ mode = "ffa", outcome = { kind = "win", standings = {} } }, teamOf, nil), nil)
		expect.equal(MatchPodium.lineup({ mode = "ffa" }, teamOf, nil), nil)
	end)

	t.test("the cake's ranks and the line, centred", function()
		local cake = MatchPodium.slots(true, 3)
		expect.deepEqual(cake, { { 0, 9, 0, 0 }, { -4.6, 4.6, 3.8, 0.18 }, { 4.6, 4.6, 3.8, -0.18 } })
		local line = MatchPodium.slots(false, 6)
		expect.near(line[1][1], -13.5, EPS)
		expect.near(line[6][1], 13.5, EPS)
		expect.near(line[1][3], 3 - 13.5 * 0.15, EPS) -- E:16
		expect.near(line[6][4], -13.5 * 0.012, EPS)
		local one = MatchPodium.slots(false, 1)
		expect.near(one[1][1], 0, EPS)
		expect.near(one[1][3], 3, EPS)
	end)

	t.test("each HIT lands at its rank's time; the line starts in a ripple", function()
		local starts = MatchPodium.starts(true, 6)
		local hits = { 2.3, 0.6, 0.85, 1.1, 1.35, 1.6 }
		for i = 1, 6 do
			local clip = PodiumPoses.CLIPS[PodiumPoses.VICTORY_ORDER[i]]
			expect.near(starts[i] + clip.hit / 30, hits[i], EPS)
		end
		local line = MatchPodium.starts(false, 3)
		expect.near(line[1], 0.15, EPS)
		expect.near(line[3], 0.15 + 2 * 0.17, EPS)
	end)

	t.test("the cake's camera: the orbit, the push and the hero shot", function()
		local quiet = { ticks = {}, kickAt = nil, strong = false }
		local p0, l0, f0 = MatchPodium.camera(0, true, quiet)
		-- node, E:242: c1(0) = (-2.1981, 3, 41.9424), c1(1.8) = (1.6224, 4.2, 30.9575)
		expect.near(p0.X, -2.1981, EPS)
		expect.near(p0.Y, 3, EPS)
		expect.near(p0.Z, 41.9424, EPS)
		expect.near(l0.Y, 7.2, EPS)
		expect.equal(f0, 70)
		local p1, _, f1 = MatchPodium.camera(1.8, true, quiet)
		expect.near(p1.X, 1.6224, EPS)
		expect.near(p1.Z, 30.9575, EPS)
		expect.equal(f1, 70)
		local p2, l2, f2 = MatchPodium.camera(2.3, true, quiet)
		expect.near(p2.Y, 9.6, EPS)
		expect.near(p2.Z, 16.5, EPS)
		expect.near(l2.Y, 11.4, EPS)
		expect.near(f2, 52, EPS)
		local p3, l3, f3 = MatchPodium.camera(3.3, true, quiet)
		expect.near(p3.Z, 30.5, EPS)
		expect.near(f3, 50, EPS)
		-- the breathing sway moves the look point a little, never the camera
		expect.truthy((l3 - Vector3.new(0, 9, 0)).Magnitude < 0.5)
	end)

	t.test("the ticks dip the FOV; a strong kick shakes, a soft one only dips", function()
		local _, _, plain = MatchPodium.camera(1.0, true, { ticks = {}, strong = false })
		local _, _, ticked = MatchPodium.camera(1.0, true, { ticks = { 0.94 }, strong = false })
		expect.near(plain - ticked, 1.5 * math.sin(math.pi * 0.5), EPS)
		local calm = MatchPodium.camera(2.0, true, { ticks = {}, strong = false })
		local shaken, _, kicked = MatchPodium.camera(2.0, true, { ticks = {}, kickAt = 1.99, strong = true })
		expect.truthy((shaken - calm).Magnitude > 0.01)
		local soft, _, dipped = MatchPodium.camera(2.0, true, { ticks = {}, kickAt = 1.99, strong = false })
		expect.near((soft - calm).Magnitude, 0, EPS)
		local _, _, base = MatchPodium.camera(2.0, true, { ticks = {}, strong = false })
		expect.truthy(dipped < base)
		expect.truthy(kicked < base)
	end)

	t.test("the line's camera pushes in slowly", function()
		local p0, l0, f0 = MatchPodium.camera(0, false, { ticks = {}, strong = false })
		expect.near(p0.Y, 6.8, EPS)
		expect.near(p0.Z, 29, EPS)
		expect.near(l0.Z, 1.8, 0.2)
		expect.equal(f0, 55)
		local p1 = MatchPodium.camera(3.2, false, { ticks = {}, strong = false })
		expect.near(p1.Z, 24.5, EPS)
	end)

	t.test("the crown drops, lands, wobbles and bobs", function()
		local y0, spin0, _, _, landed0 = MatchPodium.crownAt(0, 0)
		expect.near(y0, 6, EPS)
		expect.near(spin0, 4, EPS)
		expect.falsy(landed0)
		local y1, spin1, sx1, sy1, landed1 = MatchPodium.crownAt(0.22, 30)
		expect.truthy(landed1)
		expect.near(y1, 0, EPS)
		expect.near(spin1, 0, EPS)
		expect.near(sx1, 1.25, EPS)
		expect.near(sy1, 0.7, EPS)
		local y2, _, sx2 = MatchPodium.crownAt(2, 57)
		expect.near(y2, 0.16, EPS)
		expect.near(sx2, 1, EPS)
	end)

	t.test("the least blocked turn wins, the first on a tie", function()
		expect.equal(MatchPodium.bestYaw({ 2, 0, 1, 0 }), 2)
		expect.equal(MatchPodium.bestYaw({ 0, 0 }), 1)
	end)

	t.test("the cake's pieces and its seeded sprinkles", function()
		local full = MatchPodium.cakeParts(1)
		local phone = MatchPodium.cakeParts(0.6)
		expect.truthy(#phone < #full)
		local sprinkles = {}
		for _, p in full do
			if p.kind == "sprinkle" then
				table.insert(sprinkles, p)
			end
		end
		expect.equal(#sprinkles, 34 + 22 + 10)
		-- node, E:49-56 with seed 7: the first sprinkle of the bottom tier
		local first = sprinkles[1].at.Position
		expect.near(first.X, 11.0802, EPS)
		expect.near(first.Y, 1.26, EPS)
		expect.near(first.Z, 0.0038, EPS)
		-- the three tiers and their caps are the first pieces of each tier; the bottom one is 24 across
		expect.equal(full[1].kind, "cylinder")
		expect.near(full[1].size.Y, 24, EPS)
		expect.near(full[1].at.Position.Y, 0.6, EPS)
	end)
end
