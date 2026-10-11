--!strict
-- WorldService_Test: unit tests for ServerScriptService.Server.Services.WorldService.
-- Server only (ServerStorage.UnitTest). A fake PhysicsService and in-memory world trees are used, so the place's
-- collision groups, Workspace attributes and world never change (init() is never called here).
-- Contract (DESIGN §5.3, §1.7, §2.9):
--   * the groups SD_Characters, SD_Divider, SD_Barrier and SD_Cosmetic get registered (once; existing ones are kept);
--   * SD_Cosmetic collides with nothing, itself and any other registered group included;
--   * SD_Divider and SD_Barrier (the arena's walls and ceiling) collide only with SD_Characters, so Default-group
--     projectile rays skip them;
--   * SD_Characters still collides with Default and with itself;
--   * a registration failure (e.g. the group limit) is reported as a problem, never thrown;
--   * the generated roots (Workspace.SD_Lobby "lobby", ServerStorage.SD_Templates.Arena_CandyCourt "arena") count
--     only with their generator marks; a missing one is reported; worldReady() needs both;
--   * station(id) / stations(tag) / zones come only from the lobby root.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
}

local DEFAULT = "Default"
local CHARACTERS = "SD_Characters"
local DIVIDER = "SD_Divider"
local BARRIER = "SD_Barrier"
local COSMETIC = "SD_Cosmetic"

-- PhysicsService stand-in: every pair collides until set otherwise (the engine default for new groups).
local function fakePhysics(preRegistered: { string }?, maxGroups: number?)
	local registered: { string } = { DEFAULT }
	local initial: { string } = preRegistered or {}
	for _, name in initial do
		table.insert(registered, name)
	end
	local pairs_: { [string]: boolean } = {}
	local registerCalls: { string } = {}
	local function key(a: string, b: string): string
		return if a < b then a .. "|" .. b else b .. "|" .. a
	end
	local fake = {}
	function fake.IsCollisionGroupRegistered(_: any, name: string): boolean
		return table.find(registered, name) ~= nil
	end
	function fake.RegisterCollisionGroup(_: any, name: string)
		table.insert(registerCalls, name)
		if maxGroups and #registered >= maxGroups then
			error("too many collision groups")
		end
		table.insert(registered, name)
	end
	function fake.CollisionGroupSetCollidable(_: any, a: string, b: string, collidable: boolean)
		assert(table.find(registered, a) and table.find(registered, b), "unregistered group")
		pairs_[key(a, b)] = collidable
	end
	function fake.GetRegisteredCollisionGroups(_: any): { any }
		local list = {}
		for index, name in registered do
			table.insert(list, { name = name, id = index - 1, mask = 0 })
		end
		return list
	end
	local function collides(a: string, b: string): boolean
		local value = pairs_[key(a, b)]
		return if value == nil then true else value
	end
	return fake, collides, registerCalls
end

