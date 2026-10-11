--!strict
-- ArenaBuilder: builds the arena template "Arena_CandyCourt" (DESIGN §5.3 gameplay contract, §7.8 art, §7.7 audio
-- zone). Server only, Edit mode only (ServerStorage.SDTools); called by Main's pipeline, which parents the finished
-- tree under ServerStorage.SD_Templates. The runtime (ArenaService, Part 4) only clones it; it never builds it.
--
-- Data: every gameplay coordinate and size comes from Shared World/WorldLayout.Arena (the one layout source, §1.6):
-- origin, floor bands, gutters, neutral band, midline, side tints, pads, the 12 cover pieces and the Cream stripes on
-- the cover walls (WorldLayout.Arena.wallStripes, moved there by the feel pass, §18.3.4, so the jelly ripple's skin
-- puts a grid row on every stripe edge; same values, same output), rails, barriers and their collision group,
-- dividers, zones, apron, lollipop spots and the audio zone. Colours are Art/Palette tokens (the apron and gutters use
-- WorldLayout's apron hex). The builder only adds the placeholder art WorldLayout leaves open (user decision, Part 3:
-- simple shapes, modest decor), each a named constant below: the diagonal "no-step" stripes and Ink edge lines of the
-- neutral band, the lollipop proportions and the gumdrop stacks. No Neon, no lights, no welds: every part is anchored
-- and placed with an explicit CFrame.
--
-- Tree (coordinates relative to Origin; floor top Y 0; long axis Z; Side A = Z < 0, Side B = Z > 0):
--   Arena_CandyCourt (Model, ModelStreamingMode Default, marked SD_Generated / arena / VERSION; PrimaryPart Origin)
--     Origin     invisible part at the floor centre, no collide/query/touch
--     Geometry   everything projectiles may hit: Anchored, CanQuery true (except Barriers)
--       Floor      13 bands + 4 gutters out to the barrier walls (CanCollide true, top Y 0)
--       Markings   neutral band base, stripes, edge lines, midline, side tints (thin paint, CanCollide false)
--       Rails      low walls (CanCollide true)
--       Cover      12 Atomic Models "Cover_<A|B>_<Kind><n>" (WorldLayout names); PrimaryPart "Body"
--       Barriers   invisible walls and ceiling (collision group SD_Barrier) and the two dividers (SD_Divider):
--                  Transparency 1, CanCollide true, CanQuery false. Roblox spatial queries honour CanQuery = false
--                  only on non-colliding parts, so the collision groups (both collide only with SD_Characters) are
--                  what make a Default-group projectile ray skip every barrier.
--     Zones      HalfA, Neutral, HalfB, Bounds (+ Audio, tagged SD_AudioZone): invisible, no collide/query/touch
--     Spawns     PadA / PadB: Cylinder discs, no collide/query/touch. A Part cylinder's axis is its local X, so each
--                pad is rolled 90° about its look axis: LookVector is the facing (+Z for A, -Z for B) but UpVector is
--                NOT world up. Place characters with CFrame.lookAt(pad.Position, pad.Position + pad.CFrame.LookVector).
--     Decor      apron, 4 lollipops, 4 gumdrop stacks: no collide/query/touch
--     Runtime    empty (ArenaService puts per-match instances here)
-- Each cover piece and decor prop is its own clearly named Model, so the team can replace a look without touching
-- gameplay geometry. Everything is built UNPARENTED. Relative requires or ctx.Shared only.

local Generated = require(script.Parent.Parent.Generated)

-- Types

type BuildContext = Generated.BuildContext
type BuildResult = Generated.BuildResult

-- How a part takes part in physics and queries.
type Flags = {
	collide: boolean,
	query: boolean,
	invisible: boolean,
	shadow: boolean,
}

-- What the builder reads from the Shared clone.
type Deps = {
	palette: any,
	arena: any, -- World/WorldLayout.Arena
}

-- Constants

