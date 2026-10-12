--!strict
-- DashService_Test: unit tests for ServerScriptService.Server.Services.DashService (spec phase 5 §3.3). Server only
-- (ServerStorage.UnitTest). Edit mode: init() is never called; the service runs on a FakeClock with a recording sender
-- and a fake Spherecast (useDeps), against a fake match registered with CombatService; roots are plain tables.
-- Contract:
--   * a valid dash in Active: DashStarted {userId, dir, from, to, startAt} to the match, from the server HRP, and the
--     dasher's movement guard gets the dash's own studs (+ guardSlackStuds) as a one-time allowance for its window
--     only (MovementRules.allowDash);
--   * refused (nothing sent, no allowance): outside Active / SuddenDeath, rooted by an ultimate, during a throw windup,
--     before cooldownSeconds, from the neutral zone; the match is brought up to the request time first (port.sync);
--   * the end point stops at cover (the world query) and a body radius before the neutral band;
--   * the seq and the cooldown are per player for the session; playerRemoving forgets them.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type World = {
	clock: any,
	sent: { { remote: string, payload: any } },
	castDistance: number?,
	phase: string,
	fighter: any,
	root: any,
	synced: { number },
}

return function(t: Context)
	local expect = t.expect
	local DashService = t.requireServer("Services/DashService")
	local CombatService = t.requireServer("Services/CombatService")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local FakeClock = t.requireFake("FakeClock")
	local DASH = Config.Duel.Rules.Dash
	local STAND = Config.Combat.Hitbox.radius - Config.Combat.Hitbox.bottomOffset

	local function zones(): { [string]: any }
		local list = {}
		for name, volume in WorldLayout.Arena.zones do
			list[name] = { cframe = CFrame.new(volume.position), size = volume.size }
		end
		return list
	end

	local function setup(at: Vector3?): World
		local world: World = {
			clock = FakeClock.new(2000),
			sent = {},
			castDistance = nil,
			phase = "Active",
			fighter = nil,
			root = nil,
			synced = {},
		}
		local position = at or Vector3.new(0, STAND, -30)
		world.root = { Position = position, CFrame = CFrame.new(position), Parent = nil }
		CombatService.destroy()
		CombatService.useDeps({ now = world.clock.now, autoStep = false, send = function() end })
		DashService.useDeps({
			now = world.clock.now,
			send = function(remote: string, _recipients: { any }, payload: any)
				table.insert(world.sent, { remote = remote, payload = payload })
			end,
			reportViolation = function() end,
			cast = function(): number?
				return world.castDistance
			end,
		})
		DashService.playerRemoving({ UserId = 81 } :: any)
		local function newFighter(userId: number, side: string, root: any): any
			return CombatService.newFighter({
				userId = userId,
				side = side,
				squishyId = Catalog.starterId(),
				getRoot = function(): BasePart?
					return root
				end,
				isAlive = function(): boolean
					return true
				end,
				now = world.clock.now(),
			})
		end
		local a = newFighter(81, "A", world.root)
		local otherRoot = { Position = Vector3.new(0, STAND, 30), CFrame = CFrame.new(0, STAND, 30), Parent = nil }
		local b = newFighter(82, "B", otherRoot)
		CombatService.registerMatch({
			matchId = "dash-test",
			arena = {
				slot = 1,
				floorY = 0,
				killY = -15,
				zones = zones(),
				geometry = nil,
				raycastParams = RaycastParams.new(),
				overlapParams = OverlapParams.new(),
			},
			fighters = { a, b },
			phase = function(): string
				return world.phase
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
			applyHits = function(): { [number]: any }
				return {}
			end,
			flush = function() end,
			throwAccepted = function() end,
			outOfBounds = function() end,
			sync = function(now: number)
				table.insert(world.synced, now)
			end,
		})
		world.fighter = a
		return world
	end

	local function close()
		DashService.playerRemoving({ UserId = 81 } :: any)
		DashService.useDeps(nil)
		CombatService.destroy()
		CombatService.useDeps(nil)
	end

	local function started(world: World): { any }
		local list = {}
		for _, entry in world.sent do
			if entry.remote == "DashStarted" then
				table.insert(list, entry.payload)
			end
		end
		return list
	end

	local RIGHT = Vector3.new(1, 0, 0)

	t.test("a valid dash: DashStarted from the server HRP, and a guard allowance for its window only", function()
		local world = setup(nil)
		local now = world.clock.now()
		local ok, reason = DashService.requestDash(81, 1, RIGHT, now)
		expect.truthy(ok)
		expect.equal(reason, nil)
		expect.deepEqual(world.synced, { now }) -- the match was brought up to the request time first
		local payload = started(world)[1]
		assert(payload ~= nil, "no DashStarted")
		expect.equal(payload.userId, 81)
		expect.near((payload.from - Vector3.new(0, STAND, -30)).Magnitude, 0, 1e-4)
		expect.near((payload.to - Vector3.new(DASH.distanceStuds, STAND, -30)).Magnitude, 0, 1e-4)
		expect.near(payload.startAt, now, 1e-9)
		local allowance = world.fighter.guard.dash
		assert(allowance ~= nil, "no guard allowance")
		expect.near(allowance.studs, DASH.distanceStuds + DASH.guardSlackStuds, 1e-4)
		expect.near(allowance.startAt, now - DASH.guardLeadSeconds, 1e-9)
		expect.near(allowance.untilTime, now + DASH.seconds + DASH.guardTailSeconds, 1e-9)
		close()
	end)

	t.test("refused outside Active, while rooted or in a throw windup: nothing sent, no allowance", function()
		local world = setup(nil)
		world.phase = "Countdown"
		local ok, reason = DashService.requestDash(81, 1, RIGHT, world.clock.now())
		expect.falsy(ok)
		expect.equal(reason, "dash.context")
		world.phase = "Active"
		world.fighter.rootedUntil = world.clock.now() + 1
		expect.equal(select(2, DashService.requestDash(81, 2, RIGHT, world.clock.now())), "dash.busy")
		world.fighter.rootedUntil = -math.huge
		world.fighter.windupUntil = world.clock.now() + 0.1
		expect.equal(select(2, DashService.requestDash(81, 3, RIGHT, world.clock.now())), "dash.busy")
		expect.equal(#started(world), 0)
		expect.equal(world.fighter.guard.dash, nil)
		close()
	end)

	t.test("cooldown: 2 s between dashes; the seq rises per player", function()
		local world = setup(nil)
		expect.truthy((DashService.requestDash(81, 1, RIGHT, world.clock.now())))
		world.clock.advance(1)
		expect.equal(select(2, DashService.requestDash(81, 2, -RIGHT, world.clock.now())), "dash.cooldown")
		world.clock.advance(1)
		expect.truthy((DashService.requestDash(81, 3, -RIGHT, world.clock.now())))
		-- A replayed seq is a payload failure.
		world.clock.advance(3)
		expect.equal(select(2, DashService.requestDash(81, 3, RIGHT, world.clock.now())), "net.invalid")
		expect.equal(#started(world), 2)
		close()
	end)

	t.test("the end point stops at cover and before the neutral band", function()
		local world = setup(nil)
		world.castDistance = 5
		expect.truthy((DashService.requestDash(81, 1, RIGHT, world.clock.now())))
		expect.near((started(world)[1].to - Vector3.new(5, STAND, -30)).Magnitude, 0, 1e-4)
		close()
		local near = setup(Vector3.new(0, STAND, -15))
		expect.truthy((DashService.requestDash(81, 1, Vector3.new(0, 0, 1), near.clock.now())))
		expect.near(started(near)[1].to.Z, -8 - DASH.bodyRadiusStuds, 1e-4)
		close()
	end)

	t.test("refused from the neutral zone; playerRemoving forgets the seq and the cooldown", function()
		local world = setup(Vector3.new(0, STAND, -8 + Config.Combat.Throw.zoneToleranceStuds + 0.5))
		expect.equal(select(2, DashService.requestDash(81, 1, RIGHT, world.clock.now())), "dash.context")
		world.root.Position = Vector3.new(0, STAND, -30)
		expect.truthy((DashService.requestDash(81, 2, RIGHT, world.clock.now())))
		DashService.playerRemoving({ UserId = 81 } :: any)
		expect.truthy((DashService.requestDash(81, 1, RIGHT, world.clock.now())))
		close()
	end)
end
