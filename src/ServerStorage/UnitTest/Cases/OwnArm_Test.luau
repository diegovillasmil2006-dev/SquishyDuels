--!strict
-- OwnArm_Test: unit tests for StarterPlayerScripts.Client.Anim.OwnArm (user decision 2026-10-11: the player's own avatar
-- arms in first person; spec phase1-arms §3). Server only (ServerStorage.UnitTest). Builds instances only (nothing is
-- put in the place):
--   * read: a whole R15 character gives both sides' parts and rest shapes, its Shirt and BodyColors; each fallback
--     reason (noCharacter, noHumanoid, notR15, missing, notMesh, hidden, noRig);
--   * layout: k = handWidthDu / Hand.Size.X, sizes × k·u; past the wrist one stretch factor so the upper arm's far end
--     reaches reachDu + its radius; no stretch for long arms; too much stretch or odd sizes → nil and the reason;
--   * partFrames: the hand's centre at H·u, the arm along shoulder - H (DesignArm's root), the palms facing the toy
--     (inward), the thumb side up; the roll about the arm; the caller's table reused;
--   * build: one model SD_OwnArms with a Humanoid (R15, no automatic scaling) and a Shirt copy (no BodyColors: the
--     copies keep the character's own colours), six anchored copies that never collide, touch, are queried or cast
--     shadows, LocalTransparencyModifier 0, no joints, attachments, cages or tags; the character untouched;
--   * signature changes with the arms' looks and the rig type, and not otherwise.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-4
local SKIN = Color3.fromRGB(234, 184, 146)

return function(t: Context)
	local OwnArm = t.requireClient("Anim/OwnArm")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local FP = Config.FirstPerson
	local OWN = FP.ownArms
	local U = FP.overlayStudsPerDu

	local function expectVector(actual: Vector3, wanted: Vector3, tolerance: number?)
		expect.near((actual - wanted).Magnitude, 0, tolerance or EPS)
	end

	-- A character with usable R15 arms (test sizes, not Roblox's): arms straight down, each part's Y along the arm.
	local function character(): Model
		local model = Instance.new("Model")
		model.Name = "Tester"
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15
		humanoid.Parent = model
		for _, side in { "Left", "Right" } do
			local function part(kind: string, size: Vector3, y: number): MeshPart
				local p = Instance.new("MeshPart")
				p.Name = side .. kind
				p.Size = size
				p.Color = SKIN
				p.CFrame = CFrame.new(if side == "Left" then -1.5 else 1.5, y, 0)
				p.Parent = model
				return p
			end
			local function rig(parent: Instance, name: string, y: number)
				local a = Instance.new("Attachment")
				a.Name = side .. name
				a.CFrame = CFrame.new(0, y, 0) -- (CFrame, not Position: the offline runner links only CFrame)
				a.Parent = parent
			end
			local hand = part("Hand", Vector3.new(1, 0.3, 1), 0.85)
			local lower = part("LowerArm", Vector3.new(1, 1.05, 1), 1.6)
			local upper = part("UpperArm", Vector3.new(1, 1.17, 1), 2.6)
			rig(hand, "WristRigAttachment", 0.125)
			rig(hand, "GripAttachment", -0.15)
			rig(lower, "WristRigAttachment", -0.5)
			rig(lower, "ElbowRigAttachment", 0.2)
			rig(upper, "ElbowRigAttachment", -0.33)
			rig(upper, "ShoulderRigAttachment", 0.42)
			local joint = Instance.new("Motor6D")
			joint.Name = side .. "Wrist"
			joint.Part0, joint.Part1 = lower, hand
			joint.Parent = hand
			Instance.new("WrapTarget").Parent = upper
			local value = Instance.new("Vector3Value")
			value.Name = "OriginalSize"
			value.Parent = lower
			hand:AddTag("SD_Test")
		end
		local shirt = Instance.new("Shirt")
		shirt.ShirtTemplate = "rbxassetid://1"
		shirt.Parent = model
		-- As on a real character, BodyColors holds the arms' colours (its defaults would repaint them).
		local colours = Instance.new("BodyColors")
		colours.LeftArmColor3, colours.RightArmColor3 = SKIN, SKIN
		colours.Parent = model
		return model
	end

	t.test("read: a whole R15 character; every fallback reason", function()
		local c = character()
		local source, why = OwnArm.read(c)
		expect.equal(why, nil)
		expect.truthy(source ~= nil)
		expect.equal(source.left.parts.hand, c:FindFirstChild("LeftHand"))
		expect.equal(source.right.parts.upper, c:FindFirstChild("RightUpperArm"))
		expect.equal(source.shirt, c:FindFirstChildOfClass("Shirt"))
		expect.equal(source.bodyColors, c:FindFirstChildOfClass("BodyColors"))
		expectVector(source.right.shape.wristHand.Position, Vector3.new(0, 0.125, 0))
		expectVector(source.right.shape.shoulderUpper.Position, Vector3.new(0, 0.42, 0))
		expectVector(source.left.shape.lower, Vector3.new(1, 1.05, 1))
		local none, noneWhy = OwnArm.read(nil)
		expect.equal(none, nil)
		expect.equal(noneWhy, "noCharacter")
		local cases: { { any } } = {
			{
				"noHumanoid",
				function(m)
					(m:FindFirstChildOfClass("Humanoid") :: Humanoid):Destroy()
				end,
			},
			{
				"notR15",
				function(m)
					(m:FindFirstChildOfClass("Humanoid") :: Humanoid).RigType = Enum.HumanoidRigType.R6
				end,
			},
			{
				"missing:LeftHand",
				function(m)
					(m:FindFirstChild("LeftHand") :: Instance):Destroy()
				end,
			},
			{
				"notMesh:RightLowerArm",
				function(m)
					local old = m:FindFirstChild("RightLowerArm") :: BasePart
					old.Name = "Old"
					local block = Instance.new("Part")
					block.Name = "RightLowerArm"
					block.Parent = m
				end,
			},
			{
				"hidden:RightUpperArm",
				function(m)
					(m:FindFirstChild("RightUpperArm") :: BasePart).Transparency = 1
				end,
			},
			{
				"noRig:LeftUpperArm.LeftShoulderRigAttachment",
				function(m)
					(
						(m:FindFirstChild("LeftUpperArm") :: Instance):FindFirstChild(
							"LeftShoulderRigAttachment"
						) :: Instance
					):Destroy()
				end,
			},
		}
		for _, case in cases do
			local broken = character()
			case[2](broken)
			local none, reason = OwnArm.read(broken)
			expect.equal(none, nil)
			expect.equal(reason, case[1])
			broken:Destroy()
		end
		c:Destroy()
	end)

	t.test("layout: the hand as wide as the design's; past the wrist, one stretch to reachDu + radius", function()
		local c = character()
		local source = OwnArm.read(c)
		local shape = source.right.shape
		local layout, why = OwnArm.layout(shape, 1, U)
		expect.equal(why, nil)
		local k = OWN.handWidthDu / 1 -- Hand.Size.X = 1
		expect.near(layout.k, k, 1e-9)
		expect.near(OWN.handWidthDu, FP.arm.parts[1].size.X, 1e-6) -- the design hand's width (fp.js:67)
		expectVector(layout.sizes.hand, Vector3.new(1, 0.3, 1) * k * U)
		local f = layout.stretch
		expect.truthy(f > 1 and f <= OWN.maxStretch)
		-- Only the length (Y) stretches; the thickness stays.
		expectVector(layout.sizes.lower, Vector3.new(1, 1.05 * f, 1) * k * U)
		expectVector(layout.sizes.upper, Vector3.new(1, 1.17 * f, 1) * k * U)
		-- The hand's centre is the frame's origin; the upper arm's far end at reachDu + its radius (du) along the arm.
		expectVector(layout.rel.hand.Position, Vector3.zero)
		local upper = layout.rel.upper
		local farDu = (upper.Position.Z + layout.sizes.upper.Y / 2) / U -- the arm runs along the design frame's +Z
		expect.near(farDu, OWN.reachDu + 0.5 * math.sqrt(2) * k, 1e-4)
		-- The stretch is about the wrist (y 0.125 in the hand): the lower arm's near end (rest y 0.1: its centre at
		-- 0.125 + 0.5, half its 1.05 below) moves to 0.125 + (0.1 - 0.125)·f.
		local nearDu = (layout.rel.lower.Position.Z - layout.sizes.lower.Y / 2) / U
		expect.near(nearDu, (0.125 + (0.1 - 0.125) * f) * k, 1e-4)
		-- Long arms need no stretch.
		local long = table.clone(shape)
		long.upper = Vector3.new(1, 9, 1)
		long.elbowUpper = CFrame.new(0, -4.4, 0)
		long.shoulderUpper = CFrame.new(0, 4.4, 0)
		local longLayout = OwnArm.layout(long, 1, U)
		expect.equal(longLayout.stretch, 1)
		-- Odd shapes fall back.
		local tiny = table.clone(shape)
		tiny.upper = Vector3.new(1, 0.4, 1)
		tiny.elbowUpper = CFrame.new(0, -0.1, 0)
		tiny.shoulderUpper = CFrame.new(0, 0.1, 0)
		tiny.lower = Vector3.new(1, 0.3, 1)
		tiny.wristLower = CFrame.new(0, -0.1, 0)
		tiny.elbowLower = CFrame.new(0, 0.1, 0)
		expect.equal(select(2, OwnArm.layout(tiny, 1, U)), "odd:stretch")
		local thin = table.clone(shape)
		thin.hand = Vector3.new(1, 0.01, 1)
		expect.equal(select(2, OwnArm.layout(thin, 1, U)), "odd:thin:Hand")
		local wide = table.clone(shape)
		wide.lower = Vector3.new(3, 1.05, 3)
		expect.equal(select(2, OwnArm.layout(wide, 1, U)), "odd:wide:LowerArm")
		c:Destroy()
	end)

	t.test("partFrames: the hand at H, the arm toward the shoulder, palms inward, thumb side up, rolled", function()
		local c = character()
		local arms = OwnArm.build(OwnArm.read(c), nil, U)
		local shoulder = FP.shoulder
		for _, side in { -1, 1 } do
			local arm = if side < 0 then arms.left else arms.right
			local hand = Vector3.new(0.12 * side, -0.165, -0.465)
			local s = Vector3.new(shoulder.X * side, shoulder.Y, shoulder.Z)
			local frames = OwnArm.partFrames(arm, hand, s, 0, U, {})
			local name = if side < 0 then "Left" else "Right"
			local h = frames[name .. "Hand"]
			expectVector(h.Position, hand * U)
			-- The arm (the hand's +Y, toward the shoulder in the rest pose) points at the shoulder.
			local z = (s - hand).Unit
			expectVector(h.YVector, z)
			local upperAt = frames[name .. "UpperArm"].Position / U
			expect.near(((upperAt - hand):Cross(z)).Magnitude, 0, 1e-4)
			-- The palm (R15: the right hand's -X, the left's +X) faces the toy (toward x = 0); the thumb side (-Z) up.
			local palm = if side > 0 then -h.XVector else h.XVector
			expect.truthy(palm.X * side < 0)
			expect.truthy(-h.ZVector.Y > 0.5)
			-- The roll turns about the arm.
			local rolled = OwnArm.partFrames(arm, hand, s, 0.4, U, {})[name .. "Hand"]
			expectVector(rolled.YVector, z)
			expect.near(rolled.XVector:Dot(h.XVector), math.cos(0.4), 1e-4)
		end
		local out: { [string]: CFrame } = {}
		expect.equal(OwnArm.partFrames(arms.right, Vector3.new(0.12, -0.165, -0.465), shoulder, 0, U, out), out)
		local keys = 0
		for _ in out do
			keys += 1
		end
		expect.equal(keys, 3)
		OwnArm.destroy(arms)
		c:Destroy()
	end)

	t.test(
		"build: one model with a Humanoid and the Shirt (no BodyColors); six clean copies; the character untouched",
		function()
			local c = character()
			local before: { [Instance]: string } = {}
			for _, d in c:GetDescendants() do
				before[d] = if d:IsA("BasePart")
					then `{d.Parent}|{d.CFrame}|{d.Size}|{d.LocalTransparencyModifier}|{#d:GetChildren()}`
					else tostring(d.Parent)
			end
			local count = #c:GetDescendants()
			local folder = Instance.new("Folder")
			local arms, why = OwnArm.build(OwnArm.read(c), folder, U)
			expect.equal(why, nil)
			local model = arms.model
			expect.equal(model.Name, OwnArm.MODEL_NAME)
			expect.equal(model.Parent, folder)
			local found = model:FindFirstChildOfClass("Humanoid")
			expect.truthy(found ~= nil)
			local humanoid = found :: Humanoid
			expect.equal(humanoid.RigType, Enum.HumanoidRigType.R15)
			expect.falsy(humanoid.AutomaticScalingEnabled)
			expect.equal(humanoid.DisplayDistanceType, Enum.HumanoidDisplayDistanceType.None)
			expect.equal((model:FindFirstChildOfClass("Shirt") :: Shirt).ShirtTemplate, "rbxassetid://1")
			expect.equal(model:FindFirstChildOfClass("BodyColors"), nil) -- the copies keep their own colours
			local parts = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					expect.truthy(d.Anchored)
					expect.falsy(d.CanCollide)
					expect.falsy(d.CanTouch)
					expect.falsy(d.CanQuery)
					expect.falsy(d.CastShadow)
					expect.equal(d.LocalTransparencyModifier, 0)
					expect.equal(#d:GetChildren(), 0) -- no joints, attachments, cages or values
					expect.equal(#d:GetTags(), 0)
					expect.equal(d.Color, SKIN)
				end
			end
			expect.equal(parts, 6)
			expect.equal(arms.right.hand, model:FindFirstChild("RightHand"))
			expect.equal(arms.left.parts.LeftUpperArm, model:FindFirstChild("LeftUpperArm"))
			-- The character is only read.
			expect.equal(#c:GetDescendants(), count)
			for _, d in c:GetDescendants() do
				local now = if d:IsA("BasePart")
					then `{d.Parent}|{d.CFrame}|{d.Size}|{d.LocalTransparencyModifier}|{#d:GetChildren()}`
					else tostring(d.Parent)
				expect.equal(now, before[d])
			end
			expect.truthy((c:FindFirstChild("RightHand") :: Instance):HasTag("SD_Test"))
			OwnArm.destroy(arms)
			expect.equal(model.Parent, nil)
			folder:Destroy()
			c:Destroy()
		end
	)

	t.test("signature: changes with the arms' looks and the rig type, not otherwise", function()
		local c = character()
		local first = OwnArm.signature(c)
		expect.equal(OwnArm.signature(c), first)
		expect.equal(OwnArm.signature(nil), "none")
		local hand = c:FindFirstChild("RightHand") :: BasePart
		hand.CFrame = CFrame.new(5, 5, 5) -- moving is not a change
		expect.equal(OwnArm.signature(c), first)
		hand.Color = Color3.fromRGB(90, 60, 40)
		local second = OwnArm.signature(c)
		expect.truthy(second ~= first)
		hand.Size = Vector3.new(1.2, 0.3, 1.2)
		expect.truthy(OwnArm.signature(c) ~= second)
		local third = OwnArm.signature(c);
		(c:FindFirstChildOfClass("Shirt") :: Shirt).ShirtTemplate = "rbxassetid://2"
		expect.truthy(OwnArm.signature(c) ~= third)
		local fourth = OwnArm.signature(c);
		(c:FindFirstChildOfClass("Humanoid") :: Humanoid).RigType = Enum.HumanoidRigType.R6
		expect.truthy(OwnArm.signature(c) ~= fourth)
		c:Destroy()
	end)
end
