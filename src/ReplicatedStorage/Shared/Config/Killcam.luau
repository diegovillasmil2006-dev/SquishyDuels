--!strict
-- Config.UI.Match.finish.killcam (killcam step 1, 2026-10-26; owner: "Yes, build step 1 of the killcam like that.";
-- `K:n` = Diego's uploads/match-stage.html line n, `S:n` = his "Squishy Duels LOADING SCREEN Y MATCH HUD.dc.html"):
-- the replay of the final squish through the killer's eyes (UI/Match/Killcam). Studs and seconds; Diego's world units
-- are 0.28 a stud (his s()), so his raw world numbers are divided by 0.28 here. Shared, data only. A child module of
-- Config/UI (UI.luau is at Roblox's 200,000-character Source limit).

return {
	at = 0.95, -- S:739: the cut to the killcam, after the final squish's view
	cap = 9, -- S:740: a killcam still playing then is cut (Config.Match.killcamSeconds holds the screen for it)
	toTitle = 0.12, -- S:785: the end screen's timeline starts this long after the killcam ends
	skipAfter = 0.6, -- S:744: TAP TO SKIP ends the killcam from this long into it
	skipPill = { delay = 0.6, ms = 250 }, -- S:753: the skip pill fades in
	tape = { hz = 30, keep = 5 }, -- [P] the recording: 30 samples a second, the last 5 s (Diego: every 60 Hz tick, K:398)
	before = 190 / 60, -- K:456: from 190 frames before the final squish
	after = 54 / 60, -- K:456: to 54 frames after it
	minBefore = 12 / 60, -- K:454: less tape before the squish: no killcam
	throwBefore = 30 / 60, -- K:458: the throw's time when the tape has none of the killer's throws
	-- K:445-449 rsp(d): full speed, easing to slow from a to b, slow until c, back to full speed by d (d = seconds from
	-- the squish)
	speed = { slow = 0.22, a = -0.55, b = -0.12, c = 0.45, d = 0.9 },
	freeze = 0.16, -- K:505: the hit-stop on the squish
	camera = {
		forward = 0.5, -- K:481: the eye this far in front of the killer's head
		far = 20, -- K:484: first it looks this far ahead, at the victim's height
		victimUp = 3, -- K:482: then at the victim's root + this
		lookFrom = 0.35, -- K:483: w = lookFrom + (1 - lookFrom) * smoothstep(the run-up to the throw)
		pull = 0.22, -- K:485: between the throw and the squish the look leans this much toward the toy
		follow = 8, -- K:486: the look's rate (1 - e^(-dt * follow))
		fov = { far = 72, near = 54, after = 66, nearFrom = -0.6, afterFrom = 0.55, follow = 6 }, -- K:489-490
		punch = 10, -- K:489: the squish adds this to the FOV, fading at punchFade a second (K:516)
		punchFade = 2.2,
		kick = 0.14 / 0.28, -- K:521 fx.kick(0.14): the camera jolts this far, fading at kickFade (fx.js:160)
		kickFade = 14,
	},
	-- The killer's arm (K:434-448, 491-498): its point in the camera's space, turned yaw; the fist, the far end of the
	-- sleeve and the toy in the arm's space. Our arm is the killer's own avatar arm (Anim/OwnArm, owner 2026-10-11:
	-- every first-person arm is the player's own), its lower arm as wide as Diego's sleeve (sleeve; studsPerDu without one).
	arm = {
		at = Vector3.new(1.15, -1.2, -2.3),
		yaw = 0.22,
		hand = Vector3.new(0, 0, -0.6),
		shoulder = Vector3.new(0, 0, 2.7),
		toy = Vector3.new(0, 0.7, -0.9),
		toyScale = 0.55,
		sleeve = 0.95, -- K:438: the sleeve's width (studs)
		studsPerDu = 9, -- [P] the fallback: the avatar hand (handWidthDu 0.1) as wide as Diego's 0.9-stud fist
		walkSpeed = 1, -- K:492: faster than this (studs a second) bobs as a walk
		bob = { walk = 11, still = 3, x = 0.08, y = 0.1, stillAmp = 0.25 },
		throw = { rate = 2.4, push = 1.4, lift = 0.5, turn = 0.25 }, -- K:494-497
	},
	-- K:200-207 hitFx(..., 1.7) on the final squish: sparks, a white ring facing the camera, a ring on the floor in the
	-- victim's colour, a warm light; then our own kill effect (Anim/KillVfx, the killer's kill set) at the victim.
	hit = {
		sparks = { n = 20, speed = 3.6 * 1.7 / 0.28, size = 0.42, life = 0.55, gravity = 2 / 0.28 },
		ring = { to = 3.8 * 1.7 * 2, s = 0.34 }, -- diameters (Diego's radius x 2)
		floorRing = { to = 6.5 * 1.7 * 2, s = 0.5, up = 0.15 },
		light = { brightness = 7 * 1.7, range = 18, s = 0.28 },
	},
	-- Killcam step 2 (2026-10-26; owner: "Yes, build step 2 of the killcam like that. You can make and upload the splat
	-- sound."): the screen pieces over the replay (UI/Match/KillcamScreen; S:195-229 markup, S:744-784 motion), in the
	-- end screen's stage px (Config.UI.Match.finish's layouts, its fit). ms unless named S.
	screen = {
		flashIn = { peak = 0.9, ms = 260 }, -- S:747
		bars = { inMs = 380, outMs = 300 }, -- S:748-749, 779-780
		vignette = { ms = 400, clearShare = 0.52, edgeAlpha = 0.45 }, -- S:750, S:196 (radial: two edge gradients here)
		pill = { delayMs = 150, ms = 300, rise = 8, gap = 8, padX = 12, border = 2, blinkS = 1 }, -- S:199-203, 751
		slow = { ms = 150 }, -- S:204-206
		letters = { delayMs = 300, stepMs = 45, ms = 420, drop = 60, sx = 0.9, sy = 1.2, landSx = 1.25, landSy = 0.7 }, -- S:752
		card = { delayMs = 650, ms = 420, slide = 40, from = 0.85, over = 4, peak = 1.04 }, -- S:753
		stamp = { stepMs = 40, ms = 300, from = 2.4, fromRot = -12, mid = 0.86, holdMs = 2600, rot = -7 }, -- S:763-765
		stampPad = { desktop = 260, phone = 110 }, -- S:762
		stampUp = { desktop = 70, phone = 30 },
		flashHit = { delayMs = 90, ms = 650, peak = 0.9, at = 0.12 }, -- S:767
		burst = { n = 46, spread = 520, size = 16, ms = 1200, up = 70 }, -- S:771
		rings = { sizes = { 340, 400, 460 }, stepMs = 100 }, -- S:772: white, the killer's team colour, #FFD86B
		jolt = 16, -- S:774: the screen shakes this many px (camera shake on, no ReducedMotion)
		slamAtS = 0.14, -- S:769: the slam after the boom and the splat
		outMs = 220, -- S:781-782: the pill, card, vignette and stamp fade; the letters rise outRise px
		outRise = 30,
		flashOut = { ms = 360, peak = 0.85, at = 0.4 }, -- S:783
		goneS = 0.36, -- S:784
		layouts = { -- S:503-505
			desktop = {
				bar = 76,
				cardL = 28,
				pillL = 136,
				right = 28,
				pillT = 21,
				pillH = 34,
				pillPx = 13,
				dot = 10,
				title = 64,
				titleStroke = 12,
				titleT = 96,
				letterGap = 3,
				cardB = 96,
				cardGap = 14,
				cardPad = 9,
				cardPadR = 18,
				cardBorder = 4,
				cardRadius = 20,
				head = 58,
				headRadius = 14,
				textGap = 6,
				name = 24,
				nameStroke = 5,
				sub = 15,
				toy = 36,
				stampPx = 96,
				stampStroke = 14,
			},
			phone = {
				bar = 52,
				cardL = 12,
				pillL = 124,
				right = 12,
				pillT = 15,
				pillH = 22,
				pillPx = 10,
				dot = 7,
				title = 30,
				titleStroke = 6,
				titleT = 58,
				letterGap = 1,
				cardB = 60,
				cardGap = 8,
				cardPad = 5,
				cardPadR = 10,
				cardBorder = 2,
				cardRadius = 14,
				head = 34,
				headRadius = 10,
				textGap = 3,
				name = 15,
				nameStroke = 3,
				sub = 11,
				toy = 24,
				stampPx = 40,
				stampStroke = 7,
			},
		},
	},
}
