--!strict
-- SquishyBuilder_Test: the DESIGN §8.1 rule 11 "L1" test for Art/SquishyBuilder and Art/SquishyBlueprints (with its
-- Kit), rewritten as rule checks for the squishy overhaul (spec 2026-10-09 §3.1, §6): no per-toy geometry is pinned
-- here (exact part counts and rigidities are pinned again after the Studio tuning pass), so the geometry lanes can
-- replace any blueprint and keep this test green.
-- Server only (ServerStorage.UnitTest). Edit-mode safe: builds unparented models, no Play-only APIs.
-- Contract: the 19 blueprints (14 squishies + gift_box, dragon_head_vfx, 3 giant pads) build in every mode; the part
-- budget (<= 31 visible + Root in every face state, <= 6 hidden squish-face parts, <= 12 hinged parts in <= 6
-- sections); the longest bound 1-4 studs (giant pads: their footprint) and, for redesigned squishies, 1.5-1.7 studs in
-- hand (Dragon, Cloud Bunny 1.8); no lights/GUIs/scripts/decals/sounds; every part non-colliding/non-query/non-touch/
-- massless; face parts (embed >= 0.5) centred inside a body part and looking out of their side; look parts without
-- shadows and the squish set hidden; section pivots inside a body part and the section's first part; contact points
-- inside their holder at rest; SD_HalfExtents = half the body bounds; the flight model's body silhouette = the throw
-- radius (§8.1 #9; frontalRadius counts body parts only, §3.3). Squishies still on face kit v1 (version 1 of the 8
-- existing ones) skip the face kit v2 and contact-declaration rules until their redesign bumps the version.
-- Fixture blueprints go through build's options.blueprint (back-side faces, sections, contacts, bad input).
-- Geometry is measured from the built instances (Size × mesh Scale, CFrame), not from the builder's internals.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type Report = (message: string) -> ()

local PhysicsService = game:GetService("PhysicsService")

local MODES = { "Viewport", "World", "Held" }
local MAX_VISIBLE = 31 -- visible BaseParts in any face state, Root not included (§3.1)
local MAX_HIDDEN = 6 -- the hidden squish-face set
local MAX_HINGED, MAX_SECTIONS = 12, 6
local MIN_BOUND, MAX_BOUND = 1, 4
local FIT_MIN, FIT_MAX, FIT_MAX_LARGE = 1.5, 1.7, 1.8 -- longest side in hand, redesigned squishies (§3.1)
local FIT_LARGE: { [string]: boolean } = { dragon = true, cloud_bunny = true } -- horns, ears
local EMBED_MIN = 0.5
local RB_SPHERE_RADIUS = 1.375
local EPS = 1e-4
local FLOAT_TOLERANCE = 1e-4 -- Roblox stores sizes and attributes as float32
local FRONTAL_RADIUS_TOLERANCE = 0.02 -- frontalRadius() vs the measured silhouette
local FORBIDDEN_CLASSES = { "Light", "GuiBase", "LuaSourceContainer", "Decal", "Sound" }
local COSMETIC_GROUP = "SD_Cosmetic"
local BACK_POINT = Vector3.new(0, 0, 1)

-- The 14 squishies (§3.3 order) and the 8 that keep face kit v1 while their blueprint is version 1.
local SQUISHY_IDS = {
	"kitty_bread",
	"toast",
	"banana",
	"butter",
	"chocolate",
	"bird",
	"donut",
	"dragon",
	"boba_bear",
	"pancake_pup",
	"mochi_fox",
	"strawberry_frog",
	"cloud_bunny",
	"cupcake_axolotl",
}
local FACE_KIT_V1: { [string]: boolean } = {
	kitty_bread = true,
	toast = true,
	banana = true,
	butter = true,
	chocolate = true,
	bird = true,
	donut = true,
	dragon = true,
}
-- §17.12: the giant pads' footprint is 8-9 studs instead of the 1-4-stud bound (no Catalog entry: no flight check).
-- Phase 3 (the design lobby, D5): the design's pads are 8.4-10.2 studs wide and their rest tops 4.8-6.6 studs.
local GIANT_IDS: { [string]: boolean } = { giant_jelly = true, giant_marshmallow = true, giant_cushion = true }
local GIANT_MIN_FOOTPRINT, GIANT_MAX_FOOTPRINT = 8.4, 10.2
local GIANT_MAX_HEIGHT = 6.6
local DRAGON_HEAD_ID = "dragon_head_vfx"
local DRAGON_HEAD_MAX_PARTS = 19

-- Face states (§3.2 table): the looks each state hides (on top of the hidden squish set at rest) and shows.
local SQUISH_SET: { [string]: boolean } = { squishEye = true, squishMouth = true, tongue = true }
local HIDDEN_IN_SQUISH: { [string]: boolean } = { eye = true, eyeArc = true, shine = true, mouth = true }
local LOOKS: { [string]: boolean } = {
	eye = true,
	eyeArc = true,
	shine = true,
	mouth = true,
	mouthOpen = true,
	cheek = true,
	squishEye = true,
	squishMouth = true,
	tongue = true,
	detail = true,
}

-- §4 / §6 motion rules (Config.validate pins the same ranges).
local FEELS: { [string]: boolean } = { foam = true, mochi = true, jelly = true, plush = true }
local FLIGHT_STYLES: { [string]: boolean } = {
	tumble = true,
	frisbee = true,
	spiral = true,
	wheel = true,
	glide = true,
	face = true,
	hop = true,
	upright = true,
	float = true,
	sway = true,
	wobble = true,
	roll = true,
}
local RANGES: { [string]: { number } } =
	{ depth = { 0.55, 0.72 }, widen = { 0.4, 0.85 }, kRel = { 20, 60 }, cRel = { 6, 10 } }

-- Wedge corners in half-size units (full bottom, tall edge at +Z); only used for bounds.
local WEDGE_CORNERS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(1, -1, 1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, 1, 1),
}

-- Instance helpers ----------------------------------------------------------------------------------------------

local function sortedIds(blueprints: { [string]: any }): { string }
	local ids: { string } = {}
	for id in blueprints do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function allParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function visualParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, part in allParts(model) do
		if part ~= model.PrimaryPart then
			table.insert(parts, part)
		end
	end
	return parts
end

local function bodyParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, part in visualParts(model) do
		if part:GetAttribute("SD_Body") == true then
			table.insert(parts, part)
		end
	end
	return parts
end

local function shownParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, part in visualParts(model) do
		if part.Transparency < 1 then
			table.insert(parts, part)
		end
	end
	return parts
end

local function meshOf(part: BasePart): SpecialMesh?
	return part:FindFirstChildOfClass("SpecialMesh")
end

-- Rendered size: Size × mesh Scale (Brick/Sphere/Wedge meshes scale the part size).
local function renderedSize(part: BasePart): Vector3
	local mesh = meshOf(part)
	return if mesh then part.Size * mesh.Scale else part.Size
end

