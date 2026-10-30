--!strict
-- ThrowController_Test: unit tests for the pure parts of StarterPlayerScripts.Client.Controllers.ThrowController.
-- Server only (ServerStorage.UnitTest). Edit mode: init() is not called (no input, no remotes, no LocalPlayer); the
-- windup is stepped by hand on a FakeClock.
-- Contract (DESIGN §5.2, §5.5, §5.6, §5.10, §9.7, §9.10, §12 #8):
--   * windup ("charge") curve: throwWindup weight 0 -> 1 (Quad Out) by 0.6 W, then held cocked; the held squishy's rig
--     hold and squish face (windupRigHold) are told before the rig steps, so that very step shows them;
--   * the remaining windup is time-warped onto releaseAt (rate clamped [0.5, 3]); the release starts exactly at
--     releaseAt when on time, or now when the answer came late; an unanswered windup cancels 600 ms after it could
--     have released and fades out over 120 ms; another thrower's windup is mapped onto releaseAt - W;
--   * release -> follow-through -> return timings (70 / 250 / 450 ms), Dragon Rush caster release and recovery;
--   * aim: pitch clamped to [-35°, +65°] keeping the heading, the practice cone keeps the pitch, aim assist moves the
--     point `strength` of the way only inside its cone, ultimate aim is flat;
--   * cooldown ring progress, input buffer (0.15 s), the ThrowRejected nextThrowAt guard, the touch shoulder offset;
--   * server payloads are type-checked before use.
-- First person (spec 2026-10-10 §3.5, §3.6): the windup hold starts from the rig's depth at the throw press
--   (windupHold(squash) + (yPress - 1)·(1 - squash); exactly today's with yPress = 1), so a throw started mid-squeeze
--   never makes the shown S jump more than 0.02 between steps; localWindup() / localUlt() return plain values (nil and
--   false with nothing running), read from the local windup and ult records by windupValues / ultValues;
--   setShoulderSuppressed keeps the saved CameraOffset while first person is on, and the next update after it is
--   switched off applies the 1.75-stud offset again (shoulderApplies / shoulderStep on a stand-in humanoid).
-- Feature 1 (2026-10-11, hold to charge; design: the combat-effects page "Squishy Combat FP v2.html", html:323-339):
--   holdStep, while no charge runs: a held press starts charging once the throw is ready (a press during the cooldown
--   waits); a press let go before it was ready still throws uncharged when the throw becomes ready inside the input
--   buffer, and is dropped outside it; a running charge is the release's (nil); localCharge() is nil, nil, false with
--   nothing running; Config.Duel.Rules.HoldToCharge replaces HoldToRepeat.
-- Power-ups v1.1 review fix (2026-10-16): in a 12-player match a throw waits while the own throws in the air reach
--   the server's MaxActiveProjectilesPerPlayer (projectileCapped); duels and practice never wait for it; outside a
--   match atThrowCap is false. Integration (2026-10-16): rapidCooldownMultiplier gives the server's number, so a live
--   rapid throw's cooldown is exactly CooldownClamp.Min.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local TOLERANCE = 1e-6
local VECTOR_TOLERANCE = 1e-4

return function(t: Context)
	local ThrowController = t.requireClient("Controllers/ThrowController")
	local ProjectileMath = t.requireShared("ProjectileMath")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")
	local expect = t.expect
	local throwAnim = Config.Anim.throw
	local combat = Config.Combat
	local W = 0.18

	local function expectVectorNear(actual: Vector3, wanted: Vector3, tolerance: number?)
		local tol = tolerance or VECTOR_TOLERANCE
		expect.near(actual.X, wanted.X, tol)
		expect.near(actual.Y, wanted.Y, tol)
		expect.near(actual.Z, wanted.Z, tol)
	end

	-- The angle between the headings of a and b. atan2(|cross|, dot) rather than acos(dot): Vector3 is single precision,
	-- and acos near 1 turns a 1e-7 rounding of the dot into ~0.03°.
	local function flatAngleDeg(a: Vector3, b: Vector3): number
		local fa, fb = Vector3.new(a.X, 0, a.Z).Unit, Vector3.new(b.X, 0, b.Z).Unit
		return math.deg(math.atan2(fa:Cross(fb).Magnitude, fa:Dot(fb)))
	end

	-- Windup ("charge") curve -----------------------------------------------------------------------------------------

	t.test("the windup weight rises Quad Out to 1 by 0.6 W, then stays cocked", function()
		local reach = throwAnim.windupReachFraction * W
		expect.near(ThrowController.windupWeight(0, W), 0, TOLERANCE)
		-- Quad Out at alpha 0.5 = 1 - 0.5² = 0.75
		expect.near(ThrowController.windupWeight(reach / 2, W), 0.75, 1e-4)
		expect.near(ThrowController.windupWeight(reach, W), 1, TOLERANCE)
		expect.near(ThrowController.windupWeight(W, W), 1, TOLERANCE)
		local previous = -1
		for i = 0, 20 do
			local weight = ThrowController.windupWeight(W * i / 20, W)
			expect.truthy(weight >= previous - 1e-9)
			previous = weight
		end
		expect.equal(ThrowController.windupWeight(0.1, 0), 1)
	end)

	t.test("the windup squashes the held squishy with the arm weight", function()
		local sample = ThrowController.windupSample(W, W)
		expect.equal(sample.from, "throwWindup")
		expect.equal(sample.to, "throwWindup")
		expect.near(sample.weight, 1, TOLERANCE)
		expect.near(sample.squash, 1, TOLERANCE)
	end)

	-- Squishy overhaul (spec 2026-10-09 §3.2): the windup holds the toy's rig at c (direct, no spring), down to
	-- anticipationC 0.90 once cocked, and the squish face shows from then on.
	t.test("the windup holds the rig at c, 0.90 once cocked, with the squish face from then on", function()
		local c0, cocked0 = ThrowController.windupHold(0)
		expect.near(c0, 1, TOLERANCE)
		expect.falsy(cocked0)
		expect.equal(throwAnim.anticipationC, 0.9)
		local half, cockedHalf = ThrowController.windupHold(0.5)
		expect.near(half, 1 - (1 - throwAnim.anticipationC) / 2, TOLERANCE)
		expect.falsy(cockedHalf)
		local full, cocked = ThrowController.windupHold(1)
		expect.near(full, throwAnim.anticipationC, TOLERANCE)
		expect.truthy(cocked)
		-- Along the real windup: c follows the arm weight, and the face turns once the weight reaches 1 (0.6 W).
		local reach = throwAnim.windupReachFraction * W
		local _, before = ThrowController.windupHold(ThrowController.windupSample(reach * 0.9, W).squash)
		local _, after = ThrowController.windupHold(ThrowController.windupSample(reach, W).squash)
		expect.falsy(before)
		expect.truthy(after)
		-- Out of range or NaN never squashes past the cocked value.
		expect.near((ThrowController.windupHold(3)), throwAnim.anticipationC, TOLERANCE)
		expect.near((ThrowController.windupHold(0 / 0)), 1, TOLERANCE)
	end)

	t.test(
		"windupRigHold before the rig steps: that very step shows its c and, once cocked, the squish face",
		function()
			local SquishRig = t.requireClient("Anim/SquishRig")
			local Blueprints = t.requireShared("Art/SquishyBlueprints")
			local rig = SquishRig.new(Blueprints.kitty_bread.motion, { axis = "Y", seed = 1, blink = false })
			local out = SquishRig.newOut()
			rig:step(1 / 60, out)
			local cocked = ThrowController.windupRigHold(rig, 0.5, false)
			expect.falsy(cocked)
			rig:step(1 / 60, out)
			expect.near(out.S.Y, (ThrowController.windupHold(0.5)), 1e-5)
			expect.equal(out.face, "normal")
			cocked = ThrowController.windupRigHold(rig, 1, cocked)
			expect.truthy(cocked)
			rig:step(1 / 60, out)
			expect.near(out.S.Y, throwAnim.anticipationC, 1e-5)
			expect.equal(out.face, "squish")
			-- Letting the windup go back below cocked (a cancel fading out) turns the face back.
			cocked = ThrowController.windupRigHold(rig, 0.4, cocked)
			expect.falsy(cocked)
			rig:step(1 / 60, out)
			expect.equal(out.face, "normal")
		end
	)

	t.test("the time-warp rate is clamped to [0.5, 3] and maxes out once releaseAt has passed", function()
		expect.near(ThrowController.warpRate(0.1, 0.1), 1, TOLERANCE)
		expect.near(ThrowController.warpRate(0.13, 0.05), 2.6, 1e-9)
		expect.equal(ThrowController.warpRate(1, 0.1), throwAnim.timeWarpMax)
		expect.equal(ThrowController.warpRate(0.01, 1), throwAnim.timeWarpMin)
		expect.equal(ThrowController.warpRate(0.1, 0), throwAnim.timeWarpMax)
		expect.equal(ThrowController.warpRate(0.1, -0.2), throwAnim.timeWarpMax)
	end)

	t.test("an own windup ticks to cocked, then releases exactly at releaseAt", function()
		local clock = FakeClock.new(1000)
		local w = ThrowController.newWindup(W, clock.now() + W + throwAnim.cockedHoldMaxMs / 1000, false)
		local sample
		for _ = 1, 4 do
			clock.advance(0.05)
			sample = ThrowController.stepWindup(w, 0.05, clock.now())
		end
		expect.near(w.tau, W, TOLERANCE)
		expect.near(sample.weight, 1, TOLERANCE)
		expect.falsy(w.cancelled)
		-- ThrowStarted: releaseAt in 50 ms.
		local releaseAt = clock.now() + 0.05
		w.releaseAt = releaseAt
		clock.advance(0.025)
		sample = ThrowController.stepWindup(w, 0.025, clock.now())
		expect.equal(sample.to, "throwWindup")
		expect.equal(w.releaseStart, nil)
		clock.set(releaseAt)
		sample = ThrowController.stepWindup(w, 0.025, clock.now())
		expect.equal(w.releaseStart, releaseAt)
		expect.equal(sample.from, "throwWindup")
		expect.equal(sample.to, "throwRelease")
		expect.near(sample.squash, 0, TOLERANCE)
	end)

	t.test("an early answer time-warps the rest of the windup onto releaseAt", function()
		local clock = FakeClock.new(50)
		local w = ThrowController.newWindup(W, math.huge, false)
		clock.advance(0.05)
		ThrowController.stepWindup(w, 0.05, clock.now())
		expect.near(w.tau, 0.05, 1e-9)
		local releaseAt = clock.now() + 0.1
		w.releaseAt = releaseAt
		clock.advance(0.025)
		ThrowController.stepWindup(w, 0.025, clock.now())
		-- 0.13 s of windup left in 0.075 s: rate 1.733 for this step, so tau = 0.05 + 0.025 × 0.13 / 0.075
		expect.near(w.tau, 0.05 + 0.025 * 0.13 / 0.075, 1e-6)
		-- Far too little time left: the rate is clamped to timeWarpMax.
		clock.set(releaseAt - 0.01)
		local before = w.tau
		ThrowController.stepWindup(w, 0.01, clock.now())
		expect.near(w.tau, math.min(before + 0.01 * throwAnim.timeWarpMax, W), 1e-6)
		clock.set(releaseAt)
		ThrowController.stepWindup(w, 0.01, clock.now())
		expect.equal(w.releaseStart, releaseAt)
	end)

	t.test("a late answer releases now and the animation still runs its full length", function()
		local clock = FakeClock.new(10)
		local w = ThrowController.newWindup(W, math.huge, true)
		w.releaseAt = 9 -- a second in the past
		local sample = ThrowController.stepWindup(w, 1 / 60, clock.now())
		expect.equal(w.releaseStart, clock.now())
		expect.equal(sample.to, "throwRelease")
		clock.advance(throwAnim.returnEndMs / 2000)
		ThrowController.stepWindup(w, 1 / 60, clock.now())
		expect.falsy(w.finished)
		clock.advance(throwAnim.returnEndMs / 2000 + 0.01)
		ThrowController.stepWindup(w, 1 / 60, clock.now())
		expect.truthy(w.finished)
	end)

	t.test("an unanswered windup cancels after the cocked hold and fades out over cancelBlendMs", function()
		local clock = FakeClock.new(0)
		local deadline = W + throwAnim.cockedHoldMaxMs / 1000
		local w = ThrowController.newWindup(W, deadline, false)
		local steps = 0
		while not w.cancelled and steps < 200 do
			clock.advance(1 / 60)
			ThrowController.stepWindup(w, 1 / 60, clock.now())
			steps += 1
		end
		expect.truthy(w.cancelled)
		expect.truthy(clock.now() > deadline)
		expect.truthy(clock.now() <= deadline + 1 / 60 + 1e-9)
		local half = ThrowController.stepWindup(w, throwAnim.cancelBlendMs / 2000, clock.now())
		expect.near(half.weight, 0.5, 1e-6)
		expect.falsy(w.finished)
		ThrowController.stepWindup(w, throwAnim.cancelBlendMs / 1000, clock.now())
		expect.truthy(w.finished)
		expect.equal(ThrowController.stepWindup(w, 1 / 60, clock.now()), nil)
	end)

	t.test("cancelWindup starts the fade from the last pose and is idempotent", function()
		local w = ThrowController.newWindup(W, math.huge, false)
		ThrowController.stepWindup(w, W, 0)
		ThrowController.cancelWindup(w)
		ThrowController.cancelWindup(w)
		expect.truthy(w.cancelled)
		expect.near((w.cancelFrom :: any).weight, 1, TOLERANCE)
	end)

	t.test("another thrower's windup is mapped onto releaseAt - W", function()
		local w = ThrowController.newWindup(W, math.huge, true)
		expect.equal(ThrowController.stepWindup(w, 1 / 60, 100), nil) -- releaseAt not known yet
		w.releaseAt = 100
		expect.equal(ThrowController.stepWindup(w, 1 / 60, 100 - W - 0.1), nil) -- windup not started yet
		local sample = ThrowController.stepWindup(w, 1 / 60, 100 - W / 2)
		expect.near(w.tau, W / 2, 1e-6)
		expect.near(sample.weight, ThrowController.windupWeight(W / 2, W), 1e-9)
		ThrowController.stepWindup(w, 1 / 60, 100)
		expect.equal(w.releaseStart, 100)
	end)

	-- Release, follow-through, return ---------------------------------------------------------------------------------

	t.test("release snaps (Quint Out) in 70 ms, follows to 250 ms and returns to weight 0 by 450 ms", function()
		local snap = throwAnim.releaseSnapMs / 1000
		local follow = throwAnim.followEndMs / 1000
		local finish = throwAnim.returnEndMs / 1000
		local s0 = ThrowController.releaseSample(0)
		expect.equal(s0.from, "throwWindup")
		expect.equal(s0.to, "throwRelease")
		expect.near(s0.u, 0, TOLERANCE)
		local mid = ThrowController.releaseSample(snap / 2)
		expect.near(mid.u, 1 - 0.5 ^ 5, 1e-4) -- Quint Out at 0.5
		local s1 = ThrowController.releaseSample(snap)
		expect.equal(s1.from, "throwRelease")
		expect.equal(s1.to, "throwFollow")
		local s2, done2 = ThrowController.releaseSample((follow + finish) / 2)
		expect.equal(s2.from, "throwFollow")
		expect.near(s2.weight, 0.5, 1e-4) -- Sine InOut at 0.5
		expect.falsy(done2)
		local s3, done3 = ThrowController.releaseSample(finish)
		expect.near(s3.weight, 0, TOLERANCE)
		expect.truthy(done3)
	end)

	t.test("the Dragon Rush caster snaps, hunches through the recovery, then blends out", function()
		local recovery = Config.Abilities.dragon_rush.recoverySeconds
		local snap = Config.Vfx.DragonRush.releaseArmSnapMs / 1000
		local blend = Config.Vfx.DragonRush.recoveryBlendMs / 1000
		local a = ThrowController.ultReleaseSample(0, recovery)
		expect.equal(a.from, "ultCharge")
		expect.equal(a.to, "throwRelease")
		local b = ThrowController.ultReleaseSample(snap + 0.01, recovery)
		expect.equal(b.to, "rushRecovery")
		local c, doneC = ThrowController.ultReleaseSample(recovery - 0.01, recovery)
		expect.equal(c.from, "rushRecovery")
		expect.near(c.weight, 1, TOLERANCE)
		expect.falsy(doneC)
		local d, doneD = ThrowController.ultReleaseSample(recovery + blend + 0.01, recovery)
		expect.near(d.weight, 0, TOLERANCE)
		expect.truthy(doneD)
	end)

	t.test("blendDegrees lerps between poses; a joint missing in one pose counts as 0", function()
		local poses = Config.Anim.poses
		local at0 = ThrowController.blendDegrees("throwWindup", "throwRelease", 0, "R15")
		expectVectorNear(at0.RightShoulder, poses.throwWindup.R15.RightShoulder)
		local half = ThrowController.blendDegrees("throwWindup", "throwRelease", 0.5, "R15")
		expectVectorNear(half.RightWrist, poses.throwWindup.R15.RightWrist / 2) -- no wrist in throwRelease
		local at1 = ThrowController.blendDegrees("throwWindup", "throwRelease", 1, "R15")
		expectVectorNear(at1.RightShoulder, poses.throwRelease.R15.RightShoulder)
		expectVectorNear(at1.RightWrist, Vector3.zero)
		local r6 = ThrowController.blendDegrees("ultCharge", "throwRelease", 1, "R6")
		expectVectorNear(r6.LeftShoulder, Vector3.zero) -- throwRelease has no left shoulder on R6
	end)

	-- Aim ---------------------------------------------------------------------------------------------------------------

	t.test("clampPitch keeps the heading and clamps the pitch to [-35°, +65°]", function()
		local minDeg, maxDeg = combat.Throw.pitchMinDeg, combat.Throw.pitchMaxDeg
		local steep = Vector3.new(0.1, math.sin(math.rad(80)), -math.cos(math.rad(80))).Unit
		local up = ThrowController.clampPitch(steep, minDeg, maxDeg)
		expect.near(ProjectileMath.pitchDeg(up), maxDeg, 1e-3)
		expect.near(up.Magnitude, 1, 1e-6)
		expect.near(flatAngleDeg(up, steep), 0, 1e-3)
		local down = ThrowController.clampPitch(Vector3.new(1, -3, 0), minDeg, maxDeg)
		expect.near(ProjectileMath.pitchDeg(down), minDeg, 1e-3)
		local inside = Vector3.new(0, math.sin(math.rad(20)), -math.cos(math.rad(20)))
		expectVectorNear(ThrowController.clampPitch(inside, minDeg, maxDeg), inside)
		-- Straight up has no heading of its own: the fallback forward gives it one.
		local vertical = ThrowController.clampPitch(Vector3.yAxis, minDeg, maxDeg, Vector3.new(1, 0, 0))
		expect.near(ProjectileMath.pitchDeg(vertical), maxDeg, 1e-3)
		expect.truthy(vertical.X > 0)
	end)

	t.test("clampToCone turns the heading into the practice cone and keeps the pitch", function()
		-- The range forward (WorldLayout's arenaThrowDirection: -Z toward Diego's arena targets, FULL FINAL lobby).
		local PracticeTargets = t.requireShared("Practice/PracticeTargets")
		local forward = PracticeTargets.FORWARD
		local side = forward:Cross(Vector3.yAxis) -- 90° off forward, flat
		local cone = combat.Throw.practiceConeDeg - 1
		local pitch = math.rad(10)
		local sideways = side * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0) -- 90° off forward
		local clamped = ThrowController.clampToCone(sideways, forward, cone)
		expect.near(flatAngleDeg(clamped, forward), cone, 1e-3)
		expect.near(ProjectileMath.pitchDeg(clamped), 10, 1e-3)
		expect.near(clamped.Magnitude, 1, 1e-6)
		-- It turns toward the side the aim was on.
		expect.truthy(clamped:Dot(side) > 0)
		local inside = (forward + Vector3.new(0, 0.2, 0) + side * 0.3).Unit
		expectVectorNear(ThrowController.clampToCone(inside, forward, cone), inside)
		-- A clamped aim passes the server's practice cone check.
		expect.truthy(PracticeTargets.inCone(clamped))
	end)

	t.test("aim assist moves the point `strength` of the way only inside its cone", function()
		local origin = Vector3.zero
		local ray = Vector3.new(0, 0, -1)
		local aim = Vector3.new(0, 0, -50)
		local near = Vector3.new(1, 0, -50) -- ≈ 1.15° off the ray
		local moved, did = ThrowController.applyAimAssist(origin, ray, aim, near, 4, 0.5)
		expect.truthy(did)
		expectVectorNear(moved, Vector3.new(0.5, 0, -50))
		local far = Vector3.new(10, 0, -50) -- ≈ 11.3°
		local same, didFar = ThrowController.applyAimAssist(origin, ray, aim, far, 4, 0.5)
		expect.falsy(didFar)
		expectVectorNear(same, aim)
		local _, didZero = ThrowController.applyAimAssist(origin, ray, aim, near, 4, 0)
		expect.falsy(didZero)
		-- Keyboard and mouse have no assist (§5.10).
		expect.falsy(combat.AimAssist.KeyboardAndMouse.enabled)
	end)

	t.test("the ultimate aims flat, with a fallback heading straight above or below", function()
		local dir = ThrowController.flatAim(Vector3.new(0, 3, 0), Vector3.new(30, -5, 40), Vector3.new(0, 0, -1))
		expectVectorNear(dir, Vector3.new(0.6, 0, 0.8))
		local fallback = ThrowController.flatAim(Vector3.zero, Vector3.new(0, 10, 0), Vector3.new(0, 0.5, -2))
		expectVectorNear(fallback, Vector3.new(0, 0, -1))
		expect.truthy(Vector3.new(dir.X, 0, dir.Z).Magnitude >= Config.Abilities.dragon_rush.minHorizontalAim)
	end)

	t.test("capsule and target centres sit at the middle of the standard capsule", function()
		local hitbox = combat.Hitbox
		local mid = (hitbox.bottomOffset + hitbox.topOffset) / 2
		expectVectorNear(ThrowController.capsuleCentre(Vector3.new(1, 3, 2)), Vector3.new(1, 3 + mid, 2))
		local rootAbove = hitbox.radius - hitbox.bottomOffset
		expectVectorNear(
			ThrowController.targetCentre(Vector3.new(-36, 0.06, -27)),
			Vector3.new(-36, 0.06 + rootAbove + mid, -27)
		)
	end)

	-- Cooldown, buffer, rejection guard, shoulder offset ----------------------------------------------------------------

	t.test("the cooldown ring fills from the release to readyAt", function()
		expect.near(ThrowController.cooldownProgress(1.5, 1, 2), 0.5, TOLERANCE)
		expect.equal(ThrowController.cooldownProgress(2, 1, 2), 1)
		expect.equal(ThrowController.cooldownProgress(3, 1, 2), 1)
		expect.equal(ThrowController.cooldownProgress(0.5, 1, 1), 1) -- nothing to show
		expect.near(ThrowController.cooldownProgress(1, 1, 2), 0, TOLERANCE)
	end)

	t.test("a press is buffered only within InputBufferSeconds of readyAt", function()
		local buffer = Config.Duel.Rules.InputBufferSeconds
		expect.truthy(ThrowController.bufferKeeps(10, 10 + buffer, buffer))
		expect.truthy(ThrowController.bufferKeeps(10, 10.05, buffer))
		expect.falsy(ThrowController.bufferKeeps(10, 10 + buffer + 0.01, buffer))
		expect.truthy(ThrowController.bufferKeeps(10, 9, buffer)) -- already ready
	end)

	t.test("hold to charge: a held press charges once ready; a short tap throws in the buffer or is dropped", function()
		expect.equal(Config.Duel.Rules.HoldToCharge, true)
		expect.equal((Config.Duel.Rules :: any).HoldToRepeat, nil)
		-- held, charging, ready, buffered, keeps
		expect.equal(ThrowController.holdStep(true, false, true, true, true), "start")
		expect.equal(ThrowController.holdStep(true, false, false, true, true), nil) -- pressed in the cooldown: wait
		expect.equal(ThrowController.holdStep(true, true, true, true, true), nil) -- a running charge: the release's
		expect.equal(ThrowController.holdStep(false, true, true, false, false), nil)
		expect.equal(ThrowController.holdStep(false, false, true, true, true), "throw") -- let go early, now ready
		expect.equal(ThrowController.holdStep(false, false, false, true, true), nil) -- let go, not ready yet: wait
		expect.equal(ThrowController.holdStep(false, false, false, true, false), "drop") -- outside the buffer
		expect.equal(ThrowController.holdStep(false, false, true, false, false), nil) -- nothing pressed
		-- Edit mode: no charge runs.
		local c, elapsed, full = ThrowController.localCharge()
		expect.equal(c, nil)
		expect.equal(elapsed, nil)
		expect.equal(full, false)
	end)

	t.test("a ThrowRejected nextThrowAt is adopted only when finite and not far ahead", function()
		local ahead = Config.Duel.Rules.CooldownClamp.Max + 1
		expect.equal(ThrowController.acceptedNextThrowAt(101.2, 100, ahead), 101.2)
		expect.equal(ThrowController.acceptedNextThrowAt(99, 100, ahead), 99)
		expect.equal(ThrowController.acceptedNextThrowAt(math.huge, 100, ahead), nil) -- before Active
		expect.equal(ThrowController.acceptedNextThrowAt(0 / 0, 100, ahead), nil)
		expect.equal(ThrowController.acceptedNextThrowAt(100 + ahead + 1, 100, ahead), nil)
		expect.equal(ThrowController.acceptedNextThrowAt("soon", 100, ahead), nil)
	end)

	t.test("the touch shoulder offset is camRight × 1.75 in the root's object space", function()
		local studs = combat.Aim.touchShoulderOffsetStuds
		expectVectorNear(
			ThrowController.shoulderOffset(CFrame.identity, Vector3.xAxis, studs),
			Vector3.new(studs, 0, 0)
		)
		-- Root turned 90° about Y: world +X is the root's +Z.
		local turned = CFrame.Angles(0, math.rad(90), 0)
		expectVectorNear(ThrowController.shoulderOffset(turned, Vector3.xAxis, studs), Vector3.new(0, 0, studs))
		-- A camera right with a vertical part (rolled camera) is flattened; a vertical one gives no offset.
		local tilted = ThrowController.shoulderOffset(CFrame.identity, Vector3.new(1, 1, 0), studs)
		expect.near(tilted.Magnitude, studs, 1e-5)
		expect.near(tilted.Y, 0, 1e-6)
		expectVectorNear(ThrowController.shoulderOffset(CFrame.identity, Vector3.yAxis, studs), Vector3.zero)
	end)

	t.test("first person suppresses the shoulder offset; switched back, the next update applies it again", function()
		-- First-person spec 2026-10-10 §3.1: the 1.75-stud offset would put the eye outside the head.
		local touch, pad, mouse =
			Enum.PreferredInput.Touch, Enum.PreferredInput.Gamepad, Enum.PreferredInput.KeyboardAndMouse
		for _, input in { touch, pad } do
			expect.truthy(ThrowController.shoulderApplies(true, input, false))
			expect.falsy(ThrowController.shoulderApplies(true, input, true))
			expect.falsy(ThrowController.shoulderApplies(false, input, false))
		end
		expect.falsy(ThrowController.shoulderApplies(true, mouse, false))
		-- One update per frame on a stand-in humanoid (Duel or Practice context, touch): the offset is written and the
		-- old CameraOffset saved once; suppressed, the saved value goes back and stays; released, the offset returns.
		local studs = combat.Aim.touchShoulderOffsetStuds
		local saved = Vector3.new(0, 0.25, 0)
		local humanoid: any = { CameraOffset = saved, Parent = workspace }
		local offset = ThrowController.shoulderOffset(CFrame.identity, Vector3.xAxis, studs)
		local function update(record: any, suppressed: boolean): any
			local applies = ThrowController.shoulderApplies(true, touch, suppressed)
			return ThrowController.shoulderStep(record, humanoid, if applies then offset else nil)
		end
		local record = update(nil, false)
		expectVectorNear(humanoid.CameraOffset, Vector3.new(studs, 0, 0))
		record = update(record, false)
		expectVectorNear(record.saved, saved)
		ThrowController.setShoulderSuppressed(true)
		expect.truthy(ThrowController.isShoulderSuppressed())
		for _ = 1, 3 do
			record = update(record, ThrowController.isShoulderSuppressed())
			expectVectorNear(humanoid.CameraOffset, saved)
			expect.equal(record, nil)
		end
		ThrowController.setShoulderSuppressed(false)
		expect.falsy(ThrowController.isShoulderSuppressed())
		record = update(record, ThrowController.isShoulderSuppressed())
		expectVectorNear(humanoid.CameraOffset, Vector3.new(studs, 0, 0))
		-- A new humanoid (respawn) gets the old one's saved value back first.
		local other: any = { CameraOffset = Vector3.zero, Parent = workspace }
		local old = humanoid
		humanoid = other
		update(record, false)
		expectVectorNear(old.CameraOffset, saved)
		expectVectorNear(other.CameraOffset, Vector3.new(studs, 0, 0))
	end)

	-- Payloads ----------------------------------------------------------------------------------------------------------

	t.test("ThrowStarted payloads are type-checked", function()
		local good = {
			seq = 1,
			nextThrowAt = 101,
			projId = 7,
			throwerId = 42,
			squishyId = "kitty_bread",
			kind = "throw",
			origin = Vector3.new(0, 4, 0),
			velocity = Vector3.new(0, 10, -90),
			gravity = 30,
			radius = 1,
			releaseAt = 100,
		}
		expect.equal(ThrowController.parseThrowStarted(good), good)
		for _, field in { "projId", "throwerId", "squishyId", "origin", "velocity", "gravity", "radius", "releaseAt" } do
			local broken: any = table.clone(good)
			broken[field] = nil
			expect.equal(ThrowController.parseThrowStarted(broken), nil)
		end
		local nan: any = table.clone(good)
		nan.releaseAt = 0 / 0
		expect.equal(ThrowController.parseThrowStarted(nan), nil)
		expect.equal(ThrowController.parseThrowStarted("nope"), nil)
	end)

	t.test("ThrowImpact and UltimateEvent payloads are type-checked", function()
		local impact = { projId = 7, kind = "geometry", position = Vector3.zero, normal = Vector3.yAxis }
		expect.equal(ThrowController.parseImpact(impact), impact)
		local badNormal: any = table.clone(impact)
		badNormal.normal = "up"
		expect.equal(ThrowController.parseImpact(badNormal), nil)
		local badKnock: any = table.clone(impact)
		badKnock.knockbackDir = 3
		expect.equal(ThrowController.parseImpact(badKnock), nil)
		expect.equal(ThrowController.parseImpact({ projId = 7, kind = "player" }), nil)

		local event = {
			phase = "telegraph",
			casterId = 42,
			origin = Vector3.new(0, 4.5, -40),
			dir = Vector3.new(0, 0, 1),
			length = 80,
			radius = 4,
			telegraphEndsAt = 100.9,
			speed = 260,
		}
		expect.equal(ThrowController.parseUltimateEvent(event), event)
		local badLength: any = table.clone(event)
		badLength.length = "far"
		expect.equal(ThrowController.parseUltimateEvent(badLength), nil)
		expect.equal(ThrowController.parseUltimateEvent(nil), nil)
	end)

	-- Spec phase 5: the Epic ultimates' events carry their ultimateId and, at the release, their birds or drops.
	t.test("an Epic ultimate's event: ultimateId, shots, center and drops are type-checked", function()
		local release: any = {
			phase = "release",
			casterId = 42,
			ultimateId = "flock_volley",
			origin = Vector3.new(0, 4.8, -38),
			dir = Vector3.new(0, 0, 1),
			length = 90,
			radius = 0.9,
			telegraphEndsAt = 100.35,
			speed = 75,
			shots = {
				{ projId = 7, origin = Vector3.zero, dir = Vector3.zAxis, length = 90, releaseAt = 100.35 },
				{ projId = 8, origin = Vector3.zero, dir = Vector3.zAxis, length = 88, releaseAt = 100.4 },
			},
		}
		expect.equal(ThrowController.parseUltimateEvent(release), release)
		local rain: any = table.clone(release)
		rain.ultimateId = "rain_check"
		rain.shots = nil
		rain.center = Vector3.new(0, 0, 30)
		rain.drops = { { projId = 9, position = Vector3.new(1, 0, 30), shadowAt = 101.25, landAt = 102 } }
		expect.equal(ThrowController.parseUltimateEvent(rain), rain)
		local badId: any = table.clone(release)
		badId.ultimateId = 5
		expect.equal(ThrowController.parseUltimateEvent(badId), nil)
		local badShot: any = table.clone(release)
		badShot.shots = { { projId = "x", origin = Vector3.zero, dir = Vector3.zAxis, length = 1, releaseAt = 1 } }
		expect.equal(ThrowController.parseUltimateEvent(badShot), nil)
		local badDrop: any = table.clone(rain)
		badDrop.drops = { { projId = 9, position = "here", shadowAt = 1, landAt = 2 } }
		expect.equal(ThrowController.parseUltimateEvent(badDrop), nil)
		local badCenter: any = table.clone(rain)
		badCenter.center = 3
		expect.equal(ThrowController.parseUltimateEvent(badCenter), nil)
		local tooMany: any = table.clone(release)
		tooMany.shots = table.create(40, release.shots[1])
		expect.equal(ThrowController.parseUltimateEvent(tooMany), nil)
	end)

	t.test(
		"eventAbility: the event's ultimateId; none is Dragon Rush (an event from before the Epic ultimates)",
		function()
			local id, ability = ThrowController.eventAbility({ ultimateId = "bubble_pop" } :: any)
			expect.equal(id, "bubble_pop")
			expect.equal(ability, Config.Abilities.bubble_pop)
			local oldId, oldAbility = ThrowController.eventAbility({} :: any)
			expect.equal(oldId, "dragon_rush")
			expect.equal(oldAbility, Config.Abilities.dragon_rush)
			expect.equal(ThrowController.eventAbility({ ultimateId = "laser_eyes" } :: any), nil)
		end
	)

	t.test("aimHits: a hit far past the opponent (the next arena slot) counts as a miss (bug 2026-10-15)", function()
		local margin = Config.Combat.Aim.farHitMarginStuds
		-- the opponent ~60 studs along the ray; the neighbour slot's near end rail at ~163, an off-lane dome at ~191
		expect.falsy(ThrowController.aimHits(163, 60, margin, 200))
		expect.falsy(ThrowController.aimHits(191, 60, margin, 200))
		-- the opponent, cover before him, and the floor or cover just behind him stay hits
		expect.truthy(ThrowController.aimHits(60, 60, margin, 200))
		expect.truthy(ThrowController.aimHits(25, 60, margin, 200))
		expect.truthy(ThrowController.aimHits(60 + margin, 60, margin, 200))
		-- no hit is never a hit; nothing to anchor on (missAt = the cap) keeps every hit as before
		expect.falsy(ThrowController.aimHits(nil, 60, margin, 200))
		expect.truthy(ThrowController.aimHits(190, 200, margin, 200))
	end)

	t.test("an aim ray into open sky stops at the opponent's distance, not 200 studs (no lob to the moon)", function()
		-- Part 4 user test: camera 12 studs behind pad A, the opponent on pad B 88 studs away, the crosshair a little
		-- above the opponent (sky). The old 200-stud point gave a ~34° lob landing far past the court.
		local camera = Vector3.new(320, 7, -356)
		local up = Vector3.new(0, 0.1, 1).Unit
		local opponent = Vector3.new(320, 3, -256)
		local reach = ThrowController.missReach(camera, up, { opponent }, 200)
		expect.near(reach, 100 / Vector3.new(up.X, 0, up.Z).Magnitude, 1e-3) -- Vector3 is float32 in Roblox
		local point = camera + up * reach
		expect.near(point.Z, -256, 1e-3)
		local def = { speed = 95, gravity = 35 } -- the starter's throw (Catalog kitty_bread)
		local origin = Vector3.new(320, 4.5, -343)
		local pitch = ProjectileMath.pitchDeg(ProjectileMath.solveLaunchDir(origin, point, def.speed, def.gravity))
		local oldPitch =
			ProjectileMath.pitchDeg(ProjectileMath.solveLaunchDir(origin, camera + up * 200, def.speed, def.gravity))
		expect.truthy(pitch < 20)
		expect.truthy(oldPitch > pitch + 10)
		-- nothing to anchor on, an anchor behind, or a (nearly) vertical ray: the configured reach
		expect.equal(ThrowController.missReach(camera, up, {}, 200), 200)
		expect.equal(ThrowController.missReach(camera, up, { Vector3.new(320, 3, -400) }, 200), 200)
		expect.equal(ThrowController.missReach(camera, Vector3.new(0, 1, 0.01), { opponent }, 200), 200)
		-- never beyond the cap; practice uses the farthest target
		expect.equal(ThrowController.missReach(camera, up, { Vector3.new(320, 3, 300) }, 200), 200)
		local farthest = ThrowController.missReach(camera, up, { Vector3.new(320, 3, -330), opponent }, 200)
		expect.near(farthest, reach, 1e-6)
	end)

	t.test("a throw into open sky leaves along the crosshair, inside the pitch band (bug report 2026-10-11)", function()
		-- The crosshair 25° above the horizon toward the opponent, nothing hit: the arc solved to the point in the air
		-- at the opponent's distance climbed far steeper than the crosshair ("it goes all the way up"); the throw now
		-- leaves along the crosshair itself.
		local camera = Vector3.new(320, 7, -356)
		local up25 = Vector3.new(0, math.sin(math.rad(25)), math.cos(math.rad(25)))
		local forward = Vector3.new(0, 0, 1)
		local dir = ThrowController.limitDirection(up25, forward, false)
		expect.near(ProjectileMath.pitchDeg(dir), 25, 1e-3)
		expectVectorNear(dir, up25)
		local reach = ThrowController.missReach(camera, up25, { Vector3.new(320, 3, -256) }, 200)
		local origin = Vector3.new(320, 4.5, -343)
		local solved = ProjectileMath.solveLaunchDir(origin, camera + up25 * reach, 95, 35) -- kitty_bread's throw
		expect.truthy(ProjectileMath.pitchDeg(solved) > 35) -- the old way: well above the crosshair
		-- Straight up is held to the top of the band; practice keeps the range cone.
		local steep = ThrowController.limitDirection(Vector3.new(0, 1, 0.05).Unit, forward, false)
		expect.near(ProjectileMath.pitchDeg(steep), combat.Throw.pitchMaxDeg, 1e-3)
		local PracticeTargets = t.requireShared("Practice/PracticeTargets")
		local behind = -PracticeTargets.FORWARD + Vector3.new(0, 0.2, 0)
		expect.truthy(PracticeTargets.inCone(ThrowController.limitDirection(behind.Unit, forward, true)))
	end)

	-- Sounds (§18.4.5, §18.6) -------------------------------------------------------------------------------------------

	-- True when `key` is a sound slot of AssetTable (asked by key; silent while its id is nil).
	local function isSoundKey(key: string?): boolean
		if key == nil then
			return false
		end
		local AssetTable = t.requireShared("AssetTable")
		for _, slot in AssetTable.all() do
			if slot.kind == "sound" and slot.key == key then
				return true
			end
		end
		return false
	end

	t.test("the own throw-ready pop asks for sfx.pop; other players' pop-ins stay silent", function()
		local own = ThrowController.popInSound(true)
		expect.equal(own, "sfx.pop")
		expect.truthy(isSoundKey(own))
		expect.equal(ThrowController.popInSound(false), nil)
	end)

	-- First person (spec 2026-10-10 §3.5, §3.6) --------------------------------------------------------------------

	t.test("the windup hold starts from the depth at the press; with yPress = 1 it is exactly today's", function()
		local antC = throwAnim.anticipationC
		for i = 0, 20 do
			local s = i / 20
			local today = 1 + (antC - 1) * s
			local c, cocked = ThrowController.windupHold(s, 1)
			expect.equal(c, today)
			expect.equal(c, (ThrowController.windupHold(s)))
			expect.equal(cocked, s >= 1)
			-- From a press at depth 0.7: 0.7 at the start, 0.90 once cocked, the straight blend between.
			local from = ThrowController.windupHold(s, 0.7)
			expect.near(from, today + (0.7 - 1) * (1 - s), 1e-12)
		end
		expect.near((ThrowController.windupHold(0, 0.7)), 0.7, 1e-12)
		expect.near((ThrowController.windupHold(1, 0.7)), antC, 1e-12)
		expect.near((ThrowController.windupHold(0.5, 0 / 0)), 1 + (antC - 1) / 2, 1e-12) -- NaN depth: from rest
	end)

	t.test("a throw started mid-squeeze never makes the shown S jump more than 0.02 between steps", function()
		local SquishRig = t.requireClient("Anim/SquishRig")
		local Blueprints = t.requireShared("Art/SquishyBlueprints")
		local STEP = 0.001
		for _, id in { "kitty_bread", "mochi_fox", "strawberry_frog" } do
			for _, at in { 0, 0.03, 0.1, 0.2, 0.3, 0.36, 0.45, 0.6, 1.5 } do
				local rig = SquishRig.new(Blueprints[id].motion, { axis = "Y", seed = 1, blink = false })
				local out = SquishRig.newOut()
				rig:tap()
				for _ = 1, math.floor(at / STEP + 0.5) do
					rig:step(STEP, out)
				end
				rig:step(STEP, out)
				local last = out.S
				-- The throw press: the overlay's prepare reads the depth, then holds the rig every frame.
				local yPress = rig:squeezeY()
				local w = ThrowController.newWindup(W, math.huge, false)
				local cocked = false
				for _ = 1, 300 do
					local sample = ThrowController.stepWindup(w, STEP, 0) :: any
					cocked = ThrowController.windupRigHold(rig, sample.squash, cocked, yPress)
					rig:step(STEP, out)
					local d = out.S - last
					local jump = math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z))
					if jump > 0.02 then
						error(`{id} pressed at {at} s: the shown S jumped {jump}`)
					end
					last = out.S
				end
				expect.truthy(cocked)
				-- Cocked at 0.90 whatever the start (the shown S.Y also carries any feel jiggle still running).
				expect.near(rig:squeezeY(), throwAnim.anticipationC, 1e-6)
			end
		end
	end)

	-- First person (spec 2026-10-11 §3.5; design: fp.js:430-443, toys.js:446-455): the design's throw does not squash
	-- the toy or show its squish face, so a rig the overlay mirrors gets no windup hold and goes on with its own squeeze.
	t.test("a mirrored rig gets no windup hold or squish face; one already held is let go", function()
		local SquishRig = t.requireClient("Anim/SquishRig")
		local Blueprints = t.requireShared("Art/SquishyBlueprints")
		local function newRig(): any
			return SquishRig.new(Blueprints.kitty_bread.motion, { axis = "X", seed = 1, blink = false })
		end
		-- Mid-squeeze, every windup frame mirrored: the rig shows exactly what a rig with no throw shows.
		local rig, twin = newRig(), newRig()
		local out, twinOut = SquishRig.newOut(), SquishRig.newOut()
		rig:tap()
		twin:tap()
		local cocked = false
		for i = 1, 40 do
			cocked = ThrowController.windupRigHold(rig, math.min(1, i / 10), cocked, nil, true)
			expect.falsy(cocked)
			rig:step(1 / 60, out)
			twin:step(1 / 60, twinOut)
			expect.truthy((out.S - twinOut.S).Magnitude < 1e-9)
			expect.equal(out.face, twinOut.face)
		end
		-- Held and cocked in third person, then mirrored: the hold and the squish face go at once.
		local held = newRig()
		local heldOut = SquishRig.newOut()
		cocked = ThrowController.windupRigHold(held, 1, false)
		held:step(1 / 60, heldOut)
		expect.truthy(cocked)
		expect.equal(heldOut.face, "squish")
		cocked = ThrowController.windupRigHold(held, 1, cocked, nil, true)
		expect.falsy(cocked)
		for _ = 1, 90 do
			ThrowController.windupRigHold(held, 1, cocked, nil, true)
			held:step(1 / 60, heldOut)
		end
		expect.equal(heldOut.face, "normal")
		expect.near(held:squeezeY(), 1, 1e-3)
	end)

	t.test("localWindup() and localUlt() return plain values read from the local records", function()
		-- Edit mode: no local player, nothing running.
		local tau, windup, releaseAt, releaseStart, cancelled = ThrowController.localWindup()
		expect.deepEqual({ tau, windup, releaseAt, releaseStart }, {})
		expect.equal(cancelled, false)
		local phase, endsAt, ultStart = ThrowController.localUlt()
		expect.deepEqual({ phase, endsAt, ultStart }, {})
		-- One record type for duel and practice throws (one local windup path).
		local w = ThrowController.newWindup(W, 10, false)
		ThrowController.stepWindup(w, 0.05, 0)
		w.releaseAt = 0.2
		local a, b, c, d, e = ThrowController.windupValues(w)
		expect.deepEqual({ a, b, c, d, e }, { w.tau, W, 0.2, nil, false })
		ThrowController.stepWindup(w, 0.2, 0.25) -- past releaseAt: the release started
		local _, _, _, started = ThrowController.windupValues(w)
		expect.equal(started, 0.2)
		local rejected = ThrowController.newWindup(W, 10, false)
		ThrowController.cancelWindup(rejected)
		local _, _, _, _, wasCancelled = ThrowController.windupValues(rejected)
		expect.equal(wasCancelled, true)
		local none: { any } = { ThrowController.windupValues(nil) }
		expect.deepEqual(none, { nil, nil, nil, nil, false } :: { any })
		local ult: any = { phase = "telegraph", telegraphEndsAt = 5, releaseStart = nil, ultimateId = "rain_check" }
		local p, ends, start, id = ThrowController.ultValues(ult)
		expect.deepEqual({ p, ends, start } :: { any }, { "telegraph", 5 } :: { any })
		expect.equal(id, "rain_check") -- spec phase 5: the first-person hand times its wind-up by it
		expect.deepEqual({ ThrowController.ultValues(nil) }, {})
	end)

	t.test("a rejection of the own pending throw asks for ui.error; a stale one stays silent", function()
		local nope = ThrowController.rejectSound(12, 12)
		expect.equal(nope, "ui.error")
		expect.truthy(isSoundKey(nope))
		expect.equal(ThrowController.rejectSound(12, 13), nil) -- an answer to an older request
		expect.equal(ThrowController.rejectSound(12, nil), nil) -- nothing pending (it timed out)
		-- The "nope" never spams: its cooldown is 250 ms.
		expect.equal(Config.Audio.cooldownMs.error, 250)
	end)

	t.test("power-ups review fix: a match throw waits while the server's projectile cap is reached", function()
		local max = Config.Duel.Rules.MaxActiveProjectilesPerPlayer
		expect.equal(ThrowController.projectileCapped("match", max - 1, max), false)
		expect.equal(ThrowController.projectileCapped("match", max, max), true) -- the server would say throw.tooMany
		expect.equal(ThrowController.projectileCapped("match", max + 1, max), true)
		-- Duels and practice keep the server's answer (unchanged).
		expect.equal(ThrowController.projectileCapped("duel", max, max), false)
		expect.equal(ThrowController.projectileCapped("practice", max, max), false)
		-- Edit mode: no own throw in the air, and outside a match it is never capped.
		expect.equal(ThrowController.atThrowCap("match"), false)
		expect.equal(ThrowController.atThrowCap("duel"), false)
	end)

	t.test("power-ups integration: a match's rapid throw multiplier is the server's (the shortest cooldown)", function()
		-- MatchService.throwCooldownMultiplier's steps, with the clamp passed in (no cached Config).
		local clamp = { Min = 0.6, Max = 2.0 }
		local function cooldownOf(multiplier: number, cooldown: number?): number
			local seconds = if cooldown then cooldown else clamp.Min
			return math.clamp(seconds, clamp.Min, clamp.Max)
				* ThrowController.rapidCooldownMultiplier(multiplier, cooldown, clamp)
		end
		expect.near(ThrowController.rapidCooldownMultiplier(0, 1.5, clamp), 0.6 / 1.5, 1e-12)
		expect.near(cooldownOf(0, 1.5), clamp.Min, 1e-9) -- ThrowRules: clamp(cooldown) × multiplier = Min
		expect.near(cooldownOf(0, 5), clamp.Min, 1e-9) -- above Max: clamped first, as ThrowRules
		expect.near(cooldownOf(0, 0.3), clamp.Min, 1e-9) -- below Min: Min
		expect.near(cooldownOf(0, nil), clamp.Min, 1e-9) -- no catalog cooldown: Min
		expect.near(ThrowController.rapidCooldownMultiplier(0.8, 1.5, clamp), 0.8, 1e-12) -- 0.8 × 1.5 s > Min: kept
		expect.equal(ThrowController.rapidCooldownMultiplier(1, 1.5, clamp), 1) -- no rapid throw
		expect.equal(ThrowController.rapidCooldownMultiplier(1.2, 1.5, clamp), 1.2)
	end)
end
