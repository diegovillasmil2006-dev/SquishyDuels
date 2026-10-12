--!strict
-- CombatCatch_Test: unit tests for feature 1 (2026-10-11, the charge throw and the catch) in
-- ServerScriptService.Server.Services.CombatService (design: the combat-effects page "Squishy Combat FP v2.html").
-- Server only (ServerStorage.UnitTest). Edit mode, as CombatService_Test: a FakeClock, a recording sender, no Heartbeat
-- (useDeps), a fake match owner built here, and plain stand-in roots (a table with Position and CFrame: the service
-- only reads those), so nothing is parented into the place.
-- Contract:
--   * the charge is the server's: ChargeStart (clientTime, lag-compensated) then a ThrowRequest; c = the time between
--     them (from the throw's ready moment at the earliest) / Charge.seconds, clamped; no start (or a used one) is 0;
--     the speed is × (1 + speedGain·c) and ThrowStarted.power = c;
--   * CatchRequest opens the window [press, press + windowSeconds]; an opponent's normal throw that comes within
--     radiusStuds of the catcher's centre (HRP + 1.5) while moving toward it inside the window is caught at that
--     entry point: no ThrowImpact, CatchEvent "caught", no longer a live throw; the window is used up;
--   * a window that closed before the throw arrived, or opened only once it was going away, catches nothing;
--   * a Dragon Rush lane and an Epic ultimate's projectile are never caught;
--   * crushSeconds (1.02) later the burst: the thrower loses 1 life (a hit by the catcher, kind "catch", force: even
--     inside invulnerability), Hit fires, CatchEvent "burst" carries the lives; the match ending meanwhile: no life;
--   * the press: cooldownSeconds (0.75), busy while crushing (until handsBackSeconds after the catch), only in a live
--     duel; it drops a charge record; no throw while the hands are open or crushing (throw.busy).

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
	lives: { [string]: number },
	hits: { any },
}

type Root = { Position: Vector3, CFrame: CFrame }

local STEP = 1 / 60
local A_ROOT = Vector3.new(0, 3, -40)
local B_ROOT = Vector3.new(0, 3, 20)
local LIVE: { [string]: boolean } = { Active = true, SuddenDeath = true }

