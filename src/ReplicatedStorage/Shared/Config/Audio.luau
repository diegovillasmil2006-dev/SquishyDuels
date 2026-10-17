--!strict
-- Config.Audio: SoundGroup mix, voice caps, cooldowns, pitch variation, 3D settings and ducking (DESIGN §11.9), with
-- the feel pass sound wiring values (§18.6, §18.8).
-- Shared (read by the client SoundController), data only. All [P]. Sound ids live only in AssetTable.luau.
-- Music job (2026-10-16): battleMusic (the duel music in duels and matches) and matchStingDelaySeconds.

-- A CompressorSoundEffect on a group (Threshold dB, Ratio, Attack / Release seconds, GainMakeup dB).
export type Compressor = { threshold: number, ratio: number, attack: number, release: number, makeup: number }

export type Group = {
	maxVolume: number, -- groupVolume = maxVolume × slider / 100 (SoundGroup.Volume defaults to 0.5, always set)
	slider: string, -- the ProfileV1.settings key that drives this group
	compressor: Compressor?, -- phase2-squeeze §3.9: the Wax group's bus compressor
}

local Audio = {
	-- SoundGroups created by the client under SoundService at runtime.
	Groups = {
		Music = { maxVolume = 0.6, slider = "music" },
		SFX = { maxVolume = 1.0, slider = "sfx" },
		UI = { maxVolume = 0.8, slider = "sfx" },
		Ambient = { maxVolume = 0.5, slider = "sfx" },
		-- The knead's wax crunch (spec phase2-squeeze §3.9): on the SFX slider, through the design's wax bus compressor
		-- (squish.js:816-821: threshold -20 dB, ratio 3, attack 3 ms, release 120 ms, then ×1.8 = +5.1 dB; Roblox's
		-- compressor has no knee, the design's is 12 dB).
		Wax = {
			maxVolume = 1.0,
			slider = "sfx",
			compressor = { threshold = -20, ratio = 3, attack = 0.003, release = 0.12, makeup = 5.1 },
		},
	} :: { [string]: Group },

	-- When full: stop the oldest non-looping voice with a stealFadeMs fade, or drop a lower-priority new sound.
	VoiceCaps = {
		SFX = 10,
		SFXPerKey = 3,
		UI = 4,
		Ambient = 2, -- loops
		Music = 1,
		MusicDuringCrossfade = 2,
		-- Proposal (spec phase2-squeeze §3.9): the wax crunch's ~33 bursts a second, its ticks and taps and its two beds;
		-- the wax keys have no cooldown category and no per-key cap.
		Wax = 12,
	},
	crossfadeSeconds = 1.5,
	stealFadeMs = 30,
	-- Ambient zones (§7.7): the local HumanoidRootPart is tested against the SD_AudioZone volumes this often
	-- (WorldBinder; highest priority wins, then a crossfadeSeconds fade).
	zoneCheckSeconds = 0.25,

	-- Per-key cooldowns in ms, by sound category.
	cooldownMs = {
		squeeze = 90,
		coin = 60,
		impact = 50,
		uiClick = 40,
		-- Feel pass categories (§18.6).
		throw = 60,
		wobble = 80,
		pop = 60,
		hover = 60,
		hitConfirm = 50,
		error = 250,
		dash = 60, -- spec phase 5: sfx.dash and sfx.dashPlant (one dash plays each once)
	},
	coinBatchSeconds = 0.08, -- coin ticks batched to <= 1 per 0.08 s

	-- Random pitch variation (± fraction), by sound category.
	pitchVariance = {
		squeeze = 0.04,
		impact = 0.06,
		ui = 0.02,
		-- Feel pass categories (§18.6).
		throw = 0.05,
		wobble = 0.08,
		pop = 0.06,
		hitConfirm = 0.03,
		dash = 0.05, -- spec phase 5
	},
	-- The final pitch (random variation × the play option's `pitch`) is clamped to [pitchMin, pitchMax] (§18.6).
	pitchMin = 0.5,
	pitchMax = 2,
	-- UI FINAL R2 (plan work/ui/PLAN.md §2.2): the design's sounds (hud-lib.js SFX, lib:134-191, and its handlers) as
	-- the play option `pitch` of the UI keys that stand in for them. `lib:n` = uploads/hud-lib.js line n, `H:n` =
	-- "Squishy Duels HUD.dc.html" line n.
	uiPitch = {
		-- ui.hover over a button by its design hover kind (H:638: nav .8, card 1.15, tab 1.3, else 1;
		-- Config.UI.motion.hover)
		hover = { btn = 1, nav = 0.8, tab = 1.3, card = 1.15, x = 1, icon = 1, row = 1 },
		-- ui.click for a tab pick and the coin pill (the design's tab sound, H:75, lib:138; reading: its pitch)
		tab = 1.3,
		card = 1.15, -- ui.click for a card pick (the design's card sound, H:318, lib:137; reading)
		toggleOn = 1.2, -- ui.click for a switch going on / off (lib:152's rising / falling pair; reading)
		toggleOff = 0.9,
		-- the slider's ui.hover tick at slideFrom + slideSpan × value (lib:191: 500 + 900 v Hz; reading)
		slideFrom = 0.8,
		slideSpan = 0.9,
		slideStepShare = 0.05, -- one tick per 5% of travel (H:898)
		-- ui.coin goes landing % coinSteps semitones up: the 1st +1 .. the 9th +9, the 10th at the base (H:667,
		-- lib:145)
		coinSteps = 10,
		-- slot(i) (H:760, H:768; lib:177 note(i, 659)): ui.click i x semitone semitones up; the 1v1 search's two
		-- slots: 0 (you, on join), 1 (the opponent, on match), R4
		slot = { semitone = 1 },
		-- tick(false) every 700 ms while searching (H:763, H:768): ui.hover at lib:178's 900 Hz against lib:134's
		-- 1400 Hz hover (900 / 1400), R4
		tick = { lo = 0.643 },
	},
	-- UI FINAL R2 (plan §2.2 G2.7, one sound per click): the Button kinds whose own click is silent because their
	-- action plays its sound (the nav tiles and Settings: ui.open; the close X: ui.back, both from UIController); their
	-- hover sound stays (H:638).
	buttonSilentKinds = { tile = true, close = true },

	-- 3D sounds.
	Spatial = {
		rollOffMode = Enum.RollOffMode.InverseTapered,
		minDistance = 10,
		maxDistance = 90,
		othersSqueezeStuds = 50, -- other players' squeezes are heard only this close ...
		othersSqueezeMax = 3, -- ... at most this many at once
		othersThrowStuds = 60, -- other players' throws (§18.6) only this close ...
		othersThrowMax = 3, -- ... at most this many at once
	},

	-- Per-key voice cap overrides (§18.6), in place of VoiceCaps.SFXPerKey.
	perKeyCap = {
		["sfx.jellyWobble"] = 2,
	},

	-- duel.countdownTick pitch on 3, 2, 1, and duel.go's pitch on the sudden-death banner (§18.5.2 B6).
	countdownPitch = { 1.0, 1.06, 1.12 },
	suddenDeathGoPitch = 0.9,
	wobbleAfterImpactMs = 40, -- sfx.jellyWobble on the ripple's first frame at least this long after the impact
	softImpactMinorVolume = 0.5, -- sfx.impactSoft volume × this for expired / fizzle
	trackedStopFadeMs = 80, -- playTracked's stop fade (the cancelled Dragon telegraph)

	-- Music volume multipliers, ramped over rampMs.
	Ducking = {
		boxReveal = 0.5, -- box anticipation and reveal
		countdown = 0.6,
		result = 0.6,
		inspect = 0.8, -- while Inspect is open
		rampMs = 250,
		-- Feel pass (§18.6): an elimination ducks the music for the two duelists for knockoutSeconds (duckFor);
		-- the targeted duelist hears it ducked while a Dragon telegraph runs.
		knockout = 0.5,
		knockoutSeconds = 0.6,
		telegraph = 0.8,
	},

	-- Music job (2026-10-16): while the local player's duel or match view is in one of these phases (DuelPhase names; a
	-- match uses them too, SPEC D1) the music is `key`, whatever the audio zone says (Diego's match maps have no zone);
	-- Preparing (still in the lobby), Cancelled and Void keep the zone's music. Returning keeps it until the view ends
	-- back in the lobby, so the lobby music comes back with one crossfade. No design for music exists: proposal.
	battleMusic = {
		key = "music.duel",
		phases = {
			Positioning = true,
			Countdown = true,
			Active = true,
			SuddenDeath = true,
			Result = true,
			Returning = true,
		} :: { [string]: boolean },
	},
	-- Music job: a match's result sting (duel.win / duel.lose / duel.draw, as a duel's) plays this long after the
	-- outcome arrives: Diego's end sound starts 250 ms after the final K.O. ("Squishy Duels Match HUD.dc.html" M:570).
	matchStingDelaySeconds = 0.25,

	-- Toast code -> the sound key NotifyController passes to UIController.toast (§18.5.2 B5, §18.6). Keeps the only
	-- lobby-stat sound key out of the duel-path files.
	toastSounds = {
		["grip.levelUp"] = "ui.gripUnlock",
		["grip.rankUp"] = "ui.gripUnlock",
	},

	recentLogSize = 30, -- Studio play-attempt log (SoundController.recent, SD_DebugClient "sounds")

	-- Feature 1 (2026-10-11): the charge tone, sfx.chargeLoop as a looped voice (SoundController.playLoop) that follows
	-- the charge c while charging and the crush's e while crushing (design: the combat-effects page's
	-- squishy-lib-v2.js:378-386, html:517, 551-552: 150 + 360c Hz, gain 0.025 + 0.035c, × (1 + 0.35·sin 40T) at full).
	-- A sample only changes speed: pitch = pitchFrom + (pitchTo - pitchFrom)·c (the design's ×3.4, 150 -> 510 Hz, held
	-- to pitchMax: ×3.33), volume = the design's gain at c over its gain at 1.
	charge = {
		pitchFrom = 0.6, -- design: squishy-lib-v2.js:384 (150 Hz ...)
		pitchTo = 2, -- (... 510 Hz), held to pitchMax
		volumeFrom = 0.025 / 0.06, -- design: squishy-lib-v2.js:384 (gain 0.025 at c = 0, 0.06 at c = 1)
		tremolo = 0.35, -- at full, volume × (1 + tremolo·sin(tremoloRate·t)) (design: squishy-lib-v2.js:384)
		tremoloRate = 40, -- rad/s (design: squishy-lib-v2.js:384)
		stopFadeMs = 100, -- design: squishy-lib-v2.js:386 (a 30 ms time constant, cut at 200 ms)
	},

	-- User 2026-10-12: with the knead's wax crunch off (Config.Wax.enabled), letting go of a press and the toy rising back
	-- play their wax ticks softened (Controllers/KneadAudio.soften): every crackleStride-th tick from the first, at
	-- crackleGain of its volume, the wax let-go with about a third of its crackle.
	kneadSoft = {
		crackleStride = 3, -- proposal: about a third of the ticks
		crackleGain = 0.6, -- proposal: and quieter
	},

	-- The knead's wax crunch (spec phase2-squeeze §1.22, §3.9-§3.10; design: squish.js:796-945, fx.js:4-61), played by
	-- Controllers/KneadAudio in the Wax group (no cooldown). The files are 48 kHz mono renders of the design's own
	-- generators, each normalised to -1 dBFS (scratchpad work/sounds-out/manifest.json, normGainDb); a Volume of
	-- 10^(-levelDb / 20) gives the design's level back. The sheets (bursts, grains and taps, one per feel), the thumps
	-- and the re-wax sparkle went through the design's wax bus and SFX master when rendered; the haze and body loops did
	-- not, so they also take busGain × masterGain. trim (proposal) is the one calibration factor (spec §3.9 "Levels":
	-- match audio/wax-preview.wav by ear in Studio).
	wax = {
		gain = { foam = 1, mochi = 0.95, jelly = 0.85, plush = 0.95 }, -- WAX[feel].gain (design: squish.js:42-48)
		sheetLevelDb = { foam = 0.4, mochi = 1.5, jelly = 1.4, plush = 0.8 }, -- manifest: wax_sheet_<feel>.wav
		loopLevelDb = -1, -- manifest: wax_haze_<feel>.wav, wax_body_<feel>.wav
		thumpLevelDb = 34.9, -- manifest: wax_thump.wav
		snapThumpLevelDb = 34.6, -- manifest: wax_snapThump.wav
		rewaxLevelDb = 25.8, -- manifest: wax_rewax_1.wav (wax_rewax_2.wav: 26.0)
		busGain = 1.8, -- design: squish.js:818
		masterGain = 0.7, -- design: fx.js:5
		trim = 1, -- proposal
		-- The sheet layout (manifest: the same for every feel). Bursts: crack(E, intact) for every burstEnergies ×
		-- burstIntacts × burstVariants, burstSlot s each from 0 (E outermost, then intact, then variant). Then the 48
		-- grains (b = i / 47) in grainSlot s from grainStart, each at grainGain; then the 5 taps in tapSlot s from tapStart,
		-- each at tapGain × gain (the palm tap of amt 1).
		burstEnergies = { 0.4, 0.7, 1, 1.4, 2, 2.8 },
		burstIntacts = { 1, 0.6, 0.25 },
		burstVariants = 3,
		burstSlot = 0.12,
		grainCount = 48,
		grainStart = 6.48,
		grainSlot = 0.05,
		grainGain = 0.5,
		tapCount = 5,
		tapStart = 8.88,
		tapSlot = 0.1,
		tapGain = 0.42,
		-- A crack's burst (design: squish.js:856-866): the nearest baked E (in log steps) and intact, a random variant,
		-- Volume × 10^(energyDb·(E - baked E) / 20) (each grain is energyDb louder per unit of E) × (intactBase + (1 -
		-- intactBase)·intact) / (the same at the baked intact), PlaybackSpeed U(burstSpeedMin, burstSpeedMax).
		energyDb = 7, -- design: squish.js:861
		intactBase = 0.35, -- design: squish.js:858
		burstSpeedMin = 0.94, -- design: squish.js:862
		burstSpeedMax = 1.06,
		-- Ticks (design: squish.js:874-876): each one of the first tickGrains grains, at u^tickPower of its span (u =
		-- U(0, 1)), gain × U(tickGainMin, 1) × (1 - tickFade·u) × the feel's gain, speed U(tickSpeedMin, tickSpeedMax).
		tickGrains = 36,
		tickPower = 1.6,
		tickGainMin = 0.3,
		tickFade = 0.6,
		tickSpeedMin = 0.92,
		tickSpeedMax = 1.06,
		-- A release (design: squish.js:897): releaseFinger (a finger) or releasePress (palms, thumbs) ticks + 1 with chance
		-- releaseExtraChance, from releaseDelay over releaseSpan s, gain releaseGain·(0.5 + 0.5·amt).
		releaseFinger = 1,
		releasePress = 2,
		releaseExtraChance = 0.5,
		releaseDelay = 0.01,
		releaseSpan = 0.06,
		releaseGain = 0.12,
		-- Settling (design: squish.js:905): round(U(airMin, airMax)·(0.5 + 0.5·amt)) ticks from airDelay over min(airSpanMax,
		-- airSpanRise·rise) s (rise = the feel's), gain airGain·amt.
		airMin = 3,
		airMax = 6,
		airDelay = 0.12,
		airSpanMax = 1.6,
		airSpanRise = 0.8,
		airGain = 0.08,
		-- A press (design: squish.js:867-873; amt 1): a finger taps at fingerTap × gain, speed √p·U(fingerSpeedMin,
		-- fingerSpeedMax); palms and thumbs tap at pressTapA, then after U(pressGapMin, pressGapMax) s at pressTapB (speeds
		-- √p·U(pressSpeedAMin, pressSpeedAMax) and √p·U(pressSpeedBMin, pressSpeedBMax)), and thump (wax_thump.wav, made at
		-- p = 1: PlaybackSpeed p) at thumpGain (the render's own gain). p = the toy's motion.squeeze.pitch.
		fingerTap = 0.3,
		fingerSpeedMin = 0.95,
		fingerSpeedMax = 1.1,
		pressTapA = 0.42,
		pressSpeedAMin = 0.88,
		pressSpeedAMax = 0.98,
		pressTapB = 0.38,
		pressSpeedBMin = 0.9,
		pressSpeedBMax = 1.02,
		pressGapMin = 0.01,
		pressGapMax = 0.035,
		thumpGain = 0.06,
		-- A stretch let go (design: squish.js:935-936): a burst at snapE + a, another at echoE + echoShare·a echoDelay s
		-- later, and the snap thump (wax_snapThump.wav at snapThumpGain, its render's) at snapThumpGain·(0.5 + a).
		snapE = 1.6,
		echoE = 0.9,
		echoShare = 0.6,
		echoDelay = 0.03,
		snapThumpGain = 0.05,
		-- The beds (design: squish.js:846-854), every frame the body moves: haze = gain·hazeGain·drive·(hazeBase + (1 -
		-- hazeBase)·intact), body = gain·bodyGain·min(1, bodyDrive·drive + bodyPress·press)·(bodyBase + bodyWorn·(1 -
		-- intact)), each eased toward with its time constant (hazeTau, bodyTau; quietHazeTau, quietBodyTau when the body
		-- rests) and written once it moved bedEpsilon. Each loop starts at U(0, startMax) s.
		hazeGain = 0.055,
		hazeBase = 0.25,
		bodyGain = 0.1,
		bodyDrive = 0.9,
		bodyPress = 0.22,
		bodyBase = 0.75,
		bodyWorn = 0.45,
		hazeTau = 0.03,
		bodyTau = 0.05,
		quietHazeTau = 0.04,
		quietBodyTau = 0.06,
		bedEpsilon = 2e-4,
		startMax = 1.5,
	},

	-- Kill banners (2026-10-16): the sound sheets (AssetTable sfx.kill.*, one per kill set). Tier n plays
	-- [(n - 1)·slotSeconds, (n - 1)·slotSeconds + soundSeconds] of its sheet; 2D, for the killer only, at `volume`,
	-- never pitched (variance 0), at `priority` (above impacts: a kill sound is never the one dropped).
	killBanner = {
		tiers = 6,
		slotSeconds = 3,
		soundSeconds = 2.9,
		volume = 0.9,
		priority = 4,
	},

	-- Match HUD M6 / M7 (2026-10-17; `M:n` = "Squishy Duels Match HUD.dc.html" line n): M:515's splat(g) is one file
	-- played at volume g: another player's K.O. in the kill feed .45 (M:537), you squished 1.1 (M:548). Your own K.O.s
	-- play Diego's kill banner sound (killBanner above), never these. The feed row's and the card's click is ui.click at
	-- uiPitch.card (M:533, M:560).
	matchHud = {
		splatOthers = 0.45,
		splatYou = 1.1,
	},
}

return Audio
