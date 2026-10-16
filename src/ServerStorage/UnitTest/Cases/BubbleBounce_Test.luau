--!strict
-- BubbleBounce_Test (2026-10-16, the Bubble Pop bounce; design: ults.js:6 "40 st/s, bounces once", "pops on contact
-- or after 1.2 s", "6 st radius"). Server only (ServerStorage.UnitTest). Edit mode: init()/start() are never called;
-- fake clocks, recording senders, fake world queries (AbilityService.useDeps) and table roots, so nothing is parented
-- into the place. Contract:
--   * Config: the bubble bounces once, at 40 studs/s, and its whole path (the bounce included) is 48 studs = 1.2 s;
--   * UltRules.bounceDir mirrors the flat aim on the cover's flat normal and gives nil for a surface the bubble moves
--     away from and (review fix 2026-10-16) for one that is not close to upright (|unit normal.Y| >= bounceMaxNormalY,
--     0.5): a floor, a ceiling, a ramp, a round prop's top;
--   * AbilityService: a bubble whose path ends on cover (the Spherecast's hit with its normal) gets a second leg from
--     that end along the mirrored direction over what is left of maxLength, swept against cover (and the Bounds) again;
--     the release carries it as `bounce` {origin, dir, length}; no bounce without a normal (old fakes), on the Bounds,
--     with nothing left, off a floor or a ramp, or for any other kind (Dragon Rush, the roller, the birds);
--   * CombatService: a bubble with a bounce leg sends nothing at the cover and flies that leg at the same speed; it
--     pops on the opponent there (the splash takes the life), pops at that leg's end after 1.2 s in all (expired, or
--     geometry when the leg ends on cover too), never hits through the cover it bounced off, and an ffa enemy on the
--     second leg is hit the same way; without a bounce leg it still pops on the cover (unchanged);
--   * review fix (2026-10-16): Candy Court's jelly cover still answers: JellyRippleController.laneFor keeps the second
--     leg's dir for the end probe and schedules the old pop's wobble at the bounce point and time, along the first
--     leg's dir; a release without a (well-formed) bounce is the plain lane; anything that is not a release is nil.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type Sent = { remote: string, payload: any }
type Cast = { distance: number, normal: Vector3? }

local STEP = 1 / 60

return function(t: Context)
	local expect = t.expect
	local AbilityService = t.requireServer("Services/AbilityService")
	local CombatService = t.requireServer("Services/CombatService")
	local HitMath = t.requireServer("Logic/HitMath")
	local UltRules = t.requireServer("Logic/UltRules")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local FakeClock = t.requireFake("FakeClock")

	local B = Config.Abilities.bubble_pop
	local HITBOX = Config.Combat.Hitbox
	local STAND = HITBOX.radius - HITBOX.bottomOffset -- 3.0: the HRP height of a standing player
	local AIM = Vector3.new(0, 0, 1)

	local function near(a: Vector3, b: Vector3, tolerance: number?)
		expect.near((a - b).Magnitude, 0, tolerance or 1e-4)
	end

	local function tableRoot(position: Vector3): any
		return { Position = position, CFrame = CFrame.new(position), Parent = nil }
	end

	local function arenaZones(): { [string]: any }
		local zones = {}
		for name, volume in WorldLayout.Arena.zones do
			zones[name] = { cframe = CFrame.new(volume.position), size = volume.size }
		end
		return zones
	end

	-- One clock and one recording sender for both services.
	local clock = FakeClock.new(5000)
	local sent: { Sent } = {}
	local casts: { Cast | false } = {} -- the fake Spherecast's answers, in call order (false = clear)
	local castCalls: { { origin: Vector3, direction: Vector3 } } = {}
	local delays: { { at: number, fn: (...any) -> (), args: { any } } } = {}

	local function record(remote: string, _recipients: { any }, payload: any)
		table.insert(sent, { remote = remote, payload = payload })
	end

	local function setup()
		AbilityService.useDeps(nil)
		CombatService.destroy()
		clock = FakeClock.new(5000)
		table.clear(sent)
		table.clear(casts)
		table.clear(castCalls)
		table.clear(delays)
		CombatService.useDeps({ now = clock.now, autoStep = false, send = record, reportViolation = function() end })
		AbilityService.useDeps({
			now = clock.now,
			send = record,
			delay = function(seconds: number, fn: (...any) -> (), ...: any)
				table.insert(delays, { at = clock.now() + seconds, fn = fn, args = { ... } })
			end,
			overlaps = function(): boolean
				return false
			end,
			cast = function(origin: Vector3, _radius: number, direction: Vector3): (number?, Vector3?)
				table.insert(castCalls, { origin = origin, direction = direction })
				local answer = table.remove(casts, 1)
				if not answer then
					return nil, nil
				end
				local hit = answer :: Cast
				return hit.distance, hit.normal
			end,
		})
	end

	local function cleanup(matchId: string)
		AbilityService.detachMatch(matchId)
		AbilityService.useDeps(nil)
		CombatService.destroy()
		CombatService.useDeps(nil)
	end

	local function fighter(userId: number, side: string, squishyId: string, root: any): any
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
			now = clock.now(),
		})
	end

	-- A registered Active duel: A (`squishyId`, user 91) at (0, 3, -40), B (user 92) at `bAt`. Every hit is applied.
	local function duel(squishyId: string, bAt: Vector3?): (any, any, { any })
		local a = fighter(91, "A", squishyId, tableRoot(Vector3.new(0, STAND, -40)))
		local b = fighter(92, "B", Catalog.starterId(), tableRoot(bAt or Vector3.new(0, STAND, 30)))
		local hits: { any } = {}
		local port = {
			matchId = "bubble-bounce",
			arena = {
				slot = 1,
				floorY = 0,
				killY = -15,
				zones = arenaZones(),
				geometry = nil,
				raycastParams = RaycastParams.new(),
				overlapParams = OverlapParams.new(),
			},
			fighters = { a, b },
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
			applyHits = function(list: { any }): { [number]: any }
				local outcomes = {}
				for index, hit in list do
					table.insert(hits, hit)
					outcomes[index] = { lives = 2, invulnUntil = clock.now() + 1.5, eliminated = false }
				end
				return outcomes
			end,
			flush = function() end,
			throwAccepted = function() end,
			outOfBounds = function() end,
		}
		CombatService.registerMatch(port)
		AbilityService.attachMatch(port)
		return a, b, hits
	end

	local function payloads(remote: string, phase: string?): { any }
		local list = {}
		for _, entry in sent do
			if entry.remote == remote and (phase == nil or entry.payload.phase == phase) then
				table.insert(list, entry.payload)
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

	-- Runs the captured delays due by `untilTime` (in time order), moving the clock to each.
	local function runDelays(untilTime: number)
		while true do
			table.sort(delays, function(x, y)
				return x.at < y.at
			end)
			local nextDelay = delays[1]
			if nextDelay == nil or nextDelay.at > untilTime then
				break
			end
			table.remove(delays, 1)
			clock.advance(math.max(0, nextDelay.at - clock.now()))
			nextDelay.fn(table.unpack(nextDelay.args))
		end
		clock.advance(math.max(0, untilTime - clock.now()))
	end

	-- Steps the projectile simulation for `seconds` (no Heartbeat in tests).
	local function runFor(seconds: number)
		for _ = 1, math.ceil(seconds / STEP) do
			clock.advance(STEP)
			CombatService.step()
		end
	end

	-- A full meter, an ultimate aimed along +Z, and its release (the wind-up's delays run). Returns the release event.
	local function castAndRelease(squishyId: string): any
		local ultimateId = Catalog.get(squishyId).ultimateId
		local ability = Config.Abilities[ultimateId]
		AbilityService.setCharge(91, ability.chargeMax)
		local start = clock.now()
		local ok, reason = AbilityService.requestUltimate(91, 1, AIM, start)
		assert(ok, `the ultimate was refused: {reason}`)
		runDelays(start + ability.telegraphSeconds + 0.001)
		local release = payloads("UltimateEvent", "release")[1]
		assert(release ~= nil, "no release")
		return release
	end

	-- Config ------------------------------------------------------------------------------------------------------

	t.test("the design's numbers: bounces once, 40 studs/s, a 48-stud path (1.2 s) with the bounce", function()
		expect.equal(B.kind, "bubble")
		expect.equal(B.bounces, 1) -- ults.js:6 "bounces once"
		expect.equal(B.speed, 40) -- ults.js:6, fp.js:359
		expect.equal(B.popSeconds, 1.2) -- ults.js:6
		expect.equal(B.splashRadius, 6) -- ults.js:6, fp.js:361
		expect.near(B.maxLength, B.speed * B.popSeconds, 1e-9)
		expect.equal(B.bounceMaxNormalY, 0.5) -- review fix [P]: only cover steeper than 60° bounces it
		for id, ability in Config.Abilities do
			if id ~= "bubble_pop" then
				expect.equal(ability.bounces, nil) -- only the bubble bounces
			end
		end
	end)

	-- UltRules.bounceDir -------------------------------------------------------------------------------------------

	t.test(
		"bounceDir mirrors the flat aim on upright cover; nil off a floor, a ramp or a face it moves away from",
		function()
			local up = B.bounceMaxNormalY
			near(UltRules.bounceDir(Vector3.new(0, 0, 1), Vector3.new(0, 0, -1), up) :: Vector3, Vector3.new(0, 0, -1))
			near(
				UltRules.bounceDir(Vector3.new(1, 0, 1).Unit, Vector3.new(0, 0, -1), up) :: Vector3,
				Vector3.new(1, 0, -1).Unit
			)
			-- A nearly upright face counts by its flat side; a tilted aim is flattened.
			near(
				UltRules.bounceDir(Vector3.new(0, 0, 1), Vector3.new(0, 0.3, -0.954), up) :: Vector3,
				Vector3.new(0, 0, -1)
			)
			local tilted = UltRules.bounceDir(Vector3.new(0, 0.5, 1), Vector3.new(-1, 0, 0).Unit, up)
			expect.equal(tilted, nil) -- along the face: it does not go into it
			local flat = UltRules.bounceDir(Vector3.new(1, 0.5, 1), Vector3.new(-1, 0, 0), up) :: Vector3
			expect.near(flat.Y, 0, 1e-9)
			expect.near(flat.Magnitude, 1, 1e-9)
			near(flat, Vector3.new(-1, 0, 1).Unit)
			expect.equal(UltRules.bounceDir(Vector3.new(0, 0, 1), Vector3.new(0, 1, 0), up), nil) -- a floor
			expect.equal(UltRules.bounceDir(Vector3.new(0, 0, 1), Vector3.new(0, -1, 0), up), nil) -- a ceiling
			expect.equal(UltRules.bounceDir(Vector3.new(0, 0, 1), Vector3.new(0, 0, 1), up), nil) -- moving away
			-- Review fix (2026-10-16): a 20° or 30° ramp of a match map, a 53° slope and a round prop's upper side pop
			-- it (they are not upright), whatever their flat side says; just steeper than 60° still bounces.
			for _, degrees in { 20, 30, 53, 59 } do
				local slope = Vector3.new(0, math.cos(math.rad(degrees)), -math.sin(math.rad(degrees)))
				if UltRules.bounceDir(Vector3.new(0, 0, 1), slope, up) ~= nil then
					error(`a {degrees}° slope bounced the bubble`)
				end
			end
			local steep = Vector3.new(0, math.cos(math.rad(61)), -math.sin(math.rad(61)))
			near(UltRules.bounceDir(Vector3.new(0, 0, 1), steep, up) :: Vector3, Vector3.new(0, 0, -1))
			expect.equal(UltRules.bounceDir(Vector3.new(0, 0, 1), Vector3.new(0, 0.6, -0.8), up), nil) -- a 53° face
		end
	)

	-- AbilityService: the bounce leg at the request -----------------------------------------------------------------

	t.test(
		"a bubble that meets cover gets one bounce leg: mirrored, from the cover, the rest of its 48 studs",
		function()
			setup()
			duel("cupcake_axolotl")
			-- Cover 30 studs ahead, facing the caster; the way back is clear.
			table.insert(casts, { distance = 30, normal = Vector3.new(0, 0, -1) })
			local release = castAndRelease("cupcake_axolotl")
			near(release.origin, Vector3.new(0, B.laneHeightAboveFloor, -40 + B.originForwardStuds))
			expect.near(release.length, 30, 1e-4)
			local bounce = release.bounce
			assert(bounce ~= nil, "no bounce in the release")
			near(bounce.origin, release.origin + AIM * 30)
			near(bounce.dir, Vector3.new(0, 0, -1))
			expect.near(bounce.length, B.maxLength - 30, 1e-4)
			-- The second leg was swept from the bounce point, over what was left.
			expect.equal(#castCalls, 2)
			near(castCalls[2].origin, bounce.origin)
			near(castCalls[2].direction, Vector3.new(0, 0, -1) * (B.maxLength - 30), 1e-3)
			-- The server projectile flies the first leg now (0.75 s) and keeps the second for later.
			local info = CombatService.projectileInfo(release.projId)
			assert(info ~= nil, "no bubble projectile")
			expect.near(info.maxT, 30 / B.speed, 1e-4)
			-- The telegraph carries no bounce (nobody draws one before the release).
			expect.equal(payloads("UltimateEvent", "telegraph")[1].bounce, nil)
			cleanup("bubble-bounce")
		end
	)

	t.test("a bounce leg that meets cover again ends there: the bubble pops on that cover after its bounce", function()
		setup()
		duel("cupcake_axolotl")
		table.insert(casts, { distance = 30, normal = Vector3.new(0, 0, -1) })
		table.insert(casts, { distance = 5, normal = Vector3.new(0, 0, 1) })
		local release = castAndRelease("cupcake_axolotl")
		local bounce = release.bounce
		assert(bounce ~= nil, "no bounce in the release")
		expect.near(bounce.length, 5, 1e-4)
		runFor(30 / B.speed - 0.05)
		expect.equal(#impacts(nil), 0)
		runFor(0.1)
		expect.equal(#impacts(nil), 0) -- the bounce sends nothing
		runFor(5 / B.speed + 0.1)
		local ends = impacts(nil)
		expect.equal(#ends, 1)
		expect.equal(ends[1].kind, "geometry")
		near(ends[1].position, bounce.origin + bounce.dir * 5, 0.05)
		cleanup("bubble-bounce")
	end)

	t.test(
		"no bounce without a cover normal, with nothing left, off a floor, ceiling or ramp, or with no cover",
		function()
			local answers: { Cast | false } = {
				{ distance = 30, normal = nil }, -- an old-style answer (a distance only): it pops on the cover as before
				{ distance = B.maxLength, normal = Vector3.new(0, 0, -1) }, -- cover right at its end: nothing left to fly
				{ distance = 30, normal = Vector3.new(0, 1, 0) }, -- a floor has no side to bounce off
				{ distance = 30, normal = Vector3.new(0, -1, 0) }, -- nor a ceiling
				-- review fix (2026-10-16): a 20° ramp ahead is not upright: it pops on it as before
				{ distance = 30, normal = Vector3.new(0, math.cos(math.rad(20)), -math.sin(math.rad(20))) },
				false, -- no cover at all: the whole 48 studs
			}
			for _, answer in answers do
				setup()
				duel("cupcake_axolotl")
				table.insert(casts, answer)
				local release = castAndRelease("cupcake_axolotl")
				expect.equal(release.bounce, nil)
				expect.near(release.length, if answer then (answer :: Cast).distance else B.maxLength, 1e-4)
				cleanup("bubble-bounce")
			end
		end
	)

	t.test("the Bounds before the cover: the bubble pops at the arena's edge, no bounce", function()
		setup()
		duel("cupcake_axolotl")
		-- Aimed back along -Z from Z -40: the Bounds edge (Z -54) is 12 studs from the start, the cover 47.
		table.insert(casts, { distance = 47, normal = Vector3.new(0, 0, 1) })
		AbilityService.setCharge(91, B.chargeMax)
		local start = clock.now()
		expect.truthy((AbilityService.requestUltimate(91, 1, Vector3.new(0, 0, -1), start)))
		runDelays(start + B.telegraphSeconds + 0.001)
		local edge = payloads("UltimateEvent", "release")[1]
		assert(edge ~= nil, "no release")
		expect.equal(edge.bounce, nil)
		expect.near(edge.length, 12, 1e-3) -- cut at the Bounds, before the cover
		expect.equal(#castCalls, 1)
		cleanup("bubble-bounce")
	end)

	t.test("no other ultimate bounces: Dragon Rush, the roller and the birds stop at cover", function()
		local dragonId = nil
		for _, def in Catalog.list() do
			if def.ultimateId == "dragon_rush" then
				dragonId = def.id
			end
		end
		for _, id in { "donut", "bird", dragonId } do
			setup()
			duel(id)
			for _ = 1, 3 do
				table.insert(casts, { distance = 20, normal = Vector3.new(0, 0, -1) })
			end
			local release = castAndRelease(id)
			expect.equal(release.bounce, nil)
			expect.near(release.length, 20, 1e-4) -- the lane, the roller, or the longest bird
			for _, shot in release.shots or {} do
				expect.near(shot.length, 20, 1e-4)
			end
			cleanup("bubble-bounce")
		end
	end)

	-- CombatService: flying the bounce leg ---------------------------------------------------------------------------

	-- A bubble launched straight (no request): from (0, 4.8, -38) along +Z, 30 studs to the cover at Z -8, then (with
	-- `bounce`) 18 studs along +X.
	local LEG1 = 30
	local BOUNCE_AT = Vector3.new(0, B.laneHeightAboveFloor, -8)
	local function launch(caster: any, bounce: any?): (number, number)
		local releaseAt = clock.now() + B.telegraphSeconds
		local projId = CombatService.launchUlt({
			caster = caster,
			player = nil,
			squishyId = "cupcake_axolotl",
			origin = Vector3.new(0, B.laneHeightAboveFloor, -38),
			direction = AIM,
			length = LEG1,
			radius = B.radius,
			speed = B.speed,
			releaseAt = releaseAt,
			stoppedByGeometry = true,
			floorY = 0,
			splashRadius = B.splashRadius,
			bounce = bounce,
		})
		return projId, releaseAt
	end
	local function sideways(stopped: boolean): any
		return {
			origin = BOUNCE_AT,
			dir = Vector3.new(1, 0, 0),
			length = B.maxLength - LEG1,
			stoppedByGeometry = stopped,
		}
	end

	t.test("a bounced bubble sends nothing at the cover and pops on the opponent on its second leg", function()
		setup()
		local victimAt = Vector3.new(12, STAND, -8)
		local a, _, hits = duel("cupcake_axolotl", victimAt)
		local _, releaseAt = launch(a, sideways(false))
		runFor(B.telegraphSeconds + LEG1 / B.speed + 0.05)
		expect.equal(#impacts(nil), 0) -- past the bounce: no impact at the cover
		runFor(0.5)
		local list = impacts("player")
		expect.equal(#list, 1)
		expect.equal(#impacts(nil), 1)
		expect.equal(list[1].victimId, 92)
		expect.equal(hits[1].kind, "ult")
		-- It touched the capsule on the second leg (at the throw height, along +X from the bounce point).
		local position = list[1].position
		expect.near(position.Z, -8, 1e-3)
		local capsule = HitMath.capsule(victimAt)
		expect.near(HitMath.pointSegDistance(position, capsule.a, capsule.b), B.radius + capsule.radius, 0.01)
		expect.truthy(hits[1].at > releaseAt + LEG1 / B.speed)
		expect.equal(CombatService.projectileCount(), 0)
		cleanup("bubble-bounce")
	end)

	t.test("after its bounce the bubble pops at its second leg's end, 1.2 s after the release in all", function()
		setup()
		local a, _, hits = duel("cupcake_axolotl") -- B at (0, 3, 30): behind the cover it bounces off
		launch(a, sideways(false))
		runFor(B.telegraphSeconds + B.popSeconds - 0.05)
		expect.equal(#impacts(nil), 0)
		runFor(0.1)
		local ends = impacts(nil)
		expect.equal(#ends, 1)
		expect.equal(ends[1].kind, "expired") -- a pop that hit nobody
		near(ends[1].position, BOUNCE_AT + Vector3.new(B.maxLength - LEG1, 0, 0), 0.05)
		expect.equal(#hits, 0) -- never through the cover
		-- A second leg that ends on cover pops there as geometry.
		setup()
		local a2 = duel("cupcake_axolotl")
		launch(a2, sideways(true))
		runFor(B.telegraphSeconds + B.popSeconds + 0.05)
		local onCover = impacts(nil)
		expect.equal(#onCover, 1)
		expect.equal(onCover[1].kind, "geometry")
		cleanup("bubble-bounce")
	end)

	t.test("without a bounce leg the bubble still pops on the cover (unchanged)", function()
		setup()
		local a = duel("cupcake_axolotl")
		launch(a, nil)
		runFor(B.telegraphSeconds + LEG1 / B.speed + 0.05)
		local ends = impacts(nil)
		expect.equal(#ends, 1)
		expect.equal(ends[1].kind, "geometry")
		near(ends[1].position, BOUNCE_AT, 0.05)
		cleanup("bubble-bounce")
	end)

	t.test("Free for All: an enemy standing on the second leg is hit after the bounce", function()
		setup()
		local a = fighter(91, "A", "cupcake_axolotl", tableRoot(Vector3.new(0, STAND, -40)))
		local far = fighter(93, "A", Catalog.starterId(), tableRoot(Vector3.new(40, STAND, 40)))
		local onLeg = fighter(94, "A", Catalog.starterId(), tableRoot(Vector3.new(12, STAND, -8)))
		local hits: { any } = {}
		local port = {
			matchId = "bubble-bounce-ffa",
			arena = {
				slot = 0,
				floorY = 0,
				killY = -15,
				zones = { Bounds = { cframe = CFrame.new(0, 42.5, 0), size = Vector3.new(200, 115, 200) } },
				geometry = nil,
				raycastParams = RaycastParams.new(),
				overlapParams = OverlapParams.new(),
			},
			fighters = { a, far, onLeg },
			ffa = true,
			teams = false,
			phase = function(): string
				return "Active"
			end,
			cooldownMultiplier = function(): number
				return 1
			end,
			placement = function(): CFrame?
				return nil
			end,
			canBeHit = function(_victim: any, _at: number, attacker: any): boolean
				return attacker ~= nil
			end,
			applyHits = function(list: { any }): { [number]: any }
				local outcomes = {}
				for index, hit in list do
					table.insert(hits, hit)
					outcomes[index] = { lives = 0, invulnUntil = clock.now() + 1.5, eliminated = true }
				end
				return outcomes
			end,
			flush = function() end,
			throwAccepted = function() end,
			outOfBounds = function() end,
		}
		CombatService.registerMatch(port)
		launch(a, sideways(false))
		runFor(B.telegraphSeconds + B.popSeconds + 0.1)
		expect.equal(#hits, 1)
		expect.equal(hits[1].victim, onLeg)
		local list = impacts("player")
		expect.equal(#list, 1)
		expect.equal(list[1].victimId, 94)
		CombatService.destroy()
		CombatService.useDeps(nil)
		AbilityService.useDeps(nil)
	end)

	-- The jelly cover's answer (review fix 2026-10-16) ------------------------------------------------------------

	t.test(
		"the jelly cover answers the bounce: the old pop's wobble at the bounce, the end probe along leg 2",
		function()
			local JellyRippleController = t.requireClient("Controllers/JellyRippleController")
			local release: any = {
				phase = "release",
				projId = 7,
				origin = Vector3.new(0, B.laneHeightAboveFloor, 0),
				dir = AIM,
				length = 30,
				radius = B.radius,
				speed = B.speed,
				telegraphEndsAt = 100,
				bounce = { origin = Vector3.new(0, B.laneHeightAboveFloor, 30), dir = -AIM, length = B.maxLength - 30 },
			}
			local lane = JellyRippleController.laneFor(release)
			assert(lane ~= nil, "no lane for a bubble release")
			near(lane.dir, -AIM) -- the impact at the second leg's end probes the way that leg flies
			expect.equal(lane.radius, B.radius)
			local bounce = lane.bounce
			assert(bounce ~= nil, "no bounce wobble")
			expect.near(bounce.at, 100 + 30 / B.speed, 1e-9) -- when the first leg meets the cover
			near(bounce.position, release.bounce.origin)
			near(bounce.dir, AIM) -- probed along the first leg, as its pop on that cover was
			-- No bounce (a bubble that met no cover, Dragon Rush, the roller): the plain lane, as before.
			local plain = table.clone(release)
			plain.bounce = nil
			local plainLane = JellyRippleController.laneFor(plain) :: any
			near(plainLane.dir, AIM)
			expect.equal(plainLane.bounce, nil)
			-- A malformed bounce is ignored (the plain lane).
			local bad = table.clone(release)
			bad.bounce = { origin = "x", dir = -AIM, length = 1 }
			expect.equal((JellyRippleController.laneFor(bad) :: any).bounce, nil)
			-- Not a usable release: nothing.
			local telegraph = table.clone(release)
			telegraph.phase = "telegraph"
			expect.equal(JellyRippleController.laneFor(telegraph), nil)
			local noId = table.clone(release)
			noId.projId = nil
			expect.equal(JellyRippleController.laneFor(noId), nil)
			expect.equal(JellyRippleController.laneFor(nil), nil)
		end
	)
end
