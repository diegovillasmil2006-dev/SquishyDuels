--!strict
-- JointLayer_Test: unit tests for StarterPlayerScripts.Client.Anim.JointLayer and Anim.PoseLibrary. Server only
-- (ServerStorage.UnitTest). Characters are hand-made in memory (no Players, no Play mode) and stepped by hand.
-- Contract (DESIGN §9.4, §9.16):
--   * joints found by name from Config.Anim.joints, AnimationConstraint or Motor6D accepted; re-resolved when replaced;
--   * write-guard: our offset is never stacked on our own output; a fresh Animator value becomes the new base;
--   * overrides lerp toward the pose by weight (higher priority wins), additive layers multiply
--     fromEulerAnglesYXZ(angles·w); dizzy sways one joint; flinch is a spring that settles and removes itself;
--   * weights blend (duel end: all to 0); with no layer left the base is put back once;
--   * no Humanoid/joints within the wait → one warning and the layer is disabled; destroy() restores the joints.
-- Poses: PoseLibrary converts Config.Anim.poses degrees (joint space) to radians/CFrames per rig.

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
	local JointLayer = t.requireClient("Anim/JointLayer")
	local PoseLibrary = t.requireClient("Anim/PoseLibrary")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local function expectCFrame(actual: CFrame, wanted: CFrame, label: string?)
		local worst = math.max(
			(actual.Position - wanted.Position).Magnitude,
			(actual.XVector - wanted.XVector).Magnitude,
			(actual.YVector - wanted.YVector).Magnitude,
			(actual.ZVector - wanted.ZVector).Magnitude
		)
		if worst > TOLERANCE then
			error(`{label or "CFrame"}: expected {wanted}, got {actual}`, 2)
		end
	end

	-- An R15-shaped character: every joint of Config.Anim.joints.R15, RightShoulder as an AnimationConstraint (the AJU
	-- class) and the others as Motor6Ds.
	local function makeCharacter(withHumanoid: boolean): Model
		local character = Instance.new("Model")
		character.Name = "TestRig"
		for name, path in Config.Anim.joints.R15 do
			local part = character:FindFirstChild(path[1])
			if part == nil then
				local created = Instance.new("Part")
				created.Name = path[1]
				created.Anchored = true
				created.Parent = character
				part = created
			end
			local joint: Instance = if name == "RightShoulder"
				then Instance.new("AnimationConstraint")
				else Instance.new("Motor6D")
			joint.Name = path[2]
			joint.Parent = part
		end
		if withHumanoid then
			local humanoid = Instance.new("Humanoid")
			humanoid.RigType = Enum.HumanoidRigType.R15
			humanoid.Parent = character
		end
		return character
	end

	local function joint(character: Model, logical: string): any
		local path = Config.Anim.joints.R15[logical]
		return (character:FindFirstChild(path[1]) :: Instance):FindFirstChild(path[2])
	end

	local function newLayer(character: Model): any
		return JointLayer.new(character, { autoStep = false, cullStuds = math.huge })
	end

	-- A pose's R15 joint as a joint-space CFrame, from Config.Anim.poses (hold: an override; dizzy: an additive).
	local function poseCF(name: string, logical: string): CFrame
		local degrees: Vector3 = Config.Anim.poses[name].R15[logical]
		return rad(degrees.X, degrees.Y, degrees.Z)
	end

	-- PoseLibrary ----------------------------------------------------------------------------------------------

	t.test("PoseLibrary converts every Config pose to radians and joint-space CFrames per rig", function()
		for _, name in PoseLibrary.names() do
			local pose = Config.Anim.poses[name]
			for _, rig in { "R15", "R6" } do
				local angles = PoseLibrary.angles(name, rig)
				local frames = PoseLibrary.cframes(name, rig)
				for jointName, degrees in pose[rig] do
					expect.near(angles[jointName].X, math.rad(degrees.X), 1e-6)
					expect.near(angles[jointName].Z, math.rad(degrees.Z), 1e-6)
					expectCFrame(frames[jointName], rad(degrees.X, degrees.Y, degrees.Z), `{name}.{rig}.{jointName}`)
				end
			end
		end
		for _, required in { "hold", "throwWindup", "throwRelease", "throwFollow", "ultCharge" } do
			expect.truthy(PoseLibrary.has(required))
		end
		for _, required in { "cheer", "shrug", "dizzy", "flinch" } do
			expect.truthy(PoseLibrary.has(required))
		end
		expect.throws(function()
			PoseLibrary.angles("noSuchPose", "R15")
		end, "unknown pose")
	end)

	-- Resolution -------------------------------------------------------------------------------------------------

	t.test("finds every R15 joint by name, AnimationConstraint or Motor6D", function()
		local character = makeCharacter(true)
		local layer = newLayer(character)
		expect.truthy(layer:isReady())
		expect.equal(layer:getRig(), "R15")
		layer:setPose("hold", "hold", 1)
		layer:step(1 / 60, 0)
		expectCFrame(
			joint(character, "RightShoulder").Transform,
			poseCF("hold", "RightShoulder"),
			"RightShoulder (AnimationConstraint)"
		)
		expectCFrame(joint(character, "RightElbow").Transform, poseCF("hold", "RightElbow"), "RightElbow (Motor6D)")
		layer:destroy()
		character:Destroy()
	end)

	-- Write-guard and composition --------------------------------------------------------------------------------

	t.test("write-guard: an additive offset is never stacked on our own output", function()
		local character = makeCharacter(true)
		local layer = newLayer(character)
		layer:setPose("dizzy", "dizzy", 1)
		for _ = 1, 5 do
			layer:step(1 / 60, 0)
		end
		local shoulder = joint(character, "RightShoulder")
		expectCFrame(shoulder.Transform, poseCF("dizzy", "RightShoulder"))
		-- The Animator writes a new value: it becomes the base.
		local animated = CFrame.new(0, 0.5, 0) * rad(0, 30, 0)
		shoulder.Transform = animated
		layer:step(1 / 60, 0)
		layer:step(1 / 60, 0)
		expectCFrame(shoulder.Transform, animated * poseCF("dizzy", "RightShoulder"))
		layer:destroy()
		character:Destroy()
	end)

	t.test("overrides lerp by weight in priority order, then additive layers apply", function()
		local character = makeCharacter(true)
		local layer = newLayer(character)
		local shoulder = joint(character, "RightShoulder")
		local base = CFrame.new(0, 0.2, 0)
		shoulder.Transform = base
		layer:setPose("windup", "throwWindup", 0.5) -- priority 2
		layer:setPose("hold", "hold", 1) -- priority 1, applied first
		layer:step(1 / 60, 0)
		local wanted = base:Lerp(poseCF("hold", "RightShoulder"), 1):Lerp(rad(155, 0, -15), 0.5)
		expectCFrame(shoulder.Transform, wanted, "priority order")
		layer:setWeight("windup", 1)
		layer:setPose("dizzy", "dizzy", 1)
		layer:step(1 / 60, 0)
		expectCFrame(shoulder.Transform, rad(155, 0, -15) * poseCF("dizzy", "RightShoulder"), "override then additive")
		layer:destroy()
		character:Destroy()
	end)

	t.test("with no layer left the base is put back once, then the joint is left alone", function()
		local character = makeCharacter(true)
		local layer = newLayer(character)
		local neck = joint(character, "Neck")
		local base = rad(5, 0, 0)
		neck.Transform = base
		-- Roblox stores Transform in single precision, so compare against the value it actually holds:
		-- "put back" means bit-for-bit what the joint had before the layer touched it.
		local stored = neck.Transform
		layer:setPose("dizzy", "dizzy", 1)
		layer:step(1 / 60, 0)
		expectCFrame(neck.Transform, base * rad(0, 0, 15))
		layer:clear("dizzy")
		layer:step(1 / 60, 0)
		expect.equal(neck.Transform, stored)
		neck.Transform = CFrame.new(1, 2, 3)
		layer:step(1 / 60, 0)
		expect.equal(neck.Transform, CFrame.new(1, 2, 3))
		layer:destroy()
		character:Destroy()
	end)

	t.test("dizzy sways the Root joint about Z at the configured amplitude and rate", function()
		local character = makeCharacter(true)
		local layer = newLayer(character)
		local sway = Config.Anim.poses.dizzy.sway
		layer:setPose("dizzy", "dizzy", 1)
		layer:step(1 / 60, 10) -- the sway starts here (sin 0 = 0)
		expectCFrame(joint(character, "Root").Transform, CFrame.identity, "start")
		layer:step(1 / 60, 10 + 1 / (4 * sway.hz)) -- a quarter period later: the peak
		expectCFrame(joint(character, "Root").Transform, rad(0, 0, sway.amplitudeDeg), "peak")
		layer:destroy()
		character:Destroy()
	end)

	-- Weights, springs, lifecycle -------------------------------------------------------------------------------

	t.test("flinch kick springs back to 0, removes itself and restores the base", function()
		local character = makeCharacter(true)
		local layer = newLayer(character)
		local waist = joint(character, "Waist")
		layer:kick("flinch", "flinch")
		expect.equal(layer:getWeight("flinch"), 1)
		layer:step(1 / 60, 0)
		local first = layer:getWeight("flinch")
		expect.truthy(first ~= nil and first < 1)
		for _ = 1, 120 do
			layer:step(1 / 60, 0)
		end
		expect.falsy(layer:has("flinch"))
		layer:step(1 / 60, 0)
		expect.equal(waist.Transform, CFrame.identity)
		layer:destroy()
		character:Destroy()
	end)

	t.test("blendAll takes every weight to 0 over the duel-end blend", function()
		local character = makeCharacter(true)
		local layer = newLayer(character)
		layer:setPose("hold", "hold", 1)
		layer:setPose("cheer", "cheer", 1)
		local seconds = Config.Anim.joints.duelEndBlendMs / 1000
		layer:blendAll(0, seconds)
		layer:step(seconds / 2, 0)
		expect.near(layer:getWeight("hold"), 0.5, 1e-6)
		layer:step(seconds / 2, 0)
		expect.near(layer:getWeight("hold"), 0, 1e-9)
		expect.near(layer:getWeight("cheer"), 0, 1e-9)
		layer:blendAll(0, seconds, true)
		layer:step(seconds, 0)
		expect.falsy(layer:has("hold"))
		layer:destroy()
		character:Destroy()
	end)

	t.test("a replaced joint is found again by name", function()
		local character = makeCharacter(true)
		local layer = newLayer(character)
		layer:setPose("hold", "hold", 1)
		layer:step(1 / 60, 0)
		local old = joint(character, "RightElbow")
		local parent = old.Parent
		old:Destroy()
		local replacement = Instance.new("Motor6D")
		replacement.Name = "RightElbow"
		replacement.Parent = parent
		layer:step(1 / 60, 0)
		expectCFrame(replacement.Transform, poseCF("hold", "RightElbow"))
		layer:destroy()
		character:Destroy()
	end)

	t.test("destroy puts every joint's base back and stops the layer", function()
		local character = makeCharacter(true)
		local layer = newLayer(character)
		layer:setPose("cheer", "cheer", 1)
		layer:step(1 / 60, 0)
		layer:destroy()
		expect.equal(joint(character, "RightShoulder").Transform, CFrame.identity)
		expect.equal(joint(character, "LeftShoulder").Transform, CFrame.identity)
		expect.falsy(layer:step(1 / 60, 0))
		character:Destroy()
	end)

	t.test("without a Humanoid the layer waits, then disables itself", function()
		local character = makeCharacter(false)
		local layer = JointLayer.new(character, { autoStep = false, cullStuds = math.huge, waitSeconds = 0.05 })
		expect.falsy(layer:isReady())
		expect.truthy(layer:step(1 / 60, 0)) -- still waiting
		task.wait(0.2)
		expect.truthy(layer:isDisabled())
		expect.falsy(layer:step(1 / 60, 0))
		layer:destroy()
		character:Destroy()
	end)
end
