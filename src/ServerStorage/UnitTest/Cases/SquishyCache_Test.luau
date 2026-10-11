--!strict
-- SquishyCache_Test: unit tests for StarterPlayerScripts.Client.Models.SquishyCache. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §2.4, §8.1 rules 1, 3, 4; §10.4 step 5):
--   * one built template per (blueprint id, build mode, scale); every use gets its own clone (never the template);
--   * a squishy id is mapped to its Catalog blueprintId; other ids (gift_box, ...) are blueprint ids;
--   * a blueprint that fails to build gives a labelled placeholder (SD_Placeholder, SD_BlueprintId, Root PrimaryPart)
--     and ONE warning per blueprint id; the placeholder follows the build-mode rules (Viewport anchored, no welds;
--     Held unanchored and welded) and every part is non-colliding, non-query, non-touch and massless;
--   * the default cache builds the 8 catalog squishies with the real SquishyBuilder (no placeholder);
--   * model slots (SquishyCache header): a Model in the slot folder named after the blueprint id replaces the
--     blueprint: fitted uniformly so its longest side equals the blueprint's for that mode and scale, its pivot
--     becomes the Root at the origin (a new 0.2³ invisible PrimaryPart; a reserved "Root" part is removed), parts get
--     the builder flags and the build-mode rules (Viewport anchored, no welds; World/Held explicit Welds with C0 to
--     Root, never WeldConstraints), scripts/sounds/lights/emitters/GUIs/joints/tags are stripped while Decals and
--     materials stay, the builder's model attributes are copied and SD_ModelSlot is set; the team's source model is
--     never changed; an invalid slot (not a Model, not cloneable, no parts, > 64 parts) falls back to the blueprint
--     with ONE warning per id; the folder is read when a template is built, so clear() picks up a removed slot.
-- Private caches (SquishyCache.new) with a counting fake builder keep the cases independent; nothing is parented
-- (slot folders are unparented in-memory Folders passed to SquishyCache.new; the live place is never touched).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

type Call = { id: string, mode: string, scale: number? }

local BLUEPRINT_BODY = Vector3.new(1.6, 1.2, 1.0) -- the fake blueprint's body: longest side 1.6 at scale 1
local SLOT_PIVOT = CFrame.new(50, 10, -20) * CFrame.Angles(0, 0.5, 0) -- the team model sits away from the origin
local TOLERANCE = 1e-4 -- sizes and CFrames are stored as float32
-- Classes a slot model must lose (IsA names).
local STRIPPED = {
	"LuaSourceContainer",
	"Sound",
	"Light",
	"ParticleEmitter",
	"LayerCollector",
	"Highlight",
	"WeldConstraint",
	"Humanoid",
}

-- A minimal valid built model (Root PrimaryPart + one part), named after the blueprint.
local function fakeModel(id: string): Model
	local model = Instance.new("Model")
	model.Name = id
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Parent = model
	model.PrimaryPart = root
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Parent = model
	return model
end

local function partsOf(model: Model): { BasePart }
	local list: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

-- What the real builder returns, in miniature: Root + a Body of BLUEPRINT_BODY × scale and the model attributes.
local function blueprintModel(id: string, mode: string, scale: number?): Model
	local s = scale or 1
	local model = fakeModel(id)
	local body = model:FindFirstChild("Body") :: Part
	body.Size = BLUEPRINT_BODY * s
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	model:SetAttribute("SD_BlueprintId", id)
	model:SetAttribute("SD_BlueprintVersion", 3)
	model:SetAttribute("SD_Scale", s)
	model:SetAttribute("SD_Mode", mode)
	return model
end

