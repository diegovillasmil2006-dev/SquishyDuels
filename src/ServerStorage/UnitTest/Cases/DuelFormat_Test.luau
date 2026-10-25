--!strict
-- DuelFormat_Test: StarterPlayerScripts.Client.UI.DuelFormat (duel HUD texts, countdown, bars, result panel, the
-- off-screen arrow). Server only (ServerStorage.UnitTest). Pure: no instances (aimBlocked's case builds a few
-- unparented GuiObjects).
-- Contract (DESIGN §5.2, §5.4, §5.10, §9.14, §11.6):
--   * the timer counts down to phaseEndsAt in Active / SuddenDeath, shows the match length before Active, hides after;
--   * the countdown shows "3", "2", "1" and "Throw!" exactly from the Countdown's phaseEndsAt, for one tick;
--   * sides are text; a Studio test dummy is always labelled as one; lives never show below 0;
--   * key hints (foam UI: keycaps) only on mouse/keyboard and gamepad, the keys of the one-line hints; no ultimate key
--     for a loadout without an ultimate; final polish (2026-10-11): also the dash key, and the squeeze key in first
--     person, each the key its action is bound to;
--   * foam UI side colours: Strawberry / Mint unchanged; the top bar cards' light faces keep InkUI text >= 4.5:1;
--   * the cooldown bar uses the server's clamp and the sudden-death multiplier;
--   * the result panel shows rewards only from DuelResult (0 Coins with the blocked reason), and no stats or rewards
--     for cancelled / void duels;
--   * the arrow hides while the opponent is on screen and points to the screen edge otherwise (behind the camera too);
--   * feel pass (§18.5.2 B6-B7, §18.6): countdownCue gives a tick with its pitch (1.00 / 1.06 / 1.12), its bubble
--     colour and alternating tilt on 3 / 2 / 1, go on "Throw!", nil otherwise; the result title is Lemon / Lavender /
--     Sky with its jingle, DEFEAT pops softer, confetti is 18 on a win, 6 on a draw, none otherwise; the reward line
--     counts up to the paid Coins; the looks (Hit! and READY pops, countdown bubbles and "Throw!", the bubble burst,
--     result lines, the reward count and pulse, the ultimate meter drain) follow Config and are still under
--     ReducedMotion;
--   * Part 8 layout (§11.2, §11.6; base px, canvases of 667×375, 1280×720 and 1920×1080 at their UI scale, at the
--     Medium and the largest text): the top bar never covers the Forfeit button and stays on screen (centred when there
--     is room); the result panel stays inside the screen margins with its lines scrolling and its buttons pinned; the
--     panel's slide-in is Back Out and none under ReducedMotion;
--   * overlays fix (2026-10-09): the compact side cards are as wide as their lives row (side word and icon included)
--     needs, never narrower than the regular card and never so wide that the bar leaves the Forfeit button's row; the
--     forfeit dialog and the result card start under the top bar, or say they cannot (the bar then hides); the
--     reticle's state text moves in from a screen edge;
--   * foam fix 2 (2026-10-09): the side cards' need is their widest content from the texts on both layouts (so the
--     opponent's whole name fits on a PC; on phones the lives row decides and a longer name is cut); the result card
--     waits for the K.O. banner (capped); finished quests are marked; the reticles hide over a HUD button or an open
--     dialog, not over a plain HUD frame;
--   * feature 1 (2026-10-11, the charge throw and the catch): a fifth keycap, the catch's ("RMB/E" / "L1", the keys
--     Catch is bound to; nil on touch); the dock of five fits the narrowest phone canvas; "Your hands are busy." while
--     they are (throw.busy); the charge fills the pie to c and pulses only at full (1.08 ± 0.04 at 18 rad/s; still
--     under ReducedMotion); "Catch!" carries the key and pulses 0.75 ± 0.25 at 3 Hz (steady under ReducedMotion);
--   * Batch 3 (friends): the Rematch button reads "Rematch"; once pressed "Waiting…" (disabled) with the line "Waiting
--     for {name}…"; the line "{name} wants a rematch!" while only the opponent asked; both: loading with "Starting…".

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local DuelFormat = t.requireClient("UI/DuelFormat")
	local Strings = t.requireShared("Strings")
	local Config = t.requireShared("Config")
	local Catalog = t.requireShared("Catalog")
	local RULES = Config.Duel.Rules

	t.test("timer: time left while live, the match length before, hidden after", function()
		expect.equal(DuelFormat.timerText("Active", 200, 116.8, nil), "1:24")
		expect.equal(DuelFormat.timerText("SuddenDeath", 30, 30.5, nil), "0:00")
		local full = DuelFormat.timerText("Countdown", 0, 0, nil)
		expect.equal(full, DuelFormat.timerText("Preparing", 0, 0, { MatchSeconds = RULES.MatchSeconds }))
		expect.equal(DuelFormat.timerText("Positioning", 0, 0, { MatchSeconds = 90 }), "1:30")
		expect.equal(DuelFormat.timerText("Result", 10, 0, nil), nil)
		expect.equal(DuelFormat.timerText("Returning", 10, 0, nil), nil)
	end)

	t.test("countdown: 3, 2, 1, then Throw! from the end for one tick", function()
		local seconds = RULES.CountdownSeconds
		expect.equal(DuelFormat.countdown(10, 7.0, seconds), "3")
		expect.equal(DuelFormat.countdown(10, 7.5, seconds), "3")
		expect.equal(DuelFormat.countdown(10, 8.0, seconds), "2")
		expect.equal(DuelFormat.countdown(10, 9.99, seconds), "1")
		expect.equal(DuelFormat.countdown(10, 10, seconds), Strings.duel.countdownGo)
		expect.equal(DuelFormat.countdown(10, 10.9, seconds), Strings.duel.countdownGo)
		expect.equal(DuelFormat.countdown(10, 11.01, seconds), nil)
		expect.equal(DuelFormat.countdown(10, 2, 3), "3") -- never above the countdown length
	end)

	t.test("sides, names and lives", function()
		expect.equal(DuelFormat.sideText("A"), Strings.duel.sideA)
		expect.equal(DuelFormat.sideText("B"), Strings.duel.sideB)
		expect.equal(DuelFormat.nameText({ displayName = "Ann", isTestDummy = false, side = "A" }), "Ann")
		expect.equal(
			DuelFormat.nameText({ displayName = "Ann", isTestDummy = true, side = "B" }),
			Strings.duel.testDummy
		)
		expect.equal(DuelFormat.livesText(3), Strings.format(Strings.duel.lives.many, { n = 3 }))
		expect.equal(DuelFormat.livesText(1), Strings.format(Strings.duel.lives.one, { n = 1 }))
		expect.equal(DuelFormat.livesText(-1), Strings.format(Strings.duel.lives.many, { n = 0 }))
		expect.equal(DuelFormat.livesText(0 / 0), Strings.format(Strings.duel.lives.many, { n = 0 }))
	end)

	t.test("key hints (foam keycaps): mouse and gamepad only; no ultimate key without an ultimate", function()
		local function keys(preferred: string, hasUltimate: boolean, squeeze: boolean?): { any }
			local throwKey, ultimateKey, dashKey, squeezeKey, catchKey =
				DuelFormat.hintKeys(preferred, hasUltimate, squeeze)
			return { throwKey or false, ultimateKey or false, dashKey or false, squeezeKey or false, catchKey or false }
		end
		local key = Strings.duel.key
		expect.deepEqual(keys("Touch", true, true), { false, false, false, false, false })
		expect.deepEqual(keys("Touch", false), { false, false, false, false, false })
		expect.deepEqual(
			keys("KeyboardAndMouse", true, true),
			{ key.throwMouse, key.ultimateMouse, key.dashMouse, key.squeezeMouse, key.catchMouse }
		)
		expect.deepEqual(
			keys("KeyboardAndMouse", false),
			{ key.throwMouse, false, key.dashMouse, false, key.catchMouse }
		)
		expect.deepEqual(
			keys("Gamepad", true, true),
			{ key.throwGamepad, key.ultimateGamepad, key.dashGamepad, key.squeezeGamepad, key.catchGamepad }
		)
		expect.deepEqual(
			keys("Gamepad", false, false),
			{ key.throwGamepad, false, key.dashGamepad, false, key.catchGamepad }
		)
		-- The keycaps say what the one-line hints say ("Click Throw · Q Ultimate · C Dash · F Squeeze" / the gamepad's).
		local hints = {
			{
				Strings.duel.hintMouse,
				key.throwMouse,
				key.ultimateMouse,
				key.dashMouse,
				key.squeezeMouse,
				key.catchMouse,
			},
			{
				Strings.duel.hintGamepad,
				key.throwGamepad,
				key.ultimateGamepad,
				key.dashGamepad,
				key.squeezeGamepad,
				key.catchGamepad,
			},
		}
		for _, row in hints do
			local hint = row[1]
			expect.truthy(string.find(hint, row[2] .. " " .. Strings.controls.throw, 1, true) ~= nil)
			expect.truthy(string.find(hint, row[3] .. " " .. Strings.controls.ultimate, 1, true) ~= nil)
			expect.truthy(string.find(hint, row[4] .. " " .. Strings.controls.dash, 1, true) ~= nil)
			expect.truthy(string.find(hint, row[5] .. " " .. Strings.controls.squeeze, 1, true) ~= nil)
			expect.truthy(string.find(hint, row[6] .. " " .. Strings.controls.catch, 1, true) ~= nil)
		end
		for _, hint in { Strings.duel.hintMouseNoUlt, Strings.duel.hintGamepadNoUlt } do
			expect.equal(string.find(hint, Strings.controls.ultimate, 1, true), nil)
			expect.truthy(string.find(hint, Strings.controls.dash, 1, true) ~= nil)
		end
	end)

	-- Final polish (2026-10-11): a keycap is the key its action is really bound to (ControlsController's input map).
	t.test("the dash and squeeze keycaps are the keys Dash and DuelSqueeze are bound to", function()
		local Controls = t.requireClient("Controllers/ControlsController")
		local key = Strings.duel.key
		local function bound(action: string, keyCode: Enum.KeyCode): boolean
			local inputs = Controls.inputsOf(action)
			return inputs ~= nil and table.find(inputs, keyCode) ~= nil
		end
		expect.truthy(bound("Dash", (Enum.KeyCode :: any)[key.dashMouse]))
		expect.truthy(bound("Dash", (Enum.KeyCode :: any)["Button" .. key.dashGamepad]))
		expect.truthy(bound("DuelSqueeze", (Enum.KeyCode :: any)[key.squeezeMouse]))
		expect.truthy(bound("DuelSqueeze", (Enum.KeyCode :: any)["Button" .. key.squeezeGamepad]))
		-- Feature 1: "Q" (Duel HUD 2026-10-24, was "RMB/E"; the right mouse button still comes through UserInputService) and "L1".
		expect.equal(key.catchMouse, "Q")
		expect.truthy(bound("Catch", Enum.KeyCode.Q))
		expect.truthy(bound("Catch", (Enum.KeyCode :: any)["Button" .. key.catchGamepad]))
	end)

	t.test("side colours (foam cards): the side's own colour, a light card face with readable InkUI text", function()
		local Palette = t.requireShared("Art/Palette")
		local function luminance(color: Color3): number
			local function channel(c: number): number
				return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
			end
			return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
		end
		local function contrast(a: Color3, b: Color3): number
			local la, lb = luminance(a), luminance(b)
			return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
		end
		local aColor, aFace = DuelFormat.sideColors("A")
		local bColor, bFace = DuelFormat.sideColors("B")
		-- Unchanged side colours (§7.8): Strawberry side A, Mint side B; anything but "B" is A (like sideText).
		expect.equal(aColor, Palette.Strawberry)
		expect.equal(bColor, Palette.Mint)
		expect.equal(aFace, Palette.Bubblegum)
		expect.equal(bFace, Palette.MintCream)
		expect.equal((DuelFormat.sideColors("?")), Palette.Strawberry)
		expect.truthy(aFace ~= bFace)
		for _, face in { aFace, bFace } do
			-- The name, side and lives text on the card, in the UI ink (UI FINAL R1: StickerInk) and the world ink.
			expect.truthy(contrast(Palette.StickerInk, face) >= 4.5)
			expect.truthy(contrast(Palette.InkUI, face) >= 4.5)
			expect.truthy(face ~= Palette.Danger and face ~= Palette.CoinGold) -- reserved colours never mark a side
		end
	end)

	t.test("reticle: state as text, never colour alone", function()
		expect.equal(DuelFormat.reticleText({ state = "ready", readyAt = 0 }, 5), Strings.duel.reticle.ready)
		expect.equal(
			DuelFormat.reticleText({ state = "cooling", readyAt = 10.43 }, 10),
			Strings.format(Strings.common.secondsShort, { seconds = "0.4" })
		)
		expect.equal(
			DuelFormat.reticleText({ state = "cooling", readyAt = 9 }, 10),
			Strings.format(Strings.common.secondsShort, { seconds = "0.0" })
		)
		expect.equal(
			DuelFormat.reticleText({ state = "blocked", reason = "throw.rooted", readyAt = 0 }, 0),
			Strings.duel.reticle.rooted
		)
		expect.equal(
			DuelFormat.reticleText({ state = "blocked", reason = "throw.direction", readyAt = 0 }, 0),
			Strings.reason.throw.direction
		)
		expect.equal(
			DuelFormat.reticleText({ state = "blocked", reason = "throw.context", readyAt = 0 }, 0),
			Strings.duel.reticle.wrongZone
		)
		expect.equal(DuelFormat.reticleText({ state = "hidden", readyAt = 0 }, 0), nil)
		-- Feature 1: the hands open for a catch or crushing a caught toy.
		expect.equal(
			DuelFormat.reticleText({ state = "blocked", reason = "throw.busy", readyAt = 0 }, 0),
			Strings.reason.throw.busy
		)
	end)

	-- Feature 1 (2026-10-11): the reticle while charging and the catch prompt (design: html:88, 670-674).
	t.test("charge on the reticle: the pie filled to c; a pulse only at full and never under ReducedMotion", function()
		local RETICLE = Config.UI.Reticle
		local right, left, scale = DuelFormat.chargeLook(0.25, 0, false)
		local pr, pl = DuelFormat.pieRotations(0.25)
		expect.equal(right, pr)
		expect.equal(left, pl)
		expect.equal(scale, 1)
		local _, _, below = DuelFormat.chargeLook(0.99, 0.3, false)
		expect.equal(below, 1)
		local _, _, still = DuelFormat.chargeLook(1, 0, false)
		expect.near(still, RETICLE.chargeFullScale, 1e-9)
		local _, _, peak = DuelFormat.chargeLook(1, math.pi / 2 / RETICLE.chargePulseRate, false)
		expect.near(peak, RETICLE.chargeFullScale + RETICLE.chargePulse, 1e-9)
		expect.equal(RETICLE.chargeFullScale, 1.08) -- design: html:671
		expect.equal(RETICLE.chargePulse, 0.04)
		local _, _, reduced = DuelFormat.chargeLook(1, 0.3, true)
		expect.equal(reduced, 1)
		local fr, fl = DuelFormat.chargeLook(5, 0, true)
		expect.equal(fr, 180)
		expect.equal(fl, 360)
		local nr = DuelFormat.chargeLook(0 / 0, 0, false)
		expect.equal(nr, 0)
	end)

	t.test("the catch prompt: its key for the input, a 3 Hz pulse, steady under ReducedMotion", function()
		local RETICLE = Config.UI.Reticle
		local text, fade = DuelFormat.catchPrompt("RMB/E", 0, false)
		expect.equal(text, "Catch! RMB/E")
		expect.near(fade, 1 - RETICLE.catchPromptFrom, 1e-9)
		local touchText = DuelFormat.catchPrompt(nil, 0, false)
		expect.equal(touchText, Strings.duel.catchPrompt)
		local _, peak = DuelFormat.catchPrompt("L1", 1 / (4 * RETICLE.catchPromptHz), false)
		expect.near(peak, 0, 1e-9) -- fully shown at the top of the wave
		local _, low = DuelFormat.catchPrompt("L1", 3 / (4 * RETICLE.catchPromptHz), false)
		expect.near(low, 2 * (1 - RETICLE.catchPromptFrom), 1e-9)
		local _, steady = DuelFormat.catchPrompt("L1", 0.37, true)
		expect.equal(steady, 0)
		expect.truthy(RETICLE.catchPromptHz <= 3) -- the flicker limit (§9.12)
	end)

	t.test("cooldown arc: the right half fills first, then the left half", function()
		local r0, l0 = DuelFormat.pieRotations(0)
		expect.equal(r0, 0)
		expect.equal(l0, 180)
		local rq, lq = DuelFormat.pieRotations(0.25)
		expect.near(rq, 90)
		expect.equal(lq, 180)
		local rh, lh = DuelFormat.pieRotations(0.75)
		expect.equal(rh, 180)
		expect.near(lh, 270)
		local r1, l1 = DuelFormat.pieRotations(1)
		expect.equal(r1, 180)
		expect.equal(l1, 360)
		local rn, ln = DuelFormat.pieRotations(0 / 0)
		expect.equal(rn, 180)
		expect.equal(ln, 360)
		local rs, ls = DuelFormat.pieRotations(-3)
		expect.equal(rs, 0)
		expect.equal(ls, 180)
	end)

	t.test("forfeit note: cancelled before EarlyForfeitSeconds of Active, a loss after", function()
		local cancelNote =
			Strings.format(Strings.duel.forfeitCancelNote, { seconds = RULES.BailRequeueCooldownSeconds })
		expect.equal(string.find(cancelNote, "{", 1, true), nil)
		for _, phase in { "Preparing", "Positioning", "Countdown" } do
			expect.equal(DuelFormat.forfeitNote(phase, 100, 99, nil), cancelNote)
		end
		local endsAt = 1000
		local startedAt = endsAt - RULES.MatchSeconds
		local early = startedAt + RULES.EarlyForfeitSeconds - 0.5
		local late = startedAt + RULES.EarlyForfeitSeconds + 0.5
		expect.equal(DuelFormat.forfeitNote("Active", endsAt, early, nil), cancelNote)
		expect.equal(DuelFormat.forfeitNote("Active", endsAt, late, nil), Strings.duel.forfeitLoseNote)
		expect.equal(DuelFormat.forfeitNote("SuddenDeath", 50, 40, nil), Strings.duel.forfeitLoseNote)
		expect.equal(DuelFormat.forfeitNote("Result", 50, 40, nil), nil)
		expect.equal(DuelFormat.forfeitNote("Returning", 50, 40, nil), nil)
		-- The match's own rules win over Config.
		local rules = { MatchSeconds = 60, EarlyForfeitSeconds = 10, BailRequeueCooldownSeconds = 7 }
		expect.equal(
			DuelFormat.forfeitNote("Active", 100, 45, rules),
			Strings.format(Strings.duel.forfeitCancelNote, { seconds = 7 })
		)
		expect.equal(DuelFormat.forfeitNote("Active", 100, 55, rules), Strings.duel.forfeitLoseNote)
	end)

	t.test("cooldown bar: the server clamp and the sudden-death multiplier", function()
		local base = Catalog.get("kitty_bread").throw.cooldown
		local clamped = math.clamp(base, RULES.CooldownClamp.Min, RULES.CooldownClamp.Max)
		expect.near(DuelFormat.cooldownSeconds("kitty_bread", "Active", nil), clamped)
		expect.near(
			DuelFormat.cooldownSeconds("kitty_bread", "SuddenDeath", nil),
			clamped * RULES.SuddenDeathCooldownMultiplier
		)
		local rules = { CooldownClamp = { Min = 5, Max = 6 }, SuddenDeathCooldownMultiplier = 0.5 }
		expect.near(DuelFormat.cooldownSeconds("kitty_bread", "Active", rules), 5)
		expect.near(DuelFormat.cooldownSeconds("kitty_bread", "SuddenDeath", rules), 2.5)
		expect.near(DuelFormat.cooldownSeconds("not_a_squishy", "Active", nil), clamped) -- the starter's numbers

		expect.equal(DuelFormat.progress(nil, 5, 1), 1)
		expect.near(DuelFormat.progress(10, 9.5, 1), 0.5)
		expect.equal(DuelFormat.progress(10, 12, 1), 1)
		expect.equal(DuelFormat.progress(10, 5, 1), 0)
		expect.equal(DuelFormat.progress(10, 5, 0), 1)
	end)

	t.test("ultimate of a loadout and its meter", function()
		local id, ability = DuelFormat.ultimateOf("dragon")
		expect.equal(id, "dragon_rush")
		-- Compared by value: DuelFormat requires the real Shared, the test runner a clone, so the tables differ.
		expect.truthy(ability ~= nil)
		expect.equal(ability.nameKey, Config.Abilities.dragon_rush.nameKey)
		expect.equal(ability.chargeMax, Config.Abilities.dragon_rush.chargeMax)
		local none = DuelFormat.ultimateOf("kitty_bread")
		expect.equal(none, nil)
		expect.equal(DuelFormat.chargeFraction(50, 100), 0.5)
		expect.equal(DuelFormat.chargeFraction(150, 100), 1)
		expect.equal(DuelFormat.chargeFraction(10, 0), 0)
		expect.equal(DuelFormat.chargeFraction(0 / 0, 100), 0)
	end)

	t.test("result: titles, stats, reward lines from DuelResult only", function()
		local win = DuelFormat.result({
			matchId = "m1",
			outcome = "win",
			reasonKey = "duel.suddenDeath",
			coins = 200,
			stats = { throws = 4, hits = 3, accuracy = 0.75 },
			questProgress = { { questId = "q1_1", progress = 1, goal = 3, done = false } },
			tip = nil,
		})
		expect.equal(win.title, Strings.duel.result.win)
		expect.equal(win.reason, Strings.duel.suddenDeath)
		expect.equal(win.reward, Strings.format(Strings.duel.reward.win, { coins = "200" }))
		expect.equal(#win.stats, 3)
		expect.equal(win.stats[1].value, "4")
		expect.equal(win.stats[2].value, "3")
		expect.equal(win.stats[3].value, Strings.format(Strings.common.percent, { value = 75 }))
		expect.deepEqual(win.quests, { Strings.format(Strings.common.progress, { progress = 1, goal = 3 }) })

		local blocked = DuelFormat.result({
			matchId = "m2",
			outcome = "loss",
			reasonKey = "",
			coins = 0,
			coinsBlockedReason = "duel.tooShort",
			stats = { throws = 0, hits = 0, accuracy = 0 },
			questProgress = {},
			tip = "duel.lossTip",
		})
		expect.equal(blocked.title, Strings.duel.result.loss)
		expect.equal(blocked.reason, nil)
		expect.equal(
			blocked.reward,
			Strings.format(Strings.duel.rewardBlocked, { reason = Strings.reason.duel.tooShort })
		)
		expect.equal(blocked.stats[3].value, Strings.format(Strings.common.percent, { value = 0 }))
		expect.equal(blocked.tip, Strings.duel.lossTip)

		expect.equal(win.rewardNote, nil) -- a full reward has no note
		expect.equal(blocked.rewardNote, nil) -- 0 Coins: the reason is in the reward line itself

		-- A same-pair reduced reward (§6.7): the Coins line, plus the reason under it.
		local reduced = DuelFormat.result({
			matchId = "m7",
			outcome = "win",
			coins = 50,
			coinsBlockedReason = "duel.rewardsReduced",
			stats = { throws = 5, hits = 2 },
		})
		expect.equal(reduced.reward, Strings.format(Strings.duel.reward.win, { coins = "50" }))
		expect.equal(reduced.rewardNote, Strings.reason.duel.rewardsReduced)

		local noReward = DuelFormat.result({ matchId = "m3", outcome = "draw", coins = 0, stats = {} })
		expect.equal(noReward.reward, nil) -- nothing granted and no reason: no reward line at all

		local cancelled = DuelFormat.result({
			matchId = "m4",
			outcome = "cancelled",
			reasonKey = "duel.opponentLeftEarly",
			coins = 500,
			stats = { throws = 9, hits = 9 },
		})
		expect.equal(cancelled.title, Strings.duel.result.cancelled)
		expect.equal(cancelled.reason, Strings.duel.opponentLeftEarly)
		expect.equal(#cancelled.stats, 0)
		expect.equal(cancelled.reward, nil)
		expect.equal(DuelFormat.result({ matchId = "m5", outcome = "???" }).title, Strings.duel.result.void)
		-- Hits are never shown above throws.
		local odd = DuelFormat.result({ matchId = "m6", outcome = "win", stats = { throws = 2, hits = 5 } })
		expect.equal(odd.stats[2].value, "2")
	end)

	t.test("result poses: the winner cheers on both clients, a draw shrugs, nothing otherwise", function()
		local selfWin, oppWin = DuelFormat.endPoses("win")
		expect.equal(selfWin, "cheer")
		expect.equal(oppWin, nil)
		local selfLoss, oppLoss = DuelFormat.endPoses("loss")
		expect.equal(selfLoss, nil)
		expect.equal(oppLoss, "cheer")
		local selfDraw, oppDraw = DuelFormat.endPoses("draw")
		expect.equal(selfDraw, "shrug")
		expect.equal(oppDraw, "shrug")
		for _, outcome in { "cancelled", "void", "???" } do
			local a, b = DuelFormat.endPoses(outcome)
			expect.equal(a, nil)
			expect.equal(b, nil)
		end
		-- Every pose named here exists in Config.Anim.poses.
		expect.truthy(Config.Anim.poses.cheer)
		expect.truthy(Config.Anim.poses.shrug)
	end)

	t.test("result pose weight: rises, dips once per bounce, then holds at 1", function()
		local bounces = Config.Anim.duel.cheerBounces
		expect.equal((DuelFormat.endPoseWeight(0, bounces)), 0)
		expect.equal((DuelFormat.endPoseWeight(0 / 0, bounces)), 0)
		local samples, minimum, dips = 400, 1, 0
		local previous = 0
		local falling = false
		local done = false
		local t = 0
		while not done do
			t += 0.01
			local w
			w, done = DuelFormat.endPoseWeight(t, bounces)
			expect.truthy(w >= 0 and w <= 1)
			if w < previous - 1e-9 then
				falling = true
			elseif w > previous + 1e-9 and falling then
				dips += 1 -- the weight turned back up after a dip
				falling = false
			end
			if falling then
				minimum = math.min(minimum, w)
			end
			previous = w
			samples -= 1
			if samples <= 0 then
				error("the pose never settled")
			end
		end
		expect.equal(dips, bounces)
		expect.truthy(minimum < 0.7)
		local held, settled = DuelFormat.endPoseWeight(t + 10, bounces)
		expect.equal(held, 1)
		expect.equal(settled, true)
		-- The shrug (no bounce) rises and holds.
		local shrug, shrugDone = DuelFormat.endPoseWeight(1, 0)
		expect.equal(shrug, 1)
		expect.equal(shrugDone, true)
	end)

	t.test("result: quest lines name the quest when its text is known", function()
		local payload = {
			matchId = "m7",
			outcome = "loss",
			coins = 0,
			stats = { throws = 3, hits = 1 },
			questProgress = {
				{ questId = "q1_1", progress = 2, goal = 5, done = false },
				{ questId = "q1_2", progress = 1, goal = 1, done = true },
				{ questId = "q1_3", progress = 0 / 0, goal = 1, done = false }, -- malformed: skipped
			},
		}
		local named = DuelFormat.result(payload, function(questId: string): string?
			return if questId == "q1_1" then "Finish 5 duels" else nil
		end)
		expect.deepEqual(named.quests, {
			Strings.format(Strings.duel.questLine, { quest = "Finish 5 duels", progress = 2, goal = 5 }),
			Strings.format(Strings.common.progress, { progress = 1, goal = 1 }),
		})
		local plain = DuelFormat.result(payload)
		expect.equal(#plain.quests, 2)
		expect.equal(plain.quests[1], Strings.format(Strings.common.progress, { progress = 2, goal = 5 }))
	end)

	t.test("off-screen arrow: hidden on screen, on the edge otherwise", function()
		local viewport = Vector2.new(1000, 600)
		local margin = 50
		local hidden = DuelFormat.edgeArrow(Vector3.new(500, 300, 20), viewport, margin)
		expect.equal(hidden, false)

		local visible, right, rotation = DuelFormat.edgeArrow(Vector3.new(2000, 300, 20), viewport, margin)
		expect.equal(visible, true)
		expect.near(right.X, 950)
		expect.near(right.Y, 300)
		expect.near(rotation, 0)

		local _, top, up = DuelFormat.edgeArrow(Vector3.new(500, -400, 20), viewport, margin)
		expect.near(top.Y, 50)
		expect.near(up, -90)

		-- Behind the camera the projection is mirrored: a point drawn at the left really is to the right.
		local behind, pos, behindRotation = DuelFormat.edgeArrow(Vector3.new(400, 300, -5), viewport, margin)
		expect.equal(behind, true)
		expect.near(pos.X, 950)
		expect.near(behindRotation, 0)
		local straight, below = DuelFormat.edgeArrow(Vector3.new(500, 300, -5), viewport, margin)
		expect.equal(straight, true)
		expect.near(below.Y, 550)
	end)

	-- Feel pass (§18.5.2 B6-B7, §18.6) --------------------------------------------------------------------------------

	t.test("countdown cue: a tick with its pitch on 3, 2, 1, go on Throw!, nil otherwise", function()
		local Palette = t.requireShared("Art/Palette")
		local pitch = Config.Audio.countdownPitch
		local tilt = Config.Anim.duel.countdownBubble.tiltDeg
		local three = DuelFormat.countdownCue("3")
		expect.equal(three.key, "duel.countdownTick")
		expect.equal(three.pitch, pitch[1])
		expect.equal(three.digit, 3)
		expect.equal(three.bubble, Palette.Strawberry)
		expect.equal(three.tiltDeg, -tilt)
		local two = DuelFormat.countdownCue("2")
		expect.equal(two.key, "duel.countdownTick")
		expect.equal(two.pitch, pitch[2])
		expect.equal(two.bubble, Palette.Lemon)
		expect.equal(two.tiltDeg, tilt)
		local one = DuelFormat.countdownCue("1")
		expect.equal(one.pitch, pitch[3])
		expect.equal(one.bubble, Palette.Mint)
		expect.equal(one.tiltDeg, -tilt)
		expect.deepEqual({ three.pitch, two.pitch, one.pitch }, { 1.0, 1.06, 1.12 })
		local go = DuelFormat.countdownCue(Strings.duel.countdownGo)
		expect.equal(go.key, "duel.go")
		expect.equal(go.pitch, 1)
		expect.equal(go.digit, nil)
		expect.equal(go.bubble, nil)
		expect.equal(DuelFormat.countdownCue(nil), nil)
		expect.equal(DuelFormat.countdownCue(""), nil)
		expect.equal(DuelFormat.countdownCue("0"), nil)
		expect.equal(DuelFormat.countdownCue("1.5"), nil)
		expect.equal(DuelFormat.countdownCue("Go"), nil)
		-- A longer countdown's earlier digits tick at the first pitch, Strawberry.
		local five = DuelFormat.countdownCue("5")
		expect.equal(five.pitch, pitch[1])
		expect.equal(five.bubble, Palette.Strawberry)
		-- Every cue the real countdown produces has a cue.
		local seconds = RULES.CountdownSeconds
		for now = 7.0, 10.5, 0.25 do
			local text = DuelFormat.countdown(10, now, seconds)
			expect.truthy(DuelFormat.countdownCue(text) ~= nil)
		end
	end)

	t.test("result style: title colours, a softer defeat pop, jingles and confetti counts", function()
		local Palette = t.requireShared("Art/Palette")
		local anim = Config.Anim.duel
		local win = DuelFormat.resultStyle("win")
		expect.equal(win.color, Palette.Lemon)
		expect.equal(win.jingle, "duel.win")
		expect.equal(win.confetti, anim.confetti.pieces)
		expect.equal(win.popFrom, anim.countdownPopFrom)
		local loss = DuelFormat.resultStyle("loss")
		expect.equal(loss.color, Palette.Lavender)
		expect.equal(loss.jingle, "duel.lose")
		expect.equal(loss.confetti, 0)
		expect.equal(loss.popFrom, anim.result.defeatPopFrom)
		expect.truthy(loss.popFrom < win.popFrom) -- DEFEAT pops softer, never mocking
		local draw = DuelFormat.resultStyle("draw")
		expect.equal(draw.color, Palette.Sky)
		expect.equal(draw.jingle, "duel.draw")
		expect.equal(draw.confetti, anim.confetti.drawPieces)
		for _, outcome in { "cancelled", "void", "???" } do
			local style = DuelFormat.resultStyle(outcome)
			expect.equal(style.color, nil)
			expect.equal(style.jingle, nil)
			expect.equal(style.confetti, 0)
		end
		-- Nothing red on a title.
		for _, style in { win, loss, draw } do
			expect.truthy(style.color ~= Palette.Danger)
		end
	end)

	t.test("reward line: counts up from +0 to the paid Coins", function()
		expect.equal(DuelFormat.rewardText("win", 0), Strings.format(Strings.duel.reward.win, { coins = "0" }))
		expect.equal(DuelFormat.rewardText("loss", 49.6), Strings.format(Strings.duel.reward.loss, { coins = "50" }))
		expect.equal(DuelFormat.rewardText("cancelled", 10), nil)
		local paid = DuelFormat.result({ matchId = "m8", outcome = "draw", coins = 120, stats = {} })
		expect.equal(paid.rewardCoins, 120)
		expect.equal(paid.reward, DuelFormat.rewardText("draw", 120))
		local blocked =
			DuelFormat.result({ matchId = "m9", outcome = "win", coins = 0, coinsBlockedReason = "duel.tooShort" })
		expect.equal(blocked.rewardCoins, nil) -- a blocked line never counts
	end)

	t.test(
		"pops: Hit! 1.3 -> 1 in 200 ms with ±6° -> 0, READY 1.3 -> 1 in 220 ms, nothing under ReducedMotion",
		function()
			local hit = Config.Vfx.Hit
			local ready = Config.UI.motion.readyPop
			local s0, r0, d0 = DuelFormat.hitTextPop(0, 1, false)
			expect.near(s0, hit.hitTextPopFrom, 1e-9)
			expect.near(r0, hit.hitTextTiltDeg, 1e-9)
			expect.falsy(d0)
			local _, left = DuelFormat.hitTextPop(0, -1, false)
			expect.near(left, -hit.hitTextTiltDeg, 1e-9) -- the other way on the next hit
			local sEnd, rEnd, dEnd = DuelFormat.hitTextPop(hit.hitTextPopMs / 1000, 1, false)
			expect.equal(sEnd, 1)
			expect.equal(rEnd, 0)
			expect.truthy(dEnd)
			local sMid = DuelFormat.hitTextPop(hit.hitTextPopMs / 2000, 1, false)
			expect.truthy(sMid < hit.hitTextPopFrom)
			local sReduced, rReduced, dReduced = DuelFormat.hitTextPop(0, 1, true)
			expect.equal(sReduced, 1)
			expect.equal(rReduced, 0)
			expect.truthy(dReduced)
			expect.equal(DuelFormat.readyPop(0, false), ready.from)
			expect.equal(DuelFormat.readyPop(ready.ms / 1000, false), 1)
			local _, readyTilt = DuelFormat.readyPop(0.05, false)
			expect.equal(readyTilt, 0)
			expect.equal(DuelFormat.readyPop(0, true), 1)
		end
	)

	t.test("countdown look: digits pop with their bubble and tilt; Throw! pops, holds, grows and fades", function()
		local anim = Config.Anim.duel
		local bubble = anim.countdownBubble
		local go = anim.go
		local three = DuelFormat.countdownCue("3")
		local start = DuelFormat.countdownLook(0, three, false)
		expect.near(start.textScale, anim.countdownPopFrom, 1e-9)
		expect.near(start.bubbleScale, bubble.popFrom, 1e-9)
		expect.near(start.rotation, -bubble.tiltDeg, 1e-9)
		expect.equal(start.bubbleTransparency, bubble.transparency)
		expect.equal(start.textTransparency, 0)
		local settled = DuelFormat.countdownLook(anim.countdownPopMs / 1000, three, false)
		expect.equal(settled.textScale, 1)
		expect.equal(settled.bubbleScale, 1)
		expect.equal(settled.rotation, 0)
		expect.truthy(settled.done)
		-- ReducedMotion: full size, no tilt, a short fade in.
		local calm = DuelFormat.countdownLook(0, three, true)
		expect.equal(calm.textScale, 1)
		expect.equal(calm.bubbleScale, 1)
		expect.equal(calm.rotation, 0)
		expect.equal(calm.textTransparency, 1)
		local shown = DuelFormat.countdownLook(Config.UI.motion.reducedMotionMaxFadeMs / 1000, three, true)
		expect.equal(shown.textTransparency, 0)
		expect.near(shown.bubbleTransparency, bubble.transparency, 1e-9)
		-- "Throw!": no bubble; 1.6 -> 1, held, then 1 -> 1.15 while fading; gone after pop + hold + out.
		local cue = DuelFormat.countdownCue(Strings.duel.countdownGo)
		local first = DuelFormat.countdownLook(0, cue, false)
		expect.near(first.textScale, go.popFrom, 1e-9)
		expect.equal(first.bubbleTransparency, 1)
		local holding = DuelFormat.countdownLook((go.popMs + go.holdMs / 2) / 1000, cue, false)
		expect.equal(holding.textScale, 1)
		expect.equal(holding.textTransparency, 0)
		local fading = DuelFormat.countdownLook((go.popMs + go.holdMs + go.outMs / 2) / 1000, cue, false)
		expect.truthy(fading.textScale > 1 and fading.textScale < go.outScale)
		expect.near(fading.textTransparency, 0.5, 1e-6)
		expect.falsy(fading.done)
		local gone = DuelFormat.countdownLook((go.popMs + go.holdMs + go.outMs) / 1000, cue, false)
		expect.truthy(gone.done)
		expect.equal(gone.textTransparency, 1)
		-- ReducedMotion: never scaled; the fade out is capped.
		for ms = 0, 1200, 50 do
			local look = DuelFormat.countdownLook(ms / 1000, cue, true)
			expect.equal(look.textScale, 1)
		end
		local maxFade = Config.UI.motion.reducedMotionMaxFadeMs
		expect.truthy(DuelFormat.countdownLook((go.popMs + go.holdMs + maxFade) / 1000, cue, true).done)
	end)

	t.test("countdown burst: the old bubble grows to 1.25 while fading out in 120 ms", function()
		local bubble = Config.Anim.duel.countdownBubble
		local s0, t0, d0 = DuelFormat.burstLook(0, false)
		expect.equal(s0, 1)
		expect.near(t0, bubble.transparency, 1e-9)
		expect.falsy(d0)
		local sMid, tMid = DuelFormat.burstLook(bubble.burstMs / 2000, false)
		expect.truthy(sMid > 1 and sMid < bubble.burstScale)
		expect.truthy(tMid > bubble.transparency and tMid < 1)
		local sEnd, tEnd, dEnd = DuelFormat.burstLook(bubble.burstMs / 1000, false)
		expect.equal(sEnd, bubble.burstScale)
		expect.equal(tEnd, 1)
		expect.truthy(dEnd)
		local sCalm = DuelFormat.burstLook(bubble.burstMs / 2000, true)
		expect.equal(sCalm, 1)
	end)

	t.test("result lines fade in and slide up 10 px in 120 ms; the reward counts up, then pulses", function()
		local result = Config.Anim.duel.result
		local tBefore, slideBefore, doneBefore = DuelFormat.lineLook(-0.1, false)
		expect.equal(tBefore, 1)
		expect.equal(slideBefore, result.lineSlidePx)
		expect.falsy(doneBefore)
		local tMid, slideMid = DuelFormat.lineLook(result.lineMs / 2000, false)
		expect.truthy(tMid > 0 and tMid < 1)
		expect.truthy(slideMid > 0 and slideMid < result.lineSlidePx)
		local tEnd, slideEnd, doneEnd = DuelFormat.lineLook(result.lineMs / 1000, false)
		expect.equal(tEnd, 0)
		expect.equal(slideEnd, 0)
		expect.truthy(doneEnd)
		local _, slideCalm = DuelFormat.lineLook(-1, true)
		expect.equal(slideCalm, 0) -- no slide under ReducedMotion
		-- The reward: 0 -> coins over 600 ms (Quad Out), the number at once under ReducedMotion.
		expect.equal(DuelFormat.rewardCount(0, 120, false), 0)
		local mid, midDone = DuelFormat.rewardCount(result.rewardCountMs / 2000, 120, false)
		expect.truthy(mid > 60 and mid < 120) -- Quad Out is past half way at half time
		expect.falsy(midDone)
		local final, finalDone = DuelFormat.rewardCount(result.rewardCountMs / 1000, 120, false)
		expect.equal(final, 120)
		expect.truthy(finalDone)
		local now, nowDone = DuelFormat.rewardCount(0, 120, true)
		expect.equal(now, 120)
		expect.truthy(nowDone)
		-- The pulse: 1 -> 1.12 -> 1 over 200 ms, never past the peak by more than the Back overshoot.
		local peak = 1
		for ms = 0, result.rewardPulseMs, 5 do
			peak = math.max(peak, (DuelFormat.rewardPulse(ms / 1000, false)))
		end
		expect.near(peak, result.rewardPulseScale, 0.01)
		local last, lastDone = DuelFormat.rewardPulse(result.rewardPulseMs / 1000, false)
		expect.equal(last, 1)
		expect.truthy(lastDone)
		expect.equal(DuelFormat.rewardPulse(0.05, true), 1)
	end)

	t.test("ultimate meter: a spent charge drains over meterDrainMs", function()
		local ms = Config.Vfx.DragonRush.meterDrainMs
		expect.equal(ms, 300)
		local v0, d0 = DuelFormat.meterDrain(1, 0, 0)
		expect.equal(v0, 1)
		expect.falsy(d0)
		local vMid = DuelFormat.meterDrain(1, 0, ms / 2000)
		expect.truthy(vMid > 0 and vMid < 1)
		local vEnd, dEnd = DuelFormat.meterDrain(1, 0, ms / 1000)
		expect.equal(vEnd, 0)
		expect.truthy(dEnd)
		-- Monotonic: a drain never goes back up.
		local last = 1
		for i = 1, 30 do
			local v = DuelFormat.meterDrain(1, 0.25, i / 100)
			expect.truthy(v <= last + 1e-9 and v >= 0.25 - 1e-9)
			last = v
		end
	end)

	-- Part 8 layout ---------------------------------------------------------------------------------------------------

	local Layout = t.requireClient("UI/Layout")
	local UI = Config.UI
	local LARGEST = UI.PreferredTextScale.Largest
	-- The three screens of §13.1 as SD_DuelHud canvases (base px = actual px / UI scale).
	local SCREENS = { Vector2.new(667, 375), Vector2.new(1280, 720), Vector2.new(1920, 1080) }
	local function canvas(actual: Vector2): Vector2
		return actual / Layout.uiScale(actual.Y)
	end
	-- Text width estimate (base px): about 0.55 em per character, generous for FredokaOne / Builder Sans.
	local function textWidth(chars: number, kind: string, textScale: number): number
		return chars * 0.55 * UI.TextSize[kind] * textScale
	end
	-- Foam UI: DuelController's side cards (SIDE_WIDTH, padding included), the bar's gap (Theme.Padding.medium), the
	-- timer pill (TIMER_MIN_WIDTH, padding Theme.Padding.medium). The bar is about 135 base px tall at Medium text: a
	-- side card (padding, name, side row, lives row) and the opponent's Dragon Rush chip under theirs.
	local SIDE_WIDTH, BAR_GAP, PANEL_PADDING, TIMER_MIN_WIDTH = 220, 12, 12, 96
	local function barSize(textScale: number): Vector2
		local timer = math.max(TIMER_MIN_WIDTH, textWidth(4, "HudNumber", textScale) + 2 * PANEL_PADDING) -- "1:30"
		return Vector2.new(2 * SIDE_WIDTH + 2 * BAR_GAP + timer, 135 * textScale)
	end
	local function forfeitRect(textScale: number): any
		-- Duel_ForfeitButton at (12, 12): "Forfeit" + 2 × 18 px padding, Config.UI.Touch.closeButton tall.
		return { x = 12, y = 12, w = textWidth(7, "Button", textScale) + 36, h = UI.Touch.closeButton }
	end
	local function overlaps(a: any, b: any): boolean
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end

	-- Final polish (2026-10-11): the bottom dock (mouse / gamepad only) with the dash and squeeze keys. DuelController:
	-- two meters METER_WIDTH 150 wide, then two caption-only columns (a Keycap of at least Keycap.SIZE_PX 24, growing
	-- with its text by 2 × 5 px, Theme.Padding.small 6, the Chip caption), Theme.Padding.large 20 apart inside the
	-- panel's Theme.Padding.medium 12. A phone with a keyboard or a gamepad has the narrowest canvas. Feature 1
	-- (2026-10-11): a third meter, the catch's, between the throw and the ultimate.
	t.test("bottom dock (feature 1): the five keys fit the narrowest phone canvas at the largest text", function()
		local METER_WIDTH, KEYCAP, SMALL, LARGE, PANEL, MARGIN = 150, 24, 6, 20, 12, 12
		local key = Strings.duel.key
		local phone = canvas(SCREENS[1])
		for _, textScale in { 1, LARGEST } do
			local function keycap(text: string): number
				return math.max(KEYCAP, textWidth(#text, "Chip", textScale) + 10)
			end
			for _, keys in { { key.dashMouse, key.squeezeMouse }, { key.dashGamepad, key.squeezeGamepad } } do
				local dash = keycap(keys[1]) + SMALL + textWidth(#Strings.controls.dash, "Chip", textScale)
				local squeeze = keycap(keys[2]) + SMALL + textWidth(#Strings.controls.squeeze, "Chip", textScale)
				local dock = 2 * PANEL + 3 * METER_WIDTH + dash + squeeze + 4 * LARGE
				expect.truthy(dock <= phone.X - 2 * MARGIN)
			end
			-- The meters' own captions still fit their 150 px ("L2" + "Ultimate", "RMB/E" + "Catch" the widest).
			local ultimate = keycap(key.ultimateGamepad)
				+ SMALL
				+ textWidth(#Strings.controls.ultimate, "Chip", textScale)
			expect.truthy(ultimate <= METER_WIDTH)
			local catch = keycap(key.catchMouse) + SMALL + textWidth(#Strings.controls.catch, "Chip", textScale)
			expect.truthy(catch <= METER_WIDTH)
		end
	end)

	t.test("top bar (Part 8): never over the Forfeit button, on screen, centred when there is room", function()
		for _, actual in SCREENS do
			for _, textScale in { 1, LARGEST } do
				local screen = canvas(actual)
				local bar = barSize(textScale)
				local avoid = forfeitRect(textScale)
				local place = DuelFormat.topBarPlacement(screen, bar, avoid)
				local width = math.ceil(bar.X / 16) * 16
				local rect = { x = place.x - width / 2, y = place.y, w = width, h = bar.Y }
				expect.equal(place.fits, true)
				expect.falsy(overlaps(rect, avoid))
				expect.truthy(rect.x >= 12 - 1e-6 and rect.x + rect.w <= screen.X - 12 + 1e-6)
				expect.equal(place.row, "top")
				if actual.X >= 1280 then
					expect.near(place.x, screen.X / 2, 1e-6) -- room to spare: exactly centred
				end
			end
		end
		-- 667×375 at Medium text: the centred bar would reach under the button, so it moves right just enough.
		local phone = canvas(SCREENS[1])
		local bar = barSize(1)
		local avoid = forfeitRect(1)
		local width = math.ceil(bar.X / 16) * 16
		expect.truthy(phone.X / 2 - width / 2 < avoid.x + avoid.w + 8) -- the centred bar would overlap
		local moved = DuelFormat.topBarPlacement(phone, bar, avoid)
		expect.near(moved.x - width / 2, avoid.x + avoid.w + 8, 1e-6)
	end)

	t.test("top bar (Part 8): under the button when the row is too narrow; centred with nothing to clear", function()
		local phone = canvas(SCREENS[1])
		local avoid = forfeitRect(LARGEST)
		local wide = Vector2.new(phone.X - 100, 120)
		local place = DuelFormat.topBarPlacement(phone, wide, avoid)
		expect.equal(place.row, "below")
		expect.equal(place.fits, true)
		expect.near(place.y, avoid.y + avoid.h + 8, 1e-6)
		local width = math.ceil(wide.X / 16) * 16
		expect.truthy(place.x - width / 2 >= 12 - 1e-6 and place.x + width / 2 <= phone.X - 12 + 1e-6)
		-- Wider than the screen: centred, fits = false.
		local huge = DuelFormat.topBarPlacement(phone, Vector2.new(phone.X + 50, 120), avoid)
		expect.equal(huge.fits, false)
		expect.near(huge.x, phone.X / 2, 1e-6)
		-- No button (Result: it hides) or an empty rect: centred on the top row.
		local free = DuelFormat.topBarPlacement(phone, barSize(1), nil)
		expect.near(free.x, phone.X / 2, 1e-6)
		expect.equal(free.y, 12)
		local empty = DuelFormat.topBarPlacement(phone, barSize(1), { x = 12, y = 12, w = 0, h = 0 })
		expect.near(empty.x, phone.X / 2, 1e-6)
		-- The width counts in 16 px steps: a digit that changes the bar by a few px does not move it.
		local a = DuelFormat.topBarPlacement(phone, Vector2.new(561, 100), avoid)
		local b = DuelFormat.topBarPlacement(phone, Vector2.new(566, 100), avoid)
		expect.equal(a.x, b.x)
	end)

	t.test("result panel (Part 8): lines scroll, the pinned buttons stay in view, the panel stays on screen", function()
		local margin = 12
		for _, actual in SCREENS do
			for _, textScale in { 1, LARGEST } do
				local screen = canvas(actual)
				-- Chrome: the panel's paddings (2 × 20) + the pinned row (6 px gap + a 56 px primary button).
				local chrome = 40 + 6 + UI.Touch.primaryButton
				-- A loss with the tip, 3 quest lines and the reward note at this text size (about 560 base px at
				-- Medium), and a much taller one.
				for _, content in { 560 * textScale, 2000 } do
					local fit = DuelFormat.resultLayout(screen.Y, content, chrome)
					expect.truthy(fit.panelHeight <= screen.Y - 2 * margin + 1e-6)
					expect.truthy(fit.centerY - fit.panelHeight / 2 >= margin - 1e-6)
					expect.truthy(fit.centerY + fit.panelHeight / 2 <= screen.Y - margin + 1e-6)
					expect.truthy(fit.bodyHeight >= UI.Touch.minTarget)
					expect.equal(fit.scrolls, content > fit.bodyHeight)
					expect.near(fit.panelHeight, fit.bodyHeight + chrome, 1e-6)
				end
				-- A short card fits whole, centred 55% down (as built).
				local short = DuelFormat.resultLayout(screen.Y, 200, chrome)
				expect.equal(short.scrolls, false)
				expect.equal(short.bodyHeight, 200)
				expect.near(short.centerY, screen.Y * 0.55, 1e-6)
			end
		end
		-- On the phone the tall card scrolls (it did run off the screen before).
		local phone = canvas(SCREENS[1])
		expect.truthy(DuelFormat.resultLayout(phone.Y, 560 * LARGEST, 102).scrolls)
		-- Bad numbers never break it.
		local bad = DuelFormat.resultLayout(0 / 0, math.huge, -5)
		expect.truthy(bad.bodyHeight == bad.bodyHeight and bad.centerY == bad.centerY)
	end)

	t.test(
		"result panel slide (Part 8): 40 px -> 0 with Back Out over resultBannerMs; none under ReducedMotion",
		function()
			local ms = Config.Anim.duel.resultBannerMs
			local start, startDone = DuelFormat.slideLook(0, 40, ms, false)
			expect.equal(start, 40)
			expect.falsy(startDone)
			local mid = DuelFormat.slideLook(ms / 2000, 40, ms, false)
			expect.truthy(mid < 40)
			local finish, done = DuelFormat.slideLook(ms / 1000, 40, ms, false)
			expect.equal(finish, 0)
			expect.truthy(done)
			local reduced, reducedDone = DuelFormat.slideLook(0, 40, ms, true)
			expect.equal(reduced, 0)
			expect.truthy(reducedDone)
		end
	)

	t.test("countdown (Part 8): 40% down when there is room, else under the top bar, never off the screen", function()
		local box = math.max(150, Config.Anim.duel.countdownBubble.px) -- DuelController COUNTDOWN_BOX.Y / bubble
		for _, actual in SCREENS do
			for _, textScale in { 1, LARGEST } do
				local screen = canvas(actual)
				local bar = barSize(textScale)
				local place = DuelFormat.topBarPlacement(screen, bar, forfeitRect(textScale))
				local barBottom = place.y + bar.Y
				local centre = DuelFormat.countdownCenterY(screen.Y, barBottom, box)
				expect.truthy(centre >= screen.Y * 0.4 - 1e-6) -- never higher than as built
				expect.truthy(centre - box / 2 >= barBottom + 8 - 1e-6) -- the bubble clears the bar
				expect.truthy(centre + box / 2 <= screen.Y - 12 + 1e-6) -- and stays on the screen
				if actual.Y >= 720 then
					expect.near(centre, screen.Y * 0.4, 1e-6) -- room to spare: exactly as built
				end
			end
		end
		-- The phone at the largest text: lower than 40% (the 150 px bubble reached the lives row).
		local phone = canvas(SCREENS[1])
		local bar = barSize(LARGEST)
		expect.truthy(DuelFormat.countdownCenterY(phone.Y, 12 + bar.Y, box) > phone.Y * 0.4 + 1)
		-- A bar so tall the box cannot clear it: the box stays on screen (the bar is left behind it, as before).
		local low = DuelFormat.countdownCenterY(phone.Y, phone.Y - 20, box)
		expect.near(low, phone.Y - 12 - box / 2, 1e-6)
		-- Bad numbers fall back to 40% down.
		expect.near(DuelFormat.countdownCenterY(phone.Y, 0 / 0, box), phone.Y * 0.4, 1e-6)
	end)

	-- Overlays fix (2026-10-09) ------------------------------------------------------------------------------------

	t.test("side cards (overlays fix): compact cards fit their lives row, stay beside the Forfeit button", function()
		local phone = canvas(SCREENS[1]) -- 667×375: about 785 base wide
		local avoid = forfeitRect(1)
		local timer = barSize(1).X - 2 * SIDE_WIDTH - 2 * BAR_GAP
		local function width(need: number, button: any?): number
			return DuelFormat.sideCardWidth({
				screenWidth = phone.X,
				need = need,
				minWidth = SIDE_WIDTH,
				middle = timer,
				gap = BAR_GAP,
				avoid = button,
			})
		end
		-- A lives row with the side word and icon (about 244 base px with the paddings): wide enough, in 8 px steps.
		expect.equal(width(244, avoid), 248)
		-- A short row never makes the card narrower than the regular one; bad numbers neither.
		expect.equal(width(100, avoid), SIDE_WIDTH)
		expect.equal(width(0 / 0, avoid), SIDE_WIDTH)
		-- A very wide row (the largest text) is capped: the bar still fits on the top row beside the button.
		local capped = width(400, avoid)
		expect.truthy(capped >= SIDE_WIDTH and capped < 400)
		local bar = Vector2.new(2 * capped + timer + 2 * BAR_GAP, 80)
		local place = DuelFormat.topBarPlacement(phone, bar, avoid)
		expect.equal(place.row, "top")
		local barWidth = math.ceil(bar.X / 16) * 16
		expect.falsy(overlaps({ x = place.x - barWidth / 2, y = place.y, w = barWidth, h = bar.Y }, avoid))
		expect.truthy(place.x + barWidth / 2 <= phone.X - 12 + 1e-6)
		-- Without the button (the Result phase) the cap is wider.
		expect.truthy(width(400, nil) > capped)
	end)

	t.test("forfeit dialog (overlays fix): centred, or under the top bar; the bar hides when it cannot fit", function()
		local phone = canvas(SCREENS[1]) -- about 441 base tall
		local h, panel, overhang = phone.Y, 190, 20
		-- No bar: centred as built.
		local free, freeClears = DuelFormat.panelBelowBar(h, nil, panel, overhang, 0.5)
		expect.near(free, h / 2, 1e-6)
		expect.equal(freeClears, true)
		-- A short bar that already ends above it: still centred.
		local short, shortClears = DuelFormat.panelBelowBar(h, 90, panel, overhang, 0.5)
		expect.near(short, h / 2, 1e-6)
		expect.equal(shortClears, true)
		-- A taller bar: its header tab starts 8 under the bar.
		local low, lowClears = DuelFormat.panelBelowBar(h, 130, panel, overhang, 0.5)
		expect.near(low - panel / 2 - overhang, 130 + 8, 1e-6)
		expect.equal(lowClears, true)
		-- No room between the bar and the bottom margin: placed as without a bar, clearsBar false.
		local crowded, crowdedClears = DuelFormat.panelBelowBar(h, 260, panel, overhang, 0.5)
		expect.near(crowded, h / 2, 1e-6)
		expect.equal(crowdedClears, false)
		-- Taller than the screen: centred; it clears a bar only when there is none.
		local tall, tallClears = DuelFormat.panelBelowBar(h, 90, 500, overhang, 0.5)
		expect.near(tall, h / 2, 1e-6)
		expect.equal(tallClears, false)
		local _, noBarClears = DuelFormat.panelBelowBar(h, nil, 500, overhang, 0.5)
		expect.equal(noBarClears, true)
	end)

	t.test(
		"result card (overlays fix): under the top bar when its lines fit there whole, else clearsBar false",
		function()
			local phone = canvas(SCREENS[1])
			local chrome, content = 84, 220
			-- A compact bar ending at 90: the card starts 8 under it, nothing scrolls.
			local under = DuelFormat.resultLayout(phone.Y, content, chrome, 90)
			expect.equal(under.clearsBar, true)
			expect.equal(under.scrolls, false)
			expect.truthy(under.centerY - under.panelHeight / 2 >= 98 - 1e-6)
			expect.truthy(under.centerY + under.panelHeight / 2 <= phone.Y - 12 + 1e-6)
			-- A bar ending at 150: the lines would not fit under it; placed as without a bar (the caller hides the bar).
			local crowded = DuelFormat.resultLayout(phone.Y, content, chrome, 150)
			local none = DuelFormat.resultLayout(phone.Y, content, chrome)
			expect.equal(crowded.clearsBar, false)
			expect.equal(none.clearsBar, true)
			expect.near(crowded.centerY, none.centerY, 1e-6)
			expect.near(crowded.bodyHeight, none.bodyHeight, 1e-6)
			-- On a PC the card always starts under the bar.
			local pc = canvas(SCREENS[3])
			local pcFit = DuelFormat.resultLayout(pc.Y, 560, chrome, 12 + 135)
			expect.equal(pcFit.clearsBar, true)
			expect.truthy(pcFit.centerY - pcFit.panelHeight / 2 >= 12 + 135 + 8 - 1e-6)
			-- A bad bar bottom counts as no bar.
			expect.equal(DuelFormat.resultLayout(phone.Y, content, chrome, 0 / 0).clearsBar, true)
		end
	)

	t.test("reticle text (overlays fix): centred under the reticle, moved in from a screen edge", function()
		-- 1920 px wide at UI scale 1.25, a 180 base px text, 12 base px from the edges.
		expect.equal(DuelFormat.reticleLabelOffset(960, 180, 1920, 1.25, 12), 0)
		local right = DuelFormat.reticleLabelOffset(1900, 180, 1920, 1.25, 12)
		expect.near(right, -86, 1e-6)
		expect.near(1900 + right * 1.25 + 180 * 1.25 / 2, 1920 - 12 * 1.25, 1e-6) -- its right edge 12 base px in
		expect.near(DuelFormat.reticleLabelOffset(10, 180, 1920, 1.25, 12), 94, 1e-6)
		-- Wider than the screen: centred on the screen.
		expect.near(DuelFormat.reticleLabelOffset(50, 180, 200, 1.25, 12), 40, 1e-6)
		-- Bad numbers: no offset.
		expect.equal(DuelFormat.reticleLabelOffset(0 / 0, 180, 1920, 1.25, 12), 0)
		expect.equal(DuelFormat.reticleLabelOffset(1900, 180, 1920, 0, 12), 0)
	end)

	-- Foam fix 2 (2026-10-09) ------------------------------------------------------------------------------------------

	t.test("side cards (foam fix 2): the need is the widest content, from the texts, on both layouts", function()
		-- Base px: the name's one-line width, the side word, "N lives", the pips row, the icon, the row gap and the
		-- card's padding; 2 px spare so a rounded measure never cuts a text.
		local function need(compact: boolean, name: number): number
			return DuelFormat.sideNeed({
				compact = compact,
				name = name,
				word = 110,
				lives = 50,
				pips = 80,
				icon = 22,
				gap = 6,
				padding = 12,
			})
		end
		-- Compact (phones): the lives row holds the pips, "N lives", the icon and the side word on one line.
		expect.near(need(true, 120), 80 + 50 + 22 + 110 + 3 * 6 + 2 * 12 + 2, 1e-6)
		-- A longer name than that row is cut with "…" instead of widening both phone cards.
		expect.near(need(true, 300), 80 + 50 + 22 + 110 + 3 * 6 + 2 * 12 + 2, 1e-6)
		-- Regular (PC): the side word wraps beside its icon as built, so the name or the pips with "N lives" decide.
		expect.near(need(false, 230), 230 + 2 * 12 + 2, 1e-6)
		expect.near(need(false, 40), 80 + 6 + 50 + 2 * 12 + 2, 1e-6)
		-- Bad numbers count as nothing.
		expect.near(need(false, 0 / 0), 80 + 6 + 50 + 2 * 12 + 2, 1e-6)
	end)

	t.test(
		"side cards (foam fix 2): on a PC the opponent's whole name fits; a short one keeps the regular card",
		function()
			local pc = canvas(SCREENS[3])
			local timer = barSize(1).X - 2 * SIDE_WIDTH - 2 * BAR_GAP
			local function width(need: number): number
				return DuelFormat.sideCardWidth({
					screenWidth = pc.X,
					need = need,
					minWidth = SIDE_WIDTH,
					middle = timer,
					gap = BAR_GAP,
					avoid = forfeitRect(1),
				})
			end
			-- "TEST DUMMY (Studio)" in H2 (about 230 base px) missed the 220 card by about 6 px: now the card holds it.
			local name = 230
			local card = width(DuelFormat.sideNeed({
				compact = false,
				name = name,
				word = 110,
				lives = 50,
				pips = 80,
				icon = 22,
				gap = 6,
				padding = 12,
			}))
			expect.truthy(card - 2 * 12 >= name)
			expect.equal(card % 8, 0)
			-- "You" and a short name: the regular 220 card, as built.
			expect.equal(
				width(DuelFormat.sideNeed({
					compact = false,
					name = 40,
					word = 110,
					lives = 50,
					pips = 80,
					icon = 22,
					gap = 6,
					padding = 12,
				})),
				SIDE_WIDTH
			)
		end
	)

	t.test("result card (foam fix 2): waits for the K.O. banner to end, never longer than the cap", function()
		expect.equal(DuelFormat.resultWait(0, 10, 1.5), 0) -- no banner
		expect.near(DuelFormat.resultWait(11.2, 10, 1.5), 1.2, 1e-9)
		expect.equal(DuelFormat.resultWait(9, 10, 1.5), 0) -- already gone
		expect.equal(DuelFormat.resultWait(100, 10, 1.5), 1.5) -- capped
		expect.equal(DuelFormat.resultWait(0 / 0, 10, 1.5), 0)
		expect.equal(DuelFormat.resultWait(math.huge, 10, 1.5), 0)
	end)

	t.test("result (foam fix 2): the quests this duel finished are marked", function()
		local model = DuelFormat.result({
			matchId = "m8",
			outcome = "win",
			coins = 200,
			stats = { throws = 4, hits = 3 },
			questProgress = {
				{ questId = "q1_1", progress = 3, goal = 12, done = false },
				{ questId = "q1_2", progress = 1, goal = 1, done = true },
				{ questId = "q1_3", progress = 0 / 0, goal = 1, done = true }, -- malformed: skipped
			},
		})
		expect.equal(#model.quests, 2)
		expect.deepEqual(model.questDone, { false, true })
		expect.deepEqual(DuelFormat.result({ matchId = "m9", outcome = "cancelled" }).questDone, {})
	end)

	t.test("reticle (foam fix 2): hidden over a HUD button or an open dialog, not over a plain HUD frame", function()
		-- The GuiObjects PlayerGui:GetGuiObjectsAtPosition finds at the aim point.
		local reticle: GuiObject = Instance.new("Frame") -- the reticle's own pieces: not Active
		local card: GuiObject = Instance.new("Frame") -- a HUD panel that is no button (the top bar's side cards)
		local backdrop: GuiObject = Instance.new("Frame") -- an invisible catcher: Active, fully transparent
		backdrop.Active = true
		backdrop.BackgroundTransparency = 1
		local dialog: GuiObject = Instance.new("Frame") -- the forfeit dialog: an Active panel
		dialog.Active = true
		local button: GuiObject = Instance.new("TextButton")
		local hidden: GuiObject = Instance.new("TextButton")
		hidden.Visible = false
		expect.equal(DuelFormat.aimBlocked({}), false)
		expect.equal(DuelFormat.aimBlocked({ reticle, card, backdrop, hidden }), false)
		expect.equal(DuelFormat.aimBlocked({ reticle, card, button }), true)
		expect.equal(DuelFormat.aimBlocked({ dialog }), true)
		expect.equal(DuelFormat.aimBlocked({ Instance.new("ImageButton") }), true)
		expect.equal(DuelFormat.aimBlocked({ Instance.new("TextBox") }), true)
	end)

	t.test("phases: forfeit from Preparing to SuddenDeath; live in Active and SuddenDeath", function()
		for _, phase in { "Preparing", "Positioning", "Countdown", "Active", "SuddenDeath" } do
			expect.equal(DuelFormat.forfeitAllowed(phase), true)
		end
		for _, phase in { "Result", "Returning", "Cancelled", "Void" } do
			expect.equal(DuelFormat.forfeitAllowed(phase), false)
		end
		expect.equal(DuelFormat.isLive("Active"), true)
		expect.equal(DuelFormat.isLive("SuddenDeath"), true)
		expect.equal(DuelFormat.isLive("Countdown"), false)
	end)

	t.test(
		"rematchView: Rematch, the opponent's ask, waiting once pressed, starting once both pressed (Batch 3)",
		function()
			local view = DuelFormat.rematchView
			expect.deepEqual(view(false, false, "Ana"), { text = "Rematch", state = "normal" })
			expect.deepEqual(
				view(false, true, "Ana"),
				{ text = "Rematch", line = "Ana wants a rematch!", state = "normal" }
			)
			-- The button stays short (any name length); the name goes on the line, which wraps.
			expect.deepEqual(
				view(true, false, "Ana"),
				{ text = "Waiting…", line = "Waiting for Ana…", state = "disabled" }
			)
			expect.deepEqual(view(true, true, "Ana"), { text = "Rematch", line = "Starting…", state = "loading" })
			expect.equal(view(true, false, string.rep("W", 20)).text, "Waiting…")
		end
	)
end
