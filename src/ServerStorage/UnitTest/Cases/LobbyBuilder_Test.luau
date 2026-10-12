--!strict
-- LobbyBuilder_Test: the contract of the lobby generator ServerStorage.SDTools.Builders.LobbyBuilder (version 2: the
-- Claude Design hub, sd/lobby.js; user decision 2026-10-11, phase 3 spec D1-D14). Server only (ServerStorage.UnitTest).
-- Builders_Test already checks the generic part (ok, unparented, marked, passes Verify); these cases pin what the
-- runtime and the binders rely on, restated from the design and the game's contracts instead of read from the builder:
--   * every ProximityPrompt starts DISABLED and carries SD_TextKey (6 stands + 14 collection pedestals);
--   * static sign lines are TextLabels tagged SD_Sign with SD_TextKey; live lines have neither; ≤ 64 SurfaceGuis (D6);
--   * the spawn (an invisible SpawnLocation in the medallion, top 0.7), the 9 squeeze stations and their tiers, the
--     practice targets (on the design lanes, inert, a "Body" with a mesh), the throw box, the backstop, return points
--     and boundaries;
--   * the giant pads (D5): Atomic, one Collision station box at the design's standing surface, a Body of tiles inside
--     the rounded footprint that never collides, no Face; the gates open and invisible; one lock + rope decor model
--     per pad (SD_GripLock);
--   * Neon only on the state rings lit in the design's default states (D7);
--   * 7 SD_Ambient models with their SD_AmbientKind (4 corner lollipops spin, the daily gift spins and bobs, the mystery
--     box and the statue breathe), none of their parts collides, is queried or touched;
--   * the design's own parts where lobby.js puts them (spot checks), the odds board beside the box stand, one Status
--     label in the daily stand, 14 pedestals with RarityStyle bands (D9), a 13-stud Kitty Bread statue.
-- The lobby is built once, in memory, from the Shared folder under test; nothing is parented into the place.

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
}

-- Restated numbers.
local TAG_COUNTS: { [string]: number } = {
	SD_LobbySpawn = 1,
	SD_SqueezeStation = 9,
	SD_PracticeZone = 1,
	SD_PracticeTarget = 9,
	SD_QueuePodium = 1,
	SD_QueueBoard = 1,
	SD_BoxStand = 1,
	SD_ShopCounter = 1,
	SD_CollectionKiosk = 1,
	SD_CollectionPedestal = 14, -- D4: all 14 squishies (lobby.js:91, 278)
	SD_QuestBoard = 1,
	SD_DailyStand = 1,
	SD_ReturnPoint = 2,
	SD_GripGate = 3,
	SD_GripSign = 3,
	SD_GripLock = 3, -- D5: the design's lock + rope per pad (lobby.js:372-373, 394)
	SD_GiantPad = 3,
	SD_Boundary = 4,
	SD_AudioZone = 3,
	SD_Ambient = 7, -- §18.5.1 A8 / D12: 4 lollipops, both gift boxes, the statue
}
local AMBIENT_KINDS: { [string]: string } = {
	["Decor/Lollipop1"] = "spin",
	["Decor/Lollipop2"] = "spin",
	["Decor/Lollipop3"] = "spin",
	["Decor/Lollipop4"] = "spin",
	["DailyStand/GiftBox"] = "spinBob",
	["GiftBoxCounter/GiftBox"] = "breathe",
	["SqueezeZone/Statue"] = "breathe",
}
local STATION_TIERS: { [string]: number } = { -- §17.4
	squeeze_01 = 1,
	squeeze_02 = 1,
	squeeze_03 = 1,
	squeeze_04 = 1,
	squeeze_05 = 1,
	squeeze_06 = 1,
	squeeze_07 = 2,
	squeeze_08 = 3,
	squeeze_09 = 4,
}
type PadSpec = { tier: number, station: string, center: Vector3, collisionTop: number, restTop: number }
local GIANT_PADS: { [string]: PadSpec } = { -- D5 (design centres lobby.js:359, 363, 383; tops 361, 364, 384)
	jelly = {
		tier = 2,
		station = "squeeze_07",
		center = Vector3.new(8.9955, 0, 70.3142),
		collisionTop = 5.7,
		restTop = 6.2,
	},
	marshmallow = {
		tier = 3,
		station = "squeeze_08",
		center = Vector3.new(-12.9955, 0, 69.6858),
		collisionTop = 6.0,
		restTop = 6.6,
	},
	royal = { tier = 4, station = "squeeze_09", center = Vector3.new(46, 0, 58), collisionTop = 4.1, restTop = 4.8 },
}
-- The practice range floor (lobby.js:402: X 73..115, Z 43..81): §7.7 rule 4 keeps squishy colours off it.
local RANGE_MIN, RANGE_MAX = Vector3.new(73, 0, 43), Vector3.new(115, 0, 81)
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
local STAND_TAGS =
	{ "SD_QueuePodium", "SD_BoxStand", "SD_ShopCounter", "SD_CollectionKiosk", "SD_QuestBoard", "SD_DailyStand" }
