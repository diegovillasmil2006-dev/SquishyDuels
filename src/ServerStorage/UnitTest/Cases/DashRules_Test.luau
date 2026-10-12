--!strict
-- DashRules_Test: unit tests for ServerScriptService.Server.Logic.DashRules (spec phase 5 §3.3). Server only
-- (ServerStorage.UnitTest). Pure: the world query (the Spherecast toward cover) comes in as an adapter.
-- Contract, cheapest check first:
--   * payload: an integer seq above the last one, a Vector3 direction and a server-time clientTime, else net.invalid
--     (a payload violation); lastSeq advances as soon as the seq passes, even when a later check refuses;
--   * context: a duel in Active / SuddenDeath, or the practice range, alive with a server HRP, else dash.context;
--   * not during an ultimate's wind-up or recovery (rooted), a throw windup or (feature 1, 2026-10-11) while the
--     hands crush a caught toy: dash.busy;
--   * on the ground (the HRP at most groundToleranceStuds above standing height): dash.airborne;
--   * cooldownSeconds (2.0) since the last accepted dash, less cooldownToleranceSeconds: dash.cooldown;
--   * a flat unit direction: dash.direction;
--   * a duel dasher stands in its own half + zoneToleranceStuds (like a throw): dash.context;
--   * the end point: 14 studs, cut at cover (the adapter) and kept bodyRadiusStuds inside the own half (or the
--     practice bounds), so it never crosses into the neutral band.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local NOW = 1000
local HALF_A = { cframe = CFrame.new(0, 12.5, -30), size = Vector3.new(72, 55, 44) }
local RANGE = { cframe = CFrame.new(-38, 12.5, -37), size = Vector3.new(44, 55, 34) }

