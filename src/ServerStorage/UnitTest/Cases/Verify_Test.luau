--!strict
-- Verify_Test: unit tests for ServerStorage.SDTools.Verify. Server only (ServerStorage.UnitTest).
-- Contracts:
--   shapes (DESIGN §1.7 step 4, §8.1 #2): SD_ShapeLibrary holds exactly one RoundedBox, any PartOperation (the
--     IntersectOperation GeometryService:IntersectAsync returns), never a plain Part. An empty in-memory solid has no
--     geometry, so only the class rule is asserted for it.
--   lobby (§7.6, §7.7, §17.6, §17.6.1): exact tag counts, 9 stations with unique ids and GripTier = WorldLayout,
--     practice targets (1 moving), slots, Grip gates built open, Grip signs with exactly one Live label (no
--     SD_TextKey) and one grip.pad.* Title, giant pads (one Collision station, top = WorldLayout collisionTop ± 0.01,
--     Body top ≥ 0.4 above it, Body/Face inert), every SD_TextKey in Strings, keep-clear volumes, all stand prompts
--     disabled inside Atomic models < 64 studs, budgets (FAIL above 2,500 parts or 30 SurfaceGuis); the feel pass
--     (§18.5.1 A8): exactly 7 SD_Ambient decor pieces, each with a known SD_AmbientKind and no part that collides, is
--     queried or touched (the client turns or breathes them locally).
--   arena (§5.3, §7.8): structure, Origin PrimaryPart, Geometry CanQuery (Barriers excepted), floor top Y 0 out to
--     the barrier walls (no gap behind the rails), cover (12 pieces, top ≥ 8, width ≤ 8, outside the neutral zone,
--     point-symmetric), open pad-to-pad lane, barriers (walls and ceiling in SD_Barrier, 76-wide dividers in
--     SD_Divider: Roblox ignores CanQuery false on colliding parts, so the groups keep projectile rays off them),
--     zones, pads, inert Decor, empty Runtime, nothing forbidden, ≤ 400 parts.
--   templateLeftovers (§1.9 #4): a SpawnLocation or a floor-plane part outside the lobby root is reported.
-- Method: a small hand-built tree that passes is the baseline; each case breaks exactly one rule and expects the
-- matching problem line. Lobby cases inject fake Strings and WorldLayout modules (deps), so they do not depend on
-- the real data. RunUnitTest passes no editor folder, so the whole SDTools folder is cloned (Verify requires its
-- sibling Generated; a clone also defeats the require cache). Every instance stays in memory: nothing is parented
-- into the place, so Verify.afterSwap (which needs Workspace) is not exercised here.

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
}

type Flags = {
	collide: boolean,
	query: boolean,
	touch: boolean?,
	transparency: number?,
}

local CLASS_PROBLEM = "expected a PartOperation"

local SOLID: Flags = { collide = true, query = true }
local GHOST: Flags = { collide = false, query = false, transparency = 1 }
local INERT: Flags = { collide = false, query = false }
local WALL: Flags = { collide = true, query = false, transparency = 1 }

-- Lobby fixtures: Grip pods (§17.6) and the fake modules.
local PADS = {
	{ key = "jelly", tier = 2, station = "squeeze_07", x = -33, z = 37 },
	{ key = "marshmallow", tier = 3, station = "squeeze_08", x = -53, z = 37 },
	{ key = "royal", tier = 4, station = "squeeze_09", x = 38, z = 38 },
}
local KNOWN_KEYS: { [string]: boolean } = {
	["world.spawnLogo"] = true,
	["grip.pad.jelly"] = true,
	["grip.pad.marshmallow"] = true,
	["grip.pad.royal"] = true,
}
local FAKE_STRINGS = {
	resolve = function(key: string): string?
		return if KNOWN_KEYS[key] then "text" else nil
	end,
}

-- Arena fixtures (§7.8): Side B cover boxes (centre X, centre Z, size); Side A is the point reflection.
local COVER_B = {
	{ x = 9, z = 20, size = Vector3.new(6, 8, 2.5) },
	{ x = -9, z = 20, size = Vector3.new(6, 8, 2.5) },
	{ x = 20, z = 30, size = Vector3.new(5, 10, 5) },
	{ x = -20, z = 30, size = Vector3.new(5, 10, 5) },
	{ x = 24, z = 14, size = Vector3.new(6, 8.6, 6) },
	{ x = -24, z = 14, size = Vector3.new(6, 8.6, 6) },
}
local BARRIERS = {
	{ name = "WallXPos", center = Vector3.new(38.5, 20, 0), size = Vector3.new(1, 40, 110), group = "SD_Barrier" },
	{ name = "WallXNeg", center = Vector3.new(-38.5, 20, 0), size = Vector3.new(1, 40, 110), group = "SD_Barrier" },
	{ name = "WallZPos", center = Vector3.new(0, 20, 54.5), size = Vector3.new(78, 40, 1), group = "SD_Barrier" },
	{ name = "WallZNeg", center = Vector3.new(0, 20, -54.5), size = Vector3.new(78, 40, 1), group = "SD_Barrier" },
	{ name = "Ceiling", center = Vector3.new(0, 40.5, 0), size = Vector3.new(78, 1, 110), group = "SD_Barrier" },
	{ name = "DividerA", center = Vector3.new(0, 20, -8), size = Vector3.new(76, 40, 1), group = "SD_Divider" },
	{ name = "DividerB", center = Vector3.new(0, 20, 8), size = Vector3.new(76, 40, 1), group = "SD_Divider" },
}
local ZONES = {
	{ name = "HalfA", center = Vector3.new(0, 12.5, -30), size = Vector3.new(72, 55, 44) },
	{ name = "Neutral", center = Vector3.new(0, 12.5, 0), size = Vector3.new(72, 55, 16) },
	{ name = "HalfB", center = Vector3.new(0, 12.5, 30), size = Vector3.new(72, 55, 44) },
	{ name = "Bounds", center = Vector3.new(0, 12.5, 0), size = Vector3.new(76, 55, 108) },
}

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local function loadTools(): (any, any, Instance)
	local source = ServerStorage:FindFirstChild("SDTools")
	if source == nil then
		error("ServerStorage.SDTools not found (is Rojo connected?)")
	end
	local clone = source:Clone()
	local verify = clone:FindFirstChild("Verify")
	local generated = clone:FindFirstChild("Generated")
	if verify == nil or not verify:IsA("ModuleScript") or generated == nil or not generated:IsA("ModuleScript") then
		clone:Destroy()
		error("SDTools.Verify or SDTools.Generated is missing")
	end
	return dynamicRequire(verify), dynamicRequire(generated), clone