return function(t: Context)
	local WorldService = t.requireServer("Services/WorldService")
	local expect = t.expect

	t.test("registers the three §5.3 groups and applies their collidability", function()
		local physics, collides = fakePhysics()
		local problems = WorldService.applyCollisionRules(physics)
		expect.deepEqual(problems, {})
		for _, name in { CHARACTERS, DIVIDER, BARRIER, COSMETIC } do
			expect.truthy(physics:IsCollisionGroupRegistered(name))
		end
		expect.equal(WorldService.CollisionGroups.Barrier, BARRIER)
		-- Cosmetic: nothing.
		for _, other in { DEFAULT, CHARACTERS, DIVIDER, BARRIER, COSMETIC } do
			expect.falsy(collides(COSMETIC, other))
		end
		-- Divider and barrier: characters only (a Default-group projectile ray passes them).
		for _, group in { DIVIDER, BARRIER } do
			expect.truthy(collides(group, CHARACTERS))
			expect.falsy(collides(group, DEFAULT))
			expect.falsy(collides(group, DIVIDER))
			expect.falsy(collides(group, BARRIER))
		end
		-- Characters: like Default otherwise.
		expect.truthy(collides(CHARACTERS, DEFAULT))
		expect.truthy(collides(CHARACTERS, CHARACTERS))
		expect.truthy(collides(DEFAULT, DEFAULT))
	end)

	t.test("keeps existing groups and also isolates cosmetic/divider from other registered groups", function()
		local physics, collides, registerCalls = fakePhysics({ COSMETIC, "SomeOtherGroup" })
		local problems = WorldService.applyCollisionRules(physics)
		expect.deepEqual(problems, {})
		expect.equal(table.find(registerCalls, COSMETIC), nil)
		expect.falsy(collides(COSMETIC, "SomeOtherGroup"))
		expect.falsy(collides(DIVIDER, "SomeOtherGroup"))
		expect.falsy(collides(BARRIER, "SomeOtherGroup"))
		-- Running it again changes nothing and registers nothing new.
		local before = #registerCalls
		expect.deepEqual(WorldService.applyCollisionRules(physics), {})
		expect.equal(#registerCalls, before)
	end)

	t.test("reports a registration failure instead of throwing", function()
		local physics = fakePhysics(nil, 2) -- room for one more group only
		local problems = WorldService.applyCollisionRules(physics)
		expect.truthy(#problems >= 1)
		expect.truthy(string.find(problems[1], "SD_", 1, true) ~= nil)
	end)

	-- In-memory world: a "Workspace" folder with the lobby root and a "ServerStorage" folder with the arena template.
	-- Nothing is parented to the place; tags and attributes work on unparented instances.
	local function mark(root: Instance, generatorId: string)
		root:AddTag("SD_Generated")
		root:SetAttribute("SD_GeneratorId", generatorId)
		root:SetAttribute("SD_GeneratorVersion", 1)
	end

	local function box(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe
		part.Parent = parent
		return part
	end

	local function fakeWorld(): (Folder, Folder, Model, Model)
		local workspaceLike = Instance.new("Folder")
		workspaceLike.Name = "Workspace"
		local serverStorageLike = Instance.new("Folder")
		serverStorageLike.Name = "ServerStorage"
		local lobby = Instance.new("Model")
		lobby.Name = "SD_Lobby"
		mark(lobby, "lobby")
		lobby.Parent = workspaceLike
		local templates = Instance.new("Folder")
		templates.Name = "SD_Templates"
		templates.Parent = serverStorageLike
		local arena = Instance.new("Model")
		arena.Name = "Arena_CandyCourt"
		mark(arena, "arena")
		arena.Parent = templates
		return workspaceLike, serverStorageLike, lobby, arena
	end

	t.test("findRoots finds the marked lobby and arena template", function()
		local workspaceLike, serverStorageLike, lobby, arena = fakeWorld()
		local roots = WorldService.findRoots(workspaceLike, serverStorageLike)
		expect.equal(roots.lobby, lobby)
		expect.equal(roots.arena, arena)
		expect.deepEqual(roots.missing, {})
		workspaceLike:Destroy()
		serverStorageLike:Destroy()
	end)

	t.test("findRoots reports a missing, unmarked or foreign root as missing", function()
		local workspaceLike, serverStorageLike, lobby, arena = fakeWorld()
		lobby:RemoveTag("SD_Generated") -- a hand-made SD_Lobby is not the generated root
		arena:SetAttribute("SD_GeneratorId", "shapes") -- another generator's root
		local roots = WorldService.findRoots(workspaceLike, serverStorageLike)
		expect.equal(roots.lobby, nil)
		expect.equal(roots.arena, nil)
		expect.deepEqual(roots.missing, { "lobby", "arena" })
		-- No SD_Templates folder at all.
		local empty = Instance.new("Folder")
		expect.deepEqual(WorldService.findRoots(empty, empty).missing, { "lobby", "arena" })
		empty:Destroy()
		workspaceLike:Destroy()
		serverStorageLike:Destroy()
	end)

	t.test("findRoots accepts a marked root under another name", function()
		local workspaceLike, serverStorageLike, lobby = fakeWorld()
		lobby.Name = "SD_Lobby_Renamed"
		local roots = WorldService.findRoots(workspaceLike, serverStorageLike)
		expect.equal(roots.lobby, lobby)
		workspaceLike:Destroy()
		serverStorageLike:Destroy()
	end)

	t.test("worldReady() needs both roots; lookups come only from the lobby root", function()
		local workspaceLike, serverStorageLike, lobby, arena = fakeWorld()
		local mats = Instance.new("Folder")
		mats.Name = "Squeeze"
		mats.Parent = lobby
		for _, id in { "squeeze_02", "squeeze_01" } do
			local mat = box(id, Vector3.new(8, 0.3, 8), CFrame.new(), mats)
			mat:AddTag("SD_SqueezeStation")
			mat:SetAttribute("StationId", id)
		end
		-- A tagged instance outside the lobby root is never returned.
		local stray = box("Stray", Vector3.one, CFrame.new(), workspaceLike)
		stray:AddTag("SD_SqueezeStation")
		stray:SetAttribute("StationId", "squeeze_09")

		WorldService.useWorld(lobby, nil)
		expect.equal(WorldService.worldReady(), false)
		expect.equal(WorldService.lobby(), lobby)
		expect.equal(WorldService.arenaTemplate(), nil)
		WorldService.useWorld(lobby, arena)
		expect.equal(WorldService.worldReady(), true)

		expect.equal((WorldService.station("squeeze_01") :: Instance).Name, "squeeze_01")
		expect.equal(WorldService.station("squeeze_09"), nil)
		local list = WorldService.stations("SD_SqueezeStation")
		expect.equal(#list, 2)
		expect.equal(list[1].Name, "squeeze_01") -- ordered by StationId
		expect.equal(list[2].Name, "squeeze_02")
		table.clear(list) -- a copy: the index is untouched
		expect.equal(#WorldService.stations("SD_SqueezeStation"), 2)
		expect.deepEqual(WorldService.stations("SD_NoSuchTag"), {})

		WorldService.useWorld(nil, nil)
		expect.equal(WorldService.worldReady(), false)
		expect.equal(WorldService.station("squeeze_01"), nil)
		workspaceLike:Destroy()
		serverStorageLike:Destroy()
	end)

	t.test("zones: oriented boxes and model bounding boxes contain points", function()
		local workspaceLike, serverStorageLike, lobby, arena = fakeWorld()
		-- Practice throw box X -24..-16, Z -54..-20, Y 0..12 (§7.6).
		local zone = box("PracticeZone", Vector3.new(8, 12, 34), CFrame.new(-20, 6, -37), lobby)
		zone:AddTag("SD_PracticeZone")
		-- A box turned 45 degrees about Y.
		local turned =
			box("Turned", Vector3.new(10, 2, 2), CFrame.new(50, 1, 0) * CFrame.Angles(0, math.rad(45), 0), lobby)
		expect.truthy(WorldService.containsPoint(turned, Vector3.new(50 + 3, 1, -3)))
		expect.falsy(WorldService.containsPoint(turned, Vector3.new(50 + 3, 1, 3)))
		expect.falsy(WorldService.containsPoint(Instance.new("Folder"), Vector3.zero))

		WorldService.useWorld(lobby, arena)
		expect.equal(WorldService.zoneAt(Vector3.new(-20, 3, -37), "SD_PracticeZone"), zone)
		expect.equal(WorldService.zoneAt(Vector3.new(-20, 3, -10), "SD_PracticeZone"), nil)
		expect.equal(WorldService.zoneAt(Vector3.new(-20, 13, -37), "SD_PracticeZone"), nil)
		expect.equal(WorldService.zoneAt(Vector3.zero, "SD_NoSuchTag"), nil)
		WorldService.useWorld(nil, nil)
		workspaceLike:Destroy()
		serverStorageLike:Destroy()
	end)
end
