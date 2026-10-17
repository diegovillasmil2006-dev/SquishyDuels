--!strict
-- Config.UI: layout tokens, breakpoints, touch sizes, text sizes, ScreenGuis and UI motion (DESIGN §11.1-§11.6,
-- §5.10, §9.13). Shared (read by client UI code), data only. All [P]. Colours are in Art/Palette, rarity styles in
-- Art/RarityStyle, fonts in UI/Theme.

export type Tween = {
	ms: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
}
export type ScreenGuiSpec = { displayOrder: number, insets: Enum.ScreenInsets }
-- UI FINAL R1 (Sticker): a design surface's inset highlight and bevel; a text role; a component variant's numbers.
export type StickerSurface = { highlightPx: number, highlightAlpha: number, bevelPx: number?, bevelAlpha: number? }
export type StickerTextRole = {
	kind: string,
	stroke: number,
	drop: number?,
	color: string?,
	soft: { px: number, alpha: number, color: string? }?, -- UI FINAL R2 (T5): a soft text drop
}
export type StickerVariant = { [string]: number }
-- UI FINAL R2: one frame of a motion `frames` track (Anim/Tweens.Pose): at 0..1; base px, a non-uniform scale
-- (sx, sy), a scale, degrees, opacity.
export type MotionPose = {
	at: number,
	x: number?,
	y: number?,
	sx: number?,
	sy: number?,
	scale: number?,
	rot: number?,
	alpha: number?,
}

