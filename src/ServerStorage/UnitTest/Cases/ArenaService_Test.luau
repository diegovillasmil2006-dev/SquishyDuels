--!strict
-- ArenaService_Test: unit tests for ServerScriptService.Server.Services.ArenaService.
-- Server only (ServerStorage.UnitTest). Edit mode: init()/start() are never called; the pool runs on an in-memory
-- template (built here from WorldLayout.Arena, like ArenaBuilder's tree), an unparented container folder and a
-- FakeClock, so nothing is parented into the place.
-- Contract (DESIGN §5.3, §7.8):
--   * grid: slot i sits at Config.Duel.Arena.SlotOrigins[i] for i = 1..min(MaxSlots, #SlotOrigins); the slots'
--     footprints (apron) never overlap each other or the lobby, and every slot is inside the 1024-stud streaming
--     radius of the lobby centre;
--   * the lease is the longest possible match plus LeaseGraceSeconds;
--   * a pad CFrame is lookAt(pad.Position, + LookVector) with world up, never the rolled pad.CFrame;
--   * zones: boxContains with a margin widens X/Z only; inOwnHalf / inBounds / zoneAt follow the §5.3 Z ranges;
--   * pool: lazy clones pivoted to their slot, at most maxSlots in use, release clears Runtime and fires
--     SlotReleased, a released slot is reused, the lease janitor fires LeaseExpired once for an expired slot and
--     leaves the release to its owner (a slot without a matchId at once, a slot still held after LeaseDrainSeconds by
--     the janitor), handoff hands the same slot to the next acquire, a missing or incomplete template disables the
--     pool;
--   * the projectile RaycastParams / OverlapParams include Geometry minus Barriers, in the Default group;
--   * several arenas (phase 4 spec 2026-10-11 §5.3, D7): pickArena is an equal-chance roll over the usable arena ids
--     (sorted; one arena needs no roll); acquire takes a free clone of the picked arena, else clones it into the lowest
--     uncloned slot, else re-clones the lowest free slot of another arena (old model destroyed, zones and pads read
--     again); a broken arena leaves the rotation while the others keep working; view().arenaId names the arena;
--     debugForceArena pins the pick (Studio); every arena's apron fits the slot grid.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local ROLL_UP = CFrame.Angles(0, 0, math.pi / 2) -- how ArenaBuilder rolls a cylinder pad about its look axis

return function(t: Context)
	local expect = t.expect
	local ArenaService = t.requireServer("Services/ArenaService")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local FakeClock = t.requireFake("FakeClock")
	local FakeRng = t.requireFake("FakeRng")
	local MapData = t.requireShared("Maps/MapData")
	local Arena = WorldLayout.Arena

	local function part(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.Parent = parent
		return p
	end

	local function folder(name: string, parent: Instance): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
		return f
	end

	-- An in-memory copy of the template's gameplay tree (Origin at the world origin, like the template).
	local function makeTemplate(options: { noZones: boolean? }?): Model
		local model = Instance.new("Model")
		model.Name = Arena.templateName
		local origin = part("Origin", Vector3.one, CFrame.identity, model)
		model.PrimaryPart = origin
		local geometry = folder("Geometry", model)
		local floor = folder("Floor", geometry)
		part("Band1", Vector3.new(72, 4, 8), CFrame.new(0, -2, 0), floor)
		local cover = folder("Cover", geometry)
		part("Cover_B_Wall1", Vector3.new(6, 8, 2.5), CFrame.new(9, 4, 20), cover)
		folder("Rails", geometry)
		folder("Markings", geometry)
		local barriers = folder("Barriers", geometry)
		for _, volume in Arena.barriers do
			part(volume.name, volume.size, CFrame.new(volume.position), barriers)
		end
		if not (options and options.noZones) then
			local zones = folder("Zones", model)
			for name, volume in Arena.zones do
				part(name, volume.size, CFrame.new(volume.position), zones)
			end
		end
		local spawns = folder("Spawns", model)
		for _, pad in { Arena.pads.A, Arena.pads.B } do
			local cf = CFrame.lookAt(pad.position, pad.position + pad.facing) * ROLL_UP
			local p = part(pad.name, Vector3.new(pad.height, pad.diameter, pad.diameter), cf, spawns)
			p.Shape = Enum.PartType.Cylinder
		end
		folder("Runtime", model)
		model:AddTag("SD_Generated")
		return model
	end

	-- Records what ArenaService logs instead of printing it.
	local logged: { string } = {}
	local quietLog = {
		warn = function(_self: any, ...: any)
			table.insert(logged, "warn " .. table.concat({ ... }, " "))
		end,
		error = function(_self: any, ...: any)
			table.insert(logged, "error " .. table.concat({ ... }, " "))
		end,
	}

	-- Fresh pool on a fresh template; returns (template, container, clock).
	local function freshPool(options: { noZones: boolean? }?): (Model, Folder, any)
		local clock = FakeClock.new(1000)
		local template = makeTemplate(options)
		local container = Instance.new("Folder")
		table.clear(logged)
		ArenaService.useTemplate(template, container, clock.now, quietLog)
		return template, container, clock
	end

	local function teardown(template: Instance, container: Instance)
		ArenaService.useTemplate(nil, nil)
		template:Destroy()
		container:Destroy()
	end

	t.test("grid: one origin per slot, nil outside 1..maxSlots", function()
		local maxSlots = ArenaService.maxSlots()
		expect.equal(maxSlots, math.min(Config.Duel.Arena.MaxSlots, #Config.Duel.Arena.SlotOrigins))
		for i = 1, maxSlots do
			expect.equal(ArenaService.slotOrigin(i), Config.Duel.Arena.SlotOrigins[i])
		end
		expect.equal(ArenaService.slotOrigin(0), nil)
		expect.equal(ArenaService.slotOrigin(maxSlots + 1), nil)
		expect.equal(ArenaService.slotOrigin(1.5), nil)
	end)

	-- 2026-10-30: Diego's 1v1 sky maps float far from the lobby (Y 300, the row south of the Team maps), like his old
	-- Team / Free for All maps did; the old "inside the lobby's streaming radius" rule went with the old arenas
	-- (DuelService streams the pad in before each teleport).
	t.test("grid: slot footprints never overlap each other or the lobby", function()
		local halfX, halfZ = Arena.apron.size.X / 2, Arena.apron.size.Z / 2
		local lobbyHalfX, lobbyHalfZ = WorldLayout.Lobby.baseSlab.size.X / 2, WorldLayout.Lobby.baseSlab.size.Z / 2
		local maxSlots = ArenaService.maxSlots()
		for i = 1, maxSlots do
			local a = ArenaService.slotOrigin(i) :: Vector3
			-- Clear of the lobby slab.
			local clearOfLobby = math.abs(a.X) >= halfX + lobbyHalfX or math.abs(a.Z) >= halfZ + lobbyHalfZ
			if not clearOfLobby then
				error(`slot {i} overlaps the lobby`)
			end
			for j = i + 1, maxSlots do
				local b = ArenaService.slotOrigin(j) :: Vector3
				local apart = math.abs(a.X - b.X) >= 2 * halfX or math.abs(a.Z - b.Z) >= 2 * halfZ
				if not apart then
					error(`slots {i} and {j} overlap`)
				end
			end
		end
	end)

	t.test("lease = longest match + grace", function()
		local rules = Config.Duel.Rules
		local expected = rules.PreparingTimeoutSeconds
			+ rules.PositioningTimeoutSeconds
			+ rules.CountdownSeconds
			+ rules.MatchSeconds
			+ rules.SuddenDeathSeconds
			+ rules.ResultSeconds
			+ Config.Duel.Positioning.StreamAroundTimeoutSeconds
			+ Config.Duel.Arena.LeaseGraceSeconds
		expect.near(ArenaService.leaseSeconds(), expected)
	end)

	t.test("padLookAt: rolled cylinder -> pad position, its facing, world up", function()
		local position = Vector3.new(10, 0.05, -44)
		local rolled = CFrame.lookAt(position, position + Vector3.new(0, 0, 1)) * ROLL_UP
		expect.near(rolled.UpVector.Y, 0, 1e-4) -- the trap: pad.CFrame is not upright
		local cf = ArenaService.padLookAt(rolled)
		expect.near((cf.Position - position).Magnitude, 0, 1e-4)
		expect.near(cf.UpVector.Y, 1, 1e-4)
		expect.near(cf.LookVector.Z, 1, 1e-4)
	end)

	t.test("boxContains: margin widens X and Z only", function()
		local cf, size = CFrame.new(0, 0, 0), Vector3.new(10, 10, 10)
		expect.truthy(ArenaService.boxContains(cf, size, Vector3.new(4.9, 0, 0)))
		expect.falsy(ArenaService.boxContains(cf, size, Vector3.new(6, 0, 0)))
		expect.truthy(ArenaService.boxContains(cf, size, Vector3.new(6, 0, 6), 2))
		expect.falsy(ArenaService.boxContains(cf, size, Vector3.new(0, 6, 0), 2))
	end)

	t.test("acquire clones lazily, pivots to the slot origin and reads zones and pads", function()
		local template, container = freshPool()
		expect.truthy(ArenaService.available())
		expect.equal(ArenaService.clonedCount(), 0)
		local slot = ArenaService.acquire("match-1")
		expect.truthy(slot)
		expect.equal(slot.index, 1)
		expect.equal(slot.matchId, "match-1")
		expect.equal(slot.model.Parent, container)
		expect.falsy(slot.model:HasTag("SD_Generated"))
		local origin = Config.Duel.Arena.SlotOrigins[1]
		expect.near((slot.origin.Position - origin).Magnitude, 0, 1e-3)
		expect.near(slot.floorY, origin.Y, 1e-3)
		expect.near(slot.killY, origin.Y + Config.Duel.Rules.OutOfBounds.KillYOffset, 1e-3)
		-- Pads: upright, at the template pad positions moved to the slot, facing each other.
		local padA = slot.pads.A
		expect.near((padA.Position - (origin + Arena.pads.A.position)).Magnitude, 0, 1e-3)
		expect.near(padA.UpVector.Y, 1, 1e-4)
		expect.near(padA.LookVector.Z, 1, 1e-4)
		expect.near(slot.pads.B.LookVector.Z, -1, 1e-4)
		expect.equal(ArenaService.padCFrame(slot, "PadB"), slot.pads.B)
		local placed = ArenaService.placementCFrame(slot, "A", 3)
		expect.near(placed.Position.Y - padA.Position.Y, 3, 1e-4)
		-- Zones follow the clone.
		expect.truthy(ArenaService.inOwnHalf(slot, "A", origin + Vector3.new(0, 3, -40)))
		expect.falsy(ArenaService.inOwnHalf(slot, "A", origin + Vector3.new(0, 3, -7)))
		expect.truthy(ArenaService.inOwnHalf(slot, "A", origin + Vector3.new(0, 3, -7), 2))
		expect.falsy(ArenaService.inOwnHalf(slot, "B", origin + Vector3.new(0, 3, -40)))
		expect.equal(ArenaService.zoneAt(slot, origin + Vector3.new(0, 3, 0)), "Neutral")
		expect.equal(ArenaService.zoneAt(slot, origin + Vector3.new(0, 3, 30)), "HalfB")
		expect.equal(ArenaService.zoneAt(slot, origin + Vector3.new(37, 3, 30)), "Bounds")
		expect.equal(ArenaService.zoneAt(slot, origin + Vector3.new(0, 3, 70)), nil)
		expect.truthy(ArenaService.inBounds(slot, origin + Vector3.new(0, 3, 53)))
		expect.falsy(ArenaService.inBounds(slot, origin + Vector3.new(0, 3, 60)))
		teardown(template, container)
	end)

	t.test("projectile query params: Geometry minus Barriers, Include, Default group", function()
		local template, container = freshPool()
		local slot = ArenaService.acquire()
		for _, params in { ArenaService.raycastParams(slot), ArenaService.overlapParams(slot) } do
			expect.equal(params.FilterType, Enum.RaycastFilterType.Include)
			expect.equal(params.CollisionGroup, "Default")
			local names = {}
			for _, instance in params.FilterDescendantsInstances do
				names[instance.Name] = true
				expect.truthy(instance:IsDescendantOf(slot.geometry))
			end
			expect.falsy(names.Barriers)
			expect.truthy(names.Floor)
			expect.truthy(names.Cover)
			expect.truthy(names.Rails)
			expect.truthy(names.Markings)
		end
		teardown(template, container)
	end)

	t.test("view(): the DuelState arena payload", function()
		local template, container = freshPool()
		local slot = ArenaService.acquire()
		local view = ArenaService.view(slot)
		expect.equal(view.slot, 1)
		expect.near(view.floorY, slot.floorY)
		expect.equal(view.pads.PadA, slot.pads.A)
		expect.equal(view.pads.PadB, slot.pads.B)
		for _, name in { "HalfA", "Neutral", "HalfB", "Bounds" } do
			expect.truthy(view.zones[name])
			expect.equal(view.zones[name].size, slot.zones[name].size)
		end
		teardown(template, container)
	end)

	t.test("pool: at most maxSlots in use; release clears Runtime, fires SlotReleased and is reused", function()
		local template, container = freshPool()
		local maxSlots = ArenaService.maxSlots()
		local taken = {}
		for i = 1, maxSlots do
			local slot = ArenaService.acquire()
			expect.truthy(slot)
			expect.equal(slot.index, i)
			table.insert(taken, slot)
		end
		expect.equal(ArenaService.acquire(), nil)
		expect.equal(ArenaService.freeCount(), 0)
		expect.equal(ArenaService.inUseCount(), maxSlots)
		local second = taken[2]
		local leftover = Instance.new("Part")
		leftover.Parent = second.runtime
		local released = nil
		local connection = ArenaService.SlotReleased:connect(function(slot: any)
			released = slot
		end)
		ArenaService.release(second)
		connection:disconnect()
		expect.equal(released, second)
		expect.equal(#second.runtime:GetChildren(), 0)
		expect.falsy(second.inUse)
		expect.equal(second.matchId, nil)
		expect.equal(ArenaService.freeCount(), 1)
		ArenaService.release(second) -- idempotent
		expect.equal(ArenaService.freeCount(), 1)
		local again = ArenaService.acquire()
		expect.equal(again, second)
		expect.equal(ArenaService.clonedCount(), maxSlots)
		teardown(template, container)
	end)

	t.test("handoff: the next acquire returns the handed-off slot", function()
		local template, container = freshPool()
		local slot = ArenaService.acquire()
		ArenaService.handoff(slot)
		expect.equal(ArenaService.acquire("m-7"), slot)
		expect.equal(slot.matchId, "m-7")
		expect.equal(ArenaService.inUseCount(), 1)
		local other = ArenaService.acquire()
		expect.truthy(other ~= slot)
		ArenaService.handoff(slot)
		ArenaService.handoff(nil)
		expect.truthy(ArenaService.acquire() ~= slot)
		teardown(template, container)
	end)

	t.test("lease janitor: LeaseExpired fires once; the owner releases the slot after returning its players", function()
		local template, container, clock = freshPool()
		local slot = ArenaService.acquire("late-match")
		local keep = ArenaService.acquire("fine-match")
		expect.near(slot.leaseUntil, clock.now() + ArenaService.leaseSeconds())
		ArenaService.renewLease(keep, ArenaService.leaseSeconds() * 3)
		local expiredIds: { string? } = {}
		local connection = ArenaService.LeaseExpired:connect(function(_slot: any, matchId: string?)
			table.insert(expiredIds, matchId)
		end)
		expect.equal(#ArenaService.janitorStep(clock.now() + 1), 0)
		local late = clock.now() + ArenaService.leaseSeconds() + 1
		local expired = ArenaService.janitorStep(late)
		expect.equal(#expired, 1)
		expect.equal(expired[1], slot)
		expect.deepEqual(expiredIds, { "late-match" })
		expect.equal(#logged, 1)
		expect.truthy(string.find(logged[1], "lease expired", 1, true))
		-- The voided match is still returning its players: the slot stays taken, so no new pair can land there.
		expect.truthy(slot.inUse)
		expect.equal(ArenaService.freeCount(), ArenaService.maxSlots() - 2)
		expect.equal(#ArenaService.janitorStep(late + Config.Duel.Arena.JanitorIntervalSeconds), 0)
		expect.deepEqual(expiredIds, { "late-match" }) -- fired once
		expect.truthy(slot.inUse)
		-- The owner releases it when its players are back.
		ArenaService.release(slot)
		connection:disconnect()
		expect.falsy(slot.inUse)
		expect.truthy(keep.inUse)
		teardown(template, container)
	end)

	t.test(
		"lease janitor: a slot nobody releases is freed after LeaseDrainSeconds; no matchId frees at once",
		function()
			local template, container, clock = freshPool()
			local stuck = ArenaService.acquire("stuck-match")
			local orphan = ArenaService.acquire(nil)
			local late = clock.now() + ArenaService.leaseSeconds() + 1
			local expired = ArenaService.janitorStep(late)
			expect.equal(#expired, 2)
			expect.falsy(orphan.inUse) -- no owner to wait for
			expect.truthy(stuck.inUse)
			expect.equal(#ArenaService.janitorStep(late + Config.Duel.Arena.LeaseDrainSeconds), 0)
			expect.truthy(stuck.inUse) -- not past the drain yet
			expect.equal(#ArenaService.janitorStep(late + Config.Duel.Arena.LeaseDrainSeconds + 1), 0)
			expect.falsy(stuck.inUse)
			expect.truthy(string.find(logged[#logged], "still held", 1, true))
			-- A released slot leases afresh.
			local again = ArenaService.acquire("next-match")
			expect.truthy(again)
			expect.equal(again.drainUntil, nil)
			teardown(template, container)
		end
	)

	t.test("no template or an incomplete one disables the pool", function()
		ArenaService.useTemplate(nil, nil)
		expect.falsy(ArenaService.available())
		expect.equal(ArenaService.freeCount(), 0)
		expect.equal(ArenaService.acquire(), nil)
		local template, container = freshPool({ noZones = true })
		expect.truthy(ArenaService.available())
		expect.equal(ArenaService.acquire(), nil)
		expect.falsy(ArenaService.available())
		expect.equal(#container:GetChildren(), 0)
		expect.equal(#logged, 1)
		expect.truthy(string.find(logged[1], "Zones/HalfA", 1, true) or string.find(logged[1], "Zones/", 1, true))
		teardown(template, container)
	end)

	-- Several arenas (phase 4 spec §5.3, D7) --------------------------------------------------------------------------

	-- Fresh pool on one in-memory template per arena id (each carries SD_ArenaId, so a clone shows which arena it is);
	-- `rolls` scripts the pick (FakeRng: each NextInteger returns the next value), `broken` ids lack their zones.
	local function freshArenas(ids: { string }, rolls: { number }?, broken: string?): ({ [string]: Model }, Folder, any)
		local clock = FakeClock.new(1000)
		local templates: { [string]: Model } = {}
		for _, id in ids do
			local template = makeTemplate(if id == broken then { noZones = true } else nil)
			template:SetAttribute("SD_ArenaId", id)
			templates[id] = template
		end
		local container = Instance.new("Folder")
		table.clear(logged)
		ArenaService.useTemplates(templates, container, clock.now, quietLog, if rolls then FakeRng.new(rolls) else nil)
		return templates, container, clock
	end

	local function teardownArenas(templates: { [string]: Model }, container: Instance)
		ArenaService.useTemplate(nil, nil)
		for _, template in templates do
			template:Destroy()
		end
		container:Destroy()
	end

	local function arenaOf(slot: any): string?
		return slot.model:GetAttribute("SD_ArenaId")
	end

	t.test("pickArena: an equal-chance roll over the usable arenas; a single arena needs no roll", function()
		-- Sorted usable ids: arcade_toyworks, candy_court, pinewood_camp.
		local templates, container = freshArenas({ "candy_court", "pinewood_camp", "arcade_toyworks" }, { 1, 3, 2 })
		expect.equal(ArenaService.pickArena(), "arcade_toyworks")
		expect.equal(ArenaService.pickArena(), "pinewood_camp")
		expect.equal(ArenaService.pickArena(), "candy_court")
		teardownArenas(templates, container)
		local single, box = freshArenas({ "candy_court" }, {}) -- an empty script: any roll would raise
		expect.equal(ArenaService.pickArena(), "candy_court")
		expect.equal(ArenaService.acquire("m"), ArenaService.getSlot(1))
		teardownArenas(single, box)
	end)

	t.test("acquire: the picked arena's free clone first, else a new clone; view() names the arena", function()
		local templates, container = freshArenas({ "candy_court", "pinewood_camp" }, { 2, 1, 2 })
		local first = ArenaService.acquire("m1") -- pinewood_camp: a new clone in slot 1
		expect.equal(first.index, 1)
		expect.equal(first.arenaId, "pinewood_camp")
		expect.equal(arenaOf(first), "pinewood_camp")
		expect.equal(ArenaService.view(first).arenaId, "pinewood_camp")
		local second = ArenaService.acquire("m2") -- candy_court: no free clone of it, so slot 2
		expect.equal(second.index, 2)
		expect.equal(arenaOf(second), "candy_court")
		ArenaService.release(first)
		local model = first.model
		local third = ArenaService.acquire("m3") -- pinewood_camp again: its free clone is reused, not re-cloned
		expect.equal(third, first)
		expect.equal(third.model, model)
		expect.equal(ArenaService.clonedCount(), 2)
		teardownArenas(templates, container)
	end)

	t.test("acquire: with every slot cloned, the lowest free slot of another arena is re-cloned", function()
		local maxSlots = ArenaService.maxSlots()
		local rolls: { number } = {}
		for _ = 1, maxSlots do
			table.insert(rolls, 1) -- candy_court in every slot
		end
		table.insert(rolls, 2) -- then pinewood_camp
		local templates, container = freshArenas({ "candy_court", "pinewood_camp" }, rolls)
		local taken = {}
		for index = 1, maxSlots do
			taken[index] = ArenaService.acquire()
		end
		ArenaService.release(taken[5])
		ArenaService.release(taken[3])
		local oldModel = taken[3].model
		local slot = ArenaService.acquire("swap")
		expect.equal(slot.index, 3)
		expect.equal(slot.arenaId, "pinewood_camp")
		expect.equal(arenaOf(slot), "pinewood_camp")
		expect.equal(ArenaService.getSlot(3), slot)
		expect.equal(oldModel.Parent, nil) -- the old clone is gone
		expect.equal(slot.model.Parent, container)
		expect.equal(slot.model.Name, "Arena_3")
		local origin = Config.Duel.Arena.SlotOrigins[3]
		expect.near((slot.origin.Position - origin).Magnitude, 0, 1e-3)
		expect.truthy(ArenaService.inOwnHalf(slot, "B", origin + Vector3.new(0, 3, 40)))
		expect.equal(slot.matchId, "swap")
		expect.truthy(slot.inUse)
		expect.falsy(taken[5].inUse) -- the other free slot is untouched
		teardownArenas(templates, container)
	end)

	t.test("a broken arena leaves the rotation once; the others keep the duels going", function()
		local templates, container = freshArenas({ "candy_court", "pinewood_camp" }, { 2 }, "pinewood_camp")
		local slot = ArenaService.acquire("m1") -- picks pinewood_camp, its clone fails, the pick falls to candy_court
		expect.truthy(slot)
		expect.equal(slot.arenaId, "candy_court")
		expect.equal(#logged, 1)
		expect.truthy(string.find(logged[1], "pinewood_camp", 1, true) ~= nil)
		expect.truthy(ArenaService.available())
		expect.equal(ArenaService.pickArena(), "candy_court") -- one usable arena left: no roll
		expect.equal(#container:GetChildren(), 1)
		local state = ArenaService.debugState()
		expect.deepEqual(state.arenas, { "candy_court" })
		expect.deepEqual(state.broken, { "pinewood_camp" })
		expect.equal(state.slots[1].arenaId, "candy_court")
		teardownArenas(templates, container)
	end)

	t.test("debugForceArena pins the pick while usable; nil restores the roll; unknown ids fail", function()
		local templates, container = freshArenas({ "candy_court", "pinewood_camp" }, { 1 })
		local refused, reason = ArenaService.debugForceArena("nowhere")
		expect.equal(refused, false)
		expect.equal(reason, "no arena template nowhere")
		local pinned, problem = ArenaService.debugForceArena("pinewood_camp")
		expect.equal(pinned, true)
		expect.equal(problem, nil)
		expect.equal(ArenaService.pickArena(), "pinewood_camp") -- no roll used
		expect.equal(ArenaService.pickArena(), "pinewood_camp")
		expect.equal(ArenaService.debugState().forced, "pinewood_camp")
		ArenaService.debugForceArena(nil)
		expect.equal(ArenaService.pickArena(), "candy_court") -- the scripted roll 1
		teardownArenas(templates, container)
	end)

	t.test("prewarm clones its slots with picked arenas", function()
		local templates, container = freshArenas({ "candy_court", "pinewood_camp" }, { 2 })
		ArenaService.prewarm(1)
		local slot = ArenaService.getSlot(1)
		expect.truthy(slot)
		expect.equal(slot.arenaId, "pinewood_camp")
		expect.falsy(slot.inUse)
		teardownArenas(templates, container)
	end)

	t.test("grid: every 1v1 sky map with its floating props fits its slot, clear of the lobby and the Team maps", function()
		local lobbyRadius = (WorldLayout.Lobby.baseSlab.size * Vector3.new(1, 0, 1)).Magnitude / 2
		local maxSlots = ArenaService.maxSlots()
		for _, id in MapData.ofMode("duel") do
			local map = MapData.maps[id]
			-- his layout: sky props up to hypot(W, H) / 2 + 45 + 150 from the centre (MapLayout), ~12 studs of prop
			local reach = math.sqrt(map.W ^ 2 + map.H ^ 2) / 2 + 45 + 150 + 12
			for i = 1, maxSlots do
				local a = ArenaService.slotOrigin(i) :: Vector3
				expect.truthy(Vector3.new(a.X, 0, a.Z).Magnitude >= reach + lobbyRadius)
				expect.truthy(a.Z - reach >= 3000 + 270 + 50) -- south of the Team / Free for All row (Z 3000..3270)
				for j = i + 1, maxSlots do
					local b = ArenaService.slotOrigin(j) :: Vector3
					if (a - b).Magnitude < 2 * reach then
						error(`{id}: slots {i} and {j} overlap`)
					end
				end
			end
		end
	end)
end
