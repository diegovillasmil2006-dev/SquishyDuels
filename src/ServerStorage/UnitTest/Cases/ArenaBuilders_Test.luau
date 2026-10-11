--!strict
-- ArenaBuilders_Test: the 5 design arena generators in ServerStorage.SDTools.Builders.Arenas (phase 4 spec 2026-10-11
-- §5.2, §5.5). Server only (ServerStorage.UnitTest). Each builder runs exactly as Main's pipeline runs it (§1.7 step
-- 3): build(ctx) with a scratch Cleanup and the Shared folder under test, on an UNPARENTED tree; nothing is parented
-- into the place and every tree is destroyed afterwards. The whole SDTools folder is cloned (a clone defeats the
-- require cache).
-- Contract, per arena (World/Arenas):
--   * the build is ok, unparented, named templateName, marked with its generatorId and VERSION, carries SD_ArenaId =
--     its id, and passes Verify.verify(generatorId);
--   * the gameplay frame is Candy Court's exactly: Origin, Zones/HalfA, Neutral, HalfB, Bounds, Audio (and its
--     attributes), Spawns/PadA, PadB and every Geometry/Barriers part match the Candy Court template that ArenaBuilder
--     builds (CFrame, Size, collision group);
--   * Geometry/Cover holds the registry's 12 pieces: Atomic Models "Cover_<name>" with SD_CoverKind = the piece's
--     kind, PrimaryPart Body where the registry puts it, every part solid;
--   * budgets: <= 400 parts, Decor <= 260 parts and all inert, <= 24 SurfaceGuis, an empty Runtime.

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
}

local BUILDERS: { [string]: string } = {
	sweetshop_stadium = "SweetshopStadium",
	pinewood_camp = "PinewoodCamp",
	pillow_fort_park = "PillowFortPark",
	bubble_reef_court = "BubbleReefCourt",
	arcade_toyworks = "ArcadeToyworks",
}
local MAX_PARTS = 400
local MAX_DECOR_PARTS = 260
local MAX_SURFACE_GUIS = 24
local TOLERANCE = 1e-3

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local function loadTools(): (Instance, any)
	local source = ServerStorage:FindFirstChild("SDTools")
	if source == nil then
		error("ServerStorage.SDTools not found")
	end
	local clone = source:Clone()
	local verify = clone:FindFirstChild("Verify")
	if verify == nil or not verify:IsA("ModuleScript") then
		clone:Destroy()
		error("SDTools.Verify is missing")
	end
	return clone, dynamicRequire(verify)
end

local function partsIn(root: Instance): { BasePart }
	local list: { BasePart } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

local function sameBox(a: BasePart, b: BasePart): boolean
	local position = (a.CFrame.Position - b.CFrame.Position).Magnitude <= TOLERANCE
	local axes = a.CFrame.XVector:Dot(b.CFrame.XVector) > 1 - TOLERANCE
		and a.CFrame.YVector:Dot(b.CFrame.YVector) > 1 - TOLERANCE
	return position and axes and (a.Size - b.Size).Magnitude <= TOLERANCE
end

