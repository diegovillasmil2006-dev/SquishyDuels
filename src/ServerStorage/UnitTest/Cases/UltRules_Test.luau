--!strict
-- UltRules_Test: unit tests for ServerScriptService.Server.Logic.UltRules, the pure geometry of the four Epic
-- ultimates (spec phase 5 §1.5-§1.8, §3.2). Server only (ServerStorage.UnitTest). Pure math, runs in Edit mode.
-- Contract (design numbers in Config.Abilities):
--   * Flock Volley fans `count` directions evenly over fanDeg around the flat aim (3 over 24°: -12°, 0°, +12°);
--   * the hit tests read a player's feet: the capsule's lowest point (HRP + bottomOffset - radius), so a standing
--     player's feet are on the floor and a jump lifts them;
--   * the roller hits a body that touches its lane horizontally (lane half-width + capsule radius from its line) unless
--     the feet are higher than clearHeight above the floor;
--   * Rain Check centres on a spot clamped into a zone (the opponent's half) on the floor; drop k lands at angle 2.4k
--     rad and radius 2, 4, 6, 2, 4 around it, its shadow at 0.9 + 0.36k s after the release and its landing 0.75 s
--     later; a target within 7.5 studs of the centre gets a drop at its own spot, from the last drop back
--     (design: fp.js:352-357, 371-372);
--   * the practice range's rain centres on the target nearest the aim;
--   * Frosty Box (2026-11-10): Geyser Line's 3 drops stand in a line toward the centre, 5 studs apart, the centre last,
--     0.35 s apart; a Layer Cake Shockwave ring hits a body its wall meets this step and reaches it at d - R - width.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local UltRules = t.requireServer("Logic/UltRules")
	local Config = t.requireShared("Config")
	local HITBOX = Config.Combat.Hitbox
	local RAIN = Config.Abilities.rain_check
	local STAND = HITBOX.radius - HITBOX.bottomOffset -- 3.0: the HRP height of a standing player

	local function near(a: Vector3, b: Vector3, tolerance: number?)
		expect.near((a - b).Magnitude, 0, tolerance or 1e-6)
	end

	t.test("volleyDirs: 3 flat directions at -12°, 0° and +12° around the aim", function()
		local dirs = UltRules.volleyDirs(Vector3.new(0, 0, 1), 3, 24)
		expect.equal(#dirs, 3)
		local angles = {}
		for _, d in dirs do
			expect.near(d.Magnitude, 1, 1e-9)
			expect.near(d.Y, 0, 1e-9)
			table.insert(angles, math.deg(math.atan2(d.X, d.Z)))
		end
		table.sort(angles)
		expect.near(angles[1], -12, 1e-6)
		expect.near(angles[2], 0, 1e-6)
		expect.near(angles[3], 12, 1e-6)
		-- One direction is the aim itself; a tilted aim is flattened.
		local one = UltRules.volleyDirs(Vector3.new(1, 0.5, 0), 1, 24)
		expect.equal(#one, 1)
		near(one[1], Vector3.new(1, 0, 0))
	end)

	t.test("feet: a standing player's feet are on the floor; a jump lifts them", function()
		near(UltRules.feetPoint(Vector3.new(4, STAND, -30)), Vector3.new(4, 0, -30))
		expect.falsy(UltRules.feetAbove(Vector3.new(0, STAND, 0), 0, 3))
		expect.truthy(UltRules.feetAbove(Vector3.new(0, STAND + 3.1, 0), 0, 3))
		expect.falsy(UltRules.feetAbove(Vector3.new(0, STAND + 2.9, 0), 0, 3))
		expect.truthy(UltRules.feetWithin(Vector3.new(1.4, STAND, 0), Vector3.new(0, 0, 0), 1.5))
		expect.falsy(UltRules.feetWithin(Vector3.new(1.6, STAND, 0), Vector3.new(0, 0, 0), 1.5))
		-- In the air the feet are farther from a floor point.
		expect.falsy(UltRules.feetWithin(Vector3.new(0, STAND + 2, 0), Vector3.new(0, 0, 0), 1.5))
	end)

	t.test("flatEntry: the roller lane touches a body within half-width + capsule radius, at any height", function()
		local p0, p1 = Vector3.new(0, 3.5, -40), Vector3.new(0, 3.5, 20)
		local reach = 3 + HITBOX.radius
		local hit = UltRules.flatEntry(p0, p1, 3, Vector3.new(reach - 0.1, STAND, 0))
		expect.truthy(hit ~= nil)
		-- The roller's centre is reach studs from the body when it first touches (a disc of the lane's half-width).
		local at = p0:Lerp(p1, hit :: number)
		expect.near((Vector3.new(at.X, 0, at.Z) - Vector3.new(reach - 0.1, 0, 0)).Magnitude, reach, 1e-3)
		expect.equal(UltRules.flatEntry(p0, p1, 3, Vector3.new(reach + 0.1, STAND, 0)), nil)
		-- Height never matters to the flat test (the feet rule is separate).
		expect.truthy(UltRules.flatEntry(p0, p1, 3, Vector3.new(0, 40, 0)) ~= nil)
	end)

	-- WorldLayout's HalfB: X -36..36, Z 8..52.
	local HALF_B = { cframe = CFrame.new(0, 12.5, 30), size = Vector3.new(72, 55, 44) }

	t.test("rainCenter: the opponent's spot on the floor, clamped into its half", function()
		near(UltRules.rainCenter(Vector3.new(5, STAND, 30), Vector3.zero, HALF_B, 0), Vector3.new(5, 0, 30))
		-- Standing in the 2-stud tolerance strip of the neutral zone: pulled back to the half's edge.
		near(UltRules.rainCenter(Vector3.new(5, STAND, 6.5), Vector3.zero, HALF_B, 0), Vector3.new(5, 0, 8))
		-- No opponent: the fallback, clamped too.
		near(UltRules.rainCenter(nil, Vector3.new(50, 9, 20), HALF_B, 0), Vector3.new(36, 0, 20))
		-- No zone: the floor point as it is.
		near(UltRules.rainCenter(Vector3.new(5, STAND, 6.5), Vector3.zero, nil, 2), Vector3.new(5, 2, 6.5))
	end)

	t.test("rainDrops: 5 drops at 2.4k rad and 2, 4, 6, 2, 4 studs; shadows 0.36 s apart from 0.9 s", function()
		local center = Vector3.new(0, 0, 30)
		local drops = UltRules.rainDrops(center, RAIN, 100, {})
		expect.equal(#drops, 5)
		local radii = { 2, 4, 6, 2, 4 }
		for index, drop in drops do
			local k = index - 1
			local angle = k * 2.4
			near(drop.position, center + Vector3.new(math.cos(angle) * radii[index], 0, math.sin(angle) * radii[index]))
			expect.near(drop.shadowAt, 100 + 0.9 + 0.36 * k, 1e-9)
			expect.near(drop.landAt, drop.shadowAt + 0.45 + 0.3, 1e-9)
		end
	end)

	t.test("rainDrops: a target within 7.5 studs gets a drop at its own spot, from the last drop back", function()
		local center = Vector3.new(0, 0, 30)
		local near1 = Vector3.new(3, 0, 31)
		local far = Vector3.new(20, 0, 30)
		local near2 = Vector3.new(-5, 0, 28)
		local drops = UltRules.rainDrops(center, RAIN, 100, { near1, far, near2 })
		near(drops[5].position, near1) -- target 1 (index 0) -> the last drop
		-- target 2 is too far: drop 4 stays where the pattern puts it
		near(drops[4].position, center + Vector3.new(math.cos(3 * 2.4) * 2, 0, math.sin(3 * 2.4) * 2))
		near(drops[3].position, near2) -- target 3 (index 2) -> drop 3
		-- The times never change.
		expect.near(drops[5].landAt, 100 + 0.9 + 0.36 * 4 + 0.75, 1e-9)
		-- A drop is at floor height even when a target stands on something.
		local raised = UltRules.rainDrops(center, RAIN, 0, { Vector3.new(1, 4, 30) })
		expect.near(raised[5].position.Y, 0, 1e-9)
	end)

	t.test("rainDrops with dropSpacing: Geyser Line's drops in a line up to the centre, the nearest first", function()
		local GEYSER = Config.Abilities.geyser_line
		local center = Vector3.new(10, 0, 40)
		local drops = UltRules.rainDrops(center, GEYSER, 100, {}, Vector3.new(0, 3, 30)) -- from the caster's side (-Z)
		expect.equal(#drops, 3)
		near(drops[1].position, Vector3.new(10, 0, 30))
		near(drops[2].position, Vector3.new(10, 0, 35))
		near(drops[3].position, center)
		expect.near(drops[1].shadowAt, 100.1, 1e-9)
		expect.near(drops[3].shadowAt, 100.1 + 0.7, 1e-9)
		expect.near(drops[3].landAt - drops[3].shadowAt, 0.51, 1e-9)
		-- Without `toward` the drops stay where the angle rule puts them (Rain Check's way).
		near(UltRules.rainDrops(center, GEYSER, 0, {})[1].position, center)
	end)

	t.test("ringTouches / ringReachTime: the cake ring meets a body as its wall passes it", function()
		local center = Vector3.new(0, 0, 0)
		local R = HITBOX.radius
		local root = Vector3.new(8, STAND, 0)
		expect.falsy(UltRules.ringTouches(center, 2, 4, 0.5, root)) -- not there yet
		expect.truthy(UltRules.ringTouches(center, 6, 8 - R - 0.5, 0.5, root)) -- the wall just reaches the body
		expect.truthy(UltRules.ringTouches(center, 7.5, 8.5, 0.5, root)) -- passing through it
		expect.falsy(UltRules.ringTouches(center, 8 + R + 0.6, 12, 0.5, root)) -- already past
		expect.near(UltRules.ringReachTime(10, 12, 0.5, 8), 10 + (8 - R - 0.5) / 12, 1e-9)
		expect.near(UltRules.ringReachTime(10, 12, 0.5, 0.2), 10, 1e-9) -- at the centre: at once
	end)

	-- Lava Box (2026-11-10): Campfire Ring's 6 flames on the 8-stud ring, the first toward the aim, then clockwise a sixth
	-- each (design: lab50.js:345, a0 - i/6 TAU), 0.22 s apart after the 0.45 s slam, each lighting 0.5 s after its glow.
	t.test("rainDrops ringAroundCaster: Campfire Ring's flames on its ring from the aim, clockwise", function()
		local CAMPFIRE = Config.Abilities.campfire_ring
		local center = Vector3.new(0, 0, 0)
		local drops = UltRules.rainDrops(center, CAMPFIRE, 10, {}, Vector3.new(1, 0, 0))
		expect.equal(#drops, 6)
		near(drops[1].position, Vector3.new(8, 0, 0))
		local a = -math.pi / 3
		near(drops[2].position, Vector3.new(math.cos(a) * 8, 0, math.sin(a) * 8))
		for _, drop in drops do
			expect.near(Vector3.new(drop.position.X, 0, drop.position.Z).Magnitude, 8, 1e-6)
		end
		expect.near(drops[1].shadowAt, 10.45, 1e-9)
		expect.near(drops[6].shadowAt, 10.45 + 5 * 0.22, 1e-9)
		expect.near(drops[1].landAt - drops[1].shadowAt, 0.51, 1e-9)
	end)

	-- Lava Box (2026-11-10): Fondue Flood's 120° fan around the aim; a body reaching into its edge counts.
	t.test("inFan: inside the 120° fan, at its edge by the body's radius, behind it no", function()
		local center = Vector3.new(0, 0, 0)
		local dir = Vector3.new(0, 0, 1)
		local half = math.rad(60)
		expect.truthy(UltRules.inFan(center, dir, half, Vector3.new(0, STAND, 6)))
		expect.truthy(UltRules.inFan(center, dir, half, Vector3.new(6 * math.sin(math.rad(55)), STAND, 6 * math.cos(math.rad(55)))))
		expect.falsy(UltRules.inFan(center, dir, half, Vector3.new(8 * math.sin(math.rad(80)), STAND, 8 * math.cos(math.rad(80)))))
		expect.falsy(UltRules.inFan(center, dir, half, Vector3.new(0, STAND, -6))) -- behind the hippo
		expect.truthy(UltRules.inFan(center, dir, half, Vector3.new(0.5, STAND, -0.5))) -- on top of it
	end)

	t.test("practiceCenter: the target nearest the aim within range; none in front gives nil", function()
		local origin = Vector3.new(-20, 3, -37)
		local aim = Vector3.new(-1, 0, 0)
		local targets = { Vector3.new(-40, 0, -45), Vector3.new(-50, 0, -38), Vector3.new(-30, 0, -20) }
		near(UltRules.practiceCenter(origin, aim, targets, 110) :: Vector3, Vector3.new(-50, 0, -38))
		expect.equal(UltRules.practiceCenter(origin, aim, { Vector3.new(0, 0, -37) }, 110), nil) -- behind
		expect.equal(UltRules.practiceCenter(origin, aim, { Vector3.new(-200, 0, -37) }, 110), nil) -- too far
	end)
end
