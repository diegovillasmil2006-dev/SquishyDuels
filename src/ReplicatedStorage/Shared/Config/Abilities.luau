--!strict
-- Config.Abilities: ultimates keyed by Catalog `ultimateId` (DESIGN §5.9). Shared, data only. All [P].
-- Five abilities: Dragon Rush (Dragon, Exclusive) and the four Epic ultimates of the design (spec phase 5 §1.4-§1.8;
-- design: ults.js:3-6): Flock Volley (Birdie), Sprinkle Roller (Donut), Rain Check (Cloud Bunny) and Bubble Pop
-- (Cupcake Axolotl). Each has a `kind`, the behaviour AbilityService runs for it:
--   lane    Dragon Rush: a sphere of `radius` swept from O to E at `speed`, at laneHeightAboveFloor, flying on through
--           the player it hits; tested at standing height (jumping never avoids it).
--   volley  `count` projectiles of `radius` fanned over `fanDeg` around the aim, `staggerSeconds` apart, straight at
--           `speed` (no gravity) at laneHeightAboveFloor, each ending at its first hit, cover or maxLength.
--   roller  a lane of half-width `radius` rolling along the floor at `speed` over maxLength, flying on; a body touching
--           it is hit unless its feet are higher than clearHeight above the floor (it can be jumped).
--   rain    a zone of `radius` centred on the opponent at the release; `drops` drops, each with a shadow first, hit a
--           player whose feet are within dropHitRadius of the drop when it lands.
--   bubble  one projectile of `radius` at `speed`; it pops on a player, at cover or after popSeconds, and a player whose
--           feet are within splashRadius of the pop (on the floor) is hit. Bubble Pop bounce (2026-10-16): the first
--           `bounces` covers it meets bounce it off (mirrored on the cover's side, same speed) instead of popping it;
--           its whole path, bounce included, is still maxLength (= speed × popSeconds).
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

export type AbilityKind = "lane" | "volley" | "roller" | "rain" | "bubble"

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
} :: { [string]: Ability }

return Abilities
