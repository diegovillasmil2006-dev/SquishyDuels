--!strict
-- Config.JoyFx (2026-11-10, big job item 1; the owner: the effects are "a 6/10 ... more attractive to kids"; for
-- effects this may go beyond the design files, in the same style). Shared, data only: the everyday moments' candy
-- look, drawn with the candy kit pictures (AssetTable img.kit.*: a dark ink outline, a colour body, a white shine).
-- The rules it follows (LihFolk vault "VFX Readability and Value", "Reward Moments and Celebrations", "Juice on a
-- Budget"): reads in under a second at phone size; dark ink + colour body + white core + one accent; a hot frame
-- under 0.1 s and a short tail; a bigger prize adds layers while small prizes stay small and fast; never red, never
-- over the player. Looks only: no number here changes pay, timing windows or hit sizes.
--   squeeze   Controllers/SqueezeFeel: the peak burst, the release pop and the big pop of the held squishy (third
--             person; the first-person overlay keeps the design's own small sparkles, owner 2026-10-26)
--   penCoin   Controllers/PenController: a coin hops out of each of the own pen's squishies when the pen pays
--   levelUp   Controllers/GripController: the Grip level-up's burst round the player (Anim/FeelFx plays `moments`)
--   ui        UI/UiFx: the burst tiers' stars and hearts and its white core flash
-- Every particle goes through Anim/FxPool or Anim/MoveVfx: pooled, capped by Config.Vfx.Budgets, halved on phones
-- and under ReducedMotion. Sizes in studs, times in seconds, speeds in studs/s.

local JoyFx = {
	-- The switch: false = the looks from before 2026-11-10 (plain puffs and sparkles, no pen coins, no level burst).
	enabled = true,

	squeeze = {
		-- Of a squeeze's puff count (6 to 12 by rarity, 4 for other players), this share are gold stars; the rest
		-- are puffs in a light tint of the squishy's colour.
		starShare = 0.5,
		-- The player sees the squishy from behind their own character (the third-person camera): the pieces are drawn
		-- zOffset studs nearer the camera, so the body never hides them, and they fly up and out past the shoulders.
		zOffset = 2,
		puff = {
			tintToWhite = 0.45,
			size = { { 0, 0.45 }, { 0.3, 1 }, { 1, 0.25 } },
			transparency = { { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } },
			lifetime = { 0.28, 0.4 },
			speed = { 7, 11 },
			spreadDeg = 180,
			drag = 4,
			rotSpeed = 90,
		},
		star = {
			size = { { 0, 0.25 }, { 0.18, 0.9 }, { 0.75, 0.7 }, { 1, 0 } },
			lifetime = { 0.4, 0.55 },
			speed = { 13, 19 },
			spreadDeg = 65, -- up and out, never down into the hand
			drag = 3,
			gravity = -50,
			rotSpeed = 260,
		},
		-- The release pop's sparkles (2, the big pop 4): white twinkles with the ink edge.
		pop = {
			size = { { 0, 0 }, { 0.3, 0.8 }, { 1, 0 } },
			lifetime = { 0.25, 0.35 },
			speed = { 5, 9 },
			spreadDeg = 180,
			lightEmission = 0.5,
		},
		-- Every 8th squeeze in a row (the big pop): hearts float up and more stars fly, on top of the sparkles.
		bigPop = {
			hearts = 4,
			heart = {
				size = { { 0, 0.2 }, { 0.2, 0.95 }, { 0.8, 0.8 }, { 1, 0 } },
				lifetime = { 0.55, 0.75 },
				speed = { 5, 8 },
				spreadDeg = 45,
				drag = 2.5,
				gravity = 8, -- they keep floating up
				rotation = 20,
				rotSpeed = 45,
			},
			stars = 6,
		},
	},

	penCoin = {
		-- At most one hop a squishy every `everySeconds` (the pen pays every Config.Pen.tickSeconds); only the own pen,
		-- only squishies on screen within the pen's animation distance.
		everySeconds = 0.9,
		liftStuds = -0.35, -- over the "+N/s" label's centre (negative = above): the coin never covers the number
		size = { { 0, 0.4 }, { 0.15, 1.2 }, { 0.7, 1 }, { 1, 0 } },
		transparency = { { 0, 0 }, { 0.75, 0 }, { 1, 1 } },
		lifetime = { 0.55, 0.65 },
		speed = { 12, 14 },
		spreadDeg = 14,
		gravity = -48,
		rotation = 12,
		rotSpeed = 80,
	},

	-- The Grip level-up round the player: Anim/FeelFx events (the same format as Config.MoveFx.moments); the
	-- particles are SDTools.Builders.FeelVfxBuilder's joy* templates. Every piece starts on a ring round the feet
	-- and flies up and out: the body stays clear.
	moments = {
		levelUp = {
			{ t = 0, ring = "joyRing", at = "feet" },
			{ t = 0, burst = "joyStars", at = "feet", aim = "up" },
			{ t = 0.04, burst = "joyConfetti", at = "feet", aim = "up" },
			{ t = 0.08, burst = "joySparkles", at = "feet", aim = "up" },
			{ t = 0.1, ring = "joyRingWide", at = "feet" },
		},
		-- A rank unlock (a level-up with an unlock line): the same, one layer more (hearts). 54 particles: within the
		-- 60 an effect may show (Config.Vfx.Budgets.liveParticlesPerEffect; JoyFx_Test checks it).
		levelUpUnlock = {
			{ t = 0, ring = "joyRing", at = "feet" },
			{ t = 0, burst = "joyStars", at = "feet", aim = "up" },
			{ t = 0.04, burst = "joyConfetti", at = "feet", aim = "up" },
			{ t = 0.08, burst = "joySparkles", at = "feet", aim = "up" },
			{ t = 0.1, ring = "joyRingWide", at = "feet" },
			{ t = 0.14, burst = "joyHearts", at = "feet", aim = "up" },
		},
	} :: { [string]: { any } },
	rings = {
		joyRing = {
			color = Color3.fromHex("#FFD451"), -- Art/Palette CandyGold
			sizeStart = 1.5,
			sizeEnd = 9,
			time = 0.3,
			easing = "Quad Out",
			transparencyStart = 0,
			transparencyEnd = 1,
			transparencyEasing = "Quad In",
		},
		joyRingWide = {
			color = Color3.fromHex("#FFFFFF"),
			sizeStart = 2,
			sizeEnd = 14,
			time = 0.42,
			easing = "Quad Out",
			transparencyStart = 0.25,
			transparencyEnd = 1,
			transparencyEasing = "Quad In",
		},
	},
	-- Anim/FeelFx reads these from every moment table; this one has none of them.
	stage = { feetLift = 0.06, groundLift = 0.04, chestHeight = 3.6, backUpAngle = 35 },
	posePriority = 1.7,
	heldArmJoints = { "RightShoulder", "RightElbow", "RightWrist" },
	poses = {},
	texts = {},
	textCanvas = { aspect = 4, fontShare = 150 / 256, strokeShare = 22 / 150 },
	dips = {},
	shakes = {},
	shakeNoise = { 0.65, 0.35, 1.73 },
	fovs = {},
	lines = {},
	afterimages = {},
	glows = {},
	lights = {},
	flashes = {},
	screens = {},
	punches = {},
	slowmos = {},
	sounds = {} :: { [string]: any },
	phone = { countShare = 0.5, trailLifetimeScale = 0.7 },

	ui = {
		-- UiFx.burst: its "sparkle" pieces are chunky stars (px), popping in with an overshoot; from the "large" tier
		-- every heartEvery-th one is a heart; the white core flashes at the centre for coreSeconds.
		starPx = 30,
		sparkStarScale = 1.6, -- UiFx.sparks / converge: their stars x this (the chunky star's ink outline must read)
		heartEvery = 3,
		heartFromTier = { large = true, huge = true },
		corePx = 0.9, -- x the tier's radius
		coreSeconds = 0.12,
	},
}

return JoyFx