local GENERATOR_ID = "arena"
local VERSION = 1
local ROOT_NAME = "Arena_CandyCourt"

local DIVIDER_GROUP = "SD_Divider" -- §5.3: collides only with SD_Characters (registered by WorldService at runtime)
local DEFAULT_BARRIER_GROUP = "SD_Barrier" -- walls and ceiling; WorldLayout.Arena.barrierGroup when it is set
local AUDIO_ZONE_TAG = "SD_AudioZone"
local HALF_PI = math.pi / 2
local ROLL_UP = CFrame.Angles(0, 0, HALF_PI) -- a Part cylinder's axis (local X) -> up; the look axis is unchanged
local ZONE_ORDER = { "HalfA", "Neutral", "HalfB", "Bounds" }

-- Flag presets.
local SOLID: Flags = { collide = true, query = true, invisible = false, shadow = true } -- floor, rails, cover
local MARKING: Flags = { collide = false, query = true, invisible = false, shadow = false } -- thin floor paint
local BARRIER: Flags = { collide = true, query = false, invisible = true, shadow = false } -- invisible walls
local GHOST: Flags = { collide = false, query = false, invisible = true, shadow = false } -- Origin, zones
local DECOR: Flags = { collide = false, query = false, invisible = false, shadow = true } -- decor, pads

