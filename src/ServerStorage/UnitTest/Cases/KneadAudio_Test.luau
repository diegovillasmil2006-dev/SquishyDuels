--!strict
-- KneadAudio_Test: unit tests for StarterPlayerScripts.Client.Controllers.KneadAudio, the wax crunch of the knead screen
-- (spec phase2-squeeze §1.22, §3.9, §3.10). Server only (ServerStorage.UnitTest). The pure scheduling with FakeRng and
-- the wiring with a recording stand-in for SoundController. Contract (design: squish.js:829-905; the sheet layout of
-- scratchpad work/sounds-out/manifest.json, Config.Audio.wax):
--   * a crack plays one burst region of the feel's sheet: the nearest baked E (log steps) and intact, a random variant
--     (slot ((e - 1)·3 + (i - 1))·3 + v of 0.12 s), × 10^(7·(E - baked E) / 20) × the intact share ratio, speed
--     U(0.94, 1.06);
--   * grains sit at 6.48 + i·0.05, taps at 8.88 + i·0.1;
--   * a release: 1 (finger) or 2 (palms, thumbs) ticks + 1 with chance 0.5, over 10-70 ms, gain 0.12·(0.5 + 0.5·amt);
--     settling: round(U(3, 6)·(0.5 + 0.5·amt)) ticks from 0.12 s over min(1.6, 0.8·rise), gain 0.08·amt; each tick
--     one of the first 36 grains at gain·feel gain·U(0.3, 1)·(1 - 0.6·u) / the sheet's 0.5;
--   * a press: a finger tap at 0.3 / 0.42 of the sheet's tap, speed √p·U(0.95, 1.1); palms and thumbs two taps 10-35
--     ms apart (0.42, 0.38) and the thump at speed p;
--   * the beds follow the design's formulas, eased with their time constants, and go quiet when the body rests;
--   * every play is in the Wax group at the file's level (10^(-normGainDb / 20)), the loops × the design's bus and
--     master gains; destroy stops the beds and nothing plays after it.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local KneadAudio = t.requireClient("Controllers/KneadAudio")
	local Config = t.requireShared("Config")
	local FakeRng = t.requireFake("FakeRng")
	local expect = t.expect
	local WAX = Config.Audio.wax

	local function level(db: number): number
		return 10 ^ (-db / 20)
	end

	-- A recording SoundController stand-in: every play and every loop with its volume.
	local function recorder(): any
		local log = { plays = {}, loops = {} }
		log.player = {
			play = function(key: string, options: any): boolean
				table.insert(log.plays, { key = key, options = options })
				return true
			end,
			playLoop = function(key: string, options: any): any
				local loop = { key = key, volume = options.volume or 0, options = options, stopped = false }
				function loop.setVolume(_self: any, volume: number)
					loop.volume = volume
				end
				function loop.stop(_self: any)
					loop.stopped = true
				end
				table.insert(log.loops, loop)
				return loop
			end,
		}
		return log
	end

	t.test("a crack: the nearest baked burst, its slot, the energy and intact corrections", function()
		-- E 1.1 is nearest 1.0 in log steps (not 1.4); intact 0.7 is nearest 0.6. Variant roll 0.5 -> 1; speed roll 0.5.
		local shot = KneadAudio.burst(1.1, 0.7, FakeRng.new({ 0.5, 0.5 }))
		local slot = ((3 - 1) * 3 + (2 - 1)) * 3 + 1
		expect.near(shot.start, slot * WAX.burstSlot, 1e-9)
		expect.near(shot.length, WAX.burstSlot, 1e-9)
		local share = function(i: number): number
			return WAX.intactBase + (1 - WAX.intactBase) * i
		end
		expect.near(shot.volume, 10 ^ (WAX.energyDb * 0.1 / 20) * share(0.7) / share(0.6), 1e-9)
		expect.near(shot.speed, (WAX.burstSpeedMin + WAX.burstSpeedMax) / 2, 1e-9)
		-- Past the ends: the outer bands, corrected (E 3 -> 2.8, E 0.2 -> 0.4).
		local high = KneadAudio.burst(3, 1, FakeRng.new({ 0, 0 }))
		expect.near(high.start, ((6 - 1) * 3 + 0) * 3 * WAX.burstSlot, 1e-9)
		expect.near(high.volume, 10 ^ (WAX.energyDb * 0.2 / 20), 1e-9)
		local low = KneadAudio.burst(0.2, 0.25, FakeRng.new({ 0.99, 0.99 }))
		expect.near(low.start, (2 * 3 + 2) * WAX.burstSlot, 1e-9) -- E band 1, intact band 3, variant 3
		expect.truthy(low.volume < 1)
	end)

	t.test("grains and taps sit where the manifest says", function()
		local start, length = KneadAudio.grain(0)
		expect.near(start, 6.48, 1e-9)
		expect.near(length, 0.05, 1e-9)
		start = KneadAudio.grain(47)
		expect.near(start, 6.48 + 47 * 0.05, 1e-9)
		start, length = KneadAudio.tap(4)
		expect.near(start, 9.28, 1e-9)
		expect.near(length, 0.1, 1e-9)
	end)

	t.test("a release and the settling ticks: counts, spans, gains and the darker grains", function()
		-- A finger: 1 tick + 1 more (roll 0.4 < 0.5). Per tick: u, grain, gain, speed.
		local shots = KneadAudio.release("finger", 1, 1, FakeRng.new({ 0.4, 1 - 1e-9, 0.99, 0.5, 0.5, 0, 0, 0, 0 }))
		expect.equal(#shots, 2)
		local first = shots[1]
		expect.near(first.delay, WAX.releaseDelay + (1 - 1e-9) ^ WAX.tickPower * WAX.releaseSpan, 1e-6)
		local grainStart = KneadAudio.grain(35)
		expect.near(first.start, grainStart, 1e-9) -- the darkest third: grains 0-35
		local gain = WAX.releaseGain * (0.5 + 0.5 * 1) * (WAX.tickGainMin + (1 - WAX.tickGainMin) * 0.5)
		expect.near(first.volume, gain * (1 - WAX.tickFade * (1 - 1e-9)) / WAX.grainGain, 1e-6)
		local second = shots[2]
		expect.near(second.delay, WAX.releaseDelay, 1e-9)
		expect.near(second.speed, WAX.tickSpeedMin, 1e-9)
		-- Palms: 2 ticks, no extra (roll 0.6).
		local palms = KneadAudio.release("palm", 0.5, 1, FakeRng.new(3))
		expect.truthy(#palms == 2 or #palms == 3)
		-- Settling: round(U(3, 6)·(0.5 + 0.5·amt)); amt 1, roll 0.5 -> round(4.5) = 5 ticks over min(1.6, 0.8·1.9) s.
		local rolls = { 0.5 }
		for _ = 1, 5 * 4 do
			table.insert(rolls, 0.5)
		end
		local air = KneadAudio.air(1, 1.9, 1, FakeRng.new(rolls))
		expect.equal(#air, 5)
		for _, shot in air do
			expect.truthy(shot.delay >= WAX.airDelay and shot.delay <= WAX.airDelay + 1.52 + 1e-9)
		end
	end)

	t.test("presses: a finger tap; palms and thumbs two taps and the thump at speed p", function()
		local finger, fingerThump = KneadAudio.press("finger", 1.44, FakeRng.new({ 0.5, 0.5 }))
		expect.equal(#finger, 1)
		expect.equal(fingerThump, nil)
		expect.near(finger[1].volume, WAX.fingerTap / WAX.tapGain, 1e-9)
		expect.near(finger[1].speed, 1.2 * (WAX.fingerSpeedMin + WAX.fingerSpeedMax) / 2, 1e-9)
		local tapStart = KneadAudio.tap(2)
		expect.near(finger[1].start, tapStart, 1e-9)
		local palm, thump = KneadAudio.press("palm", 0.81, FakeRng.new({ 0, 0.5, 0.99, 0.5, 0.5 }))
		expect.equal(#palm, 2)
		expect.near(thump :: number, 0.81, 1e-9)
		expect.near(palm[1].volume, WAX.pressTapA / WAX.tapGain, 1e-9)
		expect.near(palm[2].volume, WAX.pressTapB / WAX.tapGain, 1e-9)
		expect.near(palm[2].delay - palm[1].delay, (WAX.pressGapMin + WAX.pressGapMax) / 2, 1e-9)
		expect.near(palm[1].speed, 0.9 * (WAX.pressSpeedAMin + WAX.pressSpeedAMax) / 2, 1e-9)
	end)

	t.test("the beds: the design's haze and body formulas and their easing", function()
		local haze, body = KneadAudio.beds(0.95, 0.5, 0.8, 0.6)
		expect.near(haze, 0.95 * WAX.hazeGain * 0.5 * (WAX.hazeBase + (1 - WAX.hazeBase) * 0.6), 1e-12)
		expect.near(
			body,
			0.95 * WAX.bodyGain * math.min(1, 0.9 * 0.5 + 0.22 * 0.8) * (WAX.bodyBase + WAX.bodyWorn * 0.4),
			1e-12
		)
		local _, saturated = KneadAudio.beds(1, 1, 1, 1)
		expect.near(saturated, WAX.bodyGain * WAX.bodyBase, 1e-12)
		expect.near(KneadAudio.ease(0, 1, 0.05, 0.05), 1 - math.exp(-1), 1e-12)
		expect.equal(KneadAudio.ease(0.3, 0.3, 0.05, 0.016), 0.3)
		expect.equal(KneadAudio.ease(0.5, 0, 0.05, 0), 0.5)
	end)

	t.test("wiring: the sheet in the Wax group at its level, the thumps, the beds, quiet and destroy", function()
		local log = recorder()
		local audio = KneadAudio.new("mochi", 1.2, { player = log.player, rng = FakeRng.new(11) })
		local sheetLevel = level(WAX.sheetLevelDb.mochi) * WAX.trim
		audio:crack(1, 1)
		local crack = log.plays[1]
		expect.equal(crack.key, "sfx.wax.mochi")
		expect.equal(crack.options.group, "Wax")
		expect.equal(typeof(crack.options.region), "NumberRange")
		expect.near(crack.options.volume, sheetLevel, 1e-6)
		-- A palm press: two taps now (their gap is under a frame? no: up to 35 ms) and the thump at speed p.
		audio:event({ kind = "press", brush = "palm", pan = 0 })
		local thump: any = nil
		for _, play in log.plays do
			if play.key == "sfx.wax.thump" then
				thump = play
			end
		end
		assert(thump ~= nil, "no thump")
		expect.near(thump.options.pitch, 1.2, 1e-9)
		expect.near(thump.options.volume, level(WAX.thumpLevelDb) * WAX.trim, 1e-9)
		-- A snap: the burst now, its echo later, and the snap thump at 0.5 + a.
		audio:event({ kind = "snap", amount = 0.5, pan = 0, slipped = false })
		local snapThump: any = nil
		for _, play in log.plays do
			if play.key == "sfx.wax.snapThump" then
				snapThump = play
			end
		end
		assert(snapThump ~= nil, "no snap thump")
		expect.near(snapThump.options.volume, level(WAX.snapThumpLevelDb) * WAX.trim * 1.0, 1e-9)
		-- Re-wax: the sparkle at its level.
		audio:rewax()
		expect.equal(log.plays[#log.plays].key, "sfx.wax.rewax")
		-- The beds start with the first active frame and ease toward the design's values.
		audio:frame(1 / 60, true, 1, 1, 1)
		expect.equal(#log.loops, 2)
		local haze = log.loops[1].key == "sfx.wax.haze.mochi" and log.loops[1] or log.loops[2]
		local loopScale = level(WAX.loopLevelDb) * WAX.busGain * WAX.masterGain * WAX.trim
		for _ = 1, 120 do
			audio:frame(1 / 60, true, 1, 1, 1)
		end
		local hazeTarget = KneadAudio.beds(WAX.gain.mochi, 1, 1, 1)
		expect.near(haze.volume, hazeTarget * loopScale, 1e-4)
		-- At rest the beds go quiet.
		for _ = 1, 120 do
			audio:frame(1 / 60, false, 0, 0, 1)
		end
		expect.near(haze.volume, 0, 1e-4)
		local before = #log.plays
		audio:destroy()
		expect.truthy(log.loops[1].stopped and log.loops[2].stopped)
		audio:crack(2, 1)
		audio:event({ kind = "release", brush = "finger", amount = 1, pan = 0 })
		expect.equal(#log.plays, before)
	end)
end
