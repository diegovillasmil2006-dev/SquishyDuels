--!strict
-- OwnArm (client only): the local player's own avatar arms in the first-person overlay (user decision 2026-10-11: each
-- player's own full avatar arms, their skin, shirt sleeves and body shape, in the design's hold, squeeze and throw
-- motions; spec phase1-arms §3). ViewmodelController uses them first and falls back to Anim/DesignArm.
--
-- The overlay's motion code hands each arm a hand point H, its shoulder anchor and a roll (du; design: fp.js:73-76).
-- DesignArm turns those into the design's five rounded blocks; OwnArm into copies of the character's <S>Hand,
-- <S>LowerArm and <S>UpperArm (S = Left / Right):
--   * the arm frame A, in Hand space from the R15 rest pose of the rig attachments (Part0 · att0 = Part1 · att1): the
--     origin at the hand's centre (the design's H is its hand block's centre, fp.js:70), +Y toward the shoulder joint,
--     +X the hand's X made square to it. A's +Y is the design arm's +Z (toward its shoulder) and A's +X its +X
--     (TO_DESIGN): the palms face the toy, where the design's thumbs sit (fp.js:70), and the thumb side points up;
--   * the scale k = ownArms.handWidthDu / Hand.Size.X (du per avatar stud): the hand is as wide as the design's (0.1 du,
--     fp.js:67), so its palm lands on the toy's side as the design hand's does (held.sideGap = half its width);
--   * the reach: the design's poses keep up to 0.42 du + the arm's radius on screen (spec phase1-arms §1.9). Everything
--     past the wrist stretches along the arm by one factor f >= 1 (sizes and places) until the upper arm's far end is
--     reachDu + its radius from the hand's centre, so an arm's end never shows;
--   * each frame a part goes to DesignArm's root, CFrame.lookAt(H, shoulder) · Angles(0, π, 0) · Angles(0, 0, roll),
--     times its rest frame in the design arm frame (Layout.rel; ownArms.palmRoll turns it about the arm, × side).
-- Clothing: the six copies keep their R15 names in one Model "SD_OwnArms" with its own Humanoid (R15, no automatic
-- scaling) and a copy of the character's Shirt, so Roblox paints the shirt's sleeves on them (no BodyColors copy: its
-- defaults would repaint the copies, which already carry the character's own colours, Studio test 2026-10-11). Layered
-- clothing (WrapLayer) cannot follow a partial, stretched copy and does not show; there is no outline (it would need an
-- EditableMesh per avatar mesh).
-- Fallback: read / layout / build / make return nil and the reason: off, noCharacter, noHumanoid, notR15,
-- missing:<part>, notMesh:<part>, hidden:<part>, noRig:<part>.<attachment>, odd:<what>, noClone:<part>. The real
-- character is only read, never written. Nothing here yields or connects.
--
-- API
--   OwnArm.MODEL_NAME                              "SD_OwnArms"
--   OwnArm.read(character) -> (Source?, string?)   the six arm parts and their rig attachments, the Shirt, BodyColors
--   OwnArm.layout(shape, side, studsPerDu) -> (Layout?, string?)   pure: the scale, the stretch, each part's overlay
--       size and its rest frame in the design arm frame (studs); side -1 left, +1 right
--   OwnArm.build(source, parent, studsPerDu) -> (Arms?, string?)   the copies in one Model under parent
--   OwnArm.make(character, parent, studsPerDu) -> (Arms?, string?)   read, then build
--   OwnArm.partFrames(arm, hand, shoulder, roll, studsPerDu, out) -> out   pure: out[part name] = its CFrame (studs,
--       the overlay camera's space) for the hand point and this arm's shoulder (du) and the roll (rad); returns out
--   OwnArm.apply(arm, frames)                      writes each part's CFrame only when it changed
--   OwnArm.destroy(arms)
--   OwnArm.signature(character) -> string          what the arms are built from ("none" without a character)
-- Require direction: Shared Config only.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

-- One side's rest shape (avatar studs): the three parts' sizes and the rig attachments' CFrames in their parts.
export type Shape = {
	hand: Vector3,
	lower: Vector3,
	upper: Vector3,
	wristHand: CFrame, -- <S>WristRigAttachment in <S>Hand
	wristLower: CFrame, -- <S>WristRigAttachment in <S>LowerArm
	elbowLower: CFrame, -- <S>ElbowRigAttachment in <S>LowerArm
	elbowUpper: CFrame, -- <S>ElbowRigAttachment in <S>UpperArm
	shoulderUpper: CFrame, -- <S>ShoulderRigAttachment in <S>UpperArm
}

type Parts = { hand: MeshPart, lower: MeshPart, upper: MeshPart }

export type Source = {
	left: { shape: Shape, parts: Parts },
	right: { shape: Shape, parts: Parts },
	shirt: Shirt?,
	bodyColors: BodyColors?,
}

export type Layout = {
	k: number, -- du per avatar stud
	stretch: number, -- f: everything past the wrist, along the arm
	sizes: { hand: Vector3, lower: Vector3, upper: Vector3 }, -- overlay studs
	rel: { hand: CFrame, lower: CFrame, upper: CFrame }, -- rest frames in the design arm frame (overlay studs)
}

export type Arm = {
	side: number,
	parts: { [string]: BasePart }, -- by R15 name
	rel: { [string]: CFrame }, -- by R15 name
	hand: BasePart,
}

export type Arms = { model: Model, left: Arm, right: Arm }

-- Constants

local OWN = Config.FirstPerson.ownArms
local FLIP = CFrame.Angles(0, math.pi, 0) -- Roblox's lookAt aims -Z; the design's +Z (as DesignArm)
local TO_DESIGN = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.zAxis) -- A's +Y -> the design arm's +Z
local MODEL_NAME = "SD_OwnArms"
local SIDES = { { sign = -1, name = "Left" }, { sign = 1, name = "Right" } }
local KINDS = { "hand", "lower", "upper" }
local PART_OF = { hand = "Hand", lower = "LowerArm", upper = "UpperArm" }
local NAMES = { "LeftHand", "LeftLowerArm", "LeftUpperArm", "RightHand", "RightLowerArm", "RightUpperArm" }
-- A copy keeps its looks; every joint, constraint, attachment, cage, value and script goes.
local KEEP = { SurfaceAppearance = true, Decal = true, Texture = true }

-- Module table

local OwnArm = {}
OwnArm.MODEL_NAME = MODEL_NAME

-- Private

-- A box's extent (frame rel, size) along A's +Y.
local function extentY(rel: CFrame, size: Vector3): number
	return math.abs(rel.XVector.Y) * size.X + math.abs(rel.YVector.Y) * size.Y + math.abs(rel.ZVector.Y) * size.Z
end

-- The part's own axis (1 = X, 2 = Y, 3 = Z) nearest A's +Y: its length along the arm.
local function lengthAxis(rel: CFrame): number
	local x, y, z = math.abs(rel.XVector.Y), math.abs(rel.YVector.Y), math.abs(rel.ZVector.Y)
	if y >= x and y >= z then
		return 2
	end
	return if x >= z then 1 else 3
end

-- The two sizes across the arm.
local function across(size: Vector3, axis: number): (number, number)
	if axis == 1 then
		return size.Y, size.Z
	elseif axis == 2 then
		return size.X, size.Z
	end
	return size.X, size.Y
end

local function stretched(size: Vector3, axis: number, f: number): Vector3
	if axis == 1 then
		return Vector3.new(size.X * f, size.Y, size.Z)
	elseif axis == 2 then
		return Vector3.new(size.X, size.Y * f, size.Z)
	end
	return Vector3.new(size.X, size.Y, size.Z * f)
end

local function rigFrame(part: Instance, name: string): CFrame?
	local found = part:FindFirstChild(name)
	return if found and found:IsA("Attachment") then found.CFrame else nil
end

-- A copy of an arm part for the overlay: its looks only, never colliding, touching, queried or casting a shadow, shown
-- in first person (Roblox hides the real arms there through LocalTransparencyModifier).
local function copyOf(from: BasePart): BasePart?
	local part = from:Clone() :: BasePart?
	if part == nil then
		return nil
	end
	for _, child in part:GetChildren() do
		if not KEEP[child.ClassName] then
			child:Destroy()
		elseif child:IsA("Decal") then
			child.LocalTransparencyModifier = 0
		end
	end
	for _, tag in part:GetTags() do
		part:RemoveTag(tag)
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.LocalTransparencyModifier = 0
	return part
end

-- Public

function OwnArm.read(character: Model?): (Source?, string?)
	if not OWN.enabled then
		return nil, "off"
	end
	if character == nil then
		return nil, "noCharacter"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil, "noHumanoid"
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil, "notR15"
	end
	local sides: { [number]: { shape: Shape, parts: Parts } } = {}
	for _, side in SIDES do
		local found: { [string]: MeshPart } = {}
		for _, kind in KINDS do
			local name = side.name .. PART_OF[kind]
			local part = character:FindFirstChild(name)
			if part == nil then
				return nil, "missing:" .. name
			elseif not part:IsA("MeshPart") then
				return nil, "notMesh:" .. name
			elseif part.Transparency >= OWN.maxTransparency then
				return nil, "hidden:" .. name
			end
			found[kind] = part
		end
		local wrist = side.name .. "WristRigAttachment"
		local elbow = side.name .. "ElbowRigAttachment"
		local shoulder = side.name .. "ShoulderRigAttachment"
		local wristHand = rigFrame(found.hand, wrist)
		local wristLower = rigFrame(found.lower, wrist)
		local elbowLower = rigFrame(found.lower, elbow)
		local elbowUpper = rigFrame(found.upper, elbow)
		local shoulderUpper = rigFrame(found.upper, shoulder)
		if wristHand == nil then
			return nil, `noRig:{found.hand.Name}.{wrist}`
		elseif wristLower == nil then
			return nil, `noRig:{found.lower.Name}.{wrist}`
		elseif elbowLower == nil then
			return nil, `noRig:{found.lower.Name}.{elbow}`
		elseif elbowUpper == nil then
			return nil, `noRig:{found.upper.Name}.{elbow}`
		elseif shoulderUpper == nil then
			return nil, `noRig:{found.upper.Name}.{shoulder}`
		end
		sides[side.sign] = {
			shape = {
				hand = found.hand.Size,
				lower = found.lower.Size,
				upper = found.upper.Size,
				wristHand = wristHand,
				wristLower = wristLower,
				elbowLower = elbowLower,
				elbowUpper = elbowUpper,
				shoulderUpper = shoulderUpper,
			},
			parts = { hand = found.hand, lower = found.lower, upper = found.upper },
		}
	end
	return {
		left = sides[-1],
		right = sides[1],
		shirt = character:FindFirstChildOfClass("Shirt"),
		bodyColors = character:FindFirstChildOfClass("BodyColors"),
	},
		nil
end

function OwnArm.layout(shape: Shape, side: number, studsPerDu: number): (Layout?, string?)
	local sizes: { [string]: Vector3 } = { hand = shape.hand, lower = shape.lower, upper = shape.upper }
	for _, kind in KINDS do
		local size = sizes[kind]
		if math.min(size.X, size.Y, size.Z) < OWN.minPartStuds then
			return nil, "odd:thin:" .. PART_OF[kind]
		end
	end
	-- The R15 rest chain in Hand space (Part0 · att0 = Part1 · att1).
	local lowerIn = shape.wristHand * shape.wristLower:Inverse()
	local upperIn = lowerIn * shape.elbowLower * shape.elbowUpper:Inverse()
	local shoulderIn = upperIn * shape.shoulderUpper.Position
	if shoulderIn.Magnitude < OWN.minPartStuds then
		return nil, "odd:short"
	end
	local y = shoulderIn.Unit
	local x = Vector3.xAxis - y * y.X
	if x.Magnitude < 1e-3 then
		return nil, "odd:axis" -- the arm runs along the hand's X
	end
	local toA = CFrame.fromMatrix(Vector3.zero, x.Unit, y):Inverse()
	local rest: { [string]: CFrame } = { hand = toA, lower = toA * lowerIn, upper = toA * upperIn }
	local k = OWN.handWidthDu / shape.hand.X
	if k * extentY(rest.hand, shape.hand) > OWN.maxHandLengthDu then
		return nil, "odd:hand"
	end
	local axes: { [string]: number } = { lower = lengthAxis(rest.lower), upper = lengthAxis(rest.upper) }
	for _, kind in { "lower", "upper" } do
		local a, b = across(sizes[kind], axes[kind])
		if k * math.max(a, b) > OWN.maxWidthDu then
			return nil, "odd:wide:" .. PART_OF[kind]
		end
	end
	-- The stretch (spec phase1-arms §1.9, §3.4): past the wrist (A's y = yW) everything moves out along the arm by f,
	-- so the upper arm's far end is reachDu + its radius from the hand's centre.
	local yW = (toA * shape.wristHand.Position).Y
	local far = rest.upper.Position.Y + extentY(rest.upper, shape.upper) / 2
	if far - yW < OWN.minPartStuds then
		return nil, "odd:short"
	end
	local a, b = across(shape.upper, axes.upper)
	local need = OWN.reachDu / k + 0.5 * math.sqrt(a * a + b * b)
	local f = math.max(1, (need - yW) / (far - yW))
	if f > OWN.maxStretch then
		return nil, "odd:stretch"
	end
	local s = studsPerDu * k -- overlay studs per avatar stud
	local turn = CFrame.Angles(0, 0, side * OWN.palmRoll) * TO_DESIGN
	local outSizes: { [string]: Vector3 } = {}
	local outRel: { [string]: CFrame } = {}
	for _, kind in KINDS do
		local frame = rest[kind]
		local size = sizes[kind]
		local p = frame.Position
		if kind ~= "hand" then
			p = Vector3.new(p.X, yW + (p.Y - yW) * f, p.Z)
			size = stretched(size, axes[kind], f)
		end
		outSizes[kind] = size * s
		outRel[kind] = turn * (CFrame.new(p * s) * frame.Rotation)
	end
	return {
		k = k,
		stretch = f,
		sizes = outSizes :: any,
		rel = outRel :: any,
	}, nil
end

function OwnArm.build(source: Source, parent: Instance?, studsPerDu: number): (Arms?, string?)
	local layouts: { [number]: Layout } = {}
	for _, side in SIDES do
		local data = if side.sign < 0 then source.left else source.right
		local layout, why = OwnArm.layout(data.shape, side.sign, studsPerDu)
		if layout == nil then
			return nil, why
		end
		layouts[side.sign] = layout
	end
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	-- Its own Humanoid: Roblox paints a classic Shirt onto R15-named parts of a Model with a Humanoid.
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false -- our sizes, not the scale values
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.EvaluateStateMachine = false
	humanoid.Parent = model
	local shirt = source.shirt
	if shirt then
		local copy = shirt:Clone()
		if copy then
			copy.Parent = model
		end
	end
	local arms: { [number]: Arm } = {}
	for _, side in SIDES do
		local data = if side.sign < 0 then source.left else source.right
		local layout = layouts[side.sign]
		local parts: { [string]: BasePart } = {}
		local rel: { [string]: CFrame } = {}
		local hand: BasePart? = nil
		for _, kind in KINDS do
			local from: MeshPart = (data.parts :: any)[kind]
			local copy = copyOf(from)
			if copy == nil then
				model:Destroy()
				return nil, "noClone:" .. from.Name
			end
			copy.Size = (layout.sizes :: any)[kind]
			copy.Parent = model
			parts[copy.Name] = copy
			rel[copy.Name] = (layout.rel :: any)[kind]
			if kind == "hand" then
				hand = copy
			end
		end
		arms[side.sign] = { side = side.sign, parts = parts, rel = rel, hand = hand :: BasePart }
	end
	model.Parent = parent
	return { model = model, left = arms[-1], right = arms[1] }, nil
end

function OwnArm.make(character: Model?, parent: Instance?, studsPerDu: number): (Arms?, string?)
	local source, why = OwnArm.read(character)
	if source == nil then
		return nil, why
	end
	return OwnArm.build(source, parent, studsPerDu)
end

function OwnArm.partFrames(
	arm: Arm,
	hand: Vector3,
	shoulder: Vector3,
	roll: number,
	studsPerDu: number,
	out: { [string]: CFrame }
): { [string]: CFrame }
	local u = studsPerDu
	local root = CFrame.lookAt(hand * u, shoulder * u) * FLIP * CFrame.Angles(0, 0, roll)
	for name, rel in arm.rel do
		out[name] = root * rel
	end
	return out
end

function OwnArm.apply(arm: Arm, frames: { [string]: CFrame })
	for name, part in arm.parts do
		local frame: CFrame? = frames[name]
		if frame and part.CFrame ~= frame then
			part.CFrame = frame
		end
	end
end

function OwnArm.destroy(arms: Arms)
	arms.model:Destroy()
end

function OwnArm.signature(character: Model?): string
	if character == nil then
		return "none"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local bits: { string } = { if humanoid then humanoid.RigType.Name else "noHumanoid" }
	for _, name in NAMES do
		local part = character:FindFirstChild(name)
		if part and part:IsA("MeshPart") then
			table.insert(
				bits,
				`{name}|{part.MeshId}|{part.TextureID}|{part.Size}|{part.Color:ToHex()}|{part.Transparency}`
			)
		else
			table.insert(bits, name .. "|-")
		end
	end
	local shirt = character:FindFirstChildOfClass("Shirt")
	table.insert(bits, if shirt then `shirt|{shirt.ShirtTemplate}|{shirt.Color3:ToHex()}` else "shirt|-")
	return table.concat(bits, ";")
end

return OwnArm
