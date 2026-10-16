--!strict
-- SettingsFormat_Test: StarterPlayerScripts.Client.UI.SettingsFormat (the Settings screen's values). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §11.6, §2.8 SetSettings, §3.2):
--   * the player sees the server's settings (defaults filled in) with local edits on top;
--   * SetSettings carries only the keys that differ from the server's value (all four when the server sent none),
--     at most the 4 known keys, volumes as integers 0-100; nothing to send = an empty table;
--   * a volume reads "40%";
--   * foam UI (2026-10-09): the panel (with its header tab and Close above it) stays within 86% of the screen height
--     at 667×375, 1280×720 and 1920×1080, Medium and the largest text; on PC at Medium nothing scrolls.
--   * foam fix round 2 (2026-10-09): the "No music yet" / "No sound effects yet" notes show only while nothing is
--     approved and never on the compact layout, so on 844×390 and 667×375 phones the switches field's top shows under
--     the volumes (before, the fold fell exactly between the two fields and nothing hinted at more).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local SettingsFormat = t.requireClient("UI/SettingsFormat")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local DEFAULTS = Config.Data.DefaultSettings

	local server = { music = 40, sfx = 70, cameraShake = true, showTips = true }

	t.test("keys: exactly the four SetSettings keys", function()
		expect.deepEqual(SettingsFormat.KEYS, { "music", "sfx", "cameraShake", "showTips" })
	end)

	-- First-person spec 2026-10-10 §3.8: "First-person duels" is a session switch, never saved, so a Camera shake change
	-- made in the same visit is never lost to a patch Validate.settings would refuse whole.
	t.test("the first-person switch is never a saved setting: merge and patch never carry it", function()
		local edits: any = { cameraShake = false, firstPerson = false }
		local merged: any = SettingsFormat.merge(server :: any, edits)
		expect.equal(merged.firstPerson, nil)
		local patch: any = SettingsFormat.patch(server :: any, edits)
		expect.deepEqual(patch, { cameraShake = false })
	end)

	t.test("merge: server values with defaults filled in, local edits on top", function()
		expect.deepEqual(SettingsFormat.merge(nil, {}), {
			music = DEFAULTS.music,
			sfx = DEFAULTS.sfx,
			cameraShake = DEFAULTS.cameraShake,
			showTips = DEFAULTS.showTips,
		})
		expect.deepEqual(
			SettingsFormat.merge(server :: any, { music = 15, cameraShake = false }),
			{ music = 15, sfx = 70, cameraShake = false, showTips = true }
		)
		-- Bad edits and bad server values are ignored; volumes are clamped integers.
		local merged = SettingsFormat.merge({ music = "loud", sfx = 250, cameraShake = 1 } :: any, {
			showTips = "yes",
			music = 33.4,
		})
		expect.deepEqual(merged, {
			music = 33,
			sfx = Config.Data.settingsMax,
			cameraShake = DEFAULTS.cameraShake,
			showTips = DEFAULTS.showTips,
		})
	end)

	t.test("patch: only the keys that differ; everything when the server sent nothing", function()
		local same = SettingsFormat.patch(server :: any, table.clone(server) :: any)
		expect.equal(SettingsFormat.isEmpty(same), true)
		local one = SettingsFormat.patch(server :: any, { music = 55, sfx = 70, cameraShake = true, showTips = true })
		expect.deepEqual(one, { music = 55 })
		local two = SettingsFormat.patch(server :: any, { music = 40, sfx = 70, cameraShake = false, showTips = false })
		expect.deepEqual(two, { cameraShake = false, showTips = false })
		local all = SettingsFormat.patch(nil, server :: any)
		expect.deepEqual(all, server)
		local count = 0
		for key in all do
			count += 1
			expect.truthy(table.find(SettingsFormat.KEYS, key))
		end
		expect.truthy(count <= 4)
		-- Volumes leave as integers inside 0-100.
		local rounded =
			SettingsFormat.patch(server :: any, { music = 99.6, sfx = -3, cameraShake = true, showTips = true })
		expect.deepEqual(rounded, { music = 100, sfx = Config.Data.settingsMin })
	end)

	t.test("volume and its text", function()
		expect.equal(SettingsFormat.volume(41.5), 42)
		expect.equal(SettingsFormat.volume(0 / 0), Config.Data.settingsMin)
		expect.equal(SettingsFormat.volume(500), Config.Data.settingsMax)
		expect.equal(SettingsFormat.volumeText(40), Strings.format(Strings.common.percent, { value = 40 }))
		expect.equal(SettingsFormat.same(server :: any, table.clone(server) :: any), true)
		expect.equal(
			SettingsFormat.same(server :: any, { music = 41, sfx = 70, cameraShake = true, showTips = true } :: any),
			false
		)
		expect.equal(SettingsFormat.same(nil, nil), true)
		expect.equal(SettingsFormat.same(server :: any, nil), false)
	end)

	t.test("layout (foam UI): the panel stays within 86% of the screen; the rows scroll on a phone only", function()
		local Layout = t.requireClient("UI/Layout")
		local UI = Config.UI
		local SHARE = 0.86 -- SettingsController.MAX_HEIGHT_SHARE
		local MIN = UI.Touch.minTarget
		for _, actual in { Vector2.new(667, 375), Vector2.new(1280, 720), Vector2.new(1920, 1080) } do
			local screen = actual / Layout.uiScale(actual.Y)
			for _, textScale in { 1, UI.PreferredTextScale.Largest } do
				-- The header tab (an H2 line, 2 × 4 px padding and its 2 + 5 + 3 px bands) and Close hang half above
				-- the panel; the top padding leaves room for their lower halves (+ 6 px), the bottom padding is 20.
				local tab = 1.25 * UI.TextSize.H2 * textScale + 18
				local above = math.max(tab, UI.Touch.closeButton) / 2
				local top = math.max(math.ceil(UI.Touch.closeButton / 2), math.ceil(tab / 2)) + 6
				local chrome = above + top + 20
				-- The volumes field (12 px padding; per slider: its label line, the 52 px track, the caption line,
				-- 2 px gaps; 12 between them), the switches field (two 52 px rows), Replay (UI FINAL R2, P1: its 56 px
				-- face + the 5 px lip), 12 px between the
				-- three and the body's 3 px paddings.
				local slider = 1.25 * UI.TextSize.Body * textScale + 2 + MIN + 2 + 1.25 * UI.TextSize.Small * textScale
				local volumes = 24 + 2 * slider + 12
				local switches = 24 + 2 * MIN + 12
				local content = volumes + switches + UI.Touch.primaryButton + UI.Sticker.lip.button + 2 * 12 + 6
				local body = SettingsFormat.bodyHeight(screen.Y, content, chrome, SHARE, MIN)
				expect.truthy(body + chrome <= screen.Y * SHARE + 1e-6)
				expect.truthy(body >= MIN)
				expect.truthy(body <= content + 1e-6)
				if actual.Y >= 720 and textScale == 1 then
					expect.equal(body, content) -- PC at the default text: every row shows, nothing scrolls
				end
				if actual.Y == 375 then
					expect.truthy(body < content) -- a phone scrolls
				end
			end
		end
		expect.equal(SettingsFormat.bodyHeight(864, 180, 100, SHARE, MIN), 180)
		expect.equal(SettingsFormat.bodyHeight(441, 10, 100, SHARE, MIN), MIN)
		expect.equal(SettingsFormat.bodyHeight(0 / 0, 0 / 0, 0 / 0, SHARE, MIN), MIN)
	end)

	-- Foam fix round 2 (2026-10-09) ------------------------------------------------------------------------------------

	t.test("captionShown: the no-sound note shows while nothing is approved, never on the compact layout", function()
		expect.equal(SettingsFormat.captionShown("regular", false), true)
		expect.equal(SettingsFormat.captionShown("regular", true), false)
		expect.equal(SettingsFormat.captionShown("compact", false), false)
		expect.equal(SettingsFormat.captionShown("compact", true), false)
	end)

	t.test("phones: without the notes the switches field shows its top under the volumes (it reads as more)", function()
		local Layout = t.requireClient("UI/Layout")
		local UI = Config.UI
		local MIN = UI.Touch.minTarget
		-- SD_Modal on the two phones as measured in the foam shots (the safe area under the top bar), Medium text. The
		-- chrome and the fields as in the test above, the volumes without their caption lines.
		for _, actual in { Vector2.new(844, 312), Vector2.new(667, 297) } do
			expect.equal(Layout.layoutClass(actual.X, actual.Y), "compact")
			local screen = actual / Layout.uiScale(actual.Y)
			local tab = 1.25 * UI.TextSize.H2 + 18
			local above = math.max(tab, UI.Touch.closeButton) / 2
			local top = math.max(math.ceil(UI.Touch.closeButton / 2), math.ceil(tab / 2)) + 6
			local chrome = above + top + 20
			local slider = 1.25 * UI.TextSize.Body + 2 + MIN
			local volumes = 24 + 2 * slider + 12
			local switches = 24 + 2 * MIN + 12
			local content = volumes + switches + UI.Touch.primaryButton + UI.Sticker.lip.button + 2 * 12 + 6
			local body = SettingsFormat.bodyHeight(screen.Y, content, chrome, 0.86, MIN)
			local switchesTop = 3 + volumes + 12
			-- At least the field's padding and a slice of "Camera shake" show above the fold.
			expect.truthy(body - switchesTop >= 16)
			expect.truthy(body < content) -- it still scrolls (the rail shows on touch)
		end
	end)
end
