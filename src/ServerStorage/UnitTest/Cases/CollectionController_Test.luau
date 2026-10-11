--!strict
-- CollectionController_Test: unit tests for StarterPlayerScripts.Client.Controllers.CollectionController (Part 6, the
-- per-player Collection pedestal displays). Server only (ServerStorage.UnitTest). Edit mode: start() is never called
-- (no LocalPlayer, nothing is parented to the place); only what can be injected is tested here. The placement, spin,
-- distance and plate maths are UI/CollectionFormat's (CollectionFormat_Test).
-- Contract (DESIGN §7.6 "Collection display per player", §7.7 SurfaceGui budget, §8.3 model slots):
--   * silhouette(model): every BasePart takes Palette[CollectionFormat.SILHOUETTE_TOKEN] (Lavender), MeshPart
--     TextureIDs and FileMesh TextureIds are cleared, Decals and Textures are hidden (Transparency 1) and
--     SurfaceAppearances are removed; it works on a SquishyCache clone and never reaches the cache's template or
--     another clone (the owned display keeps its full colour);
--   * lift(pivot, boxFrame, boxSize): the pivot's height above the model's bottom and the model's top above the pivot;
--   * nameplate(plate, topAbovePivot): ONE BillboardGui (no SurfaceGui), Size = Config.Inspect.Collection
--     .nameplateSizeStuds in studs, nameplateOffsetStuds above the model's top, MaxDistance =
--     WorldLayout.Collection.buildStuds, LightInfluence 0, not AlwaysOnTop; a Cream plate with the squishy's name and
--     Owned / Not owned yet (CollectionFormat.plate), text sized by Theme under a cap; foam UI restyle: an InkUI
--     outline, the name and "Owned" in InkUI, "Not owned yet" in Ink2;
--   * before start(): debugState() reports nothing built and destroy() is a no-op;
--   * idle life (squishy overhaul spec 2026-10-09 §3.2): pickIdle gives breathing and blink to the displays within
--     Config.Inspect.Collection.idleStuds, nearest first, at most min(the slots HeldSquishyController leaves, idleMax),
--     none under ReducedMotion; setIdleSlots(n) keeps a whole number >= 0 and answers how many slots it uses.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

-- Any texture works for the silhouette checks: a built-in engine texture, so no asset id is needed (§14.1).
local BUILT_IN_TEXTURE = "rbxasset://textures/face.png"

