--!strict
-- Config.Abilities: ultimates keyed by Catalog `ultimateId` (DESIGN §5.9). Shared, data only. All [P].
-- Six abilities: Dragon Rush (Dragon, Exclusive), the four Epic ultimates of the design (spec phase 5 §1.4-§1.8;
-- design: ults.js:3-6): Flock Volley (Birdie), Sprinkle Roller (Donut), Rain Check (Cloud Bunny) and Bubble Pop
-- (Cupcake Axolotl), Gravity Well (Cosmo, Exclusive; Series 01, a one-drop rain), and the Frosty Box's two (2026-11-10;
-- design: sd/ults2.js:5-6, lab50.js:295-325): Geyser Line (Gelato Narwhal, Epic; a rain of 3 drops in a line) and Layer
-- Cake Shockwave (Parfait Wyvern, Exclusive). Each has a `kind`, the behaviour AbilityService runs for it:
--   lane    Dragon Rush: a sphere of `radius` swept from O to E at `speed`, at laneHeightAboveFloor, flying on through
--           the player it hits; tested at standing height (jumping never avoids it).
--   volley  `count` projectiles of `radius` fanned over `fanDeg` around the aim, `staggerSeconds` apart, straight at
--           `speed` (no gravity) at laneHeightAboveFloor, each ending at its first hit, cover or maxLength. fanDeg 360
--           (Puff Burst, Prism Box 2026-11-10) is a full circle: one on the aim, the others evenly round.
--   roller  a lane of half-width `radius` rolling along the floor at `speed` over maxLength, flying on; a body touching
--           it is hit unless its feet are higher than clearHeight above the floor (it can be jumped).
--   rain    a zone of `radius` centred on the opponent at the release; `drops` drops, each with a shadow first, hit a
--           player whose feet are within dropHitRadius of the drop when it lands. With dropSpacing (Geyser Line) the
--           drops stand in a line toward the centre from the caster's side, dropSpacing apart, the centre last.
--   shockwave  Layer Cake Shockwave: `count` rings grow from the caster's feet, `staggerSeconds` apart, at `speed` out
--           to maxLength, through cover; a ring's wall (half-thickness `radius`) hits a body it meets unless the feet
--           are higher than clearHeight above the floor (it can be jumped).
--   bubble  one projectile of `radius` at `speed`; it pops on a player, at cover or after popSeconds, and a player whose
--           feet are within splashRadius of the pop (on the floor) is hit. Bubble Pop bounce (2026-10-16): the first
--           `bounces` covers it meets bounce it off (mirrored on the cover's side, same speed) instead of popping it;
--           its whole path, bounce included, is still maxLength (= speed × popSeconds).
--   boomerang  Halo Toss (Halo Box 2026-11-10): one projectile of `radius` at `speed` and laneHeightAboveFloor, out
--           along the aim leaned so its far end is bowStuds to the side (UltRules.bowDir) up to maxLength or cover, then
--           back the same way to its start (the Bubble Pop bounce leg), flying on through the players it hits.
-- Every kind fills the shared fields its way: `radius` (the hit radius: lane sphere, projectile, half lane width, zone),
-- `speed` (travel), maxLength (the longest path; rain: the farthest practice target the zone may centre on),
-- laneHeightAboveFloor (the flight height; rain: the height the drops fall from) and originForwardStuds.
-- Rules every ability must pass (checked by Config.validate()): telegraph >= 0.35 s (user decision 2026-10-11: the
-- design's wind-ups win, ults.js:3-6), minIntervalSeconds >= 20, a budget cost for PowerBudget, Strings for name,
-- description and warnings, a sphere that stays above the floor (laneHeightAboveFloor > radius) for every kind that
-- flies, and per kind its own fields; a volley's or a bubble's radius equals its squishy's own throw radius.
-- User decisions 2026-10-11 for the four new ultimates: the same 0-100 charge meter and fill rules as Dragon Rush (the
-- design's meter is 100 too); the design's `cooldown` is the minimum interval between uses; the design's `charge` is
-- the telegraph (wind-up); a hit costs 1 life like every hit; the caster is rooted during the wind-up, cancel and
-- refund work, and the practice range behaves, exactly like Dragon Rush.

-- Duel HUD (owner 2026-10-24, "Use design's numbers"; design: Duel HUD.dc.html:229, 318): each ultimate is a timer of
-- its squishy's cooldown (Dragon 45, Birdie 35, Cloud Bunny 40, Cupcake Axolotl 36, Donut 38 s) that starts on 8 s at
-- the match start. Built on the same meter: it fills by time only (chargeMax / cooldown a second, no charge from hits
-- or lost lives), starts ULT_START_SECONDS short of full, empties at each use, and minIntervalSeconds = the cooldown.
local ULT_START_SECONDS = 8

export type AbilityKind = "lane" | "volley" | "roller" | "rain" | "bubble" | "shockwave" | "boomerang"

export type Ability = {
	kind: AbilityKind,
	nameKey: string,
	descriptionKey: string,
	incomingKey: string, -- opponent banner during the telegraph
	readyKey: string, -- opponent chip when the caster's charge is full (§11.6)
	cancelKey: string, -- lane label when a hit on the caster cancels the telegraph (§9.10)
	chargeMax: number,
	startCharge: number,
	chargePerSecond: number, -- Active and SuddenDeath only
	chargePerHitLanded: number,
	chargePerLifeLost: number,
	minIntervalSeconds: number,
	telegraphSeconds: number,
	radius: number,
	laneHeightAboveFloor: number,
	speed: number,
	maxLength: number,
	recoverySeconds: number,
	cancelOnHitDuringTelegraph: boolean,
	refundOnCancel: number,
	livesCost: number,
	knockbackMultiplier: number,
	budgetCost: number,
	practiceCooldownSeconds: number,
	minHorizontalAim: number,
	originForwardStuds: number,
	-- volley
	count: number?,
	fanDeg: number?,
	staggerSeconds: number?,
	-- roller
	clearHeight: number?,
	-- bubble
	popSeconds: number?,
	splashRadius: number?,
	bounces: number?, -- Bubble Pop bounce (2026-10-16): covers bounced off before one pops it (0 or 1)
	bounceMaxNormalY: number?, -- review fix (2026-10-16): only a surface with |unit normal.Y| below this bounces it
	-- boomerang
	bowStuds: number?, -- Halo Toss (2026-11-10): the path's far end lies this far to the side of the aim
	-- rain
	drops: number?,
	firstShadowSeconds: number?,
	dropStepSeconds: number?,
	shadowSeconds: number?,
	fallSeconds: number?,
	dropHitRadius: number?,
	dropRadii: { number }?,
	dropAngleStep: number?,
	targetRadius: number?,
	dropSpacing: number?, -- Geyser Line (2026-11-10): the drops in a line this far apart
	ringAroundCaster: boolean?, -- Campfire Ring (2026-11-10): the drops on a ring around the caster, from the aim
	triangleDeg: number?, -- Prism Pen (2026-11-10): the pop's area is an equilateral triangle, a corner at this angle
	sliceHalf: number?, -- Bread Stamp (2026-11-10): the stamp's area is a bread slice of this half-size (UltRules)
	sliceDeg: number?, -- Bread Stamp: the slice's crown toward this angle
	-- shockwave
	fill: boolean?, -- Fondue Flood (2026-11-10): the area behind the front is in too (a flood, not a wall)
}

local Abilities = {
	dragon_rush = {
		kind = "lane",
		nameKey = "ability.dragonRush.name",
		descriptionKey = "ability.dragonRush.description",
		incomingKey = "ability.dragonRush.incoming",
		readyKey = "ability.dragonRush.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100,
		startCharge = 100 - ULT_START_SECONDS * 100 / 45, -- every match
		chargePerSecond = 100 / 45, -- Active and SuddenDeath only
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 45, -- design: Duel HUD.dc.html:229 (Dragon Burst, cd 45)
		telegraphSeconds = 0.9, -- caster rooted; lane + dragon head visible to both
		radius = 4.0, -- swept sphere radius = half the lane width
		laneHeightAboveFloor = 4.5, -- sphere spans floor+0.5 .. floor+8.5
		speed = 260, -- studs/s, no gravity
		maxLength = 110, -- capped by Geometry and Bounds
		recoverySeconds = 0.35, -- rooted after release
		cancelOnHitDuringTelegraph = true,
		refundOnCancel = 0.5, -- fraction of chargeMax refunded on cancel
		livesCost = 1,
		knockbackMultiplier = 1.5,
		budgetCost = 2.0, -- PowerBudget ultimateCost
		practiceCooldownSeconds = 10, -- practice range: no charge needed
		minHorizontalAim = 0.3, -- aimDir is flattened; its horizontal magnitude must reach this
		originForwardStuds = 2, -- O = (HRP.X, floorY + laneHeightAboveFloor, HRP.Z) + dir * originForwardStuds
	},
	-- Birdie (design: ults.js:3 "Flock Volley").
	flock_volley = {
		kind = "volley",
		nameKey = "ability.flockVolley.name",
		descriptionKey = "ability.flockVolley.description",
		incomingKey = "ability.flockVolley.incoming",
		readyKey = "ability.flockVolley.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults.js:3 (meter 100); user decision 2026-10-11: Dragon Rush's meter
		startCharge = 100 - ULT_START_SECONDS * 100 / 35, -- Duel HUD timer (header)
		chargePerSecond = 100 / 35,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 35, -- design: ults.js:3 (cooldown 35 s); user decision 2026-10-11: the minimum interval
		telegraphSeconds = 0.35, -- design: ults.js:3 (charge 0.35 s); user decision 2026-10-11: the wind-up
		-- build choice 2026-10-11 (NOT IN DESIGN; user decision: "the game's normal projectile hit radius"): Birdie's own
		-- throw radius (Catalog bird.throw.radius; Config.validate checks they match).
		radius = 0.9,
		-- build choice 2026-10-11 (NOT IN DESIGN): the height a normal throw leaves the hand (standing HRP 3.0 +
		-- Config.Combat.ReleaseOffset.Y 1.8); no gravity (user decision 2026-10-11).
		laneHeightAboveFloor = 4.8,
		speed = 75, -- design: ults.js:3, fp.js:337 (s(75))
		maxLength = 110, -- user decision 2026-10-11: arena-length range (Dragon Rush's 110; cover and Bounds cut it)
		recoverySeconds = 0.35, -- user decision 2026-10-11: as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- user decision 2026-10-11: as Dragon Rush
		refundOnCancel = 0.5, -- user decision 2026-10-11: as Dragon Rush
		livesCost = 1, -- user decision 2026-10-11: every hit costs 1 life
		knockbackMultiplier = 1.5, -- build choice 2026-10-11 (NOT IN DESIGN): an ultimate hit pushes like Dragon Rush's
		-- user decision 2026-10-11: the smallest-change cost that passes the budget without re-tuning the throws, read as
		-- the most the rule allows (|Σ 0.23 + cost| <= 0.5, PowerBudget_Test); 0 would also pass.
		budgetCost = 0.27,
		practiceCooldownSeconds = 10, -- user decision 2026-10-11: as Dragon Rush
		minHorizontalAim = 0.3, -- build choice 2026-10-11 (NOT IN DESIGN): as Dragon Rush
		originForwardStuds = 2, -- build choice 2026-10-11 (NOT IN DESIGN): as Dragon Rush
		count = 3, -- design: ults.js:3 ("3 in a 24° fan"), fp.js:337
		fanDeg = 24, -- design: ults.js:3 (±12°)
		staggerSeconds = 0.05, -- design: fp.js:337 (delay i·0.05)
	},
	-- Donut (design: ults.js:4 "Sprinkle Roller").
	sprinkle_roller = {
		kind = "roller",
		nameKey = "ability.sprinkleRoller.name",
		descriptionKey = "ability.sprinkleRoller.description",
		incomingKey = "ability.sprinkleRoller.incoming",
		readyKey = "ability.sprinkleRoller.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults.js:4 (meter 100); user decision 2026-10-11: Dragon Rush's meter
		startCharge = 100 - ULT_START_SECONDS * 100 / 38, -- Duel HUD timer (header)
		chargePerSecond = 100 / 38,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 38, -- design: ults.js:4 (cooldown 38 s); user decision 2026-10-11: the minimum interval
		telegraphSeconds = 0.45, -- design: ults.js:4 (charge 0.45 s); user decision 2026-10-11: the wind-up
		radius = 3, -- design: ults.js:4 (lane 6 st wide)
		-- build choice 2026-10-11 (NOT IN DESIGN): the room and cover checks sweep a sphere of `radius` this high, so it
		-- clears the floor by 0.5 like Dragon Rush's lane; the roller itself rolls on the floor (clearHeight).
		laneHeightAboveFloor = 3.5,
		speed = 55, -- design: ults.js:4, fp.js:342 (s(55))
		maxLength = 60, -- design: ults.js:4, fp.js:339 (s(60))
		recoverySeconds = 0.35, -- user decision 2026-10-11: as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- user decision 2026-10-11: as Dragon Rush
		refundOnCancel = 0.5, -- user decision 2026-10-11: as Dragon Rush
		livesCost = 1, -- user decision 2026-10-11: "touch = out" (ults.js:4) costs 1 life like every hit
		knockbackMultiplier = 1.5, -- build choice 2026-10-11 (NOT IN DESIGN): as Dragon Rush
		-- user decision 2026-10-11: |Σ -0.20 + cost| <= 0.5 without re-tuning the throws, the most the rule allows.
		budgetCost = 0.69,
		practiceCooldownSeconds = 10, -- user decision 2026-10-11: as Dragon Rush
		minHorizontalAim = 0.3, -- build choice 2026-10-11 (NOT IN DESIGN): as Dragon Rush
		originForwardStuds = 1.6 / 0.28, -- design: fp.js:339 (1.6 m ahead; 1 st = 0.28 m, kit.js:3)
		clearHeight = 3, -- design: ults.js:4 ("3 st tall"); user decision 2026-10-11: feet above this are not hit
	},
	-- Cloud Bunny (design: ults.js:5 "Rain Check").
	rain_check = {
		kind = "rain",
		nameKey = "ability.rainCheck.name",
		descriptionKey = "ability.rainCheck.description",
		incomingKey = "ability.rainCheck.incoming",
		readyKey = "ability.rainCheck.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults.js:5 (meter 100); user decision 2026-10-11: Dragon Rush's meter
		startCharge = 100 - ULT_START_SECONDS * 100 / 40, -- Duel HUD timer (header)
		chargePerSecond = 100 / 40,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 40, -- design: ults.js:5 (cooldown 40 s); user decision 2026-10-11: the minimum interval
		telegraphSeconds = 0.6, -- design: ults.js:5 (charge 0.6 s); user decision 2026-10-11: the wind-up
		radius = 7, -- design: ults.js:5, fp.js:348 (zone 7 st radius)
		laneHeightAboveFloor = 13, -- the drops fall from this high (design: fp.js:356, s(13))
		speed = 9 / 0.28, -- the bunny's lob, cosmetic (design: fp.js:349, 9 m/s; 1 st = 0.28 m)
		-- build choice 2026-10-11 (NOT IN DESIGN): in the practice range the zone centres on the practice target nearest
		-- the aim within this many studs (in a duel it is the opponent's spot, user decision 2026-10-11).
		maxLength = 110,
		recoverySeconds = 0.35, -- user decision 2026-10-11: as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- user decision 2026-10-11: as Dragon Rush
		refundOnCancel = 0.5, -- user decision 2026-10-11: as Dragon Rush
		livesCost = 1, -- user decision 2026-10-11: "direct hit each" (ults.js:5) costs 1 life like every hit
		knockbackMultiplier = 1.5, -- build choice 2026-10-11 (NOT IN DESIGN): as Dragon Rush
		budgetCost = 0.27, -- user decision 2026-10-11: |Σ 0.23 + cost| <= 0.5, the most the rule allows
		practiceCooldownSeconds = 10, -- user decision 2026-10-11: as Dragon Rush
		minHorizontalAim = 0.3, -- build choice 2026-10-11 (NOT IN DESIGN): as Dragon Rush
		originForwardStuds = 2, -- build choice 2026-10-11 (NOT IN DESIGN): where the bunny's lob starts (cosmetic)
		drops = 5, -- design: ults.js:5, fp.js:352
		firstShadowSeconds = 0.9, -- drop k's shadow at 0.9 + 0.36k s after the release (design: fp.js:357)
		dropStepSeconds = 0.36, -- design: fp.js:357
		shadowSeconds = 0.45, -- design: ults.js:5 ("0.45 s shadow per drop"), fp.js:356 (450 ms)
		fallSeconds = 0.3, -- design: fp.js:371 (k = t / 0.3)
		dropHitRadius = 1.5, -- design: fp.js:372 (s(1.5))
		dropRadii = { 2, 4, 6 }, -- drop k at radius dropRadii[k % 3]: 2, 4, 6, 2, 4 (design: fp.js:352, s(2 + (k % 3)·2))
		dropAngleStep = 2.4, -- drop k at angle 2.4k rad (design: fp.js:352)
		targetRadius = 7.5, -- a player this close to the centre gets a drop at its own spot (design: fp.js:353, s(7.5))
	},
	-- Cupcake Axolotl (design: ults.js:6 "Bubble Pop").
	bubble_pop = {
		kind = "bubble",
		nameKey = "ability.bubblePop.name",
		descriptionKey = "ability.bubblePop.description",
		incomingKey = "ability.bubblePop.incoming",
		readyKey = "ability.bubblePop.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults.js:6 (meter 100); user decision 2026-10-11: Dragon Rush's meter
		startCharge = 100 - ULT_START_SECONDS * 100 / 36, -- Duel HUD timer (header)
		chargePerSecond = 100 / 36,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 36, -- design: ults.js:6 (cooldown 36 s); user decision 2026-10-11: the minimum interval
		telegraphSeconds = 0.5, -- design: ults.js:6 (charge 0.5 s); user decision 2026-10-11: the wind-up
		-- build choice 2026-10-11 (NOT IN DESIGN, as Birdie's): the game's normal projectile hit radius, Cupcake Axolotl's
		-- own throw radius (Catalog cupcake_axolotl.throw.radius; Config.validate checks they match).
		radius = 1.3,
		laneHeightAboveFloor = 4.8, -- build choice 2026-10-11 (NOT IN DESIGN): the throw release height, no gravity
		speed = 40, -- design: ults.js:6, fp.js:359 (s(40))
		maxLength = 48, -- speed × popSeconds: it pops after 1.2 s (design: ults.js:6), a bounce included
		recoverySeconds = 0.35, -- user decision 2026-10-11: as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- user decision 2026-10-11: as Dragon Rush
		refundOnCancel = 0.5, -- user decision 2026-10-11: as Dragon Rush
		livesCost = 1, -- user decision 2026-10-11: every hit costs 1 life
		knockbackMultiplier = 1.5, -- build choice 2026-10-11 (NOT IN DESIGN): as Dragon Rush
		budgetCost = 0.69, -- user decision 2026-10-11: |Σ -0.20 + cost| <= 0.5, the most the rule allows
		practiceCooldownSeconds = 10, -- user decision 2026-10-11: as Dragon Rush
		minHorizontalAim = 0.3, -- build choice 2026-10-11 (NOT IN DESIGN): as Dragon Rush
		originForwardStuds = 2, -- build choice 2026-10-11 (NOT IN DESIGN): as Dragon Rush
		popSeconds = 1.2, -- design: ults.js:6 ("pops on contact or after 1.2 s")
		splashRadius = 6, -- design: ults.js:6, fp.js:361 (s(6), from the pop point on the floor)
		-- Bubble Pop bounce (2026-10-16; owner yes 2026-10-14): design: ults.js:6 ("40 st/s, bounces once"). What it
		-- bounces off is NOT IN DESIGN (spec phase5-moves §1.8): [P] cover only (not players, the floor or the Bounds).
		-- shortcut: AbilityService builds one bounce leg, so any value above 1 still bounces once; a list of legs if the
		-- design ever asks for more.
		bounces = 1,
		-- Review fix (2026-10-16), NOT IN DESIGN [P]: only cover close to upright bounces it (|unit normal.Y| < 0.5,
		-- steeper than 60°): a floor, a ceiling, a ramp of Diego's maps or a round prop's top pops it as before.
		bounceMaxNormalY = 0.5,
	},
	-- Cosmo (Series 01, 2026-11-10; design: sd/ults2.js:4 "Gravity Well": a 7 st zone at the aim point, a 1.2 s ring
	-- with the beads spiralling in, inside the ring at the pop = out; charge 0.7 s, cooldown 44 s). Built on the rain
	-- kind (the zone centres where Rain Check's does: on the opponent, or the aimed target in practice and FFA/TDM) as
	-- one "drop" as wide as the zone: its warning (UltFx draws the ring and the beads) lasts the design's 1.2 s, then
	-- anyone within 7 studs of the centre is hit.
	gravity_well = {
		kind = "rain",
		nameKey = "ability.gravityWell.name",
		descriptionKey = "ability.gravityWell.description",
		incomingKey = "ability.gravityWell.incoming",
		readyKey = "ability.gravityWell.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults2.js:4 (meter 100)
		startCharge = 100 - ULT_START_SECONDS * 100 / 44, -- Duel HUD timer (header)
		chargePerSecond = 100 / 44,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 44, -- design: ults2.js:4 (cooldown 44 s)
		telegraphSeconds = 0.7, -- design: ults2.js:4 (charge 0.7 s): the wind-up
		radius = 7, -- design: ults2.js:4 (zone 7 st radius)
		laneHeightAboveFloor = 13, -- as Rain Check (unused by the well's look; the rain kind needs it)
		speed = 9 / 0.28, -- as Rain Check (cosmetic)
		maxLength = 110, -- as Rain Check: the practice target nearest the aim within this many studs
		recoverySeconds = 0.35, -- as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- as Dragon Rush
		refundOnCancel = 0.5, -- as Dragon Rush
		livesCost = 1, -- every hit costs 1 life
		knockbackMultiplier = 1.5, -- as Dragon Rush
		budgetCost = 2.0, -- Cosmo throws exactly like the Dragon, so it pays Dragon Rush's cost (PowerBudget)
		practiceCooldownSeconds = 10, -- as Dragon Rush
		minHorizontalAim = 0.3, -- as Dragon Rush
		originForwardStuds = 2, -- as Rain Check
		drops = 1, -- one pop for the whole zone
		-- The ring shows 1.2 s before the pop (design: ults2.js:4): firstShadow + shadow + fall = 1.2 s (the rain kind
		-- wants each above 0).
		firstShadowSeconds = 0.01,
		dropStepSeconds = 0.1, -- one drop: unused
		shadowSeconds = 1.18,
		fallSeconds = 0.01,
		dropHitRadius = 7, -- design: ults2.js:4 ("inside the ring at the pop = out")
		dropRadii = { 0 }, -- the pop is the zone's centre
		dropAngleStep = 0.1, -- one drop: unused
		targetRadius = 7, -- the aimed player in the zone gets the pop at its own spot (the centre already is)
	},
	-- Gelato Narwhal (Frosty Box, 2026-11-10; design: ults2.js:5 "Geyser Line", lab50.js:295-307): 3 frost circles in a
	-- line up to the opponent, each erupting 0.5 s after it shows.
	geyser_line = {
		kind = "rain",
		nameKey = "ability.geyserLine.name",
		descriptionKey = "ability.geyserLine.description",
		incomingKey = "ability.geyserLine.incoming",
		readyKey = "ability.geyserLine.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults2.js:5 (meter 100)
		startCharge = 100 - ULT_START_SECONDS * 100 / 38, -- Duel HUD timer (header)
		chargePerSecond = 100 / 38,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 38, -- design: ults2.js:5 (cooldown 38 s)
		telegraphSeconds = 0.5, -- design: ults2.js:5 (charge 0.5 s): the wind-up
		radius = 3, -- design: ults2.js:5 (3 st each); the rain kind's zone: the drops lie on its centre's line
		laneHeightAboveFloor = 13, -- as Rain Check (unused by the geysers' look; the rain kind needs it)
		speed = 9 / 0.28, -- as Rain Check (cosmetic)
		maxLength = 110, -- as Rain Check: the practice target nearest the aim within this many studs
		recoverySeconds = 0.35, -- as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- as Dragon Rush
		refundOnCancel = 0.5, -- as Dragon Rush
		livesCost = 1, -- every hit costs 1 life
		knockbackMultiplier = 1.5, -- as Dragon Rush
		budgetCost = 0.27, -- the narwhal throws exactly like Cloud Bunny, so it pays Rain Check's cost (PowerBudget)
		practiceCooldownSeconds = 10, -- as Dragon Rush
		minHorizontalAim = 0.3, -- as Dragon Rush
		originForwardStuds = 2, -- as Rain Check
		drops = 3, -- design: ults2.js:5 ("3 in a line")
		firstShadowSeconds = 0.1, -- circle k shows 0.1 + 0.35k s after the release (design: lab50.js:301)
		dropStepSeconds = 0.35, -- design: lab50.js:301
		shadowSeconds = 0.5, -- design: ults2.js:5 ("0.5 s frost circle each"), lab50.js:301
		fallSeconds = 0.01, -- a geyser erupts at once (the rain kind wants it above 0)
		dropHitRadius = 3, -- design: ults2.js:5 ("Radius 3 st each", "inside a circle as it erupts = out")
		dropRadii = { 0 }, -- unused: the line places the drops
		dropAngleStep = 0.1, -- unused: the line places the drops
		-- Only the aimed player (at the centre, the last geyser) keeps its own spot; anyone else stays on the line.
		targetRadius = 0.5,
		dropSpacing = 5, -- design: ults2.js:5 ("5 st apart"), lab50.js:297
	},
	-- Parfait Wyvern (Frosty Box, 2026-11-10; design: ults2.js:6 "Layer Cake Shockwave", lab50.js:309-325): it leaps,
	-- lands on its own spot, and 3 cake rings (pink, cream, blueberry) grow out from it.
	layer_cake_shockwave = {
		kind = "shockwave",
		nameKey = "ability.layerCakeShockwave.name",
		descriptionKey = "ability.layerCakeShockwave.description",
		incomingKey = "ability.layerCakeShockwave.incoming",
		readyKey = "ability.layerCakeShockwave.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults2.js:6 (meter 100)
		startCharge = 100 - ULT_START_SECONDS * 100 / 45, -- Duel HUD timer (header)
		chargePerSecond = 100 / 45,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 45, -- design: ults2.js:6 (cooldown 45 s)
		telegraphSeconds = 0.8, -- design: ults2.js:6 (charge 0.8 s): the wind-up (the leap and the landing)
		radius = 0.5, -- the ring wall's half-thickness (the design's ring is a thin open cylinder, lab50.js:313)
		laneHeightAboveFloor = 0.6, -- the ring's middle (design: lab50.js:322, 0.6 st up); it does not fly
		speed = 12, -- design: ults2.js:6 ("12 st/s")
		maxLength = 14, -- design: ults2.js:6 ("out to 14 st")
		recoverySeconds = 0.35, -- as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- as Dragon Rush
		refundOnCancel = 0.5, -- as Dragon Rush
		livesCost = 1, -- every hit costs 1 life
		knockbackMultiplier = 1.5, -- as Dragon Rush
		budgetCost = 2.0, -- the wyvern throws exactly like the Dragon, so it pays Dragon Rush's cost (PowerBudget)
		practiceCooldownSeconds = 10, -- as Dragon Rush
		minHorizontalAim = 0.3, -- as Dragon Rush
		originForwardStuds = 0, -- the rings start at the caster's feet
		count = 3, -- design: ults2.js:6 ("3 layers")
		staggerSeconds = 0.4, -- design: ults2.js:6 ("0.4 s apart")
		clearHeight = 1.2, -- design: ults2.js:6 ("touch a ring = out (1.2 st tall)"): feet above it jump the ring
	},
	-- Lava Cake Hippo (Lava Box, 2026-11-10; design: ults2.js "Fondue Flood", lab50.js:324-339): after the 0.6 s fan
	-- outline, a molten flood fills a 120° fan out to 10 st in 0.5 s; anyone in the fan as the flood reaches them is hit.
	fondue_flood = {
		kind = "shockwave",
		nameKey = "ability.fondueFlood.name",
		descriptionKey = "ability.fondueFlood.description",
		incomingKey = "ability.fondueFlood.incoming",
		readyKey = "ability.fondueFlood.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults2.js (meter 100)
		startCharge = 100 - ULT_START_SECONDS * 100 / 40, -- Duel HUD timer (header)
		chargePerSecond = 100 / 40,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 40, -- design: ults2.js (cooldown 40 s)
		telegraphSeconds = 0.6, -- design: ults2.js (charge 0.6 s): the fan outline
		radius = 0.5, -- unused by a filling flood (its front is its edge)
		laneHeightAboveFloor = 0.6, -- as Layer Cake Shockwave; it does not fly
		speed = 20, -- design: ults2.js ("floods the fan in 0.5 s"): 10 st in 0.5 s
		maxLength = 10, -- design: ults2.js ("120° fan, 10 st long")
		recoverySeconds = 0.35, -- as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- as Dragon Rush
		refundOnCancel = 0.5, -- as Dragon Rush
		livesCost = 1, -- every hit costs 1 life
		knockbackMultiplier = 1.5, -- as Dragon Rush
		budgetCost = 0.69, -- the hippo throws exactly like Donut, so it pays the Sprinkle Roller's cost (PowerBudget)
		practiceCooldownSeconds = 10, -- as Dragon Rush
		minHorizontalAim = 0.3, -- as Dragon Rush
		originForwardStuds = 0, -- the fan opens at the caster's feet
		count = 1, -- one flood
		staggerSeconds = 0,
		clearHeight = 4, -- a flood, not a wall: no jump clears it (design: "inside the fan as it fills = out")
		fanDeg = 120, -- design: ults2.js ("120° fan"), lab50.js:326
		fill = true, -- the flood fills behind its front: in the fan and inside the front = hit
	},
	-- Mallow Behemoth (Lava Box, 2026-11-10; design: ults2.js "Campfire Ring", lab50.js:340-357): it hops and slams; then 6
	-- flames on an 8-stud ring around it each glow 0.5 s and light, one after another, clockwise from the aim.
	campfire_ring = {
		kind = "rain",
		nameKey = "ability.campfireRing.name",
		descriptionKey = "ability.campfireRing.description",
		incomingKey = "ability.campfireRing.incoming",
		readyKey = "ability.campfireRing.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults2.js (meter 100)
		startCharge = 100 - ULT_START_SECONDS * 100 / 42, -- Duel HUD timer (header)
		chargePerSecond = 100 / 42,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 42, -- design: ults2.js (cooldown 42 s)
		telegraphSeconds = 0.75, -- design: ults2.js (charge 0.75 s): the wind-up
		radius = 8, -- design: ults2.js ("6 flames on an 8 st ring around it"): the ring's radius
		laneHeightAboveFloor = 13, -- as Rain Check (unused by the flames' look; the rain kind needs it)
		speed = 9 / 0.28, -- as Rain Check (cosmetic)
		maxLength = 110, -- as Rain Check
		recoverySeconds = 0.35, -- as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- as Dragon Rush
		refundOnCancel = 0.5, -- as Dragon Rush
		livesCost = 1, -- every hit costs 1 life
		knockbackMultiplier = 1.5, -- as Dragon Rush
		budgetCost = 2.0, -- the Behemoth throws exactly like the Dragon, so it pays Dragon Rush's cost (PowerBudget)
		practiceCooldownSeconds = 10, -- as Dragon Rush
		minHorizontalAim = 0.3, -- as Dragon Rush
		originForwardStuds = 0, -- the ring is around the caster's feet
		drops = 6, -- design: ults2.js ("6 flames")
		firstShadowSeconds = 0.45, -- the hop and the slam first (design: lab50.js:348-350)
		dropStepSeconds = 0.22, -- design: lab50.js:352
		shadowSeconds = 0.5, -- design: ults2.js ("0.5 s ember glow each"), lab50.js:352
		fallSeconds = 0.01, -- a flame lights at once (the rain kind wants it above 0)
		dropHitRadius = 2, -- design: ults2.js ("safe inside 6 st or outside 10 st"): 8 ± 2
		dropRadii = { 8 }, -- every flame on the 8-stud ring
		dropAngleStep = math.pi / 3, -- a sixth of the ring each, clockwise from the aim (design: lab50.js:345, a0 - i/6 TAU)
		targetRadius = 0.5, -- unused: no flame moves onto a player
		ringAroundCaster = true,
	},
	-- Gummy Pufferfish (Prism Box, 2026-11-10; design: ults2.js "Puff Burst", lab50.js:359-374): it puffs up while 8
	-- lanes show, then pops 8 gummy spikes out along the ground, 45° apart from the aim, 12 st; touching a spike = out.
	puff_burst = {
		kind = "volley",
		nameKey = "ability.puffBurst.name",
		descriptionKey = "ability.puffBurst.description",
		incomingKey = "ability.puffBurst.incoming",
		readyKey = "ability.puffBurst.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults2.js (meter 100)
		startCharge = 100 - ULT_START_SECONDS * 100 / 38, -- Duel HUD timer (header)
		chargePerSecond = 100 / 38,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 38, -- design: ults2.js (cooldown 38 s)
		telegraphSeconds = 0.6, -- design: ults2.js ("0.6 s puff-up + 8 lane marks"); its charge 0.5 s is shorter
		radius = 0.9, -- its own throw radius (Config.validate: a volley's projectile is the squishy's throw size)
		laneHeightAboveFloor = 1.0, -- along the ground (design: lab50.js:371, spikes at 0.12 m): it can be jumped
		speed = 4.2 / 0.28, -- design: lab50.js:371 (r grows 4.2 m a second): 15 st/s
		maxLength = 12, -- design: ults2.js ("12 st along the ground")
		recoverySeconds = 0.35, -- as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- as Dragon Rush
		refundOnCancel = 0.5, -- as Dragon Rush
		livesCost = 1, -- every hit costs 1 life
		knockbackMultiplier = 1.5, -- as Dragon Rush
		budgetCost = 0.27, -- the puffer throws exactly like Cloud Bunny, so it pays Rain Check's cost (PowerBudget)
		practiceCooldownSeconds = 10, -- as Dragon Rush
		minHorizontalAim = 0.3, -- as Dragon Rush
		originForwardStuds = 0, -- the spikes leave from the puffer itself
		count = 8, -- design: ults2.js ("8 gummy spikes, 45° apart")
		fanDeg = 360, -- a full circle: one spike on the aim, the others every 45° (UltRules.volleyDirs)
		staggerSeconds = 0, -- all at once (design: lab50.js:369)
	},
	-- Candyglass Qilin (Prism Box, 2026-11-10; design: ults2.js "Prism Pen", lab50.js:376-388): around the opponent's spot
	-- 3 candy panels rise on a triangle of 9 st sides (open corners) for 0.8 s, then shatter; inside the triangle = out.
	prism_pen = {
		kind = "rain",
		nameKey = "ability.prismPen.name",
		descriptionKey = "ability.prismPen.description",
		incomingKey = "ability.prismPen.incoming",
		readyKey = "ability.prismPen.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults2.js (meter 100)
		startCharge = 100 - ULT_START_SECONDS * 100 / 44, -- Duel HUD timer (header)
		chargePerSecond = 100 / 44,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 44, -- design: ults2.js (cooldown 44 s)
		telegraphSeconds = 0.7, -- design: ults2.js (charge 0.7 s): the wind-up
		radius = 9 / math.sqrt(3), -- design: ults2.js ("triangle of 3 candy panels, 9 st sides"): its corner distance
		laneHeightAboveFloor = 13, -- as Rain Check (unused by the panels' look; the rain kind needs it)
		speed = 9 / 0.28, -- as Rain Check (cosmetic)
		maxLength = 110, -- as Rain Check: the practice target nearest the aim within this many studs
		recoverySeconds = 0.35, -- as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- as Dragon Rush
		refundOnCancel = 0.5, -- as Dragon Rush
		livesCost = 1, -- every hit costs 1 life
		knockbackMultiplier = 1.5, -- as Dragon Rush
		budgetCost = 2.0, -- the Qilin throws exactly like the Dragon, so it pays Dragon Rush's cost (PowerBudget)
		practiceCooldownSeconds = 10, -- as Dragon Rush
		minHorizontalAim = 0.3, -- as Dragon Rush
		originForwardStuds = 2, -- as Rain Check
		drops = 1, -- one shatter for the whole triangle
		-- The outline and the rising panels show 0.8 s before the shatter (design: ults2.js "0.8 s outline while panels
		-- rise"): firstShadow + shadow + fall = 0.8 s (the rain kind wants each above 0).
		firstShadowSeconds = 0.01,
		dropStepSeconds = 0.1, -- one drop: unused
		shadowSeconds = 0.78,
		fallSeconds = 0.01,
		dropHitRadius = 9 / math.sqrt(3), -- the triangle's corner distance (triangleDeg makes the area a triangle)
		dropRadii = { 0 }, -- the shatter is the triangle's centre
		dropAngleStep = 0.1, -- one drop: unused
		targetRadius = 0.01, -- the triangle stays on the opponent's spot at the release (the rain kind wants it above 0)
		triangleDeg = 197.19, -- design: lab50.js:378 (corners at 0.3 rad + i·120°), turned 180° like every design angle
	},
	-- Souffle Seraph (Halo Box, 2026-11-10; design: ults2.js "Halo Toss", lab50.js:391-406): a gold path shows for
	-- 0.6 s, then its halo flies 14 st out along it and back the same way at 18 st/s; touching the halo = out.
	halo_toss = {
		kind = "boomerang",
		nameKey = "ability.haloToss.name",
		descriptionKey = "ability.haloToss.description",
		incomingKey = "ability.haloToss.incoming",
		readyKey = "ability.haloToss.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults2.js (meter 100)
		startCharge = 100 - ULT_START_SECONDS * 100 / 39, -- Duel HUD timer (header)
		chargePerSecond = 100 / 39,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 39, -- design: ults2.js (cooldown 39 s)
		telegraphSeconds = 0.6, -- design: ults2.js ("0.6 s gold arc on the ground"); its charge 0.5 s is shorter
		radius = 1, -- design: ults2.js ("touch the halo = out (2 st wide)")
		laneHeightAboveFloor = 0.35 / 0.28, -- design: lab50.js:393 (the halo flies 0.35 m up): 1.25 st
		speed = 18, -- design: ults2.js ("18 st/s")
		maxLength = 14, -- design: ults2.js ("14 st out and back")
		bowStuds = 0.6 / 0.28, -- design: lab50.js:393 (0.6 m to the side at the far end): the path leans to its end
		recoverySeconds = 0.35, -- as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- as Dragon Rush
		refundOnCancel = 0.5, -- as Dragon Rush
		livesCost = 1, -- every hit costs 1 life
		knockbackMultiplier = 1.5, -- as Dragon Rush
		budgetCost = 0.27, -- the Seraph throws exactly like Cloud Bunny, so it pays Rain Check's cost (PowerBudget)
		practiceCooldownSeconds = 10, -- as Dragon Rush
		minHorizontalAim = 0.3, -- as Dragon Rush
		originForwardStuds = 0.3 / 0.28, -- design: lab50.js:393 (the path starts 0.3 m ahead)
	},
	-- Divine Loaf (Halo Box, 2026-11-10; design: ults2.js "Bread Stamp", lab50.js:408-422): on the opponent's spot a bread
	-- slice's shadow (8 x 8 st) grows dark for 1.0 s while the slab falls, then it stamps; inside the shadow = out.
	bread_stamp = {
		kind = "rain",
		nameKey = "ability.breadStamp.name",
		descriptionKey = "ability.breadStamp.description",
		incomingKey = "ability.breadStamp.incoming",
		readyKey = "ability.breadStamp.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults2.js (meter 100)
		startCharge = 100 - ULT_START_SECONDS * 100 / 45, -- Duel HUD timer (header)
		chargePerSecond = 100 / 45,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 45, -- design: ults2.js (cooldown 45 s)
		telegraphSeconds = 0.8, -- design: ults2.js (charge 0.8 s): the wind-up
		radius = 4 * math.sqrt(2), -- design: ults2.js ("8 x 8 st slice-shaped stamp"): its corner distance
		laneHeightAboveFloor = 3 / 0.28, -- design: lab50.js:412 (the slab falls from 3 m): 10.7 st
		speed = 9 / 0.28, -- as Rain Check (cosmetic)
		maxLength = 110, -- as Rain Check: the practice target nearest the aim within this many studs
		recoverySeconds = 0.35, -- as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- as Dragon Rush
		refundOnCancel = 0.5, -- as Dragon Rush
		livesCost = 1, -- every hit costs 1 life
		knockbackMultiplier = 1.5, -- as Dragon Rush
		budgetCost = 2.0, -- the Loaf throws exactly like the Dragon, so it pays Dragon Rush's cost (PowerBudget)
		practiceCooldownSeconds = 10, -- as Dragon Rush
		minHorizontalAim = 0.3, -- as Dragon Rush
		originForwardStuds = 2, -- as Rain Check
		drops = 1, -- one stamp
		-- The shadow grows dark 1.0 s before the stamp (design: ults2.js "1.0 s shadow that grows dark"): firstShadow +
		-- shadow + fall = 1.0 s (the rain kind wants each above 0).
		firstShadowSeconds = 0.01,
		dropStepSeconds = 0.1, -- one drop: unused
		shadowSeconds = 0.98,
		fallSeconds = 0.01,
		dropHitRadius = 4 * math.sqrt(2), -- the slice's corner distance (sliceHalf makes the area a bread slice)
		dropRadii = { 0 }, -- the stamp is the slice's centre
		dropAngleStep = 0.1, -- one drop: unused
		targetRadius = 0.01, -- the slice stays on the opponent's spot at the release (the rain kind wants it above 0)
		sliceHalf = 4, -- design: lab50.js:409 (h = 8 st / 2)
		sliceDeg = 90, -- design: lab50.js:410 (the crown toward the scene's -z), turned 180° like every design angle
	},
	-- Peppermint Puffin (Christmas, big job item 11, 2026-11-10; design: ults2.js "Mint Whirl", lab50.js:422-437): on the
	-- opponent's spot a ring shows the final 6-stud size at once while a peppermint swirl grows from 2 to 6 studs in
	-- 1.2 s, then it pops; inside the swirl at full size = out. Built like Gravity Well: the rain kind's one "drop" as
	-- wide as the zone, its warning the design's 1.2 s.
	-- shortcut: drawn with the rain kind's plain zone and drop shadow (UltFx), not the design's red and white swirl
	-- disc yet; give it its own look when the Christmas event gets its design pass.
	mint_whirl = {
		kind = "rain",
		nameKey = "ability.mintWhirl.name",
		descriptionKey = "ability.mintWhirl.description",
		incomingKey = "ability.mintWhirl.incoming",
		readyKey = "ability.mintWhirl.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100, -- design: ults2.js (meter 100)
		startCharge = 100 - ULT_START_SECONDS * 100 / 40, -- Duel HUD timer (header)
		chargePerSecond = 100 / 40,
		chargePerHitLanded = 0,
		chargePerLifeLost = 0,
		minIntervalSeconds = 40, -- design: ults2.js (cooldown 40 s)
		telegraphSeconds = 0.6, -- design: ults2.js (charge 0.6 s): the wind-up
		radius = 6, -- design: ults2.js ("swirl grows from 2 to 6 st radius"): the final ring
		laneHeightAboveFloor = 13, -- as Rain Check (the rain kind needs it)
		speed = 9 / 0.28, -- as Rain Check (cosmetic)
		maxLength = 110, -- as Rain Check: the practice target nearest the aim within this many studs
		recoverySeconds = 0.35, -- as Dragon Rush
		cancelOnHitDuringTelegraph = true, -- as Dragon Rush
		refundOnCancel = 0.5, -- as Dragon Rush
		livesCost = 1, -- every hit costs 1 life
		knockbackMultiplier = 1.5, -- as Dragon Rush
		budgetCost = 0.27, -- the Puffin throws exactly like Cloud Bunny, so it pays Rain Check's cost (PowerBudget)
		practiceCooldownSeconds = 10, -- as Dragon Rush
		minHorizontalAim = 0.3, -- as Dragon Rush
		originForwardStuds = 2, -- as Rain Check
		drops = 1, -- one pop for the whole swirl
		-- The final ring shows 1.2 s before the pop (design: ults2.js "final ring shown 1.2 s early"): firstShadow +
		-- shadow + fall = 1.2 s (the rain kind wants each above 0).
		firstShadowSeconds = 0.01,
		dropStepSeconds = 0.1, -- one drop: unused
		shadowSeconds = 1.18,
		fallSeconds = 0.01,
		dropHitRadius = 6, -- design: ults2.js ("inside the swirl at full size = out")
		dropRadii = { 0 }, -- the pop is the swirl's centre
		dropAngleStep = 0.1, -- one drop: unused
		targetRadius = 6, -- the aimed player in the zone gets the pop at its own spot (the centre already is)
	},
} :: { [string]: Ability }

return Abilities
