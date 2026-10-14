--!strict
-- LobbyBuilder_Test: the contract of the lobby generator ServerStorage.SDTools.Builders.LobbyBuilder (version 4: Squish
-- Island, lobby bases spec 2026-10-11 §2-§4, §7-§8, build plan Phase 4, without the giant pads since Phase 6, with the
-- Claude Design hub's stations,
-- sd/lobby.js, phase 3 spec D1-D14, in its hub sectors). Server only (ServerStorage.UnitTest).
-- Builders_Test already checks the generic part (ok, unparented, marked, passes Verify); these cases pin what the
-- runtime and the binders rely on, restated from the design and the game's contracts instead of read from the builder:
--   * every ProximityPrompt starts DISABLED and carries SD_TextKey (6 stands + 14 collection pedestals);
--   * static sign lines are TextLabels tagged SD_Sign with SD_TextKey; live lines have neither; ≤ 64 SurfaceGuis (D6);
--   * the hub spawn (an invisible SpawnLocation in the medallion on the stage, top 1.1), the 6 squeeze stations (tier
--     1), the 4 practice targets (on the island's lane, inert, a "Body" with a mesh), the throw box, the
--     backstop, return points and boundaries;
--   * the island (§2): the sea, the shallow water, the beach, the grass at Y -0.9, Squish Square at Y 0 with its curb
--     and 10 paths that stay clear (nothing collidable on them, 8 wide); the duel tower (§2, §7) over the stage;
--   * the 10 plots (§4): Base_01..10 tagged SD_Base with Plot, at their plot frames, built open (grey, "Open plot" on
--     the live Owner label), every tinted part marked SD_BaseTint, 4 capsule pads with Slot, one SpawnLocation each
--     (SD_BaseSpawn, flush with the plot floor, facing the gate), the gate's 16-stud gap open;
--   * the part budget per zone (§7) with every plot at its worst (CapsuleBuilder's templates);
--   * no giant pad, Jelly gate, pod sign, lock decor, Grip gym or Royal pod any more (build plan Phase 6);
--   * Neon only on the state rings lit in the design's default states (D7);
--   * 7 SD_Ambient models with their SD_AmbientKind (4 garden lollipops spin, the daily gift spins and bobs, the
--     mystery box and the statue breathe), none of their parts collides, is queried or touched;
--   * the stations' parts where the island puts them (spot checks), the odds board beside the box stand, one Status
--     label in the daily stand, 14 pedestals with RarityStyle bands (D9), a 13-stud Kitty Bread statue; nothing but the
--     range itself stands on the practice range (§7.7 rule 4);
--   * Batch 3 (the duel pads): the 10 queue_pad_ring parts in DuelGate sit on WorldLayout.QueuePads, one each, so the
--     server can bind the built rings at runtime (FriendDuelService.bindRings).
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
	SD_SqueezeStation = 6,
	SD_PracticeZone = 1,
	SD_PracticeTarget = 4, -- lobby bases spec §3: 3 dummies, plus the moving target the game keeps
	SD_QueuePodium = 1,
	SD_QueueBoard = 1,
	SD_BoxStand = 1,
	SD_ShopCounter = 1,
	SD_CollectionKiosk = 1,
	SD_CollectionPedestal = 14, -- D4: all 14 squishies (lobby.js:91, 278)
	SD_QuestBoard = 1,
	SD_DailyStand = 1,
	SD_ReturnPoint = 2,
	SD_Boundary = 4,
	SD_AudioZone = 3,
	SD_Ambient = 7, -- §18.5.1 A8 / D12: 4 lollipops, both gift boxes, the statue
	SD_Base = 10, -- lobby bases spec §4: one Model per plot
	SD_BaseSpawn = 10, -- and its SpawnLocation
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
}
-- A floor point `radius` studs out on compass angle `degrees` (lobby bases spec §2: clockwise from north, -Z).
local function polar(radius: number, degrees: number): Vector3
	local a = math.rad(degrees)
	return Vector3.new(radius * math.sin(a), 0, -radius * math.cos(a))
end

-- The practice range (§3; island readings): the lane floor X 46..91 across Z -10..10, and the backstop's footing under
-- the pillow wall (X 88..92, Z -21..21). §7.7 rule 4 keeps squishy colours off it.
local function onRange(p: Vector3): boolean
	return (p.X >= 46 and p.X <= 91 and math.abs(p.Z) <= 10) or (p.X >= 88 and p.X <= 92 and math.abs(p.Z) <= 21)
end
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
local MAX_PARTS = 5200 -- lobby bases spec §7: the whole island at its worst (the static tree is far below it)
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

-- The frame of a station (lobby bases spec §3: its sector's compass angle; readings for the radii; lobby.js:112: its
-- local +Z faces the hub centre) and a station-local point in the world.
local FRAMES: { [string]: { number } } = { -- { radius, compass degrees }
	box = { 52, 54 },
	shop = { 56, 18 },
	quests = { 53, 162 },
	daily = { 50, 198 },
	squeeze = { 78, 270 },
}
local function design(id: string, x: number, y: number, z: number): Vector3
	local spec = FRAMES[id]
	local p = polar(spec[1], spec[2])
	local frame = CFrame.new(p) * CFrame.Angles(0, math.atan2(-p.X, -p.Z), 0)
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

	t.test("the root is SD_Lobby, unparented, not Atomic, version 4 (Squish Island without the giant pads)", function()
		local root = lobby()
		expect.equal(root.Name, "SD_Lobby")
		expect.equal(root.Parent, nil)
		expect.equal((root :: Model).ModelStreamingMode, Enum.ModelStreamingMode.Default)
		expect.equal(LobbyBuilder.VERSION, 4)
		expect.equal(root:GetAttribute("SD_GeneratorVersion"), 4)
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

	t.test("6 squeeze stations, unique ids, GripTier from §17.4", function()
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

	t.test("the hub spawn: an invisible SpawnLocation in the medallion on the stage, top 1.1, facing -Z", function()
		local spawn = tagged(lobby(), "SD_LobbySpawn")[1] :: SpawnLocation
		expect.equal(spawn.ClassName, "SpawnLocation")
		expect.equal(spawn.Neutral, true)
		expect.equal(spawn.Duration, 0)
		expect.equal(spawn.Transparency, 1) -- the design's medallion is the spawn (lobby.js:147)
		expect.near(topY(spawn), 1.1, TOLERANCE)
		expect.near(spawn.CFrame.LookVector.Z, -1, TOLERANCE)
		expect.near(Vector3.new(spawn.CFrame.Position.X, 0, spawn.CFrame.Position.Z).Magnitude, 0, TOLERANCE)
		local medallion = named(station("Spawn"), "spawn_medallion")[1]
		expect.truthy(medallion)
		expect.near(topY(medallion), 1.1, TOLERANCE) -- reading: Ø12, 0.3 tall on the stage (top 0.8)
		expect.near(medallion.Size.Y, 12, TOLERANCE) -- an upright cylinder: diameter on Y and Z
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

	t.test(
		"no Grip gym, Royal pod, giant pad, Jelly gate, pod sign or lock decor any more (build plan Phase 6)",
		function()
			local root = lobby()
			expect.equal(root:FindFirstChild("GripGym"), nil)
			expect.equal(root:FindFirstChild("RoyalPod"), nil)
			for _, tag in { "SD_GiantPad", "SD_GripGate", "SD_GripSign", "SD_GripLock" } do
				expect.equal(#tagged(root, tag), 0)
			end
			for _, d in root:GetDescendants() do
				if d:GetAttribute("SD_PadAccent") ~= nil or d:GetAttribute("PadKey") ~= nil then
					error(`{d:GetFullName()} still carries a giant pad attribute`)
				end
			end
		end
	)

	t.test(
		"practice: 4 targets on the island's lane with attributes, one moving, inert, each with a Body mesh",
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
				expect.near(pivot.Position.Z, 0, TOLERANCE) -- the island's one lane
				expect.near(pivot.Position.X, 52 + (target:GetAttribute("Distance") :: number), TOLERANCE)
				expect.near(pivot.Position.Y, 0.6, TOLERANCE) -- on the lane floor's top
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
			expect.near(zone.CFrame.Position.X, 48, TOLERANCE) -- X 44..52, Z -10..10, Y 0..12
			expect.near(zone.Size.X, 8, TOLERANCE)
			expect.near(zone.Size.Z, 20, TOLERANCE)
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
		-- Reading (island): the 42-wide pillow wall stands on a footing past the 20-wide lane, never in the air.
		local footing = range:FindFirstChild("backstop_footing") :: BasePart
		expect.truthy((footing :: BasePart?) ~= nil and footing.CanCollide)
		expect.near(footing.Position.Y - footing.Size.Y / 2, -0.9, TOLERANCE) -- on the grass
		local bottomRow = 0
		for _, pillow in named(range, "backstop_pillow") do
			local p = pillow.Position
			if p.Y - pillow.Size.Y / 2 < 1 then -- the bottom row stands on the lane or the footing
				bottomRow += 1
				expect.truthy(math.abs(p.Z) + pillow.Size.X / 2 <= footing.Size.Z / 2 + TOLERANCE)
				expect.truthy(math.abs(p.X - footing.Position.X) <= footing.Size.X / 2)
				expect.truthy(p.Y - pillow.Size.Y / 2 <= topY(footing) + TOLERANCE)
			end
		end
		expect.equal(bottomRow, 6)
	end)

	t.test("the 10 queue pad rings sit on WorldLayout.QueuePads, one each (Batch 3 runtime binding)", function()
		local pads = t.requireShared("World/WorldLayout").QueuePads
		local hits: { [number]: number } = {}
		local rings = 0
		for _, part in station("DuelGate"):GetDescendants() do
			if part:IsA("BasePart") and part.Name == "queue_pad_ring" then
				rings += 1
				for index, pad in pads do
					local offset = part.Position - pad.position
					if Vector2.new(offset.X, offset.Z).Magnitude < 0.01 then
						hits[index] = (hits[index] or 0) + 1
					end
				end
			end
		end
		expect.equal(rings, 10)
		for index = 1, #pads do
			expect.equal(hits[index], 1)
		end
	end)

	t.test("return points at (∓6, 0.8, 19) on the stage facing +Z, Slots 1 and 2", function()
		local slots: { [number]: boolean } = {}
		for _, point in tagged(lobby(), "SD_ReturnPoint") do
			local part = point :: BasePart
			local slot = part:GetAttribute("Slot") :: number
			slots[slot] = true
			expect.near(part.CFrame.Position.X, if slot == 1 then -6 else 6, TOLERANCE)
			expect.near(part.CFrame.Position.Z, 19, TOLERANCE)
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
			-- Roblox ignores CanQuery on a colliding part: the barrier group keeps the aim ray (Default) off the walls
			-- (user bug report 2026-10-11: throws aimed high flew up to the wall).
			expect.equal(part.CollisionGroup, "SD_Barrier")
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
		for index, degrees in { 54, 126, 234, 342 } do -- island reading: in the garden at r 86, on the grass
			local foot = polar(86, degrees) + Vector3.new(0, -0.9, 0)
			local lollipop = decor:FindFirstChild("Lollipop" .. index) :: Model
			expect.equal(lollipop.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
			-- The client spins it about its pivot: the stick's foot on the grass.
			expect.near((lollipop.WorldPivot.Position - foot).Magnitude, 0, TOLERANCE)
			local _, high = extent(lollipop)
			expect.near(high.Y, -0.9 + 24 + 7, 0.1) -- stick 24, disk radius 7 (lobby.js:468)
		end
	end)

	t.test(
		"nothing but the range stands on the practice range: no squishy body colour near the lanes (§7.7 rule 4)",
		function()
			local Blueprints = t.requireShared("Art/SquishyBlueprints")
			local bodyColours: { [string]: boolean } = {}
			for _, id in SQUISHY_IDS do
				for _, spec in Blueprints[id].parts do
					if spec.body then
						bodyColours[string.upper(spec.color)] = true
					end
				end
			end
			-- Ground, volumes and walls lie under or around everything; the range's own parts are the range.
			local skip: { [string]: boolean } =
				{ PracticeRange = true, Island = true, KeepClear = true, AudioZones = true, Boundaries = true }
			local foreign = {}
			for _, child in lobby():GetChildren() do
				if skip[child.Name] then
					continue
				end
				for _, part in child:GetDescendants() do
					if part:IsA("BasePart") and part.Transparency < 1 and onRange(part.Position) then
						table.insert(foreign, part:GetFullName())
						if bodyColours[string.upper(part.Color:ToHex())] then
							error(`{part:GetFullName()} is {part.Color:ToHex()}, a squishy body colour`)
						end
					end
				end
			end
			if #foreign > 0 then
				error("decor on the practice range: " .. table.concat(foreign, ", "))
			end
			for index = 1, 4 do -- no lollipop on the range (the design hub had one on its corner)
				local lollipop = (lobby():FindFirstChild("Decor") :: Instance):FindFirstChild(
						"Lollipop" .. index
					) :: Model
				expect.falsy(onRange(lollipop.WorldPivot.Position))
			end
		end
	)

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

	t.test("the stations' parts stand where the island puts them (spot checks)", function()
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
		at("DuelGate", "queue_stage", Vector3.new(0, 0.4, 0)) -- §2: the stage Ø44 at the island centre
		expect.equal(#named(station("DuelGate"), "queue_pad"), 10) -- §2 "same 10 queue pads" (lobby.js:190-192)
		at("GiftBoxCounter", "box_dais", design("box", 0, 0.7, 0)) -- lobby.js:209
		at("ShopCounter", "shop_backwall", design("shop", 0, 7.3, -6.8)) -- lobby.js:239 (reading: the compact stall)
		expect.equal(#named(station("ShopCounter"), "awning_stripe"), 8) -- lobby.js:247 (reading: 8 on the stall)
		at("QuestBoard", "quest_header", design("quests", 0, 17.4, -1.6)) -- lobby.js:295
		expect.equal(#named(station("QuestBoard"), "quest_card"), 9) -- lobby.js:300
		expect.equal(#named(station("DailyStand"), "calendar_tile"), 7) -- lobby.js:324
		at("SqueezeZone", "statue_plinth", design("squeeze", 0, 1.4, 0)) -- lobby.js:339
		expect.equal(#named(station("SqueezeZone"), "refill_meter"), 6) -- lobby.js:346
		expect.equal(lobby():FindFirstChild("Kit"), nil) -- the design hub's kit corner is gone
		-- The props (§3, §7): the Butter Fountain at 342°, 6 chocolate benches and 4 pancake tables on the square.
		local decor = station("HubDecor")
		expect.truthy(decor:FindFirstChild("ButterFountain") ~= nil)
		local benches, tables = 0, 0
		for _, child in decor:GetChildren() do
			if string.sub(child.Name, 1, 14) == "ChocolateBench" then
				benches += 1
			elseif string.sub(child.Name, 1, 12) == "PancakeTable" then
				tables += 1
			end
		end
		expect.equal(benches, 6)
		expect.equal(tables, 4)
		local garden = station("Garden")
		expect.equal(#named(garden, "garden_path"), 10)
		for _, name in { "ToastStackTower", "BananaSlide", "FrogLilyPond" } do
			expect.truthy(garden:FindFirstChild(name) ~= nil)
		end
		expect.equal(#station("Sky"):GetChildren(), 6) -- §7: 6 Cloud Bunny clouds
	end)

	-- Squish Island (lobby bases spec §2-§4, §7) -------------------------------------------------------------------------

	-- The single part `name` of `model`.
	local function only(model: Instance, name: string): BasePart
		local parts = named(model, name)
		if #parts ~= 1 then
			error(`{model.Name} has {#parts} {name}`)
		end
		return parts[1]
	end

	t.test(
		"the ground: sea, shallow water, beach, grass at Y -0.9; Squish Square at Y 0, its curb and paths (§2)",
		function()
			local island = station("Island")
			local grass = only(island, "grass")
			expect.near(topY(grass), -0.9, TOLERANCE)
			expect.near(grass.Size.Z, 320, TOLERANCE) -- an upright cylinder: r 160
			local beach = only(island, "beach")
			expect.near(topY(beach), -1.2, TOLERANCE)
			expect.near(beach.Size.Z, 352, TOLERANCE) -- r 176
			expect.truthy(topY(only(island, "grass_edge")) < topY(grass))
			expect.truthy(topY(only(island, "sea")) < topY(only(island, "shallow_water")))
			local hub = station("Hub")
			local floor = only(hub, "hub_floor")
			expect.near(topY(floor), 0, TOLERANCE)
			expect.near(floor.Size.Z, 140, TOLERANCE) -- Ø140
			expect.near(floor.Position.Y - floor.Size.X / 2, -0.9, TOLERANCE) -- raised 0.9 from the garden
			local curb = only(hub, "hub_curb")
			expect.near(topY(curb), -0.03, TOLERANCE) -- Prims.LAYER under the floor: a white band that never flickers
			expect.near(curb.Size.Z, 142, TOLERANCE)
			expect.equal(curb.Color, t.requireShared("Art/Palette").White)
			expect.equal(#named(hub, "hub_path"), 10)
		end
	)

	t.test(
		'10 plots under Bases: Base_NN tagged SD_Base with Plot at their frames, built open: grey, "Open plot" (§4)',
		function()
			local WorldLayout = t.requireShared("World/WorldLayout")
			local Palette = t.requireShared("Art/Palette")
			local bases = station("Bases")
			expect.equal(#bases:GetChildren(), 10)
			for index = 1, 10 do
				local model = bases:FindFirstChild(string.format("Base_%02d", index)) :: Model
				expect.truthy((model :: Model?) ~= nil and model:IsA("Model"))
				expect.truthy(model:HasTag("SD_Base"))
				expect.equal(model:GetAttribute("Plot"), index)
				local frame = WorldLayout.plotFrame(index) :: CFrame
				expect.near((model.WorldPivot.Position - frame.Position).Magnitude, 0, TOLERANCE)
				local tints = { full = 0, light = 0 }
				for _, part in model:GetDescendants() do
					local which = part:GetAttribute("SD_BaseTint")
					if which ~= nil then
						expect.truthy(part:IsA("BasePart") and (which == "full" or which == "light"))
						tints[which :: string] += 1
						local want = Palette[if which == "full" then "BaseOpen" else "BaseOpenLight"]
						expect.equal((part :: BasePart).Color, want)
					end
				end
				expect.equal(tints.light, 1) -- the plinth floor
				expect.truthy(tints.full >= 10) -- the rim, the fence caps, the wall cap, the gate's icing
				-- The name sign: one live Owner label built "Open plot", without SD_TextKey (BaseService writes it).
				local owner = model:FindFirstChild("Owner", true)
				expect.truthy(owner ~= nil and owner:IsA("TextLabel"))
				expect.equal((owner :: TextLabel).Text, Strings.resolve("base.openPlot"))
				expect.equal((owner :: Instance):GetAttribute("SD_TextKey"), nil)
				-- The 4 capsule pads (Slot 1..4) on their spots, top 0.3.
				for slot, pad in WorldLayout.Bases.capsulePads do
					local part = model:FindFirstChild("Pad" .. slot) :: BasePart
					expect.equal(part:GetAttribute("Slot"), slot)
					expect.near((part.Position - frame * (pad + Vector3.new(0, 0.15, 0))).Magnitude, 0, TOLERANCE)
					expect.near(topY(part), 0.3, TOLERANCE)
				end
				-- The plinth floor: Roblox's own studs on top (§7), its top the plot floor (Y 0).
				local floor = model:FindFirstChild("Floor") :: BasePart
				expect.equal(floor.TopSurface, Enum.SurfaceType.Studs)
				expect.near(topY(floor), 0, TOLERANCE)
				expect.equal(model:FindFirstChild("Capsules"), nil) -- BaseService draws the capsules at runtime
			end
		end
	)

	t.test(
		"each plot's SpawnLocation: SD_BaseSpawn with its Plot, invisible, Neutral, flush with the floor, facing the gate",
		function()
			local WorldLayout = t.requireShared("World/WorldLayout")
			local seen: { [number]: boolean } = {}
			for _, item in tagged(lobby(), "SD_BaseSpawn") do
				local spawn = item :: SpawnLocation
				expect.equal(spawn.ClassName, "SpawnLocation")
				local plot = spawn:GetAttribute("Plot") :: number
				expect.falsy(seen[plot])
				seen[plot] = true
				expect.equal((spawn.Parent :: Instance).Name, string.format("Base_%02d", plot)) -- inside its plot's model
				expect.equal(spawn.Neutral, true)
				expect.equal(spawn.Duration, 0)
				expect.equal(spawn.Transparency, 1)
				expect.equal(spawn.CanTouch, true) -- a SpawnLocation keeps its touch (§7's rule spares it)
				expect.near(topY(spawn), 0, TOLERANCE)
				local want = (WorldLayout.plotFrame(plot) :: CFrame) * WorldLayout.Bases.spawn
				expect.near(
					Vector3.new(spawn.Position.X - want.X, 0, spawn.Position.Z - want.Z).Magnitude,
					0,
					TOLERANCE
				)
				expect.near((spawn.CFrame.LookVector - want.LookVector).Magnitude, 0, TOLERANCE)
			end
			for plot = 1, 10 do
				expect.truthy(seen[plot])
			end
		end
	)

	t.test("each plot's gate leaves its 16-stud gap open: nothing collidable stands in it (§4)", function()
		local WorldLayout = t.requireShared("World/WorldLayout")
		local Verify = dynamicRequire(toolsClone:FindFirstChild("Verify") :: ModuleScript)
		local B = WorldLayout.Bases
		for index = 1, 10 do
			local model = station("Bases"):FindFirstChild(string.format("Base_%02d", index)) :: Instance
			local frame = WorldLayout.plotFrame(index) :: CFrame
			-- The opening: 15.8 wide across the fence line (local z 23..26), from 0.5 above the floor to 6.5.
			local opening, size = frame * CFrame.new(0, 3.5, B.depth / 2 - 1.5), Vector3.new(15.8, 6, 3)
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part.CanCollide then
					if Verify.boxesOverlap(opening, size, part.CFrame, part.Size, 0.01) then
						error(`{part:GetFullName()} stands in plot {index}'s gate`)
					end
				end
			end
			expect.equal(#named(model, "FencePost"), 16) -- every 8 studs along the sides, beside the gate (§4)
			expect.equal(#named(model, "GatePillar"), 2)
		end
	end)

	t.test("the 10 paths stay clear: no collidable part stands where people walk (§2: 8 wide)", function()
		-- Points along each path, 3.5 either side of its line and on it, 1.5 and 4 studs above the walking surface
		-- (the square at Y 0 to r 70, the garden path at Y -0.8 beyond), from the stage edge to the gate.
		type Solid = { part: BasePart, reach: number }
		local solids: { Solid } = {}
		for _, part in lobby():GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide and not part:HasTag("SD_Boundary") then
				table.insert(solids, { part = part, reach = part.Size.Magnitude / 2 })
			end
		end
		local function inside(part: BasePart, point: Vector3): boolean
			local p = part.CFrame:PointToObjectSpace(point)
			local h = part.Size / 2
			local shape = if part:IsA("Part") then part.Shape else Enum.PartType.Block
			if shape == Enum.PartType.Ball then
				return p.Magnitude < h.X
			elseif shape == Enum.PartType.Cylinder then
				return math.abs(p.X) < h.X and p.Y * p.Y + p.Z * p.Z < math.min(h.Y, h.Z) ^ 2
			end
			return math.abs(p.X) < h.X and math.abs(p.Y) < h.Y and math.abs(p.Z) < h.Z
		end
		for index = 1, 10 do
			local out = polar(1, (index - 1) * 36)
			local side = Vector3.new(-out.Z, 0, out.X)
			local nearby: { BasePart } = {}
			for _, solid in solids do
				local q = solid.part.Position
				local along = math.clamp(Vector3.new(q.X, 0, q.Z):Dot(out), 22, 96)
				local flat = Vector3.new(q.X, 0, q.Z) - out * along
				if flat.Magnitude <= 4 + solid.reach then
					table.insert(nearby, solid.part)
				end
			end
			for radius = 23, 95, 1.5 do
				local floor = if radius <= 70 then 0 else -0.8
				for _, lateral in { -3.5, 0, 3.5 } do
					for _, height in { 1.5, 4 } do
						local point = out * radius + side * lateral + Vector3.new(0, floor + height, 0)
						for _, part in nearby do
							if inside(part, point) then
								error(`{part:GetFullName()} stands on path {index} at r {radius}`)
							end
						end
					end
				end
			end
		end
	end)

	t.test(
		"the duel tower: 4 pillars on the stage at (±12, ±12), the deck at 35-38.5, the Dragon's top near 68 (§2)",
		function()
			local tower = station("DuelTower")
			local pillars = named(tower, "tower_pillar")
			expect.equal(#pillars, 4)
			for _, pillar in pillars do
				expect.near(math.abs(pillar.Position.X), 12, TOLERANCE)
				expect.near(math.abs(pillar.Position.Z), 12, TOLERANCE)
				expect.near(pillar.Position.Y - pillar.Size.Y / 2, 0.8, TOLERANCE) -- on the stage top
				expect.near(topY(pillar), 35, TOLERANCE) -- under the deck
				expect.equal(pillar.CanCollide, true)
				-- On the stage (Ø44), so off every path: its outer corner inside the stage edge.
				local corner = Vector3.new(math.abs(pillar.Position.X) + 3.5, 0, math.abs(pillar.Position.Z) + 3.5)
				expect.truthy(corner.Magnitude <= 22)
			end
			local deck = only(tower, "tower_deck")
			expect.near(deck.Position.Y - deck.Size.Y / 2, 35, TOLERANCE)
			expect.near(topY(deck), 38.5, TOLERANCE)
			expect.equal(deck.CanCollide, false) -- decor above the pillars
			local dragon = tower:FindFirstChild("TowerDragon") :: Model
			expect.truthy((dragon :: Model?) ~= nil)
			local _, high = extent(dragon)
			expect.truthy(high.Y >= 60 and high.Y <= 76) -- §2: "about 68 tall"
			local badge = false
			for _, d in tower:GetDescendants() do
				if d:IsA("TextLabel") and d:GetAttribute("SD_TextKey") == "world.gateBadge" then
					badge = true
				end
			end
			expect.truthy(badge) -- "DUELS" on the deck (lobby.js:184)
		end
	)

	t.test("the part budget per zone (§7): hub 2,000, each plot at its worst 220, garden 1,000, all 5,200", function()
		local WorldLayout = t.requireShared("World/WorldLayout")
		local budgets = WorldLayout.Budgets
		expect.equal(budgets.hubParts, 2000)
		expect.equal(budgets.baseParts, 220)
		expect.equal(budgets.gardenParts, 1000)
		expect.equal(budgets.islandParts, 5200)
		-- A plot at its worst: 4 open capsules of the biggest look holding the 4 biggest squishies, and the statue.
		local builders = toolsClone:FindFirstChild("Builders") :: Instance
		local CapsuleBuilder = dynamicRequire(builders:FindFirstChild("CapsuleBuilder") :: ModuleScript)
		local templateScratch = Cleanup.new()
		local templates = CapsuleBuilder.build({ scratch = templateScratch, Shared = shared })
		expect.truthy(templates.ok)
		local worst = CapsuleBuilder.worstPlotParts(templates.root, 4)
		templates.root:Destroy()
		templateScratch:clean()
		expect.truthy(worst > 4 * 10) -- 4 capsules at least
		local function count(instance: Instance): number
			local n = 0
			for _, d in instance:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			return n
		end
		local garden: { [string]: boolean } =
			{ Island = true, Boundaries = true, Garden = true, Sky = true, Decor = true }
		local hubParts, gardenParts, total = 0, 0, 0
		for _, child in lobby():GetChildren() do
			if child.Name == "Bases" then
				for _, base in child:GetChildren() do
					local parts = count(base) + worst
					if parts > budgets.baseParts then
						error(`{base.Name} has {parts} parts at its worst`)
					end
					total += parts
				end
			elseif garden[child.Name] then
				gardenParts += count(child)
			else
				hubParts += count(child)
			end
		end
		total += hubParts + gardenParts
		expect.truthy(hubParts <= budgets.hubParts)
		expect.truthy(gardenParts <= budgets.gardenParts)
		expect.truthy(total <= budgets.islandParts)
		-- The build report states the same counts.
		local report: string? = nil
		for _, warning in built.warnings do
			if string.find(warning, "lobby report", 1, true) then
				report = warning
			end
		end
		expect.truthy(report ~= nil and string.find(report :: string, `hub {hubParts} parts`, 1, true) ~= nil)
		expect.truthy(string.find(report :: string, `the island at its worst {total} `, 1, true) ~= nil)
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
