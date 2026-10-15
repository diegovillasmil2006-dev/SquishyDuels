--!strict
-- GroundBounce_Test: unit tests for StarterPlayerScripts.Client.Anim.GroundBounce (the 2026-10-15 ground reaction) and
-- ProjectileRenderer.groundReacts. Server only (ServerStorage.UnitTest). Pure: the casts are analytic planes.
-- Contract:
--   * a fast drop lands ("land"), bounces, rolls, rests, peels, poofs and is "done" within its time, never sinking
--     below the floor; the events come in that order;
--   * jelly bounces more than mochi from the same throw; a duel throw is over sooner than a practice one;
--   * a slow touch-down lands and rolls without a bounce; a toy at rest on a slope runs downhill;
--   * a wall sends it back; pose() is finite with the scale in the deformer's range; fade() is 0 until the poof,
--     1 when done;
--   * groundReacts: only "geometry" with a normal and not caught.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local DT = 1 / 60

-- A plane through `point` with normal `n` (unit), as GroundBounce's cast.
local function plane(point: Vector3, n: Vector3)
	return function(origin: Vector3, direction: Vector3): (Vector3?, Vector3?)
		local denom = direction:Dot(n)
		if math.abs(denom) < 1e-9 then
			return nil, nil
		end
		local s = (point - origin):Dot(n) / denom
		if s < 0 or s > 1 then
			return nil, nil
		end
		return origin + direction * s, n
	end
end

local function floorCast(y: number)
	return plane(Vector3.new(0, y, 0), Vector3.yAxis)
end

type Run = { kinds: { string }, seconds: number, lowest: number, bounces: number, state: any }

local function run(GroundBounce: any, state: any, events: { any }, cast: any, maxSeconds: number): Run
	local kinds: { string } = {}
	local bounces = 0
	for _, e in events do
		table.insert(kinds, e.kind)
	end
	local seconds = 0
	local lowest = math.huge
	while state.phase ~= "done" and seconds < maxSeconds do
		for _, e in GroundBounce.step(state, DT, cast) do
			table.insert(kinds, e.kind)
			if e.kind == "bounce" then
				bounces += 1
			end
		end
		seconds += DT
		if state.phase == "air" or state.phase == "roll" then
			lowest = math.min(lowest, state.position.Y)
		end
	end
	return { kinds = kinds, seconds = seconds, lowest = lowest, bounces = bounces, state = state }
end

local function indexOf(list: { string }, kind: string): number?
	for i, k in list do
		if k == kind then
			return i
		end
	end
	return nil
end

