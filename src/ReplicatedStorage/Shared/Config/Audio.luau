--!strict
-- Config.Audio: SoundGroup mix, voice caps, cooldowns, pitch variation, 3D settings and ducking (DESIGN §11.9), with
-- the feel pass sound wiring values (§18.6, §18.8).
-- Shared (read by the client SoundController), data only. All [P]. Sound ids live only in AssetTable.luau.

export type Group = {
	maxVolume: number, -- groupVolume = maxVolume × slider / 100 (SoundGroup.Volume defaults to 0.5, always set)
	slider: string, -- the ProfileV1.settings key that drives this group
}

local Audio = {
	-- SoundGroups created by the client under SoundService at runtime.
	Groups = {
		Music = { maxVolume = 0.6, slider = "music" },
		SFX = { maxVolume = 1.0, slider = "sfx" },
		UI = { maxVolume = 0.8, slider = "sfx" },
		Ambient = { maxVolume = 0.5, slider = "sfx" },
	} :: { [string]: Group },

	-- When full: stop the oldest non-looping voice with a stealFadeMs fade, or drop a lower-priority new sound.
	VoiceCaps = {
		SFX = 10,
		SFXPerKey = 3,
		UI = 4,
		Ambient = 2, -- loops
		Music = 1,
		MusicDuringCrossfade = 2,
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
	},
	-- The final pitch (random variation × the play option's `pitch`) is clamped to [pitchMin, pitchMax] (§18.6).
	pitchMin = 0.5,
	pitchMax = 2,

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

	-- Toast code -> the sound key NotifyController passes to UIController.toast (§18.5.2 B5, §18.6). Keeps the only
	-- lobby-stat sound key out of the duel-path files.
	toastSounds = {
		["grip.levelUp"] = "ui.gripUnlock",
		["grip.padUnlocked"] = "ui.gripUnlock",
		["grip.rankUp"] = "ui.gripUnlock",
	},

	recentLogSize = 30, -- Studio play-attempt log (SoundController.recent, SD_DebugClient "sounds")
}

return Audio
