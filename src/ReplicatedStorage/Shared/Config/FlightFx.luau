--!strict
-- Config.FlightFx (2026-10-28, the physics upgrade's part 3: squishies flying in duels; owner: "Yes, build part 3").
-- Shared, data only. The co-owner's Claude Design page docs/squishy-fx-spec/duelflight.html (CONFIG.fx, CONFIG.moments;
-- readable copy notes.md "Part 3 · Duel flight"), ADDED ON TOP of what the game already has (owner, Decisions
-- 2026-10-28): Diego's charge (its tone, FOV narrowing, release rings and first-person kick), his catch crush and burst,
-- every squishy's own trail and the bounce-by-feel of a miss (Anim/GroundBounce) all stay. Ported: the release pop
-- (squash keys), the flight jiggle and the barrel spin on every drawn throw (ProjectileRenderer); the release puff and a
-- tiny camera kick (third person only: first person keeps Diego's kick); the charge's puff-up and jiggle on the held
-- squishy (its overlay; the first-person hands mirror it), its sparkles, and at full charge the glow, ring, pop and MAX!;
-- the gold halo and sparkle trail of a charged throw; BOING! and jelly drops on a miss's big bounce; on a catch the
-- catcher's clamp and release poses (every client), the leaking jelly, CAUGHT! and the camera absorb (the catcher).
-- Not ported (already in the game, or the owner chose so): throwOverhand (the windup and release poses stay), the
-- flight trails (the signature trails stay), chargeFocus (Diego's charge narrows the FOV), chargeReadyDing / charge
-- loop / throw whooshes (Diego's sounds), the design's bounce numbers and bounce puffs (GroundBounce), the catch ring,
-- puff and burst pieces (Diego's), catchReady (other clients never see a catch press).
-- Played by Client/Anim/FeelFx; the particles are FeelVfxBuilder's (SD_MoveVfx.Feel); Controllers/FlightFxController
-- picks the moments. views: "1P" / "3P" for the own throw and charge; "R1P" = the local catcher, "OBS" anyone else.

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local FlightFx = {
	-- The switch: false = the throws, charges, misses and catches look as before part 3.
	enabled = true,
	-- A throw counts as charged (the design's full charge) from this charge share (ThrowStarted's power 0..1).
	chargedFrom = 0.9,
	-- The barrel spin about the travel axis (deg/s, CONFIG.throw spinTap / spinCharged), on top of the toy's own
	-- flight style (its roll, nod and pulse stay).
	spin = { tap = 540, charged = 900 },
	-- Squash keys { t, x, y, z, easing to the next key } in pivot space (Z along the travel, Y up), the design's
	-- squash tracks. The release keys end on the design's cruise stretch: the game keeps its own cruise stretch, so
	-- FlightFxController divides by the last key (the pop ends at 1).
	squashes = {
		releaseStretch = {
			hold = true,
			keys = {
				{ 0, 0.8, 0.8, 1.45, "Quad Out" },
				{ 0.06, 1.1, 1.1, 0.88, "Quad InOut" },
				{ 0.12, 0.96, 0.96, 1.1, "Sine InOut" },
				{ 0.2, 1, 1, 1.05 },
			},
		},
		releaseStretchBig = {
			hold = true,
			keys = {
				{ 0, 0.72, 0.72, 1.6, "Quad Out" },
				{ 0.07, 1.15, 1.15, 0.85, "Quad InOut" },
				{ 0.14, 0.94, 0.94, 1.14, "Sine InOut" },
				{ 0.22, 0.97, 0.97, 1.08 },
			},
		},
		-- The held squishy inflates 18 % over the full charge (the first-person hands' toy mirrors it).
		chargeGrow = { hold = true, keys = { { 0, 1, 1, 1, "Quad Out" }, { 1, 1.18, 1.18, 1.18 } } },
	},
	-- Wobbles: k = amplitude e^(-decay t) sin(2 pi frequency t); X and Z x (1 + k), Y x (1 - k axisRatio); over at `time`.
	wobbles = {
		flightJiggle = { amplitude = 0.06, frequency = 7, decay = 2.5, axisRatio = 1, time = 1.2 },
		chargeJiggle = { amplitude = 0.05, frequency = 6, decay = 0, axisRatio = 1, time = 1 },
	},
	-- A miss's floor contact at least this fast (studs/s into the floor) is the design's big bounce (BOING!).
	bounce = { bigFrom = 18 },

	stage = { feetLift = 0.06, groundLift = 0.04, chestHeight = 3.6, backUpAngle = 35 },
	posePriority = 1.8, -- the catch poses: over the movement feel, like a hit's
	heldArmJoints = { "RightShoulder", "RightElbow", "RightWrist" },

	-- allArms: both arms clamp, the holding one too (FeelFx leaves a holding arm out of other poses).
	poses = {
		catchClamp = {
			allArms = true,
			fadeIn = 0,
			keys = {
				{
					t = 0,
					easing = "Cubic Out",
					rootPos = v(0, -0.2, 0.15),
					joints = {
						Root = v(6, 0, 0),
						Waist = v(-8, 0, 0),
						Neck = v(-10, 0, 0),
						LeftShoulder = v(38, 0, 30),
						RightShoulder = v(38, 0, -30),
						LeftElbow = v(30, 0, 0),
						RightElbow = v(30, 0, 0),
					},
				},
				{
					t = 0.12,
					easing = "Sine InOut",
					rootPos = v(0, -0.1, 0.05),
					joints = {
						Root = v(0, 0, 0),
						Waist = v(-6, 0, 0),
						Neck = v(-10, 0, 0),
						LeftShoulder = v(38, 0, 28),
						RightShoulder = v(38, 0, -28),
						LeftElbow = v(28, 0, 0),
						RightElbow = v(28, 0, 0),
					},
				},
				{
					t = 1.02,
					joints = {
						Waist = v(-10, 0, 0),
						Neck = v(-12, 0, 0),
						LeftShoulder = v(40, 0, 36),
						RightShoulder = v(40, 0, -36),
						LeftElbow = v(36, 0, 0),
						RightElbow = v(36, 0, 0),
					},
				},
			},
		},
		catchRelease = {
			allArms = true,
			fadeOut = 0.25,
			keys = {
				{
					t = 0,
					easing = "Cubic Out",
					joints = {
						Neck = v(10, 0, 0),
						LeftShoulder = v(60, 0, -40),
						RightShoulder = v(60, 0, 40),
						LeftElbow = v(20, 0, 0),
						RightElbow = v(20, 0, 0),
					},
				},
				{
					t = 0.25,
					joints = {
						Neck = v(0, 0, 0),
						LeftShoulder = v(20, 0, -20),
						RightShoulder = v(20, 0, 20),
						LeftElbow = v(15, 0, 0),
						RightElbow = v(15, 0, 0),
					},
				},
			},
		},
	},

	texts = {
		readyText = { text = "MAX!", color = Color3.fromHex("#FFD86B"), stroke = Color3.fromHex("#3B2A35"), offset = v(0, 2.2, 0), size = { { 0, 0 }, { 0.08, 1.4 }, { 0.14, 1.1 }, { 0.35, 1.1 }, { 0.45, 0 } }, transparency = { { 0, 0 }, { 0.35, 0 }, { 0.45, 1 } }, time = 0.45 },
		boingText = { text = "BOING!", color = Color3.fromHex("#FF8FB1"), stroke = Color3.fromHex("#3B2A35"), offset = v(0, 2.6, 0), size = { { 0, 0 }, { 0.08, 2.6 }, { 0.14, 2.1 }, { 0.4, 2.2 }, { 0.55, 0 } }, transparency = { { 0, 0 }, { 0.4, 0 }, { 0.55, 1 } }, time = 0.55 },
	},
	textCanvas = { aspect = 4, fontShare = 150 / 256, strokeShare = 22 / 150 },
	rings = {
		chargeReadyRing = { color = Color3.fromHex("#FFD86B"), sizeStart = 0.8, sizeEnd = 3.6, time = 0.2, easing = "Quad Out", transparencyStart = 0, transparencyEnd = 1, transparencyEasing = "Quad In" },
	},
	glows = {
		chargeReadyGlow = { fill = Color3.fromHex("#FFFFFF"), outline = Color3.fromHex("#FFD86B"), fillFrom = 0.3, outlineFrom = 0, time = 0.18, easing = "Quad Out" },
	},
	punches = {
		releaseKick = { offset = v(0, 0, 0), rotation = v(0.6, 0, 0), attack = 0.03, attackEasing = "Quad Out", hold = 0, release = 0.12, releaseEasing = "Quad Out" },
		releaseKickBig = { offset = v(0, 0, 0), rotation = v(1.5, 0, 0.6), attack = 0.03, attackEasing = "Quad Out", hold = 0, release = 0.18, releaseEasing = "Back Out" },
		catchAbsorb = { offset = v(0, 0, 0.25), rotation = v(-1.2, 0, 0), attack = 0.04, attackEasing = "Quad Out", hold = 0, release = 0.22, releaseEasing = "Quad Out" },
	},
	fovs = {
		releaseFovCharged = { delta = 4, attack = 0.04, attackEasing = "Quad Out", hold = 0.03, release = 0.25, releaseEasing = "Sine InOut" },
	},
	-- Screen words (FeelFx "banner": px at 1080p; y / fromY = the share of the screen height from the top, x of its width).
	screens = {
		caughtBanner = { kind = "banner", text = "CAUGHT!", color = Color3.fromHex("#8EDFC4"), stroke = Color3.fromHex("#3B2A35"), strokePx = 12, fontPx = 84, x = 0.5, y = 0.22, fromY = 0.08, fromScale = 0.6, fadeIn = 0.18, inEasing = "Back Out", hold = 0.7, fadeOut = 0.25, outEasing = "Quad In" },
		-- NOT IN DESIGN: first person's MAX! (the design pops it on the hands' toy, low right: the game's hands are a
		-- separate overlay, so it pops on the screen beside them, with readyText's timing).
		maxScreen = { kind = "banner", text = "MAX!", color = Color3.fromHex("#FFD86B"), stroke = Color3.fromHex("#3B2A35"), strokePx = 8, fontPx = 64, x = 0.66, y = 0.66, fromY = 0.72, fromScale = 0.6, fadeIn = 0.08, inEasing = "Back Out", hold = 0.27, fadeOut = 0.1, outEasing = "Quad In" },
	},
	shakes = {},
	dips = {},
	lines = {},
	afterimages = {},
	-- The design's sound names: all of them are the game's own sounds already (Diego's throw, charge, catch and burst
	-- sounds, GroundBounce's bounce), so none plays twice.
	sounds = {
		throw_whoosh = false,
		throw_charged_whoosh = false,
		charge_loop = false,
		charge_ready_ding = false,
		squishy_boing = false,
		squishy_boing_small = false,
		squishy_roll_loop = false,
		squishy_settle = false,
		catch_smack = false,
		squish_squeeze_loop = false,
		catch_burst_pop = false,
	} :: { [string]: any },

	moments = {
		-- The release (every viewer; at the hand on the throw's first drawn frame). The own first-person view keeps
		-- Diego's release and kick (the puff and the kick are third person only).
		release = {
			{ t = 0, burst = "releasePuff", at = "hit", aim = "forward", views = { "3P" } },
			{ t = 0, punch = "releaseKick", views = { "3P" } },
		},
		releaseCharged = {
			{ t = 0, burst = "releasePuff", at = "hit", aim = "forward", views = { "3P" } },
			{ t = 0, punch = "releaseKickBig", views = { "3P" } },
			{ t = 0, fov = "releaseFovCharged", views = { "3P" } },
		},
		-- The own charge (other clients never see a charge start). In first person the own held model is hidden (the
		-- hands' overlay shows it): its world effects would float, so the ready moment goes to the hands' toy.
		charge = {
			{ t = 0, emit = "chargeSparksA", at = "held", ["for"] = 0.5, views = { "3P" } },
			{ t = 0.5, emit = "chargeSparksB", at = "held", ["for"] = 0.5, views = { "3P" } },
			{ on = "full", t = 0, glow = "chargeReadyGlow", target = "held", views = { "3P" } },
			{ on = "full", t = 0, ring = "chargeReadyRing", at = "held", face = "forward", views = { "3P" } },
			{ on = "full", t = 0, burst = "chargeReadyPop", at = "held", views = { "3P" } },
			{ on = "full", t = 0, pop = "readyText", at = "held", views = { "3P" } },
			{ on = "full", t = 0, call = "readyMirror", views = { "1P" } },
			{ on = "full", t = 0, screen = "maxScreen", views = { "1P" } },
		},
		-- A charged throw in flight (until it lands, hits or is caught).
		chargedFlight = {
			{ t = 0, emit = "chargedSparkTrail", at = "root" },
			{ t = 0, emit = "chargedAura", at = "root" },
		},
		-- A miss's big bounce (at the floor under it).
		missBig = {
			{ t = 0, pop = "boingText", at = "hit" },
			{ t = 0, burst = "bounceDrops", at = "hit", aim = "up" },
		},
		-- A catch (every client: the catcher's body); "burst" = CatchController.Burst.
		catch = {
			{ t = 0, pose = "catchClamp" },
			{ t = 0, punch = "catchAbsorb", views = { "R1P" } },
			{ t = 0, screen = "caughtBanner", views = { "R1P" } },
			{ t = 0.05, emit = "catchLeak", at = "hands", aim = "down", ["for"] = 0.95 },
			{ on = "burst", t = 0, stop = "catchLeak" },
			{ on = "burst", t = 0, pose = "catchRelease" },
		},
	} :: { [string]: { any } },

	-- The first-person ready moment on the hands' toy (HeldSquishyController.mirrorFx): the ring and the pop's sparkles.
	mirror = { ring = Color3.fromHex("#FFD86B"), sparkles = 10, sparkleColor = Color3.fromHex("#FFFFFF") },
	phone = { countShare = 0.5, trailLifetimeScale = 0.7 },
	reduceMotion = { flash = 0.5 },
}

return FlightFx