return function(t: Context)
	local tools, Verify = loadTools()
	local Cleanup = t.requireShared("Util/Cleanup")
	local Arenas = t.requireShared("World/Arenas")
	local expect = t.expect

	-- Builds `module` (under Builders, e.g. "Arenas/PinewoodCamp") like Main does; returns (builder, root, warnings).
	local function build(path: string): (any, Instance, { string })
		local node: Instance? = tools:FindFirstChild("Builders")
		for name in string.gmatch(path, "[^/]+") do
			node = if node then node:FindFirstChild(name) else nil
		end
		if node == nil or not node:IsA("ModuleScript") then
			error(`SDTools.Builders.{path} not found`)
		end
		local shared = t.Shared
		if shared == nil then
			error("no Shared folder under test")
		end
		local builder = dynamicRequire(node)
		local scratch = Cleanup.new()
		local ok, result = pcall(builder.build, { scratch = scratch, Shared = shared })
		if not ok or not result.ok or result.root == nil then
			scratch:clean()
			error(`{path}.build failed: {if ok then tostring(result.error) else tostring(result)}`)
		end
		scratch:clean() -- the builder handed the root over: cleaning must not destroy it
		return builder, result.root :: Instance, result.warnings
	end

	local candyBuilt = false
	local candyRoot: Instance? = nil
	local function candy(): Instance
		if not candyBuilt then
			candyBuilt = true
			local _, root = build("ArenaBuilder")
			candyRoot = root
		end
		return candyRoot :: Instance
	end

	for _, id in Arenas.ids do
		local moduleName = BUILDERS[id]
		if moduleName == nil then
			continue -- Candy Court: Builders_Test
		end
		local def = Arenas.byId[id]

		t.test(`{moduleName} builds an unparented, marked template that passes Verify`, function()
			local builder, root, warnings = build("Arenas/" .. moduleName)
			local problems = Verify.verify(def.generatorId, root, { Shared = t.Shared })
			local name, parent = root.Name, root.Parent
			local marks = { root:GetAttribute("SD_GeneratorId"), root:GetAttribute("SD_GeneratorVersion") }
			local arenaId = root:GetAttribute("SD_ArenaId")
			root:Destroy()
			if #problems > 0 then
				error(
					`Verify({def.generatorId}): {table.concat(problems, " | ")} (warnings: {table.concat(
						warnings,
						" | "
					)})`
				)
			end
			expect.equal(name, def.templateName)
			expect.equal(parent, nil)
			expect.deepEqual(marks, { def.generatorId, builder.VERSION })
			expect.equal(arenaId, id)
			expect.equal(builder.GENERATOR_ID, def.generatorId)
			expect.equal(builder.ARENA_ID, id)
		end)

		t.test(`{moduleName}: the gameplay frame is Candy Court's`, function()
			local _, root = build("Arenas/" .. moduleName)
			local reference = candy()
			local mismatched: { string } = {}
			local paths = {
				{ "Origin" },
				{ "Zones", "HalfA" },
				{ "Zones", "Neutral" },
				{ "Zones", "HalfB" },
				{ "Zones", "Bounds" },
				{ "Zones", "Audio" },
				{ "Spawns", "PadA" },
				{ "Spawns", "PadB" },
			}
			for _, barrier in (reference :: any).Geometry.Barriers:GetChildren() do
				table.insert(paths, { "Geometry", "Barriers", barrier.Name })
			end
			for _, path in paths do
				local a: Instance? = root
				local b: Instance? = reference
				for _, name in path do
					a = if a then a:FindFirstChild(name) else nil
					b = if b then b:FindFirstChild(name) else nil
				end
				local label = table.concat(path, "/")
				if a == nil or b == nil or not a:IsA("BasePart") or not b:IsA("BasePart") then
					table.insert(mismatched, label .. " missing")
				elseif not sameBox(a, b) or a.CollisionGroup ~= b.CollisionGroup then
					table.insert(mismatched, label)
				elseif a.CanCollide ~= b.CanCollide or a.CanQuery ~= b.CanQuery or a.Transparency ~= b.Transparency then
					table.insert(mismatched, label .. " flags")
				end
			end
			local audio = (root :: any).Zones.Audio :: Instance
			local referenceAudio = (reference :: any).Zones.Audio :: Instance
			expect.truthy(audio:HasTag("SD_AudioZone"))
			for _, attribute in { "ZoneId", "Priority", "MusicKey", "AmbienceKey", "MusicMul" } do
				expect.equal(audio:GetAttribute(attribute), referenceAudio:GetAttribute(attribute))
			end
			root:Destroy()
			expect.deepEqual(mismatched, {})
		end)

		t.test(`{moduleName}: 12 Atomic cover pieces where World/Arenas puts them`, function()
			local _, root = build("Arenas/" .. moduleName)
			local cover = (root :: any).Geometry.Cover :: Instance
			local problems: { string } = {}
			expect.equal(#cover:GetChildren(), #def.cover)
			for _, piece in def.cover do
				local model = cover:FindFirstChild("Cover_" .. piece.name)
				if model == nil or not model:IsA("Model") then
					table.insert(problems, piece.name .. " missing")
					continue
				end
				local body = model:FindFirstChild("Body")
				if model.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then
					table.insert(problems, piece.name .. " not Atomic")
				end
				if model:GetAttribute("SD_CoverKind") ~= piece.kind then
					table.insert(problems, piece.name .. " kind")
				end
				if body == nil or model.PrimaryPart ~= body or not body:IsA("BasePart") then
					table.insert(problems, piece.name .. " Body")
					continue
				end
				local frame = CFrame.new(piece.position) * CFrame.Angles(0, piece.yaw, 0) * piece.parts[1].cframe
				if (body.CFrame.Position - frame.Position).Magnitude > TOLERANCE then
					table.insert(problems, piece.name .. " Body position")
				end
				for _, part in partsIn(model) do
					if not part.CanCollide or not part.CanQuery or not part.Anchored then
						table.insert(problems, `{piece.name}.{part.Name} not solid`)
					end
				end
				if #partsIn(model) ~= #piece.parts then
					table.insert(problems, piece.name .. " part count")
				end
			end
			root:Destroy()
			expect.deepEqual(problems, {})
		end)

		t.test(`{moduleName}: within 400 parts, Decor <= 260 and inert, <= 24 SurfaceGuis, empty Runtime`, function()
			local _, root = build("Arenas/" .. moduleName)
			local parts = #partsIn(root)
			local decor = partsIn(root:FindFirstChild("Decor") :: Instance)
			local surfaceGuis = 0
			for _, descendant in root:GetDescendants() do
				if descendant:IsA("SurfaceGui") then
					surfaceGuis += 1
				end
			end
			local active = 0
			for _, part in decor do
				if part.CanCollide or part.CanQuery or part.CanTouch then
					active += 1
				end
			end
			local runtime = #(root:FindFirstChild("Runtime") :: Instance):GetChildren()
			root:Destroy()
			if parts > MAX_PARTS or #decor > MAX_DECOR_PARTS or surfaceGuis > MAX_SURFACE_GUIS then
				error(`{parts} parts, {#decor} decor parts, {surfaceGuis} SurfaceGuis`)
			end
			expect.equal(active, 0)
			expect.equal(runtime, 0)
		end)
	end

	-- t.test runs each case at once, so every case above has finished here.
	if candyRoot then
		candyRoot:Destroy()
	end
	tools:Destroy()
end
