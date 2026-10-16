--!strict
-- DoubleJumpService_Test: unit tests for ServerScriptService.Server.Services.DoubleJumpService (2026-10-15 double
-- jump). Server only (ServerStorage.UnitTest). Edit mode: init() is never called; the service runs on a FakeClock with
-- a recording sender (useDeps), against a fake match registered with CombatService; roots are plain tables.
-- Contract:
--   * a valid double jump in Active: DoubleJumped {userId, key, at, startAt} to the match's players, from the server
--     HRP; the match is brought up to the request time first (port.sync);
--   * refused (nothing sent): outside Active / SuddenDeath, rooted by an ultimate, sooner than serverIntervalSeconds,
--     a player in no duel;
--   * the seq and the interval are per player for the session; playerRemoving forgets them.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type World = {
	clock: any,
	sent: { { remote: string, recipients: { any }, payload: any } },
	phase: string,
	fighter: any,
	synced: { number },
}

return function(t: Context)
	local expect = t.expect
	local DoubleJumpService = t.requireServer("Services/DoubleJumpService")
	local CombatService = t.requireServer("Services/CombatService")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local FakeClock = t.requireFake("FakeClock")
	local INTERVAL = Config.Duel.Rules.DoubleJump.serverIntervalSeconds
	local STAND = Config.Combat.Hitbox.radius - Config.Combat.Hitbox.bottomOffset

	local function zones(): { [string]: any }
		local list = {}
		for name, volume in WorldLayout.Arena.zones do
			list[name] = { cframe = CFrame.new(volume.position), size = volume.size }
		end
		return list
	end

	local function setup(): World
		local world: World = { clock = FakeClock.new(3000), sent = {}, phase = "Active", fighter = nil, synced = {} }
		CombatService.destroy()
		CombatService.useDeps({ now = world.clock.now, autoStep = false, send = function() end })
		DoubleJumpService.useDeps({
			now = world.clock.now,
			send = function(remote: string, recipients: { any }, payload: any)
				table.insert(world.sent, { remote = remote, recipients = recipients, payload = payload })
			end,
			reportViolation = function() end,
		})
		DoubleJumpService.playerRemoving({ UserId = 91 } :: any)
		local function newFighter(userId: number, side: string, at: Vector3): any
			local root = { Position = at, CFrame = CFrame.new(at), Parent = nil }
			return CombatService.newFighter({
				userId = userId,
				side = side,
				squishyId = Catalog.starterId(),
				getRoot = function(): BasePart?
					return root :: any
				end,
				isAlive = function(): boolean
					return true
				end,
				now = world.clock.now(),
			})
		end
		local a = newFighter(91, "A", Vector3.new(0, STAND + 6, -30))
		local b = newFighter(92, "B", Vector3.new(0, STAND, 30))
		CombatService.registerMatch({
			matchId = "double-jump-test",
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
		DoubleJumpService.playerRemoving({ UserId = 91 } :: any)
		DoubleJumpService.useDeps(nil)
		CombatService.destroy()
		CombatService.useDeps(nil)
	end

	t.test("a valid double jump in Active tells the match, from the server HRP", function()
		local world = setup()
		local now = world.clock.now()
		local ok, reason = DoubleJumpService.requestDoubleJump(world.fighter, 1, "B", now)
		expect.truthy(ok)
		expect.equal(reason, nil)
		expect.equal(#world.sent, 1)
		local entry = world.sent[1]
		expect.equal(entry.remote, "DoubleJumped")
		expect.equal(entry.payload.userId, 91)
		expect.equal(entry.payload.key, "B")
		expect.equal(entry.payload.at, Vector3.new(0, STAND + 6, -30))
		expect.equal(entry.payload.startAt, now)
		expect.equal(world.synced[1], now)
		close()
	end)

	t.test("refused outside a live phase, rooted, too soon or replayed; nothing is sent", function()
		local world = setup()
		world.phase = "Countdown"
		local ok, reason = DoubleJumpService.requestDoubleJump(world.fighter, 1, "F", world.clock.now())
		expect.falsy(ok)
		expect.equal(reason, "jump.context")
		world.phase = "SuddenDeath"
		world.fighter.rootedUntil = world.clock.now() + 1
		_, reason = DoubleJumpService.requestDoubleJump(world.fighter, 2, "F", world.clock.now())
		expect.equal(reason, "jump.busy")
		world.fighter.rootedUntil = -math.huge
		expect.truthy((DoubleJumpService.requestDoubleJump(world.fighter, 3, "F", world.clock.now())))
		world.clock.advance(INTERVAL / 2)
		_, reason = DoubleJumpService.requestDoubleJump(world.fighter, 4, "F", world.clock.now())
		expect.equal(reason, "jump.cooldown")
		world.clock.advance(INTERVAL)
		_, reason = DoubleJumpService.requestDoubleJump(world.fighter, 4, "F", world.clock.now())
		expect.equal(reason, "net.invalid") -- seq 4 was already used
		expect.truthy((DoubleJumpService.requestDoubleJump(world.fighter, 5, "F", world.clock.now())))
		expect.equal(#world.sent, 2)
		close()
	end)

	t.test("a player in no duel is refused; playerRemoving forgets the seq", function()
		local world = setup()
		local ok, reason = DoubleJumpService.requestDoubleJump(12345, 1, "F", world.clock.now())
		expect.falsy(ok)
		expect.equal(reason, "jump.context")
		expect.truthy((DoubleJumpService.requestDoubleJump(world.fighter, 7, "R", world.clock.now())))
		DoubleJumpService.playerRemoving({ UserId = 91 } :: any)
		world.clock.advance(INTERVAL)
		expect.truthy((DoubleJumpService.requestDoubleJump(world.fighter, 1, "R", world.clock.now())))
		close()
	end)
end