return function(t: Context)
	local expect = t.expect
	local DashRules = t.requireServer("Logic/DashRules")
	local Config = t.requireShared("Config")
	local DASH = Config.Duel.Rules.Dash

	local function state(overrides: { [string]: any }?): any
		local s: { [string]: any } = {
			lastSeq = 0,
			lastDashAt = -math.huge,
			mode = "duel",
			matchPhase = "Active",
			alive = true,
			rootPosition = Vector3.new(0, 3, -30),
			floorY = 0,
			rooted = false,
			windup = false,
			zone = HALF_A,
			cast = nil,
		}
		if overrides then
			for key, value in overrides do
				s[key] = value
			end
		end
		return s
	end

	local function input(seq: any, dir: any, clientTime: any?): any
		return { seq = seq, dir = dir, clientTime = if clientTime == nil then NOW else clientTime }
	end

	local function near(a: Vector3, b: Vector3, tolerance: number?)
		expect.near((a - b).Magnitude, 0, tolerance or 1e-6)
	end

	t.test("a dash on the ground in the own half: 14 studs along the direction, from the server HRP", function()
		local decision = DashRules.validate(input(1, Vector3.new(1, 0, 0)), state(), nil, NOW)
		expect.truthy(decision.ok)
		expect.equal(decision.reason, nil)
		expect.equal(decision.lastSeq, 1)
		near(decision.from, Vector3.new(0, 3, -30))
		near(decision.to, Vector3.new(14, 3, -30))
		expect.near(decision.distance, DASH.distanceStuds, 1e-9)
		near(decision.dir, Vector3.new(1, 0, 0))
	end)

	t.test("payload: a bad seq, direction or clientTime is net.invalid and a violation", function()
		for _, bad in
			{ input(1.5, Vector3.xAxis), input(0, Vector3.xAxis), input(1, "x"), input(1, Vector3.xAxis, 1e12) }
		do
			local decision = DashRules.validate(bad, state(), nil, NOW)
			expect.falsy(decision.ok)
			expect.equal(decision.reason, "net.invalid")
			expect.truthy(decision.violation)
		end
		-- A replay of an accepted seq.
		local replay = DashRules.validate(input(4, Vector3.xAxis), state({ lastSeq = 4 }), nil, NOW)
		expect.equal(replay.reason, "net.invalid")
		expect.equal(replay.lastSeq, 4)
	end)

	t.test("context: outside Active / SuddenDeath, with no context, dead or without an HRP", function()
		local changes: { (any) -> () } = {
			function(s: any)
				s.matchPhase = "Countdown"
			end,
			function(s: any)
				s.matchPhase = "Result"
			end,
			function(s: any)
				s.mode = nil
			end,
			function(s: any)
				s.alive = false
			end,
			function(s: any)
				s.rootPosition = nil
			end,
		}
		for _, change in changes do
			local s = state()
			change(s)
			local decision = DashRules.validate(input(1, Vector3.xAxis), s, nil, NOW)
			expect.falsy(decision.ok)
			expect.equal(decision.reason, "dash.context")
			expect.falsy(decision.violation)
			expect.equal(decision.lastSeq, 1) -- the seq is spent even when refused
		end
		expect.truthy(DashRules.validate(input(1, Vector3.xAxis), state({ matchPhase = "SuddenDeath" }), nil, NOW).ok)
	end)

	t.test("busy: no dash during an ultimate's wind-up or recovery, or a throw windup", function()
		expect.equal(
			DashRules.validate(input(1, Vector3.xAxis), state({ rooted = true }), nil, NOW).reason,
			"dash.busy"
		)
		expect.equal(
			DashRules.validate(input(1, Vector3.xAxis), state({ windup = true }), nil, NOW).reason,
			"dash.busy"
		)
		-- Feature 1: no dash while crushing a caught toy.
		expect.equal(
			DashRules.validate(input(1, Vector3.xAxis), state({ crushing = true }), nil, NOW).reason,
			"dash.busy"
		)
		expect.truthy(DashRules.validate(input(1, Vector3.xAxis), state({ crushing = false }), nil, NOW).ok)
	end)

	t.test("in the air: no dash (the design ignores an air dash, fp.js:524)", function()
		local standing = 3
		local high = state({ rootPosition = Vector3.new(0, standing + DASH.groundToleranceStuds + 0.2, -30) })
		expect.equal(DashRules.validate(input(1, Vector3.xAxis), high, nil, NOW).reason, "dash.airborne")
		local settling = state({ rootPosition = Vector3.new(0, standing + DASH.groundToleranceStuds - 0.2, -30) })
		expect.truthy(DashRules.validate(input(1, Vector3.xAxis), settling, nil, NOW).ok)
		-- Heights are above the slot's own floor.
		local raisedHalf = { cframe = CFrame.new(0, 112.5, -30), size = HALF_A.size }
		local raised = state({ floorY = 100, rootPosition = Vector3.new(0, 103, -30), zone = raisedHalf })
		expect.truthy(DashRules.validate(input(1, Vector3.xAxis), raised, nil, NOW).ok)
	end)

	t.test("cooldown: 2 s between accepted dashes, with the jitter allowance", function()
		local last = NOW - DASH.cooldownSeconds + DASH.cooldownToleranceSeconds + 0.05
		expect.equal(
			DashRules.validate(input(1, Vector3.xAxis), state({ lastDashAt = last }), nil, NOW).reason,
			"dash.cooldown"
		)
		local edge = NOW - DASH.cooldownSeconds + DASH.cooldownToleranceSeconds
		expect.truthy(DashRules.validate(input(1, Vector3.xAxis), state({ lastDashAt = edge }), nil, NOW).ok)
	end)

	t.test("direction: a unit vector along the ground only", function()
		for _, bad in { Vector3.new(0, 0.5, 0.86), Vector3.new(2, 0, 0), Vector3.zero, Vector3.new(0, -1, 0) } do
			expect.equal(DashRules.validate(input(1, bad), state(), nil, NOW).reason, "dash.direction")
		end
		-- A tiny tilt is flattened away.
		local decision = DashRules.validate(input(1, Vector3.new(0.6, 0.02, 0.8)), state(), nil, NOW)
		expect.truthy(decision.ok)
		expect.near(decision.to.Y, decision.from.Y, 1e-9)
	end)

	t.test("place: a duel dash from the neutral zone or the opponent's half is refused", function()
		local tolerance = Config.Combat.Throw.zoneToleranceStuds
		local neutral = state({ rootPosition = Vector3.new(0, 3, -8 + tolerance + 0.5) })
		expect.equal(DashRules.validate(input(1, Vector3.xAxis), neutral, nil, NOW).reason, "dash.context")
		local far = state({ rootPosition = Vector3.new(0, 3, 30) })
		expect.equal(DashRules.validate(input(1, Vector3.xAxis), far, nil, NOW).reason, "dash.context")
	end)

	t.test("the end point never crosses into the neutral band and stops at cover", function()
		local forward = DashRules.validate(
			input(1, Vector3.new(0, 0, 1)),
			state({ rootPosition = Vector3.new(0, 3, -15) }),
			nil,
			NOW
		)
		expect.truthy(forward.ok)
		near(forward.to, Vector3.new(0, 3, -8 - DASH.bodyRadiusStuds))
		-- Cover 6 studs ahead (the Spherecast adapter's distance).
		local cast = function(_origin: Vector3, _dir: Vector3, distance: number): number?
			expect.truthy(distance >= DASH.distanceStuds - 1e-9)
			return 6
		end
		local blocked = DashRules.validate(input(1, Vector3.xAxis), state({ cast = cast }), nil, NOW)
		expect.truthy(blocked.ok)
		expect.near(blocked.distance, 6, 1e-9)
		near(blocked.to, Vector3.new(6, 3, -30))
		-- Against a wall: 0 studs, still a dash (its cooldown is spent).
		local wall = DashRules.validate(
			input(1, Vector3.xAxis),
			state({
				cast = function()
					return 0
				end,
			}),
			nil,
			NOW
		)
		expect.truthy(wall.ok)
		expect.near(wall.distance, 0, 1e-9)
	end)

	t.test("practice: the range bounds keep the end point; no own-half rule", function()
		local s = state({ mode = "practice", matchPhase = nil, zone = RANGE, rootPosition = Vector3.new(-20, 3, -37) })
		local back = DashRules.validate(input(1, Vector3.new(1, 0, 0)), s, nil, NOW) -- toward the range's east edge
		expect.truthy(back.ok)
		near(back.to, Vector3.new(-16 - DASH.bodyRadiusStuds, 3, -37))
		local forward = DashRules.validate(input(2, Vector3.new(-1, 0, 0)), s, nil, NOW)
		expect.truthy(forward.ok)
		near(forward.to, Vector3.new(-34, 3, -37))
	end)
end
