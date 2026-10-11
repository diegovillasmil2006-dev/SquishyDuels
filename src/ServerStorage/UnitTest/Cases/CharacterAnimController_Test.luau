--!strict
-- CharacterAnimController_Test: unit tests for StarterPlayerScripts.Client.Controllers.CharacterAnimController (the
-- hold arm layer). Server only (ServerStorage.UnitTest). Edit mode: init() is not called, no Players; the character is
-- hand-made in memory and its Anim/JointLayer is stepped by hand.
-- Contract (DESIGN §9.4, §9.5; spec 2026-10-11 §4):
--   * the hold pose is on while the player holds a squishy and off otherwise;
--   * it is the design's HOLD as an override at full weight: whatever the Animator writes (the walk swing), the right
--     arm shows exactly the hold pose, so it holds still; a throw pose (a higher priority) wins over it and the left
--     arm keeps its own animation;
--   * a squeeze never moves the arms (no squeeze layer, no squeezeTwoHand pose).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local TOLERANCE = 1e-5

local function rad(x: number, y: number, z: number): CFrame
	return CFrame.fromEulerAnglesYXZ(math.rad(x), math.rad(y), math.rad(z))
end

return function(t: Context)
	local CharacterAnimController = t.requireClient("Controllers/CharacterAnimController")
	local JointLayer = t.requireClient("Anim/JointLayer")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local poses = Config.Anim.poses

	local function expectCFrame(actual: CFrame, wanted: CFrame, label: string)
		local worst = math.max(
			(actual.Position - wanted.Position).Magnitude,
			(actual.XVector - wanted.XVector).Magnitude,
			(actual.YVector - wanted.YVector).Magnitude,
			(actual.ZVector - wanted.ZVector).Magnitude
		)
		if worst > TOLERANCE then
			error(`{label}: expected {wanted}, got {actual}`, 2)
		end
	end

	-- An R15-shaped character with every joint of Config.Anim.joints.R15 (Motor6Ds) and a Humanoid.
	local function makeCharacter(): Model
		local character = Instance.new("Model")
		character.Name = "TestRig"
		for _, path in Config.Anim.joints.R15 do
			local part = character:FindFirstChild(path[1])
			if part == nil then
				local created = Instance.new("Part")
				created.Name = path[1]
				created.Anchored = true
				created.Parent = character
				part = created
			end
			local joint = Instance.new("Motor6D")
			joint.Name = path[2]
			joint.Parent = part
		end
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15
		humanoid.Parent = character
		return character
	end

	local function joint(character: Model, logical: string): Motor6D
		local path = Config.Anim.joints.R15[logical]
		return (character:FindFirstChild(path[1]) :: Instance):FindFirstChild(path[2]) :: Motor6D
	end

	local function deg(pose: string, logical: string): CFrame
		local d: Vector3 = poses[pose].R15[logical]
		return rad(d.X, d.Y, d.Z)
	end

	local function setup(): (Model, any)
		local character = makeCharacter()
		return character, JointLayer.new(character, { autoStep = false, cullStuds = math.huge })
	end

	t.test("holding adds the hold pose at full weight; not holding removes it", function()
		local character, layer = setup()
		CharacterAnimController.updateHoldLayer(layer, true)
		layer:step(1 / 60, 0)
		expectCFrame(joint(character, "RightShoulder").Transform, deg("hold", "RightShoulder"), "hold shoulder")
		expectCFrame(joint(character, "RightElbow").Transform, deg("hold", "RightElbow"), "hold elbow")
		CharacterAnimController.updateHoldLayer(layer, false)
		expect.falsy(layer:has("hold"))
		layer:step(1 / 60, 0)
		expect.equal(joint(character, "RightShoulder").Transform, CFrame.identity)
		layer:destroy()
		character:Destroy()
	end)

	t.test("the holding arm stays still: the Animator's walk swing never shows through the hold", function()
		local character, layer = setup()
		for _, swing in { 25, -25, 10 } do
			-- The Animator writes a walk swing on the right arm each frame; the hold replaces it.
			joint(character, "RightShoulder").Transform = rad(swing, 0, 4)
			joint(character, "RightElbow").Transform = rad(swing / 2, 0, 0)
			CharacterAnimController.updateHoldLayer(layer, true)
			layer:step(1 / 60, 0)
			for _, logical in { "RightShoulder", "RightElbow", "RightWrist" } do
				expectCFrame(joint(character, logical).Transform, deg("hold", logical), `{logical} at swing {swing}`)
			end
			expect.near(layer:getWeight("hold"), 1, 1e-9)
		end
		layer:destroy()
		character:Destroy()
	end)

	t.test("a throw pose wins over the hold; the left arm keeps its own animation", function()
		local character, layer = setup()
		joint(character, "LeftShoulder").Transform = rad(-20, 0, -5) -- the Animator's left arm
		-- Transform is stored in single precision: "kept" means bit for bit the value the joint holds.
		local left = joint(character, "LeftShoulder").Transform
		CharacterAnimController.updateHoldLayer(layer, true)
		layer:setPose("throw", "throwWindup", 1)
		layer:step(1 / 60, 0)
		for _, logical in { "RightShoulder", "RightElbow", "RightWrist" } do
			expectCFrame(joint(character, logical).Transform, deg("throwWindup", logical), logical)
		end
		expect.equal(joint(character, "LeftShoulder").Transform, left)
		layer:destroy()
		character:Destroy()
	end)

	t.test("the squeeze no longer moves the arms: no squeeze layer API is left", function()
		expect.equal(CharacterAnimController.setSqueezeWeight, nil)
		expect.equal(Config.Anim.poses.squeezeTwoHand, nil)
	end)
end
