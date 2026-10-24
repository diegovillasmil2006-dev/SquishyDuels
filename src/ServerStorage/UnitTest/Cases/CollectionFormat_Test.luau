--!strict
-- CollectionFormat_Test: the Collection pedestal display rules of StarterPlayerScripts.Client.UI.CollectionFormat.
-- Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §7.6, §7.7, Config.Inspect.Collection, WorldLayout.Collection):
--   * slot order = Catalog.list() order over the 14 pedestals of the design's curved shelf (phase 3 D4: all 14
--     squishies, lobby.js:91, 278); slotOf is its inverse;
--   * a model builds within 60 studs and, once built, stays until it is more than 60 + 5 studs away; a missing
--     distance never builds;
--   * restCFrame stands the model on the pedestal top with its face toward the pedestal's facing (facingOf: each bay
--     faces the arc centre, lobby.js:269; -X when none is given) at angle 0, turned about +Y;
--   * the gentle sway stays within ±swayDeg of that facing (every face toward the shelf's front) and stands still
--     under ReducedMotion (angle 0); phases spread the row;
--   * the plate is Cream with the squishy's name and "Owned" / "Not owned yet"; the silhouette token is Lavender.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local CollectionFormat = t.requireClient("UI/CollectionFormat")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local Strings = t.requireShared("Strings")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local LAYOUT = WorldLayout.Collection
	local DISPLAY = Config.Inspect.Collection

	local function near3(a: Vector3, b: Vector3, tolerance: number?)
		local tol = tolerance or 1e-5
		expect.near(a.X, b.X, tol)
		expect.near(a.Y, b.Y, tol)
		expect.near(a.Z, b.Z, tol)
	end

	t.test("slots follow Catalog.list() over the 14 pedestals (D4: every squishy has one)", function()
		local defs = Catalog.list()
		expect.equal(#LAYOUT.pedestals, 14)
		expect.equal(#defs, 14)
		for slot, def in defs do
			expect.equal(CollectionFormat.squishyForSlot(slot), def.id)
			expect.equal(CollectionFormat.slotOf(def.id), slot)
			expect.equal(LAYOUT.pedestals[slot].slot, slot)
		end
		expect.equal(CollectionFormat.squishyForSlot(8), "dragon")
		for _, bad in { 0, 15, 1.5, -1, 0 / 0 } do
			expect.equal(CollectionFormat.squishyForSlot(bad), nil)
		end
		expect.equal(CollectionFormat.slotOf("not_a_squishy"), nil)
		-- A given list is used as is (the order is the list's).
		local reversed = {}
		for i = #defs, 1, -1 do
			table.insert(reversed, defs[i])
		end
		expect.equal(CollectionFormat.squishyForSlot(1, reversed), defs[#defs].id)
		expect.equal(CollectionFormat.slotOf(defs[#defs].id, reversed), 1)
		expect.equal(CollectionFormat.slotOf(defs[1].id, reversed), 14)
		-- A short list leaves the other pedestals empty.
		expect.equal(CollectionFormat.squishyForSlot(3, { defs[1], defs[2] }), nil)
	end)

	t.test("facingOf: each pedestal faces its shelf unit's front (WorldLayout); -X without a pedestal", function()
		for slot, pedestal in LAYOUT.pedestals do
			near3(CollectionFormat.facingOf(slot), pedestal.facing)
			expect.near(CollectionFormat.facingOf(slot).Magnitude, 1, 1e-5)
		end
		for _, bad in { 0, 15, 0 / 0 } do
			near3(CollectionFormat.facingOf(bad), Vector3.new(-1, 0, 0))
		end
		-- Diego's IndexShelf (Neon Sugar lobby): its side units turn 0.38 rad in toward the middle one (slots 1-3 left,
		-- 4-6 middle, 7-9 right on the top row), so not every squishy faces the same way.
		expect.truthy(CollectionFormat.facingOf(1):Dot(CollectionFormat.facingOf(4)) < 0.95)
		expect.truthy(CollectionFormat.facingOf(7):Dot(CollectionFormat.facingOf(4)) < 0.95)
	end)

	t.test("shouldBuild: build within 60 studs, keep until more than 60 + 5", function()
		expect.equal(LAYOUT.buildStuds, 60)
		expect.equal(DISPLAY.hysteresisStuds, 5)
		expect.equal(CollectionFormat.shouldBuild(0, false), true)
		expect.equal(CollectionFormat.shouldBuild(60, false), true)
		expect.equal(CollectionFormat.shouldBuild(60.01, false), false)
		expect.equal(CollectionFormat.shouldBuild(62, true), true)
		expect.equal(CollectionFormat.shouldBuild(65, true), true)
		expect.equal(CollectionFormat.shouldBuild(65.01, true), false)
		-- No distance (no character, no camera): never built.
		expect.equal(CollectionFormat.shouldBuild(math.huge, true), false)
		expect.equal(CollectionFormat.shouldBuild(0 / 0, false), false)
		expect.equal(CollectionFormat.shouldBuild(-1, true), false)
		-- Custom radius and margin.
		expect.equal(CollectionFormat.shouldBuild(11, false, 10, 2), false)
		expect.equal(CollectionFormat.shouldBuild(11, true, 10, 2), true)
		expect.equal(CollectionFormat.shouldBuild(12.5, true, 10, 2), false)
		expect.equal(CollectionFormat.shouldBuild(10.5, true, 10, 0), false)
	end)

	t.test("restCFrame: bottom on the pedestal top, face toward -X at 0°, turned about +Y", function()
		local pedestal = LAYOUT.pedestals[1]
		local top = pedestal.position + Vector3.new(0, pedestal.size.Y / 2, 0)
		local lift = 1.7
		local rest = CollectionFormat.restCFrame(top, lift, 0)
		near3(rest.Position, top + Vector3.new(0, lift, 0))
		expect.near(rest.Position.Y - lift, top.Y, 1e-5) -- the model's bottom sits on the top (Vector3 is float32)
		near3(rest.LookVector, Vector3.new(-1, 0, 0))
		near3(rest.UpVector, Vector3.new(0, 1, 0))
		-- +90° about +Y (counter-clockwise from above): the face turns from -X to +Z.
		local turned = CollectionFormat.restCFrame(top, lift, 90)
		near3(turned.Position, rest.Position)
		near3(turned.LookVector, Vector3.new(0, 0, 1))
		near3(turned.UpVector, Vector3.new(0, 1, 0))
		near3(CollectionFormat.restCFrame(top, lift, 360).LookVector, rest.LookVector)
		-- Bad numbers fall back to 0.
		local fallback = CollectionFormat.restCFrame(top, 0 / 0, math.huge)
		near3(fallback.Position, top)
		near3(fallback.LookVector, Vector3.new(-1, 0, 0))
		-- A pedestal's facing turns the face (D4); the sway turns about +Y from there.
		local facing = Vector3.new(0.6, 0, 0.8)
		local faced = CollectionFormat.restCFrame(top, lift, 0, facing)
		near3(faced.Position, rest.Position)
		near3(faced.LookVector, facing)
		near3(faced.UpVector, Vector3.new(0, 1, 0))
		local swayed = CollectionFormat.restCFrame(top, lift, 90, facing)
		near3(swayed.LookVector, (CFrame.Angles(0, math.rad(90), 0):VectorToWorldSpace(facing)))
		-- A facing with no horizontal part keeps -X.
		near3(CollectionFormat.restCFrame(top, lift, 0, Vector3.new(0, 1, 0)).LookVector, Vector3.new(-1, 0, 0))
	end)

	t.test("sway: within ±swayDeg of each pedestal's facing; 0 under ReducedMotion; phases spread the row", function()
		local amplitude, period = DISPLAY.swayDeg, DISPLAY.swayPeriodSeconds
		local count = #LAYOUT.pedestals
		expect.equal(amplitude, 15)
		expect.equal(period, 6)
		expect.truthy(amplitude < 90) -- every face stays on the shelf's front side (a full turn showed backs)
		for _, time in { 0, 1, 7.3, 1000 } do
			for slot = 1, count do
				local phase = CollectionFormat.phaseOf(slot)
				expect.equal(CollectionFormat.swayAngle(time, phase, amplitude, period, true), 0)
			end
		end
		expect.equal(CollectionFormat.phaseOf(1), 0)
		expect.near(CollectionFormat.phaseOf(8), 0.5, 1e-12) -- (8 - 1) / 14
		local seen: { [number]: boolean } = {}
		for slot = 1, count do
			local phase = CollectionFormat.phaseOf(slot)
			expect.truthy(phase >= 0 and phase < 1)
			expect.equal(seen[phase], nil)
			seen[phase] = true
		end
		expect.equal(CollectionFormat.phaseOf(0), 0)
		expect.equal(CollectionFormat.phaseOf(15), 0)
		-- amplitude × sin(2π (t / period + phase)).
		expect.near(CollectionFormat.swayAngle(0, 0, amplitude, period, false), 0, 1e-9)
		expect.near(CollectionFormat.swayAngle(period / 4, 0, amplitude, period, false), amplitude, 1e-9)
		expect.near(CollectionFormat.swayAngle(0, 0.75, amplitude, period, false), -amplitude, 1e-9)
		expect.near(
			CollectionFormat.swayAngle(period, 0.3, amplitude, period, false),
			CollectionFormat.swayAngle(0, 0.3, amplitude, period, false),
			1e-9
		)
		local most = 0
		for step = 0, 600 do
			for slot = 1, count do
				local angle =
					CollectionFormat.swayAngle(step * 0.05, CollectionFormat.phaseOf(slot), amplitude, period, false)
				expect.truthy(math.abs(angle) <= amplitude + 1e-9)
				most = math.max(most, math.abs(angle))
				-- The face (restCFrame's LookVector) never turns away from the pedestal's facing.
				local facing = CollectionFormat.facingOf(slot)
				local look = CollectionFormat.restCFrame(Vector3.zero, 0, angle, facing).LookVector
				expect.truthy(look:Dot(facing) > 0.9)
			end
		end
		expect.truthy(most > amplitude * 0.99) -- it does sway
		-- Bad numbers: no motion.
		expect.equal(CollectionFormat.swayAngle(0 / 0, 0 / 0, amplitude, period, false), 0)
		expect.equal(CollectionFormat.swayAngle(1, 0, amplitude, 0, false), 0)
		expect.equal(CollectionFormat.swayAngle(1, 0, 0, period, false), 0)
	end)

	t.test("plate: the squishy's name on Cream; Owned / Not owned yet; Lavender silhouettes", function()
		expect.equal(CollectionFormat.PLATE_TOKEN, "Cream")
		expect.equal(CollectionFormat.SILHOUETTE_TOKEN, "Lavender")
		expect.equal(typeof(Palette[CollectionFormat.PLATE_TOKEN]), "Color3")
		expect.equal(typeof(Palette[CollectionFormat.SILHOUETTE_TOKEN]), "Color3")
		for _, def in Catalog.list() do
			expect.deepEqual(
				CollectionFormat.plate(def.id, true),
				{ title = Strings.resolve(def.nameKey), status = Strings.resolve(LAYOUT.ownedKey), owned = true }
			)
			expect.deepEqual(
				CollectionFormat.plate(def.id, false),
				{ title = Strings.resolve(def.nameKey), status = Strings.resolve(LAYOUT.notOwnedKey), owned = false }
			)
		end
		expect.deepEqual(
			CollectionFormat.plate("kitty_bread", false),
			{ title = "Kitty Bread", status = "Not owned yet", owned = false }
		)
		expect.equal(CollectionFormat.plate("kitty_bread", true).status, "Owned")
		expect.equal(CollectionFormat.plate("not_a_squishy", true).title, "not_a_squishy")
	end)
end