-- D7: the only Neon is a state ring lit in the design's default state (box Available, shop Purchasable, daily Ready).
local LIT_RINGS: { [string]: boolean } = { reveal_ring = true, turntable_ring = true, daily_ring = true }
local MAX_SURFACE_GUIS = 64 -- D6
local MAX_PARTS = 2500 -- §7.7
local TOLERANCE = 1e-3 -- CFrames are stored in single precision
local DESIGN_TOLERANCE = 0.02 -- design points restated with two decimals

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local function loadBuilder(): (any, Instance)
	local source = ServerStorage:FindFirstChild("SDTools")
	if source == nil then
		error("ServerStorage.SDTools not found (is Rojo connected?)")
	end
	local clone = source:Clone()
	local builders = clone:FindFirstChild("Builders")
	local module = if builders then builders:FindFirstChild("LobbyBuilder") else nil
	if module == nil or not module:IsA("ModuleScript") then
		clone:Destroy()
		error("SDTools.Builders.LobbyBuilder is missing")
	end
	return dynamicRequire(module), clone
end

local function everything(root: Instance): { Instance }
	local list = root:GetDescendants()
	table.insert(list, 1, root)
	return list
end

local function tagged(root: Instance, tag: string): { Instance }
	local list = {}
	for _, instance in everything(root) do
		if instance:HasTag(tag) then
			table.insert(list, instance)
		end
	end
	return list
end

local function named(root: Instance, name: string): { BasePart }
	local list = {}
	for _, instance in root:GetDescendants() do
		if instance.Name == name and instance:IsA("BasePart") then
			table.insert(list, instance)
		end
	end
	return list
end

local function topY(part: BasePart): number
	local cf, half = part.CFrame, part.Size / 2
	return cf.Position.Y
		+ math.abs(cf.XVector.Y) * half.X
		+ math.abs(cf.YVector.Y) * half.Y
		+ math.abs(cf.ZVector.Y) * half.Z
end

-- World bounds of the visible parts under `root` (lowest Y, highest Y, horizontal extent).
local function extent(root: Instance): (Vector3, Vector3)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local cf, half = part.CFrame, part.Size / 2
			local e = Vector3.new(
				math.abs(cf.XVector.X) * half.X + math.abs(cf.YVector.X) * half.Y + math.abs(cf.ZVector.X) * half.Z,
				math.abs(cf.XVector.Y) * half.X + math.abs(cf.YVector.Y) * half.Y + math.abs(cf.ZVector.Y) * half.Z,
				math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
			)
			low = low:Min(cf.Position - e)
			high = high:Max(cf.Position + e)
		end
	end
	return low, high
end

-- The design frame of a station (lobby.js:112, 119-130) and a station-local design point in the world.
local FRAMES: { [string]: { number } } = {
	duel = { 0, -66 },
	box = { -58, -46 },
	shop = { 58, -46 },
	quests = { 84, -14 },
	daily = { 84, 20 },
	squeeze = { -58, 52 },
	royal = { 46, 58 },
}
local function design(id: string, x: number, y: number, z: number): Vector3
	local spec = FRAMES[id]
	local frame = CFrame.new(spec[1], 0, spec[2]) * CFrame.Angles(0, math.atan2(-spec[1], -spec[2]), 0)
	return frame * Vector3.new(x, y, z)
end

