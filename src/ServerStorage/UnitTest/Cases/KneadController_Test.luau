--!strict
-- KneadController_Test: unit tests for the pure parts of StarterPlayerScripts.Client.Controllers.KneadController, the
-- knead screen in Inspect (spec phase2-squeeze §3.2, §3.6, §3.7). Server only (ServerStorage.UnitTest). Edit mode:
-- built models (Art/SquishyBuilder) and hand-made parts; no EditableMesh, image, sound or input. Contract:
--   * readModel: the shell takes the SD_Body parts of shape E, B or RB that are not section parts, in pivot space with
--     their colour; an RB part without a mesh gets its rest size back (its Size over the deformer's kv, SD_Rigidity
--     counted); every other visual part rides (never the Root), anchored at its contact point (SD_Contact in its unit
--     space) or else its centre; the face box covers the SD_Face parts (none: no box); no such body part: no shell;
--   * nearestVertices: each point gets the closest deforming shell vertex (never a bounds anchor);
--   * rides: a rider's offset is its anchor vertex's shown minus rest position, written into the same table;
--   * restRay: a stage ray in the shell's rest space (the pivot and the deformer's scale undone, a ray stays a ray);
--   * inputKind: Touch, any GamepadN, else the keyboard; view: the feel's Squeeze and Coat rows with that input's help;
--   * tiltTarget: the settle eases home first (fp.js:483), else a crunch that is not dragged tilts to show the top
--     (fp.js:484); a drag, ReducedMotion or nothing to do leaves the view alone.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Knead = t.requireClient("Controllers/KneadController")
	local ShellGeometry = t.requireClient("Anim/ShellGeometry")
	local KneadFormat = t.requireClient("UI/KneadFormat")
	local Builder = t.requireShared("Art/SquishyBuilder")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local EPS = 1e-4

	local function near(a: Vector3, b: Vector3, eps: number?)
		expect.near((a - b).Magnitude, 0, eps or EPS)
	end

	-- A model with an invisible Root away from the origin (so pivot space is not world space).
	local function handModel(): (Model, CFrame)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(0.2, 0.2, 0.2)
		root.CFrame = CFrame.new(10, 2, -3) * CFrame.Angles(0, math.rad(30), 0)
		root.Parent = model
		model.PrimaryPart = root
		return model, root.CFrame
	end

	local function addPart(
		model: Model,
		name: string,
		attributes: { [string]: any },
		cframe: CFrame,
		size: Vector3,
		mesh: boolean
	): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe
		part.Anchored = true
		part.Color = Color3.fromRGB(200, 120, 90)
		for key, value in attributes do
			part:SetAttribute(key, value)
		end
		if mesh then
			local special = Instance.new("SpecialMesh")
			special.MeshType = Enum.MeshType.Sphere
			special.Parent = part
		end
		part.Parent = model
		return part
	end

	local function bodyOf(reading: any, part: BasePart): any
		for _, body in reading.body do
			if body.part == part then
				return body
			end
		end
		return nil
	end

	local function riderOf(reading: any, part: BasePart): any
		for _, rider in reading.riders do
			if rider.part == part then
				return rider
			end
		end
		return nil
	end

	t.test("readModel: the shell takes the toy's E / B / RB body parts; every other visual part rides", function()
		local model = Builder.build("butter", "Viewport", 1)
		local reading = Knead.readModel(model, Vector3.one)
		local pivot = model:GetPivot()
		expect.equal(#reading.body, 3) -- Body, Wrapper and Label (butter.luau)
		local inShell: { [BasePart]: boolean } = {}
		for _, body in reading.body do
			inShell[body.part] = true
			expect.equal(body.part:GetAttribute("SD_Body"), true)
			expect.truthy(body.shape == "E" or body.shape == "B" or body.shape == "RB")
			near(body.cframe.Position, pivot:PointToObjectSpace(body.part.CFrame.Position))
			near(body.size, body.part.Size)
			expect.equal(body.color, body.part.Color)
		end
		local riding: { [BasePart]: boolean } = {}
		for _, rider in reading.riders do
			expect.falsy(inShell[rider.part])
			expect.truthy(rider.part ~= model.PrimaryPart)
			riding[rider.part] = true
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= model.PrimaryPart then
				expect.truthy(inShell[descendant] or riding[descendant]) -- every visual part is in one of them
			end
		end
		expect.truthy(#reading.riders > 0)
		expect.truthy(reading.faceMin ~= nil and reading.faceMax ~= nil)
		model:Destroy()
	end)

	t.test("readModel: an RB part's rest size undoes the deformer's scale; W and section body parts ride", function()
		local model, pivot = handModel()
		local S = Vector3.new(1.2, 0.8, 1)
		local rigidity = 0.5
		local kv = Vector3.one + (S - Vector3.one) * (1 - rigidity)
		local rb = addPart(
			model,
			"Body",
			{ SD_Body = true, SD_Shape = "RB", SD_Rigidity = rigidity },
			pivot,
			Vector3.new(2, 1, 1) * kv,
			false
		)
		local belly = addPart(
			model,
			"Belly",
			{ SD_Body = true, SD_Shape = "E" },
			pivot * CFrame.new(0, 0.2, -0.3),
			Vector3.new(1, 0.8, 0.6),
			true
		)
		local fin = addPart(
			model,
			"Fin",
			{ SD_Body = true, SD_Shape = "W" },
			pivot * CFrame.new(0.8, 0, 0),
			Vector3.new(0.1, 0.4, 0.3),
			true
		)
		local wing = addPart(
			model,
			"Wing",
			{ SD_Body = true, SD_Shape = "E", SD_Section = "wingL" },
			pivot * CFrame.new(-1, 0, 0),
			Vector3.new(0.5, 0.2, 0.4),
			true
		)
		local reading = Knead.readModel(model, S)
		expect.equal(#reading.body, 2)
		local rbBody, bellyBody = bodyOf(reading, rb), bodyOf(reading, belly)
		expect.truthy(rbBody ~= nil and bellyBody ~= nil)
		near(rbBody.size, Vector3.new(2, 1, 1))
		near(rbBody.cframe.Position, Vector3.zero)
		expect.equal(rbBody.shape, "RB")
		near(bellyBody.size, Vector3.new(1, 0.8, 0.6)) -- a mesh part's Size never scales (mesh Scale does)
		near(bellyBody.cframe.Position, Vector3.new(0, 0.2, -0.3))
		expect.truthy(riderOf(reading, fin) ~= nil)
		expect.truthy(riderOf(reading, wing) ~= nil)
		expect.equal(riderOf(reading, model.PrimaryPart :: BasePart), nil)
		expect.equal(reading.faceMin, nil) -- no face parts
		model:Destroy()
		-- No E / B / RB body part: no shell.
		local bare = handModel()
		expect.equal(#Knead.readModel(bare, Vector3.one).body, 0)
		bare:Destroy()
	end)

	t.test(
		"readModel: a rider is anchored at its contact point, else its centre; the face box covers SD_Face",
		function()
			local model, pivot = handModel()
			addPart(model, "Body", { SD_Body = true, SD_Shape = "E" }, pivot, Vector3.new(2, 2, 2), true)
			local turn = CFrame.Angles(0, math.rad(20), 0)
			local contact = Vector3.new(0, 0, 1)
			local eye = addPart(
				model,
				"Eye",
				{ SD_Face = true, SD_Contact = contact },
				pivot * CFrame.new(0.3, 0.2, -0.95) * turn,
				Vector3.new(0.2, 0.3, 0.1),
				true
			)
			local curl = addPart(model, "Curl", {}, pivot * CFrame.new(0, 1.1, 0), Vector3.new(0.4, 0.2, 0.3), true)
			local reading = Knead.readModel(model, Vector3.one)
			local expectedEye = pivot:PointToObjectSpace(eye.CFrame:PointToWorldSpace(contact * eye.Size / 2))
			near(riderOf(reading, eye).point, expectedEye)
			near(riderOf(reading, curl).point, Vector3.new(0, 1.1, 0))
			-- The face box: the eye's eight corners in pivot space.
			local local0 = CFrame.new(0.3, 0.2, -0.95) * turn
			local lo = { math.huge, math.huge, math.huge }
			local hi = { -math.huge, -math.huge, -math.huge }
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = local0:PointToWorldSpace(Vector3.new(sx, sy, sz) * eye.Size / 2)
						for axis, value in { corner.X, corner.Y, corner.Z } do
							lo[axis] = math.min(lo[axis], value)
							hi[axis] = math.max(hi[axis], value)
						end
					end
				end
			end
			near(reading.faceMin, Vector3.new(lo[1], lo[2], lo[3]))
			near(reading.faceMax, Vector3.new(hi[1], hi[2], hi[3]))
			model:Destroy()
		end
	)

	t.test("nearestVertices: each point gets the closest deforming vertex, never a bounds anchor", function()
		local shell =
			ShellGeometry.build({ { shape = "E", cframe = CFrame.identity, size = Vector3.new(2, 1, 1) } }, "Low")
		local points = { Vector3.new(5, 0, 0), Vector3.new(0, -3, 0), Vector3.new(0.2, 0.1, -0.4) }
		local anchors = Knead.nearestVertices(shell, points)
		expect.equal(#anchors, #points)
		for k, p in points do
			local best, bestDistance = 0, math.huge
			for i = 1, shell.count do
				local d = (Vector3.new(shell.px[i], shell.py[i], shell.pz[i]) - p).Magnitude
				if d < bestDistance then
					best, bestDistance = i, d
				end
			end
			expect.equal(anchors[k], best)
		end
		expect.near(shell.px[anchors[1]], 1, 1e-3) -- the +X tip of the ellipsoid
		expect.near(shell.py[anchors[2]], -0.5, 1e-3) -- its bottom
	end)

	t.test("rides: a rider's offset is its anchor vertex's shown minus rest position, in the same table", function()
		local shell =
			ShellGeometry.build({ { shape = "B", cframe = CFrame.identity, size = Vector3.new(1, 1, 1) } }, "Low")
		local px: { number }, py: { number }, pz: { number } =
			table.clone(shell.px), table.clone(shell.py), table.clone(shell.pz)
		local a, b = Instance.new("Part"), Instance.new("Part")
		local riders = { { part = a, point = Vector3.zero }, { part = b, point = Vector3.zero } }
		local anchors = { 3, 7 }
		px[3] += 0.1
		py[3] -= 0.05
		pz[7] += 0.2
		local offsets: { [BasePart]: Vector3 } = {}
		Knead.rides(offsets, riders, anchors, shell, px, py, pz)
		near(offsets[a], Vector3.new(0.1, -0.05, 0), 1e-6)
		near(offsets[b], Vector3.new(0, 0, 0.2), 1e-6)
		px[3], py[3] = shell.px[3], shell.py[3]
		Knead.rides(offsets, riders, anchors, shell, px, py, pz)
		near(offsets[a], Vector3.zero, 1e-6)
	end)

	t.test("restRay: a stage ray in the shell's rest space (the pivot and the deformer's scale undone)", function()
		local pivot = CFrame.new(3, 1, -2) * CFrame.Angles(0, math.rad(90), math.rad(10))
		local S = Vector3.new(2, 0.5, 1.25)
		local q = Vector3.new(0.3, -0.2, 0.5) -- a rest point; it shows at pivot · (q ∘ S)
		local shown = pivot:PointToWorldSpace(q * S)
		local origin = shown + Vector3.new(0.5, 1, 4)
		local direction = (shown - origin) * 3
		local o, d = Knead.restRay(pivot, S, origin, direction)
		local along = (q - o):Dot(d) / d:Dot(d)
		near(o + d * along, q, 1e-5) -- the rest ray passes through q ...
		expect.near(along, 1 / 3, 1e-5) -- ... at the same parameter (a linear map)
		near(o, pivot:PointToObjectSpace(origin) / S, 1e-5)
	end)

	t.test("inputKind and view: Touch, any gamepad, else the keyboard; the feel's rows with that help", function()
		expect.equal(Knead.inputKind(Enum.UserInputType.Touch), "Touch")
		expect.equal(Knead.inputKind(Enum.UserInputType.Gamepad1), "Gamepad")
		expect.equal(Knead.inputKind(Enum.UserInputType.Gamepad4), "Gamepad")
		expect.equal(Knead.inputKind(Enum.UserInputType.MouseMovement), "Keyboard")
		expect.equal(Knead.inputKind(Enum.UserInputType.Keyboard), "Keyboard")
		local view = Knead.view("mochi", "Gamepad")
		local rows = KneadFormat.rows("mochi")
		expect.equal(view.squeeze, rows.squeeze)
		expect.equal(view.coat, rows.coat)
		expect.equal(view.help, KneadFormat.help("Gamepad"))
		expect.equal(Knead.view("foam", "Touch").help, KneadFormat.help("Touch"))
	end)

	t.test("tiltTarget: the settle eases home first, else an undragged crunch shows the top; else nothing", function()
		local view = Config.Knead.view
		local pitch, rate = Knead.tiltTarget(true, 0, false, false)
		expect.near(pitch :: number, math.deg(view.crunchPitchRad), 1e-9)
		expect.equal(rate, view.crunchRate)
		pitch, rate = Knead.tiltTarget(false, 0.5, false, false)
		expect.near(pitch :: number, math.deg(view.homePitchRad), 1e-9)
		expect.equal(rate, view.homeRate)
		pitch = Knead.tiltTarget(true, 0.5, false, false) -- the settle before the crunch (fp.js:483-484)
		expect.near(pitch :: number, math.deg(view.homePitchRad), 1e-9)
		expect.equal(Knead.tiltTarget(true, 0, true, false), nil) -- a drag turns the view itself
		expect.equal(Knead.tiltTarget(false, 0.5, true, false), nil)
		expect.equal(Knead.tiltTarget(true, 0, false, true), nil) -- ReducedMotion: no camera move of its own
		expect.equal(Knead.tiltTarget(false, 0, false, false), nil)
	end)
end