-- "E" | "B" | "W" | "RB" from the instance itself (no mesh = a rounded-box union).
local function shapeOf(part: BasePart): string
	local mesh = meshOf(part)
	if mesh == nil then
		return "RB"
	elseif mesh.MeshType == Enum.MeshType.Sphere then
		return "E"
	elseif mesh.MeshType == Enum.MeshType.Wedge then
		return "W"
	end
	return "B"
end

-- Axis-aligned bounds of `parts`, in model (Root) space: (min, max).
local function measureBounds(model: Model, parts: { BasePart }): (Vector3, Vector3)
	local rootCFrame = (model.PrimaryPart :: BasePart).CFrame
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local function include(p: Vector3)
		minX, minY, minZ = math.min(minX, p.X), math.min(minY, p.Y), math.min(minZ, p.Z)
		maxX, maxY, maxZ = math.max(maxX, p.X), math.max(maxY, p.Y), math.max(maxZ, p.Z)
	end
	for _, part in parts do
		local cf = rootCFrame:ToObjectSpace(part.CFrame)
		local half = renderedSize(part) / 2
		local shape = shapeOf(part)
		if shape == "W" then
			for _, corner in WEDGE_CORNERS do
				include(cf:PointToWorldSpace(corner * half))
			end
		else
			local x, y, z = cf.XVector * half.X, cf.YVector * half.Y, cf.ZVector * half.Z
			local extent = if shape == "E"
				then Vector3.new(
					math.sqrt(x.X ^ 2 + y.X ^ 2 + z.X ^ 2),
					math.sqrt(x.Y ^ 2 + y.Y ^ 2 + z.Y ^ 2),
					math.sqrt(x.Z ^ 2 + y.Z ^ 2 + z.Z ^ 2)
				)
				else Vector3.new(
					math.abs(x.X) + math.abs(y.X) + math.abs(z.X),
					math.abs(x.Y) + math.abs(y.Y) + math.abs(z.Y),
					math.abs(x.Z) + math.abs(y.Z) + math.abs(z.Z)
				)
			include(cf.Position - extent)
			include(cf.Position + extent)
		end
	end
	return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
end

local function measureSize(model: Model, parts: { BasePart }?): Vector3
	local lo, hi = measureBounds(model, parts or visualParts(model))
	return hi - lo
end

