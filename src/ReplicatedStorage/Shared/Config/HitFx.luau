--!strict
-- Config.HitFx (2026-10-28, the physics upgrade's part 2: getting hit; owner: "Yes, build part 2"). Shared, data only.
-- A 1:1 port of the co-owner's Claude Design page docs/squishy-fx-spec/hit.html (CONFIG.knockback, CONFIG.fx,
-- CONFIG.shared, CONFIG.moments; readable copy notes.md "Part 2 · Hit"), with the owner's 4 answers (Decisions
-- 2026-10-28): the design's knockback; a match K.O. keeps Diego's kill effect AND gets the candy poof; the K.O. camera
-- keeps watching the attacker (the design's koCam / fallCam are not played); the round's last K.O. gets the slow motion.
-- Played by Client/Anim/FeelFx (same formats as Config.MoveFx: poses, rings, texts, shakes, fovs); the particle and
-- trail templates are ServerStorage.SDTools.Builders.FeelVfxBuilder's (SD_MoveVfx.Feel); Client/Controllers/
-- HitFxController picks the moment, moves the own body (the knockback) and hides / shows a K.O.'d player.
-- Not ported here: the lead-in (throwFollow, inTrail: the throw is part 3), the squishy's impact squash and hide (the
-- projectile is ProjectileRenderer's), "SQUISHED!" (the HUD's own SQUISHED text stays), the koCam / fallCam calls.
-- views: "V1P" = the local player is the victim, "A1P" = the attacker, "OBS" = neither (FeelFx role views).

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local HitFx = {
	-- The switch: false = the old hit, knockback and elimination looks (VfxController).
	enabled = true,

	-- CONFIG.knockback (hit.html:45-51): studs/s away from the thrower and up, held `hold` s by a LinearVelocity; then
	-- the horizontal speed fades x e^(-airDrag t) in the air and skids to a stop at groundDecel after the landing.
	knockback = {
		normal = { horizontal = 34, vertical = 34, hold = 0.12 },
		charged = { horizontal = 44, vertical = 40, hold = 0.14 },
		ultimateMultiplier = 1.5, -- ultimate = normal x 1.5 (51 / 51)
		airDrag = 1.2,
		groundDecel = 160,
	},
	-- A throw counts as charged from this charge share (ThrowStarted's power 0..1; the design's "hold 1 s").
	chargedFrom = 0.9,
	-- Hit-stop per moment (CONFIG.fx hitStopS / M / L): the impact frame's freeze, max 0.12 s.
	hitStop = { hitNormal = 0.06, hitCharged = 0.09, hitUltimate = 0.12, squished = 0.12, finalKO = 0.12 },
	-- The land signal: a knocked body counts as landed once it falls and its feet are within landSlack of the floor,
	-- and never later than landMax after the launch.
	landSlack = 0.6,
	landMinSeconds = 0.12,
	landMax = 1.5,
	-- The squished K.O.'s poof hides the body this long after the impact (the design's `poof` signal at 0.30 s).
	poofAt = 0.3,
	posePriority = 1.8, -- over the movement feel's poses (a hit wins), under the throw (2)
	heldArmJoints = { "RightShoulder", "RightElbow", "RightWrist" },
	stage = { feetLift = 0.06, groundLift = 0.04, chestHeight = 3.6, backUpAngle = 35 },

	poses = {
		hitRecoil = {
			hold = true,
			keys = {
				{
					t = 0,
					easing = "Cubic Out",
					joints = {
						Neck = v(25, 0, 0),
						Waist = v(22, 0, 0),
						LeftShoulder = v(70, 0, -70),
						RightShoulder = v(70, 0, 70),
						LeftElbow = v(45, 0, 0),
						RightElbow = v(45, 0, 0),
						LeftHip = v(35, 0, 0),
						RightHip = v(50, 0, 0),
						LeftKnee = v(-45, 0, 0),
						RightKnee = v(-65, 0, 0),
					},
				},
				{
					t = 0.2,
					easing = "Cubic InOut",
					joints = {
						Root = v(30, 0, 0),
						Neck = v(15, 0, 0),
						Waist = v(15, 0, 0),
						LeftShoulder = v(120, 0, -50),
						RightShoulder = v(120, 0, 50),
						LeftElbow = v(30, 0, 0),
						RightElbow = v(30, 0, 0),
						LeftHip = v(40, 0, 0),
						RightHip = v(55, 0, 0),
						LeftKnee = v(-50, 0, 0),
						RightKnee = v(-70, 0, 0),
					},
				},
				{
					t = 0.36,
					joints = {
						Root = v(12, 0, 0),
						Neck = v(8, 0, 0),
						Waist = v(8, 0, 0),
						LeftShoulder = v(140, 0, -40),
						RightShoulder = v(140, 0, 40),
						LeftElbow = v(20, 0, 0),
						RightElbow = v(20, 0, 0),
						LeftHip = v(30, 0, 0),
						RightHip = v(40, 0, 0),
						LeftKnee = v(-40, 0, 0),
						RightKnee = v(-55, 0, 0),
					},
				},
			},
		},
		-- The backward tumble on the Root (keys < 120 deg apart).
		tumble360 = {
			fadeIn = 0.03,
			hold = true,
			keys = {
				{ t = 0, joints = { Root = v(20, 0, 0), Neck = v(-10, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.08, joints = { Root = v(110, 0, 0), Neck = v(-10, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.16, joints = { Root = v(200, 0, 0), Neck = v(-10, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.25, easing = "Cubic Out", joints = { Root = v(290, 0, 0), Neck = v(-10, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.34, joints = { Root = v(360, 0, 0), LeftShoulder = v(140, 0, -40), RightShoulder = v(140, 0, 40), LeftElbow = v(20, 0, 0), RightElbow = v(20, 0, 0), LeftHip = v(30, 0, 0), RightHip = v(40, 0, 0), LeftKnee = v(-40, 0, 0), RightKnee = v(-55, 0, 0) } },
			},
		},
		tumble720 = {
			fadeIn = 0.03,
			hold = true,
			keys = {
				{ t = 0, joints = { Root = v(20, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.06, joints = { Root = v(120, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.12, joints = { Root = v(230, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.18, joints = { Root = v(340, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.24, joints = { Root = v(450, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.3, joints = { Root = v(560, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.37, easing = "Cubic Out", joints = { Root = v(660, 0, 0), LeftShoulder = v(50, 0, -30), RightShoulder = v(50, 0, 30), LeftElbow = v(60, 0, 0), RightElbow = v(60, 0, 0), LeftHip = v(70, 0, 0), RightHip = v(70, 0, 0), LeftKnee = v(-100, 0, 0), RightKnee = v(-100, 0, 0) } },
				{ t = 0.44, joints = { Root = v(720, 0, 0), LeftShoulder = v(140, 0, -40), RightShoulder = v(140, 0, 40), LeftElbow = v(20, 0, 0), RightElbow = v(20, 0, 0), LeftHip = v(30, 0, 0), RightHip = v(40, 0, 0), LeftKnee = v(-40, 0, 0), RightKnee = v(-55, 0, 0) } },
			},
		},
		recoverLand = {
			fadeIn = 0.03,
			fadeOut = 0.18,
			keys = {
				{ t = 0, rootPos = v(0, -0.6, 0.2), joints = { Waist = v(-16, 0, 0), Neck = v(10, 0, 0), LeftShoulder = v(20, 0, -35), RightShoulder = v(20, 0, 35), LeftHip = v(50, 0, 0), RightHip = v(50, 0, 0), LeftKnee = v(-85, 0, 0), RightKnee = v(-85, 0, 0), LeftAnkle = v(35, 0, 0), RightAnkle = v(35, 0, 0) } },
				{ t = 0.1, easing = "Cubic InOut", rootPos = v(0, -0.6, 0.2), joints = { Waist = v(-16, 0, 0), Neck = v(10, 0, 0), LeftShoulder = v(20, 0, -35), RightShoulder = v(20, 0, 35), LeftHip = v(50, 0, 0), RightHip = v(50, 0, 0), LeftKnee = v(-85, 0, 0), RightKnee = v(-85, 0, 0), LeftAnkle = v(35, 0, 0), RightAnkle = v(35, 0, 0) } },
				{ t = 0.28, joints = {} },
			},
		},
		respawnPop = {
			fadeOut = 0.15,
			keys = {
				{ t = 0, easing = "Cubic Out", joints = { Neck = v(10, 0, 0), LeftShoulder = v(150, 0, -30), RightShoulder = v(150, 0, 30) } },
				{ t = 0.25, joints = {} },
			},
		},
	},

	-- Picture and text pops (BillboardGuis): size keys in studs (height), transparency keys; `texture` = a kit picture
	-- (img.kit.<name>) drawn square, else `text`; rotation = a random tilt in that range (degrees).
	texts = {
		powS = { texture = "pow", color = Color3.fromHex("#FFD86B"), size = { { 0, 0.6 }, { 0.05, 4.8 }, { 0.1, 4.2 }, { 0.22, 4.4 }, { 0.3, 0 } }, transparency = { { 0, 0 }, { 0.22, 0 }, { 0.3, 1 } }, rotation = { -15, 15 }, time = 0.3, offset = v(0, 0, 0) },
		powM = { texture = "pow", color = Color3.fromHex("#FFD86B"), size = { { 0, 0.8 }, { 0.05, 5.8 }, { 0.11, 5 }, { 0.24, 5.3 }, { 0.32, 0 } }, transparency = { { 0, 0 }, { 0.24, 0 }, { 0.32, 1 } }, rotation = { -15, 15 }, time = 0.32, offset = v(0, 0, 0) },
		powL = { texture = "pow", color = Color3.fromHex("#FFD25E"), size = { { 0, 1 }, { 0.06, 7.2 }, { 0.12, 6.2 }, { 0.26, 6.6 }, { 0.34, 0 } }, transparency = { { 0, 0 }, { 0.26, 0 }, { 0.34, 1 } }, rotation = { -15, 15 }, time = 0.34, offset = v(0, 0, 0) },
		coreFlash = { texture = "sparkle", color = Color3.fromHex("#FFFFFF"), size = { { 0, 2 }, { 0.04, 6 }, { 0.12, 0 } }, transparency = { { 0, 0 }, { 1, 0 } }, rotation = { 0, 45 }, time = 0.12, offset = v(0, 0, 0) },
		squishText = { text = "SQUISH!", color = Color3.fromHex("#FF8FB1"), stroke = Color3.fromHex("#3B2A35"), offset = v(0, 3.2, 0), size = { { 0, 0 }, { 0.05, 2.6 }, { 0.1, 2.2 }, { 0.24, 2.3 }, { 0.3, 0 } }, transparency = { { 0, 0 }, { 0.24, 0 }, { 0.3, 1 } }, time = 0.3 },
		splatText = { text = "SPLAT!", color = Color3.fromHex("#FFD86B"), stroke = Color3.fromHex("#3B2A35"), offset = v(0, 3.8, 0), size = { { 0, 0 }, { 0.05, 3.3 }, { 0.1, 2.8 }, { 0.24, 2.9 }, { 0.3, 0 } }, transparency = { { 0, 0 }, { 0.24, 0 }, { 0.3, 1 } }, time = 0.3 },
	},
	textCanvas = { aspect = 4, fontShare = 150 / 256, strokeShare = 22 / 150 },

	rings = {
		hitRing = { color = Color3.fromHex("#FFFFFF"), sizeStart = 1, sizeEnd = 6.5, time = 0.22, easing = "Quad Out", transparencyStart = 0.1, transparencyEnd = 1, transparencyEasing = "Quad In" },
		hitRingBig = { color = Color3.fromHex("#FFD86B"), sizeStart = 1.5, sizeEnd = 10, time = 0.3, easing = "Quad Out", transparencyStart = 0.05, transparencyEnd = 1, transparencyEasing = "Quad In" },
		poofRing = { color = Color3.fromHex("#FF8FB1"), sizeStart = 2, sizeEnd = 12, time = 0.35, easing = "Quad Out", transparencyStart = 0.05, transparencyEnd = 1, transparencyEasing = "Quad In" },
		respawnRing = { color = Color3.fromHex("#5FD3AE"), sizeStart = 1, sizeEnd = 7, time = 0.3, easing = "Quad Out", transparencyStart = 0.1, transparencyEnd = 1, transparencyEasing = "Quad In" },
	},
	-- Highlights on the victim (fill and outline transparency rise to 1 over `time`).
	glows = {
		victimGlow = { fill = Color3.fromHex("#FFFFFF"), outline = Color3.fromHex("#FFFFFF"), fillFrom = 0.35, outlineFrom = 0, time = 0.2, easing = "Quad Out" },
		respawnGlow = { fill = Color3.fromHex("#FFFFFF"), outline = Color3.fromHex("#FFFFFF"), fillFrom = 0.4, outlineFrom = 0, time = 0.3, easing = "Quad Out" },
	},
	lights = {
		hitLight = { color = Color3.fromHex("#FFD86B"), brightness = 2.5, range = 12, time = 0.15, easing = "Quad Out" },
	},
	-- Full-screen flashes (the victim's own screen; <= 0.1 s, <= 30 %).
	flashes = {
		flashS = { color = Color3.fromHex("#FFFFFF"), opacity = 0.2, fadeIn = 0.02, fadeOut = 0.06 },
		flashM = { color = Color3.fromHex("#FFFFFF"), opacity = 0.25, fadeIn = 0.02, fadeOut = 0.07 },
		flashL = { color = Color3.fromHex("#FFF4E6"), opacity = 0.3, fadeIn = 0.02, fadeOut = 0.08 },
	},
	-- Screen pieces: jelly splats on the bottom edge (px at 1080p) and the movie bars of the final K.O.
	screens = {
		edgeSplat = { kind = "edgeSplat", texture = "jelly", color = Color3.fromHex("#FF8FB1"), count = 4, sizePx = { 150, 230 }, inset = 0.03, spread = 0.7, rotation = { 150, 210 }, popTime = 0.08, popEasing = "Back Out", hold = 0.3, fadeTime = 0.45, drip = 0.06, stagger = 0.02, opacity = 0.9 },
		koBars = { kind = "letterbox", color = Color3.fromHex("#3B2A35"), height = 0.1, fadeIn = 0.15, inEasing = "Quad Out", hold = 0.9, fadeOut = 0.3, outEasing = "Quad InOut" },
	},
	shakes = {
		victimShakeS = { amplitude = 1.2, time = 0.25, frequency = 18, easing = "Quad Out", axes = v(1, 0.7, 0.4) },
		victimShakeM = { amplitude = 1.6, time = 0.3, frequency = 18, easing = "Quad Out", axes = v(1, 0.7, 0.4) },
		victimShakeL = { amplitude = 2, time = 0.35, frequency = 16, easing = "Quad Out", axes = v(1, 0.7, 0.4) },
		attackerShake = { amplitude = 0.5, time = 0.12, frequency = 22, easing = "Quad Out", axes = v(1, 0.5, 0.2) },
		finalShake = { amplitude = 1.5, time = 0.4, frequency = 14, easing = "Quad Out", axes = v(1, 0.7, 0.4) },
	},
	fovs = {
		victimFovS = { delta = 4, attack = 0.04, attackEasing = "Quad Out", hold = 0.04, release = 0.25, releaseEasing = "Sine InOut" },
		victimFovM = { delta = 6, attack = 0.04, attackEasing = "Quad Out", hold = 0.06, release = 0.3, releaseEasing = "Sine InOut" },
		victimFovL = { delta = 8, attack = 0.05, attackEasing = "Quad Out", hold = 0.08, release = 0.35, releaseEasing = "Sine InOut" },
		attackerFov = { delta = -2, attack = 0.04, attackEasing = "Quad Out", hold = 0.02, release = 0.2, releaseEasing = "Sine InOut" },
		finalFov = { delta = -6, attack = 0.12, attackEasing = "Quad Out", hold = 0.45, release = 0.3, releaseEasing = "Sine InOut" },
	},
	-- Camera punches: camera-space offset (studs) and rotation (deg) on the attack / hold / release envelope.
	punches = {
		victimPunch = { offset = v(0, 0, 0.6), rotation = v(4, 0, 0), attack = 0.04, attackEasing = "Quad Out", hold = 0.02, release = 0.25, releaseEasing = "Back Out" },
	},
	-- Local slow motion (round decided only): effects and poses at `speed` (in / hold / out envelope).
	slowmos = {
		finalSlow = { speed = 0.3, fadeIn = 0.06, inEasing = "Quad Out", hold = 0.5, fadeOut = 0.3, outEasing = "Sine InOut" },
	},
	dips = {},
	lines = {},
	afterimages = {},
	-- The design's sound names -> ours (false = none of ours yet). The impact's own boing is VfxController's.
	sounds = {
		squish_hit_splat = false,
		squish_hit_big = false,
		squish_hit_ultimate = false,
		knockback_whoosh = { key = "sfx.dashWhoosh", volume = 0.7, pitch = 1.1 },
		knockback_whoosh_big = { key = "sfx.dashWhoosh", volume = 0.9, pitch = 0.9 },
		land_squish = { key = "sfx.squish", volume = 0.45 },
		poof_squish_pop = { key = "sfx.pop", volume = 0.9 },
		squished_jingle = false,
		respawn_pop = { key = "sfx.pop", volume = 0.6, pitch = 1.2 },
		fall_whistle_long = false,
		fall_out_poof = { key = "sfx.pop", volume = 0.9, pitch = 0.8 },
		final_hit_boom = { key = "sfx.impactBoing", volume = 1, pitch = 0.7 },
		slowmo_whoomp = { key = "sfx.dashWhoosh", volume = 1, pitch = 0.6 },
		slowmo_release = false,
	} :: { [string]: any },

	-- CONFIG.moments (hit.html), the shared blocks inlined. t = 0 is the impact; the hit-stop is VfxController's.
	moments = {
		hitNormal = {
			{ t = 0, pop = "powS", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0, pop = "coreFlash", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0, glow = "victimGlow" },
			{ t = 0, pose = "hitRecoil" },
			{ t = 0, flash = "flashS", views = { "V1P" } },
			{ t = 0, screen = "edgeSplat", views = { "V1P" } },
			{ t = 0, shake = "victimShakeS", views = { "V1P" } },
			{ t = 0, fov = "victimFovS", views = { "V1P" } },
			{ t = 0, punch = "victimPunch", views = { "V1P" } },
			{ t = 0, shake = "attackerShake", views = { "A1P" } },
			{ t = 0, fov = "attackerFov", views = { "A1P" } },
			{ t = 0, sound = "squish_hit_splat" },
			{ t = 0, pop = "squishText", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0.06, call = "knockback", kind = "normal" },
			{ t = 0.06, burst = "jellySplat", at = "hit", aim = "back" },
			{ t = 0.06, burst = "hitStars", at = "hit" },
			{ t = 0.06, burst = "hitSprinkles", at = "hit", aim = "back" },
			{ t = 0.06, ring = "hitRing", at = "hit", face = "back" },
			{ t = 0.06, sound = "knockback_whoosh" },
			{ t = 0.06, trail = "knockTrail", at = "chest", ["for"] = 0.4 },
			{ on = "land", t = 0, burst = "skidPuff", at = "feet", aim = "up" },
			{ on = "land", t = 0, pose = "recoverLand" },
			{ on = "land", t = 0, sound = "land_squish" },
		},
		hitCharged = {
			{ t = 0, pop = "powM", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0, pop = "coreFlash", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0, light = "hitLight", at = "hit" },
			{ t = 0, glow = "victimGlow" },
			{ t = 0, pose = "hitRecoil" },
			{ t = 0, flash = "flashM", views = { "V1P" } },
			{ t = 0, screen = "edgeSplat", views = { "V1P" } },
			{ t = 0, shake = "victimShakeM", views = { "V1P" } },
			{ t = 0, fov = "victimFovM", views = { "V1P" } },
			{ t = 0, punch = "victimPunch", views = { "V1P" } },
			{ t = 0, shake = "attackerShake", views = { "A1P" } },
			{ t = 0, fov = "attackerFov", views = { "A1P" } },
			{ t = 0, sound = "squish_hit_big" },
			{ t = 0.09, call = "knockback", kind = "charged" },
			{ t = 0.09, pose = "tumble360" },
			{ t = 0.09, burst = "jellySplatBig", at = "hit", aim = "back" },
			{ t = 0.09, burst = "hitStarsBig", at = "hit" },
			{ t = 0.09, burst = "hitSprinkles", at = "hit", aim = "back" },
			{ t = 0.09, ring = "hitRing", at = "hit", face = "back" },
			{ t = 0.09, sound = "knockback_whoosh_big" },
			{ t = 0, pop = "splatText", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0.09, trail = "knockTrail", at = "chest", ["for"] = 0.45 },
			{ t = 0.09, emit = "dizzyStars", at = "chest", ["for"] = 0.4, views = { "A1P", "OBS" } },
			{ on = "land", t = 0, burst = "skidPuff", at = "feet", aim = "up" },
			{ on = "land", t = 0, pose = "recoverLand" },
			{ on = "land", t = 0, sound = "land_squish" },
		},
		hitUltimate = {
			{ t = 0, pop = "powL", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0, pop = "coreFlash", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0, light = "hitLight", at = "hit" },
			{ t = 0, glow = "victimGlow" },
			{ t = 0, pose = "hitRecoil" },
			{ t = 0, flash = "flashL", views = { "V1P" } },
			{ t = 0, screen = "edgeSplat", views = { "V1P" } },
			{ t = 0, shake = "victimShakeL", views = { "V1P" } },
			{ t = 0, fov = "victimFovL", views = { "V1P" } },
			{ t = 0, punch = "victimPunch", views = { "V1P" } },
			{ t = 0, shake = "attackerShake", views = { "A1P" } },
			{ t = 0, fov = "attackerFov", views = { "A1P" } },
			{ t = 0, sound = "squish_hit_ultimate" },
			{ t = 0.12, call = "knockback", kind = "ultimate" },
			{ t = 0.12, pose = "tumble720" },
			{ t = 0.12, burst = "jellySplatBig", at = "hit", aim = "back" },
			{ t = 0.12, burst = "hitStarsBig", at = "hit" },
			{ t = 0.12, burst = "hitSprinklesBig", at = "hit", aim = "back" },
			{ t = 0.12, ring = "hitRingBig", at = "hit", face = "back" },
			{ t = 0.16, ring = "hitRing", at = "hit", face = "back" },
			{ t = 0.12, sound = "knockback_whoosh_big" },
			{ t = 0, pop = "splatText", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0.12, trail = "knockTrail", at = "chest", ["for"] = 0.5 },
			{ t = 0.12, emit = "dizzyStars", at = "chest", ["for"] = 0.45, views = { "A1P", "OBS" } },
			{ on = "land", t = 0, burst = "skidPuff", at = "feet", aim = "up" },
			{ on = "land", t = 0, pose = "recoverLand" },
			{ on = "land", t = 0, sound = "land_squish" },
		},
		-- A match K.O. (one hit): Diego's kill effect plays beside it (VfxController); the poof hides the body.
		squished = {
			{ t = 0, pop = "powL", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0, pop = "coreFlash", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0, glow = "victimGlow" },
			{ t = 0, pose = "hitRecoil" },
			{ t = 0, flash = "flashL", views = { "V1P" } },
			{ t = 0, screen = "edgeSplat", views = { "V1P" } },
			{ t = 0, shake = "victimShakeL", views = { "V1P" } },
			{ t = 0, fov = "victimFovL", views = { "V1P" } },
			{ t = 0, punch = "victimPunch", views = { "V1P" } },
			{ t = 0, shake = "attackerShake", views = { "A1P" } },
			{ t = 0, fov = "attackerFov", views = { "A1P" } },
			{ t = 0, sound = "squish_hit_big" },
			{ t = 0.12, call = "knockback", kind = "normal" },
			{ t = 0.12, pose = "tumble360" },
			{ t = 0.12, burst = "jellySplat", at = "hit", aim = "back" },
			{ t = 0.12, burst = "hitStars", at = "hit" },
			{ t = 0.12, ring = "hitRing", at = "hit", face = "back" },
			{ t = 0.12, sound = "squished_jingle" },
			{ t = 0, pop = "splatText", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0.12, trail = "knockTrail", at = "chest", ["for"] = 0.18 },
			{ t = 0.3, call = "hide" },
			{ t = 0.3, burst = "poofCloud", at = "chest", views = { "A1P", "OBS" } },
			{ t = 0.3, burst = "poofConfetti", at = "chest" },
			{ t = 0.3, burst = "poofSparkles", at = "chest" },
			{ t = 0.3, ring = "poofRing", at = "chest", face = "back" },
			{ t = 0.3, sound = "poof_squish_pop" },
		},
		-- A match player stands again (MatchChanged: knocked out -> alive).
		respawn = {
			{ t = 0, call = "show" },
			{ t = 0, burst = "respawnPuff", at = "feet", aim = "up" },
			{ t = 0, burst = "respawnSparkles", at = "feet", aim = "up" },
			{ t = 0, ring = "respawnRing", at = "feet" },
			{ t = 0, glow = "respawnGlow" },
			{ t = 0, pose = "respawnPop" },
			{ t = 0, sound = "respawn_pop" },
		},
		-- A match K.O. by falling off the map (the server's out-of-bounds K.O.; the wind is part 1's fast-fall wind).
		fallOff = {
			{ t = 0, call = "hide" },
			{ t = 0, burst = "fallPoof", at = "chest" },
			{ t = 0, burst = "poofSparkles", at = "chest" },
			{ t = 0, sound = "fall_out_poof" },
		},
		-- The K.O. that decides the round (a duel's last life, a match's winning K.O.): slow motion is allowed.
		finalKO = {
			{ t = 0, pop = "powL", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0, pop = "coreFlash", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0, light = "hitLight", at = "hit" },
			{ t = 0, glow = "victimGlow" },
			{ t = 0, pose = "hitRecoil" },
			{ t = 0, flash = "flashL", views = { "V1P" } },
			{ t = 0, screen = "edgeSplat", views = { "V1P" } },
			{ t = 0, shake = "finalShake" },
			{ t = 0, sound = "final_hit_boom" },
			{ t = 0.12, slowmo = "finalSlow" },
			{ t = 0.12, fov = "finalFov" },
			{ t = 0.12, call = "knockback", kind = "ultimate" },
			{ t = 0.12, pose = "tumble720" },
			{ t = 0.12, burst = "jellySplatBig", at = "hit", aim = "back", views = { "A1P", "OBS" } },
			{ t = 0.12, burst = "finalConfetti", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0.12, burst = "hitStarsBig", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0.12, ring = "hitRingBig", at = "hit", face = "back", views = { "A1P", "OBS" } },
			{ t = 0.2, ring = "hitRing", at = "hit", face = "back", views = { "A1P", "OBS" } },
			{ t = 0.12, sound = "slowmo_whoomp" },
			{ t = 0, pop = "splatText", at = "hit", views = { "A1P", "OBS" } },
			{ t = 0.12, screen = "koBars" },
			{ t = 0.12, trail = "knockTrail", at = "chest", ["for"] = 0.6 },
			{ t = 0.95, sound = "slowmo_release" },
			{ on = "land", t = 0, burst = "skidPuff", at = "feet", aim = "up" },
			{ on = "land", t = 0, sound = "land_squish" },
			-- NOT IN DESIGN (its killcam takes over): the get-up, so the held tumble never stays on the body after it.
			{ on = "land", t = 0, pose = "recoverLand" },
		},
	} :: { [string]: { any } },

	phone = { countShare = 0.5, trailLifetimeScale = 0.7 },
	-- CONFIG.reduceMotion's part FeelFx applies (shake, FOV, punch and dips are off with the movement feel; no slow motion).
	reduceMotion = { flash = 0.5 },
}

return HitFx