-- Placeholder art (not in WorldLayout).
-- Neutral band stripes sit between the band base and the midline (both from WorldLayout), so no faces share a plane.
local STRIPE_WIDTH = 1.5
local STRIPE_SPACING = 4
local EDGE_LINE_WIDTH = 0.4
-- Lollipops: stick + disc head (its top at WorldLayout's lollipopHeight) + Cream swirl.
local LOLLIPOP_HEAD_DIAMETER = 6
local LOLLIPOP_HEAD_THICKNESS = 1
local LOLLIPOP_SWIRL_DIAMETER = 3.2
local LOLLIPOP_STICK_DIAMETER = 0.8
-- Gumdrop stacks on the apron, beside the long rails (DESIGN: "gumdrop stacks"; spots are a placeholder reading).
local GUMDROP_STACK_X = 48
local GUMDROP_STACK_Z = 24

-- `require` with a runtime-chosen ModuleScript (the injected Shared clone); the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local ArenaBuilder = {}
ArenaBuilder.GENERATOR_ID = GENERATOR_ID
ArenaBuilder.VERSION = VERSION
ArenaBuilder.ROOT_NAME = ROOT_NAME
ArenaBuilder.DIVIDER_GROUP = DIVIDER_GROUP
ArenaBuilder.BARRIER_GROUP = DEFAULT_BARRIER_GROUP

-- Private

local function failure(warnings: { string }, message: string): BuildResult
	return { ok = false, root = nil, warnings = warnings, error = message }
end

local function loadShared(shared: Instance?, path: { string }): (any, string?)
	local label = "Shared/" .. table.concat(path, "/")
	local node: Instance? = shared
	for _, name in path do
		node = if node then node:FindFirstChild(name) else nil
	end
	if node == nil or not node:IsA("ModuleScript") then
		return nil, "ctx.Shared has no " .. label .. " module"
	end
	local ok, result = pcall(dynamicRequire, node)
	if not ok then
		return nil, "could not load " .. label .. ": " .. tostring(result)
	end
	return result, nil
end

local function loadDeps(shared: Instance?): (Deps?, string?)
	local palette, paletteError = loadShared(shared, { "Art", "Palette" })
	if palette == nil then
		return nil, paletteError
	end
	local layout, layoutError = loadShared(shared, { "World", "WorldLayout" })
	if layout == nil then
		return nil, layoutError
	end
	if type(layout.Arena) ~= "table" then
		return nil, "Shared/World/WorldLayout has no Arena table"
	end
	return { palette = palette, arena = layout.Arena }, nil
end

-- Palette colour for a token name; a missing token is an error (the build fails with its name).
local function color(deps: Deps, token: string?): Color3
	local value = if token then deps.palette[token] else nil
	if typeof(value) ~= "Color3" then
		error(string.format("ArenaBuilder: Palette has no colour %s", tostring(token)), 0)
	end
	return value
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(parent: Instance, name: string, atomic: boolean): Model
	local m = Instance.new("Model")
	m.Name = name
	m.ModelStreamingMode = if atomic then Enum.ModelStreamingMode.Atomic else Enum.ModelStreamingMode.Default
	m.Parent = parent
	return m
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	tint: Color3,
	flags: Flags,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape -- before Size: a Ball snaps its Size to uniform
	end
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.Color = tint
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = if flags.invisible then 1 else 0
	p.CastShadow = flags.shadow
	p.CanCollide = flags.collide
	p.CanTouch = false
	p.CanQuery = flags.query -- after CanCollide (spatial queries honour CanQuery = false only on non-colliding parts)
	p.Parent = parent
	return p
end

-- An upright cylinder: `size` is W × H × D as WorldLayout writes it (diameter, height, diameter).
local function uprightCylinder(
	parent: Instance,
	name: string,
	position: Vector3,
	diameter: number,
	height: number,
	tint: Color3,
	flags: Flags
): Part
	return part(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(position) * ROLL_UP,
		tint,
		flags,
		Enum.PartType.Cylinder
	)
end

-- A WorldLayout Box ({position, size, color?}) as an axis-aligned part.
local function boxPart(parent: Instance, name: string, box: any, tint: Color3, flags: Flags): Part
	return part(parent, name, box.size, CFrame.new(box.position), tint, flags)
end

local function buildFloor(geometry: Folder, deps: Deps)
	local floor = folder(geometry, "Floor")
	for index, band in deps.arena.floorBands do
		boxPart(floor, string.format("Band_%02d", index), band, color(deps, band.color), SOLID)
	end
	-- The strips between the playable floor and the barrier walls: walkable, in the apron's colour.
	local gutterTint = Color3.fromHex(deps.arena.apronColorHex)
	for _, gutter in deps.arena.gutters or {} do
		boxPart(floor, gutter.name, gutter, gutterTint, SOLID)
	end
end

local function buildMarkings(geometry: Folder, deps: Deps)
	local arena = deps.arena
	local markings = folder(geometry, "Markings")

	-- Neutral "no-step" band: base (WorldLayout) < diagonal stripes < Ink edge lines = midline (WorldLayout).
	local band = arena.neutralBand
	local midline = arena.midline
	boxPart(markings, "Neutral_Base", band, color(deps, band.color), MARKING)
	-- Stripes run from the base's mid-height up to halfway between the base top and the line tops.
	local baseTop = band.position.Y + band.size.Y / 2
	local lineTop = midline.position.Y + midline.size.Y / 2
	local stripeTop = (baseTop + lineTop) / 2
	local stripeBottom = band.position.Y
	local stripeThickness = stripeTop - stripeBottom
	local stripeY = (stripeTop + stripeBottom) / 2
	local halfDepth = band.size.Z / 2
	local halfWidth = band.size.X / 2
	-- A 45° stripe whose corners just reach the band edges: (length + width) / (2 √2) = halfDepth.
	local stripeLength = 2 * halfDepth * math.sqrt(2) - STRIPE_WIDTH
	local span = halfWidth - halfDepth -- outermost centres; their corners reach the band ends
	local index = 0
	for x = -span, span + 1e-6, STRIPE_SPACING do
		index += 1
		part(
			markings,
			string.format("Neutral_Stripe_%02d", index),
			Vector3.new(STRIPE_WIDTH, stripeThickness, stripeLength),
			CFrame.new(band.position.X + x, stripeY, band.position.Z) * CFrame.Angles(0, math.pi / 4, 0),
			color(deps, arena.neutralStripeColor),
			MARKING
		)
	end
	for _, sign in { -1, 1 } do
		part(
			markings,
			if sign < 0 then "Neutral_EdgeA" else "Neutral_EdgeB",
			Vector3.new(band.size.X, midline.size.Y, EDGE_LINE_WIDTH),
			CFrame.new(band.position.X, midline.position.Y, band.position.Z + sign * (halfDepth - EDGE_LINE_WIDTH / 2)),
			color(deps, arena.neutralEdgeColor),
			MARKING
		)
	end
	boxPart(markings, "Midline", midline, color(deps, midline.color), MARKING)

	for _, side in { "A", "B" } do
		for index2, tint in arena.sideTints[side] do
			boxPart(markings, string.format("Tint%s_%d", side, index2), tint, color(deps, tint.color), MARKING)
		end
	end
end

local function buildRails(geometry: Folder, deps: Deps)
	local rails = folder(geometry, "Rails")
	for _, rail in deps.arena.rails do
		boxPart(rails, rail.name, rail, color(deps, rail.color), SOLID)
	end
end

-- One cover piece (WorldLayout parts) plus the wall stripes.
local function buildCoverPiece(cover: Folder, piece: any, deps: Deps)
	local pieceModel = model(cover, "Cover_" .. piece.name, true)
	local body: Part? = nil
	local extras = 0
	for _, spec in piece.parts do
		local tint = color(deps, spec.color)
		-- The first part is the Body (PrimaryPart); a Ball on top is the Dome, anything else a Cap.
		local name = if body == nil
			then "Body"
			elseif spec.shape == "Ball" then "Dome"
			else if extras == 0 then "Cap" else string.format("Cap_%d", extras + 1)
		local made: Part
		if spec.shape == "Cylinder" then
			made = uprightCylinder(pieceModel, name, spec.position, spec.size.X, spec.size.Y, tint, SOLID)
		elseif spec.shape == "Ball" then
			made = part(pieceModel, name, spec.size, CFrame.new(spec.position), tint, SOLID, Enum.PartType.Ball)
		elseif spec.shape == "Block" then
			made = part(pieceModel, name, spec.size, CFrame.new(spec.position), tint, SOLID)
		else
			error(string.format("ArenaBuilder: cover %s has an unknown shape %s", piece.name, tostring(spec.shape)), 0)
		end
		if body == nil then
			body = made
		else
			extras += 1
		end
	end
	if body == nil then
		error(string.format("ArenaBuilder: cover %s has no parts", piece.name), 0)
	end
	local main = body :: Part
	pieceModel.PrimaryPart = main
	if piece.kind == "wall" then
		-- Cover walls: Cream stripes `heights` above the bottom, `insetX` narrower than the wall (0.01 inside each X face:
		-- no z-fighting, and the lane-side face stays where WorldLayout puts it) and `proud` deeper (0.05 proud of each
		-- Z face, so they read from the pads).
		local stripes = deps.arena.wallStripes
		if type(stripes) ~= "table" or type(stripes.heights) ~= "table" then
			error("ArenaBuilder: WorldLayout.Arena has no wallStripes table", 0)
		end
		local bottom = main.CFrame.Position.Y - main.Size.Y / 2
		for index, height in stripes.heights do
			part(
				pieceModel,
				string.format("Stripe_%d", index),
				Vector3.new(main.Size.X - stripes.insetX, stripes.thickness, main.Size.Z + stripes.proud),
				CFrame.new(main.CFrame.Position.X, bottom + height, main.CFrame.Position.Z),
				color(deps, "Cream"),
				SOLID
			)
		end
	end
end

local function buildCover(geometry: Folder, deps: Deps)
	local cover = folder(geometry, "Cover")
	for _, piece in deps.arena.cover do
		buildCoverPiece(cover, piece, deps)
	end
end

-- Sets a barrier's collision group; returns a warning when it could not be set (Verify then reports the part).
local function setGroup(part: BasePart, group: string): string?
	local ok, err = pcall(function()
		part.CollisionGroup = group
	end)
	if ok then
		return nil
	end
	return string.format("could not set %s.CollisionGroup = %q: %s", part.Name, group, tostring(err))
end

-- Adds a warning for every barrier whose collision group could not be set.
local function buildBarriers(geometry: Folder, deps: Deps, warnings: { string })
	local barriers = folder(geometry, "Barriers")
	local tint = color(deps, "Cream") -- invisible; a colour only for whoever lowers Transparency while editing
	local barrierGroup = deps.arena.barrierGroup or DEFAULT_BARRIER_GROUP
	for _, volume in deps.arena.barriers do
		local problem = setGroup(boxPart(barriers, volume.name, volume, tint, BARRIER), barrierGroup)
		if problem then
			table.insert(warnings, problem)
		end
	end
	for _, volume in deps.arena.dividers do
		local problem = setGroup(boxPart(barriers, volume.name, volume, tint, BARRIER), DIVIDER_GROUP)
		if problem then
			table.insert(warnings, problem)
		end
	end
end

local function buildZones(root: Model, deps: Deps)
	local zones = folder(root, "Zones")
	local tint = color(deps, "Lavender") -- invisible
	for _, name in ZONE_ORDER do
		local volume = deps.arena.zones[name]
		if volume == nil then
			error(string.format("ArenaBuilder: WorldLayout.Arena.zones has no %s", name), 0)
		end
		boxPart(zones, name, volume, tint, GHOST)
	end
	local spec = deps.arena.audioZone
	local audio = boxPart(zones, "Audio", spec, tint, GHOST)
	audio:AddTag(AUDIO_ZONE_TAG)
	audio:SetAttribute("ZoneId", spec.zoneId)
	audio:SetAttribute("Priority", spec.priority)
	audio:SetAttribute("MusicKey", spec.musicKey)
	audio:SetAttribute("AmbienceKey", spec.ambienceKey)
	audio:SetAttribute("MusicMul", spec.musicMul)
end

local function buildSpawns(root: Model, deps: Deps)
	local spawns = folder(root, "Spawns")
	for _, side in { "A", "B" } do
		local pad = deps.arena.pads[side]
		local position: Vector3 = pad.position
		local facing: Vector3 = pad.facing
		-- Yaw so LookVector = the (horizontal) facing: LookVector of a yaw θ is (-sin θ, 0, -cos θ).
		local yaw = math.atan2(-facing.X, -facing.Z)
		part(
			spawns,
			pad.name,
			Vector3.new(pad.height, pad.diameter, pad.diameter),
			CFrame.new(position) * CFrame.Angles(0, yaw, 0) * ROLL_UP,
			color(deps, pad.color),
			DECOR,
			Enum.PartType.Cylinder
		)
	end
end

local function buildLollipop(decor: Folder, name: string, base: Vector3, height: number, head: Color3, deps: Deps)
	local lollipop = model(decor, name, false)
	local headY = height - LOLLIPOP_HEAD_DIAMETER / 2
	local stickHeight = headY - LOLLIPOP_HEAD_DIAMETER / 2 + 1 -- 1 stud into the head
	local stick = uprightCylinder(
		lollipop,
		"Stick",
		base + Vector3.new(0, stickHeight / 2, 0),
		LOLLIPOP_STICK_DIAMETER,
		stickHeight,
		color(deps, "White"),
		DECOR
	)
	-- The disc's axis (local X) is turned to Z, so the candy faces along the court.
	local headFrame = CFrame.new(base + Vector3.new(0, headY, 0)) * CFrame.Angles(0, HALF_PI, 0)
	part(
		lollipop,
		"Head",
		Vector3.new(LOLLIPOP_HEAD_THICKNESS, LOLLIPOP_HEAD_DIAMETER, LOLLIPOP_HEAD_DIAMETER),
		headFrame,
		head,
		DECOR,
		Enum.PartType.Cylinder
	)
	part(
		lollipop,
		"Swirl",
		Vector3.new(LOLLIPOP_HEAD_THICKNESS + 0.1, LOLLIPOP_SWIRL_DIAMETER, LOLLIPOP_SWIRL_DIAMETER),
		headFrame,
		color(deps, "Cream"),
		DECOR,
		Enum.PartType.Cylinder
	)
	lollipop.PrimaryPart = stick
end

local function buildGumdropStack(decor: Folder, name: string, x: number, z: number, bottom: Color3, top: Color3)
	local stack = model(decor, name, false)
	local big = uprightCylinder(stack, "Base", Vector3.new(x, 1, z), 4, 2, bottom, DECOR)
	part(stack, "BaseDome", Vector3.one * 4, CFrame.new(x, 2, z), bottom, DECOR, Enum.PartType.Ball)
	uprightCylinder(stack, "Top", Vector3.new(x, 4.3, z), 2.6, 1.4, top, DECOR)
	part(stack, "TopDome", Vector3.one * 2.6, CFrame.new(x, 5, z), top, DECOR, Enum.PartType.Ball)
	stack.PrimaryPart = big
end

local function buildDecor(root: Model, deps: Deps)
	local arena = deps.arena
	local decor = folder(root, "Decor")
	boxPart(decor, "Apron", arena.apron, Color3.fromHex(arena.apronColorHex), DECOR)
	for index, spot in arena.decor.lollipops do
		local side = if spot.Z < 0 then "A" else "B"
		buildLollipop(
			decor,
			string.format("Lollipop_%s_%d", side, index),
			spot,
			arena.decor.lollipopHeight,
			color(deps, if spot.Z < 0 then "Strawberry" else "Mint"),
			deps
		)
	end
	local index = 0
	for _, sz in { -1, 1 } do
		for _, sx in { -1, 1 } do
			index += 1
			buildGumdropStack(
				decor,
				string.format("GumdropStack_%s_%d", if sz < 0 then "A" else "B", index),
				sx * GUMDROP_STACK_X,
				sz * GUMDROP_STACK_Z,
				color(deps, if sx < 0 then "Lavender" else "Mint"),
				color(deps, if sz < 0 then "Bubblegum" else "MintCream")
			)
		end
	end
end

local function buildTree(root: Model, deps: Deps, warnings: { string })
	local origin = boxPart(root, "Origin", deps.arena.origin, color(deps, "Cream"), GHOST)
	root.PrimaryPart = origin

	local geometry = folder(root, "Geometry")
	buildFloor(geometry, deps)
	buildMarkings(geometry, deps)
	buildRails(geometry, deps)
	buildCover(geometry, deps)
	buildBarriers(geometry, deps, warnings)

	buildZones(root, deps)
	buildSpawns(root, deps)
	buildDecor(root, deps)
	folder(root, "Runtime")
end

-- Public

-- Builds the new template tree, unparented and marked. Never yields and never changes the place.
function ArenaBuilder.build(ctx: BuildContext): BuildResult
	local warnings: { string } = {}
	local deps, depsError = loadDeps(ctx.Shared)
	if deps == nil then
		return failure(warnings, depsError or "Shared modules missing")
	end

	-- The root is destroyed with the scratch unless Main has taken it over (handedOver), so a throw half way
	-- leaves nothing behind.
	local root = Instance.new("Model")
	root.Name = ROOT_NAME
	root.ModelStreamingMode = Enum.ModelStreamingMode.Default -- §5.3: the root is not Atomic
	local handedOver = false
	ctx.scratch:add(function()
		if not handedOver then
			root:Destroy()
		end
	end)

	local ok, err = pcall(function(): string?
		buildTree(root, deps, warnings)
		return nil
	end)
	if not ok then
		return failure(warnings, "ArenaBuilder: " .. tostring(err))
	end

	Generated.mark(root, GENERATOR_ID, VERSION)
	handedOver = true
	return { ok = true, root = root, warnings = warnings, error = nil }
end

return ArenaBuilder