return function(t: Context)
	local expect = t.expect
	local Collection = t.requireClient("Controllers/CollectionController")
	local CollectionFormat = t.requireClient("UI/CollectionFormat")
	local SquishyCache = t.requireClient("Models/SquishyCache")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local Strings = t.requireShared("Strings")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local LAYOUT = WorldLayout.Collection
	local DISPLAY = Config.Inspect.Collection
	local LAVENDER: Color3 = Palette[CollectionFormat.SILHOUETTE_TOKEN]
	local CREAM: Color3 = Palette[CollectionFormat.PLATE_TOKEN]

	local function partsOf(model: Instance): { BasePart }
		local parts: { BasePart } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
		return parts
	end

	-- Each BasePart's colour by its path below the model (names can repeat, so the index is part of the key).
	local function colorsOf(model: Instance): { [string]: Color3 }
		local colors: { [string]: Color3 } = {}
		for index, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				colors[`{index}:{descendant.Name}`] = descendant.Color
			end
		end
		return colors
	end

	local function labelsOf(gui: Instance): { [string]: TextLabel }
		local labels: { [string]: TextLabel } = {}
		for _, descendant in gui:GetDescendants() do
			if descendant:IsA("TextLabel") then
				labels[descendant.Name] = descendant
			end
		end
		return labels
	end

	-- A hand-made team model (§8.3: slot models keep Decals, Textures and SurfaceAppearances) with every kind of
	-- instance silhouette() handles.
	local function teamModel(): (Model, SurfaceAppearance?)
		local model = Instance.new("Model")
		model.Name = "kitty_bread"
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Color = Color3.fromRGB(10, 20, 30)
		root.Parent = model
		model.PrimaryPart = root
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Color = Color3.fromRGB(247, 221, 176)
		body.Parent = model
		local decal = Instance.new("Decal")
		decal.Name = "Face"
		decal.Transparency = 0.2
		decal.Parent = body
		local texture = Instance.new("Texture")
		texture.Name = "Crumbs"
		texture.Parent = body
		local fileMesh = Instance.new("SpecialMesh")
		fileMesh.MeshType = Enum.MeshType.FileMesh
		fileMesh.TextureId = BUILT_IN_TEXTURE
		fileMesh.Parent = body
		local ear = Instance.new("MeshPart")
		ear.Name = "Ear"
		ear.Color = Color3.fromRGB(217, 142, 71)
		ear.TextureID = BUILT_IN_TEXTURE
		ear.Parent = model
		local inner = Instance.new("Model")
		inner.Name = "Nested"
		inner.Parent = model
		local tail = Instance.new("Part")
		tail.Name = "Tail"
		tail.Color = Color3.fromRGB(1, 2, 3)
		tail.Parent = inner
		-- SurfaceAppearance may not be creatable from every script context; the case checks it only when it is.
		local ok, appearance = pcall(function(): SurfaceAppearance
			local made = Instance.new("SurfaceAppearance")
			made.Parent = ear
			return made
		end)
		return model, if ok then appearance else nil
	end

	t.test("silhouette: every part Lavender, textures cleared, decals hidden, surface appearances removed", function()
		local model, appearance = teamModel()
		Collection.silhouette(model)
		local parts = partsOf(model)
		expect.equal(#parts, 4)
		for _, part in parts do
			expect.equal(part.Color, LAVENDER)
		end
		local ear = model:FindFirstChild("Ear") :: MeshPart
		expect.equal(ear.TextureID, "")
		local body = model:FindFirstChild("Body") :: Part
		expect.equal((body:FindFirstChild("Face") :: Decal).Transparency, 1)
		expect.equal((body:FindFirstChild("Crumbs") :: Texture).Transparency, 1)
		expect.equal((body:FindFirstChildOfClass("SpecialMesh") :: SpecialMesh).TextureId, "")
		if appearance then
			expect.equal(appearance.Parent, nil)
			expect.equal(ear:FindFirstChildOfClass("SurfaceAppearance"), nil)
		end
		-- An explicit colour wins (the default is the palette token).
		local other = teamModel()
		Collection.silhouette(other, CREAM)
		for _, part in partsOf(other) do
			expect.equal(part.Color, CREAM)
		end
	end)

	-- Two clones of one display (as CollectionController builds them): silhouette one, the other keeps its colours and
	-- so does the next clone from the template.
	local function checkClones(clone: (id: string) -> Model)
		for _, slot in { 1, #LAYOUT.pedestals } do
			local id = CollectionFormat.squishyForSlot(slot)
			expect.truthy(id ~= nil and Catalog.isValidId(id))
			local owned = clone(id :: string)
			local unowned = clone(id :: string)
			local fullColour = colorsOf(owned)
			expect.truthy(#partsOf(unowned) > 0)
			Collection.silhouette(unowned)
			for _, part in partsOf(unowned) do
				expect.equal(part.Color, LAVENDER)
			end
			expect.deepEqual(colorsOf(owned), fullColour)
			local fresh = clone(id :: string)
			expect.deepEqual(colorsOf(fresh), fullColour)
			owned:Destroy()
			unowned:Destroy()
			fresh:Destroy()
		end
	end

	t.test("silhouette on a SquishyCache clone never reaches the template or the owned clone", function()
		-- A private cache around a builder that returns the team model (no engine services needed).
		local builds = 0
		local cache = SquishyCache.new(function(_blueprintId: string, _mode: string, _scale: number?): Model
			builds += 1
			return (teamModel())
		end, function() end)
		checkClones(function(id: string): Model
			return cache:clone(id, "World", LAYOUT.squishyScale)
		end)
		expect.equal(builds, 2) -- one template per squishy: every display is a clone of it
		cache:clear()
	end)

	t.test("silhouette on the default SquishyCache's real display models (scale 2.5, World)", function()
		-- The default cache builds with SquishyBuilder and the SD_Cosmetic group check; an offline runner without
		-- PhysicsService skips this case (it always runs in Studio).
		local hasPhysics = pcall(function()
			return game:GetService("PhysicsService"):IsCollisionGroupRegistered("SD_Cosmetic")
		end)
		if not hasPhysics then
			return
		end
		checkClones(function(id: string): Model
			return SquishyCache.clone(id, "World", LAYOUT.squishyScale)
		end)
	end)

	t.test("lift: the pivot's height above the bottom and the top above the pivot", function()
		-- Pivot at the box centre: half the height each way.
		local below, above = Collection.lift(CFrame.new(5, 2, -3), CFrame.new(5, 2, -3), Vector3.new(4, 3, 2))
		expect.near(below, 1.5, 1e-6)
		expect.near(above, 1.5, 1e-6)
		-- The box centre 0.5 above the pivot (a tall ear): 1 stud of model below the pivot, 2 above.
		below, above = Collection.lift(CFrame.new(0, 10, 0), CFrame.new(0, 10.5, 0), Vector3.new(1, 3, 1))
		expect.near(below, 1, 1e-6)
		expect.near(above, 2, 1e-6)
		-- A pivot turned about Y measures the same (the display only ever turns about Y).
		local turned = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(90), 0)
		below, above = Collection.lift(turned, turned * CFrame.new(0.3, 0.5, 0), Vector3.new(1, 3, 1))
		expect.near(below, 1, 1e-6)
		expect.near(above, 2, 1e-6)
	end)

	t.test("nameplate: one stud-sized BillboardGui with a Cream plate, the name and the status", function()
		local id = CollectionFormat.squishyForSlot(1) :: string
		for _, owned in { true, false } do
			local plate = CollectionFormat.plate(id, owned)
			local gui = Collection.nameplate(plate, 1.25)
			expect.truthy(gui:IsA("BillboardGui"))
			expect.equal(gui.Parent, nil)
			for _, descendant in gui:GetDescendants() do
				expect.falsy(descendant:IsA("SurfaceGui")) -- §7.7: the lobby's 30 SurfaceGuis stay untouched
			end
			local size = DISPLAY.nameplateSizeStuds
			expect.equal(gui.Size, UDim2.fromScale(size.X, size.Y))
			expect.near(gui.StudsOffsetWorldSpace.Y, 1.25 + DISPLAY.nameplateOffsetStuds, 1e-5)
			expect.near(gui.StudsOffsetWorldSpace.X, 0, 1e-9)
			expect.near(gui.StudsOffsetWorldSpace.Z, 0, 1e-9)
			expect.equal(gui.MaxDistance, LAYOUT.buildStuds)
			expect.equal(gui.LightInfluence, 0)
			expect.equal(gui.AlwaysOnTop, false)
			local found = gui:FindFirstChildWhichIsA("Frame")
			expect.truthy(found ~= nil)
			expect.equal((found :: Frame).BackgroundColor3, CREAM)
			local labels = labelsOf(gui)
			expect.equal(labels.Title.Text, plate.title)
			expect.equal(labels.Status.Text, plate.status)
			local statusKey = if owned then LAYOUT.ownedKey else LAYOUT.notOwnedKey
			expect.equal(labels.Status.Text, Strings.resolve(statusKey))
			-- Foam UI restyle: the name in InkUI; "Owned" InkUI, "Not owned yet" Ink2; the plate outlined in InkUI.
			expect.equal(labels.Title.TextColor3, Palette.InkUI)
			expect.equal(labels.Status.TextColor3, if owned then Palette.InkUI else Palette.Ink2)
			local outline = (found :: Frame):FindFirstChildOfClass("UIStroke")
			expect.truthy(outline ~= nil and (outline :: UIStroke).Color == Palette.InkUI)
			for _, label in labels do
				expect.truthy(label.TextScaled)
				local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
				expect.truthy(cap ~= nil and (cap :: UITextSizeConstraint).MaxTextSize >= 1)
			end
			gui:Destroy()
		end
	end)

	t.test("before start(): nothing is built and destroy() is a no-op", function()
		local state = Collection.debugState()
		expect.equal(state.ok, true)
		expect.equal(state.started, false)
		expect.equal(state.builtCount, 0)
		expect.deepEqual(state.built, {})
		expect.deepEqual(state.builtList, {})
		expect.equal(state.nameplates, 0)
		expect.equal(state.surfaceGuis, 0)
		Collection.destroy()
		expect.equal(Collection.debugState().started, false)
	end)

	-- The picked slots, sorted.
	local function picked(set: { [number]: boolean }): { number }
		local list: { number } = {}
		for slot, on in set do
			if on then
				table.insert(list, slot)
			end
		end
		table.sort(list)
		return list
	end

	t.test("idle life goes to the nearest displays within idleStuds, at most min(slots, idleMax)", function()
		local near = DISPLAY.idleStuds
		local distances: { [number]: number } = {
			[1] = 5,
			[2] = near + 5,
			[3] = 3,
			[4] = 12,
			[5] = near - 0.1,
			[6] = near + 0.1,
			[7] = 0,
			[8] = 0 / 0, -- unknown: never picked
		}
		local out: { [number]: boolean } = {}
		expect.deepEqual(picked(Collection.pickIdle(distances, 3, false, out)), { 1, 3, 7 })
		expect.deepEqual(picked(Collection.pickIdle(distances, math.huge, false, out)), { 1, 3, 4, 5, 7 })
		expect.deepEqual(picked(Collection.pickIdle(distances, 0, false, out)), {})
		expect.deepEqual(picked(Collection.pickIdle(distances, 2.9, false, out)), { 3, 7 })
		expect.deepEqual(picked(Collection.pickIdle(distances, math.huge, true, out)), {}) -- ReducedMotion
		-- Never more than idleMax, however many are near.
		local crowd: { [number]: number } = {}
		for slot = 1, DISPLAY.idleMax + 4 do
			crowd[slot] = slot / 10
		end
		local all = picked(Collection.pickIdle(crowd, math.huge, false, {}))
		expect.equal(#all, DISPLAY.idleMax)
		expect.equal(all[#all], DISPLAY.idleMax) -- the nearest ones
	end)

	t.test("setIdleSlots keeps a whole number >= 0 (HeldSquishyController's leftover rig slots)", function()
		Collection.setIdleSlots(3)
		expect.equal(Collection.debugState().idleSlots, 3)
		Collection.setIdleSlots(4.7)
		expect.equal(Collection.debugState().idleSlots, 4)
		Collection.setIdleSlots(-2)
		expect.equal(Collection.debugState().idleSlots, 0)
		Collection.setIdleSlots(0 / 0)
		expect.equal(Collection.debugState().idleSlots, 0)
		Collection.setIdleSlots(math.huge)
		expect.equal(Collection.debugState().idleSlots, math.huge)
		expect.equal(Collection.debugState().idle, 0) -- nothing built before start()
	end)

	t.test("setIdleSlots answers how many slots it uses (the rest go to the Ambient breathers)", function()
		-- Nothing built before start(): it uses none, whatever it is given.
		expect.equal(Collection.setIdleSlots(3), 0)
		expect.equal(Collection.setIdleSlots(math.huge), 0)
		expect.equal(Collection.setIdleSlots(0 / 0), 0)
	end)
end
