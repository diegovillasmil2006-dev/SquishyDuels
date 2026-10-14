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

local UI = {
	-- UIScale = clamp(SD_Hud.AbsoluteSize.Y / referenceHeight, min, max), recomputed on size change.
	Scale = { referenceHeight = 800, min = 0.85, max = 1.25 },

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
		SD_Dimmer = { displayOrder = 19, insets = Enum.ScreenInsets.None },
		SD_Modal = { displayOrder = 20, insets = Enum.ScreenInsets.CoreUISafeInsets },
		SD_Overlay = { displayOrder = 30, insets = Enum.ScreenInsets.CoreUISafeInsets },
		SD_Fade = { displayOrder = 40, insets = Enum.ScreenInsets.None },
	} :: { [string]: ScreenGuiSpec },

	-- UI motion and button states (§9.13, with the feel pass values of §18.5.2 / §18.8; UI overhaul 2026-10-11: the
	-- elastic, snappy targets of the overhaul brief). Under ReducedMotion scale effects are off and fades <= maxFadeMs.
	motion = {
		-- UI overhaul: the panel pops scaleFrom -> overshoot over overshootShare of ms (Quad Out), then settles to 1 (Quad
		-- InOut), rising riseShare of its height into place; the backdrop fades in over backdropMs. `style` / `direction`
		-- stay the one-tween fallback (the banner's pop).
		modalOpen = {
			ms = 300, -- overhaul: 240 -> 300 (two phases)
			style = Enum.EasingStyle.Back,
			direction = Enum.EasingDirection.Out,
			scaleFrom = 0.9, -- overhaul: 0.88 -> 0.9
			overshoot = 1.03,
			overshootShare = 0.6,
			riseShare = 0.03,
			dimmerTransparency = 0.5, -- the Backdrop colour 1 -> 0.5
			backdropMs = 150,
		},
		-- The logical close is immediate; visually the root stays visualMs while UIScale goes 1 -> scaleTo (§18.5.2 B4).
		modalClose = {
			ms = 160, -- overhaul: 120 -> 160 (the backdrop)
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.In,
			scaleTo = 0.9, -- overhaul: a brief inward squish
			visualMs = 150,
		},
		-- UI overhaul: collectible cards pop in one after another the first time a grid fills (and when a tab or filter
		-- shows a new set): staggerMs apart, never more than maxStaggerMs for the whole set, each scaleFrom -> 1 over ms.
		cardIn = { staggerMs = 18, maxStaggerMs = 260, ms = 220, scaleFrom = 0.86 },
		-- UI overhaul: a tab's content settles in (never the whole panel): scaleFrom -> 1 over ms.
		tabSettle = { ms = 140, scaleFrom = 0.97 },
		tabSwitch = { ms = 120, slidePx = 12 },
		-- §18.5.2 B5: a UIScale pop popFrom -> 1 (Back Out, ms) with the slide; a re-armed toast nudges nudgeScale -> 1.
		toast = {
			ms = 200,
			slidePx = 16,
			autoDismissSeconds = 2.5,
			maxStacked = 3,
			popFrom = 0.9,
			nudgeScale = 1.06,
			nudgeMs = 160,
		},
		coinCounter = {
			countUpMs = 400,
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.Out,
			floatPx = 30, -- "+N" floats up and fades
			floatMs = 700,
			-- §18.5.2 B1: the pill bounces on every gain (scale over upMs Quad Out, back over downMs Back Out) and the
			-- coin icon rotates 0 -> -iconWiggleDeg -> 0; spending squishes it and counts down over countMs, no float.
			pillBounce = { scale = 1.08, upMs = 70, downMs = 160 },
			spend = { scale = 0.95, downMs = 60, upMs = 140, countMs = 300 },
			iconWiggleDeg = 12,
		},
		-- "+N" coin flights into the pill (§18.5.2 B2, UI/CoinFlight): only for amounts >= minAmount; coins =
		-- clamp(round(amount / coinsPer), minCoins, maxCoins), each arcing arcPx over ms (Quad In), staggerMs apart;
		-- the count-up lasts (k - 1) · staggerMs + countTailMs.
		coinFlight = {
			minAmount = 50,
			coinsPer = 40,
			minCoins = 3,
			maxCoins = 8,
			iconPx = 22,
			ms = 520,
			staggerMs = 45,
			arcPx = 120,
			startScale = 0.7,
			scaleInMs = 120,
			-- Reading (§18.1 #4 and §9.12 over B2's "at most once per 60 ms"): coins land 45 ms apart, so a 60 ms gap
			-- bounced the pill (and restarted the icon wiggle) about 11 times a second; >= 334 ms keeps it <= 3 Hz.
			bounceMinGapMs = 334,
			countTailMs = 400,
		},
		buttonHover = { ms = 120, scale = 1.05, fillDelta = 0.08 }, -- overhaul: 80 ms 1.04 -> 120 ms 1.05
		buttonPressed = { ms = 70, scale = 0.94, fillDelta = -0.1 }, -- overhaul: 60 ms 0.92 -> 70 ms 0.94
		-- The springy release (§18.5.2 B3): Util/Spring from the current scale to the target (≈ 2.98 Hz, under §9.12's
		-- 3 Hz); ms / style / direction stay as the fallback tween.
		buttonRelease = {
			ms = 140,
			style = Enum.EasingStyle.Back,
			direction = Enum.EasingDirection.Out,
			spring = { omega = 20, zeta = 0.35 },
		},
		-- A disabled press: a "no" wiggle of Position ±wigglePx, cycles cycles over ms, fading out (§18.5.2 B3).
		-- Reading (§18.1 #4 and §9.12 over B3's "2 cycles, 200 ms", which is 10 Hz): 1 cycle over 340 ms (2.9 Hz).
		buttonError = { wigglePx = 4, cycles = 1, ms = 340 },
		-- Pops (Back Out): the HUD badge when its count rises (§18.5.2 B5); READY and the opponent's Rush chip (B8).
		badgePop = { from = 1.4, ms = 220 },
		readyPop = { from = 1.3, ms = 220 },
		focus = { scale = 1.04, outerStrokePx = 3, innerStrokePx = 2 }, -- white outer + Ink inner stroke
		-- Reading (foam UI, spec 2026-10-09; DESIGN gives no number): a ProgressBar fill easing to a new value.
		barFill = { ms = 300, style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.Out },
		disabledTextOpacity = 0.6, -- plus a reason text; still selectable
		loadingSpinnerDelayMs = 150, -- e.g. box Open waiting for the reply
		skeletonPulseMaxHz = 1,
		ultReadyPulseSeconds = 0.9, -- static under ReducedMotion
		reducedMotionMaxFadeMs = 120,
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
}

return UI
