--!strict
-- DesignArm_Test: unit tests for StarterPlayerScripts.Client.Anim.DesignArm (spec 2026-10-11 §3.2). Server only
-- (ServerStorage.UnitTest). Builds parts only (nothing is put in the place):
--   * new(side, parent) builds one arm "SD_Arm_L" / "SD_Arm_R" of the five Config.FirstPerson.arm parts (hand, thumb,
--     forearm, cuff, sleeve), each named so and sized size × studsPerDu, anchored, never colliding, touching or queried,
--     no shadow, SmoothPlastic, in the design's colours (skin, cuff, sleeve); setColours repaints the sleeve;
--   * with SuperMesh's mesh path each part has its outline hull "<part>_outline" (toon.js:53), sized (size + 2t) ×
--     studsPerDu with t = OUTLINE_DU (3 px at 1080 rows and the hold depth, about 0.0018 du), #1B1220; without the mesh
--     path there is no hull (offline there never is);
--   * partFrames is the design's arm frame (fp.js:76): root at the hand point, +Z aimed at the shoulder, X = up × Z
--     (three.js lookAt), rolled about Z; each part at its offset along that frame (× studsPerDu), the thumb's X offset
--     and yaw × side, into the caller's table; apply writes the frames to the parts and their hulls.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-4

