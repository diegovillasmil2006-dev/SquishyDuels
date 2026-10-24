--!strict
-- PracticeTargets_Test: unit tests for ReplicatedStorage.Shared.Practice.PracticeTargets. Server only
-- (ServerStorage.UnitTest).
-- Contract (DESIGN §5.11, §7.6): the targets of WorldLayout.PracticeRange; a moving target (attributes Moving,
-- RailLength, Period) slides along Z by railLength/2 · sin(2π·t/period); positionAt is a pure function of server time
-- (same on server and client); the hitbox is the player capsule (floor+0 .. floor+6.1); the throw box and the 75° cone
-- around the range forward are the practice context of ThrowRules; the bounds come from WorldLayout. Neon Sugar lobby
-- (owner 2026-10-23, "Keep Diego's"): Diego's 4 targets stand still 6 / 11 / 16 / 21 studs past the firing line at
-- X 25 on one lane along Z 0, throws toward +X; the sliding math is tested on a rail target built from attributes.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

-- A server time like workspace:GetServerTimeNow() in 2026.
local SERVER_NOW = 1_791_000_000.25

return function(t: Context)
	local PracticeTargets = t.requireShared("Practice/PracticeTargets")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local range = WorldLayout.PracticeRange

	-- The old island's rail target (20 studs, rail 12, period 9.42 s) on the lane: Diego's targets all stand still.
	local RAIL_ATTRIBUTES = { TargetId = "target_rail", Distance = 20, Moving = true, RailLength = 12, Period = 9.42 }
	local RAIL_BASE = Vector3.new(45, 0.9, 0)
	local function movingTarget(): any
		return assert(PracticeTargets.fromAttributes(RAIL_ATTRIBUTES, RAIL_BASE), "no rail target")
	end

	-- Definitions --------------------------------------------------------------------------------------------------

	t.test("the 4 targets match WorldLayout.PracticeRange", function()
		local list = PracticeTargets.list()
		expect.equal(#list, #range.targets)
		expect.equal(#list, 4) -- Diego's 4 targets
		for index, def in list do
			local source = range.targets[index]
			expect.equal(def.id, source.id)
			expect.equal(def.distance, source.distance)
			expect.equal(def.moving, source.moving)
			expect.equal(def.railLength, source.railLength)
			expect.equal(def.period, source.period)
			-- The floor point sits on the lane floor top, under the target (where the model's pivot is built).
			expect.equal(def.position, Vector3.new(source.position.X, range.laneFloorTopY, source.position.Z))
			expect.equal(def.position.X, range.firingLineX + def.distance) -- throws go toward +X (D3)
			expect.equal(PracticeTargets.get(def.id), def)
		end
		expect.equal(PracticeTargets.get("target_99"), nil)
	end)

	t.test("Diego's targets all stand still on the lane: 6 / 11 / 16 / 21 studs past the firing line", function()
		for index, def in PracticeTargets.list() do
			expect.falsy(def.moving)
			expect.equal(def.railLength, 0)
			expect.equal(def.period, 0)
			expect.equal(def.position.Z, 0) -- the one lane runs along Z 0
			expect.equal(def.distance, ({ 6, 11, 16, 21 })[index])
		end
	end)

	-- Motion -------------------------------------------------------------------------------------------------------

	t.test("a static target never moves", function()
		for _, def in PracticeTargets.list() do
			if not def.moving then
				for _, time in { 0, 1.5, 4.71, SERVER_NOW } do
					expect.equal(PracticeTargets.positionAt(def, time), def.position)
				end
				expect.equal(PracticeTargets.velocityAt(def, SERVER_NOW), Vector3.zero)
				expect.equal(PracticeTargets.peakSpeed(def), 0)
			end
		end
	end)

	t.test("the moving target follows railLength/2 · sin(2π·t/period) along Z", function()
		local def = movingTarget()
		local period, half = def.period, def.railLength / 2
		local function zOffset(time: number): number
			return PracticeTargets.positionAt(def, time).Z - def.position.Z
		end
		expect.near(zOffset(0), 0, 1e-5)
		expect.near(zOffset(period / 4), half, 1e-4)
		expect.near(zOffset(period / 2), 0, 1e-4)
		expect.near(zOffset(3 * period / 4), -half, 1e-4)
		for step = 0, 200 do
			local time = SERVER_NOW + step * 0.137
			local position = PracticeTargets.positionAt(def, time)
			expect.equal(position.X, def.position.X)
			expect.equal(position.Y, def.position.Y)
			expect.truthy(math.abs(position.Z - def.position.Z) <= half + 1e-4)
		end
	end)

	t.test("positionAt is a pure function of server time, also at real server times", function()
		local def = movingTarget()
		expect.equal(PracticeTargets.positionAt(def, SERVER_NOW), PracticeTargets.positionAt(def, SERVER_NOW))
		-- One period later the target is back at the same place.
		local now = PracticeTargets.positionAt(def, SERVER_NOW)
		local later = PracticeTargets.positionAt(def, SERVER_NOW + def.period)
		expect.near(later.Z, now.Z, 1e-3)
	end)

	t.test("peak speed is ≈ 4 studs/s and velocityAt is the derivative", function()
		local def = movingTarget()
		expect.near(PracticeTargets.peakSpeed(def), 4, 0.01)
		expect.near(PracticeTargets.velocityAt(def, 0).Z, PracticeTargets.peakSpeed(def), 1e-6)
		local time, h = 2.2, 1e-3
		local numeric = (PracticeTargets.positionAt(def, time + h).Z - PracticeTargets.positionAt(def, time - h).Z)
			/ (2 * h)
		expect.near(PracticeTargets.velocityAt(def, time).Z, numeric, 0.01)
	end)

	t.test("a non-finite server time leaves the target at its floor point", function()
		local def = movingTarget()
		expect.equal(PracticeTargets.positionAt(def, 0 / 0), def.position)
		expect.equal(PracticeTargets.positionAt(def, math.huge), def.position)
	end)

	-- Hitbox -------------------------------------------------------------------------------------------------------

	t.test("the hitbox is the player capsule standing on the floor point", function()
		local hitbox = Config.Combat.Hitbox
		local def = movingTarget()
		local bottom, top, radius = PracticeTargets.capsuleAt(def, SERVER_NOW)
		local floor = PracticeTargets.positionAt(def, SERVER_NOW)
		expect.equal(radius, hitbox.radius)
		expect.near(bottom.Y - radius, floor.Y, 1e-4) -- floor + 0
		expect.near(top.Y + radius - floor.Y, hitbox.topOffset - hitbox.bottomOffset + 2 * hitbox.radius, 1e-4)
		expect.near(top.Y + radius - floor.Y, 6.1, 1e-4) -- §5.5: floor+0 .. floor+6.1
		expect.near(bottom.X, floor.X, 1e-6)
		expect.near(top.Z, floor.Z, 1e-6)
		expect.near(PracticeTargets.ROOT_HEIGHT, 3, 1e-9)
	end)

	-- Attributes ---------------------------------------------------------------------------------------------------

	t.test("fromAttributes reads a tagged target and rejects bad attributes", function()
		local base = RAIL_BASE -- the rail target's floor point, on the lane floor
		local attrs = { TargetId = "target_05", Distance = 20, Moving = true, RailLength = 12, Period = 9.42 }
		local def = PracticeTargets.fromAttributes(attrs, base)
		expect.truthy(def ~= nil)
		expect.equal(def.id, "target_05")
		expect.equal(def.position, base)
		expect.equal(PracticeTargets.positionAt(def, 123.4), PracticeTargets.positionAt(movingTarget(), 123.4))

		local broken: { { [string]: any } } = {
			{ Distance = 20, Moving = true, RailLength = 12, Period = 9.42 },
			{ TargetId = "t", Distance = 20, Moving = "yes", RailLength = 12, Period = 9.42 },
			{ TargetId = "t", Distance = 20, Moving = true, RailLength = -1, Period = 9.42 },
			{ TargetId = "t", Distance = 20, Moving = true, RailLength = 12, Period = 0 / 0 },
			{ TargetId = "t", Distance = math.huge, Moving = false, RailLength = 0, Period = 0 },
		}
		for _, bad in broken do
			expect.equal(PracticeTargets.fromAttributes(bad, base), nil)
		end
	end)

	-- Practice context ---------------------------------------------------------------------------------------------

	t.test("inThrowBox is the SD_PracticeZone box", function()
		expect.truthy(PracticeTargets.inThrowBox(range.approach + Vector3.new(0, 3, 0)))
		expect.truthy(PracticeTargets.inThrowBox(Vector3.new(24, 3, 5))) -- a corner spot behind the firing line
		expect.falsy(PracticeTargets.inThrowBox(Vector3.new(30, 3, 0))) -- on the runway, past the firing line
		expect.falsy(PracticeTargets.inThrowBox(Vector3.new(21, 3, 9))) -- beside the throw box (the plaza)
		expect.falsy(PracticeTargets.inThrowBox(Vector3.new(0, 3, 0))) -- the spawn
	end)

	t.test("inCone accepts aims within 75° of +X only (the design range throws east, D3)", function()
		local cone = Config.Combat.Throw.practiceConeDeg
		expect.truthy(PracticeTargets.FORWARD == Vector3.new(1, 0, 0))
		expect.truthy(PracticeTargets.inCone(Vector3.new(1, 0, 0)))
		expect.truthy(PracticeTargets.inCone(Vector3.new(1, 0.9, 0.2).Unit))
		expect.falsy(PracticeTargets.inCone(Vector3.new(-1, 0, 0)))
		expect.falsy(PracticeTargets.inCone(Vector3.new(0, 0, -1)))
		expect.falsy(PracticeTargets.inCone(Vector3.new(0, 1, 0)))
		local inside = math.rad(cone - 1)
		local outside = math.rad(cone + 1)
		expect.truthy(PracticeTargets.inCone(Vector3.new(math.cos(inside), 0, math.sin(inside))))
		expect.falsy(PracticeTargets.inCone(Vector3.new(math.cos(outside), 0, math.sin(outside))))
	end)

	t.test("the projectile bounds are WorldLayout.PracticeRange.bounds (data, not a hard-coded box)", function()
		expect.equal(PracticeTargets.BOUNDS.position, range.bounds.position)
		expect.equal(PracticeTargets.BOUNDS.size, range.bounds.size)
		expect.truthy(table.isfrozen(PracticeTargets.BOUNDS))
	end)

	t.test("every target and the throw box lie inside the practice bounds", function()
		for _, def in PracticeTargets.list() do
			for _, time in { 0, 2.355, 7.065 } do
				local root = PracticeTargets.rootAt(def, time)
				expect.truthy(PracticeTargets.inBounds(root))
			end
		end
		expect.truthy(PracticeTargets.inBounds(PracticeTargets.THROW_BOX.position))
		expect.falsy(PracticeTargets.inBounds(Vector3.new(0, 3, 0))) -- the lobby centre
	end)
end