-- A team-made slot model: 5× the blueprint size, away from the origin and turned, a nested Model, a builder-style
-- "Root" as PrimaryPart at the pivot, and everything the cache must strip (scripts, sound, light, emitter, GUIs,
-- highlight, a WeldConstraint, a tag) or keep (a Decal, the Fabric material).
local function slotModel(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local body = Instance.new("MeshPart")
	body.Name = "Body"
	body.Size = Vector3.new(8, 6, 5)
	body.CFrame = SLOT_PIVOT
	body.Anchored = true
	body.CanCollide = true
	body.Material = Enum.Material.Fabric
	body:AddTag("SD_TestTag")
	body.Parent = model
	local eye = Instance.new("Part")
	eye.Name = "EyeL"
	eye.Size = Vector3.new(1, 1, 0.5)
	eye.CFrame = SLOT_PIVOT * CFrame.new(1, 0.5, -2.6)
	eye.Parent = model
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Front
	decal.Parent = eye
	local details = Instance.new("Model")
	details.Name = "Details"
	details.Parent = model
	local tail = Instance.new("Part")
	tail.Name = "Tail"
	tail.Size = Vector3.new(1, 1, 2)
	tail.CFrame = SLOT_PIVOT * CFrame.new(0, -1, 3) * CFrame.Angles(0.4, 0, 0)
	tail.Parent = details
	local oldRoot = Instance.new("Part")
	oldRoot.Name = "Root"
	oldRoot.Size = Vector3.one * 0.2
	oldRoot.Transparency = 1
	oldRoot.CFrame = SLOT_PIVOT
	oldRoot.Parent = model
	model.PrimaryPart = oldRoot

	for _, className in { "Script", "LocalScript", "ModuleScript", "Sound", "BillboardGui", "Humanoid" } do
		Instance.new(className).Parent = model
	end
	for _, className in { "PointLight", "ParticleEmitter", "SurfaceGui", "Highlight" } do
		Instance.new(className).Parent = body
	end
	local weldConstraint = Instance.new("WeldConstraint")
	weldConstraint.Part0 = body
	weldConstraint.Part1 = eye
	weldConstraint.Parent = body
	model:SetAttribute("SD_Placeholder", true) -- the model's own attributes are replaced
	return model
end

-- Longest side of the axis-aligned box (in the model's pivot space) around every part except the PrimaryPart.
local function longestSide(model: Model): number
	local pivot = model:GetPivot()
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, part in partsOf(model) do
		if part == model.PrimaryPart then
			continue
		end
		local frame = pivot:ToObjectSpace(part.CFrame)
		local half = part.Size / 2
		local x, y, z = frame.XVector * half.X, frame.YVector * half.Y, frame.ZVector * half.Z
		local extent = Vector3.new(
			math.abs(x.X) + math.abs(y.X) + math.abs(z.X),
			math.abs(x.Y) + math.abs(y.Y) + math.abs(z.Y),
			math.abs(x.Z) + math.abs(y.Z) + math.abs(z.Z)
		)
		lo = lo:Min(frame.Position - extent)
		hi = hi:Max(frame.Position + extent)
	end
	local size = hi - lo
	return math.max(size.X, size.Y, size.Z)
end

return function(t: Context)
	local SquishyCache = t.requireClient("Models/SquishyCache")
	local Catalog = t.requireShared("Catalog")
	local expect = t.expect

	-- A cache whose builder records its calls; `fail` makes every build raise.
	local function makeCache(fail: boolean?): (any, { Call }, { string })
		local calls: { Call } = {}
		local warnings: { string } = {}
		local cache = SquishyCache.new(function(id: string, mode: string, scale: number?): Model
			table.insert(calls, { id = id, mode = mode, scale = scale })
			if fail then
				error("broken blueprint")
			end
			return fakeModel(id)
		end, function(message: string)
			table.insert(warnings, message)
		end)
		return cache, calls, warnings
	end

	t.test("builds one template per id, mode and scale and hands out fresh clones", function()
		local cache, calls = makeCache()
		local a = cache:clone("toast", "Held")
		local b = cache:clone("toast", "Held")
		expect.equal(#calls, 1)
		expect.truthy(a ~= b)
		expect.equal(a.Parent, nil)
		expect.equal(a.Name, "toast")
		expect.truthy(a.PrimaryPart ~= nil)
		a:Destroy() -- destroying a clone never touches the template
		local c = cache:clone("toast", "Held")
		expect.truthy(c.PrimaryPart ~= nil)
		expect.equal(#calls, 1)
		cache:clone("toast", "Viewport")
		cache:clone("toast", "Held", 2.5)
		expect.equal(#calls, 3)
		expect.equal(cache:templateCount(), 3)
		cache:clear()
	end)

	t.test("no scale and scale 1 share a template; the scale is passed to the builder", function()
		local cache, calls = makeCache()
		cache:clone("banana", "World")
		cache:clone("banana", "World", 1)
		expect.equal(#calls, 1)
		cache:clone("banana", "World", 0.8)
		expect.equal(#calls, 2)
		expect.equal(calls[2].scale, 0.8)
		cache:clear()
	end)

	t.test("maps squishy ids to their Catalog blueprintId and passes other ids through", function()
		local cache, calls = makeCache()
		for _, def in Catalog.list() do
			cache:clone(def.id, "Viewport")
			expect.equal(calls[#calls].id, def.blueprintId)
		end
		cache:clone("gift_box", "Viewport", 4)
		expect.equal(calls[#calls].id, "gift_box")
		cache:clear()
	end)

	t.test("a failing blueprint gives a labelled placeholder and one warning per blueprint id", function()
		local cache, _, warnings = makeCache(true)
		local held = cache:clone("dragon", "Held")
		local viewport = cache:clone("dragon", "Viewport")
		cache:clone("dragon", "World", 2)
		expect.equal(#warnings, 1)
		expect.truthy(string.find(warnings[1], "dragon", 1, true) ~= nil)
		expect.truthy(SquishyCache.isPlaceholder(held))
		expect.equal(held:GetAttribute("SD_BlueprintId"), "dragon")
		expect.truthy(held.PrimaryPart ~= nil)
		expect.equal((held.PrimaryPart :: BasePart).Name, "Root")
		cache:clone("bird", "Held")
		expect.equal(#warnings, 2)
		-- The same key is not rebuilt (and not warned) again.
		cache:clone("dragon", "Held")
		expect.equal(#warnings, 2)
		held:Destroy()
		viewport:Destroy()
		cache:clear()
	end)

	t.test("the placeholder follows the build-mode rules and is purely cosmetic", function()
		local cache = makeCache(true)
		local held = cache:clone("toast", "Held")
		local viewport = cache:clone("toast", "Viewport")
		local world = cache:clone("toast", "World")
		for _, part in partsOf(held) do
			expect.falsy(part.Anchored)
			expect.truthy(part.Massless)
			expect.falsy(part.CanCollide)
			expect.falsy(part.CanQuery)
			expect.falsy(part.CanTouch)
		end
		expect.truthy(held:FindFirstChildWhichIsA("Weld", true) ~= nil)
		expect.equal(held:FindFirstChildWhichIsA("WeldConstraint", true), nil)
		for _, part in partsOf(viewport) do
			expect.truthy(part.Anchored)
		end
		expect.equal(viewport:FindFirstChildWhichIsA("Weld", true), nil)
		expect.truthy((world.PrimaryPart :: BasePart).Anchored)
		for _, part in partsOf(world) do
			if part ~= world.PrimaryPart then
				expect.falsy(part.Anchored)
			end
		end
		for _, model in { held, viewport, world } do
			for _, descendant in model:GetDescendants() do
				local kind = descendant.ClassName
				expect.truthy(descendant:IsA("BasePart") or kind == "SpecialMesh" or kind == "Weld")
			end
		end
		cache:clear()
	end)

	t.test("a builder result that is not a usable Model becomes a placeholder", function()
		local warnings: { string } = {}
		local cache = SquishyCache.new(function(): any
			return Instance.new("Model") -- no PrimaryPart
		end, function(message: string)
			table.insert(warnings, message)
		end)
		local model = cache:clone("butter", "Held")
		expect.truthy(SquishyCache.isPlaceholder(model))
		expect.equal(#warnings, 1)
		cache:clear()
	end)

	t.test("rejects an unknown build mode and a bad scale", function()
		local cache = makeCache()
		expect.throws(function()
			cache:clone("toast", "Flying")
		end, "mode")
		expect.throws(function()
			cache:clone("toast", "Held", 0)
		end, "scale")
		expect.throws(function()
			cache:clone("toast", "Held", 0 / 0)
		end, "scale")
		cache:clear()
	end)

	-- Model slots ---------------------------------------------------------------------------------------------

	-- A cache with the fake blueprint builder and an in-memory slot folder.
	local function makeSlotCache(folder: Instance): (any, { Call }, { string })
		local calls: { Call } = {}
		local warnings: { string } = {}
		local cache = SquishyCache.new(function(id: string, mode: string, scale: number?): Model
			table.insert(calls, { id = id, mode = mode, scale = scale })
			return blueprintModel(id, mode, scale)
		end, function(message: string)
			table.insert(warnings, message)
		end, folder)
		return cache, calls, warnings
	end

	local function expectNear(actual: Vector3, wanted: Vector3, label: string)
		if (actual - wanted).Magnitude > TOLERANCE then
			error(`{label}: expected {wanted}, got {actual}`, 2)
		end
	end

	t.test("a valid model slot replaces the blueprint, fitted to its size, welded, cosmetic and stripped", function()
		local folder = Instance.new("Folder")
		folder.Name = SquishyCache.SLOT_FOLDER
		local source = slotModel("toast")
		source.Parent = folder
		local cache, calls, warnings = makeSlotCache(folder)

		local held = cache:clone("toast", "Held")
		expect.equal(#warnings, 0)
		expect.equal(#calls, 1) -- the blueprint is still built once per key (it gives the target size)
		expect.truthy(SquishyCache.isSlotModel(held))
		expect.falsy(SquishyCache.isPlaceholder(held))
		expect.equal(held.Name, "toast")

		-- Root: a new invisible 0.2³ PrimaryPart at the origin = the slot's pivot; the old "Root" is gone.
		expect.truthy(held.PrimaryPart ~= nil)
		local root = held.PrimaryPart :: BasePart
		expect.equal(root.Name, "Root")
		expectNear(root.Size, Vector3.one * 0.2, "Root.Size")
		expect.equal(root.Transparency, 1)
		expect.equal(root.CFrame, CFrame.identity)
		expect.truthy(root.Massless)
		local roots = 0
		for _, part in partsOf(held) do
			if part.Name == "Root" then
				roots += 1
			end
		end
		expect.equal(roots, 1)
		expect.equal(#partsOf(held), 4) -- Body, EyeL, Details.Tail, Root

		-- Uniform fit: longest side = the blueprint's (1.6 at scale 1); positions scale about the pivot.
		expect.near(longestSide(held), 1.6, TOLERANCE)
		expect.near(held:GetAttribute("SD_SlotFit") :: number, 0.2, 1e-5)
		local body = held:FindFirstChild("Body") :: BasePart
		local eye = held:FindFirstChild("EyeL") :: BasePart
		local tail = (held:FindFirstChild("Details") :: Model):FindFirstChild("Tail") :: BasePart
		expectNear(body.Size, Vector3.new(1.6, 1.2, 1.0), "Body.Size")
		expectNear(body.CFrame.Position, Vector3.zero, "Body.Position")
		expectNear(eye.CFrame.Position, Vector3.new(0.2, 0.1, -0.52), "EyeL.Position")
		expectNear(tail.CFrame.Position, Vector3.new(0, -0.2, 0.6), "Tail.Position")
		expectNear(tail.CFrame.LookVector, CFrame.Angles(0.4, 0, 0).LookVector, "Tail rotation")

		-- Held build: nothing anchored, every part welded to Root with an explicit Weld (C0 exact), flags applied.
		expect.equal(held:FindFirstChildWhichIsA("WeldConstraint", true), nil)
		for _, part in partsOf(held) do
			expect.falsy(part.Anchored)
			expect.truthy(part.Massless)
			expect.falsy(part.CanCollide)
			expect.falsy(part.CanTouch)
			expect.falsy(part.CanQuery)
			expect.equal(#part:GetTags(), 0)
			if part ~= root then
				expect.truthy(part.CastShadow)
				local found = part:FindFirstChildWhichIsA("Weld")
				expect.truthy(found ~= nil)
				local weld = found :: Weld
				expect.equal(weld.Name, "SD_PartWeld")
				expect.equal(weld.Part0, root)
				expect.equal(weld.Part1, part)
				expect.equal(weld.C1, CFrame.identity)
				local wanted = root.CFrame:ToObjectSpace(part.CFrame)
				expectNear(weld.C0.Position, wanted.Position, `{part.Name} weld C0`)
				expectNear(weld.C0.LookVector, wanted.LookVector, `{part.Name} weld C0 look`)
			end
		end

		-- Stripped vs kept.
		for _, descendant in held:GetDescendants() do
			for _, className in STRIPPED do
				if descendant:IsA(className) then
					error(`{descendant:GetFullName()} ({descendant.ClassName}) was not stripped`)
				end
			end
		end
		expect.truthy(held:FindFirstChildWhichIsA("Decal", true) ~= nil)
		expect.equal(body.Material, Enum.Material.Fabric)

		-- Model attributes: the builder's, plus the slot marker; the slot's own attributes are gone.
		expect.equal(held:GetAttribute("SD_BlueprintId"), "toast")
		expect.equal(held:GetAttribute("SD_BlueprintVersion"), 3)
		expect.equal(held:GetAttribute("SD_Mode"), "Held")
		expect.equal(held:GetAttribute("SD_Placeholder"), nil)

		-- The team's source model is never changed.
		expect.equal(source.Parent, folder)
		expect.truthy(source:FindFirstChildWhichIsA("Script") ~= nil)
		expect.equal((source:FindFirstChild("Body") :: BasePart).Size, Vector3.new(8, 6, 5))
		expect.equal((source.PrimaryPart :: BasePart).Name, "Root")

		-- Same key again: the cached template, no rebuild.
		cache:clone("toast", "Held")
		expect.equal(#calls, 1)

		-- Viewport: everything anchored, no welds. World at scale 2.5: Root anchored, the rest welded; the size follows.
		local viewport = cache:clone("toast", "Viewport")
		expect.truthy(SquishyCache.isSlotModel(viewport))
		for _, part in partsOf(viewport) do
			expect.truthy(part.Anchored)
		end
		expect.equal(viewport:FindFirstChildWhichIsA("JointInstance", true), nil)
		local world = cache:clone("toast", "World", 2.5)
		expect.near(longestSide(world), 1.6 * 2.5, TOLERANCE)
		expect.equal(world:GetAttribute("SD_Scale"), 2.5)
		expect.truthy((world.PrimaryPart :: BasePart).Anchored)
		for _, part in partsOf(world) do
			if part ~= world.PrimaryPart then
				expect.falsy(part.Anchored)
				expect.truthy(part:FindFirstChildWhichIsA("Weld") ~= nil)
			end
		end

		held:Destroy()
		viewport:Destroy()
		world:Destroy()
		cache:clear()
		folder:Destroy()
	end)

	t.test("an invalid model slot falls back to the blueprint with one warning per id", function()
		local folder = Instance.new("Folder")
		local notModel = Instance.new("Part")
		notModel.Name = "toast"
		notModel.Parent = folder
		local empty = Instance.new("Model")
		empty.Name = "banana"
		Instance.new("Script").Parent = empty -- stripped, leaving no parts
		empty.Parent = folder
		local crowded = Instance.new("Model")
		crowded.Name = "butter"
		for i = 1, SquishyCache.SLOT_MAX_PARTS + 1 do
			local part = Instance.new("Part")
			part.Name = `P{i}`
			part.Parent = crowded
		end
		crowded.Parent = folder
		local locked = slotModel("bird")
		locked.Archivable = false -- cannot be cloned
		locked.Parent = folder
		local cache, _, warnings = makeSlotCache(folder)

		local function expectBlueprint(model: Model, scale: number?)
			expect.falsy(SquishyCache.isSlotModel(model))
			expect.falsy(SquishyCache.isPlaceholder(model))
			local size = (model:FindFirstChild("Body") :: BasePart).Size
			expectNear(size, BLUEPRINT_BODY * (scale or 1), "blueprint Body.Size")
		end

		expectBlueprint(cache:clone("toast", "Held"))
		expect.equal(#warnings, 1)
		expect.truthy(string.find(warnings[1], "toast", 1, true) ~= nil)
		expectBlueprint(cache:clone("toast", "Viewport"))
		expect.equal(#warnings, 1) -- once per id, whatever the mode or scale
		expectBlueprint(cache:clone("banana", "Held"))
		expect.equal(#warnings, 2)
		expect.truthy(string.find(warnings[2], "banana", 1, true) ~= nil)
		expectBlueprint(cache:clone("butter", "Held"))
		expect.equal(#warnings, 3)
		expect.truthy(string.find(warnings[3], tostring(SquishyCache.SLOT_MAX_PARTS + 1), 1, true) ~= nil)
		-- Rebuilt after clear(): still the blueprint, no new warning.
		cache:clear()
		expectBlueprint(cache:clone("toast", "Held"))
		expectBlueprint(cache:clone("butter", "World", 2), 2)
		expect.equal(#warnings, 3)
		-- Archivable off: Clone() gives nil.
		expectBlueprint(cache:clone("bird", "Held"))
		expect.equal(#warnings, 4)
		expect.truthy(string.find(warnings[4], "bird", 1, true) ~= nil)
		cache:clear()
		folder:Destroy()
	end)

	t.test("a removed slot: the cached template stays until clear(), then the blueprint is built again", function()
		local folder = Instance.new("Folder")
		local slot = slotModel("toast")
		slot.Parent = folder
		local cache, _, warnings = makeSlotCache(folder)
		expect.truthy(SquishyCache.isSlotModel(cache:clone("toast", "Held")))
		slot:Destroy()
		expect.truthy(SquishyCache.isSlotModel(cache:clone("toast", "Held"))) -- template kept until clear()
		cache:clear()
		local after = cache:clone("toast", "Held")
		expect.falsy(SquishyCache.isSlotModel(after))
		expectNear((after:FindFirstChild("Body") :: BasePart).Size, BLUEPRINT_BODY, "blueprint Body.Size")
		-- A slot added later is picked up after the next clear().
		slotModel("toast").Parent = folder
		cache:clear()
		expect.truthy(SquishyCache.isSlotModel(cache:clone("toast", "Held")))
		expect.equal(#warnings, 0)
		cache:clear()
		folder:Destroy()
	end)

	t.test("a Held slot model squashes through Anim/SquishDeformer (Size + Weld.C0) and rests exactly", function()
		local SquishDeformer = t.requireClient("Anim/SquishDeformer")
		local folder = Instance.new("Folder")
		slotModel("toast").Parent = folder
		local cache = makeSlotCache(folder)
		local held = cache:clone("toast", "Held")
		local sizes: { [BasePart]: Vector3 } = {}
		local c0s: { [Weld]: CFrame } = {}
		for _, part in partsOf(held) do
			sizes[part] = part.Size
			local weld = part:FindFirstChildWhichIsA("Weld")
			if weld then
				c0s[weld] = weld.C0
			end
		end
		local deformer = SquishDeformer.attach(held)
		expect.equal(deformer:partCount(), 3) -- Body, EyeL, Tail; never the Root
		local S = SquishDeformer.squash(0.3, "Y")
		deformer:setScale(S)
		local body = held:FindFirstChild("Body") :: BasePart
		local eye = held:FindFirstChild("EyeL") :: BasePart
		expectNear(body.Size, sizes[body] * S, "squashed Body.Size")
		local eyeWeld = eye:FindFirstChildWhichIsA("Weld") :: Weld
		expectNear(eyeWeld.C0.Position, Vector3.new(0.2, 0.1, -0.52) * S, "squashed EyeL C0")
		deformer:rest()
		for part, size in sizes do
			expect.equal(part.Size, size)
		end
		for weld, c0 in c0s do
			expect.equal(weld.C0, c0)
		end
		deformer:destroy()
		held:Destroy()
		cache:clear()
		folder:Destroy()
	end)

	t.test("private caches without a slot folder never use slots", function()
		local cache, calls = makeCache()
		local model = cache:clone("toast", "Held")
		expect.falsy(SquishyCache.isSlotModel(model))
		expect.equal(#calls, 1)
		cache:clear()
	end)

	t.test("the default cache builds every catalog squishy with the real builder (no placeholder)", function()
		for _, def in Catalog.list() do
			local model = SquishyCache.clone(def.id, "Held")
			expect.falsy(SquishyCache.isPlaceholder(model))
			expect.truthy(model.PrimaryPart ~= nil)
			model:Destroy()
		end
		SquishyCache.clear()
		expect.equal(SquishyCache.templateCount(), 0)
	end)
end
