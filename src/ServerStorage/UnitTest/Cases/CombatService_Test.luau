--!strict
-- CombatService_Test: unit tests for ServerScriptService.Server.Services.CombatService.
-- Server only (ServerStorage.UnitTest). Edit mode: init()/start() are never called. The service runs on a FakeClock
-- with a recording sender and no Heartbeat (useDeps), against a fake match owner (a MatchPort built here) and
-- unparented root parts, so nothing is parented into the place. Its projectile query parameters include no part, so
-- the only things a projectile can meet are the opponent's capsule, the Bounds and its lifetime.
-- Contract (DESIGN §5.5-§5.7, §5.9, §12 #10-#13, §13.2 Part 4):
--   * an accepted throw sends ThrowStarted whose releaseAt IS the server projectile's spawn time (releaseAt = now -
--     lag + windup) and whose squishy and stats come from the match snapshot; the match owner counts it;
--   * the projectile is analytic (ProjectileMath) and its first touch of the opponent's capsule is a `player` impact
--     at the exact entry point (sphere radius + capsule radius from the capsule axis), sent to the match;
--   * canDamage: an invulnerable victim is passed through; a match that left Active/SuddenDeath before the release
--     discards the throw (`expired` at the origin);
--   * hits of one step reach the match owner in one batch, in impact order; a hit the owner refuses lets that
--     projectile fly on;
--   * limits: cooldown (throw.cooldown), 4 live per thrower (throw.tooMany), context (throw.context), a seq outside
--     the window is a payload violation; ProjectileMaxLifetime, and leaving the Bounds, expire a projectile;
--   * a Dragon Rush lane (gravity 0) hits the opponent once, flies on to its end and never counts as a live throw; it
--     tests the capsule at standing height (§5.9: jumping never avoids it) and misses just outside its stadium;
--   * nextThrowAt is always finite (§5.2), also in ThrowRejected before Active;
--   * a request first brings its match up to the request time (port.sync); syncTo sweeps up to `now` (never nested),
--     so an owner that syncs before running its timers counts a hit that lands just before a phase deadline;
--   * the movement guard pivots a player back out of the neutral zone and hands a fall below KillY to the match owner;
--     it holds a fighter on its pad in Countdown and in place during a Dragon Rush root.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type Sent = { remote: string, recipients: { any }, args: { any } }

type PortState = {
	phase: string,
	invuln: { [string]: number },
	hits: { any },
	batches: { number },
	flushes: number,
	accepted: { number },
	oob: { number },
}

local STEP = 1 / 60
local A_ROOT = Vector3.new(0, 3, -40)
local B_ROOT = Vector3.new(0, 3, 20)
local LIVE: { [string]: boolean } = { Active = true, SuddenDeath = true }

