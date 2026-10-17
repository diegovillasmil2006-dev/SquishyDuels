--!strict
-- MatchBotRules_Test: unit tests for ServerScriptService.Server.Logic.MatchBotRules (the FFA / TDM match bots,
-- 2026-10-17). Server only (ServerStorage.UnitTest). Pure: seeded Random objects, plain zones, fake raycasts.
-- Contract (Logic/MatchBotRules header, Config/MatchBots):
--   * dealTeams: humans Red, Blue, Red, ... then each bot to the smaller team: 12 entrants are always 6 vs 6, humans
--     only are dealt exactly as before;
--   * pickTarget: the nearest enemy within reach that is visible; visibility is asked nearest first and stops at the
--     first seen one; nil when none is seen or in reach;
--   * safeCircle: nil before the storm (with look-ahead), then the smaller of the circle now and stormLookaheadSeconds
--     later;
--   * pickMove: every goal is inside the Bounds (margin), inside the safe circle and walkable; outside the circle it
--     heads back toward the centre; a near ready pad is taken with padChance 1; with a target it keeps the distance
--     band and prefers cover with coverChance 1; without one it hunts toward the nearest enemy with huntChance 1; nil
--     when nothing is walkable;
--   * threatened: a throw flying at the bot within the angle and range, not one flying away or from too far.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local MatchBotRules = t.requireServer("Logic/MatchBotRules")
	local Config = t.requireShared("Config")
	local STORM = Config.Match.Storm

	-- The tuning these cases rely on, spelled out (the place's Config may be a newer tune).
	local BASE = {
		moveMinStuds = 6,
		moveCandidates = 6,
		edgeMarginStuds = 8,
		strafeStuds = 16,
		keepMinStuds = 18,
		keepMaxStuds = 45,
		coverChance = 0,
		huntChance = 0,
		huntJitterDegrees = 30,
		roamStuds = 40,
		padChance = 0,
		padSeekStuds = 50,
		stormLookaheadSeconds = 12,
		stormMarginStuds = 10,
		dodgeRangeStuds = 60,
		dodgeAngleDegrees = 15,
	}
	local function with(changes: { [string]: any }): any
		local copy = table.clone(BASE)
		for key, value in changes do
			copy[key] = value
		end
		return copy
	end

	local CENTRE = Vector3.new(500, 3, 0)
	local BOUNDS = { cframe = CFrame.new(500, 40, 0), size = Vector3.new(200, 115, 200) }
	local function always(): boolean
		return true
	end
	local function flatDistance(a: Vector3, b: Vector3): number
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	local function args(changes: { [string]: any }): any
		local a: any = {
			from = CENTRE,
			bounds = BOUNDS,
			safe = nil,
			target = nil,
			reach = 80,
			hunt = nil,
			pads = {},
			walkable = always,
			covered = nil,
		}
		for key, value in changes do
			a[key] = value
		end
		return a
	end

	t.test("dealTeams: players alternate as before, bots fill the smaller team (6 vs 6)", function()
		local names = { "Red", "Blue" }
		expect.deepEqual(MatchBotRules.dealTeams(4, 0, names), { "Red", "Blue", "Red", "Blue" })
		expect.deepEqual(MatchBotRules.dealTeams(3, 0, names), { "Red", "Blue", "Red" })
		for humans = 1, 12 do
			local teams = MatchBotRules.dealTeams(humans, 12 - humans, names)
			expect.equal(#teams, 12)
			local red = 0
			for index, team in teams do
				red += if team == "Red" then 1 else 0
				if index <= humans then
					expect.equal(team, names[(index - 1) % 2 + 1])
				end
			end
			expect.equal(red, 6)
		end
		expect.deepEqual(MatchBotRules.dealTeams(1, 2, names), { "Red", "Blue", "Red" })
	end)

	t.test("pickTarget: the nearest visible enemy in reach, asked nearest first", function()
		local from = Vector3.new(0, 3, 0)
		local enemies = { Vector3.new(50, 3, 0), Vector3.new(10, 3, 0), Vector3.new(30, 3, 0), Vector3.new(200, 3, 0) }
		local asked: { number } = {}
		local index = MatchBotRules.pickTarget(from, enemies, 80, function(i: number): boolean
			table.insert(asked, i)
			return i ~= 2 -- the nearest one is behind cover
		end)
		expect.equal(index, 3)
		expect.deepEqual(asked, { 2, 3 })
		expect.equal(MatchBotRules.pickTarget(from, enemies, 5, always), nil) -- none in reach
		expect.equal(
			MatchBotRules.pickTarget(from, enemies, 80, function(): boolean
				return false
			end),
			nil
		)
		expect.equal(MatchBotRules.pickTarget(from, {}, 80, always), nil)
	end)

	t.test("safeCircle: nil before the storm, then the smaller circle (now or after the look-ahead)", function()
		local cfg = with({})
		local startAt = STORM.stormStartSeconds
		expect.equal(MatchBotRules.safeCircle(STORM, CENTRE, 150, startAt - 30, cfg), nil)
		local early = MatchBotRules.safeCircle(STORM, CENTRE, 150, startAt - 5, cfg)
		expect.truthy(early ~= nil)
		expect.equal((early :: any).centre, CENTRE)
		local shrinking = STORM.steps[1].shrinkAt + STORM.steps[1].shrinkSeconds / 2
		local circle = MatchBotRules.safeCircle(STORM, CENTRE, 150, shrinking, cfg) :: any
		local StormMath = t.requireShared("StormMath")
		local now = StormMath.radiusAt(STORM, 150, shrinking)
		local later = StormMath.radiusAt(STORM, 150, shrinking + cfg.stormLookaheadSeconds)
		expect.equal(circle.radius, math.min(now, later))
		expect.truthy(circle.radius < now)
	end)

	t.test("insideBounds: the box shrunk by the margin, on X and Z only", function()
		expect.truthy(MatchBotRules.insideBounds(Vector3.new(590, -50, 0), BOUNDS, 8))
		expect.falsy(MatchBotRules.insideBounds(Vector3.new(595, 3, 0), BOUNDS, 8))
		expect.falsy(MatchBotRules.insideBounds(Vector3.new(500, 3, -99), BOUNDS, 8))
		expect.truthy(MatchBotRules.insideBounds(Vector3.new(500, 3, -99), BOUNDS, 0))
	end)

	t.test("pickMove: every goal is inside the Bounds and the safe circle, far enough and walkable", function()
		local rng = Random.new(3)
		local safe = { centre = CENTRE, radius = 60 }
		for _ = 1, 200 do
			local from = Vector3.new(500 + rng:NextNumber(-40, 40), 3, rng:NextNumber(-40, 40))
			local target = if rng:NextNumber() < 0.5 then Vector3.new(from.X + 25, 3, from.Z) else nil
			local goal = MatchBotRules.pickMove(
				rng,
				args({ from = from, safe = safe, target = target, hunt = Vector3.new(560, 3, 0) }),
				with({ huntChance = 0.5, coverChance = 0.5 })
			)
			if goal then
				expect.truthy(MatchBotRules.insideBounds(goal, BOUNDS, 8))
				expect.truthy(flatDistance(goal, CENTRE) <= 60 - 10 + 1e-6)
				expect.truthy(flatDistance(goal, from) >= 6 - 1e-6)
			end
		end
		local blocked = MatchBotRules.pickMove(
			rng,
			args({
				walkable = function(): boolean
					return false
				end,
			}),
			with({})
		)
		expect.equal(blocked, nil)
	end)

	t.test("pickMove: out of the coming storm it walks back in toward the centre", function()
		local rng = Random.new(5)
		local from = Vector3.new(580, 3, 0)
		local safe = { centre = CENTRE, radius = 40 }
		local goal = MatchBotRules.pickMove(rng, args({ from = from, safe = safe }), with({})) :: Vector3
		expect.truthy(flatDistance(goal, CENTRE) < flatDistance(from, CENTRE))
		expect.equal(goal.Z, 0)
		-- Nothing walkable: the centre itself.
		local stuck = MatchBotRules.pickMove(
			rng,
			args({
				from = from,
				safe = safe,
				walkable = function(): boolean
					return false
				end,
			}),
			with({})
		) :: Vector3
		expect.equal(flatDistance(stuck, CENTRE), 0)
	end)

	t.test("pickMove: a ready pad nearby with padChance 1; none too far or unwalkable", function()
		local rng = Random.new(9)
		local near = Vector3.new(520, 5, 10)
		local far = Vector3.new(500, 5, 90)
		local goal = MatchBotRules.pickMove(rng, args({ pads = { far, near } }), with({ padChance = 1 }))
		expect.equal(goal, near)
		local goal2 = MatchBotRules.pickMove(rng, args({ pads = { far } }), with({ padChance = 1 }))
		expect.truthy(goal2 ~= far) -- 90 studs: past padSeekStuds, so it roams instead
		local goal3 = MatchBotRules.pickMove(
			rng,
			args({
				pads = { near },
				walkable = function(_from: Vector3, to: Vector3): boolean
					return to ~= near
				end,
			}),
			with({ padChance = 1 })
		)
		expect.truthy(goal3 ~= near)
	end)

	t.test("pickMove: with a target it keeps the distance band, behind cover with coverChance 1", function()
		local rng = Random.new(11)
		local target = Vector3.new(530, 3, 0) -- 30 studs away: inside the 18..45 band
		local inBand = 0
		for _ = 1, 100 do
			local goal = MatchBotRules.pickMove(rng, args({ target = target }), with({ moveCandidates = 12 }))
			if goal then
				local d = flatDistance(goal, target)
				inBand += if d >= 18 and d <= 45 then 1 else 0
				expect.truthy(flatDistance(goal, CENTRE) <= 16 + 1e-6)
			end
		end
		expect.truthy(inBand >= 95)
		-- Cover: only spots with Z > 0 are hidden from the target; coverChance 1 picks one when it finds one.
		local hidden = 0
		for _ = 1, 100 do
			local goal = MatchBotRules.pickMove(
				rng,
				args({
					target = target,
					covered = function(point: Vector3): boolean
						return point.Z > 0
					end,
				}),
				with({ coverChance = 1, moveCandidates = 12 })
			)
			hidden += if goal and goal.Z > 0 then 1 else 0
		end
		expect.truthy(hidden >= 95)
		-- Its reach caps the band: a short reach keeps it close.
		for _ = 1, 50 do
			local goal = MatchBotRules.pickMove(
				rng,
				args({ target = Vector3.new(500, 3, 0) + Vector3.new(0, 0, 20), reach = 20 }),
				with({ moveCandidates = 12 })
			)
			if goal then
				expect.truthy(flatDistance(goal, Vector3.new(500, 3, 20)) <= 20 + 16 + 1e-6)
			end
		end
	end)

	t.test("pickMove: without a target it hunts toward the nearest enemy with huntChance 1", function()
		local rng = Random.new(13)
		local hunt = Vector3.new(500, 3, 80)
		for _ = 1, 50 do
			local goal = MatchBotRules.pickMove(rng, args({ hunt = hunt }), with({ huntChance = 1 })) :: Vector3
			expect.truthy(flatDistance(goal, hunt) < flatDistance(CENTRE, hunt))
			expect.truthy(flatDistance(goal, CENTRE) <= 40 + 1e-6)
			expect.truthy(flatDistance(goal, hunt) >= 18 - 1e-6) -- stops keepMinStuds short
		end
	end)

	t.test("threatened: a throw at the bot within the angle and range only", function()
		local cfg = with({})
		local at = Vector3.new(0, 3, 0)
		local origin = Vector3.new(0, 5, 40)
		expect.truthy(MatchBotRules.threatened(at, origin, Vector3.new(0, 20, -60), cfg))
		expect.truthy(MatchBotRules.threatened(at, origin, Vector3.new(10, 20, -60), cfg)) -- about 9.5 degrees off
		expect.falsy(MatchBotRules.threatened(at, origin, Vector3.new(30, 20, -60), cfg)) -- about 27 degrees off
		expect.falsy(MatchBotRules.threatened(at, origin, Vector3.new(0, 20, 60), cfg)) -- flying away
		expect.falsy(MatchBotRules.threatened(at, Vector3.new(0, 5, 70), Vector3.new(0, 20, -60), cfg)) -- too far
		expect.falsy(MatchBotRules.threatened(at, origin, Vector3.new(0, 60, 0), cfg)) -- straight up
	end)
end
