--!strict
-- DoubleJumpController_Test: unit tests for StarterPlayerScripts.Client.Controllers.DoubleJumpController's pure helpers
-- (2026-10-15 double jump). Server only (ServerStorage.UnitTest). Edit mode: init() is never called; no instances.
-- Contract:
--   * the gate: only the Duel context in Active or SuddenDeath, alive, at least minAirSeconds in the air, fewer than
--     maxPerAir since the landing, able to jump, not rooted, casting or dashing;
--   * a JumpRequest is a press only after pressGapSeconds without one (a held key repeats it);
--   * the launch speed is sqrt(2·g·h);
--   * the flip: no turn and no tuck at 0, a full spinDegrees turn about the key's axis by spinSeconds, weight 0 at
--     `seconds`; ReducedMotion tucks without turning; F / B turn about X, L / R about Z, in opposite senses;
--   * a DoubleJumped payload is used only with every field of its type and a key of F / B / L / R.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local DoubleJump = t.requireClient("Controllers/DoubleJumpController")
	local Config = t.requireShared("Config")
	local RULES = Config.Duel.Rules.DoubleJump
	local ANIM = Config.Anim.doubleJump

	local function facts(overrides: { [string]: any }?): any
		local f: { [string]: any } = {
			inDuel = true,
			phase = "Active",
			alive = true,
			airborneFor = RULES.minAirSeconds + 0.05,
			used = 0,
			canJump = true,
			rooted = false,
			ultBusy = false,
			dashing = false,
		}
		for key, value in overrides or {} do
			f[key] = value
		end
		return f
	end

	t.test("the gate: a live duel, in the air long enough, once per air time, free to jump", function()
		expect.equal(DoubleJump.gate(facts()), nil)
		expect.equal(DoubleJump.gate(facts({ phase = "SuddenDeath" })), nil)
		expect.equal(DoubleJump.gate(facts({ inDuel = false })), "jump.context")
		expect.equal(DoubleJump.gate(facts({ phase = "Countdown" })), "jump.context")
		expect.equal(DoubleJump.gate(facts({ alive = false })), "jump.context")
		local grounded = facts()
		grounded.airborneFor = nil
		expect.equal(DoubleJump.gate(grounded), "jump.grounded")
		expect.equal(DoubleJump.gate(facts({ airborneFor = RULES.minAirSeconds / 2 })), "jump.grounded")
		expect.equal(DoubleJump.gate(facts({ used = RULES.maxPerAir })), "jump.used")
		for _, busy in { { canJump = false }, { rooted = true }, { ultBusy = true }, { dashing = true } } do
			expect.equal(DoubleJump.gate(facts(busy)), "jump.busy")
		end
	end)

	t.test("a held key is one press; a press needs pressGapSeconds of quiet", function()
		expect.truthy(DoubleJump.isFreshPress(10, -math.huge))
		expect.falsy(DoubleJump.isFreshPress(10, 10 - 1 / 60))
		expect.truthy(DoubleJump.isFreshPress(10, 10 - RULES.pressGapSeconds - 1e-6))
	end)

	t.test("the launch speed reaches the height under gravity", function()
		expect.near(DoubleJump.launchSpeed(196.2, 6), math.sqrt(2 * 196.2 * 6), 1e-9)
		expect.equal(DoubleJump.launchSpeed(0, 6), 0)
		expect.equal(DoubleJump.launchSpeed(196.2, -1), 0)
	end)

	t.test("the flip: starts untucked, turns once by spinSeconds, ends at weight 0", function()
		local start, w0 = DoubleJump.poseAt("F", 0)
		expect.equal(w0, 1)
		expect.near(start.Root.Magnitude, 0, 1e-9)
		expect.near(start.RightKnee.Magnitude, 0, 1e-9)
		local mid = DoubleJump.poseAt("F", (ANIM.tuckInSeconds + ANIM.tuckOutFromSeconds) / 2)
		expect.near(mid.RightKnee.X, ANIM.tuck.RightKnee.X, 1e-6)
		expect.truthy(mid.Root.X < 0 and mid.Root.X > -ANIM.spinDegrees)
		local done = DoubleJump.poseAt("F", ANIM.spinSeconds)
		expect.near(done.Root.X, -ANIM.spinDegrees, 1e-6)
		expect.near(done.RightKnee.Magnitude, 0, 1e-6)
		local _, wEnd = DoubleJump.poseAt("F", ANIM.seconds)
		expect.equal(wEnd, 0)
		local _, wFade = DoubleJump.poseAt("F", (ANIM.fadeFromSeconds + ANIM.seconds) / 2)
		expect.truthy(wFade > 0 and wFade < 1)
	end)

	t.test("the flip's axis per key, and no turn under ReducedMotion", function()
		local t1 = ANIM.spinSeconds / 2
		local f = DoubleJump.poseAt("F", t1)
		local b = DoubleJump.poseAt("B", t1)
		local l = DoubleJump.poseAt("L", t1)
		local r = DoubleJump.poseAt("R", t1)
		expect.near(f.Root.X, -b.Root.X, 1e-6)
		expect.truthy(f.Root.X < 0 and math.abs(f.Root.Z) < 1e-9)
		expect.near(l.Root.Z, -r.Root.Z, 1e-6)
		expect.truthy(l.Root.Z > 0 and math.abs(l.Root.X) < 1e-9)
		local reduced = DoubleJump.poseAt("F", t1, true)
		expect.near(reduced.Root.Magnitude, 0, 1e-9)
		expect.truthy(reduced.RightKnee.X < 0) -- it still tucks
		expect.equal(DoubleJump.spinAxis("?"), DoubleJump.spinAxis("F"))
	end)

	t.test("a DoubleJumped payload is used only when every field has its type", function()
		local good = { userId = 7, key = "L", at = Vector3.new(1, 2, 3), startAt = 100 }
		local parsed = DoubleJump.parseDoubleJumped(good)
		expect.truthy(parsed ~= nil)
		expect.equal(parsed and parsed.key, "L")
		expect.equal(DoubleJump.parseDoubleJumped(nil), nil)
		expect.equal(DoubleJump.parseDoubleJumped({ userId = 7, key = "Q", at = Vector3.zero, startAt = 1 }), nil)
		expect.equal(DoubleJump.parseDoubleJumped({ userId = 7, key = "F", at = "here", startAt = 1 }), nil)
		expect.equal(DoubleJump.parseDoubleJumped({ userId = 0 / 0, key = "F", at = Vector3.zero, startAt = 1 }), nil)
		expect.equal(
			DoubleJump.parseDoubleJumped({ userId = 7, key = "F", at = Vector3.new(math.huge, 0, 0), startAt = 1 }),
			nil
		)
	end)
end
