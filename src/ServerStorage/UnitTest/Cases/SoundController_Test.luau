--!strict
-- SoundController_Test: the pure mixing rules of StarterPlayerScripts.Client.Controllers.SoundController. Server only
-- (ServerStorage.UnitTest). Edit mode: init() is never called (no SoundGroups, no Sound instances), so every play
-- attempt that passes the rules ends as "noId".
-- Contract (DESIGN §11.9, §14, §18.6, §18.10 L1):
--   * groupVolume = maxGroupVolume × slider / 100 (× the duck product for Music): Music 0.24, SFX 0.70, UI 0.56,
--     Ambient 0.35 at the default settings; 0 at slider 0;
--   * per-key cooldowns: squeeze 90 ms, coin 60 ms but batched to <= 1 per 0.08 s, impact 50 ms, UI click 40 ms, and
--     the feel pass categories throw 60, wobble 80, pop 60, hover 60, hitConfirm 50, error 250; other players' sounds
--     (priority below 0) keep their own cooldown, apart from the local player's;
--   * a one-shot that never loads (Ended never fires) is dropped 5 s after its start; a loaded one 5 s + its length at
--     its speed + 0.5 s after its start;
--   * pitch variation: squeeze ±4%, impact ±6%, throw ±5%, wobble ±8%, pop ±6%, hitConfirm ±3%, other UI ±2% except
--     the fixed-pitch countdown, go, jingles and reveals, others none; a play's `variance` overrides it; the final
--     pitch (variation × the play's `pitch`) is clamped to [pitchMin, pitchMax];
--   * variants: pickVariant never repeats the last pick when there are two or more, and covers every choice;
--   * other players' sounds: squeezes within 50 studs and at most 3, throws within 60 studs and at most 3;
--   * ducking multiplies (box reveal 0.5, countdown 0.6, result 0.6, inspect 0.8, knockout 0.5 for 0.6 s); duel ducks
--     follow the phase;
--   * voice caps: SFX 10 and 3 per key (Config.Audio.perKeyCap overrides, sfx.jellyWobble 2), UI 4, Ambient 2,
--     Music 1 (2 in a crossfade); when full, the oldest non-looping voice of no higher priority is stolen, else the new
--     sound is dropped;
--   * Studio auditions only while Config.Debug.soundPicker; they never count as approved ids;
--   * recent(): the last recentLogSize attempts {key, t, result} (played, noId, cooldown, caps, distance);
--   * a sound slot without an id (PENDING) is silent and listed once for the startup warning;
--   * music job (2026-10-16): the music is Config.Audio.battleMusic.key (music.duel) while the duel or the match view is
--     in a battle phase (Positioning through Returning), else the zone's; Preparing, Cancelled and Void keep the zone's.
--     Review fix (2026-10-16): both keys are Music slots, silent until the owner picks their sounds in the Studio
--     sound picker (no id is asserted here).
-- Fake ids below are tiny integers built at run time; no real asset id appears here.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local SoundController = t.requireClient("Controllers/SoundController")
	local Config = t.requireShared("Config")
	local AssetTable = t.requireShared("AssetTable")
	local AUDIO = Config.Audio
	local defaults = Config.Data.DefaultSettings

	local caps = {
		SFX = AUDIO.VoiceCaps.SFX,
		SFXPerKey = AUDIO.VoiceCaps.SFXPerKey,
		UI = AUDIO.VoiceCaps.UI,
		Ambient = AUDIO.VoiceCaps.Ambient,
		Music = AUDIO.VoiceCaps.Music,
		MusicDuringCrossfade = AUDIO.VoiceCaps.MusicDuringCrossfade,
	}

	local function voice(group: string, key: string, startedAt: number, looped: boolean?, priority: number?)
		return { group = group, key = key, startedAt = startedAt, looped = looped == true, priority = priority or 0 }
	end

	-- The results of the attempts logged since `before` entries (recent() is oldest first and capped).
	local function resultsSince(before: { any }): { string }
		local after = SoundController.recent()
		local lastBefore = before[#before]
		local start = 1
		if lastBefore ~= nil then
			for index = #after, 1, -1 do
				local entry = after[index]
				if entry.t == lastBefore.t and entry.key == lastBefore.key and entry.result == lastBefore.result then
					start = index + 1
					break
				end
			end
		end
		local results = {}
		for index = start, #after do
			table.insert(results, `{after[index].key}={after[index].result}`)
		end
		return results
	end

	t.test("group volumes: max × slider / 100, ducks on Music only", function()
		expect.near(SoundController.groupVolume("Music", defaults), 0.24, 1e-9)
		expect.near(SoundController.groupVolume("SFX", defaults), 0.70, 1e-9)
		expect.near(SoundController.groupVolume("UI", defaults), 0.56, 1e-9)
		expect.near(SoundController.groupVolume("Ambient", defaults), 0.35, 1e-9)
		local silent = { music = 0, sfx = 0, cameraShake = true, showTips = true }
		for _, group in { "Music", "SFX", "UI", "Ambient" } do
			expect.equal(SoundController.groupVolume(group, silent), 0)
		end
		expect.near(SoundController.groupVolume("Music", defaults, 0.5), 0.12, 1e-9)
		expect.near(SoundController.groupVolume("Music", { music = 250, sfx = 0 } :: any), 0.6, 1e-9)
		expect.equal(SoundController.groupVolume("Nope", defaults), 0)
		expect.near(SoundController.groupVolume("SFX", { music = 40, sfx = 0 / 0 } :: any), 0, 1e-9)
	end)

	t.test("cooldowns by category; coins batched", function()
		expect.near(SoundController.cooldownSeconds("sfx.squish"), AUDIO.cooldownMs.squeeze / 1000, 1e-9)
		expect.near(SoundController.cooldownSeconds("sfx.impactBoing"), AUDIO.cooldownMs.impact / 1000, 1e-9)
		expect.near(SoundController.cooldownSeconds("ui.click"), AUDIO.cooldownMs.uiClick / 1000, 1e-9)
		expect.near(
			SoundController.cooldownSeconds("ui.coin"),
			math.max(AUDIO.cooldownMs.coin / 1000, AUDIO.coinBatchSeconds),
			1e-9
		)
		expect.equal(SoundController.cooldownSeconds("duel.win"), 0)
		expect.equal(SoundController.categoryOf("sfx.squeezeRelease"), "squeeze")
		expect.equal(SoundController.categoryOf("music.lobby"), nil)
	end)

	t.test("the feel pass cooldown categories of §18.6", function()
		local wanted: { [string]: { any } } = {
			["sfx.throw"] = { "throw", 0.060 },
			["sfx.jellyWobble"] = { "wobble", 0.080 },
			["sfx.pop"] = { "pop", 0.060 },
			["ui.hover"] = { "hover", 0.060 },
			["ui.hitConfirm"] = { "hitConfirm", 0.050 },
			["ui.error"] = { "error", 0.250 },
			["ui.back"] = { "uiClick", 0.040 },
			["ui.open"] = { "uiClick", 0.040 },
		}
		for key, spec in wanted do
			expect.equal(SoundController.categoryOf(key), spec[1])
			expect.near(SoundController.cooldownSeconds(key), spec[2], 1e-9)
		end
		-- No cooldown: the Dragon sounds, the elimination, toasts and jingles.
		for _, key in { "sfx.throwDragon", "sfx.dragonChomp", "sfx.elimination", "ui.toast", "duel.go", "duel.draw" } do
			expect.equal(SoundController.cooldownSeconds(key), 0)
		end
	end)

	t.test("pitch variation by category; fixed-pitch UI keys; an override wins", function()
		expect.equal(SoundController.pitchVariance("sfx.squish", "SFX"), AUDIO.pitchVariance.squeeze)
		expect.equal(SoundController.pitchVariance("sfx.impactSoft", "SFX"), AUDIO.pitchVariance.impact)
		expect.equal(SoundController.pitchVariance("ui.toast", "UI"), AUDIO.pitchVariance.ui)
		expect.equal(SoundController.pitchVariance("sfx.throw", "SFX"), AUDIO.pitchVariance.throw)
		expect.equal(SoundController.pitchVariance("sfx.jellyWobble", "SFX"), AUDIO.pitchVariance.wobble)
		expect.equal(SoundController.pitchVariance("sfx.pop", "SFX"), AUDIO.pitchVariance.pop)
		expect.equal(SoundController.pitchVariance("ui.hitConfirm", "UI"), AUDIO.pitchVariance.hitConfirm)
		-- UI keys without a variance of their own vary by ±ui (§18.6: click, hover, back, error, coin, unlock).
		for _, key in { "ui.click", "ui.hover", "ui.back", "ui.error", "ui.coin", "ui.open", "box.shake" } do
			expect.equal(SoundController.pitchVariance(key, "UI"), AUDIO.pitchVariance.ui)
		end
		-- Fixed pitch: countdown ticks (the caller passes 1.00 / 1.06 / 1.12), go, jingles, box open and reveals.
		for _, key in { "duel.countdownTick", "duel.go", "duel.win", "duel.lose", "duel.draw", "box.open" } do
			expect.equal(SoundController.pitchVariance(key, "UI"), 0)
		end
		expect.equal(SoundController.pitchVariance("reveal.exclusive", "UI"), 0)
		-- No variation for the other SFX and for loops.
		expect.equal(SoundController.pitchVariance("sfx.throwDragon", "SFX"), 0)
		expect.equal(SoundController.pitchVariance("sfx.elimination", "SFX"), 0)
		expect.equal(SoundController.pitchVariance("music.lobby", "Music"), 0)
		-- Inspect plays sfx.squish on UI: the squeeze variance still applies.
		expect.equal(SoundController.pitchVariance("sfx.squish", "UI"), AUDIO.pitchVariance.squeeze)
		-- The squeeze streak's ±1% override (§18.5.1 A2), clamped to [0, 0.5].
		expect.equal(SoundController.pitchVariance("sfx.squish", "SFX", 0.01), 0.01)
		expect.equal(SoundController.pitchVariance("duel.go", "UI", 0.02), 0.02)
		expect.equal(SoundController.pitchVariance("sfx.squish", "SFX", -1), 0)
		expect.equal(SoundController.pitchVariance("sfx.squish", "SFX", 3), 0.5)
		expect.equal(SoundController.pitchVariance("sfx.squish", "SFX", 0 / 0), AUDIO.pitchVariance.squeeze)
	end)

	t.test("pitchFor: variation times the multiplier, clamped to [pitchMin, pitchMax]", function()
		expect.near(SoundController.pitchFor(0, 0.3), 1, 1e-12)
		expect.near(SoundController.pitchFor(0.05, 1), 1.05, 1e-12)
		expect.near(SoundController.pitchFor(0.05, 0), 0.95, 1e-12)
		expect.near(SoundController.pitchFor(0.05, 0.5), 1, 1e-12)
		-- The countdown pitches come through exactly with no variation.
		for _, pitch in AUDIO.countdownPitch do
			expect.near(SoundController.pitchFor(0, 0.9, pitch), pitch, 1e-12)
		end
		expect.near(SoundController.pitchFor(0.04, 1, 1.06), 1.04 * 1.06, 1e-12)
		-- Clamped.
		expect.equal(SoundController.pitchFor(0.05, 1, 3), AUDIO.pitchMax)
		expect.equal(SoundController.pitchFor(0, 0, 0.1), AUDIO.pitchMin)
		-- A missing, non-positive or non-finite multiplier counts as 1; a roll outside [0, 1] is clamped.
		for _, bad in { 0, -2, 0 / 0, math.huge } do
			expect.near(SoundController.pitchFor(0, 0.5, bad), 1, 1e-12)
		end
		expect.near(SoundController.pitchFor(0.05, 7), 1.05, 1e-12)
		expect.near(SoundController.pitchFor(0.05, -7), 0.95, 1e-12)
		-- Every random pitch of every key stays inside the range.
		local rng = Random.new(11)
		for _, slot in AssetTable.all() do
			if slot.kind == "sound" then
				local variance = SoundController.pitchVariance(slot.key, slot.group)
				for _ = 1, 20 do
					local pitch = SoundController.pitchFor(variance, rng:NextNumber(), rng:NextNumber() * 3)
					expect.truthy(pitch >= AUDIO.pitchMin and pitch <= AUDIO.pitchMax)
				end
			end
		end
	end)

	-- UI FINAL R2 (plan §2.2): the design's sounds as pitches of the UI keys (Config.Audio.uiPitch).
	t.test(
		"UI pitches: a coin landing rises a semitone a coin, the 10th wraps (H:667, lib:145); every UI pitch fits",
		function()
			-- The design's coin(landed): landed counts from 1, note(landed % 10).
			expect.near(SoundController.coinPitch(1), 2 ^ (1 / 12), 1e-12)
			expect.near(SoundController.coinPitch(2), 2 ^ (2 / 12), 1e-12)
			expect.near(SoundController.coinPitch(9), 2 ^ (9 / 12), 1e-12)
			expect.near(SoundController.coinPitch(10), 1, 1e-12) -- the 10th wraps to the base
			expect.near(SoundController.coinPitch(11), 2 ^ (1 / 12), 1e-12)
			expect.near(SoundController.coinPitch(0 / 0), 1, 1e-12)
			for i = 1, 30 do
				local pitch = SoundController.coinPitch(i)
				expect.truthy(pitch >= AUDIO.pitchMin and pitch <= AUDIO.pitchMax)
				-- With no variation the play's pitch comes through exactly.
				expect.near(SoundController.pitchFor(0, 0.5, pitch), pitch, 1e-12)
			end
			local ui = AUDIO.uiPitch
			local values = { ui.tab, ui.card, ui.toggleOn, ui.toggleOff, ui.slideFrom, ui.slideFrom + ui.slideSpan }
			for _, pitch in ui.hover do
				table.insert(values, pitch)
			end
			for _, pitch in values do
				expect.truthy(pitch >= AUDIO.pitchMin and pitch <= AUDIO.pitchMax)
			end
			-- The coin batch (§11.9, 80 ms) against the 60 ms landings: about one ping in two plays, still rising.
			local cooldown = SoundController.cooldownSeconds("ui.coin")
			local stagger = Config.UI.motion.coinFlight.staggerMs / 1000
			local last, heard = -math.huge, {}
			for i = 1, 10 do
				local at = (i - 1) * stagger
				if at - last >= cooldown - 1e-9 then
					last = at
					table.insert(heard, SoundController.coinPitch(i))
				end
			end
			expect.truthy(#heard >= 4)
			for index = 2, #heard do
				expect.truthy(heard[index] > heard[index - 1])
			end
		end
	)

	-- UI FINAL R2 (G2.6): the design's slot(i) (H:760, H:768, lib:177): the i-th filled queue slot (from 0) a semitone
	-- higher each; the tick's low pitch inside the play range.
	t.test("slotPitch: a semitone a slot from the base, clamped; the tick's low pitch fits", function()
		expect.near(SoundController.slotPitch(0), 1, 1e-12)
		expect.near(SoundController.slotPitch(1), 2 ^ (1 / 12), 1e-12)
		expect.near(SoundController.slotPitch(3), 2 ^ (3 / 12), 1e-12)
		expect.near(SoundController.slotPitch(2.7), 2 ^ (2 / 12), 1e-12)
		expect.near(SoundController.slotPitch(-1), 1, 1e-12)
		expect.near(SoundController.slotPitch(0 / 0), 1, 1e-12)
		expect.near(SoundController.slotPitch(100), AUDIO.pitchMax, 1e-12) -- clamped
		expect.truthy(AUDIO.uiPitch.tick.lo >= AUDIO.pitchMin and AUDIO.uiPitch.tick.lo <= AUDIO.pitchMax)
	end)

	t.test("pickVariant: n = 0 and n = 1; never repeats the last pick; covers every variant", function()
		expect.equal(SoundController.pickVariant(0, nil, 0.5), 0)
		for _, roll in { 0, 0.4, 0.999, 1 } do
			expect.equal(SoundController.pickVariant(1, nil, roll), 1)
			expect.equal(SoundController.pickVariant(1, 1, roll), 1)
		end
		for _, n in { 2, 3, 5 } do
			for last = 1, n do
				local seen: { [number]: boolean } = {}
				for step = 0, 99 do
					local pick = SoundController.pickVariant(n, last, step / 100)
					expect.truthy(pick >= 1 and pick <= n)
					expect.truthy(pick ~= last)
					seen[pick] = true
				end
				seen[last] = true
				for index = 1, n do
					expect.truthy(seen[index])
				end
			end
			-- No last pick (or a stale one): every choice can come up.
			local function coversAll(stale: number?)
				local seen: { [number]: boolean } = {}
				for step = 0, 99 do
					seen[SoundController.pickVariant(n, stale, step / 100)] = true
				end
				for index = 1, n do
					expect.truthy(seen[index])
				end
			end
			coversAll(nil)
			for _, stale in { 0, -1, n + 1, 1.5, 0 / 0 } do
				coversAll(stale)
			end
			-- An edge roll stays in range.
			expect.truthy(SoundController.pickVariant(n, nil, 1) <= n)
			expect.truthy(SoundController.pickVariant(n, n, 1) <= n - 1)
		end
		-- A run of seeded picks never plays the same variant twice in a row.
		local rng = Random.new(3)
		local last: number? = nil
		local counts = { 0, 0, 0 }
		for _ = 1, 300 do
			local pick = SoundController.pickVariant(3, last, rng:NextNumber())
			expect.truthy(pick ~= last)
			counts[pick] += 1
			last = pick
		end
		for index = 1, 3 do
			expect.truthy(counts[index] > 50)
		end
	end)

	t.test("other players' sounds: distance and count limits by kind", function()
		local spatial = AUDIO.Spatial
		expect.equal((SoundController.othersAllowed("squeeze", spatial.othersSqueezeStuds, 0)), true)
		expect.equal((SoundController.othersAllowed("squeeze", 10, spatial.othersSqueezeMax - 1)), true)
		local far, farReason = SoundController.othersAllowed("squeeze", spatial.othersSqueezeStuds + 0.1, 0)
		expect.equal(far, false)
		expect.equal(farReason, "distance")
		local full, fullReason = SoundController.othersAllowed("squeeze", 10, spatial.othersSqueezeMax)
		expect.equal(full, false)
		expect.equal(fullReason, "caps")
		-- Throws hear farther (60 studs) than squeezes (50).
		expect.equal((SoundController.othersAllowed("throw", spatial.othersThrowStuds, 0)), true)
		expect.equal((SoundController.othersAllowed("throw", spatial.othersThrowStuds + 0.1, 0)), false)
		expect.equal((SoundController.othersAllowed("throw", 10, spatial.othersThrowMax)), false)
		expect.equal((SoundController.othersAllowed("squeeze", 55, 0)), false)
		expect.equal((SoundController.othersAllowed("throw", 55, 0)), true)
		-- An unknown distance (no camera or no position) or kind is refused.
		expect.equal((SoundController.othersAllowed("squeeze", nil, 0)), false)
		expect.equal((SoundController.othersAllowed("squeeze", 0 / 0, 0)), false)
		expect.equal((SoundController.othersAllowed("dance", 1, 0)), false)
		-- other = "squeeze" | "throw"; otherPlayer is the old alias for squeeze.
		expect.equal(SoundController.otherKindOf({ other = "throw" }), "throw")
		expect.equal(SoundController.otherKindOf({ other = "squeeze" }), "squeeze")
		expect.equal(SoundController.otherKindOf({ otherPlayer = true }), "squeeze")
		expect.equal(SoundController.otherKindOf({ otherPlayer = false }), nil)
		expect.equal(SoundController.otherKindOf({}), nil)
		expect.equal(SoundController.otherKindOf(nil), nil)
	end)

	t.test("3D one-shots beyond Spatial.maxDistance are culled; group overrides", function()
		expect.equal(SoundController.audible(nil), true)
		expect.equal(SoundController.audible(AUDIO.Spatial.maxDistance), true)
		expect.equal(SoundController.audible(AUDIO.Spatial.maxDistance + 0.01), false)
		expect.equal(SoundController.resolveGroup("SFX", "UI"), "UI")
		expect.equal(SoundController.resolveGroup("SFX", nil), "SFX")
		expect.equal(SoundController.resolveGroup("SFX", "Nope"), "SFX")
		expect.equal(SoundController.resolveGroup(nil, nil), "SFX")
	end)

	t.test("ducking: multipliers multiply; duel ducks follow the phase", function()
		expect.equal(SoundController.duckProduct({}), 1)
		expect.near(SoundController.duckProduct({ a = 0.5, b = 0.8 }), 0.4, 1e-9)
		expect.near(SoundController.duckProduct({ a = 3, b = 0 / 0 }), 1, 1e-9) -- clamped; NaN ignored
		expect.deepEqual(SoundController.duelDucks(nil), {})
		expect.deepEqual(SoundController.duelDucks({ phase = "Countdown" }), { countdown = AUDIO.Ducking.countdown })
		expect.deepEqual(SoundController.duelDucks({ phase = "Result" }), { result = AUDIO.Ducking.result })
		expect.deepEqual(SoundController.duelDucks({ phase = "Active" }), {})
	end)

	-- Music job (2026-10-16): music.duel in duels and matches, the audio zone's music otherwise.
	t.test("musicFor: the battle music while a duel or a match runs, the zone's music otherwise", function()
		local battle = { key = "music.duel", phases = { Countdown = true, Active = true, Result = true } }
		expect.equal(SoundController.musicFor("music.lobby", nil, nil, battle), "music.lobby")
		expect.equal(SoundController.musicFor(nil, nil, nil, battle), nil)
		expect.equal(SoundController.musicFor("music.lobby", { phase = "Countdown" }, nil, battle), "music.duel")
		expect.equal(SoundController.musicFor("music.lobby", nil, { phase = "Result" }, battle), "music.duel")
		expect.equal(SoundController.musicFor(nil, nil, { phase = "Active" }, battle), "music.duel") -- a map, no zone
		-- A phase outside the list keeps the zone's music (still in the lobby, or the duel never started).
		expect.equal(SoundController.musicFor("music.lobby", { phase = "Preparing" }, nil, battle), "music.lobby")
		expect.equal(
			SoundController.musicFor("music.lobby", { phase = "Cancelled" }, { phase = "Void" }, battle),
			"music.lobby"
		)
		-- Odd input: a view without a phase, a broken rule table.
		expect.equal(SoundController.musicFor("music.lobby", {} :: any, nil, battle), "music.lobby")
		expect.equal(SoundController.musicFor("music.lobby", { phase = "Active" }, nil, {} :: any), "music.lobby")
	end)

	t.test("the battle music rules: a 2D Music slot, every phase a duel and a match play in", function()
		local battle = AUDIO.battleMusic
		local slots: { [string]: any } = {}
		for _, candidate in AssetTable.all() do
			if candidate.kind == "sound" and (candidate.key == battle.key or candidate.key == "music.lobby") then
				slots[candidate.key] = candidate
			end
		end
		-- Review fix (2026-10-16): the slots exist; their ids come from the owner's pick (the sound picker), not here.
		for _, key in { battle.key, "music.lobby" } do
			expect.truthy(slots[key] ~= nil)
			expect.equal(slots[key].group, "Music")
			expect.equal(slots[key].spatial, false)
		end
		-- Every listed phase is a DuelPhase name; the lobby-side ones are not listed.
		local duelPhases = {
			Preparing = true,
			Positioning = true,
			Countdown = true,
			Active = true,
			SuddenDeath = true,
			Result = true,
			Returning = true,
			Cancelled = true,
			Void = true,
		}
		for phase, on in battle.phases do
			expect.truthy(duelPhases[phase] == true and on == true)
		end
		for _, phase in { "Preparing", "Cancelled", "Void" } do
			expect.equal(battle.phases[phase], nil)
		end
		-- The phases a match sends (MatchService WIRE_PHASE: Waiting, Countdown, Active / Overtime, Result, Closed) and a
		-- duel's from the teleport on all play it.
		for _, phase in { "Positioning", "Countdown", "Active", "SuddenDeath", "Result", "Returning" } do
			expect.equal(SoundController.musicFor("music.lobby", nil, { phase = phase }), battle.key)
			expect.equal(SoundController.musicFor("music.lobby", { phase = phase }, nil), battle.key)
		end
		-- The match result sting's wait (Diego's 250 ms, M:570).
		expect.near(AUDIO.matchStingDelaySeconds, 0.25, 1e-9)
	end)

	t.test("duckFor: the knockout duck holds, then releases itself; an early release works", function()
		local base = SoundController.debugState().duck
		local release = SoundController.duckFor("knockout")
		expect.near(SoundController.debugState().duck, base * AUDIO.Ducking.knockout, 1e-9)
		release()
		expect.near(SoundController.debugState().duck, base, 1e-9)
		release() -- twice is harmless
		expect.near(SoundController.debugState().duck, base, 1e-9)

		local telegraph = SoundController.duck("telegraph")
		expect.near(SoundController.debugState().duck, base * AUDIO.Ducking.telegraph, 1e-9)
		telegraph()

		SoundController.duckFor("knockout", 0.05)
		expect.near(SoundController.debugState().duck, base * AUDIO.Ducking.knockout, 1e-9)
		task.wait(0.2)
		expect.near(SoundController.debugState().duck, base, 1e-9)
	end)

	t.test("caps: room, steal the oldest stealable voice, or drop", function()
		local ok, victim = SoundController.admit({}, "UI", "ui.click", 0, caps)
		expect.equal(ok, true)
		expect.equal(victim, nil)

		local ui = {}
		for i = 1, caps.UI do
			table.insert(ui, voice("UI", "ui.click", 10 + i))
		end
		local okFull, oldest = SoundController.admit(ui, "UI", "ui.toast", 0, caps)
		expect.equal(okFull, true)
		expect.equal(oldest, 1)

		-- A higher-priority voice is never stolen by a lower one; looping voices are never stolen.
		local guarded = {}
		for i = 1, caps.UI do
			table.insert(guarded, voice("UI", "ui.click", i, false, 5))
		end
		local dropped, none = SoundController.admit(guarded, "UI", "ui.toast", 0, caps)
		expect.equal(dropped, false)
		expect.equal(none, nil)
		local loops = { voice("Ambient", "amb.lobby", 1, true), voice("Ambient", "amb.arena", 2, true) }
		expect.equal((SoundController.admit(loops, "Ambient", "amb.lobby", 0, caps)), false)
	end)

	t.test("caps: SFX per key before the group cap; Music grows during a crossfade", function()
		local sfx = {}
		for i = 1, caps.SFXPerKey do
			table.insert(sfx, voice("SFX", "sfx.squish", 100 + i))
		end
		table.insert(sfx, 1, voice("SFX", "sfx.throw", 1)) -- older, but another key
		local ok, victim = SoundController.admit(sfx, "SFX", "sfx.squish", 0, caps)
		expect.equal(ok, true)
		expect.equal(sfx[victim].key, "sfx.squish")
		expect.equal(sfx[victim].startedAt, 101)
		-- Another key still fits while the group has room.
		local okOther, none = SoundController.admit(sfx, "SFX", "sfx.throw", 0, caps)
		expect.equal(okOther, true)
		expect.equal(none, nil)

		local music = { voice("Music", "music.lobby", 1, true) }
		expect.equal((SoundController.admit(music, "Music", "music.duel", 0, caps, false)), false)
		local okFade, noVictim = SoundController.admit(music, "Music", "music.duel", 0, caps, true)
		expect.equal(okFade, true)
		expect.equal(noVictim, nil)
	end)

	t.test("caps: perKeyCap overrides the per-key cap (sfx.jellyWobble at most 2 voices)", function()
		expect.equal(AUDIO.perKeyCap["sfx.jellyWobble"], 2)
		local wobbles = {
			voice("SFX", "sfx.throw", 1),
			voice("SFX", "sfx.jellyWobble", 5),
			voice("SFX", "sfx.jellyWobble", 3),
		}
		-- Without the override, SFXPerKey (3) leaves room for a third wobble.
		local okPlain, nonePlain = SoundController.admit(wobbles, "SFX", "sfx.jellyWobble", 0, caps)
		expect.equal(okPlain, true)
		expect.equal(nonePlain, nil)
		-- With it, the oldest wobble makes room.
		local ok, victim = SoundController.admit(wobbles, "SFX", "sfx.jellyWobble", 0, caps, false, AUDIO.perKeyCap)
		expect.equal(ok, true)
		expect.equal(victim, 3)
		-- Other keys are unaffected by the override.
		local okThrow, noneThrow = SoundController.admit(wobbles, "SFX", "sfx.throw", 0, caps, false, AUDIO.perKeyCap)
		expect.equal(okThrow, true)
		expect.equal(noneThrow, nil)
		-- A higher-priority wobble can't be stolen: the new one is dropped.
		local guarded = { voice("SFX", "sfx.jellyWobble", 1, false, 3), voice("SFX", "sfx.jellyWobble", 2, false, 3) }
		local dropped, none = SoundController.admit(guarded, "SFX", "sfx.jellyWobble", 0, caps, false, AUDIO.perKeyCap)
		expect.equal(dropped, false)
		expect.equal(none, nil)
		-- An override also caps a key outside SFX.
		local coins = { voice("UI", "ui.coin", 1) }
		local okCoin, coinVictim = SoundController.admit(coins, "UI", "ui.coin", 0, caps, false, { ["ui.coin"] = 1 })
		expect.equal(okCoin, true)
		expect.equal(coinVictim, 1)
		-- Every perKeyCap key is a sound slot.
		for key in AUDIO.perKeyCap do
			local found = false
			for _, slot in AssetTable.all() do
				found = found or (slot.kind == "sound" and slot.key == key)
			end
			expect.truthy(found)
		end
	end)

	t.test("auditions: only while Config.Debug.soundPicker; never counted as approved ids", function()
		-- The pure gate: off means ignored, whatever the key and id.
		expect.equal(SoundController.auditionAllowed(false, "sfx.squish", 1), false)
		expect.equal(SoundController.auditionAllowed(false, "sfx.squish", nil), false)
		expect.equal(SoundController.auditionAllowed(true, "sfx.squish", 1), true)
		expect.equal(SoundController.auditionAllowed(true, "sfx.squish", nil), true)
		for _, bad in { 0, -1, 2.5, 0 / 0 } do
			expect.equal(SoundController.auditionAllowed(true, "sfx.squish", bad), false)
		end
		expect.equal(SoundController.auditionAllowed(true, "sfx.notAKey", 1), false)
		expect.equal(SoundController.auditionAllowed(true, "img.coin", 1), false)

		local enabled = Config.Debug.soundPicker == true
		local pendingBefore = SoundController.missingKeys(AssetTable.all())
		local anySfxBefore = SoundController.hasAnyIn({ "SFX" })
		local hadSound = SoundController.hasSound("sfx.squish")
		expect.equal(SoundController.audition("sfx.squish", 1, 0.7), enabled)
		expect.equal(SoundController.hasSound("sfx.squish"), enabled or hadSound)
		expect.equal(SoundController.debugState().auditions, if enabled then 1 else 0)
		-- Ignored by the approved-id views: the startup warnings and the Settings captions.
		expect.deepEqual(SoundController.missingKeys(AssetTable.all()), pendingBefore)
		expect.equal(SoundController.hasAnyIn({ "SFX" }), anySfxBefore)
		-- A bad id is refused and keeps the current audition.
		expect.equal(SoundController.audition("sfx.squish", 0), false)
		expect.equal(SoundController.debugState().auditions, if enabled then 1 else 0)
		-- id = nil drops it; clearAuditions drops all.
		expect.equal(SoundController.audition("sfx.squish", nil), enabled)
		expect.equal(SoundController.debugState().auditions, 0)
		SoundController.audition("sfx.squish", 1)
		expect.equal(SoundController.audition("ui.click", 2, 9), enabled) -- an out-of-range volume is clamped
		expect.equal(SoundController.debugState().auditions, if enabled then 2 else 0)
		SoundController.clearAuditions()
		expect.equal(SoundController.debugState().auditions, 0)
		expect.equal(SoundController.hasSound("sfx.squish"), hadSound)
	end)

	t.test("recent(): every attempt with its result, capped at recentLogSize", function()
		if not Config.Debug.isStudio then
			expect.equal(#SoundController.recent(), 0) -- the log is Studio only
			return
		end
		local before = SoundController.recent()
		-- An unknown key, a PENDING key that asks (noId) and then repeats inside its cooldown.
		SoundController.play("sfx.notAKey")
		expect.equal(SoundController.play("ui.hover"), false)
		expect.equal(SoundController.play("ui.hover"), false)
		expect.deepEqual(resultsSince(before), { "sfx.notAKey=noId", "ui.hover=noId", "ui.hover=cooldown" })
		-- Another player's squeeze with no position is too far to hear; a far 3D one-shot is culled when there is a
		-- camera to measure from (Edit mode in Studio has one).
		before = SoundController.recent()
		SoundController.play("sfx.squeezeRelease", { otherPlayer = true })
		SoundController.play("sfx.elimination", { at = Vector3.new(1e6, 0, 0) })
		local far = if game:GetService("Workspace").CurrentCamera ~= nil then "distance" else "noId"
		expect.deepEqual(resultsSince(before), { "sfx.squeezeRelease=distance", `sfx.elimination={far}` })
		-- playTracked logs too and returns nothing to stop while nothing plays.
		before = SoundController.recent()
		expect.equal(SoundController.playTracked("sfx.elimination"), nil)
		expect.deepEqual(resultsSince(before), { "sfx.elimination=noId" })
		-- Entries carry a key, a time and a result; the log keeps the newest recentLogSize.
		for _ = 1, AUDIO.recentLogSize + 5 do
			SoundController.play("duel.win") -- no cooldown
		end
		local log = SoundController.recent()
		expect.equal(#log, AUDIO.recentLogSize)
		for _, entry in log do
			expect.equal(entry.key, "duel.win")
			expect.equal(entry.result, "noId")
			expect.equal(type(entry.t), "number")
		end
		-- recent() hands out copies.
		log[1].result = "played"
		expect.equal(SoundController.recent()[1].result, "noId")
	end)

	t.test("cooldowns: other players' sounds (priority below 0) never hold the local player's cooldown", function()
		if Config.Debug.isStudio then -- the log is Studio only
			-- Another player's error sound arms only its own cooldown: the local player's one right after is still
			-- asked for, and each kind then waits for its own cooldown (ui.error: a key with a cooldown and no upload).
			local before = SoundController.recent()
			SoundController.play("ui.error", { priority = -1 })
			SoundController.play("ui.error", { priority = 1 })
			SoundController.play("ui.error", { priority = -1 })
			SoundController.play("ui.error", { priority = 1 })
			expect.deepEqual(resultsSince(before), {
				"ui.error=noId",
				"ui.error=noId",
				"ui.error=cooldown",
				"ui.error=cooldown",
			})
		end
		expect.equal(SoundController.cooldownKey("sfx.squish", 1), "sfx.squish")
		expect.equal(SoundController.cooldownKey("sfx.squish", 0), "sfx.squish")
		expect.equal(SoundController.cooldownKey("sfx.squish", nil), "sfx.squish")
		expect.equal(SoundController.cooldownKey("sfx.squish", -1), "sfx.squish#other")
	end)

	t.test("voiceExpired: a one-shot that never loads, or is long past its end, is dropped", function()
		-- Not loaded: kept for 5 s after its start, then dropped (Sound.Ended never fires for it).
		expect.falsy(SoundController.voiceExpired(104.9, 100, false, 0, 1))
		expect.truthy(SoundController.voiceExpired(105.1, 100, false, 0, 1))
		-- Loaded, 2 s long at speed 1: the 5 s load allowance + its length + 0.5 s slack.
		expect.falsy(SoundController.voiceExpired(107.4, 100, true, 2, 1))
		expect.truthy(SoundController.voiceExpired(107.6, 100, true, 2, 1))
		-- At half speed it lasts twice as long; a speed of 0 counts as 1.
		expect.falsy(SoundController.voiceExpired(109.4, 100, true, 2, 0.5))
		expect.truthy(SoundController.voiceExpired(109.6, 100, true, 2, 0.5))
		expect.truthy(SoundController.voiceExpired(107.6, 100, true, 2, 0))
		-- Loaded with no length yet: the load allowance only. A fresh voice and a bad clock are kept.
		expect.truthy(SoundController.voiceExpired(105.1, 100, true, 0, 1))
		expect.falsy(SoundController.voiceExpired(100, 100, false, 0, 1))
		expect.falsy(SoundController.voiceExpired(0 / 0, 100, false, 0, 1))
	end)

	t.test("missing ids: exactly the sound slots without an id, each once, sorted", function()
		local slots: { any } = {
			{ key = "ui.b", kind = "sound" },
			{ key = "ui.a", kind = "sound" },
			{ key = "ui.c", kind = "sound", id = 123 },
			{ key = "img.coin", kind = "image" },
		}
		expect.deepEqual(SoundController.missingKeys(slots), { "ui.a", "ui.b" })

		-- The real table: every sound slot whose id is still PENDING (§14.2) is listed.
		local expected = {}
		for _, slot in AssetTable.all() do
			if slot.kind == "sound" and slot.id == nil then
				table.insert(expected, slot.key)
			end
		end
		table.sort(expected)
		expect.deepEqual(SoundController.missingKeys(AssetTable.all()), expected)
	end)
end