return function(t: Context)
	local expect = t.expect
	local CombatService = t.requireServer("Services/CombatService")
	local HitMath = t.requireServer("Logic/HitMath")
	local ProjectileMath = t.requireShared("ProjectileMath")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local FakeClock = t.requireFake("FakeClock")

	local RULES = Config.Duel.Rules
	local STARTER = Catalog.get(Catalog.starterId())
	local THROW = STARTER.throw

	local clock = FakeClock.new(1000)
	local sent: { Sent } = {}
	local violations: { string } = {}

	local function setup()
		CombatService.destroy()
		clock = FakeClock.new(1000)
		table.clear(sent)
		table.clear(violations)
		CombatService.useDeps({
			now = clock.now,
			autoStep = false,
			send = function(remote: string, recipients: { any }, ...: any)
				table.insert(sent, { remote = remote, recipients = recipients, args = { ... } })
			end,
			reportViolation = function(_player: any, remote: string)
				table.insert(violations, remote)
			end,
		})
	end

	local function payloads(remote: string): { any }
		local list = {}
		for _, entry in sent do
			if entry.remote == remote then
				table.insert(list, entry.args[1])
			end
		end
		return list
	end

	local function impacts(kind: string?): { any }
		local list = {}
		for _, payload in payloads("ThrowImpact") do
			if kind == nil or payload.kind == kind then
				table.insert(list, payload)
			end
		end
		return list
	end

	local function zonesFrom(boundsSize: Vector3?): { [string]: any }
		local zones = {}
		for name, volume in WorldLayout.Arena.zones do
			zones[name] = { cframe = CFrame.new(volume.position), size = volume.size }
		end
		if boundsSize then
			zones.Bounds = { cframe = CFrame.new(0, 0, 0), size = boundsSize }
		end
		return zones
	end

	local function rootPart(position: Vector3, facing: Vector3): Part
		local model = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name = "HumanoidRootPart"
		part.Size = Vector3.new(2, 2, 1)
		part.CFrame = CFrame.lookAt(position, position + facing)
		part.Parent = model
		model.PrimaryPart = part
		return part
	end

	local function fighter(userId: number, side: string, root: Part, player: any?): any
		return CombatService.newFighter({
			userId = userId,
			player = player,
			side = side,
			squishyId = STARTER.id,
			getRoot = function(): BasePart?
				return root
			end,
			isAlive = function(): boolean
				return true
			end,
		})
	end

	-- A fake match owner: lives are not tracked, invulnerability is (HitInvulnSeconds after an applied hit).
	local function makePort(a: any, b: any, boundsSize: Vector3?): (any, PortState)
		local state: PortState = {
			phase = "Active",
			invuln = { A = -math.huge, B = -math.huge },
			hits = {},
			batches = {},
			flushes = 0,
			accepted = {},
			oob = {},
		}
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {}
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {}
		local port = {
			matchId = "match-test",
			arena = {
				slot = 1,
				floorY = 0,
				killY = RULES.OutOfBounds.KillYOffset,
				zones = zonesFrom(boundsSize),
				geometry = nil,
				raycastParams = params,
				overlapParams = overlap,
			},
			fighters = { a, b },
			phase = function(): string
				return state.phase
			end,
			cooldownMultiplier = function(): number
				return 1
			end,
			placement = function(f: any): CFrame?
				return CFrame.new(if f.side == "A" then A_ROOT else B_ROOT)
			end,
			canBeHit = function(victim: any, at: number): boolean
				return LIVE[state.phase] == true and at >= state.invuln[victim.side]
			end,
			applyHits = function(hits: { any }): { [number]: any }
				table.insert(state.batches, #hits)
				local outcomes = {}
				for index, hit in hits do
					table.insert(state.hits, hit)
					local side = hit.victim.side
					if hit.at >= state.invuln[side] then
						state.invuln[side] = hit.at + RULES.HitInvulnSeconds
						outcomes[index] = { lives = 2, invulnUntil = state.invuln[side], eliminated = false }
					end
				end
				return outcomes
			end,
			flush = function()
				state.flushes += 1
			end,
			throwAccepted = function(f: any)
				table.insert(state.accepted, f.userId)
			end,
			outOfBounds = function(f: any)
				table.insert(state.oob, f.userId)
			end,
		}
		return port, state
	end

	-- Two duelists on their pads (A at -Z facing +Z, B at +Z facing -Z) in a registered Active match.
	local function duel(boundsSize: Vector3?, playerA: any?): (any, any, PortState, Part, Part, any)
		local rootA = rootPart(A_ROOT, Vector3.new(0, 0, 1))
		local rootB = rootPart(B_ROOT, Vector3.new(0, 0, -1))
		local a = fighter(1, "A", rootA, playerA)
		local b = fighter(2, "B", rootB, nil)
		local port, state = makePort(a, b, boundsSize)
		CombatService.registerMatch(port)
		a.nextThrowAt = clock.now() -- Active start
		b.nextThrowAt = clock.now()
		return a, b, state, rootA, rootB, port
	end

	local function releaseOrigin(root: Part): Vector3
		return (root.CFrame * CFrame.new(Config.Combat.ReleaseOffset)).Position
	end

	-- A's throw at `target` (default B's root); returns (accepted, reason).
	local function throwAt(seq: number, rootA: Part, target: Vector3, direction: Vector3?): (boolean, string?)
		local origin = releaseOrigin(rootA)
		local dir = direction or ProjectileMath.solveLaunchDir(origin, target, THROW.speed, THROW.gravity)
		return CombatService.requestThrow(1, seq, dir, origin, clock.now())
	end

	local function runFor(seconds: number)
		local steps = math.ceil(seconds / STEP)
		for _ = 1, steps do
			clock.advance(STEP)
			CombatService.step()
		end
	end

	t.test("an accepted throw: ThrowStarted.releaseAt is the server projectile's spawn time", function()
		setup()
		local a, _, state, rootA = duel(nil, nil)
		local now = clock.now()
		local accepted, reason = throwAt(1, rootA, B_ROOT, nil)
		expect.truthy(accepted)
		expect.equal(reason, nil)
		local started = payloads("ThrowStarted")
		expect.equal(#started, 1)
		local payload = started[1]
		local info = CombatService.projectileInfo(payload.projId)
		expect.truthy(info)
		expect.equal(payload.releaseAt, info.releaseAt) -- §13.2 Part 4: the same number, not a copy of the request
		expect.near(payload.releaseAt, now + THROW.windup, 1e-9) -- ping 0, clientTime = now: no lag compensation
		expect.equal(payload.squishyId, STARTER.id)
		expect.equal(payload.kind, "throw")
		expect.equal(payload.matchId, "match-test")
		expect.equal(payload.seq, 1)
		expect.near(payload.nextThrowAt, payload.releaseAt + THROW.cooldown, 1e-9)
		expect.near(payload.velocity.Magnitude, THROW.speed, 1e-3)
		expect.equal(payload.gravity, THROW.gravity)
		expect.equal(payload.radius, THROW.radius)
		expect.deepEqual(state.accepted, { 1 })
		expect.equal(a.activeProjectiles, 1)
		expect.equal(a.throwsAccepted, 1)
	end)

	t.test("the throw hits the opponent's capsule at its exact entry point and ends there", function()
		setup()
		local a, _, state, rootA = duel(nil, nil)
		local hitInfos = {}
		CombatService.Hit:connect(function(info: any)
			table.insert(hitInfos, info)
		end)
		expect.truthy((throwAt(1, rootA, B_ROOT, nil)))
		local payload = payloads("ThrowStarted")[1]
		runFor(1.5)
		local hits = impacts("player")
		expect.equal(#hits, 1)
		expect.equal(hits[1].victimId, 2)
		expect.equal(hits[1].livesLeft, 2)
		expect.equal(hits[1].eliminated, false)
		expect.equal(#state.hits, 1)
		local at = state.hits[1].at
		expect.truthy(at > payload.releaseAt and at < payload.releaseAt + 1)
		-- The impact point is where the sphere first touches the capsule: radius + capsule radius from its axis.
		local position =
			ProjectileMath.positionAt(payload.origin, payload.velocity, payload.gravity, at - payload.releaseAt)
		local capsule = HitMath.capsule(B_ROOT)
		local distance = HitMath.pointSegDistance(position, capsule.a, capsule.b)
		expect.near(distance, THROW.radius + capsule.radius, 0.01)
		expect.near((hits[1].position - position).Magnitude, 0, 0.01)
		expect.near(hits[1].knockbackDir.Y, 0, 1e-9)
		expect.truthy(hits[1].knockbackDir.Z > 0.9) -- along the travel, away from the thrower
		expect.equal(state.flushes, 1)
		expect.equal(CombatService.projectileCount(), 0)
		expect.equal(a.activeProjectiles, 0)
		expect.equal(a.hits, 1)
		expect.equal(#hitInfos, 1)
		expect.equal(hitInfos[1].kind, "throw")
		expect.equal(#impacts(nil), 1)
	end)

	t.test("an invulnerable victim is passed through; the projectile expires when it leaves the Bounds", function()
		setup()
		local _, _, state, rootA = duel(nil, nil)
		state.invuln.B = math.huge
		expect.truthy((throwAt(1, rootA, B_ROOT, nil)))
		runFor(RULES.ProjectileMaxLifetime + 0.5)
		expect.equal(#state.hits, 0)
		expect.equal(#impacts("player"), 0)
		local expired = impacts("expired")
		expect.equal(#expired, 1)
		expect.falsy(HitMath.inZone(expired[1].position, zonesFrom(nil).Bounds, 0))
		expect.equal(CombatService.projectileCount(), 0)
	end)

	t.test("a match that left Active before the release discards the throw at its origin", function()
		setup()
		local a, _, state, rootA = duel(nil, nil)
		expect.truthy((throwAt(1, rootA, B_ROOT, nil)))
		local payload = payloads("ThrowStarted")[1]
		state.phase = "Result"
		runFor(0.5)
		local expired = impacts("expired")
		expect.equal(#expired, 1)
		expect.equal(expired[1].projId, payload.projId)
		expect.near((expired[1].position - payload.origin).Magnitude, 0, 1e-6)
		expect.equal(#state.hits, 0)
		expect.equal(a.activeProjectiles, 0)
	end)

	t.test(
		"cooldown, then at most MaxActiveProjectilesPerPlayer live throws; rejections answer ThrowRejected",
		function()
			setup()
			local a, _, _, rootA = duel(nil, { UserId = 1 })
			expect.truthy((throwAt(1, rootA, B_ROOT, nil)))
			local ok, reason = throwAt(2, rootA, B_ROOT, nil)
			expect.falsy(ok)
			expect.equal(reason, "throw.cooldown")
			local rejected = {}
			for _, entry in sent do
				if entry.remote == "ThrowRejected" then
					table.insert(rejected, entry.args)
				end
			end
			expect.equal(#rejected, 1)
			expect.equal(rejected[1][1], 2)
			expect.equal(rejected[1][2], "throw.cooldown")
			expect.near(rejected[1][3], a.nextThrowAt, 1e-9)
			for seq = 3, 1 + RULES.MaxActiveProjectilesPerPlayer do
				a.nextThrowAt = -math.huge
				expect.truthy((throwAt(seq, rootA, B_ROOT, nil)))
			end
			expect.equal(a.activeProjectiles, RULES.MaxActiveProjectilesPerPlayer)
			a.nextThrowAt = -math.huge
			local okMax, reasonMax = throwAt(2 + RULES.MaxActiveProjectilesPerPlayer, rootA, B_ROOT, nil)
			expect.falsy(okMax)
			expect.equal(reasonMax, "throw.tooMany")
			local counters = CombatService.counters()
			expect.equal(counters.rejected["throw.cooldown"], 1)
			expect.equal(counters.rejected["throw.tooMany"], 1)
			expect.equal(counters.accepted, RULES.MaxActiveProjectilesPerPlayer)
		end
	)

	t.test("no throw outside Active/SuddenDeath; a seq outside the window is a payload violation", function()
		setup()
		local _, _, state, rootA = duel(nil, { UserId = 1 })
		state.phase = "Countdown"
		local ok, reason = throwAt(1, rootA, B_ROOT, nil)
		expect.falsy(ok)
		expect.equal(reason, "throw.context")
		state.phase = "Active"
		local okSeq, reasonSeq = throwAt(1 + Config.Combat.Throw.seqWindow, rootA, B_ROOT, nil)
		expect.falsy(okSeq)
		expect.equal(reasonSeq, "net.invalid")
		expect.deepEqual(violations, { "ThrowRequest" })
		expect.equal(#payloads("ThrowStarted"), 0)
	end)

	t.test("two hits found in one step reach the match owner as one batch, in impact order", function()
		setup()
		local a, _, state, rootA = duel(nil, nil)
		expect.truthy((throwAt(1, rootA, B_ROOT, nil)))
		clock.advance(0.05)
		a.nextThrowAt = -math.huge
		expect.truthy((throwAt(2, rootA, B_ROOT, nil)))
		clock.advance(1.0)
		CombatService.step() -- one long step: both projectiles reach the capsule inside it
		expect.deepEqual(state.batches, { 2 })
		expect.equal(#state.hits, 2)
		expect.truthy(state.hits[1].at < state.hits[2].at)
		-- The owner applied the first and refused the second (invulnerable): only one player impact, and the second
		-- projectile flies on until it leaves the Bounds.
		expect.equal(#impacts("player"), 1)
		runFor(RULES.ProjectileMaxLifetime)
		expect.equal(#impacts("player"), 1)
		expect.equal(#impacts("expired"), 1)
		expect.equal(CombatService.projectileCount(), 0)
	end)

	t.test("ProjectileMaxLifetime ends a projectile that is still inside the Bounds", function()
		setup()
		local _, _, _, rootA = duel(Vector3.new(4000, 4000, 4000), nil)
		local pitch = math.rad(60)
		local dir = Vector3.new(0, math.sin(pitch), math.cos(pitch))
		expect.truthy((throwAt(1, rootA, B_ROOT, dir)))
		local payload = payloads("ThrowStarted")[1]
		runFor(RULES.ProjectileMaxLifetime + 0.5)
		local expired = impacts("expired")
		expect.equal(#expired, 1)
		local expected =
			ProjectileMath.positionAt(payload.origin, payload.velocity, payload.gravity, RULES.ProjectileMaxLifetime)
		expect.near((expired[1].position - expected).Magnitude, 0, 1e-3)
	end)

	t.test("a Dragon Rush lane hits the opponent once, flies on to its end and is not a live throw", function()
		setup()
		local a, _, state = duel(nil, nil)
		local releaseAt = clock.now() + 0.9
		local origin = Vector3.new(0, 4.5, -38)
		local direction = Vector3.new(0, 0, 1)
		local projId = CombatService.launchLane({
			caster = a,
			player = nil,
			squishyId = "dragon",
			origin = origin,
			direction = direction,
			length = 80,
			radius = 4,
			speed = 260,
			releaseAt = releaseAt,
			stoppedByGeometry = true,
		})
		expect.equal(a.activeProjectiles, 0)
		runFor(0.9 + 80 / 260 + 0.2)
		local hits = impacts("player")
		expect.equal(#hits, 1)
		expect.equal(hits[1].projId, projId)
		expect.equal(hits[1].victimId, 2)
		expect.equal(#state.hits, 1)
		expect.equal(state.hits[1].kind, "lane")
		expect.truthy(state.hits[1].at >= releaseAt)
		local ends = impacts("geometry")
		expect.equal(#ends, 1)
		expect.near((ends[1].position - (origin + direction * 80)).Magnitude, 0, 1e-3)
		expect.equal(CombatService.projectileCount(), 0)
	end)

	t.test("movement guard: the neutral zone pivots back; below KillY goes to the match owner", function()
		setup()
		local a, _, state, rootA = duel(nil, { UserId = 1 })
		local now = clock.now()
		rootA.CFrame = CFrame.new(0, 3, -30)
		CombatService.guardStep(now)
		expect.equal(#state.oob, 0)
		rootA.CFrame = CFrame.new(0, 3, -7) -- the neutral zone (Z -8..8), still inside own half + 2
		CombatService.guardStep(now + 0.2)
		expect.near((rootA.Position - Vector3.new(0, 3, -30)).Magnitude, 0, 1e-3)
		expect.equal(CombatService.counters().guardPivots, 1)
		rootA.CFrame = CFrame.new(0, RULES.OutOfBounds.KillYOffset - 5, -30)
		CombatService.guardStep(now + 0.4)
		expect.deepEqual(state.oob, { a.userId })
	end)

	-- A lane from A's side straight down X = 0 (sphere radius 4 at floor + 4.5): its stadium reaches 4 + 1.3 studs from
	-- the lane line for a standing player.
	local function laneAt(a: any): number
		return CombatService.launchLane({
			caster = a,
			player = nil,
			squishyId = "dragon",
			origin = Vector3.new(0, 4.5, -38),
			direction = Vector3.new(0, 0, 1),
			length = 80,
			radius = 4,
			speed = 260,
			releaseAt = clock.now() + 0.9,
			stoppedByGeometry = true,
		})
	end

	t.test("Dragon Rush: jumping never avoids the lane (the capsule is tested at standing height)", function()
		setup()
		local a, _, state, _, rootB = duel(nil, nil)
		-- B 4.5 studs off the lane line, at the top of a 7.2-stud jump (HRP 3 + 7.2 above the floor): the capsule at
		-- that height would pass over the lane sphere (axis 8.5 .. 12, 4 studs above the lane centre).
		rootB.CFrame = CFrame.new(4.5, 3 + 7.2, 20)
		laneAt(a)
		runFor(0.9 + 80 / 260 + 0.2)
		expect.equal(#impacts("player"), 1)
		expect.equal(state.hits[1].kind, "lane")
	end)

	t.test("Dragon Rush: a player just outside the stadium (radius + 1.3 from the lane line) is not hit", function()
		setup()
		local a, _, state, _, rootB = duel(nil, nil)
		rootB.CFrame = CFrame.new(4 + Config.Combat.Hitbox.radius + 0.2, 3, 20)
		laneAt(a)
		runFor(0.9 + 80 / 260 + 0.2)
		expect.equal(#impacts("player"), 0)
		expect.equal(#state.hits, 0)
		expect.equal(#impacts("geometry"), 1) -- the lane still ends at its endpoint
	end)

	t.test("nextThrowAt is always finite: a new fighter and a new practice actor start at the clock", function()
		setup()
		local f = fighter(7, "A", rootPart(A_ROOT, Vector3.new(0, 0, 1)), nil)
		expect.equal(f.nextThrowAt, clock.now())
		local actor = CombatService.practiceActor({ UserId = 8 } :: any)
		expect.equal(actor.nextThrowAt, clock.now())
		-- A throw before Active is refused by the phase and ThrowRejected echoes that finite value.
		local rootA = rootPart(A_ROOT, Vector3.new(0, 0, 1))
		local a = fighter(1, "A", rootA, { UserId = 1 })
		local b = fighter(2, "B", rootPart(B_ROOT, Vector3.new(0, 0, -1)), nil)
		local port, state = makePort(a, b, nil)
		state.phase = "Countdown"
		CombatService.registerMatch(port)
		local ok, reason = throwAt(1, rootA, B_ROOT, nil)
		expect.falsy(ok)
		expect.equal(reason, "throw.context")
		local rejected = nil
		for _, entry in sent do
			if entry.remote == "ThrowRejected" then
				rejected = entry.args
			end
		end
		expect.truthy(rejected ~= nil)
		local echoed = rejected[3]
		expect.truthy(type(echoed) == "number" and echoed == echoed and math.abs(echoed) < 1e10)
	end)

	t.test(
		"a request first brings the match up to its time (port.sync): a press as Countdown ends is accepted",
		function()
			setup()
			local rootA = rootPart(A_ROOT, Vector3.new(0, 0, 1))
			local a = fighter(1, "A", rootA, nil)
			local b = fighter(2, "B", rootPart(B_ROOT, Vector3.new(0, 0, -1)), nil)
			local port, state = makePort(a, b, nil)
			state.phase = "Countdown" -- the stored phase; the Countdown's deadline has just passed
			local synced: { number } = {}
			port.sync = function(now: number)
				table.insert(synced, now)
				if state.phase == "Countdown" then
					state.phase = "Active" -- what the owner's tick does at the deadline (and nextThrowAt = Active start)
					a.nextThrowAt = now
					b.nextThrowAt = now
				end
			end
			CombatService.registerMatch(port)
			local ok, reason = throwAt(1, rootA, B_ROOT, nil)
			expect.equal(reason, nil)
			expect.truthy(ok)
			expect.deepEqual(synced, { clock.now() })
		end
	)

	t.test("syncTo sweeps up to `now` once; never from inside a step", function()
		setup()
		local _, _, state, rootA = duel(nil, nil)
		expect.truthy((throwAt(1, rootA, B_ROOT, nil)))
		clock.advance(1.0) -- long enough to reach B
		CombatService.syncTo(clock.now())
		expect.equal(#state.hits, 1)
		expect.equal(CombatService.lastStepTime(), clock.now())
		CombatService.syncTo(clock.now()) -- already swept to this time: nothing runs
		expect.equal(state.flushes, 1)
		-- Re-entry: an owner that syncs from inside the step it is called by gets no nested step.
		setup()
		local a2, _, state2, rootA2 = duel(nil, nil)
		local port2 = CombatService.portOf(a2)
		local nested: { number } = {}
		local applyHits = port2.applyHits
		port2.applyHits = function(hits: { any }, now: number): { [number]: any }
			table.insert(nested, CombatService.lastStepTime())
			CombatService.syncTo(now + 10)
			table.insert(nested, CombatService.lastStepTime())
			return applyHits(hits, now)
		end
		expect.truthy((throwAt(1, rootA2, B_ROOT, nil)))
		clock.advance(1.0)
		CombatService.step()
		expect.equal(#state2.hits, 1)
		expect.equal(nested[1], nested[2]) -- the nested syncTo did not step
	end)

	-- The match owner's order (DuelService.stepMatch): sweep the projectiles up to `now`, then run the timers to `now`.
	-- With A at 2 lives and B at 3, A's throw lands on B a few ms before the Active deadline: 2-2 at time-up is sudden
	-- death, not a win for B on time.
	t.test("a hit just before the Active deadline counts when the owner syncs before advancing its timers", function()
		local DuelRules = t.requireServer("Logic/DuelRules")
		-- 1. When does A's throw (thrown at the clock's start) reach B? Same setup, fake owner.
		setup()
		local start = clock.now()
		local _, _, probe, rootProbe = duel(nil, nil)
		expect.truthy((throwAt(1, rootProbe, B_ROOT, nil)))
		runFor(1.5)
		expect.equal(#probe.hits, 1)
		local impactIn = probe.hits[1].at - start

		-- 2. A real DuelRules match whose Active deadline is 5 ms after that impact; A already lost a life.
		local function ownerAt(deadline: number): { state: any }
			local base = deadline - RULES.MatchSeconds - RULES.CountdownSeconds
			local s = DuelRules.new("sync-match", { A = { userId = 1 }, B = { userId = 2 } }, base)
			for _, kind in { "streamed", "positioned" } do
				s = DuelRules.step(s, { kind = kind, side = "A" }, base)
				s = DuelRules.step(s, { kind = kind, side = "B" }, base)
			end
			s = DuelRules.step(s, { kind = "tick" }, base + RULES.CountdownSeconds)
			s = DuelRules.step(s, { kind = "hit", victim = "A", at = base + RULES.CountdownSeconds + 1 }, base + 4)
			expect.equal(s.phase, "Active")
			expect.near(s.phaseEndsAt, deadline, 1e-6)
			return { state = s }
		end
		local function run(syncFirst: boolean): any
			setup()
			local deadline = clock.now() + impactIn + 0.005
			local owner = ownerAt(deadline)
			local _, _, _, rootA = duel(nil, nil)
			local port = CombatService.portOf(CombatService.getFighter(1))
			port.phase = function(): string
				return owner.state.phase
			end
			port.canBeHit = function(victim: any, at: number): boolean
				return DuelRules.canBeHit(owner.state, victim.side, at)
			end
			port.applyHits = function(hits: { any }, now: number): { [number]: any }
				local list = {}
				for index, hit in hits do
					list[index] = { victim = hit.victim.side, at = hit.at }
				end
				local outcomes = {}
				local s, effects = DuelRules.step(owner.state, { kind = "hits", hits = list }, now)
				owner.state = s
				for _, effect in effects do
					if effect.kind == "lifeLost" then
						outcomes[1] = { lives = effect.lives, invulnUntil = effect.invulnUntil, eliminated = false }
					end
				end
				return outcomes
			end
			local thrownAt = clock.now()
			expect.truthy((throwAt(1, rootA, B_ROOT, nil)))
			runFor(impactIn - 0.1) -- the frames before the impact (no deadline in them)
			-- One late frame holds the impact and then, 5 ms later, the deadline.
			clock.advance(thrownAt + impactIn + 0.02 - clock.now())
			local now = clock.now()
			if syncFirst then
				CombatService.syncTo(now)
				owner.state = DuelRules.step(owner.state, { kind = "tick" }, now)
			else
				owner.state = DuelRules.step(owner.state, { kind = "tick" }, now)
				CombatService.step(now)
			end
			return owner.state
		end
		local synced = run(true)
		expect.equal(synced.phase, "SuddenDeath")
		expect.equal(synced.participants.B.lives, RULES.Lives - 1)
		expect.falsy(synced.ended)
		-- The wrong order (timers first) loses that hit: B would win on time.
		local late = run(false)
		expect.truthy(late.ended)
		expect.equal(late.outcome.winner, "B")
		expect.equal(late.participants.B.lives, RULES.Lives)
	end)

	t.test("movement guard: walking NEXT TO round cover never pivots back; inside it does (bug 2026-10-15)", function()
		setup()
		local _, _, _, rootA, _, port = duel(nil, { UserId = 1 })
		-- Pinewood's stump: a Cylinder 3.5 long (its X axis, stood up) and 6.3 across, on the floor of A's half.
		local stump = Instance.new("Part")
		stump.Shape = Enum.PartType.Cylinder
		stump.Size = Vector3.new(3.5, 6.3, 6.3)
		stump.CFrame = CFrame.new(10, 1.75, -30) * CFrame.Angles(0, 0, math.rad(90))
		stump.Anchored = true
		stump.Parent = workspace
		port.arena.overlapParams.FilterDescendantsInstances = { stump }
		local ok, err = pcall(function()
			local now = clock.now()
			local d = 4.15 * math.cos(math.rad(45)) -- 45 degrees off its centre, 1 stud clear of its side
			rootA.CFrame = CFrame.new(10 + d + 2, 3, -30 + d + 2)
			CombatService.guardStep(now)
			rootA.CFrame = CFrame.new(10 + d, 3, -30 + d) -- inside the stump's bounding box, outside the stump
			CombatService.guardStep(now + 0.2)
			expect.equal(CombatService.counters().guardPivots, 0)
			rootA.CFrame = CFrame.new(10.5, 3, -30) -- inside the stump itself
			CombatService.guardStep(now + 0.4)
			expect.equal(CombatService.counters().guardPivots, 1)
		end)
		stump:Destroy()
		assert(ok, err)
	end)

	t.test("movement guard: Countdown holds the fighter on its pad; a Dragon Rush root holds it in place", function()
		setup()
		local a, _, state, rootA = duel(nil, { UserId = 1 })
		local now = clock.now()
		local tolerance = Config.Combat.MovementGuard.holdToleranceStuds
		state.phase = "Countdown"
		rootA.CFrame = CFrame.new(A_ROOT + Vector3.new(tolerance * 0.5, 0, 0)) -- settling on the pad: fine
		CombatService.guardStep(now)
		expect.equal(CombatService.counters().guardPivots, 0)
		rootA.CFrame = CFrame.new(A_ROOT + Vector3.new(tolerance + 3, 0, 0)) -- walked off the pad
		CombatService.guardStep(now + 0.2)
		expect.equal(CombatService.counters().guardPivots, 1)
		expect.near((rootA.Position - A_ROOT).Magnitude, 0, 1e-3)
		-- Active, rooted by Dragon Rush at (10, 3, -30): walking away is pulled back to where the root began.
		state.phase = "Active"
		local spot = Vector3.new(10, 3, -30)
		a.rootedUntil = now + 5
		rootA.CFrame = CFrame.new(spot)
		CombatService.guardStep(now + 1)
		rootA.CFrame = CFrame.new(spot + Vector3.new(0, 0, 4))
		CombatService.guardStep(now + 1.2)
		expect.equal(CombatService.counters().guardPivots, 2)
		expect.near((rootA.Position - spot).Magnitude, 0, 1e-3)
		-- The root is over: moving is free again.
		a.rootedUntil = now
		rootA.CFrame = CFrame.new(spot + Vector3.new(0, 0, 3))
		CombatService.guardStep(now + 2)
		expect.equal(CombatService.counters().guardPivots, 2)
	end)

	-- Spec phase 5: the four Epic ultimates (launchUlt, launchArea). The roots here are plain tables (Position and
	-- CFrame), so these cases need no engine part.
	local ULT = Config.Abilities
	local STAND = Config.Combat.Hitbox.radius - Config.Combat.Hitbox.bottomOffset -- HRP height of a standing player

	local function tableRoot(position: Vector3): any
		return { Position = position, CFrame = CFrame.new(position), Parent = nil }
	end

	-- A registered Active match whose roots are tables: A at (0, 3, -40), B at `bAt` (default (0, 3, 20)).
	local function ultDuel(bAt: Vector3?): (any, any, PortState, any, any)
		local rootA = tableRoot(A_ROOT)
		local rootB = tableRoot(bAt or B_ROOT)
		local a = fighter(1, "A", rootA, nil)
		local b = fighter(2, "B", rootB, nil)
		local port, state = makePort(a, b, nil)
		CombatService.registerMatch(port)
		return a, b, state, rootA, rootB
	end

	local function ultSpec(a: any, overrides: { [string]: any }): any
		local spec: { [string]: any } = {
			caster = a,
			player = nil,
			squishyId = "bird",
			origin = Vector3.new(0, 4.8, -38),
			direction = Vector3.new(0, 0, 1),
			length = 80,
			radius = ULT.flock_volley.radius,
			speed = ULT.flock_volley.speed,
			releaseAt = clock.now() + 0.35,
			stoppedByGeometry = false,
			floorY = 0,
		}
		for key, value in overrides do
			spec[key] = value
		end
		return spec
	end

	t.test("a Flock Volley bird hits the opponent once and ends there; the hit is an ultimate, not a throw", function()
		setup()
		local a, _, state = ultDuel(nil)
		local infos = {}
		CombatService.Hit:connect(function(info: any)
			table.insert(infos, info)
		end)
		local projId = CombatService.launchUlt(ultSpec(a, {}))
		expect.equal(a.activeProjectiles, 0) -- never a live throw
		runFor(0.35 + 60 / 75 + 0.2)
		local hits = impacts("player")
		expect.equal(#hits, 1)
		expect.equal(hits[1].projId, projId)
		expect.equal(#impacts(nil), 1) -- it ended at the hit: no end impact
		expect.equal(state.hits[1].kind, "ult")
		expect.equal(infos[1].kind, "ult")
		expect.equal(CombatService.projectileCount(), 0)
	end)

	t.test("a Flock Volley bird stopped by cover ends there with a geometry impact", function()
		setup()
		local a = ultDuel(Vector3.new(20, 3, 20)) -- B off the bird's line
		CombatService.launchUlt(ultSpec(a, { length = 20, stoppedByGeometry = true }))
		runFor(0.35 + 20 / 75 + 0.2)
		local ends = impacts("geometry")
		expect.equal(#ends, 1)
		expect.near((ends[1].position - Vector3.new(0, 4.8, -18)).Magnitude, 0, 1e-3)
		expect.equal(#impacts("player"), 0)
	end)

	local function roller(a: any): number
		local R = ULT.sprinkle_roller
		return CombatService.launchUlt(ultSpec(a, {
			squishyId = "donut",
			origin = Vector3.new(0, R.laneHeightAboveFloor, -34),
			length = R.maxLength,
			radius = R.radius,
			speed = R.speed,
			releaseAt = clock.now() + R.telegraphSeconds,
			flyOn = true,
			clearHeight = R.clearHeight,
		}))
	end

	t.test("Sprinkle Roller: a body touching the 6-stud lane is hit once; the roller rolls on to its end", function()
		setup()
		local R = ULT.sprinkle_roller
		local reach = R.radius + Config.Combat.Hitbox.radius
		local a, _, state = ultDuel(Vector3.new(reach - 0.2, STAND, 20))
		roller(a)
		runFor(R.telegraphSeconds + R.maxLength / R.speed + 0.2)
		expect.equal(#impacts("player"), 1)
		expect.equal(state.hits[1].kind, "ult")
		expect.equal(#impacts("expired"), 1) -- it rolled on to its end
		expect.equal(CombatService.projectileCount(), 0)
	end)

	t.test("Sprinkle Roller: jumped (feet above 3 studs) or just outside the lane, no hit", function()
		setup()
		local R = ULT.sprinkle_roller
		local a, _, _, _, rootB = ultDuel(Vector3.new(0, STAND + R.clearHeight + 0.5, 20))
		roller(a)
		runFor(R.telegraphSeconds + R.maxLength / R.speed + 0.2)
		expect.equal(#impacts("player"), 0)
		setup()
		local reach = R.radius + Config.Combat.Hitbox.radius
		local a2 = ultDuel(Vector3.new(reach + 0.2, STAND, 20))
		roller(a2)
		runFor(R.telegraphSeconds + R.maxLength / R.speed + 0.2)
		expect.equal(#impacts("player"), 0)
		-- A body standing low still on the floor (feet just under 3 studs up) is hit.
		setup()
		local a3, _, _, _, rootB3 = ultDuel(Vector3.new(0, STAND + R.clearHeight - 0.5, 20))
		roller(a3)
		runFor(R.telegraphSeconds + R.maxLength / R.speed + 0.2)
		expect.equal(#impacts("player"), 1)
		expect.truthy(rootB ~= nil and rootB3 ~= nil)
	end)

	t.test("Rain Check: a drop hits a player whose feet are within 1.5 studs when it lands, not before", function()
		setup()
		local a, _, state = ultDuel(nil)
		local landAt = clock.now() + 1
		local projId = CombatService.launchArea({
			caster = a,
			player = nil,
			squishyId = "cloud_bunny",
			position = Vector3.new(1, 0, 20), -- 1 stud from B's feet
			radius = ULT.rain_check.dropHitRadius,
			at = landAt,
			floorY = 0,
		})
		runFor(0.9)
		expect.equal(#impacts(nil), 0)
		runFor(0.2)
		local hits = impacts("player")
		expect.equal(#hits, 1)
		expect.equal(hits[1].projId, projId)
		expect.near(state.hits[1].at, landAt, 1e-9)
		expect.equal(state.hits[1].kind, "ult")
		expect.equal(CombatService.projectileCount(), 0)
	end)

	t.test("Rain Check: a drop that misses sends nothing; a second one inside the invulnerability passes", function()
		setup()
		local a = ultDuel(nil)
		local function drop(at: Vector3, landAt: number)
			CombatService.launchArea({
				caster = a,
				player = nil,
				squishyId = "cloud_bunny",
				position = at,
				radius = ULT.rain_check.dropHitRadius,
				at = landAt,
				floorY = 0,
			})
		end
		drop(Vector3.new(5, 0, 20), clock.now() + 0.5) -- 5 studs away: a miss
		drop(Vector3.new(0, 0, 20), clock.now() + 1)
		drop(Vector3.new(0.5, 0, 20), clock.now() + 1.36) -- inside the 1.5 s invulnerability of the first hit
		runFor(2)
		expect.equal(#impacts("player"), 1)
		expect.equal(#impacts(nil), 1) -- misses and refused drops send nothing
		expect.equal(CombatService.projectileCount(), 0)
	end)

	local function bubble(a: any, overrides: { [string]: any }?): number
		local B = ULT.bubble_pop
		local spec = ultSpec(a, {
			squishyId = "cupcake_axolotl",
			length = B.maxLength,
			radius = B.radius,
			speed = B.speed,
			releaseAt = clock.now() + B.telegraphSeconds,
			splashRadius = B.splashRadius,
		})
		local extra: { [string]: any } = overrides or {}
		for key, value in extra do
			spec[key] = value
		end
		return CombatService.launchUlt(spec)
	end

	t.test("Bubble Pop: it pops on the opponent and the splash takes one life", function()
		setup()
		local a, _, state = ultDuel(Vector3.new(0, STAND, 0))
		bubble(a, { origin = Vector3.new(0, 4.8, -30) })
		runFor(0.5 + 1.2 + 0.2)
		expect.equal(#impacts("player"), 1)
		expect.equal(#impacts(nil), 1)
		expect.equal(state.hits[1].kind, "ult")
	end)

	t.test(
		"Bubble Pop: popping after 1.2 s, its splash hits feet within 6 studs of the pop and misses past it",
		function()
			local B = ULT.bubble_pop
			local popAt = Vector3.new(0, 4.8, -38 + B.maxLength) -- where the 1.2 s flight ends
			setup()
			local a, _, _, _, _ = ultDuel(Vector3.new(4, STAND, popAt.Z))
			bubble(a, {})
			runFor(0.5 + 1.2 + 0.2)
			local hits = impacts("player")
			expect.equal(#hits, 1)
			expect.near((hits[1].position - popAt).Magnitude, 0, 0.05) -- the hit is at the pop point
			setup()
			local a2 = ultDuel(Vector3.new(B.splashRadius + 1, STAND, popAt.Z))
			bubble(a2, {})
			runFor(0.5 + 1.2 + 0.2)
			expect.equal(#impacts("player"), 0)
			local ends = impacts("expired")
			expect.equal(#ends, 1) -- the pop with nobody near
			expect.near((ends[1].position - popAt).Magnitude, 0, 0.05)
		end
	)

	t.test("unregisterMatch drops the match's projectiles without impacts", function()
		setup()
		local _, _, _, rootA = duel(nil, nil)
		expect.truthy((throwAt(1, rootA, B_ROOT, nil)))
		CombatService.unregisterMatch("match-test")
		runFor(0.5)
		expect.equal(#impacts(nil), 0)
		expect.equal(CombatService.projectileCount(), 0)
		expect.equal(CombatService.getFighter(1), nil)
		-- Clean up for the next case file: the live dependencies come back.
		CombatService.destroy()
		CombatService.useDeps(nil)
	end)
end
