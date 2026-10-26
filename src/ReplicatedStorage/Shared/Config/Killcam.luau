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
	-- every first-person arm is the player's own), as wide as Diego's fist at studsPerDu.
	arm = {
		at = Vector3.new(1.15, -1.2, -2.3),
		yaw = 0.22,
		hand = Vector3.new(0, 0, -0.6),
		shoulder = Vector3.new(0, 0, 2.7),
		toy = Vector3.new(0, 0.7, -0.9),
		toyScale = 0.55,
		studsPerDu = 9, -- [P] the avatar hand (handWidthDu 0.1) as wide as Diego's 0.9-stud fist
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
}
