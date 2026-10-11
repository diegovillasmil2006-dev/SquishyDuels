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

	-- UI motion and button states (§9.13, with the feel pass values of §18.5.2 / §18.8). Under ReducedMotion scale
	-- effects are off and fades <= maxFadeMs.
	motion = {
		modalOpen = {
			ms = 240, -- §18.8: 180 -> 240
			style = Enum.EasingStyle.Back,
			direction = Enum.EasingDirection.Out,
			scaleFrom = 0.88, -- §18.8: 0.94 -> 0.88
			dimmerTransparency = 0.45, -- dimmer 1 -> 0.45
		},
		-- The logical close is immediate; visually the root stays visualMs while UIScale goes 1 -> scaleTo (§18.5.2 B4).
		modalClose = {
			ms = 120,
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.In,
			scaleTo = 0.92,
			visualMs = 100,
		},
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
		buttonHover = { ms = 80, scale = 1.04, fillDelta = 0.08 },
		buttonPressed = { ms = 60, scale = 0.92, fillDelta = -0.1 }, -- §18.8: scale 0.95 -> 0.92
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

	Result = {
		autoCloseAfterReturnSeconds = 6,
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
		-- Reading (DESIGN: "smaller and lighter"): the slow-training popup's text scale and transparency.
		afkPopupScale = 0.8,
		afkPopupTransparency = 0.35,
	},
}

return UI
