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
}

return FirstPerson