local UI = {
	-- UIScale = clamp(min(SD_Hud.AbsoluteSize.X / referenceWidth, AbsoluteSize.Y / referenceHeight), min, max),
	-- recomputed on size change. UI FINAL R2 (PR1, decided 2026-10-15): the design's fit min(w / 1440, h / 810)
	-- (H:624, its 1440 x 810 canvas H:73) inside the game's floor and cap.
	Scale = { referenceWidth = 1440, referenceHeight = 810, min = 0.85, max = 1.25 },

	-- Layout class "compact" if AbsoluteSize.Y < compactBelowHeight or X < compactBelowWidth, else "regular".
	Breakpoints = { compactBelowHeight = 500, compactBelowWidth = 700 },

	modalMaxWidth = 1100, -- px at scale 1
	modalStackMax = 2, -- e.g. Inspect over Squishies, Shop or Boxes

	-- Touch targets in base px (×UIScale) (§11.2, §5.10).
	Touch = {
		minTarget = 52, -- base minimum ...
		minTargetFloor = 44, -- ... never below this after scaling
		primaryButton = 56,
		closeButton = 52,
		throwButton = 104, -- duel Throw ...
		throwButtonMin = 72, -- ... never below this actual size
		ultButton = 80, -- above-left of Throw
		-- Spec phase 5 (user decision 2026-10-11): the Dash button, a third round button in the cluster, left of Throw
		-- (ControlsController.touchLayout). Reading: the Ultimate button's size.
		dashButton = 80,
		-- Feature 1 (2026-10-11): the Catch button, a fourth round button in the duel cluster (the design is a mouse page:
		-- RMB / E, html:88); build choice 2026-10-11 (NOT IN DESIGN): the Ultimate button's size, above Throw
		-- (ControlsController.touchLayout keeps it clear of the thumbstick zone, Jump and the other buttons).
		catchButton = 80,
		-- Final polish (2026-10-11), build choice (NOT IN DESIGN for touch; the design's own page has an "Inspect R" button
		-- in its bottom bar): the first-person Inspect button sits this far above the bottom of the safe area, in the
		-- middle (Anim/ViewmodelMath.inspectButtonRect keeps it clear of the touch controls).
		inspectButtonInset = 16,
		gap = 16, -- from the thumbstick zone and the jump button
		thumbstickZoneWidth = 0.4, -- lower-left 40% × 45% kept clear on phones
		thumbstickZoneHeight = 0.45,
	},

	-- Base text sizes in px; nothing below `minimum` after scaling. TextScaled only for the countdown.
	TextSize = {
		Title = 30,
		H2 = 22,
		Body = 18,
		Small = 16,
		Button = 20, -- bold
		HudNumber = 26,
		Countdown = 96,
		-- Foam UI (spec 2026-10-09): the display font at chip size, for chips, count badges, keycaps and tile labels.
		Chip = 16,
		-- UI FINAL (R1; plan §1.2: 1 design px = 1 base px, every kind at least 16 so 16 × Scale.min stays readable):
		-- the design's larger sizes ("Squishy Duels HUD.dc.html" lines).
		Big = 24, -- H:370 CLAIM / GO, H:462 CANCEL, H:498 AGAIN
		Large = 28, -- H:245 EQUIP, H:415 the Day 7 box
		Coin = 32, -- H:79 the coin number
		Name = 34, -- H:227 the detail name, H:459 the confirm title
		Found = 36, -- H:151 MATCH FOUND!
		Ribbon = 38, -- H:527 the level-up ribbon letters
		Hero = 40, -- H:95 the Grip level, H:483 the box name on the open stage
		WindowSmall = 44, -- H:429 the Settings title
		Duel = 48, -- H:130 DUEL
		Window = 50, -- H:184 the window titles
		Prize = 52, -- H:545 the congrats item title
		Reveal = 64, -- H:490 the reveal name
		Congrats = 82, -- H:539 the CONGRATULATIONS letters
		-- UI FINAL R2 (PR2, decided 2026-10-15): the design's 17, 19 and 23 kept exact (each >= 16, so checkUI's
		-- 13 / Scale.min floor allows them; R1 rounded them to 18 / 20 / 22).
		D17 = 17, -- H:131, H:151, H:324, H:495
		D19 = 19, -- H:159, H:162, H:278, H:369, H:390, H:546
		D23 = 23, -- H:101-119 the nav labels
		Open = 27, -- UI FINAL R7 (T12): H:277 OPEN
	} :: { [string]: number },
	minTextSize = 13,

	-- GuiService.PreferredTextSize multiplier, keyed by Enum.PreferredTextSize item names.
	PreferredTextScale = {
		Medium = 1.0,
		Large = 1.15,
		Larger = 1.3,
		Largest = 1.45,
	} :: { [string]: number },

	-- Created by client code with ResetOnSpawn = false and ZIndexBehavior = Sibling (§11.1).
	ScreenGuis = {
		SD_Hud = { displayOrder = 10, insets = Enum.ScreenInsets.CoreUISafeInsets },
		SD_DuelHud = { displayOrder = 11, insets = Enum.ScreenInsets.CoreUISafeInsets },
		SD_KillBanner = { displayOrder = 15, insets = Enum.ScreenInsets.CoreUISafeInsets }, -- under every modal
		SD_Dimmer = { displayOrder = 19, insets = Enum.ScreenInsets.None },
		SD_Modal = { displayOrder = 20, insets = Enum.ScreenInsets.CoreUISafeInsets },
		SD_Overlay = { displayOrder = 30, insets = Enum.ScreenInsets.CoreUISafeInsets },
		SD_Fade = { displayOrder = 40, insets = Enum.ScreenInsets.None },
	} :: { [string]: ScreenGuiSpec },

	-- UI motion and button states (§9.13, with the feel pass values of §18.5.2 / §18.8; UI FINAL R2: the design's
	-- motion, plan work/ui/PLAN.md §2 and R2; `H:n` = "Squishy Duels HUD.dc.html" line n, `lib:n` = uploads/hud-lib.js
	-- line n). Under ReducedMotion scale effects are off and fades <= reducedMotionMaxFadeMs. A `frames` list is a
	-- design @keyframes as poses (Anim/Tweens.Pose: { at = 0..1, x, y = base px, sx, sy, scale, rot = degrees, alpha };
	-- a frame names only what it moves) that Anim/Tweens.keyframes plays on an inner holder; `curve` names a
	-- Config.UI.curves entry (the design's cubic-bezier, played exactly by Anim/Tweens.bezier). R3 (windows), R5
	-- (cards) and R9 (toasts) switch to the tracks; `style` / `direction` stay the TweenService fallback today's code
	-- reads until then.
	motion = {
		-- UI FINAL R2: the design's sdPop (H:25, .5 s, H:181), without its fade and tilt (plan §1.4 RL3); the scrim's
		-- sdFade .25 s (H:178). UI FINAL R3: UIController plays `frames` on the window (its UIScale and its rise),
		-- each segment eased `curve`; the scrim fades in over backdropMs on backdropCurve; the wash between two stacked
		-- windows is the Backdrop colour at dimmerTransparency. `style` / `direction` stay the banner's one-tween pop.
		modalOpen = {
			ms = 500, -- H:181
			style = Enum.EasingStyle.Back,
			direction = Enum.EasingDirection.Out,
			curve = "windows", -- H:181
			scaleFrom = 0.55, -- H:25
			overshoot = 1.035, -- H:25 (60%)
			dimmerTransparency = 0.5, -- the Backdrop colour 1 -> 0.5
			backdropMs = 250, -- H:178
			backdropCurve = "ease", -- H:178: sdFade .25s ease
			-- H:25. CSS scale(...) translateY(...): the move is inside the scale, so 40 px at .55 moves 22 px and -4 px
			-- at 1.035 moves -4.
			frames = {
				{ at = 0, scale = 0.55, y = 22 },
				{ at = 0.6, scale = 1.035, y = -4 },
				{ at = 0.8, scale = 0.99 },
				{ at = 1, scale = 1, y = 0 },
			} :: { MotionPose },
		},
		-- The logical close is immediate; visually the root stays visualMs while UIScale goes 1 -> scaleTo (§18.5.2 B4).
		-- UI FINAL R2: the design's close (H:683-690): 190 ms to .82 and 20 px lower, cubic-bezier(.5,0,.75,0)
		-- (`curve`), the scrim fading out with it; no fade of the window (plan §1.4 RL3). UI FINAL R3: UIController
		-- plays `frames` over visualMs with `curve` on the whole run (a Web Animations easing, H:686) and hides the
		-- window at removeMs (H:689); the scrim fades out over ms on `curve`. `style` / `direction` stay the wash's
		-- TweenService fade (the wash is not in the design).
		modalClose = {
			ms = 190, -- H:686 (the backdrop)
			style = Enum.EasingStyle.Quart,
			direction = Enum.EasingDirection.In,
			curve = "close", -- H:686
			scaleTo = 0.82, -- H:687
			visualMs = 190, -- H:686
			removeMs = 185, -- H:689: the window goes 5 ms before its animation ends
			-- H:687 scale(.82) translateY(24px): the move is inside the scale, 24 x .82 = 20 px.
			frames = { { at = 0, scale = 1, y = 0 }, { at = 1, scale = 0.82, y = 20 } } :: { MotionPose },
		},
		-- Collectible cards pop in one after another the first time a grid fills (and when a tab or filter shows a new
		-- set): staggerMs apart, each scaleFrom -> 1 over ms. UI FINAL R2: the design's sdRise (H:31: 18 px lower, .9,
		-- clear; .42 s cubic-bezier(.2,1.3,.4,1), H:203) on the card's inner holder (R5), i x 28 ms apart with no cap
		-- (H:934, plan T9: maxStaggerMs is math.huge, kept as a field for UiFx.cascade's default).
		cardIn = {
			staggerMs = 28, -- H:934
			maxStaggerMs = math.huge, -- T9: no cap
			ms = 420, -- H:203
			scaleFrom = 0.9, -- H:31
			curve = "rise", -- H:203
			-- H:31
			frames = {
				{ at = 0, y = 18, scale = 0.9, alpha = 0 },
				{ at = 1, y = 0, scale = 1, alpha = 1 },
			} :: { MotionPose },
		},
		-- UI overhaul: a tab's content settles in (never the whole panel): scaleFrom -> 1 over ms.
		tabSettle = { ms = 140, scaleFrom = 0.97 },
		tabSwitch = { ms = 120, slidePx = 12 },
		-- §18.5.2 B5: a UIScale pop popFrom -> 1 (Back Out, ms) with the slide; a re-armed toast nudges nudgeScale -> 1.
		-- UI FINAL R2: the design's sdToast (H:33, 2.9 s `ease`, per keyframe): in from 30 px up at .8 over its first
		-- 10% (to 5 px down at 1.04, at rest by 16%), out 16 px up at .95 over its last 14%; gone after 2.9 s (H:175,
		-- H:661), at most 3 (H:660). `frames` spans lifeMs (UI FINAL R9: UIController plays them on every toast; a
		-- re-armed toast goes back to its rest at 16%). Also the duel toast's time (DuelController reads
		-- autoDismissSeconds); popFrom also times the coach card's pop (OnboardingController).
		toast = {
			ms = 290, -- H:33: 10% of 2.9 s
			slidePx = 30, -- H:33
			autoDismissSeconds = 2.9, -- H:661
			maxStacked = 3, -- H:660
			popFrom = 0.8, -- H:33
			nudgeScale = 1.06,
			nudgeMs = 160,
			lifeMs = 2900, -- H:175
			curve = "ease", -- H:175
			frames = { -- H:33
				{ at = 0, y = -30, scale = 0.8, alpha = 0 },
				{ at = 0.1, y = 5, scale = 1.04, alpha = 1 },
				{ at = 0.16, y = 0, scale = 1 },
				{ at = 0.86, y = 0, scale = 1, alpha = 1 },
				{ at = 1, y = -16, scale = 0.95, alpha = 0 },
			} :: { MotionPose },
		},
		-- UI FINAL R9 (G9.1, H:67, H:162, H:739): the quest-complete pop's sdQPop, 2.8 s `ease` per keyframe: in from
		-- 30 px right at .7 (to 6 px left at 1.05 by 12%, at rest by 20%), out 20 px right over its last 18%.
		qpop = {
			lifeMs = 2800, -- H:162, H:739
			curve = "ease", -- H:162
			frames = { -- H:67
				{ at = 0, x = 30, scale = 0.7, alpha = 0 },
				{ at = 0.12, x = -6, scale = 1.05, alpha = 1 },
				{ at = 0.2, x = 0, scale = 1 },
				{ at = 0.82, x = 0, scale = 1, alpha = 1 },
				{ at = 1, x = 20, alpha = 0 },
			} :: { MotionPose },
		},
		coinCounter = {
			countUpMs = 400,
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.Out,
			floatPx = 30, -- "+N" floats up and fades
			floatMs = 700,
			-- §18.5.2 B1: the pill bounces on every gain (scale over upMs Quad Out, back over downMs Back Out) and the
			-- coin icon rotates 0 -> -iconWiggleDeg -> 0; spending squishes it and counts down over countMs, no float.
			-- UI FINAL R4 (G4.11): the gain bounce, the disc wiggle and the "+N" float above are no longer drawn (a
			-- gain shows only the coin flash); Config/init still checks floatMs, so they stay until a clean-up.
			pillBounce = { scale = 1.08, upMs = 70, downMs = 160 },
			-- UI FINAL R4 (G4.10, H:671-675): a spend drops the number at once (countMs 0) and squashes the pill's face
			-- by `squash` (H:674: FX.squash(pill, .8), on the press squash's frames and time, PR4); its "-N" float is
			-- Config.UI.Fx.events.spend.
			spend = { squash = 0.8, countMs = 0 },
			-- UI FINAL R4 (G4.10, reading): a claim's StateDelta (the new Coins) arrives before its reply, which starts
			-- the coin flight (QuestController.claim): a flight-sized gain with nothing in the air holds the old number
			-- this long for the flight that claims it, so the number only rises; with no flight it lands then.
			flightWaitMs = 250,
			iconWiggleDeg = 12,
			-- UI FINAL R2: a coin landing on the pill (coinFlash, H:562-578; R4 draws it): the coin flips (a width
			-- 1 -> 0 -> 1 for rotateY) and peaks iconPeak over flipMs (comboFlipMs when it lands within comboGapMs of
			-- the last), `curve`; the number goes numberScale and numberRisePx up, white, over numberMs
			-- (numberCurve); a coin-yellow ring around the pill grows ringFromPx -> ringToPx at ringAlpha over ringMs;
			-- the glow over glowMs and the rays over raysMs (ease-out).
			flash = {
				flipMs = 560, -- H:571
				comboFlipMs = 380, -- H:571
				comboGapMs = 260, -- H:565
				curve = "coinFlip", -- H:571
				iconPeak = 1.45, -- H:568
				numberScale = 1.22, -- H:574
				numberRisePx = 3, -- H:574
				numberMs = 480, -- H:574
				numberCurve = "search", -- H:574: cubic-bezier(.2,1.4,.4,1)
				ringFromPx = 8, -- H:575
				ringToPx = 16, -- H:575
				ringAlpha = 0.7, -- H:575
				ringMs = 560, -- H:575
				glowMs = 600, -- H:572
				raysMs = 700, -- H:573
				-- UI FINAL R4 (G4.6-G4.9): the tracks HudController plays per landing (PR7: the bright parts at most
				-- once per coinFlight.bounceMinGapMs, the last coin's never dropped). Each is a Web Animations run (one
				-- easing over the whole run, the frames linear): flip = rotateY in `rot` (drawn as the coin's width
				-- |cos rot| x its scale) with the white copy's opacity in `alpha` (brightness 1.9 / 1.2 less 1,
				-- H:568-569); halo = the drop-shadow(0 0 10px #FFF3A0) glow's opacity (H:568); number = its pop and
				-- rise with numberColors (Palette names) at the same frames (H:574); ring = the pill's yellow ring in
				-- `x` px at `alpha` (H:575); glow and rays (H:572-573; the rays skipped under ReducedMotion, H:573).
				flipFrames = {
					{ at = 0, rot = 0, scale = 1, alpha = 0 },
					{ at = 0.35, rot = 180, scale = 1.45, alpha = 0.9 },
					{ at = 0.7, rot = 330, scale = 0.9, alpha = 0.2 },
					{ at = 1, rot = 360, scale = 1, alpha = 0 },
				} :: { MotionPose },
				haloFrames = {
					{ at = 0, alpha = 0 },
					{ at = 0.35, alpha = 1 },
					{ at = 0.7, alpha = 0 },
					{ at = 1, alpha = 0 },
				} :: { MotionPose },
				numberFrames = {
					{ at = 0, scale = 1, y = 0 },
					{ at = 0.25, scale = 1.22, y = -3 },
					{ at = 0.6, scale = 0.97 },
					{ at = 1, scale = 1, y = 0 },
				} :: { MotionPose },
				numberColors = { "StickerCoinText", "White", "StickerCoinFlash", "StickerCoinText" },
				ringFrames = {
					{ at = 0, x = 0, alpha = 0 },
					{ at = 0.3, x = 8, alpha = 0.7 },
					{ at = 1, x = 16, alpha = 0 },
				} :: { MotionPose },
				ringCurve = "easeOut", -- H:575
				glowFrames = {
					{ at = 0, alpha = 0, scale = 0.4 },
					{ at = 0.25, alpha = 1, scale = 1.15 },
					{ at = 1, alpha = 0, scale = 1.5 },
				} :: { MotionPose },
				glowCurve = "easeOut", -- H:572
				raysFrames = {
					{ at = 0, alpha = 0, scale = 0.3, rot = 0 },
					{ at = 0.3, alpha = 1, scale = 1, rot = 40 },
					{ at = 1, alpha = 0, scale = 1.25, rot = 90 },
				} :: { MotionPose },
				raysCurve = "easeOut", -- H:573
			},
		},
		-- UI FINAL R4 (G4.1, H:25): the duel bar's entrance on each state change, the design's sdPop on its inner
		-- holder: the search bar over searchMs on searchCurve (H:136), MATCH FOUND over foundMs on foundCurve (H:149),
		-- each segment eased (a CSS animation). The bar does not clip, so its fade and tilt are drawn (plan §1.4 RL3).
		ctaPop = {
			searchMs = 450, -- H:136
			foundMs = 500, -- H:149
			searchCurve = "search", -- H:136
			foundCurve = "slot", -- H:149
			-- H:25: scale(.55) translateY(40px): the move is inside the scale, 40 x .55 = 22 px.
			frames = {
				{ at = 0, scale = 0.55, y = 22, rot = -2, alpha = 0 },
				{ at = 0.6, scale = 1.035, y = -4, rot = 0.4, alpha = 1 },
				{ at = 0.8, scale = 0.99 },
				{ at = 1, scale = 1, y = 0, rot = 0, alpha = 1 },
			} :: { MotionPose },
		},
		-- UI FINAL R4 (H:36, H:141): a queue slot's fill pops in (sdSlot .35 s, the slot curve).
		slotPop = {
			ms = 350, -- H:141
			curve = "slot", -- H:141
			frames = { { at = 0, scale = 0 }, { at = 0.65, scale = 1.35 }, { at = 1, scale = 1 } } :: { MotionPose },
		},
		-- "+N" coin flights into the pill (§18.5.2 B2, UI/CoinFlight): only for amounts >= minAmount unless the caller
		-- gives the count. UI FINAL R2: the design's fly (lib:269-286): `count` coins a gain (H:663; a claim passes
		-- Config.UI.Fx.events.*.coins, a paid squeeze 1, plan G2.8), at most maxCoins in the air, staggerMs apart;
		-- iconPx coins (img.coin) leave within startJitterPx of the source, swing through a point up to arcXPx to
		-- either side and arcUpMinPx..arcUpMaxPx above it (at midAt of the run eased by `curve`; the second leg eased
		-- by `legCurve`), growing 0 -> midScale and landing at endScale, turned up to ±spinDeg on the way (these px x
		-- the UI scale, lib:277-278's k); each flies ms + 0..jitterMs. The count-up lasts (k - 1) · staggerMs +
		-- countTailMs.
		coinFlight = {
			minAmount = 50,
			count = 8, -- H:663
			maxCoins = 10, -- plan §2.1 (H:746, H:856: 10 on a claim)
			iconPx = 46, -- lib:275
			ms = 720, -- lib:283
			jitterMs = 220, -- lib:283
			staggerMs = 60, -- lib:284
			startJitterPx = 15, -- lib:277
			arcXPx = 130, -- lib:278
			arcUpMinPx = 50, -- lib:278
			arcUpMaxPx = 190, -- lib:278
			midAt = 0.32, -- lib:281
			midScale = 1.15, -- lib:281
			endScale = 0.55, -- lib:282
			spinDeg = 45, -- lib:281
			curve = "fly", -- lib:283 (the whole run)
			legCurve = "flyLeg", -- lib:281 (the second leg)
			-- Reading (§18.1 #4 and §9.12 over B2's "at most once per 60 ms"): coins land 60 ms apart, so a 60 ms gap
			-- bounced the pill (and restarted the icon wiggle) about 16 times a second; >= 334 ms keeps it <= 3 Hz.
			bounceMinGapMs = 334,
			countTailMs = 400, -- >= jitterMs: the count-up never ends before the last coin lands
		},
		-- UI FINAL R2 (plan §2 T3 T4, PR24): a mouse hover (or a gamepad focus) poses a Button's inner SD_Visual by its
		-- design kind (`hover`) over ms with `curve`; a live face's gradient stops take the design's filter
		-- brightness(brightness) saturate(saturate) (H:637, computed exactly, Button.hoverColor) over filterMs with
		-- filterCurve; never on an "off" or disabled face (H:637). The laid-out root (the hit box) never moves.
		buttonHover = {
			ms = 380, -- H:635
			curve = "hover", -- H:635
			filterMs = 200, -- H:635
			filterCurve = "ease", -- H:635
			brightness = 1.07, -- H:637
			saturate = 1.06, -- H:637
		},
		-- H:634: each design hover kind's pose (base px, a scale, degrees). Button kinds take btn (primary, secondary,
		-- cancel, cta), nav (tile), x (close); spec.fx picks another (the Settings sticker's "icon", H:157).
		hover = {
			btn = { scale = 1.04, y = -3 },
			nav = { scale = 1.13, rot = -4 },
			tab = { scale = 1.05, y = -2 },
			card = { scale = 1.035, y = -5 },
			x = { scale = 1.1, rot = 90 },
			icon = { scale = 1.12 },
			row = { x = 4 },
		} :: { [string]: { [string]: number } },
		-- PR4 (decided 2026-10-15, "A, closest to the design"): the design's press squash (lib:287-293, on pointer-down
		-- H:611): a = amount x the kind's amountByKind (H:644: nav 1.4, card .7, else 1); each frame's sx / sy is
		-- 1 + a x its coefficient (lib:290-292), added to the hover pose. Only slowed: ms instead of designMs, each
		-- segment eased `curve` (ease-out), so its swings between extremes are 167 ms apart = 3.0 Hz (§9.12). A text
		-- or ViewportFrame takes its uniform part, sqrt(sx x sy); a decorated object (Button.decorate: it may sit in a
		-- layout, so only a UIScale) takes its `decoratedAxis` series as the uniform scale (reading: the sy track, .86
		-- at 20%, so a tap still shows a press; sqrt(sx x sy) stays within 1% of 1).
		buttonPress = {
			ms = 667,
			designMs = 460, -- lib:293
			curve = "easeOut", -- lib:293
			amount = 0.14, -- lib:289
			amountByKind = { nav = 1.4, card = 0.7 }, -- H:644
			decoratedAxis = "sy", -- reading (above)
			frames = { -- lib:290-292: coefficients of a
				{ at = 0, sx = 0, sy = 0 },
				{ at = 0.2, sx = 1, sy = -1 },
				{ at = 0.45, sx = -0.5, sy = 0.6 },
				{ at = 0.7, sx = 0.2, sy = -0.15 },
				{ at = 1, sx = 0, sy = 0 },
			} :: { MotionPose },
		},
		-- PR5 (decided 2026-10-15): the design's "no" shake (lib:295-297): x = step x px, rotation = step x rotDeg, px
		-- 9 on a button (H:643) and 12 on the coin pill (H:676). Only slowed: ms instead of designMs, each segment
		-- eased `curve`, so the swings are 167 ms apart = 3.0 Hz (§9.12).
		buttonShake = {
			ms = 1000,
			designMs = 420, -- lib:297
			curve = "easeOut", -- lib:297
			steps = { 0, -1, 1, -0.8, 0.6, -0.3, 0 }, -- lib:297
			rotDeg = 2, -- lib:297
			px = 9, -- H:643
			pillPx = 12, -- H:676
		},
		-- A nav sticker's icon wiggles through these angles when the mouse comes over it (H:639: designMs, 3.8 Hz; PR6:
		-- held to 3 Hz over ms; R4 wires it).
		navWiggle = { ms = 668, designMs = 520, angles = { 0, -12, 9, -4, 0 } },
		-- Pops (Back Out): the HUD badge when its count rises (§18.5.2 B5); READY and the opponent's Rush chip (B8).
		badgePop = { from = 1.4, ms = 220 },
		readyPop = { from = 1.3, ms = 220 },
		-- UI FINAL R2 (PR24): a focused Button takes its hover pose (Button), so the focus has no scale of its own.
		focus = { outerStrokePx = 3, innerStrokePx = 2 }, -- Ink outer + white inner stroke (UI FINAL R1)
		disabledTextOpacity = 0.6, -- plus a reason text; still selectable
		loadingSpinnerDelayMs = 150, -- e.g. box Open waiting for the reply
		skeletonPulseMaxHz = 1,
		ultReadyPulseSeconds = 0.9, -- static under ReducedMotion
		reducedMotionMaxFadeMs = 120,
		-- UI FINAL R2: the design's perpetual loops (H:23-43), Anim/UiIdle on inner holders, each eased `curve` per
		-- segment (the CSS ease-in-out; ring ease-out; spin linear). periodS is each kind's default; a caller passes
		-- the period (and the delay) its design line uses. Every period >= 1/3 s (§9.12: <= 3 Hz, Config F9). Under
		-- ReducedMotion every loop rests at its 0% pose (plan T11, PR9).
		idle = {
			bob = { periodS = 3.1, risePx = 6, rotDeg = 2, curve = "easeInOut" }, -- H:23, H:100: up and -2° at half
			coin = { periodS = 4.5, risePx = 3, rotDeg = 8, curve = "easeInOut" }, -- H:24, H:78: -8° -> 8°, up at half
			float = { periodS = 3.6, risePx = 12, rotDeg = 3, curve = "easeInOut" }, -- H:34, H:93: -3° -> 3°, up
			pulse = { periodS = 1, scale = 1.07, curve = "easeInOut" }, -- H:29, H:89
			badge = { -- H:32, H:102: still, then a pop and a wobble in the last 30%
				periodS = 2.6,
				curve = "easeInOut",
				frames = {
					{ at = 0, scale = 1, rot = 0 },
					{ at = 0.7, scale = 1, rot = 0 },
					{ at = 0.78, scale = 1.3, rot = -12 },
					{ at = 0.86, scale = 1, rot = 10 },
					{ at = 0.93, rot = -4 },
					{ at = 1, scale = 1, rot = 0 },
				} :: { MotionPose },
			},
			-- H:35, H:139
			dot = { periodS = 1, alphaFrom = 0.35, scaleFrom = 0.8, scaleTo = 1.15, curve = "easeInOut" },
			ring = { periodS = 1.8, alphaFrom = 0.9, scaleFrom = 0.9, scaleTo = 1.5, curve = "easeOut" }, -- H:43, H:168
			twinkle = { periodS = 2.2, scaleFrom = 0.3, rotDeg = 90, curve = "easeInOut" }, -- H:40, H:221
			-- H:28: a px strip holds at fromShare of its own width (out of sight on the left) for holdShare of the
			-- period, then crosses to toShare (ease-in-out on that segment); each use gives its period
			-- (Config.UI.Sticker.shines).
			shine = { periodS = 2.6, holdShare = 0.55, fromShare = -2, toShare = 9, curve = "easeInOut" },
			spin = { periodS = 16, curve = "linear" }, -- H:30, H:219 (the rays: 18 s H:266, 20 s H:296, 26 s H:474)
		} :: { [string]: { [string]: any } },
		-- UI FINAL R2 (plan §2 G2.4): the design's other looping @keyframes, played by UiIdle.addFrames on a holder its
		-- step makes (R7 reveal hint, R9 level-up): periodS, alternate (CSS `alternate`), delayS (+ delayStepS x i for
		-- the i-th letter), curve per segment, frames. All <= 3 Hz (Config F9).
		loops = {
			lvIdle = { -- H:51, H:523: sdLvIdle .45 s ease-in-out infinite alternate
				periodS = 0.45,
				alternate = true,
				curve = "easeInOut",
				frames = {
					{ at = 0, y = 0, sx = 1, sy = 1 },
					{ at = 1, y = -16, sx = 0.94, sy = 1.06 },
				} :: { MotionPose },
			},
			lvJelly = { -- H:57, H:517: sdLvJelly 1.6 s ease-in-out infinite
				periodS = 1.6,
				curve = "easeInOut",
				frames = {
					{ at = 0, sx = 1, sy = 1, rot = 0 },
					{ at = 0.25, sx = 1.06, sy = 0.95, rot = 0 },
					{ at = 0.5, sx = 0.97, sy = 1.04, rot = -2 },
					{ at = 0.75, sx = 1.03, sy = 0.98, rot = 2 },
					{ at = 1, sx = 1, sy = 1, rot = 0 },
				} :: { MotionPose },
			},
			lvWave = { -- H:61, H:527, H:999: sdLvWave 1.2 s ease-in-out infinite, from 1.9 + .07 i s
				periodS = 1.2,
				delayS = 1.9,
				delayStepS = 0.07,
				curve = "easeInOut",
				frames = { { at = 0, y = 0 }, { at = 0.5, y = -7 }, { at = 1, y = 0 } } :: { MotionPose },
			},
			lvPulse = { -- H:63, H:515: sdLvPulse 1.1 s ease-in-out infinite
				periodS = 1.1,
				curve = "easeInOut",
				frames = { { at = 0, scale = 1 }, { at = 0.5, scale = 0.7 }, { at = 1, scale = 1 } } :: { MotionPose },
			},
			-- H:64, H:510: sdLvBubble 2.4-4.0 s ease-in infinite (each bubble its own period in that span); y is a share
			-- of the screen height (-115vh) applied by the caller (UI FINAL R9: UI/LevelUpShow).
			lvBubble = {
				periodS = 2.4,
				periodMaxS = 4,
				curve = "easeIn", -- H:510 (UI FINAL R9: was "linear")
				frames = {
					{ at = 0, alpha = 0, x = 0, y = 0, scale = 0.6 },
					{ at = 0.15, alpha = 0.9 },
					{ at = 1, alpha = 0, x = 40, y = -1.15, scale = 1.15 },
				} :: { MotionPose },
			},
			hint = { -- H:68, H:484: sdHint 1 s ease-in-out infinite
				periodS = 1,
				curve = "easeInOut",
				frames = {
					{ at = 0, alpha = 0.6, scale = 1 },
					{ at = 0.5, alpha = 1, scale = 1.08 },
					{ at = 1, alpha = 0.6, scale = 1 },
				} :: { MotionPose },
			},
		} :: { [string]: { [string]: any } },
	},

	confirmSeconds = 3, -- inline two-step spend confirm reverts after this (§11.5)
	-- UI FINAL R6 (plan work/ui/PLAN.md R6, PR13; `H:n` = "Squishy Duels HUD.dc.html" line n): the design's confirm
	-- dialog for a coin spend (H:455-469, UI/Components/ConfirmDialog), base px: its scrim, card (its top shiftY above
	-- the middle, H:457 margin -200), medallion and buttons, ConfirmButton's double-press guard, the room kept from the
	-- screen's edges when it shrinks to fit (Sticker.window.margin's reading) and the layer it draws in: its own
	-- full-screen ScreenGui above SD_Modal (a controller-owned layer, so not in ScreenGuis), shared with the Shop's
	-- congrats overlay (H:537 z 40).
	confirm = {
		scrimAlpha = 0.4, -- H:456: rgba(110,60,220,.4)
		fadeMs = 200, -- H:456: sdFade .2s ease
		fadeCurve = "ease", -- H:456
		card = {
			width = 480, -- H:457
			shiftY = -200, -- H:457
			padTop = 64, -- H:457: padding 64px 28px 26px
			padX = 28,
			padBottom = 26,
			border = 5, -- H:457
			radius = 30, -- H:457
			lip = 10, -- H:457
			gap = 12, -- H:457
			inset = { px = 4, alpha = 0.12 }, -- H:457: inset 0 4px 0 rgba(255,255,255,.12)
			shadow = { offsetY = 30, blurPx = 60, alpha = 0.5 }, -- H:457: 0 30px 60px rgba(15,8,25,.5)
			popMs = 450, -- H:457: sdPop .45s cubic-bezier(.2,1.5,.4,1)
			popCurve = "stars", -- H:457
		},
		medallion = {
			px = 130, -- H:458
			top = -70, -- H:458
			border = 5, -- H:458
			lip = 6, -- H:458
			centreY = 0.35, -- H:458: radial-gradient(circle at 50% 35%, ...)
			stickMs = 600, -- H:458: sdStick .6s .05s cubic-bezier(.2,1.4,.4,1)
			stickDelayMs = 50,
			stickCurve = "search",
			icon = 100, -- H:458
			bobS = 2.4, -- H:458
		},
		buttons = {
			face = 62, -- H:462-463
			gap = 12, -- H:461
			marginTop = 8, -- H:461
			cancelFlex = 1, -- H:462
			buyFlex = 1.4, -- H:463
			coinPx = 30, -- H:464
		},
		guardMs = 300, -- UI/Components/ConfirmButton GUARD_SECONDS
		margin = 12,
		layerName = "SD_Prompt",
		layer = { displayOrder = 25, insets = Enum.ScreenInsets.None } :: ScreenGuiSpec,
	},

	-- ControlsController (§11.7). reading (not in DESIGN, provisional): how long start() waits for the PlayerModule
	-- that block() uses to stop character movement.
	Controls = {
		playerModuleWaitSeconds = 10,
	},

	Settings = {
		sliderStep = 5, -- DPad left/right
		saveDebounceSeconds = 1.5, -- SetSettings client debounce
	},

	Queue = {
		matchedBannerSeconds = 2, -- "Opponent found: {name}"
	},

	-- Final polish (2026-10-11): the "In the lane!" warning (DuelController, UI/LaneCue) sits this far (base px) under
	-- the duel bar, or under the banner that shows there.
	LaneCue = {
		gapPx = 8,
	},

	-- jayyyyy 2026-10-15: the READY badge above other duelists whose ultimate is charged (UltReadyTagController).
	-- guiPx: the BillboardGui (room for the chip and its pop); the offset sits above the Head, rootToHeadStuds more
	-- when only the HumanoidRootPart is there; maxDistanceStuds covers a whole arena (72 x 104).
	UltReadyTag = {
		guiPx = Vector2.new(140, 48),
		headOffsetStuds = 2.5,
		rootToHeadStuds = 1.5,
		maxDistanceStuds = 140,
	},

	-- Feature 1 (2026-10-11): the charge on the reticle, the catch prompt under it and the catch's big words
	-- (DuelController, PracticeController, UI/DuelFormat; design: the combat-effects page "Squishy Combat FP v2.html",
	-- html:28, 88, 301, 670-674).
	Reticle = {
		-- build choice 2026-10-11 (NOT IN DESIGN: the design's ring is solid, html:28): the charge fills the reticle in the
		-- toy's colour at this transparency, clockwise (the cooldown's pie, which never shows while charging).
		chargeFillTransparency = 0.2,
		-- At full the reticle pulses chargeFullScale + chargePulse·sin(chargePulseRate·t) (design: html:671); static under
		-- ReducedMotion.
		chargeFullScale = 1.08,
		chargePulse = 0.04,
		chargePulseRate = 18, -- rad/s (2.9 Hz)
		-- "Catch!" under the reticle while an opponent's throw within catchPromptStuds comes at you and the catch is ready
		-- (design: html:88, 673-674: within 9 m); its opacity is catchPromptFrom + (1 - catchPromptFrom)·sin(2π·Hz·t)
		-- (design: html:674, 0.75 + 0.25·sin(20t): its 3.2 Hz held to the 3 Hz flicker limit); steady under ReducedMotion.
		catchPromptStuds = 9 / 0.28,
		catchPromptFrom = 0.75,
		catchPromptHz = 3,
		-- "CAUGHT!" and "SQUISHED!" (UIController banners under the duel bar, in the caught toy's colour) show this long
		-- (design: html:301, the toast's 1.1 s).
		bigWordSeconds = 1.1,
	},

	Result = {
		autoCloseAfterReturnSeconds = 6,
		-- Batch 3: the Rematch button's bounce when the opponent asks (the coin pill's bounce: scale over upMs, back
		-- over downMs; Button:pulse, off under ReducedMotion).
		rematchPulse = { scale = 1.08, upMs = 70, downMs = 160 },
	},

	-- Squishies screen (§11.6): columns = floor(gridWidth / (cardWidth + pad)).
	Inventory = {
		cardWidth = 112,
		gridWidthMin = 0.55, -- grid takes 55-60% of the width
		gridWidthMax = 0.6,
		lazyIconsAbove = 24, -- StaticIcon cells are created lazily above this many items
		-- UI FINAL R5 (the design's Squishies window, plan work/ui/PLAN.md R5; `H:n` = "Squishy Duels HUD.dc.html"
		-- line n; base px, border-box like the design's CSS). Read by UI/InventoryFormat and InventoryController.
		-- The body (H:191-192): its padding inside the window's border, the 600 px grid column, the column gap, the left
		-- column's gap; detailMin [P]: the detail column's least width when a small window narrows the grid.
		body = { padTop = 18, padSide = 22, padBottom = 22, gridWidth = 600, gap = 22, columnGap = 12, detailMin = 240 },
		-- The header pill (H:185-188): 46 high, padding 0 14, gap 10, border 4, the ink at .55; the 110 px bar.
		pill = { height = 46, padX = 14, gap = 10, border = 4, alpha = 0.55, barWidth = 110 },
		-- The rarity tabs (H:193-194, H:928-929): 42 face + 4 lip, padding 0 13, gap 6, border 4, radius 14, the on /
		-- off inset highlight (tabOn 3 at .5, tabOff 2 at .12), the count at opacity .85; the row's gap 8 and the
		-- "Show locked" group's gap 8 (H:195).
		tab = {
			face = 42,
			lip = 4,
			padX = 13,
			gap = 6,
			border = 4,
			radius = 14,
			onHighlightPx = 3,
			onHighlightAlpha = 0.5,
			offHighlightPx = 2,
			offHighlightAlpha = 0.12,
			countAlpha = 0.85,
			rowGap = 8,
			toggleGap = 8,
		},
		-- The card grid (H:200-202): 4 columns, gap 12, the scroller's padding 8 / 8 / 10 / 4 (top, right, bottom, left)
		-- and its matching negative margin; minCard [P]: the narrowest card before a column drops (a small window).
		grid = { columns = 4, gap = 12, padTop = 8, padRight = 8, padBottom = 10, padLeft = 4, minCard = 120 },
		-- A card (H:203, H:935): 178 face + 5 lip, border 4 (white when selected), radius 20, padding 10 6 8, gap 4,
		-- the inset highlight 2 at .1 (none when selected), the selected ring 4 px (radius 24) and glow 26 px.
		card = {
			face = 178,
			lip = 5,
			border = 4,
			radius = 20,
			padTop = 10,
			padSide = 6,
			padBottom = 8,
			gap = 4,
			highlightPx = 2,
			highlightAlpha = 0.1,
			ringPx = 4,
			ringRadius = 24,
			glowPx = 26,
		},
		-- The plate (H:204, H:936): 96 circle, border 3, radial at 50% 38%, inset 0 4px 0 white .45 and 0 -6px 0
		-- black .12; the thumbnail 104 with its drop-shadow 0 4px at .25 (H:205), the lock 40 (H:206).
		plate = {
			px = 96,
			border = 3,
			centreY = 0.38,
			topPx = 4,
			topAlpha = 0.45,
			bottomPx = 6,
			bottomAlpha = 0.12,
			thumbPx = 104,
			shadowPx = 4,
			shadowAlpha = 0.25,
			lockPx = 40,
		},
		-- The card footer (H:209): gap 6; the pips as dots [PR25] the size of the 10 px glyph (dotPx [P]: a reading of
		-- the glyph, not measured in Studio yet) with its 1 px letter-spacing.
		footer = { gap = 6, dotPx = 7, dotGap = 1 },
		-- The hanging tags (H:210-211): "Equipped" at (-8, -10), 26 high, padding 3 10 0, border 3, lip 3, turned -6;
		-- "NEW" at (right -8, -10), 28 high, padding 0 10, border 3, lip 3, sdBadge over 2 s.
		ribbon = { x = -8, y = -10, height = 26, padTop = 3, padX = 10, border = 3, lip = 3, rot = -6 },
		newTag = { x = -8, y = -10, height = 28, padX = 10, border = 3, lip = 3, badgeS = 2 },
		-- The detail (H:217-248): the column gap 12, the name row's gap 10, the chip row's gap 8, the chips' 20 px icons.
		detail = { gap = 12, nameGap = 10, chipGap = 8, iconPx = 20 },
		-- The stage (H:218-224, H:1012-1014): 186 face + 5 lip, border 4, radius 22, inset 0 5px 0 white .35; minFace
		-- [P]: the least face when the column is short (phones; the list then scrolls). Rays (raysDetail) 640 px at
		-- (50%, 60%), white .26 x the opacity (1 from Epic on, index fromIndex; .45 below), one turn in 16 s; the floor
		-- 150 x 24 at bottom 16, ink .25; the stars sdTwinkle 2.2 s; the squishy 190 floating 3.2 s, drop-shadow 0 8px
		-- at .3; the pick pop (H:937): 480 ms, the rise curve on the whole run (keyframes linear).
		stage = {
			face = 186,
			lip = 5,
			border = 4,
			radius = 22,
			shinePx = 5,
			shineAlpha = 0.35,
			centreY = 0.62,
			midAt = 0.62,
			minFace = 120,
			raysPx = 640,
			raysAlpha = 0.26,
			raysCentreY = 0.6,
			raysSpinS = 16,
			raysHigh = 1,
			raysLow = 0.45,
			raysFromIndex = 3,
			floorWidth = 150,
			floorHeight = 24,
			floorBottom = 16,
			floorAlpha = 0.25,
			twinkleS = 2.2,
			-- x from the left (or right) and y from the top (or bottom) edge, base px (H:220-222)
			stars = {
				{ px = 26, left = 28, top = 22, delayS = 0 },
				{ px = 20, right = 34, top = 40, delayS = 0.8 },
				{ px = 16, right = 70, bottom = 26, delayS = 1.4 },
			} :: { { [string]: number } },
			squishyPx = 190,
			floatS = 3.2,
			shadowPx = 8,
			shadowAlpha = 0.3,
			pickMs = 480,
			pickCurve = "rise",
			pickFrames = {
				{ at = 0, scale = 0.3, rot = -14, alpha = 0 },
				{ at = 0.6, scale = 1.16, rot = 5, alpha = 1 },
				{ at = 1, scale = 1, rot = 0, alpha = 1 },
			} :: { MotionPose },
		},
		-- The stats well (H:236-243): rows 72 | 1fr | 92 with gap 10, 7 apart, padding 12 16 inside its 4 px border,
		-- radius 18.
		stats = { label = 72, value = 92, gap = 10, rowGap = 7, padY = 12, padX = 16, border = 4, radius = 18 },
		-- The one button (H:245-247): a 60 px face (+ its 5 px lip), the check 30 and the boxes picture 44.
		button = { face = 60, checkPx = 30, iconPx = 44 },
	},

	-- Boxes screen (§11.6). Reading (DESIGN names the timeout state but gives no number): a BoxOpen with no reply after
	-- stillCheckingSeconds shows box.stillChecking; the outcome then arrives with the next StateDelta.
	Boxes = {
		stillCheckingSeconds = 10, -- [P]
		-- Reading (Part 7 review fix, §9.11 "no fake-outs"): StateController hides a new box result (the duplicate
		-- refund in the Coins, the new squishy in owned) until its reveal reaches the result; a reveal that has not
		-- played after this many seconds (e.g. queued behind another result left open) shows its result anyway.
		revealHoldMaxSeconds = 30,
		-- UI FINAL R7 (plan work/ui/PLAN.md R7; `H:n` = "Squishy Duels HUD.dc.html" line n, `stage:n` = its
		-- uploads/box-stage.html), base px. The window's body (H:262: three columns, gap 20, padding 22 24 26; PR20: the
		-- selected card 2fr, the others 1fr, never narrower than minFr, else the row scrolls sideways), the design's
		-- card (H:264-278), its odds rows (H:270-272), toy tiles (H:273-274), OPEN (H:276-278) and the stats well of the
		-- selected card (H:236; PR20: §6.10 items 3-6, one row per item: the toy tile, the name, the pill, the exact
		-- percent, Owned, the refund line, Inspect). The plate shrinks with a short body (never under plateMin, else it
		-- hides) and the tiles drop when they do not fit (readings).
		body = { gap = 20, padTop = 22, padSide = 24, padBottom = 26, minFr = 210 }, -- H:262
		card = {
			gap = 12, -- H:264
			pad = 14,
			border = 4,
			radius = 24,
			lip = 6,
			inset = { px = 3, alpha = 0.12 },
			-- H:264: sdRise .5 s cubic-bezier(.2,1.3,.4,1), card i after i x 90 ms (its fade not drawn, plan RL3)
			rise = {
				ms = 500,
				curve = "rise",
				stepMs = 90,
				frames = { { at = 0, y = 18, scale = 0.9 }, { at = 1, y = 0, scale = 1 } } :: { MotionPose },
			},
			plate = 178, -- H:265
			plateMin = 72, -- reading: the smallest plate drawn (a short phone body), else it hides
			plateBorder = 4,
			plateRadius = 18,
			plateHighlight = { px = 5, alpha = 0.4 }, -- H:265: inset 0 5px 0 rgba(255,255,255,.4)
			rays = { px = 520, alpha = 0.28, centreY = 0.55, spinS = 18 }, -- H:266
			art = { px = 176, floatS = 2.8, delayStepS = 0.5, shadow = { px = 8, alpha = 0.3 } }, -- H:267
			nameRole = "boxName", -- H:269
		},
		odds = { pill = 96, bar = 12, pct = 40, gap = 8, rowGap = 6, minPct = 6, pillHeight = 22 }, -- H:271
		oddsPill = { padTop = 2, padX = 8, border = 3, role = "rarityPill" }, -- H:271
		oddsBar = { border = 3, fillHighlight = { px = 2, alpha = 0.4 } }, -- H:271
		oddsPctRole = "oddsPct", -- H:271: 14 px -> 16 (PR2), white, bold
		toys = { tile = 42, gap = 4, border = 3, radius = 12, px = 40, max = 6 }, -- H:273-274
		open = {
			face = 62, -- H:276: 62 + lip 5, border 4, radius 18, gap 10
			gap = 10,
			labelRole = "boxOpen", -- H:277: 27 px, stroke 6
			priceH = 36, -- H:278: padding 0 10 0 4, gap 4, border 3, full radius, rgba(30,20,40,.45)
			pricePadLeft = 4,
			pricePadRight = 10,
			priceGap = 4,
			priceBorder = 3,
			priceAlpha = 0.45,
			coin = 28,
			priceRole = "boxPrice", -- H:278: 19 px, stroke 4
			shopIcon = 28, -- PR22: img.nav.shop in the coin's place
			freeRole = "confirmDesc", -- FD5: the Treat Box's box.freeOnly line in OPEN's place
		},
		well = { gap = 12, border = 4, radius = 18, inset = { px = 3, alpha = 0.3 }, pad = 10, rowGap = 8 }, -- H:236
		subtitleKind = "Small", -- H:260: 16 px #0B4B5E (StickerBoxHeaderText), bold, no outline
		-- The reveal overlay (H:470-505, stage:*): its own full-screen layer between SD_Modal and the confirm dialog's
		-- SD_Prompt (a controller-owned layer, so not in ScreenGuis [P]); the scrim (H:471: ellipse at 50% 45%), the
		-- rarity tint (H:473: at 50% 46%, alpha .9) and rays (H:474), the 3D stage's fade (H:478), the flash (H:503,
		-- H:822 under Config.Vfx.Flash: PR16), the texts by screen share (H:482, H:488, H:494) with their delays from the
		-- burst (H:489-499; sdUp H:44, sdReveal H:38), the NEW! pill (H:489), the rarity pill (H:491), the buttons
		-- (H:497-499), the Skip pill (PR21: the reset pill's look, H:359) and the close (H:837-840).
		reveal = {
			layerName = "SD_Reveal",
			layer = { displayOrder = 22, insets = Enum.ScreenInsets.None } :: ScreenGuiSpec,
			scrimFadeMs = 300, -- H:471: sdFade .3s ease
			scrimCentreY = 0.45,
			scrimInnerAlpha = 0.9,
			scrimOuterAlpha = 0.95,
			scrimOuterAt = 0.8,
			tintFadeMs = 400, -- H:473
			tintCentreY = 0.46,
			tintAlpha = 0.9,
			rays = { px = 1500, alpha = 0.12, centreY = 0.46, spinS = 26 }, -- H:474
			stageFadeMs = 250, -- H:478: transition: opacity .25s
			flash = { ms = 700, designPeak = 0.85, designPeakAt = 0.1, centreY = 0.45, midAt = 0.45, outerAlpha = 0.85 },
			boxBlock = { bottom = 0.09, gap = 10, nameRole = "revealBox", hintRole = "tapHint" }, -- H:482-484
			nameUp = { ms = 400, delayMs = 200, curve = "ease" }, -- H:483: sdUp .4s .2s ease
			hintS = 1, -- H:484: sdHint 1s
			resultBlock = { top = 0.07, gap = 12 }, -- H:488
			newPill = { height = 42, padX = 18, border = 4, lip = 5, role = "button" }, -- H:489: 24 px stroke 5
			nameRole = "revealName", -- H:490
			rarityPill = {
				height = 38,
				padX = 20,
				border = 4,
				lip = 4,
				highlight = { px = 3, alpha = 0.4 },
				role = "tab",
			},
			dupeRole = "confirmDesc", -- H:492: 16 px #F3EDFF
			bottomBlock = { bottom = 0.06, gap = 14 }, -- H:494
			dragRole = "dragHint", -- H:495: 17 px, stroke 4
			buttonGap = 14, -- H:496
			equip = { width = 180, face = 62, role = "buttonLarge" }, -- H:497: cyan, 26 px stroke 6
			again = { width = 230, face = 62, gap = 8, coin = 30, role = "againLabel", priceRole = "againPrice" }, -- H:498
			nice = { width = 180, face = 62, role = "buttonLarge" }, -- H:499: green, 26 px stroke 6
			-- From the burst (H:489-499): NEW! +.3 s (sdReveal .6 s), the name +.35, the rarity pill +.45 (sdUp .45 s
			-- search), the duplicate line +.5 (sdUp .4 s ease), the buttons +.6 (sdUp .45 s search), the drag hint +1 s.
			delays = { newMs = 300, nameMs = 350, rarityMs = 450, dupeMs = 500, buttonsMs = 600, dragMs = 1000 },
			upMs = 450,
			upCurve = "search",
			dupeUpMs = 400,
			newMs = 600,
			newCurve = "rise",
			-- PR21: Skip, the reset pill's look (H:359: 36 high, border 3, full radius, StickerWell, 16 px #F3EDFF)
			skip = { height = 36, padX = 16, border = 3, role = "confirmDesc", margin = 16 },
			closeMs = 200, -- H:837: opacity 1 -> 0 and scale 1 -> 1.06 over 200 ms (linear)
			closeScale = 1.06,
			removeMs = 190, -- H:840
			againDelayMs = 40, -- H:1020: the next box opens 40 ms after AGAIN's BUY closed this one
			tapMovePx = 8, -- reading: a press that moves less than this is a tap (Inspect), more a drag (spin)
		},
	},

	-- Shop screen (§11.6). Reading (DESIGN gives no number): the Squishies tab card width in base px, like
	-- Inventory.cardWidth (columns = floor(gridWidth / (cardWidth + pad))).
	Shop = {
		cardWidth = 146, -- [P] UI FINAL R6: 4 columns at gap 12 fill the design's 652 px right column (H:294, H:330)
		-- UI FINAL R6 (the Shop window, plan work/ui/PLAN.md R6; `H:n` = "Squishy Duels HUD.dc.html" line n), base px:
		-- the body (H:294: 330 | 1fr, gap 20, padding 20 24 24), the featured card (H:295-312: the selected squishy),
		-- the right column's section heads (H:314-315, H:329) and card gap (H:330), the coin pack cards (H:330-340,
		-- hidden while no bundle is offered) and the congrats overlay after a buy (H:536-549). A track's `frames` are
		-- the design's @keyframes (Config.UI.motion's pose shape), `curve` a Config.UI.curves name.
		body = { featuredWidth = 330, gap = 20, padTop = 20, padSide = 24, padBottom = 24 }, -- H:294
		featured = {
			border = 4, -- H:295
			radius = 24, -- H:295
			lip = 6, -- H:295: 0 6px 0 #1E1428
			inset = { px = 4, alpha = 0.5 }, -- H:295: inset 0 4px 0 rgba(255,255,255,.5)
			midAt = 0.45, -- H:295: #FFE58A 0, #F5A623 45%, #7B4FE0 100%
			-- H:295: sdRise .5s cubic-bezier(.2,1.3,.4,1) (H:31; its fade is not drawn, plan §1.4 RL3)
			rise = {
				ms = 500,
				curve = "rise",
				frames = { { at = 0, y = 18, scale = 0.9 }, { at = 1, y = 0, scale = 1 } } :: { MotionPose },
			},
			rays = { px = 760, alpha = 0.3, centreY = 0.38, spinS = 20 }, -- H:296
			-- H:302-304: sdTwinkle (H:40) from the art area's corners; the gem is decoration (not a Robux picture)
			twinkles = {
				{ key = "img.icon.star", px = 30, left = 34, top = 30, periodS = 2, delayS = 0 }, -- H:302
				{ key = "img.icon.star", px = 22, right = 30, top = 80, periodS = 2, delayS = 0.7 }, -- H:303
				{ key = "img.icon.gem", px = 34, right = 40, bottom = 20, periodS = 2.4, delayS = 1.2 }, -- H:304
			} :: { { [string]: any } },
			-- H:305: 230 px, drop-shadow(0 10px 0 rgba(30,20,40,.35)), sdFloat 3s; minPx: the smallest it is drawn
			-- (the old detail preview's DETAIL_ICON_MIN_PX reading), else it hides
			art = { px = 230, minPx = 48, floatS = 3, shadow = { px = 10, alpha = 0.35 } },
			text = { padX = 16, padBottom = 16, gap = 6 }, -- H:307
			nameRole = "featuredName", -- H:308
			lineRole = "featuredLine", -- H:309
			lineCoinPx = 22, -- H:309
			-- H:310: the BUY, 62 + lip 5, margin-top 4, radius 18, gap 10, the coin 36 and the price, sdPulse 1.6s
			buy = { face = 62, marginTop = 4, gap = 10, coinPx = 36, pulseS = 1.6, textRole = "buyFeatured" },
			-- H:311: OWNED, the lilac bar 62 high, border 4, radius 18, the check 30 raised 5, gap 10
			owned = {
				face = 62,
				border = 4,
				radius = 18,
				checkPx = 30,
				checkRaise = 5,
				gap = 10,
				textRole = "ownedBar",
			},
		},
		sections = { gap = 12, headRole = "sectionHead", cellGap = 12 }, -- H:314-315, H:329-330
		-- H:330-340: 4 columns, gap 12, padding 12 8 10, gap 6, border 4, radius 20, lip 5, inset 4 .7, the icon 92
		-- sdBob 2.8s, the amount, the green price bar 38 (border 3, radius 12, inset 2 .55, lip 3)
		packs = {
			columns = 4,
			gap = 12,
			padTop = 12,
			padX = 8,
			padBottom = 10,
			innerGap = 6,
			border = 4,
			radius = 20,
			lip = 5,
			inset = { px = 4, alpha = 0.7 },
			iconPx = 92,
			iconMinPx = 70,
			bobS = 2.8,
			amountRole = "packAmount",
			priceBar = 38,
			priceBorder = 3,
			priceRadius = 12,
			priceInset = { px = 2, alpha = 0.55 },
			priceLip = 3,
			priceRole = "packPrice",
		},
		-- H:536-549 (G6.8, G6.9): the radial's alphas (H:537), the rays (H:538), the letters' sdSlam (H:45) per letter
		-- .05 + .035 i s, the icon's sdReveal (H:38) with its glow disc and float, the texts' and AWESOME!'s sdUp (H:44),
		-- the close (H:878: fade 1 -> 0 and scale 1 -> 1.08 over 220 ms linear, removed at 210 ms).
		congrats = {
			alphas = { top = 0.92, mid = 0.9, midAt = 0.35, outer = 0.96 }, -- H:537
			centreY = 0.45, -- H:537
			fadeMs = 300, -- H:537: sdFade .3s ease
			fadeCurve = "ease",
			gap = 10, -- H:537
			rays = { px = 1600, alpha = 0.28, centreY = 0.45, spinS = 20 }, -- H:538
			letters = {
				delayS = 0.05, -- H:1005
				staggerS = 0.035, -- H:1005
				slamMs = 600, -- H:539
				curve = "rise", -- H:539: cubic-bezier(.2,1.3,.4,1)
				frames = { -- H:45
					{ at = 0, y = -160, scale = 2.4, rot = -12, alpha = 0 },
					{ at = 0.55, y = 8, sx = 0.9, sy = 1.15, rot = 3, alpha = 1 },
					{ at = 0.75, y = -6, sx = 1.08, sy = 0.94 },
					{ at = 1, y = 0, scale = 1, rot = 0, alpha = 1 },
				} :: { MotionPose },
			},
			icon = {
				holder = 240, -- H:540
				revealMs = 800, -- H:540: sdReveal .8s cubic-bezier(.2,1.3,.4,1) .55s
				revealDelayS = 0.55,
				revealCurve = "rise",
				frames = { -- H:38
					{ at = 0, scale = 0, rot = -30, alpha = 0 },
					{ at = 0.55, scale = 1.25, rot = 8, alpha = 1 },
					{ at = 0.75, scale = 0.92, rot = -3 },
					{ at = 1, scale = 1, rot = 0, alpha = 1 },
				} :: { MotionPose },
				glowInset = 10, -- H:541
				glowAlpha = 0.95, -- H:541: rgba(255,255,255,.95) -> 0 at 70%
				pulseS = 1.6, -- H:541
				size = 210, -- H:542
				shadow = { px = 10, alpha = 0.35 }, -- H:542
				floatS = 3, -- H:542: sdFloat 3s 1.2s
				floatDelayS = 1.2,
			},
			-- H:44 sdUp: 30 px lower and clear -> rest, .45 s
			up = {
				ms = 450,
				frames = { { at = 0, y = 30, alpha = 0 }, { at = 1, y = 0, alpha = 1 } } :: { MotionPose },
			},
			youGot = { delayS = 0.9, curve = "ease", textRole = "youGot" }, -- H:544
			title = { delayS = 1.0, curve = "search", textRole = "prize" }, -- H:545
			desc = { delayS = 1.1, curve = "ease", textRole = "congratsDesc" }, -- H:546
			-- H:547: 240 x 66 + lip 5, radius 20, margin-top 12, 30 px stroke 6
			button = { width = 240, face = 66, radius = 20, marginTop = 12, delayS = 1.25, curve = "search" },
			closeMs = 220, -- H:878
			closeScale = 1.08, -- H:878
			removeMs = 210, -- H:879
			margin = 12, -- reading: the letters shrink to fit the width less this on each side
		},
	},

	-- UI FINAL R8 (the Daily Rewards window, plan work/ui/PLAN.md R8; `H:n` = "Squishy Duels HUD.dc.html" line n):
	-- DailyController and UI/DailyFormat. Base px; colours are Art/Palette names; every pill and card border is drawn
	-- inside its box (CSS border-box) and every lip under its face (our lip takes room, Layout.lipGap).
	Daily = {
		body = { padTop = 18, padX = 26, padBottom = 26, gap = 16, topGap = 12 }, -- H:388-389
		-- H:390: the streak pill (#FFB25C -> #FF4F6E, inset 2 at .5), the flame raised 4 and pulsing 1 s
		streak = {
			height = 40,
			padLeft = 4,
			padRight = 16,
			gap = 6,
			border = 3,
			iconPx = 34,
			iconRaise = 4,
			pulseS = 1,
			inset = { px = 2, alpha = 0.5 },
			textRole = "streak",
		},
		-- H:391: the timer pill (the well), pushed right
		timer = { height = 40, padLeft = 4, padRight = 16, gap = 6, border = 3, iconPx = 30, textRole = "wellText" },
		grid = { columns = { 1, 1, 1, 1.25 }, gap = 14 }, -- H:393: 1fr 1fr 1fr 1.25fr x 2 rows
		compactColumns = 3, -- plan R8 (phones): 3 columns, Day 7 under them, the grid scrolls
		-- H:395-404, H:965-966: a day card (column, centred, gap 4, padding 10 8 10, border 4, radius 22, lip 5, the
		-- surface `day`); the icon 84 with its drop shadow (0 5px 0 at .25), at .5 once claimed; today's icon area
		-- pulses 1.4 s; the check 60, the lock 34 at (right 14, bottom 0); the CLAIM! chip's face 34 (Button size
		-- "chip"); sdRise .45 s, i x 50 ms apart (H:31 frames: Config.UI.motion.cardIn).
		card = {
			padTop = 10,
			padX = 8,
			padBottom = 10,
			gap = 4,
			border = 4,
			radius = 22,
			lip = 5,
			iconPx = 84,
			iconShadow = { px = 5, alpha = 0.25 },
			claimedIconAlpha = 0.5,
			pulseS = 1.4,
			checkPx = 60,
			lockPx = 34,
			lockRight = 14,
			lockBottom = 0,
			chipFace = 34,
			nameKind = "Body", -- H:396: 18 px, its colour per state (DailyFormat.cardLook)
			valueRole = "dayValue", -- H:401
			nextRole = "dayNext", -- H:403
			rise = { ms = 450, stepMs = 50, curve = "rise" },
		},
		-- H:406-416: day 7 (column 4, both rows; gap 6, padding 14 12 14, border 4 always ink, radius 24, lip 6, inset 4
		-- at .5; #FFE58A -> #F5A623 at 50% -> #9363F0; clips): the rays 640 at (50%, 46%), white .3, 18 s a turn; "Day 7";
		-- the MEGA REWARD pill (26, padding 3 10 0, border 3, #FF8A9A -> #E83A5A); the Treat Box art 170 (drop-shadow 0
		-- 8px 0 at .3, sdFloat 3 s); the twinkles 28 (left 20, top 20) and 22 (right 16, bottom 24), 2 s, .9 s apart; the
		-- lock 40 at (right 18, top 12); "Treat Box"; the foot; sdRise .5 s after .35 s.
		day7 = {
			padTop = 14,
			padX = 12,
			padBottom = 14,
			gap = 6,
			border = 4,
			radius = 24,
			lip = 6,
			inset = { px = 4, alpha = 0.5 },
			midAt = 0.5,
			rays = { px = 640, alpha = 0.3, spinS = 18, centreY = 0.46 },
			artPx = 170,
			artShadow = { px = 8, alpha = 0.3 },
			floatS = 3,
			pill = { height = 26, padTop = 3, padX = 10, border = 3, textRole = "megaReward" },
			stars = {
				{ px = 28, left = 20, top = 20, periodS = 2, delayS = 0 },
				{ px = 22, right = 16, bottom = 24, periodS = 2, delayS = 0.9 },
			} :: { { [string]: number } },
			lockPx = 40,
			lockRight = 18,
			lockTop = 12,
			titleRole = "day7Title", -- H:408
			nameRole = "day7", -- H:415
			footRole = "dayFoot", -- H:416
			rise = { ms = 500, delayMs = 350, curve = "rise" },
		},
		-- H:41 sdStamp .5 s cubic-bezier(.2,1.4,.4,1): the check drawn at its rest -10° (also the ReducedMotion rest),
		-- so the frames are relative to it (0%: -25° -> -15, 60%: -8° -> 2). Also the quest rows' check (H:372).
		stamp = {
			ms = 500,
			curve = "search",
			restRot = -10,
			frames = {
				{ at = 0, scale = 3, rot = -15, alpha = 0 },
				{ at = 0.6, scale = 0.9, rot = 2, alpha = 1 },
				{ at = 1, scale = 1, rot = 0, alpha = 1 },
			} :: { MotionPose },
		},
		claimSoundDelayMs = 120, -- H:853: the claim sound after the stamp
		boxFlow = { closeAfterMs = 750, revealAfterMs = 280 }, -- H:858: the day 7 Treat Box
	},

	-- UI FINAL R8 (the Quests window, plan R8; H:350-381): QuestController and UI/QuestFormat. Base px.
	Quests = {
		body = { padTop = 18, padX = 26, padBottom = 24, gap = 14, tabGap = 10 }, -- H:356-358
		-- H:358: a tab (46 + lip 4, padding 0 22, border 4, radius 16, inset 3 at .4; mint #9AF5D2 -> #25B886 when
		-- selected, the purple card otherwise) and its count badge (28 at (right -10, top -12), padding-top 3, sdBadge
		-- 2.4 s)
		tab = {
			face = 46,
			lip = 4,
			padX = 22,
			border = 4,
			radius = 16,
			inset = { px = 3, alpha = 0.4 },
			textRole = "tab",
			badgePx = 28,
			badgeRight = -10,
			badgeTop = -12,
			badgeS = 2.4,
		},
		-- H:359: the reset pill (the well), pushed right
		reset = { height = 36, padLeft = 4, padRight = 14, gap = 6, border = 3, iconPx = 28, textRole = "wellText" },
		-- H:361-363: rows 12 apart; a row 94 + lip 5, padding 0 14 0 12, gap 16, border 4 (#FFE36B when ready), radius
		-- 22, the surface `row`; sdRise .45 s, i x 60 ms apart; a claimed row at .6 (T15). Phones (plan R8): the reward
		-- and the chips go under the bar, the row grows by them (compactExtra, a reading).
		row = {
			face = 94,
			lip = 5,
			padLeft = 12,
			padRight = 14,
			gap = 16,
			border = 4,
			radius = 22,
			rowsGap = 12,
			claimedAlpha = 0.6,
			rise = { ms = 450, stepMs = 60, curve = "rise" },
			compactExtra = 48,
		},
		icon = { tile = 70, px = 58, border = 4, radius = 18 }, -- H:364
		-- H:365-366: the text column (gap 8): the title (20 px, the soft drop) and "x / y" (20 px, stroke 4), 10 apart,
		-- at most titleLines lines (a reading: the design has one)
		text = { gap = 8, titleGap = 10, titleRole = "trackerTitle", progressRole = "trackerProgress", titleLines = 2 },
		-- H:369: the reward pill (the well), the coin 30
		reward = { height = 40, padLeft = 4, padRight = 12, gap = 4, border = 3, iconPx = 30, textRole = "questReward" },
		-- H:370-372: CLAIM (green) / GO (cyan) 126 x 56 + lip 5, radius 16, 24 px stroke 5, CLAIM's sdPulse 1.1 s; the
		-- claimed check 52 in the 126 slot
		button = { width = 126, face = 56, lip = 5, radius = 16, textRole = "button", pulseS = 1.1 },
		checkPx = 52,
		goDelayMs = 240, -- H:755
		goWaypointSeconds = 120, -- reading: as BoxController's earn waypoint (WAYPOINT_MAX_SECONDS)
	},

	-- Grip HUD card, toasts and popups (GripController, §17.7). Timers and gameplay values are in Config.Grip.
	Grip = {
		compactRowMaxHeight = 40, -- `compact` layout: the card is one row at most this tall (base px) ...
		compactBarHeight = 4, -- ... with a bar this tall
		leftColumnMaxFraction = 0.55, -- L5 check: at 667×375 the left HUD column ends above this share of the height
		heldToastsMax = 3, -- grip.* toasts kept from Matched to Returning, then shown merged into one
	},

	-- The knead screen in Inspect (spec phase2-squeeze §1.18, §1.20, §3.7; design: the FP page html:59-77, fp.js:700).
	-- Base px under the modal's UIScale; colours are Art/Palette Knead* / Wax*. The wax HUD: a paper box hudTopPx under
	-- the stage's top edge (proposal: the design's 72 px is from its window's top), its row gap, padding, radius, ink
	-- outline and ink drop band; the coat bar's track and outline; the state word's minimum width; the count's opacity;
	-- refreshed every refreshSeconds, the bar easing over fillMs. Text is the Chip kind (16 base px): the design's 12 px
	-- Fredoka and 10.5 px DM Mono are under minTextSize at Scale.min. The vignette: an EditableImage of vignetteTexels²
	-- stretched over the stage, the CSS radial gradient (ellipse rx × ry of the stage at (cx, cy), alpha stops), fading
	-- in over vignetteMs. The fingertip ring (mouse only): ringPx over the toy, ringPressPx pressing, ringPullPx
	-- stretching; a white ringStrokePx border inside and an ink ringOutlinePx ring outside; white at
	-- ringPressTransparency while pressing, solid while stretching; its size eases over ringSizeMs.
	Knead = {
		hudTopPx = 8, -- proposal
		hudGapPx = 8, -- design: html:72
		hudPadX = 12, -- design: html:72
		hudPadY = 6, -- design: html:72
		hudRadius = 12, -- design: html:72
		hudStrokePx = 2, -- design: html:72
		hudDropPx = 3, -- design: html:72 (box-shadow 0 3px 0 ink)
		trackWidth = 96, -- design: html:75
		trackHeight = 9, -- design: html:75
		trackStrokePx = 1.5, -- design: html:75
		stateMinWidth = 58, -- design: html:77
		countTransparency = 0.4, -- opacity .6 (design: html:77)
		refreshSeconds = 0.1, -- design: fp.js:700
		fillMs = 250, -- design: html:76
		vignetteMs = 450, -- design: html:70
		vignetteTexels = 256, -- proposal (spec §3.7)
		vignette = {
			cx = 0.5, -- design: html:70 (at 50% 45%)
			cy = 0.45,
			rx = 1.25, -- design: html:70 (125% 95%)
			ry = 0.95,
			stops = { 0.44, 0.64, 1 }, -- design: html:70
			alphas = { 0, 0.1, 0.4 }, -- design: html:70
		},
		ringPx = 40, -- design: html:59
		ringPressPx = 28, -- design: html:61
		ringPullPx = 20, -- design: html:62
		ringStrokePx = 2.5, -- design: html:59
		ringOutlinePx = 2, -- design: html:59
		ringPressTransparency = 0.6, -- white at 40% (design: html:61)
		ringSizeMs = 100, -- design: html:59
	},

	-- Pens3 phase 1: the walking pen squishies, their coin labels and the own PEN SPACE sign's pop
	-- (Controllers/PenController; lobby design v6: `K:n` = kit.json line n, `P3D:n` = "Squishy Lobby 3D.html" line n).
	-- Studs and seconds. The walk area's edge margin is WorldLayout.Bases.pen.edgeMargin (shared with PenMath).
	Pen = {
		animateStuds = 60, -- K:5897 (A17): beyond this from the camera a pen's squishies stand still
		cullStuds = 220, -- [P] beyond this they are unparented (kept for later)
		-- A17 PenWanderHop (K:5890-5954): while it walks a squishy hops hopHeight × its size (its studs over the
		-- Common's, P3D:834) and back once every hopSeconds (Sine Out up, Sine In down); none under ReducedMotion.
		hopSeconds = 0.36,
		hopHeight = 0.35,
		-- P3D:398, 829-833: it walks speedMin..speedMax studs/s toward a random spot of its walk area; within
		-- arriveStuds of it, it waits waitMin..waitMax s (the first time 0..firstWaitMax s), facing the way it walked.
		speedMin = 2,
		speedMax = 3.5,
		waitMin = 1,
		waitMax = 3.5,
		firstWaitMax = 2,
		arriveStuds = 0.4,
		-- K:4266-4270: the coin label, a BillboardGui labelSize studs whose bottom is labelLift studs over the model's
		-- top, seen within labelMaxStuds (labelMaxStudsLow when MeshQuality.forCamera() is "Low"); the coin icon and
		-- the text are labelInner of its height, labelGap of its height apart; the text's outline labelStrokePx.
		labelSize = Vector2.new(3.2, 1.2),
		labelLift = 0.6,
		labelMaxStuds = 120,
		labelMaxStudsLow = 60,
		labelInner = 0.8,
		labelGap = 0.1,
		labelStrokePx = 2,
		-- K:4052-4081: the longest side of a squishy of each rarity.
		rarityStuds = { Common = 2, Uncommon = 2.8, Epic = 3.8, Exclusive = 5 } :: { [string]: number },
		-- K:5711-5747 (A13 UpgradeBuyPunch): the price face's scale after an own buy (Anim/Timeline keys).
		signPop = {
			{ t_ms = 0, value = 1 },
			{ t_ms = 80, value = 0.85, style = Enum.EasingStyle.Quad, dir = Enum.EasingDirection.Out },
			{ t_ms = 200, value = 1.15, style = Enum.EasingStyle.Back, dir = Enum.EasingDirection.Out },
			{ t_ms = 350, value = 1, style = Enum.EasingStyle.Sine, dir = Enum.EasingDirection.Out },
		},
	},

	-- UI FINAL (R1, the look kit; plan work/ui/PLAN.md §2): the sticker look of the design "Squishy Duels UI FINAL"
	-- (2026-10-14), read through UI/Theme (Theme.Sticker). Base px (1 design px = 1 base px). `H:n` = "Squishy Duels
	-- HUD.dc.html" line n. Colours are Art/Palette Sticker*; a role's `color` names a Palette token.
	Sticker = {
		-- The ink border (CSS border-box: drawn inside the box, Theme.foam's `inner`).
		border = {
			thin = 3, -- H:102 badges, pills, chips, bar tracks
			normal = 4, -- H:203 buttons, cards, rows, tabs
			heavy = 5, -- H:252 the duel bar, the window, the close X
		},
		-- The solid ink lip under a surface (box-shadow: 0 Npx 0 #1E1428), drawn inside the box under its face.
		lip = {
			bar = 3, -- H:84
			chip = 4, -- H:171
			row = 5, -- H:363
			button = 5, -- H:245
			card = 5, -- H:935
			boxCard = 6, -- H:264
			closeX = 6, -- H:252
			cta = 7, -- H:126
			search = 7, -- H:136
			window = 10, -- H:182
		},
		radius = {
			slot = 8, -- H:141
			chip = 10, -- H:232
			tile = 12, -- H:274
			tab = 14, -- H:194
			tabQuest = 16, -- H:358
			button = 18, -- H:245
			card = 20, -- H:203
			row = 22, -- H:363
			plate = 24, -- H:264
			duel = 28, -- H:126
			confirm = 30, -- H:457
			window = 32, -- H:182
		},
		-- The inset highlight along a surface's top (box-shadow: inset 0 Hpx 0 rgba(255,255,255,a)) and the bevel along
		-- its bottom (inset 0 -Bpx 0 rgba(c,b); c is black unless UI/Theme names a tint for the surface). Theme paints
		-- them as solid bands: the top stop lerped to white by highlightAlpha, the end stop lerped to c by bevelAlpha.
		-- The tints: duel StickerDuelBevel, found StickerFoundBevel (Art/Palette). No squeeze surface: the squeeze
		-- button stays removed (the user's Q2).
		surfaces = {
			primary = { highlightPx = 3, highlightAlpha = 0.55, bevelPx = 6, bevelAlpha = 0.15 }, -- H:245, H:247
			disabled = { highlightPx = 3, highlightAlpha = 0.2 }, -- H:246
			cancel = { highlightPx = 3, highlightAlpha = 0.3 }, -- H:462
			again = { highlightPx = 3, highlightAlpha = 0.6, bevelPx = 6, bevelAlpha = 0.15 }, -- H:498
			duel = { highlightPx = 4, highlightAlpha = 0.6, bevelPx = 8, bevelAlpha = 0.3 }, -- H:126
			found = { highlightPx = 4, highlightAlpha = 0.65, bevelPx = 8, bevelAlpha = 0.25 }, -- H:149
			close = { highlightPx = 4, highlightAlpha = 0.5, bevelPx = 6, bevelAlpha = 0.18 }, -- H:252
			badge = { highlightPx = 2, highlightAlpha = 0.5 }, -- H:102
			badgeMark = { highlightPx = 2, highlightAlpha = 0.6 }, -- H:120: the daily "!" badge
			coinPill = { highlightPx = 3, highlightAlpha = 0.14 }, -- H:75
			search = { highlightPx = 4, highlightAlpha = 0.12 }, -- H:136
			toast = { highlightPx = 3, highlightAlpha = 0.35 }, -- H:175
			qpop = { highlightPx = 3, highlightAlpha = 0.45 }, -- H:162
			row = { highlightPx = 3, highlightAlpha = 0.1 }, -- H:363, H:433: quest and settings rows
			card = { highlightPx = 2, highlightAlpha = 0.1 }, -- H:935: the squishy cards
			day = { highlightPx = 3, highlightAlpha = 0.2 }, -- H:395: the day cards (UI FINAL R8)
			chip = { highlightPx = 2, highlightAlpha = 0.55 }, -- H:402: Button size "chip" (UI FINAL R2, P12)
		} :: { [string]: StickerSurface },
		-- Text roles (Theme.stickerText): the kind (Config.UI.TextSize), the CSS -webkit-text-stroke width (the ink
		-- outline is half of it), the solid ink drop under the letters (text-shadow: 0 Npx 0 #1E1428; a mirrored copy,
		-- only from 3 px) and a Palette colour (default white). UI FINAL R2 (T5, PR3): `soft` = the design's thin soft
		-- drop (text-shadow: 0 Npx 0 rgba(c, a) of 1-2 px): a copy px lower in the Palette colour (default the ink) at
		-- alpha, no outline, behind the letters, which keep the game's thinnest ink outline (stroke 3 = 1.5 px).
		text = {
			windowTitle = { kind = "Window", stroke = 9, drop = 5 }, -- H:184
			settingsTitle = { kind = "WindowSmall", stroke = 8, drop = 5 }, -- H:429
			duel = { kind = "Duel", stroke = 8, drop = 4 }, -- H:130
			navLabel = { kind = "D23", stroke = 7, drop = 3 }, -- H:101 (23 px, PR2)
			settingsLabel = { kind = "D19", stroke = 6, drop = 3 }, -- H:159 (19 px, PR2)
			coin = { kind = "Coin", stroke = 6, drop = 3, color = "StickerCoinText" }, -- H:79
			found = { kind = "Found", stroke = 7, drop = 4 }, -- H:151
			hero = { kind = "Hero", stroke = 8, drop = 4 }, -- H:95
			revealBox = { kind = "Hero", stroke = 8, drop = 5 }, -- H:483
			detailName = { kind = "Name", stroke = 7, drop = 4 }, -- H:227
			confirmTitle = { kind = "Name", stroke = 7, drop = 4 }, -- H:459
			boxName = { kind = "Title", stroke = 6, drop = 4 }, -- H:269
			day7 = { kind = "Large", stroke = 7, drop = 4 }, -- H:415
			ribbon = { kind = "Ribbon", stroke = 7, drop = 4 }, -- H:527
			-- UI FINAL R6 (the Shop window): the featured name (H:308) and line (H:309: 15 px -> 16, PR2; white with a
			-- soft drop, PR3's thinnest outline), the featured BUY (H:310) and OWNED (H:311), the section heads (H:315),
			-- a coin pack's amount (H:338) and price (H:339), the confirm dialog's description (H:460: 16 px 600
			-- #F3EDFF), "You got" (H:544), the congrats description (H:546: 19 px, soft drop 0 2 .7) and AWESOME! (H:547).
			featuredName = { kind = "Found", stroke = 8, drop = 4 }, -- H:308
			featuredLine = { kind = "Small", stroke = 3, soft = { px = 2, alpha = 0.6 } }, -- H:309
			buyFeatured = { kind = "Large", stroke = 6 }, -- H:310
			ownedBar = { kind = "HudNumber", stroke = 6 }, -- H:311 (26 px)
			sectionHead = { kind = "H2", stroke = 5, color = "StickerCoinText" }, -- H:315
			packAmount = { kind = "Big", stroke = 6, drop = 3 }, -- H:338
			packPrice = { kind = "Body", stroke = 4 }, -- H:339 (18 px)
			confirmDesc = { kind = "Small", stroke = 3, color = "StickerTextSoft" }, -- H:460
			youGot = { kind = "Big", stroke = 6 }, -- H:544
			congratsDesc = { kind = "D19", stroke = 3, soft = { px = 2, alpha = 0.7 } }, -- H:546
			awesome = { kind = "Title", stroke = 6 }, -- H:547
			revealName = { kind = "Reveal", stroke = 10, drop = 6 }, -- H:490
			congrats = { kind = "Congrats", stroke = 13, drop = 6 }, -- H:539
			prize = { kind = "Prize", stroke = 10, drop = 6, color = "StickerCoinText" }, -- H:545
			button = { kind = "Big", stroke = 5 }, -- H:370, H:462
			buttonLarge = { kind = "HudNumber", stroke = 6 }, -- H:246 (26 px)
			tab = { kind = "H2", stroke = 5 }, -- H:358
			badge = { kind = "Body", stroke = 3 }, -- H:102 (18 px)
			badgeMark = { kind = "Button", stroke = 4 }, -- H:120 (the daily "!", 20 px)
			small = { kind = "Small", stroke = 4 }, -- H:89 (14 px -> 16)
			gripText = { kind = "Small", stroke = 3.5 }, -- H:87 (12 px -> 16)
			-- UI FINAL R2: UI/UiFx.float's numbers (lib:259: a 6 px stroke and a 3 px drop; the call gives the size).
			float = { kind = "Title", stroke = 6, drop = 3 },
			-- UI FINAL R2: the toast's text (H:175: 18 px white, text-shadow 0 2px 0 rgba(30,20,40,.6); R9 draws it).
			toastText = { kind = "Body", stroke = 3, soft = { px = 2, alpha = 0.6 } },
			-- Match HUD M6 / M7 (2026-10-17; M = "Squishy Duels Match HUD.dc.html"): a kill feed name (M:124: 17 px,
			-- stroke 4; its colour is the player's) and tag (M:132: 13 px -> 16, stroke 3); the card's FINAL KILL chip
			-- (M:158: 16 px, stroke 4), name pills (M:159: 15 px -> 16, stroke 3.5), "squished by" (M:160: stroke 4), the
			-- squishy's name (M:168: 36 px, stroke 8, drop 4) and title (M:169: 15 px -> 16, soft drop 0 2 .65), the
			-- killer's name (M:179: 26 px, stroke 6), @handle (M:180: 14 px -> 16 #E9E1FF; PR3's thinnest outline), the
			-- Grip / streak numbers (M:183: 24 px, stroke 5) and captions (M:184: 11 px -> 16 #E9E1FF); RESPAWNING IN
			-- (M:197: 20 px, stroke 5) and its number (40 px #FFE36B, stroke 8, drop 4).
			matchFeedName = { kind = "D17", stroke = 4 },
			matchFeedTag = { kind = "Small", stroke = 3 },
			matchCardFinal = { kind = "Chip", stroke = 4 },
			matchCardPill = { kind = "Small", stroke = 3.5 },
			matchCardBy = { kind = "Small", stroke = 4 },
			matchCardName = { kind = "Found", stroke = 8, drop = 4 },
			matchCardTitle = { kind = "Small", stroke = 3, soft = { px = 2, alpha = 0.65 } },
			matchCardKiller = { kind = "HudNumber", stroke = 6 },
			matchCardHandle = { kind = "Small", stroke = 3, color = "MatchCardHandle" },
			matchCardStat = { kind = "Big", stroke = 5 },
			matchCardCaption = { kind = "Small", stroke = 3, color = "MatchCardHandle" },
			matchRespawnLabel = { kind = "Button", stroke = 5 },
			matchRespawnNumber = { kind = "Hero", stroke = 8, drop = 4, color = "StickerCoinText" },
			-- UI FINAL R4 (the lobby HUD): "Join the queue" (H:131: 17 px white, text-shadow 0 2px 0
			-- rgba(120,10,50,.55); PR3 adds the 1.5 px ink outline), the "GRIP" tag over the level (H:94: 18 px
			-- #9AF5D2, stroke 5), the Double Grip chip (H:89: 14 px -> 16, #FFE36B, stroke 4), the search bar's time
			-- (H:139: 16 px #FFE36B; PR3 outline), the quest tracker's title (the quest row's H:366: 20 px white,
			-- text-shadow 0 2px 0 rgba(30,20,40,.5); PR3 outline) and its progress (H:366: 20 px, stroke 4).
			duelSub = { kind = "D17", stroke = 3, soft = { px = 2, alpha = 0.55, color = "StickerDuelSubDrop" } },
			gripTag = { kind = "Body", stroke = 5, color = "StickerMintTop" },
			boost = { kind = "Small", stroke = 4, color = "StickerCoinText" },
			searchTime = { kind = "Small", stroke = 3, color = "StickerCoinText" },
			trackerTitle = { kind = "Button", stroke = 3, soft = { px = 2, alpha = 0.5 } },
			trackerProgress = { kind = "Button", stroke = 4 },
			-- UI FINAL R8 (the Daily and Quests windows): the streak (H:390: 19 px, stroke 4); the well pills' text (H:359,
			-- H:391: 14-15 px -> 16 (PR2) #F3EDFF, PR3's thinnest outline); a day's value (H:401: 22 px, stroke 5) and
			-- "Tomorrow" (H:403: 14 px -> 16 #FFE36B); "Day 7" (H:408: 26 px, stroke 6); MEGA REWARD (H:409: 12 px -> 16);
			-- the day 7 foot (H:416: 14 px -> 16 white, soft drop 0 2 .6); a quest's reward (H:369: 19 px #FFE36B, stroke
			-- 4); the tab badge's count (H:358: 15 px -> 16, stroke 3).
			streak = { kind = "D19", stroke = 4 },
			wellText = { kind = "Small", stroke = 3, color = "StickerTextSoft" },
			dayValue = { kind = "H2", stroke = 5 },
			dayNext = { kind = "Small", stroke = 3, color = "StickerCoinText" },
			day7Title = { kind = "HudNumber", stroke = 6 },
			megaReward = { kind = "Small", stroke = 3 },
			dayFoot = { kind = "Small", stroke = 3, soft = { px = 2, alpha = 0.6 } },
			questReward = { kind = "D19", stroke = 4, color = "StickerCoinText" },
			tabBadge = { kind = "Small", stroke = 3 },
			-- UI FINAL R9: a Settings row's label (H:435: 20 px white; PR3's thinnest outline), its On / Off (H:436:
			-- 14 px -> 16 #EDE4FF) and the volume's value (H:447: 20 px, stroke 4); the quest pop's tag (H:162: 13 px
			-- -> 16 #E6FFF4, stroke 3) and title (H:162: 19 px, stroke 5); the level-up's unlock line (H:531: 28 px,
			-- stroke 7, drop 4).
			settingsRow = { kind = "Button", stroke = 3 },
			settingsState = { kind = "Small", stroke = 3, color = "StickerTextMuted" },
			settingsValue = { kind = "Button", stroke = 4 },
			qpopTag = { kind = "Small", stroke = 3, color = "StickerQuestPopText" },
			qpopTitle = { kind = "D19", stroke = 5 },
			levelUnlock = { kind = "Large", stroke = 7, drop = 4 },
			-- UI FINAL R5 (the Squishies window): the header pill's count (H:188: 20 px #FFE36B, stroke 4); the tab and
			-- card name (H:194, H:208: 15 px -> 16 (PR2) white, text-shadow 0 2px 0 rgba(30,20,40,.5); PR3 outline); the
			-- rarity and EQUIPPED pills (H:209, H:228-229: 11-12 px -> 16, text-shadow 0 1px 0 at .5); the Equipped
			-- ribbon (H:210: 12 px -> 16, 0 1px 0 at .6); NEW (H:211: 15 px -> 16, stroke 3).
			collectedCount = { kind = "Button", stroke = 4, color = "StickerCoinText" },
			tabLabel = { kind = "Small", stroke = 3, soft = { px = 2, alpha = 0.5 } },
			cardName = { kind = "Small", stroke = 3, soft = { px = 2, alpha = 0.5 } },
			rarityPill = { kind = "Small", stroke = 3, soft = { px = 1, alpha = 0.5 } },
			cardRibbon = { kind = "Small", stroke = 3, soft = { px = 1, alpha = 0.6 } },
			cardNew = { kind = "Small", stroke = 3 },
			-- UI FINAL R7 (the Boxes window and the box reveal): OPEN (H:277: 27 px, stroke 6) and its price (H:278: 19 px,
			-- stroke 4), an odds row's percent (H:271: 14 px -> 16 white, PR3's thinnest outline), the tap hint (H:484:
			-- 22 px #FFE36B, stroke 5), the drag hint (H:495: 17 px, stroke 4), AGAIN (H:498: 24 px, stroke 6) and its
			-- price (20 px, stroke 5).
			boxOpen = { kind = "Open", stroke = 6 },
			boxPrice = { kind = "D19", stroke = 4 },
			oddsPct = { kind = "Small", stroke = 3 },
			tapHint = { kind = "H2", stroke = 5, color = "StickerCoinText" },
			dragHint = { kind = "D17", stroke = 4 },
			againLabel = { kind = "Big", stroke = 6 },
			againPrice = { kind = "Button", stroke = 5 },
			-- 2026-10-16 (the coin pill's "+", plan [UD5]): its "+" (H:80: 28 px white, -webkit-text-stroke 4px, no
			-- drop).
			coinPlus = { kind = "Large", stroke = 4 },
		} :: { [string]: StickerTextRole },
		-- UI FINAL R5 (UI/Components/RarityTag variants, PR2: a 16 px label grows a pill only by the measured extra): the
		-- card pill (H:209: 22 border-box, padding 2 9 0, border 3, the rarity's card colour, pips beside it) and the
		-- detail pill (H:228: 26, padding 3 11 0, the rarity's own colour, no pips). R7 adds the odds and reveal pills.
		pills = {
			card = { height = 22, padTop = 2, padX = 9, border = 3 },
			detail = { height = 26, padTop = 3, padX = 11, border = 3 },
		} :: { [string]: StickerVariant },
		-- UI FINAL R5 (PR23, UI/Components/StatePill: the loading, data-error and filter-empty states of every window):
		-- the design's timer pill (H:391): 40 high, padding 0 16 0 4, gap 6, border 3, full radius, the icon 30.
		statePill = { height = 40, padLeft = 4, padRight = 16, gap = 6, border = 3, iconPx = 30 } :: StickerVariant,
		-- Q5 (the user, 2026-10-14): big button labels in capitals (a display transform; Strings stay as they are).
		buttonCaps = true,
		-- UI/Components/ProgressBar variants: the track's border, its alpha (the Grip track is white at .7), an inner
		-- shade along its top (troughShade), and the fill's top highlight; colours in ProgressBar (Palette). UI FINAL
		-- R2 (P9, G2.5): `height` is the design's border-box height (the border drawn inside it; the default heightPx),
		-- the fill eases over fillMs with barFillCurve (H:85, H:187, H:240, H:367; the odds and volume fills have no
		-- transition, H:271, H:444: they jump), the Grip fill is never narrower than minFillPx (H:85 min-width), and
		-- barShines names the moving strip a bar draws (shines).
		bars = {
			grip = { -- H:84-85
				height = 14,
				border = 3,
				troughAlpha = 0.7,
				fillHighlightPx = 3,
				fillHighlightAlpha = 0.55,
				fillMs = 550,
				minFillPx = 10,
			},
			stat = { height = 14, border = 3, fillHighlightPx = 3, fillHighlightAlpha = 0.45, fillMs = 600 }, -- H:240
			quest = { -- H:367
				height = 20,
				border = 3,
				troughShadePx = 3,
				troughShadeAlpha = 0.35,
				fillHighlightPx = 4,
				fillHighlightAlpha = 0.5,
				fillMs = 600,
			},
			-- H:271: no transition (the fill jumps)
			odds = { height = 12, border = 3, fillHighlightPx = 2, fillHighlightAlpha = 0.4, fillMs = 0 },
			collected = { height = 16, border = 3, fillMs = 600 }, -- H:187
			volume = { height = 20, border = 3, fillHighlightPx = 3, fillHighlightAlpha = 0.5, fillMs = 0 }, -- H:444
		} :: { [string]: StickerVariant },
		barFillCurve = "bars", -- H:85, H:187, H:240, H:367
		barShines = { grip = "grip", quest = "quest" } :: { [string]: string }, -- H:85, H:367
		-- UI FINAL R2 (G4.13, P2): the moving shine strips (sdShine, H:28; Anim/UiIdle's "shine"): px wide, white at
		-- alpha in its middle (a UIGradient at Rotation slantDeg for skewX(-20deg)), one pass every periodS; the CTA's
		-- runs overhangPx past the face's top and bottom inside a holder inset by its border (H:127).
		shines = {
			cta = { px = 54, alpha = 0.6, periodS = 3.4, overhangPx = 10, slantDeg = 20 }, -- H:127
			grip = { px = 22, alpha = 0.75, periodS = 2.6, overhangPx = 0, slantDeg = 20 }, -- H:85
			quest = { px = 26, alpha = 0.7, periodS = 3, overhangPx = 0, slantDeg = 20 }, -- H:367
		} :: { [string]: StickerVariant },
		-- UI/Components/Toggle's two switches: size, border, the knob (size, border, its top inset and left edge off /
		-- on, inside the border), the knob's drop (small) or bevel (large), the track's top shade (large). UI FINAL R2
		-- (G1.1, P7): the knob slides over knobMs (toggleKnobCurve, H:197, H:437) and the track's colour eases over
		-- trackMs (toggleTrackCurve: H:197 transition .2s, H:437 .25s).
		toggles = {
			small = { -- H:197, H:1010 (the Squishies "Show locked" switch)
				width = 56,
				height = 32,
				border = 4,
				knob = 20,
				knobBorder = 0,
				knobTop = 2,
				knobOff = 3,
				knobOn = 26,
				knobDropPx = 2,
				knobDropAlpha = 0.4,
				knobMs = 300, -- H:197
				trackMs = 200, -- H:197
			},
			large = { -- H:437, H:980 (the Settings switches)
				width = 80,
				height = 42,
				border = 4,
				knob = 28,
				knobBorder = 3,
				knobTop = 3,
				knobOff = 4,
				knobOn = 40,
				knobBevelPx = 3,
				knobBevelAlpha = 0.12,
				trackShadePx = 3,
				trackShadeAlpha = 0.25,
				knobMs = 350, -- H:437
				trackMs = 250, -- H:437
			},
		} :: { [string]: StickerVariant },
		toggleKnobCurve = "switch", -- H:197, H:437
		toggleTrackCurve = "ease", -- H:197, H:437
		-- UI FINAL R9 (plan work/ui/PLAN.md R9; `H:n` = "Squishy Duels HUD.dc.html" line n): the Settings window's
		-- body and rows (H:431-447, Controllers/SettingsController, UI/Components/Toggle's row look): the body's
		-- padding and the rows' gap (H:431); a row 74 + the 5 px lip, padding 0 16 0 10, gap 14, border 4, radius 20,
		-- the row surface (H:433); the icon 50 (H:434); the large switch (H:437); the volume row's slider area 44 and
		-- its value 48 wide (H:443-447).
		settings = {
			bodyPad = { top = 20, x = 26, bottom = 24 }, -- H:431: padding 20px 26px 24px
			rowGap = 12, -- H:431
			row = { face = 74, lip = 5, padLeft = 10, padRight = 16, gap = 14, border = 4, radius = 20 }, -- H:433
			icon = 50, -- H:434, H:441
			volume = { area = 44, value = 48 }, -- H:443, H:447
		},
		-- UI FINAL R9 (H:174-175): a toast pill: 52 + the 5 px lip, border 4, full radius, padding 0 20 0 8, the
		-- picture 40 (contain), gap 10, the toastText role (18 px white, the soft drop); the column's gap 8 (H:174).
		-- Reading: a toast with no picture pads its text padRight on both sides; a text too long for the column wraps
		-- and the pill grows by its extra lines.
		toast = {
			face = 52, -- H:175
			lip = 5, -- H:175
			border = 4, -- H:175
			padLeft = 8, -- H:175
			padRight = 20, -- H:175
			gap = 10, -- H:175
			icon = 40, -- H:175
			columnGap = 8, -- H:174
			textRole = "toastText", -- H:175
		},
		-- UI FINAL R9 (G9.1-G9.3, H:161-162, H:739): the quest-complete pop: 60 + the 5 px lip, border 4, full radius,
		-- padding 0 18 0 8, gap 10, the check 42, the two lines 3 apart (qpopTag over qpopTitle); the chime 150 ms
		-- after it shows (H:739).
		qpop = {
			face = 60, -- H:162
			lip = 5, -- H:162
			border = 4, -- H:162
			padLeft = 8, -- H:162
			padRight = 18, -- H:162
			gap = 10, -- H:162
			check = 42, -- H:162
			textGap = 3, -- H:162
			chimeDelayMs = 150, -- H:739
		},
		-- UI FINAL R9 (G9.10-G9.25, UD8: the user's Q3, the design's whole show; UI/LevelUpShow): every number of the
		-- level-up show (H:506-535, its keyframes H:44-65, the timers H:715-731, the lists H:999-1002), base px of the
		-- design's 1440 x 810 canvas (the UI scale). `frames` are the @keyframes as poses (Anim/Tweens.poseAt), each
		-- segment eased `curve` unless the design gives the whole animation one timing function.
		levelUp = {
			layer = { name = "SD_LevelUp", displayOrder = 24, insets = Enum.ScreenInsets.None }, -- H:506-507 (z 25)
			lifeMs = 4200, -- H:730
			centreY = 0.44, -- H:509, H:511
			-- G9.15 (PR1, H:624): the content's box kept fitMargin inside the safe area at most (a UIScale <= 1)
			fit = { width = 500, height = 560, margin = 32 },
			scrim = { innerAlpha = 0.5, outerAlpha = 0.6, outerAt = 0.72, fadeMs = 300, curve = "ease" }, -- H:508
			rays = { -- H:509, H:49: sdLvRays 4.2 s linear (the whole show)
				px = 1600,
				curve = "linear",
				frames = {
					{ at = 0, alpha = 0, scale = 0.3, rot = 0 },
					{ at = 0.23, alpha = 0, scale = 0.3, rot = 0 },
					{ at = 0.3, alpha = 1, scale = 1, rot = 15 },
					{ at = 1, alpha = 1, scale = 1.05, rot = 110 },
				} :: { MotionPose },
			},
			bubbles = { -- H:510, H:1000 (randomised once per session and kept); loops.lvBubble's frames
				n = 16,
				xFrom = 4, -- % of the width: 4 + 6 i + 0..4
				xStep = 6,
				xJitter = 4,
				sizeFrom = 18, -- px: 18 + 0..38
				sizeJitter = 38,
				bottom = -90, -- H:510: bottom -90px
				border = 2, -- H:510: 2px solid rgba(255,255,255,.8)
				borderAlpha = 0.8,
				periodFrom = 2.4, -- s: 2.4 + 0..1.6
				periodJitter = 1.6,
				delayFrom = 1.0, -- s: 1 + 0..1.8
				delayJitter = 1.8,
				dotShare = 0.12, -- H:510: radial-gradient(circle at 32% 30%, #fff 0 12%, ...): the fallback's dot
				dotX = 0.32,
				dotY = 0.3,
			},
			suck = { -- H:512, H:1001, H:54: sdLvSuck .45 s ease-in
				n = 10,
				stepDeg = 36,
				px = 18,
				border = 3,
				delayS = 0.55, -- + (i mod 3) x delayStepS
				delayStepS = 0.05,
				delayCycle = 3,
				ms = 450,
				curve = "easeIn",
				colors = { "StickerCoinText", "StickerMintTop", "StickerPinkSoft", "StickerFxPurple", "White" },
				frames = {
					{ at = 0, x = 250, scale = 1.4, alpha = 0 },
					{ at = 0.3, alpha = 1 },
					{ at = 1, x = 30, scale = 0.4, alpha = 0 },
				} :: { MotionPose },
			},
			ring = { -- H:513, H:52-53: sdLvRing 4.2 s ease; the arc's sdLvFill .45 s cubic-bezier(.5,0,.9,.6) .55 s
				box = 340,
				r = 150,
				inkPx = 30,
				whitePx = 18,
				whiteAlpha = 0.25,
				arcPx = 18,
				arcDelayMs = 550,
				arcMs = 450,
				arcCurve = "ringFill",
				dashPx = 6, -- the pink dashed ring (img.fx.dashRing, pack 2; none while it has no id): stroke 6, 14 / 22
				curve = "ease",
				frames = {
					{ at = 0, alpha = 0, scale = 0.6 },
					{ at = 0.1, alpha = 0, scale = 0.6 },
					{ at = 0.13, alpha = 1, scale = 1 },
					{ at = 0.22, scale = 0.96 },
					{ at = 0.235, alpha = 1, scale = 1.04 },
					{ at = 0.28, alpha = 0, scale = 1.7 },
					{ at = 1, alpha = 0, scale = 1.7 },
				} :: { MotionPose },
			},
			flash = { -- H:514, H:55: sdLvFlash .55 s ease-out 1 s both (PR17: at most Config.Vfx.Flash's opacity)
				px = 300,
				delayMs = 1000,
				ms = 550,
				curve = "easeOut",
				midAt = 0.6, -- the fallback's 60% stop (StickerFlashGlow at .8); #fff to 40%, clear at 72%
				midAlpha = 0.8,
				frames = { { at = 0, alpha = 1, scale = 0.2 }, { at = 1, alpha = 0, scale = 3 } } :: { MotionPose },
			},
			stars = { -- H:515, H:1002: sdLvTw .5 s cubic-bezier(.2,1.5,.4,1) 1.1 + .07 i s; sdLvPulse from 1.6 + .15 i s
				offsets = {
					{ x = -215, y = -70, px = 44 },
					{ x = 175, y = -100, px = 38 },
					{ x = -170, y = 60, px = 34 },
					{ x = 190, y = 40, px = 46 },
					{ x = -90, y = -170, px = 30 },
					{ x = 110, y = -175, px = 34 },
				},
				ms = 500,
				delayS = 1.1,
				stepS = 0.07,
				curve = "stars",
				pulseDelayS = 1.6,
				pulseStepS = 0.15,
				frames = {
					{ at = 0, alpha = 0, scale = 0, rot = -120 },
					{ at = 1, alpha = 1, scale = 1, rot = 0 },
				} :: { MotionPose },
			},
			number = { -- H:516-519, H:56-58
				width = 400,
				height = 224,
				textSize = 100, -- Roblox's TextSize cap; times `scale` = the design's 210 px
				scale = 2.1,
				inkStroke = 10, -- on screen: -webkit-text-stroke 20px behind the fill
				drop = 12, -- H:518: text-shadow 0 12px 0 #1E1428
				delayMs = 1000, -- sdLvInflate .7 s cubic-bezier(.2,1.4,.4,1) 1 s
				ms = 700,
				curve = "search",
				jellyDelayS = 1.8, -- sdLvJelly 1.6 s ease-in-out 1.8 s infinite (loops.lvJelly)
				gradPeriodS = 2.4, -- sdLvGrad 2.4 s ease-in-out infinite alternate
				gradCurve = "easeInOut",
				gradShare = 1 / 2.2, -- background-size 220%
				gradStops = { -- H:519
					{ pos = 0, color = "StickerLevelGradTop" },
					{ pos = 0.22, color = "StickerCoinText" },
					{ pos = 0.44, color = "StickerPinkSoft" },
					{ pos = 0.62, color = "StickerFxPurple" },
					{ pos = 0.8, color = "StickerMintTop" },
					{ pos = 1, color = "StickerCoinText" },
				},
				frames = {
					{ at = 0, alpha = 0, sx = 0, sy = 0 },
					{ at = 0.4, alpha = 1, sx = 1.4, sy = 0.78 },
					{ at = 0.6, sx = 0.84, sy = 1.22 },
					{ at = 0.8, sx = 1.08, sy = 0.95 },
					{ at = 1, alpha = 1, sx = 1, sy = 1 },
				} :: { MotionPose },
			},
			squishy = { -- H:522-523, H:50-51: sdLvSq 4.2 s ease; sdLvIdle from 1.6 s (loops.lvIdle)
				px = 160,
				shadow = { px = 6, alpha = 0.45 }, -- H:523: drop-shadow(0 6px 0 rgba(30,20,40,.45))
				curve = "ease",
				idleDelayS = 1.6,
				frames = {
					{ at = 0, alpha = 0, y = -560, sx = 0.9, sy = 1.1, rot = 0 },
					{ at = 0.04, alpha = 0, y = -560, sx = 0.9, sy = 1.1, rot = 0 },
					{ at = 0.05, alpha = 1, y = -560, sx = 0.9, sy = 1.1, rot = 0 },
					{ at = 0.11, y = 0, sx = 1.32, sy = 0.66, rot = 0 },
					{ at = 0.135, y = -28, sx = 0.9, sy = 1.12, rot = 0 },
					{ at = 0.155, y = 0, sx = 1.08, sy = 0.94, rot = 0 },
					{ at = 0.17, y = 0, sx = 0.86, sy = 1.1, rot = -4 },
					{ at = 0.19, y = 0, sx = 0.74, sy = 1.2, rot = 4 },
					{ at = 0.21, y = 0, sx = 0.64, sy = 1.3, rot = -5 },
					{ at = 0.23, y = 0, sx = 0.54, sy = 1.42, rot = 5 },
					{ at = 0.24, y = 0, sx = 1.35, sy = 0.6, rot = 0 },
					{ at = 0.29, y = -260, sx = 0.6, sy = 0.6, rot = -340 },
					{ at = 0.33, y = -186, sx = 0.62, sy = 0.48, rot = -360 },
					{ at = 0.36, alpha = 1, y = -200, sx = 0.55, sy = 0.55, rot = -360 },
					{ at = 1, alpha = 1, y = -200, sx = 0.55, sy = 0.55, rot = -360 },
				} :: { MotionPose },
				-- its brightness 1 -> 1.6 (23%) -> 2 (24%) -> none (29%): a white copy at brightness - 1 (G4.6's mapping)
				glow = {
					{ at = 0, alpha = 0 },
					{ at = 0.23, alpha = 0.6 },
					{ at = 0.24, alpha = 1 },
					{ at = 0.29, alpha = 0 },
					{ at = 1, alpha = 0 },
				} :: { MotionPose },
			},
			ribbon = { -- H:525-527, H:59-61
				width = 460,
				height = 84,
				y = 100,
				band = { x = 32, y = 8, width = 396, height = 60, radius = 10, stroke = 5 }, -- H:526
				gloss = { x = 42, y = 15, width = 376, height = 10, radius = 5, alpha = 0.4 }, -- H:526
				unfurlDelayMs = 1150, -- sdLvUnfurl .5 s cubic-bezier(.2,1.3,.4,1) 1.15 s
				unfurlMs = 500,
				unfurlCurve = "rise",
				grow = 20, -- clip-path inset(-20px): the clip reaches 20 px past the ribbon on every side
				unfurl = {
					{ at = 0, sx = 0, sy = 84 / 124, scale = 0.8 },
					{ at = 0.7, sx = 1, sy = 1, scale = 1.08 },
					{ at = 1, sx = 1, sy = 1, scale = 1 },
				} :: { MotionPose },
				letterDelayS = 1.3, -- sdLvLetIn .45 s cubic-bezier(.2,1.5,.4,1) 1.3 + .035 i s (H:999)
				letterStepS = 0.035,
				letterMs = 450,
				letterCurve = "stars",
				letterRole = "ribbon", -- H:527: 38 px, stroke 7, drop 4
				letter = {
					{ at = 0, alpha = 0, y = 30, scale = 0.3 },
					{ at = 0.6, alpha = 1, y = -10, scale = 1.25 },
					{ at = 1, alpha = 1, y = 0, scale = 1 },
				} :: { MotionPose },
			},
			pill = { -- H:529-530: the column at (-150, 196), 300 wide, gap 10; the pill padding 8 20, gap 10, border 3
				y = 196,
				width = 300,
				columnGap = 10,
				padY = 8,
				padX = 20,
				gap = 10,
				border = 3,
				kind = "Big", -- 24 px, no outline
				delayMs = 1500, -- sdUp .45 s cubic-bezier(.2,1.4,.4,1) 1.5 s
				ms = 450,
				curve = "search",
			},
			unlock = { gift = 44, gap = 8, role = "levelUnlock", delayMs = 1750, ms = 500, curve = "search" }, -- H:531
			up = { { at = 0, alpha = 0, y = 30 }, { at = 1, alpha = 1, y = 0 } } :: { MotionPose }, -- H:44: sdUp
			exit = { -- H:65, H:507: sdLvWrap 4.2 s ease: whole until 88%, then out to 0 at 1.3 about the screen centre
				curve = "ease",
				frames = {
					{ at = 0, alpha = 1, scale = 1 },
					{ at = 0.88, alpha = 1, scale = 1 },
					{ at = 1, alpha = 0, scale = 1.3 },
				} :: { MotionPose },
			},
		},
		-- UI FINAL R4 (the lobby HUD, plan work/ui/PLAN.md R4; `N:n` = Diego's newer "Squishy Duels TDMFFA animations
		-- and hud/Squishy Duels HUD.dc.html" line n, its DUEL mode picker): the design's spots and parts in base px,
		-- read through UI/HudFormat.COLUMN (the layout maths) and the HUD controllers. Phones (the compact class) keep
		-- the game's own spots (COLUMN.edge); every other size uses these.
		hud = {
			left = { x = 24, y = 18, gap = 14 }, -- H:74: the coin pill and the Grip row's column
			coins = { -- H:75-81
				face = 58,
				minWidth = 220,
				padLeft = 68,
				padRight = 10,
				gap = 12,
				coinPx = 78, -- H:78
				coinX = -14,
				coinY = -12,
				glowPx = 106, -- H:76
				glowX = -28,
				glowY = -26,
				raysPx = 146, -- H:77
				raysX = -48,
				raysY = -46,
				raysAlpha = 0.9, -- H:77
				haloPx = 10, -- H:568: drop-shadow(0 0 10px #FFF3A0) around the coin
			},
			-- 2026-10-16 (the coin pill's "+", owner yes "Add it", plan [UD5]): the green "+" at the pill's right end
			-- (H:80: 36 x 36 border-box, border 3, radius 12, inset 0 3px 0 rgba(255,255,255,.6), 0 3px 0 #1E1428), a
			-- part of the pill (H:75's one tap target), so it has no tap target of its own.
			coinPlus = { -- H:80
				face = 36,
				border = 3,
				radius = 12,
				lip = 3,
				highlightPx = 3,
				highlightAlpha = 0.6,
			},
			grip = { -- H:82-90
				pull = 4, -- H:82 margin-top -4
				padLeft = 6,
				gap = 10,
				barWidth = 200, -- H:83
				barGap = 3,
				boostRaise = 14, -- H:89 margin-top -14
				boostGap = 2,
				boltPx = 22,
				boltPulseS = 1, -- H:89 sdPulse 1s
				squash = 0.3, -- H:707: FX.squash(grip, .3) on each Grip gain (buttonPress.amount x this)
			},
			gripFloat = { top = 300, gap = 6, periodS = 3.6 }, -- H:92-96
			nav = { -- H:98-120
				x = 14,
				y = 150,
				width = 118,
				height = 104,
				iconPx = 92,
				labelPull = 28, -- H:101 margin-top -28
				shadowPx = 5, -- H:100 drop-shadow(0 5px 0 rgba(30,20,40,.3))
				shadowAlpha = 0.3,
				bobS = 3.1, -- H:100 sdBob 3.1s, each tile .3 s later (H:105-118)
				bobStepS = 0.3,
				badgeRight = 8, -- H:102: right 8, top 0
				badgeTop = 0,
			},
			-- H:102, H:115, H:120: the badges' sdBadge delays (Squishies 0, Quests .4, Daily .8)
			badgeDelays = { squishies = 0, quests = 0.4, daily = 0.8 } :: { [string]: number },
			right = { edge = 22, top = 16, gap = 12 }, -- H:156
			settings = { -- H:157-159
				width = 92,
				height = 90,
				iconPx = 70,
				labelPull = 12,
				shadowPx = 4,
				shadowAlpha = 0.3,
			},
			cta = { -- H:126-133
				top = 30, -- PR10 (decided 2026-10-15): the design's 18 (H:123) + the 12 px the emblem pokes up
				designTop = 18, -- H:123
				width = 350,
				padLeft = 128,
				padRight = 24,
				textGap = 4,
				emblemPx = 132, -- H:128
				emblemX = -10,
				emblemY = -24,
				emblemShadowPx = 5,
				emblemShadowAlpha = 0.3,
				emblemBobS = 2.4,
				shadowY = 16, -- H:126: 0 16px 30px rgba(60,20,50,.25)
				shadowBlur = 30,
				shadowAlpha = 0.25,
				-- Phones (reading): the design's CTA drawn at today's phone CTA height (64 base px) over its 99 px
				-- frame, the second line hidden (it would be under the 16 px text floor).
				compactScale = 64 / 99,
			},
			search = { -- H:135-146
				width = 560,
				face = 96,
				padLeft = 104,
				padRight = 14,
				gap = 16,
				columnGap = 8,
				line1Gap = 10,
				line2Gap = 5, -- H:140
				emblemPx = 108, -- H:137
				emblemX = -6,
				emblemY = -10,
				emblemPulseS = 0.9,
				dotPx = 7, -- H:139
				dotGap = 3,
				dotDelayS = 0.2,
				playersPad = 6, -- H:142
				tickMs = 700, -- H:763, H:768: tick(false) every 700 ms while searching (the 1v1 queue)
				dropBelow = 420, -- plan R4: narrower than this, the dots and the second line drop
			},
			slots = { -- H:141
				px = 24,
				border = 3,
				radius = 8,
				fill = 18,
				fillRadius = 5,
				highlightPx = 3,
				highlightAlpha = 0.55,
			},
			found = { -- H:148-152
				width = 420,
				face = 96,
				padLeft = 120,
				padRight = 24,
				gap = 14,
				columnGap = 4,
				midAt = 0.6, -- H:149: #FFC23A at 60%
				iconPx = 112, -- H:150
				iconX = 4,
				iconY = -18,
				iconPulseS = 0.6,
				swapDelayMs = 350, -- H:772: the opponent's slot fills, then the found bar
			},
			cancelX = { -- H:145: 48 + lip 4, a 52 px touch box (PR1)
				face = 48,
				border = 4,
				radius = 16,
				lip = 4,
				iconPx = 28,
				highlightPx = 3,
				highlightAlpha = 0.5,
			},
			picker = { -- N:154-158, N:1255-1256 (testers: Config.Match.picker)
				gap = 14, -- N:145: under the DUEL button
				padding = 5,
				tabGap = 6,
				border = 4,
				radius = 20,
				lip = 5,
				highlightPx = 3,
				highlightAlpha = 0.08,
				tabHeight = 42,
				tabPadLeft = 14,
				tabPadRight = 9,
				tabBorder = 3,
				tabRadius = 14,
				tabGapInside = 8,
				tabLip = 3, -- N:1255: 0 3px 0 #1E1428 on the picked tab
				tabHighlightPx = 3,
				tabHighlightAlpha = 0.5,
				chipHeight = 22,
				chipPad = 7,
				chipRadius = 8,
				offChipAlpha = 0.08, -- N:1256: rgba(255,255,255,.08)
				-- N:710: linear-gradient(100deg, ...): 100 - 90 degrees on the screen (SegmentedTabs turns it into the
				-- tab's own 0..1 space, where a UIGradient rotates, from the tab's size).
				tdmRotation = 10,
				tdmStops = { 0, 0.32, 0.68, 1 } :: { number }, -- N:710: the four stops' places
				ffaRotation = 90, -- N:711: linear-gradient(180deg, ...)
				markPx = 24, -- Phone HUD B (reading): the mode chip's swap mark (SegmentedTabs `mark`) on the 42 px face
			},
			-- The design computes the tracker (H:994-996) but draws none: its insides are the quest row's (H:363-367),
			-- its card the plan's card numbers (plan R4: radius 20, the 2 px highlight at .1, H:935), a uniform pad.
			tracker = {
				width = 320, -- reading: the right column's width (no design line)
				pad = 12, -- reading (the quest row's left padding, H:363)
				gap = 16, -- H:363
				iconTile = 70, -- H:364
				iconPx = 58,
				iconBorder = 4,
				iconRadius = 18,
				textGap = 8, -- H:365
				titleGap = 10, -- H:366: the title to "x/y"
			},
			toastTop = 200, -- N:197: the toast column's top (the newer file; was 132, H:174)
			-- Phone HUD B (the owner's pick, 2026-10-17; readings, the design draws no phone layout): on phones (the
			-- compact class, UI/PhoneHud) the toasts sit at the right under Daily and Settings, at most toastWidth
			-- and toastShare of the canvas wide (narrowed beside the DUEL area down to toastMinWidth), toastMax of them.
			phone = {
				toastWidth = 300,
				toastShare = 0.36,
				toastMinWidth = 240,
				toastMax = 2,
			},
		},
		-- UI FINAL R3 (the window frame, plan work/ui/PLAN.md R3): the six design windows (H:180-454) and the game's
		-- own, read through UI/Theme (window, headerTab's band, fitWindow, the sticker, the scrim) and
		-- UI/Layout.windowFit (the size that fits the screen). The window's border, radius and lip are border.heavy,
		-- radius.window and lip.window. Base px.
		window = {
			-- Each kind's face (width x height; the lip hangs under it) and its CSS margin-top (H:181, H:256, H:289,
			-- H:351, H:383, H:426: centred height / 2 + marginTop px below the true centre), its header band
			-- (Palette names of the gradient's stops, the top highlight's and the dots' alpha: H:183, H:258, H:291,
			-- H:353, H:385, H:428), its sticker picture (H:251, H:284, H:346, H:378, H:421, H:451), `small` (the
			-- Settings band: 92 high, the settingsTitle role, the 150 px sticker, H:428-451) and `innerRing` (H:182:
			-- Squishies only). Readings for the windows the design lacks (plan R3): grip (the Grip panel and its idle
			-- card) the grip bar's pair (H:85), no sticker; duel (the forfeit dialog) the DUEL pink (H:126), its
			-- sticker and Settings' small band (a short question in a 600 px dialog); inspect the Squishies pink, no
			-- sticker; their sizes are the nearest design window's.
			kinds = {
				squishies = {
					width = 1060,
					height = 650,
					marginTop = -310,
					top = "StickerPinkTop",
					bottom = "StickerHeaderPinkEnd",
					highlightAlpha = 0.45,
					dotsAlpha = 0.28,
					sticker = "img.nav.squishies",
					innerRing = true,
				},
				boxes = {
					width = 1060,
					height = 650,
					marginTop = -310,
					top = "StickerHeaderCyanTop",
					bottom = "StickerHeaderCyanEnd",
					highlightAlpha = 0.45,
					dotsAlpha = 0.3,
					sticker = "img.nav.boxes",
				},
				shop = {
					width = 1060,
					height = 650,
					marginTop = -310,
					top = "StickerHeaderGoldTop",
					bottom = "StickerHeaderGoldEnd",
					highlightAlpha = 0.5,
					dotsAlpha = 0.32,
					sticker = "img.nav.shop",
				},
				quests = {
					width = 900,
					height = 620,
					marginTop = -296,
					top = "StickerMintTop",
					bottom = "StickerHeaderMintEnd",
					highlightAlpha = 0.45,
					dotsAlpha = 0.3,
					sticker = "img.nav.quests",
				},
				daily = {
					width = 980,
					height = 620,
					marginTop = -296,
					top = "StickerHeaderPurpleTop",
					bottom = "StickerHeaderPurpleEnd",
					highlightAlpha = 0.45,
					dotsAlpha = 0.28,
					sticker = "img.nav.daily",
				},
				settings = {
					width = 600,
					height = 500,
					marginTop = -236,
					top = "StickerHeaderLilacTop",
					bottom = "StickerHeaderLilacEnd",
					highlightAlpha = 0.4,
					dotsAlpha = 0.24,
					sticker = "img.nav.settings",
					small = true,
				},
				grip = {
					width = 600,
					height = 500,
					marginTop = -236,
					top = "StickerGripTop",
					bottom = "StickerGripEnd",
					highlightAlpha = 0.45,
					dotsAlpha = 0.28,
				},
				duel = {
					width = 600,
					height = 500,
					marginTop = -236,
					top = "StickerPinkTop",
					bottom = "StickerPinkEnd",
					highlightAlpha = 0.45,
					dotsAlpha = 0.28,
					sticker = "img.nav.duel",
					small = true,
				},
				inspect = {
					width = 1060,
					height = 650,
					marginTop = -310,
					top = "StickerPinkTop",
					bottom = "StickerHeaderPinkEnd",
					highlightAlpha = 0.45,
					dotsAlpha = 0.28,
				},
			},
			-- The header band (H:183-184, H:428-429): its height (Settings smallHeight), the title's padding with a
			-- sticker (Settings small*) and without one (plainPad both sides), the gap before its extra (H:183), the
			-- top highlight and the bevel (inset 0 5px 0 / inset 0 -7px 0 rgba(0,0,0,.12)), its bottom border, the
			-- rounding of its top corners (the window's 32 less its 5 px border, H:182), the dots' tile (H:183: 26 px)
			-- and the room kept over and under the title's line at large text sizes (reading).
			band = {
				height = 98,
				smallHeight = 92,
				padLeft = 176,
				padRight = 110,
				smallPadLeft = 140,
				smallPadRight = 100,
				plainPad = 110,
				gap = 18,
				highlightPx = 5,
				bevelPx = 7,
				bevelAlpha = 0.12,
				border = 5,
				cornerRadius = 27,
				dotsTile = 26,
				titlePad = 5,
			},
			-- The sticker (H:251, H:451): px square at (x, y) from the window's top-left (Settings small*), its drop
			-- shadow (drop-shadow(0 7px 0 rgba(20,10,30,.35))), sdBob over bobS from the start, and sdStick on every
			-- open (H:27: .75 s after .08 s, each segment eased `curve`; the move is in px).
			sticker = {
				px = 190,
				x = -40,
				y = -62,
				smallPx = 150,
				smallX = -30,
				smallY = -46,
				shadowPx = 7,
				shadowAlpha = 0.35,
				bobS = 3,
				ms = 750,
				delayMs = 80,
				curve = "search", -- H:251: cubic-bezier(.2,1.4,.4,1)
				frames = {
					{ at = 0, x = -40, y = -60, scale = 0.2, rot = -40, alpha = 0 },
					{ at = 0.6, scale = 1.15, rot = 8, alpha = 1 },
					{ at = 0.8, scale = 0.95, rot = -4 },
					{ at = 1, x = 0, y = 0, scale = 1, rot = 0, alpha = 1 },
				} :: { MotionPose },
			},
			close = { face = 76, right = 22, top = 22 }, -- H:252: the X at (right -22, top -22)
			-- H:178: radial-gradient(ellipse at center, rgba(255,150,210,.28), rgba(110,60,220,.55)); a click on it
			-- closes the top window (onClick = closeModal).
			scrim = { innerAlpha = 0.28, outerAlpha = 0.55, closeOnClick = true },
			innerRing = { px = 3, alpha = 0.05 }, -- H:182: inset 0 0 0 3px rgba(255,255,255,.05)
			shadow = { offsetY = 34, blurPx = 70, alpha = 0.5 }, -- H:182: 0 34px 70px rgba(15,8,25,.5)
			margin = 12, -- reading: the room kept from the screen's edges when a window shrinks to fit
			scrollbarPx = 12, -- H:22: ::-webkit-scrollbar { width: 12px }
		},
	},

	-- UI FINAL R2 (the motion kit; plan work/ui/PLAN.md §2.1): the design's own effects (hud-lib.js FX, lib:215-268),
	-- drawn by UI/UiFx.sparks / ring / rain / float next to its Candy tiers, and the design's events that fire them
	-- (H:703-874; each screen's round wires its own, R3-R9). Base px. Colours are Art/Palette names; "rarityBase" /
	-- "rarityLight" are the revealed rarity's RarityStyle ui colours, passed by the caller. `jolt` is the design's
	-- jolt in px (UiFx.jolt, lib:299-303: only while Camera shake is on, none under ReducedMotion). Under
	-- ReducedMotion only the float draws (lib:220, 237, 244). Every curve is a Config.UI.curves name.
	Fx = {
		-- lib:299-303 (T6): `frames` random offsets of px x (1 - i / frames) in x and y, then back to 0, linear over
		-- ms.
		jolt = { frames = 8, ms = 380 },
		-- lib:219-235: n pieces size x (sizeMin .. sizeMin + sizeSpan), `stars` of them four-point stars (lib:225: the
		-- img.fx.spark picture, tinted; a 45° diamond while it has no id), the rest circles with an outlinePx ink ring;
		-- each launched at a random angle (or `angle` ± cone / 2) spread x (reachMin .. reachMin + reachSpan) out and
		-- `up` higher, turning up to ±spinDeg; peakTravel of the way at peakScale by peakAt of its life, then grav
		-- lower at endScale and clear at the end (the whole run eased by `curve`, lib:233); each over ms + 0..jitterMs.
		sparks = {
			n = 16, -- lib:221
			size = 13, -- lib:223
			sizeMin = 0.55, -- lib:223
			sizeSpan = 0.9, -- lib:223
			stars = 0.55, -- lib:223
			spread = 150, -- lib:228
			reachMin = 0.35, -- lib:228
			reachSpan = 0.85, -- lib:228
			up = 40, -- lib:228
			grav = 110, -- lib:232
			cone = 1.2, -- lib:227 (radians)
			spinDeg = 300, -- lib:228
			peakAt = 0.35, -- lib:231
			peakTravel = 0.7, -- lib:231
			peakScale = 1.25, -- lib:231
			endScale = 0.1, -- lib:232
			ms = 820, -- lib:233
			jitterMs = 420, -- lib:233
			outlinePx = 2.5, -- lib:225
			curve = "sparks", -- lib:233
			-- lib:221
			colors = { "StickerFxYellow", "StickerFxPink", "StickerFxCyan", "StickerFxGreen", "StickerFxPurple" },
		},
		-- lib:236-242: a ring `size` wide with a borderPx border, scaleFrom -> scaleTo while it fades, over ms
		-- (`curve`).
		ring = { size = 160, borderPx = 6, scaleFrom = 0.2, scaleTo = 1.3, ms = 520, color = "White", curve = "ring" },
		-- lib:243-254: n pieces across the screen, from startMinPx .. + startSpanPx above it, sizeMin .. + sizeSpan
		-- wide (tallShare of them `tall` x as high, roundShare round, the rest radius 2) with an outlinePx ink ring;
		-- swaying up to ±swayPx (and back -0.4 x of it at the end) and turning up to ±spinDeg while they fall fallShare
		-- of the screen by half time and pastPx below it at the end, over ms + 0..jitterMs after 0..delayMs (the whole
		-- run eased by `curve`, lib:252). PR14 (= A): the design's counts, halved only on the compact layout or with
		-- UiPrefs.fewerEffects.
		rain = {
			n = 60, -- lib:243
			sizeMin = 8, -- lib:248
			sizeSpan = 8, -- lib:248
			tallShare = 0.5, -- lib:248
			tall = 1.8, -- lib:248
			roundShare = 0.4, -- lib:249
			outlinePx = 2, -- lib:249
			startMinPx = 30, -- lib:249
			startSpanPx = 80, -- lib:249
			swayPx = 80, -- lib:251
			spinDeg = 540, -- lib:251
			fallShare = 0.55, -- lib:252
			pastPx = 120, -- lib:252
			ms = 1900, -- lib:252
			jitterMs = 1400, -- lib:252
			delayMs = 600, -- lib:252
			curve = "rain", -- lib:252
			colors = {
				"StickerFxYellow",
				"StickerFxPink",
				"StickerFxCyan",
				"StickerFxGreen",
				"StickerFxPurple",
				"White",
			}, -- lib:245
		},
		-- lib:255-268: a number that pops .3 -> 1.25 (18%) -> 1 (60%) -> .9 as it rises risePx (and drifts dx, ±dxPx
		-- when the call gives none) and fades in and out, over ms (the whole run eased by `curve`, lib:267), in the
		-- Sticker text role `float` at the call's size; under ReducedMotion it holds still and fades out at its end.
		-- `frames` is lib:262-266 with x / y as shares of the drift and the rise (y up is negative).
		float = {
			kind = "Title",
			risePx = 80,
			dxPx = 15,
			ms = 1050,
			color = "White",
			curve = "ring", -- lib:267
			frames = {
				{ at = 0, x = 0, y = 0, scale = 0.3, alpha = 0 },
				{ at = 0.18, x = 0.3, y = -0.25, scale = 1.25, alpha = 1 },
				{ at = 0.6, x = 0.6, y = -0.55, scale = 1, alpha = 1 },
				{ at = 1, x = 1, y = -1, scale = 0.9, alpha = 0 },
			} :: { MotionPose },
		},
		-- The design's events (each `sparks` overrides the defaults above; `rings` = { color, size, delayMs? }; `coins`
		-- = the coin flight's coins, H:663; `jolt` = UiFx.jolt px). Each screen's round wires its own (R4-R9).
		events = {
			questClaim = { -- H:744-746
				sparks = { n = 22, spread = 180 },
				rings = { { color = "StickerCoinText", size = 160 } },
				coins = 10,
			},
			dailyClaim = { -- H:854-856
				sparks = { n = 28, spread = 230 },
				rings = { { color = "StickerCoinText", size = 280 } },
				coins = 10,
			},
			duelJoin = { -- H:762
				sparks = {
					n = 14,
					spread = 170,
					colors = { "StickerFxPink", "StickerFxCyan", "StickerFxYellow", "White" },
				},
			},
			matchFound = { -- H:774-775
				sparks = {
					n = 30,
					spread = 260,
					ms = 1000,
					colors = { "StickerFxYellow", "White", "StickerPinkSoft", "StickerFxCyan" },
				},
				rings = { { color = "StickerCoinText", size = 360 } },
				jolt = 7,
			},
			-- H:815-816: wobble j (0, 1, 2) adds perWobble's n, spread and jolt j times.
			boxWobble = {
				sparks = { n = 6, spread = 140, size = 10, colors = { "White", "StickerFxYellow", "StickerFxIce" } },
				perWobble = { n = 5, spread = 60, jolt = 3 },
				jolt = 3,
			},
			-- H:822-830: two rings, then (delayMs later) n + perRarity x the rarity's index pieces, at most maxPieces.
			-- §9.15 counts every animated frame of the reveal (BoxController :60): 1 rays picture + the 2 rings (alive
			-- 0-520 ms, over the burst from 120 ms) + 21 pieces = 24; sparks still alive from the last wobble
			-- (boxWobble) count in the same 24. PR18 (decided 2026-10-15): from the rarity index fromRarity on (Epic,
			-- Exclusive) the design's rain (H:830: n + perRarity x the index pieces in these colours) falls once the
			-- burst's pieces are gone, R7 capping it to the frames then free in the same 24.
			boxBurst = {
				rings = { { color = "White", size = 420 }, { color = "rarityLight", size = 700 } },
				sparks = {
					n = 30,
					spread = 380,
					up = 80,
					ms = 1150,
					size = 16,
					colors = { "rarityBase", "rarityLight", "White", "StickerFxYellow" },
				},
				delayMs = 120,
				perRarity = 12,
				maxPieces = 21,
				jolt = 14,
				rarityRain = { -- H:830
					n = 50,
					perRarity = 20,
					fromRarity = 2,
					colors = { "rarityBase", "rarityLight", "White", "StickerFxYellow" },
				},
			},
			equip = { sparks = { n = 16, spread = 140 } }, -- H:845
			-- H:871: the rain falls over the congrats overlay; R6 passes that overlay as UiFx.rain's parent, so the
			-- rain goes when the overlay closes and never falls on over the play area.
			purchase = { -- H:868, H:871
				sparks = { n = 30, spread = 240 },
				rings = { { color = "StickerFxGreen", size = 240 } },
				rain = 90,
				rainDelayMs = 300,
				jolt = 8,
			},
			-- H:719-726 (the full level-up, the user's Q3): a slam jolt at slamMs, then at atMs three rings, the burst,
			-- the rain and the big jolt. UI FINAL R9 (G9.12): the rising tone (ui.levelTone) at toneMs (H:720).
			levelUp = {
				slamMs = 460,
				slamJolt = 5,
				toneMs = 560,
				atMs = 1000,
				rings = {
					{ color = "White", size = 420, delayMs = 0 },
					{ color = "StickerCoinText", size = 620, delayMs = 110 },
					{ color = "StickerMintTop", size = 820, delayMs = 220 },
				},
				sparks = {
					n = 48,
					spread = 420,
					up = 80,
					ms = 1300,
					size = 16,
					colors = { "StickerCoinText", "StickerMintTop", "White", "StickerPinkSoft", "StickerFxPurple" },
				},
				rain = 80,
				jolt = 14,
			},
			squeeze = { -- H:703-705
				sparks = {
					n = 8,
					spread = 100,
					up = 70,
					size = 10,
					colors = { "StickerPinkSoft", "White", "StickerFxYellow" },
				},
				coinFloat = { color = "StickerCoinText", kind = "Name", dx = -34 },
				gripFloat = { color = "StickerGripFloat", kind = "H2", dx = 34 },
			},
			-- H:577: each landing's sparks (`big` for the last coin of a flight).
			coinLand = {
				sparks = {
					n = 6,
					spread = 70,
					up = 20,
					grav = 40,
					size = 10,
					stars = 0.9,
					ms = 520,
					colors = { "StickerCoinFlash", "StickerFxYellow", "White" },
				},
				big = { n = 12, spread = 110 },
			},
			-- H:673: the "-N" float at the pill's centre + xShare x its width, + yShare x its height.
			spend = {
				float = {
					color = "StickerSpendFloat",
					kind = "HudNumber",
					rise = -40,
					dx = 10,
					at = { xShare = 0.2, yShare = 0.9 },
				},
			},
			boxLand = { jolt = 6 }, -- H:602: the box landing's jolt (with the stamp sound), R7
		},
	},

	-- Match HUD M4 (2026-10-16; plan work/matchhud2/PLAN.md §4 M4 = v1 M3a, v1 §1.3, §1.9): the in-match screens of
	-- Diego's "Squishy Duels Match HUD.dc.html" (Client/Controllers/MatchHudController; checks: Config/ValidateMatchHud).
	-- gui = their ScreenGui SD_MatchHud, made on first use (a controller-owned layer, so not in ScreenGuis, which
	-- UIController makes at boot), inside Roblox's safe area (the shared UIScale). DisplayOrder 14 [P] (critic fix: the
	-- plan's 12 is taken by the touch buttons' SD_Touch, ControlsController TOUCH_DISPLAY_ORDER; 13 by
	-- SD_PracticeReticle): over the touch buttons (the boot cover, intro and countdown cover the whole screen; no piece
	-- enters the touch cluster during Active, v1 §1.4), under SD_Dimmer 19, the modals and SD_Overlay's sparks.
	-- enabled = one switch per piece in a real match (a Studio preview builds every piece): all off until the step that
	-- builds a piece turns it on with the owner's yes [P]. compact.fitMin = the smallest nested UIScale of a piece bigger
	-- than the safe area (v1 §1.3b) [P].
	Match = {
		gui = { displayOrder = 14, insets = Enum.ScreenInsets.CoreUISafeInsets } :: ScreenGuiSpec,
		enabled = {
			topBar = false, -- M5 (waits for Diego's big-match bar)
			feed = true, -- M6 kill feed (2026-10-17: on, with look-alike pictures and sounds until the owner's upload)
			medal = false, -- M6 SQUISHED! medal: not built, Diego's kill banner (KillBannerController) is that moment
			card = true, -- M7 "squished by" card
			respawn = true, -- M7 RESPAWNING IN bar and vignette
			boot = false, -- M8 Loading arena cover
			intro = false, -- M8 intro card
			introOrbit = false, -- M8 the map fly-over behind it (owner Q6: yes)
			countdown = false, -- M8 3-2-1 SQUISH!
			killerCam = false, -- M7 the camera on your killer while you wait (owner Q6: yes; not built yet, M7 notes)
			finish = false, -- M9 VICTORY / DEFEAT splash
			results = false, -- M9 results bar, LOBBY / PLAY AGAIN
			podium = false, -- M10a / M10b 3D podium (owner Q2: his podium exactly)
			cards = false, -- M10c podium cards (hidden from players until Diego's fix, owner Q2)
			replay = false, -- M11-M13 final-kill replay (owner Q1: yes, last)
		} :: { [string]: boolean },
		compact = { fitMin = 0.6 },
		-- Match HUD M6 (2026-10-17; plan §4 M6 = v1 M4; `M:n` = the design's line): the kill feed (UI/Match/KillFeed),
		-- top right, newest at the bottom. Base px (SD_MatchHud carries the UI scale). A row: 50 high + the 4 px ink lip
		-- drawn under it (inside its box, the house rule), the next one 8 below the face (the lip takes 4 of it); the
		-- player who squished, the 3 speed bars and their squishy, the one squished (greyed and squashed) and a tag.
		-- Reading: Roblox scales a whole row evenly, so M's scale(sx, sy) frames are their even part sqrt(sx * sy).
		feed = {
			right = 18, -- M:120
			top = 16,
			rowGap = 8,
			face = 50, -- M:122
			lip = 4,
			border = 4,
			radius = 16,
			padX = 6,
			gap = 8,
			fillAlpha = 0.9, -- rgba(36,24,58,.9)
			glow = 3, -- 0 0 0 3px at .3 around your rows
			glowAlpha = 0.3,
			head = { size = 36, border = 3, radius = 11 }, -- M:123, M:131
			nameRole = "matchFeedName", -- M:124, M:130
			weapon = { -- M:125-128
				width = 50,
				height = 34,
				toy = 34,
				toyRot = -18,
				toyDrop = 2,
				barHeight = 4,
				bars = {
					{ w = 16, x = 0, y = 9, alpha = 0.55 },
					{ w = 12, x = 4, y = 17, alpha = 0.4 },
					{ w = 14, x = 0, y = 25, alpha = 0.3 },
				},
			},
			victim = { sx = 1.25, sy = 0.7, y = 6, gray = 0.85, brightness = 0.85, inkAlpha = 0.15 }, -- M:131; inkAlpha [P]
			tag = { height = 28, padX = 9, border = 3, radius = 10, role = "matchFeedTag" }, -- M:132
			enter = { -- smFeedIn M:39, M:655
				ms = 500,
				curve = "search",
				frames = {
					{ at = 0, alpha = 0, x = 70, scale = 0.735 },
					{ at = 0.55, alpha = 1, x = -8, scale = 1.009 },
					{ at = 0.75, x = 3, scale = 1 },
					{ at = 1, alpha = 1 },
				} :: { MotionPose },
			},
			leave = { -- smFeedOut M:40, out at 4.6 s, gone at 5.0 s (M:531-532)
				atMs = 4600,
				ms = 400,
				curve = "easeIn",
				frames = { { at = 0, alpha = 1 }, { at = 1, alpha = 0, x = 40, scale = 0.9 } } :: { MotionPose },
			},
			multiWindowS = 4, -- M:521 DOUBLE! / TRIPLE!
			streakMin = 3, -- M:527 "{n} STREAK"
			maxRows = 5, -- [P] v1 §1.3d (M keeps every row)
			compactMaxRows = 2, -- [P] phones: clear of the touch buttons
		},
		-- Match HUD M7 (plan §4 M7 = v1 M5, §12): the "squished by" card (UI/Match/DeathCard, M:155-193), bottom left,
		-- 486 wide. With touch controls it sits `gap` above the thumbstick zone (owner 2026-10-16: never over the
		-- thumbstick corner), shrunk to fit down to Match.compact.fitMin; on other compact screens to compactShare of the
		-- height (v1 §1.3e). Reading: M's soft 0 22px 40px shadow under the body is not drawn.
		card = {
			left = 22, -- M:156
			bottom = 22,
			top = 8, -- [P] never above this
			gap = 16, -- [P] from the thumbstick zone (Config.UI.Touch.gap)
			compactShare = 0.62, -- [P] v1 §1.3e
			width = 486,
			rowGap = 8, -- the header to the body
			header = { height = 32, gap = 8, padLeft = 4 }, -- M:157
			finalChip = { height = 32, padX = 12, border = 4, lip = 3, role = "matchCardFinal" }, -- M:158 (M13's card)
			pill = { height = 30, padX = 11, border = 3, role = "matchCardPill" }, -- M:159, M:161
			byRole = "matchCardBy", -- M:160
			body = { border = 5, radius = 26, lip = 8 }, -- M:163
			banner = { -- M:164-175
				height = 140,
				rotation = 25, -- [P] v1 §1.6: CSS 115deg - 90
				mid = 0.52,
				dots = { tile = 24, alpha = 0.26 },
				rays = { size = 480, fromRight = 130, alpha = 0.32, spinS = 14 }, -- right -110, 480 wide: centre 130 in
				textX = 20,
				textY = 18,
				textGap = 7,
				nameRole = "matchCardName",
				titleRole = "matchCardTitle",
				toy = { size = 172, right = 10, top = -14, shadowPx = 8, shadowAlpha = 0.35 },
				twinkles = {
					{ size = 22, x = 214, y = 22, delayS = 0.3, cream = false },
					{ size = 16, x = 258, y = 96, delayS = 0.9, cream = true },
				},
				twinkleS = 1.8,
				shine = { px = 70, overhang = 20, alpha = 0.6, slantDeg = 20, periodS = 2.8, delayS = 0.6 },
			},
			info = { -- M:176-191
				height = 106,
				borderTop = 5,
				padLeft = 14,
				padRight = 16,
				gap = 14,
				highlight = 3,
				highlightAlpha = 0.14,
				head = { size = 76, border = 4, radius = 20, lip = 4, highlight = 4, highlightAlpha = 0.4 },
				nameGap = 4,
				nameRole = "matchCardKiller",
				handleRole = "matchCardHandle",
				box = {
					height = 42,
					padLeft = 4,
					padRight = 12,
					gap = 3,
					border = 3,
					radius = 14,
					lip = 3,
					icon = 32,
					highlight = 3,
					gripAlpha = 0.55,
					streakAlpha = 0.5,
					flameY = -4,
					captionGap = 3,
					numberRole = "matchCardStat",
					captionRole = "matchCardCaption",
				},
			},
			show = { -- M:558 (whole run)
				ms = 620,
				wholeRun = "beat",
				frames = {
					{ at = 0, alpha = 0, x = -60, y = 260, scale = 0.55, rot = -8 },
					{ at = 0.6, alpha = 1, x = 6, y = -12, scale = 1.04, rot = 1 },
					{ at = 0.8, x = 0, y = 3, scale = 0.99 },
					{ at = 1, alpha = 1 },
				} :: { MotionPose },
			},
			hide = { -- M:565 (whole run)
				ms = 260,
				wholeRun = "close",
				frames = { { at = 0, alpha = 1 }, { at = 1, alpha = 0, x = -30, y = 120, scale = 0.8 } } :: { MotionPose },
			},
			toyIn = { -- smToyIn M:49, M:171 (reading: the toy grows in; its own fade is not drawn)
				ms = 700,
				delayMs = 120,
				curve = "search",
				frames = {
					{ at = 0, x = 120, scale = 0.3, rot = 40 },
					{ at = 0.6, x = -8, scale = 1.12, rot = -12 },
					{ at = 1, rot = -8 },
				} :: { MotionPose },
			},
			toyBob = { periodS = 2.4, delayS = 0.9, risePx = 7 }, -- smToyBob M:50
			clickDelayMs = 260, -- M:560
			jolt = 10, -- M:548
			preview = { grip = 37, streak = 4 }, -- Studio previews only: the pretend players' Grip level and win streak
		},
		-- Match HUD M7: the RESPAWNING IN bar (UI/Match/RespawnBar, M:195-200), bottom centre, and v1 §1.3h: beside the
		-- card, else above it, when they would meet, never on the thumbstick zone (each place tried at each of `scales`;
		-- [P] it may cover the touch buttons, which do nothing while you are knocked out).
		respawn = {
			bottom = 30, -- M:196
			width = 380,
			gap = 16, -- [P] v1 §1.3h cardGap; also from the touch areas
			top = 8,
			rowGap = 8, -- the label row to the bar
			labelGap = 10, -- M:197
			labelRole = "matchRespawnLabel",
			numberRole = "matchRespawnNumber",
			bar = { height = 20, border = 4, lip = 4, troughAlpha = 0.6, highlight = 3, highlightAlpha = 0.55 }, -- M:198
			enter = { -- smRise M:48, M:196
				ms = 400,
				curve = "search",
				frames = { { at = 0, alpha = 0, y = 40, scale = 0.8 }, { at = 1, alpha = 1 } } :: { MotionPose },
			},
			scales = { 1, 0.9, 0.8, 0.7, 0.6 }, -- [P]
		},
		-- Match HUD M7: the knocked-out vignette (M:61: the radial picture over the whole screen, `margin` past the safe
		-- area for the notch [P]) and backdrop-filter saturate(.4) brightness(.95) as a client ColorCorrectionEffect;
		-- sdFade .4 s in, gone at once at the respawn. While img.fx.radial.matchVignette has no id: M:61's stops on two
		-- edge gradients (clear in the middle `clearShare` of each axis) [P].
		vignette = {
			fadeMs = 400,
			curve = "ease",
			saturation = -0.6,
			brightness = -0.05,
			margin = 64,
			fallback = { clearShare = 0.4, midAlpha = 0.35, edgeAlpha = 0.72 },
		},
	},

	-- UI FINAL R2 (plan §0 easing rule, G2.3): every design timing function as cubic-bezier numbers { x1, y1, x2, y2 },
	-- played exactly by Anim/Tweens.bezier (the CSS keywords at their standard numbers). `H:n` / `lib:n` cite each.
	curves = {
		ease = { 0.25, 0.1, 0.25, 1 }, -- CSS `ease`
		easeIn = { 0.42, 0, 1, 1 }, -- CSS `ease-in`
		easeOut = { 0, 0, 0.58, 1 }, -- CSS `ease-out`
		easeInOut = { 0.42, 0, 0.58, 1 }, -- CSS `ease-in-out`
		linear = { 0, 0, 1, 1 }, -- CSS `linear`
		hover = { 0.3, 1.9, 0.45, 1 }, -- H:635
		switch = { 0.3, 1.8, 0.5, 1 }, -- H:197, H:437
		slot = { 0.2, 1.6, 0.4, 1 }, -- H:141, H:149 (slot, found)
		stars = { 0.2, 1.5, 0.4, 1 }, -- H:457, H:515, H:527 (confirm, stars, letters)
		search = { 0.2, 1.4, 0.4, 1 }, -- H:136, H:251, H:398, H:490, H:574 (search, sticker, sdUp, stamp, coin number)
		windows = { 0.2, 1.35, 0.4, 1 }, -- H:181
		rise = { 0.2, 1.3, 0.4, 1 }, -- H:203, H:489, H:525, H:937 (rise, reveal, unfurl, pick)
		bars = { 0.3, 1.5, 0.5, 1 }, -- H:85, H:187, H:240, H:367
		coinFlip = { 0.2, 1.2, 0.4, 1 }, -- H:571
		close = { 0.5, 0, 0.75, 0 }, -- H:686
		ringFill = { 0.5, 0, 0.9, 0.6 }, -- H:513
		sparks = { 0.15, 0.7, 0.35, 1 }, -- lib:233
		ring = { 0.2, 0.8, 0.3, 1 }, -- lib:241, lib:267 (ring, float)
		rain = { 0.3, 0.1, 0.7, 1 }, -- lib:252
		fly = { 0.25, 0.7, 0.35, 1 }, -- lib:283
		flyLeg = { 0.55, 0, 0.85, 0.55 }, -- lib:281
		-- Match HUD M4 (v1 §1.5; M = "Squishy Duels Match HUD.dc.html"): the countdown beat M:489 and the card entry
		-- M:558 (both whole-run), the podium ribbon M:331 and the replay banner M:298 (sdMfUnfurl; not `rise`).
		beat = { 0.2, 1, 0.4, 1 },
		unfurl = { 0.3, 1.3, 0.5, 1 },
	} :: { [string]: { number } },

	-- Kill banners (2026-10-16, VillasmilGaming: Valorant-style; UI/KillBanner, UI/KillBannerFormat). The killer's banner
	-- is a medallion bottom-centre (below the crosshair, above the bottom HUD) that gains one ornament per K.O. without
	-- being knocked out (1-5) and its crown at 6; every K.O. after the 6th shows the 6k banner again. Px at UI scale 1
	-- (SD_KillBanner carries the UI scale); seconds; angles in degrees from the top, clockwise.
	KillBanner = {
		discPx = 104, -- the medallion's diameter
		discMinPx = 64, -- never smaller
		discShare = 0.15, -- and at most this share of the gui's height
		centerYShare = 0.76, -- the medallion's centre, down from the top
		compactCenterYShare = 0.7, -- below Breakpoints.compactBelowHeight (phones: clear of the thumb buttons)
		ornamentRadius = 0.66, -- the ornaments' centres from the medallion's centre, × the disc
		slotAngles = { 0, -38, 38, -76, 76 }, -- the 1k..5k ornaments
		crownAngle = 118, -- the 6k crown pieces at ±crownAngle
		tiers = 6,
		introSeconds = 0.32, -- the pop
		holdSeconds = 1.6,
		outroSeconds = 0.36, -- the shrink and fade
		popScale = 1.18, -- the medallion's overshoot
		replaceFromScale = 0.82, -- a K.O. during a banner restarts it from this scale (no blink)
		staggerSeconds = 0.035, -- the earlier ornaments appear this far apart
		newestAt = 0.2, -- the new ornament (or the 6k crown) pops this long after the hit
		newestPopScale = 1.45, -- the new ornament's overshoot
		reducedFadeSeconds = 0.15, -- ReducedMotion: a plain fade in and out, no pop or spin
	},
}

return UI
