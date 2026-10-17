--!strict
-- Config.FirstPerson: first person in duels, the practice range's throw box and the lobby look (spec 2026-10-10 §4.1,
-- spec 2026-10-11 §3). Shared, data only. Read by the client FirstPersonController (camera), ViewmodelController (the
-- two-arm overlay), Anim/ViewmodelMath, Anim/SuperMesh, Anim/DesignArm, Anim/OwnArm, Anim/NearFade,
-- ProjectileRenderer and VfxController.
-- Units: "du" are the 3D Lab's viewmodel metres (camera space: -Z forward, +Y up, +X right); the overlay draws
-- overlayStudsPerDu studs per du. Angles in radians unless the name says Deg. Springs are { k, c } (x'' = -k x - c x');
-- every one is <= 3 Hz (Config.validate).
-- The switch is session only (answer 2): defaultOn is where every join starts, and nothing here is ever saved.
-- Spec 2026-10-11 §3 (design fidelity) replaces step 2's one hand with the 3D Lab FP viewmodel: its numbers are the
-- keys from `light` down, plus the step-2 keys that already held them (fovDeg, toyLongestDu, rest, shoulder, equipFrom,
-- the springs, idle, kick.release), each with its "design: <file>:<line>" (the 3D Lab package sd/*.js and HANDOFF.md).
-- Step 2's inventions (the cup hand, its pose and sizes, look sway, walk bob, the landing / hit / lift kicks, the Rush
-- lift and push, the mode blend, the reticle rule, the Inspect hand and the per-toy hand offsets) are gone with the
-- code that read them (spec 2026-10-11 §2, §6); resultHoldSeconds to victimImpactScale are step 2's game rules, kept
-- (§3.7).

-- One arm part (spec 2026-10-11 §3.2): a superellipsoid of `exponent`, full size `size` (du), coloured by a `colours`
-- key, at `pos` with Euler XYZ `rot` (rad) in the arm frame; pos.X and rot.Y are the right arm's, × side.
export type ArmPart = { name: string, size: Vector3, exponent: number, colour: string, pos: Vector3, rot: Vector3 }

local FirstPerson = {
	defaultOn = true, -- session switch default (answer 2: not saved)
	gui = { displayOrder = -1, insets = Enum.ScreenInsets.None }, -- SD_Viewmodel (not in Config.UI.ScreenGuis)
	padGui = { displayOrder = 6, insets = Enum.ScreenInsets.CoreUISafeInsets }, -- SD_ViewmodelPad (touch only)
	touchGuiFallbackOrder = 7, -- only if DisplayOrder -1 does not sort under Roblox's TouchGui (Studio check)
	-- Phone speed fix (2026-10-16, NOT IN DESIGN): on the low tier (Anim/MeshQuality "Low": touch-only devices and
	-- windows under 700 px wide or 500 px tall) the overlay steps at most stepHz times a second (on a 60 fps phone its
	-- hands redraw every other frame; the springs get the skipped time, so every motion keeps its timing; the world FOV
	-- still moves every frame). stepHz = 0 switches the cap off (every frame, as before). Batch B (owner 2026-10-17:
	-- "throws make half the sparkles"): the duel hands' specks (charge, release, catch, crush) come at speckShare
	-- there (ReducedMotion's share on top); the Inspect showcases keep every speck. 1 = off.
	lowTier = {
		stepHz = 30,
		speckShare = 0.5,
	},
	practiceExitDelaySeconds = 0.3, -- leaving the throw box: first person ends this long after (no flip on the edge)
	-- The overlay toy squeezes on X: it narrows and grows taller between the two palms (spec 2026-10-11 §3.4;
	-- design: HANDOFF.md:56). The held rig switches axis only at rest.
	squeezeAxis = "X",
	fovDeg = 70, -- the overlay camera's vertical FOV, never changed (design: fp.js:28)
	overlayStudsPerDu = 4, -- u (any value: only ratios matter, spec 2026-10-11 §3.1)
	toyLongestDu = 0.19, -- the held toy's longest side (design: fp.js:99)
	rest = Vector3.new(0.16, -0.23, -0.46), -- the empty right hand, REST_R; X × side (design: fp.js:77)
	shoulder = Vector3.new(0.5, -0.52, -0.04), -- the right shoulder anchor; X × side (design: fp.js:73)
	equipFrom = Vector3.new(0, -0.42, -0.44), -- the pop-in's start, at speed 0 (design: fp.js:103)
	-- The design's springs are semi-implicit Euler, substeps <= 1/240 s (fp.js:16-18).
	springs = {
		hand = { 520, 40 }, -- 1.74 Hz; the hand point H (design: fp.js:73)
		roll = { 300, 30 }, -- 1.38 Hz; the arm's roll (design: fp.js:73)
		toyPos = { 420, 36 }, -- 1.56 Hz (design: fp.js:94)
		toyRot = { 260, 30 }, -- 0.94 Hz (design: fp.js:94)
		toyScale = { 500, 30 }, -- 2.64 Hz (design: fp.js:94)
		kick = { 150, 15 }, -- 1.54 Hz (design: fp.js:49)
		focus = { 140, 24 }, -- overdamped (ζ 1.01); the focus share 0..1 (design: fp.js:78)
		fov = { 170, 17 }, -- 1.57 Hz; the world FOV offset, see focus (design: fp.js:49)
	},
	-- The whole overlay (design: fp.js:660): offset (x·sin(2π·xHz·T), y·sin(2π·yHz·T) + kickY·kick.x, 0) du, rotation X
	-- kickPitch·kick.x, applied as the inverse on the overlay camera (spec 2026-10-11 §3.1); the toy breathes
	-- y += breath·sin(breathRate·T) (design: fp.js:396).
	idle = {
		x = 0.002, -- design: fp.js:660
		xHz = 0.9 / (2 * math.pi), -- design: fp.js:660
		y = 0.003, -- design: fp.js:660
		yHz = 1.7 / (2 * math.pi), -- design: fp.js:660
		kickY = 0.01, -- design: fp.js:660
		kickPitch = 0.02, -- design: fp.js:660
		breath = 0.004, -- design: fp.js:396
		breathRate = 2.2, -- design: fp.js:396
	},
	-- impulses on the kick spring's velocity (springs.kick; idle.kickY / kickPitch show it)
	kick = {
		release = -0.8, -- a throw's release: kick.v.x -= 0.8 (design: fp.js:437)
	},
	-- the throw strike reads Config.Anim.throw.releaseSnapMs (70 ms); no copy here
	resultHoldSeconds = 0.4,
	countdownPitchDeg = -3,
	nearFade = { from = 2.5, to = 4.5 },
	rushFadeIn = { from = 3, to = 8 },
	invulnTransparency = 0.4,
	ownRingScale = 0.5,
	victimImpactScale = 0.25,

	-- The 3D Lab FP viewmodel (spec 2026-10-11 §3). "X × side": the right arm's value (side +1), mirrored for the left
	-- (side -1). Roblox has no slot for what the design does here and there; §3.9 names the closest option used.
	-- The overlay's light (§3.1, closest option): Ambient ≈ the hemisphere light (sky, ground, intensity), LightColor =
	-- key, LightDirection = -keyFrom.Unit (the key shines from keyFrom toward the origin). The rim light (fp.js:34) has
	-- no slot: a ViewportFrame has one directional light.
	-- The three.js light numbers do not map 1:1 onto a ViewportFrame (Ambient + LightColor · N·L clipped the skin to
	-- pale yellow, Studio 2026-10-11). viewportAmbient and viewportLight are set so the overlay's skin matches the
	-- design's own picture: the hands' top face measured (232, 189, 144) against the design shot 02-fp3's
	-- (231, 192, 145), at 1920 × 1080 (Studio 2026-10-11). The direction stays the design's key.
	light = {
		sky = Color3.fromHex("#FFFFFF"), -- design: fp.js:32
		ground = Color3.fromHex("#B8C9A8"), -- design: fp.js:32
		hemisphere = 1.1, -- design: fp.js:32
		key = Color3.fromHex("#FFF3DC"), -- design: fp.js:33
		keyIntensity = 1.9, -- design: fp.js:33
		keyFrom = Vector3.new(-0.4, 1, 0.6), -- design: fp.js:33
		viewportAmbient = Color3.new(0.88, 0.86, 0.82), -- matched to design shot 02-fp3 (see above)
		viewportLight = Color3.new(0.46, 0.44, 0.4), -- matched to design shot 02-fp3 (see above)
	},
	-- Two arms of five parts (§3.2; design: fp.js:64-76). The arm frame: root at the hand point H, +Z aimed at the
	-- arm's shoulder (`shoulder`, X × side), rolled about its Z: CFrame.lookAt(H, shoulder) · Angles(0, π, 0) ·
	-- Angles(0, 0, roll) (Anim/DesignArm.partFrames). Each part is a superellipsoid (design: kit.js:41-71) of
	-- `segments` (width × height); no shadow, no collide, touch or query.
	arm = {
		parts = {
			{
				name = "hand",
				size = Vector3.new(0.1, 0.094, 0.112), -- design: fp.js:67
				exponent = 7, -- design: fp.js:65, 67
				colour = "skin", -- design: fp.js:70
				pos = Vector3.zero, -- design: fp.js:70
				rot = Vector3.zero,
			},
			{
				name = "thumb",
				size = Vector3.new(0.036, 0.04, 0.062), -- design: fp.js:67
				exponent = 5, -- design: fp.js:67
				colour = "skin", -- design: fp.js:70
				pos = Vector3.new(-0.047, 0.026, -0.02), -- X × side (design: fp.js:70)
				rot = Vector3.new(0, 0.35, 0), -- Y × side (design: fp.js:70)
			},
			{
				name = "forearm",
				size = Vector3.new(0.09, 0.086, 0.3), -- design: fp.js:67
				exponent = 7, -- design: fp.js:65, 67
				colour = "skin", -- design: fp.js:71
				pos = Vector3.new(0, 0, 0.2), -- design: fp.js:71
				rot = Vector3.zero,
			},
			{
				name = "cuff",
				size = Vector3.new(0.117, 0.114, 0.036), -- design: fp.js:67
				exponent = 8, -- design: fp.js:67
				colour = "cuff", -- design: fp.js:71
				pos = Vector3.new(0, 0, 0.35), -- design: fp.js:71
				rot = Vector3.zero,
			},
			{
				name = "sleeve",
				size = Vector3.new(0.114, 0.11, 0.42), -- design: fp.js:67
				exponent = 7, -- design: fp.js:65, 67
				colour = "sleeve", -- design: fp.js:71
				pos = Vector3.new(0, 0, 0.57), -- design: fp.js:71
				rot = Vector3.zero,
			},
		} :: { ArmPart },
		segments = { 28, 20 }, -- design: fp.js:65 (kit.js:48 SphereGeometry(1, ws, hs))
		startPos = Vector3.new(0.16, -0.25, -0.46), -- the hand spring's first position, X × side (design: fp.js:73)
		roll = 0.4, -- at rest and holding: the left hand +roll, the right -roll (design: fp.js:394)
	},
	colours = {
		skin = Color3.fromHex("#F5CDA4"), -- design: fp.js:66
		cuff = Color3.fromHex("#FFF8EE"), -- design: fp.js:66
		sleeve = Color3.fromHex("#5FD3AE"), -- mint; practice and the lobby (design: fp.js:66)
	},
	-- In a duel the sleeve is the side's team colour (§3.2; design: HANDOFF.md:83, avatar.js:12). Side A is Strawberry
	-- and side B Mint, as DuelFormat.sideColors.
	teamSleeves = {
		A = Color3.fromHex("#F2687F"), -- strawberry (design: HANDOFF.md:83)
		B = Color3.fromHex("#5FD3AE"), -- mint (design: HANDOFF.md:83)
	},
	-- The outline (§3.2, closest option: a fixed inverted hull per part, the unit mesh with reversed winding, sized part
	-- size + 2t on each axis): t = px · 2 · refDepthDu · tan(fovDeg / 2) / refHeightPx, about 0.0018 du.
	outline = {
		colour = Color3.fromHex("#1B1220"), -- design: toon.js:17, 46
		px = 3, -- design: fp.js:72
		refHeightPx = 1080, -- spec 2026-10-11 §3.2 (1920 × 1080)
		refDepthDu = 0.46, -- the hold depth (spec 2026-10-11 §3.2; REST z, design: fp.js:77)
	},
	-- The player's own avatar arms (user decision 2026-10-11: each player's own full avatar arms, skin, shirt sleeves
	-- and body shape, in the design's motions; Anim/OwnArm): copies of the local R15 Hand, LowerArm and UpperArm. The
	-- design arms above are the fallback. Engineering limits, not design visuals (spec phase1-arms §3.6).
	ownArms = {
		enabled = true,
		handWidthDu = 0.1, -- the avatar hand's Size.X shows this wide: the design hand's width (design: fp.js:67)
		-- + the upper arm's radius: past this the arm is off screen in every design pose (0.42 du + the arm's radius,
		-- measured 2026-10-11 from fp.js:77, 145-155; 0.03 du margin)
		reachDu = 0.45,
		maxStretch = 5, -- past the wrist the arm stretches at most this much along its length; more = odd (fallback)
		palmRoll = 0, -- an extra turn about the arm (rad, × side) if the palms do not face the toy
		maxWidthDu = 0.2, -- a scaled LowerArm / UpperArm thicker than this is odd
		maxHandLengthDu = 0.2, -- a scaled hand longer than this along the arm is odd
		minPartStuds = 0.05, -- a source part thinner than this on any axis is odd
		maxTransparency = 0.99, -- a source part at least this transparent is hidden on purpose: odd
		recheckSeconds = 1, -- a shown overlay compares the avatar's signature this often; a change rebuilds the arms
	},
	-- The held toy (§3.3): its longest side is toyLongestDu, centred on pos with Euler XYZ rot; the hands sit at its
	-- sides: x = its centre - (left) or + (right) its shown half-width + sideGap, y + sideY, z + sideZ (design:
	-- fp.js:393-395). Empty hands go to rest (X × side).
	held = {
		pos = Vector3.new(0, -0.13, -0.5), -- HOLD (design: fp.js:77)
		rot = Vector3.new(0, 0.25, 0), -- HOLD_R (design: fp.js:77)
		sideGap = 0.05, -- design: fp.js:393 (and the squeeze's, fp.js:413)
		sideY = -0.035, -- design: fp.js:395
		sideZ = 0.035, -- design: fp.js:395
	},
	-- The pop-in (§3.3): the toy springs up from equipFrom; its scale is K·max(minScale, backOut(min(1, t / seconds))),
	-- backOut(u) = 1 + (c + 1)(u - 1)³ + c(u - 1)² with c = backOutC (design: fp.js:14, 103, 403).
	equip = {
		seconds = 0.38, -- design: fp.js:403
		backOutC = 1.9, -- design: fp.js:14
		minScale = 0.0001, -- design: fp.js:103, 403
	},
	-- The two-palm squeeze (§3.4), c = the press amount 0..1: each palm at the toy's shown half-width + held.sideGap
	-- minus the inset (design: palmD·K·inset, fp.js:413; with our rig the shown X narrowing of that side), y, z from the
	-- toy centre; rolls ±(arm.roll + rollPress·c). After tremorAfterSeconds the hands shake ±tremor·c at tremorRateL /
	-- tremorRateR rad/s and the toy's x ±tremor·c·toyTremorShare at toyTremorRate (off under ReducedMotion); camera shake
	-- >= shake·c.
	squeeze = {
		inset = 0.94, -- design: fp.js:413
		y = -0.02, -- design: fp.js:414
		z = 0.03, -- design: fp.js:414
		rollPress = 0.3, -- design: fp.js:414
		tremorAfterSeconds = 0.3, -- design: fp.js:413
		tremor = 0.0008, -- design: fp.js:413
		tremorRateL = 53, -- design: fp.js:414
		tremorRateR = 49, -- design: fp.js:414
		toyTremorRate = 47, -- design: fp.js:415
		toyTremorShare = 0.6, -- design: fp.js:415
		shake = 0.025, -- design: fp.js:416
	},
	-- Focus (§3.4): while squeezing and lingerSeconds after, the focus share (springs.focus) goes to 1: the toy to pos,
	-- its rotation to rot (lerped from held by the share). The world camera's FOV offset (springs.fov, units of
	-- worldFovPerUnit degrees) aims at worldFovTarget × share: 70° -> 64.5° (design: fp.js:399-400, 652, 656).
	focus = {
		pos = Vector3.new(0, -0.105, -0.44), -- FOCUS (design: fp.js:78)
		rot = Vector3.new(0.1, 0, 0), -- FOCUS_R (design: fp.js:78)
		lingerSeconds = 1.1, -- design: fp.js:399
		worldFovTarget = -55, -- design: fp.js:652
		worldFovPerUnit = 0.1, -- cam.fov = 70 + fov.p · 0.1 (design: fp.js:656)
	},
	-- The design's camera shake value: it decays by decayPerSecond, and the world camera's pitch and yaw each get
	-- (random - 0.5) · shake² · radPerShakeSq rad a frame (design: fp.js:652-655). Ours goes through CameraController's
	-- shake (the Camera shake setting and ReducedMotion apply, spec §3.4).
	shake = {
		decayPerSecond = 1.4, -- design: fp.js:652
		radPerShakeSq = 0.03, -- design: fp.js:653
	},
	-- Throw extras (§3.5; the tracks are Anim/ThrowTracks'): the right hand rolls -(arm.roll + rollCocked) until the
	-- release, then -arm.roll; the left rollL. At the release: kick.release, fov.v += fovKick, shake >= shake. Shove:
	-- toy jitter ±shoveJitter and shake >= shoveShake while t < shoveUntil; sling: shake >= slingShake · t / slingUntil
	-- while slingFrom < t < slingUntil (design: fp.js:433-437). The Dragon roars as its throw starts: shake >=
	-- dragonRoarShake (design: fp.js:181, 305; the roar's sound and particles are not ported, §3.9).
	throwFx = {
		rollCocked = 0.5, -- design: fp.js:433
		rollL = 0.3, -- design: fp.js:433
		fovKick = 80, -- design: fp.js:437
		shake = 0.18, -- design: fp.js:437
		shoveJitter = 0.006, -- design: fp.js:434
		shoveShake = 0.12, -- design: fp.js:434
		shoveUntil = 0.4, -- design: fp.js:434
		slingShake = 0.06, -- design: fp.js:435
		slingFrom = 0.1, -- design: fp.js:435
		slingUntil = 0.45, -- design: fp.js:435
		dragonRoarShake = 0.25, -- design: fp.js:181, 305
	},
	-- Dragon Rush's charge (§3.6), ch = the charge share 0..1 (over the game's own telegraph, as step 2) and e =
	-- ease(ch): the toy goes toward pos by e, rotation X = pitch·e, scale (1 + wobble·sin(wobbleRate·t)·ch, 1 -
	-- squashY·ch, 1), jitter ±jitter·ch while ch < 1, the hands at its sides; a glow ball at the toy, radius glowRadius +
	-- glowPulse·sin(glowPulseRate·t), opacity glowOpacity·e, then × exp(-glowFadeRate·dt) a frame once over. The design
	-- also shakes >= shake·ch and pulls the world FOV spring's speed down by fovPullPerSecond·dt a frame (fp.js:459);
	-- spec §3.6 does not name those two. At the release the glow goes off at once (fp.js:461) and the camera reacts
	-- once: fov.v += releaseFovKick, the kick spring's speed += releaseKick, shake >= releaseShake (fp.js:331).
	ult = {
		pos = Vector3.new(0, -0.06, -0.47), -- design: fp.js:453
		pitch = -0.15, -- design: fp.js:453
		wobble = 0.08, -- design: fp.js:453
		wobbleRate = 40, -- design: fp.js:453
		squashY = 0.06, -- design: fp.js:453
		jitter = 0.004, -- design: fp.js:454
		glowRadius = 0.13, -- design: fp.js:457
		glowPulse = 0.02, -- design: fp.js:457
		glowPulseRate = 30, -- design: fp.js:457
		glowOpacity = 0.35, -- design: fp.js:457
		glowColour = Color3.fromHex("#FF9A4D"), -- Dragon's (design: fp.js:457)
		glowFadeRate = 8, -- design: fp.js:466
		shake = 0.12, -- design: fp.js:459
		fovPullPerSecond = 36, -- fov.v -= 6 · dt · 60 · 0.1 (design: fp.js:459)
		releaseFovKick = 90, -- design: fp.js:331
		releaseKick = -1.2, -- design: fp.js:331
		releaseShake = 0.3, -- design: fp.js:331
	},

	-- Feature 1 (2026-10-11): the charge throw, the catch and the crush on the overlay (Anim/ChargePoses, Anim/ChargeFx;
	-- design: the combat-effects page "Squishy Combat FP v2.html", html:<line>). That page has its own viewmodel: a
	-- vertical FOV of 56° (html:131), its hold POSE (html:410-415) with the toy 0.6 deep and 0.066 m round (html:208).
	-- Its moves are taken as offsets from its own hold and put on ours (held.pos, the hands at the toy's sides, rest),
	-- each offset × depthScale in depth and × depthScale × fovScale across (the same place on screen through our 70°
	-- camera); its rolls as changes from its hold's; its effect sizes in toy radii (÷ toyRadius), shown on ours.
	v2 = {
		depthScale = 0.5 / 0.6, -- held.pos.Z (fp.js:77) over the design's hold depth (design: html:411)
		fovScale = math.tan(math.rad(35)) / math.tan(math.rad(28)), -- our 70° (fp.js:28) over its 56° (design: html:131)
		toyRadius = 0.066, -- the held toy's size, m (design: html:208)
		hold = Vector3.new(0, -0.175, -0.6), -- POSE.sq (design: html:411)
		holdR = Vector3.new(0.06, -0.245, -0.575), -- POSE.R (design: html:412)
		holdL = Vector3.new(-0.108, -0.195, -0.57), -- POSE.L (design: html:412)
		emptyR = Vector3.new(0.16, -0.33, -0.55), -- POSE.emptyR (design: html:414)
		emptyL = Vector3.new(-0.17, -0.34, -0.55), -- POSE.emptyL (design: html:414)
		rollR = -0.2, -- POSE.eR.z (design: html:413)
		rollL = 0.5, -- POSE.eL.z (design: html:413)
		kickPerRecoil = 0.8 / 0.5, -- its recoil impulse on our kick spring: a throw's 0.5 (html:333) is our 0.8 (fp.js:437)
		hitStopTimeScale = 0.07, -- the overlay's time runs this slow during a hit-stop (design: html:422)
	},
	-- The charge (design: html:498-517; c = the charge 0-1, ec = ease(min(1, c × easeGain)), ease = html:115).
	charge = {
		easeGain = 1.4, -- design: html:499
		toy = Vector3.new(0.12, -0.165, -0.52), -- the toy's charged point (design: html:500)
		handR = Vector3.new(0.048, -0.066, 0.022), -- the right hand from the toy (design: html:501)
		leftAway = Vector3.new(-0.03, 0.02, 0.05), -- the left hand's away point from emptyL (design: html:502)
		leftSteady = Vector3.new(-0.087, 0.004, 0.01), -- the left hand steadying the toy, from it (design: html:502)
		leftAwayOver = 0.3, -- the left hand goes away over c 0 -> 0.3 (design: html:503)
		leftBackFrom = 0.55, -- and comes back to steady the toy over c 0.55 -> 0.85 (design: html:503-504)
		leftBackOver = 0.3,
		leftRollTo = 1.3, -- the left roll goes rollL -> this as it comes back (design: html:504)
		jitterFrom = 0.8, -- design: html:505
		jitter = 0.0045, -- design: html:505
		-- The toy's squash target s (design: html:507), shown as the scale (1 + squashX·s, 1 - squashY·s, 1 + squashX·s)
		-- (design: squishy-lib-v2.js:196) on our scale-key spring.
		squashSlope = 0.15,
		squashKnee = 0.6,
		squashBase = 0.09,
		squashRise = 0.5,
		squashPulse = 0.06, -- at full: + squashPulse·sin(squashPulseRate·t) (design: html:507)
		squashPulseRate = 26,
		squashX = 0.34, -- design: squishy-lib-v2.js:196
		squashY = 0.44,
		glowFrom = 0.2, -- design: html:508
		glowGain = 0.45, -- design: html:508 (min(glowMax, (c - glowFrom)·glowGain))
		glowMax = 0.24, -- design: html:508
		glowScale = 1.08, -- × the toy's radius (design: html:192, 509)
		glowPulse = 0.04, -- at full: + glowPulse·sin(glowPulseRate·t) (design: html:509)
		glowFlicker = 0.2, -- at full: opacity × (1 - glowFlicker + glowFlicker·sin(glowPulseRate·t)) (design: html:508)
		glowPulseRate = 18, -- rad/s, 2.9 Hz (design: html:508-509)
		outlineScale = 1.15, -- the white shell at full, × the toy's radius (design: html:193, 510)
		orbitFrom = 0.4, -- design: html:510
		orbitCount = 7, -- design: html:195
		orbitRadius = 1.55, -- × the toy's radius (design: html:195)
		orbitWave = 0.35, -- the pieces' height wave, × the toy's radius (design: html:195)
		orbitPiece = 0.11, -- a piece's size, × the toy's radius (design: html:195)
		orbitTilt = 0.4, -- design: html:510
		orbitSpin = 4, -- rad/s × c before full (design: html:510)
		orbitSpinFull = 14, -- rad/s at full (design: html:510)
		orbitScaleFrom = 0.6, -- the ring's scale 0.6 + 0.4c before full (design: html:511)
		sparkFrom = 0.2, -- design: html:513
		sparkRate = 30, -- + sparkRateGain·c a second (design: html:513)
		sparkRateGain = 70,
		sparkDistMin = 0.09, -- m from the toy (design: html:513)
		sparkDistMax = 0.15,
		sparkGather = 3.4, -- velocity = -offset × this (design: html:513)
		sparkSizeMin = 0.0025, -- m (design: html:513)
		sparkSizeMax = 0.005,
		sparkLife = 0.27, -- design: html:513
		sparkMaxLive = 24, -- build choice 2026-10-11 (NOT IN DESIGN): parts in the overlay, at most this many at once
		ringEvery = 0.32, -- at full, a ring this often (design: html:514)
		ringFrom = 0.07, -- m (design: html:514)
		ringTo = 0.1,
		ringSeconds = 0.4,
		fullRingFrom = 0.06, -- the white ring the moment it is full (design: html:514)
		fullRingTo = 0.12,
		fullRingSeconds = 0.25,
		shake = 0.12, -- at full (design: html:514)
		-- The release of a charged throw at the hand, c = its charge (design: html:335-339); an uncharged throw keeps the
		-- overlay's own release.
		release = {
			ringFrom = 0.01, -- m (design: html:335)
			ringTo = 0.09, -- + ringGain·c
			ringGain = 0.05,
			ringSeconds = 0.3,
			whiteFrom = 0.006, -- the white ring (design: html:335)
			whiteTo = 0.06,
			whiteSeconds = 0.22,
			burst = 8, -- + burstGain·c pieces (design: html:336)
			burstGain = 14,
			burstSpeed = 0.6, -- + burstSpeedGain·c m/s
			burstSpeedGain = 0.6,
			burstSize = 0.008, -- m
			burstLife = 0.5,
			sparks = 6, -- + sparksGain·c (design: html:337)
			sparksGain = 12,
			sparkSpeed = 2.4, -- × (sparkSpeedBase + c): the mean of the design's 1.6..3.2 (design: html:337)
			sparkSpeedBase = 0.6,
			sparkSize = 0.004, -- m (design: html:337, 0.002..0.004)
			sparkLife = 0.22, -- the mean of 0.16..0.28 (design: html:337)
			sparkDrag = 4, -- design: html:337
		},
	},
	-- The open hands (design: html:528-533) and the catch itself (design: html:346-354).
	catch = {
		openSeconds = 0.07, -- the hands open over this (design: html:529)
		handR = Vector3.new(0.115, -0.15, -0.62), -- design: html:530
		handL = Vector3.new(-0.115, -0.15, -0.62),
		rollR = 0.5, -- design: html:531 (eR.z)
		rollL = -0.5, -- design: html:531 (eL.z)
		toy = Vector3.new(0, -0.42, -0.45), -- the own toy tucked away below the screen (design: html:531)
		recoil = 1.4, -- design: html:351
		fovKick = -50, -- design: html:351
		shake = 0.25, -- design: html:351
		ringAt = Vector3.new(0, -0.1, -0.7), -- design: html:353
		ringFrom = 0.02, -- m (design: html:353)
		ringTo = 0.2,
		ringSeconds = 0.28,
		sparks = 14, -- design: html:353
		sparkSpeed = 1.2, -- m/s (design: html:353)
		sparkSize = 0.006, -- m (design: html:353)
		sparkLife = 0.4, -- design: html:353
		hitStopSeconds = 0.06, -- design: html:353
	},
	-- The crush (design: html:535-569): t = seconds since the catch, e = clamp((t - easeFrom) / easeOver, 0, 1).
	crush = {
		toyScale = 0.07 / 0.066, -- the caught toy against the held one (design: html:208, 348)
		from = Vector3.new(0, -0.02, -0.95), -- it arrives from here ... (design: html:349)
		fromVelocity = Vector3.new(0, 0, 2), -- ... at this speed
		spring = { 700, 44 }, -- design: html:188 (2.6 Hz)
		base = Vector3.new(0, -0.13, -0.56), -- design: html:539
		easeFrom = 0.12, -- design: html:538
		easeOver = 0.9,
		shakeBase = 0.0015, -- ± m on the toy and the hands (design: html:538)
		shakeGain = 0.009, -- × e²
		wobble = 0.07, -- × e (design: html:541)
		wobbleRate = 30, -- rad/s, + wobbleRateGain·e
		wobbleRateGain = 30,
		squeezeX = 0.52, -- its scale (1 - squeezeX·e² + w, 1 + growY·e² - wobbleY·w, 1 + growZ·e² - wobbleZ·w) (design: html:542)
		growY = 0.3,
		growZ = 0.22,
		wobbleY = 0.6,
		wobbleZ = 0.4,
		wowUntil = 0.18, -- the "wow" face, then the squish face (design: html:543)
		glow = 0.32, -- × e² (design: html:544)
		glowFlickerFrom = 0.6, -- design: html:544
		glowFlicker = 0.15, -- design: html:544
		-- The flicker's rate: the design's 40 rad/s (6.4 Hz, html:544) held to the 3 Hz flicker limit (DESIGN §9.12), as
		-- phase 5 held the drop shadow's pulse.
		glowFlickerHz = 3,
		glowPulse = 0.05, -- the glow's size pulse × e (design: html:544, sin(35t): 5.6 Hz, held to glowFlickerHz too)
		orbitFrom = 0.3, -- design: html:545
		orbitSpin = 6, -- rad/s, + orbitSpinGain·e (design: html:545)
		orbitSpinGain = 20,
		speckRate = 80, -- a second × e (design: html:550)
		speckSizeMin = 0.004, -- m (design: html:550)
		speckSizeMax = 0.009,
		speckLife = 0.5, -- design: html:550
		speckSpeed = Vector3.new(0.25, 0.3, 0.1), -- m/s: ±X, 0..Y up, ±Z (design: html:550)
		speckMaxLive = 24, -- build choice 2026-10-11 (NOT IN DESIGN): parts in the overlay
		shake = 0.2, -- + shakeGainE·e² (design: html:551)
		shakeGainE = 0.35,
		squeakAt = 0.12, -- design: html:553
		toy = Vector3.new(0, -0.45, -0.45), -- the own toy tucked away (design: html:549)
		-- The burst (design: html:554-563), held to Config.Vfx.Budgets.liveParticlesPerEffect parts (its 80 + 30 + 7 + 18
		-- pieces at 4/9; ReducedMotion halves them again).
		burstPieces = 35, -- design: html:557 (80)
		burstSparks = 13, -- design: html:557 (30)
		burstPuffs = 3, -- design: html:557 (7)
		burstWhite = 8, -- design: html:558 (18)
		burstSpeed = 1.5, -- m/s (design: html:557)
		burstSize = 0.012, -- m (design: html:557)
		burstLife = 1.1, -- design: html:557
		burstDrag = 2.4, -- design: html:557
		-- The burst's sparks and puffs against its pieces (design: squishy-lib-v2.js:323, 327; the means of its ranges).
		sparkSpeedShare = 1.35, -- speed × 0.9..1.8
		sparkSizeShare = 0.35,
		sparkLife = 0.52, -- 0.25..0.5 × life / 0.8
		puffSpeedShare = 0.35, -- speed × 0.35 (+ 0.4 m/s, left out)
		puffSizeShare = 4.5, -- size × 3..6
		puffLife = 0.62, -- 0.45..0.8
		whiteSpeed = 0.8, -- design: html:558
		whiteSize = 0.006,
		whiteLife = 0.5,
		whiteDrag = 3,
		rings = { -- from, to (m), seconds; the toy's colour, white, then its colour again (design: html:559)
			{ 0.03, 0.3, 0.5 },
			{ 0.02, 0.2, 0.32 },
			{ 0.05, 0.45, 0.7 },
		},
		burstFovKick = 160, -- design: html:560
		burstRecoil = -2, -- design: html:560
		burstShake = 0.55, -- design: html:560
		burstHands = Vector3.new(3, 0.5, 1), -- the hands thrown apart, a speed in m/s (X × side) (design: html:561)
	},
}

return FirstPerson
