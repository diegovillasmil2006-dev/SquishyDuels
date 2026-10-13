--!strict
-- CapsuleFeel_Test: StarterPlayerScripts.Client.Anim.CapsuleFeel (the capsule feel's timing and curves, build plan
-- Phase 5). Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract (lobby bases spec 2026-10-11 §5.3; numbers from Config.UI.Capsule):
--   * squeeze(t, contact): the press comes down in pressDownMs (0 -> 1), holds pressHoldMs and rises in pressUpMs
--     (back to 0); the squishy keeps its height until the press reaches `contact`, squashes to squashHeight at the
--     full press, springs back to springHeight as the press is back up, then wobbles to rest; the wobble stays under
--     the 3 Hz flicker limit (§18.1 #4);
--   * width(height): squashWidth at squashHeight, 1 at rest, thinner when stretched;
--   * spring(t, depth): a home tap squishes tapSquish and springs back;
--   * upgrade(t, evolve): the squishy stretches upgradeStretch (evolveStretch) and turns upgradeTurns (evolveTurns) full
--     turns over spinMs, then rests; an evolve is the bigger burst;
--   * duration(kind): the motion is at rest from then on;
--   * brick(velocity, t): the confetti's flight under Config.Vfx.Confetti's gravity, fading over its last fadeSeconds;
--   * pop(t, reduced): the owner's "+N" rises popRiseStuds over popMs, fading over its last popFadeShare; under
--     ReducedMotion it never rises and only fades at its end.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local CapsuleFeel = t.requireClient("Anim/CapsuleFeel")
	local Config = t.requireShared("Config")
	local C = Config.UI.Capsule
	local CONFETTI = Config.Vfx.Confetti
	local DOWN = C.pressDownMs / 1000
	local HOLD = C.pressHoldMs / 1000
	local UP = C.pressUpMs / 1000

	t.test("the press comes down in 0.16 s, holds 0.14 s and rises in 0.32 s (spec §5.3)", function()
		expect.equal(DOWN, 0.16)
		expect.equal(HOLD, 0.14)
		expect.equal(UP, 0.32)
		expect.equal((CapsuleFeel.squeeze(0)), 0)
		expect.truthy((CapsuleFeel.squeeze(DOWN / 2)) > 0 and (CapsuleFeel.squeeze(DOWN / 2)) < 1)
		expect.near((CapsuleFeel.squeeze(DOWN)), 1, 1e-9)
		expect.near((CapsuleFeel.squeeze(DOWN + HOLD / 2)), 1, 1e-9)
		expect.near((CapsuleFeel.squeeze(DOWN + HOLD)), 1, 1e-9)
		local rising = CapsuleFeel.squeeze(DOWN + HOLD + UP / 2)
		expect.truthy(rising > 0 and rising < 1)
		expect.near((CapsuleFeel.squeeze(DOWN + HOLD + UP)), 0, 1e-9)
		expect.equal((CapsuleFeel.squeeze(5)), 0)
		expect.equal((CapsuleFeel.squeeze(-1)), 0)
		-- It only goes down, then only up.
		local last = 0
		for step = 1, 16 do
			local press = CapsuleFeel.squeeze(DOWN * step / 16)
			expect.truthy(press >= last)
			last = press
		end
		for step = 1, 32 do
			local press = CapsuleFeel.squeeze(DOWN + HOLD + UP * step / 32)
			expect.truthy(press <= last + 1e-12)
			last = press
		end
	end)

	t.test("the squishy squashes to 58% height and 125% width, springs back to 112% and wobbles to rest", function()
		local contact = 0.6 -- the press meets the squishy's top at 60% of its travel
		local _, before = CapsuleFeel.squeeze(DOWN * 0.5, contact) -- the press is still above the squishy
		expect.equal(before, 1)
		local _, full = CapsuleFeel.squeeze(DOWN, contact)
		expect.near(full, C.squashHeight, 1e-9)
		expect.near(CapsuleFeel.width(full), C.squashWidth, 1e-9)
		local _, held = CapsuleFeel.squeeze(DOWN + HOLD, contact)
		expect.near(held, C.squashHeight, 1e-9)
		-- The spring back peaks at springHeight as the press is fully up again.
		local _, peak = CapsuleFeel.squeeze(DOWN + HOLD + UP, contact)
		expect.near(peak, C.springHeight, 1e-6)
		expect.truthy(CapsuleFeel.width(peak) < 1) -- stretched: thinner
		for step = 1, 40 do
			local _, height = CapsuleFeel.squeeze(DOWN + HOLD + UP * step / 40, contact)
			expect.truthy(height <= C.springHeight + 1e-6)
		end
		-- At rest from duration("squeeze") on.
		local rest = CapsuleFeel.duration("squeeze")
		expect.truthy(rest > DOWN + HOLD + UP)
		local _, settled = CapsuleFeel.squeeze(rest, contact)
		expect.truthy(math.abs(settled - 1) < 0.01)
		expect.near(CapsuleFeel.width(1), 1, 1e-12)
		-- A press that never reaches the squishy never squashes it.
		local _, untouched = CapsuleFeel.squeeze(DOWN, 1)
		expect.equal(untouched, 1)
		local _, after = CapsuleFeel.squeeze(DOWN + HOLD + UP, 1)
		expect.equal(after, 1)
	end)

	t.test("the wobble stays under the 3 Hz flicker limit (§18.1 #4)", function()
		expect.truthy(CapsuleFeel.WOBBLE_HZ > 0 and CapsuleFeel.WOBBLE_HZ <= 3)
		-- Half a wobble is the press's rise: the peak comes as the press is back up.
		expect.near(1 / (2 * CapsuleFeel.WOBBLE_HZ), UP, 1e-9)
	end)

	t.test("a home tap gives a small 8% squish that springs back", function()
		expect.equal(C.tapSquish, 0.08)
		expect.near(CapsuleFeel.spring(0, C.tapSquish), 1 - C.tapSquish, 1e-12)
		for step = 0, 40 do
			local height = CapsuleFeel.spring(step / 40, C.tapSquish)
			expect.truthy(height >= 1 - C.tapSquish - 1e-12 and height <= 1 + C.tapSquish)
		end
		local rest = CapsuleFeel.duration("tap")
		expect.truthy(rest > 0)
		expect.truthy(math.abs(CapsuleFeel.spring(rest, C.tapSquish) - 1) < 0.01)
	end)

	t.test("an upgrade stretches and spins the squishy; an evolve is the bigger burst", function()
		local height, turn = CapsuleFeel.upgrade(0, false)
		expect.near(height, 1 + C.upgradeStretch, 1e-12)
		expect.equal(turn, 0)
		local spin = C.spinMs / 1000
		local _, half = CapsuleFeel.upgrade(spin / 2, false)
		expect.truthy(half > 0 and half < 2 * math.pi * C.upgradeTurns)
		local _, done = CapsuleFeel.upgrade(spin, false)
		expect.near(done, 2 * math.pi * C.upgradeTurns, 1e-9)
		local evolveHeight, evolveTurn = CapsuleFeel.upgrade(0, true)
		expect.near(evolveHeight, 1 + C.evolveStretch, 1e-12)
		expect.truthy(C.evolveStretch > C.upgradeStretch and C.evolveTurns > C.upgradeTurns)
		expect.equal(evolveTurn, 0)
		local _, evolveDone = CapsuleFeel.upgrade(spin, true)
		expect.near(evolveDone, 2 * math.pi * C.evolveTurns, 1e-9)
		for _, kind in { "upgrade", "evolve" } do
			local rest = CapsuleFeel.duration(kind)
			expect.truthy(rest >= spin)
			local restHeight, restTurn = CapsuleFeel.upgrade(rest, kind == "evolve")
			expect.truthy(math.abs(restHeight - 1) < 0.01)
			expect.near(math.cos(restTurn), 1, 1e-9) -- whole turns: facing front again
		end
		expect.equal(CapsuleFeel.duration("nothing"), 0)
	end)

	t.test("brick confetti flies up and out, falls under the confetti's gravity and fades at the end", function()
		local velocity = Vector3.new(3, 12, -2)
		local start, solid, over = CapsuleFeel.brick(velocity, 0)
		expect.equal(start, Vector3.zero)
		expect.equal(solid, 0)
		expect.equal(over, false)
		local t1 = 0.3
		local offset = CapsuleFeel.brick(velocity, t1)
		local FLOAT32 = 1e-5 -- Vector3 components are single precision
		expect.near(offset.X, 3 * t1, FLOAT32)
		expect.near(offset.Y, 12 * t1 - 0.5 * CONFETTI.gravity * t1 * t1, FLOAT32)
		expect.near(offset.Z, -2 * t1, FLOAT32)
		local life = CONFETTI.lifetime
		local _, fading = CapsuleFeel.brick(velocity, life - CONFETTI.fadeSeconds / 2)
		expect.near(fading, 0.5, 1e-9)
		local _, gone, ended = CapsuleFeel.brick(velocity, life)
		expect.equal(gone, 1)
		expect.equal(ended, true)
	end)

	t.test("the owner's pop rises and fades; under ReducedMotion it holds still and only fades", function()
		local seconds = C.popMs / 1000
		local rise, transparency, done = CapsuleFeel.pop(0, false)
		expect.equal(rise, 0)
		expect.equal(transparency, 0)
		expect.equal(done, false)
		local fadeFrom = seconds * (1 - C.popFadeShare)
		local midRise, midTransparency = CapsuleFeel.pop(fadeFrom, false)
		expect.truthy(midRise > 0 and midRise < C.popRiseStuds)
		expect.near(midTransparency, 0, 1e-9)
		local endRise, endTransparency, ended = CapsuleFeel.pop(seconds, false)
		expect.near(endRise, C.popRiseStuds, 1e-9)
		expect.equal(endTransparency, 1)
		expect.equal(ended, true)
		for step = 0, 10 do
			local reducedRise = CapsuleFeel.pop(seconds * step / 10, true)
			expect.equal(reducedRise, 0)
		end
		local _, reducedStart = CapsuleFeel.pop(0, true)
		expect.equal(reducedStart, 0)
		local _, reducedEnd, reducedDone = CapsuleFeel.pop(seconds, true)
		expect.equal(reducedEnd, 1)
		expect.equal(reducedDone, true)
	end)
end