-- 0.5·√(W·H) of the measured front silhouette of the body parts (§8.1 #9, §3.3).
local function measureFrontalRadius(model: Model): number
	local size = measureSize(model, bodyParts(model))
	return 0.5 * math.sqrt(size.X * size.Y)
end

-- Whether `point` (model space) is inside a part (E, B, W, or RB = box ∩ sphere of normalized radius 1.375).
local function contains(part: BasePart, point: Vector3): boolean
	local q = part.CFrame:PointToObjectSpace(point) / (renderedSize(part) / 2)
	local shape = shapeOf(part)
	if shape == "E" then
		return q.Magnitude <= 1 + EPS
	end
	local inBox = math.abs(q.X) <= 1 + EPS and math.abs(q.Y) <= 1 + EPS and math.abs(q.Z) <= 1 + EPS
	if shape == "RB" then
		return inBox and q.Magnitude <= RB_SPHERE_RADIUS + EPS
	elseif shape == "W" then
		return inBox and q.Y <= q.Z + EPS -- under the slope (bottom y = -1, tall edge at z = +1)
	end
	return inBox
end

-- The built part(s) of one spec: a TRI is its two W halves.
local function builtOf(model: Model, spec: any): { BasePart }
	local names: { string } = if spec.shape == "TRI"
		then { spec.name .. "_HalfL", spec.name .. "_HalfR" }
		else { spec.name }
	local parts: { BasePart } = {}
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

local function near(a: Vector3, b: Vector3, tolerance: number): boolean
	return (a - b).Magnitude <= tolerance
end

local function failIfAny(problems: { string })
	if #problems > 0 then
		error(string.format("%d problem(s): %s", #problems, table.concat(problems, "; ")), 2)
	end
end

return function(t: Context)
	local Builder = t.requireShared("Art/SquishyBuilder")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local Kit = t.requireShared("Art/SquishyBlueprints/Kit")
	local expect = t.expect
	local ids = sortedIds(Blueprints)
	local v, F = Kit.v, Kit.F

	-- Face kit v2 rules apply to every squishy except the 8 old ones while they are still version 1.
	local function onFaceKitV2(id: string): boolean
		local blueprint = Blueprints[id]
		return blueprint.motion ~= nil and not (FACE_KIT_V1[id] and blueprint.version == 1)
	end

	-- Builds every blueprint in every mode (default options), runs `check`, destroys the model.
	local function eachBuild(check: (id: string, mode: string, model: Model, report: Report) -> ()): { string }
		local problems: { string } = {}
		for _, id in ids do
			for _, mode in MODES do
				local model = Builder.build(id, mode)
				check(id, mode, model, function(message: string)
					table.insert(problems, `{id}/{mode}: {message}`)
				end)
				model:Destroy()
			end
		end
		return problems
	end

	-- A stand-in for ReplicatedStorage.SD_ShapeLibrary.RoundedBox, with junk the builder must not copy.
	local function fakeRoundedBox(): Part
		local template = Instance.new("Part")
		template.Name = "RoundedBox"
		template:SetAttribute("Junk", 1)
		template:AddTag("SD_TestJunk")
		Instance.new("Folder").Parent = template
		return template
	end

	-- The fixture: a body with a hinged ear pair, a back-side spot, the v2 face and its squish set.
	local function fixture(): any
		return {
			version = 1,
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
	end

	local function buildFixture(blueprint: any, mode: string?, scale: number?): Model
		return Builder.build("fixture", mode or "Viewport", scale, { blueprint = blueprint })
	end

	-- Data -----------------------------------------------------------------------------------------------------------

	t.test("the 19 blueprints: 14 squishies, gift_box, dragon_head_vfx and the 3 giant pads", function()
		local expected = table.clone(SQUISHY_IDS)
		for _, id in { "gift_box", DRAGON_HEAD_ID, "giant_jelly", "giant_marshmallow", "giant_cushion" } do
			table.insert(expected, id)
		end
		table.sort(expected)
		expect.deepEqual(ids, expected)
		for _, id in ids do
			local blueprint = Blueprints[id]
			expect.truthy(type(blueprint.version) == "number" and blueprint.version >= 1)
			expect.truthy(type(blueprint.scale) == "number" and blueprint.scale > 0)
		end
	end)

	t.test("the 14 squishies carry a §4 motion row inside the §6 ranges; the others have none", function()
		local problems: { string } = {}
		local isSquishy: { [string]: boolean } = {}
		for _, id in SQUISHY_IDS do
			isSquishy[id] = true
		end
		for _, id in ids do
			local motion = Blueprints[id].motion
			if not isSquishy[id] then
				if motion ~= nil then
					table.insert(problems, `{id} has a motion row`)
				end
				continue
			end
			if type(motion) ~= "table" or type(motion.squeeze) ~= "table" or type(motion.flight) ~= "table" then
				table.insert(problems, `{id} has no motion row`)
				continue
			end
			for key, range in RANGES do
				local value = motion.squeeze[key]
				if type(value) ~= "number" or value < range[1] or value > range[2] then
					table.insert(problems, `{id}.squeeze.{key} {value} outside {range[1]}-{range[2]}`)
				end
			end
			if not FEELS[motion.feel] then
				table.insert(problems, `{id}.feel {motion.feel}`)
			end
			if not FLIGHT_STYLES[motion.flight.style] then
				table.insert(problems, `{id}.flight.style {motion.flight.style}`)
			end
		end
		failIfAny(problems)
	end)

	t.test("face kit v2 squishies have eyes (or happy eyes), one shine per eye and a full squish set", function()
		local problems: { string } = {}
		for _, id in SQUISHY_IDS do
			local blueprint = Blueprints[id]
			local count: { [string]: number } = {}
			for _, spec in blueprint.parts do
				if spec.look then
					count[spec.look] = (count[spec.look] or 0) + 1
				end
			end
			if not onFaceKitV2(id) then
				-- Face kit v1 (version 1 of the 8 old ones): no looks until the redesign.
				if next(count) ~= nil then
					table.insert(
						problems,
						`{id}: looks on a face kit v1 blueprint (bump its version with the redesign)`
					)
				end
				continue
			end
			local eyes, arcs = count.eye or 0, count.eyeArc or 0
			if not (eyes == 2 or (eyes == 0 and arcs >= 2)) then
				table.insert(problems, `{id}: {eyes} eyes and {arcs} eye arcs`)
			end
			if (count.shine or 0) ~= eyes then
				table.insert(problems, `{id}: {count.shine or 0} shines for {eyes} eyes`)
			end
			if (count.squishEye or 0) ~= 4 then
				table.insert(problems, `{id}: {count.squishEye or 0} squish-eye strokes (expected 4)`)
			end
			local wantsMouth = (count.mouth or 0) > 0
			if (count.squishMouth or 0) ~= (if wantsMouth then 1 else 0) then
				table.insert(
					problems,
					`{id}: {count.squishMouth or 0} squish mouths for {count.mouth or 0} mouth parts`
				)
			end
			if (count.tongue or 0) > (count.squishMouth or 0) then
				table.insert(problems, `{id}: a squish tongue without a squish mouth`)
			end
		end
		failIfAny(problems)
	end)

	t.test(
		"part budget: <= 31 visible + Root in every face state, <= 6 hidden, <= 12 hinged in <= 6 sections",
		function()
			local problems: { string } = {}
			for _, id in ids do
				local model = Builder.build(id, "Viewport")
				local shown, hidden, hinged = 0, 0, 0
				local inSquish, inWow = 0, 0
				local sections: { [string]: boolean } = {}
				local sectionCount = 0
				for _, part in visualParts(model) do
					local look = part:GetAttribute("SD_Look")
					local section = part:GetAttribute("SD_Section")
					if type(look) == "string" and SQUISH_SET[look] then
						hidden += 1
						inSquish += 1
						if look == "squishMouth" then
							inWow += 1 -- the wow face's round "o"
						end
					else
						shown += 1
						if not (type(look) == "string" and HIDDEN_IN_SQUISH[look]) then
							inSquish += 1
						end
						if look ~= "mouth" then
							inWow += 1
						end
					end
					if type(section) == "string" then
						hinged += 1
						if not sections[section] then
							sections[section] = true
							sectionCount += 1
						end
					end
				end
				model:Destroy()
				local cap = if id == DRAGON_HEAD_ID then DRAGON_HEAD_MAX_PARTS else MAX_VISIBLE
				local most = math.max(shown, inSquish, inWow)
				if most > cap then
					table.insert(
						problems,
						`{id}: {most} visible parts (rest {shown}, squish {inSquish}, wow {inWow}) > {cap}`
					)
				end
				if hidden > MAX_HIDDEN then
					table.insert(problems, `{id}: {hidden} hidden parts > {MAX_HIDDEN}`)
				end
				if hinged > MAX_HINGED or sectionCount > MAX_SECTIONS then
					table.insert(problems, `{id}: {hinged} hinged parts in {sectionCount} sections`)
				end
			end
			failIfAny(problems)
		end
	)

	-- Rules on built models ----------------------------------------------------------------------------------------

	t.test("L1: at most 31 visible + 6 hidden parts + Root in every mode", function()
		failIfAny(eachBuild(function(_id, _mode, model, report)
			local count = #allParts(model)
			if count > MAX_VISIBLE + MAX_HIDDEN + 1 then
				report(`{count} parts`)
			end
		end))
	end)

	t.test("L1: the longest bound is 1-4 studs at blueprint scale (giant pads: an 8.4-10.2-stud footprint)", function()
		failIfAny(eachBuild(function(id, _mode, model, report)
			local size = measureSize(model)
			if GIANT_IDS[id] then
				-- The footprint is the width (X); the face stands out of the -Z side, so Z is a little deeper.
				if size.X < GIANT_MIN_FOOTPRINT - EPS or size.X > GIANT_MAX_FOOTPRINT + EPS then
					report(`footprint {size.X}, expected {GIANT_MIN_FOOTPRINT}-{GIANT_MAX_FOOTPRINT}`)
				end
				if not (size.Y > 0 and size.Y <= GIANT_MAX_HEIGHT + EPS and size.Z >= size.X) then
					report(`bounds {size}`)
				end
				return
			end
			local longest = math.max(size.X, size.Y, size.Z)
			if longest < MIN_BOUND or longest > MAX_BOUND or math.min(size.X, size.Y, size.Z) <= 0 then
				report(`bounds {size}`)
			end
		end))
	end)

	t.test(
		"redesigned squishies fit the hand: the longest shown side is 1.5-1.7 studs (Dragon, Cloud Bunny 1.8)",
		function()
			local problems: { string } = {}
			for _, id in SQUISHY_IDS do
				if not onFaceKitV2(id) then
					continue
				end
				local model = Builder.build(id, "Held")
				local size = measureSize(model, shownParts(model))
				model:Destroy()
				local longest = math.max(size.X, size.Y, size.Z)
				local most = if FIT_LARGE[id] then FIT_MAX_LARGE else FIT_MAX
				if longest < FIT_MIN - EPS or longest > most + EPS then
					table.insert(problems, `{id}: longest side {longest}, expected {FIT_MIN}-{most}`)
				end
			end
			failIfAny(problems)
		end
	)

	-- The lobby generator stands each giant pad's face on the side of its WorldLayout pad: the blueprint must have the
	-- pad's footprint and rest top, and its face must sit on the lower half of the side, below the quilted tiles' top.
	t.test("giant pad blueprints match WorldLayout.GiantPads and keep their faces low on the side", function()
		local WorldLayout = t.requireShared("World/WorldLayout")
		local problems: { string } = {}
		local seen = 0
		for _, key in WorldLayout.GiantPadKeys do
			local pad = WorldLayout.giantPad(key)
			local id = pad.blueprintId
			if not GIANT_IDS[id] or Blueprints[id] == nil then
				table.insert(problems, `{key}: blueprint {id} is missing`)
				continue
			end
			seen += 1
			local model = Builder.build(id, "Viewport")
			local body = model:FindFirstChild("Body") :: BasePart
			if not near(renderedSize(body), Vector3.new(pad.footprint, pad.restTop, pad.footprint), EPS) then
				table.insert(problems, `{id}: Body {renderedSize(body)} is not the pad's footprint x rest top`)
			end
			local floor = -pad.restTop / 2
			for _, spec in Blueprints[id].parts do
				if spec.face == nil then
					continue
				end
				local part = model:FindFirstChild(spec.name) :: BasePart
				local height = part.CFrame.Position.Y - floor
				if height <= 0 or height >= pad.restTop / 2 then
					table.insert(problems, `{id}/{spec.name} is {height} above the floor, not on the lower half`)
				end
				if part.CFrame.Position.Z > -pad.footprint / 2 + 0.5 then
					table.insert(problems, `{id}/{spec.name} is not on the front (-Z) side`)
				end
			end
			model:Destroy()
		end
		expect.equal(seen, 3)
		failIfAny(problems)
	end)

	t.test("L1: no lights, GUIs, scripts, decals or sounds", function()
		failIfAny(eachBuild(function(_id, _mode, model, report)
			for _, descendant in model:GetDescendants() do
				for _, className in FORBIDDEN_CLASSES do
					if descendant:IsA(className) then
						report(`{descendant:GetFullName()} is a {className}`)
					end
				end
			end
		end))
	end)

	t.test("L1: every part is non-colliding, non-query, non-touch and massless", function()
		failIfAny(eachBuild(function(_id, _mode, model, report)
			for _, part in allParts(model) do
				if part.CanCollide or part.CanQuery or part.CanTouch or not part.Massless then
					report(`{part.Name} has a physics flag set`)
				end
			end
		end))
	end)

	t.test("L1: every face part has embed >= 0.5 and its centre inside a body part (RB and fallback)", function()
		local template = fakeRoundedBox()
		local problems: { string } = {}
		local variants: { { roundedBox: any } } = { { roundedBox = false }, { roundedBox = template } }
		for _, options in variants do
			for _, id in ids do
				for _, mode in MODES do
					local model = Builder.build(id, mode, nil, options)
					local bodies = bodyParts(model)
					for _, spec in Blueprints[id].parts do
						if spec.face == nil then
							continue
						end
						local where = `{id}/{mode}/{spec.name}`
						if not (spec.face.embed >= EMBED_MIN) then
							table.insert(problems, `{where}: embed {spec.face.embed} < {EMBED_MIN}`)
						end
						local part = model:FindFirstChild(spec.name)
						if part == nil or not part:IsA("BasePart") then
							table.insert(problems, `{where}: part missing`)
							continue
						end
						local inside = false
						for _, body in bodies do
							if body ~= part and contains(body, part.CFrame.Position) then
								inside = true
								break
							end
						end
						if not inside then
							table.insert(problems, `{where}: centre {part.CFrame.Position} is not inside a body part`)
						end
					end
					model:Destroy()
				end
			end
		end
		template:Destroy()
		failIfAny(problems)
	end)

	t.test("the flight model's body silhouette matches the throw radius (all 14; §8.1 #9, §3.3)", function()
		local Catalog = t.requireShared("Catalog")
		local Config = t.requireShared("Config")
		local tolerance = Config.Vfx.Projectile.flightRadiusTolerance
		local radiusOf: { [string]: number } = {}
		local problems: { string } = {}
		local isSquishy: { [string]: boolean } = {}
		for _, id in SQUISHY_IDS do
			isSquishy[id] = true
		end
		for _, def in Catalog.list() do
			if not isSquishy[def.blueprintId] then
				table.insert(problems, `{def.id}: blueprint {def.blueprintId} is not one of the 14 squishies`)
			end
			radiusOf[def.blueprintId] = def.throw.radius
		end
		for _, id in SQUISHY_IDS do
			local radius = radiusOf[id] or 1 -- not in the Catalog yet: any radius checks the builder
			local scale = Builder.flightScale(id, radius)
			local model = Builder.build(id, "World", scale)
			local measured = measureFrontalRadius(model)
			model:Destroy()
			if math.abs(measured - radius) > tolerance * radius then
				table.insert(problems, `{id}: body frontal radius {measured} vs throw radius {radius}`)
			end
		end
		failIfAny(problems)
	end)

	-- §9.10: the Rush head (built at Config.Vfx.DragonRush.headScale) is never wider than the lane, 2R.
	t.test("dragon_head_vfx at Config.Vfx.DragonRush.headScale is at most 2 x the Dragon Rush radius wide", function()
		local Config = t.requireShared("Config")
		local scale = Config.Vfx.DragonRush.headScale
		local laneWidth = 2 * Config.Abilities.dragon_rush.radius
		local model = Builder.build(DRAGON_HEAD_ID, "World", scale)
		local size = measureSize(model)
		model:Destroy()
		if not (size.X > 0 and size.X <= laneWidth) then
			error(`head width {size.X} at scale {scale} is not within (0, {laneWidth}]`)
		end
	end)

	-- Construction rules ---------------------------------------------------------------------------------------------

	t.test("Root is the invisible 0.2³ PrimaryPart at the origin, without a mesh", function()
		failIfAny(eachBuild(function(id, _mode, model, report)
			local root = model.PrimaryPart
			if root == nil or root.Name ~= "Root" or root.Parent ~= model then
				report("PrimaryPart is not the Root")
				return
			end
			if model.Name ~= id then
				report(`model named {model.Name}`)
			end
			if root.Transparency ~= 1 or not near(root.Size, Vector3.new(0.2, 0.2, 0.2), EPS) then
				report("Root is not an invisible 0.2³ part")
			end
			if not near(root.CFrame.Position, Vector3.zero, EPS) or meshOf(root) ~= nil then
				report("Root is not at the origin or has a mesh")
			end
		end))
	end)

	t.test("build modes: Viewport anchored without welds; World and Held welded to Root", function()
		failIfAny(eachBuild(function(_id, mode, model, report)
			local root = model.PrimaryPart :: BasePart
			if root.Anchored ~= (mode ~= "Held") then
				report(`Root.Anchored = {root.Anchored}`)
			end
			for _, part in visualParts(model) do
				if part.Anchored ~= (mode == "Viewport") then
					report(`{part.Name}.Anchored = {part.Anchored}`)
				end
				local welded = false
				for _, child in part:GetChildren() do
					if child:IsA("Weld") and child.Part0 == root and child.Part1 == part then
						welded = true
						-- The weld must hold the part exactly where the builder placed it, whatever the parenting
						-- order later (a WeldConstraint captured a wrong offset in Play, 2026-10-05).
						local placed = root.CFrame * child.C0 * child.C1:Inverse()
						if (placed.Position - part.CFrame.Position).Magnitude > 1e-4 then
							report(`{part.Name} weld offset does not match its built position`)
						end
					end
				end
				if welded ~= (mode ~= "Viewport") then
					report(`{part.Name} welded = {welded}`)
				end
			end
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("WeldConstraint") then
					report(`{descendant.Name}: WeldConstraint is not allowed (offset depends on parenting order)`)
				end
				if mode == "Viewport" and descendant:IsA("JointInstance") then
					report(`{descendant.Name} in a Viewport build`)
				end
			end
		end))
	end)

	t.test("visual parts: meshed Blocks or RB, SmoothPlastic, SD_Cosmetic when registered", function()
		local expectedGroup = if PhysicsService:IsCollisionGroupRegistered(COSMETIC_GROUP)
			then COSMETIC_GROUP
			else "Default"
		failIfAny(eachBuild(function(_id, _mode, model, report)
			for _, part in visualParts(model) do
				local mesh = meshOf(part)
				if mesh then
					if not part:IsA("Part") or (part :: Part).Shape ~= Enum.PartType.Block then
						report(`{part.Name} is not a Block Part`)
					end
				elseif part:GetAttribute("SD_Shape") ~= "RB" then
					report(`{part.Name} has no mesh and is not an RB`)
				end
				if part.Material ~= Enum.Material.SmoothPlastic then
					report(`{part.Name} material {part.Material}`)
				end
				if part.CollisionGroup ~= expectedGroup then
					report(`{part.Name} in collision group {part.CollisionGroup}`)
				end
			end
		end))
	end)

	t.test("looks: the squish set is built hidden, every other part shown; no look part casts a shadow", function()
		local problems: { string } = {}
		local function check(where: string, model: Model)
			for _, part in visualParts(model) do
				local look = part:GetAttribute("SD_Look")
				local hidden = type(look) == "string" and SQUISH_SET[look] == true
				if part.Transparency ~= (if hidden then 1 else 0) then
					table.insert(problems, `{where}/{part.Name}: Transparency {part.Transparency}`)
				end
				if part.CastShadow ~= (look == nil) then
					table.insert(problems, `{where}/{part.Name}: CastShadow {part.CastShadow} (look {look})`)
				end
			end
		end
		for _, id in ids do
			local model = Builder.build(id, "Held")
			check(id, model)
			model:Destroy()
		end
		local model = buildFixture(fixture(), "Held")
		check("fixture", model)
		-- The fixture holds every v2 role, so the rule above really ran on hidden and shadowless parts.
		expect.equal((model:FindFirstChild("SquishTongue") :: BasePart).Transparency, 1)
		expect.falsy((model:FindFirstChild("EyeL") :: BasePart).CastShadow)
		expect.truthy((model:FindFirstChild("Body") :: BasePart).CastShadow)
		model:Destroy()
		failIfAny(problems)
	end)

	t.test("face parts look out of their side: -Z, or +Z on the back (face.side)", function()
		local problems: { string } = {}
		local function check(where: string, blueprint: any, model: Model)
			for _, spec in blueprint.parts do
				if spec.face == nil then
					continue
				end
				local back = spec.face.side == "back"
				for _, part in builtOf(model, spec) do
					local look = part.CFrame.LookVector.Z
					if (back and not (look > 0)) or (not back and not (look < 0)) then
						table.insert(problems, `{where}/{part.Name} looks along {part.CFrame.LookVector}`)
					end
				end
			end
		end
		for _, id in ids do
			local model = Builder.build(id, "Viewport")
			check(id, Blueprints[id], model)
			model:Destroy()
		end
		local blueprint = fixture()
		local model = buildFixture(blueprint)
		check("fixture", blueprint, model)
		-- The back-side spot sits on the body's back surface, sunk by (embed - 0.5) of its depth. The ray math runs on
		-- float32 Vector3s 100 studs out, so the surface is found to about 1e-3 (front and back alike).
		local spot = model:FindFirstChild("Spot") :: BasePart
		local surfaceZ = 0.6 * math.sqrt(1 - (0.3 / 0.7) ^ 2 - (0.1 / 0.6) ^ 2)
		expect.near(spot.CFrame.Position.Z, surfaceZ - 0.1 * 0.04, 2e-3)
		expect.near(spot.CFrame.Position.X, 0.3, FLOAT_TOLERANCE)
		model:Destroy()
		failIfAny(problems)
	end)

	t.test("attached parts touch their anchor", function()
		local problems: { string } = {}
		for _, id in ids do
			local model = Builder.build(id, "Viewport")
			for _, spec in Blueprints[id].parts do
				if spec.attach == nil then
					continue
				end
				local part = model:FindFirstChild(spec.name)
				local anchor = model:FindFirstChild(spec.attach.to)
				if part == nil or anchor == nil or not part:IsA("BasePart") or not anchor:IsA("BasePart") then
					table.insert(problems, `{id}/{spec.name}: part or anchor missing`)
					continue
				end
				local offset = anchor.CFrame:PointToObjectSpace(part.CFrame.Position)
				local limit = renderedSize(anchor) / 2 + renderedSize(part) / 2
				if math.abs(offset.X) > limit.X or math.abs(offset.Y) > limit.Y or math.abs(offset.Z) > limit.Z then
					table.insert(problems, `{id}/{spec.name} is detached from {spec.attach.to}`)
				end
			end
			model:Destroy()
		end
		failIfAny(problems)
	end)

	t.test("roles: SD_Look, SD_Section, SD_Contact, SD_ContactWith and SD_Rigidity mirror the spec", function()
		local problems: { string } = {}
		local function check(where: string, blueprint: any, model: Model)
			for _, spec in blueprint.parts do
				local built = builtOf(model, spec)
				if #built == 0 then
					table.insert(problems, `{where}/{spec.name}: not built`)
				end
				local contact = spec.contact or (if spec.face or spec.attach then BACK_POINT else nil)
				local holder = spec.contactWith or (if spec.attach then spec.attach.to else nil)
				for _, part in built do
					local at = `{where}/{part.Name}`
					if part:GetAttribute("SD_Look") ~= spec.look then
						table.insert(problems, `{at}: SD_Look {part:GetAttribute("SD_Look")} (spec {spec.look})`)
					end
					if part:GetAttribute("SD_Section") ~= spec.section then
						table.insert(problems, `{at}: SD_Section {part:GetAttribute("SD_Section")}`)
					end
					local got = part:GetAttribute("SD_Contact")
					if contact == nil then
						if got ~= nil then
							table.insert(problems, `{at}: SD_Contact {got} on a part without a contact point`)
						end
					elseif typeof(got) ~= "Vector3" or not near(got, contact, FLOAT_TOLERANCE) then
						table.insert(problems, `{at}: SD_Contact {got} (expected {contact})`)
					end
					if part:GetAttribute("SD_ContactWith") ~= holder then
						table.insert(problems, `{at}: SD_ContactWith {part:GetAttribute("SD_ContactWith")}`)
					end
					local rigidity = part:GetAttribute("SD_Rigidity")
					if rigidity ~= spec.rigidity then
						table.insert(problems, `{at}: SD_Rigidity {rigidity} (spec {spec.rigidity})`)
					end
					local look = part:GetAttribute("SD_Look")
					if look ~= nil and not LOOKS[look :: string] then
						table.insert(problems, `{at}: unknown look {look}`)
					end
				end
			end
		end
		for _, id in ids do
			local model = Builder.build(id, "Held")
			check(id, Blueprints[id], model)
			model:Destroy()
		end
		local blueprint = fixture()
		local model = buildFixture(blueprint, "Held")
		check("fixture", blueprint, model)
		-- pair() mirrored the ear's section name and its contact point's x.
		local earR = model:FindFirstChild("EarR") :: BasePart
		expect.equal(earR:GetAttribute("SD_Section"), "EarR")
		expect.truthy(near(earR:GetAttribute("SD_Contact") :: Vector3, v(-0.2, -1, 0), FLOAT_TOLERANCE))
		model:Destroy()
		failIfAny(problems)
	end)

	t.test("contact points sit inside their holder at rest; redesigned toys declare one on every detail", function()
		local problems: { string } = {}
		local function check(where: string, blueprint: any, model: Model, strict: boolean)
			local bodies = bodyParts(model)
			for _, part in visualParts(model) do
				local contact = part:GetAttribute("SD_Contact")
				if typeof(contact) ~= "Vector3" then
					continue
				end
				local point = part.CFrame:PointToWorldSpace((contact :: Vector3) * renderedSize(part) / 2)
				local holderName = part:GetAttribute("SD_ContactWith")
				local holders: { BasePart } = bodies
				if type(holderName) == "string" then
					holders = builtOf(model, { name = holderName, shape = "" })
					if #holders == 0 then
						holders = builtOf(model, { name = holderName, shape = "TRI" })
					end
				end
				local inside = false
				for _, holder in holders do
					if holder ~= part and contains(holder, point) then
						inside = true
						break
					end
				end
				if not inside then
					table.insert(problems, `{where}/{part.Name}: contact point is outside {holderName or "the body"}`)
				end
			end
			if strict then
				for _, spec in blueprint.parts do
					if not spec.body and spec.face == nil and spec.attach == nil and spec.contact == nil then
						table.insert(problems, `{where}/{spec.name}: a detail without a contact point`)
					end
				end
			end
		end
		for _, id in ids do
			local model = Builder.build(id, "Viewport")
			check(id, Blueprints[id], model, onFaceKitV2(id))
			model:Destroy()
		end
		local blueprint = fixture()
		local model = buildFixture(blueprint)
		check("fixture", blueprint, model, true)
		model:Destroy()
		failIfAny(problems)
	end)

	t.test("every section has parts, and its pivot sits inside a body part and inside its first part", function()
		local problems: { string } = {}
		local function check(where: string, blueprint: any, model: Model)
			local sections = blueprint.sections
			if sections == nil then
				return
			end
			local scale = model:GetAttribute("SD_Scale") :: number
			local bodies = bodyParts(model)
			for name, section in sections do
				local first: any = nil
				for _, spec in blueprint.parts do
					if spec.section == name then
						first = spec
						break
					end
				end
				if first == nil then
					table.insert(problems, `{where}: section {name} has no parts`)
					continue
				end
				local pivot = section.pivot * scale
				local function inAny(parts: { BasePart }): boolean
					for _, part in parts do
						if contains(part, pivot) then
							return true
						end
					end
					return false
				end
				if not inAny(bodies) then
					table.insert(problems, `{where}: section {name} pivot {section.pivot} is not inside a body part`)
				end
				if not inAny(builtOf(model, first)) then
					table.insert(problems, `{where}: section {name} pivot is not inside its first part {first.name}`)
				end
			end
		end
		for _, id in ids do
			local model = Builder.build(id, "Viewport")
			check(id, Blueprints[id], model)
			model:Destroy()
		end
		local blueprint = fixture()
		local model = buildFixture(blueprint, "Viewport", 2)
		check("fixture", blueprint, model)
		model:Destroy()
		failIfAny(problems)
	end)

	t.test("SD_HalfExtents is half the body bounds at build scale", function()
		local problems: { string } = {}
		for _, id in ids do
			for _, scale in { 1, 2.5 } do
				local model = Builder.build(id, "World", scale)
				local expected = measureSize(model, bodyParts(model)) / 2
				local got = model:GetAttribute("SD_HalfExtents")
				if typeof(got) ~= "Vector3" or not near(got :: Vector3, expected, 1e-3 * scale) then
					table.insert(problems, `{id} x{scale}: SD_HalfExtents {got} (measured {expected})`)
				end
				model:Destroy()
			end
		end
		failIfAny(problems)
	end)

	t.test("scale is baked into every size and position", function()
		local problems: { string } = {}
		for _, id in ids do
			local base = Builder.build(id, "Viewport", nil, { roundedBox = false })
			local scaled = Builder.build(id, "Viewport", 2.5, { roundedBox = false })
			for _, part in visualParts(base) do
				local other = scaled:FindFirstChild(part.Name)
				if other == nil or not other:IsA("BasePart") then
					table.insert(problems, `{id}/{part.Name} missing at scale 2.5`)
					continue
				end
				local ok = near(other.CFrame.Position, part.CFrame.Position * 2.5, EPS)
					and near(renderedSize(other), renderedSize(part) * 2.5, EPS)
					and near(other.CFrame.LookVector, part.CFrame.LookVector, EPS)
					and near(other.CFrame.UpVector, part.CFrame.UpVector, EPS)
				if not ok then
					table.insert(problems, `{id}/{part.Name} not scaled by 2.5`)
				end
			end
			base:Destroy()
			scaled:Destroy()
		end
		failIfAny(problems)
	end)

	t.test("the blueprint's own scale applies to every build (each part's size = spec size x scale)", function()
		local problems: { string } = {}
		for _, id in ids do
			local blueprint = Blueprints[id]
			for _, factor in { 1, 2 } do
				local model = Builder.build(id, "World", factor, { roundedBox = false })
				for _, spec in blueprint.parts do
					if spec.size == nil then
						continue
					end
					local part = model:FindFirstChild(spec.name) :: BasePart
					local expected = spec.size * blueprint.scale * factor
					if not near(renderedSize(part), expected, EPS * factor) then
						table.insert(problems, `{id}/{spec.name} x{factor}: {renderedSize(part)} (expected {expected})`)
					end
				end
				model:Destroy()
			end
		end
		failIfAny(problems)
	end)

	t.test("frontalRadius matches the built body silhouette; flightScale = radius / frontalRadius", function()
		local problems: { string } = {}
		for _, id in ids do
			local model = Builder.build(id, "World")
			local measured = measureFrontalRadius(model)
			model:Destroy()
			local radius = Builder.frontalRadius(id)
			if math.abs(radius - measured) > FRONTAL_RADIUS_TOLERANCE * measured then
				table.insert(problems, `{id}: frontalRadius {radius} vs measured {measured}`)
			end
			expect.near(Builder.flightScale(id, 1.3), 1.3 / radius, 1e-9)
		end
		failIfAny(problems)
	end)

	-- Rounded boxes (§8.1 #2) ------------------------------------------------------------------------------------------

	-- The first RB part of the sorted blueprints (Butter's Body today), so a redesign never breaks these two cases.
	local function firstRB(): (string, any)
		for _, id in ids do
			for _, spec in Blueprints[id].parts do
				if spec.shape == "RB" then
					return id, spec
				end
			end
		end
		error("no blueprint has an RB part")
	end

	t.test("RB fallback: a Block Part with a Brick mesh of the RB size", function()
		local id, spec = firstRB()
		local scale = Blueprints[id].scale
		local model = Builder.build(id, "Viewport", nil, { roundedBox = false })
		local part = model:FindFirstChild(spec.name) :: BasePart
		local mesh = meshOf(part)
		expect.truthy(mesh ~= nil and mesh.MeshType == Enum.MeshType.Brick)
		expect.equal(part:GetAttribute("SD_Shape"), "B")
		expect.truthy(near(renderedSize(part), spec.size * scale, EPS))
		model:Destroy()
	end)

	t.test("RB from the library: a clean clone, sized, pivot-centred and unrotated, without a mesh", function()
		local id, spec = firstRB()
		local scale = Blueprints[id].scale
		local template = fakeRoundedBox()
		local model = Builder.build(id, "World", 2, { roundedBox = template })
		local part = model:FindFirstChild(spec.name) :: BasePart
		expect.equal(meshOf(part), nil)
		expect.equal(part:GetAttribute("SD_Shape"), "RB")
		expect.equal(part:GetAttribute("Junk"), nil)
		expect.falsy(part:HasTag("SD_TestJunk"))
		expect.equal(part:FindFirstChildOfClass("Folder"), nil)
		expect.truthy(near(part.Size, spec.size * scale * 2, EPS))
		expect.truthy(near(part.CFrame.Position, Vector3.zero, EPS))
		expect.truthy(
			near(part.CFrame.LookVector, -Vector3.zAxis, EPS) and near(part.CFrame.UpVector, Vector3.yAxis, EPS)
		)
		expect.equal(part.Color, Color3.fromHex(spec.color))
		expect.truthy(part.Massless and not part.CanCollide and not part.CanQuery and not part.CanTouch)
		expect.equal(template:GetAttribute("Junk"), 1) -- the template itself is untouched
		model:Destroy()
		template:Destroy()
	end)

	-- Kit ---------------------------------------------------------------------------------------------------------------

	t.test("Kit.pair mirrors x, ry, rz, attach offsets, the contact's x and L names; rx stays", function()
		local left, right = table.unpack(Kit.pair({
			name = "WingL",
			shape = "E",
			color = "FFFFFF",
			size = v(0.2, 0.3, 0.4),
			pos = v(-0.5, 0.1, 0.2),
			rot = v(10, 20, 30),
			section = "WingL",
			contact = v(0.5, -1, 0.25),
			contactWith = "BodyL",
		}))
		expect.equal(left.name, "WingL")
		expect.equal(right.name, "WingR")
		expect.equal(right.pos, v(0.5, 0.1, 0.2))
		expect.equal(right.rot, v(10, -20, -30))
		expect.equal(right.section, "WingR")
		expect.equal(right.contact, v(-0.5, -1, 0.25))
		expect.equal(right.contactWith, "BodyR")
		local _, spotR = table.unpack(Kit.pair({
			name = "SpotL",
			shape = "E",
			color = "FFFFFF",
			size = v(0.1, 0.1, 0.1),
			face = F(-0.2, 0.1, 0.6, "back"),
			section = "Tail",
		}))
		expect.equal(spotR.face.x, 0.2)
		expect.equal(spotR.face.side, "back")
		expect.equal(spotR.section, "Tail") -- a shared section keeps its name
	end)

	t.test("Kit.pairSection mirrors the pivot's x and flips the sign for Y and Z axes only", function()
		local x = Kit.pairSection("EarL", { pivot = v(-0.3, 0.5, 0.1), axis = "X", amp = 0.9 })
		expect.equal(x.EarR.pivot, v(0.3, 0.5, 0.1))
		expect.equal(x.EarR.sign, nil) -- X keeps the default 1
		expect.equal(x.EarR.amp, 0.9)
		local y = Kit.pairSection("WingL", { pivot = v(-0.2, 0, 0), axis = "Y", amp = 1.4, sign = -1 })
		expect.equal(y.WingR.sign, 1)
		local z = Kit.pairSection("GillL", { pivot = v(-0.2, 0, 0), axis = "Z", amp = 1.4, flap = { deg = 20 } })
		expect.equal(z.GillR.sign, -1)
		expect.equal(z.GillR.flap.deg, 20)
		local merged = Kit.mergeSections(x, y, { Tail = { pivot = v(0, 0, 0.5), axis = "Y", amp = 0.8 } })
		expect.truthy(merged.EarL and merged.EarR and merged.WingL and merged.WingR and merged.Tail)
		expect.throws(function()
			Kit.mergeSections(x, x)
		end, "listed twice")
	end)

	t.test(
		"face kit v2: shines at the viewer's upper left in front, chevrons point to the centre, mouths tilt",
		function()
			local model = buildFixture(fixture())
			local function part(name: string): BasePart
				return model:FindFirstChild(name) :: BasePart
			end
			for _, side in { "L", "R" } do
				-- The viewer looks along +Z, so the viewer's left is +X; "in front" is toward -Z.
				local eye, shine = part("Eye" .. side), part("Shine" .. side)
				local offset = eye.CFrame:PointToObjectSpace(shine.CFrame.Position)
				expect.truthy(offset.X > 0 and offset.Y > 0 and offset.Z <= -0.01)
				expect.equal(shine:GetAttribute("SD_AttachedTo"), "Eye" .. side)
			end
			-- "> <": on the left eye (x < 0) the upper stroke's top leans outward (-X), so the point faces +X.
			expect.truthy(part("SquishEyeUpL").CFrame.UpVector.X < 0 and part("SquishEyeDownL").CFrame.UpVector.X > 0)
			expect.truthy(part("SquishEyeUpR").CFrame.UpVector.X > 0 and part("SquishEyeDownR").CFrame.UpVector.X < 0)
			-- The tongue sits in front of the open mouth, attached to it.
			local mouth, tongue = part("SquishMouth"), part("SquishTongue")
			expect.truthy(mouth.CFrame:PointToObjectSpace(tongue.CFrame.Position).Z <= -0.01)
			-- Cat mouth "ω": the inner ends lift (MouthL's +X end is higher).
			expect.truthy(part("MouthL").CFrame.RightVector.Y > 0 and part("MouthR").CFrame.RightVector.Y < 0)
			model:Destroy()
			-- Smile "‿": the outer ends lift; the squish set without a tongue is 5 parts, without a mouth 4.
			local smile = Kit.smileStrokes(-0.1, 0.2)
			expect.equal(#smile, 2)
			expect.truthy(smile[1].rot.Z < 0 and smile[2].rot.Z > 0)
			expect.equal(#Kit.squishFace(-0.25, 0.1, 0.08, { y = -0.1, w = 0.2, tongue = false }), 5)
			expect.equal(#Kit.squishFace(-0.25, 0.1, 0.08), 4)
			local arcs = Kit.happyEyes(-0.25, 0.1, 0.08)
			expect.equal(#arcs, 4)
			for _, spec in arcs do
				expect.equal(spec.look, "eyeArc")
			end
		end
	)

	t.test("Kit.extremes: rest, every Config phase scaled to the toy, the overshoot and the jiggle caps", function()
		local Config = t.requireShared("Config")
		local phases = Config.Anim.squeeze.phases
		local deepest = math.huge
		for _, phase in phases do
			deepest = math.min(deepest, phase.c)
		end
		-- Birdie's §4 row: depth 0.60, widen 0.70, kRel 54, cRel 8 -> overshoot 5.2%.
		local motion = { squeeze = { depth = 0.6, widen = 0.7, kRel = 54, cRel = 8 }, feel = "plush", flight = {} }
		local list = Kit.extremes(motion, "Y")
		local byLabel: { [string]: Vector3 } = {}
		for _, extreme in list do
			byLabel[extreme.label] = extreme.S
		end
		expect.equal(list[1].label, "rest")
		expect.equal(list[1].S, Vector3.one)
		expect.equal(#list, #phases + 4)
		for _, phase in phases do
			local c = 1 - (1 - phase.c) * 0.4 / (1 - deepest)
			local S = byLabel[phase.name]
			expect.near(S.Y, c, 1e-6)
			expect.near(S.X, 1 + (1 - c) * 0.7, 1e-6)
			expect.near(S.Z, S.X, 1e-9)
		end
		local press = byLabel.widening -- the deepest phase reaches the toy's depth and its widen peak
		expect.near(press.Y, 0.6, 1e-6)
		expect.near(press.X, 1.28, 1e-6)
		expect.near(byLabel.overshoot.Y, 1.052, 0.001)
		expect.near(byLabel.jiggleSquash.Y, 1 - Kit.JIGGLE_CAP, 1e-6) -- Vector3 holds float32
		expect.near(byLabel.jiggleStretch.X, 1 - Kit.JIGGLE_CAP / 2, 1e-6)
		-- The squeeze axis carries c; the result is clamped like the deformer's.
		local onZ = Kit.extremes(motion, "Z")
		for i, extreme in onZ do
			expect.near(extreme.S.Z, list[i].S.Y, 1e-9)
			expect.near(extreme.S.Y, list[i].S.X, 1e-9)
		end
		local deep = { squeeze = { depth = 0.2, widen = 2, kRel = 40, cRel = 8 }, feel = "foam", flight = {} }
		for _, extreme in Kit.extremes(deep, "X") do
			local S = extreme.S
			for _, value in { S.X, S.Y, S.Z } do
				local lo, hi = Config.Anim.deform.scaleMin, Config.Anim.deform.scaleMax
				expect.truthy(value >= lo - 1e-6 and value <= hi + 1e-6) -- float32 1.6 is a hair above 1.6
			end
		end
	end)

	-- Fixtures and bad input ------------------------------------------------------------------------------------------

	t.test("options.blueprint builds a fixture under its own id without touching the blueprint map", function()
		local model = buildFixture(fixture(), "Held", 2)
		expect.equal(model.Name, "fixture")
		expect.equal(model:GetAttribute("SD_BlueprintId"), "fixture")
		expect.equal(model:GetAttribute("SD_Scale"), 2)
		expect.truthy(model:FindFirstChild("EarR") ~= nil and model:FindFirstChild("SquishMouth") ~= nil)
		model:Destroy()
		expect.equal(Blueprints.fixture, nil)
		-- A fixture is never cached under its id: a second, different fixture builds its own parts.
		local other = fixture()
		other.parts = { { name = "Lone", shape = "B", size = v(1, 1, 1), color = "FFFFFF", body = true } }
		other.sections = nil
		local lone = buildFixture(other)
		expect.equal(#visualParts(lone), 1)
		lone:Destroy()
	end)

	t.test("rejects unknown blueprints, modes, scales and throw radii", function()
		expect.throws(function()
			Builder.build("not_a_blueprint", "Viewport")
		end, "unknown blueprint")
		expect.throws(function()
			Builder.build("toast", "Inventory")
		end, "unknown build mode")
		for _, scale in { 0, -1, 0 / 0, math.huge } do
			expect.throws(function()
				Builder.build("toast", "Viewport", scale)
			end, "scale")
		end
		expect.throws(function()
			Builder.frontalRadius("not_a_blueprint")
		end, "unknown blueprint")
		expect.throws(function()
			Builder.flightScale("toast", 0)
		end, "throwRadius")
	end)

	t.test("rejects broken looks, sides, sections and contacts with the part's name", function()
		local function broken(edit: (blueprint: any) -> (), message: string)
			local blueprint = fixture()
			edit(blueprint)
			expect.throws(function()
				buildFixture(blueprint)
			end, message)
		end
		local function partNamed(blueprint: any, name: string): any
			for _, spec in blueprint.parts do
				if spec.name == name then
					return spec
				end
			end
			error(`fixture has no {name}`)
		end
		broken(function(b)
			partNamed(b, "EyeL").look = "pupil"
		end, "fixture.EyeL: unknown look pupil")
		broken(function(b)
			partNamed(b, "Spot").face.side = "top"
		end, "fixture.Spot: face side")
		broken(function(b)
			partNamed(b, "EarL").section = "Tail"
		end, "fixture.EarL: unknown section Tail")
		broken(function(b)
			partNamed(b, "EarL").contact = v(0, -1.5, 0)
		end, "fixture.EarL: contact")
		broken(function(b)
			partNamed(b, "EarL").contactWith = "Nose"
		end, "fixture.EarL: contactWith Nose")
		broken(function(b)
			b.sections.EarL.axis = "W"
		end, "fixture.EarL: section axis")
		broken(function(b)
			b.sections.EarL.amp = 0
		end, "fixture.EarL: section amp")
		broken(function(b)
			b.sections.Tail = { pivot = v(0, 0, 0.5), axis = "Y", amp = 1 }
		end, "fixture.Tail: section has no parts")
	end)
end
