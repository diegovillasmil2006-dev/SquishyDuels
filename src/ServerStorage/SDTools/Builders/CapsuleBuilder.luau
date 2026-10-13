--!strict
-- CapsuleBuilder: builds the capsule templates ServerStorage.SD_Templates.Capsules (build plan Phase 4; lobby bases spec
-- 2026-10-11 §4, §5.1-§5.2, §7; big-number progression spec 2026-10-12 §4), which BaseService clones onto the island's
-- plots at runtime (the server never builds squishy visuals itself). Server only, Edit mode only (ServerStorage.SDTools);
-- called by Main's pipeline (target "capsules") and by LobbyBuilder's part budget, never at runtime. Contract
-- (Generated.BuildContext / BuildResult): build(ctx) returns { ok, root, warnings, error } with the new tree UNPARENTED
-- and marked GeneratorId "capsules". Relative requires, or modules of the injected ctx.Shared clone.
--
-- Tree (a Folder named Capsules, marked SD_Generated / capsules / VERSION):
--   Capsule_<look>  one per Config.Grip.Capsule.Tiers key (foam .. royal), the spec §5.1 capsule in its tier's look
--                   (progression §4, the LOOKS table of Palette tokens): Drum Ø7 × 1.5, DrumTrim, ProgressRing (the ring
--                   that fills until the next squeeze; Phase 5 animates it), Tube Ø6 × 7 (see-through), Band1-3 (the
--                   look's stripes on the tube), Press + PressRod (Phase 5 brings the press down), Cap, CapTrim, Knob and
--                   LevelPlate (a live TextLabel "Level" BaseService writes). Pivot (WorldPivot): the drum's bottom
--                   centre, its front (the level plate) along the pivot's LookVector. Attributes SD_Look (the tier key)
--                   and SD_SeatY (the height above the pivot where the squishy stands).
--   Lock            a locked slot (spec §4): the design's lock icon (Kit/Props) on a post over a price plate (a live
--                   TextLabel "Price"). Pivot as a capsule's.
--   Squishy_<id>    one per Catalog squishy: the squishy that sits in the tube, CAPSULE_SQUISHY tall (max(height, 0.8 ×
--                   width), like the lobby's toys), in low detail: its eyes and its biggest other visible parts, LOW_DETAIL
--                   parts in all (spec §7 budget). Built in "Viewport" mode (every part anchored, no welds). Pivot: its
--                   bottom centre, facing -Z.
--   Statue_<id>     the same at WorldLayout.Bases.statueHeight, for the base's back wall (spec §4).
-- Every part: anchored, CanTouch false, CastShadow off when it is under 2 studs (spec §7). Only the drum, the tube and
-- the cap collide (players walk around a capsule); the rest is decor. Self-check: every look, the lock and every
-- squishy and statue present, part counts within CAPSULE_PARTS / LOCK_PARTS / LOW_DETAIL; any problem fails the build.

local Generated = require(script.Parent.Parent.Generated)
local Prims = require(script.Parent.Parent.Kit.Prims)
local Props = require(script.Parent.Parent.Kit.Props)
local Signs = require(script.Parent.Parent.Kit.Signs)

-- Types

type BuildContext = Generated.BuildContext
type BuildResult = Generated.BuildResult

-- A look (progression spec §4): Palette tokens of the drum and cap (body), the trims and knob (trim), the tube (glass)
-- and the press, the tube's transparency and shine, and the 3 stripes on the tube (bands, bottom to top).
type Look = {
	body: string,
	trim: string,
	glass: string,
	glassTransparency: number,
	shine: number,
	press: string,
	bands: { string },
}

type Deps = {
	Palette: any,
	Strings: any,
	Config: any,
	Catalog: any,
	SquishyBuilder: any,
	WorldLayout: any,
}

-- Constants

local GENERATOR_ID = "capsules"
local VERSION = 1
local ROOT_NAME = "Capsules"

-- Spec §5.1 (readings where it gives no number).
local DRUM_DIAMETER = 7
local DRUM_HEIGHT = 1.5
local TUBE_DIAMETER = 6
local TUBE_HEIGHT = 7
local CAP_HEIGHT = 1
local TRIM_DIAMETER = 7.4 -- reading: the trims stand 0.2 proud of the drum and the cap
local BAND_DIAMETER = 6.2 -- reading: the stripes stand 0.1 proud of the tube
local BAND_HEIGHT = 0.5
local BAND_Y = { 3.2, 5, 6.8 } -- reading: three stripes up the tube
local PRESS_DIAMETER = 5.2
local CAPSULE_SQUISHY = 3.5 -- spec §5.1: the squishy inside, 3.5 tall
local LOW_DETAIL = 12 -- reading (spec §7 budget): parts kept per squishy and statue
local EYE_LOOKS: { [string]: boolean } = { eye = true, eyeArc = true } -- SquishyBuilder's SD_Look of the eyes
local CAPSULE_PARTS = 16 -- spec §5.1: "about 16 parts"
local LOCK_PARTS = 12
local SMALL_PART = 2 -- spec §7: parts under 2 studs cast no shadow
local PLATE_STYLE_TOKENS = { background = "LobbyPlate", text = "LobbyInk" }
local LOCK_SCALE = 0.9 -- reading: the design's lock icon (lobby.js:52-58) at 0.9

-- The 10 looks (progression spec §4: Foam cream, Jelly glossy red, Marshmallow white with toasted trim, Gummy see-through
-- green, Taffy pink and white stripes, Caramel amber, Bubblegum bright pink, Rainbow stripes, Crystal icy see-through,
-- Royal purple and gold; the four old pad looks are tiers 1, 2, 3 and 10), keyed by Config.Grip.Capsule.Tiers keys.
local LOOKS: { [string]: Look } = {
	foam = {
		body = "CapsuleFoam",
		trim = "CapsuleFoamTrim",
		glass = "CapsuleFoamGlass",
		glassTransparency = 0.5,
		shine = 0,
		press = "LobbyTrimWhite",
		bands = { "CapsuleFoamTrim", "CapsuleFoam", "CapsuleFoamTrim" },
	},
	jelly = {
		body = "LobbyJellyCore",
		trim = "LobbyTrimWhite",
		glass = "LobbyJellyShell",
		glassTransparency = 0.4,
		shine = 0.2,
		press = "LobbyTrimWhite",
		bands = { "LobbyJellyShell", "LobbyTrimWhite", "LobbyJellyShell" },
	},
	marshmallow = {
		body = "LobbyMarshmallow",
		trim = "LobbyMallowToast",
		glass = "LobbyMarshmallow",
		glassTransparency = 0.5,
		shine = 0,
		press = "LobbyMallowCenter",
		bands = { "LobbyMallowToast", "LobbyMarshmallow", "LobbyMallowToast" },
	},
	gummy = {
		body = "CapsuleGummy",
		trim = "CapsuleGummyLight",
		glass = "CapsuleGummyGlass",
		glassTransparency = 0.6,
		shine = 0.1,
		press = "CapsuleGummyLight",
		bands = { "CapsuleGummyLight", "CapsuleGummy", "CapsuleGummyLight" },
	},
	taffy = {
		body = "CapsuleTaffy",
		trim = "White",
		glass = "CapsuleTaffyGlass",
		glassTransparency = 0.5,
		shine = 0,
		press = "White",
		bands = { "CapsuleTaffy", "White", "CapsuleTaffy" },
	},
	caramel = {
		body = "CapsuleCaramel",
		trim = "CapsuleCaramelDark",
		glass = "CapsuleCaramelGlass",
		glassTransparency = 0.45,
		shine = 0.1,
		press = "CapsuleCaramelDark",
		bands = { "CapsuleCaramelDark", "CapsuleCaramel", "CapsuleCaramelDark" },
	},
	bubblegum = {
		body = "CapsuleBubblegum",
		trim = "CapsuleBubblegumLight",
		glass = "CapsuleBubblegumGlass",
		glassTransparency = 0.5,
		shine = 0,
		press = "CapsuleBubblegumLight",
		bands = { "CapsuleBubblegumLight", "CapsuleBubblegum", "CapsuleBubblegumLight" },
	},
	rainbow = {
		body = "White",
		trim = "LobbyViolet",
		glass = "CapsuleRainbowGlass",
		glassTransparency = 0.5,
		shine = 0,
		press = "LobbyButter",
		bands = { "LobbyJellyShell", "LobbyButter", "LobbySky" },
	},
	crystal = {
		body = "CapsuleCrystal",
		trim = "White",
		glass = "CapsuleCrystalGlass",
		glassTransparency = 0.65,
		shine = 0.25,
		press = "White",
		bands = { "White", "CapsuleCrystal", "White" },
	},
	royal = {
		body = "LobbyRoyalVelvet",
		trim = "LobbyGold",
		glass = "CapsuleRoyalGlass",
		glassTransparency = 0.5,
		shine = 0.1,
		press = "LobbyGold",
		bands = { "LobbyGold", "LobbyRoyalVelvet", "LobbyGold" },
	},
}

-- `require` with a runtime-chosen ModuleScript (the injected Shared clone); the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local CapsuleBuilder = {}
CapsuleBuilder.GENERATOR_ID = GENERATOR_ID
CapsuleBuilder.VERSION = VERSION
CapsuleBuilder.ROOT_NAME = ROOT_NAME
CapsuleBuilder.LOW_DETAIL = LOW_DETAIL

-- Private

local function failure(warnings: { string }, message: string): BuildResult
	return { ok = false, root = nil, warnings = warnings, error = message }
end

-- Requires the module at `path` ("Art/Palette") inside the injected Shared clone.
local function requirePath(shared: Instance, path: string): (any, string?)
	local node: Instance? = shared
	for segment in string.gmatch(path, "[^/]+") do
		node = if node then node:FindFirstChild(segment) else nil
	end
	if node == nil or not node:IsA("ModuleScript") then
		return nil, string.format("deps.Shared has no %s module", path)
	end
	local ok, result = pcall(dynamicRequire, node :: ModuleScript)
	if not ok then
		return nil, string.format("could not load Shared %s: %s", path, tostring(result))
	end
	return result, nil
end

local function loadDeps(shared: Instance): (Deps?, string?)
	local loaded: { [string]: any } = {}
	for _, entry in
		{
			{ "Palette", "Art/Palette" },
			{ "Strings", "Strings" },
			{ "Config", "Config" },
			{ "Catalog", "Catalog" },
			{ "SquishyBuilder", "Art/SquishyBuilder" },
			{ "WorldLayout", "World/WorldLayout" },
		}
	do
		local module, err = requirePath(shared, entry[2])
		if module == nil then
			return nil, err
		end
		loaded[entry[1]] = module
	end
	return {
		Palette = loaded.Palette,
		Strings = loaded.Strings,
		Config = loaded.Config,
		Catalog = loaded.Catalog,
		SquishyBuilder = loaded.SquishyBuilder,
		WorldLayout = loaded.WorldLayout,
	},
		nil
end

local function color(deps: Deps, token: string): Color3
	local value = deps.Palette[token]
	if typeof(value) ~= "Color3" then
		error(string.format("[SD][CapsuleBuilder] Art/Palette has no colour token %s", tostring(token)), 0)
	end
	return value
end

-- A collar (Kit/Props cylinder) around a core: `diameter` wide, its top `top` (pivot space), `height` tall.
local function band(parent: Instance, name: string, diameter: number, height: number, top: number, c: Color3): Part
	return Props.cylinder(parent, name, diameter, height, CFrame.new(0, top - height / 2, 0), c)
end

-- A plate part with a live label (no key: BaseService writes its text) on its Front face, in the design plate's look.
local function plate(deps: Deps, parent: Instance, name: string, size: Vector3, cframe: CFrame, label: string): Part
	local part = Prims.part({
		name = name,
		size = size,
		cframe = cframe,
		color = color(deps, PLATE_STYLE_TOKENS.background),
		flags = "decor",
		parent = parent,
	})
	local ink = color(deps, PLATE_STYLE_TOKENS.text)
	Signs.surface(
		deps.Strings,
		part,
		Enum.NormalId.Front,
		{ { name = label, live = true, letterHeight = size.Y * 0.56, font = "heading" } },
		{ panel = part.Color, frame = part.Color, text = ink, stroke = part.Color },
		nil,
		"center",
		{ text = ink } -- the design plate's text: no outline; the part itself is the plate
	)
	return part
end

-- Capsule_<key> (see the header).
local function buildCapsule(deps: Deps, key: string, look: Look): Model
	local model = Prims.model("Capsule_" .. key, nil, false, CFrame.identity)
	local body, trim = color(deps, look.body), color(deps, look.trim)
	local drum =
		Props.cylinder(model, "Drum", DRUM_DIAMETER, DRUM_HEIGHT, CFrame.new(0, DRUM_HEIGHT / 2, 0), body, "solid")
	drum.CanQuery = true
	-- Prims.LAYER under the drum's top, so the two tops never share a plane (Flicker_Test).
	band(model, "DrumTrim", TRIM_DIAMETER, 0.5, DRUM_HEIGHT - Prims.LAYER, trim)
	band(model, "ProgressRing", DRUM_DIAMETER + 0.3, 0.3, 0.65, color(deps, "LobbyTrimWhite"))
	-- The tube starts Prims.LAYER above the drum and ends as far under the cap: see-through faces never meet theirs.
	local tubeHeight = TUBE_HEIGHT - 2 * Prims.LAYER
	local tube = Props.cylinder(
		model,
		"Tube",
		TUBE_DIAMETER,
		tubeHeight,
		CFrame.new(0, DRUM_HEIGHT + TUBE_HEIGHT / 2, 0),
		color(deps, look.glass),
		"solid"
	)
	tube.Transparency = look.glassTransparency
	tube.Reflectance = look.shine
	tube.CastShadow = false
	for index, y in BAND_Y do
		band(model, "Band" .. index, BAND_DIAMETER, BAND_HEIGHT, y + BAND_HEIGHT / 2, color(deps, look.bands[index]))
	end
	local capBottom = DRUM_HEIGHT + TUBE_HEIGHT
	local press = color(deps, look.press)
	Props.cylinder(model, "Press", PRESS_DIAMETER, 0.5, CFrame.new(0, capBottom - 0.6, 0), press)
	Props.cylinder(model, "PressRod", 0.8, 0.35, CFrame.new(0, capBottom - 0.175, 0), press)
	Props.cylinder(model, "Cap", DRUM_DIAMETER, CAP_HEIGHT, CFrame.new(0, capBottom + CAP_HEIGHT / 2, 0), body, "solid")
	band(model, "CapTrim", TRIM_DIAMETER, 0.4, capBottom + 0.4, trim)
	Props.ball(model, "Knob", 1.6, Vector3.new(0, capBottom + CAP_HEIGHT + 0.6, 0), trim)
	plate(
		deps,
		model,
		"LevelPlate",
		Vector3.new(2.6, 1, 0.2),
		CFrame.new(0, DRUM_HEIGHT / 2, -(DRUM_DIAMETER / 2 + 0.1)),
		"Level"
	)
	model:SetAttribute("SD_Look", key)
	model:SetAttribute("SD_SeatY", DRUM_HEIGHT)
	return model
end

-- Lock (see the header).
local function buildLock(deps: Deps): Model
	local model = Prims.model("Lock", nil, false, CFrame.identity)
	Props.cylinder(model, "Post", 0.6, 3, CFrame.new(0, 1.5, 0), color(deps, "LobbyTrimWhite"))
	-- Kit/Props.lockIcon faces its frame's +Z: turned so it faces the pivot's front (-Z), its body on the post.
	Props.lockIcon(
		nil,
		model,
		CFrame.new(0, 3 + 2.4 * LOCK_SCALE / 2, 0) * CFrame.Angles(0, math.pi, 0),
		LOCK_SCALE,
		color(deps, "LobbyGold"),
		color(deps, "LobbyInk")
	)
	plate(deps, model, "PricePlate", Vector3.new(4.6, 1.2, 0.2), CFrame.new(0, 1.9, -0.45), "Price")
	return model
end

-- The visible size of a model built around its pivot at the origin (its own axes) and its lowest point.
local function bounds(model: Model): (Vector3, number)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local cf, half = part.CFrame, part.Size / 2
			local extent = Vector3.new(
				math.abs(cf.XVector.X) * half.X + math.abs(cf.YVector.X) * half.Y + math.abs(cf.ZVector.X) * half.Z,
				math.abs(cf.XVector.Y) * half.X + math.abs(cf.YVector.Y) * half.Y + math.abs(cf.ZVector.Y) * half.Z,
				math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
			)
			low = low:Min(cf.Position - extent)
			high = high:Max(cf.Position + extent)
		end
	end
	if low.X == math.huge then
		return Vector3.zero, 0
	end
	return high - low, low.Y
end

-- Squishy_<id> / Statue_<id>: the blueprint at `tall` (max(height, 0.8 × width)), low detail, pivot at its bottom
-- centre. A blueprint that fails is a problem (the build fails), never a crash.
local function buildSquishy(deps: Deps, name: string, id: string, tall: number, problems: { string }): Model?
	local build = deps.SquishyBuilder.build
	local ok, probe = pcall(build, id, "Viewport", 1)
	if not ok or typeof(probe) ~= "Instance" or not probe:IsA("Model") then
		table.insert(problems, string.format("%s: SquishyBuilder.build(%q) failed: %s", name, id, tostring(probe)))
		return nil
	end
	local size = bounds(probe :: Model)
	probe:Destroy()
	local measure = math.max(size.Y, 0.8 * size.X)
	if measure <= 0 then
		table.insert(problems, string.format("%s: blueprint %s has no visible parts", name, id))
		return nil
	end
	local model = build(id, "Viewport", tall / measure) :: Model
	model.Name = name
	model.PrimaryPart = nil
	-- Low detail: the eyes, then the biggest other visible parts.
	local eyes, others = {}, {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if part.Transparency >= 1 then
				part:Destroy()
			elseif EYE_LOOKS[part:GetAttribute("SD_Look") :: any] then
				table.insert(eyes, part)
			else
				table.insert(others, part)
			end
		end
	end
	table.sort(others, function(a: BasePart, b: BasePart): boolean
		local va, vb = a.Size.X * a.Size.Y * a.Size.Z, b.Size.X * b.Size.Y * b.Size.Z
		if va ~= vb then
			return va > vb
		end
		return a.Name < b.Name
	end)
	for index = LOW_DETAIL - #eyes + 1, #others do
		others[index]:Destroy()
	end
	local _, lowest = bounds(model)
	model.WorldPivot = CFrame.new(0, lowest, 0)
	return model
end

-- Spec §7 render rules on a finished tree: no part is touched; parts under SMALL_PART studs cast no shadow.
local function applyRenderRules(root: Instance)
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanTouch = false
			if math.max(part.Size.X, part.Size.Y, part.Size.Z) < SMALL_PART then
				part.CastShadow = false
			end
		end
	end
end

local function partCount(instance: Instance): number
	return Prims.countParts(instance)
end

-- Public

-- Builds the templates, unparented and marked. Never changes the place.
function CapsuleBuilder.build(ctx: BuildContext): BuildResult
	local warnings: { string } = {}
	local root = Prims.folder(ROOT_NAME)
	local handedOver = false
	ctx.scratch:add(function()
		if not handedOver then
			root:Destroy()
		end
	end)

	local deps, depsError = loadDeps(ctx.Shared)
	if deps == nil then
		return failure(warnings, depsError or "could not load Shared modules")
	end
	local problems: { string } = {}
	for _, tier in deps.Config.Grip.Capsule.Tiers do
		local look = LOOKS[tier.key]
		if look == nil then
			table.insert(problems, string.format("no look for capsule tier %s", tostring(tier.key)))
			continue
		end
		local capsule = buildCapsule(deps, tier.key, look)
		if partCount(capsule) > CAPSULE_PARTS then
			table.insert(
				problems,
				string.format("%s has %d parts (%d at most)", capsule.Name, partCount(capsule), CAPSULE_PARTS)
			)
		end
		capsule.Parent = root
	end
	local lock = buildLock(deps)
	if partCount(lock) > LOCK_PARTS then
		table.insert(problems, string.format("Lock has %d parts (%d at most)", partCount(lock), LOCK_PARTS))
	end
	lock.Parent = root
	for _, def in deps.Catalog.list() do
		for _, entry in
			{
				{ "Squishy_" .. def.id, CAPSULE_SQUISHY },
				{ "Statue_" .. def.id, deps.WorldLayout.Bases.statueHeight },
			} :: { { any } }
		do
			local model = buildSquishy(deps, entry[1], def.id, entry[2], problems)
			if model then
				model.Parent = root
			end
		end
	end
	applyRenderRules(root)
	if #problems > 0 then
		return failure(
			warnings,
			string.format("capsule self-check found %d problem(s): %s", #problems, table.concat(problems, "; "))
		)
	end
	table.insert(
		warnings,
		string.format("capsule templates: %d parts in %d models", partCount(root), #root:GetChildren())
	)
	Generated.mark(root, GENERATOR_ID, VERSION)
	handedOver = true
	return { ok = true, root = root, warnings = warnings, error = nil }
end

-- The parts one plot can hold at its worst (spec §7): `slots` open capsules of the biggest look holding the `slots`
-- biggest squishies, and the biggest statue. `root` is a built Capsules tree.
function CapsuleBuilder.worstPlotParts(root: Instance, slots: number): number
	local capsule, statue = 0, 0
	local squishies: { number } = {}
	for _, child in root:GetChildren() do
		local count = partCount(child)
		if string.sub(child.Name, 1, 8) == "Capsule_" then
			capsule = math.max(capsule, count)
		elseif string.sub(child.Name, 1, 8) == "Squishy_" then
			table.insert(squishies, count)
		elseif string.sub(child.Name, 1, 7) == "Statue_" then
			statue = math.max(statue, count)
		end
	end
	table.sort(squishies, function(a: number, b: number): boolean
		return a > b
	end)
	local total = slots * capsule + statue
	for index = 1, math.min(slots, #squishies) do
		total += squishies[index]
	end
	return total
end

return CapsuleBuilder
