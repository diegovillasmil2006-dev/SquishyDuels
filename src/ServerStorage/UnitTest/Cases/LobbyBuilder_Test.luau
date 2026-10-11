--!strict
-- LobbyBuilder_Test: the DESIGN contract of the lobby generator ServerStorage.SDTools.Builders.LobbyBuilder. Server
-- only (ServerStorage.UnitTest). Builders_Test already checks the generic part (ok, unparented, marked, passes
-- Verify); these cases pin what the runtime and the binders rely on, restated from DESIGN (§5.11, §7.6, §7.7, §17.4,
-- §17.6, §17.6.1) instead of read from WorldLayout, so a drift in either is caught:
--   * every ProximityPrompt starts DISABLED and carries SD_TextKey (WorldBinder enables it only when its UI exists);
--   * static sign lines are TextLabels tagged SD_Sign with SD_TextKey; live lines have neither (one writer each);
--   * the spawn, the 9 squeeze stations and their tiers, the practice targets, return points and boundaries;
--   * the giant pads: Atomic, one Collision station box, a path B Body of Sphere tiles that never collides, a Face
--     from the pad's giant_* blueprint on the side the pad looks toward;
--   * §7.7 rule 4: the lollipop standing on the practice lanes uses no squishy body colour;
--   * the feel pass (§18.5.1 A8, §18.8): 7 SD_Ambient models with their SD_AmbientKind (4 Atomic lollipops spin, the
--     daily gift box spins and bobs, the counter gift box and the statue breathe), none of their parts collides, is
--     queried or touched; the practice audio zone covers the practice throw box.
-- The lobby is built once, in memory, from the Shared folder under test; nothing is parented into the place.

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
}

-- DESIGN numbers (restated).
local TAG_COUNTS: { [string]: number } = { -- §7.7 self-check + §17.6 additions
	SD_LobbySpawn = 1,
	SD_SqueezeStation = 9,
	SD_PracticeZone = 1,
	SD_PracticeTarget = 9,
	SD_QueuePodium = 1,
	SD_QueueBoard = 1,
	SD_BoxStand = 1,
	SD_ShopCounter = 1,
	SD_CollectionKiosk = 1,
	SD_CollectionPedestal = 8,
	SD_QuestBoard = 1,
	SD_DailyStand = 1,
	SD_ReturnPoint = 2,
	SD_GripGate = 3,
	SD_GripSign = 3,
	SD_GiantPad = 3,
	SD_Ambient = 7, -- §18.5.1 A8: 4 lollipops, both gift boxes, the statue
}
-- §18.5.1 A8: which models the client moves, and how (SD_AmbientKind).
local AMBIENT_KINDS: { [string]: string } = {
	["Decor/Lollipop1"] = "spin",
	["Decor/Lollipop2"] = "spin",
	["Decor/Lollipop3"] = "spin",
	["Decor/Lollipop4"] = "spin",
	["DailyStand/GiftBox"] = "spinBob",
	["GiftBoxCounter/GiftBox"] = "breathe",
	["SqueezeZone/Statue"] = "breathe",
}
-- §18.8: the practice audio zone grew to cover the practice throw box (X -24..-16, Z -54..-20).
local PRACTICE_AUDIO = { position = Vector3.new(-38, 15, -37), size = Vector3.new(44, 30, 34) }
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
type PadSpec = {
	tier: number,
	station: string,
	center: Vector3,
	tiles: number,
	restTop: number,
	gate: number,
	footprint: number,
	face: Vector3,
}
local GIANT_PADS: { [string]: PadSpec } = { -- §17.6.1 pad specs ("Face looks toward": +X spawn side, -X promenade)
	jelly = {
		tier = 2,
		station = "squeeze_07",
		center = Vector3.new(-33, 0, 37),
		tiles = 64,
		restTop = 1.5,
		gate = 12,
		footprint = 8,
		face = Vector3.new(1, 0, 0),
	},
	marshmallow = {
		tier = 3,
		station = "squeeze_08",
		center = Vector3.new(-53, 0, 37),
		tiles = 64,
		restTop = 1.6,
		gate = 12,
		footprint = 8,
		face = Vector3.new(1, 0, 0),
	},
	royal = {
		tier = 4,
		station = "squeeze_09",
		center = Vector3.new(38, 0, 38),
		tiles = 81,
		restTop = 1.7,
		gate = 14,
		footprint = 9,
		face = Vector3.new(-1, 0, 0),
	},
}
-- §7.6 practice lane floor X -60..-24, Z -54..-20 (§7.7 props rule 4: nothing squishy-coloured near the lanes).
local LANE_MIN, LANE_MAX = Vector3.new(-60, 0, -54), Vector3.new(-24, 0, -20)
-- The 8 squishies (§4.2): their body colours are what rule 4 keeps away from the lanes.
local SQUISHY_IDS = {
	"kitty_bread",
	"toast",
	"banana",
	"butter",
	"chocolate",
	"bird",
	"donut",
	"dragon",
	-- Spec 2026-10-09 §3.3: the 6 new squishies.
	"boba_bear",
	"pancake_pup",
	"mochi_fox",
	"strawberry_frog",
	"cloud_bunny",
	"cupcake_axolotl",
}
local COLLISION_TOP = 1.0 -- §17.6.1
local TILE_SIZE = Vector3.new(2, 1, 2) -- §17.6.1 path B
local STAND_TAGS = { "SD_QueuePodium", "SD_BoxStand", "SD_ShopCounter", "SD_CollectionKiosk", "SD_QuestBoard" }
local MAX_SURFACE_GUIS = 30 -- §7.7 / §17.6
local MAX_PARTS = 2500 -- §7.7
local TOLERANCE = 1e-3 -- CFrames are stored in single precision

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

