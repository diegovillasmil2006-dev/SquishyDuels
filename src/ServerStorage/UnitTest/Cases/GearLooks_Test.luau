--!strict
-- GearLooks_Test: unit tests for ReplicatedStorage.Shared.GearLooks (big job item 9, 2026-11-10: the launcher and gear
-- models, each tier its own look). Server only (ServerStorage.UnitTest). Pure, but for the models' folder.
-- Contract:
--   * what a player wears is public as ONE number (the Player attribute SD_Gear): a digit a gear line in GearMath.LINES
--     order, each the tier owned (a power line: the tier of the last step bought; armor: a step a tier); it reads back
--     to the same tiers; anything that is not such a number reads as no gear;
--   * ReplicatedStorage.SD_Gear holds one model for every line and tier, named by modelName: MeshParts only, one of
--     them the ink hull "Outline", all anchored, weightless and never colliding, queried or touched, with the Grip
--     attribute and the pivot turned so PivotTo puts the front along the LookVector;
--   * a worn piece sits on its body part: the held launcher's grip point just in front of the fist at its own size;
--     arm gear and armor on the part (an R6 limb: lower down), fitted to the part axis by axis within the scale
--     limits, no axis more than `stretch` times the thinnest (the piece keeps its shape on a slim or a bulky body);
--   * the platform launcher stands on the deck's floor beside its player, on the side of the deck's middle, a little
--     toward the lane, never over an edge; it changes sides only once the player is well past the middle;
--   * a player is on the deck inside the throw area, and stays on it a little outside once there.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local GearLooks = t.requireShared("GearLooks")
	local GearMath = t.requireShared("GearMath")
	local L = t.requireShared("Config/GearLooks")
	local Gear = t.requireShared("Config").Economy.Gear
	local AREA = t.requireShared("World/WorldLayout").Highway.throwArea

	local TIERS = #Gear.tierSteps
	-- (the places below are read back from Vector3s, which keep single precision: hence the 1e-4)
	local FLOOR = AREA.position.Y - AREA.size.Y / 2
	local MID = AREA.position

	t.test("pack: a digit a line, the tier owned; unpack reads it back", function()
		local firstOfTier2 = Gear.tierSteps[1] + 1
		local gear = { held = firstOfTier2, platform = 0, arm = GearMath.maxStep("arm"), armor = 3 }
		local tiers = GearLooks.tiers(gear)
		expect.deepEqual(tiers, { held = 2, platform = 0, arm = TIERS, armor = 3 })
		local packed = GearLooks.pack(gear)
		expect.equal(packed, 2000 + TIERS * 10 + 3) -- LINES = held, platform, arm, armor
		expect.deepEqual(GearLooks.unpack(packed), tiers)
		-- the last star of a tier is still that tier; nothing bought is tier 0
		expect.equal(GearLooks.tiers({ held = Gear.tierSteps[1] }).held, 1)
		expect.equal(GearLooks.pack(nil), 0)
		expect.equal(GearLooks.pack({ held = "x", armor = -4 }), 0)
		-- everything bought
		local full: { [string]: number } = {}
		for _, line in GearMath.LINES do
			full[line] = GearMath.maxStep(line)
		end
		expect.equal(GearLooks.pack(full), 7777)
	end)

	t.test("unpack: anything but such a number is no gear; a digit never reads past the last tier", function()
		local none = { held = 0, platform = 0, arm = 0, armor = 0 }
		for _, junk in { "1234", true, -1, 0 / 0, math.huge, 10 ^ #GearMath.LINES } :: { any } do
			expect.deepEqual(GearLooks.unpack(junk), none)
		end
		expect.deepEqual(GearLooks.unpack(nil), none)
		expect.deepEqual(GearLooks.unpack(9999), { held = TIERS, platform = TIERS, arm = TIERS, armor = TIERS })
		expect.deepEqual(GearLooks.unpack(305.9), { held = 0, platform = 3, arm = 0, armor = 5 })
	end)

	t.test("the models: one for every line and tier, inert MeshParts with an ink hull", function()
		local folder = game:GetService("ReplicatedStorage"):FindFirstChild(GearLooks.FOLDER)
		expect.truthy(folder ~= nil)
		local count = 0
		for _, line in GearMath.LINES do
			for tier = 1, TIERS do
				local name = GearLooks.modelName(line, tier)
				expect.equal(name, line .. "_" .. tier)
				local model = (folder :: Instance):FindFirstChild(name)
				expect.truthy(model ~= nil and model:IsA("Model"))
				expect.equal(typeof((model :: Model):GetAttribute("Grip")), "Vector3")
				-- the import's half turn is taken back by the pivot: the front is the LookVector
				expect.truthy((model :: Model):GetPivot().LookVector:FuzzyEq(Vector3.new(0, 0, 1), 1e-3))
				local hull = false
				for _, part in (model :: Model):GetChildren() do
					expect.truthy(part:IsA("MeshPart"))
					local p = part :: MeshPart
					expect.truthy(p.Anchored and p.Massless and not p.CanCollide and not p.CanQuery and not p.CanTouch)
					hull = hull or p.Name == "Outline"
				end
				expect.truthy(hull)
				count += 1
			end
		end
		expect.equal(count, #(folder :: Instance):GetChildren())
	end)

	t.test("mount: the held launcher's grip just in front of the fist; arm gear and armor fitted to the part", function()
		local S = L.scale
		local whole = { part = "X", y = 0, h = 1 }
		local hand = Vector3.new(1, 0.3, 1)
		local grip = Vector3.new(0, 0.6, 0.38)
		local at, scale = GearLooks.mount("held", hand, whole, grip)
		expect.equal(scale, Vector3.one) -- a launcher is never resized
		expect.truthy(at.Rotation == CFrame.identity)
		-- the grip point lands gapStuds in front of the hand's front face
		expect.truthy((at * grip):FuzzyEq(Vector3.new(0, 0, -(0.5 + L.held.gapStuds)), 1e-5))
		-- an R6 arm: the hand is its lower end
		local r6 = GearLooks.mount("held", Vector3.new(1, 2, 1), L.held.mounts[2], nil)
		expect.near(r6.Position.Y, -0.84, 1e-5)
		for _, line in { "arm", "armor" } do
			local fit: Vector3 = (L :: any)[line].fitStuds
			-- the body it was modelled for: as it is, on the part's centre
			local same, one = GearLooks.mount(line, fit, whole, nil)
			expect.truthy(same == CFrame.identity)
			expect.truthy(one:FuzzyEq(Vector3.one, 1e-5))
			-- a bulky body: every axis stops at the most
			local _, bulky = GearLooks.mount(line, fit * 3, whole, nil)
			expect.truthy(bulky:FuzzyEq(Vector3.one * S.max, 1e-5))
			-- a stick-thin part: the thin axis stops at the least, and no axis is over `stretch` times it
			local _, thin = GearLooks.mount(line, Vector3.new(fit.X * 0.1, fit.Y * 3, fit.Z * 3), whole, nil)
			expect.near(thin.X, S.min, 1e-5)
			expect.near(thin.Y, S.min * S.stretch, 1e-5)
			expect.near(thin.Z, S.min * S.stretch, 1e-5)
			-- a little wider only: only that axis grows
			local _, wider = GearLooks.mount(line, Vector3.new(fit.X * 1.2, fit.Y, fit.Z), whole, nil)
			expect.truthy(wider:FuzzyEq(Vector3.new(1.2, 1, 1), 1e-4))
		end
		-- the owner's own slim avatar (measured 2026-11-10): the armor hugs the 1.15-stud torso, the cuff the 0.44 arm
		local _, slimTorso = GearLooks.mount("armor", Vector3.new(1.15, 2.24, 0.96), whole, nil)
		expect.truthy(slimTorso:FuzzyEq(Vector3.new(0.575, 0.8625, 0.8625), 1e-4))
		local _, slimArm = GearLooks.mount("arm", Vector3.new(0.44, 1.2, 0.53), whole, nil)
		expect.truthy(slimArm:FuzzyEq(Vector3.new(0.5, 0.75, 0.53), 1e-4))
		-- an R6 arm is upper and lower arm in one: the cuff sits on the lower half, fitted to half its length
		local lower, half = GearLooks.mount("arm", Vector3.new(1, 2, 1), L.arm.mounts[2], nil)
		expect.near(lower.Position.Y, -0.5, 1e-4)
		expect.near(half.Y, 1 / L.arm.fitStuds.Y, 1e-4)
	end)

	t.test("the platform launcher: on the floor beside its player, toward the middle and the lane, on the deck", function()
		local P = L.platform
		local right = MID + Vector3.new(6, 3, 0)
		local goal, side = GearLooks.platformGoal(right, 0)
		expect.equal(side, -1) -- a player right of the middle: the launcher at their left
		expect.near(goal.X, right.X - P.sideStuds, 1e-4)
		expect.near(goal.Y, FLOOR, 1e-4)
		expect.near(goal.Z, right.Z - P.aheadStuds, 1e-4)
		local left = MID + Vector3.new(-6, 3, 0)
		local goalL, sideL = GearLooks.platformGoal(left, 0)
		expect.equal(sideL, 1)
		expect.near(goalL.X, left.X + P.sideStuds, 1e-4)
		-- near the middle it keeps its side; flipStuds past it, it changes
		local _, kept = GearLooks.platformGoal(MID + Vector3.new(-P.flipStuds * 0.5, 3, 0), -1)
		expect.equal(kept, -1)
		local _, flipped = GearLooks.platformGoal(MID + Vector3.new(-P.flipStuds - 0.1, 3, 0), -1)
		expect.equal(flipped, 1)
		local _, first = GearLooks.platformGoal(MID + Vector3.new(-0.1, 3, 0), 0)
		expect.equal(first, 1)
		-- never over an edge: every corner of the area keeps the launcher's footprint on the deck
		local half = AREA.size / 2
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				for _, last in { -1, 0, 1 } do
					local corner = MID + Vector3.new(sx * half.X, 0, sz * half.Z)
					local at = GearLooks.platformGoal(corner, last)
					expect.truthy(math.abs(at.X - MID.X) <= half.X - P.halfWidthStuds + 1e-4)
					expect.truthy(at.Z >= MID.Z - half.Z + P.frontStuds - 1e-4)
					expect.truthy(at.Z <= MID.Z + half.Z - P.backStuds + 1e-4)
				end
			end
		end
		-- beside, never on top of its player: sideStuds clears the footprint
		expect.truthy(P.sideStuds > P.halfWidthStuds + 1)
	end)

	t.test("on the deck: inside the throw area, and a little outside once there", function()
		local P = L.platform
		expect.equal(GearLooks.onDeck(MID, false), true)
		local outside = MID + Vector3.new(AREA.size.X / 2 + P.leaveStuds * 0.5, 0, 0)
		expect.equal(GearLooks.onDeck(outside, false), false)
		expect.equal(GearLooks.onDeck(outside, true), true)
		local far = MID + Vector3.new(AREA.size.X / 2 + P.leaveStuds + 0.5, 0, 0)
		expect.equal(GearLooks.onDeck(far, true), false)
	end)
end
