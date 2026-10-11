--!strict
-- SquishDeformer_Test: unit tests for StarterPlayerScripts.Client.Anim.SquishDeformer. Server only
-- (ServerStorage.UnitTest). Models are built in memory and never parented into the place.
-- Contract (DESIGN §8.1 #5-#6, §9.3):
--   * attach once per built model; it stores, relative to the pivot, p, R, base mesh Scale/Offset, base Size (RB only)
--     and rigidity (attribute SD_Rigidity);
--   * setScale(S) is computed from the base every time (never incremental): mesh.Scale = base ∘ kv with
--     kv = 1 + (|R·axis ∘ S| - 1)(1 - rigidity), mesh.Offset = base + R⁻¹(p∘S - p); RB: Size = base ∘ kv;
--     no part ever moves; faces stay on the body (their centres follow the same linear map);
--   * squash(a): c = 1 - a on the axis, w = 1/√c elsewhere (volume kept), a <= maxSquash; S clamped per axis;
--   * twist turns the whole model (held: Weld.C1; viewport: pivot), never a part;
--   * rest: below the epsilons the base values are written exactly once, then nothing is written; after any number of
--     squeezes, rest returns every value exactly to its base (no drift);
--   * §8.1 #6 "no squash opens a gap", on every blueprint with a `motion` row (squishy overhaul spec 2026-10-09 §3.1,
--     §6) plus a sectioned fixture: at rest, at each of the toy's SquishRig.extremes along its Catalog squeezeAxis ("Y"
--     before it is in the Catalog), the throw anticipation and squash(maxSquash), and with the sections at ±1.1·maxDeg
--     (at rest and at depth), every part's contact point (SD_Contact, unit space; face and attach parts: the back
--     point) lies inside its holder (SD_ContactWith, else any body part) (the deformer is exact only for parts turned
--     about the squeeze axis, so this is not implied by the rest-pose L1 test);
--   * faces, looks and sections (spec §3.2): setFace hides and shows the face set by SD_Look, writing Transparency only
--     on a change (force re-applies); hidden parts are skipped while deformed and get the current values when shown;
--     blink, wow, cheek and mouth multipliers fold into mesh Scale and rest restores every value exactly; a section part
--     at θ = 0 renders like the mesh path (also after many twisted Viewport frames), a turned one rotates about its
--     pivot (Held: SD_PartWeld.C0, Viewport: CFrame), ±maxDeg rests bit-exactly; a tier drop (sections off, face
--     normal) and a pool return (rest) leave no angle or face behind;
--   * setTwistBase(base, true) stores a new twist base without writing; the next set() writes the weld once;
--   * solid parts (MeshParts and plain parts without a SpecialMesh, as in team model slots): Size = base ∘ kv, and the
--     part moves by p∘S - p from its base: welded (Held/World) through Weld.C0 = base C0 + (p∘S - p) without any
--     CFrame write, unwelded (Viewport) through CFrame = current pivot · CFrame(p∘S) · R; the Root (PrimaryPart) never
--     deforms; rest restores Size, C0 and CFrame bit-exactly after any number of squeezes (no drift); a model moved
--     by its owner (PivotTo) is deformed about its new pivot.
--   * feel pass (DESIGN §18.3.5, the jelly ripple's path B on world cover): includePrimary also deforms the
--     PrimaryPart (a cover piece's Body) and pivot = the piece's bottom centre: every squash keeps the rendered base on
--     the floor, only SpecialMesh Scale/Offset are written (no part moves or resizes), and rest restores every value to
--     within 1e-4 (a turned Cylinder body with a Ball dome too).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

type PartState = {
	cframe: CFrame,
	size: Vector3,
	scale: Vector3?,
	offset: Vector3?,
}

-- Pivot of the hand-made model: away from the origin and turned, so pivot-relative maths is exercised.
local PIVOT = CFrame.new(10, 5, -3) * CFrame.Angles(0, 0.3, 0)
local TOLERANCE = 1e-4 -- mesh and part values are stored as float32

local function meshPart(
	model: Model,
	name: string,
	size: Vector3,
	relative: CFrame,
	meshType: Enum.MeshType,
	rigidity: number?
): (Part, SpecialMesh)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = PIVOT * relative
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = meshType
	mesh.Parent = part
	if rigidity ~= nil then
		part:SetAttribute("SD_Rigidity", rigidity)
	end
	part.Parent = model
	return part, mesh
end

-- A Kitty-Bread-like model with the cases that matter: unrotated body parts, a tilted ear (rigidity 0.2), a 50° banana
-- segment, a face feature, a fully rigid horn, a half-rigid wing, a non-default base mesh, and a rounded box (RB).
local function handMadeModel(): Model
	local model = Instance.new("Model")
	model.Name = "HandMade"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.Transparency = 1
	root.Anchored = true
	root.CFrame = PIVOT
	root.Parent = model
	model.PrimaryPart = root

	meshPart(model, "Body", Vector3.new(1.5, 1.05, 1.15), CFrame.identity, Enum.MeshType.Sphere)
	meshPart(model, "Crust", Vector3.new(1.58, 0.7, 1.21), CFrame.new(0, 0.28, 0.02), Enum.MeshType.Sphere)
	meshPart(
		model,
		"EarL",
		Vector3.new(0.16, 0.4, 0.19),
		CFrame.new(-0.42, 0.68, 0.05) * CFrame.Angles(0, math.rad(90), math.rad(12)),
		Enum.MeshType.Wedge,
		0.2
	)
	meshPart(
		model,
		"Seg",
		Vector3.new(0.46, 0.36, 0.38),
		CFrame.new(0.613, 0.136, 0) * CFrame.Angles(0, 0, math.rad(50)),
		Enum.MeshType.Sphere
	)
	meshPart(model, "EyeL", Vector3.new(0.15, 0.19, 0.08), CFrame.new(-0.25, 0, -0.55), Enum.MeshType.Sphere)
	meshPart(model, "Horn", Vector3.new(0.2, 0.38, 0.16), CFrame.new(0.3, 0.9, 0), Enum.MeshType.Brick, 1)
	meshPart(model, "Wing", Vector3.new(0.26, 0.66, 0.78), CFrame.new(-0.66, -0.05, 0.06), Enum.MeshType.Sphere, 0.5)
	local _, odd = meshPart(model, "Odd", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0.2, -0.3, 0.1), Enum.MeshType.Brick)
	odd.Scale = Vector3.new(1.1, 0.9, 1)
	odd.Offset = Vector3.new(0, 0.05, 0)

	local roundedBox = Instance.new("Part")
	roundedBox.Name = "CrustBase"
	roundedBox.Anchored = true
	roundedBox.Size = Vector3.new(1.3, 0.95, 0.4)
	roundedBox.CFrame = PIVOT
	roundedBox:SetAttribute("SD_Shape", "RB")
	roundedBox.Parent = model
	return model
end

-- A slot-like model of solid parts (MeshParts and Parts without a SpecialMesh, one in a nested Model) plus one
-- SpecialMesh part. welded = a Held/World build (parts unanchored, each with an explicit Weld to the Root, C0 exact);
-- otherwise a Viewport build (everything anchored, no welds).
local function solidModel(welded: boolean): Model
	local model = Instance.new("Model")
	model.Name = if welded then "SolidHeld" else "SolidViewport"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.Transparency = 1
	root.Anchored = true
	root.CFrame = PIVOT
	root.Parent = model
	model.PrimaryPart = root
	local details = Instance.new("Model")
	details.Name = "Details"
	details.Parent = model

	local function add(part: BasePart, name: string, size: Vector3, relative: CFrame, parent: Instance)
		part.Name = name
		part.Anchored = not welded
		part.Size = size
		part.CFrame = PIVOT * relative
		part.Parent = parent
		if welded then
			local weld = Instance.new("Weld")
			weld.Name = "SD_PartWeld"
			weld.Part0 = root
			weld.Part1 = part
			weld.C0 = root.CFrame:ToObjectSpace(part.CFrame)
			weld.C1 = CFrame.identity
			weld.Parent = part
		end
	end

	add(Instance.new("MeshPart"), "Body", Vector3.new(1.5, 1.05, 1.15), CFrame.identity, model)
	add(Instance.new("MeshPart"), "EyeL", Vector3.new(0.15, 0.19, 0.08), CFrame.new(-0.25, 0.05, -0.55), model)
	local ear = Instance.new("Part")
	ear:SetAttribute("SD_Rigidity", 0.2)
	add(
		ear,
		"Ear",
		Vector3.new(0.16, 0.4, 0.19),
		CFrame.new(-0.42, 0.68, 0.05) * CFrame.Angles(0, math.rad(90), math.rad(12)),
		model
	)
	add(
		Instance.new("Part"),
		"Tail",
		Vector3.new(0.3, 0.2, 0.5),
		CFrame.new(0.1, -0.2, 0.6) * CFrame.Angles(math.rad(30), 0, 0),
		details
	)
	local nose = Instance.new("Part")
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = nose
	add(nose, "Nose", Vector3.new(0.2, 0.15, 0.15), CFrame.new(0, -0.05, -0.6), model)
	return model
end

-- Weld.C0 of every weld in the model (solid parts are moved through it in Held/World builds).
local function weldSnapshot(model: Model): { [Weld]: CFrame }
	local states: { [Weld]: CFrame } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Weld") then
			states[descendant] = descendant.C0
		end
	end
	return states
end

local function snapshot(model: Model): { [BasePart]: PartState }
	local states: { [BasePart]: PartState } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local mesh = descendant:FindFirstChildWhichIsA("DataModelMesh")
			states[descendant] = {
				cframe = descendant.CFrame,
				size = descendant.Size,
				scale = if mesh then mesh.Scale else nil,
				offset = if mesh then mesh.Offset else nil,
			}
		end
	end
	return states
end

-- Returns a description of the first value that is not bit-for-bit equal to the snapshot, or nil.
local function firstChange(before: { [BasePart]: PartState }): string?
	for part, state in before do
		if part.CFrame ~= state.cframe then
			return `{part.Name}.CFrame moved`
		end
		if part.Size ~= state.size then
			return `{part.Name}.Size {part.Size} ~= {state.size}`
		end
		local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
		if mesh and (mesh.Scale ~= state.scale or mesh.Offset ~= state.offset) then
			return `{part.Name} mesh {mesh.Scale} / {mesh.Offset} ~= base {state.scale} / {state.offset}`
		end
	end
	return nil
end

-- Returns the name of the first part whose CFrame is not bit-for-bit the snapshot's, or nil.
local function firstMove(before: { [BasePart]: PartState }): string?
	for part, state in before do
		if part.CFrame ~= state.cframe then
			return part.Name
		end
	end
	return nil
end

-- The rendered shape of a (deformed) part relative to `pivot`: its CFrame moved by the mesh Offset (part space) and
-- Size × mesh Scale; a part without a mesh (rounded box) is its CFrame and Size.
local function renderedShape(pivot: CFrame, part: BasePart): (CFrame, Vector3)
	local frame = pivot:ToObjectSpace(part.CFrame)
	local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
	if mesh then
		return frame * CFrame.new(mesh.Offset), part.Size * mesh.Scale
	end
	return frame, part.Size
end

-- Whether `point` lies inside a rendered shape: E ellipsoid, B box, RB box ∩ sphere of normalized radius 1.375, W the
-- wedge under its slope (bottom y = -1, tall edge at z = +1).
local function shapeContains(shape: unknown, frame: CFrame, size: Vector3, point: Vector3): boolean
	local q = frame:PointToObjectSpace(point) / (size / 2)
	local slack = 1e-4
	if shape == "E" then
		return q.Magnitude <= 1 + slack
	end
	local inBox = math.abs(q.X) <= 1 + slack and math.abs(q.Y) <= 1 + slack and math.abs(q.Z) <= 1 + slack
	if shape == "RB" then
		return inBox and q.Magnitude <= 1.375 + slack
	elseif shape == "W" then
		return inBox and q.Y <= q.Z + slack
	end
	return inBox and shape == "B"
end

-- The §9.3 formula, recomputed from a part's base values.
local function expected(part: BasePart, base: PartState, S: Vector3): (Vector3, Vector3, Vector3)
	local relative = PIVOT:ToObjectSpace(base.cframe)
	local R, p = relative.Rotation, relative.Position
	local function k(axis: Vector3): number
		return (R:VectorToWorldSpace(axis) * S).Magnitude
	end
	local rigidity = (part:GetAttribute("SD_Rigidity") :: number?) or 0
	local kv = Vector3.new(k(Vector3.xAxis), k(Vector3.yAxis), k(Vector3.zAxis))
	kv = Vector3.one + (kv - Vector3.one) * (1 - rigidity)
	local scale = (base.scale or Vector3.one) * kv
	local offset = (base.offset or Vector3.zero) + R:VectorToObjectSpace(p * S - p)
	return scale, offset, base.size * kv
end

return function(t: Context)
	local SquishDeformer = t.requireClient("Anim/SquishDeformer")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local DEFORM = Config.Anim.deform

	local function expectVector(actual: Vector3, wanted: Vector3, tolerance: number?, label: string?)
		local tol = tolerance or TOLERANCE
		if (actual - wanted).Magnitude > tol then
			error(`{label or "vector"}: expected {wanted}, got {actual}`, 2)
		end
	end

	-- Within `tolerance` on every axis (the deformer's writeEpsilon is per axis).
	local function expectAxes(actual: Vector3, wanted: Vector3, tolerance: number, label: string)
		local d = actual - wanted
		if math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z)) > tolerance then
			error(`{label}: expected {wanted} within {tolerance} per axis, got {actual}`, 2)
		end
	end

	local function partNamed(model: Model, name: string): BasePart
		return model:FindFirstChild(name) :: BasePart
	end

	local function meshOf(model: Model, name: string): DataModelMesh
		return partNamed(model, name):FindFirstChildWhichIsA("DataModelMesh") :: DataModelMesh
	end

	-- Attach --------------------------------------------------------------------------------------------------

	t.test("attaches once per model and drives every mesh part and rounded box, not the Root", function()
		local model = handMadeModel()
		local deformer = SquishDeformer.attach(model)
		expect.equal(SquishDeformer.attach(model), deformer)
		expect.equal(SquishDeformer.get(model), deformer)
		expect.equal(deformer:partCount(), 9)
		expect.truthy(deformer:isResting())
		deformer:destroy()
		expect.equal(SquishDeformer.get(model), nil)
		model:Destroy()
	end)

	-- Apply ---------------------------------------------------------------------------------------------------

	t.test("setScale follows the §9.3 formula from the base values and never moves a part", function()
		local model = handMadeModel()
		local base = snapshot(model)
		local deformer = SquishDeformer.attach(model)
		for _, S in { SquishDeformer.squash(0.3, "Y"), Vector3.new(1.2, 0.8, 1.05), SquishDeformer.squash(-0.2, "X") } do
			deformer:setScale(S)
			for part, state in base do
				expect.equal(part.CFrame, state.cframe)
				local scale, offset, size = expected(part, state, S)
				local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
				if mesh then
					expectVector(mesh.Scale, scale, nil, `{part.Name}.Scale`)
					expectVector(mesh.Offset, offset, nil, `{part.Name}.Offset`)
					expect.equal(part.Size, state.size)
				elseif part.Name == "CrustBase" then
					expectVector(part.Size, size, nil, "CrustBase.Size")
				end
			end
		end
		deformer:destroy()
		model:Destroy()
	end)

	t.test("faces and details stay attached: every part centre follows the same linear map", function()
		local model = handMadeModel()
		local deformer = SquishDeformer.attach(model)
		local S = SquishDeformer.squash(DEFORM.maxSquash, "Y")
		local centres: { [string]: Vector3 } = {}
		for _, name in { "EyeL", "EarL", "Horn", "Wing", "Seg" } do
			centres[name] = PIVOT:PointToObjectSpace(partNamed(model, name).CFrame.Position)
		end
		deformer:setScale(S)
		for name, p in centres do
			local part = partNamed(model, name)
			local mesh = meshOf(model, name)
			local centre = PIVOT:PointToObjectSpace(part.CFrame:PointToWorldSpace(mesh.Offset))
			expectVector(centre, p * S, nil, `{name} centre`)
		end
		deformer:destroy()
		model:Destroy()
	end)

	t.test("squash keeps the volume and caps the squash at maxSquash", function()
		for _, axis in { "X", "Y", "Z" } do
			for _, a in { -0.3, 0, 0.1, 0.2, DEFORM.maxSquash } do
				local S = SquishDeformer.squash(a, axis)
				expect.near(S.X * S.Y * S.Z, 1, 1e-5)
				local c = if axis == "X" then S.X elseif axis == "Y" then S.Y else S.Z
				expect.near(c, 1 - a, 1e-6)
			end
			expect.equal(SquishDeformer.squash(0.9, axis), SquishDeformer.squash(DEFORM.maxSquash, axis))
		end
		-- Default axis is Y.
		expect.equal(SquishDeformer.squash(0.2), SquishDeformer.squash(0.2, "Y"))

		local model = handMadeModel()
		local bodyMesh = meshOf(model, "Body")
		local before = bodyMesh.Scale
		local deformer = SquishDeformer.attach(model)
		deformer:setScale(SquishDeformer.squash(0.3, "Y"))
		local after = bodyMesh.Scale
		expect.near(after.X * after.Y * after.Z, before.X * before.Y * before.Z, 1e-4)
		deformer:destroy()
		model:Destroy()
	end)

	t.test("S is clamped per axis to [scaleMin, scaleMax]", function()
		local model = handMadeModel()
		local deformer = SquishDeformer.attach(model)
		deformer:setScale(Vector3.new(5, 0.1, 1))
		expect.equal(deformer:getScale(), Vector3.new(DEFORM.scaleMax, DEFORM.scaleMin, 1))
		expect.equal(
			SquishDeformer.axisScale(0.1, 9, "Z"),
			Vector3.new(DEFORM.scaleMax, DEFORM.scaleMax, DEFORM.scaleMin)
		)
		expect.equal(SquishDeformer.clampScale(Vector3.new(0 / 0, 1, 1)), Vector3.one)
		deformer:destroy()
		model:Destroy()
	end)

	t.test("options.scaleMax lifts one deformer's ceiling (the first-person copy); the floor stays", function()
		local model = handMadeModel()
		local deformer = SquishDeformer.attach(model, { scaleMax = math.huge })
		local out = t.requireClient("Anim/SquishRig").newOut()
		out.S = Vector3.new(0.78, 0.85, 1.75) -- the design's sling key (fp.js:152)
		deformer:apply(out)
		expect.equal(deformer:getScale(), Vector3.new(0.78, 0.85, 1.75))
		deformer:setScale(Vector3.new(5, 0.1, 1))
		expect.equal(deformer:getScale(), Vector3.new(5, DEFORM.scaleMin, 1))
		deformer:set(Vector3.new(1, 1, 2), 0)
		expect.equal(deformer:getScale(), Vector3.new(1, 1, 2))
		deformer:destroy()
		model:Destroy()
		expect.throws(function()
			SquishDeformer.attach(handMadeModel(), { scaleMax = 1.2 }) -- below Config.Anim.deform.scaleMax
		end, "scaleMax")
	end)

	t.test("rigidity resists a part's own stretching while its position still follows the body", function()
		local model = handMadeModel()
		local hornBase, wingBase = meshOf(model, "Horn").Scale, meshOf(model, "Wing").Scale
		local deformer = SquishDeformer.attach(model)
		local S = Vector3.new(1.2, 0.7, 1.2)
		deformer:setScale(S)
		-- Rigidity 1: the horn keeps its own shape but rides on the squashed body.
		expect.equal(meshOf(model, "Horn").Scale, hornBase)
		expectVector(meshOf(model, "Horn").Offset, Vector3.new(0.3, 0.9, 0) * S - Vector3.new(0.3, 0.9, 0))
		-- Rigidity 0.5 (unrotated): half of the stretch.
		expectVector(meshOf(model, "Wing").Scale, wingBase * (Vector3.one + (S - Vector3.one) * 0.5))
		deformer:destroy()
		model:Destroy()
	end)

	t.test("a rounded box (RB) is resized from its base Size, never moved", function()
		local model = handMadeModel()
		local box = partNamed(model, "CrustBase")
		local baseSize, baseCFrame = box.Size, box.CFrame
		local deformer = SquishDeformer.attach(model)
		local S = SquishDeformer.squash(0.25, "Y")
		deformer:setScale(S)
		expectVector(box.Size, baseSize * S)
		expect.equal(box.CFrame, baseCFrame)
		expect.equal(box:FindFirstChildWhichIsA("DataModelMesh"), nil)
		deformer:rest()
		expect.equal(box.Size, baseSize)
		deformer:destroy()
		model:Destroy()
	end)

	-- Rest and drift ------------------------------------------------------------------------------------------

	t.test("no drift: after 1000 random squeezes, rest returns every value exactly to its base", function()
		local model = handMadeModel()
		local base = snapshot(model)
		local deformer = SquishDeformer.attach(model)
		local rng = Random.new(20261005)
		for i = 1, 1000 do
			local roll = i % 3
			if roll == 0 then
				deformer:setScale(
					Vector3.new(rng:NextNumber(0.3, 1.9), rng:NextNumber(0.3, 1.9), rng:NextNumber(0.3, 1.9))
				)
			elseif roll == 1 then
				local axes = { "X", "Y", "Z" }
				deformer:setScale(SquishDeformer.squash(rng:NextNumber(-0.6, 0.5), axes[rng:NextInteger(1, 3)]))
			else
				deformer:set(SquishDeformer.axisScale(rng:NextNumber(0.6, 1.1), rng:NextNumber(0.9, 1.3)), 0.1)
			end
		end
		deformer:setScale(SquishDeformer.squash(0.2))
		expect.falsy(deformer:isResting())
		deformer:rest()
		expect.truthy(deformer:isResting())
		expect.equal(firstChange(base), nil)
		deformer:destroy()
		model:Destroy()
	end)

	t.test("near rest the base is written exactly once, then nothing is written", function()
		local model = handMadeModel()
		local base = snapshot(model)
		local deformer = SquishDeformer.attach(model)
		deformer:setScale(SquishDeformer.squash(0.2))
		-- Within restEpsilon of 1 on every axis: exact base values, not a tiny deformation.
		local nearOne = 1 + DEFORM.restEpsilon * 0.5
		deformer:setScale(Vector3.new(nearOne, 2 - nearOne, 1))
		expect.truthy(deformer:isResting())
		expect.equal(firstChange(base), nil)
		-- Asleep: a value changed from outside stays untouched by further rest calls.
		local bodyMesh = meshOf(model, "Body")
		bodyMesh.Scale = Vector3.new(3, 3, 3)
		deformer:setScale(Vector3.one)
		deformer:rest()
		expect.equal(bodyMesh.Scale, Vector3.new(3, 3, 3))
		-- Waking up writes from the base again.
		local S = SquishDeformer.squash(0.2)
		deformer:setScale(S)
		expectVector(bodyMesh.Scale, (base[partNamed(model, "Body")].scale :: Vector3) * S)
		deformer:destroy()
		model:Destroy()
	end)

	t.test(
		"a value moves only once it changed by writeEpsilon studs; a bigger change is written; rest is exact",
		function()
			local model = handMadeModel()
			local base = snapshot(model)
			local deformer = SquishDeformer.attach(model)
			local S = Vector3.new(1.1, 0.8, 1.1)
			deformer:setScale(S)
			local written = snapshot(model)
			-- A change far below writeEpsilon on every part (and still a new float32 value): nothing is rewritten.
			deformer:setScale(S * (1 + 1e-5))
			expect.equal(firstChange(written), nil)
			-- Every value stays within writeEpsilon studs of the formula for the new S (mesh Scale as rendered size).
			local eps = DEFORM.writeEpsilon + 1e-6
			for part, state in base do
				local scale, offset, size = expected(part, state, deformer:getScale())
				local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
				if mesh then
					expectAxes((mesh.Scale - scale) * part.Size, Vector3.zero, eps, `{part.Name} rendered size`)
					expectAxes(mesh.Offset, offset, eps, `{part.Name}.Offset`)
				elseif part.Name == "CrustBase" then
					expectAxes(part.Size, size, eps, "CrustBase.Size")
				end
			end
			-- A bigger change is written from the base as always.
			local bigger = SquishDeformer.squash(0.25, "Y")
			deformer:setScale(bigger)
			for part, state in base do
				local scale, offset = expected(part, state, bigger)
				local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
				if mesh then
					expectVector(mesh.Scale, scale, nil, `{part.Name}.Scale`)
					expectVector(mesh.Offset, offset, nil, `{part.Name}.Offset`)
				end
			end
			-- Rest after skipped writes is still bit-exact.
			deformer:setScale(bigger * (1 + 1e-5))
			deformer:rest()
			expect.equal(firstChange(base), nil)
			deformer:destroy()
			model:Destroy()
		end
	)

	-- Twist ---------------------------------------------------------------------------------------------------

	t.test("twist turns the whole held model through Weld.C1 and rests exactly", function()
		local model = handMadeModel()
		local hand = Instance.new("Part")
		hand.Anchored = true
		hand.Parent = model
		local weld = Instance.new("Weld")
		local baseC1 = CFrame.new(0, 0.1, 0.2) * CFrame.Angles(0, 0.5, 0)
		weld.Part0 = hand
		weld.Part1 = model.PrimaryPart
		weld.C1 = baseC1
		weld.Parent = hand
		local deformer = SquishDeformer.attach(model, { twist = "weld", weld = weld, twistAxis = "Y" })
		local base = snapshot(model)
		local angle = math.rad(8)
		deformer:setTwist(angle)
		local wanted = CFrame.fromAxisAngle(Vector3.yAxis, -angle) * baseC1
		expectVector(weld.C1.Position, wanted.Position, 1e-4, "C1 position")
		expectVector(weld.C1.LookVector, wanted.LookVector, 1e-4, "C1 look")
		expect.equal(firstChange(base), nil) -- no part or mesh touched by the twist
		-- A new un-twisted base (e.g. the idle bob) keeps the twist on top.
		local bobbed = CFrame.new(0, -0.03, 0) * baseC1
		deformer:setTwistBase(bobbed)
		expectVector(weld.C1.Position, (CFrame.fromAxisAngle(Vector3.yAxis, -angle) * bobbed).Position, 1e-4)
		-- Below twistEpsilon the base itself is written (no residual rotation). 1e-6: CFrame property storage only.
		deformer:setTwist(DEFORM.twistEpsilon * 0.5)
		expectVector(weld.C1.Position, bobbed.Position, 1e-6, "rest C1 position")
		expectVector(weld.C1.LookVector, bobbed.LookVector, 1e-6, "rest C1 look")
		expectVector(weld.C1.UpVector, bobbed.UpVector, 1e-6, "rest C1 up")
		deformer:destroy()
		model:Destroy()
	end)

	t.test("a deferred twist base is written by the next set(), with the twist on top", function()
		local model = handMadeModel()
		local hand = Instance.new("Part")
		hand.Anchored = true
		hand.Parent = model
		local weld = Instance.new("Weld")
		local baseC1 = CFrame.new(0, 0.1, 0.2) * CFrame.Angles(0, 0.5, 0)
		weld.Part0 = hand
		weld.Part1 = model.PrimaryPart
		weld.C1 = baseC1
		weld.Parent = hand
		local deformer = SquishDeformer.attach(model, { twist = "weld", weld = weld, twistAxis = "Y" })
		local angle = math.rad(8)
		deformer:setTwist(angle)
		local before = weld.C1
		local bobbed = CFrame.new(0, -0.03, 0) * baseC1
		deformer:setTwistBase(bobbed, true)
		expect.equal(weld.C1, before) -- deferred: nothing written yet
		deformer:set(Vector3.one, angle)
		local wanted = CFrame.fromAxisAngle(Vector3.yAxis, -angle) * bobbed
		expectVector(weld.C1.Position, wanted.Position, 1e-4, "twisted C1 position")
		expectVector(weld.C1.LookVector, wanted.LookVector, 1e-4, "twisted C1 look")
		-- Untwisted and already at the twist base: a deferred new base is still written by the next set().
		deformer:set(Vector3.one, 0)
		deformer:setTwistBase(baseC1, true)
		deformer:set(Vector3.one, 0)
		expectVector(weld.C1.Position, baseC1.Position, 1e-6, "untwisted C1 position")
		expectVector(weld.C1.LookVector, baseC1.LookVector, 1e-6, "untwisted C1 look")
		-- setTwist with an unchanged angle also flushes a deferred base.
		deformer:setTwistBase(bobbed, true)
		deformer:setTwist(0)
		expectVector(weld.C1.Position, bobbed.Position, 1e-6, "flushed by setTwist")
		deformer:destroy()
		model:Destroy()
	end)

	t.test("twist turns a viewport model about its pivot without deforming any part", function()
		local model = handMadeModel()
		local root = model.PrimaryPart :: BasePart
		local relative: { [BasePart]: CFrame } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				relative[descendant] = root.CFrame:ToObjectSpace(descendant.CFrame)
			end
		end
		local deformer = SquishDeformer.attach(model, { twist = "pivot" })
		deformer:setTwist(0.2)
		local wanted = PIVOT * CFrame.fromAxisAngle(Vector3.yAxis, 0.2)
		expectVector(root.CFrame.Position, wanted.Position, 1e-4)
		expectVector(root.CFrame.LookVector, wanted.LookVector, 1e-4)
		for part, rel in relative do
			expectVector(root.CFrame:ToObjectSpace(part.CFrame).Position, rel.Position, 1e-4, part.Name)
		end
		deformer:rest()
		expectVector(root.CFrame.Position, PIVOT.Position, 1e-4)
		expectVector(root.CFrame.LookVector, PIVOT.LookVector, 1e-4)
		deformer:destroy()
		model:Destroy()
	end)

	-- Solid parts (model slots: MeshParts and plain parts) -----------------------------------------------------

	local function squeezeMany(deformer: any, count: number, seed: number)
		local rng = Random.new(seed)
		local axes = { "X", "Y", "Z" }
		for i = 1, count do
			if i % 2 == 0 then
				deformer:setScale(
					Vector3.new(rng:NextNumber(0.3, 1.9), rng:NextNumber(0.3, 1.9), rng:NextNumber(0.3, 1.9))
				)
			else
				deformer:setScale(SquishDeformer.squash(rng:NextNumber(-0.6, 0.5), axes[rng:NextInteger(1, 3)]))
			end
		end
	end

	t.test("welded MeshParts and plain parts resize and move through Weld.C0 only, and rest exactly", function()
		local model = solidModel(true)
		local base = snapshot(model)
		local baseC0 = weldSnapshot(model)
		local deformer = SquishDeformer.attach(model)
		expect.equal(deformer:partCount(), 5) -- Body, EyeL, Ear, Details.Tail, Nose; never the Root
		for _, S in { SquishDeformer.squash(0.3, "Y"), Vector3.new(1.2, 0.8, 1.05), SquishDeformer.squash(-0.2, "Z") } do
			deformer:setScale(S)
			local clamped = deformer:getScale()
			-- No CFrame is written for welded parts (the weld moves them in the world); the Root is untouched.
			local moved = firstMove(base)
			if moved then
				error(`{moved}.CFrame was written`)
			end
			for part, state in base do
				local relative = PIVOT:ToObjectSpace(state.cframe)
				local _, offset, size = expected(part, state, clamped)
				local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
				local weld = part:FindFirstChildWhichIsA("Weld")
				if part == model.PrimaryPart then
					expect.equal(part.Size, state.size)
				elseif mesh then
					expectVector(mesh.Offset, offset, nil, `{part.Name} mesh Offset`)
					expect.equal(part.Size, state.size)
					expect.equal((weld :: Weld).C0, baseC0[weld :: Weld])
				else
					local w = weld :: Weld
					expectVector(part.Size, size, nil, `{part.Name}.Size`)
					local p = relative.Position
					expectVector(w.C0.Position, baseC0[w].Position + (p * clamped - p), nil, `{part.Name} C0`)
					expectVector(w.C0.LookVector, baseC0[w].LookVector, 1e-6, `{part.Name} C0 rotation`)
					expectVector(w.C0.UpVector, baseC0[w].UpVector, 1e-6, `{part.Name} C0 rotation`)
				end
			end
		end
		-- No drift: after many random squeezes, rest gives back every Size, C0 and mesh value bit-exactly.
		squeezeMany(deformer, 1000, 20261005)
		expect.falsy(deformer:isResting())
		deformer:rest()
		expect.truthy(deformer:isResting())
		expect.equal(firstChange(base), nil)
		for weld, c0 in baseC0 do
			expect.equal(weld.C0, c0)
		end
		deformer:destroy()
		model:Destroy()
	end)

	t.test(
		"unwelded (viewport) MeshParts and plain parts move through CFrame from the base, and rest exactly",
		function()
			local model = solidModel(false)
			local base = snapshot(model)
			local deformer = SquishDeformer.attach(model)
			expect.equal(deformer:partCount(), 5)
			local S = Vector3.new(1.25, 0.7, 1.1)
			deformer:setScale(S)
			local root = model.PrimaryPart :: BasePart
			for part, state in base do
				if part == root then
					expect.equal(part.CFrame, state.cframe)
					expect.equal(part.Size, state.size)
					continue
				end
				local relative = PIVOT:ToObjectSpace(state.cframe)
				local _, _, size = expected(part, state, S)
				if part:FindFirstChildWhichIsA("DataModelMesh") then
					expect.equal(part.CFrame, state.cframe) -- mesh parts never move
					continue
				end
				local wanted = PIVOT * CFrame.new(relative.Position * S) * relative.Rotation
				expectVector(part.Size, size, nil, `{part.Name}.Size`)
				expectVector(part.CFrame.Position, wanted.Position, nil, `{part.Name}.Position`)
				expectVector(part.CFrame.LookVector, wanted.LookVector, nil, `{part.Name} rotation`)
				expectVector(part.CFrame.UpVector, wanted.UpVector, nil, `{part.Name} rotation`)
			end
			-- No drift: rest after many squeezes writes the base CFrames and Sizes bit-exactly.
			squeezeMany(deformer, 1000, 7)
			deformer:rest()
			expect.equal(firstChange(base), nil)

			-- A model the owner moved (PivotTo: turntable, display) deforms about its new pivot and rests there.
			local moved = CFrame.new(-4, 2, 9) * CFrame.Angles(0, -1.1, 0.2)
			model:PivotTo(moved)
			deformer:setScale(S)
			local tail = (model:FindFirstChild("Details") :: Model):FindFirstChild("Tail") :: BasePart
			local tailRelative = PIVOT:ToObjectSpace(base[tail].cframe)
			local wanted = moved * CFrame.new(tailRelative.Position * S) * tailRelative.Rotation
			expectVector(tail.CFrame.Position, wanted.Position, nil, "moved Tail.Position")
			expectVector(tail.CFrame.LookVector, wanted.LookVector, nil, "moved Tail rotation")
			deformer:rest()
			expectVector(tail.CFrame.Position, (moved * tailRelative).Position, nil, "moved Tail rest position")
			expect.equal(tail.Size, base[tail].size)
			deformer:destroy()
			model:Destroy()
		end
	)

	-- World cover (feel pass, §18.3.5) ----------------------------------------------------------------------

	-- The lowest point of a rendered box (frame relative to the pivot, size) along the pivot's Y.
	local function renderedBottom(frame: CFrame, size: Vector3): number
		local half = size / 2
		return frame.Y
			- (
				math.abs(frame.RightVector.Y) * half.X
				+ math.abs(frame.UpVector.Y) * half.Y
				+ math.abs(frame.LookVector.Y) * half.Z
			)
	end

	-- A cover piece as ArenaBuilder makes it, with the SpecialMesh children path B adds: a wall (Body + a stripe) and a
	-- gumdrop (a Cylinder Body turned upright + a Ball dome). FLOOR is the floor point under the piece (arena axes).
	local FLOOR = CFrame.new(10, 2, -3) * CFrame.Angles(0, 0.4, 0)
	local function coverPart(model: Model, name: string, size: Vector3, relative: CFrame, shape: Enum.PartType): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = shape
		part.Size = size
		part.CFrame = FLOOR * relative
		part.Anchored = true
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = if shape == Enum.PartType.Ball
			then Enum.MeshType.Sphere
			elseif shape == Enum.PartType.Cylinder then Enum.MeshType.Cylinder
			else Enum.MeshType.Brick
		mesh.Parent = part
		part.Parent = model
		return part
	end

	local function wallModel(): Model
		local model = Instance.new("Model")
		local body = coverPart(model, "Body", Vector3.new(6, 8, 2.5), CFrame.new(0, 4, 0), Enum.PartType.Block)
		coverPart(model, "Stripe_1", Vector3.new(5.98, 0.5, 2.6), CFrame.new(0, 2, 0), Enum.PartType.Block)
		model.PrimaryPart = body
		return model
	end

	local function gumdropModel(): Model
		local model = Instance.new("Model")
		local upright = CFrame.new(0, 3.75, 0) * CFrame.Angles(0, 0, math.rad(90))
		local body = coverPart(model, "Body", Vector3.new(7.5, 5, 5), upright, Enum.PartType.Cylinder)
		coverPart(model, "Dome", Vector3.new(5, 5, 5), CFrame.new(0, 7.5, 0), Enum.PartType.Ball)
		model.PrimaryPart = body
		return model
	end

	t.test("includePrimary and a bottom pivot: the base stays on the floor, no part moves, rest restores", function()
		for _, make in { wallModel, gumdropModel } do
			local model = make()
			local body = model.PrimaryPart :: BasePart
			local base = snapshot(model)
			local deformer = SquishDeformer.attach(model, { includePrimary = true, pivot = FLOOR })
			expect.equal(deformer:partCount(), 2)
			for _, S in
				{
					SquishDeformer.squash(0.1, "Y"),
					SquishDeformer.squash(0.1, "X"),
					SquishDeformer.squash(-0.08, "Z"),
					Vector3.new(1.05, 0.93, 1.02),
				}
			do
				deformer:setScale(S)
				expect.equal(firstMove(base), nil)
				for part, state in base do
					expect.equal(part.Size, state.size)
				end
				local frame, size = renderedShape(FLOOR, body)
				expect.near(renderedBottom(frame, size), 0, TOLERANCE)
				-- The body's rendered centre follows p ∘ S about the floor point.
				local p = FLOOR:PointToObjectSpace(base[body].cframe.Position)
				expectVector(frame.Position, p * S, nil, "Body centre")
			end
			deformer:destroy()
			for part, state in base do
				local mesh = part:FindFirstChildWhichIsA("DataModelMesh") :: SpecialMesh
				expectVector(mesh.Scale, state.scale :: Vector3, TOLERANCE, `{part.Name}.Scale`)
				expectVector(mesh.Offset, state.offset :: Vector3, TOLERANCE, `{part.Name}.Offset`)
			end
			model:Destroy()
		end
	end)

	t.test("without includePrimary the PrimaryPart still never deforms", function()
		local model = wallModel()
		local deformer = SquishDeformer.attach(model, { pivot = FLOOR })
		expect.equal(deformer:partCount(), 1)
		deformer:setScale(SquishDeformer.squash(0.2, "Y"))
		local mesh = (model.PrimaryPart :: BasePart):FindFirstChildWhichIsA("DataModelMesh") :: SpecialMesh
		expect.equal(mesh.Scale, Vector3.one)
		expect.equal(mesh.Offset, Vector3.zero)
		deformer:destroy()
		model:Destroy()
	end)

	-- Models from the real builder ---------------------------------------------------------------------------

	local okBuilder, Builder = pcall(t.requireShared, "Art/SquishyBuilder")
	local okCatalog, Catalog = pcall(t.requireShared, "Catalog")
	if okBuilder and okCatalog then
		t.test("every SquishyBuilder model deforms without moving a part and rests exactly (no drift)", function()
			for _, def in Catalog.list() do
				for _, mode in { "Viewport", "Held" } do
					local model: Model = Builder.build(def.blueprintId, mode)
					local base = snapshot(model)
					local deformer = SquishDeformer.attach(model)
					expect.truthy(deformer:partCount() > 0)
					local rng = Random.new(#def.id)
					for _ = 1, 300 do
						deformer:setScale(SquishDeformer.squash(rng:NextNumber(-0.3, 0.4), def.anim.squeezeAxis))
						local moved = firstMove(base)
						if moved then
							error(`{def.id} ({mode}): part {moved} moved`)
						end
					end
					deformer:rest()
					local change = firstChange(base)
					if change then
						error(`{def.id} ({mode}) did not rest exactly: {change}`)
					end
					deformer:destroy()
					model:Destroy()
				end
			end
		end)

		t.test("the skipped writes never leave a shown value more than writeEpsilon studs off the formula", function()
			-- The lobby breath (as Held/Inspect show it) and a squeeze, frame by frame, on every Catalog toy: each shown
			-- mesh part stays within writeEpsilon of the full §9.3 values (Scale as rendered size), and rests exactly.
			local eps = DEFORM.writeEpsilon + 1e-5 -- float32 storage
			local breath = Config.Anim.held.lobbyIdle
			local skipped, frames = 0, 0
			for _, def in Catalog.list() do
				local model: Model = Builder.build(def.blueprintId, "Held")
				local base = snapshot(model)
				local pivot = model:GetPivot()
				local deformer = SquishDeformer.attach(model)
				local last: { [BasePart]: Vector3 } = {}
				for frame = 1, 90 do
					local phi = 2 * math.pi * frame / 60 / breath.periodSeconds
					local squeeze = if frame > 45 then 0.3 * math.sin(math.pi * (frame - 45) / 45) else 0
					local S = SquishDeformer.squash(squeeze, def.anim.squeezeAxis)
						* Vector3.new(
							1 - breath.ampXZ * math.sin(phi),
							1 + breath.ampY * math.sin(phi),
							1 - breath.ampXZ * math.sin(phi)
						)
					deformer:setScale(S)
					local clamped = deformer:getScale()
					local d = clamped - Vector3.one
					local atRest = math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z)) < DEFORM.restEpsilon
					if atRest then
						clamped = Vector3.one -- the rest snap writes the base values (exact, as before)
					end
					for part, state in base do
						local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
						if mesh == nil or part.Transparency >= 1 then
							continue
						end
						local relative = pivot:ToObjectSpace(state.cframe)
						local R, p = relative.Rotation, relative.Position
						local rigidity = (part:GetAttribute("SD_Rigidity") :: number?) or 0
						local function k(axis: Vector3): number
							return 1 + ((R:VectorToWorldSpace(axis) * clamped).Magnitude - 1) * (1 - rigidity)
						end
						local scale = (state.scale :: Vector3)
							* Vector3.new(k(Vector3.xAxis), k(Vector3.yAxis), k(Vector3.zAxis))
						local offset = (state.offset :: Vector3) + R:VectorToObjectSpace(p * clamped - p)
						expectAxes((mesh.Scale - scale) * part.Size, Vector3.zero, eps, `{def.id} {part.Name} size`)
						expectAxes(mesh.Offset, offset, eps, `{def.id} {part.Name}.Offset`)
						frames += 1
						if last[part] == mesh.Scale then
							skipped += 1
						end
						last[part] = mesh.Scale
					end
				end
				deformer:rest()
				local change = firstChange(base)
				if change then
					error(`{def.id} did not rest exactly: {change}`)
				end
				deformer:destroy()
				model:Destroy()
			end
			expect.truthy(skipped > 0 and skipped < frames) -- some writes are skipped, never all of them
		end)

		-- Faces, looks and sections (squishy overhaul spec 2026-10-09 §3.2) ------------------------------------------

		local Kit = t.requireShared("Art/SquishyBlueprints/Kit")
		local Blueprints = t.requireShared("Art/SquishyBlueprints")
		local SquishRig = t.requireClient("Anim/SquishRig")
		local LOOKS = Config.Anim.rig.looks
		local DEFAULT_MAX_DEG = Config.Anim.rig.sections.maxDeg
		-- The looks each face state hides (spec §3.2 table); every other look part shows.
		local HIDDEN: { [string]: { [string]: boolean } } = {
			normal = { squishEye = true, squishMouth = true, tongue = true },
			squish = { eye = true, eyeArc = true, shine = true, mouth = true },
			wow = { mouth = true, squishEye = true, tongue = true },
		}

		-- A body with a hinged ear pair (sections EarL / EarR on Z), a back spot, an open mouth, the v2 face and its
		-- squish set. Built through options.blueprint; the deformer gets its sections through options.sections.
		local v, F = Kit.v, Kit.F
		local FIXTURE = {
			version = 2,
			scale = 1,
			parts = Kit.concat(
				{ { name = "Body", shape = "E", size = v(1.4, 1.2, 1.2), color = "FFE9A3", body = true } },
				Kit.pair({
					name = "EarL",
					shape = "E",
					size = v(0.3, 0.5, 0.2),
					pos = v(-0.35, 0.65, 0),
					rot = v(0, 10, 12),
					color = "D98E47",
					section = "EarL",
					contact = v(0.2, -1, 0),
				}),
				{
					{
						name = "Spot",
						shape = "E",
						size = v(0.12, 0.1, 0.04),
						face = F(0.3, 0.1, 0.6, "back"),
						color = "C49A45",
						look = "detail",
					},
					{
						name = "Gasp",
						shape = "E",
						size = v(0.1, 0.06, 0.04),
						face = F(0.22, -0.22, 0.6),
						color = "8A2440",
						look = "mouthOpen",
					},
				},
				Kit.eyes2(-0.25, 0.1, 0.08),
				Kit.catMouth(-0.12, 0.16),
				Kit.blush2(-0.42, -0.02, 0.07),
				Kit.squishFace(-0.25, 0.1, 0.08, { y = -0.12, w = 0.16 })
			),
			sections = Kit.pairSection(
				"EarL",
				{ pivot = v(-0.33, 0.48, 0), axis = "Z", amp = 1.2, flap = { deg = 20 } }
			),
			motion = {
				squeeze = { depth = 0.6, widen = 0.7, kRel = 40, cRel = 8 },
				feel = "foam",
				flight = { style = "tumble" },
			},
		}

		local function buildFixture(mode: string): Model
			return Builder.build("fixture", mode :: any, nil, { blueprint = FIXTURE :: any, roundedBox = false })
		end

		local function attachFixture(model: Model, twist: string?): any
			return SquishDeformer.attach(model, { sections = FIXTURE.sections :: any, twist = twist :: any })
		end

		local function checkFace(model: Model, state: string)
			for _, descendant in model:GetDescendants() do
				local look = descendant:GetAttribute("SD_Look")
				if descendant:IsA("BasePart") and type(look) == "string" then
					local wanted = if HIDDEN[state][look] then 1 else 0
					if descendant.Transparency ~= wanted then
						error(
							`{state}: {descendant.Name} ({look}) Transparency {descendant.Transparency} ~= {wanted}`,
							2
						)
					end
				end
			end
		end

		-- The §9.3 mesh values of a builder part (pivot = Root at the origin) for S, then × a look multiplier.
		local function formula(base: PartState, S: Vector3, mul: Vector3?): (Vector3, Vector3)
			local R, p = base.cframe.Rotation, base.cframe.Position
			local function k(axis: Vector3): number
				return (R:VectorToWorldSpace(axis) * S).Magnitude
			end
			local kv = Vector3.new(k(Vector3.xAxis), k(Vector3.yAxis), k(Vector3.zAxis))
			local scale = (base.scale :: Vector3) * kv * (mul or Vector3.one)
			return scale, (base.offset :: Vector3) + R:VectorToObjectSpace(p * S - p)
		end

		-- The rendered frame of a builder part relative to its model's Root: Held from the weld's C0 (C1 identity, no
		-- physics in tests), Viewport from the CFrame; then the mesh Offset.
		local function renderedOf(model: Model, part: BasePart): (CFrame, Vector3)
			local mesh = part:FindFirstChildWhichIsA("DataModelMesh") :: DataModelMesh
			local weld = part:FindFirstChildWhichIsA("Weld")
			local frame = if weld then weld.C0 else model:GetPivot():ToObjectSpace(part.CFrame)
			return frame * CFrame.new(mesh.Offset), part.Size * mesh.Scale
		end

		local function sameRendered(a: Model, b: Model, tolerance: number, label: string)
			for _, part in a:GetChildren() do
				if part:IsA("BasePart") and part ~= a.PrimaryPart then
					local other = b:FindFirstChild(part.Name) :: BasePart
					local fa, sa = renderedOf(a, part)
					local fb, sb = renderedOf(b, other)
					expectVector(fa.Position, fb.Position, tolerance, `{label} {part.Name} position`)
					expectVector(fa.LookVector, fb.LookVector, tolerance, `{label} {part.Name} look`)
					expectVector(fa.UpVector, fb.UpVector, tolerance, `{label} {part.Name} up`)
					expectVector(sa, sb, tolerance, `{label} {part.Name} size`)
				end
			end
		end

		t.test(
			"setFace shows and hides the face set by SD_Look, writes only on a change, and force re-applies",
			function()
				local model = buildFixture("Viewport")
				local built: { [BasePart]: number } = {}
				for _, descendant in model:GetDescendants() do
					if descendant:IsA("BasePart") then
						built[descendant] = descendant.Transparency
					end
				end
				local deformer = attachFixture(model)
				expect.equal(deformer:getFace(), "normal")
				checkFace(model, "normal")
				for _, state in { "squish", "wow", "normal", "squish" } do
					deformer:setFace(state)
					expect.equal(deformer:getFace(), state)
					checkFace(model, state)
				end
				-- An outside write stays until the face changes or force re-applies it.
				local chevron = partNamed(model, "SquishEyeUpL")
				chevron.Transparency = 0.5
				deformer:setFace("squish")
				expect.equal(chevron.Transparency, 0.5)
				deformer:setFace("squish", true)
				expect.equal(chevron.Transparency, 0)
				deformer:setFace("normal")
				for part, transparency in built do
					expect.equal(part.Transparency, transparency)
				end
				deformer:destroy()
				model:Destroy()
			end
		)

		t.test("hidden face parts are skipped while deformed and get the current values when shown", function()
			local model = buildFixture("Viewport")
			local base = snapshot(model)
			local deformer = attachFixture(model)
			local S = SquishDeformer.squash(0.3, "Y")
			deformer:setScale(S)
			for part, state in base do
				local look = part:GetAttribute("SD_Look")
				local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
				if mesh and HIDDEN.normal[look :: string] then
					expect.equal(mesh.Scale, state.scale)
					expect.equal(mesh.Offset, state.offset)
				end
			end
			local eye = meshOf(model, "EyeL")
			local eyeScale = eye.Scale
			deformer:setFace("squish")
			for part, state in base do
				local look = part:GetAttribute("SD_Look")
				local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
				if mesh and HIDDEN.normal[look :: string] then
					local scale, offset = formula(state, S)
					expectVector(mesh.Scale, scale, nil, `{part.Name}.Scale`)
					expectVector(mesh.Offset, offset, nil, `{part.Name}.Offset`)
				end
			end
			-- The eyes now hide: the next squash does not write them.
			deformer:setScale(SquishDeformer.squash(0.2, "Y"))
			expect.equal(eye.Scale, eyeScale)
			deformer:destroy()
			model:Destroy()
		end)

		t.test(
			"blink, wow eyes, cheeks and open mouths fold into mesh Scale; rest restores every value exactly",
			function()
				local model = buildFixture("Viewport")
				local base = snapshot(model)
				local deformer = attachFixture(model)
				local function scaleOf(name: string): Vector3
					return meshOf(model, name).Scale
				end
				local function baseOf(name: string): PartState
					return base[partNamed(model, name)]
				end
				local out = SquishRig.newOut()
				out.face, out.blink, out.cheek = "wow", 0.4, 1.3
				deformer:apply(out)
				expect.falsy(deformer:isResting())
				expectVector(scaleOf("EyeL"), (baseOf("EyeL").scale :: Vector3) * Vector3.new(1.3, 1.3 * 0.4, 1))
				expectVector(scaleOf("ShineL"), Vector3.zero) -- the blink is past half: the shine hides
				expectVector(scaleOf("BlushL"), (baseOf("BlushL").scale :: Vector3) * 1.3)
				expectVector(scaleOf("SquishMouth"), (baseOf("SquishMouth").scale :: Vector3) * LOOKS.wowSquishMouth)
				expectVector(scaleOf("Gasp"), (baseOf("Gasp").scale :: Vector3) * LOOKS.wowMouthOpen)
				out.face, out.blink, out.cheek = "squish", 1, 1
				deformer:apply(out)
				expectVector(scaleOf("Gasp"), (baseOf("Gasp").scale :: Vector3) * LOOKS.squishMouthOpen)
				-- With a squash the multipliers sit on the §9.3 values.
				local S = SquishDeformer.squash(0.25, "Y")
				out.face, out.blink, out.S = "normal", 0.6, S
				deformer:apply(out)
				local eyeScale, eyeOffset = formula(baseOf("EyeL"), S, Vector3.new(1, 0.6, 1))
				expectVector(scaleOf("EyeL"), eyeScale, nil, "EyeL.Scale")
				expectVector(meshOf(model, "EyeL").Offset, eyeOffset, nil, "EyeL.Offset")
				expectVector(scaleOf("ShineL"), (formula(baseOf("ShineL"), S))) -- 0.6: the shine shows
				-- Rest: every value back, bit for bit.
				deformer:apply(SquishRig.newOut())
				expect.truthy(deformer:isResting())
				expect.equal(firstChange(base), nil)
				checkFace(model, "normal")
				deformer:destroy()
				model:Destroy()
			end
		)

		t.test(
			"sections: θ = 0 renders like the mesh path, a turned part rotates about its pivot, ±maxDeg rests",
			function()
				for _, mode in { "Viewport", "Held" } do
					local turned, plain = buildFixture(mode), buildFixture(mode)
					local base = snapshot(turned)
					local baseC0 = weldSnapshot(turned)
					local a, b = attachFixture(turned), attachFixture(plain)
					expect.deepEqual(a:sectionNames(), { "EarL", "EarR" })
					local S = Vector3.new(1.2, 0.7, 1.15)
					a:setSections({ 0, 0 })
					a:setScale(S)
					b:setScale(S)
					sameRendered(turned, plain, TOLERANCE, `{mode} θ = 0`)
					-- Turned: EarL about its pivot on Z, then the squash; EarR the other way.
					local theta = math.rad(25)
					a:setSections({ theta, -theta })
					local ear = partNamed(turned, "EarL")
					local h = FIXTURE.sections.EarL.pivot
					local Q = CFrame.fromAxisAngle(Vector3.zAxis, theta)
					local relative = base[ear].cframe
					local p = h + Q:VectorToWorldSpace(relative.Position - h)
					local R = Q * relative.Rotation
					local frame, size = renderedOf(turned, ear)
					expectVector(frame.Position, p * S, TOLERANCE, `{mode} EarL centre`)
					expectVector(frame.LookVector, R.LookVector, TOLERANCE, `{mode} EarL look`)
					expectVector(frame.UpVector, R.UpVector, TOLERANCE, `{mode} EarL up`)
					local kv =
						Vector3.new((R.XVector * S).Magnitude, (R.YVector * S).Magnitude, (R.ZVector * S).Magnitude)
					expectVector(size, ear.Size * kv, TOLERANCE, `{mode} EarL size`)
					-- After ±maxDeg and squashes, rest gives back every CFrame, C0 and mesh value bit for bit.
					for _, angle in { math.rad(DEFAULT_MAX_DEG), -math.rad(DEFAULT_MAX_DEG) } do
						a:setSections({ angle, angle })
						a:setScale(SquishDeformer.squash(0.3, "Y"))
					end
					a:rest()
					expect.truthy(a:isResting())
					expect.equal(firstChange(base), nil)
					for weld, c0 in baseC0 do
						expect.equal(weld.C0, c0)
					end
					a:destroy()
					b:destroy()
					turned:Destroy()
					plain:Destroy()
				end
			end
		)

		t.test(
			"a section part at θ = 0 takes the mesh path: no C0 or CFrame write, and back to base when it stops",
			function()
				for _, mode in { "Held", "Viewport" } do
					local turned, plain = buildFixture(mode), buildFixture(mode)
					local base = snapshot(turned)
					local baseC0 = weldSnapshot(turned)
					local a, b = attachFixture(turned), attachFixture(plain)
					local ear = partNamed(turned, "EarL")
					local earWeld = ear:FindFirstChildWhichIsA("Weld")
					local S = Vector3.new(1.15, 0.75, 1.1)
					a:setSections({ 0, 0 })
					a:setScale(S)
					b:setScale(S)
					-- At rest angles the section parts never move: the weld C0 (Held) and the CFrame (Viewport) keep their base.
					expect.equal(firstMove(base), nil)
					for weld, c0 in baseC0 do
						expect.equal(weld.C0, c0)
					end
					sameRendered(turned, plain, TOLERANCE, `{mode} θ = 0`)
					-- Turned, the part moves; back at θ = 0 its base C0 or CFrame is written exactly and the render matches.
					a:setSections({ math.rad(20), -math.rad(20) })
					if earWeld then
						expect.truthy(earWeld.C0 ~= baseC0[earWeld])
					else
						expect.truthy(ear.CFrame ~= base[ear].cframe)
					end
					a:setSections({ 0, 0 })
					expect.equal(firstMove(base), nil)
					for weld, c0 in baseC0 do
						expect.equal(weld.C0, c0)
					end
					sameRendered(turned, plain, TOLERANCE, `{mode} back at θ = 0`)
					a:rest()
					expect.equal(firstChange(base), nil)
					a:destroy()
					b:destroy()
					turned:Destroy()
					plain:Destroy()
				end
			end
		)

		t.test("setScale never moves a part while the sections are off", function()
			local model = buildFixture("Viewport")
			local base = snapshot(model)
			local deformer = attachFixture(model)
			for _, S in { SquishDeformer.squash(0.3, "Y"), Vector3.new(1.2, 0.8, 1.05) } do
				deformer:setScale(S)
				expect.equal(firstMove(base), nil)
			end
			deformer:destroy()
			model:Destroy()
		end)

		t.test("Viewport sections at θ = 0 still match the mesh path after many twisted frames", function()
			local turned, plain = buildFixture("Viewport"), buildFixture("Viewport")
			local a, b = attachFixture(turned, "pivot"), attachFixture(plain, "pivot")
			a:setSections({ 0, 0 })
			for frame = 1, 90 do
				local S = SquishDeformer.squash(0.3 * math.sin(frame * 0.2), "Y")
				local twist = math.rad(6) * math.sin(frame * 0.15)
				a:set(S, twist)
				b:set(S, twist)
			end
			sameRendered(turned, plain, 1e-3, "after 90 twisted frames")
			a:destroy()
			b:destroy()
			turned:Destroy()
			plain:Destroy()
		end)

		t.test("a tier drop and a pool return leave no section angle or face behind", function()
			local model = buildFixture("Held")
			local base = snapshot(model)
			local baseC0 = weldSnapshot(model)
			local deformer = attachFixture(model)
			local ear = partNamed(model, "EarL")
			local earWeld = ear:FindFirstChildWhichIsA("Weld") :: Weld
			local S = SquishDeformer.squash(0.2, "Y")
			local out = SquishRig.newOut()
			out.S, out.face, out.sectionsOn, out.sections = S, "squish", true, { 0.4, -0.4 }
			deformer:apply(out)
			expect.truthy(earWeld.C0 ~= baseC0[earWeld])
			checkFace(model, "squish")
			-- Tier drop: sections off and the face back to normal; the squash goes on through the mesh path.
			out.sectionsOn, out.face = false, "normal"
			deformer:apply(out)
			expect.equal(earWeld.C0, baseC0[earWeld])
			checkFace(model, "normal")
			local _, earOffset = formula(base[ear], S)
			expectVector(meshOf(model, "EarL").Offset, earOffset, nil, "EarL mesh path Offset")
			-- Pool return: rest() after a squeeze with turned sections and the squish face.
			out.sectionsOn, out.face = true, "squish"
			deformer:apply(out)
			deformer:rest()
			expect.truthy(deformer:isResting())
			expect.equal(deformer:getFace(), "normal")
			checkFace(model, "normal")
			expect.equal(firstChange(base), nil)
			for weld, c0 in baseC0 do
				expect.equal(weld.C0, c0)
			end
			deformer:destroy()
			model:Destroy()
		end)

		t.test("contact points stay inside their holder at every extreme and with sections at ±1.1·maxDeg", function()
			local throw = Config.Anim.throw
			-- Stand-in for the shape library's RoundedBox (no mesh: the deformer resizes it), next to the B fallback.
			local template = Instance.new("Part")
			local problems: { string } = {}
			local axisOf: { [string]: string } = {}
			for _, def in Catalog.list() do
				axisOf[def.blueprintId] = def.anim.squeezeAxis
			end
			local entries: { { id: string, blueprint: any, fixture: boolean } } = {}
			for id, blueprint in Blueprints do
				if blueprint.motion then
					table.insert(entries, { id = id, blueprint = blueprint, fixture = false })
				end
			end
			table.sort(entries, function(x, y)
				return x.id < y.id
			end)
			table.insert(entries, { id = "fixture", blueprint = FIXTURE, fixture = true })
			for _, entry in entries do
				local motion = entry.blueprint.motion
				local axis = axisOf[entry.id] or "Y"
				local cases: { { label: string, S: Vector3, turn: number } } = {}
				local depthS = Vector3.one
				for _, extreme in SquishRig.extremes(motion, axis) do
					table.insert(cases, { label = extreme.label, S = extreme.S, turn = 0 })
					if extreme.label == "widening" then
						depthS = extreme.S
					end
				end
				table.insert(cases, {
					label = "throwAnticipation",
					S = SquishDeformer.axisScale(throw.anticipationC, throw.anticipationW, axis),
					turn = 0,
				})
				table.insert(
					cases,
					{ label = "maxSquash", S = SquishDeformer.squash(DEFORM.maxSquash, axis), turn = 0 }
				)
				local sections = entry.blueprint.sections
				if sections then
					for _, turn in { 1.1, -1.1 } do
						table.insert(cases, { label = `sections {turn} rest`, S = Vector3.one, turn = turn })
						table.insert(cases, { label = `sections {turn} depth`, S = depthS, turn = turn })
					end
				end
				local variants: { BasePart | false } = { false, template }
				for _, roundedBox in variants do
					local model: Model = Builder.build(
						entry.id,
						"Viewport",
						nil,
						{ roundedBox = roundedBox, blueprint = if entry.fixture then entry.blueprint else nil }
					)
					local pivot = model:GetPivot()
					local deformer =
						SquishDeformer.attach(model, if entry.fixture then { sections = sections } else nil)
					local names = deformer:sectionNames()
					local angles = table.create(#names, 0)
					-- Hidden parts are not written (spec §3.2), so each case is checked in every face state, shown parts only.
					for _, case in cases do
						for _, face in { "normal", "squish", "wow" } do
							if case.turn ~= 0 then
								for i, name in names do
									angles[i] = case.turn * math.rad(sections[name].maxDeg or DEFAULT_MAX_DEG)
								end
								deformer:setSections(angles)
							else
								deformer:setSections(nil)
							end
							deformer:setFace(face)
							deformer:setScale(case.S)
							local frames: { [string]: CFrame } = {}
							local sizes: { [string]: Vector3 } = {}
							local shapes: { [string]: unknown } = {}
							local bodies: { string } = {}
							for _, child in model:GetChildren() do
								if child:IsA("BasePart") and child ~= model.PrimaryPart then
									frames[child.Name], sizes[child.Name] = renderedShape(pivot, child)
									shapes[child.Name] = child:GetAttribute("SD_Shape")
									if child:GetAttribute("SD_Body") == true then
										table.insert(bodies, child.Name)
									end
								end
							end
							local where = `{entry.id}/{if roundedBox then "RB" else "B"}/{case.label}/{face}`
							for _, child in model:GetChildren() do
								local name = child.Name
								local contact = child:GetAttribute("SD_Contact")
								if typeof(contact) ~= "Vector3" or (child :: BasePart).Transparency >= 1 then
									continue
								end
								local point = frames[name]:PointToWorldSpace((contact :: Vector3) * sizes[name] / 2)
								local holderName = child:GetAttribute("SD_ContactWith")
								local holders = bodies
								if type(holderName) == "string" then
									holders = if frames[holderName]
										then { holderName }
										else { holderName .. "_HalfL", holderName .. "_HalfR" }
								end
								local inside = false
								for _, holder in holders do
									if
										holder ~= name
										and frames[holder]
										and shapeContains(shapes[holder], frames[holder], sizes[holder], point)
									then
										inside = true
										break
									end
								end
								if not inside then
									table.insert(problems, `{where}: {name} left {holderName or "the body"}`)
								end
							end
						end
					end
					deformer:destroy()
					model:Destroy()
				end
			end
			template:Destroy()
			if #problems > 0 then
				error(`{#problems} problem(s): {table.concat(problems, "; ")}`)
			end
		end)
	else
		print("[UnitTest] SquishDeformer_Test: Art/SquishyBuilder or Catalog not available; builder case skipped")
	end
end
