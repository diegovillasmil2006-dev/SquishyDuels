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
--   * the projectile RaycastParams / OverlapParams include Geometry minus Barriers, in the Default group.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local STREAMING_RADIUS = 1024 -- §5.3: slots stay inside the lobby's streaming radius
local ROLL_UP = CFrame.Angles(0, 0, math.pi / 2) -- how ArenaBuilder rolls a cylinder pad about its look axis

return function(t: Context)
	local expect = t.expect
	local ArenaService = t.requireServer("Services/ArenaService")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local FakeClock = t.requireFake("FakeClock")
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

	t.test("grid: slot footprints never overlap each other or the lobby, and stay within streaming range", function()
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
			-- Farthest apron corner inside the streaming radius.
			local far = Vector3.new(math.abs(a.X) + halfX, 0, math.abs(a.Z) + halfZ).Magnitude
			if far > STREAMING_RADIUS then
				error(`slot {i} reaches {far} studs from the lobby centre`)
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
end