end

local function hasProblem(problems: { string }, needle: string): boolean
	for _, problem in problems do
		if string.find(problem, needle, 1, true) then
			return true
		end
	end
	return false
end

local function newFolder(parent: Instance?, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function newModel(parent: Instance?, name: string, atomic: boolean): Model
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = if atomic then Enum.ModelStreamingMode.Atomic else Enum.ModelStreamingMode.Default
	model.Parent = parent
	return model
end

local function newPart(parent: Instance?, name: string, size: Vector3, cframe: CFrame, flags: Flags): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = flags.collide
	part.CanTouch = flags.touch == true
	part.CanQuery = flags.query
	part.Transparency = flags.transparency or 0
	part.Parent = parent
	return part
end

local function newLabel(parent: Instance, name: string, textKey: string?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	if textKey then
		label:SetAttribute("SD_TextKey", textKey)
	end
	label.Parent = parent
	return label
end

local function tagged(root: Instance, tag: string): { Instance }
	local found: { Instance } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:HasTag(tag) then
			table.insert(found, descendant)
		end
	end
	return found
end

local function firstTagged(root: Instance, tag: string): Instance
	local found: Instance? = tagged(root, tag)[1]
	if found == nil then
		error(string.format("fixture has no %s", tag))
	end
	return found
end

local function findTagged(root: Instance, tag: string, attribute: string, value: any): Instance
	for _, instance in tagged(root, tag) do
		if instance:GetAttribute(attribute) == value then
			return instance
		end
	end
	error(string.format("fixture has no %s with %s = %s", tag, attribute, tostring(value)))
end

-- A WorldLayout fake in the "Stations array + GiantPads map" shape.
local function fakeLayout(): any
	local stations = {}
	for index = 1, 9 do
		table.insert(
			stations,
			{ id = string.format("squeeze_%02d", index), gripTier = if index <= 6 then 1 else index - 5 }
		)
	end
	local pads = {}
	for _, pad in PADS do
		pads[pad.key] = { stationId = pad.station, collisionTop = 1.0 }
	end
	return { Stations = stations, GiantPads = pads }
end

-- A small lobby that satisfies every lobby rule (positions follow §7.6 / §17.6 loosely; only the rules matter).
local function lobbyTree(Generated: any): Model
	local root = newModel(nil, "SD_Lobby", false)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 8)
	spawn.CFrame = CFrame.new(0, -0.45, 40)
	spawn.Anchored = true
	spawn.Duration = 0
	spawn.Neutral = true
	spawn:AddTag("SD_LobbySpawn")
	spawn.Parent = root

	local mats = newFolder(root, "Mats")
	for index = 1, 6 do
		local x = -46 + 10 * ((index - 1) % 3)
		local z = if index <= 3 then 0 else 14
		local mat = newPart(mats, "Mat_" .. index, Vector3.new(8, 0.3, 8), CFrame.new(x, 0.15, z), SOLID)
		mat:AddTag("SD_SqueezeStation")
		mat:SetAttribute("StationId", string.format("squeeze_%02d", index))
		mat:SetAttribute("GripTier", 1)
	end

	local practice = newModel(root, "Practice", false)
	newPart(practice, "ThrowBox", Vector3.new(8, 12, 34), CFrame.new(-20, 6, -37), GHOST):AddTag("SD_PracticeZone")
	for index = 1, 9 do
		local x = -36 - 8 * ((index - 1) % 3)
		local z = -47 + 10 * math.floor((index - 1) / 3)
		local target = newPart(practice, "Target_" .. index, Vector3.new(2, 4, 1), CFrame.new(x, 2, z), SOLID)
		target:AddTag("SD_PracticeTarget")
		target:SetAttribute("TargetId", "t" .. index)
		target:SetAttribute("Distance", 12)
		target:SetAttribute("Moving", index == 5)
		target:SetAttribute("RailLength", if index == 5 then 8 else 0)
		target:SetAttribute("Period", if index == 5 then 4 else 0)
	end

	local function stand(tag: string, x: number, z: number, prompt: boolean): Part
		local model = newModel(root, tag, true)
		local body = newPart(model, "Body", Vector3.new(3, 3.5, 2), CFrame.new(x, 1.75, z), SOLID)
		body:AddTag(tag)
		if prompt then
			local proximity = Instance.new("ProximityPrompt")
			proximity.Enabled = false
			proximity.Parent = body
		end
		return body
	end
	stand("SD_QueuePodium", 0, -42, true)
	stand("SD_QueueBoard", 0, -51, false)
	stand("SD_BoxStand", 29.5, -42, true):SetAttribute("BoxId", "snack")
	stand("SD_ShopCounter", 30.5, -21, true)
	stand("SD_CollectionKiosk", 35, 6, true)
	stand("SD_QuestBoard", -17, 26, true)
	stand("SD_DailyStand", 17, 26, true)

	local collection = newModel(root, "Collection", false)
	for slot = 1, 8 do
		local pedestal = newPart(
			collection,
			"Pedestal_" .. slot,
			Vector3.new(3, 0.4, 3),
			CFrame.new(40, 2.2, -3 + 2.5 * slot),
			SOLID
		)
		pedestal:AddTag("SD_CollectionPedestal")
		pedestal:SetAttribute("Slot", slot)
	end
	for slot = 1, 2 do
		local point = newPart(
			root,
			"Return_" .. slot,
			Vector3.new(2, 1, 2),
			CFrame.new(if slot == 1 then -6 else 6, 0.5, -24),
			GHOST
		)
		point:AddTag("SD_ReturnPoint")
		point:SetAttribute("Slot", slot)
	end

	local sign = newPart(root, "SpawnLogo", Vector3.new(24, 0.05, 8), CFrame.new(0, 0.03, 28), SOLID)
	sign:AddTag("SD_Sign")
	sign:SetAttribute("SD_TextKey", "world.spawnLogo")
	local logoGui = Instance.new("SurfaceGui")
	logoGui.Parent = sign
	newLabel(logoGui, "Text")

	for index, zoneId in { "lobby", "squeeze", "practice" } do
		local zone =
			newPart(root, "Audio_" .. zoneId, Vector3.new(10, 10, 10), CFrame.new(0, 100 + 20 * index, 0), GHOST)
		zone:AddTag("SD_AudioZone")
		zone:SetAttribute("ZoneId", zoneId)
		zone:SetAttribute("Priority", index)
	end
	for _, spec in
		{
			{ x = 66, z = 0, size = Vector3.new(4, 60, 132) },
			{ x = -66, z = 0, size = Vector3.new(4, 60, 132) },
			{ x = 0, z = 58, size = Vector3.new(132, 60, 4) },
			{ x = 0, z = -58, size = Vector3.new(132, 60, 4) },
		}
	do
		newPart(root, "Boundary", spec.size, CFrame.new(spec.x, 30, spec.z), WALL):AddTag("SD_Boundary")
	end
	newPart(newFolder(root, "KeepClear"), "Promenade", Vector3.new(20, 23, 40), CFrame.new(0, 12, 0), GHOST):AddTag(
		"SD_KeepClear"
	)

	for _, pad in PADS do
		local pod = newModel(root, "Pod_" .. pad.key, false)
		local gate = newPart(pod, "Gate", Vector3.new(12, 9, 12), CFrame.new(pad.x, 4.5, pad.z), INERT)
		gate.Transparency = 0.55
		gate:AddTag("SD_GripGate")
		gate:SetAttribute("GripTier", pad.tier)

		local panel = newPart(pod, "Sign", Vector3.new(8, 4, 0.4), CFrame.new(pad.x, 11.5, pad.z - 6.8), INERT)
		panel:AddTag("SD_GripSign")
		panel:SetAttribute("GripTier", pad.tier)
		local gui = Instance.new("SurfaceGui")
		gui.Parent = panel
		newLabel(gui, "Title", "grip.pad." .. pad.key)
		newLabel(gui, "Live")

		local giant = newModel(pod, "GiantPad_" .. pad.key, true)
		giant:AddTag("SD_GiantPad")
		giant:SetAttribute("GripTier", pad.tier)
		giant:SetAttribute("PadKey", pad.key)
		local collision = newPart(giant, "Collision", Vector3.new(6.8, 1, 6.8), CFrame.new(pad.x, 0.5, pad.z), WALL)
		collision.CanQuery = true
		collision:AddTag("SD_SqueezeStation")
		collision:SetAttribute("StationId", pad.station)
		collision:SetAttribute("GripTier", pad.tier)
		newPart(newModel(giant, "Body", false), "Base", Vector3.new(8, 1.5, 8), CFrame.new(pad.x, 0.75, pad.z), INERT)
		newPart(newFolder(giant, "Face"), "Eye", Vector3.new(1, 1, 0.2), CFrame.new(pad.x + 4, 1, pad.z), INERT)
	end

	-- §18.5.1 A8: 4 spinning lollipops, the daily gift box (spinBob), the counter gift box and the statue (breathe).
	local decor = newModel(root, "Decor", false)
	for index, spec in
		{
			{ name = "Lollipop1", kind = "spin", x = -55, z = -50 },
			{ name = "Lollipop2", kind = "spin", x = 58, z = -50 },
			{ name = "Lollipop3", kind = "spin", x = -58, z = 50 },
			{ name = "Lollipop4", kind = "spin", x = 58, z = 50 },
			{ name = "GiftBox", kind = "spinBob", x = 17, z = 26 },
			{ name = "GiftBox", kind = "breathe", x = 40, z = -42 },
			{ name = "Statue", kind = "breathe", x = -55, z = 6 },
		}
	do
		local piece = newModel(decor, spec.name, index <= 4)
		newPart(piece, "Body", Vector3.new(1, 4, 1), CFrame.new(spec.x, 3, spec.z), INERT)
		piece:AddTag("SD_Ambient")
		piece:SetAttribute("SD_AmbientKind", spec.kind)
	end

	Generated.mark(root, "lobby", 1)
	return root
end

-- A small arena template that satisfies every arena rule.
local function arenaTree(Generated: any): Model
	local root = newModel(nil, "Arena_CandyCourt", false)
	local origin = newPart(root, "Origin", Vector3.one, CFrame.identity, GHOST)
	root.PrimaryPart = origin

	local geometry = newFolder(root, "Geometry")
	-- One slab out to the barrier walls (X ±38, Z ±54), top Y 0.
	newPart(newFolder(geometry, "Floor"), "Floor", Vector3.new(76, 4, 108), CFrame.new(0, -2, 0), SOLID)
	local cover = newFolder(geometry, "Cover")
	for index, spec in COVER_B do
		for _, sign in { 1, -1 } do
			local piece = newModel(cover, string.format("Cover_%d_%s", index, if sign > 0 then "B" else "A"), true)
			newPart(piece, "Body", spec.size, CFrame.new(sign * spec.x, spec.size.Y / 2, sign * spec.z), SOLID)
		end
	end
	local barriers = newFolder(geometry, "Barriers")
	for _, spec in BARRIERS do
		local wall = newPart(barriers, spec.name, spec.size, CFrame.new(spec.center), WALL)
		pcall(function() -- an unregistered group may be refused; the baseline test then reports the barrier
			wall.CollisionGroup = spec.group
		end)
	end

	local zones = newFolder(root, "Zones")
	for _, spec in ZONES do
		newPart(zones, spec.name, spec.size, CFrame.new(spec.center), GHOST)
	end
	local audio = newPart(zones, "Audio", Vector3.new(120, 60, 152), CFrame.new(0, 15, 0), GHOST)
	audio:AddTag("SD_AudioZone")
	audio:SetAttribute("ZoneId", "arena")
	audio:SetAttribute("Priority", 3)

	local spawns = newFolder(root, "Spawns")
	newPart(spawns, "PadA", Vector3.new(8, 0.1, 8), CFrame.new(0, 0.05, -44) * CFrame.Angles(0, math.pi, 0), INERT)
	newPart(spawns, "PadB", Vector3.new(8, 0.1, 8), CFrame.new(0, 0.05, 44), INERT)

	newPart(newFolder(root, "Decor"), "Apron", Vector3.new(120, 4, 152), CFrame.new(0, -2.05, 0), INERT)
	newFolder(root, "Runtime")

	Generated.mark(root, "arena", 1)
	return root
end

local function firstCoverBody(root: Instance): Part
	local cover = (root :: any).Geometry.Cover
	return (cover:GetChildren()[1] :: Instance):FindFirstChild("Body") :: Part
end

return function(t: Context)
	local Verify, Generated, toolsClone = loadTools()
	local expect = t.expect

	local function lobbyDeps(): any
		return { Strings = FAKE_STRINGS, WorldLayout = fakeLayout() }
	end

	-- Runs `mutate` on a fresh lobby fixture and returns Verify's problems.
	local function lobbyProblems(mutate: ((root: Model) -> ())?, deps: any?): { string }
		local root = lobbyTree(Generated)
		if mutate then
			mutate(root)
		end
		local problems = Verify.verify("lobby", root, deps or lobbyDeps())
		root:Destroy()
		return problems
	end

	local function arenaProblems(mutate: ((root: Model) -> ())?): { string }
		local root = arenaTree(Generated)
		if mutate then
			mutate(root)
		end
		local problems = Verify.verify("arena", root)
		root:Destroy()
		return problems
	end

	local function expectProblem(problems: { string }, needle: string)
		if not hasProblem(problems, needle) then
			error(string.format("expected a problem containing %q, got: %s", needle, table.concat(problems, " | ")))
		end
	end

	local function expectClean(problems: { string })
		if #problems > 0 then
			error("expected no problems, got: " .. table.concat(problems, " | "))
		end
	end

	-- shapes ----------------------------------------------------------------------------------------------------

	-- A marked SD_ShapeLibrary folder holding one RoundedBox of `className`, with the §8.1 #2 flags where settable.
	local function library(className: string): Folder
		local root = Instance.new("Folder")
		root.Name = "SD_ShapeLibrary"
		Generated.mark(root, "shapes", 1)
		local box = Instance.new(className) :: BasePart
		box.Name = "RoundedBox"
		box.Anchored = true
		box.CanCollide = false
		box.CanTouch = false
		box.CanQuery = false
		pcall(function()
			box.Size = Vector3.new(2, 2, 2)
		end)
		box.Parent = root
		return root
	end

	t.test("shapes: the IntersectOperation from IntersectAsync is accepted as the RoundedBox", function()
		local root = library("IntersectOperation")
		local problems = Verify.verify("shapes", root)
		root:Destroy()
		if hasProblem(problems, CLASS_PROBLEM) then
			error("rejected an IntersectOperation: " .. table.concat(problems, "; "))
		end
	end)

	t.test("shapes: any PartOperation is accepted (a UnionOperation too)", function()
		local root = library("UnionOperation")
		local problems = Verify.verify("shapes", root)
		root:Destroy()
		expect.falsy(hasProblem(problems, CLASS_PROBLEM))
	end)

	t.test("shapes: a plain Part named RoundedBox is rejected", function()
		local root = library("Part")
		local problems = Verify.verify("shapes", root)
		root:Destroy()
		expect.truthy(hasProblem(problems, CLASS_PROBLEM))
	end)

	t.test("shapes: a library without a RoundedBox is rejected", function()
		local root = Instance.new("Folder")
		root.Name = "SD_ShapeLibrary"
		Generated.mark(root, "shapes", 1)
		local problems = Verify.verify("shapes", root)
		root:Destroy()
		expect.truthy(hasProblem(problems, "expected exactly one RoundedBox"))
	end)

	-- boxesOverlap ----------------------------------------------------------------------------------------------

	t.test("boxesOverlap: overlapping boxes overlap, touching faces do not", function()
		local size = Vector3.new(2, 2, 2)
		expect.truthy(Verify.boxesOverlap(CFrame.identity, size, CFrame.new(1.5, 0, 0), size, 0.01))
		expect.falsy(Verify.boxesOverlap(CFrame.identity, size, CFrame.new(2, 0, 0), size, 0))
		expect.falsy(Verify.boxesOverlap(CFrame.identity, size, CFrame.new(1.995, 0, 0), size, 0.01))
	end)

	t.test("boxesOverlap: a rotated box is tested by its real faces, not its axis-aligned bounds", function()
		local size = Vector3.new(2, 2, 2)
		local turned = CFrame.new(2.3, 2.3, 0) * CFrame.Angles(0, 0, math.pi / 4)
		-- The bounds overlap (corner region), the oriented boxes do not.
		expect.falsy(Verify.boxesOverlap(CFrame.identity, size, turned, size, 0))
		expect.truthy(
			Verify.boxesOverlap(
				CFrame.identity,
				size,
				CFrame.new(1.9, 0, 0) * CFrame.Angles(0, 0, math.pi / 4),
				size,
				0
			)
		)
	end)

	-- lobby -----------------------------------------------------------------------------------------------------

	t.test("lobby: the baseline fixture passes", function()
		expectClean(lobbyProblems())
	end)

	t.test("lobby: a missing station breaks the exact tag count and the id set", function()
		local problems = lobbyProblems(function(root)
			findTagged(root, "SD_SqueezeStation", "StationId", "squeeze_03"):Destroy()
		end)
		expectProblem(problems, "tag SD_SqueezeStation: expected 9, found 8")
		expectProblem(problems, "no station has StationId squeeze_03")
	end)

	t.test("lobby: a duplicate StationId is reported", function()
		expectProblem(
			lobbyProblems(function(root)
				findTagged(root, "SD_SqueezeStation", "StationId", "squeeze_02"):SetAttribute("StationId", "squeeze_01")
			end),
			"StationId squeeze_01 is used twice"
		)
	end)

	t.test("lobby: a GripTier that differs from WorldLayout is reported", function()
		expectProblem(
			lobbyProblems(function(root)
				findTagged(root, "SD_SqueezeStation", "StationId", "squeeze_04"):SetAttribute("GripTier", 2)
			end),
			"WorldLayout says 1"
		)
	end)

	t.test("lobby: a station WorldLayout does not know is reported", function()
		local deps = lobbyDeps()
		table.remove(deps.WorldLayout.Stations, 9)
		expectProblem(lobbyProblems(nil, deps), "WorldLayout has no GripTier for station squeeze_09")
	end)

	t.test("lobby: WorldLayout as stationTier() plus a GiantPads array is read too", function()
		local tiers = { squeeze_07 = 2, squeeze_08 = 3, squeeze_09 = 4 }
		-- Mixed key fields on purpose: Verify accepts key, padKey or PadKey.
		local pads: { any } = {}
		table.insert(pads, { key = "jelly", collisionTop = 1.0 })
		table.insert(pads, { key = "marshmallow", collisionTop = 1.0 })
		table.insert(pads, { padKey = "royal", collisionTop = 1.0 })
		local layout: any = {
			stationTier = function(id: string): number
				return tiers[id] or 1
			end,
			GiantPads = pads,
		}
		expectClean(lobbyProblems(nil, { Strings = FAKE_STRINGS, WorldLayout = layout }))
	end)

	t.test("lobby: without Strings or WorldLayout the build cannot pass", function()
		local problems = lobbyProblems(nil, {})
		expectProblem(problems, "Shared/Strings cannot load")
		expectProblem(problems, "Shared/World/WorldLayout cannot load")
	end)

	t.test("lobby: practice targets need exactly one moving target and unique ids", function()
		local problems = lobbyProblems(function(root)
			findTagged(root, "SD_PracticeTarget", "TargetId", "t1"):SetAttribute("Moving", true)
			findTagged(root, "SD_PracticeTarget", "TargetId", "t2"):SetAttribute("TargetId", "t3")
		end)
		expectProblem(problems, "expected exactly 1 with Moving = true, found 2")
		expectProblem(problems, "TargetId t3 is used twice")
	end)

	t.test("lobby: a duplicate pedestal Slot is reported", function()
		expectProblem(
			lobbyProblems(function(root)
				findTagged(root, "SD_CollectionPedestal", "Slot", 2):SetAttribute("Slot", 1)
			end),
			"SD_CollectionPedestal: Slot 1 is used twice"
		)
	end)

	t.test("lobby: a Grip gate must be built open (no collide, query or touch)", function()
		expectProblem(
			lobbyProblems(function(root)
				local gate = findTagged(root, "SD_GripGate", "GripTier", 3) :: Part
				gate.CanCollide = true
			end),
			"SD_GripGate (built open)"
		)
	end)

	t.test("lobby: a Grip sign needs exactly one Live label without SD_TextKey", function()
		local keyed = lobbyProblems(function(root)
			local sign = findTagged(root, "SD_GripSign", "GripTier", 2)
			local live = (sign:FindFirstChildWhichIsA("SurfaceGui") :: SurfaceGui):FindFirstChild("Live") :: Instance
			live:SetAttribute("SD_TextKey", "grip.pad.jelly")
		end)
		expectProblem(keyed, "the Live label must not carry SD_TextKey")
		local doubled = lobbyProblems(function(root)
			local sign = findTagged(root, "SD_GripSign", "GripTier", 4)
			newLabel(sign:FindFirstChildWhichIsA("SurfaceGui") :: SurfaceGui, "Live")
		end)
		expectProblem(doubled, "has 2 Live labels, expected exactly 1")
	end)

	t.test("lobby: a giant pad's collision top must match WorldLayout", function()
		expectProblem(
			lobbyProblems(function(root)
				local pad = findTagged(root, "SD_GiantPad", "PadKey", "royal")
				local collision = pad:FindFirstChild("Collision") :: Part
				collision.CFrame = collision.CFrame + Vector3.new(0, 0.2, 0)
			end),
			"collision top is 1.200, WorldLayout says 1.000"
		)
	end)

	t.test("lobby: a giant pad's Body must rise 0.4 above the collision top and be inert", function()
		local low = lobbyProblems(function(root)
			local pad = findTagged(root, "SD_GiantPad", "PadKey", "jelly")
			local base = (pad:FindFirstChild("Body") :: Instance):FindFirstChild("Base") :: Part
			base.Size = Vector3.new(8, 1.2, 8)
			base.CFrame = CFrame.new(base.CFrame.Position.X, 0.6, base.CFrame.Position.Z)
		end)
		expectProblem(low, "is less than 0.4 above the collision top")
		local solid = lobbyProblems(function(root)
			local pad = findTagged(root, "SD_GiantPad", "PadKey", "marshmallow")
			local eye = (pad:FindFirstChild("Face") :: Instance):FindFirstChild("Eye") :: Part
			eye.CanTouch = true
		end)
		expectProblem(solid, "Face: ")
	end)

	t.test("lobby: an SD_TextKey missing from Strings is reported", function()
		expectProblem(
			lobbyProblems(function(root)
				local logo = root:FindFirstChild("SpawnLogo") :: Instance
				logo:SetAttribute("SD_TextKey", "world.noSuchKey")
			end),
			'"world.noSuchKey"'
		)
	end)

	t.test("lobby: a colliding prop inside a keep-clear volume is reported", function()
		expectProblem(
			lobbyProblems(function(root)
				newPart(newModel(root, "Lollipop", false), "Stick", Vector3.new(1, 6, 1), CFrame.new(0, 3, 0), SOLID)
			end),
			"keep-clear: SD_Lobby.Lollipop.Stick reaches into"
		)
	end)

	t.test("lobby: station bodies, floor coverings and touching parts are exempt from keep-clear", function()
		local problems = lobbyProblems(function(root)
			local podium = firstTagged(root, "SD_QueuePodium") :: Part
			podium.CFrame = CFrame.new(0, 1.75, 0) -- a station body
			newPart(root, "Rug", Vector3.new(10, 0.06, 10), CFrame.new(0, 0.03, 5), SOLID) -- top 0.06
			newPart(newModel(root, "Crate", false), "Box", Vector3.new(1, 6, 1), CFrame.new(10.5, 3, 0), SOLID) -- touches X 10
		end)
		expect.falsy(hasProblem(problems, "keep-clear"))
	end)

	t.test("lobby: more than 30 SurfaceGuis or 2,500 parts fail the budget", function()
		local guis = lobbyProblems(function(root)
			local holder = newPart(root, "GuiHolder", Vector3.one, CFrame.new(0, -50, 0), INERT)
			for _ = 1, 27 do -- the fixture has 4
				Instance.new("SurfaceGui").Parent = holder
			end
		end)
		expectProblem(guis, "SurfaceGuis, budget 30")
		local parts = lobbyProblems(function(root)
			local filler = newFolder(root, "Filler")
			for index = 1, 2500 do
				newPart(filler, "P" .. index, Vector3.one, CFrame.new(0, -50, 0), INERT)
			end
		end)
		expectProblem(parts, "parts, budget 2500")
	end)

	t.test("lobby: stand prompts must be disabled and inside an Atomic station model", function()
		local enabled = lobbyProblems(function(root)
			local stand = firstTagged(root, "SD_ShopCounter")
			local proximity = stand:FindFirstChildWhichIsA("ProximityPrompt") :: ProximityPrompt
			proximity.Enabled = true
		end)
		expectProblem(enabled, "is enabled")
		local loose = lobbyProblems(function(root)
			local proximity = Instance.new("ProximityPrompt")
			proximity.Enabled = false
			proximity.Parent = root:FindFirstChild("SpawnLogo")
		end)
		expectProblem(loose, "is not inside an Atomic station model")
	end)

	t.test("lobby: a missing SD_Ambient tag is reported (§18.5.1 A8: exactly 7)", function()
		local problems = lobbyProblems(function(root)
			local decor = root:FindFirstChild("Decor") :: Instance
			(decor:FindFirstChild("Lollipop3") :: Instance):RemoveTag("SD_Ambient")
		end)
		expectProblem(problems, "tag SD_Ambient: expected 7, found 6")
	end)

	t.test("lobby: SD_Ambient decor must be inert and carry a known SD_AmbientKind", function()
		local solid = lobbyProblems(function(root)
			local decor = root:FindFirstChild("Decor") :: Instance
			local statue = decor:FindFirstChild("Statue") :: Instance
			(statue:FindFirstChild("Body") :: Part).CanQuery = true
		end)
		expectProblem(solid, "must not collide, be queried or be touched")
		local unknown = lobbyProblems(function(root)
			local decor = root:FindFirstChild("Decor") :: Instance
			(decor:FindFirstChild("Lollipop1") :: Instance):SetAttribute("SD_AmbientKind", "wobble")
		end)
		expectProblem(unknown, "has SD_AmbientKind wobble")
	end)

	-- arena -----------------------------------------------------------------------------------------------------

	t.test("arena: the baseline fixture passes", function()
		expectClean(arenaProblems())
	end)

	t.test("arena: Origin must be the PrimaryPart and the children complete", function()
		local problems = arenaProblems(function(root)
			root.PrimaryPart = (root :: any).Geometry.Floor.Floor
			local runtime = root:FindFirstChild("Runtime") :: Instance
			runtime:Destroy()
			newFolder(root, "Extra")
		end)
		expectProblem(problems, "PrimaryPart is not Origin")
		expectProblem(problems, "missing Runtime")
		expectProblem(problems, "unexpected child")
	end)

	t.test("arena: Geometry outside Barriers must be queryable and the floor top at Y 0", function()
		local problems = arenaProblems(function(root)
			local floor = (root :: any).Geometry.Floor.Floor :: Part
			floor.CanCollide = false
			floor.CanQuery = false
		end)
		expectProblem(problems, "has CanQuery false")
		expectProblem(problems, "floor:")
	end)

	t.test("arena: cover must be at least 8 tall and at most 8 wide", function()
		local short = arenaProblems(function(root)
			local body = firstCoverBody(root)
			body.Size = Vector3.new(body.Size.X, 7, body.Size.Z)
			body.CFrame = body.CFrame - Vector3.new(0, 0.5, 0)
		end)
		expectProblem(short, "is below 8")
		local wide = arenaProblems(function(root)
			local body = firstCoverBody(root)
			body.Size = Vector3.new(9, body.Size.Y, body.Size.Z)
		end)
		expectProblem(wide, "wider than 8")
	end)

	t.test("arena: cover must be point-symmetric and stay out of the neutral zone", function()
		local moved = arenaProblems(function(root)
			local body = firstCoverBody(root)
			body.CFrame = body.CFrame + Vector3.new(1, 0, 0)
		end)
		expectProblem(moved, "point symmetry")
		local neutral = arenaProblems(function(root)
			for _, piece in (root :: any).Geometry.Cover:GetChildren() do
				local body = piece:FindFirstChild("Body") :: Part
				local position = body.CFrame.Position
				if math.abs(position.Z) == 14 then -- the blocks: move both to Z +-9 (into Z -8..8 by 2)
					body.CFrame = CFrame.new(position.X, position.Y, if position.Z > 0 then 9 else -9)
				end
			end
		end)
		expectProblem(neutral, "reaches into the neutral zone")
	end)

	t.test("arena: cover in the pad-to-pad lane is reported", function()
		expectProblem(
			arenaProblems(function(root)
				local pieces = (root :: any).Geometry.Cover:GetChildren()
				for _, piece in pieces do
					local body = piece:FindFirstChild("Body") :: Part
					local position = body.CFrame.Position
					if math.abs(position.X) == 9 then -- the walls: slide both pairs to X +-5 (into X -6..6)
						body.CFrame = CFrame.new(if position.X > 0 then 5 else -5, position.Y, position.Z)
					end
				end
			end),
			"blocks the pad-to-pad lane"
		)
	end)

	t.test("arena: barriers must be invisible, colliding and unqueryable; dividers in SD_Divider", function()
		local problems = arenaProblems(function(root)
			local barriers = (root :: any).Geometry.Barriers
			local wall = barriers.WallXPos :: Part
			wall.CanQuery = true
			local divider = barriers.DividerA :: Part
			divider.CollisionGroup = "Default"
		end)
		expectProblem(problems, "Barriers: ")
		expectProblem(problems, "expected 2 parts in collision group SD_Divider, found 1")
		expectProblem(problems, "expected SD_Divider")
	end)

	-- Roblox ignores CanQuery = false on a colliding part, so a wall left in Default would stop projectile rays.
	t.test("arena: walls and ceiling must be in SD_Barrier (projectile rays skip them)", function()
		local problems = arenaProblems(function(root)
			local barriers = (root :: any).Geometry.Barriers
			local wall = barriers.WallXNeg :: Part
			wall.CollisionGroup = "Default"
		end)
		expectProblem(problems, "expected 5 parts in collision group SD_Barrier, found 4")
		expectProblem(problems, "expected SD_Barrier")
	end)

	-- §5.3: dividers that stop short of the side walls leave a way around their ends into the neutral zone.
	t.test("arena: 72-wide dividers that stop short of the walls are reported", function()
		local problems = arenaProblems(function(root)
			local barriers = (root :: any).Geometry.Barriers
			for _, name in { "DividerA", "DividerB" } do
				local divider = barriers[name] :: Part
				divider.Size = Vector3.new(72, 40, 1)
			end
		end)
		expectProblem(problems, "Barriers: no divider")
	end)

	-- The apron is decor: without floor behind the rails, a player who hops a rail falls into the void.
	t.test("arena: the strip between the rails and the walls needs a colliding floor", function()
		local problems = arenaProblems(function(root)
			local floor = (root :: any).Geometry.Floor.Floor :: Part
			floor.Size = Vector3.new(72, 4, 104) -- the playable area only
		end)
		expectProblem(problems, "floor:")
	end)

	t.test("templateLeftovers: a template SpawnLocation and a floor-plane Baseplate are reported", function()
		local place = Instance.new("Folder")
		local lobby = newModel(place, "SD_Lobby", false)
		-- The lobby's own spawn and floor are fine.
		local ownSpawn = Instance.new("SpawnLocation")
		ownSpawn.Size = Vector3.new(12, 1, 8)
		ownSpawn.CFrame = CFrame.new(0, -0.45, 40)
		ownSpawn.Parent = lobby
		newPart(lobby, "BaseSlab", Vector3.new(148, 2, 132), CFrame.new(0, -1, 0), SOLID)
		expect.deepEqual(Verify.templateLeftovers(place, lobby), {})
		-- The place template: a 512 × 20 × 512 Baseplate with its top at Y 0, and a SpawnLocation.
		newPart(place, "Baseplate", Vector3.new(512, 20, 512), CFrame.new(0, -10, 0), SOLID)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "SpawnLocation"
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = CFrame.new(0, 0.5, 0)
		spawn.Parent = place
		-- A small part on the floor plane (the team's decor) is not a leftover.
		newPart(place, "Rug", Vector3.new(4, 0.2, 4), CFrame.new(10, -0.1, 10), SOLID)
		local lines = Verify.templateLeftovers(place, lobby)
		place:Destroy()
		expect.equal(#lines, 2)
		expectProblem(lines, "Baseplate has its top at Y 0.00")
		expectProblem(lines, "is a SpawnLocation outside the lobby")
	end)

	t.test("arena: zones, pads and Runtime follow the contract", function()
		local problems = arenaProblems(function(root)
			local halfA = (root :: any).Zones.HalfA :: Part
			halfA.Size = Vector3.new(72, 55, 40)
			local padB = (root :: any).Spawns.PadB :: Part
			padB.CFrame = CFrame.new(0, 0.05, 44) * CFrame.Angles(0, math.pi, 0) -- faces +Z instead of -Z
			newFolder(root:FindFirstChild("Runtime"), "Leftover")
		end)
		expectProblem(problems, "Zones/HalfA spans Z")
		expectProblem(problems, "Spawns/PadB faces")
		expectProblem(problems, "Runtime must be empty")
	end)

	t.test("arena: Decor must be inert and nothing forbidden may appear", function()
		local problems = arenaProblems(function(root)
			local apron = (root :: any).Decor.Apron :: Part
			apron.CanQuery = true
			apron.CanCollide = true
			Instance.new("ProximityPrompt").Parent = root:FindFirstChild("Decor")
			local spawn = Instance.new("SpawnLocation")
			spawn.Parent = root:FindFirstChild("Runtime")
			local floor = (root :: any).Geometry.Floor.Floor :: Part
			floor.Material = Enum.Material.Neon
		end)
		expectProblem(problems, "Decor part")
		expectProblem(problems, "no ProximityPrompts allowed")
		expectProblem(problems, "no SpawnLocations allowed")
		expectProblem(problems, "no Neon in the arena")
	end)

	t.test("arena: more than 400 parts fail the budget", function()
		expectProblem(
			arenaProblems(function(root)
				local runtime = root:FindFirstChild("Decor") :: Instance
				for index = 1, 400 do
					newPart(runtime, "P" .. index, Vector3.one, CFrame.new(0, -20, 100), INERT)
				end
			end),
			"parts, budget 400"
		)
	end)

	toolsClone:Destroy()
end
