--!strict
-- Config.UI.Match.finish's podium and name tags (end screens round B1, 2026-10-26; owner: "Yes, build step 1 of round
-- B like that. You can make and upload the sounds."; E = Diego's uploads/sd/tdm-end.js, P = uploads/sd/poses.js, A =
-- uploads/sd/avatar.js, S = his "Squishy Duels LOADING SCREEN Y MATCH HUD.dc.html"): the 3D podium (UI/Match/
-- MatchPodium) in studs and seconds from its cue, and the name tags MatchEnd draws over it. Shared, data only. A child
-- module of Config/UI (UI.luau is near Roblox's 200,000-character Source limit), exposed as
-- Config.UI.Match.finish.podium, .plates and each finish layout's `plates`.

return {
	podium = {
		at = 2.4, -- S:824: the podium cue, 2.4 s after the last squish (the jelly wave covers the screen)
		skipAt = 3.4, -- E:317: a skip jumps here, every clip done
		lift = 0.1, -- the maps' floor art sits 0.1 over the floor (JAR_Decal_JellyFloor, SPF_Decal_SugarFloor ...)
		-- the map's middle prop: its parts within hideRadius of the centre, up to hideTop over the floor (the cake's 12
		-- and the line's 13.5 plus room); the floor art (under hideFloor) stays
		hideRadius = 15,
		hideTop = 30,
		hideFloor = 0.6,
		yaws = 8, -- the scene faces the one of 8 turns whose shots the map blocks least
		max = 6, -- E:197
		-- E:15: rank 1-6 on the cake { x, y, z, turn (rad) }; tier tops 1.2 / 4.6 / 9.0
		cakeSlots = {
			{ 0, 9, 0, 0 },
			{ -4.6, 4.6, 3.8, 0.18 },
			{ 4.6, 4.6, 3.8, -0.18 },
			{ 0, 1.2, 10, 0 },
			{ -9, 1.2, 5.8, 0.3 },
			{ 9, 1.2, 5.8, -0.3 },
		},
		-- E:16, 200: the line, gap apart, bowed (z = depth - |x|·slope), turned in (-x·turn), centred for fewer than 6;
		-- its clips start at start + step per player
		line = { gap = 5.4, depth = 3, slope = 0.15, turn = 0.012, start = 0.15, step = 0.17 },
		hits = { 2.3, 0.6, 0.85, 1.1, 1.35, 1.6 }, -- E:17-18: each cake rank's HIT after the cue
		idle = { speed = 2.4, lift = 0.03, waist = 1.2 }, -- E:214: before a clip starts
		hitStop = 0.08, -- E:162: the MVP's slam freezes the poses
		rigHeight = 2.85, -- A:19: the design rig's root height; root offsets scale by ours / this
		-- E:132-135: where the held squishy sits: over the head's top, in front of the chest, the left hand's palm
		prop = { headLift = 0.42, chestUp = 0.2, chestFront = 1.1, handsDrop = 0.34 },
		-- E:35-63: { radius, height, bottom } per tier; the frosting cap r + capOver, capH tall, capDrop under the top;
		-- the cream rim's tube (here dollops dollopGap apart); drips: round(r · drips) a tier, radius drip, dripLen[1] +
		-- (k mod 3) · dripLen[2] long, dripDrop[1] + (k mod 3) · dripDrop[2] under the top; the sprinkles seeded
		-- (Park-Miller, seed) from `inner` past the next tier (`centre` on the top one) to `edge` inside the rim
		cake = {
			tiers = { { 12, 1.2, 0 }, { 7.5, 3.4, 1.2 }, { 4.2, 4.4, 4.6 } },
			capOver = 0.12,
			capH = 0.55,
			capDrop = 0.27,
			rim = 0.42,
			dollopGap = 1.25,
			drips = 3.2,
			drip = 0.34,
			dripLen = { 0.5, 0.45 },
			dripDrop = { 0.75, 0.22 },
			sprinkles = { 34, 22, 10 },
			sprinkle = { radius = 0.09, length = 0.36, rise = 0.06, inner = 0.6, edge = 0.7, centre = 0.4 },
			seed = 7,
			phoneDetail = 0.6, -- phones: this share of the dollops, drips and sprinkles
			outline = 0, -- the Highlight outline's OutlineTransparency (the design's toon outline)
		},
		-- E:64-76, 226-240: the band (radius, height, thickness, pieces), the spikes (width, height, centre height),
		-- the gems; it drops dropS from `drop` studs over the head's top + seat, spinning `spin` rad, lands and wobbles
		-- (1 + squashX·sq, 1 - squashY·sq, sq = e^(-wobbleDecay·u)·cos(wobbleHz·u) for wobbleS), and bobs from frame
		-- bobFrom of the MVP's clip (|sin((f - bobFrom) / bobFrames · π)| · bob)
		crown = {
			radius = 0.62,
			bandH = 0.42,
			bandThick = 0.12,
			bandPieces = 10,
			spikes = 5,
			spikeW = 0.36,
			spikeH = 0.46,
			spikeY = 0.62,
			gem = 0.17,
			gemY = 0.88,
			seat = 0.06,
			drop = 6,
			dropS = 0.22,
			spin = 4,
			wobbleS = 0.4,
			wobbleDecay = 9,
			wobbleHz = 26,
			squashX = 0.25,
			squashY = 0.3,
			bobFrom = 48,
			bobFrames = 18,
			bob = 0.16,
		},
		-- E:241-266 (design studs; the FOV is vertical, as Roblox's)
		camera = {
			orbit = { from = 0.2, span = 1.6, deg = 3, radius = 42, close = 11, y = 3, rise = 1.2, lookY = 7.2 },
			push = { at = 1.8, span = 0.5, pos = { 0, 9.6, 16.5 }, look = { 0, 11.4, 0 }, fov = 70, fovTo = 52 },
			hero = { at = 2.6, span = 0.7, pos = { 0, 5.4, 30.5 }, look = { 0, 9, 0 }, fovTo = 50 },
			line = { from = { 0, 6.8, 29 }, to = { 0, 6.2, 24.5 }, look = { 0, 3.6, 1.8 }, span = 3.2, fov = 55 },
			tick = { s = 0.12, fov = 1.5 },
			kick = { fov = 8, decay = 9, freq = 16, shakeS = 0.35, amp = 0.5, hz = 14, yHz = 1.1, yAmp = 0.6 },
			softKick = { fov = 2.5, s = 0.45 },
			breathe = { from = 2.6, hz = 0.25, yawDeg = 0.4, pitchDeg = 0.25, phase = 1.2 },
		},
		-- E:164-170: the slam's rings (height, diameter, seconds, first transparency), its burst (height, count per
		-- layout, studs/s, size, seconds, fall) and its light (E:167)
		slam = {
			ring = { y = 9.05, size = 22, s = 0.45, from = 0.05 },
			ring2 = { y = 10.6, size = 16, s = 0.5, from = 0.15 },
			burst = { y = 9.8, desktop = 32, phone = 16, speed = { 12, 18 }, size = 0.5, life = 1.1, gravity = 21 },
			light = { y = 12, z = 3, brightness = 8, range = 30, s = 0.3 },
		},
		-- E:156, 158: a pose's HIT stars and the hug's hearts at the chest
		stars = { desktop = 10, phone = 6, speed = { 8, 12 }, size = 0.42, life = 0.8, rise = 10 },
		hearts = { desktop = 10, phone = 6, up = 1.2, speed = { 6, 9 }, size = 0.5, life = 1.1, gravity = 8 },
		-- E:205-206: the grade (ColorCorrection saturation, brightness; the tint is Palette.PodiumLineTint)
		grade = { cakeSaturation = 0.06, lineSaturation = -0.22, lineBrightness = -0.03 },
		-- E:327: the name tags' point over the head's top (the crowned MVP's higher)
		plateLift = 0.25,
		mvpPlateLift = 1.2,
		poseSteps = { 0, 4, 7, 12, 16 }, -- sd-cues poseHit(i): the ting's semitones by ripple slot
		flash = { ms = 280, peak = 0.2, at = 0.25, softMs = 600, softPeak = 0.1, softAt = 0.5 }, -- S:890
		-- End screens round B2 (2026-10-26; owner: "Yes, build step 2 of round B like that. You can make and upload the
		-- pictures."): the party whenever the cake shows (E:93-128, 296-305). The design's speeds and pulls are its world
		-- units over STUD 0.28 (kit.js:3); particle sizes are a piece's span (twice the design's size). Its counts
		-- (BUDGET E:19-22) keep the live particles under its caps (desktop 900, phone 400) on their own.
		party = {
			budget = {
				desktop = {
					cannon = 45,
					rain = 60,
					rainThin = 18,
					rocketGap = 0.7,
					rocketGapThin = 2.2,
					sparks = 26,
					hearts = 8,
					balloons = 5,
				},
				phone = {
					cannon = 22,
					rain = 26,
					rainThin = 8,
					rocketGap = 1.1,
					rocketGapThin = 2.6,
					sparks = 14,
					hearts = 4,
					balloons = 3,
				},
			},
			-- E:93-105, at the "!" (S:831, victory only): 4 cannons { x, z } at height y aim at (-x, up, -z); each piece
			-- within `spread` degrees (the design's jitter), its kind in turn (flake, petal, cube), its colour in turn (the
			-- winners' main and light, lemon, white); a star puff at each mouth
			cannons = {
				at = { { -58, -70 }, { 58, -70 }, { -58, 70 }, { 58, 70 } },
				y = 14,
				up = 62,
				spread = 17,
				speed = { 21.4, 35.7 }, -- 6 + 4 world/s
				size = { 0.6, 1 }, -- s(0.3 + 0.2)
				life = { 3.2, 4.2 },
				gravity = 7.9, -- 2.2 world/s²
				drag = 1.6, -- the design's e^(-1.1·t) as Roblox's halving rate
				spinDeg = 400, -- 7 rad/s
				puff = { count = 6, speed = 14.3, size = 1.2, life = 0.4 },
			},
			-- E:77-83, 296, 312: 4 warm beams from these points (design studs), radius 5.2 over their 50 studs, each
			-- sweeping its aim round the cake (x = sin(0.7t + 1.7i)·9, z = cos(0.5t + i)·5), alpha 0.12, 0.07 with the
			-- results
			spots = {
				from = { { -34, 34, 18 }, { 34, 34, 18 }, { -24, 40, -30 }, { 24, 40, -30 } },
				radius = 5.2,
				length = 50,
				alpha = 0.12,
				thinAlpha = 0.07,
				sweep = { x = 9, z = 5, xHz = 0.7, zHz = 0.5, xPhase = 1.7 },
			},
			-- E:106-121, 297: a rocket every budget rocketGap from `first`, from x within ±halfX, y, z = -(back + up to
			-- backSpread) behind the cake; its speed (studs/s), pull and life; its ribbon (E:108); its burst of stars
			-- (sparks) and hearts (E:116-117)
			rockets = {
				first = 0.3,
				halfX = 55,
				y = 12,
				back = 78,
				backSpread = 10,
				side = 1.07, -- 0.6 world/s across, 0.4 deep
				depth = 0.71,
				rise = { 32.1, 37.5 }, -- 9 + 1.5 world/s
				gravity = 14.3, -- 4 world/s²
				life = { 0.85, 1.05 },
				trail = { width = 0.55, life = 0.35, alpha = 0.75 },
				stars = { speed = 19.6, size = 1.4, life = 1.3, gravity = 5.7, drag = 2 },
				hearts = { speed = 14.3, size = 1.5, life = 1.4, gravity = 4.3, drag = 2 },
			},
			-- E:122-128, 300-301: a balloon at each of these podium times (up to the budget's): a winner's squishy
			-- (in turn) scale times its size, lift over its string's foot, on a string `string` long; starting at x =
			-- ±(x + (i·xStep) mod xMod) (left first), y, z = -(z + (i·zStep) mod zMod); rising speed + (i mod 3)·speedStep
			-- studs/s with a sway (studs/s, rad/s) and a tilt (rad, rad/s), both from i·phase; gone above `top`
			balloons = {
				at = { 0.3, 0.7, 1.1, 1.6, 2.1 },
				scale = 2.3,
				lift = 5.4,
				string = 5,
				stringWidth = 0.1,
				x = 13,
				xStep = 3.7,
				xMod = 8,
				y = -4,
				z = 3,
				zStep = 2.3,
				zMod = 6,
				speed = 2.2,
				speedStep = 0.35,
				phase = 1.7,
				sway = { 0.4, 1.3 },
				tilt = { 0.12, 1.1 },
				top = 70,
			},
			-- E:302-304: sprinkles a second (the budget's rain, rainThin with the results) over x ±area[1]/2, z from z0
			-- over area[2], y from y over ySpread; falling speed, pull, drag, life, size and spin; colours in turn
			rain = {
				area = { 44, 26 },
				z0 = -10,
				y = 26,
				ySpread = 4,
				speed = { 4.3, 7.9 }, -- 1.2 + 1 world/s
				gravity = 1.8, -- 0.5 world/s²
				drag = 0.36, -- e^(-0.25·t)
				life = 4.2,
				size = 0.42, -- the capsule's length at size 0.2
				spinDeg = 290, -- 5 rad/s
			},
		},
	},
	-- The name tags (S:893-910, 857-858): drawn in the `text` kind scaled to their px; `gap` between two that meet,
	-- `clear` under the pill, `edge` inside the stage, their point `below` px under the head's; the pop: popMs each,
	-- stepMs apart (none after a skip), from `rise` px lower at scale `from` (the introSlam curve)
	plates = {
		text = "Small",
		gap = 4,
		clear = 6,
		edge = 4,
		below = 6,
		popMs = 380,
		stepMs = 60,
		rise = 14,
		from = 0.7,
	},
	-- Each finish layout's tags (S:272-277; tdm-hud.js:62, 69 plateName / plateH / plateMax; S:495-500 the rest): px of
	-- the name, the chip, its SQ (unit: shown) and the tag over the tag
	layouts = {
		desktop = {
			height = 40,
			maxW = 190,
			mvpMaxW = 220,
			pad = 9,
			gap = 6,
			border = 3,
			radius = 13,
			lip = 3,
			name = 16,
			chipH = 24,
			chip = 15,
			chipLabel = 11,
			unit = true,
			unitGap = 3,
			chipPad = 6,
			chipAlpha = 0.88, -- S:975 rgba(255,246,234,.12)
			tagTop = 13,
			tagH = 20,
			tag = 12,
			tagPad = 7,
			crownW = 24,
			crownH = 18,
		},
		phone = {
			height = 28,
			maxW = 120,
			mvpMaxW = 132,
			pad = 4,
			gap = 3,
			border = 2,
			radius = 8,
			lip = 3,
			name = 12,
			chipH = 16,
			chip = 12,
			chipLabel = 12,
			unit = false, -- S:975: phones show the number only
			unitGap = 3,
			chipPad = 6,
			chipAlpha = 0.88,
			tagTop = 11,
			tagH = 16,
			tag = 12,
			tagPad = 7,
			crownW = 13,
			crownH = 11,
		},
	},
}