return function(t: Context)
	local expect = t.expect
	local GroundBounce = t.requireClient("Anim/GroundBounce")

	t.test("a fast drop lands, bounces, rests, peels, poofs and is done in order, never below the floor", function()
		local state, events = GroundBounce.new(Vector3.new(0, 1, 0), Vector3.new(40, -30, 0), Vector3.yAxis, 1, 35, "foam")
		expect.equal(events[1].kind, "land")
		local r = run(GroundBounce, state, events, floorCast(0), 10)
		expect.equal(state.phase, "done")
		expect.truthy(r.bounces >= 1)
		local order = { "land", "rest", "peel", "poof", "done" }
		local last = 0
		for _, kind in order do
			local i = indexOf(r.kinds, kind)
			expect.truthy(i ~= nil and (i :: number) > last)
			last = i :: number
		end
		expect.truthy(r.lowest >= 1 - 0.05) -- the centre stays one radius above the floor
	end)

	t.test("jelly bounces more than mochi; a duel throw is over sooner than a practice one", function()
		local function bounces(feel: string): number
			local s, e = GroundBounce.new(Vector3.new(0, 1, 0), Vector3.new(30, -40, 0), Vector3.yAxis, 1, 35, feel)
			return run(GroundBounce, s, e, floorCast(0), 10).bounces
		end
		expect.truthy(bounces("jelly") > bounces("mochi"))
		local p, pe = GroundBounce.new(Vector3.new(0, 1, 0), Vector3.new(30, -40, 0), Vector3.yAxis, 1, 35, "jelly")
		local d, de = GroundBounce.new(Vector3.new(0, 1, 0), Vector3.new(30, -40, 0), Vector3.yAxis, 1, 35, "jelly", { duel = true })
		local practice = run(GroundBounce, p, pe, floorCast(0), 10)
		local duel = run(GroundBounce, d, de, floorCast(0), 10)
		expect.truthy(duel.seconds < practice.seconds)
		expect.truthy(duel.seconds < 3)
	end)

	t.test("a slow touch-down rolls without a bounce", function()
		local state, events = GroundBounce.new(Vector3.new(0, 1, 0), Vector3.new(6, -2, 0), Vector3.yAxis, 1, 35, "foam")
		expect.equal(events[1].kind, "land")
		local r = run(GroundBounce, state, events, floorCast(0), 10)
		expect.equal(r.bounces, 0)
		expect.truthy(indexOf(r.kinds, "rest") ~= nil)
	end)

	t.test("on a slope steeper than its friction holds it runs downhill; a gentle one keeps it", function()
		-- 35°: gravity along it (35 · sin 35° ≈ 20 studs/s²) beats foam's rolling friction (16)
		local n = Vector3.new(math.sin(math.rad(35)), math.cos(math.rad(35)), 0) -- the surface falls toward +X
		local start = n * 1
		local state, events = GroundBounce.new(start, Vector3.new(0, -3, 0), n, 1, 35, "foam")
		local cast = plane(Vector3.zero, n)
		for _ = 1, 30 do
			for _, e in GroundBounce.step(state, DT, cast) do
				table.insert(events, e)
			end
		end
		expect.truthy(state.position.X > start.X + 0.05)
		-- 10°: friction wins, it comes to rest
		local g = Vector3.new(math.sin(math.rad(10)), math.cos(math.rad(10)), 0)
		local still, stillEvents = GroundBounce.new(g * 1, Vector3.new(0, -3, 0), g, 1, 35, "foam")
		local gentle = plane(Vector3.zero, g)
		local rested = false
		for _, e in stillEvents do
			rested = rested or e.kind == "rest"
		end
		for _ = 1, 60 do
			for _, e in GroundBounce.step(still, DT, gentle) do
				rested = rested or e.kind == "rest"
			end
		end
		expect.truthy(rested)
	end)

	t.test("a wall sends it back", function()
		-- a wall at x = 0 facing -X; the toy flies at it along +X
		local state, events = GroundBounce.new(Vector3.new(-1, 5, 0), Vector3.new(50, 0, 0), Vector3.new(-1, 0, 0), 1, 35, "foam")
		expect.truthy(state.velocity.X < 0)
		expect.equal(events[1].kind, "land")
	end)

	t.test("pose is finite with the scale in the deformer's range; fade 0 until the poof, 1 when done", function()
		local Config = t.requireShared("Config")
		local lo, hi = Config.Anim.deform.scaleMin, Config.Anim.deform.scaleMax
		local state, events = GroundBounce.new(Vector3.new(0, 1, 0), Vector3.new(20, -25, 5), Vector3.yAxis, 0.8, 35, "plush")
		local cast = floorCast(0)
		local sawPoof = false
		for _ = 1, 600 do
			GroundBounce.step(state, DT, cast)
			if state.phase == "done" then
				break
			end
			local frame, scale = GroundBounce.pose(state)
			local p = frame.Position
			expect.truthy(p.X == p.X and p.Y == p.Y and p.Z == p.Z)
			for _, v in { scale.X, scale.Y, scale.Z } do
				expect.truthy(v == v and v >= lo - 0.1 and v <= hi + 0.25)
			end
			local fade = GroundBounce.fade(state)
			if state.phase == "poof" then
				sawPoof = true
			else
				expect.equal(fade, 0)
			end
		end
		expect.truthy(sawPoof)
		expect.equal(state.phase, "done")
		expect.equal(GroundBounce.fade(state), 1)
		local _ = events
	end)

	t.test("ProjectileRenderer.groundReacts: geometry with a normal, not caught", function()
		local ProjectileRenderer = t.requireClient("Controllers/ProjectileRenderer")
		expect.equal(ProjectileRenderer.groundReacts("geometry", Vector3.yAxis, false), true)
		expect.equal(ProjectileRenderer.groundReacts("geometry", nil, false), false)
		expect.equal(ProjectileRenderer.groundReacts("geometry", Vector3.yAxis, true), false)
		for _, kind in { "player", "target", "expired", "fizzle" } do
			expect.equal(ProjectileRenderer.groundReacts(kind, Vector3.yAxis, false), false)
		end
	end)
end