return function(t: Context)
	local LobbyBuilder, toolsClone = loadBuilder()
	local Cleanup = t.requireShared("Util/Cleanup")
	local Strings = t.requireShared("Strings")
	local Catalog = t.requireShared("Catalog")
	local RarityStyle = t.requireShared("Art/RarityStyle")
	local expect = t.expect

	-- One build shared by every case (about 1,700 parts, all in memory).
	local scratch = Cleanup.new()
	local shared = t.Shared
	local okBuild, built = pcall(function()
		if shared == nil then
			error("no Shared folder under test")
		end
		return LobbyBuilder.build({ scratch = scratch, Shared = shared })
	end)
	local function lobby(): Instance
		if not okBuild then
			error("LobbyBuilder.build threw: " .. tostring(built))
		end
		if not built.ok then
			error("LobbyBuilder.build failed: " .. tostring(built.error))
		end
		return built.root
	end
	local function station(name: string): Instance
		local model = lobby():FindFirstChild(name)
		if model == nil then
			error("no station model " .. name)
		end
		return model
	end

	t.test("the root is SD_Lobby, unparented, not Atomic, version 2", function()
		local root = lobby()
		expect.equal(root.Name, "SD_Lobby")
		expect.equal(root.Parent, nil)
		expect.equal((root :: Model).ModelStreamingMode, Enum.ModelStreamingMode.Default)
		expect.equal(LobbyBuilder.VERSION, 2)
		expect.equal(root:GetAttribute("SD_GeneratorVersion"), 2)
	end)

	t.test("exact tag counts", function()
		local root = lobby()
		for tag, count in TAG_COUNTS do
			local found = #tagged(root, tag)
			if found ~= count then
				error(string.format("%s: %d tagged, expected %d", tag, found, count))
			end
		end
	end)

	t.test("9 squeeze stations, unique ids, GripTier from §17.4", function()
		local seen: { [string]: boolean } = {}
		for _, item in tagged(lobby(), "SD_SqueezeStation") do
			local id = item:GetAttribute("StationId")
			expect.truthy(type(id) == "string" and STATION_TIERS[id :: string] ~= nil)
			expect.falsy(seen[id :: string])
			seen[id :: string] = true
			expect.equal(item:GetAttribute("GripTier"), STATION_TIERS[id :: string])
			expect.truthy(item:IsA("BasePart"))
		end
	end)

	t.test("the foam mats: the design's puffy mats at the design ring, solid, top 2.05, coloured matColor", function()
		local WorldLayout = t.requireShared("World/WorldLayout")
		local Palette = t.requireShared("Art/Palette")
		local mats = 0
		for _, item in tagged(lobby(), "SD_SqueezeStation") do
			local part = item :: BasePart
			local id = part:GetAttribute("StationId") :: string
			if STATION_TIERS[id] ~= 1 then
				continue
			end
			mats += 1
			local spec = WorldLayout.station(id)
			expect.near((part.CFrame.Position - spec.position).Magnitude, 0, TOLERANCE)
			expect.near(topY(part), 2.05, TOLERANCE) -- lobby.js:338-344
			expect.equal(part.CanCollide, true)
			-- SqueezeController pulses this part's Color from Palette[matColor] (never read back).
			expect.equal(part.Color, Palette[WorldLayout.SqueezeZone.matColor])
		end
		expect.equal(mats, 6)
	end)

	t.test("every prompt starts disabled and carries a Strings key (§7.6)", function()
		local count = 0
		for _, instance in lobby():GetDescendants() do
			if instance:IsA("ProximityPrompt") then
				count += 1
				expect.equal(instance.Enabled, false)
				local key = instance:GetAttribute("SD_TextKey")
				expect.truthy(type(key) == "string")
				expect.equal(instance.ActionText, Strings.resolve(key :: string))
				expect.truthy((instance.Parent :: Instance):IsA("Attachment"))
			end
		end
		expect.equal(count, 20) -- podium, box, shop, kiosk, quest, daily + 14 pedestals
	end)

	t.test("each stand carries one prompt; pedestal prompts reach 12 studs without line of sight", function()
		local root = lobby()
		for _, tag in STAND_TAGS do
			local stand = tagged(root, tag)[1]
			local prompts = 0
			for _, d in stand:GetDescendants() do
				if d:IsA("ProximityPrompt") then
					prompts += 1
				end
			end
			if prompts ~= 1 then
				error(string.format("%s has %d prompts", tag, prompts))
			end
		end
		for _, pedestal in tagged(root, "SD_CollectionPedestal") do
			local prompt = pedestal:FindFirstChildWhichIsA("ProximityPrompt", true) :: ProximityPrompt
			expect.equal(prompt.MaxActivationDistance, 12)
			expect.equal(prompt.RequiresLineOfSight, false)
		end
	end)

	t.test("the spawn: an invisible SpawnLocation in the medallion, Neutral, Duration 0, top 0.7, facing -Z", function()
		local spawn = tagged(lobby(), "SD_LobbySpawn")[1] :: SpawnLocation
		expect.equal(spawn.ClassName, "SpawnLocation")
		expect.equal(spawn.Neutral, true)
		expect.equal(spawn.Duration, 0)
		expect.equal(spawn.Transparency, 1) -- the design's medallion is the spawn (lobby.js:147)
		expect.near(topY(spawn), 0.7, TOLERANCE)
		expect.near(spawn.CFrame.LookVector.Z, -1, TOLERANCE)
		local medallion = named(station("Spawn"), "spawn_medallion")[1]
		expect.truthy(medallion)
		expect.near(topY(medallion), 0.7, TOLERANCE) -- C(14, 14.5, 0.7) at Y 0.35
		expect.near(medallion.Size.Y, 29, TOLERANCE) -- an upright cylinder: diameter on Y and Z
	end)

	t.test("sign labels: static lines tagged with a key, live lines never keyed; ≤ 64 SurfaceGuis (D6)", function()
		local guis = 0
		for _, instance in lobby():GetDescendants() do
			if instance:IsA("SurfaceGui") then
				guis += 1
			elseif instance:HasTag("SD_Sign") then
				expect.truthy(instance:IsA("TextLabel"))
				local key = instance:GetAttribute("SD_TextKey")
				expect.truthy(type(key) == "string")
				expect.equal((instance :: TextLabel).Text, Strings.resolve(key :: string))
			elseif instance:IsA("TextLabel") then
				expect.equal(instance:GetAttribute("SD_TextKey"), nil)
			end
		end
		expect.truthy(guis >= 40 and guis <= MAX_SURFACE_GUIS)
	end)

	t.test("the spawn logo: a Top SurfaceGui reading north with the design's two keyed lines", function()
		local spawn = station("Spawn")
		local keys: { [string]: boolean } = {}
		local gui: SurfaceGui? = nil
		for _, d in spawn:GetDescendants() do
			if d:IsA("TextLabel") and d:HasTag("SD_Sign") then
				local key = d:GetAttribute("SD_TextKey") :: string
				keys[key] = true
				if key == "world.logoTop" or key == "world.logoBottom" then
					gui = d:FindFirstAncestorWhichIsA("SurfaceGui")
				end
			end
		end
		expect.truthy(keys["world.logoTop"] and keys["world.logoBottom"])
		local logoGui = gui :: SurfaceGui
		expect.equal(logoGui.Face, Enum.NormalId.Top)
		local host = logoGui.Parent :: BasePart
		expect.near((-host.CFrame.RightVector - Vector3.new(0, 0, -1)).Magnitude, 0, TOLERANCE)
	end)

	t.test("pod signs: one Live label without a key, a keyed grip.pad Title, near their pad", function()
		for _, sign in tagged(lobby(), "SD_GripSign") do
			local live, titles = 0, 0
			for _, d in sign:GetDescendants() do
				if d:IsA("TextLabel") and d.Name == "Live" then
					live += 1
					expect.equal(d:GetAttribute("SD_TextKey"), nil)
					expect.falsy(d:HasTag("SD_Sign"))
					expect.truthy(string.find(d.Text, "{", 1, true) == nil)
				elseif d:IsA("TextLabel") and d.Name == "Title" then
					titles += 1
					local key = d:GetAttribute("SD_TextKey")
					expect.truthy(type(key) == "string" and string.sub(key :: string, 1, 9) == "grip.pad.")
				end
			end
			expect.equal(live, 1)
			expect.equal(titles, 1)
			local tier = sign:GetAttribute("GripTier")
			expect.truthy(type(tier) == "number")
			for _, spec in GIANT_PADS do
				if spec.tier == tier then
					local p = (sign :: BasePart).CFrame.Position
					expect.truthy(Vector3.new(p.X - spec.center.X, 0, p.Z - spec.center.Z).Magnitude <= 12)
				end
			end
		end
	end)

	t.test("giant pads: Atomic, one Collision at the design's standing surface, an inert Body, no Face (D5)", function()
		local root = lobby()
		for _, model in tagged(root, "SD_GiantPad") do
			local key = model:GetAttribute("PadKey")
			local spec = GIANT_PADS[key :: string]
			expect.truthy(spec ~= nil and model:IsA("Model"))
			expect.equal(model.Name, "GiantPad_" .. (key :: string))
			expect.equal((model :: Model).ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
			expect.equal(model:GetAttribute("GripTier"), spec.tier)
			local collisions = {}
			for _, child in model:GetChildren() do
				if child.Name == "Collision" then
					table.insert(collisions, child)
				end
			end
			expect.equal(#collisions, 1)
			local box = collisions[1] :: BasePart
			expect.truthy(box:HasTag("SD_SqueezeStation"))
			expect.equal(box:GetAttribute("StationId"), spec.station)
			expect.equal(box.Transparency, 1)
			expect.equal(box.CanCollide, true)
			expect.equal(box.CanTouch, false)
			expect.near(topY(box), spec.collisionTop, 0.01)
			expect.near(box.CFrame.Position.X, spec.center.X, DESIGN_TOLERANCE)
			expect.near(box.CFrame.Position.Z, spec.center.Z, DESIGN_TOLERANCE)
			expect.equal(model:FindFirstChild("Face"), nil) -- the design pads have no faces
			local body = model:FindFirstChild("Body") :: Model
			expect.truthy(body and body:IsA("Model"))
			local tiles, bodyTop = 0, -math.huge
			for _, part in body:GetDescendants() do
				if part:IsA("BasePart") then
					expect.equal(part.CanCollide, false)
					expect.equal(part.CanQuery, false)
					expect.equal(part.CanTouch, false)
					bodyTop = math.max(bodyTop, topY(part))
					if string.sub(part.Name, 1, 5) == "Tile_" then
						tiles += 1
						local mesh = part:FindFirstChildOfClass("SpecialMesh")
						expect.truthy(mesh ~= nil and mesh.MeshType == Enum.MeshType.Sphere)
					end
				end
			end
			expect.truthy(tiles >= 40)
			expect.near(bodyTop, spec.restTop, 0.151) -- tile tops at restTop; accents ride at most 0.15 over it (float32)
			expect.truthy(bodyTop >= spec.collisionTop + 0.4)
		end
	end)

	t.test(
		"giant pad accents (SD_PadAccent): jelly shines, the toasted marshmallow top, royal tufts and piping",
		function()
			local accents: { [string]: number } = {}
			for _, model in tagged(lobby(), "SD_GiantPad") do
				local key = model:GetAttribute("PadKey") :: string
				local count = 0
				for _, part in (model:FindFirstChild("Body") :: Instance):GetDescendants() do
					if part:IsA("BasePart") and part:GetAttribute("SD_PadAccent") == true then
						count += 1
					end
				end
				accents[key] = count
			end
			expect.equal(accents.jelly, 2) -- lobby.js:362
			expect.equal(accents.marshmallow, 1) -- lobby.js:365 (toast top)
			expect.equal(accents.royal, 9) -- lobby.js:385-386 (4 piping + 5 tufts)
		end
	)

	t.test("jelly gates: open and invisible as built, one per pad tier, Ø14 (D5)", function()
		local tiers: { [number]: boolean } = {}
		for _, gate in tagged(lobby(), "SD_GripGate") do
			local part = gate :: BasePart
			expect.equal(part.CanCollide, false)
			expect.equal(part.CanQuery, false)
			expect.equal(part.CanTouch, false)
			expect.equal(part.Transparency, 1)
			local tier = part:GetAttribute("GripTier") :: number
			expect.truthy(tier >= 2 and tier <= 4 and not tiers[tier])
			tiers[tier] = true
			expect.near(part.Size.Y, 14, TOLERANCE) -- an upright cylinder: diameter on Y and Z
			expect.near(part.Size.X, 14, TOLERANCE) -- height
		end
	end)

	t.test("lock + rope decor: one SD_GripLock model per pad tier, inert, pivot on its pad, shown as built", function()
		local tiers: { [number]: boolean } = {}
		for _, lock in tagged(lobby(), "SD_GripLock") do
			expect.truthy(lock:IsA("Model"))
			local tier = lock:GetAttribute("GripTier") :: number
			expect.truthy(tier >= 2 and tier <= 4 and not tiers[tier])
			tiers[tier] = true
			local pivot = (lock :: Model).WorldPivot.Position -- no PrimaryPart: GetPivot() is WorldPivot
			local found = false
			for _, spec in GIANT_PADS do
				if spec.tier == tier then
					found = true
					expect.near(
						Vector3.new(pivot.X - spec.center.X, 0, pivot.Z - spec.center.Z).Magnitude,
						0,
						DESIGN_TOLERANCE
					)
				end
			end
			expect.truthy(found)
			local parts = 0
			for _, part in lock:GetDescendants() do
				if part:IsA("BasePart") then
					parts += 1
					expect.equal(part.CanCollide, false)
					expect.equal(part.CanQuery, false)
					expect.equal(part.CanTouch, false)
					expect.equal(part.Transparency, 0)
				end
			end
			expect.truthy(parts >= 10) -- a lock icon and a rope barrier
		end
	end)

	t.test(
		"practice: 9 targets on the design lanes with attributes, one moving, inert, each with a Body mesh",
		function()
			local moving = 0
			for _, target in tagged(lobby(), "SD_PracticeTarget") do
				for _, attribute in { "TargetId", "Distance", "Moving", "RailLength", "Period" } do
					expect.truthy(target:GetAttribute(attribute) ~= nil)
				end
				if target:GetAttribute("Moving") == true then
					moving += 1
					expect.equal(target:GetAttribute("Distance"), 20)
					expect.equal(target:GetAttribute("RailLength"), 12)
					expect.near(target:GetAttribute("Period") :: number, 9.42, TOLERANCE)
				end
				local pivot = (target :: Model).WorldPivot -- no PrimaryPart: GetPivot() is WorldPivot
				expect.truthy(table.find({ 52, 62, 72 }, math.round(pivot.Position.Z)) ~= nil)
				expect.near(pivot.Position.X, 79 + (target:GetAttribute("Distance") :: number), TOLERANCE)
				expect.near(pivot.Position.Y, 0.6, TOLERANCE) -- on the range floor (lobby.js:402)
				expect.near(pivot.LookVector.X, -1, TOLERANCE) -- facing the thrower (throws go +X, D3)
				for _, part in target:GetDescendants() do
					if part:IsA("BasePart") then
						expect.equal(part.CanCollide, false) -- hits are capsule maths on the server, never touches
					end
				end
				local body = target:FindFirstChild("Body", true)
				expect.truthy(body ~= nil and body:FindFirstChildWhichIsA("SpecialMesh") ~= nil)
			end
			expect.equal(moving, 1)
			local zone = tagged(lobby(), "SD_PracticeZone")[1] :: BasePart
			expect.near(zone.CFrame.Position.X, 75, TOLERANCE) -- X 71..79, Z 43..81, Y 0..12
			expect.near(zone.Size.X, 8, TOLERANCE)
			expect.near(zone.Size.Z, 38, TOLERANCE)
			expect.near(zone.Size.Y, 12, TOLERANCE)
			expect.equal(zone.CanCollide, false)
		end
	)

	t.test("practice: LaneFloor, FiringLine and Backstop are queryable parts directly under PracticeRange", function()
		local WorldLayout = t.requireShared("World/WorldLayout")
		local range = station("PracticeRange")
		for _, name in { "LaneFloor", "FiringLine", "Backstop" } do
			local part = range:FindFirstChild(name)
			expect.truthy(part ~= nil and part:IsA("BasePart"))
			expect.equal((part :: BasePart).CanQuery, true) -- PracticeService splats on them (Include raycasts)
		end
		-- The jelly ripple binds the Backstop only when its box equals WorldLayout's (JellySkin mismatch guard).
		local backstop = range:FindFirstChild("Backstop") :: BasePart
		local spec = WorldLayout.PracticeRange.backstop
		expect.near((backstop.CFrame.Position - spec.position).Magnitude, 0, TOLERANCE)
		expect.near((backstop.Size - spec.size).Magnitude, 0, TOLERANCE)
		expect.equal(#named(range, "backstop_pillow"), 18) -- lobby.js:412
	end)

	t.test("return points at (±6, 0, -42) facing +Z, Slots 1 and 2", function()
		local slots: { [number]: boolean } = {}
		for _, point in tagged(lobby(), "SD_ReturnPoint") do
			local part = point :: BasePart
			local slot = part:GetAttribute("Slot") :: number
			slots[slot] = true
			expect.near(math.abs(part.CFrame.Position.X), 6, TOLERANCE)
			expect.near(part.CFrame.Position.Z, -42, TOLERANCE)
			expect.near(part.CFrame.LookVector.Z, 1, TOLERANCE)
			expect.equal(part.CanCollide, false)
		end
		expect.truthy(slots[1] and slots[2])
	end)

	t.test("boundaries are invisible, collide, and are never queried (§7.7)", function()
		for _, wall in tagged(lobby(), "SD_Boundary") do
			local part = wall :: BasePart
			expect.equal(part.Transparency, 1)
			expect.equal(part.CanCollide, true)
			expect.equal(part.CanQuery, false)
			expect.equal(part.CanTouch, false)
		end
	end)

	t.test("collidable parts are anchored; Neon only on the lit state rings (D7); part budget", function()
		local parts, neon = 0, 0
		for _, instance in lobby():GetDescendants() do
			if instance:IsA("BasePart") then
				parts += 1
				if instance.CanCollide then
					expect.equal(instance.Anchored, true)
				end
				if instance.Material == Enum.Material.Neon then
					neon += 1
					if not LIT_RINGS[instance.Name] then
						error(`{instance:GetFullName()} is Neon`)
					end
				end
			end
		end
		expect.truthy(neon >= 3)
		expect.truthy(parts <= MAX_PARTS)
	end)

	t.test("SD_Ambient: 7 tagged models with their kind, the lollipops Atomic, every part inert", function()
		local root = lobby()
		local found: { [string]: string } = {}
		for _, instance in tagged(root, "SD_Ambient") do
			expect.truthy(instance:IsA("Model"))
			local parent = instance.Parent :: Instance
			found[parent.Name .. "/" .. instance.Name] = instance:GetAttribute("SD_AmbientKind") :: string
			for _, part in everything(instance) do
				if part:IsA("BasePart") and (part.CanCollide or part.CanQuery or part.CanTouch) then
					error(`{part:GetFullName()} collides, is queried or touched`)
				end
			end
		end
		expect.deepEqual(found, AMBIENT_KINDS)
		local decor = root:FindFirstChild("Decor") :: Instance
		local corners = {
			Vector3.new(-104, 0, -80),
			Vector3.new(104, 0, -80),
			Vector3.new(-104, 0, 80),
			Vector3.new(104, 0, 80),
		} -- lobby.js:468
		for index = 1, 4 do
			local lollipop = decor:FindFirstChild("Lollipop" .. index) :: Model
			expect.equal(lollipop.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
			-- The client spins it about its pivot: the stick's foot on the floor.
			expect.near((lollipop.WorldPivot.Position - corners[index]).Magnitude, 0, TOLERANCE)
			local _, high = extent(lollipop)
			expect.near(high.Y, 24 + 7, 0.1) -- stick 24, disk radius 7 (lobby.js:468)
		end
	end)

	t.test("the corner lollipop on the practice range uses no squishy body colour (§7.7 rule 4)", function()
		local Blueprints = t.requireShared("Art/SquishyBlueprints")
		local bodyColours: { [string]: boolean } = {}
		for _, id in SQUISHY_IDS do
			for _, spec in Blueprints[id].parts do
				if spec.body then
					bodyColours[string.upper(spec.color)] = true
				end
			end
		end
		local decor = lobby():FindFirstChild("Decor") :: Instance
		local onRange = 0
		for _, model in decor:GetChildren() do
			if not (model:IsA("Model") and string.sub(model.Name, 1, 8) == "Lollipop") then
				continue
			end
			local base = (model :: Model).WorldPivot.Position
			if base.X < RANGE_MIN.X or base.X > RANGE_MAX.X or base.Z < RANGE_MIN.Z or base.Z > RANGE_MAX.Z then
				continue
			end
			onRange += 1
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and bodyColours[string.upper(part.Color:ToHex())] then
					error(`{part:GetFullName()} is {part.Color:ToHex()}, a squishy body colour`)
				end
			end
		end
		expect.equal(onRange, 1) -- the SE lollipop (104, 80) stands on the range floor's north-east corner
	end)

	t.test("the statue: a 13-stud Kitty Bread on the plinth with its ambient sparkle; emitter budget", function()
		local Config = t.requireShared("Config")
		local emitters = {}
		for _, d in lobby():GetDescendants() do
			if d:IsA("ParticleEmitter") then
				table.insert(emitters, d)
			end
		end
		expect.truthy(#emitters >= 1 and #emitters <= 3)
		local squeeze = station("SqueezeZone")
		local sparkle = squeeze:FindFirstChild("StatueSparkle", true)
		expect.truthy(sparkle ~= nil and sparkle:IsA("ParticleEmitter"))
		local emitter = sparkle :: ParticleEmitter
		expect.equal(emitter.Rate, Config.Vfx.Effects.statueSparkleRate)
		expect.equal(emitter.LightEmission, 0)
		local statue = squeeze:FindFirstChild("Statue") :: Model
		expect.truthy(statue)
		local low = extent(statue)
		expect.near(low.Y, 2.8, 0.05) -- on the plinth top (lobby.js:339, 351)
		-- toyAt (lobby.js:37): scaled so max(height, 0.8 × width) = 13, measured in the toy's own frame.
		local pivot = statue:GetPivot()
		local lowLocal, highLocal = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, part in statue:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				for _, sx in { -0.5, 0.5 } do
					for _, sy in { -0.5, 0.5 } do
						for _, sz in { -0.5, 0.5 } do
							local corner = pivot:PointToObjectSpace(part.CFrame * (part.Size * Vector3.new(sx, sy, sz)))
							lowLocal = lowLocal:Min(corner)
							highLocal = highLocal:Max(corner)
						end
					end
				end
			end
		end
		local size = highLocal - lowLocal
		expect.near(math.max(size.Y, 0.8 * size.X), 13, 0.05)
	end)

	t.test("the statue and both gift boxes are built", function()
		local squeeze = station("SqueezeZone")
		local box = station("GiftBoxCounter")
		local daily = station("DailyStand")
		expect.truthy(squeeze:FindFirstChild("Statue") ~= nil)
		expect.truthy(box:FindFirstChild("GiftBox") ~= nil)
		expect.truthy(daily:FindFirstChild("GiftBox") ~= nil)
	end)

	t.test("the odds board is a sibling of the box stand with a keyed Title and a live Body (BoxController)", function()
		local stand = tagged(lobby(), "SD_BoxStand")[1]
		local model = stand.Parent :: Instance
		local board = model:FindFirstChild("OddsBoard")
		expect.truthy(board ~= nil and board:IsA("BasePart"))
		local title = (board :: Instance):FindFirstChild("Title", true)
		local body = (board :: Instance):FindFirstChild("Body", true)
		expect.truthy(title ~= nil and title:IsA("TextLabel") and title:GetAttribute("SD_TextKey") == "box.oddsTitle")
		expect.truthy(body ~= nil and body:IsA("TextLabel") and body:GetAttribute("SD_TextKey") == nil)
		expect.equal(stand:GetAttribute("BoxId"), "snack")
	end)

	t.test("the daily stand holds exactly one Status label, built empty (DailyController)", function()
		local daily = station("DailyStand")
		local found = {}
		for _, d in daily:GetDescendants() do
			if d.Name == "Status" and d:IsA("TextLabel") then
				table.insert(found, d)
			end
		end
		expect.equal(#found, 1)
		expect.equal(found[1].Text, "")
		expect.equal(found[1]:GetAttribute("SD_TextKey"), nil)
	end)

	t.test(
		"14 pedestals: cylinders topped at the design shelf height, banded in their squishy's rarity colour (D9)",
		function()
			local WorldLayout = t.requireShared("World/WorldLayout")
			local defs = Catalog.list()
			for _, item in tagged(lobby(), "SD_CollectionPedestal") do
				local part = item :: Part
				local slot = part:GetAttribute("Slot") :: number
				local spec = WorldLayout.Collection.pedestals[slot]
				expect.equal(part.Shape, Enum.PartType.Cylinder)
				expect.near(topY(part), spec.position.Y + 0.35, TOLERANCE)
				local band = (part.Parent :: Instance):FindFirstChild(string.format("collection_rarity_rim_%02d", slot))
				expect.truthy(band ~= nil and band:IsA("BasePart"))
				local def = defs[slot]
				expect.equal((band :: BasePart).Color, RarityStyle.get(def.rarity).color)
			end
		end
	)

	t.test("the design's parts stand where lobby.js puts them (spot checks)", function()
		local root = lobby()
		local function at(model: string, name: string, point: Vector3)
			local parts = named(station(model), name)
			if #parts == 0 then
				error(`{model} has no {name}`)
			end
			local best = math.huge
			for _, part in parts do
				best = math.min(best, (part.CFrame.Position - point).Magnitude)
			end
			if best > DESIGN_TOLERANCE then
				error(`{model}/{name}: nearest is {best} studs from {point}`)
			end
		end
		at("DuelGate", "queue_stage", Vector3.new(0, 0.8, -66)) -- lobby.js:172
		at("DuelGate", "gate_lintel", Vector3.new(0, 24, -75)) -- lobby.js:182
		at("DuelGate", "gate_badge", Vector3.new(0, 24, -71.2)) -- lobby.js:183
		expect.equal(#named(station("DuelGate"), "queue_pad"), 10) -- lobby.js:190-192
		expect.equal(#named(station("DuelGate"), "slot_light"), 10) -- lobby.js:188
		at("GiftBoxCounter", "box_dais", design("box", 0, 0.7, 0)) -- lobby.js:209
		at("ShopCounter", "shop_backwall", design("shop", 0, 8.3, -6.5)) -- lobby.js:239
		expect.equal(#named(station("ShopCounter"), "awning_stripe"), 10) -- lobby.js:247
		at("QuestBoard", "quest_header", design("quests", 0, 17.4, -1.6)) -- lobby.js:295
		expect.equal(#named(station("QuestBoard"), "quest_card"), 9) -- lobby.js:300
		expect.equal(#named(station("DailyStand"), "calendar_tile"), 7) -- lobby.js:324
		at("SqueezeZone", "statue_plinth", design("squeeze", 0, 1.4, 0)) -- lobby.js:339
		expect.equal(#named(station("SqueezeZone"), "refill_meter"), 6) -- lobby.js:346
		at("RoyalPod", "canopy_finial", design("royal", 0, 23.4, 0)) -- lobby.js:391
		expect.equal(#named(station("RoyalPod"), "canopy_post"), 4) -- lobby.js:388
		local kit = root:FindFirstChild("Kit") :: Instance
		local walls = 0
		for _, part in kit:GetDescendants() do
			if part.Name == "kit_wall_module" then
				walls += 1
			end
		end
		expect.equal(walls, 54) -- 15 + 15 + 12 + 12 (lobby.js:427, 436)
		expect.equal(#named(kit, "kit_wall_pillar"), 58) -- lobby.js:434
		expect.equal(#named(kit, "kit_gumdrop_hedge"), 15) -- lobby.js:441-442
	end)

	t.test("the practice audio zone covers the throw box (§18.8)", function()
		local practice: BasePart? = nil
		for _, zone in tagged(lobby(), "SD_AudioZone") do
			if zone:GetAttribute("ZoneId") == "practice" then
				practice = zone :: BasePart
			end
		end
		expect.truthy(practice ~= nil)
		local part = practice :: BasePart
		local zone = tagged(lobby(), "SD_PracticeZone")[1] :: BasePart
		local half = part.Size / 2
		local offset = zone.CFrame.Position - part.CFrame.Position
		expect.truthy(math.abs(offset.X) + zone.Size.X / 2 <= half.X + TOLERANCE)
		expect.truthy(math.abs(offset.Z) + zone.Size.Z / 2 <= half.Z + TOLERANCE)
		expect.equal(part.CanCollide, false)
		expect.equal(part.CanQuery, false)
		expect.equal(part.CanTouch, false)
	end)

	t.test("no keep-clear warnings in the build report", function()
		local _ = lobby()
		for _, warning in built.warnings do
			if string.find(warning, "keep-clear", 1, true) then
				error(warning)
			end
		end
	end)

	t.test("two builds are identical (deterministic generator)", function()
		local root = lobby()
		local again = Cleanup.new()
		local second = LobbyBuilder.build({ scratch = again, Shared = shared })
		expect.truthy(second.ok)
		local function names(tree: Instance): { string }
			local list = {}
			for _, d in tree:GetDescendants() do
				table.insert(list, d:GetFullName())
			end
			table.sort(list)
			return list
		end
		local a, b = names(root), names(second.root)
		expect.equal(#a, #b)
		for i = 1, #a do
			if a[i] ~= b[i] then
				error(string.format("first difference: %s vs %s", a[i], b[i]))
			end
		end
		second.root:Destroy()
		again:clean()
	end)

	t.test("a Shared folder without WorldLayout fails cleanly (ok = false, nothing returned)", function()
		if shared == nil then
			error("no Shared folder under test")
		end
		local broken = (shared :: Instance):Clone()
		local world = broken:FindFirstChild("World")
		if world then
			world:Destroy()
		end
		local cleanup = Cleanup.new()
		local result = LobbyBuilder.build({ scratch = cleanup, Shared = broken })
		cleanup:clean()
		broken:Destroy()
		expect.equal(result.ok, false)
		expect.equal(result.root, nil)
		expect.truthy(type(result.error) == "string")
	end)

	t.test("teardown", function()
		if okBuild and built.ok then
			built.root:Destroy()
		end
		scratch:clean()
		toolsClone:Destroy()
	end)
end
