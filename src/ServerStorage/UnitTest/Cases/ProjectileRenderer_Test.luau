--!strict
-- ProjectileRenderer_Test: unit tests for the pure parts of StarterPlayerScripts.Client.Controllers.ProjectileRenderer.
-- Server only (ServerStorage.UnitTest). Edit mode: init() is not called (no remotes, no models built); time comes from
-- a FakeClock standing in for workspace:GetServerTimeNow().
-- Contract (DESIGN §5.1, §5.5, §9.7, §9.8, §9.15):
--   * render interpolation: the drawn position is a pure function of server time, P(τ) =
--     positionAt(origin, v, g, τ) + offset·e^(-τ/0.04), τ = now - releaseAt; nothing before releaseAt; uneven frames
--     and hitches land on the same path (no accumulated error); after ≈ 160 ms it is the server path;
--   * the model scale blends from the hand size to the flight size with the same factor, stretched (0.94, 0.94, 1.12)
--     along travel; flightSpin adds only roll ("roll" 360°/s, "wobble" ±8°);
--   * the shadow disc is 1.1× the flight diameter at the floor, shrinking to 0.4× with height;
--   * impact squash: major ("player" / "target") splat 0.55 along / 1.4 across in 90 ms then shrink and fade in
--     120 ms; minor splat then a 200 ms fade; lifetime + grace; the facing frame never degenerates;
--   * the cosmetic contact hold rests the centre half a radius off the touched surface;
--   * at a match end a projectile whose splat has started plays it out; the rest are removed at once;
--   * the hit-stop contact hold (§18.4.4): with a hold the splat starts at its contact squash (u = 0.35), stays there
--     for the hold (HitStop.elapsed), then plays on; without one nothing changes;
--   * the impact flash (§18.4.2): FillTransparency 1 -> 0.5 -> 1 over 120 ms;
--   * the release air ring is ThrowRing's (0 -> 1.6 studs in 0.18 s, from Transparency 0.5).
-- Squishy overhaul (spec 2026-10-09 §3.2 flight, option A):
--   * with a blueprint flight style the roll, nod and pulse are SquishRig.flightPose of the time since the release;
--     without one (ReducedMotion, no motion row) it is today's flightSpin with no nod and no pulse;
--   * the pose frameAt(P, V, roll)·Angles(nod, 0, 0) keeps the face leading for every toy: LookVector·V̂ >=
--     cos(maxNod + 1°);
--   * the stretch pulse runs along travel and keeps the volume;
--   * pulse and flaps go to at most flightDetailModels projectiles (phone flightDetailModelsLow, none under
--     ReducedMotion), incoming first (dot(V, camera - P) > 0), then by distance, the local player's own one last, and
--     only to toys whose style has a pulse or flaps for their sections;
--   * a pool return puts the rig and the model back at rest: no flight, flap angle or squish face left behind.
-- First person (spec 2026-10-10 §3.6, §3.10):
--   * the local player's own throw in first person (duel or practice) starts at ViewmodelController's release point
--     with handScale = factor / flightScale, so its size on screen is the same with and without the cover cut;
--     everything else starts at the held model at 1 / flightScale, as before;
--   * the own first-person release ring is half size;
--   * in first person every projectile within 4.5 studs of the camera fades (parts and outline), except the own one in
--     its first 0.2 s; at impact the near fade wins over the splat fade (a max), and the outline fades with it;
--   * the local first-person victim gets no white impact fill; third person is unchanged.
-- Feature 1 (2026-10-11, the charge throw and the catch): ThrowStarted.power reads as a charge 0..1 (anything else 0);
--   a caught toy flies from where it was caught into the catcher's hands over Catch.flyInSeconds (Quad Out) and stays
--   there; with no catcher in reach it stays where it was caught.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local POSITION_TOLERANCE = 0.02 -- Vector3 components are single precision