return function(t: Context)
	local expect = t.expect
	local CombatService = t.requireServer("Services/CombatService")
	local ProjectileMath = t.requireShared("ProjectileMath")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local FakeClock = t.requireFake("FakeClock")

	local RULES = Config.Duel.Rules
	local CHARGE = Config.Combat.Charge
	local CATCH = Config.Combat.Catch
	local STARTER = Catalog.get(Catalog.starterId())
	local THROW = STARTER.throw

	local clock = FakeClock.new(1000)
	local sent: { Sent } = {}

	local function setup()
		CombatService.destroy()
		clock = FakeClock.new(1000)
		table.clear(sent)
		CombatService.useDeps({
			now = clock.now,
			autoStep = false,
			send = function(remote: string, recipients: { any }, ...: any)
				table.insert(sent, { remote = remote, recipients = recipients, args = { ... } })
			end,
			reportViolation = function() end,
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

	local function catchEvents(phase: string): { any }
		local list = {}
		for _, payload in payloads("CatchEvent") do
			if payload.phase == phase then
				table.insert(list, payload)
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

	local function zones(): { [string]: any }
		local list = {}
		for name, volume in WorldLayout.Arena.zones do
			list[name] = { cframe = CFrame.new(volume.position), size = volume.size }
		end
		return list
	end

	local function root(position: Vector3): Root
		return { Position = position, CFrame = CFrame.new(position) }
	end

	local function fighter(userId: number, side: string, r: Root): any
		return CombatService.newFighter({
			userId = userId,
			side = side,
			squishyId = STARTER.id,
			getRoot = function(): BasePart?
				return r :: any
			end,
			isAlive = function(): boolean
				return true
			end,
			now = clock.now(),
		})
	end

	-- A fake match owner: 3 lives a side; invulnerability after an applied hit (a forced hit lands inside it, as
	-- DuelRules' Hit.force); no hit once the match has left Active / SuddenDeath.
	local function duel(): (any, any, PortState)
		local rootA, rootB = root(A_ROOT), root(B_ROOT)
		local a, b = fighter(1, "A", rootA), fighter(2, "B", rootB)
		local state: PortState = {
			phase = "Active",
			invuln = { A = -math.huge, B = -math.huge },
			lives = { A = 3, B = 3 },
			hits = {},
		}
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {}
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {}
		CombatService.registerMatch({
			matchId = "match-catch",
			arena = {
				slot = 1,
				floorY = 0,
				killY = RULES.OutOfBounds.KillYOffset,
				zones = zones(),
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
				local outcomes = {}
				for index, hit in hits do
					local side = hit.victim.side
					if LIVE[state.phase] and (hit.force == true or hit.at >= state.invuln[side]) then
						table.insert(state.hits, hit)
						state.lives[side] -= 1
						state.invuln[side] = math.max(state.invuln[side], hit.at + RULES.HitInvulnSeconds)
						outcomes[index] = {
							lives = state.lives[side],
							invulnUntil = state.invuln[side],
							eliminated = state.lives[side] <= 0,
						}
					end
				end
				return outcomes
			end,
			flush = function() end,
			throwAccepted = function() end,
			outOfBounds = function() end,
		})
		a.nextThrowAt = clock.now() -- Active start
		b.nextThrowAt = clock.now()
		return a, b, state
	end

	local function origin(position: Vector3): Vector3
		return CFrame.new(position) * Config.Combat.ReleaseOffset
	end

	-- `userId`'s throw from its root at `target`; returns (accepted, reason).
	local function throwAt(userId: number, seq: number, target: Vector3): (boolean, string?)
		local from = origin(if userId == 1 then A_ROOT else B_ROOT)
		local dir = ProjectileMath.solveLaunchDir(from, target, THROW.speed, THROW.gravity)
		return CombatService.requestThrow(userId, seq, dir, from, clock.now())
	end

	local function runFor(seconds: number)
		for _ = 1, math.ceil(seconds / STEP) do
			clock.advance(STEP)
			CombatService.step()
		end
	end

	-- Steps up to server time `at` exactly (the last step is shorter).
	local function runUntil(at: number)
		while clock.now() + STEP < at do
			clock.advance(STEP)
			CombatService.step()
		end
		local rest = at - clock.now()
		if rest > 0 then
			clock.advance(rest)
			CombatService.step()
		end
	end

	local function centreOf(position: Vector3): Vector3
		return position + Vector3.new(0, CATCH.centreAboveRootStuds, 0)
	end

	-- Seconds after the release when the thrown path first comes within the catch radius of `centre` (nil: never), and
	-- when it is closest to it.
	local function entryOf(payload: any, centre: Vector3): (number?, number)
		local entry: number? = nil
		local closest, best = 0, math.huge
		for i = 0, 3000 do
			local tau = i / 1000
			local p = ProjectileMath.positionAt(payload.origin, payload.velocity, payload.gravity, tau)
			local d = (p - centre).Magnitude
			if entry == nil and d <= CATCH.radiusStuds then
				entry = tau
			end
			if d < best then
				closest, best = tau, d
			end
		end
		return entry, closest
	end

	-- A's throw at B with B's window opening `lead` seconds before the throw reaches B's catch radius.
	local function caughtThrow(lead: number?): (any, any, PortState, any)
		local a, b, state = duel()
		expect.truthy((throwAt(1, 1, B_ROOT)))
		local payload = payloads("ThrowStarted")[1]
		local entry = entryOf(payload, centreOf(B_ROOT)) :: number
		runUntil(payload.releaseAt + entry - (lead or 0.1))
		expect.truthy((CombatService.requestCatch(2, clock.now())))
		return a, b, state, payload
	end

	-- The charge --------------------------------------------------------------------------------------------------

	t.test(
		"the charge is the server's: ChargeStart then the throw 0.5 s later flies at speed × (1 + 0.85·0.5)",
		function()
			setup()
			duel()
			expect.truthy((CombatService.requestChargeStart(1, clock.now())))
			runFor(0.5)
			expect.truthy((throwAt(1, 1, B_ROOT)))
			local payload = payloads("ThrowStarted")[1]
			local c = payload.power
			expect.truthy(math.abs(c - 0.5) <= STEP) -- the steps land on 1/60 s
			expect.near(payload.velocity.Magnitude, THROW.speed * (1 + CHARGE.speedGain * c), 1e-3)
			-- The record is used up: the next throw (after the cooldown) without a new start is uncharged.
			runFor(THROW.cooldown + THROW.windup + 0.1)
			expect.truthy((throwAt(1, 2, B_ROOT)))
			local second = payloads("ThrowStarted")[2]
			expect.equal(second.power, 0)
			expect.near(second.velocity.Magnitude, THROW.speed, 1e-3)
		end
	)

	t.test("the charge is clamped at 1 and counts only once the throw is ready", function()
		setup()
		duel()
		expect.truthy((CombatService.requestChargeStart(1, clock.now())))
		runFor(3)
		expect.truthy((throwAt(1, 1, B_ROOT)))
		expect.equal(payloads("ThrowStarted")[1].power, 1)
		-- Pressed during the cooldown: the charge counts from the moment the throw is ready (nextThrowAt - windup).
		local readyAt = payloads("ThrowStarted")[1].nextThrowAt - THROW.windup
		runFor(0.1)
		expect.truthy((CombatService.requestChargeStart(1, clock.now())))
		runUntil(readyAt + 0.3)
		expect.truthy((throwAt(1, 2, B_ROOT)))
		expect.near(payloads("ThrowStarted")[2].power, 0.3, 1e-6)
	end)

	t.test("a bad ChargeStart time is refused (net.invalid); no start means an uncharged throw", function()
		setup()
		duel()
		local ok, reason = CombatService.requestChargeStart(1, "now")
		expect.falsy(ok)
		expect.equal(reason, "net.invalid")
		expect.truthy((throwAt(1, 1, B_ROOT)))
		expect.equal(payloads("ThrowStarted")[1].power, 0)
	end)

	-- The catch ---------------------------------------------------------------------------------------------------

	t.test("caught: no ThrowImpact, CatchEvent caught at the radius's entry point, no longer a live throw", function()
		setup()
		local a, b, state, payload = caughtThrow(0.1)
		runFor(0.3)
		local caught = catchEvents("caught")
		expect.equal(#caught, 1)
		local event = caught[1]
		expect.equal(event.projId, payload.projId)
		expect.equal(event.catcherId, 2)
		expect.equal(event.throwerId, 1)
		expect.equal(event.squishyId, STARTER.id)
		expect.equal(event.matchId, "match-catch")
		expect.near((event.position - centreOf(B_ROOT)).Magnitude, CATCH.radiusStuds, 0.01)
		expect.near(event.burstAt, event.at + CATCH.crushSeconds, 1e-9)
		expect.near(event.at, payload.releaseAt + (entryOf(payload, centreOf(B_ROOT)) :: number), 0.005)
		expect.equal(#impacts(nil), 0)
		expect.equal(#state.hits, 0)
		expect.equal(a.activeProjectiles, 0)
		expect.near(b.handsBackAt, event.at + CATCH.handsBackSeconds, 1e-9)
		expect.equal(CombatService.counters().catches, 1)
	end)

	t.test("the burst crushSeconds later: the thrower loses 1 life, even while invulnerable (kind catch)", function()
		setup()
		local a, b, state = caughtThrow(0.1)
		local hitInfos = {}
		CombatService.Hit:connect(function(info: any)
			table.insert(hitInfos, info)
		end)
		runFor(0.3)
		local event = catchEvents("caught")[1]
		state.invuln.A = math.huge -- the thrower is invulnerable: the burst still costs the life
		runUntil(event.burstAt - 0.05)
		expect.equal(#catchEvents("burst"), 0)
		runFor(0.1)
		local bursts = catchEvents("burst")
		expect.equal(#bursts, 1)
		expect.equal(bursts[1].livesLeft, 2)
		expect.equal(bursts[1].eliminated, false)
		expect.equal(#state.hits, 1)
		local hit = state.hits[1]
		expect.equal(hit.victim, a)
		expect.equal(hit.attacker, b)
		expect.equal(hit.kind, "catch")
		expect.equal(hit.force, true)
		expect.near(hit.at, event.burstAt, 1e-9)
		expect.equal(#hitInfos, 1)
		expect.equal(hitInfos[1].kind, "catch")
		expect.equal(hitInfos[1].attacker, b)
		expect.equal(b.hits, 1)
		expect.equal(CombatService.projectileCount(), 0)
		expect.equal(#impacts(nil), 0)
	end)

	t.test("the match ends during the crush: the burst costs no life", function()
		setup()
		local _, _, state = caughtThrow(0.1)
		runFor(0.3)
		expect.equal(#catchEvents("caught"), 1)
		state.phase = "Result"
		runFor(CATCH.crushSeconds + 0.1)
		local bursts = catchEvents("burst")
		expect.equal(#bursts, 1)
		expect.equal(bursts[1].livesLeft, nil)
		expect.equal(#state.hits, 0)
		expect.equal(state.lives.A, 3)
		expect.equal(CombatService.projectileCount(), 0)
	end)

	t.test("a window that closed before the throw arrived catches nothing: the throw hits", function()
		setup()
		local _, _, state = caughtThrow(CATCH.windowSeconds + 0.1)
		runFor(1.5)
		expect.equal(#catchEvents("caught"), 0)
		expect.equal(#impacts("player"), 1)
		expect.equal(#state.hits, 1)
	end)

	t.test("approaching only: a window opening once the throw is going away catches nothing", function()
		setup()
		duel()
		local beside = B_ROOT + Vector3.new(6, 0, 0) -- inside the catch radius, clear of B's capsule
		expect.truthy((throwAt(1, 1, beside)))
		local payload = payloads("ThrowStarted")[1]
		local entry, closest = entryOf(payload, centreOf(B_ROOT))
		expect.truthy(entry ~= nil and entry < closest)
		runUntil(payload.releaseAt + closest + 0.02)
		expect.truthy((CombatService.requestCatch(2, clock.now())))
		runFor(CATCH.windowSeconds + 0.2)
		expect.equal(#catchEvents("caught"), 0)
		-- The same pass is caught when the window opens while it still comes.
		setup()
		duel()
		expect.truthy((throwAt(1, 1, beside)))
		payload = payloads("ThrowStarted")[1]
		entry, closest = entryOf(payload, centreOf(B_ROOT))
		runUntil(payload.releaseAt + (entry :: number) - 0.05)
		expect.truthy((CombatService.requestCatch(2, clock.now())))
		runFor(CATCH.windowSeconds)
		expect.equal(#catchEvents("caught"), 1)
	end)

	t.test("a pass outside the radius is never caught", function()
		setup()
		duel()
		local wide = B_ROOT + Vector3.new(CATCH.radiusStuds + 4, 0, 0)
		expect.truthy((throwAt(1, 1, wide)))
		local payload = payloads("ThrowStarted")[1]
		local _, closest = entryOf(payload, centreOf(B_ROOT))
		runUntil(payload.releaseAt + closest - 0.2)
		expect.truthy((CombatService.requestCatch(2, clock.now())))
		runFor(1)
		expect.equal(#catchEvents("caught"), 0)
	end)

	t.test("a Dragon Rush lane and an Epic ultimate's projectile are never caught", function()
		setup()
		local a, _, state = duel()
		expect.truthy((CombatService.requestCatch(2, clock.now())))
		CombatService.launchLane({
			caster = a,
			player = nil,
			squishyId = "dragon",
			origin = Vector3.new(0, 4.5, -38),
			direction = Vector3.new(0, 0, 1),
			length = 80,
			radius = 4,
			speed = 260,
			releaseAt = clock.now(),
			stoppedByGeometry = true,
		})
		runFor(0.4)
		expect.equal(#catchEvents("caught"), 0)
		expect.equal(#state.hits, 1)
		expect.equal(state.hits[1].kind, "lane")

		setup()
		a, _, state = duel()
		expect.truthy((CombatService.requestCatch(2, clock.now())))
		CombatService.launchUlt({
			caster = a,
			player = nil,
			squishyId = STARTER.id,
			origin = Vector3.new(0, 4.5, -38),
			direction = Vector3.new(0, 0, 1),
			length = 80,
			radius = 1.5,
			speed = 200,
			releaseAt = clock.now(),
			stoppedByGeometry = false,
			floorY = 0,
		})
		runFor(0.42)
		expect.equal(#catchEvents("caught"), 0)
		expect.equal(#state.hits, 1)
		expect.equal(state.hits[1].kind, "ult")
	end)

	-- The press -------------------------------------------------------------------------------------------------------

	t.test("the press: a live duel only, cooldownSeconds between presses, busy while crushing", function()
		setup()
		local _, _, state = duel()
		state.phase = "Countdown"
		local ok, reason = CombatService.requestCatch(2, clock.now())
		expect.falsy(ok)
		expect.equal(reason, "catch.context")
		state.phase = "Active"
		expect.truthy((CombatService.requestCatch(2, clock.now())))
		runFor(0.5)
		ok, reason = CombatService.requestCatch(2, clock.now())
		expect.falsy(ok)
		expect.equal(reason, "catch.cooldown")
		runFor(0.3)
		expect.truthy((CombatService.requestCatch(2, clock.now())))
		local _, reasonUnknown = CombatService.requestCatch(99, clock.now())
		expect.equal(reasonUnknown, "catch.context")
		local okBad, reasonBad = CombatService.requestCatch(2, "soon")
		expect.falsy(okBad)
		expect.equal(reasonBad, "net.invalid")
	end)

	t.test("crushing: no catch, no throw (throw.busy) until the hands are back", function()
		setup()
		local _, b = caughtThrow(0.1)
		runFor(0.3)
		local event = catchEvents("caught")[1]
		expect.truthy(event ~= nil)
		runUntil(event.at + CATCH.windowSeconds + 0.4) -- past any cooldown, still crushing
		local ok, reason = CombatService.requestCatch(2, clock.now())
		expect.falsy(ok)
		expect.equal(reason, "catch.busy")
		local thrown, why = throwAt(2, 1, A_ROOT)
		expect.falsy(thrown)
		expect.equal(why, "throw.busy")
		runUntil(b.handsBackAt + 0.05)
		expect.truthy((throwAt(2, 2, A_ROOT)))
	end)

	t.test("an open window keeps the hands busy (throw.busy) and a press drops the charge record", function()
		setup()
		duel()
		expect.truthy((CombatService.requestChargeStart(2, clock.now())))
		runFor(0.3)
		expect.truthy((CombatService.requestCatch(2, clock.now())))
		local thrown, why = throwAt(2, 1, A_ROOT)
		expect.falsy(thrown)
		expect.equal(why, "throw.busy")
		runFor(CATCH.windowSeconds + 0.05)
		expect.truthy((throwAt(2, 2, A_ROOT)))
		local started = payloads("ThrowStarted")
		expect.equal(started[#started].power, 0) -- the press dropped the charge
	end)
end
