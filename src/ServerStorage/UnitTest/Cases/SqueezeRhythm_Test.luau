--!strict
-- SqueezeRhythm_Test: unit tests for StarterPlayerScripts.Client.Anim.SqueezeRhythm (pure). Server only
-- (ServerStorage.UnitTest). Edit mode: no instances, the clock is passed in.
-- Contract (DESIGN §18.5.1 A2, §18.11, Config.Anim.squeeze.rhythm):
--   * the streak continues while own squeezes are <= rhythm.streakSeconds (2.1 s, its own value since every click
--     pays: it no longer depends on Config.Squeeze.cycleSeconds) apart and starts again above; fast clicking (12 a
--     second, the anti-autoclicker cap) keeps one streak, its pitch pattern and a big pop every 8th;
--   * the pitch follows pitchPattern {1, 1.03, 1.06, 1.03} from the streak's first squeeze, repeating; the random
--     variance is cut to pitchVariance once the streak is >= 2 (the first squeeze keeps the key's own variance);
--   * every popEvery-th (8th) squeeze is a big pop (bigPopSparkles + sfx.pop) that replaces the release pop
--     (popSparkles);
--   * any rejection but squeeze.tooFast resets the streak.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local SqueezeRhythm = t.requireClient("Anim/SqueezeRhythm")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local R = Config.Anim.squeeze.rhythm
	local HOLD = Config.Grip.Hold.repeatSeconds -- the hold-to-squeeze rhythm
	local CLICK = 1 / 12 -- the fastest clicking the anti-autoclicker cap lets through
	local T0 = 1000

	t.test("DESIGN values: 2.1 s streak gap, the pitch pattern, a big pop every 8th", function()
		expect.equal(R.streakSeconds, 2.1)
		expect.equal(R.gapSeconds, nil) -- the old cycle-relative gap is gone
		expect.deepEqual(R.pitchPattern, { 1, 1.03, 1.06, 1.03 })
		expect.equal(R.popEvery, 8)
		expect.equal(R.popSparkles, 2)
		expect.equal(R.bigPopSparkles, 4)
		expect.equal(R.pitchVariance, 0.01)
	end)

	t.test("the streak continues at gaps <= 2.1 s and starts again above", function()
		expect.truthy(SqueezeRhythm.continues(CLICK))
		expect.truthy(SqueezeRhythm.continues(HOLD))
		expect.truthy(SqueezeRhythm.continues(1.5))
		expect.truthy(SqueezeRhythm.continues(R.streakSeconds))
		expect.falsy(SqueezeRhythm.continues(R.streakSeconds + 0.01))
		expect.falsy(SqueezeRhythm.continues(-0.1))

		local state = SqueezeRhythm.new()
		expect.equal(SqueezeRhythm.beat(state, T0).streak, 1)
		expect.equal(SqueezeRhythm.beat(state, T0 + 1.5).streak, 2)
		expect.equal(SqueezeRhythm.beat(state, T0 + 1.5 + 2.1).streak, 3)
		-- A gap of 2.2 s starts a new streak.
		expect.equal(SqueezeRhythm.beat(state, T0 + 1.5 + 2.1 + 2.2).streak, 1)
	end)

	t.test("the pitch follows the pattern and the variance is cut from the 2nd squeeze", function()
		local state = SqueezeRhythm.new()
		local pitches, variances = {}, {}
		for i = 1, 9 do
			local beat = SqueezeRhythm.beat(state, T0 + (i - 1) * HOLD)
			table.insert(pitches, beat.pitch)
			variances[i] = beat.variance
		end
		expect.deepEqual(pitches, { 1, 1.03, 1.06, 1.03, 1, 1.03, 1.06, 1.03, 1 })
		expect.equal(variances[1], nil) -- the first squeeze keeps the key's own ±4%
		for i = 2, 9 do
			expect.equal(variances[i], R.pitchVariance)
		end
		expect.equal(SqueezeRhythm.pitchAt(4), 1.03)
		expect.equal(SqueezeRhythm.pitchAt(6), 1.03)
	end)

	t.test("a big pop every 8th squeeze replaces the release pop", function()
		local state = SqueezeRhythm.new()
		for i = 1, 24 do
			local beat = SqueezeRhythm.beat(state, T0 + (i - 1) * HOLD)
			local big = i % 8 == 0
			expect.equal(beat.bigPop, big)
			expect.equal(beat.sparkles, if big then R.bigPopSparkles else R.popSparkles)
		end
		-- Never more than the larger of the two (the squeeze particle budget, §18.9).
		expect.truthy(math.max(R.popSparkles, R.bigPopSparkles) == R.bigPopSparkles)
	end)

	t.test("a rejection other than squeeze.tooFast resets the streak; tooFast does not", function()
		local state = SqueezeRhythm.new()
		for i = 1, 5 do
			SqueezeRhythm.beat(state, T0 + (i - 1) * HOLD)
		end
		expect.falsy(SqueezeRhythm.reject(state, "squeeze.tooFast"))
		expect.equal(SqueezeRhythm.beat(state, T0 + 5 * HOLD).streak, 6)
		expect.truthy(SqueezeRhythm.reject(state, "squeeze.inDuel"))
		expect.equal(state.streak, 0)
		local next = SqueezeRhythm.beat(state, T0 + 6 * HOLD)
		expect.equal(next.streak, 1)
		expect.equal(next.pitch, 1)
		expect.equal(next.variance, nil)
		-- A rejection without a reason (malformed) also resets.
		SqueezeRhythm.beat(state, T0 + 7 * HOLD)
		expect.truthy(SqueezeRhythm.reject(state, nil))
		expect.equal(state.streak, 0)
	end)

	t.test("fast clicking (12 a second for 3 s) keeps one streak, the pitch pattern and a big pop every 8th", function()
		local state = SqueezeRhythm.new()
		local bigPops = 0
		for i = 1, 36 do
			local beat = SqueezeRhythm.beat(state, T0 + (i - 1) * CLICK)
			expect.equal(beat.streak, i)
			expect.equal(beat.pitch, R.pitchPattern[(i - 1) % #R.pitchPattern + 1])
			expect.equal(beat.bigPop, i % R.popEvery == 0)
			if beat.bigPop then
				bigPops += 1
			end
		end
		expect.equal(bigPops, 4)
		-- Mixed clicking and holding stays one streak; a pause longer than 2.1 s starts a new one.
		expect.equal(SqueezeRhythm.beat(state, T0 + 35 * CLICK + HOLD).streak, 37)
		expect.equal(SqueezeRhythm.beat(state, T0 + 35 * CLICK + HOLD + R.streakSeconds + 0.1).streak, 1)
	end)
end
