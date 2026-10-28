--!strict
-- Config.HighwayFx (2026-10-28, the physics upgrade's part 4: the highway throw; owner: "Yes, build part 4"). Shared,
-- data only. The co-owner's Claude Design page docs/squishy-fx-spec/highway.html (CONFIG.fx, CONFIG.shared
-- .highwayThrow; readable copy notes.md "Part 4 · Highway"), ADDED ON TOP of the game's highway (owner, Decisions
-- 2026-10-28): the server's flight path, the boost, the rings, the PERFECT bar, the distance number, the zone names,
-- Diego's wind-up arm, the launcher-coloured trail and the pay all stay. The camera keeps its throw, chase and landing
-- shots; the design's hero shot replaces the landing shot. The slow motions really slow the drawn flight, which then
-- runs a little faster until it is back on the server's clock (catchUp), so the boost keeps working.
-- Not ported: the stop-point solver (the server's path stays), windup / throwBig poses (Diego's ThrowMotion stays),
-- distanceCounter and zoneBanner (the game's own HUD shows them), flightTrail (the game's trail stays), the chase
-- camera's offsets and bank (the owner kept the game's chase).
-- The design's zone order is the game's (Config.Economy.Highway.starts: Candy Meadow .. Divine Heaven); its preview
-- zone starts are not used. Played by Client/Anim/FeelFx (two runs: the thrower's wind-up, the flying squishy's
-- flight); particles from FeelVfxBuilder (SD_MoveVfx.Feel); Controllers/HighwayFxController drives the signals.
-- Offsets (`offset`) are lane-space studs: x right, y up, z back toward the thrower (the design's axes).

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local INK = Color3.fromHex("#3B2A35")

local HighwayFx = {
	-- The switch: false = the highway throw looks as before part 4.
	enabled = true,
	sonicFrom = 2000, -- a landing at least this far: sound-barrier rings at the launch
	hangFrom = 2000, -- this far: the apex hang slow motion
	impactFrom = 2000, -- this far: the first landing's freeze and slow motion
	fastFrom = 400, -- studs/s: edge speed lines every fastLinesEvery s while the arc is this fast
	fastLinesEvery = 0.22,
	-- The drawn flight's clock after a slow motion: this x real time until it is back on the server's clock.
	catchUp = 1.5,
	-- The design's zone colours and ids, in the game's zone order.
	zones = {
		{ id = "meadow", color = Color3.fromHex("#8EDFC4") },
		{ id = "bakery", color = Color3.fromHex("#FFD25E") },
		{ id = "lagoon", color = Color3.fromHex("#8CC8FF") },
		{ id = "frozen", color = Color3.fromHex("#B9A6E8") },
		{ id = "lava", color = Color3.fromHex("#F2687F") },
		{ id = "rainbow", color = Color3.fromHex("#B892F0") },
		{ id = "heaven", color = Color3.fromHex("#FFD86B") },
	},
	-- Squash tracks { t, x, y, z, easing } (x across, y up, z along the travel); on the tumbling squishy the y share
	-- goes to its axis nearest the world's up and the z share to the one nearest the travel (HighwayFxController).
	squashes = {
		windupSquish = { hold = true, keys = { { 0, 1, 1, 1, "Sine InOut" }, { 0.5, 1.14, 0.86, 1.14 } } },
		launchStretch = {
			hold = true,
			keys = {
				{ 0, 0.7, 0.7, 1.7, "Quad Out" },
				{ 0.1, 1.12, 1.12, 0.86, "Quad InOut" },
				{ 0.2, 0.95, 0.95, 1.12, "Sine InOut" },
				{ 0.32, 0.97, 0.97, 1.08 },
			},
		},
		bounceSquashBig = {
			keys = { { 0, 1.6, 0.45, 1.6, "Quad Out" }, { 0.06, 0.82, 1.25, 0.82, "Quad InOut" }, { 0.13, 1.08, 0.92, 1.08, "Sine InOut" }, { 0.22, 1, 1, 1 } },
		},
		bounceSquashSmall = {
			keys = { { 0, 1.3, 0.7, 1.3, "Quad Out" }, { 0.06, 0.9, 1.12, 0.9, "Sine InOut" }, { 0.14, 1, 1, 1 } },
		},
		stopSquash = {
			keys = { { 0, 1.3, 0.7, 1.3, "Quad Out" }, { 0.1, 0.88, 1.18, 0.88, "Sine InOut" }, { 0.22, 1.05, 0.95, 1.05, "Sine InOut" }, { 0.34, 1, 1, 1 } },
		},
	},
	wobbles = {
		flightWobble = { amplitude = 0.05, frequency = 6, decay = 0.8, axisRatio = 1, time = 8 },
	},
	scaleMax = 1.8, -- the flying squishy's deformer ceiling (launchStretch reaches 1.7)

	stage = { feetLift = 0.06, groundLift = 0.04, chestHeight = 3.6, backUpAngle = 35 },
	posePriority = 1.8,
	heldArmJoints = { "RightShoulder", "RightElbow", "RightWrist" },
	poses = {},

	rings = {
		chargeInRing = { color = Color3.fromHex("#FFD86B"), sizeStart = 14, sizeEnd = 2.5, time = 0.45, easing = "Quad In", transparencyStart = 1, transparencyEnd = 0.2, transparencyEasing = "Quad Out" },
		launchRing = { color = Color3.fromHex("#FFFFFF"), sizeStart = 1, sizeEnd = 9, time = 0.3, easing = "Quad Out", transparencyStart = 0.05, transparencyEnd = 1, transparencyEasing = "Quad In" },
		launchShock = { color = Color3.fromHex("#FFFFFF"), sizeStart = 2, sizeEnd = 22, time = 0.4, easing = "Quad Out", transparencyStart = 0, transparencyEnd = 1, transparencyEasing = "Quad In" },
		sonicRing = { color = Color3.fromHex("#FFFFFF"), sizeStart = 3, sizeEnd = 16, time = 0.4, easing = "Quad Out", transparencyStart = 0.1, transparencyEnd = 1, transparencyEasing = "Quad In" },
		zoneRing = { color = Color3.fromHex("#FFFFFF"), tinted = true, follow = true, sizeStart = 4, sizeEnd = 26, time = 0.4, easing = "Quad Out", transparencyStart = 0, transparencyEnd = 1, transparencyEasing = "Quad In" },
		haloRing = { color = Color3.fromHex("#FFD86B"), follow = true, sizeStart = 3, sizeEnd = 16, time = 0.45, easing = "Quad Out", transparencyStart = 0, transparencyEnd = 1, transparencyEasing = "Quad In" },
		landRing = { color = Color3.fromHex("#FFF4E6"), sizeStart = 2, sizeEnd = 14, time = 0.35, easing = "Quad Out", transparencyStart = 0.05, transparencyEnd = 1, transparencyEasing = "Quad In" },
		craterRing = { color = Color3.fromHex("#FFFFFF"), sizeStart = 4, sizeEnd = 26, time = 0.45, easing = "Quad Out", transparencyStart = 0.1, transparencyEnd = 1, transparencyEasing = "Quad In" },
		stopRing = { color = Color3.fromHex("#FFD86B"), sizeStart = 2, sizeEnd = 14, time = 0.4, easing = "Quad Out", transparencyStart = 0, transparencyEnd = 1, transparencyEasing = "Quad In" },
	},
	lights = {
		launchLight = { color = Color3.fromHex("#FFF4E6"), brightness = 4, range = 24, time = 0.35, easing = "Quad Out" },
		stopLight = { color = Color3.fromHex("#FFD86B"), brightness = 3, range = 22, time = 1.2, easing = "Quad Out" },
	},
	glows = {
		heavenGlow = { fill = Color3.fromHex("#FFE7A3"), outline = Color3.fromHex("#FFD86B"), fillFrom = 0.3, outlineFrom = 0, time = 0.5, easing = "Quad Out" },
		stopGlow = { fill = Color3.fromHex("#FFFFFF"), outline = Color3.fromHex("#FFD86B"), fillFrom = 0.35, outlineFrom = 0, time = 0.35, easing = "Quad Out" },
	},
	screens = {
		cineBars = { kind = "letterbox", color = INK, height = 0.085, fadeIn = 0.2, inEasing = "Quad Out", hold = 0.75, fadeOut = 0.3, outEasing = "Quad InOut" },
		cineBarsHero = { kind = "letterbox", color = INK, height = 0.085, fadeIn = 0.3, inEasing = "Quad Out", hold = 0.85, fadeOut = 0.3, outEasing = "Quad InOut" },
		-- Edge glows (squishy-fx.js uiVignette: clear inside clearRadius of the half screen, opacity at the edge).
		frostVignette = { kind = "vignette", color = Color3.fromHex("#CFE0FF"), clearRadius = 0.5, opacity = 0.55, fadeIn = 0.12, hold = 0.35, fadeOut = 0.6 },
		heatVignette = { kind = "vignette", color = Color3.fromHex("#FF8A5C"), clearRadius = 0.5, opacity = 0.4, fadeIn = 0.12, hold = 0.3, fadeOut = 0.6 },
		heavenVignette = { kind = "vignette", color = Color3.fromHex("#FFF6D6"), clearRadius = 0.5, opacity = 0.6, fadeIn = 0.15, hold = 0.35, fadeOut = 0.7 },
	},
	lines = {
		sonicLines = { color = Color3.fromHex("#FFFFFF"), count = 22, inner = 0.5, outer = 1, lengthPx = { 220, 380 }, widthPx = { 10, 18 }, jitter = 10, travel = 0.18, time = 0.35, stagger = 0.04, opacity = 0.85, easing = "Quad Out", fadeEasing = "Quad In" },
		speedLines = { color = Color3.fromHex("#FFFFFF"), count = 10, inner = 0.62, outer = 1, lengthPx = { 160, 300 }, widthPx = { 8, 14 }, jitter = 14, travel = 0.12, time = 0.3, stagger = 0.06, opacity = 0.55, easing = "Quad Out", fadeEasing = "Quad In" },
		zoneWarp = { color = Color3.fromHex("#FFFFFF"), tinted = true, count = 18, inner = 0.55, outer = 1, lengthPx = { 200, 360 }, widthPx = { 10, 18 }, jitter = 10, travel = 0.16, time = 0.35, stagger = 0.05, opacity = 0.75, easing = "Quad Out", fadeEasing = "Quad In" },
	},
	slowmos = {
		releaseSlow = { speed = 0.3, fadeIn = 0.04, inEasing = "Quad Out", hold = 0.3, fadeOut = 0.35, outEasing = "Sine InOut" },
		apexHang = { speed = 0.6, fadeIn = 0.15, inEasing = "Sine InOut", hold = 0.25, fadeOut = 0.35, outEasing = "Sine InOut" },
		impactSlow = { speed = 0.35, fadeIn = 0.02, inEasing = "Quad Out", hold = 0.2, fadeOut = 0.3, outEasing = "Sine InOut" },
		finalSlow = { speed = 0.5, fadeIn = 0.08, inEasing = "Quad Out", hold = 0.35, fadeOut = 0.3, outEasing = "Sine InOut" },
	},
	fovs = {
		launchFov = { delta = 8, attack = 0.08, attackEasing = "Quad Out", hold = 0.3, release = 0.6, releaseEasing = "Sine InOut" },
	},
	shakes = {
		launchShake = { amplitude = 0.8, time = 0.25, frequency = 18, easing = "Quad Out", axes = v(1, 0.6, 0.4) },
		heatRumble = { amplitude = 0.5, time = 0.35, frequency = 12, easing = "Quad Out", axes = v(1, 0.5, 0.3) },
		landShake = { amplitude = 1.2, time = 0.3, frequency = 16, easing = "Quad Out", axes = v(1, 0.6, 0.4) },
	},
	impactFreeze = 0.06, -- s (the design's hitstop impactFreeze; the moment's `freeze`)
	-- The hero shot at the stop (CONFIG.chaseCam.Hero; lane space: Side right, Up, Front ahead of the squishy).
	hero = { side = 9, up = 3.5, front = 11, fov = 58, time = 0.9, easing = "Sine InOut" },
	texts = {
		-- text = the landing's distance (HighwayFxController); lifted by the flying squishy's size over the design's.
		distancePop = { text = "", color = Color3.fromHex("#FFD86B"), stroke = INK, offset = v(0, 5.5, 0), size = { { 0, 0 }, { 0.18, 3.6 }, { 0.3, 3 }, { 1.2, 3 }, { 1.45, 0 } }, transparency = { { 0, 0 }, { 1.2, 0 }, { 1.45, 1 } }, time = 1.45 },
		fireworkFlash = { texture = "sparkle", color = Color3.fromHex("#FFFFFF"), size = { { 0, 1 }, { 0.06, 7 }, { 0.2, 0 } }, transparency = { { 0, 0 }, { 1, 0 } }, rotation = { 0, 45 }, time = 0.2, offset = v(0, 0, 0) },
	},
	textCanvas = { aspect = 4, fontShare = 150 / 256, strokeShare = 22 / 150 },
	dips = {},
	punches = {},
	afterimages = {},
	-- The design's sound names -> ours (false = the game's own sound plays there already, or none of ours fits yet).
	sounds = {
		windup_charge_rise = false,
		highway_launch_whoomp = { key = "sfx.dashWhoosh", volume = 1, pitch = 0.7 },
		sonic_boom = false,
		apex_whistle = false,
		zone_chime = false,
		splash_bloop = { key = "sfx.pop", volume = 0.8, pitch = 0.8 },
		frost_crackle = false,
		lava_whoosh = { key = "sfx.dashWhoosh", volume = 0.8, pitch = 0.8 },
		rainbow_shimmer = false,
		choir_hit = false,
		land_boing_big = { key = "sfx.impactBoing", volume = 1, pitch = 0.8 },
		land_boing_small = { key = "sfx.squish", volume = 0.5 },
		roll_squish_loop = false,
		highway_stop_fanfare = false,
		firework_pop = { key = "sfx.pop", volume = 0.7, pitch = 1.2 },
	} :: { [string]: any },

	moments = {
		-- The thrower, from the press (the design's t = -0.5; the game's release comes RELEASE s later); "launch" = the
		-- release.
		windup = {
			{ t = 0, emit = "windupSparks", at = "held", ["for"] = 0.45 },
			{ t = 0, ring = "chargeInRing", at = "feet" },
			{ t = 0.1, screen = "cineBars" },
			{ t = 0, sound = "windup_charge_rise" },
			{ on = "launch", t = 0, ring = "launchShock", at = "feet" },
			{ on = "launch", t = 0, burst = "launchDust", at = "feet", aim = "up" },
		},
		-- The flying squishy, from the release. at "root" = its centre, "hit" = the lane under it.
		flight = {
			{ t = 0, slowmo = "releaseSlow" },
			{ t = 0, fov = "launchFov" },
			{ t = 0, shake = "launchShake" },
			{ t = 0, burst = "launchStars", at = "root", aim = "back" },
			{ t = 0, burst = "launchSparkles", at = "root" },
			{ t = 0, burst = "launchPuff", at = "root", aim = "forward" },
			{ t = 0, ring = "launchRing", at = "root", face = "forward" },
			{ t = 0, light = "launchLight", at = "root" },
			{ t = 0, emit = "meadowConfetti", at = "root", aim = "back", group = "zoneAmbient" },
			{ t = 0, sound = "highway_launch_whoomp" },
			{ on = "sonic", t = 0.05, ring = "sonicRing", at = "root", face = "forward" },
			{ on = "sonic", t = 0.11, ring = "sonicRing", at = "root", face = "forward" },
			{ on = "sonic", t = 0.17, ring = "sonicRing", at = "root", face = "forward" },
			{ on = "sonic", t = 0.05, lines = "sonicLines" },
			{ on = "sonic", t = 0.05, sound = "sonic_boom" },
			{ on = "fast", t = 0, lines = "speedLines" },
			{ on = "apex", t = 0, sound = "apex_whistle" },
			{ on = "apexLong", t = 0, slowmo = "apexHang" },
			-- Bursts the design locks to the squishy (LockedToPart) ride on it: held carriers (`emit`) for their lifetime.
			{ on = "apexLong", t = 0, emit = "apexTwinkle", at = "root", ["for"] = 0.5 },
			{ on = "zoneExit", t = 0, stop = "zoneAmbient" },
			{ on = "zone", t = 0, ring = "zoneRing", at = "root", face = "forward" },
			{ on = "zone", t = 0, emit = "zoneSparkles", at = "root", ["for"] = 0.5 },
			{ on = "zone", t = 0, lines = "zoneWarp" },
			{ on = "zone", t = 0, sound = "zone_chime" },
			{ on = "zone_bakery", t = 0, emit = "sprinkleBurst", at = "root", ["for"] = 0.7 },
			{ on = "zone_bakery", t = 0, emit = "bakerySprinkles", at = "root", aim = "back", group = "zoneAmbient" },
			{ on = "zone_lagoon", t = 0, emit = "splashBurst", at = "root", ["for"] = 0.55 },
			{ on = "zone_lagoon", t = 0, emit = "lagoonBubbles", at = "root", aim = "back", group = "zoneAmbient" },
			{ on = "zone_lagoon", t = 0, sound = "splash_bloop" },
			{ on = "zone_frozen", t = 0, emit = "frostBurst", at = "root", ["for"] = 0.55 },
			{ on = "zone_frozen", t = 0, screen = "frostVignette" },
			{ on = "zone_frozen", t = 0, emit = "snowSparkles", at = "root", aim = "back", group = "zoneAmbient" },
			{ on = "zone_frozen", t = 0, sound = "frost_crackle" },
			{ on = "zone_lava", t = 0, emit = "lavaBurst", at = "root", ["for"] = 0.6 },
			{ on = "zone_lava", t = 0, screen = "heatVignette" },
			{ on = "zone_lava", t = 0, shake = "heatRumble" },
			{ on = "zone_lava", t = 0, emit = "lavaEmbers", at = "root", aim = "back", group = "zoneAmbient" },
			{ on = "zone_lava", t = 0, sound = "lava_whoosh" },
			{ on = "zone_rainbow", t = 0, emit = "rainbowBurst", at = "root", ["for"] = 0.7 },
			{ on = "zone_rainbow", t = 0, trail = "bandRed", at = "band", offset = -1.5, group = "zoneAmbient" },
			{ on = "zone_rainbow", t = 0, trail = "bandOrange", at = "band", offset = -0.9, group = "zoneAmbient" },
			{ on = "zone_rainbow", t = 0, trail = "bandYellow", at = "band", offset = -0.3, group = "zoneAmbient" },
			{ on = "zone_rainbow", t = 0, trail = "bandMint", at = "band", offset = 0.3, group = "zoneAmbient" },
			{ on = "zone_rainbow", t = 0, trail = "bandSky", at = "band", offset = 0.9, group = "zoneAmbient" },
			{ on = "zone_rainbow", t = 0, trail = "bandViolet", at = "band", offset = 1.5, group = "zoneAmbient" },
			{ on = "zone_rainbow", t = 0, sound = "rainbow_shimmer" },
			{ on = "zone_heaven", t = 0, emit = "heavenBurst", at = "root", ["for"] = 0.65 },
			{ on = "zone_heaven", t = 0, ring = "haloRing", at = "root", face = "up" },
			{ on = "zone_heaven", t = 0, glow = "heavenGlow" },
			{ on = "zone_heaven", t = 0, screen = "heavenVignette" },
			{ on = "zone_heaven", t = 0, emit = "heavenSparkles", at = "root", aim = "back", group = "zoneAmbient" },
			{ on = "zone_heaven", t = 0, sound = "choir_hit" },
			{ on = "bounce1", t = 0, stop = "zoneAmbient" },
			{ on = "bounce1", t = 0, burst = "landPuffBig", at = "hit", aim = "up" },
			{ on = "bounce1", t = 0, burst = "landDrops", at = "hit", aim = "up" },
			{ on = "bounce1", t = 0, burst = "impactStars", at = "hit", aim = "up" },
			{ on = "bounce1", t = 0, ring = "landRing", at = "hit" },
			{ on = "bounce1", t = 0.05, ring = "craterRing", at = "hit" },
			{ on = "bounce1", t = 0, shake = "landShake" },
			{ on = "bounce1", t = 0, sound = "land_boing_big" },
			{ on = "impactBig", t = 0, freeze = 0.06 },
			{ on = "impactBig", t = 0, slowmo = "impactSlow" },
			{ on = "bounceN", t = 0, burst = "bouncePuff", at = "hit", aim = "up" },
			{ on = "bounceN", t = 0, sound = "land_boing_small" },
			{ on = "lastBounce", t = 0, slowmo = "finalSlow" },
			{ on = "roll", t = 0, emit = "rollDust", at = "hit", aim = "back" },
			{ on = "roll", t = 0, sound = "roll_squish_loop" },
			{ on = "stop", t = 0, stop = "rollDust" },
			{ on = "stop", t = 0, burst = "stopConfetti", at = "hit", aim = "up" },
			{ on = "stop", t = 0, burst = "stopSparkles", at = "root" },
			{ on = "stop", t = 0, ring = "stopRing", at = "hit" },
			{ on = "stop", t = 0, glow = "stopGlow" },
			{ on = "stop", t = 0, light = "stopLight", at = "root" },
			{ on = "stop", t = 0, pop = "distancePop", at = "root" },
			{ on = "stop", t = 0, screen = "cineBarsHero" },
			{ on = "stop", t = 0, sound = "highway_stop_fanfare" },
			{ on = "stop", t = 0.1, emit = "confettiRain", at = "root", offset = v(0, 18, 6), aim = "down", ["for"] = 0.5 },
			{ on = "stop", t = 0.3, burst = "fireworkA", at = "root", offset = v(-7, 10, 14) },
			{ on = "stop", t = 0.3, pop = "fireworkFlash", at = "root", offset = v(-7, 10, 14) },
			{ on = "stop", t = 0.3, sound = "firework_pop" },
			{ on = "stop", t = 0.55, burst = "fireworkB", at = "root", offset = v(5, 13, 20) },
			{ on = "stop", t = 0.55, pop = "fireworkFlash", at = "root", offset = v(5, 13, 20) },
			{ on = "stop", t = 0.55, sound = "firework_pop" },
			{ on = "stop", t = 0.8, burst = "fireworkC", at = "root", offset = v(-1, 8.5, 26) },
			{ on = "stop", t = 0.8, pop = "fireworkFlash", at = "root", offset = v(-1, 8.5, 26) },
			{ on = "stop", t = 0.8, sound = "firework_pop" },
		},
	} :: { [string]: { any } },

	phone = { countShare = 0.5, trailLifetimeScale = 0.7 },
	reduceMotion = { flash = 0.5 },
}

return HighwayFx
