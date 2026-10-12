--!strict
-- SoundControllerWax_Test: unit tests for StarterPlayerScripts.Client.Controllers.SoundController's rules for the
-- knead's wax crunch (spec phase2-squeeze §3.9). Server only (ServerStorage.UnitTest). The pure rules only. Contract:
--   * "Wax" is a group a play may choose (resolveGroup), on the SFX slider at its own maxVolume;
--   * the wax keys have no cooldown and no pitch variation (their speeds are KneadAudio's);
--   * the Wax group holds VoiceCaps.Wax voices with no per-key cap: one more steals the oldest one-shot, never a loop.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local SoundController = t.requireClient("Controllers/SoundController")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local AUDIO = Config.Audio

	t.test("the Wax group: chosen by a play's group option, on the SFX slider", function()
		expect.equal(SoundController.resolveGroup("SFX", "Wax"), "Wax")
		expect.equal(AUDIO.Groups.Wax.slider, "sfx")
		local settings = { music = 100, sfx = 50 } :: any
		expect.near(SoundController.groupVolume("Wax", settings), AUDIO.Groups.Wax.maxVolume * 0.5, 1e-12)
	end)

	t.test("the wax keys: no cooldown, no pitch variation", function()
		for _, key in { "sfx.wax.foam", "sfx.wax.haze.jelly", "sfx.wax.thump", "sfx.wax.rewax" } do
			expect.equal(SoundController.cooldownSeconds(key), 0)
			expect.equal(SoundController.pitchVariance(key, "Wax"), 0)
		end
	end)

	t.test("the Wax voices: VoiceCaps.Wax of one key, then the oldest one-shot goes, never a loop", function()
		local cap = AUDIO.VoiceCaps.Wax
		local playing = {}
		for i = 1, cap - 2 do
			table.insert(playing, { group = "Wax", key = "sfx.wax.foam", startedAt = i, looped = false, priority = 0 })
		end
		table.insert(playing, { group = "Wax", key = "sfx.wax.haze.foam", startedAt = 0, looped = true, priority = 0 })
		table.insert(playing, { group = "Wax", key = "sfx.wax.body.foam", startedAt = 0, looped = true, priority = 0 })
		local allowed, victim = SoundController.admit(
			playing,
			"Wax",
			"sfx.wax.foam",
			0,
			AUDIO.VoiceCaps :: any,
			false,
			AUDIO.perKeyCap :: any
		)
		expect.truthy(allowed)
		expect.equal(victim, 1) -- the oldest burst, not a bed
		-- One less: room, no steal (no per-key cap in the Wax group).
		table.remove(playing, 1)
		local roomy, none = SoundController.admit(
			playing,
			"Wax",
			"sfx.wax.foam",
			0,
			AUDIO.VoiceCaps :: any,
			false,
			AUDIO.perKeyCap :: any
		)
		expect.truthy(roomy)
		expect.equal(none, nil)
	end)
end
