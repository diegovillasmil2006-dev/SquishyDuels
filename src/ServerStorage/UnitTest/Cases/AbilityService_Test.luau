--!strict
-- AbilityService_Test: unit tests for ServerScriptService.Server.Services.AbilityService (pure helpers, and the place
-- check of a request against a fake match). Server only (ServerStorage.UnitTest). Edit mode: init()/start() are never
-- called; nothing is parented into the place.
-- Contract (DESIGN §5.9, §12 #8):
--   * the aim is flattened to horizontal and must keep at least minHorizontalAim of horizontal length;
--   * the lane starts at O = (HRP.X, floorY + laneHeightAboveFloor, HRP.Z) + dir × originForwardStuds, so its sphere
--     spans floor + 0.5 .. floor + 8.5 with the live config (the lane never touches the floor, jumping never avoids it);
--   * the lane end is clamped to the arena Bounds (X and Z; the lane flies at a fixed height);
--   * a duel caster must stand in its own half + zoneToleranceStuds, like a thrower (§5.6 #5, §12 #5): a request from
--     the neutral zone or the opponent's half is ult.context before any other check (a fake match registered with
--     CombatService; cleaned up at the end);
--   * spec phase 5, the four Epic ultimates through the same request path (AbilityService.useDeps: fake clock, sender,
--     delays and world queries; table roots): each is refused from the neutral zone and until its meter is full; Flock
--     Volley releases 3 birds fanned over 24° and 0.05 s apart, cut at cover; Sprinkle Roller's lane starts 1.6 m
--     ahead, 60 studs long, at 55 studs/s; Rain Check centres on the opponent's spot at the release with 5 drops at
--     the design's times, the last on that spot; Bubble Pop's flight ends after 1.2 s; no room is ult.noRoom (not for
--     Rain Check); the minimum interval is the design's cooldown; Dragon Rush keeps its lane, now with its ultimateId.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local AbilityService = t.requireServer("Services/AbilityService")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")

	local RUSH = Config.Abilities.dragon_rush
	local boundsVolume = WorldLayout.Arena.zones.Bounds
	local BOUNDS = { cframe = CFrame.new(boundsVolume.position), size = boundsVolume.size }

	local function near(a: Vector3, b: Vector3, tolerance: number?)
		expect.near((a - b).Magnitude, 0, tolerance or 1e-6)
	end

	t.test("flatAim drops the vertical part and normalizes the rest", function()
		near(AbilityService.flatAim(Vector3.new(1, 0.5, 0), RUSH.minHorizontalAim), Vector3.new(1, 0, 0))
		near(AbilityService.flatAim(Vector3.new(3, -2, 4), RUSH.minHorizontalAim), Vector3.new(0.6, 0, 0.8))
	end)

	t.test("flatAim refuses an aim whose horizontal part is shorter than minHorizontalAim", function()
		expect.equal(AbilityService.flatAim(Vector3.new(0.1, 1, 0.1), RUSH.minHorizontalAim), nil)
		expect.equal(AbilityService.flatAim(Vector3.new(0, -1, 0), RUSH.minHorizontalAim), nil)
		expect.equal(AbilityService.flatAim(Vector3.zero, 0), nil)
	end)

	t.test("the lane origin sits above the HRP at the lane height, moved forward along the aim", function()
		local origin = AbilityService.laneOrigin(Vector3.new(10, 3.2, -30), 0, Vector3.new(0, 0, 1), RUSH)
		near(origin, Vector3.new(10, RUSH.laneHeightAboveFloor, -30 + RUSH.originForwardStuds))
		-- The swept sphere stays off the floor and covers a standing (or jumping) capsule.
		expect.truthy(origin.Y - RUSH.radius > 0)
		expect.near(origin.Y - RUSH.radius, 0.5, 1e-9)
		expect.near(origin.Y + RUSH.radius, 8.5, 1e-9)
		local raised = AbilityService.laneOrigin(Vector3.new(0, 50, 0), 20, Vector3.new(1, 0, 0), RUSH)
		expect.near(raised.Y, 20 + RUSH.laneHeightAboveFloor, 1e-9) -- the floor decides the height, not the HRP
	end)

	t.test("clampToBounds stops the lane at the arena Bounds", function()
		expect.near(AbilityService.clampToBounds(Vector3.new(0, 4.5, -40), Vector3.new(0, 0, 1), 110, BOUNDS), 94, 1e-6)
		expect.near(AbilityService.clampToBounds(Vector3.new(30, 4.5, 0), Vector3.new(1, 0, 0), 110, BOUNDS), 8, 1e-6)
		expect.near(
			AbilityService.clampToBounds(Vector3.new(0, 4.5, 0), Vector3.new(0.6, 0, 0.8), 110, BOUNDS),
			38 / 0.6,
			1e-4
		)
	end)

	t.test("clampToBounds keeps a shorter lane and gives 0 from outside the Bounds", function()
		expect.near(AbilityService.clampToBounds(Vector3.new(0, 4.5, 0), Vector3.new(0, 0, 1), 20, BOUNDS), 20, 1e-9)
		expect.equal(AbilityService.clampToBounds(Vector3.new(50, 4.5, 0), Vector3.new(-1, 0, 0), 110, BOUNDS), 0)
	end)

	local function arenaZones(): { [string]: any }
		local zones = {}
		for name, volume in WorldLayout.Arena.zones do
			zones[name] = { cframe = CFrame.new(volume.position), size = volume.size }
		end
		return zones
	end

	t.test("castFromOwnHalf: the caster's own half + zoneToleranceStuds only (the throw rule, §5.6 #5)", function()
		local zones = arenaZones()
		local tolerance = Config.Combat.Throw.zoneToleranceStuds
		expect.truthy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, -40), zones, "A"))
		expect.truthy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, -8 + tolerance * 0.5), zones, "A"))
		expect.falsy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, -8 + tolerance + 0.5), zones, "A")) -- neutral
		expect.falsy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, 30), zones, "A")) -- the opponent's half
		expect.truthy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, 30), zones, "B"))
		expect.falsy(AbilityService.castFromOwnHalf(Vector3.new(0, 3, -40), {}, "A"))
	end)

	t.test("UltimateRequest from the neutral zone or the opponent's half is refused before anything else", function()
		local CombatService = t.requireServer("Services/CombatService")
		local Catalog = t.requireShared("Catalog")
		local Workspace = game:GetService("Workspace")
		CombatService.destroy()
		CombatService.useDeps({
			autoStep = false,
			send = function() end,
			reportViolation = function() end,
		})
		local dragonId = nil
		for _, def in Catalog.list() do
			if def.ultimateId == "dragon_rush" then
				dragonId = def.id
			end
		end
		expect.truthy(dragonId ~= nil)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = model
		model.PrimaryPart = root
		local function newFighter(userId: number, side: string, squishyId: string): any
			return CombatService.newFighter({
				userId = userId,
				side = side,
				squishyId = squishyId,
				getRoot = function(): BasePart?
					return root
				end,
				isAlive = function(): boolean
					return true
				end,
			})
		end
		local caster = newFighter(91, "A", dragonId)
		local other = newFighter(92, "B", Catalog.starterId())
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {}
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {}
		local port = {
			matchId = "ult-place-test",
			arena = {
				slot = 1,
				floorY = 0,
				killY = -15,
				zones = arenaZones(),
				geometry = nil,
				raycastParams = params,
				overlapParams = overlap,
			},
			fighters = { caster, other },
			phase = function(): string
				return "Active"
			end,
			cooldownMultiplier = function(): number
				return 1
			end,
			placement = function(): CFrame?
				return nil
			end,
			canBeHit = function(): boolean
				return false
			end,
			applyHits = function(): { [number]: any }
				return {}
			end,
			flush = function() end,
			throwAccepted = function() end,
			outOfBounds = function() end,
		}
		CombatService.registerMatch(port)
		AbilityService.attachMatch(port)
		local aim = Vector3.new(0, 0, 1)
		local function request(seq: number, at: Vector3): (boolean, string?)
			root.CFrame = CFrame.new(at)
			return AbilityService.requestUltimate(91, seq, aim, Workspace:GetServerTimeNow())
		end
		local okNeutral, neutral = request(1, Vector3.new(0, 3, -2))
		expect.falsy(okNeutral)
		expect.equal(neutral, "ult.context")
		local okFar, far = request(2, Vector3.new(0, 3, 30))
		expect.falsy(okFar)
		expect.equal(far, "ult.context")
		-- From the own half the place passes: the next check (no charge yet) answers instead.
		local okOwn, own = request(3, Vector3.new(0, 3, -40))
		expect.falsy(okOwn)
		expect.equal(own, "ult.notReady")
		AbilityService.detachMatch("ult-place-test")
		CombatService.destroy()
		CombatService.useDeps(nil)
		model:Destroy()
	end)

	-- Spec phase 5: the four Epic ultimates through the same request path (useDeps: a fake clock, a recording sender,
	-- captured delays and fake world queries; roots are plain tables, so no engine part is needed). ------------------

	local Catalog = t.requireShared("Catalog")
	local CombatService = t.requireServer("Services/CombatService")
	local FakeClock = t.requireFake("FakeClock")
	local STAND = Config.Combat.Hitbox.radius - Config.Combat.Hitbox.bottomOffset

	type Sent = { remote: string, payload: any }
	type World = {
		clock: any,
		sent: { Sent },
		delays: { { at: number, fn: (...any) -> (), args: { any } } },
		rootA: any,
		rootB: any,
		caster: any,
		port: any,
		castDistance: number?, -- what the fake Spherecast returns (nil = clear)
		blocked: boolean, -- what the fake room check returns
	}

	local function tableRoot(position: Vector3): any
		return { Position = position, CFrame = CFrame.new(position), Parent = nil }
	end

	-- A registered Active match: A (`squishyId`, user 91) at (0, 3, -40) and B (user 92) at `bAt`.
	local function ultWorld(squishyId: string, bAt: Vector3?): World
		local world: World = {
			clock = FakeClock.new(5000),
			sent = {},
			delays = {},
			rootA = tableRoot(Vector3.new(0, STAND, -40)),
			rootB = tableRoot(bAt or Vector3.new(0, STAND, 30)),
			caster = nil,
			port = nil,
			castDistance = nil,
			blocked = false,
		}
		CombatService.destroy()
		CombatService.useDeps({
			now = world.clock.now,
			autoStep = false,
			send = function(remote: string, _recipients: { any }, payload: any)
				table.insert(world.sent, { remote = remote, payload = payload })
			end,
			reportViolation = function() end,
		})
		AbilityService.useDeps({
			now = world.clock.now,
			send = function(remote: string, _recipients: { any }, payload: any)
				table.insert(world.sent, { remote = remote, payload = payload })
			end,
			delay = function(seconds: number, fn: (...any) -> (), ...: any)
				table.insert(world.delays, { at = world.clock.now() + seconds, fn = fn, args = { ... } })
			end,
			overlaps = function(): boolean
				return world.blocked
			end,
			cast = function(): number?
				return world.castDistance
			end,
		})
		local function newFighter(userId: number, side: string, id: string, root: any): any
			return CombatService.newFighter({
				userId = userId,
				side = side,
				squishyId = id,
				getRoot = function(): BasePart?
					return root
				end,
				isAlive = function(): boolean
					return true
				end,
				now = world.clock.now(),
			})
		end
		local caster = newFighter(91, "A", squishyId, world.rootA)
		local other = newFighter(92, "B", Catalog.starterId(), world.rootB)
		local port = {
			matchId = "ult-phase5",
			arena = {
				slot = 1,
				floorY = 0,
				killY = -15,
				zones = arenaZones(),
				geometry = nil,
				raycastParams = RaycastParams.new(),
				overlapParams = OverlapParams.new(),
			},
			fighters = { caster, other },
			phase = function(): string
				return "Active"
			end,
			cooldownMultiplier = function(): number
				return 1
			end,
			placement = function(): CFrame?
				return nil
			end,
			canBeHit = function(): boolean
				return true
			end,
			applyHits = function(hits: { any }): { [number]: any }
				local outcomes = {}
				for index in hits do
					outcomes[index] = { lives = 2, invulnUntil = world.clock.now() + 1.5, eliminated = false }
				end
				return outcomes
			end,
			flush = function() end,
			throwAccepted = function() end,
			outOfBounds = function() end,
		}
		CombatService.registerMatch(port)
		AbilityService.attachMatch(port)
		world.caster = caster
		world.port = port
		return world
	end

	local function closeWorld()
		AbilityService.detachMatch("ult-phase5")
		AbilityService.useDeps(nil)
		CombatService.destroy()
		CombatService.useDeps(nil)
	end

	local function events(world: World, phase: string?): { any }
		local list = {}
		for _, entry in world.sent do
			if entry.remote == "UltimateEvent" and (phase == nil or entry.payload.phase == phase) then
				table.insert(list, entry.payload)
			end
		end
		return list
	end

	-- Runs the captured delays that are due by `untilTime` (in time order), moving the clock to each.
	local function runDelays(world: World, untilTime: number)
		while true do
			table.sort(world.delays, function(x, y)
				return x.at < y.at
			end)
			local next = world.delays[1]
			if next == nil or next.at > untilTime then
				break
			end
			table.remove(world.delays, 1)
			world.clock.advance(math.max(0, next.at - world.clock.now()))
			next.fn(table.unpack(next.args))
		end
		world.clock.advance(math.max(0, untilTime - world.clock.now()))
	end

	local function ready(world: World)
		AbilityService.setCharge(91, Config.Abilities[Catalog.get(world.caster.squishyId).ultimateId].chargeMax)
	end

	local AIM = Vector3.new(0, 0, 1)

	t.test("each Epic ultimate is refused from the neutral zone (ult.context) and until its meter is full", function()
		for _, id in { "bird", "donut", "cloud_bunny", "cupcake_axolotl" } do
			local world = ultWorld(id)
			world.rootA.Position = Vector3.new(0, STAND, -2)
			local okNeutral, neutral = AbilityService.requestUltimate(91, 1, AIM, world.clock.now())
			expect.falsy(okNeutral)
			expect.equal(neutral, "ult.context")
			world.rootA.Position = Vector3.new(0, STAND, -40)
			local okEmpty, empty = AbilityService.requestUltimate(91, 2, AIM, world.clock.now())
			expect.falsy(okEmpty)
			expect.equal(empty, "ult.notReady")
			expect.equal(#events(world), 0)
			closeWorld()
		end
	end)

	t.test(
		"Flock Volley: a 0.35 s wind-up, then 3 birds fanned over 24°, 0.05 s apart, from the throw height",
		function()
			local world = ultWorld("bird")
			local V = Config.Abilities.flock_volley
			ready(world)
			local start = world.clock.now()
			local ok, reason = AbilityService.requestUltimate(91, 1, AIM, start)
			expect.truthy(ok)
			expect.equal(reason, nil)
			local telegraph = events(world, "telegraph")[1]
			expect.equal(telegraph.ultimateId, "flock_volley")
			expect.near(telegraph.telegraphEndsAt, start + V.telegraphSeconds, 1e-9)
			expect.equal(AbilityService.chargeOf(91), 0)
			expect.near(world.caster.rootedUntil, start + V.telegraphSeconds + V.recoverySeconds, 1e-9)
			runDelays(world, start + V.telegraphSeconds + 0.01)
			local release = events(world, "release")[1]
			assert(release ~= nil, "no release")
			expect.equal(release.ultimateId, "flock_volley")
			local shots = release.shots
			expect.equal(#shots, V.count)
			for index, shot in shots do
				expect.near(shot.releaseAt, start + V.telegraphSeconds + V.staggerSeconds * (index - 1), 1e-9)
				expect.near(shot.origin.Y, V.laneHeightAboveFloor, 1e-4) -- Vector3 is single precision
				-- No cover: each bird flies maxLength or to the arena Bounds, whichever is nearer.
				expect.near(shot.length, AbilityService.clampToBounds(shot.origin, shot.dir, V.maxLength, BOUNDS), 1e-3)
				local info = CombatService.projectileInfo(shot.projId)
				assert(info ~= nil, "no bird projectile")
				expect.equal(info.kind, "ult")
				expect.near(info.radius, V.radius, 1e-9)
			end
			local first = math.deg(math.atan2(shots[1].dir.X, shots[1].dir.Z))
			local last = math.deg(math.atan2(shots[V.count].dir.X, shots[V.count].dir.Z))
			expect.near(math.abs(last - first), V.fanDeg, 1e-3)
			closeWorld()
		end
	)

	t.test("Flock Volley: a bird is cut where the Spherecast meets cover", function()
		local world = ultWorld("bird")
		ready(world)
		world.castDistance = 20
		expect.truthy((AbilityService.requestUltimate(91, 1, AIM, world.clock.now())))
		runDelays(world, world.clock.now() + 1)
		for _, shot in events(world, "release")[1].shots do
			expect.near(shot.length, 20, 1e-4)
		end
		closeWorld()
	end)

	t.test(
		"Sprinkle Roller: the lane starts 1.6 m ahead on the floor, 60 studs long, and rolls at 55 studs/s",
		function()
			local world = ultWorld("donut")
			local R = Config.Abilities.sprinkle_roller
			ready(world)
			local start = world.clock.now()
			expect.truthy((AbilityService.requestUltimate(91, 1, AIM, start)))
			local telegraph = events(world, "telegraph")[1]
			expect.equal(telegraph.ultimateId, "sprinkle_roller")
			expect.near(telegraph.origin.Z, -40 + R.originForwardStuds, 1e-4)
			expect.near(telegraph.origin.Y, R.laneHeightAboveFloor, 1e-4)
			expect.near(telegraph.length, R.maxLength, 1e-4)
			expect.near(telegraph.radius, R.radius, 1e-9)
			runDelays(world, start + R.telegraphSeconds + 0.01)
			local release = events(world, "release")[1]
			local info = CombatService.projectileInfo(release.projId)
			assert(info ~= nil, "no roller projectile")
			expect.equal(info.kind, "ult")
			expect.near(info.velocity.Magnitude, R.speed, 1e-3)
			closeWorld()
		end
	)

	t.test(
		"Rain Check: at the release the zone centres on the opponent's spot with 5 drops at the design's times",
		function()
			local world = ultWorld("cloud_bunny", Vector3.new(6, STAND, 25))
			local C = Config.Abilities.rain_check
			ready(world)
			local start = world.clock.now()
			expect.truthy((AbilityService.requestUltimate(91, 1, AIM, start)))
			world.rootB.Position = Vector3.new(-4, STAND, 30) -- the opponent moves during the wind-up
			local releaseAt = start + C.telegraphSeconds
			runDelays(world, releaseAt + 0.01)
			local release = events(world, "release")[1]
			assert(release ~= nil, "no release")
			expect.equal(release.ultimateId, "rain_check")
			expect.near((release.center - Vector3.new(-4, 0, 30)).Magnitude, 0, 1e-4)
			expect.equal(#release.drops, C.drops)
			for index, drop in release.drops do
				local k = index - 1
				expect.near(drop.shadowAt, releaseAt + C.firstShadowSeconds + C.dropStepSeconds * k, 1e-9)
				expect.near(drop.landAt, drop.shadowAt + C.shadowSeconds + C.fallSeconds, 1e-9)
				expect.truthy(CombatService.projectileInfo(drop.projId) ~= nil)
			end
			-- The last drop lands on the opponent's spot at the release (design: fp.js:353).
			expect.near((release.drops[C.drops].position - Vector3.new(-4, 0, 30)).Magnitude, 0, 1e-4)
			closeWorld()
		end
	)

	t.test("Bubble Pop: one bubble at 40 studs/s whose flight ends after 1.2 s", function()
		local world = ultWorld("cupcake_axolotl")
		local B = Config.Abilities.bubble_pop
		ready(world)
		local start = world.clock.now()
		expect.truthy((AbilityService.requestUltimate(91, 1, AIM, start)))
		expect.near(events(world, "telegraph")[1].length, B.speed * B.popSeconds, 1e-4)
		runDelays(world, start + B.telegraphSeconds + 0.01)
		local release = events(world, "release")[1]
		local info = CombatService.projectileInfo(release.projId)
		assert(info ~= nil, "no bubble")
		expect.near(info.maxT, B.popSeconds, 1e-4)
		closeWorld()
	end)

	t.test("no room at the start is ult.noRoom and spends nothing; Rain Check needs no room", function()
		for _, id in { "bird", "donut", "cupcake_axolotl" } do
			local world = ultWorld(id)
			ready(world)
			world.blocked = true
			local ok, reason = AbilityService.requestUltimate(91, 1, AIM, world.clock.now())
			expect.falsy(ok)
			expect.equal(reason, "ult.noRoom")
			expect.truthy(AbilityService.chargeOf(91) > 0)
			closeWorld()
		end
		local world = ultWorld("cloud_bunny")
		ready(world)
		world.blocked = true
		expect.truthy((AbilityService.requestUltimate(91, 1, AIM, world.clock.now())))
		closeWorld()
	end)

	t.test("the minimum interval between uses is the design's cooldown (Flock Volley 35 s)", function()
		local world = ultWorld("bird")
		local V = Config.Abilities.flock_volley
		ready(world)
		expect.truthy((AbilityService.requestUltimate(91, 1, AIM, world.clock.now())))
		runDelays(world, world.clock.now() + 2)
		ready(world)
		world.clock.advance(V.minIntervalSeconds - 3)
		local ok, reason = AbilityService.requestUltimate(91, 2, AIM, world.clock.now())
		expect.falsy(ok)
		expect.equal(reason, "ult.notReady")
		world.clock.advance(2)
		expect.truthy((AbilityService.requestUltimate(91, 3, AIM, world.clock.now())))
		closeWorld()
	end)

	t.test("Dragon Rush still: its telegraph and release carry the same lane, now with its ultimateId", function()
		local world = ultWorld("dragon")
		local D = Config.Abilities.dragon_rush
		ready(world)
		local start = world.clock.now()
		expect.truthy((AbilityService.requestUltimate(91, 1, AIM, start)))
		local telegraph = events(world, "telegraph")[1]
		expect.equal(telegraph.ultimateId, "dragon_rush")
		expect.near(telegraph.radius, D.radius, 1e-9)
		expect.near(telegraph.speed, D.speed, 1e-9)
		expect.near(telegraph.origin.Y, D.laneHeightAboveFloor, 1e-4)
		expect.near(telegraph.telegraphEndsAt, start + D.telegraphSeconds, 1e-9)
		expect.equal(telegraph.shots, nil)
		runDelays(world, start + D.telegraphSeconds + 0.01)
		local release = events(world, "release")[1]
		local info = CombatService.projectileInfo(release.projId)
		assert(info ~= nil, "no lane")
		expect.equal(info.kind, "lane")
		closeWorld()
	end)
end
