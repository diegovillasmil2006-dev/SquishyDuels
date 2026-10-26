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
