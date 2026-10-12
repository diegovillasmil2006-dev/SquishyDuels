--!strict
-- Config.Vfx: hit feedback, camera shake, flash safety, projectile readability and flight size, Dragon Rush visuals,
-- client zone lighting presets and VFX budgets (DESIGN §7.4, §8.1, §9.7, §9.8, §9.10, §9.12, §9.15), plus the feel
-- pass blocks (§18.4, §18.5.1, §18.8, §18.9): Splat, HitStop, Punch, ImpactFlash, HeldBoing, ThrowRing, Confetti,
-- MatPulse, CoinPopup, Ambient. Shared (read by client VFX code and the SquishyBuilder test), data only. All [P].
-- Budgets are our own limits, not engine limits; when a cap is reached cosmetic effects are dropped first.
-- VFX never create dynamic lights. Rarity trails are in Art/RarityStyle.

local Vfx = {
	-- Engine built-in particle textures (verified AssetFetchStatus Success, §9.15). Not asset ids.
	Textures = {
		smoke = "rbxasset://textures/particles/smoke_main.dds",
		sparkles = "rbxasset://textures/particles/sparkles_main.dds",
		fire = "rbxasset://textures/particles/fire_main.dds",
	},

	-- Impact and hit feedback (§9.8), triggered only by the server's ThrowImpact.
	Hit = {
		splatMs = 90, -- player hit: splat along the normal (Quad Out) ...
		splatAlong = 0.55,
		splatAcross = 1.4,
		shrinkMs = 120, -- ... then shrink to 0
		puffs = 14, -- accent + white
		ringToStuds = 4, -- shockwave ring 0 -> 4 studs
		ringSeconds = 0.25,
		ringTransparencyFrom = 0.3, -- 0.3 -> 1
		minorPuffs = 6, -- expired / fizzle (geometry hits use geometryPuffs, §18.4.2)
		minorFadeMs = 200,
		geometryPuffs = { accent = 4, white = 4 }, -- a geometry hit: 4 in the splat colour + 4 white (§18.4.2)
		flinchSettleMs = 350,
		flashFillFrom = 0.6, -- victim hit flash: white Highlight FillTransparency 0.6 -> 1 ...
		flashSeconds = 0.15, -- ... over 0.15 s
		invulnFillTransparency = 0.75, -- steady ghost Highlight until invulnUntil, no pulse
		vignetteMaxOpacity = 0.2, -- own screen, in the squishy's accent
		vignetteInMs = 80,
		vignetteOutMs = 300,
		hitMarkerScaleFrom = 1.3, -- attacker: ring at the reticle 1.3 -> 1
		hitMarkerMs = 250,
		hitTextMs = 400, -- "Hit!"
		hitTextPopFrom = 1.3, -- "Hit!" pops 1.3 -> 1 (Back Out) ... (§18.4.2)
		hitTextPopMs = 200,
		hitTextTiltDeg = 6, -- ... and tilts ±6° -> 0
		lifePipScaleFrom = 1.2, -- the victim's life pip pops 1.2 -> 0 (Back In)
		lifePipMs = 300,
	},

	-- Splats on a geometry hit (§18.4.1): FxPool parts, one Scheduler effect for all of them. Sizes are fractions of
	-- d = diameterPerRadius × the throw radius; times in ms or seconds as named. Never red: accent:Lerp(White, whiten),
	-- or redGuardWhiten for a hue within redHueDeg of red with saturation > redMinSaturation.
	Splat = {
		diameterPerRadius = 2.2,
		thickness = 0.05,
		oval = 0.86, -- main blob Size (d, thickness, oval × d)
		growMs = 70, -- 0 -> overshoot (Quad Out) ...
		overshoot = 1.12,
		settleMs = 90, -- ... -> 1.0 by growMs + settleMs (Sine InOut)
		droplets = 4,
		dropletDelayMs = 40,
		dropletGrowMs = 80, -- 0 -> 1 (Back Out)
		dropletSizeMin = 0.16, -- × d
		dropletSizeMax = 0.30,
		dropletDistMin = 0.55, -- × d from the centre
		dropletDistMax = 0.85,
		holdSeconds = 1.6,
		fadeSeconds = 0.9, -- after holdSeconds: Transparency `transparency` -> 1 (Quad In), scale 1 -> fadeScaleTo
		fadeScaleTo = 0.9,
		transparency = 0.1,
		lift = 0.03, -- off the surface: lift + (serial % layers) × layerStep
		layerStep = 0.003,
		layers = 12,
		whiten = 0.25,
		redGuardWhiten = 0.6,
		redHueDeg = 15,
		redMinSaturation = 0.45,
		wallNormalMaxY = 0.35, -- |n.Y| below this = a wall (drip)
		dripStuds = 0.5,
		dripFromSeconds = 0.3, -- the drip runs from here to holdSeconds (Quad In)
		dripStretch = 1.4,
		maxLive = 12, -- a 13th sends the oldest to an evictFadeSeconds fade
		evictFadeSeconds = 0.25,
		cullStuds = 120, -- from the camera
		othersCullStuds = 60, -- other players' practice splats (dropped first)
		probeStuds = 1.0, -- visible-surface probe: a ray from position + n · 0.5 along -n · probeStuds
		minVisibleTransparency = 0.5, -- a probed part at or above this gets no splat
		curvedMaxDiameter = 1.6, -- Ball / Cylinder parts: main blob only, d <= this
	},

	-- Hit-stop (§18.4.4), seconds of hold. Holds merge, never stack; at most maxPerWindow per windowSeconds.
	HitStop = {
		playerHit = 0.06,
		elimination = 0.10,
		practiceTarget = 0.04,
		maxPerWindow = 0.12,
		windowSeconds = 0.5,
	},

	-- The attacker's FOV punch (§18.4.3): 0 -> fovDeg by attackMs (Quad Out), -> 0 by attackMs + releaseMs (Sine
	-- InOut). Same gates as the shake (off under ReducedMotion or with settings.cameraShake false).
	Punch = {
		maxFovDeg = 4,
		hitDealt = { fovDeg = -2.5, attackMs = 50, releaseMs = 200 },
		elimDealt = { fovDeg = -3.5, attackMs = 60, releaseMs = 260 },
		practiceHit = { fovDeg = -1.2, attackMs = 50, releaseMs = 180 },
	},

	-- Projectile impact flash (§18.4.2): its own outline Highlight goes White, FillTransparency 1 -> fillFrom -> 1.
	ImpactFlash = { fillFrom = 0.5, ms = 120 },

	-- The victim's held squishy boing (§18.4.2): squash impulse on w, Util/Spring (≈ 2.7 Hz, under §9.12's 3 Hz).
	HeldBoing = { impulse = 0.10, omega = 18, zeta = 0.30, ms = 350 },

	-- Release air ring at the hand, every rarity (§18.4.5): 0 -> toStuds over seconds, White, transparencyFrom -> 1.
	ThrowRing = { toStuds = 1.6, seconds = 0.18, transparencyFrom = 0.5 },

	-- Elimination confetti parts (§18.4.6): parts == Effects.eliminationConfettiParts. Speeds in studs/s, gravity in
	-- studs/s², drag e^(-dragPerSecond · dt), spin in °/s; the pop ring where the squishy vanishes.
	Confetti = {
		parts = 10,
		size = Vector3.new(0.3, 0.05, 0.45),
		upMin = 10,
		upMax = 16,
		outMin = 4,
		outMax = 8,
		gravity = 35,
		dragPerSecond = 1.2,
		spinMinDeg = 360,
		spinMaxDeg = 900,
		lifetime = 1.0,
		fadeSeconds = 0.35, -- fades over the last 0.35 s
		popRingStuds = 3,
		popRingSeconds = 0.25,
	},

	-- Foam Mat feedback (§18.5.1 A3): colour pulse toward SqueezeZone.pulseColor, then a ring on the mat top.
	-- upMs + downMs = Effects.matPulseSeconds × 1000.
	MatPulse = {
		towardPulseColor = 0.55,
		upMs = 40,
		downMs = 110,
		ringToStuds = 5,
		ringSeconds = 0.35,
		ringTransparencyFrom = 0.45,
	},

	-- "+N" above the squishy (§18.5.1 A4). Rise, seconds and max visible stay in Effects (coinPopup*).
	CoinPopup = {
		startStuds = 1.2, -- StudsOffsetWorldSpace Y start; it rises by Effects.coinPopupRiseStuds
		widthPx = 120,
		heightPx = 36,
		iconPx = 22,
		popFrom = 0.6, -- UIScale popFrom -> 1 (Back Out) over popMs
		popMs = 140,
		fadeFromSeconds = 0.4, -- fades from here to Effects.coinPopupSeconds
	},

	-- Lobby background motion (§18.5.1 A8): always the base pivot × f(t), never accumulated.
	Ambient = {
		lollipopDegPerSecond = 10,
		giftSpinDegPerSecond = 18,
		giftBobStuds = 0.12, -- bob = giftBobStuds · (0.5 - 0.5 cos(2πt / giftBobPeriod)), never below the rest pose
		giftBobPeriod = 3.2,
		counterBreatheAmp = 0.02,
		counterBreathePeriod = 3.6,
		statueBreatheAmp = 0.012,
		statueBreathePeriod = 4.2,
		cullStuds = 120,
	},

	-- Camera shake (§9.12): BindToRenderStep(bindName, Camera + priorityOffset), the one documented exception to
	-- the PreRender rule. a = amp·(1 - t/dur)²; off when settings.cameraShake is false or ReducedMotion is on.
	-- Reading: its undo (undoBindName at Camera + undoPriorityOffset, before the camera module) takes the last frame's
	-- offset off again, so the module never rebuilds the camera from a shaken look vector (no lasting aim drift).
	Shake = {
		bindName = "SD_Shake",
		priorityOffset = 1,
		undoBindName = "SD_ShakeUndo",
		undoPriorityOffset = -1,
		noiseHz = 18,
		rollFactor = 0.5, -- z axis uses a·0.5
		maxAmplitudeDeg = 1,
		hitReceived = { amplitudeDeg = 0.5, ms = 200 },
		eliminated = { amplitudeDeg = 0.6, ms = 250 },
		dragonRushNearby = { amplitudeDeg = 0.8, ms = 260, extraStuds = 10 }, -- local players within R + 10
	},

	-- Flash safety (§9.12). The dark duel transition fade is the only exception to maxOverlayOpacity.
	Flash = {
		maxOverlayOpacity = 0.3,
		minPeakMs = 80, -- no overlay reaches its peak faster
		maxFlickerHz = 3,
	},

	-- Projectile readability (§9.7).
	Projectile = {
		outlineTransparency = 0.15, -- Ink outline Highlight, DepthMode Occluded
		fillTransparency = 1,
		shadowTransparency = 0.7, -- soft shadow disc at floorY
		shadowScaleLow = 1.1, -- × flight diameter at the floor ...
		shadowScaleHigh = 0.4, -- ... shrinking with height
		-- Flight size = hit size (§8.1 #9, #11): the flight model is built at flightScale = throw.radius /
		-- frontalRadius, and frontalRadius × flightScale must be within ±this fraction of throw.radius.
		flightRadiusTolerance = 0.15,
	},

	-- Client zone lighting presets (§7.4). Applied only by the client at runtime, tweened over tweenSeconds
	-- (instant under ReducedMotion); back in the lobby the client restores the values it saved on entry.
	-- contrast / saturation: the SD_Grade ColorCorrectionEffect; atmosphereDensity: Lighting.Atmosphere.Density.
	ZonePresets = {
		tweenSeconds = 0.5,
		Arena = {
			contrast = 0.10,
			saturation = 0.0,
			atmosphereDensity = 0.15,
		},
	},

	-- Dragon Rush visuals (§9.10), built only from UltimateEvent numbers.
	DragonRush = {
		castPredictMaxMs = 600, -- predicted ultCharge pose cancels without a telegraph by then
		meterDrainMs = 300,
		handSparkRate = 8, -- ember sparks at the hand during the telegraph (fire texture) ...
		handSparkMaxLive = 8,
		indicatorYOffset = 0.05, -- stadium indicator at floorY + 0.05
		indicatorEdgeTransparency = 0.35, -- edge in Danger colour
		indicatorFillTransparency = 0.6, -- fill strip grows O -> E over the telegraph
		releaseArmSnapMs = 80,
		jawOpenAt = 0.7, -- fraction of the flight
		releaseEmbers = 30,
		jawChompMs = 100,
		indicatorFadeMs = 250,
		cancelFadeMs = 200, -- "Interrupted!"
		recoveryBlendMs = 400, -- hunch weight -> 0 (pose Config.Anim.poses.rushRecovery)
		-- Build scale of the dragon_head_vfx blueprint: DESIGN §8.2 "built at ≈ 3.2" (≈ 3.5 studs wide). §9.10 bounds
		-- it: head width <= 2R (Config.Abilities.dragon_rush.radius); SquishyBuilder_Test checks it.
		headScale = 3.2,
	},

	-- The dash's effects (spec phase 5 §1.2; design: fp.js:506-546, the third-person "Watch a dash"), drawn by
	-- DashController for every dasher. Sizes and speeds in studs: the design writes metres, and 1 stud = 0.28 m
	-- (kit.js:3), so a design value of m metres is m / 0.28 studs. Particle drag: the design multiplies speed by
	-- exp(-drag·dt) (fx.js:135), Roblox halves it every 1/Drag s, so Drag = drag / ln 2. Colours: Art/Palette Dash*.
	-- Small game-feel tier: no shake, no hit-stop, no camera effect for the dasher (user decision 2026-10-11).
	Dash = {
		pushoffPuffs = 12, -- design: fp.js:516
		pushoffSpeed = 2 / 0.28, -- design: fp.js:516 (2 m/s)
		pushoffSize = 0.07 / 0.28, -- design: fp.js:516
		pushoffLifetime = 0.5, -- design: fp.js:516
		pushoffDrag = 4.5 / math.log(2), -- design: fp.js:516 (drag 4.5)
		pushoffGravity = 0.4 / 0.28, -- design: fp.js:516 (gravity 0.4 m/s², a slow rise)
		ringToStuds = 2 * 0.8 / 0.28, -- the push-off ring's diameter: radius 0.1 -> 0.8 m (design: fp.js:516)
		ringSeconds = 0.3, -- design: fp.js:516
		ringTransparencyFrom = 1 - 0.55, -- opacity 0.55 (design: fp.js:516)
		plantPuffs = 8, -- design: fp.js:517
		plantSpeed = 1.4 / 0.28, -- design: fp.js:517
		plantSize = 0.06 / 0.28, -- design: fp.js:517
		plantLifetime = 0.45, -- design: fp.js:517
		plantDrag = 5 / math.log(2), -- design: fp.js:517
		plantGravity = 0.3 / 0.28, -- design: fp.js:517
		-- Three ribbons while the dash runs (Config.Duel.Rules.Dash.ribbonSeconds), at the waist + `height`, in the dasher's
		-- team tint (side A Strawberry, side B Mint; practice: Strawberry, the design runner's), `tintFirst` = the colour
		-- goes tint -> white with age, else white -> tint (design: fp.js:529).
		ribbons = {
			{ height = 0.3 / 0.28, width = 0.32 / 0.28, lifetime = 0.2, opacity = 0.5, tintFirst = true },
			{ height = -0.2 / 0.28, width = 0.2 / 0.28, lifetime = 0.16, opacity = 0.4, tintFirst = false },
			{ height = 0.75 / 0.28, width = 0.12 / 0.28, lifetime = 0.14, opacity = 0.35, tintFirst = false },
		},
		-- Speed lines while the ribbons run: one white particle a frame with this chance, at the waist ± spread, moving
		-- back along the dash (design: fp.js:539).
		speedLineChance = 0.6,
		speedLineSpeed = 3 / 0.28,
		speedLineSize = 0.025 / 0.28,
		speedLineLifetime = 0.2,
		speedLineDrag = 2 / math.log(2),
		speedLineSpread = Vector3.new(0.3 / 0.28, 0.7 / 0.28, 0.3 / 0.28), -- ± (0.3, -0.6..0.8, 0.3) m, centred
		speedLineLift = 0.1 / 0.28,
	},

	-- The four Epic ultimates' effects (spec phase 5 §1.4-§1.8; design: fp.js:236-372), drawn by Anim/UltFx from the
	-- UltimateEvent numbers only. Same metre conversion as Dash. Capped design values (user decision 2026-10-11): the
	-- roller's spin (the design's 22 rad/s ≈ 1260°/s is held to the 720°/s flight-spin limit) and the drop shadow's
	-- pulse (the design's 30 rad/s ≈ 4.8 Hz is held to the 3 Hz flicker limit). Colours: Art/Palette Ult*; the
	-- rarity-coloured pieces use Art/RarityStyle.
	Ultimates = {
		chargeSparkRate = 20, -- glow sparks at the caster's hand during the wind-up, cosmetic (like Dragon Rush's)
		-- Flock Volley: a glide arc and wobble on the drawn bird (design: fp.js:241, 246), the server path is straight.
		glideArcStuds = 0.3 / 0.28, -- design: fp.js:337 (arc 0.3)
		glideWobbleStuds = 0.08 / 0.28, -- design: fp.js:241 (0.08·sin(14k))
		glideWobbleRate = 14, -- radians over the whole flight (k = 0..1)
		glideRollRad = 0.2, -- design: fp.js:246 (0.2·sin(18t))
		glideRollRate = 18, -- rad/s (2.9 Hz)
		growSeconds = 0.14, -- design: fp.js:242 (held size -> 1)
		growFrom = 0.5, -- reading: the held size the design starts from (H.K), relative to the flight size
		-- Sprinkle Roller (design: fp.js:240-245, 339-343).
		laneTransparency = 1 - 0.25, -- design: fp.js:340 (opacity 0.25)
		laneSeconds = 1.6, -- design: fp.js:341
		laneLift = 0.015 / 0.28, -- design: fp.js:341
		rollerScaleFrom = 0.5, -- design: fp.js:342 (scale0)
		rollerScaleTo = 2.3, -- design: fp.js:342 (s1)
		rollerGrowSeconds = 0.3, -- design: fp.js:242 (backOut over 0.3 s)
		rollerSpinDegPerSecond = 720, -- design: fp.js:245 (22 rad/s), capped (see above)
		rollerTiltRad = 0.5, -- design: fp.js:245
		rollerTiltWobbleRad = 0.12, -- design: fp.js:245
		rollerTiltRate = 9, -- rad/s (1.4 Hz), design: fp.js:245
		sprinkleChance = 0.9, -- a frame (design: fp.js:243)
		sprinkleSpeedMin = 1 / 0.28, -- up (design: fp.js:243, 1..2.5 m/s)
		sprinkleSpeedMax = 2.5 / 0.28,
		sprinkleSize = 0.035 / 0.28,
		sprinkleLifetime = 0.7,
		sprinkleGravity = -5 / 0.28,
		-- Rain Check (design: fp.js:255-268, 348-357, 371-372).
		zoneSeconds = 3.2, -- design: fp.js:348
		zonePulseHz = 16 / (2 * math.pi), -- design: fp.js:348 (ω 16 rad/s, 2.5 Hz)
		zoneOpacity = 0.8, -- design: fp.js:335
		zoneFill = 0.2, -- reading: the zone's floor disc is this share of zoneOpacity (the design draws a 10% annulus)
		bunnyHeight = 14, -- above the centre (design: fp.js:349, s(14))
		bunnyArcStuds = 1.4 / 0.28, -- design: fp.js:349
		bunnyGrow = 2.2, -- scale 1 + 2.2·backOut (design: fp.js:266)
		bunnyGrowSeconds = 0.35, -- design: fp.js:266
		hoverSeconds = 2.6, -- design: fp.js:268 (ults.js:5 says it parks 2.2 s)
		-- The hover's bob: the design adds 0.004·sin(3t) m a frame (fp.js:266), at 60 fps a 0.08 m swing (derived).
		bunnyBobStuds = 0.004 * 60 / 3 / 0.28,
		bunnyBobRate = 3, -- rad/s (0.5 Hz)
		drizzleRate = 20, -- a second (design: fp.js:267)
		drizzleSpreadStuds = 0.8 / 0.28,
		drizzleDropStuds = 0.4 / 0.28,
		drizzleSpeed = 2 / 0.28,
		drizzleSize = 0.04 / 0.28,
		drizzleLifetime = 0.5,
		drizzleGravity = -6 / 0.28,
		shadowRadius = 1.6, -- design: fp.js:355 (s(1.6))
		shadowOpacity = 0.5, -- design: fp.js:355
		shadowPulseHz = 3, -- design: fp.js:355 (ω 30 rad/s ≈ 4.8 Hz), capped (see above)
		dropRadius = 0.09 / 0.28, -- design: fp.js:356
		dropScale = Vector3.new(0.8, 1.4, 0.8), -- design: fp.js:371
		splashRingToStuds = 2 * 2, -- diameter: radius 0.05 m -> 2 st (design: fp.js:372)
		splashRingSeconds = 0.3,
		splashTransparencyFrom = 1 - 0.8,
		splashPuffs = 8,
		splashSpeed = 1.5 / 0.28,
		splashSize = 0.03 / 0.28,
		splashLifetime = 0.4,
		-- Bubble Pop (design: fp.js:359-361).
		bubbleRadius = 0.42 / 0.28, -- the shell, visual only (design: fp.js:360)
		bubbleTransparency = 1 - 0.35, -- design: fp.js:360
		bubbleArcStuds = 0.9 / 0.28, -- design: fp.js:359 (arc 0.9)
		popRingToStuds = 2 * 6, -- diameter: radius 0.1 m -> 6 st (design: fp.js:361)
		popRingSeconds = 0.45,
		popTransparencyFrom = 1 - 0.8,
		popPuffs = 26, -- design: fp.js:361
		popSpeed = 3 / 0.28,
		popSize = 0.04 / 0.28,
		popLifetime = 0.6,
		popGravity = -3 / 0.28,
		lingerSeconds = 0.25, -- reading: a drawn projectile fades this long after its server end
	},

	-- Per-effect budgets (§9.15).
	Effects = {
		-- Per squeeze: §9.15's 12 (6 / 8 / 10 / 12 puffs by rarity, §9.6) raised to 18 by §18.9: Exclusive's 12 puffs +
		-- 2 steam, plus the release pop's 2 sparkles or the big pop's 4 (Config.validate checks every flourish against it).
		squeezePuffs = 18,
		othersSqueezePuffs = 4, -- Emit 4 for other players' squeezes ...
		othersSqueezeStuds = 40, -- ... within 40 studs
		matPulseSeconds = 0.15, -- mat pulses Lemon on an accepted squeeze
		coinPopupRiseStuds = 1.5, -- BillboardGui "+N", own player only
		coinPopupSeconds = 0.6,
		coinPopupMaxVisible = 3,
		throwReleasePuffs = 6, -- at the hand at releaseAt
		throwReleaseLifetime = 0.25,
		projectileModels = 1,
		projectileHighlights = 1,
		projectileTrails = 2,
		projectileParticles = 12,
		impactParticles = 20,
		impactRings = 2, -- §18.9: the floor's double ring
		impactHighlights = 1,
		eliminationParticles = 40,
		eliminationConfettiParts = 10, -- §18.9: FxPool confetti parts (Confetti.parts), not particles
		dragonRushHeadParts = 19,
		dragonRushParticles = 60,
		dragonRushSeconds = 1.5,
		boxRevealViewports = 1,
		boxRevealUiFrames = 24,
		ambientEmitters = 3,
		statueSparkleRate = 2, -- Lemon
		statueSparkleLifetime = 1.5,
	},

	-- Client-wide budgets (§9.15). Held-model and joint-layer distances are in Config.Anim.
	Budgets = {
		animatedViewports = 1,
		deformingRigs = 12, -- closest, on screen, <= deformingRigStuds (the Inspect and box reveal models count inside)
		deformingRigStuds = 120,
		liveParticlesPerEffect = 60,
		liveParticlesTotal = 150,
		activeTrails = 8, -- other players' practice trails are culled first
		highlights = 16, -- create/destroy per use (disabled ones still count)
		-- Feel pass (§18.9).
		splats = 12, -- live splats (5 parts each)
		ambientMovers = 6, -- lobby SD_Ambient movers (5 used); the 2 breathers count in deformingRigs
		uiJuiceFrames = 32, -- 8 coins + 18 confetti + 3 popups + 2 bubbles + slack (the box reveal keeps its own 24)
		-- per client: the 3 giant pads + 1 ripple skin (arena or backstop, never both) + 1 knead shell (spec phase2-squeeze
		-- §3.2: MeshQuota key "soft", Inspect's kneaded toy)
		editableMeshes = 5,
		-- (The first-person arms' 2 small session meshes, Anim/SuperMesh, are outside this quota: DESIGN §18.9.)
		-- Squishy overhaul detail levels (spec 2026-10-09 §3.2, §5; the "Low" keys apply when MeshQuality.forCamera()
		-- is "Low", or nil in the first frames). Hero (own held, Inspect, reveal; at most heroRigs, Inspect and the
		-- reveal first) gets everything; near (the next held models by distance) squash, face, blink and jiggle; the
		-- rest up to deformingRigs breathing and squash (HeldSquishyController.rigBudget).
		-- Section flaps and the flight pulse run on at most flightDetailModels projectiles.
		deformingRigsLow = 8,
		heroRigs = 3,
		heroRigsLow = 2,
		nearRigs = 6,
		nearRigsLow = 3,
		flightDetailModels = 2,
		flightDetailModelsLow = 1,
	},

	-- ReducedMotion (GuiService.ReducedMotionEnabled; no in-game setting, DESIGN §11.6): shake off, box light rays off,
	-- particle counts × this.
	reducedParticleMultiplier = 0.5,

	-- Anim/FxPool sizing. reading (not in DESIGN, provisional).
	Pool = {
		idlePerKind = 24, -- released instances kept per kind (emitter, trail, part); extra ones are destroyed
		releaseMarginSeconds = 0.1, -- an emitter is reused this long after its burst's longest particle lifetime
	},
}

return Vfx
