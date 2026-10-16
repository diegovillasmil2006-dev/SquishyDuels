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
		-- UI overhaul: the panel pops scaleFrom -> overshoot over overshootShare of ms (Quad Out), then settles to 1 (Quad
		-- InOut), rising riseShare of its height into place; the backdrop fades in over backdropMs. `style` / `direction`
		-- stay the one-tween fallback (the banner's pop). UI FINAL R2: the design's sdPop (H:25, .5 s, H:181), without
		-- its fade and tilt (plan §1.4 RL3); the scrim's sdFade .25 s (H:178).
		modalOpen = {
			ms = 500, -- H:181
			style = Enum.EasingStyle.Back,
			direction = Enum.EasingDirection.Out,
			curve = "windows", -- H:181
			scaleFrom = 0.55, -- H:25
			overshoot = 1.035, -- H:25 (60%)
			overshootShare = 0.6,
			riseShare = 0.03,
			dimmerTransparency = 0.5, -- the Backdrop colour 1 -> 0.5
			backdropMs = 250, -- H:178
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
		-- (`curve`; today's tween: Quart In, 0.006 off), the scrim fading out with it; no fade of the window (plan §1.4
		-- RL3).
		modalClose = {
			ms = 190, -- H:686 (the backdrop)
			style = Enum.EasingStyle.Quart,
			direction = Enum.EasingDirection.In,
			curve = "close", -- H:686
			scaleTo = 0.82, -- H:687
			visualMs = 190, -- H:686
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
		-- H:661), at most 3 (H:660). `frames` spans lifeMs (R9); ms / slidePx / popFrom give today's slide its
		-- entrance. Also the duel toast's time (DuelController reads autoDismissSeconds). Until R9 plays `frames`,
		-- today's exit starts at autoDismissSeconds and slides slidePx up over ms.
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
			-- H:64, H:510: sdLvBubble 2.4-4.0 s linear infinite (each bubble its own period in that span); y is a share
			-- of the screen height (-115vh) applied by the caller.
			lvBubble = {
				periodS = 2.4,
				periodMaxS = 4,
				curve = "linear",
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
	},

	-- Boxes screen (§11.6). Reading (DESIGN names the timeout state but gives no number): a BoxOpen with no reply after
	-- stillCheckingSeconds shows box.stillChecking; the outcome then arrives with the next StateDelta.
	Boxes = {
		stillCheckingSeconds = 10, -- [P]
		-- Reading (Part 7 review fix, §9.11 "no fake-outs"): StateController hides a new box result (the duplicate
		-- refund in the Coins, the new squishy in owned) until its reveal reaches the result; a reveal that has not
		-- played after this many seconds (e.g. queued behind another result left open) shows its result anyway.
		revealHoldMaxSeconds = 30,
	},

	-- Shop screen (§11.6). Reading (DESIGN gives no number): the Squishies tab card width in base px, like
	-- Inventory.cardWidth (columns = floor(gridWidth / (cardWidth + pad))).
	Shop = {
		cardWidth = 150, -- [P]
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

	-- Capsules (lobby bases spec 2026-10-11 §5.3, §9; build plan Phase 5): the capsule card (Controllers/CapsuleController,
	-- UI/CapsuleFormat) and the capsule feel (Anim/CapsuleFeel). Base px for the card; seconds, studs and shares for the
	-- feel. Colours come from Art/Palette (the bricks take the capsule's own colours), the brick flight from
	-- Config.Vfx.Confetti.
	Capsule = {
		-- The card: at most cardWidth base px wide (cardMargin to the screen's sides), at most heightShare of the screen
		-- (the rest scrolls, DailyFormat.bodyHeight); the squishy picture iconPx, the swap list's pictures swapIconPx.
		cardWidth = 420,
		cardMargin = 24,
		heightShare = 0.86,
		iconPx = 72,
		swapIconPx = 56,
		-- It opens from the ProximityPrompt within promptStuds of a capsule's front (E / ButtonX), or a tap or click on a
		-- capsule within clickStuds of the camera that moves less than Config.Inspect.Input.tapMaxPixels.
		promptStuds = 7,
		clickStuds = 80,
		-- The feel (spec §5.3): the press comes down in pressDownMs, holds pressHoldMs and rises in pressUpMs; the squishy
		-- squashes to squashHeight × squashWidth, springs back to springHeight and wobbles. Reading: the wobble's half
		-- period is pressUpMs, so it peaks as the press is back up (1.56 Hz, under the 3 Hz flicker limit, §18.1 #4).
		pressDownMs = 160,
		pressHoldMs = 140,
		pressUpMs = 320,
		squashHeight = 0.58,
		squashWidth = 1.25,
		springHeight = 1.12,
		tapSquish = 0.08, -- spec §5.3: a home tap gives every capsule a small squish
		-- An upgrade (spec §5.3; readings): the squishy stretches upgradeStretch and turns upgradeTurns times over spinMs,
		-- `bricks` brick confetti fly, a ring flashes over the drum and the level plate pops platePop -> 1 over
		-- platePopMs; a new tier look (an evolve) is the bigger burst: evolveStretch, evolveTurns, evolveBricks, 2 rings.
		upgradeStretch = 0.25,
		evolveStretch = 0.4,
		upgradeTurns = 1,
		evolveTurns = 2,
		spinMs = 700,
		bricks = 8,
		evolveBricks = 16,
		brickSize = Vector3.new(0.5, 0.3, 0.5),
		ringStuds = 9,
		ringMs = 350,
		platePop = 1.4,
		platePopMs = 300,
		-- The owner's "+N Coins +N Grip" over a capsule (spec §5.3): it rises popRiseStuds over popMs, fading over the
		-- last popFadeShare of it (under ReducedMotion it holds still, then fades). Visitors see `sparkles` sparkles
		-- sparkleStuds big (reading: the squeeze particles' look, Anim.squeeze.particles, big enough to read at a distance).
		popMs = 900,
		popRiseStuds = 2.5,
		popFadeShare = 0.35,
		sparkles = 3,
		sparkleStuds = 0.5,
		-- Nothing moves on a capsule farther than cullStuds from the camera or off the screen (as Squeeze.othersCullStuds).
		cullStuds = 60,
		-- Batch 1 #7b: the "UP!" marker over an own capsule whose next level the Coins cover now. It hangs over the
		-- +Coins pop's highest point (the controller's POP_STUDS + popRiseStuds) and is lifted upLift of its own height
		-- (BillboardGui.SizeOffset, so in screen pixels): its bottom (upPx.Y × upLift - upPx.Y / 2 = 35 px) stays
		-- above the pop's top (28 px, half its 56 px) at any distance. It bobs upBob more of its height and back once
		-- every upBobMs (1.1 Hz, under the 3 Hz flicker limit, §18.1 #4); still under ReducedMotion.
		upPx = Vector2.new(80, 32),
		upLift = 1.6,
		upBob = 0.25,
		upBobMs = 900,
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
		} :: { [string]: StickerTextRole },
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
			-- the rain and the big jolt.
			levelUp = {
				slamMs = 460,
				slamJolt = 5,
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