return function(t: Context)
	local DesignArm = t.requireClient("Anim/DesignArm")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local FP = Config.FirstPerson
	local U = FP.overlayStudsPerDu

	local function expectColor(actual: Color3, wanted: Color3)
		expect.near(actual.R, wanted.R, 1 / 255)
		expect.near(actual.G, wanted.G, 1 / 255)
		expect.near(actual.B, wanted.B, 1 / 255)
	end

	local function expectVector(actual: Vector3, wanted: Vector3, tolerance: number?)
		expect.near((actual - wanted).Magnitude, 0, tolerance or EPS)
	end

	t.test("new(side, parent): the five design parts, sized × studsPerDu, in the design's colours", function()
		expect.deepEqual(DesignArm.PARTS, { "hand", "thumb", "forearm", "cuff", "sleeve" })
		local folder = Instance.new("Folder")
		for _, side in { -1, 1 } do
			local arm = DesignArm.new(side, folder)
			expect.equal(arm.side, side)
			expect.equal(arm.model.Parent, folder)
			expect.equal(arm.model.Name, if side < 0 then "SD_Arm_L" else "SD_Arm_R")
			for _, row in FP.arm.parts do
				local part = arm.parts[row.name]
				expect.truthy(part ~= nil and part:IsA("BasePart"))
				expect.equal(part.Name, row.name)
				expect.equal(part.Parent, arm.model)
				expectVector(part.Size, row.size * U)
				expect.truthy(part.Anchored)
				expect.falsy(part.CanCollide)
				expect.falsy(part.CanTouch)
				expect.falsy(part.CanQuery)
				expect.falsy(part.CastShadow)
				expect.equal(part.Material, Enum.Material.SmoothPlastic)
				expectColor(part.Color, FP.colours[row.colour])
			end
			DesignArm.setColours(arm, FP.teamSleeves.A)
			expectColor(arm.parts.sleeve.Color, FP.teamSleeves.A)
			expectColor(arm.parts.hand.Color, FP.colours.skin)
			DesignArm.destroy(arm)
			expect.equal(arm.model.Parent, nil)
		end
		folder:Destroy()
	end)

	t.test(
		"partFrames: +Z at the shoulder, X = up × Z, rolled about Z; parts along the arm, the thumb mirrored",
		function()
			local hand, shoulder = Vector3.new(0.16, -0.165, -0.465), FP.shoulder
			local frames = DesignArm.partFrames(hand, shoulder, 0, 1, U, {})
			local root = frames.hand
			local z = (shoulder - hand).Unit
			expectVector(root.Position, hand * U)
			expectVector(root.ZVector, z)
			expectVector(root.XVector, Vector3.new(0, 1, 0):Cross(z).Unit)
			expectVector(frames.forearm.Position, (hand + z * 0.2) * U)
			expectVector(frames.cuff.Position, (hand + z * 0.35) * U)
			expectVector(frames.sleeve.Position, (hand + z * 0.57) * U)
			-- The thumb: (-side · 0.047, 0.026, -0.02) in the arm frame, yawed side · 0.35 (fp.js:70).
			local right = frames.thumb
			expectVector(root:PointToObjectSpace(right.Position), Vector3.new(-0.047, 0.026, -0.02) * U)
			local yaw = select(2, (root:ToObjectSpace(right)):ToEulerAnglesXYZ())
			expect.near(yaw, 0.35, 1e-4)
			local leftShoulder = Vector3.new(-shoulder.X, shoulder.Y, shoulder.Z)
			local leftHand = Vector3.new(-hand.X, hand.Y, hand.Z)
			local left = DesignArm.partFrames(leftHand, leftShoulder, 0, -1, U, {})
			expectVector(left.hand:PointToObjectSpace(left.thumb.Position), Vector3.new(0.047, 0.026, -0.02) * U)
			expect.near(select(2, (left.hand:ToObjectSpace(left.thumb)):ToEulerAnglesXYZ()), -0.35, 1e-4)
			-- The roll turns the frame about its own Z (the arm's axis stays on the shoulder).
			local rolled = DesignArm.partFrames(hand, shoulder, 0.4, 1, U, {})
			expectVector(rolled.hand.ZVector, z)
			expectVector(rolled.hand.XVector, (root * CFrame.Angles(0, 0, 0.4)).XVector)
			-- The out table is filled in place and returned: the same table every frame, only the five names.
			local out: { [string]: CFrame } = {}
			expect.equal(DesignArm.partFrames(hand, shoulder, 0, 1, U, out), out)
			expect.equal(DesignArm.partFrames(hand, shoulder, 0.4, 1, U, out), out)
			local keys = 0
			for name in out do
				keys += 1
				expect.truthy(table.find(DesignArm.PARTS, name) ~= nil)
			end
			expect.equal(keys, #DesignArm.PARTS)
			expectVector(out.hand.XVector, rolled.hand.XVector)
		end
	)

	t.test("OUTLINE_DU: 3 px at 1080 rows at the hold depth (vertical FOV 70), about 0.0018 du", function()
		local outline = FP.outline
		local wanted = outline.px * 2 * outline.refDepthDu * math.tan(math.rad(FP.fovDeg) / 2) / outline.refHeightPx
		expect.near(DesignArm.OUTLINE_DU, wanted, 1e-12)
		expect.near(DesignArm.OUTLINE_DU, 0.0018, 0.00005)
	end)

	t.test("new: with the mesh path an outline hull per part, (size + 2t) × u, #1B1220; without it none", function()
		local SuperMesh = t.requireClient("Anim/SuperMesh")
		local ready = SuperMesh.prepare()
		local arm = DesignArm.new(-1)
		local t2 = 2 * DesignArm.OUTLINE_DU
		for _, row in FP.arm.parts do
			local hull = arm.hulls[row.name]
			if not ready then
				expect.equal(hull, nil)
			else
				expect.truthy(hull ~= nil and hull:IsA("MeshPart"))
				expect.equal(hull.Name, row.name .. "_outline")
				expect.equal(hull.Parent, arm.model)
				expectVector(hull.Size, (row.size + Vector3.one * t2) * U)
				expectColor(hull.Color, FP.outline.colour)
				expect.falsy(hull.CastShadow)
				expect.falsy(hull.CanQuery)
			end
		end
		DesignArm.destroy(arm)
	end)

	t.test("apply writes each part's frame, and its hull's", function()
		local arm = DesignArm.new(1)
		local hull = Instance.new("Part")
		hull.Parent = arm.model
		arm.hulls.forearm = hull
		local frames = DesignArm.partFrames(Vector3.new(0.16, -0.23, -0.46), FP.shoulder, -0.4, 1, U, {})
		DesignArm.apply(arm, frames)
		for _, name in DesignArm.PARTS do
			expectVector(arm.parts[name].CFrame.Position, frames[name].Position)
			expectVector(arm.parts[name].CFrame.ZVector, frames[name].ZVector)
		end
		expectVector(hull.CFrame.Position, frames.forearm.Position)
		expectVector(hull.CFrame.ZVector, frames.forearm.ZVector)
		DesignArm.destroy(arm)
	end)
end