local function topY(part: BasePart): number
	local cf, half = part.CFrame, part.Size / 2
	return cf.Position.Y
		+ math.abs(cf.XVector.Y) * half.X
		+ math.abs(cf.YVector.Y) * half.Y
		+ math.abs(cf.ZVector.Y) * half.Z
end

return function(t: Context)
	local LobbyBuilder, toolsClone = loadBuilder()
	local Cleanup = t.requireShared("Util/Cleanup")
	local Strings = t.requireShared("Strings")
	local expect = t.expect

	-- One build shared by every case (about 700 parts, all in memory).
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

	t.test("the root is SD_Lobby, unparented, not Atomic", function()
		local root = lobby()
		expect.equal(root.Name, "SD_Lobby")
		expect.equal(root.Parent, nil)
		expect.equal((root :: Model).ModelStreamingMode, Enum.ModelStreamingMode.Default)
	end)

	t.test("exact tag counts (§7.7, §17.6)", function()
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
		for _, station in tagged(lobby(), "SD_SqueezeStation") do
			local id = station:GetAttribute("StationId")
			expect.truthy(type(id) == "string" and STATION_TIERS[id :: string] ~= nil)
			expect.falsy(seen[id :: string])
			seen[id :: string] = true
			expect.equal(station:GetAttribute("GripTier"), STATION_TIERS[id :: string])
			expect.truthy(station:IsA("BasePart"))
		end
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
		expect.equal(count, 14) -- podium, box, shop, kiosk, quest, daily + 8 pedestals
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

	t.test("the spawn: SpawnLocation, Neutral, Duration 0, top Y 0.05, facing -Z (§7.6)", function()
		local spawn = tagged(lobby(), "SD_LobbySpawn")[1] :: SpawnLocation
		expect.equal(spawn.ClassName, "SpawnLocation")
		expect.equal(spawn.Neutral, true)
		expect.equal(spawn.Duration, 0)
		expect.near(topY(spawn), 0.05, TOLERANCE)
		expect.near(spawn.CFrame.LookVector.Z, -1, TOLERANCE)
	end)

	t.test("sign labels: static lines tagged with a key, live lines never keyed (§1.6, §17.6)", function()
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
		expect.truthy(guis > 0 and guis <= MAX_SURFACE_GUIS)
	end)

	t.test("pod signs: one Live label without a key, a keyed grip.pad Title", function()
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
			expect.truthy(type(sign:GetAttribute("GripTier")) == "number")
		end
	end)

	t.test("giant pads: Atomic, one Collision station box, Body and Face never collide (§17.6.1)", function()
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
			expect.near(topY(box), COLLISION_TOP, 0.01)
			expect.near(box.CFrame.Position.X, spec.center.X, TOLERANCE)
			expect.near(box.CFrame.Position.Z, spec.center.Z, TOLERANCE)

			local bodyChild = model:FindFirstChild("Body")
			local faceChild = model:FindFirstChild("Face")
			expect.truthy(bodyChild ~= nil and bodyChild:IsA("Model"))
			expect.truthy(faceChild ~= nil and faceChild:IsA("Model"))
			local body = bodyChild :: Model
			local face = faceChild :: Model
			expect.near((body.WorldPivot.Position - spec.center).Magnitude, 0, TOLERANCE) -- bottom centre
			local tiles, bodyTop, faceParts = 0, -math.huge, 0
			for _, folder in { body, face } do
				for _, part in folder:GetDescendants() do
					if part:IsA("BasePart") then
						expect.equal(part.CanCollide, false)
						expect.equal(part.CanQuery, false)
						expect.equal(part.CanTouch, false)
						if folder == face then
							faceParts += 1
						else
							bodyTop = math.max(bodyTop, topY(part))
						end
						if string.sub(part.Name, 1, 5) == "Tile_" then
							tiles += 1
							expect.near((part.Size - TILE_SIZE).Magnitude, 0, TOLERANCE)
							local mesh = part:FindFirstChildOfClass("SpecialMesh")
							expect.truthy(mesh ~= nil and mesh.MeshType == Enum.MeshType.Sphere)
						end
					end
				end
			end
			expect.equal(tiles, spec.tiles)
			expect.near(bodyTop, spec.restTop, 0.01)
			expect.truthy(bodyTop >= COLLISION_TOP + 0.4)
			expect.truthy(faceParts > 0)
		end
	end)

	-- §17.6.1 "Face: eyes, mouth and blush made of geometry (§8), on the side" that looks toward the promenade or the
	-- spawn; §17.11: the faces come from the giant_* blueprints, not from the generator's fallback.
	t.test("giant pad faces come from their blueprints and sit low on the side they look toward", function()
		local root = lobby()
		for _, warning in built.warnings do
			if string.find(warning, "generator face", 1, true) then
				error("a pad used the fallback face: " .. warning)
			end
		end
		for _, model in tagged(root, "SD_GiantPad") do
			local spec = GIANT_PADS[model:GetAttribute("PadKey") :: string]
			local face = model:FindFirstChild("Face") :: Model
			local names: { [string]: boolean } = {}
			for _, part in face:GetDescendants() do
				if part:IsA("BasePart") then
					names[part.Name] = true
					local offset = part.CFrame.Position - spec.center
					expect.truthy(offset:Dot(spec.face) > spec.footprint / 2 - 0.5) -- on the facing side
					expect.truthy(offset.Y > 0 and offset.Y < spec.restTop) -- between the floor and the top
				end
			end
			for _, name in { "EyeL", "EyeR", "ShineL", "ShineR", "Mouth", "BlushL", "BlushR" } do
				if not names[name] then
					error(`{model.Name}: Face has no {name}`)
				end
			end
		end
	end)

	t.test("the lollipop on the practice lanes uses no squishy body colour (§7.7 rule 4)", function()
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
		local onLanes = 0
		for _, model in decor:GetChildren() do
			if not (model:IsA("Model") and string.sub(model.Name, 1, 8) == "Lollipop") then
				continue
			end
			local base = (model :: Model).WorldPivot.Position
			if base.X < LANE_MIN.X or base.X > LANE_MAX.X or base.Z < LANE_MIN.Z or base.Z > LANE_MAX.Z then
				continue
			end
			onLanes += 1
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and bodyColours[string.upper(part.Color:ToHex())] then
					error(`{part:GetFullName()} is {part.Color:ToHex()}, a squishy body colour`)
				end
			end
		end
		expect.equal(onLanes, 1) -- the NW lollipop (DESIGN (-58, 0, -50), moved to X -55 off the backstop)
	end)

	-- §7.7 "ambient sparkle at the statue" (≤ 3 ambient emitters): one emitter, Config.Vfx rates, built-in texture,
	-- no glow.
	t.test("the statue has its ambient sparkle and the lobby stays within the emitter budget", function()
		local Config = t.requireShared("Config")
		local emitters = {}
		for _, d in lobby():GetDescendants() do
			if d:IsA("ParticleEmitter") then
				table.insert(emitters, d)
			end
		end
		expect.truthy(#emitters >= 1 and #emitters <= 3)
		local squeeze = lobby():FindFirstChild("SqueezeZone") :: Instance
		local sparkle = squeeze:FindFirstChild("StatueSparkle", true)
		expect.truthy(sparkle ~= nil and sparkle:IsA("ParticleEmitter"))
		local emitter = sparkle :: ParticleEmitter
		expect.equal(emitter.Rate, Config.Vfx.Effects.statueSparkleRate)
		expect.near(emitter.Lifetime.Max, Config.Vfx.Effects.statueSparkleLifetime, 1e-6)
		expect.equal(emitter.LightEmission, 0)
		expect.truthy(string.sub(emitter.Texture, 1, 10) == "rbxasset:/")
	end)

	-- §17.6.1 looks: path A replaces Body with a one-colour mesh, so the accents path A keeps are marked.
	t.test("giant pad accents are marked SD_PadAccent: the Marshmallow band and the Royal tuft", function()
		local accents: { [string]: { string } } = {}
		for _, model in tagged(lobby(), "SD_GiantPad") do
			local key = model:GetAttribute("PadKey") :: string
			local names = {}
			for _, part in (model:FindFirstChild("Body") :: Instance):GetDescendants() do
				if part:IsA("BasePart") and part:GetAttribute("SD_PadAccent") == true then
					table.insert(names, part.Name)
				end
			end
			table.sort(names)
			accents[key] = names
		end
		expect.deepEqual(accents.jelly, {})
		expect.deepEqual(accents.marshmallow, { "Band" })
		expect.equal(#accents.royal, 1)
		expect.truthy(string.sub(accents.royal[1], 1, 5) == "Tile_") -- the centre tile, Strawberry
	end)

	t.test("jelly gates are open by default, one per pad tier (§17.6)", function()
		local tiers: { [number]: boolean } = {}
		for _, gate in tagged(lobby(), "SD_GripGate") do
			local part = gate :: BasePart
			expect.equal(part.CanCollide, false)
			expect.equal(part.CanQuery, false)
			expect.equal(part.CanTouch, false)
			local tier = part:GetAttribute("GripTier") :: number
			expect.truthy(tier >= 2 and tier <= 4 and not tiers[tier])
			tiers[tier] = true
			for _, spec in GIANT_PADS do
				if spec.tier == tier then
					expect.near(part.Size.Y, spec.gate, TOLERANCE) -- an upright cylinder: diameter on Y and Z
				end
			end
		end
	end)

	t.test("practice: 9 targets with attributes, exactly one moving (§5.11)", function()
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
			for _, part in target:GetDescendants() do
				if part:IsA("BasePart") then
					expect.equal(part.CanCollide, false) -- hits are capsule maths on the server, never touches
				end
			end
		end
		expect.equal(moving, 1)
		local zone = tagged(lobby(), "SD_PracticeZone")[1] :: BasePart
		expect.near(zone.CFrame.Position.X, -20, TOLERANCE) -- X -24..-16, Z -54..-20, Y 0..12
		expect.near(zone.Size.X, 8, TOLERANCE)
		expect.near(zone.Size.Z, 34, TOLERANCE)
		expect.near(zone.Size.Y, 12, TOLERANCE)
		expect.equal(zone.CanCollide, false)
	end)

	t.test("return points at (+-6, 0, -24) facing +Z, Slots 1 and 2 (§7.6)", function()
		local slots: { [number]: boolean } = {}
		for _, point in tagged(lobby(), "SD_ReturnPoint") do
			local part = point :: BasePart
			local slot = part:GetAttribute("Slot") :: number
			slots[slot] = true
			expect.near(math.abs(part.CFrame.Position.X), 6, TOLERANCE)
			expect.near(part.CFrame.Position.Z, -24, TOLERANCE)
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

	t.test("collidable parts are anchored; Neon only on the gift box rim; part budget (§7.3, §7.7)", function()
		local parts = 0
		for _, instance in lobby():GetDescendants() do
			if instance:IsA("BasePart") then
				parts += 1
				if instance.CanCollide then
					expect.equal(instance.Anchored, true)
				end
				if instance.Material == Enum.Material.Neon then
					expect.equal(instance.Name, "NeonRim")
				end
			end
		end
		expect.truthy(parts <= MAX_PARTS)
	end)

	t.test(
		"SD_Ambient: 7 tagged models with their kind, the lollipops Atomic, every part inert (§18.5.1 A8)",
		function()
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
			for index = 1, 4 do
				local lollipop = decor:FindFirstChild("Lollipop" .. index) :: Model
				expect.equal(lollipop.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
				-- The client spins it about its pivot: the stick's foot on the floor.
				expect.near(lollipop.WorldPivot.Position.Y, 0, TOLERANCE)
			end
		end
	)

	t.test("the practice audio zone covers the throw box (§18.8)", function()
		local practice: BasePart? = nil
		for _, zone in tagged(lobby(), "SD_AudioZone") do
			if zone:GetAttribute("ZoneId") == "practice" then
				practice = zone :: BasePart
			end
		end
		expect.truthy(practice ~= nil)
		local part = practice :: BasePart
		expect.truthy((part.CFrame.Position - PRACTICE_AUDIO.position).Magnitude < TOLERANCE)
		expect.truthy((part.Size - PRACTICE_AUDIO.size).Magnitude < TOLERANCE)
		expect.equal(part.CanCollide, false)
		expect.equal(part.CanQuery, false)
		expect.equal(part.CanTouch, false)
	end)

	t.test("the statue and both gift boxes are built", function()
		local root = lobby()
		local squeeze = root:FindFirstChild("SqueezeZone")
		local box = root:FindFirstChild("GiftBoxCounter")
		local daily = root:FindFirstChild("DailyStand")
		expect.truthy(squeeze and squeeze:FindFirstChild("Statue"))
		expect.truthy(box and box:FindFirstChild("GiftBox"))
		expect.truthy(daily and daily:FindFirstChild("GiftBox"))
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
		expect.truthy(string.find(result.error or "", "WorldLayout", 1, true) ~= nil)
	end)

	-- Teardown: the shared build and the tools clone.
	t.test("teardown", function()
		if okBuild and built.root then
			built.root:Destroy()
		end
		scratch:clean()
		toolsClone:Destroy()
	end)
end