return function(t: Context)
	local ProjectileRenderer = t.requireClient("Controllers/ProjectileRenderer")
	local ProjectileMath = t.requireShared("ProjectileMath")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")
	local expect = t.expect
	local throwAnim = Config.Anim.throw
	local hit = Config.Vfx.Hit
	local stretch: Vector3 = throwAnim.speedStretch

	local function expectVectorNear(actual: Vector3, wanted: Vector3, tolerance: number?)
		local tol = tolerance or POSITION_TOLERANCE
		expect.near(actual.X, wanted.X, tol)
		expect.near(actual.Y, wanted.Y, tol)
		expect.near(actual.Z, wanted.Z, tol)
	end

	local function payload(releaseAt: number): any
		return {
			seq = 1,
			nextThrowAt = releaseAt + 1,
			projId = 1,
			throwerId = 1,
			squishyId = "kitty_bread",
			kind = "throw",
			origin = Vector3.new(0, 4.8, -42.5),
			velocity = Vector3.new(0, 18, 93),
			gravity = 30,
			radius = 1,
			releaseAt = releaseAt,
		}
	end

	t.test("the settle factor starts at 1 and decays with tau = pathSettleTau", function()
		expect.equal(ProjectileRenderer.settleFactor(0), 1)
		expect.equal(ProjectileRenderer.settleFactor(-1), 1)
		expect.near(ProjectileRenderer.settleFactor(throwAnim.pathSettleTau), math.exp(-1), 1e-9)
		expect.truthy(ProjectileRenderer.settleFactor(throwAnim.pathSettleMs / 1000) < 0.02) -- settled by ≈ 160 ms
	end)

	t.test("nothing is drawn before releaseAt; at the release it starts in the hand at the hand size", function()
		local p = payload(100)
		local offset = Vector3.new(-0.4, -0.3, 0.6)
		expect.equal(ProjectileRenderer.sampleAtTime(p, 99.99, offset, 0.8, "wobble"), nil)
		local first = ProjectileRenderer.sampleAtTime(p, 100, offset, 0.8, "wobble")
		expectVectorNear(first.position, p.origin + offset)
		expectVectorNear(first.scale, stretch * 0.8, 1e-6)
		expectVectorNear(first.velocity, p.velocity, 1e-4)
	end)

	t.test("render interpolation follows server time over uneven frames and hitches, with no drift", function()
		local p = payload(500)
		local offset = Vector3.new(0.5, -0.5, 0.2)
		local clock = FakeClock.new(499.9)
		local frames = { 1 / 60, 1 / 60, 0.05, 1 / 144, 0.2, 1 / 60, 0.1, 1 / 30, 0.3, 1 / 60 }
		for _, dt in frames do
			clock.advance(dt)
			local now = clock.now()
			local sample = ProjectileRenderer.sampleAtTime(p, now, offset, 1, "roll")
			if now < p.releaseAt then
				expect.equal(sample, nil)
			else
				local tau = now - p.releaseAt
				local exact = ProjectileMath.positionAt(p.origin, p.velocity, p.gravity, tau)
					+ offset * math.exp(-tau / throwAnim.pathSettleTau)
				expectVectorNear(sample.position, exact)
				expectVectorNear(sample.velocity, ProjectileMath.velocityAt(p.velocity, p.gravity, tau), 1e-3)
			end
		end
		-- Long after the settle window the drawn path is the server path.
		local late = ProjectileRenderer.sampleAtTime(p, 500.6, offset, 1, "roll")
		expectVectorNear(late.position, ProjectileMath.positionAt(p.origin, p.velocity, p.gravity, 0.6))
		expectVectorNear(late.scale, stretch, 1e-6)
	end)

	t.test("flightSpin adds only roll: 360°/s for roll, ±8° for wobble", function()
		expect.near(ProjectileRenderer.rollAt("roll", 0.5), math.rad(throwAnim.rollDegPerSecond) * 0.5, 1e-9)
		local bound = math.rad(throwAnim.wobbleRollDeg)
		for i = 0, 50 do
			local roll = ProjectileRenderer.rollAt("wobble", i / 37)
			expect.truthy(math.abs(roll) <= bound + 1e-9)
		end
		local frame = ProjectileRenderer.frameAt(Vector3.zero, Vector3.new(0, 0, -10), math.rad(30))
		expectVectorNear(frame.LookVector, Vector3.new(0, 0, -1), 1e-5) -- the face leads; roll keeps the travel axis
	end)

	t.test("the facing frame never degenerates for straight-up or zero travel", function()
		local up = ProjectileRenderer.frameAt(Vector3.zero, Vector3.new(0, 5, 0), 0)
		expectVectorNear(up.LookVector, Vector3.yAxis, 1e-5)
		local still = ProjectileRenderer.frameAt(Vector3.new(1, 2, 3), Vector3.zero, 0)
		expect.truthy(still.LookVector.X == still.LookVector.X)
		expectVectorNear(still.Position, Vector3.new(1, 2, 3), 1e-6)
	end)

	t.test("the shadow disc is 1.1× the flight diameter at the floor and 0.4× high up", function()
		local radius = 1.2
		local low = Config.Vfx.Projectile.shadowScaleLow
		local high = Config.Vfx.Projectile.shadowScaleHigh
		expect.near(ProjectileRenderer.shadowDiameter(radius, 0), 2 * radius * low, 1e-9)
		expect.near(ProjectileRenderer.shadowDiameter(radius, -2), 2 * radius * low, 1e-9)
		expect.near(ProjectileRenderer.shadowDiameter(radius, 100), 2 * radius * high, 1e-9)
		local previous = math.huge
		for height = 0, 14 do
			local d = ProjectileRenderer.shadowDiameter(radius, height)
			expect.truthy(d <= previous + 1e-9)
			previous = d
		end
	end)

	t.test("a major impact splats 0.55 along / 1.4 across in 90 ms, then shrinks and fades in 120 ms", function()
		local splat = hit.splatMs / 1000
		local shrink = hit.shrinkMs / 1000
		local from = Vector3.new(0.94, 0.94, 1.12)
		local start = ProjectileRenderer.splatSample(0, true, from)
		expectVectorNear(start.scale, from, 1e-6)
		expect.equal(start.fade, 0)
		local peak = ProjectileRenderer.splatSample(splat, true, from)
		expectVectorNear(peak.scale, Vector3.new(hit.splatAcross, hit.splatAcross, hit.splatAlong), 1e-6)
		expect.falsy(peak.done)
		local halfway = ProjectileRenderer.splatSample(splat + shrink / 2, true, from)
		expect.near(halfway.fade, 0.5, 1e-6)
		local done = ProjectileRenderer.splatSample(splat + shrink + 0.001, true, from)
		expect.truthy(done.done)
		expect.near(done.fade, 1, 1e-9)
		-- The shrink ends at the deformer's floor (Config.Anim.deform.scaleMin); the fade does the rest.
		expectVectorNear(done.scale, Vector3.one * Config.Anim.deform.scaleMin, 1e-6)
	end)

	t.test("a minor impact (geometry / expired / fizzle) splats a little, then fades over 200 ms", function()
		local splat = hit.splatMs / 1000
		local fade = hit.minorFadeMs / 1000
		local mid = ProjectileRenderer.splatSample(splat + fade / 2, false, nil)
		expect.near(mid.fade, 0.5, 1e-6)
		expect.falsy(mid.done)
		expect.truthy(ProjectileRenderer.splatSample(splat + fade + 0.001, false, nil).done)
	end)

	t.test("a projectile with no impact message lives ProjectileMaxLifetime plus a short grace", function()
		local lifetime = Config.Duel.Rules.ProjectileMaxLifetime
		expect.truthy(ProjectileRenderer.inLifetime(lifetime))
		expect.falsy(ProjectileRenderer.inLifetime(lifetime + 2))
		expect.truthy(ProjectileRenderer.inLifetime(0.5, 1))
		expect.falsy(ProjectileRenderer.inLifetime(5, 1))
	end)

	t.test("the contact hold rests the centre half a radius off the touched surface", function()
		expectVectorNear(
			ProjectileRenderer.contactPosition(Vector3.new(2, 0, 3), Vector3.yAxis, 1.2),
			Vector3.new(2, 0.6, 3),
			1e-6
		)
		expectVectorNear(
			ProjectileRenderer.contactPosition(Vector3.new(0, 4, 10), Vector3.new(0, 0, -2), 1),
			Vector3.new(0, 4, 9.5),
			1e-6
		)
		-- A degenerate normal falls back to up.
		expectVectorNear(
			ProjectileRenderer.contactPosition(Vector3.zero, Vector3.zero, 1),
			Vector3.new(0, 0.5, 0),
			1e-6
		)
	end)

	t.test("at a match end only projectiles still in flight go; a started splat plays out", function()
		-- The match-ending hit: its ThrowImpact and DuelState(Result) arrive in the same frame.
		expect.falsy(ProjectileRenderer.removeOnMatchEnd(true, false))
		expect.truthy(ProjectileRenderer.removeOnMatchEnd(false, false))
		-- Back in the lobby (the view is gone) everything goes.
		expect.truthy(ProjectileRenderer.removeOnMatchEnd(true, true))
		expect.truthy(ProjectileRenderer.removeOnMatchEnd(false, true))
	end)

	-- Feel pass (§18.4) ------------------------------------------------------------------------------------------------

	t.test("the hit-stop holds the projectile at its contact squash, then the splat plays on", function()
		local HitStop = t.requireClient("Anim/HitStop")
		local splat = hit.splatMs / 1000
		local contact = 0.35 * splat
		-- No hold: the splat clock is the time since the impact.
		expect.near(ProjectileRenderer.impactElapsed(0.05, nil), 0.05, 1e-9)
		expect.near(ProjectileRenderer.impactElapsed(-1, nil), 0, 1e-9)
		-- A 0.06 s hold from the impact (a private stopper on a FakeClock).
		local clock = FakeClock.new(50)
		local stopper = HitStop.new(clock.now)
		local start = stopper:trigger(9, Config.Vfx.HitStop.playerHit, 50)
		expect.equal(start, 50)
		local during = ProjectileRenderer.impactElapsed(0.03, stopper:elapsed(start, 50.03))
		local atEnd = ProjectileRenderer.impactElapsed(0.06, stopper:elapsed(start, 50.06))
		expect.near(during, contact, 1e-9)
		expect.near(atEnd, contact, 1e-6)
		-- The squash really is held: the same sample all through the hold.
		local heldA = ProjectileRenderer.splatSample(during, true, Vector3.one)
		local heldB = ProjectileRenderer.splatSample(atEnd, true, Vector3.one)
		expectVectorNear(heldA.scale, heldB.scale, 1e-5)
		expect.truthy(heldA.scale.Z < 1) -- part-way squashed along the normal
		-- After the hold it plays on from there.
		local after = ProjectileRenderer.impactElapsed(0.1, stopper:elapsed(start, 50.1))
		expect.near(after, contact + 0.04, 1e-6)
	end)

	t.test("the impact flash: FillTransparency 1 -> 0.5 -> 1 over 120 ms", function()
		local flash = Config.Vfx.ImpactFlash
		local length = flash.ms / 1000
		expect.equal(ProjectileRenderer.flashFill(0), 1)
		expect.near(ProjectileRenderer.flashFill(length / 2), flash.fillFrom, 1e-9)
		expect.near(ProjectileRenderer.flashFill(length / 4), 1 - (1 - flash.fillFrom) / 2, 1e-9)
		expect.equal(ProjectileRenderer.flashFill(length), 1)
		expect.equal(ProjectileRenderer.flashFill(1), 1)
		-- It never goes below fillFrom (no hard white flash).
		for i = 0, 24 do
			expect.truthy(ProjectileRenderer.flashFill(i * length / 24) >= flash.fillFrom - 1e-9)
		end
	end)

	t.test("during a hit-stop the impact flash stays at its peak, then fades out", function()
		local flash = Config.Vfx.ImpactFlash
		local length = flash.ms / 1000
		-- No hold: the flash clock is the time since the impact.
		expect.near(ProjectileRenderer.flashElapsed(0.03, nil), 0.03, 1e-9)
		-- Held (holdElapsed 0 all through the hold): the peak.
		local held = ProjectileRenderer.flashFill(ProjectileRenderer.flashElapsed(0.04, 0))
		expect.near(held, flash.fillFrom, 1e-9)
		-- After the hold it fades out over the second half and ends at 1.
		local later = ProjectileRenderer.flashFill(ProjectileRenderer.flashElapsed(0.09, length / 4))
		expect.truthy(later > flash.fillFrom and later < 1)
		expect.equal(ProjectileRenderer.flashFill(ProjectileRenderer.flashElapsed(0.2, length / 2)), 1)
	end)

	t.test("the release air ring is ThrowRing's", function()
		local ring = Config.Vfx.ThrowRing
		expect.equal(ring.toStuds, 1.6)
		expect.equal(ring.seconds, 0.18)
		expect.equal(ring.transparencyFrom, 0.5)
	end)

	-- Squishy overhaul: flight styles (spec 2026-10-09 §3.2) ------------------------------------------------------------

	local SquishRig = t.requireClient("Anim/SquishRig")
	local Catalog = t.requireShared("Catalog")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local STYLES = Config.Anim.rig.flight

	local function flightOf(def: any): any
		return Blueprints[def.blueprintId].motion.flight
	end

	t.test("a flight style's roll, nod and pulse are SquishRig.flightPose of the time since the release", function()
		local p = payload(10)
		for _, def in Catalog.list() do
			local flight = flightOf(def)
			for _, tau in { 0, 0.13, 0.5, 1.27 } do
				local sample = ProjectileRenderer.flightSample(p, tau, Vector3.zero, 1, def.visuals.flightSpin, flight)
				local roll, nod, pulse = SquishRig.flightPose(flight.style, tau, false, flight.amp, flight.pulse)
				expect.near(sample.roll, roll, 1e-9)
				expect.near(sample.nod, nod, 1e-9)
				expect.near(sample.pulse, pulse, 1e-9)
				expectVectorNear(sample.scale, stretch, 1e-6) -- the pulse is applied only to the detailed models
			end
		end
		-- Without a style (ReducedMotion, no motion row): today's flightSpin, no nod, no pulse.
		local plain = ProjectileRenderer.flightSample(p, 0.3, Vector3.zero, 1, "roll", nil)
		expect.near(plain.roll, ProjectileRenderer.rollAt("roll", 0.3), 1e-9)
		expect.equal(plain.nod, 0)
		expect.equal(plain.pulse, 1)
	end)

	t.test("every toy's flight keeps the face leading: LookVector·V̂ >= cos(maxNod + 1°)", function()
		local p = payload(0)
		expect.equal(#Catalog.list(), 14)
		for _, def in Catalog.list() do
			local flight = flightOf(def)
			local style = STYLES[flight.style]
			expect.truthy(style ~= nil)
			local maxNod = math.rad((style.nodDeg or 0) * (flight.amp or 1))
			local bound = math.cos(maxNod + math.rad(1))
			for i = 0, 150 do
				local tau = i / 50
				local sample = ProjectileRenderer.flightSample(p, tau, Vector3.zero, 1, def.visuals.flightSpin, flight)
				local frame = ProjectileRenderer.poseAt(sample.position, sample.velocity, sample.roll, sample.nod)
				local lead = frame.LookVector:Dot(sample.velocity.Unit)
				if lead < bound then
					error(`{def.id} ({flight.style}) at {tau} s: the face leads by {lead}, below {bound}`)
				end
				expectVectorNear(frame.Position, sample.position, 1e-4)
			end
		end
		-- No nod: the face points exactly along travel, whatever the roll.
		local frame = ProjectileRenderer.poseAt(Vector3.zero, Vector3.new(3, 4, 0), 2.1, 0)
		expectVectorNear(frame.LookVector, Vector3.new(0.6, 0.8, 0), 1e-5)
	end)

	t.test("the stretch pulse runs along travel (pivot Z) and keeps the volume", function()
		expect.equal(ProjectileRenderer.pulseScale(1), Vector3.one)
		for _, pulse in { 0.9, 1.1, 1.15 } do
			local S = ProjectileRenderer.pulseScale(pulse)
			expect.near(S.Z, pulse, 1e-6)
			expect.near(S.X, S.Y, 1e-9)
			expect.near(S.X * S.Y * S.Z, 1, 1e-5)
		end
	end)

	t.test("detail order: incoming first, then the rest by distance, the local player's own one last", function()
		local camera = Vector3.zero
		local toward = Vector3.new(0, 0, 30)
		local away = Vector3.new(0, 0, -30)
		local nearIn = ProjectileRenderer.detailKey(Vector3.new(0, 0, -10), toward, camera, false)
		local farIn = ProjectileRenderer.detailKey(Vector3.new(0, 0, -40), toward, camera, false)
		local nearOut = ProjectileRenderer.detailKey(Vector3.new(0, 0, -5), away, camera, false)
		local farOut = ProjectileRenderer.detailKey(Vector3.new(0, 0, -50), away, camera, false)
		local own = ProjectileRenderer.detailKey(Vector3.new(0, 0, -2), toward, camera, true)
		expect.truthy(nearIn < farIn)
		expect.truthy(farIn < nearOut)
		expect.truthy(nearOut < farOut)
		expect.truthy(farOut < own)
	end)

	t.test("detail budget: flightDetailModels, flightDetailModelsLow on phones (nil = Low), none reduced", function()
		local budgets = Config.Vfx.Budgets
		expect.equal(ProjectileRenderer.detailBudget("High", false), budgets.flightDetailModels)
		expect.equal(ProjectileRenderer.detailBudget("Low", false), budgets.flightDetailModelsLow)
		expect.equal(ProjectileRenderer.detailBudget(nil, false), budgets.flightDetailModelsLow)
		expect.equal(ProjectileRenderer.detailBudget("High", true), 0)
		expect.equal(budgets.flightDetailModels, 2)
		expect.equal(budgets.flightDetailModelsLow, 1)
	end)

	t.test("only a style with a pulse, or flaps for the toy's sections, asks for a detailed model", function()
		local wanted: { [string]: boolean } = {
			kitty_bread = true, -- tumble flaps its ears and tail
			pancake_pup = true, -- frisbee ear flaps
			strawberry_frog = true, -- hop pulse
			mochi_fox = true, -- tumble + pulse
			bird = true,
			dragon = true,
			cloud_bunny = true,
			cupcake_axolotl = true,
			toast = false, -- frisbee without sections
			chocolate = false,
			banana = false, -- spiral: roll only
			donut = false, -- wheel: roll only
			butter = false, -- tumble without sections or pulse
			boba_bear = false, -- upright: no flaps
		}
		for _, def in Catalog.list() do
			local blueprint = Blueprints[def.blueprintId]
			local got = ProjectileRenderer.wantsDetail(blueprint.motion.flight, blueprint.sections)
			if got ~= wanted[def.id] then
				error(`{def.id}: wantsDetail {got}, expected {wanted[def.id]}`)
			end
		end
		expect.falsy(ProjectileRenderer.wantsDetail(nil, nil))
		expect.falsy(ProjectileRenderer.wantsDetail({ style = "no_such_style" }, nil))
	end)

	t.test("a pool return puts the rig and the model back at rest: no flight, flap or squish face left", function()
		local Builder = t.requireShared("Art/SquishyBuilder")
		local SquishDeformer = t.requireClient("Anim/SquishDeformer")
		local def = Catalog.get("pancake_pup")
		local blueprint = Blueprints.pancake_pup
		local model = Builder.build("pancake_pup", "World", 1, { roundedBox = false })
		local before: { [Instance]: any } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("Weld") then
				before[descendant] = descendant.C0
			elseif descendant:IsA("DataModelMesh") then
				before[descendant] = { descendant.Scale, descendant.Offset }
			elseif descendant:IsA("BasePart") then
				before[descendant] = descendant.Transparency
			end
		end
		local deformer = SquishDeformer.attach(model)
		local rig = SquishRig.new(blueprint.motion, {
			axis = def.anim.squeezeAxis,
			rarity = def.rarity,
			sections = blueprint.sections,
			blink = false,
		})
		local out = SquishRig.newOut()
		rig:flight()
		rig:setDetail("hero")
		local turned = false
		for _ = 1, 30 do
			rig:step(1 / 60, out)
			out.S = out.S * stretch
			deformer:apply(out)
			for weld, c0 in before do
				if weld:IsA("Weld") and (weld :: Weld).C0 ~= c0 then
					turned = true
				end
			end
		end
		expect.truthy(turned) -- the ears flapped
		expect.equal(deformer:getFace(), "squish")
		ProjectileRenderer.resetModel(deformer, rig)
		expect.truthy(deformer:isResting())
		expect.equal(deformer:getFace(), "normal")
		for instance, value in before do
			if instance:IsA("Weld") then
				expect.equal((instance :: Weld).C0, value)
			elseif instance:IsA("DataModelMesh") then
				local mesh = instance :: DataModelMesh
				expect.equal(mesh.Scale, value[1])
				expect.equal(mesh.Offset, value[2])
			else
				expect.equal((instance :: BasePart).Transparency, value)
			end
		end
		-- The rig starts the next throw from rest: no flight, no lock, no flap.
		rig:step(1 / 60, out)
		expect.equal(out.face, "normal")
		expect.equal(out.roll, 0)
		expect.equal(out.pulse, 1)
		for _, angle in out.sections do
			expect.equal(angle, 0)
		end
		deformer:destroy()
		model:Destroy()
	end)

	-- First person (spec 2026-10-10 §3.6, §3.10) -----------------------------------------------------------------------

	local FP = Config.FirstPerson
	local NearFade = t.requireClient("Anim/NearFade")

	t.test("an own first-person throw starts at the release point; anything else at the held model", function()
		local fpPoint = Vector3.new(-1, 3.2, -45.5)
		local held = Vector3.new(1.2, 4, -42)
		-- The own throw in first person: the overlay's release point and its size factor.
		local point, factor = ProjectileRenderer.startPoint(true, fpPoint, 0.8, held)
		expect.equal(point, fpPoint)
		expect.equal(factor, 0.8)
		-- No release point for this release: the held model, factor 1.
		point, factor = ProjectileRenderer.startPoint(true, nil, nil, held)
		expect.equal(point, held)
		expect.equal(factor, 1)
		-- Another player's throw, or third person: never the release point.
		point, factor = ProjectileRenderer.startPoint(false, fpPoint, 0.8, held)
		expect.equal(point, held)
		expect.equal(factor, 1)
		-- No hand at all: nothing (the projectile starts on the server path, as before).
		expect.equal(ProjectileRenderer.startPoint(false, nil, nil, nil), nil)
		-- Duel and practice alike: the first drawn frame sits on the release point, at factor / flightScale.
		for _, kind in { "throw", "practice" } do
			local p = payload(100)
			p.kind = kind
			local offset, handScale = ProjectileRenderer.handStart(p.origin, fpPoint, 1, 0.5)
			expectVectorNear(offset, fpPoint - p.origin, 1e-5)
			expect.near(handScale, 2, 1e-9)
			local first = ProjectileRenderer.sampleAtTime(p, 100, offset, handScale, "wobble")
			expectVectorNear(first.position, fpPoint)
			expectVectorNear(first.scale, stretch * 2, 1e-5)
		end
	end)

	t.test("the apparent size is continuous at release, with and without the cover cut", function()
		local camera = Vector3.new(0, 5, 0)
		local ray = Vector3.new(0.25, -0.35, -1).Unit
		local d0 = 4.4 -- the uncut distance (a held-size model there looks exactly as big as the overlay toy)
		for _, flightScale in { 0.45, 0.62, 1.1 } do
			-- Uncut (factor 1 at D₀), cut by cover to 3 studs, and cut to the 1.5-stud minimum.
			for _, d in { d0, 3, 1.5 } do
				local p = payload(0)
				local point = camera + ray * d
				local offset, handScale = ProjectileRenderer.handStart(p.origin, point, d / d0, flightScale)
				local first = ProjectileRenderer.flightSample(p, 0, offset, handScale, "wobble", nil)
				-- The drawn size (the flight model built at flightScale × the deformer scale, stretch taken out) over
				-- its distance from the camera: the same angle on screen whatever the cut.
				local drawn = flightScale * first.scale.X / stretch.X
				expect.near(drawn / (first.position - camera).Magnitude, 1 / d0, 1e-5)
			end
		end
		-- Third person is today's: a held-size model (scale 1) at the hand.
		local _, handScale = ProjectileRenderer.handStart(Vector3.zero, Vector3.one, 1, 0.62)
		expect.near(handScale, 1 / 0.62, 1e-9)
	end)

	t.test("the own first-person release ring is half size; every other ring as before", function()
		expect.equal(FP.ownRingScale, 0.5)
		expect.equal(ProjectileRenderer.ringScale(true), FP.ownRingScale)
		expect.equal(ProjectileRenderer.ringScale(false), 1)
	end)

	t.test("in first person projectiles near the camera fade, except the own one in its first 0.2 s", function()
		local eye = Vector3.new(3, 5, -20)
		local function at(d: number): Vector3
			return eye + Vector3.new(0, 0, -d)
		end
		-- Third person (no eye): nothing ever fades.
		expect.equal(ProjectileRenderer.nearFadeAt(nil, at(1), false, 1), 0)
		expect.equal(ProjectileRenderer.nearFadeAt(nil, at(1), true, 1), 0)
		-- First person: 1 inside 2.5 studs, 0 beyond 4.5, linear between, for any thrower's projectile.
		expect.equal(ProjectileRenderer.nearFadeAt(eye, at(2), false, 0.05), 1)
		expect.near(ProjectileRenderer.nearFadeAt(eye, at(3.5), false, 0.5), 0.5, 1e-5)
		expect.equal(ProjectileRenderer.nearFadeAt(eye, at(6), false, 0.5), 0)
		-- The own projectile leaves the hand inside the band on purpose: no fade for its first 0.2 s.
		expect.equal(ProjectileRenderer.nearFadeAt(eye, at(3.5), true, 0.1), 0)
		expect.near(ProjectileRenderer.nearFadeAt(eye, at(3.5), true, NearFade.OWN_GRACE_SECONDS), 0.5, 1e-5)
	end)

	t.test("at impact the near fade wins over the splat fade, and the outline fades with it", function()
		local projectile = Config.Vfx.Projectile
		local splat = hit.splatMs / 1000
		local shrink = hit.shrinkMs / 1000
		-- A first-person victim: the splat sits 2.1-2.7 studs from the eyes, near 0.9-1.
		for _, distance in { 2.1, 2.4, 2.7, 3.5 } do
			local near = NearFade.amount(distance)
			for i = 0, 20 do
				local sample = ProjectileRenderer.splatSample((splat + shrink) * i / 20, true, Vector3.one)
				local fade = ProjectileRenderer.partFade(sample.fade, near)
				expect.equal(fade, math.max(sample.fade, near)) -- never lower than either
			end
		end
		expect.equal(ProjectileRenderer.partFade(0, 0), 0) -- third person: the splat fade alone
		expect.equal(ProjectileRenderer.partFade(0.7, 0), 0.7)
		-- The outline: both transparencies move toward 1 by the near fade (a Highlight may not follow the parts).
		local outline, fill = ProjectileRenderer.outlineFade(0, projectile.fillTransparency)
		expect.near(outline, projectile.outlineTransparency, 1e-6) -- no fade: today's outline
		expect.near(fill, projectile.fillTransparency, 1e-6)
		outline, fill = ProjectileRenderer.outlineFade(1, Config.Vfx.ImpactFlash.fillFrom)
		expect.near(outline, 1, 1e-6)
		expect.near(fill, 1, 1e-6)
		outline, fill = ProjectileRenderer.outlineFade(0.5, Config.Vfx.ImpactFlash.fillFrom)
		expect.near(outline, projectile.outlineTransparency + (1 - projectile.outlineTransparency) * 0.5, 1e-6)
		expect.near(fill, 0.75, 1e-6)
	end)

	t.test("feature 1: ThrowStarted.power reads as a charge 0..1", function()
		expect.equal(ProjectileRenderer.powerOf(nil), 0)
		expect.equal(ProjectileRenderer.powerOf(0.4), 0.4)
		expect.equal(ProjectileRenderer.powerOf(3), 1)
		expect.equal(ProjectileRenderer.powerOf(-1), 0)
		expect.equal(ProjectileRenderer.powerOf(0 / 0), 0)
		expect.equal(ProjectileRenderer.powerOf(math.huge), 0)
		expect.equal(ProjectileRenderer.powerOf("1"), 0)
	end)

	t.test("feature 1: a caught toy flies into the catcher's hands over flyInSeconds, then stays", function()
		local fly = Config.Vfx.Catch.flyInSeconds
		local from, hands = Vector3.new(0, 4, 10), Vector3.new(0, 4.8, 1.8)
		expect.near((ProjectileRenderer.caughtAt(from, hands, 0) - from).Magnitude, 0, 1e-6)
		local half = ProjectileRenderer.caughtAt(from, hands, fly / 2)
		expect.near((half - from:Lerp(hands, 0.75)).Magnitude, 0, 1e-5) -- Quad Out: 3/4 of the way at half time
		expect.near((ProjectileRenderer.caughtAt(from, hands, fly) - hands).Magnitude, 0, 1e-6)
		expect.near((ProjectileRenderer.caughtAt(from, hands, 5) - hands).Magnitude, 0, 1e-6)
		expect.near((ProjectileRenderer.caughtAt(from, nil, 0.05) - from).Magnitude, 0, 1e-6)
	end)

	t.test("no white impact fill for the local first-person victim; every other flash as before", function()
		expect.falsy(ProjectileRenderer.impactFlashOn("player", true, true))
		expect.truthy(ProjectileRenderer.impactFlashOn("player", true, false)) -- the victim in third person
		expect.truthy(ProjectileRenderer.impactFlashOn("player", false, true)) -- the thrower or a spectator
		expect.truthy(ProjectileRenderer.impactFlashOn("target", false, true)) -- a practice target
		expect.truthy(ProjectileRenderer.impactFlashOn("target", false, false))
		for _, kind in { "geometry", "expired", "fizzle" } do
			expect.falsy(ProjectileRenderer.impactFlashOn(kind, false, false)) -- minor impacts never flashed
		end
	end)
end
