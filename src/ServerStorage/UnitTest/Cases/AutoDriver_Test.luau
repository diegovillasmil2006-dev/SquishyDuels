--!strict
-- AutoDriver_Test: unit tests for the pure parts of StarterPlayerScripts.Client.Studio.AutoDriver (Studio-only
-- scripted input). Server only (ServerStorage.UnitTest). Edit mode: init() is not called (nothing runs, nothing is
-- sent).
-- Contract (DESIGN §12 #21, §13.1, §13.4):
--   * it acts only while Workspace.SD_TestScenario is set: "duel_e2e" queues and fights, "practice*" throws at the
--     targets, any other scenario (the T2 dummy ones) fights in Active / SuddenDeath, empty = off;
--   * a named practice target is aimed at by TargetId, else the nearest one; practice targets are taken in turn;
--   * "backstop" (DESIGN §18.7, §18.10 L6) aims high on the practice backstop's front face, from the practice range only.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local AutoDriver = t.requireClient("Studio/AutoDriver")
	local PracticeTargets = t.requireShared("Practice/PracticeTargets")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local expect = t.expect

	local targets = {
		{ id = "target_01", distance = 12, position = Vector3.new(-36, 0, -47) },
		{ id = "target_02", distance = 20, position = Vector3.new(-44, 0, -47) },
		{ id = "target_04", distance = 12, position = Vector3.new(-36, 0, -37) },
	}

	t.test("the scenario name picks what the driver does; empty means off", function()
		expect.equal(AutoDriver.modeFor(nil), "off")
		expect.equal(AutoDriver.modeFor(""), "off")
		expect.equal(AutoDriver.modeFor(42), "off")
		expect.equal(AutoDriver.modeFor("duel_e2e"), "duel")
		expect.equal(AutoDriver.modeFor("practice"), "practice")
		expect.equal(AutoDriver.modeFor("practice_hits"), "practice")
		expect.equal(AutoDriver.modeFor("dummy_duel"), "fight")
		expect.equal(AutoDriver.modeFor("dummy_passive"), "fight")
	end)

	t.test("a named target is picked by TargetId, otherwise the nearest one", function()
		local from = Vector3.new(-20, 3, -38)
		expect.equal(AutoDriver.pickTarget(targets, from, nil), targets[3])
		expect.equal(AutoDriver.pickTarget(targets, from, "target_02"), targets[2])
		expect.equal(AutoDriver.pickTarget(targets, from, "target_09"), nil)
		expect.equal(AutoDriver.pickTarget({}, from, nil), nil)
	end)

	t.test("practice targets are taken in turn and wrap around", function()
		local first, i2 = AutoDriver.nextInTurn(targets, 1)
		expect.equal(first, targets[1])
		local second, i3 = AutoDriver.nextInTurn(targets, i2)
		expect.equal(second, targets[2])
		local third, i4 = AutoDriver.nextInTurn(targets, i3)
		expect.equal(third, targets[3])
		expect.equal(i4, 1)
		-- An index past the end (the list shrank as targets streamed out) wraps instead of failing.
		local wrapped = AutoDriver.nextInTurn(targets, 7)
		expect.equal(wrapped, targets[1])
		local none, reset = AutoDriver.nextInTurn({}, 3)
		expect.equal(none, nil)
		expect.equal(reset, 1)
	end)

	t.test("a command with nothing to aim at (no match, Edit mode) sends nothing", function()
		-- Outside Studio or with Config.Debug.autoDriver off the driver refuses; in Studio Edit mode there is no
		-- opponent and no throw context. Either way nothing is sent.
		local reply = AutoDriver.fireOnce("opponent")
		expect.falsy(reply.ok)
		expect.equal(AutoDriver.state().throwsSent, 0)
	end)

	t.test("the backstop target sits high on the backstop's front face, at the thrower's Z inside its ends", function()
		-- DESIGN §18.7 / §18.10 L6: fireOnce("backstop") gives the jelly ripple and sfx.impactSoft a real geometry hit.
		local box = WorldLayout.PracticeRange.backstop
		-- Phase 3 (D3): throws go toward +X, so the face toward the throw box is the backstop's -X face.
		local faceX = box.position.X - box.size.X / 2
		local topY = box.position.Y + box.size.Y / 2
		local minZ = box.position.Z - box.size.Z / 2
		local maxZ = box.position.Z + box.size.Z / 2
		-- Neon Sugar lobby: Diego's cushion wall (4.8 tall) is lower than a target's capsule, so a shot at it no longer
		-- clears every target; it still lands on the wall's face.
		local middle = AutoDriver.backstopPoint(nil)
		expect.near(middle.X, faceX, 1e-5) -- the face toward the throw box (throws go toward +X)
		expect.truthy(faceX < box.position.X)
		expect.near(middle.Z, box.position.Z, 1e-5)
		expect.truthy(middle.Y < topY) -- on the face, under its top edge
		expect.truthy(middle.Y > PracticeTargets.FLOOR_Y) -- above the runway

		local inLane = AutoDriver.backstopPoint(Vector3.new(30, 3, 0.5)) -- on the runway, inside the wall's reach
		expect.near(inLane.Z, 0.5, 1e-5)
		expect.near(inLane.X, faceX, 1e-5)
		local farSouth = AutoDriver.backstopPoint(Vector3.new(75, 3, 200))
		local farNorth = AutoDriver.backstopPoint(Vector3.new(75, 3, -100))
		expect.truthy(farSouth.Z < maxZ and farSouth.Z > minZ)
		expect.truthy(farNorth.Z < maxZ and farNorth.Z > minZ)
		expect.near(farSouth.Z - farNorth.Z, box.size.Z - 8, 1e-4) -- 4 studs inside each end (Vector3 is float32)
	end)

	t.test("fireOnce('backstop') outside the practice range sends nothing", function()
		local before = AutoDriver.state().throwsSent
		local reply = AutoDriver.fireOnce("backstop")
		expect.falsy(reply.ok)
		expect.equal(AutoDriver.state().throwsSent, before)
	end)
end
