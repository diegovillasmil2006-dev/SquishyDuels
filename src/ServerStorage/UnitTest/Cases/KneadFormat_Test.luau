--!strict
-- KneadFormat_Test: unit tests for StarterPlayerScripts.Client.UI.KneadFormat, what the knead screen's HUD, panel rows,
-- caption, vignette and fingertip ring show (spec phase2-squeeze §1.18-§1.20, §3.7, §3.14). Server only
-- (ServerStorage.UnitTest). Pure. Contract (design: the FP page fp.js:700-701, html:59-77):
--   * the state word: Crunchy above 0.7, Crackled above 0.4, else Soft (strictly above);
--   * the bar: round(waxLeft·100) %, clamped to 0..1; the count: digit grouping and "1 crack" / "{n} cracks";
--   * the panel rows: "Squeeze: <b>{feel label}.</b> {note}" and "Coat: <b>{coat label}.</b> {note}" (unknown = foam);
--   * the caption: the touch, gamepad or keyboard help line;
--   * the wax switch (user 2026-10-12; nil = Config.Wax.enabled): off, no Coat row, the help lines without crunch or
--     re-wax words (helpNoWax) and the thumb button reads Thumb press; on, Coat, the wax help and Thumb crunch;
--   * the vignette: the CSS radial gradient (125% 95% at 50% 45%) with premultiplied stops: clear in the middle and at
--     the side edges' middle, about 0.017 at the top centre, 0.07 at the bottom centre, 0.09 at the top corners and
--     0.15 at the bottom corners in about rgb(153, 113, 84); its RGBA8 pixels follow it;
--   * the ring: hidden, 40 px over the toy, 28 px at 40% white pressing, 20 px solid stretching.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local KneadFormat = t.requireClient("UI/KneadFormat")
	local Strings = t.requireShared("Strings")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local K = Strings.knead

	t.test("the state word: Crunchy above 0.7, Crackled above 0.4, else Soft", function()
		expect.equal(KneadFormat.stateKey(1), "crunchy")
		expect.equal(KneadFormat.stateKey(0.71), "crunchy")
		expect.equal(KneadFormat.stateKey(0.7), "crackled")
		expect.equal(KneadFormat.stateKey(0.41), "crackled")
		expect.equal(KneadFormat.stateKey(0.4), "soft")
		expect.equal(KneadFormat.stateKey(0), "soft")
		expect.equal(KneadFormat.stateKey(0 / 0), "soft")
	end)

	t.test("the HUD: the bar to the whole percent, the state word and the crack count", function()
		local hud = KneadFormat.hud(0.876, 0.8, 1234)
		expect.near(hud.fill, 0.88, 1e-12)
		expect.equal(hud.state, K.state.crunchy)
		expect.equal(hud.count, "1,234 cracks")
		expect.equal(KneadFormat.hud(1, 1, 0).count, "0 cracks")
		expect.equal(KneadFormat.hud(1, 1, 1).count, "1 crack")
		expect.equal(KneadFormat.hud(1.4, 0.5, 2).fill, 1)
		expect.equal(KneadFormat.hud(-0.2, 0.2, 2).fill, 0)
		expect.equal(KneadFormat.hud(0.5, 0.5, 2).state, K.state.crackled)
		expect.equal(KneadFormat.hud(0.5, 0.1, 2).state, K.state.soft)
	end)

	t.test("the panel rows: the feel and the coat, bold labels; an unknown feel is foam", function()
		local rows = KneadFormat.rows("mochi", true)
		expect.equal(rows.squeeze, `{K.squeezeRow}: <b>{K.feel.mochi.label}.</b> {K.feel.mochi.note}`)
		expect.equal(rows.coat, `{K.coatRow}: <b>{K.coat.mochi.label}.</b> {K.coat.mochi.note}`)
		expect.deepEqual(KneadFormat.rows("no_such_feel", true), KneadFormat.rows("foam", true))
		for feel in Config.Anim.rig.feels do
			local each = KneadFormat.rows(feel, true)
			-- Rich text: the notes carry no markup of their own.
			for _, text in { K.feel[feel].note, K.coat[feel].note, K.feel[feel].label, K.coat[feel].label } do
				expect.falsy(string.find(text, "[<>&]"))
			end
			expect.truthy(#each.squeeze > 0 and #(each.coat :: string) > 0)
		end
	end)

	t.test("the caption: the help line for touch, gamepad, else the keyboard's", function()
		expect.equal(KneadFormat.help("Touch", true), K.help.touch)
		expect.equal(KneadFormat.help("Gamepad", true), K.help.gamepad)
		expect.equal(KneadFormat.help("KeyboardAndMouse", true), K.help.keyboard)
		expect.equal(KneadFormat.help(nil, true), K.help.keyboard)
	end)

	-- User 2026-10-12: the wax crunch off (Config.Wax.enabled false): no Coat row, press wording, no re-wax.
	t.test("the wax off: no Coat row, the help without crunch or re-wax, the thumb button reads Thumb press", function()
		local rows = KneadFormat.rows("mochi", false)
		expect.equal(rows.squeeze, KneadFormat.rows("mochi", true).squeeze)
		expect.equal(rows.coat, nil)
		expect.equal(KneadFormat.help("Touch", false), K.helpNoWax.touch)
		expect.equal(KneadFormat.help("Gamepad", false), K.helpNoWax.gamepad)
		expect.equal(KneadFormat.help("KeyboardAndMouse", false), K.helpNoWax.keyboard)
		expect.equal(KneadFormat.help(nil, false), K.helpNoWax.keyboard)
		for _, line in { K.helpNoWax.keyboard, K.helpNoWax.touch, K.helpNoWax.gamepad } do
			local lower = string.lower(line)
			expect.falsy(string.find(lower, "crunch", 1, true))
			expect.falsy(string.find(lower, "wax", 1, true))
			expect.truthy(string.find(lower, "press", 1, true) ~= nil) -- the thumbs press
		end
		expect.truthy(string.find(K.helpNoWax.touch, K.thumbPress, 1, true) ~= nil) -- it names the button
		expect.equal(KneadFormat.thumb(false), K.thumbPress)
		expect.equal(K.thumbPress, "Thumb press")
		expect.equal(KneadFormat.thumb(true), K.thumbCrunch)
		-- nil follows the switch.
		local on = Config.Wax.enabled
		expect.equal(KneadFormat.rows("foam").coat ~= nil, on)
		expect.equal(KneadFormat.help("Touch"), if on then K.help.touch else K.helpNoWax.touch)
		expect.equal(KneadFormat.thumb(), if on then K.thumbCrunch else K.thumbPress)
	end)

	t.test("the vignette: the CSS radial gradient's alphas at the edges and corners", function()
		local _, middle = KneadFormat.vignette(0.5, 0.45)
		expect.equal(middle, 0)
		local _, side = KneadFormat.vignette(0, 0.45)
		expect.equal(side, 0)
		local _, top = KneadFormat.vignette(0.5, 0)
		expect.near(top, 0.017, 0.001)
		local _, bottom = KneadFormat.vignette(0.5, 1)
		expect.near(bottom, 0.07, 0.001)
		local _, topCorner = KneadFormat.vignette(0, 0)
		expect.near(topCorner, 0.09, 0.001)
		local color, bottomCorner = KneadFormat.vignette(1, 1)
		expect.near(bottomCorner, 0.153, 0.001)
		expect.near(color.R * 255, 153, 1)
		expect.near(color.G * 255, 113, 1)
		expect.near(color.B * 255, 84, 1)
		-- The warm stop's colour where only it and the clear stop mix (premultiplied: the colour stays the stop's).
		local warm = KneadFormat.vignette(0.5, 0)
		expect.near(warm.R * 255, 255, 1)
		expect.near(warm.G * 255, 190, 1)
		expect.near(warm.B * 255, 120, 1)
	end)

	t.test("the vignette's RGBA8 pixels follow the gradient (row 0 at the top)", function()
		local n = 16
		local pixels = KneadFormat.vignettePixels(n)
		expect.equal(buffer.len(pixels), n * n * 4)
		local function alphaAt(x: number, y: number): number
			return buffer.readu8(pixels, (y * n + x) * 4 + 3) / 255
		end
		local _, expected = KneadFormat.vignette((n - 0.5) / n, (n - 0.5) / n)
		expect.near(alphaAt(n - 1, n - 1), expected, 1 / 255)
		expect.equal(alphaAt(n // 2, n // 2), 0)
		expect.truthy(alphaAt(n // 2, n - 1) > alphaAt(n // 2, 0)) -- heavier at the bottom
	end)

	t.test("the ring: hidden, over the toy, pressing, stretching", function()
		local ui = Config.UI.Knead
		expect.deepEqual(KneadFormat.ring("hidden"), { visible = false, px = ui.ringPx, transparency = 1 })
		expect.deepEqual(KneadFormat.ring("over"), { visible = true, px = ui.ringPx, transparency = 1 })
		expect.deepEqual(
			KneadFormat.ring("press"),
			{ visible = true, px = ui.ringPressPx, transparency = ui.ringPressTransparency }
		)
		expect.deepEqual(KneadFormat.ring("pull"), { visible = true, px = ui.ringPullPx, transparency = 0 })
	end)
end
